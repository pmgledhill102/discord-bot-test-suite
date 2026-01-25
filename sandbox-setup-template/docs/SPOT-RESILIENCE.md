# Spot Instance Resilience for Claude Code

When using GCP spot/preemptible instances, you get a **30-second warning** before termination. This guide shows how to preserve Claude Code session state across preemptions.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     Spot Instance (ephemeral)                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  tmux sessions with Claude Code agents                    │  │
│  │  ~/.claude/ ──symlink──► /mnt/persist/.claude/           │  │
│  │  /workspaces/ ──mount──► /mnt/persist/workspaces/        │  │
│  └──────────────────────────────────────────────────────────┘  │
│                              │                                  │
│              shutdown-hook: saves session state                 │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                ┌──────────────┴──────────────┐
                │    Persistent SSD Disk       │
                │    /mnt/persist/             │
                │    ├── .claude/              │  ← Session DB
                │    ├── workspaces/           │  ← Git repos
                │    ├── session-state/        │  ← Agent metadata
                │    └── backups/              │  ← Periodic snapshots
                └─────────────────────────────┘
```

## Key Mechanisms

### 1. Persistent Disk for Session Storage

Claude Code stores sessions in `~/.claude/` (SQLite database). Mount this on persistent storage:

```bash
# Create persistent disk (one-time)
gcloud compute disks create claude-persist \
  --size=50GB \
  --type=pd-ssd \
  --zone=europe-north1-b

# Attach to instance
gcloud compute instances attach-disk claude-sandbox \
  --disk=claude-persist \
  --zone=europe-north1-b
```

### 2. Session Resumption

Claude Code has built-in session persistence:

```bash
# Continue most recent session
claude --continue

# Resume specific named session
claude --resume my-task-name

# Interactive session picker
claude --resume
```

### 3. Preemption Shutdown Hook

GCP sends SIGTERM 30 seconds before termination. Use this to save state:

```bash
# /etc/systemd/system/claude-shutdown.service
[Unit]
Description=Save Claude state on shutdown
DefaultDependencies=no
Before=shutdown.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/save-claude-state.sh
TimeoutStartSec=25

[Install]
WantedBy=shutdown.target
```

## Implementation Files

See the following scripts in this directory:
- `setup-persistent-storage.sh` - Initial disk setup
- `save-claude-state.sh` - Shutdown hook to save state
- `restore-claude-state.sh` - Startup restoration
- `start-agents-resilient.sh` - Start agents with auto-resume

## Session Naming Convention

Name sessions for easy resumption after preemption:

```bash
# Inside Claude Code session, rename it:
/rename agent-1-issue-123

# Later, resume by name:
claude --resume agent-1-issue-123
```

## Monitoring Preemption

Check if running on a preemptible instance:

```bash
curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/scheduling/preemptible"
```

Monitor for preemption notice:

```bash
curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/preempted"
```
