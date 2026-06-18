import { Router, type Response } from 'express';
import { z } from 'zod';
import { prisma } from '../db.js';
import { authRequired, type AuthedRequest } from '../middleware/auth.js';

const router = Router();
router.use(authRequired);

// =====================================================================
// ACCOUNTS
// =====================================================================

const accountSchema = z.object({
  name: z.string().min(1).max(80),
  type: z.enum([
    'CASH', 'MOBILE_MONEY_MTN', 'MOBILE_MONEY_MOOV',
    'MOBILE_MONEY_WAVE', 'BANK', 'SAVINGS', 'TONTINE', 'OTHER',
  ]),
  balance: z.number().optional().default(0),
  currency: z.string().max(5).optional().default('XOF'),
  color: z.string().max(20).optional(),
  icon: z.string().max(50).optional(),
});

router.get('/accounts', async (req: AuthedRequest, res: Response) => {
  const accounts = await prisma.account.findMany({
    where: { userId: req.userId, archived: false },
    orderBy: { createdAt: 'asc' },
  });
  res.json({ accounts });
});

router.post('/accounts', async (req: AuthedRequest, res: Response) => {
  const parsed = accountSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT', details: parsed.error.issues });
  const account = await prisma.account.create({
    data: { ...parsed.data, userId: req.userId! },
  });
  res.status(201).json({ account });
});

router.patch('/accounts/:id', async (req: AuthedRequest, res: Response) => {
  const id = req.params.id;
  const parsed = accountSchema.partial().safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
  const account = await prisma.account.updateMany({
    where: { id, userId: req.userId },
    data: parsed.data,
  });
  if (account.count === 0) return res.status(404).json({ error: 'NOT_FOUND' });
  res.json({ ok: true });
});

router.delete('/accounts/:id', async (req: AuthedRequest, res: Response) => {
  const id = req.params.id;
  // Archive au lieu de supprimer pour préserver l'historique
  const result = await prisma.account.updateMany({
    where: { id, userId: req.userId },
    data: { archived: true },
  });
  if (result.count === 0) return res.status(404).json({ error: 'NOT_FOUND' });
  res.json({ ok: true });
});

// =====================================================================
// TRANSACTIONS
// =====================================================================

const transactionSchema = z.object({
  accountId: z.string(),
  type: z.enum(['INCOME', 'EXPENSE', 'TRANSFER']),
  amount: z.number().positive(),
  category: z.string().optional(),
  subcategory: z.string().optional(),
  label: z.string().min(1).max(200),
  note: z.string().max(2000).optional(),
  tags: z.array(z.string()).optional(),
  date: z.string().optional(),
  recurring: z.boolean().optional(),
  recurringRule: z.string().optional(),
  transferToAccountId: z.string().optional().nullable(),
  savingsGoalId: z.string().optional().nullable(),
  boutiqueLogId: z.string().optional().nullable(),
});

router.get('/transactions', async (req: AuthedRequest, res: Response) => {
  const limit = Math.min(parseInt(String(req.query.limit || '50'), 10), 500);
  const offset = Math.max(parseInt(String(req.query.offset || '0'), 10), 0);
  const accountId = req.query.accountId as string | undefined;
  const category = req.query.category as string | undefined;
  const from = req.query.from ? new Date(req.query.from as string) : undefined;
  const to = req.query.to ? new Date(req.query.to as string) : undefined;

  const where: any = { userId: req.userId };
  if (accountId) where.accountId = accountId;
  if (category) where.category = category;
  if (from || to) where.date = {};
  if (from) where.date.gte = from;
  if (to) where.date.lte = to;

  const [transactions, total] = await Promise.all([
    prisma.transaction.findMany({
      where,
      orderBy: { date: 'desc' },
      take: limit,
      skip: offset,
      include: { account: true, savingsGoal: true },
    }),
    prisma.transaction.count({ where }),
  ]);

  res.json({ transactions, total, limit, offset });
});

