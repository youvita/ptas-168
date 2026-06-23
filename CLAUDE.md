# CLAUDE.md

This file is auto-loaded into Claude's context. Sub-app `CLAUDE.md` files are **not** auto-loaded — read them on demand when the work touches that app.

## Project

**PTAS168** — Property management system (Telegram Mini App + REST API). Originally two private repos under the `4khmer` GitHub org, unified into this Turborepo monorepo at https://github.com/4khmer/Ptas168.

## Layout

```
ptas168/
├── apps/
│   ├── backend/                    Express + TypeScript + Prisma 5 + PostgreSQL — :3001
│   │   └── CLAUDE.md               READ THIS before touching backend code
│   ├── frontend/                   Vite + React 18 + Zustand (TypeScript) — :8080
│   │   └── CLAUDE.md               READ THIS before touching frontend code
│   ├── worker/                     BullMQ jobs: cron + event-driven (no HTTP surface)
│   └── telegram-bot/               grammy long-polling + BullMQ consumer (no HTTP surface)
├── packages/
│   ├── db/                         @ptas/db — Prisma schema + migrations + seeds (single owner of the DB layer)
│   ├── contracts/                  @ptas/contracts — Zod schemas + TS types (pure, no logic)
│   │   └── CLAUDE.md               extract rules + NodeNext quirk
│   ├── sdk/                        @ptas/sdk — frontend's typed HTTP client + adapters
│   └── bank-parsers/               @ptas/bank-parsers — pure bank-text parsers (ABA, …)
├── infrastructure/
│   └── docker/
│       ├── docker-compose.dev.yml         dev stack (hot-reload); db:* starts its Postgres 16 + Redis 7
│       └── docker-compose.production.yml  production stack (built images, migrate + seed)
├── pnpm-workspace.yaml
├── turbo.json
├── MIGRATION_ANALYSIS.md           Phase 1+2 inventory (still useful as a map)
└── package.json
```

Three runtime processes share Postgres + Redis: **backend** (HTTP), **worker** (BullMQ consumer), **telegram-bot** (BullMQ consumer + Telegram polling). The frontend is a static bundle the browser runs.

## Commands you'll use most

```bash
# infra (docker)
pnpm db:up                                # start postgres + redis containers
pnpm db:down                              # stop (data preserved in named volumes)
pnpm db:reset                             # nuke volumes + restart
pnpm db:psql                              # psql shell into the docker DB
pnpm db:logs                              # follow container logs

# prisma (delegates to @ptas/db; schema + migrations live there)
pnpm db:generate                          # regenerate @prisma/client from schema.prisma
pnpm db:migrate                           # prisma migrate dev (create + apply)
pnpm db:deploy                            # prisma migrate deploy (prod-safe)
pnpm db:studio                            # http://localhost:5555
pnpm db:seed                              # bootstrap admin user + system services + settings

# dev — each process in its own terminal
pnpm dev:backend                          # api on http://localhost:3001
pnpm dev:frontend                         # vite on http://localhost:8080/
pnpm --filter @ptas/worker dev            # BullMQ worker (overdue cron + invoice-paid)
pnpm --filter @ptas/telegram-bot dev      # grammy bot (stub mode without TELEGRAM_BOT_TOKEN)

# build everything (turbo orchestrates db → contracts → sdk → bank-parsers → apps)
pnpm turbo run build
```

## Dev login

`admin` / `admin123` (seeded by `pnpm db:seed`). **Do not ship this to production** — `db:seed` is guarded against `NODE_ENV=production`.

## Environment

