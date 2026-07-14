#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
# Hermes boot-time config reconciler (AEF2 local stack)
#
# Deep-merges the committed override fragment (hermes-config.yaml, mounted at
# /hermes-config.yaml) into $HERMES_HOME/config.yaml, which Hermes itself seeds
# and migrates during cont-init. Idempotent: safe to run on every boot.
#
# Runs as the `hermes` user with the venv on PATH (main-wrapper.sh activates it
# and drops privileges before exec'ing this via the container command).
#
# SECRET-FREE: no API keys are written. The LiteLLM key is resolved at runtime
# from $LITELLM_API_KEY via the provider's `key_env` mapping.
# ─────────────────────────────────────────────────────────────────────────────
set -eu

HOME_DIR="${HERMES_HOME:-/opt/data}"
CONFIG="$HOME_DIR/config.yaml"
FRAGMENT="${HERMES_CONFIG_FRAGMENT:-/hermes-config.yaml}"

if [ ! -f "$FRAGMENT" ]; then
    echo "[hermes-init] WARNING: fragment $FRAGMENT not found; leaving config.yaml untouched" >&2
    exit 0
fi

python3 - "$CONFIG" "$FRAGMENT" <<'PY'
import os, sys, yaml

cfg_path, frag_path = sys.argv[1], sys.argv[2]

def load(p):
    if os.path.exists(p):
        with open(p) as fh:
            return yaml.safe_load(fh) or {}
    return {}

def deep_merge(base, over):
    for k, v in over.items():
        if isinstance(v, dict) and isinstance(base.get(k), dict):
            deep_merge(base[k], v)
        else:
            base[k] = v
    return base

cfg = load(cfg_path)
frag = load(frag_path)
deep_merge(cfg, frag)

tmp = cfg_path + ".tmp"
with open(tmp, "w") as fh:
    yaml.safe_dump(cfg, fh, sort_keys=False)
os.replace(tmp, cfg_path)

m = cfg.get("model", {}) or {}
print(f"[hermes-init] merged {frag_path} -> {cfg_path}: "
      f"provider={m.get('provider')} model={m.get('default')} "
      f"base_url={m.get('base_url')}")
PY
