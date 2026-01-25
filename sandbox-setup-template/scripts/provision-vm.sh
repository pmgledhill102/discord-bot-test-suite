#!/bin/bash
# VM Provisioning Script - Runs on first boot via startup-script metadata
# Installs Docker, pulls agent images, and configures the sandbox environment

set -e

LOG_FILE="/var/log/claude-sandbox-provision.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== Claude Sandbox VM Provisioning ==="
echo "Started at: $(date)"
echo "Hostname: $(hostname)"

# Wait for cloud-init to complete
cloud-init status --wait || true

# Update system packages
echo "Updating system packages..."
apt-get update
apt-get upgrade -y

# Install Docker
echo "Installing Docker..."
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Configure Docker
echo "Configuring Docker..."
systemctl enable docker
systemctl start docker

# Configure Docker to use less disk space
cat > /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
EOF
systemctl restart docker

# Install additional tools
echo "Installing additional tools..."
apt-get install -y \
    git \
    jq \
    htop \
    tmux \
    screen \
    ncdu \
    ripgrep

# Install gcloud CLI (if not present)
if ! command -v gcloud &> /dev/null; then
    echo "Installing gcloud CLI..."
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
    apt-get update
    apt-get install -y google-cloud-cli
fi

# Configure Docker credential helper for Artifact Registry
echo "Configuring Docker for Artifact Registry..."
gcloud auth configure-docker us-central1-docker.pkg.dev --quiet 2>/dev/null || true

# Create sandbox user
echo "Creating sandbox user..."
if ! id "sandbox" &>/dev/null; then
    useradd -m -s /bin/bash sandbox
    usermod -aG docker sandbox
fi

# Create workspace directories
echo "Creating workspace directories..."
mkdir -p /workspaces
mkdir -p /config
mkdir -p /var/log/claude-agents
chown -R sandbox:sandbox /workspaces /config /var/log/claude-agents

# Set up systemd service for agent management
cat > /etc/systemd/system/claude-agents.service <<EOF
[Unit]
Description=Claude Code Agents
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
User=sandbox
WorkingDirectory=/workspaces
ExecStart=/usr/local/bin/start-agents.sh
ExecStop=/usr/local/bin/stop-agents.sh

[Install]
WantedBy=multi-user.target
EOF

# Create convenience scripts
cat > /usr/local/bin/start-agents.sh <<'SCRIPT'
#!/bin/bash
AGENT_COUNT=${AGENT_COUNT:-12}
echo "Starting $AGENT_COUNT Claude agents..."
cd /workspaces
docker compose up -d --scale agent=$AGENT_COUNT 2>/dev/null || docker-compose up -d --scale agent=$AGENT_COUNT
SCRIPT

cat > /usr/local/bin/stop-agents.sh <<'SCRIPT'
#!/bin/bash
echo "Stopping all Claude agents..."
cd /workspaces
docker compose down 2>/dev/null || docker-compose down
SCRIPT

cat > /usr/local/bin/agent-logs.sh <<'SCRIPT'
#!/bin/bash
AGENT_ID=${1:-1}
docker logs -f "claude-agent-${AGENT_ID}" 2>/dev/null || docker logs -f "workspaces-agent-${AGENT_ID}"
SCRIPT

cat > /usr/local/bin/agent-shell.sh <<'SCRIPT'
#!/bin/bash
AGENT_ID=${1:-1}
docker exec -it "claude-agent-${AGENT_ID}" /bin/bash 2>/dev/null || docker exec -it "workspaces-agent-${AGENT_ID}" /bin/bash
SCRIPT

chmod +x /usr/local/bin/*.sh

# Pull agent images (if registry is configured)
echo "Attempting to pull agent images..."
PROJECT_ID=$(curl -s "http://metadata.google.internal/computeMetadata/v1/project/project-id" -H "Metadata-Flavor: Google")
REGION="us-central1"
REGISTRY="${REGION}-docker.pkg.dev/${PROJECT_ID}/claude-sandbox"

docker pull "${REGISTRY}/agent:latest" 2>/dev/null || echo "Agent image not found in registry - will need to build locally"

# Set up tmux configuration for multi-pane viewing
cat > /home/sandbox/.tmux.conf <<'EOF'
# Claude Sandbox tmux configuration
set -g mouse on
set -g history-limit 50000
set -g base-index 1
setw -g pane-base-index 1

# Better colors
set -g default-terminal "screen-256color"

# Status bar
set -g status-bg black
set -g status-fg white
set -g status-left '[#S] '
set -g status-right '%H:%M %d-%b'

# Easy pane navigation
bind -n M-Left select-pane -L
bind -n M-Right select-pane -R
bind -n M-Up select-pane -U
bind -n M-Down select-pane -D
EOF
chown sandbox:sandbox /home/sandbox/.tmux.conf

# Create tmux session launcher
cat > /usr/local/bin/sandbox-tmux.sh <<'SCRIPT'
#!/bin/bash
# Launch tmux session with agent panes
AGENT_COUNT=${1:-12}
SESSION_NAME="claude-sandbox"

tmux kill-session -t $SESSION_NAME 2>/dev/null || true
tmux new-session -d -s $SESSION_NAME

# Create panes in a 4x3 grid for 12 agents
for i in $(seq 2 $AGENT_COUNT); do
    if [ $((i % 4)) -eq 1 ]; then
        tmux split-window -v -t $SESSION_NAME
    else
        tmux split-window -h -t $SESSION_NAME
    fi
    tmux select-layout -t $SESSION_NAME tiled
done

# Run agent-logs in each pane
for i in $(seq 1 $AGENT_COUNT); do
    tmux send-keys -t $SESSION_NAME:0.$((i-1)) "agent-logs.sh $i" Enter
done

tmux attach -t $SESSION_NAME
SCRIPT
chmod +x /usr/local/bin/sandbox-tmux.sh

echo "=== Provisioning Complete ==="
echo "Finished at: $(date)"
echo ""
echo "Quick start:"
echo "  1. SSH into VM: gcloud compute ssh $(hostname) --zone=ZONE --tunnel-through-iap"
echo "  2. Switch to sandbox user: sudo su - sandbox"
echo "  3. Start agents: start-agents.sh"
echo "  4. View in tmux: sandbox-tmux.sh 12"
