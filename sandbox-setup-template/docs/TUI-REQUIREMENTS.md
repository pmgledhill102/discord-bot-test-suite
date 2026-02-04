# Terminal UI (TUI) Requirements

A terminal-based user interface for managing AI coding agent sandboxes.

## Overview

The TUI provides a simple interface to:

1. Verify prerequisites and setup status
2. Manage VM lifecycle (create, start, stop, resize)
3. Monitor and manage agent sessions

## Implementation Approach

Per ADR-0011 and ADR-0013:

- **Language:** Go with Bubbletea (TUI) + Cobra (CLI)
- **Cloud operations:** Native Go SDKs (not gcloud CLI)
- **Remote commands:** Go SSH library for programmatic commands
- **Interactive connect:** Shell out to `ssh` for terminal attachment

## User Interface Concept

```text
┌─────────────────────────────────────────────────────────────────┐
│  cloudcoop                                           v0.1.0     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Infrastructure Status                                          │
│  ────────────────────                                           │
│  Cloud: GCP (europe-north2-a)                                   │
│  VM: claude-sandbox          ● Running (c4a-highcpu-16)        │
│  IP Firewall: ✓ 203.0.113.42/32                                │
│  Uptime: 2h 34m              Cost: ~$0.12/hr (spot)            │
│                                                                 │
│  Agent Sessions (8 active)                                      │
│  ────────────────────────                                       │
│  [1] agent-1   claude  ● issue-142  go-gin       2h 30m        │
│  [2] agent-2   claude  ● issue-143  flask        2h 28m        │
│  [3] agent-3   aider   ● issue-144  quick fix    1h 45m        │
│  [4] agent-4   claude  ○ idle                    -             │
│  ...                                                            │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│  [S]tart  s[T]op  [R]esize  [A]dd  [K]ill  [C]onnect  [Q]uit   │
└─────────────────────────────────────────────────────────────────┘
```

## Functional Requirements

### 1. Setup Verification

Check and display the status of required infrastructure:

| Check              | Description                  | Implementation                    |
| ------------------ | ---------------------------- | --------------------------------- |
| GCP Authentication | SDK can authenticate         | `google.FindDefaultCredentials()` |
| Project Set        | Correct project configured   | Config file + SDK validation      |
| Service Account    | SA exists with correct roles | IAM SDK `GetServiceAccount`       |
| VM Exists          | Sandbox VM created           | Compute SDK `Instances.Get`       |
| Firewall Rules     | SSH access configured        | Compute SDK `Firewalls.Get`       |

**Setup wizard:** If any prerequisite is missing, guide user through creation (see SETUP-FLOW.md).

### 2. VM Lifecycle Management

#### 2.1 View Status

Display current VM state via Compute SDK:

```go
instance, err := client.Get(ctx, &computepb.GetInstanceRequest{...})
// Extract: status, machineType, networkInterfaces, scheduling
```

Display:

- Instance name and zone
- Current status (RUNNING, STOPPED, TERMINATED, etc.)
- Machine type (e.g., c4a-highcpu-16)
- Internal/external IP (when running)
- Uptime (when running)
- Estimated hourly/monthly cost

#### 2.2 Start VM

```go
op, err := client.Start(ctx, &computepb.StartInstanceRequest{...})
err = op.Wait(ctx)
```

Post-action: Wait for RUNNING status, display IP, offer to connect.

#### 2.3 Stop VM

```go
op, err := client.Stop(ctx, &computepb.StopInstanceRequest{...})
err = op.Wait(ctx)
```

Pre-check: Warn if agents have uncommitted work (via SSH check).
Post-action: Confirm stopped, show disk-only cost estimate.

#### 2.4 Resize VM

Change machine type (requires stopped VM):

```text
Current: c4a-highcpu-16 (16 vCPU, 32GB) - ~$0.12/hr spot
Available sizes:
  [1] arm-8cpu-16gb   ( 8 vCPU, 16GB) - ~$0.06/hr spot
  [2] arm-16cpu-32gb  (16 vCPU, 32GB) - ~$0.12/hr spot  ← current
  [3] arm-32cpu-64gb  (32 vCPU, 64GB) - ~$0.24/hr spot

Select size [1-3]:
```

```go
op, err := client.SetMachineType(ctx, &computepb.SetMachineTypeInstanceRequest{...})
```

Pre-check: VM must be stopped (offer to stop if running).

### 3. Agent Session Management

Agent session management uses Go SSH library (per ADR-0013).

#### 3.1 List Sessions

```go
output, err := sshClient.Run(`tmux list-windows -t agents -F '#{window_index}|#{window_name}|#{pane_current_command}'`)
```

Display:

- Window/pane index
- Session name (e.g., "agent-1", "issue-142")
- Agent type (claude, aider, etc.)
- Current process (claude, bash, idle)
- Duration

#### 3.2 Add Agent Session

```go
agentCmd := "claude --dangerously-skip-permissions"  // From agent config
err := sshClient.Run(fmt.Sprintf(`tmux new-window -t agents -n %s '%s'`, name, agentCmd))
```

Options:

- Select agent type (Claude, Aider, etc.)
- Specify working directory
- Resume existing session (`--continue` or `--resume`)
- Fresh session

#### 3.3 Remove Agent Session

```go
err := sshClient.Run(fmt.Sprintf(`tmux kill-window -t agents:%s`, index))
```

Pre-check: Warn if agent process is active (not idle).

#### 3.4 Connect to Agent

Interactive connection shells out to `ssh` for proper terminal handling:

```go
cmd := exec.Command("ssh", "-t", host,
    fmt.Sprintf("tmux select-window -t agents:%s && tmux attach -t agents", index))
cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
cmd.Run()
```

### 4. Quick Actions

| Key | Action  | Description               |
| --- | ------- | ------------------------- |
| S   | Start   | Start stopped VM          |
| T   | Stop    | Stop running VM           |
| R   | Resize  | Change machine type       |
| A   | Add     | Create new agent session  |
| K   | Kill    | Remove agent session      |
| C   | Connect | SSH into agent session    |
| L   | Logs    | View recent activity logs |
| Q   | Quit    | Exit TUI                  |

### 5. Monitoring View

Optional expanded view showing real-time agent activity:

```text
┌─ Agent 1: issue-142 ─────────────────────────────────────────┐
│ Type: Claude Code                                            │
│ Working on: go-gin service implementation                    │
│ Last action: Modified services/go-gin/handlers/ping.go      │
│ Files changed: 3  |  Commits: 2  |  Tests: passing          │
└──────────────────────────────────────────────────────────────┘
┌─ Agent 2: issue-143 ─────────────────────────────────────────┐
│ Type: Aider                                                  │
│ Working on: python-flask service                             │
│ Last action: Running pytest                                  │
│ Files changed: 5  |  Commits: 1  |  Tests: 12/14 passing    │
└──────────────────────────────────────────────────────────────┘
```

## Non-Functional Requirements

### Simplicity

- Single binary, no runtime dependencies
- Configuration via `~/.config/cloudcoop/config.yaml`
- Keyboard-driven navigation
- Clear, minimal UI

### Responsiveness

- Status checks should complete in <2 seconds
- VM operations show progress indicator
- SSH operations timeout gracefully (5s default)

### Error Handling

- Clear error messages with suggested fixes
- Graceful handling of network issues
- Retry logic for transient failures

## Future Enhancements

- Cost tracking and alerts
- Agent task assignment from TUI
- Git status summary per agent
- Automatic session naming based on issue numbers
- Integration with issue tracker (GitHub Issues, Linear, etc.)
- Multi-VM support for different projects
- AWS and Azure provider support
