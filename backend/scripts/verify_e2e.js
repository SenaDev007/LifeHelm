// Vérification E2E : le compte de test a-t-il bien synchronisé ses données ?
// NB : noms de tables/colonnes = noms de modèles Prisma (PascalCase / camelCase).
const { Client } = require('pg');
const url = process.env.DIRECT_URL;

async function main() {
  const client = new Client({ connectionString: url });
  await client.connect();

  const user = await client.query(
    `SELECT id, email, "firstName", "lastName" FROM "User" WHERE email = $1`,
    ['awa.e2e@lifehelm.test'],
  );
  if (user.rows.length === 0) {
    console.log('✘ Utilisateur awa.e2e@lifehelm.test INTROUVABLE');
    process.exit(1);
  }
  const u = user.rows[0];
  console.log(`✔ Utilisateur : ${u.firstName} ${u.lastName} <${u.email}>`);

  const sessions = await client.query(
    `SELECT count(*)::int AS n FROM "Session" WHERE "userId" = $1 AND "revokedAt" IS NULL`,
    [u.id],
  );
  console.log(`✔ Sessions actives : ${sessions.rows[0].n}`);

  const resources = await client.query(
    `SELECT type, count(*)::int AS n FROM "Resource" WHERE "ownerId" = $1 GROUP BY type ORDER BY n DESC`,
    [u.id],
  );
  const total = resources.rows.reduce((s, r) => s + r.n, 0);
  console.log(`\nRessources synchronisées (${total} au total) :`);
  for (const r of resources.rows) console.log(`  - ${r.type}: ${r.n}`);

  const changes = await client.query(
    `SELECT count(*)::int AS n FROM "SyncChange" WHERE "ownerId" = $1`,
    [u.id],
  );
  console.log(`\n✔ Journal sync_changes (pull) : ${changes.rows[0].n}`);

  const applied = await client.query(
    `SELECT count(*)::int AS n FROM "AppliedOp" WHERE "userId" = $1`,
    [u.id],
  );
  console.log(`✔ Ops idempotentes appliquées : ${applied.rows[0].n}`);

  const sample = await client.query(
    `SELECT type, data FROM "Resource" WHERE "ownerId" = $1 AND type = 'Space' ORDER BY "createdAt" LIMIT 3`,
    [u.id],
  );
  for (const s of sample.rows) {
    console.log(`  Exemple ${s.type} → ${JSON.stringify(s.data).slice(0, 110)}`);
  }

  await client.end();
}

main().catch((e) => { console.error('ERREUR:', e.message); process.exit(1); });
