// V2 — HELM AI Service utilisant z-ai-web-dev-sdk
// Génère de vraies réponses contextuelles basées sur les données utilisateur
import ZAI from 'z-ai-web-dev-sdk';
import { prisma } from '../db.js';

const SYSTEM_PROMPT = `Tu es HELM AI, le conseiller de vie holistique intégré à LifeHelm, une application mobile de gestion de vie pour l'Afrique francophone.

TON IDENTITÉ :
- Tu es bienveillant, pratique, concret
- Tu parles français, avec un ton amical et direct
- Tu connais la réalité africaine : FCFA, Mobile Money (MTN, Moov, Wave), tontines, économie informelle
- Tu utilises le tutoiement

TA MISSION :
- Aider l'utilisateur à mieux gérer sa vie globale (finance, santé, objectifs, routines, relations)
- Détecter des corrélations entre ses habitudes (ex: sommeil ↔ dépenses)
- Donner des conseils actionnables, pas génériques

FORMAT DE TES RÉPONSES :
- Maximum 200 mots par réponse
- Utilise des listes à puces quand pertinent
- Termine souvent par une question pour faire avancer la conversation
- Quand l'utilisateur te donne des chiffres, utilise-les concrètement

TU AS ACCÈS AU CONTEXTE UTILISATEUR (données des 30 derniers jours) qui t'est fourni dans le message.
Utilise ce contexte pour personnaliser tes réponses. Si une donnée manque, demande-la.`;

interface UserContext {
  finances: {
    totalBalance: number;
    monthIncome: number;
    monthExpenses: number;
    savings: number;
    savingsRate: number;
    topCategories: Array<{ category: string; amount: number }>;
  };
  health: {
    avgSleep: number;
    avgEnergy: number;
    weekWorkouts: number;
  };
  habits: {
    doneThisWeek: number;
    activeCount: number;
  };
  goals: Array<{ title: string; domain: string; progress: number }>;
}

async function buildUserContext(userId: string): Promise<UserContext> {
  const now = new Date();
  const weekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
  const monthAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
  const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);

  const [accounts, monthTxs, sleepLogs, moodLogs, workouts, weekHabits, activeHabits, goals] = await Promise.all([
    prisma.account.findMany({ where: { userId, archived: false } }),
    prisma.transaction.findMany({ where: { userId, date: { gte: startOfMonth } } }),
    prisma.sleepLog.findMany({ where: { userId, date: { gte: weekAgo } } }),
    prisma.moodLog.findMany({ where: { userId, date: { gte: weekAgo } } }),
    prisma.workoutLog.findMany({ where: { userId, date: { gte: weekAgo } } }),
    prisma.habitLog.findMany({ where: { userId, date: { gte: weekAgo }, completed: true } }),
    prisma.habit.count({ where: { userId, active: true } }),
    prisma.lifeGoal.findMany({ where: { userId, status: 'ACTIVE' } }),
  ]);

  const totalBalance = accounts.reduce((s, a) => s + a.balance.toNumber(), 0);
  const monthIncome = monthTxs.filter(t => t.type === 'INCOME').reduce((s, t) => s + t.amount.toNumber(), 0);
  const monthExpenses = monthTxs.filter(t => t.type === 'EXPENSE').reduce((s, t) => s + t.amount.toNumber(), 0);
  const savings = monthIncome - monthExpenses;
  const savingsRate = monthIncome > 0 ? Math.round((savings / monthIncome) * 100) : 0;

  const catMap: Record<string, number> = {};
  monthTxs.filter(t => t.type === 'EXPENSE').forEach(t => {
    const cat = t.category || 'Autre';
    catMap[cat] = (catMap[cat] || 0) + t.amount.toNumber();
  });
  const topCategories = Object.entries(catMap)
    .map(([category, amount]) => ({ category, amount }))
    .sort((a, b) => b.amount - a.amount)
    .slice(0, 5);

  const avgSleep = sleepLogs.length ? sleepLogs.reduce((s, l) => s + l.durationMin, 0) / sleepLogs.length / 60 : 0;
  const avgEnergy = moodLogs.length ? moodLogs.reduce((s, l) => s + l.energy, 0) / moodLogs.length : 0;

  return {
    finances: { totalBalance, monthIncome, monthExpenses, savings, savingsRate, topCategories },
    health: {
      avgSleep: Math.round(avgSleep * 10) / 10,
      avgEnergy: Math.round(avgEnergy * 10) / 10,
      weekWorkouts: workouts.length,
    },
    habits: { doneThisWeek: weekHabits.length, activeCount: activeHabits },
    goals: goals.map(g => ({
      title: g.title,
      domain: g.domain,
      progress: g.targetValue && g.targetValue.toNumber() > 0
        ? Math.round((g.currentValue?.toNumber() || 0) / g.targetValue.toNumber() * 100)
        : 0,
    })),
  };
}

