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
CONTAINER="${OPENWEBUI_CONTAINER:-open_webui}"

log() { printf '[init-openwebui-admin] %s\n' "$*"; }
die() { printf '[init-openwebui-admin] ERROR: %s\n' "$*" >&2; exit 1; }

[ -f "$ENV_FILE" ] || die "env file not found: $ENV_FILE"
read_env() { grep -E "^${1}=" "$ENV_FILE" | tail -1 | cut -d= -f2- || true; }
set_env() {
  local var="$1" val="$2" esc
  esc=$(printf '%s' "$val" | sed -e 's/[\/&|]/\\&/g')
  if grep -qE "^${var}=" "$ENV_FILE"; then
    sed -i "s|^${var}=.*|${var}=${esc}|" "$ENV_FILE"
  else
    printf '%s=%s\n' "$var" "$val" >> "$ENV_FILE"
  fi
}

OPENWEBUI_ADMIN_EMAIL="$(read_env OPENWEBUI_ADMIN_EMAIL)"; OPENWEBUI_ADMIN_EMAIL="${OPENWEBUI_ADMIN_EMAIL:-admin@local.dev}"
OPENWEBUI_ADMIN_NAME="$(read_env OPENWEBUI_ADMIN_NAME)"; OPENWEBUI_ADMIN_NAME="${OPENWEBUI_ADMIN_NAME:-Admin}"

OPENWEBUI_ADMIN_PASSWORD="$(read_env OPENWEBUI_ADMIN_PASSWORD)"

log "waiting for Open WebUI to answer /health at ${BASE_URL}..."
for i in $(seq 1 30); do
  if curl -fsS "${BASE_URL}/health" >/dev/null 2>&1; then break; fi
  [ "$i" = "30" ] && die "Open WebUI not reachable at ${BASE_URL}"
  sleep 2
done

if [ -z "$OPENWEBUI_ADMIN_PASSWORD" ] || [ "$OPENWEBUI_ADMIN_PASSWORD" = "<CHANGE_ME>" ]; then
  log "OPENWEBUI_ADMIN_PASSWORD not set in $ENV_FILE — skipping the admin-claim step (refusing to"
  log "claim the slot with no real password). Continuing to the API-key step below regardless,"
  log "since it only needs an EXISTING user, not this one's password."
else
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
fi


# #11: Homepage's dashboard widget needs a real Open WebUI API key to read
# /api/v1/models (that endpoint isn't part of the signup/session flow above,
# and Open WebUI has no way to mint one over HTTP without an interactive
# session) — generate one directly in its own DB, idempotent (only if
# OPENWEBUI_API_KEY isn't already set), and persist it to .env the same way
# init-portainer-auth.sh does for its own generated password.
OPENWEBUI_API_KEY_VAL="$(read_env OPENWEBUI_API_KEY)"
if [ -z "$OPENWEBUI_API_KEY_VAL" ]; then
  log "generating a Homepage widget API key (none set yet)..."
  OPENWEBUI_API_KEY_VAL="$(docker exec "$CONTAINER" python3 -c "
import sqlite3, secrets, time, uuid, json
con = sqlite3.connect('/app/backend/data/webui.db')
cur = con.cursor()
cur.execute(\"SELECT id FROM user ORDER BY created_at ASC LIMIT 1\")
row = cur.fetchone()
if not row:
    raise SystemExit('no user exists yet')
user_id = row[0]
key = 'sk-' + secrets.token_hex(32)
now = int(time.time())
cur.execute(
    'INSERT INTO api_key (id, user_id, key, data, expires_at, last_used_at, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?)',
    (str(uuid.uuid4()), user_id, key, json.dumps({}), None, None, now, now),
)
con.commit()
print(key)
")" || die "failed to generate Open WebUI API key inside ${CONTAINER}"
  set_env OPENWEBUI_API_KEY "$OPENWEBUI_API_KEY_VAL"
  log "generated and persisted OPENWEBUI_API_KEY to $ENV_FILE (recreate homepage to pick it up)."
else
  log "OPENWEBUI_API_KEY already set — idempotent no-op."
fi

log "DONE."
