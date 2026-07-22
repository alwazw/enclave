#!/usr/bin/env bash
# Toggle AIR-GAP MODE: swap LiteLLM's active config between the normal
# multi-provider cascade (litellm.yml) and a local-only config (litellm.airgap.yml)
# whose model_list has NO cloud model_name and NO fallbacks entry that could
# reach one — an architectural guarantee of zero cloud calls, not just "keys
# happen to be unset". Recreates the litellm container so the swap takes effect
# (config.yaml is bind-mounted from the config.yml symlink at container-create
# time, not re-read live).
#
# Usage:
#   scripts/set-airgap.sh on    # route morpheus-main/-utility/-embedding-model to local Ollama only
#   scripts/set-airgap.sh off   # restore the normal cloud-first cascade
#   scripts/set-airgap.sh status
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$REPO_DIR/config/litellm"
COMPOSE_FILE="${COMPOSE_FILE:-$REPO_DIR/local-stack.yml}"
PROJECT="${COMPOSE_PROJECT_NAME:-aef2}"

log() { printf '[set-airgap] %s\n' "$*"; }
die() { printf '[set-airgap] ERROR: %s\n' "$*" >&2; exit 1; }

current_target() {
  readlink "$CONFIG_DIR/config.yml" 2>/dev/null || echo "(not a symlink)"
}

case "${1:-}" in
  on)
    ln -sf litellm.airgap.yml "$CONFIG_DIR/config.yml"
    log "config.yml -> $(current_target) (local Ollama only, zero cloud model_name entries)"
    ;;
  off)
    ln -sf litellm.yml "$CONFIG_DIR/config.yml"
    log "config.yml -> $(current_target) (normal multi-provider cascade)"
    ;;
  status)
    log "config.yml -> $(current_target)"
    exit 0
    ;;
  *)
    die "usage: $0 {on|off|status}"
    ;;
esac

log "recreating litellm to load the new config..."
docker compose -p "$PROJECT" -f "$COMPOSE_FILE" up -d --no-deps --force-recreate litellm

log "waiting for litellm to become healthy..."
for _ in $(seq 1 30); do
  status="$(docker inspect --format '{{.State.Health.Status}}' litellm 2>/dev/null || echo unknown)"
  [ "$status" = "healthy" ] && { log "litellm healthy."; exit 0; }
  sleep 2
done
die "litellm did not become healthy within 60s — check: docker logs litellm"