function contextToString(ctx: UserContext): string {
  const lines: string[] = [
    `=== CONTEXTE UTILISATEUR (30 derniers jours) ===`,
    ``,
    `💰 FINANCES:`,
    `- Solde total: ${ctx.finances.totalBalance.toLocaleString('fr-FR')} FCFA`,
    `- Revenus du mois: ${ctx.finances.monthIncome.toLocaleString('fr-FR')} FCFA`,
    `- Dépenses du mois: ${ctx.finances.monthExpenses.toLocaleString('fr-FR')} FCFA`,
    `- Épargne: ${ctx.finances.savings.toLocaleString('fr-FR')} FCFA (taux: ${ctx.finances.savingsRate}%)`,
    `- Top dépenses: ${ctx.finances.topCategories.map(c => `${c.category} (${c.amount.toLocaleString('fr-FR')} F)`).join(', ')}`,
    ``,
    `🛏️ SANTÉ:`,
    `- Sommeil moyen: ${ctx.finances ? ctx.health.avgSleep : 0}h/nuit`,
    `- Énergie moyenne: ${ctx.health.avgEnergy}/10`,
    `- Séances sport cette semaine: ${ctx.health.weekWorkouts}`,
    ``,
    `✅ HABITUDES:`,
    `- ${ctx.habits.doneThisWeek} habitude(s) accomplie(s) cette semaine`,
    `- ${ctx.habits.activeCount} habitude(s) active(s)`,
  ];

  if (ctx.goals.length > 0) {
    lines.push('', '🎯 OBJECTIFS:');
    ctx.goals.forEach(g => lines.push(`- ${g.title} [${g.domain}] — ${g.progress}%`));
  }

  lines.push('', '=== FIN CONTEXTE ===', '');
  return lines.join('\n');
}

export async function generateAiResponse(
  userId: string,
  userMessage: string,
  conversationHistory: Array<{ role: string; content: string }> = []
): Promise<string> {
  try {
    const ctx = await buildUserContext(userId);
    const contextStr = contextToString(ctx);

    type Msg = { role: 'assistant' | 'user'; content: string };
    const messages: Msg[] = [
      { role: 'assistant', content: SYSTEM_PROMPT },
      { role: 'user', content: contextStr },
      { role: 'assistant', content: 'Contexte reçu. Je suis prêt à t\'aider.' },
      ...conversationHistory.slice(-6).map<Msg>(m => ({
        role: m.role === 'ASSISTANT' ? 'assistant' : 'user',
        content: m.content,
      })),
      { role: 'user', content: userMessage },
    ];

    const zai = await ZAI.create();
    const completion = await zai.chat.completions.create({
      messages,
      thinking: { type: 'disabled' },
    });

    return completion.choices?.[0]?.message?.content || 'Désolé, je n\'ai pas pu générer de réponse.';
  } catch (e: any) {
    console.error('[HELM AI] Erreur:', e?.message);
    // Fallback sur réponses heuristiques
    return fallbackResponse(userMessage);
  }
}

