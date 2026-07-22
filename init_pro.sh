#!/usr/bin/env bash
# ==============================================================================
# 🚀 ENTERPRISE UBUNTU INITIALIZATION SUITE (THE PRO-SPEC ORCHESTRATOR)
# Path: ./init_pro.sh
# ==============================================================================
set -Eeuo pipefail
trap 'failure_handler $? $LINENO' ERR

# Diagnostics and Logging Framework
log_info() { echo -e "\n\e[1;34m[INFO]\e[0m \e[1;36m▶ $1\e[0m"; }
log_success() { echo -e "\e[1;32m[SUCCESS] ✔ $1\e[0m"; }
log_warn() { echo -e "\e[1;33m[WARNING] ⚠️ $1\e[0m"; }
log_error() { echo -e "\e[1;31m[ERROR] ❌ $1\e[0m"; }

failure_handler() {
    local exit_code=$1
    local line_no=$2
    log_error "Critical system failure captured inside initialization timeline (Line: ${line_no} | Exit Status: ${exit_code})"
    exit "${exit_code}"
}

# Gatekeeper: Ensure execution happens under root validation loops
if [ "$EUID" -ne 0 ]; then
   log_error "This suite requires elevated administrative orchestration privileges. Re-run execution leveraging 'sudo ./init_pro.sh'"
   exit 1
fi

# Identify calling non-root user variables dynamically
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(eval echo "~$TARGET_USER")
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log_info "Bootstrapping Modular Provisioning Framework for System User: ${TARGET_USER}"

# Pre-create the shared deploy log owned by the target user.
# Rationale: modules run as root, but 05_stitch.sh runs as the target user via
# `sudo -u`. It (and 00_init_core.sh) append to LOG_FILE with `tee -a`. Under a
# root-owned /var/log file that append fails for the non-root user and, with
# `pipefail`, aborts the run. Creating it up front with the right owner makes
# logging work identically for both root- and user-context modules.
if [ -f "$BASE_DIR/config.env" ]; then
    # shellcheck disable=SC1091
    source "$BASE_DIR/config.env"
fi
LOG_FILE="${LOG_FILE:-/var/log/ubuntu-customz-deploy.log}"
touch "$LOG_FILE" 2>/dev/null || true
chown "$TARGET_USER":"$TARGET_USER" "$LOG_FILE" 2>/dev/null || true
chmod 0664 "$LOG_FILE" 2>/dev/null || true

# Ensure interactive dialog boxes are present natively
if ! command -v whiptail &>/dev/null; then
    log_warn "Whiptail UI engine missing. Initializing runtime package manager dependency hooks..."
    apt-get update && apt-get install -y whiptail
fi

# ------------------------------------------------------------------------------
# STEP 1: DEPLOYMENT PROFILE SELECTION (interactive + non-interactive)
# ------------------------------------------------------------------------------
# Selection precedence:
#   1. PROFILE environment variable  -> unattended / CI runs
#        Accepted values: full | stitch | abort  (also 1 | 2 | 3)
#   2. Interactive whiptail TUI menu -> only when STDIN is a real terminal
#   3. Fallback default = "full"     -> no TTY and no PROFILE (piped/unattended)
#
# Example unattended invocation:
#   sudo PROFILE=full   bash init_pro.sh
#   sudo PROFILE=stitch bash init_pro.sh
#
# normalize_profile(): map any accepted alias/number to a canonical keyword
#   so there is a single downstream code path regardless of input source.
normalize_profile() {
    case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
        1|full|full-suite|all)   echo "full"   ;;
        2|stitch|stitch-only)    echo "stitch" ;;
        3|abort|cancel|quit)     echo "abort"  ;;
        *)                       echo ""       ;;
    esac
}

PROFILE_RAW="${PROFILE:-}"
PROFILE_SELECTED="$(normalize_profile "$PROFILE_RAW")"

# A PROFILE was supplied but is not recognized -> fail fast (don't guess).
if [ -n "$PROFILE_RAW" ] && [ -z "$PROFILE_SELECTED" ]; then
    log_error "Unrecognized PROFILE='${PROFILE_RAW}' (expected: full | stitch | abort)"
    exit 1
fi

# No PROFILE provided: use the interactive menu on a TTY, else default to full.
if [ -z "$PROFILE_SELECTED" ]; then
    if [ -t 0 ] && command -v whiptail &>/dev/null; then
        CHOICE=$(whiptail --title "Ubuntu Pro-Spec Architecture Deployment" \
        --menu "Choose your desired machine targeting profiles:" 15 60 4 \
        "1" "Full Suite Installation (All Modules + System Upgrades)" \
        "2" "Environment Configuration Re-Compile (Stitch Only)" \
        "3" "Abort Routine Initialization" 3>&1 1>&2 2>&3)
        PROFILE_SELECTED="$(normalize_profile "$CHOICE")"
    else
        log_warn "No TTY and no PROFILE set — defaulting to unattended 'full' profile."
        PROFILE_SELECTED="full"
    fi
fi

log_info "Selected deployment profile: ${PROFILE_SELECTED:-abort}"

case "$PROFILE_SELECTED" in
    full)
        log_info "Beginning system configuration profiling baseline matrix..."
        ;;
    stitch)
        log_info "Isolating framework layers. Executing configuration tree compilers..."
        sudo -u "$TARGET_USER" env TARGET_USER="$TARGET_USER" TARGET_HOME="$TARGET_HOME" \
            bash "$BASE_DIR/scripts/05_stitch.sh"
        log_success "Profile compilation complete. Session operations resolved successfully."
        exit 0
        ;;
    *)
        log_warn "Installation procedure abandoned gracefully (profile: ${PROFILE_SELECTED:-none})."
        exit 0
        ;;
esac

# ------------------------------------------------------------------------------
# STEP 2: DETERMINISTIC LOOP ITERATION OVER MODULAR COMPONENT SCRIPTS
# ------------------------------------------------------------------------------
# Iterate through scripts cleanly by alphanumeric index markers
MODULES=(
    "01_privileges.sh"
    "02_environment.sh"
    "03_tools.sh"
    "04_optimization.sh"
    "05_stitch.sh"
)

for script in "${MODULES[@]}"; do
    SCRIPT_PATH="$BASE_DIR/scripts/$script"
    if [ -f "$SCRIPT_PATH" ]; then
        log_info "Executing Modular Module Task: [ $script ]"
        chmod +x "$SCRIPT_PATH"
        
        # Execute orchestration hooks keeping target execution ownership pristine.
        # 05_stitch runs as the *target* user; pass the resolved user/home through
        # `env` so config.env doesn't mis-derive them from the nested sudo context.
        if [ "$script" == "05_stitch.sh" ]; then
            sudo -u "$TARGET_USER" env TARGET_USER="$TARGET_USER" TARGET_HOME="$TARGET_HOME" \
                bash "$SCRIPT_PATH"
        else
            bash "$SCRIPT_PATH"
        fi
        log_success "Task Verification Standard Complete: [ $script ]"
    else
        log_warn "Expected optimization payload not found at target directory mapping: $script"
    fi
done

echo -e "\n\e[1;32m========================================================================\e[0m"
log_success "PRO-SPEC INITIALIZATION COMPILATION TRACEWAY STACK COMPLETE"
echo -e "\e[1;32m========================================================================\e[0m"
log_warn "NOTICE: Source the updated interface profile mapping to inherit environmental context variables:"
echo -e "         \e[1;37msource ~/.bashrc\e[0m\n"