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

# Source component files live in the repo's var/ directory. Resolve that path
# RELATIVE TO THIS SCRIPT (not the caller's cwd) so it works no matter where
# init_pro.sh was invoked from.
DATA_DIR="$(cd "$(dirname "$0")/../var" && pwd)"

# Step A: Compile modular context components securely
echo "# =========================================================" > "$STITCH_TARGET"
echo "# COMPILED PROFILE ENVIRONMENT - DO NOT DIRECTLY EDIT THIS FILE" >> "$STITCH_TARGET"
echo "# Generated dynamically via alwazw/ubuntu-customz" >> "$STITCH_TARGET"
echo "# =========================================================" >> "$STITCH_TARGET"

# Step A1: Compile aliases. aliases.env uses KEY='VALUE' format, so it must be
# transformed into real `alias KEY='VALUE'` statements (a raw cat would only set
# shell variables, not aliases). Comments and blank lines are skipped.
if [ -f "$DATA_DIR/aliases.env" ]; then
    echo "📌 Compiling shortcut aliases from var/aliases.env..." | tee -a "$LOG_FILE"
    printf '\n# --- SHORTCUT ALIASES ---\n' >> "$STITCH_TARGET"
    while IFS='=' read -r key value || [ -n "$key" ]; do
        # Trim surrounding whitespace from the key
        key="$(printf '%s' "$key" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [[ "$key" =~ ^#.*$ ]] && continue   # skip comment lines
        [ -z "$key" ] && continue           # skip blank lines
        # Strip one layer of surrounding single/double quotes from the value
        clean_value="$(printf '%s' "$value" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")"
        printf "alias %s='%s'\n" "$key" "$clean_value" >> "$STITCH_TARGET"
    done < "$DATA_DIR/aliases.env"
fi

# Step A2: Compile functions. functions.env is raw bash, so cat it verbatim.
if [ -f "$DATA_DIR/functions.env" ]; then
    echo "📌 Compiling runtime functions from var/functions.env..." | tee -a "$LOG_FILE"
    printf '\n# --- SYSTEM RUNTIME FUNCTIONS ---\n' >> "$STITCH_TARGET"
    cat "$DATA_DIR/functions.env" >> "$STITCH_TARGET"
fi

# Step B: Securely hook the compiled file to the user's primary .bashrc
echo "🔗 Anchoring profile linkage inside target .bashrc..." | tee -a "$LOG_FILE"
safe_append_line "$BASHRC_HOOK" "$TARGET_HOME/.bashrc"

# Step C: Fix file permissions so the normal user owns their files (Crucial Fix)
chown "$TARGET_USER":"$TARGET_USER" "$STITCH_TARGET"

echo "✅ Environment stitched successfully. Clean terminal profile active for $TARGET_USER." | tee -a "$LOG_FILE"
