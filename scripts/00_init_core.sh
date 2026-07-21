#!/bin/bash
# ---------------------------------------------------------------------
# scripts/00_init_core.sh - Structural Error Control & Log Routing
# ---------------------------------------------------------------------

# Strict Failures: Exit instantly if any subcommand or piped line fails
set -euo pipefail

# Error Trap Function: Records exactly where and why a script broke
error_trap_handler() {
    local exit_code=$?
    local line_num=$1
    echo "❌ FATAL SYSTEM ERROR: Pipeline crashed at line $line_num with Exit Code $exit_code." | tee -a "$LOG_FILE"
    exit "$exit_code"
}
trap 'error_trap_handler $LINENO' ERR

# Idempotent Append Function (Replaces 'echo >>' hazards)
safe_append_line() {
    local line_content="$1"
    local target_file="$2"
    
    # Touch the file first to ensure it securely exists
    touch "$target_file"
    
    # Only append if the line text pattern does not already exist inside the file
    if ! grep -Fxq "$line_content" "$target_file"; then
        echo "$line_content" >> "$target_file"
        echo "✅ Line successfully injected into $target_file" >> "$LOG_FILE"
    else
        echo "ℹ️ Config line already present in $target_file. Skipping append to prevent redundancy." >> "$LOG_FILE"
    fi
}
