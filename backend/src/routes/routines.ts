import { Router, type Response } from 'express';
import { z } from 'zod';
import { prisma } from '../db.js';
import { authRequired, type AuthedRequest } from '../middleware/auth.js';

const router = Router();
router.use(authRequired);

// =====================================================================
// HABITS
// =====================================================================

const habitSchema = z.object({
  name: z.string().min(1).max(120),
  description: z.string().optional(),
  type: z.enum(['BINARY', 'NUMERIC']).optional().default('BINARY'),
  frequency: z.enum(['DAILY', 'WEEKLY', 'CUSTOM']).optional().default('DAILY'),
  targetValue: z.number().optional(),
  unit: z.string().optional(),
  color: z.string().optional(),
  icon: z.string().optional(),
  reminderHour: z.number().int().min(0).max(23).optional(),
  reminderMin: z.number().int().min(0).max(59).optional(),
});

router.get('/habits', async (req: AuthedRequest, res: Response) => {
  const habits = await prisma.habit.findMany({
    where: { userId: req.userId, active: true },
    include: { logs: { orderBy: { date: 'desc' }, take: 90 } },
    orderBy: { createdAt: 'asc' },
  });
  res.json({ habits });
});

router.post('/habits', async (req: AuthedRequest, res: Response) => {
  const parsed = habitSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
  const habit = await prisma.habit.create({
    data: { ...parsed.data, userId: req.userId! },
  });
  res.status(201).json({ habit });
});

router.patch('/habits/:id', async (req: AuthedRequest, res: Response) => {
  const parsed = habitSchema.partial().safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
  const result = await prisma.habit.updateMany({
    where: { id: req.params.id, userId: req.userId },
    data: parsed.data,
  });
  if (result.count === 0) return res.status(404).json({ error: 'NOT_FOUND' });
  res.json({ ok: true });
});

router.delete('/habits/:id', async (req: AuthedRequest, res: Response) => {
  await prisma.habit.updateMany({
    where: { id: req.params.id, userId: req.userId },
    data: { active: false },
  });
  res.json({ ok: true });
});

// =====================================================================
// HABIT LOGS
// =====================================================================

const logSchema = z.object({
  date: z.string(),
  value: z.number().optional(),
  completed: z.boolean().optional().default(true),
  note: z.string().optional(),
});

router.post('/habits/:id/log', async (req: AuthedRequest, res: Response) => {
  const habit = await prisma.habit.findFirst({ where: { id: req.params.id, userId: req.userId } });
  if (!habit) return res.status(404).json({ error: 'NOT_FOUND' });
  const parsed = logSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
  const date = new Date(parsed.data.date);
  const log = await prisma.habitLog.upsert({
    where: { habitId_date: { habitId: habit.id, date } },
    update: { value: parsed.data.value, completed: parsed.data.completed, note: parsed.data.note },
    create: { habitId: habit.id, userId: req.userId!, date, value: parsed.data.value, completed: parsed.data.completed, note: parsed.data.note },
  });
  res.status(201).json({ log });
});

router.delete('/habits/:id/log', async (req: AuthedRequest, res: Response) => {
  const habit = await prisma.habit.findFirst({ where: { id: req.params.id, userId: req.userId } });
  if (!habit) return res.status(404).json({ error: 'NOT_FOUND' });
  const dateStr = req.query.date as string;
  if (!dateStr) return res.status(400).json({ error: 'DATE_REQUIRED' });
  await prisma.habitLog.deleteMany({ where: { habitId: habit.id, date: new Date(dateStr) } });
  res.json({ ok: true });
});

// =====================================================================
// MORNING RITUAL
// =====================================================================

router.get('/morning-ritual', async (req: AuthedRequest, res: Response) => {
  const dateStr = (req.query.date as string) || new Date().toISOString().slice(0, 10);
  const ritual = await prisma.morningRitual.findUnique({
    where: { userId_date: { userId: req.userId!, date: new Date(dateStr) } },
  });
  res.json({ ritual });
});

router.post('/morning-ritual', async (req: AuthedRequest, res: Response) => {
  const schema = z.object({
    date: z.string(),
    steps: z.array(z.object({
      key: z.string(),
      label: z.string(),
      completed: z.boolean(),
      durationSec: z.number().optional(),
    })),
    totalDuration: z.number().optional(),
    completed: z.boolean().optional(),
    note: z.string().optional(),
  });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
  const date = new Date(parsed.data.date);
  const ritual = await prisma.morningRitual.upsert({
    where: { userId_date: { userId: req.userId!, date } },
    update: {
      steps: parsed.data.steps,
      totalDuration: parsed.data.totalDuration || 0,
      completed: parsed.data.completed || false,
      completedAt: parsed.data.completed ? new Date() : null,
      note: parsed.data.note,
    },
    create: {
      userId: req.userId!,
      date,
      steps: parsed.data.steps,
      totalDuration: parsed.data.totalDuration || 0,
      completed: parsed.data.completed || false,
      completedAt: parsed.data.completed ? new Date() : null,
      note: parsed.data.note,
    },
  });
  res.status(201).json({ ritual });
});

// =====================================================================
// EVENING REVIEW
// =====================================================================

router.get('/evening-review', async (req: AuthedRequest, res: Response) => {
  const dateStr = (req.query.date as string) || new Date().toISOString().slice(0, 10);
  const review = await prisma.eveningReview.findUnique({
    where: { userId_date: { userId: req.userId!, date: new Date(dateStr) } },
  });
  res.json({ review });
});

router.post('/evening-review', async (req: AuthedRequest, res: Response) => {
  const schema = z.object({
    date: z.string(),
    gratitude: z.array(z.string()).min(1).max(5),
    reflection: z.string().optional(),
    topPriorities: z.array(z.string()).max(3).optional(),
    energyLevel: z.number().int().min(1).max(10).optional(),
  });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
  const date = new Date(parsed.data.date);
  const review = await prisma.eveningReview.upsert({
    where: { userId_date: { userId: req.userId!, date } },
    update: {
      gratitude: parsed.data.gratitude,
      reflection: parsed.data.reflection,
      topPriorities: parsed.data.topPriorities || [],
      energyLevel: parsed.data.energyLevel,
    },
    create: {
      userId: req.userId!,
      date,
      gratitude: parsed.data.gratitude,
      reflection: parsed.data.reflection,
      topPriorities: parsed.data.topPriorities || [],
      energyLevel: parsed.data.energyLevel,
    },
  });
  res.status(201).json({ review });
});

export default router;