- pnpm 11.3 via Corepack (Node ≥ 20)
- `gh` CLI authenticated as `KheangZinII` — `gh repo clone 4khmer/<name>` works for the org's private repos
- Docker Desktop required for the local DB stack
- **Env files per process** (each loads `.env.development` / `.env.production` based on `NODE_ENV`):
  - [packages/db/.env](packages/db/.env) — `DATABASE_URL` for the Prisma CLI + seed scripts (gitignored)
  - [apps/backend/.env.development](apps/backend/.env.development) — `DATABASE_URL`, `REDIS_URL`, `JWT_SECRET`, `TELEGRAM_BANK_BOT_TOKEN`, …
  - [apps/worker/.env.development](apps/worker/.env.development) — `DATABASE_URL`, `REDIS_URL`, `OVERDUE_CRON`
  - [apps/telegram-bot/.env.development](apps/telegram-bot/.env.development) — `DATABASE_URL`, `REDIS_URL`, `TELEGRAM_BOT_TOKEN` (leave empty for stub mode)
  - [apps/frontend/.env.production](apps/frontend/.env.production) — `VITE_API_URL`, `VITE_FILE_URL`

## Current architecture (post-migration)

| Layer | Package/App | What it does |
|---|---|---|
| Database layer | `@ptas/db` | Owns `prisma/schema.prisma`, migrations, seed. Apps that touch the DB depend on this (each app still instantiates its own `PrismaClient` for connection-pool tuning, but the schema and generated client are shared via pnpm-hoisted `@prisma/client`). |
| Wire-format contracts | `@ptas/contracts` | All Zod schemas + DTO types. **No logic.** Both reads and writes flow through these. |
| HTTP client | `@ptas/sdk` | The frontend's only path to the backend. Wraps fetch, owns the 3 wire→UI adapters (`adaptInvoice`, `groupMeterReadings`, `parseInvoiceSettings`). ESM. |
| Bank parsers | `@ptas/bank-parsers` | Pure regex-based parsers for bank confirmation text. Shared by backend (`/api/bank-payments` list) and bot (raw-message ingestion). |
| API | `apps/backend` | Express + Prisma. Reads/writes the DB. Mints Telegram link codes to Redis. Enqueues BullMQ jobs. **No Telegram credentials.** |
| Async jobs | `apps/worker` | Two BullMQ workers: `overdue-check` (cron, default 09:00 daily) and `invoice-paid` (event-driven from backend). The only notification producer in the system. |
| Telegram | `apps/telegram-bot` | grammy long-polling. Consumes `telegram-send` BullMQ queue for outbound. Owns its own Prisma client. Owns the bot token. |
| Web | `apps/frontend` | Vite + React 18 + Zustand. No validation libs except Zod (via `@ptas/contracts` schemas in modal forms). |
| DB + queues | `infrastructure/docker` | Postgres 16 + Redis 7 with named volumes, healthchecks, 127.0.0.1-bound. |

Cross-process communication is **Redis only** (BullMQ queues + the `tg:link-code:*` / `tg:notify-code:*` keys). No process makes HTTP calls to another.

## Hard constraints (load-bearing — repeat for every change)

- **Do not** break either app
- **Do not** rewrite business logic
- **Do not** change Prisma schema unnecessarily
- Every change must keep all processes runnable; migrations are **incremental and reversible**

## Never confuse the apps

Five distinct runtime contexts, two distinct languages. Before editing code, **always know which app you're in.** When a request is ambiguous, state the assumption explicitly and confirm before changing anything.

### At-a-glance contrast

|  | `apps/backend` | `apps/frontend` | `apps/worker` | `apps/telegram-bot` |
|---|---|---|---|---|
| Language | **TypeScript** strict | **TypeScript** (.ts/.tsx) | TypeScript | TypeScript |
| Module system | ESM (NodeNext) | ESM (bundler) | ESM (NodeNext) | ESM (NodeNext) |
| Runtime | Node ≥ 20 (Express) | Browser (Vite) | Node ≥ 20 (BullMQ) | Node ≥ 20 (grammy + BullMQ) |
| Persistence | Postgres via Prisma | localStorage + Zustand | Postgres + Redis | Postgres + Redis |
| Port | `:3001` | `:8080` (base `/`) | none (no HTTP) | none (no HTTP) |
| Entry | [src/server.ts](apps/backend/src/server.ts) | [src/main.tsx](apps/frontend/src/main.tsx) | [src/index.ts](apps/worker/src/index.ts) | [src/index.ts](apps/telegram-bot/src/index.ts) |

