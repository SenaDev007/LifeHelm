// V2 — Mode Famille : routes API
import { Router, type Response } from 'express';
import { z } from 'zod';
import crypto from 'node:crypto';
import { prisma } from '../db.js';
import { authRequired, type AuthedRequest } from '../middleware/auth.js';

const router = Router();
router.use(authRequired);

// Helper : vérifier appartenance à une famille
async function checkFamilyMembership(familyId: string, userId: string) {
  const m = await prisma.familyMember.findUnique({
    where: { familyId_userId: { familyId, userId } },
    include: { family: true },
  });
  return m;
}

async function checkFamilyAdmin(familyId: string, userId: string) {
  const m = await checkFamilyMembership(familyId, userId);
  if (!m) return null;
  return m.role === 'ADMIN' ? m : null;
}

// =====================================================================
// CRUD FAMILY
// =====================================================================

router.post('/', async (req: AuthedRequest, res: Response) => {
  const schema = z.object({
    name: z.string().min(1).max(120),
    description: z.string().optional(),
  });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });

  const inviteCode = crypto.randomBytes(4).toString('hex').toUpperCase();

  const family = await prisma.family.create({
    data: {
      name: parsed.data.name,
      description: parsed.data.description,
      inviteCode,
      ownerId: req.userId!,
      members: {
        create: { userId: req.userId!, role: 'ADMIN' },
      },
    },
    include: { members: true },
  });

  res.status(201).json({ family });
});

router.get('/mine', async (req: AuthedRequest, res: Response) => {
  const memberships = await prisma.familyMember.findMany({
    where: { userId: req.userId },
    include: {
      family: {
        include: {
          members: { include: { user: { select: { id: true, firstName: true, lastName: true, avatarUrl: true } } } },
        },
      },
    },
  });
  const families = memberships.map(m => m.family);
  res.json({ families });
});

router.get('/:id', async (req: AuthedRequest, res: Response) => {
  const m = await checkFamilyMembership(req.params.id, req.userId!);
  if (!m) return res.status(404).json({ error: 'NOT_MEMBER' });

  const family = await prisma.family.findUnique({
    where: { id: req.params.id },
    include: {
      members: {
        include: { user: { select: { id: true, firstName: true, lastName: true, avatarUrl: true, email: true } } },
        orderBy: { joinedAt: 'asc' },
      },
      budgets: { include: { contributions: true }, orderBy: { month: 'desc' }, take: 6 },
      goals: { orderBy: { createdAt: 'desc' } },
    },
  });
  res.json({ family });
});

// Rejoindre une famille par code d'invitation
router.post('/join', async (req: AuthedRequest, res: Response) => {
  const schema = z.object({ inviteCode: z.string().length(8) });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });

  const family = await prisma.family.findUnique({ where: { inviteCode: parsed.data.inviteCode } });
  if (!family) return res.status(404).json({ error: 'INVALID_CODE' });

  const existing = await prisma.familyMember.findUnique({
    where: { familyId_userId: { familyId: family.id, userId: req.userId! } },
  });
  if (existing) return res.status(409).json({ error: 'ALREADY_MEMBER' });

  const memberCount = await prisma.familyMember.count({ where: { familyId: family.id } });
  if (memberCount >= family.maxMembers) return res.status(409).json({ error: 'FAMILY_FULL' });

  const member = await prisma.familyMember.create({
    data: { familyId: family.id, userId: req.userId!, role: 'MEMBER' },
  });

  res.status(201).json({ family, member });
});

router.delete('/:id/leave', async (req: AuthedRequest, res: Response) => {
  const m = await checkFamilyMembership(req.params.id, req.userId!);
  if (!m) return res.status(404).json({ error: 'NOT_MEMBER' });

  // Si admin et dernier membre, supprimer la famille
  const memberCount = await prisma.familyMember.count({ where: { familyId: req.params.id } });
  if (m.role === 'ADMIN' && memberCount === 1) {
    await prisma.family.delete({ where: { id: req.params.id } });
    return res.json({ ok: true, deleted: true });
  }

  // Si admin mais reste des membres, transférer la propriété au plus ancien
  if (m.role === 'ADMIN') {
    const oldest = await prisma.familyMember.findFirst({
      where: { familyId: req.params.id, userId: { not: req.userId } },
      orderBy: { joinedAt: 'asc' },
    });
    if (oldest) {
      await prisma.familyMember.update({
        where: { id: oldest.id },
        data: { role: 'ADMIN' },
      });
      await prisma.family.update({
        where: { id: req.params.id },
        data: { ownerId: oldest.userId },
      });
    }
  }

  await prisma.familyMember.delete({ where: { id: m.id } });
  res.json({ ok: true });
});

