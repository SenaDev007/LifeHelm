// V2 — Subscriptions & Payments (FedaPay)
import { Router, type Response } from 'express';
import { z } from 'zod';
import { prisma } from '../db.js';
import { authRequired, type AuthedRequest } from '../middleware/auth.js';
import { config } from '../config.js';
import { initiateFedaPayPayment, verifyFedaPayPayment } from '../services/fedapay.js';

const router = Router();
router.use(authRequired);

// Pricing (FCFA)
const PRICING = {
  FREE: { monthly: 0, annual: 0 },
  PRO: { monthly: 4900, annual: 49000 }, // 2 mois offerts
  FAMILY: { monthly: 9900, annual: 99000 },
};

// =====================================================================
// GET PLANS
// =====================================================================

router.get('/plans', (_req, res) => {
  res.json({ plans: PRICING });
});

// =====================================================================
// GET CURRENT SUBSCRIPTION
// =====================================================================

router.get('/current', async (req: AuthedRequest, res: Response) => {
  let sub = await prisma.subscription.findUnique({ where: { userId: req.userId }, include: { payments: true } });
  if (!sub) {
    // Créer une subscription FREE par défaut
    sub = await prisma.subscription.create({
      data: { userId: req.userId!, plan: 'FREE', status: 'ACTIVE', startedAt: new Date() },
      include: { payments: true },
    });
  }

  // Vérifier expiration
  if (sub.expiresAt && sub.expiresAt < new Date() && sub.plan !== 'FREE') {
    sub = await prisma.subscription.update({
      where: { id: sub.id },
      data: { plan: 'FREE', status: 'EXPIRED' },
      include: { payments: true },
    });
  }

  res.json({ subscription: sub });
});

// =====================================================================
// INITIATE PAYMENT (FedaPay)
// =====================================================================

const initiateSchema = z.object({
  plan: z.enum(['PRO', 'FAMILY']),
  period: z.enum(['MONTHLY', 'ANNUAL']),
  method: z.enum(['MTN', 'MOOV', 'WAVE', 'CARD']),
  phone: z.string().optional(),
  callbackUrl: z.string().optional(),
});

router.post('/initiate', async (req: AuthedRequest, res: Response) => {
  const parsed = initiateSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT', details: parsed.error.issues });

  const { plan, period, method, phone, callbackUrl } = parsed.data;
  const planPricing = PRICING[plan] as { monthly: number; annual: number };
  const amount = period === 'MONTHLY' ? planPricing.monthly : planPricing.annual;

  // Récupérer ou créer la subscription
  let sub = await prisma.subscription.findUnique({ where: { userId: req.userId } });
  if (!sub) {
    sub = await prisma.subscription.create({
      data: { userId: req.userId!, plan: 'FREE', status: 'ACTIVE', startedAt: new Date() },
    });
  }

  // Créer le payment en PENDING
  const payment = await prisma.payment.create({
    data: {
      userId: req.userId!,
      subscriptionId: sub.id,
      provider: 'FEDAPAY',
      amount,
      currency: 'XOF',
      status: 'PENDING',
      method,
      phone,
      metadata: { plan, period },
    },
  });

  // Initier FedaPay
  try {
    const fedaResult = await initiateFedaPayPayment({
      amount,
      currency: 'XOF',
      description: `LifeHelm ${plan} — ${period === 'MONTHLY' ? '1 mois' : '1 an (2 mois offerts)'}`,
      callbackUrl: callbackUrl || `${config.corsOrigin}/payments/callback`,
      paymentMethod: method,
      phone,
      reference: payment.id,
    });

    await prisma.payment.update({
      where: { id: payment.id },
      data: { providerRef: fedaResult.id },
    });

    res.status(201).json({
      paymentId: payment.id,
      fedaPayId: fedaResult.id,
      checkoutUrl: fedaResult.checkoutUrl,
      reference: fedaResult.reference,
    });
  } catch (e: any) {
    await prisma.payment.update({
      where: { id: payment.id },
      data: { status: 'FAILED', metadata: { ...(payment.metadata as any), error: e.message } },
    });
    res.status(500).json({ error: 'PAYMENT_INIT_FAILED', message: e.message });
  }
});

// =====================================================================
// VERIFY PAYMENT (callback after payment)
// =====================================================================

