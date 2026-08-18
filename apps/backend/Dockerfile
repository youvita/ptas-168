# Multi-stage build for apps/backend.
# Build context = repo root (so the whole pnpm workspace is visible).
# Build with:
#   docker build -f apps/backend/Dockerfile -t ptas168-backend .
#
# Stages:
#   base    — node:20-slim + pnpm 11.3 (matches packageManager pin).
#   deps    — install workspace deps from lockfile (cache-friendly: only
#             invalidated by lockfile or package.json changes).
#   build   — copy sources, generate prisma client, run `turbo build`.
#   runtime — slim image with only what's needed to run the compiled JS.

ARG NODE_VERSION=22

# ── base ──────────────────────────────────────────────────────────────────
FROM node:${NODE_VERSION}-slim AS base
ENV PNPM_HOME=/pnpm
ENV PATH=$PNPM_HOME:$PATH
RUN apt-get update \
 && apt-get install -y --no-install-recommends openssl ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && corepack enable \
 && corepack prepare pnpm@11.3.0 --activate
WORKDIR /repo

# ── deps ──────────────────────────────────────────────────────────────────
# Copy only the manifest files first so the install layer is cached as long
# as no manifest changes. Workspace packages must all be present at install
# time because pnpm resolves the workspace graph from these files.
FROM base AS deps
COPY pnpm-lock.yaml pnpm-workspace.yaml package.json turbo.json ./
COPY apps/backend/package.json       ./apps/backend/
COPY apps/frontend/package.json      ./apps/frontend/
COPY apps/worker/package.json        ./apps/worker/
COPY apps/telegram-bot/package.json  ./apps/telegram-bot/
COPY packages/bank-parsers/package.json ./packages/bank-parsers/
COPY packages/contracts/package.json    ./packages/contracts/
COPY packages/db/package.json           ./packages/db/
COPY packages/sdk/package.json          ./packages/sdk/
RUN --mount=type=cache,id=pnpm,target=/pnpm/store \
    pnpm install --frozen-lockfile

# ── build ─────────────────────────────────────────────────────────────────
# Bring in source for the backend and every package the backend depends on.
# Generate the Prisma client, then build the backend + its transitive
# package deps via turbo.
FROM deps AS build
COPY packages ./packages
COPY apps/backend ./apps/backend
RUN pnpm --filter @ptas/db generate
RUN pnpm turbo run build --filter=ptas168-backend...

# ── runtime ───────────────────────────────────────────────────────────────
# Copy the built repo as-is. pnpm uses symlinked node_modules; copying the
# whole tree preserves them. NODE_ENV=production keeps Express + libraries
# in their fast paths.
FROM base AS runtime
ENV NODE_ENV=production
COPY --from=build /repo /repo
WORKDIR /repo/apps/backend
EXPOSE 3001
CMD ["node", "dist/server.js"]
