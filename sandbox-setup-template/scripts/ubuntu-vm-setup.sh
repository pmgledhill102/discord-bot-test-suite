#!/bin/bash
# shellcheck disable=SC1091,SC2016
set -euo pipefail

# =============================================================================
# Ubuntu VM Setup Script for Claude Code Development Environment
# =============================================================================
# SC1091: Not following external files (/etc/os-release, .cargo/env) - they exist on target
# SC2016: Single quotes intentional - we want literal $PATH/$HOME written to .bashrc

echo "=== Claude Code Development Environment Setup ==="
echo ""

# -----------------------------------------------------------------------------
# Core APT Packages
# -----------------------------------------------------------------------------
echo ">>> Installing core APT packages..."
sudo apt update
sudo apt install -y \
  git \
  curl \
  wget \
  jq \
  ssh \
  nano \
  build-essential \
  ca-certificates \
  gnupg \
  lsb-release \
  ripgrep \
  fd-find \
  fzf \
  shellcheck \
  unzip \
  php \
  php-cli \
  ruby \
  clang-format \
  skopeo \
  sqlite3 \
  gdb

# fd is installed as fdfind on Ubuntu - create symlink
sudo ln -sf "$(which fdfind)" /usr/local/bin/fd

# -----------------------------------------------------------------------------
# Docker (from official Docker repo for latest version)
# -----------------------------------------------------------------------------
echo ">>> Installing Docker..."
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add current user to docker group
sudo usermod -aG docker "$USER"

# -----------------------------------------------------------------------------
# GitHub CLI
# -----------------------------------------------------------------------------
echo ">>> Installing GitHub CLI..."
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update
sudo apt install -y gh

# -----------------------------------------------------------------------------
# yq (YAML processor)
# -----------------------------------------------------------------------------
echo ">>> Installing yq..."
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq

