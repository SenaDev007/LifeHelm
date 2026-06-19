# LifeHelm Backend — Dockerfile simple et robuste pour Railway
FROM node:20-slim

# OpenSSL requis par Prisma
RUN apt-get update && apt-get install -y openssl ca-certificates && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copier package.json + installer TOUTES les deps (incluant prisma CLI pour db push)
COPY backend/package.json backend/package-lock.json* ./
RUN npm ci

# Copier le code source + schema Prisma
COPY backend/ ./

# Générer le client Prisma + compiler TypeScript
RUN npx prisma generate
RUN npx tsc -p .

# Variables d'environnement (Railway les fournira)
ENV NODE_ENV=production
ENV PORT=3001
ENV HOST=0.0.0.0

EXPOSE 3001

# Healthcheck simple (le endpoint /health ne touche pas la BDD)
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=5 \
  CMD node -e "fetch('http://localhost:'+process.env.PORT+'/health').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"

# Démarrage : génère Prisma client (au cas où) + lance le serveur
CMD ["sh", "-c", "npx prisma generate && node dist/index.js"]
