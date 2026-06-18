import { Router, type Response } from 'express';
import { z } from 'zod';
import { prisma } from '../db.js';
import { authRequired, type AuthedRequest } from '../middleware/auth.js';

const router = Router();
router.use(authRequired);

// =====================================================================
// DAILY BOUTIQUE LOG
// =====================================================================

const boutiqueSchema = z.object({
  date: z.string(),
  openingCapital: z.number().min(0).optional().default(0),
  restockCost: z.number().min(0).optional().default(0),
  totalSales: z.number().min(0).optional().default(0),
  note: z.string().optional(),
});

router.get('/boutique', async (req: AuthedRequest, res: Response) => {
  const dateStr = (req.query.date as string) || new Date().toISOString().slice(0, 10);
  const log = await prisma.dailyBoutiqueLog.findUnique({
    where: { userId_date: { userId: req.userId!, date: new Date(dateStr) } },
  });
  // Récupère les 30 derniers jours pour historique
  const from = new Date();
  from.setDate(from.getDate() - 30);
  const history = await prisma.dailyBoutiqueLog.findMany({
    where: { userId: req.userId, date: { gte: from } },
    orderBy: { date: 'desc' },
  });
  res.json({ log, history });
});

router.post('/boutique', async (req: AuthedRequest, res: Response) => {
  const parsed = boutiqueSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
  const date = new Date(parsed.data.date);
  const netProfit = parsed.data.totalSales - parsed.data.restockCost;
  const log = await prisma.dailyBoutiqueLog.upsert({
    where: { userId_date: { userId: req.userId!, date } },
    update: {
      openingCapital: parsed.data.openingCapital,
      restockCost: parsed.data.restockCost,
      totalSales: parsed.data.totalSales,
      netProfit,
      note: parsed.data.note,
    },
    create: {
      userId: req.userId!,
      date,
      openingCapital: parsed.data.openingCapital,
      restockCost: parsed.data.restockCost,
      totalSales: parsed.data.totalSales,
      netProfit,
      note: parsed.data.note,
    },
  });
  res.status(201).json({ log });
});

// =====================================================================
// CLIENT ARDOISE
// =====================================================================

router.get('/ardoises', async (req: AuthedRequest, res: Response) => {
  const ardoises = await prisma.clientArdoise.findMany({
    where: { userId: req.userId, settled: false },
    include: { entries: { orderBy: { date: 'desc' } } },
    orderBy: { updatedAt: 'desc' },
  });
  res.json({ ardoises });
});

const ardoiseSchema = z.object({
  clientName: z.string().min(1).max(120),
  clientPhone: z.string().optional(),
  note: z.string().optional(),
});

router.post('/ardoises', async (req: AuthedRequest, res: Response) => {
  const parsed = ardoiseSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
  const ardoise = await prisma.clientArdoise.create({
    data: { ...parsed.data, userId: req.userId! },
  });
  res.status(201).json({ ardoise });
});

router.post('/ardoises/:id/entries', async (req: AuthedRequest, res: Response) => {
  const schema = z.object({
    amount: z.number().positive(),
    direction: z.enum(['CREDIT', 'PAYMENT']),
    note: z.string().optional(),
  });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
  const ardoise = await prisma.clientArdoise.findFirst({ where: { id: req.params.id, userId: req.userId } });
  if (!ardoise) return res.status(404).json({ error: 'NOT_FOUND' });

  const entry = await prisma.ardoiseEntry.create({
    data: { ardoiseId: ardoise.id, amount: parsed.data.amount, direction: parsed.data.direction, note: parsed.data.note },
  });

  const delta = parsed.data.direction === 'CREDIT' ? parsed.data.amount : -parsed.data.amount;
  const newTotal = Math.max(0, ardoise.totalDebt.toNumber() + delta);
  await prisma.clientArdoise.update({
    where: { id: ardoise.id },
    data: {
      totalDebt: newTotal,
      settled: newTotal === 0,
      settledAt: newTotal === 0 ? new Date() : null,
    },
  });

  res.status(201).json({ entry, ardoise: { ...ardoise, totalDebt: newTotal } });
});

router.delete('/ardoises/:id', async (req: AuthedRequest, res: Response) => {
  await prisma.clientArdoise.updateMany({
    where: { id: req.params.id, userId: req.userId },
    data: { settled: true, settledAt: new Date() },
  });
  res.json({ ok: true });
});

// =====================================================================
// SUPPLIER CREDITS
// =====================================================================

router.get('/suppliers', async (req: AuthedRequest, res: Response) => {
  const suppliers = await prisma.supplierCredit.findMany({
    where: { userId: req.userId, settled: false },
    orderBy: { dueDate: 'asc' },
  });
  res.json({ suppliers });
});

router.post('/suppliers', async (req: AuthedRequest, res: Response) => {
  const schema = z.object({
    supplierName: z.string().min(1).max(120),
    supplierPhone: z.string().optional(),
    amount: z.number().positive(),
    dueDate: z.string().optional(),
    note: z.string().optional(),
  });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
  const supplier = await prisma.supplierCredit.create({
    data: {
      ...parsed.data,
      dueDate: parsed.data.dueDate ? new Date(parsed.data.dueDate) : null,
      userId: req.userId!,
    },
  });
  res.status(201).json({ supplier });
});

router.post('/suppliers/:id/pay', async (req: AuthedRequest, res: Response) => {
  const supplier = await prisma.supplierCredit.findFirst({ where: { id: req.params.id, userId: req.userId } });
  if (!supplier) return res.status(404).json({ error: 'NOT_FOUND' });
  await prisma.supplierCredit.update({
    where: { id: supplier.id },
    data: { settled: true, settledAt: new Date() },
  });
  res.json({ ok: true });
});

// =====================================================================
// DASHBOARD MODE ACCESSIBLE
// =====================================================================

router.get('/dashboard', async (req: AuthedRequest, res: Response) => {
  const today = new Date();
  const todayStr = today.toISOString().slice(0, 10);
  const startOfMonth = new Date(today.getFullYear(), today.getMonth(), 1);

  const [todayLog, monthLogs, ardoises, suppliers] = await Promise.all([
    prisma.dailyBoutiqueLog.findUnique({
      where: { userId_date: { userId: req.userId!, date: new Date(todayStr) } },
    }),
    prisma.dailyBoutiqueLog.findMany({
      where: { userId: req.userId, date: { gte: startOfMonth } },
      orderBy: { date: 'desc' },
    }),
    prisma.clientArdoise.findMany({ where: { userId: req.userId, settled: false } }),
    prisma.supplierCredit.findMany({ where: { userId: req.userId, settled: false } }),
  ]);

  const monthSales = monthLogs.reduce((s, l) => s + l.totalSales.toNumber(), 0);
  const monthProfit = monthLogs.reduce((s, l) => s + l.netProfit.toNumber(), 0);
  const totalArdoises = ardoises.reduce((s, a) => s + a.totalDebt.toNumber(), 0);
  const totalSuppliers = suppliers.reduce((s, c) => s + c.amount.toNumber(), 0);

  res.json({
    today: todayLog,
    monthSales,
    monthProfit,
    monthDays: monthLogs.length,
    totalArdoises,
    totalSuppliers,
  });
});

export default router;
