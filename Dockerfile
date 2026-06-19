# LifeHelm Backend — Dockerfile à la racine pour Railway
FROM node:20-slim

# OpenSSL + CA certs (requis par Prisma pour Neon)
RUN apt-get update && apt-get install -y openssl ca-certificates && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copier package.json + package-lock.json
COPY backend/package.json backend/package-lock.json* ./

# Installer TOUTES les deps (incluant devDeps pour prisma CLI + z-ai SDK)
RUN npm ci

# Copier le code source backend
COPY backend/ ./

# Générer le client Prisma + compiler TypeScript
RUN npx prisma generate
RUN npx tsc -p .

# Variables d'environnement (Railway les fournira au runtime)
ENV NODE_ENV=production
ENV PORT=8080

EXPOSE 8080

# Healthcheck : GET /health (ne touche pas la BDD)
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=5 \
  CMD node -e "fetch('http://localhost:'+process.env.PORT+'/health').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"

# Démarrage : génère Prisma client (rapide) + lance le serveur
CMD ["sh", "-c", "npx prisma generate && node dist/index.js"]
