# Two-stage build for apps/frontend.
#   build   — vite build with VITE_API_URL baked in (defaults to /api so the
#             nginx layer can proxy without browser CORS).
#   runtime — nginx-alpine serving the static bundle from
#             /usr/share/nginx/html and proxying /api → backend service.
#
# Build context = repo root. Build with:
#   docker build -f apps/frontend/Dockerfile -t ptas168-frontend .

# Base images are named build contexts (`nodebase`, `nginxbase`) so CI can
# load local images without Docker Hub / osxkeychain.

FROM nodebase AS build
ENV PNPM_HOME=/pnpm
ENV PATH=$PNPM_HOME:$PATH
RUN corepack enable && corepack prepare pnpm@11.3.0 --activate
WORKDIR /repo

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

COPY packages ./packages
COPY apps/frontend ./apps/frontend

# Override the production env so the browser hits /api (same-origin),
# which nginx then proxies to the backend container. Override at build
# time via `--build-arg VITE_API_URL=<absolute-url>` if deploying with
# a separate API host.
ARG VITE_API_URL=/api
ARG VITE_FILE_URL=/files
ARG VITE_BASE_PATH=/
ENV VITE_API_URL=$VITE_API_URL
ENV VITE_FILE_URL=$VITE_FILE_URL
ENV VITE_BASE_PATH=$VITE_BASE_PATH

RUN pnpm turbo run build --filter=pbms-app...

# ── runtime ───────────────────────────────────────────────────────────────
FROM nginxbase AS runtime
COPY apps/frontend/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /repo/apps/frontend/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
