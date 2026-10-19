// Smoke test complet de l'API LifeHelm — valide le flux réel de bout en bout :
// health, register, login, me, refresh (+rotation+rejeu), sessions, 2FA TOTP,
// sync push (idempotence, conflit explicite, DELETE), sync pull (curseur), status,
// password change, forgot/reset, logout.
// Usage : node scripts/smoke.js [baseUrl]   (défaut http://localhost:3001/api/v1)
const assert = require('assert');

const BASE = process.argv[2] || 'http://localhost:3001/api/v1';
const RUN = Math.floor(Math.random() * 1e6);
const DEVICE_A = 'smoke-device-A';
const DEVICE_B = 'smoke-device-B';

let passed = 0;
let failed = 0;

function ok(name, cond, extra = '') {
  if (cond) {
    passed++;
    console.log(`  ✔ ${name}`);
  } else {
    failed++;
    console.error(`  ✘ ${name} ${extra}`);
  }
}

async function api(method, path, { token, body } = {}) {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  let json = null;
  try {
    json = await res.json();
  } catch {
    /* 204 */
  }
  return { status: res.status, json };
}

// TOTP local pour vérifier la 2FA (même algo que le serveur)
const crypto = require('crypto');
const B32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
function b32decode(input) {
  const clean = input.toUpperCase().replace(/[^A-Z2-7]/g, '');
  let bits = 0, value = 0;
  const bytes = [];
  for (const c of clean) {
    value = (value << 5) | B32.indexOf(c);
    bits += 5;
    if (bits >= 8) { bytes.push((value >>> (bits - 8)) & 0xff); bits -= 8; }
  }
  return Buffer.from(bytes);
}
function totpNow(secret) {
  const counter = Math.floor(Date.now() / 1000 / 30);
  const buf = Buffer.alloc(8);
  buf.writeUInt32BE(Math.floor(counter / 0x100000000), 0);
  buf.writeUInt32BE(counter % 0x100000000, 4);
  const hmac = crypto.createHmac('sha1', b32decode(secret)).update(buf).digest();
  const o = hmac[hmac.length - 1] & 0x0f;
  const code = (((hmac[o] & 0x7f) << 24) | (hmac[o + 1] << 16) | (hmac[o + 2] << 8) | hmac[o + 3]) % 1000000;
  return code.toString().padStart(6, '0');
}

