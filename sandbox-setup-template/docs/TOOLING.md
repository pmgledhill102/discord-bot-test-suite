# Complete Tooling Reference

This document lists all tools pre-installed on the Claude Sandbox VM by the provisioning script.

## Sources

The tooling list is based on:
1. **Anthropic's official devcontainer** - [github.com/anthropics/claude-code/.devcontainer](https://github.com/anthropics/claude-code/tree/main/.devcontainer)
2. **Docker's Claude Code sandbox template** - [docker/sandbox-templates:claude-code](https://docs.docker.com/ai/sandboxes/claude-code/)
3. **Additional tools** commonly needed for full-stack development

---

## Core Tools (from Anthropic Devcontainer)

These tools are installed in Anthropic's official development container:

| Tool | Version | Purpose |
|------|---------|---------|
| Node.js | 20 LTS | Claude Code runtime |
| npm | bundled | Node package manager |
| git | latest | Version control |
| gh | latest | GitHub CLI |
| jq | latest | JSON processor |
| fzf | latest | Fuzzy finder |
| ripgrep (rg) | latest | Fast code search |
| git-delta | 0.18.2 | Syntax-highlighted git diffs |
| zsh | latest | Shell |
| oh-my-zsh | latest | ZSH framework |
| less | latest | Pager |
| procps | latest | Process utilities |
| sudo | latest | Privilege escalation |
| man-db | latest | Manual pages |
| unzip/zip | latest | Archive utilities |
| gnupg2 | latest | GPG encryption |
| nano/vim | latest | Text editors |
| iptables/ipset | latest | Firewall (if needed) |
| iproute2 | latest | Network utilities |
| dnsutils | latest | DNS tools |

---

## Language Runtimes

| Runtime | Version | Package Managers | Linters/Formatters |
|---------|---------|------------------|-------------------|
| **Node.js** | 20 LTS | npm, yarn, pnpm | eslint, prettier |
| **Python** | 3.11+ | pip, pipx, poetry, uv | black, ruff, mypy |
| **Go** | 1.22+ | go modules | golangci-lint |
| **Rust** | stable | cargo, rustup | clippy, rustfmt |
| **Java** | 21 (Temurin) | Maven, Gradle | - |
| **Ruby** | 3.3+ | bundler, gem | rubocop |
| **PHP** | 8.3+ | composer | - |
| **.NET** | 8.0 | dotnet CLI | - |

### Node.js Global Packages
```
@anthropic-ai/claude-code
yarn
pnpm
typescript
ts-node
eslint
prettier
```

### Python Packages (pip)
```
pipx
poetry
uv
black
ruff
mypy
pytest
pre-commit
httpie
semgrep
```

### Go Tools
```
golangci-lint
delve (dlv)
grpcurl
```

### Rust Components
```
clippy
rustfmt
```

---

## Container & Cloud Tools

| Tool | Purpose |
|------|---------|
| docker | Container runtime |
| docker-compose | Multi-container orchestration |
| docker-buildx | Extended build capabilities |
| gcloud | Google Cloud CLI |
| gsutil | Cloud Storage CLI |
| bq | BigQuery CLI |
| kubectl | Kubernetes CLI |
| helm | Kubernetes package manager |
| k9s | Kubernetes TUI |

---

## Database Clients

| Client | Database |
|--------|----------|
| psql | PostgreSQL |
| mysql | MySQL/MariaDB |
| redis-cli | Redis |
| mongosh | MongoDB |

---

## HTTP & API Tools

| Tool | Purpose |
|------|---------|
| curl | HTTP client |
| wget | Download utility |
| httpie | Modern HTTP client |
| grpcurl | gRPC client |

---

## Text & Data Processing

| Tool | Purpose |
|------|---------|
| jq | JSON processor |
| yq | YAML processor |
| ripgrep (rg) | Fast search |
| fzf | Fuzzy finder |
| git-delta | Diff viewer |

---

## Editors

| Editor | Notes |
|--------|-------|
| vim | Classic |
| nano | Simple |
| micro | Modern terminal editor |

---

## Monitoring & System Tools

| Tool | Purpose |
|------|---------|
| htop | Interactive process viewer |
| btop | Resource monitor |
| ncdu | Disk usage analyzer |
| tmux | Terminal multiplexer |
| screen | Terminal multiplexer |

---

## Security & Scanning

| Tool | Purpose |
|------|---------|
| trivy | Container/filesystem scanner |
| semgrep | Static analysis |
| pre-commit | Git hooks framework |

---

## Version Reference

Update these versions in `scripts/provision-vm.sh`:

```bash
NODE_VERSION="20"
GO_VERSION="1.22.5"
PYTHON_VERSION="3.11"
RUST_VERSION="stable"
JAVA_VERSION="21"
RUBY_VERSION="3.3"
PHP_VERSION="8.3"
DOTNET_VERSION="8.0"
DELTA_VERSION="0.18.2"
```

---

## Verification Commands

After provisioning, verify installations:

```bash
# Core
node --version
git --version
gh --version
rg --version
delta --version

# Languages
python3 --version
go version
rustc --version
java --version
ruby --version
php --version
dotnet --version

# Cloud/Containers
docker --version
gcloud version
kubectl version --client

# Claude Code
claude --version
```

---

## Adding Custom Tools

To add tools for your specific projects, either:

1. **Modify `provision-vm.sh`** before creating the VM
2. **Use Packer** to bake a custom VM image with additional tools
3. **Install at runtime** via the sandbox user

Example adding a tool at runtime:
```bash
sudo su - sandbox
npm install -g some-tool
pip install some-package
go install github.com/some/tool@latest
```
