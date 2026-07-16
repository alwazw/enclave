#!/usr/bin/env bash
# Headless, idempotent first-run admin bootstrap for Open WebUI (core profile).
#
# ROOT CAUSE THIS CLOSES (verified against the running ghcr.io/open-webui/open-webui:main
# image's actual source, backend/open_webui/routers/auths.py, 2026-07-16):
#   Open WebUI's POST /api/v1/auths/signup deliberately does NOT gate the FIRST account
#   on ENABLE_SIGNUP/OPENWEBUI_ENABLE_SIGNUP — see the upstream code comment "Don't gate
#   the first admin on ENABLE_SIGNUP: it auto-disables and can persist stale across a DB
#   reset." This is intentional bootstrap design (there is no other non-interactive way to
#   create the first admin) — NOT a bug in ENABLE_SIGNUP itself. `/api/config` reports
#   `onboarding:true` for as long as zero users exist, and the FIRST successful signup
#   (by anyone reachable on the port) is auto-promoted to admin; only the 2nd+ signup is
#   actually blocked by ENABLE_SIGNUP. Same class of gap as AFFiNE (see .env comment,
#   dead-config finding 2026-07-13) and n8n's owner-claim step — this repo must claim that
#   first-user slot atomically as part of bring-up, before the port is meaningfully
#   reachable by anyone else. Mirrors the scripts/init-trilium.sh idiom.
#
# What this does:
#   1) GET /api/config -> {"onboarding": true|false}. onboarding:true means zero users
#      exist yet (the vulnerable window).
#   2) If onboarding:true -> POST /api/v1/auths/signup with the real admin's
#      name/email/password from .env. Open WebUI auto-promotes the first-ever account to
#      admin and immediately flips its own `ui.enable_signup` config to false (persisted
#      in the DB, not just the env var) — closing the window in the same call.
#   3) If onboarding:false -> a user already exists. Do NOT attempt another signup (would
#      either 403 or create a second, non-admin account). Instead verify the configured
#      admin's credentials actually log in. If they don't, someone else may have already
#      claimed the account (hostile race) -> exits non-zero so an operator investigates;
#      never silently reports success in that case.
#
# Idempotent: safe to re-run. Secret handling: password is read from the gitignored .env
# (OPENWEBUI_ADMIN_PASSWORD) and is never echoed or passed on argv (JSON body goes to
# curl via a temp file, not a command-line argument).
set -euo pipefail

BASE_URL="${OPENWEBUI_BASE_URL:-http://127.0.0.1:${OPENWEBUI_PORT:-3000}}"
ENV_FILE="${ENV_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.env}"

log() { printf '[init-open-webui-admin] %s\n' "$*"; }

# --- read config from .env (last-write-wins to match docker compose) ---
if [ ! -f "$ENV_FILE" ]; then log "ERROR: env file not found: $ENV_FILE"; exit 1; fi
envval() { grep -E "^${1}=" "$ENV_FILE" | tail -1 | cut -d= -f2-; }

OPENWEBUI_ADMIN_EMAIL="$(envval OPENWEBUI_ADMIN_EMAIL)"
OPENWEBUI_ADMIN_PASSWORD="$(envval OPENWEBUI_ADMIN_PASSWORD)"
OPENWEBUI_ADMIN_NAME="$(envval OPENWEBUI_ADMIN_NAME)"
OPENWEBUI_ADMIN_NAME="${OPENWEBUI_ADMIN_NAME:-Admin}"

if [ -z "${OPENWEBUI_ADMIN_EMAIL}" ] || [ -z "${OPENWEBUI_ADMIN_PASSWORD}" ]; then
  log "ERROR: OPENWEBUI_ADMIN_EMAIL / OPENWEBUI_ADMIN_PASSWORD not set in $ENV_FILE"
  exit 1
fi

config() { curl -fsS "${BASE_URL}/api/config"; }

# --- wait for the server to answer /api/config ---
for i in $(seq 1 30); do
  if config >/dev/null 2>&1; then break; fi
  [ "$i" = "30" ] && { log "ERROR: server not reachable at ${BASE_URL}"; exit 1; }
  sleep 2
done

# Open WebUI's /api/config only emits the "onboarding" key at all when it is true
# (`**({'onboarding': True} if onboarding else {})` in its source) — the key is
# omitted entirely once a user exists, it is never sent as a literal `false`.
is_onboarding() { printf '%s' "$1" | grep -q '"onboarding":true' && echo true || echo false; }

ONBOARDING="$(is_onboarding "$(config)")"

# tmpfile so the password never appears in `ps`/shell history via argv
BODY_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE"' EXIT

login() {
  printf '{"email":"%s","password":"%s"}' "$OPENWEBUI_ADMIN_EMAIL" "$OPENWEBUI_ADMIN_PASSWORD" > "$BODY_FILE"
  curl -s -o /dev/null -w '%{http_code}' -X POST "${BASE_URL}/api/v1/auths/signin" \
    -H 'Content-Type: application/json' --data-binary "@${BODY_FILE}"
}

if [ "$ONBOARDING" != "true" ]; then
  log "onboarding already false (a user already exists) — verifying configured admin can log in, not re-signing up."
  code="$(login)"
  if [ "$code" = "200" ]; then
    log "DONE. Admin account already claimed and verified working. No action needed."
    exit 0
  else
    log "ERROR: onboarding is false but the configured admin credentials do NOT log in (HTTP ${code})."
    log "This means a different account already claimed the first-user/admin slot (possible race)."
    log "Manual investigation required — do not assume this is safe."
    exit 1
  fi
fi

log "onboarding:true (zero users) — claiming the first-user admin slot now."
printf '{"name":"%s","email":"%s","password":"%s"}' \
  "$OPENWEBUI_ADMIN_NAME" "$OPENWEBUI_ADMIN_EMAIL" "$OPENWEBUI_ADMIN_PASSWORD" > "$BODY_FILE"
signup_code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "${BASE_URL}/api/v1/auths/signup" \
  -H 'Content-Type: application/json' --data-binary "@${BODY_FILE}")"
if [ "$signup_code" != "200" ]; then
  log "ERROR: signup returned HTTP ${signup_code} — did another visitor win the race first?"
  log "post-attempt config: $(config)"
  exit 1
fi

# verify: (a) our admin can log in, (b) onboarding has flipped to false (window closed)
code="$(login)"
if [ "$code" != "200" ]; then
  log "ERROR: signup reported success but login verification failed (HTTP ${code})."
  exit 1
fi
POST_ONBOARDING="$(is_onboarding "$(config)")"
if [ "$POST_ONBOARDING" != "false" ]; then
  log "ERROR: admin created and login verified, but onboarding is still not false ($(config)) — investigate."
  exit 1
fi

log "DONE. Admin claimed + login verified + onboarding window closed. status: $(config)"
