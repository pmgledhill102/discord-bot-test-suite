# Claude Code Sandboxing Infrastructure

A reusable infrastructure pattern for running multiple Claude Code agents in isolated Docker containers on Google Cloud Compute Engine.

## Overview

This repository provisions a GCP VM configured as a secure sandbox for running 10-12 concurrent Claude Code agents. Each agent runs in its own Docker container with:

- Full development tooling pre-installed
- Isolated filesystem and network namespace
- Configurable GCP service account permissions
- Ghost terminal (ghostty) integration for local monitoring

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    GCP Compute Engine VM                     │
│                     (e2-standard-16)                         │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                    Docker Engine                         ││
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐     ┌─────────┐   ││
│  │  │ Agent 1 │ │ Agent 2 │ │ Agent 3 │ ... │Agent 12 │   ││
│  │  │ Claude  │ │ Claude  │ │ Claude  │     │ Claude  │   ││
│  │  │  Code   │ │  Code   │ │  Code   │     │  Code   │   ││
│  │  └────┬────┘ └────┬────┘ └────┬────┘     └────┬────┘   ││
│  │       │           │           │               │         ││
│  │  ┌────┴───────────┴───────────┴───────────────┴────┐   ││
│  │  │            Shared Volume Mounts                  │   ││
│  │  │         (workspaces, credentials, etc.)          │   ││
│  │  └─────────────────────────────────────────────────┘   ││
│  └─────────────────────────────────────────────────────────┘│
│                              │                               │
│                    Service Account                           │
│              (limited GCP API permissions)                   │
└──────────────────────────────┬──────────────────────────────┘
                               │
                    ┌──────────┴──────────┐
                    │   Your Workstation   │
                    │  (ghostty terminal)  │
                    │   SSH multiplexing   │
                    └─────────────────────┘
```

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

# 3. Build and push the agent image
cd ../docker
./build-and-push.sh

# 4. Connect and start agents
./scripts/connect.sh
./scripts/start-agents.sh 12
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
├── docker/
│   ├── Dockerfile         # Claude Code agent image
│   ├── Dockerfile.base    # Base image with all tooling
│   ├── build-and-push.sh
│   └── entrypoint.sh
├── config/
│   ├── claude-settings.json    # Default Claude Code settings
│   ├── ssh-config.template     # SSH config for multiplexing
│   └── ghostty-config.template # Ghostty terminal config
├── scripts/
│   ├── connect.sh         # SSH into VM
│   ├── start-agents.sh    # Launch N agent containers
│   ├── stop-agents.sh     # Stop all agents
│   ├── attach.sh          # Attach to specific agent
│   ├── logs.sh            # View agent logs
│   ├── provision-vm.sh    # Post-boot VM setup
│   └── setup-ghostty.sh   # Configure local ghostty
├── compose/
│   ├── docker-compose.yml # Multi-agent orchestration
│   └── .env.example
└── docs/
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

## Local Ghostty Integration

Configure ghostty to show multiple agent sessions:

```bash
# Generate ghostty config
./scripts/setup-ghostty.sh 12

# Opens 12-pane layout connected to each agent
ghostty --config=config/ghostty-sandbox.conf
```

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ANTHROPIC_API_KEY` | Claude API key | (required) |
| `AGENT_COUNT` | Number of agents to run | 12 |
| `WORKSPACE_DIR` | Shared workspace mount | /workspaces |
| `CLAUDE_SETTINGS` | Path to settings.json | /config/claude-settings.json |

### Claude Code Settings (Permissive Mode)

The default configuration disables safety prompts for automated operation:

```json
{
  "permissions": {
    "allow_all": true
  },
  "auto_approve": ["Bash", "Write", "Edit"],
  "disable_confirmations": true
}
```

## Cost Management

Estimated monthly costs (us-central1):

| Configuration | Agents | Monthly Cost |
|--------------|--------|--------------|
| e2-standard-8 | 6-8 | ~$200 |
| e2-standard-16 | 10-12 | ~$400 |
| n2-standard-16 | 10-12 | ~$500 |
| n2-highmem-16 | 10-12 | ~$600 |

**Save money:**
- Use spot/preemptible instances (60-70% off)
- Schedule shutdown during off-hours
- Use committed use discounts (40% off)

## License

MIT
