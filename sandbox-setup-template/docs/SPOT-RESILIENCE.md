# Spot Instance Resilience for Claude Code

This guide covers two usage patterns:

1. **Stop/Start workflow** (simplest) - Keep VM, just stop when not in use
2. **Spot instance workflow** - Use cheap spot VMs with preemption handling

## Option 1: Stop/Start Workflow (Recommended)

The simplest approach - create the VM once, stop it when not in use.

**Costs when stopped:**
- Compute: $0 (not running)
- Boot disk: ~$0.10/GB/month ($20/month for 200GB SSD)

```bash
# Create VM once
gcloud compute instances create claude-sandbox \
  --zone=europe-north1-b \
  --machine-type=c4a-highcpu-16 \
  --boot-disk-size=200GB \
  --boot-disk-type=pd-ssd \
  --image-family=ubuntu-2404-lts-arm64 \
  --image-project=ubuntu-os-cloud

# When you want to work
gcloud compute instances start claude-sandbox --zone=europe-north1-b
# SSH in, run: ./start-agents-resilient.sh 12 continue

# When done working
gcloud compute instances stop claude-sandbox --zone=europe-north1-b
```

**Everything persists:**
- `~/.claude/` - All Claude sessions intact
- `/workspaces/` - All git repos and work
- Installed tools, configs, everything

**Resume agents after start:**
```bash
# Agents auto-continue their previous sessions
./start-agents-resilient.sh 12 continue
```

---

## Option 2: Spot Instance Workflow

Use spot VMs for ~70% cost savings, with automatic state preservation.

**How spot preemption works:**
1. GCP sends SIGTERM with 30-second warning
2. Shutdown hook saves state (git stash, session metadata)
3. Boot disk survives (default behavior)
4. You restart the instance, agents resume

### Setup

Boot disks persist by default. Just ensure auto-delete is off:

```bash
# Create spot instance
gcloud compute instances create claude-sandbox \
  --zone=europe-north1-b \
  --machine-type=c4a-highcpu-16 \
  --boot-disk-size=200GB \
  --boot-disk-type=pd-ssd \
  --boot-disk-auto-delete=no \
  --image-family=ubuntu-2404-lts-arm64 \
  --image-project=ubuntu-os-cloud \
  --provisioning-model=SPOT \
  --instance-termination-action=STOP
```

Key flags:
- `--boot-disk-auto-delete=no` - Disk survives instance deletion
- `--provisioning-model=SPOT` - Use spot pricing
- `--instance-termination-action=STOP` - Stop (don't delete) on preemption

### Shutdown Hook

Install the shutdown hook to cleanly save state before preemption:

```bash
sudo cp scripts/save-claude-state.sh /usr/local/bin/
sudo cp scripts/restore-claude-state.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/*.sh

# Install systemd service
sudo tee /etc/systemd/system/claude-shutdown.service << 'EOF'
[Unit]
Description=Save Claude state on shutdown/preemption
DefaultDependencies=no
Before=shutdown.target reboot.target halt.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/save-claude-state.sh
TimeoutStartSec=25

[Install]
WantedBy=shutdown.target reboot.target halt.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable claude-shutdown.service
```

### After Preemption

```bash
# Restart the stopped instance
gcloud compute instances start claude-sandbox --zone=europe-north1-b

# SSH in and resume
./start-agents-resilient.sh 12 continue
```

---

## Testing

```bash
# Test shutdown hook without shutting down
sudo /usr/local/bin/save-claude-state.sh
cat /var/log/claude-state-save.log

# Test full cycle
sudo reboot
# After reboot:
./start-agents-resilient.sh 12 continue
```

---

## Session Resumption

Claude Code has built-in session persistence:

```bash
# Continue most recent session in current directory
claude --continue

# Resume specific named session
claude --resume my-task-name

# Interactive session picker
claude --resume
```

**Tip:** Name your sessions for easy resumption:
```bash
# Inside Claude Code:
/rename agent-1-issue-123

# Later:
claude --resume agent-1-issue-123
```

---

## Cost Comparison

For c4a-highcpu-16 in europe-north1 (Finland):

| Usage Pattern | Monthly Cost |
|---------------|-------------|
| On-demand 24/7 | ~$280 |
| On-demand 8h/day | ~$95 |
| Spot 24/7 | ~$85 |
| Spot 8h/day | ~$30 |
| Stopped (disk only) | ~$20 |

**Recommendation:**
- Predictable work: Stop/start on-demand
- Cost-sensitive: Spot with auto-restart
