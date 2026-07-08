#!/usr/bin/env bash
# ==============================================================================
# 🚀 ARCHITECTURE COMPILER & ENVIRONMENT STITCHER (v4.0.1)
# Path: scripts/05_stitch.sh
# ==============================================================================
set -Eeuo pipefail

SYNCHED_ALIASES="$HOME/.bash_aliases_pro"
DATA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log_info() { echo -e "\e[1;34m[COMPILER]\e[0m \e[1;36m▶ $1\e[0m"; }
log_success() { echo -e "\e[1;32m[SUCCESS] ✔ $1\e[0m"; }
log_warn() { echo -e "\e[1;33m[WARNING] ⚠️ $1\e[0m"; }

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

# 2. Automatically inject Node/NPM/NVM environment profiles if discovered
# Looks in project root directory (var/node.env or node.env)
for node_path in "$DATA_DIR/var/node.env" "$DATA_DIR/node.env"; do
    if [ -f "$node_path" ]; then
        log_info "Processing Node & NPM system vectors [$(basename "$node_path")]..."
        echo -e "\n# --- NODE ENVIRONMENT RUNTIME CAPTURES ---" >> "$SYNCHED_ALIASES"
        cat "$node_path" >> "$SYNCHED_ALIASES"
        break
    fi
done

# 3. Parse and Compile structural data mappings (aliases.env)
if [ -f "$DATA_DIR/var/aliases.env" ]; then
    log_info "Processing shortcuts database [var/aliases.env]..."
    echo -e "\n# --- HARDCODED RUNTIME TRANSLATIONS ---" >> "$SYNCHED_ALIASES"

    while IFS='=' read -r key value || [ -n "$key" ]; do
        key=$(echo "$key" | xargs 2>/dev/null || echo "$key")
        [[ "$key" =~ ^#.*$ ]] && continue
        [[ -z "$key" ]] && continue

        clean_value=$(echo "$value" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
        echo "alias ${key}='${clean_value}'" >> "$SYNCHED_ALIASES"
    done < "$DATA_DIR/var/aliases.env"
else
    log_warn "Could not locate $DATA_DIR/var/aliases.env"
fi

# 4. Concatenate and Inject Core System Operational Scripts (functions.env)
if [ -f "$DATA_DIR/var/functions.env" ]; then
    log_info "Injecting custom binary functional scopes [var/functions.env]..."
    echo -e "\n# --- INTEGRATED ORCHESTRATION FUNCTIONS ---" >> "$SYNCHED_ALIASES"
    cat "$DATA_DIR/var/functions.env" >> "$SYNCHED_ALIASES"
else
    log_warn "Could not locate $DATA_DIR/var/functions.env"
fi

# 5. Bind compiled asset upstream matrix securely inside local machine profiles
if ! grep -q "source $SYNCHED_ALIASES" "$HOME/.bashrc"; then
    log_info "Stitching local manifest references within home shell profile..."
    
    # Using single quotes around 'EOF' prevents Bash from trying to evaluate variables during injection
    cat << 'EOF' >> "$HOME/.bashrc"

# --- SYNCED MANIFESTATION ORCHESTRATION LAYER ---
if [ -f "$HOME/.bash_aliases_pro" ]; then
    source "$HOME/.bash_aliases_pro"
fi
EOF
fi

log_success "Environment profiles compiled down to active machine: $SYNCHED_ALIASES"
