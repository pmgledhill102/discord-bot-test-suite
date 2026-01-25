#!/bin/bash
# VM Provisioning Script - Installs all development tooling for Claude Code agents
# Run as root via startup-script metadata or manually after VM creation

set -e

LOG_FILE="/var/log/claude-sandbox-provision.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== Claude Sandbox VM Provisioning ==="
echo "Started at: $(date)"
echo "Hostname: $(hostname)"

# Versions (update these as needed)
NODE_VERSION="20"
GO_VERSION="1.22.5"
PYTHON_VERSION="3.11"
RUST_VERSION="stable"
JAVA_VERSION="21"
RUBY_VERSION="3.3"
PHP_VERSION="8.3"
DOTNET_VERSION="8.0"
DELTA_VERSION="0.18.2"

export DEBIAN_FRONTEND=noninteractive

# Wait for cloud-init to complete
cloud-init status --wait || true

# ============================================
# System Updates
# ============================================
echo "=== Updating system packages ==="
apt-get update
apt-get upgrade -y

# ============================================
# Core System Packages (from Anthropic devcontainer)
# ============================================
echo "=== Installing core system packages ==="
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    wget \
    gnupg \
    gnupg2 \
    lsb-release \
    software-properties-common \
    build-essential \
    git \
    less \
    procps \
    sudo \
    fzf \
    zsh \
    man-db \
    unzip \
    zip \
    iptables \
    ipset \
    iproute2 \
    dnsutils \
    jq \
    nano \
    vim \
    tmux \
    screen \
    htop \
    ncdu

# ============================================
# git-delta (from Anthropic devcontainer)
# ============================================
echo "=== Installing git-delta ==="
ARCH=$(dpkg --print-architecture)
if [ "$ARCH" = "amd64" ]; then
    DELTA_ARCH="x86_64"
else
    DELTA_ARCH="aarch64"
fi
wget -q "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/git-delta_${DELTA_VERSION}_${ARCH}.deb" -O /tmp/git-delta.deb
dpkg -i /tmp/git-delta.deb || apt-get install -f -y
rm /tmp/git-delta.deb

# ============================================
# ripgrep
# ============================================
echo "=== Installing ripgrep ==="
apt-get install -y ripgrep

# ============================================
# GitHub CLI
# ============================================
echo "=== Installing GitHub CLI ==="
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null
apt-get update
apt-get install -y gh

# ============================================
# Docker
# ============================================
echo "=== Installing Docker ==="
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Configure Docker
systemctl enable docker
systemctl start docker
cat > /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
systemctl restart docker

# ============================================
# Node.js (Claude Code runtime)
# ============================================
echo "=== Installing Node.js ${NODE_VERSION} ==="
curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -
apt-get install -y nodejs

# Install global npm packages
npm install -g \
    @anthropic-ai/claude-code \
    yarn \
    pnpm \
    typescript \
    ts-node \
    eslint \
    prettier

# ============================================
# Python
# ============================================
echo "=== Installing Python ${PYTHON_VERSION} ==="
add-apt-repository -y ppa:deadsnakes/ppa
apt-get update
apt-get install -y \
    python${PYTHON_VERSION} \
    python${PYTHON_VERSION}-venv \
    python${PYTHON_VERSION}-dev \
    python3-pip

# Set as default python3
update-alternatives --install /usr/bin/python3 python3 /usr/bin/python${PYTHON_VERSION} 1
update-alternatives --install /usr/bin/python python /usr/bin/python${PYTHON_VERSION} 1

# Install Python tools
pip3 install --break-system-packages \
    pipx \
    poetry \
    uv \
    black \
    ruff \
    mypy \
    pytest \
    pre-commit \
    httpie

# ============================================
# Go
# ============================================
echo "=== Installing Go ${GO_VERSION} ==="
wget -q "https://go.dev/dl/go${GO_VERSION}.linux-$(dpkg --print-architecture).tar.gz" -O /tmp/go.tar.gz
rm -rf /usr/local/go
tar -C /usr/local -xzf /tmp/go.tar.gz
rm /tmp/go.tar.gz

# Go environment
cat > /etc/profile.d/go.sh <<'EOF'
export PATH=$PATH:/usr/local/go/bin
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin
EOF

# Install Go tools
export PATH=$PATH:/usr/local/go/bin
export GOPATH=/root/go
export PATH=$PATH:$GOPATH/bin
go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
go install github.com/go-delve/delve/cmd/dlv@latest

# ============================================
# Rust
# ============================================
echo "=== Installing Rust ==="
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain ${RUST_VERSION}
source $HOME/.cargo/env
rustup component add clippy rustfmt

