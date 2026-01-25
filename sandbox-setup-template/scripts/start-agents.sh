#!/bin/bash
# Start Claude Code agents on the sandbox VM

set -e

AGENT_COUNT=${1:-12}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Starting $AGENT_COUNT Claude Code agents..."

# Check if running locally or should run on VM
if [ -f /.dockerenv ] || [ -n "$SANDBOX_VM" ]; then
    # Running on the VM or in container
    cd /workspaces

    # Export agent count for docker-compose
    export AGENT_COUNT

    # Start containers
    if command -v docker-compose &> /dev/null; then
        docker-compose up -d --scale agent=$AGENT_COUNT
    else
        docker compose up -d --scale agent=$AGENT_COUNT
    fi

    echo "Agents started. Use 'docker ps' to see running containers."
else
    # Running locally - execute on VM
    VM_NAME="${VM_NAME:-claude-sandbox}"
    VM_ZONE="${VM_ZONE:-us-central1-a}"

    echo "Executing on VM: $VM_NAME"
    gcloud compute ssh "$VM_NAME" \
        --zone="$VM_ZONE" \
        --tunnel-through-iap \
        --command="sudo -u sandbox AGENT_COUNT=$AGENT_COUNT /usr/local/bin/start-agents.sh"
fi