router.delete('/:id/members/:userId', async (req: AuthedRequest, res: Response) => {
  const admin = await checkFamilyAdmin(req.params.id, req.userId!);
  if (!admin) return res.status(403).json({ error: 'NOT_ADMIN' });

  if (req.params.userId === req.userId) {
    return res.status(400).json({ error: 'CANNOT_REMOVE_SELF_USE_LEAVE' });
  }

  await prisma.familyMember.deleteMany({
    where: { familyId: req.params.id, userId: req.params.userId },
  });
  res.json({ ok: true });
});

router.patch('/:id', async (req: AuthedRequest, res: Response) => {
  const admin = await checkFamilyAdmin(req.params.id, req.userId!);
  if (!admin) return res.status(403).json({ error: 'NOT_ADMIN' });

  const schema = z.object({
    name: z.string().min(1).max(120).optional(),
    description: z.string().optional(),
  });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });

  const family = await prisma.family.update({
    where: { id: req.params.id },
    data: parsed.data,
  });
  res.json({ family });
});

// Régénérer le code d'invitation
router.post('/:id/regenerate-code', async (req: AuthedRequest, res: Response) => {
  const admin = await checkFamilyAdmin(req.params.id, req.userId!);
  if (!admin) return res.status(403).json({ error: 'NOT_ADMIN' });

  const inviteCode = crypto.randomBytes(4).toString('hex').toUpperCase();
  const family = await prisma.family.update({
    where: { id: req.params.id },
    data: { inviteCode },
  });
  res.json({ family });
});

// =====================================================================
// BUDGET FAMILIAL
// =====================================================================

router.post('/:id/budgets', async (req: AuthedRequest, res: Response) => {
  const m = await checkFamilyMembership(req.params.id, req.userId!);
  if (!m) return res.status(404).json({ error: 'NOT_MEMBER' });

  const schema = z.object({
    month: z.string(),
    totalIncome: z.number().optional().default(0),
    totalExpense: z.number().optional().default(0),
    note: z.string().optional(),
  });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });

  const month = new Date(parsed.data.month);
  const budget = await prisma.familyBudget.upsert({
    where: { familyId_month: { familyId: req.params.id, month } },
    update: parsed.data,
    create: { ...parsed.data, familyId: req.params.id },
  });
  res.status(201).json({ budget });
});

router.get('/:id/budgets', async (req: AuthedRequest, res: Response) => {
  const m = await checkFamilyMembership(req.params.id, req.userId!);
  if (!m) return res.status(404).json({ error: 'NOT_MEMBER' });

  const budgets = await prisma.familyBudget.findMany({
    where: { familyId: req.params.id },
    include: { contributions: true },
    orderBy: { month: 'desc' },
    take: 12,
  });
  res.json({ budgets });
});

router.post('/budgets/:budgetId/contributions', async (req: AuthedRequest, res: Response) => {
  const budget = await prisma.familyBudget.findUnique({
    where: { id: req.params.budgetId },
    include: { family: { include: { members: true } } },
  });
  if (!budget) return res.status(404).json({ error: 'NOT_FOUND' });

  const isMember = budget.family.members.some(m => m.userId === req.userId);
  if (!isMember) return res.status(403).json({ error: 'NOT_MEMBER' });

  const schema = z.object({
    amount: z.number().positive(),
    note: z.string().optional(),
  });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });

  const contribution = await prisma.familyBudgetContribution.create({
    data: {
      familyBudgetId: budget.id,
      userId: req.userId!,
      amount: parsed.data.amount,
      note: parsed.data.note,
    },
  });

  // Recalculer totalIncome
  const total = await prisma.familyBudgetContribution.aggregate({
    where: { familyBudgetId: budget.id },
    _sum: { amount: true },
  });
  await prisma.familyBudget.update({
    where: { id: budget.id },
    data: { totalIncome: total._sum.amount || 0 },
  });

  res.status(201).json({ contribution });
});

