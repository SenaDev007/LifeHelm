// E2E HELM AI Phase 3 — briefing quotidien + alertes intelligentes + consentements granulaires.
// Exécution : node scripts/e2e_ai_phase3.js (backend local sur :3001, BDD Neon).
const crypto = require('crypto');
const { Client } = require('pg');

const BASE = 'http://localhost:3001/api/v1';
const NEON = 'postgresql://neondb_owner:npg_i4rolEXA9fpy@ep-small-mouse-al74os4c-pooler.c-3.eu-central-1.aws.neon.tech/LifeHelm?sslmode=require';

const randomUUID = () => crypto.randomUUID();
const now = () => new Date().toISOString();
const today = () => new Date().toISOString().slice(0, 10);
const plusDays = (n) => new Date(Date.now() + n * 86400000).toISOString().slice(0, 10);
const minusDays = (n) => new Date(Date.now() - n * 86400000).toISOString().slice(0, 10);
const monthStart = () => `${today().slice(0, 7)}-01`;
const monthEnd = () => {
  const d = new Date();
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 0)).getUTCDate()).padStart(2, '0')}`;
};

let passed = 0, failed = 0;
const ok = (name, cond, extra = '') => {
  if (cond) { passed++; console.log(`  ✓ ${name}`); }
  else { failed++; console.log(`  ✗ ${name} ${extra}`); }
};

async function api(method, path, body, token) {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  let json = null;
  try { json = await res.json(); } catch {}
  return { status: res.status, json };
}

(async () => {
  console.log('═══ E2E HELM AI Phase 3 ═══');

  // 0) Compte QA
  const email = `qa-p3-${Date.now()}@yehiortech.com`;
  await api('POST', '/auth/register', { email, password: 'MotDePasse1!', firstName: 'QA', lastName: 'Phase3' });
  const login = await api('POST', '/auth/login', { identifier: email, password: 'MotDePasse1!' });
  const token = login.json?.accessToken ?? login.json?.access_token;
  if (!token) { console.log('PAS DE TOKEN — ABANDON'); process.exit(1); }
  ok('register + login', !!token);

  const pg = new Client({ connectionString: NEON, ssl: { rejectUnauthorized: false } });
  await pg.connect();
  const userId = (await pg.query('SELECT id FROM "User" WHERE email=$1', [email])).rows[0].id;

  // 1) Statut — Phase 3
  const status = await api('GET', '/ai/status', null, token);
  ok('status phase=PHASE_3', status.json?.phase === 'PHASE_3');
  ok('status capabilities Phase 3', ['daily_briefing', 'smart_alerts', 'granular_consents'].every((c) => status.json?.capabilities?.includes(c)));
  ok('status sensitiveScopes=3', Array.isArray(status.json?.sensitiveScopes) && status.json.sensitiveScopes.length === 3);

  // 2) Consentements granulaires
  const consents0 = await api('GET', '/ai/consents', null, token);
  ok('consents catalogue 3 scopes', consents0.json?.scopes?.length === 3 && consents0.json.scopes.every((s) => s.granted === false));
  const badScope = await api('PUT', '/ai/consents/banane', { granted: true }, token);
  ok('consent scope inconnu refusé', badScope.status === 400 || badScope.status === 422);
  const g1 = await api('PUT', '/ai/consents/notes.content', { granted: true }, token);
  ok('consent notes.content accordé', g1.json?.granted === true && g1.json?.grantedAt);
  const g2 = await api('PUT', '/ai/consents/wellbeing.journal', { granted: true }, token);
  ok('consent wellbeing.journal accordé', g2.json?.granted === true);
  const consents1 = await api('GET', '/ai/consents', null, token);
  ok('consents persistés (2/3 accordés)', consents1.json.scopes.filter((s) => s.granted).length === 2);
  const auditC = await pg.query(
    `SELECT action FROM "AiAuditEvent" WHERE "userId"=$1 AND action IN ('CONSENT_GRANTED','CONSENT_REVOKED') ORDER BY "createdAt"`,
    [userId],
  );
  ok('audit CONSENT_GRANTED ×2', auditC.rows.filter((r) => r.action === 'CONSENT_GRANTED').length === 2);

  // 3) Préférences : scope sensible exige préférence + consentement
  await api('PATCH', '/ai/preferences', { contextScope: { notes: true, wellbeing: true, messaging: true }, dailyBriefing: true, briefingHour: 7 }, token);
  const prefs = await api('GET', '/ai/preferences', null, token);
  ok('prefs dailyBriefing=true', prefs.json?.dailyBriefing === true && prefs.json?.briefingHour === 7);
  ok('prefs scope notes=true (consentement requis pour effet)', prefs.json?.contextScope?.notes === true);

  // 4) Briefing désactivé → enabled:false
  const email2 = `qa-p3b-${Date.now()}@yehiortech.com`;
  await api('POST', '/auth/register', { email: email2, password: 'MotDePasse1!', firstName: 'QA', lastName: 'P3b' });
  const login2 = await api('POST', '/auth/login', { identifier: email2, password: 'MotDePasse1!' });
  const token2 = login2.json?.accessToken ?? login2.json?.access_token;
  const bOff = await api('GET', '/ai/briefing', null, token2);
  ok('briefing désactivé par défaut (enabled:false)', bOff.json?.enabled === false && typeof bOff.json?.briefingHour === 'number');

  // 5) Données métier riches via sync push
  const spaceId = randomUUID(), accountId = randomUUID();
  const budgetId = randomUUID(), budgetOverId = randomUUID();
  const catCoursesId = randomUUID(), catTransportId = randomUUID();
  const dueId = randomUUID(), dueOverId = randomUUID(), loanId = randomUUID(), taskOverId = randomUUID(), eventTodayId = randomUUID(), wbId = randomUUID();
  const ops = (resourceId, resourceType, data) => ({ opId: randomUUID(), resourceId, resourceType, op: 'CREATE', data, occurredAt: now() });
  const push = await api('POST', '/sync/operations', { deviceId: 'qa-e2e-p3', operations: [
    ops(spaceId, 'Space', { id: spaceId, type: 'PERSONAL', name: 'Personnel', colorHex: '#FFB400', isDefault: true, createdAt: now() }),
    ops(accountId, 'FinancialAccount', { id: accountId, spaceId, name: 'Espèces', type: 'CASH', currency: 'XOF', initialAmount: 100000, initialDate: today(), note: null, archivedAt: null, createdAt: now() }),
    // Catégories distinctes pour que chaque budget ne compte que ses dépenses
    ops(catCoursesId, 'FinancialCategory', { id: catCoursesId, spaceId, name: 'Courses', kind: 'EXPENSE', parentId: null, createdAt: now(), updatedAt: now() }),
    ops(catTransportId, 'FinancialCategory', { id: catTransportId, spaceId, name: 'Transport', kind: 'EXPENSE', parentId: null, createdAt: now(), updatedAt: now() }),
    // Budget Courses à 83% (10 000 / 12 000) → BUDGET_THRESHOLD NORMAL
    ops(budgetId, 'Budget', { id: budgetId, spaceId, name: 'Budget courses', categoryId: catCoursesId, periodStart: monthStart(), periodEnd: monthEnd(), initialAmount: 12000, note: null, status: 'ACTIVE', createdAt: now(), updatedAt: now() }),
    ops(randomUUID(), 'FinancialTransaction', { id: randomUUID(), spaceId, accountId, categoryId: catCoursesId, kind: 'EXPENSE', amount: 10000, currency: 'XOF', label: 'Marché', note: null, occurredAt: today(), status: 'CONFIRMED', createdAt: now(), updatedAt: now() }),
    // Budget Transport dépassé (15 000 / 10 000 = 150%) → BUDGET_THRESHOLD IMPORTANT
    ops(budgetOverId, 'Budget', { id: budgetOverId, spaceId, name: 'Budget transport', categoryId: catTransportId, periodStart: monthStart(), periodEnd: monthEnd(), initialAmount: 10000, note: null, status: 'ACTIVE', createdAt: now(), updatedAt: now() }),
    ops(randomUUID(), 'FinancialTransaction', { id: randomUUID(), spaceId, accountId, categoryId: catTransportId, kind: 'EXPENSE', amount: 15000, currency: 'XOF', label: 'Taxis', note: null, occurredAt: today(), status: 'CONFIRMED', createdAt: now(), updatedAt: now() }),
    // Échéance dans 3 jours → DUE_ITEM_UPCOMING
    ops(dueId, 'FinancialDueItem', { id: dueId, spaceId, label: 'Loyer', expectedAmount: 45000, currency: 'XOF', dueDate: plusDays(3), status: 'OPEN', note: null, createdAt: now(), updatedAt: now() }),
    // Échéance en retard de 2 jours → DUE_ITEM_OVERDUE (IMPORTANT)
    ops(dueOverId, 'FinancialDueItem', { id: dueOverId, spaceId, label: 'Facture internet', expectedAmount: 12000, currency: 'XOF', dueDate: minusDays(2), status: 'OPEN', note: null, createdAt: now(), updatedAt: now() }),
    // Tâche URGENT en retard → TASK_OVERDUE IMPORTANT
    ops(taskOverId, 'Task', { id: taskOverId, spaceId, title: 'Appeler le banquier', description: null, status: 'TODO', priority: 'URGENT', dueDate: minusDays(1), projectId: null, createdAt: now(), updatedAt: now() }),
    // Prêt LENT attendu dans 5 jours → LOAN_DUE NORMAL
    ops(loanId, 'Loan', { id: loanId, spaceId, direction: 'LENT', counterparty: 'Marc', principalAmount: 25000, currency: 'XOF', interestRate: null, startedAt: minusDays(30), expectedAt: plusDays(5), status: 'ACTIVE', note: null, createdAt: now() }),
    // Événement aujourd'hui → briefing agenda
    ops(eventTodayId, 'CalendarEvent', { id: eventTodayId, spaceId, calendarId: spaceId, title: 'Point équipe', description: null, location: null, allDay: false, startDate: today(), startTime: '10:00', endDate: today(), endTime: '11:00', status: 'SCHEDULED', originalStart: null, recurrenceRuleId: null, createdAt: now(), updatedAt: now() }),
    // Entrée bien-être (consentement accordé à l'étape 2) → section sensible du briefing
    ops(wbId, 'WellbeingEntry', { id: wbId, spaceId, dateKey: today(), mood: 4, energy: 3, stress: 2, note: null, tagsJson: null, createdAt: now() }),
  ] }, token);
  ok('sync push 14 ressources APPLIED', push.json?.results?.filter((r) => r.status === 'APPLIED').length === 14, JSON.stringify(push.json?.results?.filter((r) => r.status !== 'APPLIED')).slice(0, 200));

  // 6) Briefing — génération à la demande (mode honnête déterministe sans clé)
  const b1 = await api('GET', '/ai/briefing', null, token);
  ok('briefing enabled=true généré', b1.json?.enabled === true && b1.json?.briefing?.id, JSON.stringify(b1.json).slice(0, 160));
  const br = b1.json?.briefing ?? {};
  ok('briefing headline + message', typeof br.headline === 'string' && br.headline.length > 3 && br.message.length > 10);
  ok('briefing date=aujourd\'hui', br.date === today());
  ok('briefing degraded=true (sans clé modèle)', br.degraded === true && br.modelKey === null);
  const sections = br.sections ?? {};
  ok('briefing agenda aujourd\'hui = 1 événement', sections.agenda?.today?.length === 1 && sections.agenda.today[0].title === 'Point équipe');
  ok('briefing tâches en retard = 1', sections.tasks?.overdueCount === 1);
  ok('briefing finance présente (income/expense)', typeof sections.finance?.expense === 'number' && sections.finance.expense === 25000);
  ok('briefing budgets = 2', Array.isArray(sections.budgets) && sections.budgets.length === 2);
  ok('briefing prêt actif = 1', Array.isArray(sections.loans) && sections.loans.length === 1);
  ok('briefing bien-être (consenti) = humeur 4', sections.wellbeing?.entriesCount === 1 && sections.wellbeing?.moodAverage === 4);
  ok('briefing généréNow=true', b1.json?.generatedNow === true);

  // 7) Alertes intelligentes — règles + déduplication
  const alertsR = b1.json?.alerts ?? [];
  const kinds = alertsR.map((a) => a.kind);
  ok('alertes générées (≥5)', alertsR.length >= 5, JSON.stringify(kinds));
  ok('alerte BUDGET_THRESHOLD 83% (NORMAL)', kinds.includes('BUDGET_THRESHOLD') && alertsR.some((a) => a.severity === 'NORMAL' && a.title.includes('courses')));
  ok('alerte BUDGET dépassé (IMPORTANT)', alertsR.some((a) => a.severity === 'IMPORTANT' && a.title.toLowerCase().includes('transport')));
  ok('alerte DUE_ITEM_UPCOMING (Loyer)', kinds.includes('DUE_ITEM_UPCOMING') && alertsR.some((a) => a.title.includes('Loyer')));
  ok('alerte DUE_ITEM_OVERDUE (IMPORTANT)', kinds.includes('DUE_ITEM_OVERDUE') && alertsR.some((a) => a.severity === 'IMPORTANT' && a.title.includes('internet')));
  ok('alerte TASK_OVERDUE URGENT (IMPORTANT)', kinds.includes('TASK_OVERDUE') && alertsR.some((a) => a.severity === 'IMPORTANT' && a.title.includes('banquier')));
  ok('alerte LOAN_DUE (Marc)', kinds.includes('LOAN_DUE') && alertsR.some((a) => a.title.includes('Marc')));

  // Cache briefing : 2e appel = même briefing, pas de nouvelle génération
  const b2 = await api('GET', '/ai/briefing', null, token);
  ok('briefing en cache (generatedNow=false, même id)', b2.json?.generatedNow === false && b2.json?.briefing?.id === br.id);

  // Déduplication : suppression du briefing du jour → régénération → pas de doublons d'alertes
  await pg.query('DELETE FROM "AiBriefing" WHERE "userId"=$1 AND date=$2', [userId, today()]);
  const b3 = await api('GET', '/ai/briefing', null, token);
  const alerts3 = b3.json?.alerts ?? [];
  const dedupKeys = alerts3.map((a) => a.dedupKey);
  ok('déduplication : aucune alerte dupliquée', new Set(dedupKeys).size === dedupKeys.length);
  const dbAlerts = await pg.query('SELECT COUNT(*)::int AS n, COUNT(DISTINCT "dedupKey")::int AS d FROM "AiAlert" WHERE "userId"=$1', [userId]);
  ok('BDD : alertes = distinct dedupKey', dbAlerts.rows[0].n === dbAlerts.rows[0].d, JSON.stringify(dbAlerts.rows[0]));

  // 8) Cycle de vie alerte : lue (idempotent) puis ignorée
  const target = alerts3.find((a) => a.status === 'UNREAD');
  const read1 = await api('POST', `/ai/alerts/${target.id}/read`, null, token);
  ok('alerte lue', read1.json?.status === 'READ' && read1.json?.readAt);
  const read2 = await api('POST', `/ai/alerts/${target.id}/read`, null, token);
  ok('relecture idempotente', read2.status === 200 && read2.json?.status === 'READ');
  const dismiss = await api('POST', `/ai/alerts/${target.id}/dismiss`, null, token);
  ok('alerte ignorée (DISMISSED)', dismiss.json?.status === 'DISMISSED' && dismiss.json?.dismissedAt);
  // Une alerte ignorée n'est PAS recréée à la régénération
  await pg.query('DELETE FROM "AiBriefing" WHERE "userId"=$1 AND date=$2', [userId, today()]);
  const b4 = await api('GET', '/ai/briefing', null, token);
  const resurface = (b4.json?.alerts ?? []).find((a) => a.id === target.id || a.dedupKey === target.dedupKey);
  ok('alerte ignorée non recréée', resurface?.status === 'DISMISSED');

  // 9) Filtre par seuil : IMPORTANT uniquement
  const normalBefore = (await pg.query(`SELECT COUNT(*)::int AS n FROM "AiAlert" WHERE "userId"=$1 AND severity='NORMAL'`, [userId])).rows[0].n;
  await api('PATCH', '/ai/preferences', { alertThreshold: 'IMPORTANT' }, token);
  await pg.query('DELETE FROM "AiBriefing" WHERE "userId"=$1 AND date=$2', [userId, today()]);
  const b5 = await api('GET', '/ai/briefing', null, token);
  ok('briefing régénéré après changement de seuil', b5.json?.generatedNow === true);
  const normalAfter = (await pg.query(`SELECT COUNT(*)::int AS n FROM "AiAlert" WHERE "userId"=$1 AND severity='NORMAL'`, [userId])).rows[0].n;
  ok('seuil IMPORTANT : aucune nouvelle alerte NORMAL créée', normalAfter === normalBefore, `${normalBefore} → ${normalAfter}`);
  const newImportant = (await pg.query(`SELECT COUNT(*)::int AS n FROM "AiAlert" WHERE "userId"=$1 AND severity='IMPORTANT' AND "dismissedAt" IS NULL`, [userId])).rows[0].n;
  ok('seuil IMPORTANT : alertes importantes présentes', newImportant > 0);
  await api('PATCH', '/ai/preferences', { alertThreshold: 'NORMAL' }, token);

  // 10) Retrait de consentement — effectif immédiatement (audit)
  const r1 = await api('PUT', '/ai/consents/notes.content', { granted: false }, token);
  ok('consentement retiré', r1.json?.granted === false && r1.json?.revokedAt);
  const auditR = await pg.query(`SELECT COUNT(*)::int AS n FROM "AiAuditEvent" WHERE "userId"=$1 AND action='CONSENT_REVOKED'`, [userId]);
  ok('audit CONSENT_REVOKED', auditR.rows[0].n >= 1);

  // 11) Isolation inter-comptes
  const alien = await api('POST', `/ai/alerts/${target.id}/read`, null, token2);
  ok('alerte d\'autrui → 404', alien.status === 404);
  const alienB = await api('GET', '/ai/briefing', null, token2);
  ok('briefing d\'autrui : enabled:false (opt-in propre)', alienB.json?.enabled === false);
  const consentsB = await api('GET', '/ai/consents', null, token2);
  ok('consentements d\'autrui vierges', consentsB.json?.scopes?.every((s) => !s.granted));

  // 12) Briefing hier/avant-hier autorisé, date lointaine refusée → aujourd'hui
  const bOld = await api('GET', `/ai/briefing?date=${minusDays(1)}`, null, token);
  ok('date hier acceptée', bOld.json?.enabled === true && bOld.json?.briefing?.date === minusDays(1));
  const bFar = await api('GET', `/ai/briefing?date=2024-01-01`, null, token);
  ok('date lointaine ramenée à aujourd\'hui', bFar.json?.enabled === true && bFar.json?.briefing?.date === today());

  // 13) Usage — briefing comptabilisé
  const usage = await api('GET', '/ai/usage', null, token);
  ok('usage total30d > 0', usage.json?.total30d > 0);

  console.log(`\n═══ RÉSULTAT : ${passed} ✓ / ${failed} ✗ ═══`);
  await pg.end();
  process.exit(failed > 0 ? 1 : 0);
})().catch((e) => { console.error('ERREUR E2E :', e); process.exit(1); });
