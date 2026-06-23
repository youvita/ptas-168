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
│   ├── db/             Prisma schema, migrations, seed
│   ├── contracts/      Zod schemas + DTO types (single source of truth)
│   ├── sdk/            Frontend HTTP client + wire→UI adapters
│   └── bank-parsers/   Pure regex parsers for bank confirmation text
└── infrastructure/docker/   Docker Compose files (dev, prod) + Postgres 16 + Redis 7
```

Three Node runtimes share Postgres + Redis: **backend** (HTTP), **worker** (BullMQ consumer), **telegram-bot** (BullMQ consumer + Telegram polling). Cross-process traffic goes over Redis only — no app makes HTTP calls to another. The frontend is a static bundle the browser runs.

## Prerequisites

- **Node ≥ 20** and **pnpm 11.3** (via Corepack: `corepack enable`)
- **Docker Desktop** for the local Postgres + Redis stack
- macOS or Linux (Windows is unverified)

## Quickstart (native dev)

Apps run natively on your machine; only Postgres + Redis run in Docker.

```bash
pnpm install
pnpm db:up                                # start postgres + redis containers
pnpm db:migrate                           # apply schema
pnpm db:seed                              # bootstrap admin/admin123
```

Then run each process in its own terminal:

```bash
pnpm dev:backend                          # http://localhost:3001
pnpm dev:frontend                         # http://localhost:8080
pnpm --filter @ptas/worker dev            # BullMQ worker
pnpm --filter @ptas/telegram-bot dev      # grammY bot (stub mode w/o TELEGRAM_BOT_TOKEN)
```

Dev login: `admin` / `admin123`.

## Docker dev

Everything runs in Docker with hot reload via bind-mounted source code.

```bash
pnpm dev:docker:up                        # build + install deps + start all 6 containers
pnpm dev:docker:build                     # rebuild the dev image
pnpm dev:docker:logs                      # follow all logs
pnpm dev:docker:down                      # stop (data preserved)
pnpm dev:docker:install                   # re-run after adding/removing deps
pnpm dev:docker:psql                      # psql shell
pnpm dev:docker:reset                     # wipe everything (DB + Redis + node_modules)
```

Same ports as native dev (`:5432`, `:6379`, `:3001`, `:8080`) — stop one before starting the other. `pnpm db:up` (native dev) and `pnpm dev:docker:up` share this same compose file, so `db:up` just starts its `postgres` + `redis` services.

## Production (Docker)

Full stack in Docker with pre-built images. Uses different ports so it can run alongside dev.

```bash
# One-time setup
cp .env.production.example .env.production  # fill in POSTGRES_PASSWORD, JWT_SECRET, etc.
pnpm prod:build                             # build all Docker images

# Database setup
pnpm prod:migrate                           # prisma migrate deploy
pnpm prod:seed                              # seed admin user + system services

# Run
pnpm prod:up                                # start all 6 containers
pnpm prod:logs                              # follow all logs
pnpm prod:down                              # stop (data preserved)
pnpm prod:restart                           # restart all
pnpm prod:psql                              # psql shell into prod DB
```

### Port map

| Service  | Native dev | Docker dev | Production |
|----------|-----------|-----------|-----------|
| Postgres | `5432`    | `5432`    | `5433`    |
| Redis    | `6379`    | `6379`    | `6380`    |
| Backend  | `3001`    | `3001`    | `3101`    |
| Frontend | `8080`    | `8080`    | `8180`    |

## Common commands

```bash
# Infra (native dev) — starts Postgres + Redis from the dev compose file
pnpm db:up | db:down                      # start / stop postgres + redis
pnpm db:reset                             # down -v + up (wipes the dev volumes)
pnpm db:psql                              # psql shell
pnpm db:logs                              # follow container logs

# Prisma (delegates to @ptas/db)
pnpm db:generate                          # regenerate @prisma/client
pnpm db:migrate                           # prisma migrate dev
pnpm db:deploy                            # prisma migrate deploy (prod-safe)
pnpm db:studio                            # http://localhost:5555

# Build everything (turbo: db → contracts → sdk → bank-parsers → apps)
pnpm build

# Quality checks (the same ones CI gates deploys on)
pnpm -r --if-present typecheck            # tsc --noEmit across packages
pnpm --filter ptas168-backend test        # backend unit tests (vitest, Prisma-mocked)
```

## Environment

Two layers of env files, both gitignored:

- **Compose-level (production only)** — a repo-root `.env.production` (copy from `.env.production.example`), read by the `prod:*` scripts via `docker compose --env-file` to substitute `${VAR}` references in `docker-compose.production.yml`. Vars have sensible defaults via `${VAR:-default}`, so you only set what you override. The dev compose file uses hardcoded dev defaults, so `db:*` / `dev:docker:*` need no env file.
- **Per-process** — each app loads its own `.env.development` / `.env.production`. Required keys:

| Process       | Required keys                                                                |
|---------------|------------------------------------------------------------------------------|
| `@ptas/db`    | `DATABASE_URL` (for the Prisma CLI + seed scripts)                            |
| backend       | `DATABASE_URL`, `REDIS_URL`, `JWT_SECRET`, `TELEGRAM_BANK_BOT_TOKEN`           |
| worker        | `DATABASE_URL`, `REDIS_URL`, `OVERDUE_CRON`                                   |
| telegram-bot  | `DATABASE_URL`, `REDIS_URL`, `TELEGRAM_BOT_TOKEN` (leave empty for stub mode) |
| frontend      | `VITE_API_URL`, `VITE_FILE_URL` (build); `BACKEND_URL` (dev proxy target)     |

## Continuous integration

`.github/workflows/deploy-production.yml` runs on push to `main` (and manual dispatch) on the self-hosted runner. It has two jobs:

1. **`verify`** — `pnpm install` → `pnpm build` → `pnpm -r --if-present typecheck` → backend unit tests. Build breakage or type errors stop the pipeline here.
2. **`deploy`** — `needs: verify`, so it only runs if the gate passes: builds the production images, runs migrations + seed, restarts the stack, and health-checks the backend.

Lint and the frontend Playwright E2E suite are **not** in the gate yet — there's no ESLint config, and the E2E suite needs a `baseURL` fix. Widen the `verify` job once those are addressed.

## Per-app docs

- [apps/backend/CLAUDE.md](apps/backend/CLAUDE.md) — module pattern, adapters, JWT flow
- [apps/frontend/CLAUDE.md](apps/frontend/CLAUDE.md) — Zustand layout, routing, styling tokens
- [packages/contracts/CLAUDE.md](packages/contracts/CLAUDE.md) — extract rules + NodeNext quirk
- [MIGRATION_ANALYSIS.md](MIGRATION_ANALYSIS.md) — original Phase 1+2 inventory + asymmetric shape catalog
- [CLAUDE.md](CLAUDE.md) — top-level developer guide (read this before non-trivial changes)
