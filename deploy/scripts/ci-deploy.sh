#!/usr/bin/env bash
# GitHub Actions deploy on the Mac mini self-hosted runner.
# Rebuilds the Docker app stack. Never starts or stops Cloudflare / macmini-tunnel.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

export PATH="/opt/homebrew/bin:/usr/local/bin:${HOME}/.docker/bin:${PATH:-/usr/bin:/bin}"

if [[ ! -f .env ]]; then
  echo "Missing .env in ${ROOT}." >&2
  echo "The workflow writes it from GitHub secrets, or keep ~/Projects/ptas-168/.env on the Mini." >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker CLI not found on PATH: $PATH" >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker is not running on this Mac mini. Start Docker Desktop and re-run." >&2
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "docker compose plugin not found. Install Docker Desktop / Compose v2." >&2
  docker version || true
  exit 1
fi

COMPOSE=(docker compose --env-file .env -f infrastructure/docker/docker-compose.yml)
BACKEND_PORT="$(awk -F= '/^BACKEND_PORT=/{print $2; exit}' .env)"
BACKEND_PORT="${BACKEND_PORT:-3002}"
HEALTH_URL="http://127.0.0.1:${BACKEND_PORT}/api/health"

echo "==> Deploying PTAS168 from $(pwd) @ ${GITHUB_SHA:-unknown}"
echo "==> docker $(command -v docker) / $(docker compose version)"

# Named services only — no --profile tunnel, no --remove-orphans.
"${COMPOSE[@]}" up -d postgres redis

echo "==> Waiting for postgres"
for i in $(seq 1 30); do
  if docker exec ptas168_postgres pg_isready -U postgres -d ptas168_dev >/dev/null 2>&1; then
    echo "    postgres ready"
    break
  fi
  if [[ "$i" -eq 30 ]]; then
    echo "Postgres did not become ready." >&2
    "${COMPOSE[@]}" logs postgres >&2 || true
    exit 1
  fi
  sleep 2
done

echo "==> Prisma migrate deploy"
"${COMPOSE[@]}" run --rm --no-deps --entrypoint sh backend \
  -c 'cd /repo && pnpm --filter @ptas/db deploy'

echo "==> Rebuild and start apps (tunnel is not touched)"
"${COMPOSE[@]}" up -d --build backend worker telegram-bot frontend

echo "==> Waiting for ${HEALTH_URL}"
for i in $(seq 1 40); do
  if curl -fsS -m 3 "${HEALTH_URL}" >/dev/null 2>&1; then
    echo "    healthy"
    break
  fi
  if [[ "$i" -eq 40 ]]; then
    echo "Backend did not become healthy. Check: docker compose -f infrastructure/docker/docker-compose.yml logs backend" >&2
    "${COMPOSE[@]}" logs --tail=80 backend >&2 || true
    exit 1
  fi
  sleep 2
done

"${COMPOSE[@]}" ps
echo
echo "================================================================"
echo "  PTAS168 redeployed — Cloudflare tunnel was NOT restarted"
echo "  Health: ${HEALTH_URL}"
echo "  UI:     http://127.0.0.1:8082/ptas168/"
echo "================================================================"
