# CLAUDE.md

Backend for the Ptas168 Property Management System — TypeScript / Express / Prisma / PostgreSQL.

## Commands

```bash
npm run dev              # tsx watch — auto-reload on changes
npm run build            # tsc → dist/
npm run start            # node dist/server.js (after build)
npm test                 # Vitest one-shot
npm run test:watch       # Vitest watch mode
npm run prisma:migrate   # prisma migrate dev (create + apply migration)
npm run prisma:deploy    # prisma migrate deploy (production-safe)
npm run prisma:generate  # regenerate Prisma client
npm run prisma:studio    # GUI for the dev DB
```

## Architecture

**Module pattern:** every domain owns a folder under [`src/modules/`](src/modules/) with five files:

```
modules/<domain>/
  <domain>.routes.ts        Express Router; mounts at /api/<plural>
  <domain>.controller.ts    Thin: parse request, call service, return response
  <domain>.service.ts       Business logic; never imports Prisma directly
  <domain>.repository.ts    Owns all Prisma queries for this domain
  <domain>.schema.ts        Zod schemas (.strict() — unknown fields rejected)
```

`controller → service → repository → Prisma`. Services depend on repositories, never on each other's Prisma layer. Cross-domain composition happens at the service layer (e.g. `contracts.service` calls `tenantsRepository`).

**Adapter layer:** [`src/utils/adapters.ts`](src/utils/adapters.ts) maps Prisma rows → frontend-shaped DTOs. Field names mirror the frontend store *exactly* (camelCase, `name` not `fullName`, `photo` not `photoUrl`, etc.). Backend never reshapes per-call — it always goes through an adapter.

**Auth flow:** `validateTelegramInitData()` in [`src/modules/auth/telegram-validator.ts`](src/modules/auth/telegram-validator.ts) does HMAC-SHA256 with constant-time comparison. After validation, the user is upserted by `telegramId` and a JWT is signed (24h, payload `{ userId, role, telegramId }`). The frontend stores it as `pbms_token` in `localStorage` and sends it as `Authorization: Bearer <jwt>`.

**Errors:** custom hierarchy in [`src/utils/errors.ts`](src/utils/errors.ts) (`AppError` → `ValidationError`, `UnauthorizedError`, `ForbiddenError`, `NotFoundError`, `ConflictError`). The error handler in [`src/middleware/error-handler.ts`](src/middleware/error-handler.ts) catches them, plus Zod `ZodError` and Prisma `PrismaClientKnownRequestError`, and returns a uniform `{ error: { code, message, details? } }` shape. Stacks are stripped in production.

**Logging:** pino with pretty-print in dev, JSON in prod. `pino-http` adds a request-id header (`x-request-id`) and logs every request with status + duration.

## Endpoints

All endpoints under `/api`. See [README.md § Frontend Contract](README.md#frontend-contract) for the full list with request/response shapes.

| Domain | Routes |
|---|---|
| Health | `GET /health`, `GET /health/db` |
| Auth | `POST /auth/login`, `POST /auth/telegram`, `POST /auth/logout`, `GET/PATCH /auth/me`, `POST /auth/password` |
| Buildings | `GET/POST /buildings`, `PATCH/DELETE /buildings/:id` |
| Floors | `POST /buildings/:buildingId/floors`, `GET/PATCH/DELETE /floors[/:id]` |
| Rooms | `POST /floors/:floorId/rooms`, `GET /rooms`, `GET/PATCH/DELETE /rooms/:id` |
| Tenants | `GET/POST /tenants`, `GET /tenants/lookup?phone=`, `PATCH /tenants/:id` |
| Contracts | `POST /rooms/:roomId/contracts`, `GET/PATCH /contracts[/:id]`, `POST /contracts/:id/terminate` |
| Room services | `GET/PUT /rooms/:roomId/services` |
| Meter readings | `GET/POST /rooms/:roomId/meter-readings`, `GET .../latest` |
| Invoices | `GET/POST /invoices`, `GET /invoices/:id`, `POST /invoices/:id/pay`, `POST /invoices/:id/cancel` |
| Service fees | `GET/POST /service-fees`, `PATCH/DELETE /service-fees/:id` |
| Settings | `GET/PATCH /settings` |
| Sub-users | `GET/POST /users`, `PATCH/DELETE /users/:id` (manager+ only) |
| Notifications | `GET /notifications`, `POST /notifications/:id/read`, `POST /notifications/read-all`, `DELETE /notifications` |

## Code conventions

- **TypeScript strict mode**, no `any`, no `as` assertions outside narrow type-narrowing in error handlers
- **Env access** only through the typed `env` object in [`src/config/env.ts`](src/config/env.ts) — never `process.env` directly elsewhere
- **Validation** at the controller boundary via Zod schemas with `.strict()` — unknown fields are rejected with 400
- **Async handlers** wrapped with [`asyncHandler`](src/middleware/async-handler.ts) so rejected promises hit the error middleware
- **No `console.log`** — always pino (`logger.info`, `logger.error`, etc.)
- **Field names** in responses match what the frontend store consumes (don't rename fields without updating the frontend in lockstep)

## Business rules implemented

- Adding a tenant to a room (`POST /rooms/:roomId/contracts`) auto-activates the room's Water + Electricity room services in a single transaction. Tenants are de-duplicated by phone.
- An `in_progress` invoice with a past `dueDate` is reported as `overdue` on read (derived, not persisted).
- Water/Electricity master service fees are seeded as non-deletable; the delete endpoint returns 403 for them.
- Invoice numbering: `INV-YYYYMM-NNNNNN`, where `NNNNNN` is a zero-padded global counter and the digit count is configurable via the `INVOICE_NO_DIGITS` setting.
- Sub-users (`/users`) require role `owner` or `manager`.

## Local DB setup (one-time)

```bash
createdb ptas168_dev
cp .env.example .env.development
# edit JWT_SECRET + TELEGRAM_BOT_TOKEN
npm install
npm run prisma:migrate -- --name init
npm run dev
```

The dev server listens on `http://localhost:3001`. The frontend's Vite dev server (`:8080`) proxies `/api/*` to it — see [apps/frontend/vite.config.ts](../frontend/vite.config.ts).

## Testing

`tests/setup.ts` injects test env vars. Tests that touch the DB layer use Vitest module mocks against `src/lib/prisma`, so no live Postgres is required to run `npm test`.

The Telegram validator has a full happy-path + tampering + expiry suite. Auth controller has login + 401 + me. Buildings has list + create + strict-field-rejection (the same pattern can be replicated for any domain module).
