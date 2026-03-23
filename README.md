# LifeHelm

Monorepo initial de LifeHelm (web + API + Prisma/PostgreSQL).

## Stack

- `apps/web`: Next.js (mobile-first, pages auth + mode accessible V1)
- `apps/api`: NestJS (health, auth JWT, endpoints mode accessible)
- `packages/database`: Prisma schema (modèles CDC) + seed

## Démarrage local

1. Installer les dépendances:
   - `pnpm install`
2. Copier les variables:
   - `.env.example` vers `.env`
   - `apps/web/.env.example` vers `apps/web/.env.local`
3. Démarrer PostgreSQL/Redis:
   - `docker compose -f docker-compose.dev.yml up -d`
4. Générer Prisma + migrer + seed:
   - `pnpm --filter @lifehelm/database prisma:generate`
   - `pnpm --filter @lifehelm/database prisma:migrate --name init`
   - `pnpm --filter @lifehelm/database prisma:seed`
5. Lancer API + Web:
   - `pnpm dev`

## Endpoints disponibles (V1)

- `GET /health`
- `POST /auth/register`
- `POST /auth/login`
- `POST /auth/refresh`
- `POST /auth/logout`
- `GET /auth/sessions`
- `GET /accessible/shop-log/today`
- `POST /accessible/shop-log`
- `PATCH /accessible/shop-log/:id`

## Écrans disponibles (V1)

- `/login`
- `/register`
- `/(accessible)/home`
- `/(accessible)/vente`
- `/(accessible)/depense`
- `/(accessible)/bilan`

