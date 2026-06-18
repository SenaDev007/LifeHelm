// V2 — Export PDF : génère un rapport mensuel/annuel en HTML/PDF
import { Router, type Response } from 'express';
import { prisma } from '../db.js';
import { authRequired, type AuthedRequest } from '../middleware/auth.js';

const router = Router();
router.use(authRequired);

// Génère un rapport HTML (le client peut l'imprimer en PDF via le navigateur)
router.get('/monthly/:year/:month', async (req: AuthedRequest, res: Response) => {
  const year = parseInt(req.params.year, 10);
  const month = parseInt(req.params.month, 10);
  if (!year || !month || month < 1 || month > 12) {
    return res.status(400).json({ error: 'INVALID_PERIOD' });
  }

  const userId = req.userId!;
  const start = new Date(year, month - 1, 1);
  const end = new Date(year, month, 1);

  const [user, accounts, transactions, sleepLogs, moodLogs, workouts, habits, goals, savingsGoals, debts, bills, tontines] = await Promise.all([
    prisma.user.findUnique({ where: { id: userId }, select: { firstName: true, lastName: true, email: true } }),
    prisma.account.findMany({ where: { userId, archived: false } }),
    prisma.transaction.findMany({ where: { userId, date: { gte: start, lt: end } }, orderBy: { date: 'desc' } }),
    prisma.sleepLog.findMany({ where: { userId, date: { gte: start, lt: end } } }),
    prisma.moodLog.findMany({ where: { userId, date: { gte: start, lt: end } } }),
    prisma.workoutLog.findMany({ where: { userId, date: { gte: start, lt: end } } }),
    prisma.habitLog.findMany({ where: { userId, date: { gte: start, lt: end } } }),
    prisma.lifeGoal.findMany({ where: { userId, status: 'ACTIVE' } }),
    prisma.savingsGoal.findMany({ where: { userId, archived: false } }),
    prisma.debt.findMany({ where: { userId, settled: false } }),
    prisma.bill.findMany({ where: { userId } }),
    prisma.tontine.findMany({ where: { userId } }),
  ]);

  // Calculs
  const income = transactions.filter(t => t.type === 'INCOME').reduce((s, t) => s + t.amount.toNumber(), 0);
  const expenses = transactions.filter(t => t.type === 'EXPENSE').reduce((s, t) => s + t.amount.toNumber(), 0);
  const savings = income - expenses;
  const savingsRate = income > 0 ? Math.round((savings / income) * 100) : 0;
  const totalBalance = accounts.reduce((s, a) => s + a.balance.toNumber(), 0);

  // Catégories
  const byCategory: Record<string, number> = {};
  transactions.filter(t => t.type === 'EXPENSE').forEach(t => {
    const cat = t.category || 'Autre';
    byCategory[cat] = (byCategory[cat] || 0) + t.amount.toNumber();
  });
  const topCategories = Object.entries(byCategory).sort((a, b) => b[1] - a[1]).slice(0, 10);

  // Santé
  const avgSleep = sleepLogs.length ? sleepLogs.reduce((s, l) => s + l.durationMin, 0) / sleepLogs.length / 60 : 0;
  const avgEnergy = moodLogs.length ? moodLogs.reduce((s, l) => s + l.energy, 0) / moodLogs.length : 0;

  // Score global
  let financeScore = 50;
  if (savingsRate >= 20) financeScore += 25;
  if (savingsRate >= 30) financeScore += 10;
  if (totalBalance > 0) financeScore += 10;
  if (debts.length === 0) financeScore += 5;
  financeScore = Math.max(0, Math.min(100, financeScore));

  const monthNames = ['Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin', 'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre'];

  const html = `<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<title>Rapport LifeHelm — ${monthNames[month - 1]} ${year}</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 800px; margin: 0 auto; padding: 40px; color: #1a1a1a; }
  h1 { color: #1E3A5F; font-size: 32px; margin-bottom: 8px; }
  h2 { color: #1E3A5F; border-bottom: 2px solid #E89B3C; padding-bottom: 8px; margin-top: 32px; }
  .header { text-align: center; padding: 24px; background: #F8F6F1; border-radius: 16px; margin-bottom: 32px; }
  .stats { display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; margin: 24px 0; }
  .stat { padding: 16px; border-radius: 12px; background: #F8F6F1; }
  .stat-label { font-size: 12px; color: #6B7280; }
  .stat-value { font-size: 24px; font-weight: 700; margin-top: 4px; }
  .positive { color: #10B981; }
  .negative { color: #EF4444; }
  .info { color: #3B82F6; }
  table { width: 100%; border-collapse: collapse; margin: 16px 0; }
  th, td { text-align: left; padding: 10px 12px; border-bottom: 1px solid #E5E7EB; }
  th { background: #F8F6F1; font-weight: 600; }
  .badge { display: inline-block; padding: 4px 12px; border-radius: 999px; font-size: 12px; font-weight: 600; }
  .score-ring { display: inline-block; width: 80px; height: 80px; line-height: 80px; border-radius: 50%; text-align: center; font-size: 28px; font-weight: 800; }
  ul { padding-left: 20px; }
  li { margin: 4px 0; }
  .footer { margin-top: 48px; padding-top: 16px; border-top: 1px solid #E5E7EB; font-size: 12px; color: #6B7280; text-align: center; }
  @media print { body { padding: 20px; } .no-print { display: none; } }
</style>
</head>
<body>

<div class="header">
  <h1>LifeHelm — Rapport Mensuel</h1>
  <p style="font-size: 18px; color: #6B7280; margin: 4px 0 0;">
    ${monthNames[month - 1]} ${year} · ${user?.firstName || ''} ${user?.lastName || ''}
  </p>
</div>

<button class="no-print" onclick="window.print()" style="background: #1E3A5F; color: white; padding: 12px 24px; border: none; border-radius: 8px; font-size: 14px; cursor: pointer;">📄 Imprimer / Sauver en PDF</button>

<h2>💰 Synthèse Financière</h2>
<div style="text-align: center; margin: 24px 0;">
  <div class="score-ring" style="background: ${financeScore >= 60 ? '#10B98120' : '#EF444420'}; color: ${financeScore >= 60 ? '#10B981' : '#EF4444'};">
    ${financeScore}
  </div>
  <p style="margin-top: 8px; color: #6B7280;">Score de santé financière</p>
</div>

<div class="stats">
  <div class="stat">
    <div class="stat-label">Revenus</div>
    <div class="stat-value positive">${income.toLocaleString('fr-FR')} F</div>
  </div>
  <div class="stat">
    <div class="stat-label">Dépenses</div>
    <div class="stat-value negative">${expenses.toLocaleString('fr-FR')} F</div>
  </div>
  <div class="stat">
    <div class="stat-label">Épargne (${savingsRate}%)</div>
    <div class="stat-value ${savings >= 0 ? 'positive' : 'negative'}">${savings.toLocaleString('fr-FR')} F</div>
  </div>
</div>

<div class="stat" style="margin: 16px 0;">
  <div class="stat-label">Solde total (tous comptes)</div>
  <div class="stat-value info">${totalBalance.toLocaleString('fr-FR')} FCFA</div>
</div>

<h2>📊 Top Dépenses par Catégorie</h2>
<table>
  <thead><tr><th>Catégorie</th><th>Montant</th><th>% du total</th></tr></thead>
  <tbody>
    ${topCategories.map(([cat, amt]) => `
      <tr>
        <td>${cat}</td>
        <td>${amt.toLocaleString('fr-FR')} F</td>
        <td>${expenses > 0 ? Math.round((amt / expenses) * 100) : 0}%</td>
      </tr>
    `).join('')}
  </tbody>
</table>

<h2>🛏️ Santé & Bien-être</h2>
<div class="stats">
  <div class="stat">
    <div class="stat-label">Sommeil moyen</div>
    <div class="stat-value info">${avgSleep.toFixed(1)}h</div>
  </div>
  <div class="stat">
    <div class="stat-label">Énergie moyenne</div>
    <div class="stat-value info">${avgEnergy.toFixed(1)}/10</div>
  </div>
  <div class="stat">
    <div class="stat-label">Séances sport</div>
    <div class="stat-value positive">${workouts.length}</div>
  </div>
</div>

<h2>🎯 Objectifs Actifs</h2>
<ul>
  ${goals.map(g => `
    <li><strong>${g.title}</strong> [${g.domain}] ${g.targetValue ? `— ${(g.currentValue?.toNumber() || 0).toLocaleString('fr-FR')} / ${g.targetValue.toNumber().toLocaleString('fr-FR')} ${g.unit || ''}` : ''}</li>
  `).join('') || '<li>Aucun objectif actif</li>'}
</ul>

<h2>🐷 Épargne</h2>
<ul>
  ${savingsGoals.map(g => `
    <li><strong>${g.name}</strong> — ${g.currentAmount.toNumber().toLocaleString('fr-FR')} / ${g.targetAmount.toNumber().toLocaleString('fr-FR')} F (${Math.round((g.currentAmount.toNumber() / g.targetAmount.toNumber()) * 100)}%)</li>
  `).join('') || "<li>Aucun objectif d'épargne</li>"}
</ul>

<h2>🤝 Tontines</h2>
<ul>
  ${tontines.map(t => `
    <li><strong>${t.name}</strong> — Mise: ${t.contributionAmount.toNumber().toLocaleString('fr-FR')} F · Pot total: ${(t.contributionAmount.toNumber() * t.totalMembers).toLocaleString('fr-FR')} F · Ton rang: ${t.myRank}/${t.totalMembers}</li>
  `).join('') || '<li>Aucune tontine</li>'}
</ul>

<h2>💳 Dettes en cours</h2>
<ul>
  ${debts.map(d => `
    <li>${d.direction === 'OWING' ? '🔴 Tu dois à' : '🟢 On te doit'} <strong>${d.personName}</strong> — ${d.amount.toNumber().toLocaleString('fr-FR')} F ${d.dueDate ? `(échéance: ${new Date(d.dueDate).toLocaleDateString('fr-FR')})` : ''}</li>
  `).join('') || '<li>Aucune dette en cours ✅</li>'}
</ul>

<div class="footer">
  Rapport généré par LifeHelm le ${new Date().toLocaleDateString('fr-FR')} à ${new Date().toLocaleTimeString('fr-FR')}<br>
  LifeHelm — Prends le gouvernail de ta vie
</div>

</body>
</html>`;

  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.send(html);
});

