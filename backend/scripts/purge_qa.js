// Purge des comptes QA résiduels (qa-p2*, dbg-*, debug-*) + toutes leurs données.
const { Client } = require('pg');
const NEON = 'postgresql://neondb_owner:npg_i4rolEXA9fpy@ep-small-mouse-al74os4c-pooler.c-3.eu-central-1.aws.neon.tech/LifeHelm?sslmode=require';

(async () => {
  const pg = new Client({ connectionString: NEON, ssl: { rejectUnauthorized: false } });
  await pg.connect();
  const users = await pg.query(
    `SELECT id, email FROM "User" WHERE email LIKE 'qa-p2%' OR email LIKE 'dbg-%' OR email LIKE 'debug-%' OR email LIKE 'qa-%'`,
  );
  console.log(`comptes QA à purger : ${users.rows.length}`);
  for (const u of users.rows) {
    await pg.query('DELETE FROM "AiAuditEvent" WHERE "userId"=$1', [u.id]);
    await pg.query('DELETE FROM "AiToolExecution" WHERE "userId"=$1', [u.id]);
    await pg.query('DELETE FROM "AiIdempotencyRecord" WHERE "userId"=$1', [u.id]);
    await pg.query('DELETE FROM "AiUsageRecord" WHERE "userId"=$1', [u.id]);
    await pg.query('DELETE FROM "AiAction" WHERE "userId"=$1', [u.id]);
    await pg.query('DELETE FROM "AiPreference" WHERE "userId"=$1', [u.id]);
    await pg.query('DELETE FROM "AiMessage" WHERE "conversationId" IN (SELECT id FROM "AiConversation" WHERE "userId"=$1)', [u.id]);
    await pg.query('DELETE FROM "AiConversation" WHERE "userId"=$1', [u.id]);
    await pg.query('DELETE FROM "SyncChange" WHERE "ownerId"=$1', [u.id]);
    await pg.query('DELETE FROM "AppliedOp" WHERE "userId"=$1', [u.id]);
    await pg.query('DELETE FROM "Resource" WHERE "ownerId"=$1', [u.id]);
    await pg.query('DELETE FROM "Session" WHERE "userId"=$1', [u.id]);
    await pg.query('DELETE FROM "User" WHERE id=$1', [u.id]);
  }
  const counts = await pg.query(`
    SELECT
      (SELECT COUNT(*)::int FROM "User") AS users,
      (SELECT COUNT(*)::int FROM "AiAction") AS actions,
      (SELECT COUNT(*)::int FROM "Resource") AS resources,
      (SELECT COUNT(*)::int FROM "AiIdempotencyRecord") AS idem,
      (SELECT COUNT(*)::int FROM "AiAuditEvent") AS audit,
      (SELECT COUNT(*)::int FROM "AiUsageRecord") AS usage
  `);
  console.log('état final :', counts.rows[0]);
  await pg.end();
})();
