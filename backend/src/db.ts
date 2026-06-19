import { PrismaClient } from '@prisma/client';

declare global {
  // eslint-disable-next-line no-var
  var __prisma: PrismaClient | undefined;
}

// Configuration Prisma optimisée pour Neon (serverless PostgreSQL)
// - Neon ferme les connexions inactives (scale-to-zero)
// - On limite le pool à 1 connexion (suffisant en low-traffic)
// - On active les retries automatiques sur connexions fermées
export const prisma =
  global.__prisma ||
  new PrismaClient({
    log: process.env.NODE_ENV === 'development' ? ['warn', 'error'] : ['error'],
    datasources: {
      db: {
        // Prisma lit process.env.DATABASE_URL automatiquement
        // On ne le surcharge pas ici
      },
    },
    // Retry automatique sur erreurs de connexion (Neon scale-to-zero)
    // transactionOptions: {
    //   maxWait: 10000,    // 10s max à attendre pour une connexion
    //   timeout: 30000,    // 30s max par transaction
    //   isolationLevel: 'ReadCommitted',
    // },
  });

// En dev, on réutilise l'instance pour éviter d'épuiser les connexions
// pendant le hot-reload
if (process.env.NODE_ENV !== 'production') {
  global.__prisma = prisma;
}

// Helper pour gérer les erreurs de connexion Neon (scale-to-zero)
// Les requêtes qui plantent avec P1001 (connection closed) sont retry-ées
export async function withRetry<T>(fn: () => Promise<T>, retries = 3): Promise<T> {
  let lastError: any;
  for (let i = 0; i < retries; i++) {
    try {
      return await fn();
    } catch (e: any) {
      lastError = e;
      // P1001 = connection closed, P1017 = server closed the connection
      // P1002 = connection timeout, P1015 = pool connection timeout
      if (e.code === 'P1001' || e.code === 'P1017' || e.code === 'P1002' || e.code === 'P1015') {
        console.warn(`[Prisma] Connection error (attempt ${i + 1}/${retries}): ${e.code} — retrying in 1s...`);
        await new Promise(resolve => setTimeout(resolve, 1000));
        continue;
      }
      throw e;
    }
  }
  throw lastError;
}

// Ping la BDD toutes les 30s pour maintenir la connexion (évite le scale-to-zero)
let keepaliveInterval: NodeJS.Timeout | null = null;
export function startKeepalive() {
  if (keepaliveInterval) return;
  keepaliveInterval = setInterval(async () => {
    try {
      await prisma.$queryRaw`SELECT 1`;
    } catch (e) {
      console.warn('[Prisma] Keepalive failed:', (e as Error).message);
    }
  }, 30_000);
  console.log('[Prisma] Keepalive started (every 30s)');
}

export function stopKeepalive() {
  if (keepaliveInterval) {
    clearInterval(keepaliveInterval);
    keepaliveInterval = null;
  }
}
