// V2 — Sync Queue : pour l'offline-first
import { Router, type Response } from 'express';
import { z } from 'zod';
import { prisma } from '../db.js';
import { authRequired, type AuthedRequest } from '../middleware/auth.js';

const router = Router();
router.use(authRequired);

// Push un batch d'items créés/modifiés offline
router.post('/push', async (req: AuthedRequest, res: Response) => {
  const schema = z.object({
    items: z.array(z.object({
      entityType: z.enum([
        'TRANSACTION', 'ACCOUNT', 'SAVINGS_GOAL', 'HABIT', 'HABIT_LOG',
        'LIFE_GOAL', 'SLEEP_LOG', 'MOOD_LOG', 'WORKOUT_LOG', 'HYDRATION_LOG',
        'BOUTIQUE_LOG', 'DEBT', 'BILL', 'TONTINE',
      ]),
      entityId: z.string(),
      operation: z.enum(['CREATE', 'UPDATE', 'DELETE']),
      payload: z.any(),
      clientCreatedAt: z.string().optional(),
    })),
  });

  const parsed = schema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT', details: parsed.error.issues });

  const results: any[] = [];

  for (const item of parsed.data.items) {
    try {
      // Traiter chaque item
      const result = await processSyncItem(req.userId!, item);
      results.push({ entityId: item.entityId, success: true, result });
    } catch (e: any) {
      results.push({ entityId: item.entityId, success: false, error: e.message });
    }
  }

  res.json({ results, processed: results.length });
});

// Récupère les dernières modifications serveur (pull)
router.get('/pull', async (req: AuthedRequest, res: Response) => {
  const since = req.query.since ? new Date(req.query.since as string) : new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
  const userId = req.userId!;

  // Pour chaque type d'entité, on récupère les modifications depuis `since`
  const [transactions, accounts, savingsGoals, habits, habitLogs, lifeGoals, sleepLogs, moodLogs, workoutLogs, hydrationLogs, boutiqueLogs, debts, bills, tontines] = await Promise.all([
    prisma.transaction.findMany({ where: { userId, updatedAt: { gte: since } }, orderBy: { updatedAt: 'desc' }, take: 500 }),
    prisma.account.findMany({ where: { userId, updatedAt: { gte: since } } }),
    prisma.savingsGoal.findMany({ where: { userId, updatedAt: { gte: since } } }),
    prisma.habit.findMany({ where: { userId, updatedAt: { gte: since } } }),
    prisma.habitLog.findMany({ where: { userId, createdAt: { gte: since } }, orderBy: { createdAt: 'desc' }, take: 500 }),
    prisma.lifeGoal.findMany({ where: { userId, updatedAt: { gte: since } } }),
    prisma.sleepLog.findMany({ where: { userId, createdAt: { gte: since } }, orderBy: { createdAt: 'desc' }, take: 200 }),
    prisma.moodLog.findMany({ where: { userId, createdAt: { gte: since } }, orderBy: { createdAt: 'desc' }, take: 200 }),
    prisma.workoutLog.findMany({ where: { userId, createdAt: { gte: since } }, orderBy: { createdAt: 'desc' }, take: 200 }),
    prisma.hydrationLog.findMany({ where: { userId, createdAt: { gte: since } }, orderBy: { createdAt: 'desc' }, take: 200 }),
    prisma.dailyBoutiqueLog.findMany({ where: { userId, updatedAt: { gte: since } } }),
    prisma.debt.findMany({ where: { userId, updatedAt: { gte: since } } }),
    prisma.bill.findMany({ where: { userId, updatedAt: { gte: since } } }),
    prisma.tontine.findMany({ where: { userId, updatedAt: { gte: since } } }),
  ]);

  res.json({
    pulledAt: new Date().toISOString(),
    since: since.toISOString(),
    entities: {
      transactions, accounts, savingsGoals, habits, habitLogs, lifeGoals,
      sleepLogs, moodLogs, workoutLogs, hydrationLogs, boutiqueLogs, debts, bills, tontines,
    },
  });
});

