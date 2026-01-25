# Terminal UI (TUI) Requirements

A terminal-based user interface for managing the Claude Code sandbox environment.

## Overview

The TUI provides a simple interface to:
1. Verify prerequisites and setup status
2. Manage VM lifecycle (create, start, stop, resize)
3. Monitor and manage agent sessions

## User Interface Concept

```
┌─────────────────────────────────────────────────────────────────┐
│  Claude Sandbox Manager                              v0.1.0     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Infrastructure Status                                          │
│  ────────────────────                                           │
│  Service Account:  ✓ claude-sandbox@project.iam.gserviceaccount │
│  VM Instance:      ✓ claude-sandbox (europe-north2-a)           │
│  VM Status:        ● Running (c4a-highcpu-16)                   │
│  Uptime:           2h 34m                                       │
│  Monthly Cost:     ~$0.12/hr (spot)                             │
│                                                                 │
│  Agent Sessions (8 active)                                      │
│  ────────────────────────                                       │
│  [1] agent-1   ● issue-142  go-gin service      2h 30m          │
│  [2] agent-2   ● issue-143  python-flask        2h 28m          │
│  [3] agent-3   ● issue-144  contract tests      1h 45m          │
│  [4] agent-4   ○ idle                           -               │
│  ...                                                            │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│  [S]tart VM  [T]op VM  [R]esize  [A]dd Agent  [K]ill Agent     │
│  [C]onnect   [L]ogs    [Q]uit                                   │
└─────────────────────────────────────────────────────────────────┘
```

## Functional Requirements

### 1. Setup Verification

Check and display the status of required infrastructure:

| Check | Description | How to Verify |
|-------|-------------|---------------|
| GCP Authentication | Local gcloud authenticated | `gcloud auth list` |
| Project Set | Correct project selected | `gcloud config get project` |
| Service Account | SA exists with correct roles | `gcloud iam service-accounts describe` |
| IAM Bindings | SA has required permissions | `gcloud projects get-iam-policy` |
| VM Exists | Sandbox VM created | `gcloud compute instances describe` |
| Firewall Rules | SSH access configured | `gcloud compute firewall-rules list` |

**Setup wizard:** If any prerequisite is missing, offer to create it interactively.

### 2. VM Lifecycle Management

#### 2.1 View Status

Display current VM state:
- Instance name and zone
- Current status (RUNNING, STOPPED, TERMINATED, etc.)
- Machine type (e.g., c4a-highcpu-16)
- Internal/external IP (when running)
- Uptime (when running)
- Estimated hourly/monthly cost

#### 2.2 Start VM

```
Action: Start stopped VM
Command: gcloud compute instances start claude-sandbox --zone=europe-north2-a
Post-action: Wait for RUNNING status, display IP, offer to connect
```

#### 2.3 Stop VM

```
Action: Stop running VM
Pre-check: Warn if agents have uncommitted work
Command: gcloud compute instances stop claude-sandbox --zone=europe-north2-a
Post-action: Confirm stopped, show disk-only cost estimate
```

#### 2.4 Resize VM

Change machine type (requires stopped VM):

```
Current: c4a-highcpu-16 (16 vCPU, 32GB) - ~$0.12/hr spot
Available sizes:
  [1] c4a-highcpu-8   ( 8 vCPU, 16GB) - ~$0.06/hr spot
  [2] c4a-highcpu-16  (16 vCPU, 32GB) - ~$0.12/hr spot  ← current
  [3] c4a-highcpu-32  (32 vCPU, 64GB) - ~$0.24/hr spot
  [4] c4a-highcpu-48  (48 vCPU, 96GB) - ~$0.36/hr spot

Select size [1-4]:
```

```
Command: gcloud compute instances set-machine-type claude-sandbox \
           --zone=europe-north2-a --machine-type=c4a-highcpu-32
Pre-check: VM must be stopped (offer to stop if running)
```

### 3. Agent Session Management

#### 3.1 List Sessions

Query tmux sessions on the VM via SSH:

```bash
ssh claude-sandbox "tmux list-windows -t agents -F '#{window_index}:#{window_name}:#{pane_current_command}'"
```

Display:
- Window/pane index
- Session name (e.g., "agent-1", "issue-142")
- Current process (claude, bash, idle)
- Duration

#### 3.2 Add Agent Session

Create a new tmux window with Claude Code:

```bash
ssh claude-sandbox "tmux new-window -t agents -n agent-N 'claude --dangerously-skip-permissions'"
```

Options:
- Specify working directory
- Resume existing Claude session (`--continue` or `--resume`)
- Fresh session

#### 3.3 Remove Agent Session

Kill a tmux window:

```bash
ssh claude-sandbox "tmux kill-window -t agents:N"
```

Pre-check: Warn if Claude process is active (not idle).

#### 3.4 Connect to Agent

Attach to a specific agent's tmux window:

```bash
ssh -t claude-sandbox "tmux select-window -t agents:N && tmux attach -t agents"
```

### 4. Quick Actions

| Key | Action | Description |
|-----|--------|-------------|
| S | Start | Start stopped VM |
| T | Stop | Stop running VM |
| R | Resize | Change machine type |
| A | Add | Create new agent session |
| K | Kill | Remove agent session |
| C | Connect | SSH into agent session |
| L | Logs | View recent activity logs |
| Q | Quit | Exit TUI |

### 5. Monitoring View

Optional expanded view showing real-time agent activity:

```
┌─ Agent 1: issue-142 ─────────────────────────────────────────┐
│ Working on: go-gin service implementation                    │
│ Last action: Modified services/go-gin/handlers/ping.go      │
│ Files changed: 3  |  Commits: 2  |  Tests: passing          │
└──────────────────────────────────────────────────────────────┘
┌─ Agent 2: issue-143 ─────────────────────────────────────────┐
│ Working on: python-flask service                             │
│ Last action: Running pytest                                  │
│ Files changed: 5  |  Commits: 1  |  Tests: 12/14 passing    │
└──────────────────────────────────────────────────────────────┘
```

## Non-Functional Requirements

### Simplicity

- Single binary, no dependencies beyond gcloud CLI
- No configuration files required (uses gcloud defaults)
- Keyboard-driven navigation
- Clear, minimal UI

### Responsiveness

- Status checks should complete in <2 seconds
- VM operations show progress indicator
- SSH operations timeout gracefully

### Error Handling

- Clear error messages with suggested fixes
- Graceful handling of network issues
- Retry logic for transient failures

## Technology Considerations

Potential implementation approaches:

| Approach | Pros | Cons |
|----------|------|------|
| Go + bubbletea | Fast, single binary, good TUI library | Learning curve |
| Python + textual | Familiar, rich widgets | Requires Python runtime |
| Bash + dialog | Simple, universal | Limited UI capabilities |
| Rust + ratatui | Fast, safe, good TUI | Steeper learning curve |

**Recommendation:** Go with bubbletea for single-binary distribution and good TUI support.

## Future Enhancements

- Cost tracking and alerts
- Agent task assignment from TUI
- Git status summary per agent
- Automatic session naming based on issue numbers
- Integration with issue tracker (GitHub Issues, Linear, etc.)
- Multi-VM support for different projects
