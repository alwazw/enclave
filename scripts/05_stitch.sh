# 05_stitch.sh - Modular Sync & Alias Management
MANAGED_ALIASES="$HOME/.bash_aliases_pro"
LOCAL_ALIASES="$HOME/.bash_aliases_local" # For aliases not yet in the repo
REPO_DIR="$HOME/Ubuntu-Pro-Suite"

cat << 'INNER_EOF' > "$MANAGED_ALIASES"
### --- PATHS ---
export PATH="$HOME/.local/bin:$PATH"

### --- FUNCTIONS ---

# 1. Modular Sync Function
repo_sync() {
    if [ -d "$REPO_DIR" ]; then
        echo "🔄 Syncing Universal Repo & Templates..."
        git -C "$REPO_DIR" pull
        
        # CI/DI Template Sync Check
        for template in .env.template .secrets.template; do
            if [ -f "$REPO_DIR/$template" ] && [ -f "$HOME/${template%.template}" ]; then
                if ! cmp -s "$HOME/${template%.template}" "$REPO_DIR/$template" 2>/dev/null; then
                    echo "⚠️  NOTICE: $template has changed. Review your local config."
                fi
            fi
        done
    else
        echo "❌ Repo directory not found at $REPO_DIR"
    fi
}

# 2. Local Push/Contribution Logic
# Identifies aliases in .bash_aliases_local that are missing from the Managed Suite
alias_audit() {
    echo "🔍 Auditing local vs. managed aliases..."
    if [ -f "$LOCAL_ALIASES" ]; then
        # Finds aliases in local file not present in managed file
        comm -23 <(grep "^alias " "$LOCAL_ALIASES" | sort) \
                 <(grep "^alias " "$MANAGED_ALIASES" | sort) > /tmp/missing_aliases
        
        if [ -s /tmp/missing_aliases ]; then
            echo "💡 New local aliases detected:"
            cat /tmp/missing_aliases
            read -p "Push these changes to the Universal Repo? (y/n): " PUSH_CHOICE
            if [[ "$PUSH_CHOICE" == "y" ]]; then
                echo "🚀 Preparing commit to $REPO_DIR..."
                # Logic to append to repo source file and git push would go here
            fi
        else
            echo "✅ All local aliases are already in the Managed Suite."
        fi
    fi
}

# 3. Enhanced Update Function
sys_update() {
    repo_sync        # Invoke modular sync [Question 1]
    alias_audit      # Identify local changes [Question 4]
    
    echo "📦 System Update..."
    sudo apt update && sudo apt full-upgrade -y && sudo apt autoremove -y
}

### --- DYNAMIC CHEATS ---
cheats() {
    echo -e "\e[1;35m--- 💡 DYNAMIC PRO-SPEC CHEATSHEET ---\e[0m"
    grep -E '^### ----|alias ' "$MANAGED_ALIASES" "$LOCAL_ALIASES" 2>/dev/null | \
    sed -e 's/alias //g' -e "s/='/: /g" -e "s/'//g"
}

### --- ALIASES ---
alias update='sys_update'
alias dps='docker ps -a'
alias ..='cd ..'

# Auto-source local overrides if they exist [Question 3]
[ -f "$LOCAL_ALIASES" ] && source "$LOCAL_ALIASES"
INNER_EOF

# Link to .bashrc (Single Stitch Pattern) [1, 2]
STITCH="[ -f $MANAGED_ALIASES ] && source $MANAGED_ALIASES"
grep -qF "$MANAGED_ALIASES" "$HOME/.bashrc" || echo -e "\n$STITCH" >> "$HOME/.bashrc"
