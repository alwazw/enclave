#!/usr/bin/env bash
# #20: remove exited one-shot job containers (e.g. affine-migration) so they
# don't sit "Exited" forever, reading as "down" in Homepage/Portainer even
# though exit 0 means success.
#
# Extracted out of onboard.sh's bring_up() (still calls this script) so it can
# ALSO run periodically via cron/systemd without requiring a full manual
# onboarding/deploy run — #20's original fix only ran inside bring_up(), so it
# only cleaned up once, during the fix's own verification, then never fired
# again until someone next ran the whole installer by hand.
#
# Safe to remove: compose recreates and reruns a removed one-shot job
# (idempotent migration script) before starting the real service again.
set -euo pipefail

log() { printf '[cleanup-oneshot-jobs] %s\n' "$*"; }

exited_jobs="$(docker ps -a --filter "label=aef2.oneshot=true" --filter "status=exited" -q)"
if [ -n "$exited_jobs" ]; then
  echo "$exited_jobs" | xargs -r docker rm >/dev/null
  log "cleaned up $(echo "$exited_jobs" | wc -l) completed one-shot job container(s)."
else
  log "nothing to clean up."
fi
