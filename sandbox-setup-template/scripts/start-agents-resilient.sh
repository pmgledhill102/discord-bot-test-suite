#!/bin/bash
# start-agents-resilient.sh
# Starts Claude Code agents with automatic session resumption
#
# Features:
# - Auto-continues previous sessions if available
# - Names sessions for easy resumption after preemption
# - Periodically saves state to persistent storage
#
# Usage:
#   ./start-agents-resilient.sh [AGENT_COUNT] [MODE]
#   ./start-agents-resilient.sh 12 fresh     # Fresh sessions
#   ./start-agents-resilient.sh 12 continue  # Continue previous (default)
#   ./start-agents-resilient.sh 12 pick      # Interactive picker

AGENT_COUNT=${1:-12}
MODE=${2:-continue}
SESSION_NAME="claude-agents"
PERSIST_MOUNT="/mnt/persist"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

log_info "Starting $AGENT_COUNT Claude agents (mode: $MODE)"

# Kill existing session
tmux kill-session -t $SESSION_NAME 2>/dev/null || true

# Create new tmux session
tmux new-session -d -s $SESSION_NAME -n "agent-1"

# Create windows for each agent
for i in $(seq 2 $AGENT_COUNT); do
    tmux new-window -t $SESSION_NAME -n "agent-$i"
done

# Start Claude in each window based on mode
for i in $(seq 1 $AGENT_COUNT); do
    WORKSPACE="/workspaces/agent-$i"
    SESSION_ID="agent-$i-$(date +%Y%m%d)"

    case "$MODE" in
        fresh)
            # Start fresh session with a named ID for later resumption
            tmux send-keys -t $SESSION_NAME:agent-$i \
                "cd $WORKSPACE && claude --dangerously-skip-permissions" Enter
            # Rename the session after it starts
            sleep 2
            tmux send-keys -t $SESSION_NAME:agent-$i "/rename $SESSION_ID" Enter
            ;;
        continue)
            # Continue most recent session for this workspace
            tmux send-keys -t $SESSION_NAME:agent-$i \
                "cd $WORKSPACE && claude --continue --dangerously-skip-permissions 2>/dev/null || claude --dangerously-skip-permissions" Enter
            ;;
        pick)
            # Open interactive session picker
            tmux send-keys -t $SESSION_NAME:agent-$i \
                "cd $WORKSPACE && claude --resume" Enter
            ;;
        *)
            log_warn "Unknown mode: $MODE. Using 'continue'."
            tmux send-keys -t $SESSION_NAME:agent-$i \
                "cd $WORKSPACE && claude --continue --dangerously-skip-permissions 2>/dev/null || claude --dangerously-skip-permissions" Enter
            ;;
    esac
done

# Start background state saver (every 5 minutes)
log_info "Starting periodic state saver..."
(
    while true; do
        sleep 300  # 5 minutes
        if tmux has-session -t $SESSION_NAME 2>/dev/null; then
            # Quick state snapshot
            TIMESTAMP=$(date +%Y%m%d-%H%M%S)
            SNAPSHOT_DIR="$PERSIST_MOUNT/session-state/periodic-$TIMESTAMP"
            mkdir -p "$SNAPSHOT_DIR"

            # Save tmux state
            tmux list-windows -t $SESSION_NAME > "$SNAPSHOT_DIR/tmux-windows.txt" 2>/dev/null || true

            # Save which agents are active
            for j in $(seq 1 $AGENT_COUNT); do
                PANE_PID=$(tmux display-message -p -t $SESSION_NAME:agent-$j '#{pane_pid}' 2>/dev/null || echo "")
                if [ -n "$PANE_PID" ]; then
                    echo "agent-$j:active:$PANE_PID" >> "$SNAPSHOT_DIR/agent-status.txt"
                fi
            done

            # Keep only last 3 periodic snapshots
            ls -dt "$PERSIST_MOUNT/session-state"/periodic-* 2>/dev/null | tail -n +4 | xargs rm -rf 2>/dev/null || true
        else
            # Session gone, stop the saver
            break
        fi
    done
) &

STATE_SAVER_PID=$!
echo $STATE_SAVER_PID > /tmp/claude-state-saver.pid

log_info "Started $AGENT_COUNT agent sessions in tmux session '$SESSION_NAME'"
echo ""
echo "Commands:"
echo "  Attach to all:     tmux attach -t $SESSION_NAME"
echo "  Attach to agent N: tmux select-window -t $SESSION_NAME:agent-N && tmux attach -t $SESSION_NAME"
echo "  List windows:      tmux list-windows -t $SESSION_NAME"
echo "  Stop all:          tmux kill-session -t $SESSION_NAME"
echo ""
echo "After preemption:"
echo "  1. Instance auto-restarts (if configured)"
echo "  2. Run: ./start-agents-resilient.sh $AGENT_COUNT continue"
echo "  3. Agents resume with previous context"
echo ""
