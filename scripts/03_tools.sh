#!/usr/bin/env bash
set -Eeuo pipefail

# 1. Update system and install absolute essential utilities
echo "📦 Updating package lists and installing core utilities..."
apt-get update && apt-get install -y \
    ca-certificates \
    openssh-server \
    curl \
    git \
    tmux \
    btop \
    htop \
    ncdu \
    tree \
    ripgrep \
    bat \
    fzf \
    dos2unix

# 2. Prepare and Register Docker Official Repository
echo "🔑 Registering Docker repository and security keys..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# 3. Install Docker Engine and Plugins
echo "🐳 Installing Docker CE, CLI, and Compose plugin..."
apt-get update && apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

# 4. Handle Post-Installation Permissions securely
echo "👥 Setting up Docker user groups..."
groupadd -f docker

# Detect the actual user running the script via sudo
SUDO_USER_NAME="${SUDO_USER:-$USER}"
if [ "$SUDO_USER_NAME" = "root" ]; then
    SUDO_USER_NAME=$(logname 2>/dev/null || echo "ubuntu")
fi

usermod -aG docker "$SUDO_USER_NAME"

# 5. Configure WSL configurations
echo "⚙️  Optimizing /etc/wsl.conf for network and systemd..."
cat << 'EOF' > /etc/wsl.conf
[boot]
systemd=true

[user]
default=ubuntu
EOF

# Dynamically fix the user field inside wsl.conf to mirror your current user
sed -i "s/default=ubuntu/default=$SUDO_USER_NAME/g" /etc/wsl.conf

# 6. Enable services to auto-start on boot (Queued for next boot)
echo "🔄 Hooking Docker and SSH into systemd boot timeline..."
systemctl enable ssh
systemctl enable docker.service
systemctl enable containerd.service

echo ""
echo "=============================================================================="
echo "✅ INITIAL TOOL INSTALLATION COMPLETE!"
echo "=============================================================================="
echo "To finalize your systemd engine and apply your new Docker groups:"
echo "1. Exit this terminal right now."
echo "2. Open PowerShell on Windows and run: wsl --terminate vm2"
echo "3. Re-open your terminal. Docker and SSH will start automatically!"
echo "4. Verify Docker by running: docker run hello-world"
echo "=============================================================================="
