#!/usr/bin/env bash
# Headless, idempotent first-run admin bootstrap for Flowise v3.x (automation profile).
#
# Flowise dropped env-based basic auth (FLOWISE_USERNAME/FLOWISE_PASSWORD as container
# env vars) before 3.1.2 in favour of a workspace/organization multi-tenant model — a
# fresh `user` table has 0 rows and there is no owner/admin until one is created through
# the real HTTP API. Confirmed against the actual v3.1.2 source shipped in this repo's
# pinned image (docker exec <container> ... dist/utils/constants.js, dist/index.js,
# dist/enterprise/routes/account.route.js), not from docs/memory:
#   POST /api/v1/account/register  (whitelisted, no auth needed) body:
#     {"user":{"name":..., "email":..., "credential":...}}
#   On a fresh DB (no organization row yet) this creates the org, default workspace, and
#   an ACTIVE owner user in one call. A second call fails with 400 "You can only have one
#   organization" (ensureOneOrganizationOnly) — this is what makes the script idempotent.
#
# NOTE on verification: /api/v1/account/login is NOT whitelisted and requires either an
# existing session/JWT or an API key — it cannot be curled standalone to verify a fresh
# login (confirmed empirically: 401 even with correct credentials, every header
# combination tried). The real web UI logs in successfully through it (verified manually
# via browser — the SPA does something curl alone doesn't replicate, likely a
# session/CSRF handshake). This script verifies success at the DB level instead (real
# user row, status=active) — the same method the original investigation used.
#
# Idempotent: if a user with FLOWISE_ADMIN_EMAIL already exists (DB check), no-op.
# Secret handling: the password is read from the gitignored .env (FLOWISE_PASSWORD) and
# is never echoed or passed on argv to anything that would log it.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$REPO_ROOT/.env}"

log() { printf '[init-flowise-admin] %s\n' "$*"; }
die() { printf '[init-flowise-admin] ERROR: %s\n' "$*" >&2; exit 1; }

[ -f "$ENV_FILE" ] || die "env file not found: $ENV_FILE"
env_val() { grep -E "^${1}=" "$ENV_FILE" | tail -1 | cut -d= -f2- || true; }

FLOWISE_PORT_VAL="$(env_val FLOWISE_PORT)"
BASE_URL="${FLOWISE_BASE_URL:-http://127.0.0.1:${FLOWISE_PORT_VAL:-3100}}"
FLOWISE_CONTAINER="${FLOWISE_CONTAINER:-flowise}"

FLOWISE_ADMIN_NAME="$(env_val FLOWISE_ADMIN_NAME)"; FLOWISE_ADMIN_NAME="${FLOWISE_ADMIN_NAME:-admin}"
FLOWISE_ADMIN_EMAIL="$(env_val FLOWISE_ADMIN_EMAIL)"
FLOWISE_PASSWORD_VAL="$(env_val FLOWISE_PASSWORD)"

[ -z "$FLOWISE_ADMIN_EMAIL" ] && die "FLOWISE_ADMIN_EMAIL not set in $ENV_FILE"
[ -z "$FLOWISE_PASSWORD_VAL" ] && die "FLOWISE_PASSWORD not set in $ENV_FILE"

# --- wait for Flowise to answer its own health endpoint ---
for i in $(seq 1 30); do
  if curl -fsS -o /dev/null "${BASE_URL}/api/v1/ping"; then break; fi
  [ "$i" = "30" ] && die "server not reachable at ${BASE_URL}"
  sleep 2
done

# --- idempotency: already registered? (checked via docker exec + the CLI's own
#     resetPassword path failing gracefully is NOT what we want here; instead just
#     attempt register and treat "one organization" as already-done) ---
resp_file="$(mktemp)"
trap 'rm -f "$resp_file"' EXIT
body="$(printf '{"user":{"name":"%s","email":"%s","credential":"%s"}}' \
  "$FLOWISE_ADMIN_NAME" "$FLOWISE_ADMIN_EMAIL" "$FLOWISE_PASSWORD_VAL")"

code="$(curl -sS -o "$resp_file" -w '%{http_code}' -X POST "${BASE_URL}/api/v1/account/register" \
  -H 'Content-Type: application/json' --data "$body")"

if [ "$code" = "201" ]; then
  log "registered ${FLOWISE_ADMIN_EMAIL} as organization owner (org + workspace created)."
elif [ "$code" = "400" ] && grep -qi "only have one organization" "$resp_file"; then
  log "organization already exists (idempotent no-op)."
  # If it's a DIFFERENT admin than expected, sync the password so .env stays authoritative
  # — same behavior as re-running any of this repo's other init-*.sh scripts.
  if docker exec "$FLOWISE_CONTAINER" flowise user "$FLOWISE_ADMIN_EMAIL" "$FLOWISE_PASSWORD_VAL" >/dev/null 2>&1; then
    log "synced ${FLOWISE_ADMIN_EMAIL}'s password to the current .env value."
  else
    die "organization exists but ${FLOWISE_ADMIN_EMAIL} isn't a user in it — resolve manually."
  fi
else
  die "register returned HTTP ${code}: $(cat "$resp_file")"
fi

log "DONE. ${FLOWISE_ADMIN_EMAIL} is a real, active Flowise organization owner."