// Export CSV des transactions
router.get('/transactions/:year/:month', async (req: AuthedRequest, res: Response) => {
  const year = parseInt(req.params.year, 10);
  const month = parseInt(req.params.month, 10);
  const start = new Date(year, month - 1, 1);
  const end = new Date(year, month, 1);

  const transactions = await prisma.transaction.findMany({
    where: { userId: req.userId, date: { gte: start, lt: end } },
    orderBy: { date: 'desc' },
    include: { account: true },
  });

  const header = 'Date,Type,Compte,Categorie,Libelle,Montant,Note\n';
  const rows = transactions.map(t => {
    const date = new Date(t.date).toLocaleDateString('fr-FR');
    const type = t.type;
    const account = t.account?.name || '';
    const cat = t.category || '';
    const label = `"${(t.label || '').replace(/"/g, '""')}"`;
    const amount = t.amount.toNumber();
    const note = `"${(t.note || '').replace(/"/g, '""')}"`;
    return [date, type, account, cat, label, amount, note].join(',');
  }).join('\n');

  res.setHeader('Content-Type', 'text/csv; charset=utf-8');
  res.setHeader('Content-Disposition', `attachment; filename="lifehelm_transactions_${year}_${month}.csv"`);
  res.send(header + rows);
});

// Liste des exports jobs (pour suivi async)
router.get('/jobs', async (req: AuthedRequest, res: Response) => {
  const jobs = await prisma.exportJob.findMany({
    where: { userId: req.userId },
    orderBy: { createdAt: 'desc' },
    take: 20,
  });
  res.json({ jobs });
});

export default router;
