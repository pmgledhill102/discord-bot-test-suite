#!/bin/bash
# Stop all Claude Code agents on the sandbox VM

set -e

# shellcheck disable=SC2034
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Stopping all Claude Code agents..."

# Check if running locally or should run on VM
if [ -f /.dockerenv ] || [ -n "$SANDBOX_VM" ]; then
    # Running on the VM or in container
    cd /workspaces

    if command -v docker-compose &> /dev/null; then
        docker-compose down
    else
        docker compose down
    fi

    echo "All agents stopped."
else
    # Running locally - execute on VM
    VM_NAME="${VM_NAME:-claude-sandbox}"
    VM_ZONE="${VM_ZONE:-us-central1-a}"

    echo "Executing on VM: $VM_NAME"
    gcloud compute ssh "$VM_NAME" \
        --zone="$VM_ZONE" \
        --tunnel-through-iap \
        --command="sudo -u sandbox /usr/local/bin/stop-agents.sh"
fi
