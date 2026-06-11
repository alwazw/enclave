echo "$USER ALL=(ALL:ALL) NOPASSWD:ALL" | sudo tee "/etc/sudoers.d/90-$USER-nopasswd" > /dev/null
sudo chmod 0440 "/etc/sudoers.d/90-$USER-nopasswd"
echo "[SUCCESS] Passwordless sudo mapped."
