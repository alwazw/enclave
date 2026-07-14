#!/usr/bin/env bash
# block-real-env.sh — refuse to stage any real .env file.
#
# Allowed (scaffolds with placeholder values only):
#   *.env.example   .env.example
#   *.env.template  .env.template
#
# Blocked (anything that could carry real secret values):
#   .env  .env.local  .env.production  compose/x/.env  ...
#
# Invoked by pre-commit with the staged file paths as arguments. Exits non-zero
# (blocking the commit) if any blocked path is present.
set -euo pipefail

blocked=0
for f in "$@"; do
  base="$(basename -- "$f")"
  case "$base" in
    *.example|*.template)
      # placeholder scaffolds — always allowed
      ;;
    .env|.env.*|*.env)
      echo "BLOCKED: refusing to stage real env file: $f" >&2
      echo "         Only *.example / *.template env files may be committed." >&2
      blocked=1
      ;;
  esac
done

if [ "$blocked" -ne 0 ]; then
  echo "" >&2
  echo "If this file is truly placeholder-only, rename it to .env.example or .env.template." >&2
  exit 1
fi
exit 0
