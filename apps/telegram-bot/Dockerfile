# Multi-stage build for apps/telegram-bot (grammY long-polling + BullMQ
# `telegram-send` consumer). Without TELEGRAM_BOT_TOKEN the bot runs in
# stub mode — still consumes the queue but logs "would have sent".
#
# Build context = repo root. Build with:
#   docker build -f apps/telegram-bot/Dockerfile -t ptas168-telegram-bot .

ARG NODE_IMAGE=node:22-slim

FROM ${NODE_IMAGE} AS base
ENV PNPM_HOME=/pnpm
ENV PATH=$PNPM_HOME:$PATH
RUN apt-get update \
 && apt-get install -y --no-install-recommends openssl ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && corepack enable \
 && corepack prepare pnpm@11.3.0 --activate
WORKDIR /repo

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

FROM deps AS build
COPY packages ./packages
COPY apps/telegram-bot ./apps/telegram-bot
RUN pnpm --filter @ptas/db generate
RUN pnpm turbo run build --filter=@ptas/telegram-bot...

FROM base AS runtime
ENV NODE_ENV=production
COPY --from=build /repo /repo
WORKDIR /repo/apps/telegram-bot
CMD ["node", "dist/index.js"]
