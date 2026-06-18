import { Router, type Response } from 'express';
import { z } from 'zod';
import { prisma } from '../db.js';
import { authRequired, type AuthedRequest } from '../middleware/auth.js';

const router = Router();
router.use(authRequired);

// =====================================================================
// SLEEP LOGS
// =====================================================================

const sleepSchema = z.object({
  date: z.string(),
  bedtime: z.string(),
  wakeTime: z.string(),
  quality: z.number().int().min(1).max(5),
  note: z.string().optional(),
});

router.get('/sleep', async (req: AuthedRequest, res: Response) => {
  const limit = Math.min(parseInt(String(req.query.limit || '30'), 10), 365);
  const logs = await prisma.sleepLog.findMany({
    where: { userId: req.userId },
    orderBy: { date: 'desc' },
    take: limit,
  });
  res.json({ logs });
});

router.post('/sleep', async (req: AuthedRequest, res: Response) => {
  const parsed = sleepSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
  const bedtime = new Date(parsed.data.bedtime);
  const wakeTime = new Date(parsed.data.wakeTime);
  const durationMin = Math.round((wakeTime.getTime() - bedtime.getTime()) / 60000);
  const log = await prisma.sleepLog.upsert({
    where: { userId_date: { userId: req.userId!, date: new Date(parsed.data.date) } },
    update: { bedtime, wakeTime, durationMin, quality: parsed.data.quality, note: parsed.data.note },
    create: {
      userId: req.userId!,
      date: new Date(parsed.data.date),
      bedtime, wakeTime, durationMin,
      quality: parsed.data.quality,
      note: parsed.data.note,
    },
  });
  res.status(201).json({ log });
});

// =====================================================================
// MOOD LOGS
// =====================================================================

const moodSchema = z.object({
  date: z.string(),
  mood: z.enum(['VERY_BAD', 'BAD', 'NEUTRAL', 'GOOD', 'VERY_GOOD']),
  energy: z.number().int().min(1).max(10),
  emotions: z.array(z.string()).optional(),
  note: z.string().optional(),
});

router.get('/mood', async (req: AuthedRequest, res: Response) => {
  const limit = Math.min(parseInt(String(req.query.limit || '30'), 10), 365);
  const logs = await prisma.moodLog.findMany({
    where: { userId: req.userId },
    orderBy: { date: 'desc' },
    take: limit,
  });
  res.json({ logs });
});

router.post('/mood', async (req: AuthedRequest, res: Response) => {
  const parsed = moodSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
  const log = await prisma.moodLog.upsert({
    where: { userId_date: { userId: req.userId!, date: new Date(parsed.data.date) } },
    update: {
      mood: parsed.data.mood,
      energy: parsed.data.energy,
      emotions: parsed.data.emotions || [],
      note: parsed.data.note,
    },
    create: {
      userId: req.userId!,
      date: new Date(parsed.data.date),
      mood: parsed.data.mood,
      energy: parsed.data.energy,
      emotions: parsed.data.emotions || [],
      note: parsed.data.note,
    },
  });
  res.status(201).json({ log });
});

// =====================================================================
// WORKOUT LOGS
// =====================================================================

const workoutSchema = z.object({
  date: z.string(),
  type: z.string().min(1).max(80),
  durationMin: z.number().int().positive(),
  intensity: z.number().int().min(1).max(5),
  calories: z.number().int().optional(),
  note: z.string().optional(),
});

router.get('/workouts', async (req: AuthedRequest, res: Response) => {
  const limit = Math.min(parseInt(String(req.query.limit || '30'), 10), 365);
  const logs = await prisma.workoutLog.findMany({
    where: { userId: req.userId },
    orderBy: { date: 'desc' },
    take: limit,
  });
  res.json({ logs });
});

router.post('/workouts', async (req: AuthedRequest, res: Response) => {
  const parsed = workoutSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
  const log = await prisma.workoutLog.create({
    data: {
      userId: req.userId!,
      date: new Date(parsed.data.date),
      type: parsed.data.type,
      durationMin: parsed.data.durationMin,
      intensity: parsed.data.intensity,
      calories: parsed.data.calories,
      note: parsed.data.note,
    },
  });
  res.status(201).json({ log });
});

router.delete('/workouts/:id', async (req: AuthedRequest, res: Response) => {
  await prisma.workoutLog.deleteMany({ where: { id: req.params.id, userId: req.userId } });
  res.json({ ok: true });
});

