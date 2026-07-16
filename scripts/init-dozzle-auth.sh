#!/usr/bin/env bash
# Headless, idempotent generation of Dozzle's file-based "simple" auth credential.
#
# SECURITY FINDING (2026-07-13, independently flagged by 3 executives — CTO,
# Security, Engineering): Dozzle shipped with DOZZLE_AUTH_PROVIDER=none while
# holding a read-only docker.sock mount. Its "Inspect" panel surfaces every
# container's full `Env` array over an unauthenticated web UI — the T-0029
# cleartext-provider-key concern becomes one-click browser-visible on the LAN,
# no `docker exec` needed. compose/productivity/dozzle/dozzle.yml now sets
# DOZZLE_AUTH_PROVIDER=simple + DOZZLE_ENABLE_ACTIONS=false; this script builds
# the users.yml file that mode requires.
#
# Per current Dozzle docs (https://dozzle.dev/guide/authentication), simple-auth
# reads /data/users.yml with bcrypt-hashed passwords, generated via:
#   docker run amir20/dozzle generate <user> --password <pw> --email <e> --name <n>
# This script does exactly that — it NEVER writes or logs the plaintext password,
# only the bcrypt hash Dozzle itself produces.
#
# Idempotent: regenerates config/dozzle/users.yml from the current .env values
# every run (safe to re-run; a fresh bcrypt salt each time is expected, not a bug).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$REPO_DIR/.env}"
OUT_FILE="$REPO_DIR/config/dozzle/users.yml"
DOZZLE_IMAGE="${DOZZLE_IMAGE:-amir20/dozzle:latest}"

log() { printf '[init-dozzle-auth] %s\n' "$*"; }
die() { printf '[init-dozzle-auth] ERROR: %s\n' "$*" >&2; exit 1; }

[ -f "$ENV_FILE" ] || die "env file not found: $ENV_FILE"

# read_env VAR — last-write-wins, matches docker compose's own .env semantics
read_env() { grep -E "^${1}=" "$ENV_FILE" | tail -1 | cut -d= -f2- || true; }

gen_password() {
  head -c 24 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 20 2>/dev/null \
    || openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 20
}

set_env() {
  local var="$1" val="$2" esc
  esc=$(printf '%s' "$val" | sed -e 's/[\/&|]/\\&/g')
  if grep -qE "^${var}=" "$ENV_FILE"; then
    sed -i "s|^${var}=.*|${var}=${esc}|" "$ENV_FILE"
  else
    printf '%s=%s\n' "$var" "$val" >> "$ENV_FILE"
  fi
}

DOZZLE_AUTH_USER="$(read_env DOZZLE_AUTH_USER)"
DOZZLE_AUTH_USER="${DOZZLE_AUTH_USER:-admin}"

DOZZLE_AUTH_PASSWORD="$(read_env DOZZLE_AUTH_PASSWORD)"
if [ -z "$DOZZLE_AUTH_PASSWORD" ] || [ "$DOZZLE_AUTH_PASSWORD" = "<CHANGE_ME>" ]; then
  log "generating a new DOZZLE_AUTH_PASSWORD (never printed)..."
  DOZZLE_AUTH_PASSWORD="$(gen_password)"
  set_env "DOZZLE_AUTH_PASSWORD" "$DOZZLE_AUTH_PASSWORD"
fi

log "ensuring Dozzle image is present locally (needed for the 'generate' helper)..."
docker image inspect "$DOZZLE_IMAGE" >/dev/null 2>&1 || docker pull "$DOZZLE_IMAGE" >/dev/null

mkdir -p "$(dirname "$OUT_FILE")"

log "generating bcrypt-hashed users.yml for user '${DOZZLE_AUTH_USER}'..."
# Password is passed via argv to the throwaway container (not logged by this
# script), output is ONLY the bcrypt hash file content — redirected straight to
# disk, never assigned to a shell var or echoed.
docker run --rm "$DOZZLE_IMAGE" generate "$DOZZLE_AUTH_USER" \
  --password "$DOZZLE_AUTH_PASSWORD" \
  --email "${DOZZLE_AUTH_USER}@local.dev" \
  --name "Admin" > "$OUT_FILE"

chmod 600 "$OUT_FILE"

if ! grep -q '^\s*password:\s*\$2[aby]\$' "$OUT_FILE"; then
  die "generated $OUT_FILE does not contain an expected bcrypt hash — aborting"
fi

log "DONE. $OUT_FILE written (bcrypt hash only, 600 perms, gitignored)."
log "Bring up dozzle (profile: observability) then verify: unauth request to"
log "http://<host>:\${DOZZLE_PORT:-9999}/ must be challenged, not show logs."
