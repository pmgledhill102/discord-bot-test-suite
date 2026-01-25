# Claude Code Sandboxing Infrastructure

A reusable infrastructure pattern for running multiple Claude Code agents directly on a Google Cloud Compute Engine VM with full development tooling.

## Overview

This repository provisions a GCP VM configured as a secure sandbox for running 10-12 concurrent Claude Code agents. Each agent runs in its own shell session (via tmux) with:

- Full development tooling pre-installed (matching Anthropic's official devcontainer)
- Isolated workspaces per agent
- Docker available for agents to build/run containers
- Configurable GCP service account permissions
- Ghostty terminal integration for local multi-pane monitoring

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                     GCP Compute Engine VM                         │
│                      (e2-standard-16)                             │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │                    tmux session manager                     │  │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐    ┌──────────┐   │  │
│  │  │ Session 1│ │ Session 2│ │ Session 3│ ...│Session 12│   │  │
│  │  │  claude  │ │  claude  │ │  claude  │    │  claude  │   │  │
│  │  │   code   │ │   code   │ │   code   │    │   code   │   │  │
│  │  │          │ │          │ │          │    │          │   │  │
│  │  │/work/ag1 │ │/work/ag2 │ │/work/ag3 │    │/work/ag12│   │  │
│  │  └──────────┘ └──────────┘ └──────────┘    └──────────┘   │  │
│  └────────────────────────────────────────────────────────────┘  │
│                              │                                    │
│  ┌───────────────────────────┴────────────────────────────────┐  │
│  │                    Shared Infrastructure                    │  │
│  │  • Docker Engine (for agent container builds)               │  │
│  │  • Development tooling (languages, CLIs, utilities)         │  │
│  │  • Git credentials & SSH keys                               │  │
│  └────────────────────────────────────────────────────────────┘  │
│                              │                                    │
│                    Service Account                                │
│              (limited GCP API permissions)                        │
└──────────────────────────────┬───────────────────────────────────┘
                               │
                    ┌──────────┴──────────┐
                    │   Your Workstation   │
                    │  (ghostty terminal)  │
                    │   SSH multiplexing   │
                    └─────────────────────┘
```

## Pre-installed Tooling

Based on Anthropic's official devcontainer plus additional tools for comprehensive development:

### Core (from Anthropic devcontainer)
| Tool | Purpose |
|------|---------|
| Node.js 20 LTS | Claude Code runtime |
| @anthropic-ai/claude-code | Claude Code CLI |
| git | Version control |
| gh (GitHub CLI) | GitHub operations |
| jq | JSON processing |
| fzf | Fuzzy finder |
| ripgrep (rg) | Fast code search |
| git-delta | Syntax-highlighted git diffs |
| zsh + powerlevel10k | Enhanced shell |

### Language Runtimes
| Runtime | Version | Package Manager |
|---------|---------|-----------------|
| Node.js | 20 LTS | npm, yarn, pnpm |
| Python | 3.11+ | pip, pipx, poetry, uv |
| Go | 1.22+ | go modules |
| Rust | latest | cargo, rustup |
| Java | 21 (Temurin) | Maven, Gradle |
| Ruby | 3.3+ | bundler, gem |
| PHP | 8.3+ | composer |
| .NET | 8.0 | dotnet CLI |

### Build & Development Tools
| Category | Tools |
|----------|-------|
| Containers | docker, docker-compose, buildx |
| Cloud CLIs | gcloud, gsutil, bq |
| Kubernetes | kubectl, helm, k9s |
| Databases | psql, mysql-client, redis-cli, mongosh |
| HTTP/API | curl, wget, httpie, grpcurl |
| Text processing | jq, yq, xmllint, csvkit |
| Editors | vim, nano, micro |
| Monitoring | htop, btop, ncdu |

### Code Quality & Testing
| Category | Tools |
|----------|-------|
| Linting | eslint, prettier, black, ruff, golangci-lint, rubocop, phpcs |
| Testing | jest, pytest, go test, cargo test, rspec, phpunit |
| Security | trivy, grype, semgrep |
| Git hooks | pre-commit |

## Quick Start

```bash
# 1. Set your GCP project
export PROJECT_ID=your-project-id
export REGION=us-central1
export ZONE=us-central1-a

# 2. Create infrastructure
cd terraform
terraform init
terraform apply

# 3. Connect to VM
./scripts/connect.sh

# 4. Start agent sessions
./scripts/start-agents.sh 12

# 5. (Local) Set up Ghostty for multi-pane view
./scripts/setup-ghostty.sh 12
```

## Directory Structure

```
.
├── README.md
├── terraform/              # GCP infrastructure as code
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── vm.tf              # Compute Engine instance
│   ├── iam.tf             # Service account & permissions
│   ├── network.tf         # VPC & firewall rules
│   └── terraform.tfvars.example
├── packer/                 # VM image builder (optional)
│   ├── claude-sandbox.pkr.hcl
│   └── scripts/
│       └── install-tools.sh
├── config/
│   ├── claude-settings.json    # Default Claude Code settings
│   ├── ssh-config.template     # SSH config for multiplexing
│   └── ghostty-config.template # Ghostty terminal config
├── scripts/
│   ├── connect.sh         # SSH into VM
│   ├── start-agents.sh    # Launch N tmux sessions with claude
│   ├── stop-agents.sh     # Stop all agent sessions
│   ├── attach.sh          # Attach to specific agent session
│   ├── list-agents.sh     # Show all running agents
│   ├── provision-vm.sh    # Post-boot VM setup (installs all tools)
│   └── setup-ghostty.sh   # Configure local ghostty
└── docs/
    ├── TOOLING.md         # Complete tool list with versions
    ├── SECURITY.md        # Security considerations
    ├── TROUBLESHOOTING.md
    └── COST-OPTIMIZATION.md
```

## Security Model

The VM runs under a dedicated service account with minimal permissions:

- **Artifact Registry Reader** - Pull container images
- **Cloud Storage Object Viewer** - Read shared assets (optional)
- **Pub/Sub Publisher** - Send messages (optional)
- **Secret Manager Accessor** - Access specific secrets (optional)

**What's NOT permitted:**
- IAM modifications
- Compute Admin (can't create/delete VMs)
- Network Admin
- Billing access

### Agent Isolation

Each agent session:
- Runs in a dedicated tmux window
- Has its own workspace directory (`/workspaces/agent-N`)
- Shares Docker daemon (agents can build/run containers)
- Shares git credentials and SSH keys

## Local Ghostty Integration

Configure Ghostty to show multiple agent sessions in a tiled layout:

```bash
# Generate config and launcher scripts
./scripts/setup-ghostty.sh 12

# Launch multi-pane view (connects to VM, opens tmux)
./config/launch-sandbox-view.sh
```

## Configuration

### Environment Variables (on VM)

| Variable | Description | Default |
|----------|-------------|---------|
| `ANTHROPIC_API_KEY` | Claude API key | (required) |
| `AGENT_COUNT` | Number of agent sessions | 12 |
| `WORKSPACE_BASE` | Base directory for workspaces | /workspaces |

### Claude Code Settings (Permissive Mode)

The default configuration runs with `--dangerously-skip-permissions` for automated operation:

```bash
claude --dangerously-skip-permissions
```

## Cost Management

Estimated monthly costs (us-central1):

| Configuration | Agents | Monthly Cost |
|--------------|--------|--------------|
| e2-standard-8 | 6-8 | ~$200 |
| e2-standard-16 | 10-12 | ~$400 |
| n2-standard-16 | 10-12 | ~$500 |

**Save money:**
- Use spot/preemptible instances (60-70% off)
- Schedule shutdown during off-hours
- Use committed use discounts

## Building a Custom VM Image (Optional)

For faster VM boot times, pre-bake all tools into a custom image:

```bash
cd packer
packer build claude-sandbox.pkr.hcl
```

Then reference the image in terraform instead of using startup scripts.

## License

MIT
