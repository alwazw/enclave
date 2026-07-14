#!/usr/bin/env bash
# Headless, idempotent first-run initialization for TriliumNext (knowledge profile).
#
# TriliumNext ships a first-run *setup wizard*: a fresh `document.db` has 0 tables and
# `/api/setup/status` reports {isInitialized:false, schemaExists:false}. The container is
# `healthy` and serves HTTP 200 but only the wizard — non-functional for a real user.
#
# This script drives the same two steps the wizard performs, non-interactively:
#   1) POST /api/setup/new-document  -> runs schema.sql, creates the root note, imports the
#      built-in demo notebook (the wizard's default; the "skip demo" path is not exposed by
#      this API endpoint). After this, status = {isInitialized:true, schemaExists:true} but
#      no password is set, so the app redirects to /set-password.
#   2) POST /set-password (form: password1/password2) -> sets the admin password from .env,
#      after which `/` redirects to /login (the real notes app) and ETAPI login works.
#
# Idempotent: if already initialized, it exits 0 without touching anything.
# Secret handling: the password is read from the gitignored .env (TRILIUM_PASSWORD) and is
# never echoed or passed on argv.
set -euo pipefail

BASE_URL="${TRILIUM_BASE_URL:-http://127.0.0.1:8190}"
ENV_FILE="${ENV_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.env}"

log() { printf '[init-trilium] %s\n' "$*"; }

status() { curl -fsS "${BASE_URL}/api/setup/status"; }

# --- read password from .env (last-write-wins to match docker compose) ---
if [ ! -f "$ENV_FILE" ]; then log "ERROR: env file not found: $ENV_FILE"; exit 1; fi
TRILIUM_PASSWORD="$(grep -E '^TRILIUM_PASSWORD=' "$ENV_FILE" | tail -1 | cut -d= -f2- || true)"
if [ -z "${TRILIUM_PASSWORD}" ]; then
  log "ERROR: TRILIUM_PASSWORD not set in $ENV_FILE"; exit 1
fi

# --- wait for the server to answer setup/status ---
for i in $(seq 1 30); do
  if status >/dev/null 2>&1; then break; fi
  [ "$i" = "30" ] && { log "ERROR: server not reachable at ${BASE_URL}"; exit 1; }
  sleep 2
done

INIT="$(status | sed -n 's/.*"isInitialized":\([a-z]*\).*/\1/p')"
if [ "$INIT" = "true" ]; then
  log "already initialized -> $(status)"; exit 0
fi

log "initializing document (schema + root note + demo)..."
curl -fsS -X POST "${BASE_URL}/api/setup/new-document" >/dev/null
log "post-init status: $(status)"

log "setting admin password from ${ENV_FILE}..."
code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "${BASE_URL}/set-password" \
  --data-urlencode "password1=${TRILIUM_PASSWORD}" \
  --data-urlencode "password2=${TRILIUM_PASSWORD}")"
# 302 -> /login on success
if [ "$code" != "302" ] && [ "$code" != "200" ]; then
  log "ERROR: set-password returned HTTP ${code}"; exit 1
fi

# verify password works via ETAPI login (proves a real user can authenticate)
tok="$(curl -fsS -X POST "${BASE_URL}/etapi/auth/login" -H 'Content-Type: application/json' \
  --data "{\"password\":\"${TRILIUM_PASSWORD}\",\"tokenName\":\"init-verify\"}" \
  | sed -n 's/.*"authToken":"\([^"]*\)".*/\1/p')"
if [ -z "$tok" ]; then log "ERROR: ETAPI login failed after set-password"; exit 1; fi

log "DONE. initialized + password set + ETAPI login verified. status: $(status)"
