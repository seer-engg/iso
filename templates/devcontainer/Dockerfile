# Multi-stage Dockerfile for Seer unified devcontainer
# Includes: Python 3.12, Node 20, uv, Bun, development tools

FROM mcr.microsoft.com/devcontainers/python:3.12-bookworm

# Remove Yarn repository (expired GPG key)
RUN rm -f /etc/apt/sources.list.d/yarn.list

# Install Node.js 20
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs

# Install system dependencies
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive && \
    apt-get install -y \
    git \
    curl \
    wget \
    zsh \
    fzf \
    postgresql-client \
    redis-tools \
    netcat-openbsd \
    build-essential \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install uv (Python package manager)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh && \
    mv /root/.local/bin/uv /usr/local/bin/ && \
    mv /root/.local/bin/uvx /usr/local/bin/

# Install Bun (JavaScript runtime)
RUN curl -fsSL https://bun.sh/install | bash && \
    mv /root/.bun/bin/bun /usr/local/bin/

# Install Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# Copy dependency installation script
COPY init-deps.sh /usr/local/bin/init-deps.sh
RUN chmod +x /usr/local/bin/init-deps.sh

# Ensure vscode user home directory and .vscode-server have correct permissions
RUN mkdir -p /home/vscode/.vscode-server /home/vscode/.local/bin \
    && chown -R vscode:vscode /home/vscode

# Set up vscode user
USER vscode

# Set workspace
WORKDIR /workspace

# Environment variables
ENV UV_LINK_MODE=copy \
    PATH="/home/vscode/.local/bin:$PATH"

# Default command
CMD ["sleep", "infinity"]
