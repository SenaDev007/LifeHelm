# LifeHelm Backend — Dockerfile multi-stage
FROM node:20-slim AS base
WORKDIR /app

# 1. Dependencies
FROM base AS deps
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev && npm cache clean --force

# 2. Build
FROM base AS builder
COPY package.json package-lock.json* ./
RUN npm ci
COPY . .
RUN npx prisma generate
RUN npx tsc -p .

# 3. Production
FROM base AS runner
ENV NODE_ENV=production

# Variables attendues (à passer au runtime)
ENV PORT=3001
ENV DATABASE_URL=""
ENV DIRECT_URL=""
ENV JWT_ACCESS_SECRET=""
ENV JWT_REFRESH_SECRET=""
ENV CORS_ORIGIN="*"
ENV FEDAPAY_SECRET_KEY=""
ENV FEDAPAY_BASE_URL="https://api.fedapay.com/v1"

# Copier node_modules, dist, prisma schema, package.json
COPY --from=deps /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/package.json ./

# Healthcheck
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://localhost:'+(process.env.PORT||3001)+'/health').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"

EXPOSE 3001

# Démarrage: applique le schéma Prisma au démarrage (idempotent) puis lance le serveur
CMD npx prisma db push --accept-data-loss && node dist/index.js
