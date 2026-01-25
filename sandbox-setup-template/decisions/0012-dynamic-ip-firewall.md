# ADR-0012: Dynamic IP-Based Firewall Rules

## Status

Accepted

## Context

The sandbox VM runs with SSH accessible from the internet. Even with key-based authentication, exposing SSH to all IPs increases attack surface:
- Brute force attempts
- Exploitation of SSH vulnerabilities
- Port scanning noise

Most developers work from a small number of IP addresses (home, office, coffee shop). Restricting SSH access to only the current IP significantly reduces exposure.

However, IPs change:
- Home ISPs often use dynamic IPs
- Moving between networks (home → office → mobile)
- VPN connections

The firewall rules need to be updated when the IP changes.

## Decision

The TUI automatically detects the user's public IP on startup and updates GCP firewall rules to allow SSH only from that IP.

## Implementation

### IP Detection

```go
// internal/network/ip.go
package network

import (
    "context"
    "io"
    "net/http"
    "strings"
    "time"
)

var ipServices = []string{
    "https://api.ipify.org",
    "https://ifconfig.me/ip",
    "https://icanhazip.com",
    "https://checkip.amazonaws.com",
}

func GetPublicIP(ctx context.Context) (string, error) {
    client := &http.Client{Timeout: 5 * time.Second}

    for _, service := range ipServices {
        req, err := http.NewRequestWithContext(ctx, "GET", service, nil)
        if err != nil {
            continue
        }

        resp, err := client.Do(req)
        if err != nil {
            continue
        }
        defer resp.Body.Close()

        if resp.StatusCode == http.StatusOK {
            body, err := io.ReadAll(resp.Body)
            if err != nil {
                continue
            }
            ip := strings.TrimSpace(string(body))
            if isValidIP(ip) {
                return ip, nil
            }
        }
    }

    return "", fmt.Errorf("failed to detect public IP from any service")
}

func isValidIP(ip string) bool {
    return net.ParseIP(ip) != nil
}
```

### Firewall Rule Management

```go
// internal/cloud/gcp/firewall.go
package gcp

import (
    "context"
    "fmt"

    compute "cloud.google.com/go/compute/apiv1"
    computepb "cloud.google.com/go/compute/apiv1/computepb"
    "google.golang.org/protobuf/proto"
)

const firewallRuleName = "sandbox-ssh-allow"

func (p *GCPProvider) UpdateSSHAllowedIP(ctx context.Context, ip string) error {
    client, err := compute.NewFirewallsRESTClient(ctx)
    if err != nil {
        return fmt.Errorf("create firewall client: %w", err)
    }
    defer client.Close()

    cidr := fmt.Sprintf("%s/32", ip)  // Single IP as /32

    // Try to get existing rule
    rule, err := client.Get(ctx, &computepb.GetFirewallRequest{
        Project:  p.project,
        Firewall: firewallRuleName,
    })

    if err != nil {
        // Rule doesn't exist, create it
        return p.createSSHFirewallRule(ctx, client, cidr)
    }

    // Check if IP already matches
    if len(rule.SourceRanges) == 1 && rule.SourceRanges[0] == cidr {
        return nil  // Already up to date
    }

    // Update existing rule
    rule.SourceRanges = []string{cidr}

    op, err := client.Update(ctx, &computepb.UpdateFirewallRequest{
        Project:          p.project,
        Firewall:         firewallRuleName,
        FirewallResource: rule,
    })
    if err != nil {
        return fmt.Errorf("update firewall rule: %w", err)
    }

    return p.waitForOperation(ctx, op)
}

func (p *GCPProvider) createSSHFirewallRule(ctx context.Context, client *compute.FirewallsClient, cidr string) error {
    rule := &computepb.Firewall{
        Name:        proto.String(firewallRuleName),
        Description: proto.String("Allow SSH from current IP - managed by Sandbox Manager"),
        Network:     proto.String(fmt.Sprintf("projects/%s/global/networks/default", p.project)),
        Direction:   proto.String("INGRESS"),
        Priority:    proto.Int32(1000),
        SourceRanges: []string{cidr},
        Allowed: []*computepb.Allowed{
            {
                IPProtocol: proto.String("tcp"),
                Ports:      []string{"22"},
            },
        },
        TargetTags: []string{"sandbox-vm"},  // Only VMs with this tag
    }

    op, err := client.Insert(ctx, &computepb.InsertFirewallRequest{
        Project:          p.project,
        FirewallResource: rule,
    })
    if err != nil {
        return fmt.Errorf("create firewall rule: %w", err)
    }

    return p.waitForOperation(ctx, op)
}

func (p *GCPProvider) GetCurrentAllowedIP(ctx context.Context) (string, error) {
    client, err := compute.NewFirewallsRESTClient(ctx)
    if err != nil {
        return "", err
    }
    defer client.Close()

    rule, err := client.Get(ctx, &computepb.GetFirewallRequest{
        Project:  p.project,
        Firewall: firewallRuleName,
    })
    if err != nil {
        return "", err
    }

    if len(rule.SourceRanges) > 0 {
        // Strip /32 suffix
        return strings.TrimSuffix(rule.SourceRanges[0], "/32"), nil
    }

    return "", nil
}
```

### TUI Integration

