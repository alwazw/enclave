#!/usr/bin/env bash
# Renders agents/hermes/SOUL.md from SOUL.md.template, substituting real
# .env values (#30: SOUL.md was static plain text — the HERMES_NAME env var
# reached the container fine but the persona file that actually defines
# self-identification never read it, so the bot kept calling itself
# "Hermes" even with HERMES_NAME=Morpheus set).
#
# Must run HOST-SIDE, before `docker compose up`: hermes.yml bind-mounts
# this file read-only into the container, so the container itself can
# never render it — the substitution has to already be done by the time
# the mount happens.
#
# Idempotent: safe to re-run any time (e.g. after changing HERMES_NAME in
# .env) — just re-renders from the template, overwriting the previous
# render. Not gitignored on purpose: keeping a real, readable file
# committed (rendered with the defaults below) means a fresh clone still
# has a working persona file even before anyone runs this script.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="${ENV_FILE:-$REPO_DIR/.env}"
TEMPLATE="$REPO_DIR/agents/hermes/SOUL.md.template"
OUT_FILE="$REPO_DIR/agents/hermes/SOUL.md"

read_env() { [ -f "$ENV_FILE" ] && grep -E "^${1}=" "$ENV_FILE" | tail -1 | cut -d= -f2- || true; }

HERMES_NAME="$(read_env HERMES_NAME)"; HERMES_NAME="${HERMES_NAME:-Hermes}"
PRODUCT_NAME="$(read_env PRODUCT_NAME)"; PRODUCT_NAME="${PRODUCT_NAME:-Enclave}"

sed \
  -e "s/{{HERMES_NAME}}/${HERMES_NAME}/g" \
  -e "s/{{PRODUCT_NAME}}/${PRODUCT_NAME}/g" \
  "$TEMPLATE" > "$OUT_FILE"

printf '[render-soul] Rendered %s (HERMES_NAME=%s, PRODUCT_NAME=%s)\n' "$OUT_FILE" "$HERMES_NAME" "$PRODUCT_NAME"
