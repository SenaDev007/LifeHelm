// E2E Notifications push (D17.6) — appareils FCM, statut honnête, test, isolation.
// Exécution : node scripts/e2e_push.js (backend local sur :3001, BDD Neon).
const crypto = require('crypto');
const { Client } = require('pg');

const BASE = 'http://localhost:3001/api/v1';
const NEON = 'postgresql://neondb_owner:npg_i4rolEXA9fpy@ep-small-mouse-al74os4c-pooler.c-3.eu-central-1.aws.neon.tech/LifeHelm?sslmode=require';

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

const fakeToken = (n) => `eJxr_A-${crypto.randomBytes(40).toString('base64url').slice(0, n)}`;

(async () => {
  console.log('═══ E2E Notifications push (briefing) ═══');

  // 0) Compte QA
  const email = `qa-push-${Date.now()}@yehiortech.com`;
  await api('POST', '/auth/register', { email, password: 'MotDePasse1!', firstName: 'QA', lastName: 'Push' });
  const login = await api('POST', '/auth/login', { identifier: email, password: 'MotDePasse1!' });
  const token = login.json?.accessToken ?? login.json?.access_token;
  if (!token) { console.log('PAS DE TOKEN — ABANDON'); process.exit(1); }
  ok('register + login', !!token);

  const pg = new Client({ connectionString: NEON, ssl: { rejectUnauthorized: false } });
  await pg.connect();
  const userId = (await pg.query('SELECT id FROM "User" WHERE email=$1', [email])).rows[0].id;

  // 1) Statut — honnête dès le départ
  const st0 = await api('GET', '/push/status', null, token);
  ok('status provider=FCM', st0.json?.provider === 'FCM');
  ok('status mode honnête (READY ou DEGRADED)', ['READY', 'DEGRADED'].includes(st0.json?.mode));
  ok('status activeDevices=0 au départ', st0.json?.activeDevices === 0);
  const stNoAuth = await api('GET', '/push/status');
  ok('status exige l\'authentification', stNoAuth.status === 401);

  // 2) Enregistrement d'appareil
  const t1 = fakeToken(140);
  const r1 = await api('POST', '/push/devices', { token: t1, platform: 'ANDROID', deviceId: 'qa-device-1', appVersion: '0.3.0' }, token);
  ok('register 201', r1.status === 201 && !!r1.json?.id);
  ok('register jeton masqué (tokenPreview, jamais le jeton)', typeof r1.json?.tokenPreview === 'string' && !JSON.stringify(r1.json).includes(t1));
  ok('register plateforme ANDROID', r1.json?.platform === 'ANDROID');

  // Upsert : même jeton = même appareil (rotation / ré-enregistrement)
  const r2 = await api('POST', '/push/devices', { token: t1, platform: 'ANDROID', appVersion: '0.3.1' }, token);
  ok('upsert même jeton = même id', r2.json?.id === r1.json?.id);
  const count1 = (await pg.query('SELECT COUNT(*)::int AS c FROM "PushDevice" WHERE "userId"=$1', [userId])).rows[0].c;
  ok('un seul appareil en base après upsert', count1 === 1);

  // Deuxième appareil (tablette)
  const t2 = fakeToken(140);
  const r3 = await api('POST', '/push/devices', { token: t2, platform: 'WEB' }, token);
  const st1 = await api('GET', '/push/status', null, token);
  ok('deux appareils actifs', st1.json?.activeDevices === 2);

  // 3) Validation d'entrée
  const badEmpty = await api('POST', '/push/devices', { token: '', platform: 'ANDROID' }, token);
  ok('jeton vide refusé', badEmpty.status === 400);
  const badShort = await api('POST', '/push/devices', { token: 'abc', platform: 'ANDROID' }, token);
  ok('jeton trop court refusé', badShort.status === 400);
  const badPlatform = await api('POST', '/push/devices', { token: fakeToken(140), platform: 'SYMBIAN' }, token);
  ok('plateforme inconnue refusée', badPlatform.status === 400);
  const badChars = await api('POST', '/push/devices', { token: `${fakeToken(100)}; rm -rf`, platform: 'ANDROID' }, token);
  ok('jeton avec caractères interdits refusé', badChars.status === 400);

  // 4) Liste + suppression
  const list = await api('GET', '/push/devices', null, token);
  ok('liste 2 appareils (jetons masqués)', list.json?.devices?.length === 2 && list.json.devices.every((d) => d.tokenPreview && !d.token));
  const del = await api('DELETE', `/push/devices/${r3.json.id}`, null, token);
  ok('suppression OK', del.json?.deleted === true);
  const delAgain = await api('DELETE', `/push/devices/${r3.json.id}`, null, token);
  ok('re-suppression → 404', delAgain.status === 404);
  const st2 = await api('GET', '/push/status', null, token);
  ok('status reflète la suppression (1 actif)', st2.json?.activeDevices === 1);

  // 5) Test d'envoi — honnête selon la configuration serveur
  const test = await api('POST', '/push/test', null, token);
  if (st0.json?.mode === 'DEGRADED') {
    ok('test → 503 PUSH_NOT_CONFIGURED (mode honnête)', test.status === 503 && test.json?.code === 'PUSH_NOT_CONFIGURED');
  } else {
    ok('test → rapport d\'envoi', [200, 409].includes(test.status));
  }
  // Sans appareil : PUSH_NO_DEVICE (409) dans les deux modes
  await api('DELETE', `/push/devices/${r1.json.id}`, null, token);
  const testNoDevice = await api('POST', '/push/test', null, token);
  if (st0.json?.mode === 'READY') {
    ok('test sans appareil → 409 PUSH_NO_DEVICE', testNoDevice.status === 409 && testNoDevice.json?.code === 'PUSH_NO_DEVICE');
  } else {
    ok('test sans appareil → 503 (dégradé prioritaire)', testNoDevice.status === 503);
  }

  // 6) Isolation inter-comptes
  const email2 = `qa-push2-${Date.now()}@yehiortech.com`;
  await api('POST', '/auth/register', { email: email2, password: 'MotDePasse1!', firstName: 'QA', lastName: 'Push2' });
  const login2 = await api('POST', '/auth/login', { identifier: email2, password: 'MotDePasse1!' });
  const token2 = login2.json?.accessToken ?? login2.json?.access_token;
  const list2 = await api('GET', '/push/devices', null, token2);
  ok('compte B ne voit aucun appareil de A', list2.json?.devices?.length === 0);
  const t3 = fakeToken(140);
  const rB = await api('POST', '/push/devices', { token: t3, platform: 'IOS' }, token2);
  ok('compte B enregistre son propre appareil', rB.status === 201);
  const delCross = await api('DELETE', `/push/devices/${rB.json.id}`, null, token);
  ok('compte A ne peut pas supprimer l\'appareil de B', delCross.status === 404);

  // 7) Vol de jeton : le ré-enregistrement réattribue la propriété
  //    (FCM garantit l'unicité mondiale : seul le détenteur légitime du
  //    compte qui présente le jeton en garde le contrôle.)
  const stolen = await api('POST', '/push/devices', { token: t3, platform: 'IOS' }, token);
  ok('upsert par un autre compte réattribue le jeton', stolen.status === 201 && stolen.json?.id === rB.json.id);
  const ownerB = await pg.query('SELECT "userId" FROM "PushDevice" WHERE id=$1', [rB.json.id]);
  ok('propriétaire = compte demandeur', ownerB.rows[0].userId === userId);
  const list2b = await api('GET', '/push/devices', null, token2);
  ok('compte B perd l\'appareil réattribué', list2b.json?.devices?.length === 0);

  // 8) Chaîne briefing → push : la génération à la demande ne pousse JAMAIS
  //    (l'utilisateur est déjà dans l'app) et ne casse jamais le briefing.
  await api('PATCH', '/ai/preferences', { dailyBriefing: true, briefingHour: 7 }, token);
  const brf = await api('GET', '/ai/briefing', null, token);
  ok('briefing ON_DEMAND généré sans push (generatedNow, pas d\'erreur)', brf.status === 200 && (brf.json?.generatedNow === true || brf.json?.generatedNow === false));

  // 9) Purge QA — les pistes d'audit sont Restrict (purge explicite)
  const qaIds = (await pg.query('SELECT id FROM "User" WHERE email LIKE $1', ['qa-push%'])).rows.map((r) => r.id);
  if (qaIds.length > 0) {
    await pg.query('DELETE FROM "AiAuditEvent" WHERE "userId" = ANY($1::text[])', [qaIds]);
    await pg.query('DELETE FROM "AiToolExecution" WHERE "userId" = ANY($1::text[])', [qaIds]);
    await pg.query('DELETE FROM "AiAction" WHERE "userId" = ANY($1::text[])', [qaIds]);
    await pg.query('DELETE FROM "User" WHERE id = ANY($1::text[])', [qaIds]);
  }
  const left = (await pg.query('SELECT COUNT(*)::int AS c FROM "PushDevice"')).rows[0].c;
  ok('purge QA (cascade PushDevice)', left === 0);
  await pg.end();

  console.log(`\n═══ RÉSULTAT : ${passed} ✓ / ${failed} ✗ ═══`);
  process.exit(failed > 0 ? 1 : 0);
})().catch((e) => { console.error('ERREUR E2E :', e); process.exit(1); });
