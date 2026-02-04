#!/usr/bin/env bash
#
# Helper script for managing the Pub/Sub emulator
#
# Usage:
#   ./scripts/pubsub-emulator.sh start   # Start emulator in background
#   ./scripts/pubsub-emulator.sh stop    # Stop emulator
#   ./scripts/pubsub-emulator.sh status  # Check emulator status
#   ./scripts/pubsub-emulator.sh logs    # View emulator logs
#   ./scripts/pubsub-emulator.sh env     # Print environment variables

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.pubsub.yml"

PUBSUB_HOST="localhost:8085"
PUBSUB_PROJECT="test-project"

case "${1:-help}" in
  start)
    echo "Starting Pub/Sub emulator..."
    docker-compose -f "$COMPOSE_FILE" up -d
    echo ""
    echo "Waiting for emulator to be ready..."
    for _ in {1..30}; do
      if curl -s "http://$PUBSUB_HOST" > /dev/null 2>&1; then
        echo "Pub/Sub emulator is ready!"
        echo ""
        echo "Set these environment variables:"
        echo "  export PUBSUB_EMULATOR_HOST=$PUBSUB_HOST"
        echo "  export GOOGLE_CLOUD_PROJECT=$PUBSUB_PROJECT"
        exit 0
      fi
      sleep 1
    done
    echo "ERROR: Emulator failed to start within 30 seconds"
    exit 1
    ;;

  stop)
    echo "Stopping Pub/Sub emulator..."
    docker-compose -f "$COMPOSE_FILE" down
    echo "Pub/Sub emulator stopped."
    ;;

  status)
    if docker-compose -f "$COMPOSE_FILE" ps | grep -q "Up"; then
      echo "Pub/Sub emulator is running"
      if curl -s "http://$PUBSUB_HOST" > /dev/null 2>&1; then
        echo "Health check: OK"
      else
        echo "Health check: FAILED (not responding)"
      fi
    else
      echo "Pub/Sub emulator is not running"
    fi
    ;;

  logs)
    docker-compose -f "$COMPOSE_FILE" logs -f
    ;;

  env)
    echo "export PUBSUB_EMULATOR_HOST=$PUBSUB_HOST"
    echo "export GOOGLE_CLOUD_PROJECT=$PUBSUB_PROJECT"
    ;;

  help|--help|-h|*)
    echo "Pub/Sub Emulator Management Script"
    echo ""
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  start   Start the Pub/Sub emulator in background"
    echo "  stop    Stop the Pub/Sub emulator"
    echo "  status  Check if emulator is running"
    echo "  logs    Follow emulator logs"
    echo "  env     Print environment variables to set"
    echo "  help    Show this help message"
    ;;
esac
