#!/bin/bash
# View logs from Claude Code agent containers

set -e

AGENT_ID=${1:-}
FOLLOW=${FOLLOW:-true}

show_usage() {
    echo "Usage: $0 [agent_id] [--no-follow]"
    echo ""
    echo "Examples:"
    echo "  $0           # View all agent logs"
    echo "  $0 3         # View logs for agent 3"
    echo "  $0 3 --no-follow  # View logs without following"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-follow)
            FOLLOW=false
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            AGENT_ID=$1
            shift
            ;;
    esac
done

# Build follow flag
FOLLOW_FLAG=""
if [ "$FOLLOW" = "true" ]; then
    FOLLOW_FLAG="-f"
fi

# Check if running locally or should run on VM
if [ -f /.dockerenv ] || [ -n "$SANDBOX_VM" ]; then
    # Running on the VM
    if [ -n "$AGENT_ID" ]; then
        # Single agent logs
        CONTAINER_NAME="claude-agent-${AGENT_ID}"
        if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            docker logs $FOLLOW_FLAG "$CONTAINER_NAME"
        elif docker ps --format '{{.Names}}' | grep -q "workspaces-agent-${AGENT_ID}"; then
            docker logs $FOLLOW_FLAG "workspaces-agent-${AGENT_ID}"
        else
            echo "Agent $AGENT_ID not found"
            exit 1
        fi
    else
        # All agent logs (using docker-compose)
        cd /workspaces
        if command -v docker-compose &> /dev/null; then
            docker-compose logs $FOLLOW_FLAG agent
        else
            docker compose logs $FOLLOW_FLAG agent
        fi
    fi
else
    # Running locally - execute on VM
    VM_NAME="${VM_NAME:-claude-sandbox}"
    VM_ZONE="${VM_ZONE:-us-central1-a}"

    CMD="/usr/local/bin/agent-logs.sh"
    if [ -n "$AGENT_ID" ]; then
        CMD="$CMD $AGENT_ID"
    fi

    echo "Executing on VM: $VM_NAME"
    gcloud compute ssh "$VM_NAME" \
        --zone="$VM_ZONE" \
        --tunnel-through-iap \
        --command="sudo -u sandbox $CMD"
fi
