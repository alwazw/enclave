#!/usr/bin/env bash
# Headless, idempotent first-run owner claim for n8n (automation profile).
#
# n8n ships with a "shell" user (role global:owner, email/password NULL) already present
# in the DB from first boot. Until that shell user is claimed, `/rest/settings` reports
# userManagement.showSetupOnFirstLoad:true and the FIRST LAN VISITOR to hit the web UI can
# claim owner with whatever email/password they type in — same class of risk as an
# unclaimed Open WebUI admin account.
#
# This script drives the same call the setup wizard makes, non-interactively:
#   POST /rest/owner/setup  (skipAuth) body: {email, firstName, lastName, password}
#   -> claims the existing shell user, sets userManagement.isInstanceOwnerSetUp=true.
# Confirmed against the actual n8n source shipped in this repo's pinned image
# (n8nio/n8n:latest, n8n 2.30.5 at time of writing — verified via
# `docker exec <container> cat .../controllers/owner.controller.js` and
# `.../services/ownership.service.js`, not from docs/memory). If a future image bump
# changes this endpoint, re-check those two files inside the running container before
# assuming this script still applies.
#
# Idempotent: n8n itself refuses a second claim (setupOwner throws "Instance owner already
# setup" once `hasInstanceOwner()` is true) — this script treats that as success, and also
# short-circuits early via /rest/settings so a re-run does zero writes when already claimed.
# Secret handling: password is read from the gitignored .env (N8N_OWNER_PASSWORD) and is
# never echoed or passed on argv (sent as a curl --data-binary JSON body only).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$REPO_ROOT/.env}"

log() { printf '[init-n8n-owner] %s\n' "$*"; }

if [ ! -f "$ENV_FILE" ]; then log "ERROR: env file not found: $ENV_FILE"; exit 1; fi

env_val() { grep -E "^${1}=" "$ENV_FILE" | tail -1 | cut -d= -f2- || true; }

N8N_PORT_VAL="$(env_val N8N_PORT)"
BASE_URL="${N8N_BASE_URL:-http://127.0.0.1:${N8N_PORT_VAL:-5678}}"

N8N_OWNER_EMAIL="$(env_val N8N_OWNER_EMAIL)"
N8N_OWNER_FIRST_NAME="$(env_val N8N_OWNER_FIRST_NAME)"
N8N_OWNER_LAST_NAME="$(env_val N8N_OWNER_LAST_NAME)"
N8N_OWNER_PASSWORD="$(env_val N8N_OWNER_PASSWORD)"

for var_name in N8N_OWNER_EMAIL N8N_OWNER_FIRST_NAME N8N_OWNER_LAST_NAME N8N_OWNER_PASSWORD; do
  if [ -z "${!var_name}" ]; then
    log "ERROR: $var_name not set in $ENV_FILE"; exit 1
  fi
done

# --- wait for n8n to answer its healthcheck endpoint ---
for i in $(seq 1 30); do
  if curl -fsS -o /dev/null "${BASE_URL}/healthz"; then break; fi
  [ "$i" = "30" ] && { log "ERROR: server not reachable at ${BASE_URL}"; exit 1; }
  sleep 2
done

settings() { curl -fsS "${BASE_URL}/rest/settings"; }

already_claimed() {
  settings | grep -q '"showSetupOnFirstLoad":false'
}

if already_claimed; then
  log "owner already claimed (showSetupOnFirstLoad:false) -> no-op"
  exit 0
fi

log "claiming owner account for ${N8N_OWNER_EMAIL}..."
resp_file="$(mktemp)"
trap 'rm -f "$resp_file"' EXIT
http_code="$(curl -s -o "$resp_file" -w '%{http_code}' -X POST "${BASE_URL}/rest/owner/setup" \
  -H 'Content-Type: application/json' \
  --data-binary @- <<JSON
{"email":"${N8N_OWNER_EMAIL}","firstName":"${N8N_OWNER_FIRST_NAME}","lastName":"${N8N_OWNER_LAST_NAME}","password":"${N8N_OWNER_PASSWORD}"}
JSON
)"

if [ "$http_code" = "200" ]; then
  log "owner/setup returned 200 (claimed)"
elif [ "$http_code" = "400" ] && grep -qi "already setup" "$resp_file"; then
  log "owner/setup returned 400 'already setup' -> another process won the race, treating as no-op"
else
  log "ERROR: owner/setup returned HTTP ${http_code}: $(cat "$resp_file")"
  exit 1
fi

# verify claim really took (settings flips) AND the real credentials authenticate
if ! already_claimed; then
  log "ERROR: /rest/settings still reports showSetupOnFirstLoad:true after owner/setup"
  exit 1
fi

login_code="$(curl -s -o "$resp_file" -w '%{http_code}' -X POST "${BASE_URL}/rest/login" \
  -H 'Content-Type: application/json' \
  --data-binary @- <<JSON
{"emailOrLdapLoginId":"${N8N_OWNER_EMAIL}","password":"${N8N_OWNER_PASSWORD}"}
JSON
)"
if [ "$login_code" != "200" ]; then
  log "ERROR: verification login failed with HTTP ${login_code}: $(cat "$resp_file")"
  exit 1
fi

log "DONE. owner claimed + verified via authenticated /rest/login as ${N8N_OWNER_EMAIL}."
