// Réinitialisation complète de la base Neon LifeHelm (demande utilisateur) :
// suppression de TOUTES les anciennes tables/types/séquences du schéma public
// pour laisser place au nouveau schéma Prisma (auth + sync).
const { Client } = require('pg');

const url = process.env.DIRECT_URL || process.env.NEON_URL;

async function main() {
  const client = new Client({ connectionString: url });
  await client.connect();

  const before = await client.query(
    `SELECT count(*)::int AS n FROM information_schema.tables WHERE table_schema='public'`,
  );
  console.log(`Tables avant reset : ${before.rows[0].n}`);

  // Compte le nombre d'objets qui vont être détruits (audit trail)
  const enums = await client.query(
    `SELECT count(*)::int AS n FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname='public' AND t.typtype='e'`,
  );
  console.log(`Types enum avant reset : ${enums.rows[0].n}`);

  await client.query('DROP SCHEMA public CASCADE');
  await client.query('CREATE SCHEMA public');
  // Privilèges par défaut Neon
  await client.query('GRANT ALL ON SCHEMA public TO neondb_owner');
  await client.query('GRANT ALL ON SCHEMA public TO public');

  const after = await client.query(
    `SELECT count(*)::int AS n FROM information_schema.tables WHERE table_schema='public'`,
  );
  console.log(`Tables après reset : ${after.rows[0].n}`);
  console.log('RESET TERMINÉ — schéma public vide, prêt pour Prisma.');

  await client.end();
}

main().catch((e) => {
  console.error('ERREUR RESET:', e.message);
  process.exit(1);
});
