#!/bin/sh
# Start script pour Railway avec logs détaillés
set -e

echo "=========================================="
echo "LifeHelm Backend — Starting"
echo "=========================================="
echo "NODE_ENV: $NODE_ENV"
echo "PORT: $PORT"
echo "DATABASE_URL: ${DATABASE_URL:+✓ set}${DATABASE_URL:-✗ MISSING}"
echo "DIRECT_URL: ${DIRECT_URL:+✓ set}${DIRECT_URL:-✗ MISSING}"
echo "JWT_ACCESS_SECRET: ${JWT_ACCESS_SECRET:+✓ set}${JWT_ACCESS_SECRET:-✗ MISSING}"
echo "JWT_REFRESH_SECRET: ${JWT_REFRESH_SECRET:+✓ set}${JWT_REFRESH_SECRET:-✗ MISSING}"
echo "CORS_ORIGIN: ${CORS_ORIGIN:-*}"
echo ""

cd /app

echo "→ Generating Prisma client..."
npx prisma generate

echo "→ Pushing schema to database (idempotent, may take 5-15s on first run)..."
npx prisma db push --accept-data-loss || echo "⚠️ db push failed (continuing anyway)"

echo "→ Starting server..."
exec node dist/index.js
