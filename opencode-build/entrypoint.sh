#!/bin/bash

# =============================================================================
# OpenCode DDEV Entrypoint
# =============================================================================

# --- 1. Fix Docker socket access if needed ---
# On Linux, the socket GID may not match the container's docker group.
# On macOS/Windows Docker Desktop, the socket is already accessible — this is skipped.
if [ -z "$_DOCKER_GROUP_FIXED" ] && [ -S /var/run/docker.sock ] && ! docker info > /dev/null 2>&1; then
  SOCK_GID=$(stat -c '%g' /var/run/docker.sock)
  if [ -n "$SOCK_GID" ] && [ "$SOCK_GID" != "0" ]; then
    sudo groupadd -g "$SOCK_GID" docker-host 2>/dev/null || true
    sudo usermod -aG docker-host "$(whoami)" 2>/dev/null || true
    export _DOCKER_GROUP_FIXED=1
    exec sg docker-host -c "$0 $*"
  fi
fi

# --- 2. Set up config from synced agents volume ---
if [ -d "/agents-opencode" ]; then
  mkdir -p "$HOME/.config/opencode"

  # Always symlink agent/rules/skills from synced volume to OpenCode config dir
  for d in /agents-opencode/agent /agents-opencode/rules /agents-opencode/skills; do
    [ -d "$d" ] && ln -sfn "$d" "$HOME/.config/opencode/"
  done

  # Also symlink to .claude/ path for cross-tool compatibility
  mkdir -p /var/www/html/.claude
  [ -d "/agents-opencode/skills" ] && ln -sfn /agents-opencode/skills /var/www/html/.claude/skills
  [ -d "/agents-opencode/rules" ] && ln -sfn /agents-opencode/rules /var/www/html/.claude/rules

  # Symlink CLAUDE.md from synced volume
  [ -f "/agents-opencode/CLAUDE.md" ] && ln -sf "/agents-opencode/CLAUDE.md" "$HOME/.config/opencode/"

  # Symlink config files from synced volume if user has no custom ones
  for f in /agents-opencode/*.json; do
    [ -f "$f" ] && [ ! -f "$HOME/.config/opencode/$(basename "$f")" ] && ln -sf "$f" "$HOME/.config/opencode/"
  done
fi

exec "$@"