router.post('/transactions', async (req: AuthedRequest, res: Response) => {
  const parsed = transactionSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT', details: parsed.error.issues });
  const { date, amount, type, accountId, ...rest } = parsed.data;

  // Vérifier compte appartient à l'utilisateur
  const account = await prisma.account.findFirst({ where: { id: accountId, userId: req.userId } });
  if (!account) return res.status(404).json({ error: 'ACCOUNT_NOT_FOUND' });

  const tx = await prisma.transaction.create({
    data: {
      ...rest,
      userId: req.userId!,
      accountId,
      type,
      amount,
      date: date ? new Date(date) : new Date(),
    },
  });

  // Mettre à jour le solde du compte
  const delta = type === 'INCOME' ? amount : type === 'EXPENSE' ? -amount : 0;
  if (delta !== 0) {
    await prisma.account.update({ where: { id: accountId }, data: { balance: { increment: delta } } });
  }
  if (type === 'TRANSFER' && rest.transferToAccountId) {
    const destAccount = await prisma.account.findFirst({ where: { id: rest.transferToAccountId, userId: req.userId } });
    if (!destAccount) return res.status(404).json({ error: 'DEST_ACCOUNT_NOT_FOUND' });
    await prisma.account.update({ where: { id: account.id }, data: { balance: { decrement: amount } } });
    await prisma.account.update({ where: { id: destAccount.id }, data: { balance: { increment: amount } } });
  }

  // Si lié à un objectif d'épargne
  if (rest.savingsGoalId && type === 'INCOME') {
    await prisma.savingsGoal.update({
      where: { id: rest.savingsGoalId },
      data: { currentAmount: { increment: amount } },
    });
  }

  res.status(201).json({ transaction: tx });
});

router.patch('/transactions/:id', async (req: AuthedRequest, res: Response) => {
  const id = req.params.id;
  const parsed = transactionSchema.partial().safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
  const existing = await prisma.transaction.findFirst({ where: { id, userId: req.userId } });
  if (!existing) return res.status(404).json({ error: 'NOT_FOUND' });

  const tx = await prisma.transaction.update({
    where: { id },
    data: { ...parsed.data, date: parsed.data.date ? new Date(parsed.data.date) : undefined },
  });
  res.json({ transaction: tx });
});

router.delete('/transactions/:id', async (req: AuthedRequest, res: Response) => {
  const id = req.params.id;
  const existing = await prisma.transaction.findFirst({ where: { id, userId: req.userId } });
  if (!existing) return res.status(404).json({ error: 'NOT_FOUND' });

  // Revert balance
  const delta = existing.type === 'INCOME' ? -existing.amount.toNumber()
              : existing.type === 'EXPENSE' ? existing.amount.toNumber() : 0;
  if (delta !== 0) {
    await prisma.account.update({ where: { id: existing.accountId }, data: { balance: { increment: delta } } });
  }
  if (existing.type === 'TRANSFER' && existing.transferToAccountId) {
    await prisma.account.update({ where: { id: existing.accountId }, data: { balance: { increment: existing.amount.toNumber() } } });
    await prisma.account.update({ where: { id: existing.transferToAccountId }, data: { balance: { decrement: existing.amount.toNumber() } } });
  }

  await prisma.transaction.delete({ where: { id } });
  res.json({ ok: true });
});

// =====================================================================
// DASHBOARD FINANCE
// =====================================================================

