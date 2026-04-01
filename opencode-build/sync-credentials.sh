#!/bin/bash
#ddev-generated

# =============================================================================
# Sync Claude Code OAuth credentials to OpenCode auth.json
# =============================================================================
# Runs in background, checks every 60 seconds if Claude Code credentials
# have changed and updates OpenCode's auth.json accordingly.
#
# Claude Code stores:  ~/.claude-credentials/.credentials.json
# OpenCode reads:      ~/.local/share/opencode/auth.json
# =============================================================================

CLAUDE_CREDS="/home/opencode/.claude-credentials/.credentials.json"
OPENCODE_AUTH="/home/opencode/.local/share/opencode/auth.json"
INTERVAL=60
LAST_HASH=""

log() { echo "[credentials-sync] $*"; }

sync_credentials() {
  # Read Claude Code OAuth values
  local access refresh expires
  access=$(jq -r '.claudeAiOauth.accessToken // empty' "$CLAUDE_CREDS" 2>/dev/null)
  refresh=$(jq -r '.claudeAiOauth.refreshToken // empty' "$CLAUDE_CREDS" 2>/dev/null)
  expires=$(jq -r '.claudeAiOauth.expiresAt // 0' "$CLAUDE_CREDS" 2>/dev/null)

  if [ -z "$access" ] || [ -z "$refresh" ]; then
    return 1
  fi

  # Update or create auth.json with the anthropic OAuth section
  if [ -f "$OPENCODE_AUTH" ]; then
    # Update existing file — preserve other providers (litellm, etc.)
    jq --arg a "$access" --arg r "$refresh" --argjson e "$expires" \
      '.anthropic = {"type": "oauth", "access": $a, "refresh": $r, "expires": $e}' \
      "$OPENCODE_AUTH" > "${OPENCODE_AUTH}.tmp" \
      && mv "${OPENCODE_AUTH}.tmp" "$OPENCODE_AUTH"
  else
    # Create new file
    mkdir -p "$(dirname "$OPENCODE_AUTH")"
    jq -n --arg a "$access" --arg r "$refresh" --argjson e "$expires" \
      '{"anthropic": {"type": "oauth", "access": $a, "refresh": $r, "expires": $e}}' \
      > "$OPENCODE_AUTH"
  fi
}

main() {
  log "Starting (checking every ${INTERVAL}s)"

  while true; do
    if [ -f "$CLAUDE_CREDS" ]; then
      # Hash the 3 relevant fields to detect changes
      current_hash=$(jq -r '[.claudeAiOauth.accessToken, .claudeAiOauth.refreshToken, .claudeAiOauth.expiresAt] | join(",")' "$CLAUDE_CREDS" 2>/dev/null | md5sum | cut -d' ' -f1)

      if [ "$current_hash" != "$LAST_HASH" ]; then
        if sync_credentials; then
          LAST_HASH="$current_hash"
          log "Credentials synced from Claude Code"
        fi
      fi
    fi

    sleep "$INTERVAL"
  done
}

main