async function processSyncItem(userId: string, item: any) {
  const { entityType, entityId, operation, payload } = item;

  switch (entityType) {
    case 'TRANSACTION':
      if (operation === 'CREATE') {
        // Vérifier que l'account appartient à l'utilisateur
        const account = await prisma.account.findFirst({ where: { id: payload.accountId, userId } });
        if (!account) throw new Error('ACCOUNT_NOT_FOUND');
        const tx = await prisma.transaction.create({
          data: { ...payload, userId, id: entityId },
        });
        // MAJ solde
        const delta = tx.type === 'INCOME' ? tx.amount.toNumber() : tx.type === 'EXPENSE' ? -tx.amount.toNumber() : 0;
        if (delta !== 0) {
          await prisma.account.update({ where: { id: account.id }, data: { balance: { increment: delta } } });
        }
        return tx;
      } else if (operation === 'UPDATE') {
        return await prisma.transaction.updateMany({ where: { id: entityId, userId }, data: payload });
      } else if (operation === 'DELETE') {
        return await prisma.transaction.deleteMany({ where: { id: entityId, userId } });
      }
      break;

    case 'HABIT_LOG':
      if (operation === 'CREATE' || operation === 'UPDATE') {
        return await prisma.habitLog.upsert({
          where: { habitId_date: { habitId: payload.habitId, date: new Date(payload.date) } },
          update: { value: payload.value, completed: payload.completed, note: payload.note },
          create: { ...payload, userId, date: new Date(payload.date) },
        });
      } else if (operation === 'DELETE') {
        return await prisma.habitLog.deleteMany({ where: { id: entityId, userId } });
      }
      break;

    case 'SLEEP_LOG':
      if (operation === 'CREATE' || operation === 'UPDATE') {
        return await prisma.sleepLog.upsert({
          where: { userId_date: { userId, date: new Date(payload.date) } },
          update: payload,
          create: { ...payload, userId },
        });
      }
      break;

    case 'MOOD_LOG':
      if (operation === 'CREATE' || operation === 'UPDATE') {
        return await prisma.moodLog.upsert({
          where: { userId_date: { userId, date: new Date(payload.date) } },
          update: payload,
          create: { ...payload, userId },
        });
      }
      break;

    case 'HYDRATION_LOG':
      if (operation === 'CREATE' || operation === 'UPDATE') {
        return await prisma.hydrationLog.upsert({
          where: { userId_date: { userId, date: new Date(payload.date) } },
          update: payload,
          create: { ...payload, userId },
        });
      }
      break;

    case 'BOUTIQUE_LOG':
      if (operation === 'CREATE' || operation === 'UPDATE') {
        return await prisma.dailyBoutiqueLog.upsert({
          where: { userId_date: { userId, date: new Date(payload.date) } },
          update: payload,
          create: { ...payload, userId },
        });
      }
      break;

    // Pour les autres types, on fait un simple upsert ou create/update/delete générique
    case 'ACCOUNT':
      if (operation === 'CREATE') return await prisma.account.create({ data: { ...payload, userId, id: entityId } });
      if (operation === 'UPDATE') return await prisma.account.updateMany({ where: { id: entityId, userId }, data: payload });
      if (operation === 'DELETE') return await prisma.account.deleteMany({ where: { id: entityId, userId } });
      break;

    case 'HABIT':
      if (operation === 'CREATE') return await prisma.habit.create({ data: { ...payload, userId, id: entityId } });
      if (operation === 'UPDATE') return await prisma.habit.updateMany({ where: { id: entityId, userId }, data: payload });
      if (operation === 'DELETE') return await prisma.habit.deleteMany({ where: { id: entityId, userId } });
      break;

    case 'LIFE_GOAL':
      if (operation === 'CREATE') return await prisma.lifeGoal.create({ data: { ...payload, userId, id: entityId } });
      if (operation === 'UPDATE') return await prisma.lifeGoal.updateMany({ where: { id: entityId, userId }, data: payload });
      if (operation === 'DELETE') return await prisma.lifeGoal.deleteMany({ where: { id: entityId, userId } });
      break;

    case 'WORKOUT_LOG':
      if (operation === 'CREATE') return await prisma.workoutLog.create({ data: { ...payload, userId, id: entityId } });
      if (operation === 'DELETE') return await prisma.workoutLog.deleteMany({ where: { id: entityId, userId } });
      break;

    case 'SAVINGS_GOAL':
      if (operation === 'CREATE') return await prisma.savingsGoal.create({ data: { ...payload, userId, id: entityId } });
      if (operation === 'UPDATE') return await prisma.savingsGoal.updateMany({ where: { id: entityId, userId }, data: payload });
      if (operation === 'DELETE') return await prisma.savingsGoal.updateMany({ where: { id: entityId, userId }, data: { archived: true } });
      break;

    case 'DEBT':
      if (operation === 'CREATE') return await prisma.debt.create({ data: { ...payload, userId, id: entityId } });
      if (operation === 'UPDATE') return await prisma.debt.updateMany({ where: { id: entityId, userId }, data: payload });
      if (operation === 'DELETE') return await prisma.debt.updateMany({ where: { id: entityId, userId }, data: { settled: true, settledAt: new Date() } });
      break;

    case 'BILL':
      if (operation === 'CREATE') return await prisma.bill.create({ data: { ...payload, userId, id: entityId } });
      if (operation === 'UPDATE') return await prisma.bill.updateMany({ where: { id: entityId, userId }, data: payload });
      if (operation === 'DELETE') return await prisma.bill.deleteMany({ where: { id: entityId, userId } });
      break;

    case 'TONTINE':
      if (operation === 'CREATE') return await prisma.tontine.create({ data: { ...payload, userId, id: entityId } });
      if (operation === 'UPDATE') return await prisma.tontine.updateMany({ where: { id: entityId, userId }, data: payload });
      if (operation === 'DELETE') return await prisma.tontine.deleteMany({ where: { id: entityId, userId } });
      break;
  }

  throw new Error(`Unsupported operation: ${entityType}.${operation}`);
}

export default router;
