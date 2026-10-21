// Purge QA : comptes de test + données résiduelles (Phase push incluse).
const { Client } = require('pg');
const NEON = 'postgresql://neondb_owner:npg_i4rolEXA9fpy@ep-small-mouse-al74os4c-pooler.c-3.eu-central-1.aws.neon.tech/LifeHelm?sslmode=require';

(async () => {
  const pg = new Client({ connectionString: NEON, ssl: { rejectUnauthorized: false } });
  await pg.connect();

  const qa = (await pg.query("SELECT id, email FROM \"User\" WHERE email LIKE 'qa-%@yehiortech.com' OR email LIKE '%qa%'")).rows;
  console.log(`Comptes QA trouvés : ${qa.length}`);
  if (qa.length > 0) {
    const ids = qa.map((r) => r.id);
    await pg.query('DELETE FROM "AiAuditEvent" WHERE "userId" = ANY($1::text[])', [ids]);
    await pg.query('DELETE FROM "AiToolExecution" WHERE "userId" = ANY($1::text[])', [ids]);
    await pg.query('DELETE FROM "AiAction" WHERE "userId" = ANY($1::text[])', [ids]);
    await pg.query('DELETE FROM "User" WHERE id = ANY($1::text[])', [ids]);
  }

  const counts = {};
  for (const t of ['User', 'Session', 'Resource', 'SyncChange', 'AppliedOp', 'AiConversation', 'AiMessage',
    'AiAction', 'AiToolExecution', 'AiAuditEvent', 'AiConsent', 'AiPreference', 'AiIdempotencyRecord',
    'AiUsageRecord', 'AiBriefing', 'AiAlert', 'PushDevice']) {
    counts[t] = (await pg.query(`SELECT COUNT(*)::int AS c FROM "${t}"`)).rows[0].c;
  }
  console.log(JSON.stringify(counts));
  const dirty = Object.entries(counts).filter(([, v]) => v > 0);
  console.log(dirty.length === 0 ? 'BASE PROPRE ✓' : `RÉSIDUS : ${dirty.map(([k, v]) => `${k}=${v}`).join(', ')}`);
  await pg.end();
})().catch((e) => { console.error('ERREUR :', e.message); process.exit(1); });