# ============================================
# Java (Temurin)
# ============================================
echo "=== Installing Java ${JAVA_VERSION} ==="
wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor | tee /etc/apt/keyrings/adoptium.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/adoptium.list
apt-get update
apt-get install -y temurin-${JAVA_VERSION}-jdk

# Maven and Gradle
apt-get install -y maven
wget -q "https://services.gradle.org/distributions/gradle-8.8-bin.zip" -O /tmp/gradle.zip
unzip -q /tmp/gradle.zip -d /opt
ln -sf /opt/gradle-8.8/bin/gradle /usr/local/bin/gradle
rm /tmp/gradle.zip

# ============================================
# Ruby
# ============================================
echo "=== Installing Ruby ==="
apt-get install -y ruby-full
gem install bundler rubocop

# ============================================
# PHP
# ============================================
echo "=== Installing PHP ${PHP_VERSION} ==="
add-apt-repository -y ppa:ondrej/php
apt-get update
apt-get install -y \
    php${PHP_VERSION} \
    php${PHP_VERSION}-cli \
    php${PHP_VERSION}-common \
    php${PHP_VERSION}-curl \
    php${PHP_VERSION}-mbstring \
    php${PHP_VERSION}-xml \
    php${PHP_VERSION}-zip

# Composer
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# ============================================
# .NET
# ============================================
echo "=== Installing .NET ${DOTNET_VERSION} ==="
wget https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb -O /tmp/packages-microsoft-prod.deb
dpkg -i /tmp/packages-microsoft-prod.deb
rm /tmp/packages-microsoft-prod.deb
apt-get update
apt-get install -y dotnet-sdk-${DOTNET_VERSION}

# ============================================
# Google Cloud CLI
# ============================================
echo "=== Installing Google Cloud CLI ==="
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee /etc/apt/sources.list.d/google-cloud-sdk.list
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
apt-get update
apt-get install -y google-cloud-cli google-cloud-cli-gke-gcloud-auth-plugin

# ============================================
# Kubernetes Tools
# ============================================
echo "=== Installing Kubernetes tools ==="
# kubectl
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y kubectl

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# k9s
wget -q "https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_$(dpkg --print-architecture).tar.gz" -O /tmp/k9s.tar.gz
tar -xzf /tmp/k9s.tar.gz -C /usr/local/bin k9s
rm /tmp/k9s.tar.gz

# ============================================
# Database Clients
# ============================================
echo "=== Installing database clients ==="
apt-get install -y \
    postgresql-client \
    default-mysql-client \
    redis-tools

# MongoDB shell
wget -qO - https://www.mongodb.org/static/pgp/server-7.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg
echo "deb [signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/7.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-7.0.list
apt-get update
apt-get install -y mongodb-mongosh

# ============================================
# Additional CLI Tools
# ============================================
echo "=== Installing additional CLI tools ==="

# yq (YAML processor)
wget -q "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_$(dpkg --print-architecture)" -O /usr/local/bin/yq
chmod +x /usr/local/bin/yq

# btop (better top)
apt-get install -y btop || true

# micro editor
curl https://getmic.ro | bash
mv micro /usr/local/bin/

# grpcurl
go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest
cp /root/go/bin/grpcurl /usr/local/bin/ 2>/dev/null || true

# ============================================
# Security Scanning Tools
# ============================================
echo "=== Installing security tools ==="

# Trivy
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor -o /usr/share/keyrings/trivy.gpg
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" | tee /etc/apt/sources.list.d/trivy.list
apt-get update
apt-get install -y trivy

# Semgrep
pip3 install --break-system-packages semgrep

# ============================================
# ZSH Configuration (from Anthropic devcontainer)
# ============================================
echo "=== Configuring ZSH ==="
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended || true

# ============================================
# Create sandbox user
# ============================================
echo "=== Creating sandbox user ==="
if ! id "sandbox" &>/dev/null; then
    useradd -m -s /bin/zsh sandbox
    usermod -aG docker sandbox
    echo "sandbox ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/sandbox
fi

# Copy tools to sandbox user
cp -r /root/.cargo /home/sandbox/ 2>/dev/null || true
cp -r /root/go /home/sandbox/ 2>/dev/null || true
cp -r /root/.oh-my-zsh /home/sandbox/ 2>/dev/null || true
chown -R sandbox:sandbox /home/sandbox/

# ============================================
# Create workspace directories
# ============================================
echo "=== Creating workspace directories ==="
mkdir -p /workspaces
for i in $(seq 1 16); do
    mkdir -p /workspaces/agent-$i
done
chown -R sandbox:sandbox /workspaces

# ============================================
# Environment setup for sandbox user
# ============================================
cat > /home/sandbox/.zshrc <<'EOF'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git docker kubectl)
source $ZSH/oh-my-zsh.sh

