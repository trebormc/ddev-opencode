#!/bin/bash

# Set up config from synced agents volume
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
