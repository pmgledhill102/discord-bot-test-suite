# Claude Code Agent Container
# Extends the base image with Claude Code and agent-specific configuration

ARG BASE_IMAGE=claude-sandbox-base:latest
FROM ${BASE_IMAGE}

LABEL description="Claude Code agent container for sandbox execution"

USER root

# Install Claude Code globally via npm
RUN npm install -g @anthropic-ai/claude-code

# Create agent-specific directories
RUN mkdir -p /home/agent/.claude \
    && mkdir -p /home/agent/.config \
    && chown -R agent:agent /home/agent

# Copy default Claude Code settings
COPY --chown=agent:agent config/claude-settings.json /home/agent/.claude/settings.json

# Copy entrypoint script
COPY --chown=agent:agent entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Switch to agent user
USER agent
WORKDIR /workspaces

# Environment variables
ENV CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
ENV CLAUDE_CODE_SKIP_PERMISSIONS_CHECK=1

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD pgrep -f "claude" || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["claude", "--help"]
