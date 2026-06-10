. /etc/os-release
if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
    echo "[WARN] Unsupported OS: $ID. Proceeding with caution."
fi
mkdir -p "$HOME/.local/bin"