router.post('/verify/:paymentId', async (req: AuthedRequest, res: Response) => {
  const payment = await prisma.payment.findFirst({
    where: { id: req.params.paymentId, userId: req.userId },
    include: { subscription: true },
  });
  if (!payment) return res.status(404).json({ error: 'NOT_FOUND' });

  if (payment.status === 'SUCCESS') {
    return res.json({ payment, alreadyPaid: true });
  }

  if (!payment.providerRef) {
    return res.status(400).json({ error: 'NO_PROVIDER_REF' });
  }

  try {
    const fedaStatus = await verifyFedaPayPayment(payment.providerRef);
    if (fedaStatus.status === 'approved') {
      const now = new Date();
      const meta = payment.metadata as any;
      const period = meta?.period || 'MONTHLY';
      const expiresAt = new Date(now);
      if (period === 'MONTHLY') expiresAt.setMonth(expiresAt.getMonth() + 1);
      else expiresAt.setFullYear(expiresAt.getFullYear() + 1);

      const updated = await prisma.$transaction([
        prisma.payment.update({
          where: { id: payment.id },
          data: { status: 'SUCCESS', completedAt: now },
        }),
        prisma.subscription.update({
          where: { id: payment.subscriptionId! },
          data: {
            plan: meta?.plan || 'PRO',
            status: 'ACTIVE',
            startedAt: now,
            expiresAt,
            paymentMethod: payment.method || undefined,
          },
        }),
        prisma.user.update({
          where: { id: req.userId },
          data: { plan: meta?.plan || 'PRO' },
        }),
      ]);

      return res.json({ payment: updated[0], subscription: updated[1], activated: true });
    } else {
      await prisma.payment.update({
        where: { id: payment.id },
        data: { status: 'FAILED', metadata: { ...(payment.metadata as any), fedaStatus } },
      });
      return res.json({ payment, activated: false, fedaStatus });
    }
  } catch (e: any) {
    return res.status(500).json({ error: 'VERIFY_FAILED', message: e.message });
  }
});

// =====================================================================
// WEBHOOK FEDAPAY (callback serveur)
// =====================================================================

router.post('/webhook/fedapay', async (req, res) => {
  const event = req.body;
  console.log('[FedaPay Webhook]', JSON.stringify(event).substring(0, 500));

  try {
    if (event?.name === 'transaction.approved' || event?.data?.status === 'approved') {
      const txId = event?.data?.id || event?.data?.reference;
      const payment = await prisma.payment.findFirst({
        where: { providerRef: String(txId) },
        include: { subscription: true },
      });
      if (payment && payment.status !== 'SUCCESS') {
        const now = new Date();
        const meta = payment.metadata as any;
        const period = meta?.period || 'MONTHLY';
        const expiresAt = new Date(now);
        if (period === 'MONTHLY') expiresAt.setMonth(expiresAt.getMonth() + 1);
        else expiresAt.setFullYear(expiresAt.getFullYear() + 1);

        await prisma.$transaction([
          prisma.payment.update({
            where: { id: payment.id },
            data: { status: 'SUCCESS', completedAt: now },
          }),
          prisma.subscription.update({
            where: { id: payment.subscriptionId! },
            data: {
              plan: meta?.plan || 'PRO',
              status: 'ACTIVE',
              startedAt: now,
              expiresAt,
            },
          }),
          prisma.user.update({
            where: { id: payment.userId },
            data: { plan: meta?.plan || 'PRO' },
          }),
        ]);
      }
    }
    res.json({ received: true });
  } catch (e: any) {
    console.error('[Webhook error]', e.message);
    res.status(500).json({ error: 'WEBHOOK_FAILED' });
  }
});

// =====================================================================
// CANCEL SUBSCRIPTION
// =====================================================================

router.post('/cancel', async (req: AuthedRequest, res: Response) => {
  const sub = await prisma.subscription.findUnique({ where: { userId: req.userId } });
  if (!sub) return res.status(404).json({ error: 'NO_SUBSCRIPTION' });

  const updated = await prisma.subscription.update({
    where: { id: sub.id },
    data: { autoRenew: false },
  });

  res.json({ subscription: updated });
});

// =====================================================================
// HISTORY
// =====================================================================

router.get('/payments', async (req: AuthedRequest, res: Response) => {
  const payments = await prisma.payment.findMany({
    where: { userId: req.userId },
    orderBy: { createdAt: 'desc' },
    take: 20,
  });
  res.json({ payments });
});

export default router;
