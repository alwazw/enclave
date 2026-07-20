#!/usr/bin/env bash
# Headless, idempotent first-run owner-account bootstrap for n8n (automation profile).
#
# n8n ships with NO owner account until the first visitor completes an interactive
# setup wizard at :5678 — closes T-0042's n8n half (mirrors scripts/init-trilium.sh's
# pattern for TriliumNext).
#
# Endpoint verified against n8n's own source (packages/cli/src/controllers/
# owner.controller.ts + @n8n/api-types' OwnerSetupRequestDto):
#   POST /rest/owner/setup   { email, firstName, lastName, password }  (skipAuth)
# Password policy (packages/@n8n/api-types/src/schemas/password.schema.ts):
#   8-64 chars, >=1 digit, >=1 uppercase letter.
# Idempotent by construction: if an owner already exists, n8n's own
# OwnershipService throws a 400 "Instance owner already setup" — this script
# treats that specific response as success, not an error.
set -euo pipefail

BASE_URL="${N8N_BASE_URL:-http://127.0.0.1:${N8N_PORT:-5678}}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$REPO_DIR/.env}"

log() { printf '[init-n8n-owner] %s\n' "$*"; }
die() { printf '[init-n8n-owner] ERROR: %s\n' "$*" >&2; exit 1; }

[ -f "$ENV_FILE" ] || die "env file not found: $ENV_FILE"
read_env() { grep -E "^${1}=" "$ENV_FILE" | tail -1 | cut -d= -f2- || true; }

gen_password() {
  # Guarantee n8n's policy (>=1 digit, >=1 uppercase) rather than hoping a random
  # 20-char alnum sample happens to include both.
  local p
  p="$(head -c 24 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 18 2>/dev/null \
        || openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 18)"
  printf '%sA1' "$p"
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

N8N_OWNER_EMAIL="$(read_env N8N_OWNER_EMAIL)"; N8N_OWNER_EMAIL="${N8N_OWNER_EMAIL:-admin@local.dev}"
N8N_OWNER_FIRST_NAME="$(read_env N8N_OWNER_FIRST_NAME)"; N8N_OWNER_FIRST_NAME="${N8N_OWNER_FIRST_NAME:-Admin}"
N8N_OWNER_LAST_NAME="$(read_env N8N_OWNER_LAST_NAME)"; N8N_OWNER_LAST_NAME="${N8N_OWNER_LAST_NAME:-Operator}"

N8N_OWNER_PASSWORD="$(read_env N8N_OWNER_PASSWORD)"
if [ -z "$N8N_OWNER_PASSWORD" ] || [ "$N8N_OWNER_PASSWORD" = "<CHANGE_ME>" ]; then
  log "generating a new N8N_OWNER_PASSWORD (never printed)..."
  N8N_OWNER_PASSWORD="$(gen_password)"
  set_env "N8N_OWNER_PASSWORD" "$N8N_OWNER_PASSWORD"
fi

log "waiting for n8n to answer /healthz at ${BASE_URL}..."
for i in $(seq 1 30); do
  if curl -fsS "${BASE_URL}/healthz" >/dev/null 2>&1; then break; fi
  [ "$i" = "30" ] && die "n8n not reachable at ${BASE_URL}"
  sleep 2
done

log "attempting owner setup for ${N8N_OWNER_EMAIL}..."
body="$(printf '{"email":"%s","firstName":"%s","lastName":"%s","password":"%s"}' \
  "$N8N_OWNER_EMAIL" "$N8N_OWNER_FIRST_NAME" "$N8N_OWNER_LAST_NAME" "$N8N_OWNER_PASSWORD")"

resp_file="$(mktemp)"
trap 'rm -f "$resp_file"' EXIT
code="$(curl -sS -o "$resp_file" -w '%{http_code}' -X POST "${BASE_URL}/rest/owner/setup" \
  -H 'Content-Type: application/json' --data "$body")"

if [ "$code" = "200" ]; then
  log "owner account created."
elif [ "$code" = "400" ] && grep -qi "already setup" "$resp_file"; then
  log "owner already set up (idempotent no-op) -> $(cat "$resp_file")"
else
  die "POST /rest/owner/setup returned HTTP ${code}: $(cat "$resp_file")"
fi

# verify a real login works (proves a real user can authenticate, not just that
# the setup call returned 200)
login_code="$(curl -sS -o /dev/null -w '%{http_code}' -c /dev/null -X POST "${BASE_URL}/rest/login" \
  -H 'Content-Type: application/json' \
  --data "{\"emailOrLdapLoginId\":\"${N8N_OWNER_EMAIL}\",\"password\":\"${N8N_OWNER_PASSWORD}\"}")"
if [ "$login_code" != "200" ]; then
  die "post-setup login check failed (HTTP ${login_code}) — owner setup may not have taken"
fi

log "DONE. Owner set up + login verified for ${N8N_OWNER_EMAIL}."