router.get('/dashboard', async (req: AuthedRequest, res: Response) => {
  const userId = req.userId!;
  const now = new Date();
  const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
  const startOfPrevMonth = new Date(now.getFullYear(), now.getMonth() - 1, 1);

  const [accounts, monthTxs, prevTxs, budgets, savingsGoals, debts, bills, tontines] = await Promise.all([
    prisma.account.findMany({ where: { userId, archived: false } }),
    prisma.transaction.findMany({ where: { userId, date: { gte: startOfMonth } } }),
    prisma.transaction.findMany({ where: { userId, date: { gte: startOfPrevMonth, lt: startOfMonth } } }),
    prisma.budget.findMany({ where: { userId }, include: { categories: true }, orderBy: { month: 'desc' }, take: 1 }),
    prisma.savingsGoal.findMany({ where: { userId, archived: false } }),
    prisma.debt.findMany({ where: { userId, settled: false } }),
    prisma.bill.findMany({ where: { userId, status: { in: ['PENDING', 'LATE'] } } }),
    prisma.tontine.findMany({ where: { userId, active: true }, include: { members: true } }),
  ]);

  const totalBalance = accounts.reduce((sum, a) => sum + a.balance.toNumber(), 0);
  const income = monthTxs.filter(t => t.type === 'INCOME').reduce((s, t) => s + t.amount.toNumber(), 0);
  const expenses = monthTxs.filter(t => t.type === 'EXPENSE').reduce((s, t) => s + t.amount.toNumber(), 0);
  const prevIncome = prevTxs.filter(t => t.type === 'INCOME').reduce((s, t) => s + t.amount.toNumber(), 0);
  const prevExpenses = prevTxs.filter(t => t.type === 'EXPENSE').reduce((s, t) => s + t.amount.toNumber(), 0);
  const savings = income - expenses;
  const savingsRate = income > 0 ? Math.round((savings / income) * 100) : 0;

  // Catégories de dépenses du mois
  const byCategory: Record<string, number> = {};
  for (const t of monthTxs) {
    if (t.type === 'EXPENSE') {
      const cat = t.category || 'Autre';
      byCategory[cat] = (byCategory[cat] || 0) + t.amount.toNumber();
    }
  }

  // Score de santé financière (0-100)
  let score = 50;
  if (savingsRate >= 20) score += 20;
  if (savingsRate >= 30) score += 10;
  if (totalBalance > 0) score += 10;
  if (debts.length === 0) score += 10;
  if (savingsGoals.some(g => g.currentAmount.toNumber() > 0)) score += 10;
  if (savingsRate < 0) score = Math.max(0, score - 20);
  score = Math.max(0, Math.min(100, score));

  return res.json({
    score,
    totalBalance,
    accounts,
    month: {
      income,
      expenses,
      savings,
      savingsRate,
      prevIncome,
      prevExpenses,
      incomeChange: prevIncome ? Math.round(((income - prevIncome) / prevIncome) * 100) : 0,
      expensesChange: prevExpenses ? Math.round(((expenses - prevExpenses) / prevExpenses) * 100) : 0,
    },
    byCategory: Object.entries(byCategory).map(([category, amount]) => ({ category, amount })).sort((a, b) => b.amount - a.amount),
    budget: budgets[0] || null,
    savingsGoals,
    debts,
    bills,
    tontines,
  });
});

// =====================================================================
// BUDGETS
// =====================================================================

const budgetSchema = z.object({
  month: z.string(), // ISO date (premier jour du mois)
  method: z.enum(['FIFTY_THIRTY_TWENTY', 'ENVELOPES', 'CUSTOM']).optional(),
  totalIncome: z.number().optional(),
  needsPct: z.number().int().min(0).max(100).optional(),
  wantsPct: z.number().int().min(0).max(100).optional(),
  savingsPct: z.number().int().min(0).max(100).optional(),
  rollover: z.boolean().optional(),
  categories: z.array(z.object({
    name: z.string(),
    allocated: z.number(),
  })).optional(),
});

router.get('/budgets', async (req: AuthedRequest, res: Response) => {
  const budgets = await prisma.budget.findMany({
    where: { userId: req.userId },
    include: { categories: true },
    orderBy: { month: 'desc' },
    take: 12,
  });
  res.json({ budgets });
});

router.post('/budgets', async (req: AuthedRequest, res: Response) => {
  const parsed = budgetSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT', details: parsed.error.issues });
  const { categories, month, ...rest } = parsed.data;
  const monthDate = new Date(month);

  const budget = await prisma.budget.upsert({
    where: { userId_month: { userId: req.userId!, month: monthDate } },
    update: { ...rest },
    create: {
      ...rest,
      userId: req.userId!,
      month: monthDate,
      categories: categories ? { create: categories } : undefined,
    },
    include: { categories: true },
  });

  res.status(201).json({ budget });
});

// =====================================================================
// SAVINGS GOALS
// =====================================================================

const savingsGoalSchema = z.object({
  name: z.string().min(1).max(120),
  description: z.string().max(2000).optional(),
  targetAmount: z.number().positive(),
  currentAmount: z.number().optional().default(0),
  deadline: z.string().optional(),
  imageUrl: z.string().optional(),
});

router.get('/savings-goals', async (req: AuthedRequest, res: Response) => {
  const goals = await prisma.savingsGoal.findMany({
    where: { userId: req.userId, archived: false },
    orderBy: { createdAt: 'desc' },
  });
  res.json({ savingsGoals: goals });
});

router.post('/savings-goals', async (req: AuthedRequest, res: Response) => {
  const parsed = savingsGoalSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
  const goal = await prisma.savingsGoal.create({
    data: {
      ...parsed.data,
      deadline: parsed.data.deadline ? new Date(parsed.data.deadline) : null,
      userId: req.userId!,
    },
  });
  res.status(201).json({ savingsGoal: goal });
});

