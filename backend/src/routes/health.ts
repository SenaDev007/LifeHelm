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
  bedtime: z.string().optional(),
  wakeTime: z.string().optional(),
  hours: z.number().min(0.5).max(24).optional(),
  quality: z.number().int().min(1).max(5),
  note: z.string().optional(),
}).refine((value) => value.hours != null || (value.bedtime != null && value.wakeTime != null), {
  message: 'HOURS_OR_SLEEP_TIMES_REQUIRED',
});

router.get('/sleep', async (req: AuthedRequest, res: Response) => {
  const limit = Math.min(parseInt(String(req.query.limit || '30'), 10), 365);
  const logs = await prisma.sleepLog.findMany({
    where: { userId: req.userId },
    orderBy: { date: 'desc' },
    take: limit,
  });
  res.json({ logs: logs.map((log) => ({ ...log, hours: Math.round(log.durationMin / 6) / 10 })) });
});

router.post('/sleep', async (req: AuthedRequest, res: Response) => {
  const parsed = sleepSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
  const date = new Date(parsed.data.date);
  const bedtime = parsed.data.bedtime ? new Date(parsed.data.bedtime) : new Date(date);
  const wakeTime = parsed.data.wakeTime
    ? new Date(parsed.data.wakeTime)
    : new Date(bedtime.getTime() + (parsed.data.hours ?? 0) * 60 * 60 * 1000);
  const durationMin = parsed.data.hours != null
    ? Math.round(parsed.data.hours * 60)
    : Math.round((wakeTime.getTime() - bedtime.getTime()) / 60000);
  if (durationMin <= 0 || !Number.isFinite(durationMin)) return res.status(400).json({ error: 'INVALID_SLEEP_DURATION' });
  const log = await prisma.sleepLog.upsert({
    where: { userId_date: { userId: req.userId!, date } },
    update: { bedtime, wakeTime, durationMin, quality: parsed.data.quality, note: parsed.data.note },
    create: { userId: req.userId!, date, bedtime, wakeTime, durationMin, quality: parsed.data.quality, note: parsed.data.note },
  });
  res.status(201).json({ log: { ...log, hours: Math.round(log.durationMin / 6) / 10 } });
});

// =====================================================================
// MOOD LOGS
// =====================================================================

const moodSchema = z.object({
  date: z.string().optional(),
  mood: z.union([z.enum(['VERY_BAD', 'BAD', 'NEUTRAL', 'GOOD', 'VERY_GOOD']), z.number().int().min(1).max(5)]),
  energy: z.number().int().min(1).max(10).optional().default(5),
  emotions: z.array(z.string()).optional(),
  note: z.string().optional(),
});

router.get('/mood', async (req: AuthedRequest, res: Response) => {
  const limit = Math.min(parseInt(String(req.query.limit || '30'), 10), 365);
  const logs = await prisma.moodLog.findMany({ where: { userId: req.userId }, orderBy: { date: 'desc' }, take: limit });
  res.json({ logs: logs.map((log) => ({ ...log, mood: ['VERY_BAD', 'BAD', 'NEUTRAL', 'GOOD', 'VERY_GOOD'].indexOf(log.mood) + 1 })) });
});

router.post('/mood', async (req: AuthedRequest, res: Response) => {
  const parsed = moodSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
  const mood = typeof parsed.data.mood === 'number'
    ? (['VERY_BAD', 'BAD', 'NEUTRAL', 'GOOD', 'VERY_GOOD'] as const)[parsed.data.mood - 1]
    : parsed.data.mood;
  const date = new Date(parsed.data.date ?? new Date().toISOString());
  const log = await prisma.moodLog.upsert({
    where: { userId_date: { userId: req.userId!, date } },
    update: { mood, energy: parsed.data.energy, emotions: parsed.data.emotions || [], note: parsed.data.note },
    create: { userId: req.userId!, date, mood, energy: parsed.data.energy, emotions: parsed.data.emotions || [], note: parsed.data.note },
  });
  res.status(201).json({ log: { ...log, mood: ['VERY_BAD', 'BAD', 'NEUTRAL', 'GOOD', 'VERY_GOOD'].indexOf(log.mood) + 1 } });
});

// =====================================================================
// WORKOUT LOGS
// =====================================================================

const workoutSchema = z.object({
  date: z.string().optional(),
  type: z.string().min(1).max(80),
  durationMin: z.number().int().positive(),
  intensity: z.number().int().min(1).max(5).optional().default(3),
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
      date: new Date(parsed.data.date ?? new Date().toISOString()),
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
  res.json({ todayMl: log?.amountMl ?? 0, goalMl: log?.goalMl ?? 2000, date: dateStr, log, logs: [] });
});

const hydrationSchema = z.object({
  date: z.string().optional(),
  amountMl: z.number().int().min(0).optional(),
  addMl: z.number().int().min(1).optional(),
  goalMl: z.number().int().min(1).optional().default(2000),
}).refine((value) => value.amountMl != null || value.addMl != null);

async function saveHydration(req: AuthedRequest, res: Response, incrementOnly: boolean) {
  const parsed = hydrationSchema.safeParse(req.body);
  if (!parsed.success || (incrementOnly && parsed.data?.addMl == null)) return res.status(400).json({ error: 'INVALID_INPUT' });
  const date = new Date(parsed.data.date ?? new Date().toISOString());
  const existing = await prisma.hydrationLog.findUnique({ where: { userId_date: { userId: req.userId!, date } } });
  const amountMl = parsed.data.addMl != null
    ? (existing?.amountMl ?? 0) + parsed.data.addMl
    : parsed.data.amountMl!;
  const log = await prisma.hydrationLog.upsert({
    where: { userId_date: { userId: req.userId!, date } },
    update: { amountMl, goalMl: parsed.data.goalMl },
    create: { userId: req.userId!, date, amountMl, goalMl: parsed.data.goalMl },
  });
  res.status(201).json({ todayMl: log.amountMl, goalMl: log.goalMl, date: log.date, log, logs: [] });
}

router.post('/hydration', (req: AuthedRequest, res: Response) => saveHydration(req, res, false));
router.post('/hydration/add', (req: AuthedRequest, res: Response) => saveHydration(req, res, true));

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
