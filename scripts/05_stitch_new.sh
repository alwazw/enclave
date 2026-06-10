#!/bin/bash
# scripts/05_stitch.sh

SYNCHED_ALIASES="$HOME/.synched_aliases"
DATA_DIR="$(dirname "$0")/../var" # Points to ~/ubuntu-customz/var

echo "🛠️ Compiling environment profiles..."

# 1. Clear previous compilation to prevent ghost configurations
cat << 'EOF' > "$SYNCHED_ALIASES"
# ==============================================================================
# 🛠️ MANAGED ALIASES & FUNCTIONS (DYNAMICALLY COMPILED - DO NOT EDIT)
# Generated: $(date)
# ==============================================================================
EOF

# 2. The Alias Variable Parsing Loop
if [ -f "$DATA_DIR/aliases.env" ]; then
    echo "📌 Compiling Shortcuts..."
    echo -e "\n# --- SHORTCUT MAP ---" >> "$SYNCHED_ALIASES"
    
    # Read the file line by line, skipping comments and empty space
    while IFS='=' read -r key value || [ -n "$key" ]; do
        [[ "$key" =~ ^#.*$ ]] && continue # Skip comments
        [[ -z "$key" ]] && continue       # Skip empty lines
        
        # Strip trailing/leading quotes if any, then output uniformly
        clean_value=$(echo "$value" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
        echo "alias $key='$clean_value'" >> "$SYNCHED_ALIASES"
    done < "$DATA_DIR/aliases.env"
fi

# 3. The Function Compilation Drop
if [ -f "$DATA_DIR/functions.env" ]; then
    echo "📌 Compiling Core Functions..."
    echo -e "\n# --- SYSTEM RUNTIME FUNCTIONS ---" >> "$SYNCHED_ALIASES"
    cat "$DATA_DIR/functions.env" >> "$SYNCHED_ALIASES"
fi

echo "✅ Compilation complete: $SYNCHED_ALIASES"
