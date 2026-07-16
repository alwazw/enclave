#!/usr/bin/env bash
# Idempotent generation of config/dozzle/users.yml (bcrypt-hashed credential file).
#
# Dozzle's DOZZLE_AUTH_PROVIDER=simple reads /data/users.yml, bind-mounted from
# config/dozzle/users.yml. If that host path doesn't exist BEFORE the container is
# first created, Docker auto-creates it as a directory (bind-mount gotcha) instead
# of a file, and Dozzle fails at startup with "read ./data/users.yml: is a
# directory" — this script must run before `docker compose up` ever creates the
# dozzle container for the first time.
#
# Idempotent: if config/dozzle/users.yml already exists as a regular file, exits 0
# without touching it (re-running won't rotate an already-generated hash).
# Secret handling: the password is read from the gitignored .env
# (DOZZLE_AUTH_PASSWORD) and is passed to `docker run` via --password, never
# echoed or written anywhere in plaintext.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-${ROOT_DIR}/.env}"
OUT_FILE="${ROOT_DIR}/config/dozzle/users.yml"
DOZZLE_IMAGE="${DOZZLE_IMAGE:-amir20/dozzle:latest}"

log() { printf '[init-dozzle-auth] %s\n' "$*"; }

if [ -f "$OUT_FILE" ]; then
  log "already present -> ${OUT_FILE} (skipping; delete it first to regenerate)"
  exit 0
fi
if [ -d "$OUT_FILE" ]; then
  log "found a DIRECTORY at ${OUT_FILE} (leftover from a bad bind-mount before this script ran) -- removing it"
  rmdir "$OUT_FILE"
fi

if [ ! -f "$ENV_FILE" ]; then log "ERROR: env file not found: $ENV_FILE"; exit 1; fi
DOZZLE_AUTH_USER="$(grep -E '^DOZZLE_AUTH_USER=' "$ENV_FILE" | tail -1 | cut -d= -f2- || true)"
DOZZLE_AUTH_PASSWORD="$(grep -E '^DOZZLE_AUTH_PASSWORD=' "$ENV_FILE" | tail -1 | cut -d= -f2- || true)"
DOZZLE_AUTH_USER="${DOZZLE_AUTH_USER:-admin}"
if [ -z "${DOZZLE_AUTH_PASSWORD}" ]; then
  log "ERROR: DOZZLE_AUTH_PASSWORD not set in $ENV_FILE"; exit 1
fi

log "generating bcrypt-hashed users.yml for user '${DOZZLE_AUTH_USER}'..."
mkdir -p "$(dirname "$OUT_FILE")"
docker run --rm "$DOZZLE_IMAGE" generate "$DOZZLE_AUTH_USER" \
  --password "$DOZZLE_AUTH_PASSWORD" \
  --email "${DOZZLE_AUTH_USER}@local" \
  --name "$DOZZLE_AUTH_USER" > "$OUT_FILE"

log "DONE. wrote ${OUT_FILE} ($(wc -l < "$OUT_FILE") lines, no plaintext password in it)"
