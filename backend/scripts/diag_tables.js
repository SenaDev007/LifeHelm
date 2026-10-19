// Compare les tables vues via pooler vs direct (diagnostic branching Neon)
const { Client } = require('pg');

const POOLER = 'postgresql://neondb_owner:npg_i4rolEXA9fpy@ep-small-mouse-al74os4c-pooler.c-3.eu-central-1.aws.neon.tech/LifeHelm?sslmode=require';
const DIRECT = 'postgresql://neondb_owner:npg_i4rolEXA9fpy@ep-small-mouse-al74os4c.c-3.eu-central-1.aws.neon.tech/LifeHelm?sslmode=require';

async function list(name, url) {
  const c = new Client({ connectionString: url });
  await c.connect();
  const t = await c.query(
    `SELECT table_name FROM information_schema.tables WHERE table_schema='public' ORDER BY 1`,
  );
  const db = await c.query(`SELECT current_database()`);
  console.log(`${name} (db=${db.rows[0].current_database}) : ${t.rows.map((r) => r.table_name).join(', ') || '(vide)'}`);
  await c.end();
}

(async () => {
  await list('POOLER ', POOLER);
  await list('DIRECT ', DIRECT);
})();
