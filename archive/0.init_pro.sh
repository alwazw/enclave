#!/bin/bash
### ?? PRO-SPEC ORCHESTRATOR
set -o pipefail
log_info() { echo -e "\n\e[1;34m[INFO]\e[0m \e[1;36m? $1\e[0m"; }
log_success() { echo -e "\e[1;32m[SUCCESS] ? $1\e[0m"; }
failure_trap() { 
    echo -e "\e[1;31m[ERROR] ? Execution failed at line $1\e[0m"; exit 1 
}
trap 'failure_trap ${LINENO}' ERR

log_info "Initializing Modular Suite..."
if [ "$EUID" -eq 0 ]; then echo "Do not run as root."; exit 1; fi

# Iterate over all .sh files in scripts/ directory [11]
for script in scripts/*.sh; do
    log_info "Executing Module: $script"
    bash "$script" || exit 1
done

log_success "INITIALIZATION COMPLETE. Run 'source ~/.bashrc' to apply."

