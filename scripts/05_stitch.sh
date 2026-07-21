#!/bin/bash
# ---------------------------------------------------------------------
# scripts/05_stitch.sh - Secure, Non-Destructive Environment Compiler
# ---------------------------------------------------------------------
set -euo pipefail

# Source global parameters and error controllers
source "$(dirname "$0")/../config.env"
source "$(dirname "$0")/00_init_core.sh"

if [ "$EXEC_STITCH" -ne 1 ]; then
    echo "⏭️ Module [05_stitch] disabled in config.env. Skipping." | tee -a "$LOG_FILE"
    exit 0
fi

echo "🚀 [05_stitch] Initiating environment compilation for user: $TARGET_USER..." | tee -a "$LOG_FILE"

# Define compile targets cleanly pointing to user space
STITCH_TARGET="$TARGET_HOME/.bash_aliases_pro"
BASHRC_HOOK="[ -f $STITCH_TARGET ] && . $STITCH_TARGET"

# Step A: Compile modular context components securely
echo "# =========================================================" > "$STITCH_TARGET"
echo "# COMPILED PROFILE ENVIRONMENT - DO NOT DIRECTLY EDIT THIS FILE" >> "$STITCH_TARGET"
echo "# Generated dynamically via alwazw/ubuntu-customz" >> "$STITCH_TARGET"
echo "# =========================================================" >> "$STITCH_TARGET"

# Inject component files if they exist in repo root
[ -f "../aliases.env" ] && cat "../aliases.env" >> "$STITCH_TARGET"
[ -f "../functions.env" ] && cat "../functions.env" >> "$STITCH_TARGET"

# Step B: Securely hook the compiled file to the user's primary .bashrc
echo "🔗 Anchoring profile linkage inside target .bashrc..." | tee -a "$LOG_FILE"
safe_append_line "$BASHRC_HOOK" "$TARGET_HOME/.bashrc"

# Step C: Fix file permissions so the normal user owns their files (Crucial Fix)
chown "$TARGET_USER":"$TARGET_USER" "$STITCH_TARGET"

echo "✅ Environment stitched successfully. Clean terminal profile active for $TARGET_USER." | tee -a "$LOG_FILE"