router.patch('/savings-goals/:id', async (req: AuthedRequest, res: Response) => {
  const parsed = savingsGoalSchema.partial().safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
  const result = await prisma.savingsGoal.updateMany({
    where: { id: req.params.id, userId: req.userId },
    data: { ...parsed.data, deadline: parsed.data.deadline ? new Date(parsed.data.deadline) : undefined },
  });
  if (result.count === 0) return res.status(404).json({ error: 'NOT_FOUND' });
  res.json({ ok: true });
});

router.delete('/savings-goals/:id', async (req: AuthedRequest, res: Response) => {
  const result = await prisma.savingsGoal.updateMany({
    where: { id: req.params.id, userId: req.userId },
    data: { archived: true },
  });
  if (result.count === 0) return res.status(404).json({ error: 'NOT_FOUND' });
  res.json({ ok: true });
});

// =====================================================================
// TONTINES
// =====================================================================

const tontineSchema = z.object({
  name: z.string().min(1).max(120),
  description: z.string().optional(),
  contributionAmount: z.number().positive(),
  frequency: z.enum(['MONTHLY', 'WEEKLY']).optional().default('MONTHLY'),
  startDate: z.string(),
  endDate: z.string().optional(),
  myRank: z.number().int().positive(),
  totalMembers: z.number().int().positive(),
  members: z.array(z.object({
    name: z.string(),
    phone: z.string().optional(),
    rank: z.number().int().positive(),
  })).optional(),
});

router.get('/tontines', async (req: AuthedRequest, res: Response) => {
  const tontines = await prisma.tontine.findMany({
    where: { userId: req.userId },
    include: { members: true },
    orderBy: { createdAt: 'desc' },
  });
  res.json({ tontines });
});

router.post('/tontines', async (req: AuthedRequest, res: Response) => {
  const parsed = tontineSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT', details: parsed.error.issues });
  const { members, startDate, endDate, ...rest } = parsed.data;
  const tontine = await prisma.tontine.create({
    data: {
      ...rest,
      userId: req.userId!,
      startDate: new Date(startDate),
      endDate: endDate ? new Date(endDate) : null,
      members: members ? { create: members } : undefined,
    },
    include: { members: true },
  });
  res.status(201).json({ tontine });
});

router.patch('/tontines/:id', async (req: AuthedRequest, res: Response) => {
  const parsed = tontineSchema.partial().safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
  const { members, startDate, endDate, ...rest } = parsed.data;
  const tontine = await prisma.tontine.update({
    where: { id: req.params.id, userId: req.userId },
    data: {
      ...rest,
      startDate: startDate ? new Date(startDate) : undefined,
      endDate: endDate ? new Date(endDate) : undefined,
    },
  });
  res.json({ tontine });
});

router.delete('/tontines/:id', async (req: AuthedRequest, res: Response) => {
  await prisma.tontine.deleteMany({ where: { id: req.params.id, userId: req.userId } });
  res.json({ ok: true });
});

// =====================================================================
// DEBTS
// =====================================================================

const debtSchema = z.object({
  direction: z.enum(['OWED', 'OWING']),
  personName: z.string().min(1).max(120),
  personPhone: z.string().optional(),
  amount: z.number().positive(),
  interestRate: z.number().optional(),
  dueDate: z.string().optional(),
  note: z.string().optional(),
  strategy: z.enum(['SNOWBALL', 'AVALANCHE']).optional(),
});

router.get('/debts', async (req: AuthedRequest, res: Response) => {
  const debts = await prisma.debt.findMany({
    where: { userId: req.userId, settled: false },
    include: { payments: true },
    orderBy: { createdAt: 'desc' },
  });
  res.json({ debts });
});

router.post('/debts', async (req: AuthedRequest, res: Response) => {
  const parsed = debtSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
  const { dueDate, ...rest } = parsed.data;
  const debt = await prisma.debt.create({
    data: { ...rest, dueDate: dueDate ? new Date(dueDate) : null, userId: req.userId! },
  });
  res.status(201).json({ debt });
});