# Path additions
export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin:$HOME/.cargo/bin
export GOPATH=$HOME/go

# Aliases
alias ll='ls -la'
alias k='kubectl'
alias d='docker'
alias g='git'

# Load API key from metadata if available
if command -v curl &> /dev/null; then
    METADATA_KEY=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/anthropic-api-key" 2>/dev/null)
    if [ -n "$METADATA_KEY" ] && [ "$METADATA_KEY" != "" ]; then
        export ANTHROPIC_API_KEY="$METADATA_KEY"
    fi
fi
EOF
chown sandbox:sandbox /home/sandbox/.zshrc

# ============================================
# tmux configuration
# ============================================
cat > /home/sandbox/.tmux.conf <<'EOF'
set -g mouse on
set -g history-limit 50000
set -g base-index 1
setw -g pane-base-index 1
set -g default-terminal "screen-256color"
set -g status-bg colour235
set -g status-fg white
set -g status-left '[#S] '
set -g status-right '#H | %H:%M'
bind -n M-Left select-pane -L
bind -n M-Right select-pane -R
bind -n M-Up select-pane -U
bind -n M-Down select-pane -D
EOF
chown sandbox:sandbox /home/sandbox/.tmux.conf

# ============================================
# Agent management scripts
# ============================================
cat > /usr/local/bin/start-agents.sh <<'SCRIPT'
#!/bin/bash
AGENT_COUNT=${1:-12}
SESSION_NAME="claude-agents"

# Kill existing session
tmux kill-session -t $SESSION_NAME 2>/dev/null || true

# Create new session
tmux new-session -d -s $SESSION_NAME -n "agent-1"

# Create windows for each agent
for i in $(seq 2 $AGENT_COUNT); do
    tmux new-window -t $SESSION_NAME -n "agent-$i"
done

# Start claude in each window
for i in $(seq 1 $AGENT_COUNT); do
    tmux send-keys -t $SESSION_NAME:agent-$i "cd /workspaces/agent-$i && claude --dangerously-skip-permissions" Enter
done

echo "Started $AGENT_COUNT agent sessions in tmux session '$SESSION_NAME'"
echo "Attach with: tmux attach -t $SESSION_NAME"
echo "Or use: attach-agent.sh <number>"
SCRIPT

cat > /usr/local/bin/stop-agents.sh <<'SCRIPT'
#!/bin/bash
tmux kill-session -t claude-agents 2>/dev/null && echo "Stopped all agents" || echo "No agents running"
SCRIPT

cat > /usr/local/bin/attach-agent.sh <<'SCRIPT'
#!/bin/bash
AGENT_NUM=${1:-1}
tmux select-window -t claude-agents:agent-$AGENT_NUM 2>/dev/null
tmux attach -t claude-agents
SCRIPT

cat > /usr/local/bin/list-agents.sh <<'SCRIPT'
#!/bin/bash
tmux list-windows -t claude-agents 2>/dev/null || echo "No agents running"
SCRIPT

chmod +x /usr/local/bin/*.sh

# ============================================
# Git configuration
# ============================================
cat > /home/sandbox/.gitconfig <<'EOF'
[core]
    pager = delta
[interactive]
    diffFilter = delta --color-only
[delta]
    navigate = true
    light = false
    line-numbers = true
[merge]
    conflictstyle = diff3
[diff]
    colorMoved = default
[init]
    defaultBranch = main
[pull]
    rebase = true
EOF
chown sandbox:sandbox /home/sandbox/.gitconfig

# ============================================
# Cleanup
# ============================================
echo "=== Cleaning up ==="
apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/*

# ============================================
# Summary
# ============================================
echo ""
echo "=== Provisioning Complete ==="
echo "Finished at: $(date)"
echo ""
echo "Installed:"
echo "  - Node.js $(node --version)"
echo "  - Python $(python3 --version)"
echo "  - Go $(/usr/local/go/bin/go version)"
echo "  - Rust $(rustc --version 2>/dev/null || echo 'installed')"
echo "  - Java $(java --version 2>&1 | head -1)"
echo "  - Ruby $(ruby --version)"
echo "  - PHP $(php --version | head -1)"
echo "  - .NET $(dotnet --version)"
echo "  - Docker $(docker --version)"
echo "  - Claude Code $(claude --version 2>/dev/null || echo 'installed')"
echo ""
echo "Quick start:"
echo "  1. SSH in: gcloud compute ssh $(hostname) --zone=ZONE --tunnel-through-iap"
echo "  2. Switch user: sudo su - sandbox"
echo "  3. Start agents: start-agents.sh 12"
echo "  4. Attach: tmux attach -t claude-agents"
