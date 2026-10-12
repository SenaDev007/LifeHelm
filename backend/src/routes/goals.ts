import { Router, type Response } from 'express';
import { z } from 'zod';
import { prisma } from '../db.js';
import { authRequired, type AuthedRequest } from '../middleware/auth.js';

const router = Router();
router.use(authRequired);

// =====================================================================
// LIFE GOALS
// =====================================================================

const goalSchema = z.object({
  domain: z.enum(['FINANCE', 'HEALTH', 'CAREER', 'RELATIONS', 'PERSONAL', 'SPIRITUAL', 'FAMILY', 'EDUCATION', 'OTHER']),
  title: z.string().min(1).max(200),
  description: z.string().optional(),
  type: z.enum(['BINARY', 'NUMERIC', 'MILESTONE']).optional().default('BINARY'),
  priority: z.union([z.enum(['LOW', 'MEDIUM', 'HIGH']), z.number().int().min(1).max(5)]).optional().default('MEDIUM'),
  status: z.enum(['ACTIVE', 'PAUSED', 'COMPLETED', 'ABANDONED']).optional().default('ACTIVE'),
  targetValue: z.number().optional(),
  currentValue: z.number().optional(),
  unit: z.string().optional(),
  deadline: z.string().optional(),
  isPublic: z.boolean().optional(),
  imageUrl: z.string().optional(),
  vision: z.string().optional(),
  visionHorizon: z.enum(['1Y', '3Y', '5Y', '10Y']).optional(),
});

router.get('/', async (req: AuthedRequest, res: Response) => {
  const goals = await prisma.lifeGoal.findMany({
    where: { userId: req.userId, status: { not: 'ABANDONED' } },
    include: {
      projects: { include: { tasks: true } },
      journal: { orderBy: { createdAt: 'desc' }, take: 5 },
    },
    orderBy: { createdAt: 'desc' },
  });
  res.json({ goals });
});

router.post('/', async (req: AuthedRequest, res: Response) => {
  const parsed = goalSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT', details: parsed.error.issues });
  const { deadline, priority, domain, ...rest } = parsed.data;
  const normalizedPriority = typeof priority === 'number' ? (priority <= 2 ? 'HIGH' : priority >= 4 ? 'LOW' : 'MEDIUM') : priority;
  const normalizedDomain = domain === 'EDUCATION' || domain === 'OTHER' ? 'PERSONAL' : domain;
  const goal = await prisma.lifeGoal.create({
    data: { ...rest, domain: normalizedDomain, priority: normalizedPriority, deadline: deadline ? new Date(deadline) : null, userId: req.userId! },
  });
  res.status(201).json({ goal });
});

router.patch('/:id', async (req: AuthedRequest, res: Response) => {
  const parsed = goalSchema.partial().safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
  const { deadline, priority, domain, ...rest } = parsed.data;
  const normalizedPriority = typeof priority === 'number' ? (priority <= 2 ? 'HIGH' : priority >= 4 ? 'LOW' : 'MEDIUM') : priority;
  const normalizedDomain = domain === 'EDUCATION' || domain === 'OTHER' ? 'PERSONAL' : domain;
  const result = await prisma.lifeGoal.updateMany({
    where: { id: req.params.id, userId: req.userId },
    data: {
      ...rest,
      ...(normalizedDomain ? { domain: normalizedDomain } : {}),
      ...(normalizedPriority ? { priority: normalizedPriority } : {}),
      deadline: deadline ? new Date(deadline) : undefined,
    },
  });
  if (result.count === 0) return res.status(404).json({ error: 'NOT_FOUND' });
  const goal = await prisma.lifeGoal.findFirst({ where: { id: req.params.id, userId: req.userId } });
  res.json({ goal });
});

router.delete('/:id', async (req: AuthedRequest, res: Response) => {
  await prisma.lifeGoal.updateMany({
    where: { id: req.params.id, userId: req.userId },
    data: { status: 'ABANDONED' },
  });
  res.json({ ok: true });
});

