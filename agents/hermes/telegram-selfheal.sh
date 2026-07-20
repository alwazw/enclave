#!/bin/sh
# One-shot Telegram boot-race self-heal (#29, permanent fix for #27's
# original symptom: NousResearch/hermes-agent#59202 — connect() hangs
# indefinitely at "attempt 1/8" during early container boot when network/DNS
# isn't fully settled yet). Guarded by a marker file so it fires at most once
# per container lifecycle — avoids a reconnect-storm if the underlying issue
# isn't fully resolved by one cycle.
#
# Scope: this targets the ORIGINAL stuck-at-"attempt 1/8" boot-race only. A
# separate, already-resolving getUpdates 409 conflict loop was observed
# during #27's follow-up investigation (Telegram-side session conflict, not
# a local hang) — this script does not detect or attempt to fix that; the
# log line it looks for ("Connecting to Telegram (attempt 1/8)") won't match
# once the adapter has moved past connect() into the conflict-retry loop.
#
# Invoked from hermes.yml's healthcheck (runs every `interval`, so it
# naturally re-checks until the marker is set) — but only as a background
# side effect. The healthcheck's PASS/FAIL is never gated on this: Hermes's
# core chat function is independent of the Telegram platform adapter, and
# other services' `depends_on: condition: service_healthy` must not block on
# a third-party bug in one optional messaging platform.
MARKER=/opt/data/.telegram-selfheal-attempted
LOGFILE=/opt/data/logs/gateway.log

[ -z "$TELEGRAM_BOT_TOKEN" ] && exit 0   # nothing to self-heal if Telegram isn't configured
[ -f "$MARKER" ] && exit 0
[ -f "$LOGFILE" ] || exit 0

LAST_TG_LINE=$(grep -a 'Telegram' "$LOGFILE" 2>/dev/null | tail -1)
case "$LAST_TG_LINE" in
  *'Connecting to Telegram (attempt 1/8)'*)
    LINE_TS=$(echo "$LAST_TG_LINE" | awk '{print $1" "$2}' | sed 's/,.*//')
    LINE_EPOCH=$(date -d "$LINE_TS" +%s 2>/dev/null || echo 0)
    NOW_EPOCH=$(date +%s)
    AGE=$((NOW_EPOCH - LINE_EPOCH))
    if [ "$LINE_EPOCH" -gt 0 ] && [ "$AGE" -ge 50 ]; then
      touch "$MARKER"
      ( HOME=/opt/data hermes gateway stop >/dev/null 2>&1
        sleep 2
        HOME=/opt/data hermes gateway run --replace >/dev/null 2>&1 ) &
    fi
    ;;
esac
exit 0
