# LifeHelm Backend — Dockerfile Railway avec logs détaillés
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

# Install prod deps + prisma CLI + z-ai SDK
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev && npm install prisma@^6.0.0 --no-save && npm cache clean --force

# Copy built artifacts
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/node_modules/@prisma ./node_modules/@prisma
COPY --from=builder /app/node_modules/z-ai-web-dev-sdk ./node_modules/z-ai-web-dev-sdk

# Copy start script
COPY start.sh ./
RUN chmod +x start.sh

# Healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=5 \
  CMD node -e "fetch('http://localhost:'+(process.env.PORT||3001)+'/health').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"

EXPOSE 3001

# Start avec logs détaillés des variables
CMD ["./start.sh"]
