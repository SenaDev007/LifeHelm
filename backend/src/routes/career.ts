import { Router, type Response } from 'express';
import { z } from 'zod';
import { prisma } from '../db.js';
import { authRequired, type AuthedRequest } from '../middleware/auth.js';

const router = Router();
router.use(authRequired);

const careerSchema = z.object({
  jobTitle: z.string().max(120).nullable().optional(),
  company: z.string().max(120).nullable().optional(),
  sector: z.string().max(120).nullable().optional(),
  employmentType: z.enum(['EMPLOYEE', 'FREELANCE', 'ENTREPRENEUR', 'STUDENT', 'OTHER']).nullable().optional(),
  skills: z.array(z.object({ name: z.string().min(1).max(80), level: z.number().int().min(1).max(5).default(1) })).max(50).optional(),
  annualRevenueGoal: z.number().nonnegative().nullable().optional(),
});

router.get('/', async (req: AuthedRequest, res: Response) => {
  const yearStart = new Date(new Date().getFullYear(), 0, 1);
  const [profile, income] = await Promise.all([
    prisma.careerProfile.findUnique({ where: { userId: req.userId } }),
    prisma.transaction.aggregate({ where: { userId: req.userId, type: 'INCOME', date: { gte: yearStart } }, _sum: { amount: true } }),
  ]);
  const earnedThisYear = income._sum.amount?.toNumber() ?? 0;
  const goal = profile?.annualRevenueGoal?.toNumber() ?? 0;
  res.json({ profile, earnedThisYear, annualRevenueGoal: goal, revenueProgress: goal > 0 ? Math.min(1, earnedThisYear / goal) : 0 });
});

router.patch('/', async (req: AuthedRequest, res: Response) => {
  const parsed = careerSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT', details: parsed.error.issues });
  const { annualRevenueGoal, ...rest } = parsed.data;
  const hasRevenueGoal = Object.prototype.hasOwnProperty.call(parsed.data, 'annualRevenueGoal');
  const profile = await prisma.careerProfile.upsert({
    where: { userId: req.userId! },
    update: { ...rest, ...(hasRevenueGoal ? { annualRevenueGoal } : {}) },
    create: { userId: req.userId!, ...rest, annualRevenueGoal: annualRevenueGoal ?? null },
  });
  res.json({ profile });
});

export default router;
