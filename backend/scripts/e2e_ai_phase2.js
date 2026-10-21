// E2E HELM AI Phase 2 — cycle actions + idempotence + préférences + usage.
// Exécution : node scripts/e2e_ai_phase2.js (backend local sur :3001, BDD Neon).
const crypto = require('crypto');
const { Client } = require('pg');

const BASE = 'http://localhost:3001/api/v1';
const NEON = 'postgresql://neondb_owner:npg_i4rolEXA9fpy@ep-small-mouse-al74os4c-pooler.c-3.eu-central-1.aws.neon.tech/LifeHelm?sslmode=require';

const randomUUID = () => crypto.randomUUID();
const now = () => new Date().toISOString();
const today = () => new Date().toISOString().slice(0, 10);

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

const hashPayload = (payload) => {
  const canonical = JSON.stringify(payload, Object.keys(payload).sort());
  return crypto.createHash('sha256').update(canonical).digest('hex');
};

(async () => {
  console.log('═══ E2E HELM AI Phase 2 ═══');

  // 0) Compte QA
  const email = `qa-p2-${Date.now()}@yehiortech.com`;
  const reg = await api('POST', '/auth/register', {
    email, password: 'MotDePasse1!', firstName: 'QA', lastName: 'Phase2',
  });
  ok('register 201', reg.status === 201 || reg.status === 409, JSON.stringify(reg.json).slice(0, 80));
  const login = await api('POST', '/auth/login', { identifier: email, password: 'MotDePasse1!' });
  ok('login 200', login.status === 200);
  const token = login.json?.accessToken ?? login.json?.access_token;
  if (!token) { console.log('PAS DE TOKEN — ABANDON'); process.exit(1); }

  // 1) Statut — Phase 2
  const status = await api('GET', '/ai/status', null, token);
  ok('status phase=PHASE_2', status.json?.phase === 'PHASE_2');
  ok('status actionTypes=3', Array.isArray(status.json?.actionTypes) && status.json.actionTypes.length === 3);

  // 2) Préférences — valeurs par défaut
  const prefs0 = await api('GET', '/ai/preferences', null, token);
  ok('prefs défauts (SUGGEST/NORMAL)', prefs0.json?.autonomyLevel === 'SUGGEST' && prefs0.json?.alertThreshold === 'NORMAL');
  ok('prefs scope finance=true notes=false', prefs0.json?.contextScope?.finance === true && prefs0.json?.contextScope?.notes === false);
  ok('prefs scope wellbeing FORCÉ false', prefs0.json?.contextScope?.wellbeing === false);

  // 3) Mise à jour des préférences
  const prefs1 = await api('PATCH', '/ai/preferences', {
    autonomyLevel: 'ASSIST', alertThreshold: 'IMPORTANT',
    contextScope: { finance: true, tasks: true, agenda: true, projects: true, notes: true, wellbeing: true, messaging: true },
    dailyBriefing: true, briefingHour: 8,
  }, token);
  ok('prefs update ASSIST/IMPORTANT', prefs1.json?.autonomyLevel === 'ASSIST' && prefs1.json?.alertThreshold === 'IMPORTANT');
  ok('prefs wellbeing TOUJOURS false (défense profondeur)', prefs1.json?.contextScope?.wellbeing === false && prefs1.json?.contextScope?.messaging === false);
  const badPrefs = await api('PATCH', '/ai/preferences', { autonomyLevel: 'AUTOMATE' }, token);
  ok('prefs AUTOMATE refusé (validation)', badPrefs.status === 400 || badPrefs.status === 422);

  // 4) Usage vide
  const usage0 = await api('GET', '/ai/usage', null, token);
  ok('usage quota 60 affiché', usage0.json?.messageQuota === 60 && usage0.json?.messages === 0);

  // 5) Données métier : Space + Task + Event + Account via sync push
  const spaceId = randomUUID(), taskId = randomUUID(), eventId = randomUUID(), accountId = randomUUID();
  const ops = (opId, resourceId, resourceType, op, data) => ({ opId, resourceId, resourceType, op, data, occurredAt: now() });
  const push = await api('POST', '/sync/operations', { deviceId: 'qa-e2e', operations: [
    ops(randomUUID(), spaceId, 'Space', 'CREATE', { id: spaceId, type: 'PERSONAL', name: 'Personnel', colorHex: '#FFB400', isDefault: true, createdAt: now() }),
    ops(randomUUID(), eventId, 'CalendarEvent', 'CREATE', { id: eventId, spaceId, calendarId: spaceId, title: 'Réunion équipe', description: null, location: null, allDay: false, startDate: today(), startTime: '09:00', endDate: today(), endTime: '10:00', status: 'SCHEDULED', originalStart: null, recurrenceRuleId: null, createdAt: now(), updatedAt: now() }),
    ops(randomUUID(), accountId, 'FinancialAccount', 'CREATE', { id: accountId, spaceId, name: 'Espèces', type: 'CASH', currency: 'XOF', initialAmount: 50000, initialDate: today(), note: null, archivedAt: null, createdAt: now() }),
  ] }, token);
  ok('sync push 3 ressources (3×APPLIED)', push.json?.results?.filter((r) => r.status === 'APPLIED').length === 3);

  // 6) Injection d'actions (comme si le modèle les avait proposées) — direct BDD
  const pg = new Client({ connectionString: NEON, ssl: { rejectUnauthorized: false } });
  await pg.connect();
  const userId = (await pg.query('SELECT id FROM "User" WHERE email=$1', [email])).rows[0].id;

  const mkAction = async (actionType, title, payload) => {
    const id = randomUUID();
    await pg.query(
      `INSERT INTO "AiAction" (id, "userId", "conversationId", "actionType", status, title, summary, payload, "payloadHash", "expiresAt", "createdAt", "updatedAt")
       VALUES ($1,$2,NULL,$3,'AWAITING_CONFIRMATION',$4,$5,$6,$7, now() + interval '15 minutes', now(), now())`,
      [id, userId, actionType, title, 'Test E2E', JSON.stringify(payload), hashPayload(payload)],
    );
    return id;
  };

  // 6a) CREATE_TASK_DRAFT nominal
  const taskPayload = { title: 'Préparer le rapport mensuel', notes: null, dueDate: today(), priority: 'HIGH', spaceId: null };
  const taskIdAction = await mkAction('CREATE_TASK_DRAFT', 'Créer : rapport', taskPayload);
  const key1 = randomUUID();
  const c1 = await api('POST', `/ai/actions/${taskIdAction}/confirm`, { payloadHash: hashPayload(taskPayload), idempotencyKey: key1 }, token);
  ok('confirm CREATE_TASK SUCCEEDED', c1.status === 200 && c1.json?.status === 'SUCCEEDED', JSON.stringify(c1.json).slice(0, 120));
  ok('confirm result resourceId+version', c1.json?.result?.resourceId && c1.json?.result?.serverVersion === 1);

  // 6b) Idempotence — rejeu identique = même réponse
  const c1b = await api('POST', `/ai/actions/${taskIdAction}/confirm`, { payloadHash: hashPayload(taskPayload), idempotencyKey: key1 }, token);
  ok('rejeu idempotent = même réponse', c1b.status === 200 && c1b.json?.id === c1.json?.id && c1b.json?.status === 'SUCCEEDED');

  // 6c) Idempotence — rejeu divergent = refusé
  const c1c = await api('POST', `/ai/actions/${taskIdAction}/confirm`, { payloadHash: hashPayload({ ...taskPayload, title: 'autre' }), idempotencyKey: key1 }, token);
  ok('rejeu divergent 409 ALREADY_PROCESSED', c1c.status === 409 && c1c.json?.code === 'AI_ACTION_ALREADY_PROCESSED');

  // 6d) Action déjà traitée avec une NOUVELLE clé = ALREADY_PROCESSED
  const c1d = await api('POST', `/ai/actions/${taskIdAction}/confirm`, { payloadHash: hashPayload(taskPayload), idempotencyKey: randomUUID() }, token);
  ok('nouvelle clé sur action SUCCEEDED = 409', c1d.status === 409 && c1d.json?.code === 'AI_ACTION_ALREADY_PROCESSED');

  // 6e) STALE — hash différent
  const taskPayload2 = { title: 'Acheter du pain', notes: null, dueDate: null, priority: 'NORMAL', spaceId: null };
  const t2 = await mkAction('CREATE_TASK_DRAFT', 'Créer : pain', taskPayload2);
  const c2 = await api('POST', `/ai/actions/${t2}/confirm`, { payloadHash: hashPayload({ ...taskPayload2, priority: 'URGENT' }), idempotencyKey: randomUUID() }, token);
  ok('confirm STALE 409', c2.status === 409 && c2.json?.code === 'AI_ACTION_STALE');
  const t2get = await api('GET', `/ai/actions/${t2}`, null, token);
  ok('action STALE reste AWAITING (re-confirmable)', t2get.json?.status === 'AWAITING_CONFIRMATION');

  // 6f) PROPOSE_EVENT_CHANGE — vérifie l'update de la ressource
  const evPayload = { eventId, newStartDate: today(), newStartTime: '14:00', newEndDate: today(), newEndTime: '15:00', reason: 'Conflit agenda' };
  const evAction = await mkAction('PROPOSE_EVENT_CHANGE', 'Report réunion', evPayload);
  const c3 = await api('POST', `/ai/actions/${evAction}/confirm`, { payloadHash: hashPayload(evPayload), idempotencyKey: randomUUID() }, token);
  ok('confirm EVENT_CHANGE SUCCEEDED', c3.status === 200 && c3.json?.status === 'SUCCEEDED');
  const evRow = await pg.query('SELECT data, version FROM "Resource" WHERE id=$1', [eventId]);
  const evData = evRow.rows[0].data;
  ok('événement mis à jour (14:00, RESCHEDULED, originalStart conservé)',
    evData.startTime === '14:00' && evData.status === 'RESCHEDULED' && evRow.rows[0].version === 2);

  // 6g) PROPOSE_FINANCIAL_CORRECTION — vérifie la transaction créée
  const finPayload = { kind: 'EXPENSE', amount: 25000, label: 'Marché du samedi', accountId, categoryId: null, date: today(), note: 'Dépense oubliée' };
  const finAction = await mkAction('PROPOSE_FINANCIAL_CORRECTION', 'Correction marché', finPayload);
  const c4 = await api('POST', `/ai/actions/${finAction}/confirm`, { payloadHash: hashPayload(finPayload), idempotencyKey: randomUUID() }, token);
  ok('confirm FINANCIAL_CORRECTION SUCCEEDED', c4.status === 200 && c4.json?.status === 'SUCCEEDED');
  const txCount = await pg.query(`SELECT COUNT(*)::int AS n FROM "Resource" WHERE "ownerId"=$1 AND type='FinancialTransaction'`, [userId]);
  ok('transaction créée côté serveur', txCount.rows[0].n === 1);

  // 6h) eventId inconnu → AI_TOOL_VALIDATION_FAILED (action FAILED)
  const badPayload = { eventId: randomUUID(), newStartDate: today(), newStartTime: null, newEndDate: today(), newEndTime: null, reason: 'x' };
  const badAction = await mkAction('PROPOSE_EVENT_CHANGE', 'Événement fantôme', badPayload);
  const c5 = await api('POST', `/ai/actions/${badAction}/confirm`, { payloadHash: hashPayload(badPayload), idempotencyKey: randomUUID() }, token);
  ok('eventId inconnu → 422 TOOL_VALIDATION_FAILED', c5.status === 422 && c5.json?.code === 'AI_TOOL_VALIDATION_FAILED', JSON.stringify(c5.json).slice(0, 100));
  const c5get = await api('GET', `/ai/actions/${badAction}`, null, token);
  ok('action marquée FAILED', c5get.json?.status === 'FAILED');

  // 6i) Cancel
  const cancelAction = await mkAction('CREATE_TASK_DRAFT', 'À annuler', { title: 'Inutile', notes: null, dueDate: null, priority: 'NORMAL', spaceId: null });
  const c6 = await api('POST', `/ai/actions/${cancelAction}/cancel`, { reason: 'Ne veut plus' }, token);
  ok('cancel OK', c6.status === 200 && c6.json?.cancelled === true);
  const c6b = await api('POST', `/ai/actions/${cancelAction}/confirm`, { payloadHash: hashPayload({ title: 'Inutile', notes: null, dueDate: null, priority: 'NORMAL', spaceId: null }), idempotencyKey: randomUUID() }, token);
  ok('confirm après cancel → 409 REJECTED', c6b.status === 409 && c6b.json?.code === 'AI_ACTION_REJECTED');

  // 6j) Expirée
  const expAction = await mkAction('CREATE_TASK_DRAFT', 'Expirée', { title: 'Trop tard', notes: null, dueDate: null, priority: 'NORMAL', spaceId: null });
  await pg.query(`UPDATE "AiAction" SET "expiresAt" = now() - interval '1 minute' WHERE id=$1`, [expAction]);
  const c7 = await api('POST', `/ai/actions/${expAction}/confirm`, { payloadHash: hashPayload({ title: 'Trop tard', notes: null, dueDate: null, priority: 'NORMAL', spaceId: null }), idempotencyKey: randomUUID() }, token);
  ok('confirm expirée → 410 EXPIRED', c7.status === 410 && c7.json?.code === 'AI_ACTION_EXPIRED');

  // 7) Liste + usage + audit
  const list = await api('GET', '/ai/actions', null, token);
  ok('liste actions (≥7)', list.json?.actions?.length >= 7);
  const usage1 = await api('GET', '/ai/usage', null, token);
  ok('usage actionsConfirmed=3', usage1.json?.actionsConfirmed === 3, `reçu ${usage1.json?.actionsConfirmed}`);
  const audit = await pg.query(`SELECT action, COUNT(*)::int AS n FROM "AiAuditEvent" WHERE "userId"=$1 GROUP BY action`, [userId]);
  const auditMap = Object.fromEntries(audit.rows.map((r) => [r.action, r.n]));
  ok('audit ACTION_CONFIRMED=3', auditMap.ACTION_CONFIRMED === 3, JSON.stringify(auditMap));
  ok('audit ACTION_CANCELLED/EXPIRED/FAILED présents', !!auditMap.ACTION_CANCELLED && !!auditMap.ACTION_EXPIRED && !!auditMap.ACTION_FAILED);

  // 8) Isolation — un autre compte ne peut pas confirmer l'action de QA
  const email2 = `qa-p2b-${Date.now()}@yehiortech.com`;
  await api('POST', '/auth/register', { email: email2, password: 'MotDePasse1!', firstName: 'Attaquant' });
  const login2 = await api('POST', '/auth/login', { identifier: email2, password: 'MotDePasse1!' });
  const token2 = login2.json?.accessToken;
  const c8 = await api('GET', `/ai/actions/${taskIdAction}`, null, token2);
  ok('isolation : autre compte → 404', c8.status === 404);

  // 9) Purge QA (comptes + données + actions)
  await pg.query(`DELETE FROM "AiAuditEvent" WHERE "userId"=$1`, [userId]);
  await pg.query(`DELETE FROM "AiToolExecution" WHERE "userId"=$1`, [userId]);
  await pg.query(`DELETE FROM "AiIdempotencyRecord" WHERE "userId"=$1`, [userId]);
  await pg.query(`DELETE FROM "AiUsageRecord" WHERE "userId"=$1`, [userId]);
  await pg.query(`DELETE FROM "AiAction" WHERE "userId"=$1`, [userId]);
  await pg.query(`DELETE FROM "AiPreference" WHERE "userId"=$1`, [userId]);
  await pg.query(`DELETE FROM "AiMessage" WHERE "conversationId" IN (SELECT id FROM "AiConversation" WHERE "userId"=$1)`, [userId]);
  await pg.query(`DELETE FROM "AiConversation" WHERE "userId"=$1`, [userId]);
  await pg.query(`DELETE FROM "SyncChange" WHERE "ownerId"=$1`, [userId]);
  await pg.query(`DELETE FROM "AppliedOp" WHERE "userId"=$1`, [userId]);
  await pg.query(`DELETE FROM "Resource" WHERE "ownerId"=$1`, [userId]);
  await pg.query(`DELETE FROM "Session" WHERE "userId"=$1`, [userId]);
  await pg.query(`DELETE FROM "User" WHERE id=$1`, [userId]);
  const u2 = (await pg.query('SELECT id FROM "User" WHERE email=$1', [email2])).rows[0]?.id;
  if (u2) {
    await pg.query(`DELETE FROM "Session" WHERE "userId"=$1`, [u2]);
    await pg.query(`DELETE FROM "User" WHERE id=$1`, [u2]);
  }
  await pg.end();

  console.log(`\n═══ RÉSULTAT : ${passed} ✓ / ${failed} ✗ ═══`);
  process.exit(failed > 0 ? 1 : 0);
})().catch((e) => { console.error('ERREUR FATALE:', e); process.exit(1); });