```go
// internal/tui/startup.go
package tui

func (m *Model) Init() tea.Cmd {
    return tea.Batch(
        m.checkAndUpdateIP,
        m.refreshVMStatus,
    )
}

func (m *Model) checkAndUpdateIP() tea.Msg {
    ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()

    // Get current public IP
    currentIP, err := network.GetPublicIP(ctx)
    if err != nil {
        return ipCheckMsg{err: fmt.Errorf("detect IP: %w", err)}
    }

    // Get IP currently allowed in firewall
    allowedIP, err := m.provider.GetCurrentAllowedIP(ctx)
    if err != nil {
        // Rule might not exist yet
        allowedIP = ""
    }

    // Update if different
    if currentIP != allowedIP {
        err = m.provider.UpdateSSHAllowedIP(ctx, currentIP)
        if err != nil {
            return ipCheckMsg{err: fmt.Errorf("update firewall: %w", err)}
        }
        return ipCheckMsg{
            currentIP:  currentIP,
            previousIP: allowedIP,
            updated:    true,
        }
    }

    return ipCheckMsg{
        currentIP: currentIP,
        updated:   false,
    }
}

type ipCheckMsg struct {
    currentIP  string
    previousIP string
    updated    bool
    err        error
}
```

### TUI Display

```
┌─────────────────────────────────────────────────────────────────┐
│  Sandbox Manager                                     v0.1.0     │
├─────────────────────────────────────────────────────────────────┤
│  Network Security                                               │
│  Your IP:     203.0.113.42                                     │
│  SSH Access:  ✓ Restricted to your IP only                     │
│  Firewall:    sandbox-ssh-allow (updated 2s ago)               │
│                                                                 │
│  VM Status                                                      │
│  ...                                                            │
└─────────────────────────────────────────────────────────────────┘
```

Or when IP changed:

```
┌─────────────────────────────────────────────────────────────────┐
│  ⚠ IP Address Changed                                           │
│  Previous: 198.51.100.10                                        │
│  Current:  203.0.113.42                                        │
│  Firewall rule updated automatically.                           │
└─────────────────────────────────────────────────────────────────┘
```

### VM Network Tag

Ensure VMs are created with the target tag:

```go
func (p *GCPProvider) CreateVM(ctx context.Context, config VMConfig) error {
    instance := &computepb.Instance{
        // ... other config ...
        Tags: &computepb.Tags{
            Items: []string{"sandbox-vm"},  // Matches firewall rule target
        },
    }
    // ...
}
```

### Required Permissions

Add to the service account:

```bash
# Firewall admin - create/update firewall rules
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/compute.securityAdmin"
```

Or more restrictive custom role:

```bash
gcloud iam roles create sandboxFirewallManager \
  --project=$PROJECT_ID \
  --title="Sandbox Firewall Manager" \
  --permissions="compute.firewalls.create,compute.firewalls.get,compute.firewalls.update,compute.firewalls.delete"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_EMAIL" \
  --role="projects/$PROJECT_ID/roles/sandboxFirewallManager"
```

## Configuration

```yaml
# ~/.config/sandbox-manager/config.yaml
network:
  # Enable dynamic IP firewall management
  dynamic_ip_firewall: true

  # Firewall rule name
  firewall_rule_name: sandbox-ssh-allow

  # Additional IPs to always allow (e.g., office static IP)
  additional_allowed_ips:
    - 192.0.2.100/32  # Office
    - 10.0.0.0/8      # VPN range

  # Disable IP restriction entirely (allow 0.0.0.0/0)
  allow_all_ips: false
```

## Edge Cases

### Multiple IPs (Additional Allowed)

For users with known static IPs (office, VPN), allow combining:

```go
func (p *GCPProvider) UpdateSSHAllowedIPs(ctx context.Context, dynamicIP string, additionalCIDRs []string) error {
    cidrs := []string{fmt.Sprintf("%s/32", dynamicIP)}
    cidrs = append(cidrs, additionalCIDRs...)

    rule.SourceRanges = cidrs
    // ...
}
```

### VPN Users

If user is on a VPN, their public IP is the VPN exit node. This still works - just update to VPN's IP.

For split-tunnel VPNs where only some traffic goes through VPN:
- SSH might go direct (home IP)
- Or through VPN (VPN IP)
- User should configure `additional_allowed_ips` with both

### IPv6

Some users may have IPv6. Handle both:

```go
func GetPublicIP(ctx context.Context) (string, string, error) {
    ipv4, _ := getIPv4(ctx)
    ipv6, _ := getIPv6(ctx)
    return ipv4, ipv6, nil
}

// Firewall rule with both
rule.SourceRanges = []string{
    fmt.Sprintf("%s/32", ipv4),
    fmt.Sprintf("%s/128", ipv6),  // IPv6 single host
}
```

### Startup Without Internet

If IP detection fails, warn but don't block:

```go
if err != nil {
    return ipCheckMsg{
        err:     err,
        warning: "Could not detect IP. Firewall rules unchanged. SSH may fail if IP has changed.",
    }
}
```

### Existing Firewall Rules

Don't clobber user's other firewall rules. Only manage the specific rule named `sandbox-ssh-allow`.

## Consequences

### Positive

- SSH only accessible from user's current IP
- Automatic updates when IP changes
- Significantly reduced attack surface
- No manual firewall management needed
- Audit log shows firewall changes

### Negative

- Requires `compute.securityAdmin` or custom role
- Small delay on TUI startup (IP detection + firewall update)
- If IP detection fails, may lose SSH access until fixed
- Slightly more complex setup

### Neutral

- IP detection uses external services (privacy consideration)
- Firewall rule visible in GCP console
- Can be disabled for users preferring static rules
