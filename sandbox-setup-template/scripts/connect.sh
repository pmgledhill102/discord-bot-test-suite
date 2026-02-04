#!/bin/bash
# Connect to the Claude sandbox VM via IAP tunnel

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Load terraform outputs if available
if [ -f "$PROJECT_DIR/terraform/terraform.tfstate" ]; then
    VM_NAME=$(cd "$PROJECT_DIR/terraform" && terraform output -raw vm_name 2>/dev/null || echo "")
    VM_ZONE=$(cd "$PROJECT_DIR/terraform" && terraform output -raw vm_zone 2>/dev/null || echo "")
fi

# Allow override via environment
VM_NAME="${VM_NAME:-claude-sandbox}"
VM_ZONE="${VM_ZONE:-us-central1-a}"
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"

echo "Connecting to $VM_NAME in $VM_ZONE..."

# Use IAP tunnel (more secure, no external IP needed)
gcloud compute ssh "$VM_NAME" \
    --zone="$VM_ZONE" \
    --project="$PROJECT_ID" \
    --tunnel-through-iap \
    "$@"
