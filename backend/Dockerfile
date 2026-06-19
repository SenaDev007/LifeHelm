# LifeHelm Backend — Dockerfile multi-stage pour Railway
FROM node:20-slim AS base
WORKDIR /app

# 1. Build stage (avec devDependencies pour prisma + tsc)
FROM base AS builder
COPY package.json package-lock.json* ./
RUN npm ci
COPY . .
# Génère le client Prisma dans node_modules/@prisma/client
RUN npx prisma generate
# Compile TypeScript → dist/
RUN npx tsc -p .

# 2. Production stage (dependencies production uniquement + prisma CLI)
FROM base AS runner
ENV NODE_ENV=production

# Variables attendues (à passer au runtime via Railway dashboard)
ENV PORT=3001
ENV DATABASE_URL=""
ENV DIRECT_URL=""
ENV JWT_ACCESS_SECRET=""
ENV JWT_REFRESH_SECRET=""
ENV CORS_ORIGIN="*"
ENV FEDAPAY_SECRET_KEY=""
ENV FEDAPAY_BASE_URL="https://api.fedapay.com/v1"

# Copier package.json + installer deps prod + prisma CLI
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev && npm install prisma@^6.0.0 --no-save && npm cache clean --force

# Copier le code compilé + le schéma Prisma + le client généré
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/node_modules/@prisma ./node_modules/@prisma

# Healthcheck (Railway l'utilise pour savoir si l'app répond)
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD node -e "fetch('http://localhost:'+(process.env.PORT||3001)+'/health').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"

EXPOSE 3001

# Démarrage : 
# 1. Génère le client Prisma (rapide, ~1s)
# 2. Applique le schéma (idempotent, ~5-15s la 1ère fois)
# 3. Lance le serveur
CMD npx prisma generate && npx prisma db push --accept-data-loss && node dist/index.js
