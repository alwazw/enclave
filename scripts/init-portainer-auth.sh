#!/usr/bin/env bash
# Idempotent generation of config/portainer/admin_password (plaintext, gitignored,
# 600 perms -- Portainer hashes it internally on first boot only, via
# --admin-password-file).
#
# If this host path doesn't exist BEFORE the container is first created, Docker
# auto-creates it as a directory (same bind-mount gotcha as Dozzle's users.yml),
# and Portainer fails at startup with "could not get the contents of the file
# '/run/secrets/portainer_admin_password'" -- this script must run before
# `docker compose up` ever creates the portainer container for the first time.
#
# Idempotent: if config/portainer/admin_password already exists as a regular
# file, exits 0 without touching it (Portainer only consumes this file on a
# fresh portainer_data volume anyway -- rewriting it later has no effect on an
# already-claimed admin account).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-${ROOT_DIR}/.env}"
OUT_FILE="${ROOT_DIR}/config/portainer/admin_password"

log() { printf '[init-portainer-auth] %s\n' "$*"; }

if [ -f "$OUT_FILE" ]; then
  log "already present -> ${OUT_FILE} (skipping; delete it first to regenerate)"
  exit 0
fi
if [ -d "$OUT_FILE" ]; then
  log "found a DIRECTORY at ${OUT_FILE} (leftover from a bad bind-mount before this script ran) -- removing it"
  rmdir "$OUT_FILE"
fi

if [ ! -f "$ENV_FILE" ]; then log "ERROR: env file not found: $ENV_FILE"; exit 1; fi
PORTAINER_ADMIN_PASSWORD="$(grep -E '^PORTAINER_ADMIN_PASSWORD=' "$ENV_FILE" | tail -1 | cut -d= -f2- || true)"
if [ -z "${PORTAINER_ADMIN_PASSWORD}" ]; then
  log "ERROR: PORTAINER_ADMIN_PASSWORD not set in $ENV_FILE"; exit 1
fi

mkdir -p "$(dirname "$OUT_FILE")"
printf '%s' "$PORTAINER_ADMIN_PASSWORD" > "$OUT_FILE"
chmod 600 "$OUT_FILE"

log "DONE. wrote ${OUT_FILE} ($(wc -c < "$OUT_FILE") bytes, 600 perms)"
