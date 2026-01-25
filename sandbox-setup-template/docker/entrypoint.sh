#!/bin/bash
set -e

# Claude Code Agent Entrypoint
# Handles initialization and starts the agent

echo "=== Claude Code Agent Container ==="
echo "Agent ID: ${AGENT_ID:-unset}"
echo "Workspace: ${WORKSPACE_DIR:-/workspaces}"
echo "==================================="

# Fetch API key from Secret Manager if not provided directly
if [ -z "$ANTHROPIC_API_KEY" ] && [ -n "$API_KEY_SECRET" ]; then
    echo "Fetching API key from Secret Manager..."
    export ANTHROPIC_API_KEY=$(gcloud secrets versions access latest --secret="$API_KEY_SECRET" 2>/dev/null || echo "")
    if [ -z "$ANTHROPIC_API_KEY" ]; then
        echo "WARNING: Could not fetch API key from Secret Manager"
    else
        echo "API key loaded from Secret Manager"
    fi
fi

# Validate API key is present
if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "ERROR: ANTHROPIC_API_KEY is not set"
    echo "Set it directly or provide API_KEY_SECRET for Secret Manager lookup"
    exit 1
fi

# Configure git if credentials are available
if [ -n "$GIT_USER_NAME" ]; then
    git config --global user.name "$GIT_USER_NAME"
fi
if [ -n "$GIT_USER_EMAIL" ]; then
    git config --global user.email "$GIT_USER_EMAIL"
fi

# Configure GitHub CLI if token is available
if [ -n "$GITHUB_TOKEN" ]; then
    echo "$GITHUB_TOKEN" | gh auth login --with-token 2>/dev/null || true
    echo "GitHub CLI authenticated"
fi

# Set up workspace
WORKSPACE="${WORKSPACE_DIR:-/workspaces}"
if [ -n "$REPO_URL" ] && [ ! -d "$WORKSPACE/.git" ]; then
    echo "Cloning repository: $REPO_URL"
    git clone "$REPO_URL" "$WORKSPACE" || true
fi

cd "$WORKSPACE"

# Apply custom Claude settings if provided
if [ -f "/config/claude-settings.json" ]; then
    cp /config/claude-settings.json /home/agent/.claude/settings.json
fi

# Log startup
echo "Starting Claude Code agent at $(date)"
echo "Working directory: $(pwd)"
echo "Node version: $(node --version)"
echo "Claude Code version: $(claude --version 2>/dev/null || echo 'unknown')"

# Execute the command
exec "$@"
