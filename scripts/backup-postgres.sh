#!/usr/bin/env bash
#
# backup-postgres.sh — Scheduled logical backup of the AEF2 Postgres cluster.
#
# What it does (idempotent, non-destructive):
#   1. pg_dumpall --globals-only        -> globals.sql.gz   (roles / grants)
#   2. per-DB pg_dump (plain SQL)       -> <db>.sql.gz      (schema + data)
#   3. writes SHA256SUMS + a MANIFEST    (sizes, row markers)
#   4. prunes to the last N dated backups (default 14 = 14 days daily)
#   5. atomically updates backups/LATEST -> newest COMPLETE backup dir
#
# Secrets: POSTGRES_* are read from .env and passed to the container via the
# process environment (docker exec --env NAME), never on the command line, and
# are never echoed. The dump itself uses the container's local unix socket.
#
# Exit non-zero on ANY dump/validation failure; LATEST is only advanced after a
# fully successful, validated run, so LATEST never points at a partial backup.
#
set -euo pipefail

# --- Config -----------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$REPO_ROOT/.env}"
BACKUP_ROOT="${BACKUP_ROOT:-$REPO_ROOT/backups}"
CONTAINER="${PG_CONTAINER:-aef2_postgres}"
RETENTION="${RETENTION:-14}"          # keep this many dated backup dirs
# Service databases to dump (globals are handled separately).
DBS=(aef2 litellm n8n affine flowise langfuse mem0)

log() { printf '%s [backup-postgres] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
die() { printf '%s [backup-postgres][ERROR] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; exit 1; }

# --- Preconditions ----------------------------------------------------------
[ -f "$ENV_FILE" ] || die "env file not found: $ENV_FILE"
command -v docker >/dev/null 2>&1 || die "docker not on PATH"
docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -q true \
  || die "container '$CONTAINER' is not running"

# Read creds from .env (tail -1 => last-write-wins, matching compose behaviour).
# Values are captured into shell vars only; never printed.
read_env() { grep -E "^$1=" "$ENV_FILE" | tail -1 | cut -d= -f2- ; }
PGUSER_VAL="$(read_env POSTGRES_USER)"; : "${PGUSER_VAL:=aef2}"
PGPASSWORD_VAL="$(read_env POSTGRES_PASSWORD)"
export PGPASSWORD="$PGPASSWORD_VAL"   # consumed by docker exec --env PGPASSWORD

# --- Backup -----------------------------------------------------------------
STAMP="$(date '+%Y-%m-%d_%H%M')"
DEST="$BACKUP_ROOT/$STAMP"
mkdir -p "$DEST"
log "starting backup -> $DEST (container=$CONTAINER user=$PGUSER_VAL)"
START_EPOCH=$(date +%s)

# pg exec helper: password via env (--env PGPASSWORD), never argv; local socket.
pgx() { docker exec --env PGPASSWORD "$CONTAINER" "$@"; }

# 1. Globals (roles/grants) — restore of per-DB owners depends on these.
log "dumping globals (--globals-only)"
pgx pg_dumpall -U "$PGUSER_VAL" --globals-only 2>>"$DEST/.stderr" \
  | gzip -c > "$DEST/globals.sql.gz"
[ -s "$DEST/globals.sql.gz" ] || die "globals dump is empty"

# 2. Per-DB dumps.
for db in "${DBS[@]}"; do
  log "dumping database '$db'"
  # --create makes each dump self-contained (CREATE DATABASE); restore-friendly.
  if ! pgx pg_dump -U "$PGUSER_VAL" --create --clean --if-exists "$db" \
        2>>"$DEST/.stderr" | gzip -c > "$DEST/$db.sql.gz"; then
    die "pg_dump failed for '$db' (see $DEST/.stderr)"
  fi
  [ -s "$DEST/$db.sql.gz" ] || die "dump for '$db' is empty"
  gzip -t "$DEST/$db.sql.gz" || die "gzip integrity check failed for '$db'"
done

# 3. Checksums + manifest.
( cd "$DEST" && sha256sum ./*.sql.gz > SHA256SUMS )
{
  echo "backup_stamp: $STAMP"
  echo "container: $CONTAINER"
  echo "pg_user: $PGUSER_VAL"
  echo "databases: ${DBS[*]} (+ globals)"
  echo "created_utc: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo ""
  echo "file                          bytes"
  for f in "$DEST"/*.sql.gz; do
    printf '%-30s %s\n' "$(basename "$f")" "$(stat -c %s "$f")"
  done
} > "$DEST/MANIFEST"
[ -s "$DEST/.stderr" ] || rm -f "$DEST/.stderr"

END_EPOCH=$(date +%s)
log "backup complete in $((END_EPOCH - START_EPOCH))s — $(du -sh "$DEST" | cut -f1)"

# 4. Advance LATEST pointer only now that the backup is complete + validated.
ln -sfn "$STAMP" "$BACKUP_ROOT/LATEST"
log "LATEST -> $STAMP"

# 5. Retention prune: keep newest $RETENTION dated dirs, delete older ones.
#    Strict pattern guard so we never touch non-backup dirs.
mapfile -t ALL < <(find "$BACKUP_ROOT" -maxdepth 1 -type d \
  -regextype posix-extended \
  -regex '.*/[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{4}' -printf '%f\n' | sort)
if [ "${#ALL[@]}" -gt "$RETENTION" ]; then
  prune_count=$(( ${#ALL[@]} - RETENTION ))
  for old in "${ALL[@]:0:$prune_count}"; do
    log "pruning old backup: $old"
    rm -rf "${BACKUP_ROOT:?}/$old"
  done
fi

log "done. retained: $(find "$BACKUP_ROOT" -maxdepth 1 -type d -regextype posix-extended -regex '.*/[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{4}' | wc -l) dated backup(s)."
