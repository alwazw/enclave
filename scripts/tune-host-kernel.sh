#!/usr/bin/env bash
# Applies host kernel tunables this stack's services recommend at startup —
# currently just vm.overcommit_memory=1, which Redis's own startup log warns
# about: "Memory overcommit must be enabled! Without it, a background save
# or replication may fail under low memory condition."
#
# NOT auto-run by onboard.sh: this is a persistent, HOST-WIDE kernel change
# (affects every process on the host, forever, across reboots via
# /etc/sysctl.d) — outside docker/compose's scope entirely, and requires
# root. Run explicitly, with sudo, when you're ready to accept that:
#   sudo bash scripts/tune-host-kernel.sh
#
# Idempotent: safe to re-run. Only appends the sysctl.d drop-in if it
# doesn't already exist; only changes the live value if it's not already 1.
set -euo pipefail

[ "$(id -u)" = "0" ] || { echo "Must run as root: sudo bash $0" >&2; exit 1; }

DROPIN=/etc/sysctl.d/99-aef2-redis.conf

if [ "$(sysctl -n vm.overcommit_memory)" != "1" ]; then
  sysctl -w vm.overcommit_memory=1
  echo "Applied vm.overcommit_memory=1 for this boot."
else
  echo "vm.overcommit_memory already 1 for this boot — no change needed."
fi

if [ ! -f "$DROPIN" ]; then
  printf '# Redis requires this — see startup warning in docker logs redis\nvm.overcommit_memory = 1\n' > "$DROPIN"
  echo "Persisted to ${DROPIN} (survives reboot)."
else
  echo "${DROPIN} already exists — not overwriting."
fi
