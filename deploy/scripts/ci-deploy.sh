#!/usr/bin/env bash
# GitHub Actions deploy on the Mac mini self-hosted runner.
# Rebuilds the Docker app stack. Never starts or stops Cloudflare / macmini-tunnel.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

export PATH="/opt/homebrew/bin:/usr/local/bin:${HOME}/.docker/bin:${PATH:-/usr/bin:/bin}"
# Compose v5 bake fails immediately in this LaunchAgent session (and hides
# the real error behind the TTY progress UI). Classic `up --build` is enough.
export COMPOSE_BAKE=false
export BUILDKIT_PROGRESS=plain
# Compose interpolates this even though the tunnel profile is never started.
export CLOUDFLARE_TUNNEL_TOKEN="${CLOUDFLARE_TUNNEL_TOKEN:-}"

# LaunchAgent jobs cannot unlock macOS Keychain. Docker Desktop's
# credsStore=osxkeychain then fails the Hub pull of `docker/dockerfile:1.7`
# (the `# syntax=` line) right after "load build definition". Use a
# throwaway config with no credsStore, and symlink every CLI plugin so
# Compose / Buildx stay visible (a bare DOCKER_CONFIG hid them before).
if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  DOCKER_CONFIG_DIR="${RUNNER_TEMP:-/tmp}/ptas168-docker-config"
  mkdir -p "${DOCKER_CONFIG_DIR}/cli-plugins"
  printf '{}\n' > "${DOCKER_CONFIG_DIR}/config.json"
  for d in \
    /Applications/Docker.app/Contents/Resources/cli-plugins \
    /usr/local/lib/docker/cli-plugins \
    /opt/homebrew/lib/docker/cli-plugins \
    "${HOME}/.docker/cli-plugins"
  do
    [[ -d "$d" ]] || continue
    for plugin in "$d"/docker-*; do
      [[ -e "$plugin" || -L "$plugin" ]] || continue
      ln -sf "$plugin" "${DOCKER_CONFIG_DIR}/cli-plugins/$(basename "$plugin")"
    done
  done
  export DOCKER_CONFIG="${DOCKER_CONFIG_DIR}"
  echo "==> Isolated Docker config (no osxkeychain) at ${DOCKER_CONFIG}"
fi

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
  ls -la "${DOCKER_CONFIG:-${HOME}/.docker}/cli-plugins" >&2 || true
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
# `pnpm deploy` is a built-in (needs a target dir). Use `run` to hit the
# @ptas/db script → prisma migrate deploy.
"${COMPOSE[@]}" run --rm --no-deps --entrypoint sh backend \
  -c 'cd /repo && pnpm --filter @ptas/db run deploy'

echo "==> Rebuild and start apps (tunnel is not touched)"
"${COMPOSE[@]}" up -d --build --no-deps backend worker telegram-bot frontend

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