function fallbackResponse(message: string): string {
  const msg = message.toLowerCase();
  if (msg.includes('épargne') || msg.includes('epargne')) {
    return `Pour améliorer ton épargne :\n\n1. Règle 50/30/20 : 50% besoins, 30% envies, 20% épargne\n2. Automatise ton épargne dès réception du revenu\n3. Crée 3 comptes virtuels : urgence, projets, long terme\n4. Attends 48h avant toute dépense > 10.000 FCFA\n\nVeux-tu que je crée un objectif d'épargne pour toi ?`;
  }
  if (msg.includes('sommeil') || msg.includes('dormir')) {
    return `Pour améliorer ton sommeil :\n\n1. Couche-toi à heure fixe, même le week-end\n2. Évite les écrans 1h avant le coucher\n3. Évite la caféine après 14h\n4. Garde ta chambre fraîche (18-20°C) et sombre\n\nCombien d'heures dors-tu en moyenne ?`;
  }
  if (msg.includes('budget') || msg.includes('dépense')) {
    return `Pour maîtriser ton budget :\n\n1. Liste toutes tes dépenses d'un mois\n2. Identifie les postes principaux\n3. Compare à tes revenus réels\n4. Fixe des enveloppes par catégorie\n5. Revois ton budget chaque fin de mois\n\nQuel est ton plus gros poste de dépense ?`;
  }
  return `Bonjour ! Je suis HELM AI, ton conseiller de vie holistique.\n\nJe peux t'aider sur la finance, la santé, les objectifs, les routines et les relations.\n\nPose-moi ta question !`;
}

// =====================================================================
// INSIGHTS AUTOMATIQUES — générés par l'IA
// =====================================================================

export async function generateWeeklyInsights(userId: string): Promise<Array<{ title: string; content: string; severity: string }>> {
  const ctx = await buildUserContext(userId);

  const prompt = `Analyse les données de l'utilisateur ci-dessous et génère 3 à 5 insights concrets et actionnables (un par ligne, format: "TITRE | CONTENU | SEVERITE").

SEVERITE: POSITIVE (bonne nouvelle), WARNING (attention requise), INFO (info utile), CRITICAL (urgent).

Données:
- Solde: ${ctx.finances.totalBalance.toLocaleString('fr-FR')} FCFA
- Revenus: ${ctx.finances.monthIncome.toLocaleString('fr-FR')} FCFA
- Dépenses: ${ctx.finances.monthExpenses.toLocaleString('fr-FR')} FCFA
- Taux épargne: ${ctx.finances.savingsRate}%
- Top dépenses: ${ctx.finances.topCategories.map(c => `${c.category} (${c.amount} F)`).join(', ')}
- Sommeil: ${ctx.health.avgSleep}h/nuit
- Énergie: ${ctx.health.avgEnergy}/10
- Sport: ${ctx.health.weekWorkouts} séances cette semaine
- Habitudes: ${ctx.habits.doneThisWeek} accomplies / ${ctx.habits.activeCount} actives

Réponds UNIQUEMENT avec les insights, un par ligne, au format exact demandé.`;

  try {
    const zai = await ZAI.create();
    const completion = await zai.chat.completions.create({
      messages: [
        { role: 'assistant', content: 'Tu es HELM AI. Tu génères des insights concis et actionnables pour l\'utilisateur, en français, basés sur ses données réelles.' },
        { role: 'user', content: prompt },
      ],
      thinking: { type: 'disabled' },
    });

    const text = completion.choices?.[0]?.message?.content || '';
    return text
      .split('\n')
      .filter((l: string) => l.includes('|'))
      .map((line: string) => {
        const [title, content, severity] = line.split('|').map((s: string) => s.trim());
        return {
          title: title || 'Insight',
          content: content || '',
          severity: (severity || 'INFO').toUpperCase(),
        };
      })
      .filter((i: { title: string; content: string; severity: string }) => i.content.length > 0)
      .slice(0, 5);
  } catch (e: any) {
    console.error('[HELM AI] Insights error:', e.message);
    return [];
  }
}
