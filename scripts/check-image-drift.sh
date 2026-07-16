#!/usr/bin/env bash
# Checks every pinned image tag in requirements.yml for real drift since the
# last time this ran — Recommendation 1 from #16 (nothing caught the Flowise
# auth-model change or docling's GPU/CPU tag split until a full manual
# deep-validate sweep). Read-only: anonymous registry API calls only, never
# touches the running stack.
#
# Design note (learned the hard way — an earlier version of this script
# compared each pinned tag against "the most-recently-updated tag in the
# repo" and it was NOISE: rolling tags like :latest constantly lost to
# unrelated nightly/PR/dev-branch tags being pushed more often, and even a
# real version tag on Quay (docling-serve:v0.5.1) lost to an OLDER v0.4.0
# because Quay's last_modified isn't a reliable version-recency signal.
# Dropped that approach entirely rather than ship a tool that cries wolf.
#
# What this DOES reliably: records each pinned tag's current digest and
# compares it against the digest recorded the previous run
# (.github/image-digest-state.json, committed to the repo). A changed
# digest on a supposedly-stable pin (docling:v0.5.1, portainer:2.43.0-alpine)
# means the upstream image was silently rebuilt under the same tag — worth
# knowing. A changed digest on a :latest/:main-style pin just means normal
# upstream movement, reported as an FYI rather than an alarm.
#
# Supports Docker Hub (docker.io, incl. official "library/x") and GHCR
# (ghcr.io) — both have anonymous digest-lookup APIs. Quay.io and anything
# else are reported as UNSUPPORTED, not silently skipped.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REQUIREMENTS_FILE="${REQUIREMENTS_FILE:-$REPO_DIR/requirements.yml}"
STATE_FILE="${STATE_FILE:-$REPO_DIR/.github/image-digest-state.json}"

[ -f "$REQUIREMENTS_FILE" ] || { echo "requirements.yml not found at $REQUIREMENTS_FILE" >&2; exit 2; }

changed_count=0
missing_count=0
unsupported_count=0
unchanged_count=0

declare -A NEW_DIGESTS

is_rolling_tag() {
  case "$1" in
    latest|main|main-stable|stable|nightly|develop|dev) return 0 ;;
    *) return 1 ;;
  esac
}

check_docker_hub() {
  local namespace="$1"
  local repo="$2"
  local tag="$3"
  local key="docker.io/${namespace}/${repo}:${tag}"
  local cur_digest
  cur_digest=$(curl -sS -m 15 "https://hub.docker.com/v2/repositories/${namespace}/${repo}/tags/${tag}" 2>/dev/null \
    | python3 -c "import json,sys
try: print(json.load(sys.stdin)['images'][0]['digest'])
except Exception: print('')" 2>/dev/null)
  report "$key" "$cur_digest"
}

check_ghcr() {
  local repo="$1"
  local tag="$2"
  local key="ghcr.io/${repo}:${tag}"
  local tok cur_digest
  tok=$(curl -sS -m 15 "https://ghcr.io/token?scope=repository:${repo}:pull&service=ghcr.io" 2>/dev/null \
        | python3 -c "import json,sys
try: print(json.load(sys.stdin)['token'])
except Exception: print('')" 2>/dev/null)
  if [ -z "$tok" ]; then
    echo "UNSUPPORTED ${key} — could not obtain anonymous pull token"
    unsupported_count=$((unsupported_count+1))
    return
  fi
  cur_digest=$(curl -sS -m 15 -H "Authorization: Bearer ${tok}" \
    -H "Accept: application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json" \
    -I "https://ghcr.io/v2/${repo}/manifests/${tag}" 2>/dev/null \
    | grep -i '^docker-content-digest:' | tr -d '\r' | awk '{print $2}')
  report "$key" "$cur_digest"
}

report() {
  local key="$1" cur_digest="$2"
  local tag="${key##*:}"
  if [ -z "$cur_digest" ]; then
    echo "MISSING     ${key} — could not resolve a digest (tag may no longer exist)"
    missing_count=$((missing_count+1))
    return
  fi
  NEW_DIGESTS["$key"]="$cur_digest"
  local prev_digest
  prev_digest=$(python3 -c "import json,sys
try:
    d=json.load(open('$STATE_FILE'))
    print(d.get('$key',''))
except Exception:
    print('')" 2>/dev/null)
  if [ -z "$prev_digest" ]; then
    echo "BASELINE    ${key} — no prior recorded digest, recording now"
    unchanged_count=$((unchanged_count+1))
  elif [ "$prev_digest" != "$cur_digest" ]; then
    if is_rolling_tag "$tag"; then
      echo "MOVED (fyi) ${key} — digest changed since last check (expected for a rolling tag)"
    else
      echo "CHANGED     ${key} — digest changed since last check on a VERSIONED pin — investigate"
    fi
    changed_count=$((changed_count+1))
  else
    echo "OK          ${key} — unchanged since last check"
    unchanged_count=$((unchanged_count+1))
  fi
}

while IFS= read -r image; do
  [ -z "$image" ] && continue
  repo_tag="${image%:*}"
  tag="${image##*:}"
  if [[ "$repo_tag" == ghcr.io/* ]]; then
    check_ghcr "${repo_tag#ghcr.io/}" "$tag"
  elif [[ "$repo_tag" == *"."*"/"* && "$repo_tag" != docker.io/* ]]; then
    echo "UNSUPPORTED ${repo_tag}:${tag} — registry not implemented (only docker.io/ghcr.io are)"
    unsupported_count=$((unsupported_count+1))
  else
    repo_tag="${repo_tag#docker.io/}"
    if [[ "$repo_tag" == */* ]]; then
      check_docker_hub "${repo_tag%%/*}" "${repo_tag#*/}" "$tag"
    else
      check_docker_hub "library" "$repo_tag" "$tag"
    fi
  fi
done < <(python3 -c "
import yaml, sys
with open('$REQUIREMENTS_FILE') as f:
    d = yaml.safe_load(f)
for img in d.get('image_tags', []):
    print(img)
" 2>/dev/null)

echo "---"
echo "unchanged=${unchanged_count} changed=${changed_count} missing=${missing_count} unsupported=${unsupported_count}"

# Persist new state (only if not a dry run)
if [ "${DRY_RUN:-0}" != "1" ]; then
  python3 -c "
import json
new = {
$(for k in "${!NEW_DIGESTS[@]}"; do printf '    %s: %s,\n' "$(python3 -c "import json;print(json.dumps('''$k'''))")" "$(python3 -c "import json;print(json.dumps('''${NEW_DIGESTS[$k]}'''))")"; done)
}
import os
os.makedirs('$(dirname "$STATE_FILE")', exist_ok=True)
with open('$STATE_FILE', 'w') as f:
    json.dump(new, f, indent=2, sort_keys=True)
    f.write('\n')
"
fi

[ "$missing_count" -eq 0 ]