// =====================================================================
// OBJECTIFS FAMILIAUX
// =====================================================================

router.post('/:id/goals', async (req: AuthedRequest, res: Response) => {
  const m = await checkFamilyMembership(req.params.id, req.userId!);
  if (!m) return res.status(404).json({ error: 'NOT_MEMBER' });

  const schema = z.object({
    title: z.string().min(1).max(200),
    description: z.string().optional(),
    targetAmount: z.number().positive(),
    deadline: z.string().optional(),
    assignedTo: z.string().optional(),
  });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });

  const goal = await prisma.familyGoal.create({
    data: {
      ...parsed.data,
      deadline: parsed.data.deadline ? new Date(parsed.data.deadline) : null,
      familyId: req.params.id,
    },
  });
  res.status(201).json({ goal });
});

router.get('/:id/goals', async (req: AuthedRequest, res: Response) => {
  const m = await checkFamilyMembership(req.params.id, req.userId!);
  if (!m) return res.status(404).json({ error: 'NOT_MEMBER' });

  const goals = await prisma.familyGoal.findMany({
    where: { familyId: req.params.id, completed: false },
    orderBy: { createdAt: 'desc' },
  });
  res.json({ goals });
});

router.patch('/goals/:goalId', async (req: AuthedRequest, res: Response) => {
  const goal = await prisma.familyGoal.findUnique({
    where: { id: req.params.goalId },
    include: { family: { include: { members: true } } },
  });
  if (!goal) return res.status(404).json({ error: 'NOT_FOUND' });

  const isMember = goal.family.members.some(m => m.userId === req.userId);
  if (!isMember) return res.status(403).json({ error: 'NOT_MEMBER' });

  const schema = z.object({
    title: z.string().optional(),
    description: z.string().optional(),
    targetAmount: z.number().positive().optional(),
    currentAmount: z.number().optional(),
    deadline: z.string().nullable().optional(),
    assignedTo: z.string().nullable().optional(),
    completed: z.boolean().optional(),
  });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });

  const updated = await prisma.familyGoal.update({
    where: { id: goal.id },
    data: {
      ...parsed.data,
      deadline: parsed.data.deadline === null ? null : parsed.data.deadline ? new Date(parsed.data.deadline) : undefined,
    },
  });
  res.json({ goal: updated });
});

// Dashboard famille
router.get('/:id/dashboard', async (req: AuthedRequest, res: Response) => {
  const m = await checkFamilyMembership(req.params.id, req.userId!);
  if (!m) return res.status(404).json({ error: 'NOT_MEMBER' });

  const now = new Date();
  const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);

  const [family, members, currentBudget, goals, memberCount] = await Promise.all([
    prisma.family.findUnique({
      where: { id: req.params.id },
      include: { members: { include: { user: { select: { id: true, firstName: true, lastName: true, avatarUrl: true } } } } },
    }),
    prisma.familyMember.findMany({
      where: { familyId: req.params.id },
      include: { user: { select: { id: true, firstName: true, lastName: true } } },
    }),
    prisma.familyBudget.findUnique({
      where: { familyId_month: { familyId: req.params.id, month: startOfMonth } },
      include: { contributions: true },
    }),
    prisma.familyGoal.findMany({ where: { familyId: req.params.id, completed: false } }),
    prisma.familyMember.count({ where: { familyId: req.params.id } }),
  ]);

  const totalContributions = currentBudget?.contributions.reduce((s, c) => s + c.amount.toNumber(), 0) || 0;
  const totalGoalsTarget = goals.reduce((s, g) => s + g.targetAmount.toNumber(), 0);
  const totalGoalsCurrent = goals.reduce((s, g) => s + g.currentAmount.toNumber(), 0);

  res.json({
    family,
    memberCount,
    currentMonth: {
      budget: currentBudget,
      totalContributions,
    },
    goals: {
      active: goals.length,
      totalTarget: totalGoalsTarget,
      totalCurrent: totalGoalsCurrent,
      progress: totalGoalsTarget > 0 ? Math.round((totalGoalsCurrent / totalGoalsTarget) * 100) : 0,
    },
  });
});

export default router;
