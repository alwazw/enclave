#!/usr/bin/env bash
# Headless, idempotent generation of Portainer's --admin-password-file secret.
#
# SECURITY FINDING (2026-07-13): Portainer shipped with NO env-driven admin
# bootstrap — the first LAN device to reach :9000/:9443 within a ~5min window
# after first boot claims the admin account (or the instance locks and needs a
# manual reset). compose/dev-tools/portainer/portainer.yml now runs Portainer
# with `--admin-password-file=/run/secrets/portainer_admin_password`, reading a
# file this script writes.
#
# Per Portainer's own CLI help + documented pattern, --admin-password-file takes
# the PLAINTEXT password (Portainer hashes it internally on startup) — unlike
# --admin-password, which expects a pre-hashed bcrypt value. This file is never
# printed/echoed, is written 600, and only takes effect the FIRST time Portainer
# boots against an uninitialized `portainer_data` volume (by Portainer's own
# design) — it is a no-op, not a reset mechanism, on an already-initialized
# instance.
#
# This script does not itself talk to a running Portainer (no HTTP verification
# is possible pre-bootstrap); QA's Phase B/C deep-validate step is what proves
# the credential actually authenticates.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$REPO_DIR/.env}"
OUT_FILE="$REPO_DIR/config/portainer/admin_password"

log() { printf '[init-portainer-auth] %s\n' "$*"; }
die() { printf '[init-portainer-auth] ERROR: %s\n' "$*" >&2; exit 1; }

[ -f "$ENV_FILE" ] || die "env file not found: $ENV_FILE"

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

PORTAINER_ADMIN_PASSWORD="$(read_env PORTAINER_ADMIN_PASSWORD)"
if [ -z "$PORTAINER_ADMIN_PASSWORD" ] || [ "$PORTAINER_ADMIN_PASSWORD" = "<CHANGE_ME>" ]; then
  log "generating a new PORTAINER_ADMIN_PASSWORD (never printed)..."
  PORTAINER_ADMIN_PASSWORD="$(gen_password)"
  set_env "PORTAINER_ADMIN_PASSWORD" "$PORTAINER_ADMIN_PASSWORD"
fi

# Portainer's minimum password length is 12 chars — the generator above always
# produces 20, but guard explicitly in case an operator hand-set a short value.
if [ "${#PORTAINER_ADMIN_PASSWORD}" -lt 12 ]; then
  die "PORTAINER_ADMIN_PASSWORD is shorter than Portainer's 12-char minimum"
fi

mkdir -p "$(dirname "$OUT_FILE")"
printf '%s' "$PORTAINER_ADMIN_PASSWORD" > "$OUT_FILE"
chmod 600 "$OUT_FILE"

log "DONE. $OUT_FILE written (plaintext, 600 perms, gitignored, read by Portainer"
log "at boot only — never displayed by this script)."
log "Bring up portainer (profile: tools) fresh, then verify: login with"
log "user 'admin' + the PORTAINER_ADMIN_PASSWORD from .env succeeds, and an"
log "unrelated/blank credential is rejected."