router.post('/:id/progress', async (req: AuthedRequest, res: Response) => {
  const parsed = z.object({ increment: z.number().positive() }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
  const goal = await prisma.lifeGoal.findFirst({ where: { id: req.params.id, userId: req.userId, status: 'ACTIVE' } });
  if (!goal) return res.status(404).json({ error: 'NOT_FOUND' });
  const current = goal.currentValue?.toNumber() ?? 0;
  const target = goal.targetValue?.toNumber();
  const next = target == null ? current + parsed.data.increment : Math.min(target, current + parsed.data.increment);
  const updated = await prisma.lifeGoal.update({
    where: { id: goal.id },
    data: { currentValue: next, ...(target != null && next >= target ? { status: 'COMPLETED' } : {}) },
  });
  await prisma.goalJournal.create({ data: { goalId: goal.id, note: `Progression : ${next}${goal.unit ? ` ${goal.unit}` : ''}`, progress: target && target > 0 ? Math.min(100, Math.round(next / target * 100)) : null } });
  res.json({ goal: updated });
});

router.post('/:id/complete', async (req: AuthedRequest, res: Response) => {
  const result = await prisma.lifeGoal.updateMany({ where: { id: req.params.id, userId: req.userId, status: { not: 'ABANDONED' } }, data: { status: 'COMPLETED' } });
  if (!result.count) return res.status(404).json({ error: 'NOT_FOUND' });
  const goal = await prisma.lifeGoal.findFirst({ where: { id: req.params.id, userId: req.userId } });
  res.json({ goal });
});

// =====================================================================
// PROJECTS & TASKS
// =====================================================================

router.post('/:id/projects', async (req: AuthedRequest, res: Response) => {
  const goal = await prisma.lifeGoal.findFirst({ where: { id: req.params.id, userId: req.userId } });
  if (!goal) return res.status(404).json({ error: 'NOT_FOUND' });
  const schema = z.object({
    name: z.string().min(1).max(120),
    description: z.string().optional(),
    endDate: z.string().optional(),
  });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
  const project = await prisma.goalProject.create({
    data: {
      goalId: goal.id,
      name: parsed.data.name,
      description: parsed.data.description,
      endDate: parsed.data.endDate ? new Date(parsed.data.endDate) : null,
    },
  });
  res.status(201).json({ project });
});

router.post('/projects/:id/tasks', async (req: AuthedRequest, res: Response) => {
  const project = await prisma.goalProject.findFirst({
    where: { id: req.params.id, goal: { userId: req.userId } },
  });
  if (!project) return res.status(404).json({ error: 'NOT_FOUND' });
  const schema = z.object({
    title: z.string().min(1).max(200),
    description: z.string().optional(),
    dueDate: z.string().optional(),
  });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
  const task = await prisma.goalTask.create({
    data: {
      projectId: project.id,
      title: parsed.data.title,
      description: parsed.data.description,
      dueDate: parsed.data.dueDate ? new Date(parsed.data.dueDate) : null,
    },
  });
  res.status(201).json({ task });
});

router.patch('/tasks/:id', async (req: AuthedRequest, res: Response) => {
  const schema = z.object({
    title: z.string().optional(),
    status: z.enum(['TODO', 'IN_PROGRESS', 'DONE', 'BLOCKED']).optional(),
    dueDate: z.string().nullable().optional(),
  });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
  const task = await prisma.goalTask.findFirst({
    where: { id: req.params.id, project: { goal: { userId: req.userId } } },
  });
  if (!task) return res.status(404).json({ error: 'NOT_FOUND' });
  const updated = await prisma.goalTask.update({
    where: { id: task.id },
    data: {
      ...parsed.data,
      dueDate: parsed.data.dueDate === null ? null : parsed.data.dueDate ? new Date(parsed.data.dueDate) : undefined,
      completedAt: parsed.data.status === 'DONE' ? new Date() : undefined,
    },
  });
  res.json({ task: updated });
});

router.delete('/tasks/:id', async (req: AuthedRequest, res: Response) => {
  await prisma.goalTask.deleteMany({
    where: { id: req.params.id, project: { goal: { userId: req.userId } } },
  });
  res.json({ ok: true });
});

// =====================================================================
// JOURNAL
// =====================================================================

router.post('/:id/journal', async (req: AuthedRequest, res: Response) => {
  const schema = z.object({ note: z.string().min(1).max(5000), progress: z.number().int().min(0).max(100).optional() });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
  const goal = await prisma.lifeGoal.findFirst({ where: { id: req.params.id, userId: req.userId } });
  if (!goal) return res.status(404).json({ error: 'NOT_FOUND' });
  const entry = await prisma.goalJournal.create({
    data: { goalId: goal.id, note: parsed.data.note, progress: parsed.data.progress },
  });
  res.status(201).json({ entry });
});

export default router;
