import { Router, type Response } from 'express';
import { z } from 'zod';
import { prisma } from '../db.js';
import { authRequired, type AuthedRequest } from '../middleware/auth.js';
import { config } from '../config.js';

const router = Router();
router.use(authRequired);

// Mock insights hebdomadaires — générés à partir des vraies données utilisateur
async function generateWeeklyInsights(userId: string) {
  const now = new Date();
  const weekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);

  const [transactions, sleepLogs, moodLogs, habits, workouts] = await Promise.all([
    prisma.transaction.findMany({ where: { userId, date: { gte: weekAgo } } }),
    prisma.sleepLog.findMany({ where: { userId, date: { gte: weekAgo } } }),
    prisma.moodLog.findMany({ where: { userId, date: { gte: weekAgo } } }),
    prisma.habitLog.findMany({ where: { userId, date: { gte: weekAgo }, completed: true } }),
    prisma.workoutLog.findMany({ where: { userId, date: { gte: weekAgo } } }),
  ]);

  const insights: { title: string; content: string; severity: 'INFO' | 'WARNING' | 'POSITIVE' | 'CRITICAL' }[] = [];

  // Insight finances
  const expenses = transactions.filter(t => t.type === 'EXPENSE').reduce((s, t) => s + t.amount.toNumber(), 0);
  const income = transactions.filter(t => t.type === 'INCOME').reduce((s, t) => s + t.amount.toNumber(), 0);
  const foodExpenses = transactions.filter(t => t.type === 'EXPENSE' && (t.category === 'Alimentation' || t.category === 'food')).reduce((s, t) => s + t.amount.toNumber(), 0);

  if (income > 0 && expenses > income) {
    insights.push({
      title: 'Dépenses supérieures aux revenus',
      content: `Cette semaine, tes dépenses (${expenses.toLocaleString('fr-FR')} FCFA) dépassent tes revenus (${income.toLocaleString('fr-FR')} FCFA). Pense à revoir ton budget.`,
      severity: 'WARNING',
    });
  } else if (income > 0 && expenses < income * 0.7) {
    insights.push({
      title: 'Belle gestion financière',
      content: `Tu as économisé ${Math.round((1 - expenses / income) * 100)}% de tes revenus cette semaine. Continue ainsi !`,
      severity: 'POSITIVE',
    });
  }

  // Insight sommeil
  if (sleepLogs.length > 0) {
    const avgSleep = sleepLogs.reduce((s, l) => s + l.durationMin, 0) / sleepLogs.length / 60;
    if (avgSleep < 6) {
      insights.push({
        title: 'Sommeil insuffisant',
        content: `Tu dors en moyenne ${avgSleep.toFixed(1)}h cette semaine (recommandé : 7h+). Cela peut impacter ton énergie et tes décisions financières.`,
        severity: 'WARNING',
      });
    } else if (avgSleep >= 7) {
      insights.push({
        title: 'Excellent sommeil',
        content: `Tu dors en moyenne ${avgSleep.toFixed(1)}h cette semaine, c'est idéal pour ta santé et ta productivité.`,
        severity: 'POSITIVE',
      });
    }
  }

  // Corrélation sommeil/dépenses alimentaires
  if (sleepLogs.length >= 3 && foodExpenses > 0) {
    const lowSleepDays = sleepLogs.filter(l => l.durationMin < 6 * 60).length;
    if (lowSleepDays >= 2) {
      insights.push({
        title: 'Corrélation détectée',
        content: `Tu as dépensé ${foodExpenses.toLocaleString('fr-FR')} FCFA en alimentation cette semaine et dormi moins de 6h pendant ${lowSleepDays} jours. Les recherches montrent que le manque de sommeil augmente les dépenses alimentaires de 20 à 30%.`,
        severity: 'INFO',
      });
    }
  }

  // Insight humeur
  if (moodLogs.length >= 3) {
    const avgEnergy = moodLogs.reduce((s, l) => s + l.energy, 0) / moodLogs.length;
    if (avgEnergy < 4) {
      insights.push({
        title: 'Énergie faible',
        content: `Ton énergie moyenne est de ${avgEnergy.toFixed(1)}/10 cette semaine. Pense à revoir ton sommeil, ton hydratation et ton alimentation.`,
        severity: 'WARNING',
      });
    }
  }

  // Insight activité physique
  if (workouts.length === 0) {
    insights.push({
      title: 'Aucune activité physique',
      content: `Tu n'as enregistré aucune séance cette semaine. Même 20 minutes de marche par jour peuvent faire une grande différence sur ton énergie et ta santé.`,
      severity: 'INFO',
    });
  } else if (workouts.length >= 3) {
    insights.push({
      title: 'Belle régularité sportive',
      content: `Tu as fait ${workouts.length} séances cette semaine. C'est excellent pour ta santé physique et mentale.`,
      severity: 'POSITIVE',
    });
  }

  // Insight habitudes
  if (habits.length === 0) {
    insights.push({
      title: 'Aucune habitude enregistrée',
      content: `Tu n'as coché aucune habitude cette semaine. Commence par en créer une petite et facile (ex: 1 verre d'eau au réveil).`,
      severity: 'INFO',
    });
  }

  if (insights.length === 0) {
    insights.push({
      title: 'Bienvenue dans LifeHelm',
      content: `Continue à enregistrer tes données cette semaine pour recevoir des insights personnalisés sur tes habitudes de vie.`,
      severity: 'INFO',
    });
  }

  return insights;
}

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
          severity: g.severity,
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

  // Generate response
  let response = '';
  const userMsg = parsed.data.content.toLowerCase();

  if (config.anthropic.apiKey) {
    // TODO: intégration Anthropic réelle
    response = '(Intégration Anthropic à configurer)';
  } else {
    // Mode mock — réponses heuristiques basées sur le contexte
    if (userMsg.includes('épargne') || userMsg.includes('epargne')) {
      response = `Pour améliorer ton épargne, je te recommande :\n\n1. Applique la règle 50/30/20 : 50% besoins, 30% envies, 20% épargne\n2. Automatise ton épargne dès réception du revenu (paye-toi en premier)\n3. Crée 3 comptes virtuels : urgence, projets, long terme\n4. Évite les achats impulsifs en attendant 48h avant toute dépense > 10.000 FCFA\n\nVeux-tu que je crée un objectif d'épargne pour toi ?`;
    } else if (userMsg.includes('sommeil') || userMsg.includes('dormir')) {
      response = `Pour améliorer ton sommeil :\n\n1. Couche-toi et lève-toi à heure fixe, même le week-end\n2. Évite les écrans 1h avant le coucher\n3. Évite la caféine après 14h\n4. Garde ta chambre fraîche (18-20°C) et sombre\n5. Crée un rituel du coucher apaisant\n\nCombien d'heures dors-tu en moyenne ?`;
    } else if (userMsg.includes('budget') || userMsg.includes('dépense')) {
      response = `Pour maîtriser ton budget :\n\n1. Listes toutes tes dépenses d'un mois (même les petites)\n2. Identifie les postes principaux : logement, alimentation, transport\n3. Compare à tes revenus réels\n4. Fixe des enveloppes par catégorie\n5. Revois ton budget chaque fin de mois\n\nQuel est ton plus gros poste de dépense ce mois-ci ?`;
    } else if (userMsg.includes('objectif') || userMsg.includes('goal')) {
      response = `Pour atteindre tes objectifs :\n\n1. Formule-les en SMART : Spécifique, Mesurable, Atteignable, Réaliste, Temporel\n2. Décompose en sous-tâches hebdomadaires\n3. Mesure ta progression chaque semaine\n4. Célèbre chaque jalon (25%, 50%, 75%, 100%)\n5. Ajuste si nécessaire — c'est normal, pas un échec\n\nQuel objectif veux-tu travailler ?`;
    } else if (userMsg.includes('stress') || userMsg.includes('anx')) {
      response = `Pour gérer ton stress :\n\n1. 5 min de respiration profonde le matin (cohérence cardiaque)\n2. Marche 15 min en plein air\n3. Note 3 choses positives chaque soir\n4. Limite les réseaux sociaux\n5. Parles-en à quelqu'un de confiance\n\nSi le stress persiste, n'hésite pas à consulter un professionnel de santé.`;
    } else if (userMsg.includes('tontine')) {
      response = `Les tontines sont un excellent outil d'épargne collective africain.\n\nPour bien les gérer :\n1. Choisis des membres de confiance\n2. Formalise les règles par écrit (montant, fréquence, ordre)\n3. Garde une trace de chaque contribution\n4. Connais ton rang pour anticiper ton tour\n5. Réinvestis intelligemment quand tu reçois la cagnotte\n\nDans LifeHelm, tu peux suivre tes tontines dans le module Finance.`;
    } else if (userMsg.includes('bonjour') || userMsg.includes('salut') || userMsg.includes('hello')) {
      response = `Bonjour ! Je suis HELM AI, ton conseiller de vie holistique.\n\nJe peux t'aider sur :\n- Finance (épargne, budget, dettes, tontines)\n- Santé (sommeil, humeur, activité physique)\n- Objectifs et productivité\n- Relations et bien-être\n\nPose-moi ta question !`;
    } else {
      response = `C'est une bonne question. Pour mieux t'aider, j'ai besoin de comprendre ton contexte.\n\nPeux-tu me dire :\n- Quel aspect de ta vie veux-tu améliorer ?\n- As-tu des données récentes dans LifeHelm sur ce sujet ?\n- Quel est ton objectif concret ?\n\nJe peux aussi te proposer des insights basés sur tes données des 7 derniers jours si tu le souhaites.`;
    }
  }

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
