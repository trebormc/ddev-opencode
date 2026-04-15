#!/bin/bash
#ddev-generated

# =============================================================================
# OpenCode DDEV Entrypoint
# =============================================================================

# --- 0. Ensure HOME directory is writable ---
# When docker-compose overrides user UID/GID, /home/opencode may be owned by
# the build-time UID (1000). Fix ownership so the runtime user can write there.
if [ -d "$HOME" ] && [ ! -w "$HOME" ]; then
  sudo chown -R "$(id -u):$(id -g)" "$HOME"
fi

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

# --- 2. Install notifier plugin if not already installed ---
# Agents, skills, rules, CLAUDE.md, and config files are mounted directly
# via docker-compose volume subpaths — no symlinks needed.
if [ ! -d "$HOME/.config/opencode/node_modules/@mohak34/opencode-notifier" ]; then
  mkdir -p "$HOME/.config/opencode"
  cd "$HOME/.config/opencode"
  npm install --save @mohak34/opencode-notifier@latest 2>/dev/null || true
  cd /var/www/html
fi

exec "$@"
