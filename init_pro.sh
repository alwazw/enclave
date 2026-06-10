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

# Ensure interactive dialog boxes are present natively
if ! command -v whiptail &>/dev/null; then
    log_warn "Whiptail UI engine missing. Initializing runtime package manager dependency hooks..."
    apt-get update && apt-get install -y whiptail
fi

# ------------------------------------------------------------------------------
# STEP 1: INTERACTIVE SELECTION DIALOG (Whiptail TUI Verification)
# ------------------------------------------------------------------------------
CHOICE=$(whiptail --title "Ubuntu Pro-Spec Architecture Deployment" \
--menu "Choose your desired machine targeting profiles:" 15 60 4 \
"1" "Full Suite Installation (All Modules + System Upgrades)" \
"2" "Environment Configuration Re-Compile (Stitch Only)" \
"3" "Abort Routine Initialization" 3>&1 1>&2 2>&3)

case "$CHOICE" in
    1)
        log_info "Beginning system configuration profiling baseline matrix..."
        ;;
    2)
        log_info "Isolating framework layers. Executing configuration tree compilers..."
        sudo -u "$TARGET_USER" bash "$BASE_DIR/scripts/05_stitch.sh"
        log_success "Profile compilation complete. Session operations resolved successfully."
        exit 0
        ;;
    *)
        log_warn "Installation procedure abandoned gracefully by user interface."
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
        
        # Execute orchestration hooks keeping target execution ownership pristine
        if [ "$script" == "05_stitch.sh" ]; then
            sudo -u "$TARGET_USER" bash "$SCRIPT_PATH"
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