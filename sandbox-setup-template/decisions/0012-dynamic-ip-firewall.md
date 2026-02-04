# ADR-0012: Dynamic IP-Based Firewall Rules

## Status

Accepted

## Context

The sandbox VM exposes SSH to the internet. Even with key-based authentication,
restricting access to known IPs significantly reduces attack surface.

Most developers work from dynamic IPs (home ISP, mobile hotspot) that change periodically.
Manual firewall management creates friction.

## Decision

The TUI can optionally manage a firewall rule that restricts SSH access to the user's current IP address.

**Modes:**

| Mode       | Behavior                                          |
| ---------- | ------------------------------------------------- |
| `auto`     | Detect public IP on startup, update firewall rule |
| `manual`   | User specifies IP/CIDR in config, TUI applies it  |
| `disabled` | No firewall management, user handles manually     |

Default: `disabled` (opt-in feature)

## Configuration

```yaml
# ~/.config/sandbox-manager/config.yaml
network:
  ip_allowlist:
    mode: auto # auto | manual | disabled

    # For mode: manual
    allowed_ranges:
      - 203.0.113.0/24 # Home ISP range
      - 198.51.100.50/32 # Office static IP
```

## Required Permissions

Minimal custom role (not full `compute.securityAdmin`):

```bash
gcloud iam roles create sandboxFirewallManager \
  --project=$PROJECT_ID \
  --title="Sandbox Firewall Manager" \
  --permissions="\
compute.firewalls.get,\
compute.firewalls.create,\
compute.firewalls.update"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_EMAIL" \
  --role="projects/$PROJECT_ID/roles/sandboxFirewallManager"
```

This grants permission to manage firewall rules only - not security policies, SSL certificates,
or other security resources that `compute.securityAdmin` includes.

## Consequences

### Positive

- SSH only accessible from specified IPs when enabled
- Automatic or manual - user's choice
- Minimal permissions required
- Disabled by default - no surprise behavior

### Negative

- Requires custom IAM role setup
- If enabled and IP detection fails, SSH access may break

### Neutral

- Feature is opt-in
- Users comfortable with manual firewall management can ignore this entirely
