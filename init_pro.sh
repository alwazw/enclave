#!/usr/bin/env bash

# ==============================================================================
# 🚀 PRO-SPEC UBUNTU SYSTEM INITIALIZATION (v3.1 - FINAL ROBUST EDITION)
# ==============================================================================
# Logic: 
#   1. Priviledge Check
#   2. Overwrites a MANAGED alias file (~/.bash_aliases_pro) to prevent duplicates.
#   3. Stitches that file into the main ~/.bashrc managed by your Git repo.
#   4. Uses official Docker repos and merges all tools from your files.
# ==============================================================================

# ------------------------------------------------------------------------------
# FAULT HANDLING & TELEMETRY CONFIGURATION
# ------------------------------------------------------------------------------

set -o pipefail

# --- LOGGING UTILITIES ---
log_info() { echo -e "\n\e[1;34m[INFO]\e[0m \e[1;36m▶ $1\e[0m"; }
log_success() { echo -e "\e[1;32m[SUCCESS] ✔ $1\e[0m"; }
log_warn() { echo -e "\e[1;33m[WARNING] ⚠️  $1\e[0m"; }
log_error() { echo -e "\e[1;31m[ERROR] ❌ $1\e[0m"; }

# --- FAULT HANDLING ---
failure_trap() {
    local exit_code=$?
    log_error "CRITICAL INTERRUPT: Execution failed at line $1 with Exit Code: ${exit_code}"
    exit "${exit_code}"
}
trap 'failure_trap ${LINENO}' ERR

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# ------------------------------------------------------------------------------
# 1. PRIVILEGE CHECK & ELEVATION LOOP
# ------------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
    echo -e "\e[1;35m==================================================\e[0m"
    echo -e "\e[1;32m   Privilege Elevation Required for Suite Logic   \e[0m"
    echo -e "\e[1;35m==================================================\e[0m"
    echo "1. Enter sudo password to apply changes"
    echo "2. Exit - No changes will be made"
    echo "--------------------------------------------------"
    read -p "Select an option (1 or 2): " CHOICE

    case "$CHOICE" in
        1)
            log_info "Requesting sudo elevation..."
            # Re-execute script as root, preserving environment
            exec sudo "$0" "$@"
            ;;
        2|*)
            log_warn "User aborted elevation. Exiting."
            exit 0
            ;;
    esac
fi

# ------------------------------------------------------------------------------
# 2. MODULAR EXECUTION (EUID IS 0)
# ------------------------------------------------------------------------------
log_info "Authenticated as root. Commencing Modular Suite Deployment..."

# Verify the scripts directory exists before looping
if [ ! -d "scripts" ]; then
    log_error "Directory 'scripts/' not found. Ensure you are in the repo root."
    exit 1
fi

# Iterate over all .sh files in alphabetical/numerical order [3, 4]
for script in scripts/*.sh; do
    if [ -f "$script" ]; then
        log_info "Executing Module: $script"
        # Run with bash to ensure sub-scripts execute in a clean environment
        bash "$script" || exit 1
    fi
done