router.patch('/debts/:id', async (req: AuthedRequest, res: Response) => {
  const parsed = debtSchema.partial().safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
  const { dueDate, ...rest } = parsed.data;
  const debt = await prisma.debt.updateMany({
    where: { id: req.params.id, userId: req.userId },
    data: { ...rest, dueDate: dueDate ? new Date(dueDate) : undefined },
  });
  if (debt.count === 0) return res.status(404).json({ error: 'NOT_FOUND' });
  res.json({ ok: true });
});

router.delete('/debts/:id', async (req: AuthedRequest, res: Response) => {
  await prisma.debt.updateMany({
    where: { id: req.params.id, userId: req.userId },
    data: { settled: true, settledAt: new Date() },
  });
  res.json({ ok: true });
});

router.post('/debts/:id/payments', async (req: AuthedRequest, res: Response) => {
  const schema = z.object({ amount: z.number().positive(), note: z.string().optional() });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
  const debt = await prisma.debt.findFirst({ where: { id: req.params.id, userId: req.userId } });
  if (!debt) return res.status(404).json({ error: 'NOT_FOUND' });
  const payment = await prisma.debtPayment.create({
    data: { debtId: debt.id, amount: parsed.data.amount, note: parsed.data.note },
  });
  const newAmount = Math.max(0, debt.amount.toNumber() - parsed.data.amount);
  if (newAmount === 0) {
    await prisma.debt.update({ where: { id: debt.id }, data: { settled: true, settledAt: new Date() } });
  } else {
    await prisma.debt.update({ where: { id: debt.id }, data: { amount: newAmount } });
  }
  res.status(201).json({ payment });
});

// =====================================================================
// BILLS
// =====================================================================

const billSchema = z.object({
  name: z.string().min(1).max(120),
  amount: z.number().positive(),
  category: z.string().optional(),
  recurrence: z.enum(['MONTHLY', 'WEEKLY', 'YEARLY']).optional().default('MONTHLY'),
  dueDay: z.number().int().min(1).max(31),
  nextDueDate: z.string(),
  reminderDays: z.number().int().min(0).max(30).optional().default(3),
});

router.get('/bills', async (req: AuthedRequest, res: Response) => {
  const bills = await prisma.bill.findMany({
    where: { userId: req.userId },
    include: { history: true },
    orderBy: { nextDueDate: 'asc' },
  });
  res.json({ bills });
});

router.post('/bills', async (req: AuthedRequest, res: Response) => {
  const parsed = billSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
  const { nextDueDate, ...rest } = parsed.data;
  const bill = await prisma.bill.create({
    data: { ...rest, nextDueDate: new Date(nextDueDate), userId: req.userId! },
  });
  res.status(201).json({ bill });
});

router.patch('/bills/:id', async (req: AuthedRequest, res: Response) => {
  const parsed = billSchema.partial().safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
  const { nextDueDate, ...rest } = parsed.data;
  const bill = await prisma.bill.updateMany({
    where: { id: req.params.id, userId: req.userId },
    data: { ...rest, nextDueDate: nextDueDate ? new Date(nextDueDate) : undefined },
  });
  if (bill.count === 0) return res.status(404).json({ error: 'NOT_FOUND' });
  res.json({ ok: true });
});

router.post('/bills/:id/pay', async (req: AuthedRequest, res: Response) => {
  const bill = await prisma.bill.findFirst({ where: { id: req.params.id, userId: req.userId } });
  if (!bill) return res.status(404).json({ error: 'NOT_FOUND' });

  await prisma.$transaction([
    prisma.billHistory.create({
      data: { billId: bill.id, amount: bill.amount, paidAt: new Date() },
    }),
    prisma.bill.update({
      where: { id: bill.id },
      data: { status: 'PAID', paidAt: new Date() },
    }),
  ]);

  // Calculer la prochaine échéance
  const next = new Date(bill.nextDueDate);
  if (bill.recurrence === 'MONTHLY') next.setMonth(next.getMonth() + 1);
  else if (bill.recurrence === 'WEEKLY') next.setDate(next.getDate() + 7);
  else if (bill.recurrence === 'YEARLY') next.setFullYear(next.getFullYear() + 1);

  await prisma.bill.update({
    where: { id: bill.id },
    data: { status: 'PENDING', paidAt: null, nextDueDate: next },
  });

  res.json({ ok: true, nextDueDate: next });
});

router.delete('/bills/:id', async (req: AuthedRequest, res: Response) => {
  await prisma.bill.deleteMany({ where: { id: req.params.id, userId: req.userId } });
  res.json({ ok: true });
});

export default router;
