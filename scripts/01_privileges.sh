# Use $SUDO_USER so it targets the person who ran sudo, not root
echo "$SUDO_USER ALL=(ALL:ALL) NOPASSWD:ALL" | sudo tee "/etc/sudoers.d/90-$SUDO_USER-nopasswd" > /dev/null
sudo chmod 0440 "/etc/sudoers.d/90-$SUDO_USER-nopasswd"
echo "[SUCCESS] Passwordless sudo mapped."