// =====================================================================
// HYDRATION
// =====================================================================

router.get('/hydration', async (req: AuthedRequest, res: Response) => {
  const dateStr = (req.query.date as string) || new Date().toISOString().slice(0, 10);
  const log = await prisma.hydrationLog.findUnique({
    where: { userId_date: { userId: req.userId!, date: new Date(dateStr) } },
  });
  res.json({ log });
});

router.post('/hydration', async (req: AuthedRequest, res: Response) => {
  const schema = z.object({
    date: z.string(),
    amountMl: z.number().int().min(0),
    goalMl: z.number().int().min(1).optional().default(2000),
  });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
  const log = await prisma.hydrationLog.upsert({
    where: { userId_date: { userId: req.userId!, date: new Date(parsed.data.date) } },
    update: { amountMl: parsed.data.amountMl, goalMl: parsed.data.goalMl },
    create: {
      userId: req.userId!,
      date: new Date(parsed.data.date),
      amountMl: parsed.data.amountMl,
      goalMl: parsed.data.goalMl,
    },
  });
  res.status(201).json({ log });
});

router.post('/hydration/add', async (req: AuthedRequest, res: Response) => {
  const schema = z.object({
    date: z.string(),
    addMl: z.number().int().min(1),
    goalMl: z.number().int().min(1).optional().default(2000),
  });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
  const date = new Date(parsed.data.date);
  const existing = await prisma.hydrationLog.findUnique({
    where: { userId_date: { userId: req.userId!, date } },
  });
  const newAmount = (existing?.amountMl || 0) + parsed.data.addMl;
  const log = await prisma.hydrationLog.upsert({
    where: { userId_date: { userId: req.userId!, date } },
    update: { amountMl: newAmount },
    create: { userId: req.userId!, date, amountMl: newAmount, goalMl: parsed.data.goalMl },
  });
  res.json({ log });
});

// =====================================================================
// DASHBOARD SANTÉ
// =====================================================================

router.get('/dashboard', async (req: AuthedRequest, res: Response) => {
  const userId = req.userId!;
  const now = new Date();
  const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
  const weekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);

  const [sleepLogs, moodLogs, workouts, hydrationToday] = await Promise.all([
    prisma.sleepLog.findMany({ where: { userId, date: { gte: weekAgo } }, orderBy: { date: 'desc' } }),
    prisma.moodLog.findMany({ where: { userId, date: { gte: weekAgo } }, orderBy: { date: 'desc' } }),
    prisma.workoutLog.findMany({ where: { userId, date: { gte: startOfMonth } }, orderBy: { date: 'desc' } }),
    prisma.hydrationLog.findUnique({ where: { userId_date: { userId, date: new Date(now.toISOString().slice(0, 10)) } } }),
  ]);

  const avgSleep = sleepLogs.length
    ? Math.round(sleepLogs.reduce((s, l) => s + l.durationMin, 0) / sleepLogs.length / 60 * 10) / 10
    : 0;
  const avgMood = moodLogs.length
    ? moodLogs.reduce((s, l) => {
        const v = l.mood === 'VERY_BAD' ? 1 : l.mood === 'BAD' ? 2 : l.mood === 'NEUTRAL' ? 3 : l.mood === 'GOOD' ? 4 : 5;
        return s + v;
      }, 0) / moodLogs.length
    : 0;
  const avgEnergy = moodLogs.length
    ? Math.round(moodLogs.reduce((s, l) => s + l.energy, 0) / moodLogs.length * 10) / 10
    : 0;
  const weekWorkouts = workouts.filter(w => w.date >= weekAgo).length;

  // Score santé (0-100)
  let score = 50;
  if (avgSleep >= 7) score += 15;
  if (avgSleep >= 6) score += 5;
  if (avgMood >= 3.5) score += 10;
  if (avgEnergy >= 6) score += 10;
  if (weekWorkouts >= 2) score += 10;
  if (hydrationToday && hydrationToday.amountMl >= hydrationToday.goalMl) score += 5;
  score = Math.max(0, Math.min(100, score));

  res.json({
    score,
    avgSleep,
    avgMood: Math.round(avgMood * 10) / 10,
    avgEnergy,
    weekWorkouts,
    hydration: hydrationToday || { amountMl: 0, goalMl: 2000 },
    sleepLogs: sleepLogs.slice(0, 7),
    moodLogs: moodLogs.slice(0, 7),
    workouts,
  });
});

export default router;
