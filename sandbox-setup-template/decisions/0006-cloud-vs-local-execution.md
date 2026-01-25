# ADR-0006: Cloud vs Local Execution Environment

## Status

Accepted

## Context

Claude Code agents need to run with safety guardrails disabled (`--dangerously-skip-permissions`) to work autonomously on development tasks. This flag allows agents to execute arbitrary commands, modify files, and run code without manual approval prompts.

The agents also need Docker access to:
- Build container images for services under development
- Run containers locally for testing
- Push images to container registries
- Deploy to Cloud Run for integration testing

This creates a security challenge: how do we provide autonomous execution capability while limiting blast radius if something goes wrong?

The development machine is a MacBook Air used for personal and professional work.

## Decision

Run Claude Code agents on a dedicated GCP Compute Engine VM rather than locally on the development machine.

Use GCP IAM service accounts with least-privilege permissions to control what cloud resources agents can access.

## Options Considered

### Option 1: Local Execution on MacBook

Run agents directly on the development machine with restricted user accounts.

**Pros:**
- No cloud costs
- Lower latency (no network hop)
- Simpler setup (no VM management)
- Works offline

**Cons:**
- Docker daemon runs as root with system-wide privileges
- Even with restricted user accounts, Docker socket access grants effective root
- Risk to personal data and credentials on the machine
- Difficult to truly isolate agents from sensitive files (~/.ssh, ~/.aws, browser data)
- No cloud IAM integration - agents would need personal credentials
- Machine resources shared with other work

### Option 2: Local Virtual Machine (Parallels/UTM)

Run agents inside a VM on the MacBook.

**Pros:**
- Better isolation than bare metal
- No cloud costs
- Works offline
- Full control over VM environment

**Cons:**
- Significant resource overhead on laptop (RAM, CPU, battery)
- Still no cloud IAM integration - need to manage credentials in VM
- VM has broad network access unless manually restricted
- Docker-in-VM performance penalty
- Managing VM snapshots and state adds complexity
- MacBook Air thermal constraints for sustained workloads

### Option 3: Cloud VM with Service Account (Chosen)

Run agents on a GCP Compute Engine VM with a dedicated service account.

**Pros:**
- **Complete isolation from personal machine** - no risk to local data
- **Docker runs in isolated environment** - elevated privileges contained to VM
- **Native IAM integration** - service account with least-privilege permissions
- **No credentials on VM** - uses instance metadata for authentication
- **Auditable** - all API calls logged with service account identity
- **Scalable resources** - 16 vCPUs vs laptop's limited cores
- **Disposable** - can delete and recreate VM without risk
- **Network isolation** - firewall rules control egress

**Cons:**
- Cloud costs (~$5/month stopped, ~$85/month spot when running)
- Requires internet connectivity
- Slight latency for SSH/remote access
- Need to manage VM lifecycle

### Option 4: Cloud-based Development Environments (Codespaces/Cloud Workstations)

Use managed cloud development environments.

**Pros:**
- Managed infrastructure
- Good IDE integration
- Built-in security controls

**Cons:**
- Higher cost than raw VM
- Less control over environment
- May have restrictions on long-running processes
- Not optimized for running multiple autonomous agents

## Security Analysis

### Docker Daemon Risk

The Docker daemon (`dockerd`) runs as root and provides:
- Ability to mount any host filesystem path into containers
- Ability to run privileged containers with full host access
- Access to host network namespace
- Ability to load kernel modules (with --privileged)

**On local machine:** Any process with Docker socket access can effectively become root. Restricting user accounts is insufficient - Docker socket access bypasses these restrictions.

**On cloud VM:** Docker's elevated privileges are contained within the VM. The VM itself has limited permissions via its service account. Even if an agent compromises the VM completely, it cannot:
- Access personal files (they're not on the VM)
- Use personal cloud credentials (VM uses service account)
- Exceed service account IAM permissions
- Access other cloud resources not explicitly granted

### Service Account Least-Privilege

The VM's service account can be scoped to only:
- Push/pull from specific Artifact Registry repositories
- Deploy to specific Cloud Run services
- Read/write specific GCS buckets
- Access specific Pub/Sub topics

Example minimal permissions for this project:
```
roles/artifactregistry.writer  (scoped to project)
roles/run.developer            (scoped to specific services)
roles/pubsub.publisher         (scoped to specific topics)
roles/logging.logWriter        (for observability)
```

### Audit Trail

All GCP API calls made by the service account are logged in Cloud Audit Logs, providing:
- What action was attempted
- When it occurred
- Whether it succeeded or was denied
- Which service account made the request

This audit trail doesn't exist for local Docker/CLI operations.

## Consequences

### Positive

- Personal machine remains clean and secure
- Docker's elevated privileges are sandboxed to disposable VM
- Fine-grained IAM controls what cloud resources agents can touch
- Complete audit trail of all cloud API operations
- Can run 12 agents with 16 vCPUs without laptop thermal throttling
- Easy to add/remove permissions as project needs change
- Can delete entire VM if compromised, recreate in minutes

### Negative

- Monthly cloud costs (mitigated by spot instances and stop when idle)
- Requires internet connectivity to work
- Additional complexity of VM management
- SSH latency for interactive work (mitigated by tmux persistence)

### Neutral

- Development workflow shifts to remote-first
- Need to sync code via git (good practice anyway)
- Local machine becomes thin client for SSH access
