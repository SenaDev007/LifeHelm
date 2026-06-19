// Configuration de l'app — version robuste pour production
import dotenv from 'dotenv';
import path from 'node:path';
import fs from 'node:fs';

// Charge .env s'il existe (en dev), sans crasher s'il n'existe pas (en prod)
const envPath = path.resolve(process.cwd(), '.env');
if (fs.existsSync(envPath)) {
  dotenv.config({ path: envPath, override: true });
}

// Nettoie et optimise les URLs PostgreSQL pour Neon + Prisma
// - Retire channel_binding=require (Prisma ne le supporte pas)
// - Ajoute pgbouncer=true si pas présent (nécessaire pour Neon pooler)
// - Ajoute connection_limit=1 (évite d'épuiser le pool Neon en low-traffic)
function cleanDbUrl(url: string | undefined, opts: { addPgbouncer?: boolean } = {}): string | undefined {
  if (!url) return url;
  let cleaned = url;
  // Retire &channel_binding=require ou ?channel_binding=require
  cleaned = cleaned
    .replace(/[?&]channel_binding=require/g, '')
    .replace(/\?&/, '?')
    .replace(/&&/g, '&')
    .replace(/[?&]$/, '');

  // Pour DATABASE_URL (pooler Neon) : ajoute pgbouncer + connection_limit
  if (opts.addPgbouncer && !cleaned.includes('pgbouncer=')) {
    const sep = cleaned.includes('?') ? '&' : '?';
    cleaned = `${cleaned}${sep}pgbouncer=true&connection_limit=1`;
  }

  if (cleaned !== url) {
    console.log(`  → Optimized DB URL (channel_binding removed${opts.addPgbouncer ? ', pgbouncer+connection_limit=1 added' : ''})`);
  }
  return cleaned;
}

const rawDbUrl = process.env.DATABASE_URL;
const rawDirectUrl = process.env.DIRECT_URL;
// DATABASE_URL (utilisé au runtime) → avec pgbouncer pour Neon pooler
const optimizedDbUrl = cleanDbUrl(rawDbUrl, { addPgbouncer: true });
// DIRECT_URL (utilisé pour migrations) → sans pgbouncer
const optimizedDirectUrl = cleanDbUrl(rawDirectUrl, { addPgbouncer: false });

// Override process.env pour que Prisma utilise les URLs optimisées
if (optimizedDbUrl && optimizedDbUrl !== rawDbUrl) {
  process.env.DATABASE_URL = optimizedDbUrl;
}
if (optimizedDirectUrl && optimizedDirectUrl !== rawDirectUrl) {
  process.env.DIRECT_URL = optimizedDirectUrl;
}

// Diagnostics de démarrage (utile pour debug Railway)
console.log('═══════════════════════════════════════════════');
console.log('  LifeHelm Backend — Configuration');
console.log('═══════════════════════════════════════════════');
console.log(`  NODE_ENV:        ${process.env.NODE_ENV || '(unset, default: development)'}`);
console.log(`  PORT:            ${process.env.PORT || '(unset, default: 3001)'}`);
console.log(`  DATABASE_URL:    ${process.env.DATABASE_URL ? '✓ set (' + process.env.DATABASE_URL.substring(0, 60) + '...)' : '✗ MISSING'}`);
console.log(`  DIRECT_URL:      ${process.env.DIRECT_URL ? '✓ set' : '⚠ unset (will use DATABASE_URL)'}`);
console.log(`  JWT_ACCESS:      ${process.env.JWT_ACCESS_SECRET ? '✓ set' : '⚠ using default (not secure!)'}`);
console.log(`  JWT_REFRESH:     ${process.env.JWT_REFRESH_SECRET ? '✓ set' : '⚠ using default (not secure!)'}`);
console.log(`  CORS_ORIGIN:     ${process.env.CORS_ORIGIN || '*'}`);
console.log(`  FEDAPAY_KEY:     ${process.env.FEDAPAY_SECRET_KEY ? '✓ set' : '✗ unset (mock mode)'}`);
console.log('═══════════════════════════════════════════════');

export const config = {
  port: parseInt(process.env.PORT || '3001', 10),
  nodeEnv: process.env.NODE_ENV || 'development',
  corsOrigin: process.env.CORS_ORIGIN || '*',

  jwt: {
    accessSecret: process.env.JWT_ACCESS_SECRET || 'dev_access_secret_change_me_in_prod',
    refreshSecret: process.env.JWT_REFRESH_SECRET || 'dev_refresh_secret_change_me_in_prod',
    accessExpires: process.env.JWT_ACCESS_EXPIRES || '15m',
    refreshExpires: process.env.JWT_REFRESH_EXPIRES || '7d',
  },

  anthropic: {
    apiKey: process.env.ANTHROPIC_API_KEY || '',
  },

  fedapay: {
    secretKey: process.env.FEDAPAY_SECRET_KEY || '',
    baseUrl: process.env.FEDAPAY_BASE_URL || 'https://api.fedapay.com/v1',
  },

  rateLimit: {
    windowMs: 15 * 60 * 1000, // 15 min
    max: 100,
  },
};
