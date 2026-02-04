#!/bin/bash
# setup-persistent-storage.sh
# Sets up persistent storage for Claude Code sessions to survive spot preemption
#
# Run once after creating the persistent disk

set -e

PERSIST_DISK="${PERSIST_DISK:-claude-persist}"
PERSIST_MOUNT="/mnt/persist"
SANDBOX_USER="${SANDBOX_USER:-sandbox}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Must run as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo)"
    exit 1
fi

log_info "Setting up persistent storage for Claude Code sessions..."

# Find the persistent disk device
DISK_DEVICE=""
for dev in /dev/sd[b-z] /dev/nvme[0-9]n[0-9]; do
    if [ -b "$dev" ]; then
        # Check if it's the right size (our persist disk)
        SIZE=$(lsblk -b -d -n -o SIZE "$dev" 2>/dev/null || echo 0)
        if [ "$SIZE" -gt 0 ]; then
            DISK_DEVICE="$dev"
            break
        fi
    fi
done

if [ -z "$DISK_DEVICE" ]; then
    log_warn "No additional disk found. Creating local persistent directory instead."
    mkdir -p "$PERSIST_MOUNT"
else
    log_info "Found disk device: $DISK_DEVICE"

    # Check if already formatted
    if ! blkid "$DISK_DEVICE" | grep -q ext4; then
        log_info "Formatting disk as ext4..."
        mkfs.ext4 -F "$DISK_DEVICE"
    fi

    # Create mount point
    mkdir -p "$PERSIST_MOUNT"

    # Mount the disk
    if ! mountpoint -q "$PERSIST_MOUNT"; then
        log_info "Mounting $DISK_DEVICE to $PERSIST_MOUNT..."
        mount "$DISK_DEVICE" "$PERSIST_MOUNT"
    fi

    # Add to fstab for auto-mount on boot
    if ! grep -q "$PERSIST_MOUNT" /etc/fstab; then
        UUID=$(blkid -s UUID -o value "$DISK_DEVICE")
        echo "UUID=$UUID $PERSIST_MOUNT ext4 defaults,nofail 0 2" >> /etc/fstab
        log_info "Added to /etc/fstab"
    fi
fi

# Create directory structure
log_info "Creating directory structure..."
mkdir -p "$PERSIST_MOUNT/.claude"
mkdir -p "$PERSIST_MOUNT/workspaces"
mkdir -p "$PERSIST_MOUNT/session-state"
mkdir -p "$PERSIST_MOUNT/backups"

# Set ownership
chown -R "$SANDBOX_USER:$SANDBOX_USER" "$PERSIST_MOUNT"

# Create symlink for .claude directory
SANDBOX_HOME="/home/$SANDBOX_USER"
if [ -d "$SANDBOX_HOME/.claude" ] && [ ! -L "$SANDBOX_HOME/.claude" ]; then
    log_info "Backing up existing .claude directory..."
    mv "$SANDBOX_HOME/.claude" "$SANDBOX_HOME/.claude.backup"
fi

if [ ! -L "$SANDBOX_HOME/.claude" ]; then
    log_info "Creating symlink: $SANDBOX_HOME/.claude -> $PERSIST_MOUNT/.claude"
    ln -sf "$PERSIST_MOUNT/.claude" "$SANDBOX_HOME/.claude"
    chown -h "$SANDBOX_USER:$SANDBOX_USER" "$SANDBOX_HOME/.claude"
fi

# Set up workspaces mount/symlink
if [ -d "/workspaces" ] && [ ! -L "/workspaces" ]; then
    log_info "Moving existing workspaces to persistent storage..."
    rsync -a /workspaces/ "$PERSIST_MOUNT/workspaces/"
    rm -rf /workspaces
fi

if [ ! -L "/workspaces" ]; then
    log_info "Creating symlink: /workspaces -> $PERSIST_MOUNT/workspaces"
    ln -sf "$PERSIST_MOUNT/workspaces" /workspaces
fi

# Create agent workspace directories on persistent storage
for i in $(seq 1 16); do
    mkdir -p "$PERSIST_MOUNT/workspaces/agent-$i"
done
chown -R "$SANDBOX_USER:$SANDBOX_USER" "$PERSIST_MOUNT/workspaces"

# Install shutdown hook
log_info "Installing shutdown hook..."
cat > /etc/systemd/system/claude-shutdown.service << 'EOF'
[Unit]
Description=Save Claude Code state on shutdown/preemption
DefaultDependencies=no
Before=shutdown.target reboot.target halt.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/save-claude-state.sh
TimeoutStartSec=25
RemainAfterExit=yes

[Install]
WantedBy=shutdown.target reboot.target halt.target
EOF

systemctl daemon-reload
systemctl enable claude-shutdown.service

# Install startup hook
log_info "Installing startup hook..."
cat > /etc/systemd/system/claude-startup.service << 'EOF'
[Unit]
Description=Restore Claude Code state on startup
After=network.target local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/restore-claude-state.sh
RemainAfterExit=yes
User=sandbox

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable claude-startup.service

log_info "Setup complete!"
echo ""
echo "Persistent storage mounted at: $PERSIST_MOUNT"
echo "Claude sessions stored in: $PERSIST_MOUNT/.claude"
echo "Workspaces stored in: $PERSIST_MOUNT/workspaces"
echo ""
echo "On preemption, state will be automatically saved."
echo "On restart, use 'claude --continue' or 'claude --resume <name>' to resume."
