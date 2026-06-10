# dir-git-check.sh
#!/bin/bash

# 1. Store the paths:
UPSTREAM_REPO="git@github.com:alwazw/ubuntu-customz.git" 
REPO_DIR="$HOME/ubuntu-customz"
MANAGED_ALIASES="$HOME/.bash_aliases_pro"
SUCCESS_TASKS=()
FAILED_TASKS=()

# 2. Handle the Aliases File (File check)
[ -f "$MANAGED_ALIASES" ] || touch "$MANAGED_ALIASES"

# 3. Handle the Repository (Directory + Git status check)
if [ ! -d "$REPO_DIR" ]; then
    echo "?? Repository directory does not exist. Cloning..."
    if git clone "$UPSTREAM_REPO" "$REPO_DIR"; then
        SUCCESS_TASKS+=("Cloned repository")
    else
        FAILED_TASKS+=("Failed to clone repository")
    fi
else
    echo "? Repository directory exists. Checking Git status..."
    
    # Move into the repo to run Git commands
    cd "$REPO_DIR" || exit 1

    # Check if it's actually a git repo
    if [ ! -d ".git" ]; then
        echo "??  Error: $REPO_DIR exists but is not a Git repository!"
        FAILED_TASKS+=("Repo directory is not a git repo")
    else
        # Fetch the latest updates from GitHub silently
        git fetch origin &> /dev/null

        # Compare local HEAD with the remote tracking branch
        LOCAL=$(git rev-parse @)
        REMOTE=$(git rev-parse @{u})
        BASE=$(git merge-base @ @{u})

        if [ "$LOCAL" = "$REMOTE" ]; then
            echo "?? Everything is up-to-date."
            SUCCESS_TASKS+=("Repo up-to-date")
        elif [ "$LOCAL" = "$BASE" ]; then
            echo "?? You are BEHIND upstream. You need to 'git pull'."
            FAILED_TASKS+=("Repo needs pull")
        elif [ "$REMOTE" = "$BASE" ]; then
            echo "?? You are AHEAD of upstream. You need to 'git push'."
            SUCCESS_TASKS+=("Repo has local changes to push")
        else
            echo "?? Diverged! Local and upstream have different commits."
            FAILED_TASKS+=("Repo diverged")
        fi

        # Also check for uncommitted changes (dirty working tree)
        if ! git diff-index --quiet HEAD --; then
            echo "?? Note: You have uncommitted local changes."
        fi
    fi
fi