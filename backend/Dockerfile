# LifeHelm Backend — Dockerfile optimisé pour Railway
FROM node:20-slim AS base
WORKDIR /app

# 1. Build stage
FROM base AS builder
COPY package.json package-lock.json* ./
RUN npm ci
COPY . .
RUN npx prisma generate
RUN npx tsc -p .

# 2. Production stage
FROM base AS runner
ENV NODE_ENV=production

ENV PORT=3001
ENV DATABASE_URL=""
ENV DIRECT_URL=""
ENV JWT_ACCESS_SECRET=""
ENV JWT_REFRESH_SECRET=""
ENV CORS_ORIGIN="*"
ENV FEDAPAY_SECRET_KEY=""
ENV FEDAPAY_BASE_URL="https://api.fedapay.com/v1"

# Install prod deps + prisma CLI
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev && npm install prisma@^6.0.0 --no-save && npm cache clean --force

# Copy built artifacts + Prisma client + schema
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/node_modules/@prisma ./node_modules/@prisma
COPY --from=builder /app/node_modules/z-ai-web-dev-sdk ./node_modules/z-ai-web-dev-sdk

# Healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD node -e "fetch('http://localhost:'+(process.env.PORT||3001)+'/health').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"

EXPOSE 3001

# Démarrage simple : génère le client Prisma (~1s) et lance le serveur
# Le schéma BDD doit être appliqué manuellement via: npx prisma db push
CMD npx prisma generate && node dist/index.js
