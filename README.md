# PTAS168

Property management system — Telegram Mini App + REST API. Unified monorepo for the two predecessor repos (`Ptas168_Backend`, `Ptas168_Frontend`) at https://github.com/4khmer.

## Layout

```
ptas168/
├── apps/
│   ├── backend/        Express + Prisma + Postgres — REST API on :3001
│   ├── frontend/       Vite + React 18 + Zustand — Mini App on :8080
│   ├── worker/         BullMQ jobs (overdue cron + invoice-paid)
│   └── telegram-bot/   grammY long-polling + BullMQ consumer
├── packages/
│   ├── db/             Prisma schema, migrations, seeds
│   ├── contracts/      Zod schemas + DTO types (single source of truth)
│   ├── sdk/            Frontend HTTP client + wire→UI adapters
│   └── bank-parsers/   Pure regex parsers for bank confirmation text
└── infrastructure/docker/   Postgres 16 + Redis 7 for local dev
```

Three Node runtimes share Postgres + Redis: **backend** (HTTP), **worker** (BullMQ consumer), **telegram-bot** (BullMQ consumer + Telegram polling). Cross-process traffic goes over Redis only — no app makes HTTP calls to another. The frontend is a static bundle the browser runs.

## Prerequisites

- **Node ≥ 20** and **pnpm 11.3** (via Corepack: `corepack enable`)
- **Docker Desktop** for the local Postgres + Redis stack
- macOS or Linux (Windows is unverified)

## Quickstart

```bash
pnpm install
pnpm db:up                                # start postgres + redis
pnpm db:migrate                           # apply schema
pnpm db:seed                              # bootstrap admin/admin123
pnpm db:demo-seed                         # demo dataset (optional)
```

Then run each process in its own terminal:

```bash
pnpm dev:backend                          # http://localhost:3001
pnpm dev:frontend                         # http://localhost:8080/Ptas168_Frontend/
pnpm --filter @ptas/worker dev            # BullMQ worker
pnpm --filter @ptas/telegram-bot dev      # grammY bot (stub mode w/o TELEGRAM_BOT_TOKEN)
```

Dev login: `admin` / `admin123`. **Do not ship the seed user to production** — `db:seed` is guarded against `NODE_ENV=production`.

## Common commands

```bash
# Infra
pnpm db:up | db:down | db:reset           # docker compose
pnpm db:psql                              # psql shell
pnpm db:logs                              # follow container logs

# Prisma (delegates to @ptas/db)
pnpm db:generate                          # regenerate @prisma/client
pnpm db:migrate                           # prisma migrate dev
pnpm db:deploy                            # prisma migrate deploy (prod-safe)
pnpm db:studio                            # http://localhost:5555

# Build everything (turbo: db → contracts → sdk → bank-parsers → apps)
pnpm turbo run build
```

## Environment

Each process loads its own `.env.development` / `.env.production` (gitignored). Required keys:

| Process       | Required keys                                                                |
|---------------|------------------------------------------------------------------------------|
| `@ptas/db`    | `DATABASE_URL` (for the Prisma CLI + seed scripts)                            |
| backend       | `DATABASE_URL`, `REDIS_URL`, `JWT_SECRET`, `TELEGRAM_BANK_BOT_TOKEN`           |
| worker        | `DATABASE_URL`, `REDIS_URL`, `OVERDUE_CRON`                                   |
| telegram-bot  | `DATABASE_URL`, `REDIS_URL`, `TELEGRAM_BOT_TOKEN` (leave empty for stub mode) |
| frontend      | `VITE_API_URL`, `VITE_FILE_URL`                                               |

## CI/CD

GitHub Actions at [`.github/workflows/ci-cd.yml`](.github/workflows/ci-cd.yml):

| Event | What runs |
|-------|-----------|
| Pull request | CI — `pnpm install`, Prisma generate, turbo build, backend tests |
| Push to `main` (or **Run workflow**) | CI, then deploy on the self-hosted Mac Mini, then a Telegram status message |

Deploy syncs the built monorepo to `$HOME/apps/Ptas168`, writes each process's `.env.production` from GitHub secrets, applies Prisma migrations, reloads PM2 (`ptas168-api`, `ptas168-worker`, `ptas168-telegram-bot`), and rsyncs the Vite `dist/` to Tomcat `ROOT` (override with the `FRONTEND_DEPLOY_DIR` variable). Seed is **not** run — `pnpm db:seed` is blocked in production.

### GitHub secrets

| Secret | Required | Used by |
|--------|----------|---------|
| `DATABASE_URL` | yes | backend, worker, telegram-bot, Prisma migrate |
| `REDIS_URL` | yes | backend, worker, telegram-bot |
| `JWT_SECRET` | yes | backend (≥ 32 chars) |
| `TELEGRAM_BOT_TOKEN` | yes | Mini App / grammY bot, and deploy Telegram notify |
| `TELEGRAM_CHAT_ID` | no* | chat/group that receives deploy success/failure |
| `TELEGRAM_BANK_BOT_TOKEN` | no | backend bank-ingest webhook |
| `TELEGRAM_BANK_WEBHOOK_SECRET` | no | backend bank-ingest webhook |
| `R2_ACCOUNT_ID` / `R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY` / `R2_BUCKET` / `R2_PUBLIC_URL` | no | backend uploads (disk fallback if unset) |

\*Notify is skipped (deploy still succeeds) if `TELEGRAM_CHAT_ID` is missing.

### GitHub variables (optional overrides)

| Variable | Default |
|----------|---------|
| `CORS_ORIGIN` | `https://ptas168.kilozin.xyz` |
| `VITE_API_URL` | `https://ptas168.kilozin.xyz/api` |
| `VITE_FILE_URL` | `https://cdn.kilozin.xyz` |
| `FILE_URL_BASE` | `https://cdn.kilozin.xyz` |
| `API_BASE_PATH` | `/api` |
| `FRONTEND_DEPLOY_DIR` | `/usr/local/Cellar/tomcat@10/10.1.52/libexec/webapps/ROOT` |

The self-hosted runner needs Node-capable `actions/setup-node`, pnpm via Corepack, global `pm2`, rsync, and the Tomcat webapps path (or `FRONTEND_DEPLOY_DIR`). Postgres + Redis must already be reachable at `DATABASE_URL` / `REDIS_URL`.

## Per-app docs

- [apps/backend/CLAUDE.md](apps/backend/CLAUDE.md) — module pattern, adapters, JWT flow
- [apps/frontend/CLAUDE.md](apps/frontend/CLAUDE.md) — Zustand layout, routing, styling tokens
- [packages/contracts/CLAUDE.md](packages/contracts/CLAUDE.md) — extract rules + NodeNext quirk
- [MIGRATION_ANALYSIS.md](MIGRATION_ANALYSIS.md) — original Phase 1+2 inventory + asymmetric shape catalog
- [CLAUDE.md](CLAUDE.md) — top-level developer guide (read this before non-trivial changes)
