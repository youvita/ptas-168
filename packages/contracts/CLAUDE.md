# @ptas/contracts

Shared types + Zod schemas for the PTAS168 monorepo. The wire-format source of truth.

## Hard rules

- **Zero runtime deps** except `zod`. No Prisma, no Express, no React, no DOM types.
- **No logic.** No adapters, no transforms, no helpers that do work. Just shapes.
- **One file per domain** under `src/` (e.g. `enums.ts`, `error.ts`, `building.ts`, …). Re-export from `src/index.ts`.
- **Paired exports for asymmetric entities.** Many backend endpoints take one shape and return another (`profilePhotoUrl` in → `photo` out, `pricePerMonth` in → `price` out). Each affected entity needs:
  - `Create<Entity>Input` + `Create<Entity>InputSchema` — what `POST /entities` accepts
  - `Update<Entity>Input` + `Update<Entity>InputSchema` — what `PATCH /entities/:id` accepts
  - `<Entity>Dto` + `<Entity>DtoSchema` — what the API returns on read

  See [MIGRATION_ANALYSIS.md §5](../../MIGRATION_ANALYSIS.md) for the full list of asymmetric entities.

- **Keep enums in sync with [`apps/backend/prisma/schema.prisma`](../../apps/backend/prisma/schema.prisma).** This package mirrors the Prisma enums; it does not generate from them. If you change a Prisma enum, update [`src/enums.ts`](src/enums.ts) in the same commit.

## Build setup

- `tsc` emits **ESM** (NodeNext) to `dist/` with declaration files + source maps. `package.json` is `"type": "module"`, matching the backend and every other package in the monorepo.
- `package.json` `main` is `./dist/index.js`, `types` is `./dist/index.d.ts`.
- Turbo wires the dependency edge automatically: `pnpm turbo run build --filter=ptas168-backend` builds this package first. Don't need to script it manually.
- For iterative work in another package, run `pnpm --filter @ptas/contracts dev` (tsc watch) in one terminal and consumer dev in another.

## NodeNext quirk

`tsconfig.json` uses `module: NodeNext`, so **relative imports inside this package must use `.js`** even though the source is `.ts`:

```ts
// src/index.ts
export * from './enums.js'      // ✓
export * from './enums'         // ✗  (tsc will fail under NodeNext)
```

External imports (`zod`, future `@ptas/*` cross-package) follow the usual no-extension form.

## Adding a new export

1. Create `src/<domain>.ts` with the Zod schemas + inferred TS types
2. Add a `export * from './<domain>.js'` line to `src/index.ts`
3. `pnpm --filter @ptas/contracts build`
4. Use in a consumer: `import { ... } from '@ptas/contracts'`
5. Verify the consumer compiles: `pnpm --filter ptas168-backend build`

## Sequencing for the Phase 3 extract

The order in [MIGRATION_ANALYSIS.md §7](../../MIGRATION_ANALYSIS.md) — paraphrased here for stickiness:

1. ✅ Enums ([enums.ts](src/enums.ts))
2. ⏭ Error envelope (`ErrorEnvelope`, `ErrorCode` union) — pure types, easy
3. ⏭ `BuildingDto` + inputs — first symmetric entity, validates the `*Input`/`*Dto` pattern
4. ⏭ `TenantDto` + inputs — first **asymmetric** entity, validates the dual-shape pattern
5. → rest of the domains
6. ⏭ Save `Invoice` for last (flat wire shape ↔ nested UI shape is the most complex)

After each domain extract, run the consumer build to keep the safety net green.
