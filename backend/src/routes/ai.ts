import { Router, type Response } from 'express';
import { z } from 'zod';
import { prisma } from '../db.js';
import { authRequired, type AuthedRequest } from '../middleware/auth.js';
import { config } from '../config.js';
import { generateAiResponse, generateWeeklyInsights } from '../services/helm-ai.js';

const router = Router();
router.use(authRequired);

// =====================================================================
// INSIGHTS
// =====================================================================

router.get('/insights', async (req: AuthedRequest, res: Response) => {
  const refresh = req.query.refresh === 'true';
  const since = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);

  let insights = await prisma.aiInsight.findMany({
    where: { userId: req.userId, createdAt: { gte: since } },
    orderBy: { createdAt: 'desc' },
    take: 20,
  });

  if (refresh || insights.length === 0) {
    const generated = await generateWeeklyInsights(req.userId!);
    // Marquer les anciens comme lus
    await prisma.aiInsight.updateMany({ where: { userId: req.userId, read: false }, data: { read: true, readAt: new Date() } });
    // Créer les nouveaux
    const created = await Promise.all(
      generated.map(g => prisma.aiInsight.create({
        data: {
          userId: req.userId!,
          type: 'WEEKLY',
          severity: (g.severity as 'INFO' | 'WARNING' | 'POSITIVE' | 'CRITICAL') || 'INFO',
          title: g.title,
          content: g.content,
        },
      }))
    );
    insights = created;
  }

  res.json({ insights });
});

router.post('/insights/:id/read', async (req: AuthedRequest, res: Response) => {
  await prisma.aiInsight.updateMany({
    where: { id: req.params.id, userId: req.userId },
    data: { read: true, readAt: new Date() },
  });
  res.json({ ok: true });
});

// =====================================================================
// CHAT
// =====================================================================

router.get('/conversations', async (req: AuthedRequest, res: Response) => {
  const conversations = await prisma.aiConversation.findMany({
    where: { userId: req.userId },
    orderBy: { updatedAt: 'desc' },
    include: { messages: { orderBy: { createdAt: 'asc' }, take: 50 } },
  });
  res.json({ conversations });
});

router.post('/conversations', async (req: AuthedRequest, res: Response) => {
  const schema = z.object({ title: z.string().optional() });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
  const conv = await prisma.aiConversation.create({
    data: { userId: req.userId!, title: parsed.data.title || 'Nouvelle conversation' },
  });
  res.status(201).json({ conversation: conv });
});

router.post('/conversations/:id/messages', async (req: AuthedRequest, res: Response) => {
  const schema = z.object({ content: z.string().min(1).max(5000) });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });

  const conv = await prisma.aiConversation.findFirst({ where: { id: req.params.id, userId: req.userId } });
  if (!conv) return res.status(404).json({ error: 'NOT_FOUND' });

  // Save user message
  await prisma.aiMessage.create({
    data: { conversationId: conv.id, role: 'USER', content: parsed.data.content },
  });

  // Récupérer l'historique récent
  const history = await prisma.aiMessage.findMany({
    where: { conversationId: conv.id },
    orderBy: { createdAt: 'asc' },
    take: 12,
  });

  // V2 — Génère une vraie réponse via HELM AI (z-ai-web-dev-sdk)
  const response = await generateAiResponse(
    req.userId!,
    parsed.data.content,
    history.map(m => ({ role: m.role, content: m.content })),
  );

  const assistantMsg = await prisma.aiMessage.create({
    data: { conversationId: conv.id, role: 'ASSISTANT', content: response },
  });

  await prisma.aiConversation.update({ where: { id: conv.id }, data: { title: parsed.data.content.slice(0, 60) } });

  res.status(201).json({ message: assistantMsg });
});

router.delete('/conversations/:id', async (req: AuthedRequest, res: Response) => {
  await prisma.aiConversation.deleteMany({ where: { id: req.params.id, userId: req.userId } });
  res.json({ ok: true });
});

export default router;
