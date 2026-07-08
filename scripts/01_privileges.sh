#!/bin/bash

# Fallback to current user if script wasn't run with sudo
TARGET_USER="${SUDO_USER:-$USER}"

# Ensure the target user string isn't completely empty
if [ -z "$TARGET_USER" ]; then
    echo "[ERROR] Could not determine user name."
    exit 1
fi

echo "$TARGET_USER ALL=(ALL:ALL) NOPASSWD:ALL" | sudo tee "/etc/sudoers.d/90-$TARGET_USER-nopasswd" > /dev/null
sudo chmod 0440 "/etc/sudoers.d/90-$TARGET_USER-nopasswd"
echo "[SUCCESS] Passwordless sudo mapped for $TARGET_USER."
