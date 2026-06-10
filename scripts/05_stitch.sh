#!/usr/bin/env bash
# ==============================================================================
# 🚀 ARCHITECTURE COMPILER & ENVIRONMENT STITCHER (v4.0)
# Path: scripts/05_stitch.sh
# ==============================================================================
set -Eeuo pipefail

SYNCHED_ALIASES="$HOME/.bash_aliases_pro"
DATA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log_info() { echo -e "\e[1;34m[COMPILER]\e[0m \e[1;36m▶ $1\e[0m"; }
log_success() { echo -e "\e[1;32m[SUCCESS] ✔ $1\e[0m"; }

log_info "Initializing compilation sequence..."

# 1. Establish fresh, untainted active runtime file
cat << EOF > "$SYNCHED_ALIASES"
# ==============================================================================
# 🛠️ SYNCHED AUTOMATED DESKTOP PROFILE (DYNAMICALLY COMPILED - DO NOT EDIT)
# Engine Matrix Version: 2026.4
# Generated: $(date)
# Source Core: $DATA_DIR
# ==============================================================================
EOF

# 2. Parse and Compile structural data mappings (aliases.env)
if [ -f "$DATA_DIR/aliases.env" ]; then
    log_info "Processing shortcuts database [aliases.env]..."
    echo -e "\n# --- HARDCODED RUNTIME TRANSLATIONS ---" >> "$SYNCHED_ALIASES"
    
    while IFS='=' read -r key value || [ -n "$key" ]; do
        # Sanitize whitespace, skip declarations, empty vectors, or raw annotations
        key=$(echo "$key" | xargs 2>/dev/null || echo "$key")
        [[ "$key" =~ ^#.*$ ]] && continue
        [[ -z "$key" ]] && continue
        
        # Strip string-literal quotes cleanly
        clean_value=$(echo "$value" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
        echo "alias ${key}='${clean_value}'" >> "$SYNCHED_ALIASES"
    done < "$DATA_DIR/aliases.env"
fi

# 3. Concatenate and Inject Core System Operational Scripts (functions.env)
if [ -f "$DATA_DIR/functions.env" ]; then
    log_info "Injecting custom binary functional scopes [functions.env]..."
    echo -e "\n# --- INTEGRATED ORCHESTRATION FUNCTIONS ---" >> "$SYNCHED_ALIASES"
    cat "$DATA_DIR/functions.env" >> "$SYNCHED_ALIASES"
fi

# 4. Bind compiled asset upstream matrix securely inside local machine profiles
if ! grep -q "source $SYNCHED_ALIASES" "$HOME/.bashrc"; then
    log_info "Stitching local manifest references within home shell profile..."
    cat << EOF >> "$HOME/.bashrc"

# --- SYNCED MANIFESTATION ORCHESTRATION LAYER ---
if [ -f "$SYNCHED_ALIASES" ]; then
    source "$SYNCHED_ALIASES"
fi
EOF
fi

log_success "Environment profiles compiled down to active machine: $SYNCHED_ALIASES"