### Where each concept lives — never mix these up

| Concept | Lives **only** in |
|---|---|
| Prisma schema, migrations, seeds | `packages/db/prisma/` (run via `pnpm db:migrate`, `pnpm db:seed`, etc.) |
| `@prisma/client` DB queries | `apps/backend/src/modules/<domain>/<domain>.repository.ts`, plus `apps/worker/src/` and `apps/telegram-bot/src/` for those processes |
| Wire types + Zod schemas | `packages/contracts/src/*.ts` (single source of truth for both ends) |
| HTTP route handlers, controllers, services | `apps/backend/src/modules/<domain>/` |
| JWT signing / `Bearer` verification | `apps/backend/src/utils/jwt.ts` + middleware |
| **Prisma row → wire DTO** adapters | `apps/backend/src/utils/adapters.ts` |
| **Wire DTO → UI shape** adapters | `packages/sdk/src/adapters/` (`adaptInvoice`, `groupMeterReadings`, `parseInvoiceSettings`) |
| Frontend HTTP wrapper | `packages/sdk/src/http/client.ts` + `apps/frontend/src/sdk.js` (consumer init) |
| Zustand store | `apps/frontend/src/store/index.js` |
| Page components, modals, UI primitives | `apps/frontend/src/{pages,components}/` |
| Form validation | each modal in `apps/frontend/src/components/modals/` imports from `@ptas/contracts` |
| Tailwind tokens, CSS variables | `apps/frontend/tailwind.config.js`, `apps/frontend/src/index.css` |
| `pbms_token` (JWT) read/write | `apps/frontend/src/sdk.js` (only here) |
| Vite config, dev proxy | `apps/frontend/vite.config.js` |
| BullMQ job processors | `apps/worker/src/jobs/` (overdue, invoice-paid) and `apps/telegram-bot/src/queues/` (telegram-send) |
| BullMQ producers (enqueue) | `apps/backend/src/lib/queue.ts` |
| Bank confirmation parsing | `packages/bank-parsers/src/` |
| Telegram link-code mint | `apps/backend/src/modules/telegramLinks/telegramLinks.service.ts` (writes to Redis) |
| Telegram link-code consume | `apps/telegram-bot/src/lib/link-codes.ts` (atomic GETDEL on Redis) |
| Grammy handlers (`/link`, `/pay`, raw text) | `apps/telegram-bot/src/bot.ts` |

### Forbidden imports

