// V2 — Notifications : routes API
import { Router, type Response } from 'express';
import { prisma } from '../db.js';
import { authRequired, type AuthedRequest } from '../middleware/auth.js';

const router = Router();
router.use(authRequired);

// Liste des notifications
router.get('/', async (req: AuthedRequest, res: Response) => {
  const limit = Math.min(parseInt(String(req.query.limit || '50'), 10), 200);
  const unreadOnly = req.query.unread === 'true';

  const notifications = await prisma.notificationLog.findMany({
    where: { userId: req.userId, ...(unreadOnly ? { read: false } : {}) },
    orderBy: { createdAt: 'desc' },
    take: limit,
  });

  const unreadCount = await prisma.notificationLog.count({
    where: { userId: req.userId, read: false },
  });

  res.json({ notifications, unreadCount });
});

// Marquer comme lu
router.post('/:id/read', async (req: AuthedRequest, res: Response) => {
  await prisma.notificationLog.updateMany({
    where: { id: req.params.id, userId: req.userId },
    data: { read: true, readAt: new Date() },
  });
  res.json({ ok: true });
});

// Marquer tout comme lu
router.post('/read-all', async (req: AuthedRequest, res: Response) => {
  await prisma.notificationLog.updateMany({
    where: { userId: req.userId, read: false },
    data: { read: true, readAt: new Date() },
  });
  res.json({ ok: true });
});

// Supprimer une notification
router.delete('/:id', async (req: AuthedRequest, res: Response) => {
  await prisma.notificationLog.deleteMany({
    where: { id: req.params.id, userId: req.userId },
  });
  res.json({ ok: true });
});

// Programmer un rappel personnalisé
router.post('/schedule', async (req: AuthedRequest, res: Response) => {
  const { type, title, body, scheduledFor, data } = req.body;
  if (!title || !scheduledFor) return res.status(400).json({ error: 'INVALID_INPUT' });

  const notif = await prisma.notificationLog.create({
    data: {
      userId: req.userId!,
      type: type || 'CUSTOM',
      title,
      body: body || '',
      data,
      scheduledFor: new Date(scheduledFor),
    },
  });

  res.status(201).json({ notification: notif });
});

// Génère les notifications intelligentes du jour (rappels factures, dettes, habitudes)
router.post('/generate-daily', async (req: AuthedRequest, res: Response) => {
  const userId = req.userId!;
  const today = new Date();
  const todayStr = today.toISOString().slice(0, 10);

  // Évite de générer 2x le même jour
  const existing = await prisma.notificationLog.findFirst({
    where: {
      userId,
      type: 'DAILY_SUMMARY',
      createdAt: { gte: new Date(todayStr) },
    },
  });
  if (existing) return res.json({ ok: true, alreadyGenerated: true });

  const generated: any[] = [];

  // 1. Factures à venir (J-3 et J-0)
  const bills = await prisma.bill.findMany({
    where: { userId, status: { in: ['PENDING', 'LATE'] } },
  });
  for (const bill of bills) {
    const days = Math.ceil((bill.nextDueDate.getTime() - today.getTime()) / (24 * 60 * 60 * 1000));
    if (days <= 3 && days >= 0) {
      const n = await prisma.notificationLog.create({
        data: {
          userId,
          type: 'BILL_DUE',
          title: days === 0 ? `Facture à payer aujourd'hui` : `Facture dans ${days} jour(s)`,
          body: `${bill.name} — ${bill.amount.toNumber().toLocaleString('fr-FR')} FCFA`,
          data: { billId: bill.id, amount: bill.amount.toNumber() },
          scheduledFor: today,
        },
      });
      generated.push(n);
    }
  }

  // 2. Dettes à échéance proche
  const debts = await prisma.debt.findMany({ where: { userId, settled: false, dueDate: { not: null } } });
  for (const debt of debts) {
    const days = Math.ceil((debt.dueDate!.getTime() - today.getTime()) / (24 * 60 * 60 * 1000));
    if (days <= 7 && days >= 0) {
      const n = await prisma.notificationLog.create({
        data: {
          userId,
          type: 'DEBT_DUE',
          title: days === 0 ? `Dette à rembourser aujourd'hui` : `Dette dans ${days} jour(s)`,
          body: `${debt.isOwing ? 'Tu dois à' : 'On te doit'} ${debt.personName} — ${debt.amount.toNumber().toLocaleString('fr-FR')} FCFA`,
          data: { debtId: debt.id },
          scheduledFor: today,
        },
      });
      generated.push(n);
    }
  }

  // 3. Habitudes du jour non faites
  const todayHabits = await prisma.habitLog.findMany({
    where: { userId, date: new Date(todayStr), completed: true },
  });
  const activeHabits = await prisma.habit.count({ where: { userId, active: true } });
  const pendingHabits = activeHabits - todayHabits.length;

  if (pendingHabits > 0 && today.getHours() >= 18) {
    const n = await prisma.notificationLog.create({
      data: {
        userId,
        type: 'HABIT_REMINDER',
        title: `${pendingHabits} habitude(s) à accomplir`,
        body: `Il te reste ${pendingHabits} habitude(s) à cocher aujourd'hui. Tu peux le faire !`,
        scheduledFor: today,
      },
    });
    generated.push(n);
  }

  // 4. Résumé quotidien (matin)
  if (today.getHours() < 12) {
    const startOfMonth = new Date(today.getFullYear(), today.getMonth(), 1);
    const monthTxs = await prisma.transaction.findMany({ where: { userId, date: { gte: startOfMonth } } });
    const expenses = monthTxs.filter(t => t.type === 'EXPENSE').reduce((s, t) => s + t.amount.toNumber(), 0);
    const income = monthTxs.filter(t => t.type === 'INCOME').reduce((s, t) => s + t.amount.toNumber(), 0);
    const savings = income - expenses;

    const n = await prisma.notificationLog.create({
      data: {
        userId,
        type: 'DAILY_SUMMARY',
        title: 'Bonjour ! Voici ton résumé',
        body: savings >= 0
          ? `Ce mois: +${savings.toLocaleString('fr-FR')} FCFA d'épargne. Continue ainsi !`
          : `Attention: tu es à -${Math.abs(savings).toLocaleString('fr-FR')} FCFA ce mois.`,
        scheduledFor: today,
      },
    });
    generated.push(n);
  }

  res.json({ ok: true, generated: generated.length, notifications: generated });
});

export default router;
