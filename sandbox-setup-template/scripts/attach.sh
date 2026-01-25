#!/bin/bash
# Attach to a specific Claude Code agent container

set -e

AGENT_ID=${1:-1}

if [ -z "$1" ]; then
    echo "Usage: $0 <agent_id>"
    echo "Example: $0 3  # Attach to agent 3"
    exit 1
fi

echo "Attaching to agent $AGENT_ID..."

# Check if running locally or should run on VM
if [ -f /.dockerenv ] || [ -n "$SANDBOX_VM" ]; then
    # Running on the VM
    CONTAINER_NAME="claude-agent-${AGENT_ID}"

    # Try different naming conventions
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        docker exec -it "$CONTAINER_NAME" /bin/bash
    elif docker ps --format '{{.Names}}' | grep -q "workspaces-agent-${AGENT_ID}"; then
        docker exec -it "workspaces-agent-${AGENT_ID}" /bin/bash
    else
        echo "Agent container not found. Available containers:"
        docker ps --format '{{.Names}}' | grep -E "(claude|agent)" || echo "  (none)"
        exit 1
    fi
else
    # Running locally - execute on VM
    VM_NAME="${VM_NAME:-claude-sandbox}"
    VM_ZONE="${VM_ZONE:-us-central1-a}"

    echo "Executing on VM: $VM_NAME"
    gcloud compute ssh "$VM_NAME" \
        --zone="$VM_ZONE" \
        --tunnel-through-iap \
        --command="sudo -u sandbox /usr/local/bin/agent-shell.sh $AGENT_ID"
fi
