import { Router, type Response } from 'express';
import { z } from 'zod';
import { prisma } from '../db.js';
import { authRequired, type AuthedRequest } from '../middleware/auth.js';

const router = Router();
router.use(authRequired);

// =====================================================================
// HOME DASHBOARD 360°
// =====================================================================

router.get('/home', async (req: AuthedRequest, res: Response) => {
  const userId = req.userId!;
  const now = new Date();
  const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
  const weekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);

  const [
    accounts, monthTxs, prevTxs, savingsGoals, debts, bills,
    sleepLogs, moodLogs, workouts, weekHabits, todayHabits, goals,
    boutiqueLogs, conversations, unreadInsights,
  ] = await Promise.all([
    prisma.account.findMany({ where: { userId, archived: false } }),
    prisma.transaction.findMany({ where: { userId, date: { gte: startOfMonth } } }),
    prisma.transaction.findMany({ where: { userId, date: { gte: new Date(now.getFullYear(), now.getMonth() - 1, 1), lt: startOfMonth } } }),
    prisma.savingsGoal.findMany({ where: { userId, archived: false } }),
    prisma.debt.findMany({ where: { userId, settled: false } }),
    prisma.bill.findMany({ where: { userId, status: { in: ['PENDING', 'LATE'] } } }),
    prisma.sleepLog.findMany({ where: { userId, date: { gte: weekAgo } } }),
    prisma.moodLog.findMany({ where: { userId, date: { gte: weekAgo } } }),
    prisma.workoutLog.findMany({ where: { userId, date: { gte: weekAgo } } }),
    prisma.habitLog.findMany({ where: { userId, date: { gte: weekAgo }, completed: true } }),
    prisma.habitLog.findMany({ where: { userId, date: new Date(now.toISOString().slice(0, 10)), completed: true } }),
    prisma.lifeGoal.findMany({ where: { userId, status: 'ACTIVE' } }),
    prisma.dailyBoutiqueLog.findMany({ where: { userId, date: { gte: weekAgo } } }),
    prisma.aiConversation.findMany({ where: { userId }, orderBy: { updatedAt: 'desc' }, take: 1, include: { messages: { orderBy: { createdAt: 'desc' }, take: 1 } } }),
    prisma.aiInsight.count({ where: { userId, read: false } }),
  ]);

  // ---------- Score Finance ----------
  const totalBalance = accounts.reduce((s, a) => s + a.balance.toNumber(), 0);
  const income = monthTxs.filter(t => t.type === 'INCOME').reduce((s, t) => s + t.amount.toNumber(), 0);
  const expenses = monthTxs.filter(t => t.type === 'EXPENSE').reduce((s, t) => s + t.amount.toNumber(), 0);
  const savings = income - expenses;
  const savingsRate = income > 0 ? Math.round((savings / income) * 100) : 0;
  let financeScore = 50;
  if (savingsRate >= 20) financeScore += 20;
  if (savingsRate >= 30) financeScore += 10;
  if (totalBalance > 0) financeScore += 10;
  if (debts.length === 0) financeScore += 10;
  if (savingsGoals.some(g => g.currentAmount.toNumber() > 0)) financeScore += 10;
  if (savingsRate < 0) financeScore = Math.max(0, financeScore - 20);
  financeScore = Math.max(0, Math.min(100, financeScore));

  // ---------- Score Santé ----------
  const avgSleep = sleepLogs.length ? sleepLogs.reduce((s, l) => s + l.durationMin, 0) / sleepLogs.length / 60 : 0;
  const avgEnergy = moodLogs.length ? moodLogs.reduce((s, l) => s + l.energy, 0) / moodLogs.length : 0;
  let healthScore = 50;
  if (avgSleep >= 7) healthScore += 15;
  if (avgSleep >= 6) healthScore += 5;
  if (avgEnergy >= 6) healthScore += 10;
  if (avgEnergy >= 4) healthScore += 5;
  if (workouts.length >= 2) healthScore += 10;
  if (workouts.length >= 3) healthScore += 5;
  healthScore = Math.max(0, Math.min(100, healthScore));

  // ---------- Score Routines ----------
  const totalHabitsThisWeek = weekHabits.length;
  const habitScore = Math.min(100, Math.round((totalHabitsThisWeek / 21) * 100)); // ~3 habitudes x 7 jours

  // ---------- Score Objectifs ----------
  const activeGoals = goals.length;
  const goalsWithProgress = goals.filter(g => g.currentValue && g.targetValue && g.currentValue.toNumber() / g.targetValue.toNumber() > 0.1).length;
  let goalScore = activeGoals === 0 ? 30 : Math.min(100, 40 + (goalsWithProgress / activeGoals) * 60);

  // ---------- Score global vie (pondéré) ----------
  const globalScore = Math.round(
    financeScore * 0.30 +
    healthScore * 0.20 +
    habitScore * 0.20 +
    goalScore * 0.15 +
    70 * 0.075 + // Carrière (placeholder)
    65 * 0.075   // Relations (placeholder)
  );

  // ---------- Today's habits ----------
  const todayHabitsDone = todayHabits.length;

  // ---------- Top priorités ----------
  const topGoals = goals
    .filter(g => g.priority === 'HIGH')
    .slice(0, 3)
    .map(g => ({ id: g.id, title: g.title, domain: g.domain }));

  // ---------- Alertes ----------
  const alerts: { type: string; message: string }[] = [];
  if (bills.length > 0) {
    const nextBill = bills.sort((a, b) => a.nextDueDate.getTime() - b.nextDueDate.getTime())[0];
    const days = Math.ceil((nextBill.nextDueDate.getTime() - now.getTime()) / (24 * 60 * 60 * 1000));
    if (days <= 3) {
      alerts.push({ type: 'BILL', message: `Facture "${nextBill.name}" à payer dans ${days} jour(s) — ${nextBill.amount.toNumber().toLocaleString('fr-FR')} FCFA` });
    }
  }
  if (debts.length > 0) {
    const nextDebt = debts.filter(d => d.dueDate).sort((a, b) => a.dueDate!.getTime() - b.dueDate!.getTime())[0];
    if (nextDebt?.dueDate) {
      const days = Math.ceil((nextDebt.dueDate.getTime() - now.getTime()) / (24 * 60 * 60 * 1000));
      if (days <= 7 && days >= 0) {
        alerts.push({ type: 'DEBT', message: `Dette envers ${nextDebt.personName} à rembourser dans ${days} jour(s)` });
      }
    }
  }
  if (avgSleep > 0 && avgSleep < 6) {
    alerts.push({ type: 'SLEEP', message: `Tu dors en moyenne ${avgSleep.toFixed(1)}h cette semaine — vise 7h+` });
  }
  if (savingsRate < 0) {
    alerts.push({ type: 'FINANCE', message: `Tu dépenses plus que tu ne gagnes ce mois (-${Math.abs(savingsRate)}%)` });
  }

  return res.json({
    globalScore,
    scores: {
      finance: financeScore,
      health: healthScore,
      routines: habitScore,
      goals: goalScore,
      career: 70, // placeholder
      relations: 65, // placeholder
    },
    financial: {
      totalBalance,
      income,
      expenses,
      savings,
      savingsRate,
      accountsCount: accounts.length,
    },
    health: {
      avgSleep: Math.round(avgSleep * 10) / 10,
      avgEnergy: Math.round(avgEnergy * 10) / 10,
      weekWorkouts: workouts.length,
    },
    habits: {
      doneToday: todayHabitsDone,
      doneThisWeek: totalHabitsThisWeek,
    },
    goals: {
      active: activeGoals,
      topPriorities: topGoals,
    },
    alerts,
    boutiqueWeekProfit: boutiqueLogs.reduce((s, l) => s + l.netProfit.toNumber(), 0),
    unreadInsights,
    lastConversation: conversations[0]?.id || null,
  });
});

