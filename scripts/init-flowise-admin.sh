#!/usr/bin/env bash
# Headless, idempotent first-run admin bootstrap for Flowise v3.x (automation profile).
#
# Flowise dropped env-based basic auth (FLOWISE_USERNAME/FLOWISE_PASSWORD as container env
# vars) somewhere before 3.1.2 in favour of a workspace/organization multi-tenant model — a
# fresh `user` table has 0 rows and there is no owner/admin until one is created through the
# real HTTP API. Confirmed against the actual v3.1.2 source shipped in this repo's pinned
# image (`docker exec <container> cat .../enterprise/services/account.service.js`, `.../
# routes/index.js`, `.../utils/constants.js`), not from docs/memory:
#   1) POST /api/v1/account/register  (public — listed in WHITELIST_URLS) body:
#      {"user":{"name":..., "email":..., "credential":...}}
#      On a fresh DB (no organization row yet) this creates the org, default workspace, and
#      an ACTIVE owner user in one call — no email verification needed on the OPEN_SOURCE
#      platform tier (the tier this image runs as; no license key is configured). A second
#      call fails with 400 "You can only have one organization" (ensureOneOrganizationOnly).
#   2) POST /api/v1/auth/login  (passport-local, field names email/password — NOT the same
#      shape as /api/v1/account/login, which sits behind the API-key gate and is a dead end
#      for this purpose) — used here purely to VERIFY the credentials actually authenticate.
# If a future image bump changes any of this, re-check those three files inside the running
# container before assuming this script still applies.
#
# Idempotent: if login with the target credentials already succeeds, this is a no-op. If an
# organization already exists but the target credentials do NOT authenticate, this is a real
# misconfiguration (a previous run with different credentials, or manual changes) and the
# script fails loudly rather than silently leaving stale/wrong credentials in place.
# Secret handling: the password is read from the gitignored .env (FLOWISE_PASSWORD) and is
# never echoed or passed on argv.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$REPO_ROOT/.env}"

log() { printf '[init-flowise-admin] %s\n' "$*"; }

if [ ! -f "$ENV_FILE" ]; then log "ERROR: env file not found: $ENV_FILE"; exit 1; fi

env_val() { grep -E "^${1}=" "$ENV_FILE" | tail -1 | cut -d= -f2- || true; }

FLOWISE_PORT_VAL="$(env_val FLOWISE_PORT)"
BASE_URL="${FLOWISE_BASE_URL:-http://127.0.0.1:${FLOWISE_PORT_VAL:-3100}}"

FLOWISE_USERNAME_VAL="$(env_val FLOWISE_USERNAME)"
FLOWISE_ADMIN_EMAIL="$(env_val FLOWISE_ADMIN_EMAIL)"
FLOWISE_PASSWORD_VAL="$(env_val FLOWISE_PASSWORD)"
FLOWISE_USERNAME_VAL="${FLOWISE_USERNAME_VAL:-admin}"

for pair in "FLOWISE_ADMIN_EMAIL:$FLOWISE_ADMIN_EMAIL" "FLOWISE_PASSWORD:$FLOWISE_PASSWORD_VAL"; do
  name="${pair%%:*}"; val="${pair#*:}"
  if [ -z "$val" ]; then log "ERROR: $name not set in $ENV_FILE"; exit 1; fi
done

# --- wait for Flowise to answer its healthcheck endpoint ---
for i in $(seq 1 30); do
  if curl -fsS -o /dev/null "${BASE_URL}/api/v1/ping"; then break; fi
  [ "$i" = "30" ] && { log "ERROR: server not reachable at ${BASE_URL}"; exit 1; }
  sleep 2
done

resp_file="$(mktemp)"
trap 'rm -f "$resp_file"' EXIT

try_login() {
  curl -s -o "$resp_file" -w '%{http_code}' -X POST "${BASE_URL}/api/v1/auth/login" \
    -H 'Content-Type: application/json' \
    --data-binary @- <<JSON
{"email":"${FLOWISE_ADMIN_EMAIL}","password":"${FLOWISE_PASSWORD_VAL}"}
JSON
}

login_code="$(try_login)"
if [ "$login_code" = "200" ]; then
  log "credentials already work (login 200) -> no-op"
  exit 0
fi

log "no working admin yet (login returned ${login_code}) — registering ${FLOWISE_ADMIN_EMAIL}..."
reg_code="$(curl -s -o "$resp_file" -w '%{http_code}' -X POST "${BASE_URL}/api/v1/account/register" \
  -H 'Content-Type: application/json' \
  --data-binary @- <<JSON
{"user":{"name":"${FLOWISE_USERNAME_VAL}","email":"${FLOWISE_ADMIN_EMAIL}","credential":"${FLOWISE_PASSWORD_VAL}"}}
JSON
)"

if [ "$reg_code" = "201" ]; then
  log "register returned 201 (org + owner created)"
elif [ "$reg_code" = "400" ] && grep -qi "only have one organization" "$resp_file"; then
  log "ERROR: an organization already exists but ${FLOWISE_ADMIN_EMAIL} did not authenticate with"
  log "the .env FLOWISE_PASSWORD (login returned ${login_code} above). This means Flowise was"
  log "already bootstrapped with DIFFERENT credentials than what's currently in .env — refusing"
  log "to guess. Reset manually: docker exec <flowise_container> flowise user --email <email>"
  log "--password <newPassword> (resets an existing user's password), or inspect the 'user' /"
  log "'organization' tables in the flowise Postgres DB to find the real admin email."
  exit 1
else
  log "ERROR: register returned HTTP ${reg_code}: $(cat "$resp_file")"
  exit 1
fi

# verify the credentials really authenticate (not just "request succeeded")
login_code="$(try_login)"
if [ "$login_code" != "200" ]; then
  log "ERROR: verification login failed with HTTP ${login_code}: $(cat "$resp_file")"
  exit 1
fi
if ! grep -q '"isOrganizationAdmin":true' "$resp_file"; then
  log "ERROR: login succeeded but ${FLOWISE_ADMIN_EMAIL} is not an organization admin: $(cat "$resp_file")"
  exit 1
fi

log "DONE. admin registered + verified via authenticated /api/v1/auth/login as ${FLOWISE_ADMIN_EMAIL} (isOrganizationAdmin:true)."