- Files under `apps/frontend/` **never** import from `apps/backend/`, `apps/worker/`, or `apps/telegram-bot/`.
- Files under `apps/backend/` **never** import from any other `apps/*`.
- `apps/worker/` and `apps/telegram-bot/` may share **packages/** but never import from each other or from `apps/backend`.
- All apps may import from `packages/*` (contracts, sdk, bank-parsers).
- `packages/contracts` **never** imports from `apps/*` or any framework (Prisma, Express, React, grammy, BullMQ).
- `packages/bank-parsers` **never** imports anything except `./types.js` — must stay pure.

### Triple-shape entities — name the shape you mean

The same domain concept exists in three forms. Always say which:

| Shape | Where | Example |
|---|---|---|
| **Prisma model** | `apps/backend/prisma/schema.prisma` | `Invoice.pricePerMonth`, `Tenant.photoUrl`, `Contract.startDate` |
| **Wire DTO** | what the backend emits, defined in `@ptas/contracts` and built by `apps/backend/src/utils/adapters.ts` | `Room.price`, `Tenant.photo`, `Contract.startDate` |
| **UI shape** | what `apps/frontend` consumes after the SDK's adapters run | `Invoice.tenantSnapshot/roomSnapshot/total`, grouped meter readings |

Some entities have a **write input shape** distinct from the read shape — tenants use `fullName`/`profilePhotoUrl` on `POST`, but `name`/`photo` on the response. Same for rooms (`pricePerMonth` ↔ `price`) and contracts (`moveInDate` ↔ `startDate`). See [MIGRATION_ANALYSIS.md §5](MIGRATION_ANALYSIS.md) and the `*Input` / `*Dto` paired exports in `packages/contracts/`.

### When the request is ambiguous

1. **State the assumption** ("I read this as a frontend issue because the symptom is in the UI — confirm?")
2. **Don't touch code yet** until they confirm or redirect
3. For data-flow bugs, **trace the call path** (frontend page → store action → `sdk.js` → backend route → repository → DB) and identify *where* the problem is before deciding *what* to change

### One real example — the Billing empty-list bug

The user reported "Billing displays count but no data." The instinct could be to check backend (`/invoices/page` query). But the backend was fine: the bug was a stale `loading: true` flag in [apps/frontend/src/store/index.js](apps/frontend/src/store/index.js) that `resetPagedInvoices` failed to clear. **Frontend bug, frontend fix.** Diagnosing meant first verifying the backend returned data (it did via curl), then driving the frontend with Playwright to find where the state diverged. Always confirm which side before patching.

## Codebase quirks worth knowing upfront

- **Asymmetric write/read shapes** on the wire — `POST /tenants` takes `fullName`/`profilePhotoUrl`, response returns `name`/`photo`. Same for rooms and contracts. Each affected entity in `@ptas/contracts` has paired `Create<X>Input` (write) and `<X>Dto` (read) exports.
- **All packages + apps are ESM** (`"type": "module"`). NodeNext requires relative imports to use `.js` extensions in TS source (`import { foo } from './bar.js'` even though the file is `bar.ts`). This is mechanical — match the surrounding code.
- **One CJS-typed dep needs special handling** — `pino-http` v10 ships a `.d.ts` without a default export, so `import pinoHttp from 'pino-http'` fails type-check under NodeNext+ESM. [apps/backend/src/middleware/request-logger.ts](apps/backend/src/middleware/request-logger.ts) goes through `createRequire` to get the runtime callable while keeping types via `import type { Options, HttpLogger }`. Other CJS deps (express, helmet, etc.) work fine because their types are correct.
- **Telegram link codes share via Redis** — backend mints codes into `tg:link-code:<code>` (and `tg:notify-code:<code>`); the bot atomically consumes via `GETDEL`. **No in-memory state.** If you change the code-mint TTL in the backend, also update the messaging in [apps/telegram-bot/src/bot.ts](apps/telegram-bot/src/bot.ts).
- **No notifications without the worker.** The backend never writes to the `notifications` table — only `apps/worker` does (via `daily-overdue-check` and `invoice-paid` handlers). If you're testing notifications locally, the worker must be running.
- **Bot stub mode** — when `TELEGRAM_BOT_TOKEN` is empty, `apps/telegram-bot` skips grammy polling but still consumes the BullMQ `telegram-send` queue (logs "would have sent"). Useful for local dev without @BotFather.
- **`tsx watch`** picks up `.env` file changes — the dev backend hot-reloads on env edits, occasionally leaving stuck `node` processes on port 3001 (`pkill -f tsx` to clear).
- **Vite base path is `/`** ([apps/frontend/vite.config.ts](apps/frontend/vite.config.ts)) — the app serves from the root in both dev and the production bundle. (It historically served under `/Ptas168_Frontend/`; that prefix is gone.)

## When in doubt — read the per-app docs

| Where | What you'll find there |
|---|---|
| [apps/backend/CLAUDE.md](apps/backend/CLAUDE.md) | module pattern, adapters, JWT/auth flow, business rules |
| [apps/frontend/CLAUDE.md](apps/frontend/CLAUDE.md) | Zustand store layout, routing, styling tokens |
| [packages/contracts/CLAUDE.md](packages/contracts/CLAUDE.md) | extract rules + the NodeNext `.js` import quirk |
| [apps/worker/](apps/worker/) | inline comments on the 2 job processors |
| [apps/telegram-bot/](apps/telegram-bot/) | inline comments on grammy handlers and queue consumer |
| [MIGRATION_ANALYSIS.md](MIGRATION_ANALYSIS.md) | original Phase 1+2 inventory, asymmetric shape catalog, priority lists |