// =====================================================================
// USER SETTINGS & PROFILE
// =====================================================================

const profileSchema = z.object({
  firstName: z.string().min(1).max(80).optional(),
  lastName: z.string().max(80).nullable().optional(),
  phone: z.string().max(30).nullable().optional(),
  avatarUrl: z.string().nullable().optional(),
  language: z.enum(['FR', 'FON', 'BARIBA', 'YORUBA']).optional(),
  appMode: z.enum(['STANDARD', 'ACCESSIBLE']).optional(),
  currency: z.string().max(5).optional(),
  onboarded: z.boolean().optional(),
  accessibleOnboarded: z.boolean().optional(),
});

router.patch('/profile', async (req: AuthedRequest, res: Response) => {
  const parsed = profileSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
  const user = await prisma.user.update({
    where: { id: req.userId },
    data: parsed.data,
    select: {
      id: true, email: true, firstName: true, lastName: true, phone: true,
      plan: true, language: true, appMode: true, currency: true,
      onboarded: true, accessibleOnboarded: true, avatarUrl: true,
    },
  });
  res.json({ user });
});

router.get('/settings', async (req: AuthedRequest, res: Response) => {
  let settings = await prisma.userSetting.findUnique({ where: { userId: req.userId } });
  if (!settings) {
    settings = await prisma.userSetting.create({ data: { userId: req.userId! } });
  }
  res.json({ settings });
});

router.patch('/settings', async (req: AuthedRequest, res: Response) => {
  const schema = z.object({
    notificationsEnabled: z.boolean().optional(),
    dailyReminderHour: z.number().int().min(0).max(23).optional(),
    weeklyReportDay: z.number().int().min(0).max(6).optional(),
    weeklyReportHour: z.number().int().min(0).max(23).optional(),
    sleepGoalHours: z.number().int().min(4).max(12).optional(),
    hydrationGoalMl: z.number().int().min(500).max(10000).optional(),
    weeklyWorkoutGoal: z.number().int().min(0).max(14).optional(),
    monthlySavingsPct: z.number().int().min(0).max(80).optional(),
  });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
  const settings = await prisma.userSetting.upsert({
    where: { userId: req.userId! },
    update: parsed.data,
    create: { userId: req.userId!, ...parsed.data },
  });
  res.json({ settings });
});

export default router;
