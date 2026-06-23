# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
pnpm dev          # Vite dev server on http://localhost:8080/ (base path is `/`)
pnpm build        # Production build → /dist (vite build — does NOT run tsc)
pnpm preview      # Preview the production build
pnpm typecheck    # tsc --noEmit (the type gate; build skips it)
pnpm test         # Playwright E2E (tests/*.test.js)
```

The package name is `pbms-app`; from the repo root use `pnpm dev:frontend`.
**TypeScript** throughout (`.ts`/`.tsx`) — the JS→TS migration is complete, there are no `.js`/`.jsx` files under `src/`. No ESLint config is set up yet; `tsc` does the static checking.

## Architecture

**Telegram Mini App** — React 18 SPA with a 430px max-width mobile viewport. All pages are functional components using hooks. ESM, bundled by Vite.

### State

All application state lives in a single Zustand store at [`src/store/index.ts`](src/store/index.ts). The store is **API-driven** — every CRUD action calls the backend through the SDK, and caches successful responses so reads stay synchronous.

- The only path to the backend is [`src/sdk.ts`](src/sdk.ts), which initializes [`@ptas/sdk`](../../packages/sdk/) (`createSdk`) and re-exports per-domain clients (`authApi = sdk.auth`, `buildingsApi = sdk.buildings`, …) that the store calls.
- `@ptas/sdk` owns the HTTP wrapper (`Authorization: Bearer <token>`, JSON parsing, 401 auto-logout) **and** the three wire→UI adapters — `adaptInvoice`, `groupMeterReadings`, `parseInvoiceSettings`. The frontend does **not** reshape DTOs itself.
- JWT is stored in `localStorage` under `pbms_token` — read/written **only** in [`src/sdk.ts`](src/sdk.ts) (`TOKEN_KEY`).
- API base URL is `import.meta.env.VITE_API_URL ?? '/api'`. In dev, `/api/*` is proxied to `BACKEND_URL` (default `http://localhost:3001`) — see [vite.config.ts](vite.config.ts).
- Login flow: `loginWithCredentials` / `loginWithTelegram` → store token → `loadInitialData()` populates buildings/rooms/services/settings in parallel.

### Routing

[`src/App.tsx`](src/App.tsx) defines two layouts:
- `<AppLayout>` (bottom nav) wraps the four main tabs: Rooms, Tenants, Billing, More
- Detail/form pages render without the nav bar

Unauthenticated users are redirected to `/login` via a `useStore(s => s.isLoggedIn)` guard.

### Key utilities (`src/lib/`)

| File | Purpose |
|---|---|
| `billing.ts` | Invoice calculations (rent, utilities, fixed services) |
| `dayCounter.ts` | Monthly billing cycle logic and DayRing coloring |
| `date.ts` | Date formatting/parsing helpers |
| `i18n.ts` | UI string localization |
| `khqr.ts` / `qr.ts` | KHQR payment-string + QR generation/scanning |
| `image.ts` | Client-side image resize/compression for uploads |
| `phone.ts` | Phone-number normalization |

### Styling

Tailwind CSS with a custom palette in [`tailwind.config.js`](tailwind.config.js) and CSS variables in [`src/index.css`](src/index.css). Color tokens: `pr`, `pl`, `tx`, `su`, `bd`, `re`, `am`, `gr`, `info`. Icons via `lucide-react`.

### Component conventions

- Reusable UI primitives live in `src/components/ui/`
- Layout wrappers in `src/components/layout/`
- Modal dialogs for CRUD operations in `src/components/modals/` — each imports its Zod schema from `@ptas/contracts` for form validation
- Report widgets in `src/components/reports/`
- Page components in `src/pages/`