# -----------------------------------------------------------------------------
# git-delta (better git diffs)
# -----------------------------------------------------------------------------
echo ">>> Installing git-delta..."
DELTA_VERSION=$(curl -s https://api.github.com/repos/dandavison/delta/releases/latest | grep tag_name | cut -d '"' -f 4)
wget -q "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/git-delta_${DELTA_VERSION}_amd64.deb"
sudo dpkg -i "git-delta_${DELTA_VERSION}_amd64.deb"
rm "git-delta_${DELTA_VERSION}_amd64.deb"

# -----------------------------------------------------------------------------
# Node.js 25
# -----------------------------------------------------------------------------
echo ">>> Installing Node.js 25..."
curl -fsSL https://deb.nodesource.com/setup_25.x | sudo -E bash -
sudo apt install -y nodejs

# -----------------------------------------------------------------------------
# Go 1.25
# -----------------------------------------------------------------------------
echo ">>> Installing Go 1.25..."
GO_VERSION="1.25.0"
wget -q "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf "go${GO_VERSION}.linux-amd64.tar.gz"
rm "go${GO_VERSION}.linux-amd64.tar.gz"

# Add Go to PATH (for current script and .bashrc/.zshrc)
export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> ~/.bashrc

# -----------------------------------------------------------------------------
# Rust
# -----------------------------------------------------------------------------
echo ">>> Installing Rust..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"
rustup component add clippy rustfmt

# -----------------------------------------------------------------------------
# .NET 9.0
# -----------------------------------------------------------------------------
echo ">>> Installing .NET 9.0..."
wget "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb" -O packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
rm packages-microsoft-prod.deb
sudo apt update
sudo apt install -y dotnet-sdk-9.0

# -----------------------------------------------------------------------------
# uv (Python package manager) and Python
# -----------------------------------------------------------------------------
echo ">>> Installing uv and Python..."
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

# Install Python via uv
uv python install 3.12

# -----------------------------------------------------------------------------
# Terraform
# -----------------------------------------------------------------------------
echo ">>> Installing Terraform..."
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update
sudo apt install -y terraform

# -----------------------------------------------------------------------------
# Cloud CLIs
# -----------------------------------------------------------------------------
echo ">>> Installing Google Cloud CLI..."
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list
sudo apt update
sudo apt install -y google-cloud-cli

echo ">>> Installing AWS CLI..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
sudo ./aws/install
rm -rf aws awscliv2.zip

echo ">>> Installing Azure CLI..."
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# -----------------------------------------------------------------------------
# Container Tools
# -----------------------------------------------------------------------------
echo ">>> Installing container tools..."

# crane
go install github.com/google/go-containerregistry/cmd/crane@latest

# hadolint
sudo wget -qO /usr/local/bin/hadolint https://github.com/hadolint/hadolint/releases/latest/download/hadolint-Linux-x86_64
sudo chmod +x /usr/local/bin/hadolint

# dive
DIVE_VERSION=$(curl -s https://api.github.com/repos/wagoodman/dive/releases/latest | grep tag_name | cut -d '"' -f 4)
wget -q "https://github.com/wagoodman/dive/releases/download/${DIVE_VERSION}/dive_${DIVE_VERSION#v}_linux_amd64.deb"
sudo dpkg -i "dive_${DIVE_VERSION#v}_linux_amd64.deb"
rm "dive_${DIVE_VERSION#v}_linux_amd64.deb"

# trivy
sudo apt install -y apt-transport-https
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo gpg --dearmor -o /usr/share/keyrings/trivy.gpg
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" | sudo tee /etc/apt/sources.list.d/trivy.list
sudo apt update
sudo apt install -y trivy

# -----------------------------------------------------------------------------
# Go Tools
# -----------------------------------------------------------------------------
echo ">>> Installing Go tools..."
go install github.com/rhysd/actionlint/cmd/actionlint@latest
go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest

# -----------------------------------------------------------------------------
# Python Tools (via uv)
# -----------------------------------------------------------------------------
echo ">>> Installing Python tools via uv..."
uv tool install ruff
uv tool install mypy
uv tool install pre-commit
uv tool install yamllint

# -----------------------------------------------------------------------------
# Node.js Tools
# -----------------------------------------------------------------------------
echo ">>> Installing Node.js tools..."
sudo npm install -g prettier eslint markdownlint-cli2 cspell yarn pnpm

# -----------------------------------------------------------------------------
# Ruby Tools
# -----------------------------------------------------------------------------
echo ">>> Installing Ruby tools..."
sudo gem install rubocop

# -----------------------------------------------------------------------------
# Claude Code CLI
# -----------------------------------------------------------------------------
echo ">>> Installing Claude Code..."
curl -fsSL https://claude.ai/install.sh | sh

# -----------------------------------------------------------------------------
# Beads (bd) - Issue Tracking
# -----------------------------------------------------------------------------
echo ">>> Installing Beads (bd)..."
curl -fsSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash

# -----------------------------------------------------------------------------
# JVM Tools (for Java/Kotlin/Scala services)
# -----------------------------------------------------------------------------
echo ">>> Installing JDK 21 and build tools..."
sudo apt install -y openjdk-21-jdk maven

# Gradle
GRADLE_VERSION="8.12"
wget -q "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip"
sudo unzip -q -d /opt/gradle "gradle-${GRADLE_VERSION}-bin.zip"
rm "gradle-${GRADLE_VERSION}-bin.zip"
sudo ln -sf "/opt/gradle/gradle-${GRADLE_VERSION}/bin/gradle" /usr/local/bin/gradle

# sbt (for Scala)
echo "deb https://repo.scala-sbt.org/scalasbt/debian all main" | sudo tee /etc/apt/sources.list.d/sbt.list
curl -sL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x2EE0EA64E40A89B84B2DF73499E82A75642AC823" | sudo gpg --dearmor -o /usr/share/keyrings/sbt-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/sbt-archive-keyring.gpg] https://repo.scala-sbt.org/scalasbt/debian all main" | sudo tee /etc/apt/sources.list.d/sbt.list
sudo apt update
sudo apt install -y sbt

# -----------------------------------------------------------------------------
# Cleanup
# -----------------------------------------------------------------------------
echo ">>> Cleaning up..."
sudo apt autoremove -y
sudo apt clean

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo "=== Installation Complete ==="
echo ""
echo "Installed tools:"
echo "  Core: git, curl, wget, jq, nano, ripgrep, fd, fzf, shellcheck, sqlite3, gdb"
echo "  Languages: Python 3.12 (uv), Node.js 25, Go 1.25, Rust, .NET 9, PHP, Ruby, JDK 21"
echo "  Containers: Docker, docker-buildx, docker-compose, crane, hadolint, dive, trivy, skopeo"
echo "  Cloud CLIs: gcloud, aws, az"
echo "  Linters: ruff, mypy, eslint, prettier, rubocop, actionlint, golangci-lint, hadolint, yamllint, cspell, markdownlint"
echo "  Build tools: maven, gradle, sbt, terraform, yarn, pnpm"
echo "  Other: gh, yq, delta, pre-commit, claude, beads"
echo ""
echo "NOTE: Log out and back in (or run 'newgrp docker') to use Docker without sudo."
echo "NOTE: Run 'source ~/.bashrc' to update PATH in current shell."
