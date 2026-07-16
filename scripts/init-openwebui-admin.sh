#!/usr/bin/env bash
# Headless, idempotent first-run admin claim for Open WebUI (core profile).
#
# SECURITY FINDING (2026-07-16, empirically verified in an isolated throwaway
# container — not the live instance): Open WebUI's own POST /api/v1/auths/
# signup grants role "admin" to whichever request arrives FIRST, regardless
# of ENABLE_SIGNUP. That flag only rejects the *second* signup onward (HTTP
# 403 once one user exists) — before any account exists, signup always
# succeeds. On a LAN-reachable fresh install, whoever hits the port first
# (not necessarily the operator) becomes the permanent admin.
#
# This script claims that first-signup slot immediately at bring-up, using
# OPENWEBUI_ADMIN_EMAIL/NAME/PASSWORD from .env, so the race window closes
# before any other LAN device can reach the port.
#
# Idempotent: if a user already exists, signup returns 403 — treated as
# success (already claimed), not an error. Never logs the plaintext password.
set -euo pipefail

BASE_URL="${OPENWEBUI_BASE_URL:-http://127.0.0.1:${OPENWEBUI_PORT:-3000}}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$REPO_DIR/.env}"

log() { printf '[init-openwebui-admin] %s\n' "$*"; }
die() { printf '[init-openwebui-admin] ERROR: %s\n' "$*" >&2; exit 1; }

[ -f "$ENV_FILE" ] || die "env file not found: $ENV_FILE"
read_env() { grep -E "^${1}=" "$ENV_FILE" | tail -1 | cut -d= -f2- || true; }

OPENWEBUI_ADMIN_EMAIL="$(read_env OPENWEBUI_ADMIN_EMAIL)"; OPENWEBUI_ADMIN_EMAIL="${OPENWEBUI_ADMIN_EMAIL:-admin@local.dev}"
OPENWEBUI_ADMIN_NAME="$(read_env OPENWEBUI_ADMIN_NAME)"; OPENWEBUI_ADMIN_NAME="${OPENWEBUI_ADMIN_NAME:-Admin}"

OPENWEBUI_ADMIN_PASSWORD="$(read_env OPENWEBUI_ADMIN_PASSWORD)"
if [ -z "$OPENWEBUI_ADMIN_PASSWORD" ] || [ "$OPENWEBUI_ADMIN_PASSWORD" = "<CHANGE_ME>" ]; then
  die "OPENWEBUI_ADMIN_PASSWORD not set in $ENV_FILE — refusing to claim the admin slot with no real password"
fi

log "waiting for Open WebUI to answer /health at ${BASE_URL}..."
for i in $(seq 1 30); do
  if curl -fsS "${BASE_URL}/health" >/dev/null 2>&1; then break; fi
  [ "$i" = "30" ] && die "Open WebUI not reachable at ${BASE_URL}"
  sleep 2
done

body="$(printf '{"name":"%s","email":"%s","password":"%s"}' \
  "$OPENWEBUI_ADMIN_NAME" "$OPENWEBUI_ADMIN_EMAIL" "$OPENWEBUI_ADMIN_PASSWORD")"

resp_file="$(mktemp)"
trap 'rm -f "$resp_file"' EXIT
code="$(curl -sS -o "$resp_file" -w '%{http_code}' -X POST "${BASE_URL}/api/v1/auths/signup" \
  -H 'Content-Type: application/json' --data "$body")"

if [ "$code" = "200" ]; then
  role="$(sed -n 's/.*"role":"\([^"]*\)".*/\1/p' "$resp_file")"
  [ "$role" = "admin" ] || die "signup succeeded but role was '${role}', not admin — investigate"
  log "admin account claimed for ${OPENWEBUI_ADMIN_EMAIL}."
elif [ "$code" = "403" ]; then
  log "signup already closed (a user already exists) — idempotent no-op."
else
  die "POST /api/v1/auths/signup returned HTTP ${code}: $(cat "$resp_file")"
fi

log "DONE."