async function main() {
  console.log(`\n══ Smoke test LifeHelm API — ${BASE} ══\n`);

  // 1) Health
  console.log('▸ Santé');
  let r = await api('GET', '/health');
  ok('GET /health → 200 ok', r.status === 200 && r.json.status === 'ok');
  ok('Base de données joignable', r.json.database === 'up');

  // 2) Inscription
  console.log('▸ Inscription (courriel + téléphone)');
  const email = `smoke${RUN}@lifehelm.test`;
  const phone = `+22990000${RUN % 100000}`.slice(0, 15);
  r = await api('POST', '/auth/register', {
    body: { email, phone, password: 'MotDePasse1!', firstName: 'Awa', lastName: 'Test', deviceName: 'SmokeTest' },
  });
  ok('POST /auth/register → 201', r.status === 201, JSON.stringify(r.json));
  ok('Tokens émis', !!r.json?.accessToken && !!r.json?.refreshToken && r.json.expiresIn === 900);
  ok('User public sans hash', r.json?.user?.email === email && !('passwordHash' in (r.json?.user ?? {})));
  ok('Code de vérification dev fourni', /^\d{6}$/.test(r.json?.devVerificationCode ?? ''));
  const accessToken = r.json.accessToken;
  const refreshToken = r.json.refreshToken;

  r = await api('POST', '/auth/register', {
    body: { email, password: 'MotDePasse1!', firstName: 'X' },
  });
  ok('Doublon courriel → 409 EMAIL_TAKEN', r.status === 409 && r.json.code === 'EMAIL_TAKEN');

  r = await api('POST', '/auth/register', {
    body: { password: 'MotDePasse1!', firstName: 'X' },
  });
  ok('Sans contact → 400 CONTACT_REQUIRED', r.status === 400 && r.json.code === 'CONTACT_REQUIRED');

  // 3) Profil & vérification
  console.log('▸ Profil & vérification courriel');
  r = await api('GET', '/auth/me', { token: accessToken });
  ok('GET /auth/me → user', r.status === 200 && r.json.user.firstName === 'Awa');

  // 4) Connexion
  console.log('▸ Connexion');
  r = await api('POST', '/auth/login', { body: { identifier: email, password: 'Mauvais' } });
  ok('Mauvais mot de passe → 401 INVALID_CREDENTIALS', r.status === 401 && r.json.code === 'INVALID_CREDENTIALS');

  r = await api('POST', '/auth/login', { body: { identifier: email, password: 'MotDePasse1!', deviceName: 'SmokeTest' } });
  ok('POST /auth/login → 200', r.status === 200 && !!r.json.accessToken);
  const rt2 = r.json.refreshToken;

  r = await api('POST', '/auth/login', { body: { identifier: phone, password: 'MotDePasse1!' } });
  ok('Connexion par téléphone → 200', r.status === 200 && !!r.json.accessToken);

  // 5) Refresh : rotation puis détection de rejeu
  console.log('▸ Rotation des jetons de renouvellement');
  r = await api('POST', '/auth/refresh', { body: { refreshToken: rt2 } });
  ok('POST /auth/refresh → nouveaux tokens', r.status === 200 && r.json.refreshToken !== rt2);
  const rt3 = r.json.refreshToken;

  r = await api('POST', '/auth/refresh', { body: { refreshToken: rt2 } });
  ok('Rejeu du jeton tourné → 401 TOKEN_REUSED', r.status === 401 && r.json.code === 'TOKEN_REUSED');

  r = await api('POST', '/auth/refresh', { body: { refreshToken: rt3 } });
  ok('Famille révoquée après rejeu → 401', r.status === 401);

  // 6) Sessions
  console.log('▸ Sessions & appareils');
  r = await api('GET', '/auth/sessions', { token: accessToken });
  ok('GET /auth/sessions liste', r.status === 200 && Array.isArray(r.json.sessions));
  const nbSessions = r.json.sessions.length;
  ok('Au moins 2 sessions actives (register + login)', nbSessions >= 2, `(${nbSessions})`);
  const other = r.json.sessions.find((s) => !s.current);
  if (other) {
    r = await api('DELETE', `/auth/sessions/${other.id}`, { token: accessToken });
    ok('DELETE session → 204', r.status === 204);
  }

  // 7) 2FA TOTP
  console.log('▸ 2FA TOTP');
  r = await api('POST', '/auth/2fa/setup', { token: accessToken });
  ok('2FA setup → secret + otpauth', r.status === 200 && !!r.json.secret && r.json.otpauthUrl.startsWith('otpauth://totp/'));
  const totpSecret = r.json.secret;
  const goodCode = totpNow(totpSecret);

  r = await api('POST', '/auth/2fa/enable', { token: accessToken, body: { totpCode: '000000' } });
  ok('Code TOTP invalide refusé (probablement)', r.status === 400 || r.status === 401 || (r.status === 204 && goodCode === '000000'));

  r = await api('POST', '/auth/2fa/enable', { token: accessToken, body: { totpCode: goodCode } });
  ok('2FA activée', r.status === 204);

  r = await api('POST', '/auth/login', { body: { identifier: email, password: 'MotDePasse1!' } });
  ok('Login sans code → 428 TOTP_REQUIRED', r.status === 428 && r.json.code === 'TOTP_REQUIRED');

  r = await api('POST', '/auth/login', { body: { identifier: email, password: 'MotDePasse1!', totpCode: totpNow(totpSecret), deviceName: 'Smoke 2FA' } });
  ok('Login avec code TOTP → 200', r.status === 200 && !!r.json.accessToken);
  const totpAccessToken = r.json.accessToken;

  r = await api('POST', '/auth/2fa/disable', { token: totpAccessToken, body: { totpCode: totpNow(totpSecret) } });
  ok('2FA désactivée', r.status === 204);

  // 8) SYNCHRONISATION — push idempotent
  console.log('▸ Synchronisation — push');
  const opA = {
    opId: crypto.randomUUID(),
    resourceType: 'Task',
    resourceId: crypto.randomUUID(),
    op: 'CREATE',
    occurredAt: new Date().toISOString(),
    data: { id: 'x', title: 'Payer la tontine', status: 'TODO', priority: 'HIGH', position: 0 },
  };
  r = await api('POST', '/sync/operations', { token: accessToken, body: { deviceId: DEVICE_A, operations: [opA] } });
  ok('Push 1 op → APPLIED v1', r.status === 200 && r.json.results[0].status === 'APPLIED' && r.json.results[0].serverVersion === 1);
  ok('serverSeq > 0', r.json.serverSeq > 0);

  r = await api('POST', '/sync/operations', { token: accessToken, body: { deviceId: DEVICE_A, operations: [opA] } });
  ok('Re-push même opId → DUPLICATE (idempotence)', r.json.results[0].status === 'DUPLICATE');

  r = await api('POST', '/sync/operations', {
    token: accessToken,
    body: { deviceId: DEVICE_A, operations: [{ ...opA, opId: crypto.randomUUID(), resourceType: 'Inconnu', data: {} }] },
  });
  ok('Type inconnu → REJECTED', r.json.results[0].status === 'REJECTED');

  r = await api('POST', '/sync/operations', {
    token: accessToken,
    body: { deviceId: DEVICE_A, operations: [{ opId: crypto.randomUUID(), resourceType: 'Task', resourceId: crypto.randomUUID(), op: 'CREATE', occurredAt: new Date().toISOString(), data: null }] },
  });
  ok('CREATE sans data → REJECTED', r.json.results[0].status === 'REJECTED');

  // Batch de 3 (dont une FinancialTransaction)
  const txId = crypto.randomUUID();
  const opTx = {
    opId: crypto.randomUUID(),
    resourceType: 'FinancialTransaction',
    resourceId: txId,
    op: 'CREATE',
    occurredAt: new Date(Date.now() - 60000).toISOString(),
    data: { id: txId, amount: 15000, currency: 'XOF', label: 'Vente tissus' },
  };
  const opNote = {
    opId: crypto.randomUUID(),
    resourceType: 'Note',
    resourceId: crypto.randomUUID(),
    op: 'CREATE',
    occurredAt: new Date().toISOString(),
    data: { id: 'n1', title: 'Idées boutique', plainText: 'Acheter du wax' },
  };
  const opTaskUp = {
    opId: crypto.randomUUID(),
    resourceType: 'Task',
    resourceId: opA.resourceId,
    op: 'UPDATE',
    occurredAt: new Date().toISOString(),
    data: { ...opA.data, status: 'DONE' },
  };
  r = await api('POST', '/sync/operations', { token: accessToken, body: { deviceId: DEVICE_A, operations: [opTx, opNote, opTaskUp] } });
  ok('Batch de 3 → tous APPLIED', r.json.results.every((x) => x.status === 'APPLIED'), JSON.stringify(r.json));

  // 9) Conflit explicite : device B réécrit la transaction divergente
  console.log('▸ Synchronisation — conflit explicite (transaction financière)');
  const opTxB = {
    opId: crypto.randomUUID(),
    resourceType: 'FinancialTransaction',
    resourceId: txId,
    op: 'UPDATE',
    occurredAt: new Date(Date.now() - 30000).toISOString(), // plus ancien que la maj serveur
    data: { id: txId, amount: 20000, currency: 'XOF', label: 'Autre device' },
  };
  r = await api('POST', '/sync/operations', { token: accessToken, body: { deviceId: DEVICE_B, operations: [opTxB] } });
  ok('Device B + data divergente + serveur plus récent → CONFLICT', r.json.results[0].status === 'CONFLICT', JSON.stringify(r.json));

  const opTxBsame = { ...opTxB, opId: crypto.randomUUID(), data: opTx.data };
  r = await api('POST', '/sync/operations', { token: accessToken, body: { deviceId: DEVICE_B, operations: [opTxBsame] } });
  ok('Mêmes données (pas de divergence) → APPLIED', r.json.results[0].status === 'APPLIED', JSON.stringify(r.json));

  // Non-sensible : last-arrival-wins documenté
  const opTaskB = {
    opId: crypto.randomUUID(),
    resourceType: 'Task',
    resourceId: opA.resourceId,
    op: 'UPDATE',
    occurredAt: new Date(Date.now() - 30000).toISOString(),
    data: { ...opA.data, status: 'IN_PROGRESS' },
  };
  r = await api('POST', '/sync/operations', { token: accessToken, body: { deviceId: DEVICE_B, operations: [opTaskB] } });
  ok('Tâche (non sensible) → APPLIED sans conflit', r.json.results[0].status === 'APPLIED');

  // 10) DELETE + pull par curseur
  console.log('▸ Synchronisation — pull par curseur');
  r = await api('POST', '/sync/operations', {
    token: accessToken,
    body: { deviceId: DEVICE_A, operations: [{ opId: crypto.randomUUID(), resourceType: 'Note', resourceId: opNote.resourceId, op: 'DELETE', occurredAt: new Date().toISOString() }] },
  });
  ok('DELETE → APPLIED', r.json.results[0].status === 'APPLIED');

  r = await api('GET', '/sync/changes?cursor=0&limit=2', { token: accessToken });
  ok('Pull page 1 (limit 2, hasMore)', r.status === 200 && r.json.changes.length <= 2 && r.json.hasMore === true);
  const cursor1 = r.json.nextCursor;

  r = await api('GET', `/sync/changes?cursor=${cursor1}&limit=500`, { token: accessToken });
  ok('Pull page 2 → reste des changements', r.status === 200 && r.json.changes.length >= 1 && r.json.hasMore === false);
  const noteChange = r.json.changes.find((c) => c.resourceType === 'Note');
  ok('Note marquée supprimée (tombstone)', noteChange && noteChange.deleted === true && noteChange.op === 'DELETE');

  r = await api('GET', `/sync/changes?cursor=${r.json.nextCursor}&limit=500`, { token: accessToken });
  ok('Curseur avancé → plus rien', r.json.changes.length === 0);

  r = await api('GET', '/sync/status', { token: accessToken });
  ok('GET /sync/status cohérent', r.status === 200 && r.json.serverSeq > 0 && r.json.resourceCount >= 2, JSON.stringify(r.json));

  // 11) Mot de passe
  console.log('▸ Mot de passe');
  r = await api('POST', '/auth/password', { token: accessToken, body: { currentPassword: 'Mauvais', newPassword: 'Nouveau1!2!' } });
  ok('Ancien mot de passe faux → 401', r.status === 401);

  r = await api('POST', '/auth/password/forgot', { body: { identifier: email } });
  ok('Forgot → 202 + devResetToken', r.status === 202 && typeof r.json.devResetToken === 'string');

  r = await api('POST', '/auth/password', { token: accessToken, body: { currentPassword: 'MotDePasse1!', newPassword: 'Nouveau1!2!' } });
  ok('Changement mot de passe → 204', r.status === 204);

  r = await api('GET', '/auth/me', { token: accessToken });
  ok('Sessions révoquées après changement → 401', r.status === 401);

  r = await api('POST', '/auth/login', { body: { identifier: email, password: 'Nouveau1!2!', deviceName: 'Après reset' } });
  ok('Login avec le nouveau mot de passe', r.status === 200 && !!r.json.accessToken);
  const finalToken = r.json.accessToken;
  const finalRefresh = r.json.refreshToken;

  r = await api('POST', '/auth/password/forgot', { body: { identifier: email } });
  r = await api('POST', '/auth/password/reset', { body: { resetToken: r.json.devResetToken, newPassword: 'Troisieme1!3!' } });
  ok('Reset par token → 204', r.status === 204);

  r = await api('POST', '/auth/login', { body: { identifier: email, password: 'Troisieme1!3!' } });
  ok('Login après reset', r.status === 200);

  // 12) Déconnexion
  console.log('▸ Déconnexion');
  r = await api('POST', '/auth/logout', { body: { refreshToken: finalRefresh } });
  ok('Logout → 204', r.status === 204);
  r = await api('POST', '/auth/refresh', { body: { refreshToken: finalRefresh } });
  ok('Refresh après logout → 401', r.status === 401);

  console.log(`\n══ RÉSULTAT : ${passed} OK / ${failed} ÉCHEC(S) ══\n`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((e) => {
  console.error('FATAL:', e.message);
  process.exit(1);
});
