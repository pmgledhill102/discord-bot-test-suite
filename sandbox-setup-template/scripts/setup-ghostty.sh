#!/bin/bash
# Generate Ghostty terminal configuration for multi-pane agent viewing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$PROJECT_DIR/config"

AGENT_COUNT=${1:-12}
VM_NAME="${VM_NAME:-claude-sandbox}"
VM_ZONE="${VM_ZONE:-us-central1-a}"
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"

echo "Generating Ghostty configuration for $AGENT_COUNT agents..."

# Create config directory if needed
mkdir -p "$CONFIG_DIR"

# Generate main ghostty config
cat > "$CONFIG_DIR/ghostty-sandbox.conf" <<EOF
# Ghostty configuration for Claude Sandbox
# Generated for $AGENT_COUNT agents

# Font configuration
font-family = JetBrains Mono
font-size = 11

# Window configuration
window-decoration = true
window-padding-x = 4
window-padding-y = 4

# Colors (dark theme optimized for terminal work)
background = 1a1b26
foreground = c0caf5
selection-background = 33467c
selection-foreground = c0caf5

# Cursor
cursor-style = block
cursor-style-blink = true

# Shell integration
shell-integration = detect

# Performance
scrollback-limit = 50000

# Keybindings for pane navigation
keybind = ctrl+shift+h=goto_split:left
keybind = ctrl+shift+l=goto_split:right
keybind = ctrl+shift+j=goto_split:down
keybind = ctrl+shift+k=goto_split:up

# Initial window size (adjust based on monitor)
window-width = 1920
window-height = 1080
EOF

# Generate SSH config for multiplexing
cat > "$CONFIG_DIR/ssh-config-sandbox" <<EOF
# SSH config for Claude Sandbox - enables connection multiplexing
# Add this to ~/.ssh/config or use: ssh -F $CONFIG_DIR/ssh-config-sandbox

Host claude-sandbox
    HostName $VM_NAME
    User sandbox
    ProxyCommand gcloud compute ssh $VM_NAME --zone=$VM_ZONE --tunnel-through-iap --project=$PROJECT_ID --quiet --verbosity=none -- -W %h:%p

    # Connection multiplexing for faster subsequent connections
    ControlMaster auto
    ControlPath ~/.ssh/sockets/%r@%h-%p
    ControlPersist 600

    # Keep connection alive
    ServerAliveInterval 60
    ServerAliveCountMax 3

    # Compression
    Compression yes
EOF

# Create socket directory
mkdir -p ~/.ssh/sockets
chmod 700 ~/.ssh/sockets

# Generate launcher script
cat > "$CONFIG_DIR/launch-sandbox-view.sh" <<'LAUNCHER'
#!/bin/bash
# Launch Ghostty with multi-pane view of all agents

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_COUNT=${1:-12}

# Calculate grid dimensions
if [ $AGENT_COUNT -le 4 ]; then
    COLS=2
    ROWS=2
elif [ $AGENT_COUNT -le 6 ]; then
    COLS=3
    ROWS=2
elif [ $AGENT_COUNT -le 9 ]; then
    COLS=3
    ROWS=3
else
    COLS=4
    ROWS=3
fi

echo "Launching Ghostty with ${COLS}x${ROWS} grid for $AGENT_COUNT agents..."

# Method 1: Use ghostty with splits (if supported)
# ghostty --config="$SCRIPT_DIR/ghostty-sandbox.conf" ...

# Method 2: Launch tmux on remote and connect
# This is more reliable across different Ghostty versions

ghostty --config="$SCRIPT_DIR/ghostty-sandbox.conf" \
    -e ssh -F "$SCRIPT_DIR/ssh-config-sandbox" claude-sandbox \
    -t "sandbox-tmux.sh $AGENT_COUNT"
LAUNCHER

chmod +x "$CONFIG_DIR/launch-sandbox-view.sh"

# Generate alternative: direct multi-window launcher (one window per agent)
cat > "$CONFIG_DIR/launch-multi-window.sh" <<'MULTIWIN'
#!/bin/bash
# Launch multiple Ghostty windows, one per agent

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_COUNT=${1:-12}

echo "Launching $AGENT_COUNT Ghostty windows..."

for i in $(seq 1 $AGENT_COUNT); do
    ghostty --config="$SCRIPT_DIR/ghostty-sandbox.conf" \
        --title="Agent $i" \
        -e ssh -F "$SCRIPT_DIR/ssh-config-sandbox" claude-sandbox \
        -t "agent-logs.sh $i" &
    sleep 0.2  # Stagger window creation
done

echo "Launched $AGENT_COUNT windows. Use your window manager to tile them."
MULTIWIN

chmod +x "$CONFIG_DIR/launch-multi-window.sh"

echo ""
echo "Configuration generated in: $CONFIG_DIR/"
echo ""
echo "Files created:"
echo "  - ghostty-sandbox.conf    : Ghostty terminal settings"
echo "  - ssh-config-sandbox      : SSH config with IAP tunnel + multiplexing"
echo "  - launch-sandbox-view.sh  : Launch tmux-based multi-pane view"
echo "  - launch-multi-window.sh  : Launch separate window per agent"
echo ""
echo "Quick start:"
echo "  1. Add SSH config: cat $CONFIG_DIR/ssh-config-sandbox >> ~/.ssh/config"
echo "  2. Launch viewer:  $CONFIG_DIR/launch-sandbox-view.sh $AGENT_COUNT"
echo ""
echo "Or manually connect:"
echo "  ssh -F $CONFIG_DIR/ssh-config-sandbox claude-sandbox"
