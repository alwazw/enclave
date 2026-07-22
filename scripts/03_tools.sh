#!/usr/bin/env bash
set -Eeuo pipefail

#!/bin/bash
# ---------------------------------------------------------------------
# scripts/03_tools.sh - Component of alwazw/ubuntu-customz Suite
# Deploys Unified Terminal Core Utilities, Dev Tooling, and NVM Engine
# ---------------------------------------------------------------------

echo "📦 [03_tools] Updating package lists and installing system engines..."
apt-get update && apt-get install -y \
    bat \
    btop \
    build-essential \
    ca-certificates \
    curl \
    dos2unix \
    fzf \
    git \
    htop \
    jq \
    ncdu \
    net-tools \
    openssh-server \
    pipx \
    python3 \
    python3-pip \
    python3-venv \
    ripgrep \
    sudo \
    tmux \
    tree \
    ufw \
    zram-tools

# ------------------------------------------------------------------------------
# NVM + Node.js LTS  (installed as the TARGET USER, not root)
# ------------------------------------------------------------------------------
# This module runs as root, but NVM is a *user-level* runtime and var/node.env
# (written further below) points at the target user's ~/.nvm. If we installed as
# root, NVM would land in /root/.nvm and node.env would reference a path that
# does not exist for the user. So resolve the unprivileged user and run the whole
# NVM install/use flow as them via `sudo -u ... -H` (so $HOME is their home).
NVM_RUN_USER="${SUDO_USER:-$USER}"
if [ "$NVM_RUN_USER" = "root" ]; then
    NVM_RUN_USER=$(logname 2>/dev/null || echo "ubuntu")
fi

echo "🚀 Triggering user-level Node Version Manager (NVM) deployment for '${NVM_RUN_USER}'..."
# NOTE: nvm.sh is NOT compatible with `set -u` (nounset) — it references unbound
# internals like PROVIDED_VERSION and aborts under strict mode. The inner shell
# therefore disables nounset around the nvm sourcing/commands. Idempotent: the
# NVM installer updates in place and `nvm install --lts` is a no-op if present.
sudo -u "$NVM_RUN_USER" -H bash <<'NVM_SETUP'
set -eo pipefail
export NVM_DIR="$HOME/.nvm"
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
set +u
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
echo "🟢 Provisioning Node.js LTS Engine & Native NPM layer..."
nvm install --lts
nvm use --lts
node -v && npm -v
NVM_SETUP

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

# ==============================================================================
# 📦 AUTOMATED NODE PROFILE VECTOR EXPORTER
# ==============================================================================
echo "📦 Exporting Node runtime pathways into custom configuration layers..."

DATA_DIR="$(cd "$(dirname "${BASH_SOURCE}")/.." && pwd)"
mkdir -p "$DATA_DIR/var"

# Capture the target user running sudo
SUDO_USER_NAME="${SUDO_USER:-$USER}"
if [ "$SUDO_USER_NAME" = "root" ]; then
    SUDO_USER_NAME=$(logname 2>/dev/null || echo "ubuntu")
fi
TARGET_USER_HOME=$(eval echo "~$SUDO_USER_NAME")

# Automatically write paths cleanly without opening an editor
cat << EOF > "$DATA_DIR/var/node.env"
# --- AUTOMATED NODE VERSION MANAGER CONFIGURATION MAPPINGS ---
export NVM_DIR="$TARGET_USER_HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \. "\$NVM_DIR/nvm.sh"
[ -s "\$NVM_DIR/bash_completion" ] && \. "\$NVM_DIR/bash_completion"

# Universal fallback layout path for global npm packages
export PATH="$TARGET_USER_HOME/.npm-global/bin:\$PATH"
EOF

echo "✅ Node operational environment metrics locked into: $DATA_DIR/var/node.env"

echo ""
echo "=============================================================================="
echo "✅ INITIAL TOOL INSTALLATION COMPLETE!"
echo "=============================================================================="
echo "To finalize your systemd engine and apply your new Docker groups:"
echo "1. Exit this terminal right now."
echo "2. Open PowerShell on Windows and run: wsl --terminate vm2"
echo "3. Re-open your terminal. Docker and SSH will start automatically!"
echo "4. Verify Docker by running: docker run hello-world"
