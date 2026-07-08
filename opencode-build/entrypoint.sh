#!/bin/bash
#ddev-generated

# =============================================================================
# OpenCode DDEV Entrypoint
# =============================================================================

# --- 0. Ensure HOME directory is writable ---
if [ -d "$HOME" ] && [ ! -w "$HOME" ]; then
  sudo chown -R "$(id -u):$(id -g)" "$HOME"
fi

# --- 0a. Human token-usage forwarding config (Atlas extension — EARLY) ---
# The human-usage config MUST be written before the first `opencode` invocation
# by any user, which can happen while the entrypoint is still running (races
# against the self-update, plugin installation, daemon startup, etc.). Source
# the Multica env file early, write the config file, then continue; the daemon
# section below (step 4) re-sources the same file for its own needs.
# The config is regenerated on every start; clear any stale copy first so a
# disabled or reconfigured container never keeps forwarding from a previous run.
rm -f "$HOME/.config/atlas/human-usage.env" 2>/dev/null || true

PROJECT_MULTICA_ENV_FILE="/var/www/html/.ddev/.env.multica"
GLOBAL_MULTICA_ENV_FILE="$HOME/.env.multica"
if [ -s "$PROJECT_MULTICA_ENV_FILE" ]; then
  MULTICA_ENV_FILE="$PROJECT_MULTICA_ENV_FILE"
  MULTICA_ENV_SOURCE="per-project (.ddev/.env.multica)"
elif [ -s "$GLOBAL_MULTICA_ENV_FILE" ]; then
  MULTICA_ENV_FILE="$GLOBAL_MULTICA_ENV_FILE"
  MULTICA_ENV_SOURCE="global (~/.ddev/multica/.env.multica)"
else
  MULTICA_ENV_FILE=""
fi

# Subshell: the sourced Multica vars (tokens included) must NOT leak into the
# environment of the self-update/plugin/SSH steps below — only step 4 needs
# them, and it sources the file itself.
if [ -n "$MULTICA_ENV_FILE" ]; then
  (
    set -a
    # shellcheck disable=SC1090
    . "$MULTICA_ENV_FILE"
    set +a

    if [ -n "${MULTICA_TOKEN:-}" ] && [ -n "${ATLAS_HUMAN_USAGE_TOKEN:-}" ]; then
      if [ -n "${ATLAS_USAGE_ENDPOINT:-}${MULTICA_APP_URL:-}" ]; then
        MULTICA_DAEMON_DEVICE_NAME="ddev-${DDEV_SITENAME}-opencode"
        HUMAN_USAGE_ENDPOINT="${ATLAS_USAGE_ENDPOINT:-${MULTICA_APP_URL%/}/api/usage}"
        HUMAN_USAGE_CONFIG="$HOME/.config/atlas/human-usage.env"
        mkdir -p "$(dirname "$HUMAN_USAGE_CONFIG")"
        # Create with 600 BEFORE writing the token (no world-readable window).
        : > "$HUMAN_USAGE_CONFIG" && chmod 600 "$HUMAN_USAGE_CONFIG"
        cat > "$HUMAN_USAGE_CONFIG" <<EOF
ATLAS_HUMAN_USAGE_TOKEN=${ATLAS_HUMAN_USAGE_TOKEN}
ATLAS_USAGE_ENDPOINT=${HUMAN_USAGE_ENDPOINT}
MULTICA_DAEMON_DEVICE_NAME=${MULTICA_DAEMON_DEVICE_NAME}
ATLAS_USAGE_INTERVAL=${ATLAS_USAGE_INTERVAL:-10000}
EOF
        echo "[atlas] human token-usage forwarding enabled (early) -> ${HUMAN_USAGE_ENDPOINT%/}/v1/metrics"
      else
        echo "[atlas] human token-usage forwarding disabled (set ATLAS_USAGE_ENDPOINT or MULTICA_APP_URL)."
      fi
    elif [ -n "${MULTICA_TOKEN:-}" ]; then
      echo "[atlas] human token-usage forwarding disabled (no ATLAS_HUMAN_USAGE_TOKEN)."
    fi
  )
fi

# --- 0b. Self-update OpenCode (best effort) ---
# The image bakes whatever OpenCode version was latest at BUILD time, and
# Docker layer caching freezes that layer across rebuilds — so restarts keep
# serving a stale version. Refresh on every container start instead: a quick
# registry check, and a reinstall only when a newer version exists. Offline or
# npm failure keeps the baked version. Opt out with OPENCODE_AUTO_UPDATE=false
# in .ddev/.env.opencode.
if [ "${OPENCODE_AUTO_UPDATE:-true}" = "true" ]; then
  OC_REAL="$HOME/.npm-global/bin/opencode-real"
  OC_CURRENT=$("$OC_REAL" --version 2>/dev/null || echo "unknown")
  OC_LATEST=$(timeout 20 npm view opencode-ai version 2>/dev/null || echo "")
  if [ -n "$OC_LATEST" ] && ! printf '%s' "$OC_CURRENT" | grep -qF "$OC_LATEST"; then
    echo "[opencode] updating OpenCode $OC_CURRENT -> $OC_LATEST ..."
    if timeout 300 npm install -g "opencode-ai@$OC_LATEST" >/dev/null 2>&1; then
      # npm relinks ~/.npm-global/bin/opencode to the real CLI, clobbering the
      # usage wrapper — move the fresh binary to opencode-real and restore the
      # wrapper (pristine copy baked at /opt/opencode-defaults/).
      if ! head -c 512 "$HOME/.npm-global/bin/opencode" 2>/dev/null | grep -q 'ddev-generated'; then
        mv -f "$HOME/.npm-global/bin/opencode" "$OC_REAL"
        cp /opt/opencode-defaults/opencode-usage-wrapper.sh "$HOME/.npm-global/bin/opencode"
        chmod +x "$HOME/.npm-global/bin/opencode"
      fi
      echo "[opencode] OpenCode updated to $("$OC_REAL" --version 2>/dev/null || echo unknown)"
    else
      echo "[opencode] WARNING: update failed — keeping $OC_CURRENT"
    fi
  else
    echo "[opencode] OpenCode $OC_CURRENT is up to date (latest: ${OC_LATEST:-unreachable})"
  fi
fi

# --- 1. Build the container-global OpenCode config ---
# Config cascade — all levels are DEEP-MERGED, higher levels win key by key:
#   1. /opt/opencode-defaults/  basic defaults baked into the image, so the
#                               container works without the agents-sync add-on
#   2. /agents-data/            defaults synced from the agents repo (agents-sync)
#   3. /host-opencode-config/   user's config shared across all DDEV projects
#                               (${HOST_OPENCODE_DIR}/config on the host)
# A per-PROJECT opencode.json (project root) is merged on top of the global
# config natively by OpenCode and always has the highest priority — same
# merge semantics as the levels below it.
# Note: like OpenCode's own merge, objects merge recursively but arrays and
# scalars are replaced wholesale (e.g. an `instructions` array in a higher
# level fully replaces the lower one).
AGENTS_DATA="/agents-data"
OC_CONFIG="$HOME/.config/opencode"
mkdir -p "$OC_CONFIG"

for name in opencode.json opencode-notifier.json; do
  sources=()
  for src in "/opt/opencode-defaults/$name" "$AGENTS_DATA/$name" "/host-opencode-config/$name"; do
    if [ -s "$src" ] && jq -e 'type == "object"' "$src" >/dev/null 2>&1; then
      sources+=("$src")
    elif [ -s "$src" ]; then
      echo "[opencode] WARNING: $src is not a valid JSON object — skipped"
    fi
  done
  if [ "${#sources[@]}" -gt 0 ]; then
    # del: strip the DDEV update-tracking signature key from the baked default
    jq -s 'reduce .[] as $x ({}; . * $x) | del(."#ddev-generated")' "${sources[@]}" > "$OC_CONFIG/$name"
    echo "[opencode] $name <- merged: ${sources[*]}"
  fi
done

# Orchestrator: OpenCode only auto-loads ~/.config/opencode/AGENTS.md as its
# global rules file (it never reads CLAUDE.md from the config dir), so the
# synced orchestrator must be installed under that name. Host override wins.
if [ -s "/host-opencode-config/AGENTS.md" ]; then
  cp "/host-opencode-config/AGENTS.md" "$OC_CONFIG/AGENTS.md"
  echo "[opencode] AGENTS.md <- /host-opencode-config/AGENTS.md"
elif [ -s "$AGENTS_DATA/CLAUDE.md" ]; then
  cp "$AGENTS_DATA/CLAUDE.md" "$OC_CONFIG/AGENTS.md"
  echo "[opencode] AGENTS.md <- $AGENTS_DATA/CLAUDE.md"
fi

# --- 2. Set up SSH (keys generated by ddev-ai-ssh add-on) ---
SSH_KEY_DIR="/var/www/html/.ddev/.agent-ssh-keys"
mkdir -p ~/.ssh && chmod 700 ~/.ssh

# SSH client: copy private key for connecting to web/beads
cp "$SSH_KEY_DIR/id_ed25519" ~/.ssh/ddev_agent_key 2>/dev/null
chmod 600 ~/.ssh/ddev_agent_key 2>/dev/null

# Detect web container username (written by ai-ssh-setup.sh in the web container)
# Wait for the web container to write its username (max 15s)
for i in $(seq 1 15); do
  [ -f /var/www/html/.ddev/.agent-ssh-keys/web-user ] && break
  sleep 1
done
WEB_USER=$(cat /var/www/html/.ddev/.agent-ssh-keys/web-user 2>/dev/null || echo "ddev")
if ! sed -n '/^Host web$/,/^Host /p' ~/.ssh/config 2>/dev/null | grep -q "^    User "; then
  sed -i "/^Host web$/a\\    User $WEB_USER" ~/.ssh/config 2>/dev/null
fi

# SSH server: authorized_keys for Ralph to connect to this container
cp "$SSH_KEY_DIR/id_ed25519.pub" ~/.ssh/authorized_keys 2>/dev/null
chmod 600 ~/.ssh/authorized_keys 2>/dev/null

# Start sshd for Ralph access
env | grep -E '^(DDEV_|IS_DDEV_PROJECT|HOME=|PATH=|LANG|TZ=|PLAYWRIGHT_)' \
    | sed 's/^/export /' | sudo tee /etc/ddev-env > /dev/null
sudo chmod 644 /etc/ddev-env
sudo /usr/sbin/sshd 2>/dev/null || true

# --- 3. Install OpenCode plugins if not already installed ---
# Notifier: desktop notifications. OTEL: token-usage telemetry for the human
# forwarding feature (inert unless OPENCODE_ENABLE_TELEMETRY is set, which only
# the CLI wrapper does — for human sessions). Both are also registered in the
# `plugin` array of the merged opencode.json.
for _oc_plugin in "@mohak34/opencode-notifier" "@devtheops/opencode-plugin-otel"; do
  if [ ! -d "$HOME/.config/opencode/node_modules/$_oc_plugin" ]; then
    mkdir -p "$HOME/.config/opencode"
    (cd "$HOME/.config/opencode" && npm install --save "${_oc_plugin}@latest" 2>/dev/null) || true
  fi
done

# --- 3b. Trust the DDEV mkcert root CA ---
# The Multica daemon's Go HTTPS/WSS client must verify *.ddev.site
# certificates, otherwise `multica login` fails with x509 "certificate signed
# by unknown authority" and no runtime ever registers. The CA is mounted at
# runtime from the DDEV global cache (it does not exist at image build time),
# and the container trust store is reset on every rebuild, so this must run on
# each start — and BEFORE the Multica daemon authenticates below.
DDEV_ROOT_CA="/mnt/ddev-global-cache/mkcert/rootCA.pem"
if [ -f "$DDEV_ROOT_CA" ]; then
  sudo cp "$DDEV_ROOT_CA" /usr/local/share/ca-certificates/ddev-rootCA.crt
  sudo update-ca-certificates >/dev/null 2>&1 || true
fi

# --- 4. Multica daemon (optional) ---
# Activated only if a Multica env file with non-empty MULTICA_TOKEN is found.
# Resolution order (first match wins):
#   1. /var/www/html/.ddev/.env.multica   — per-project override
#   2. $HOME/.env.multica                  — global (~/.ddev/multica/.env.multica on host)
# The global file is mounted from the shared ~/.ddev/multica/ directory so
# one configuration enables the daemon in every Multica-aware addon.
# Watch list is managed automatically (`multica login` subscribes the daemon
# to all UI workspaces) — the user controls it from the Multica panel.
#
# NOTE: The human-usage forwarding config was already written above (step 0a).
# This section only handles daemon startup — do NOT write the config again.
if [ -n "$MULTICA_ENV_FILE" ] && command -v multica >/dev/null 2>&1; then
  echo "[multica] config source: $MULTICA_ENV_SOURCE"
  # Step 0a sourced this file in a subshell only — the daemon needs the vars
  # in THIS shell, so source it here.
  set -a
  # shellcheck disable=SC1090
  . "$MULTICA_ENV_FILE"
  set +a

  if [ -z "${MULTICA_TOKEN:-}" ]; then
    echo "[multica] $MULTICA_ENV_FILE has no MULTICA_TOKEN — daemon disabled."
  elif [ -z "${MULTICA_SERVER_URL:-}" ] || [ -z "${MULTICA_APP_URL:-}" ]; then
    echo "[multica] MULTICA_SERVER_URL or MULTICA_APP_URL missing — daemon disabled."
  else
    # Identity for this runtime in the Multica UI (always tied to the DDEV
    # project name so the user can tell runtimes apart at a glance).
    export MULTICA_DAEMON_DEVICE_NAME="ddev-${DDEV_SITENAME}-opencode"
    export MULTICA_AGENT_RUNTIME_NAME="OpenCode DDEV (${DDEV_SITENAME})"

    echo "[multica] starting daemon as '$MULTICA_AGENT_RUNTIME_NAME'..."
    multica config set server_url "$MULTICA_SERVER_URL" >/dev/null 2>&1 || true
    multica config set app_url    "$MULTICA_APP_URL"    >/dev/null 2>&1 || true

    # Non-interactive login. `--token=` (empty) reads from stdin so the
    # token never lands in shell history; fall back to flag form if the
    # CLI version doesn't support the stdin shortcut.
    printf '%s\n' "$MULTICA_TOKEN" | multica login --token= >/dev/null 2>&1 || \
      multica login --token="$MULTICA_TOKEN" >/dev/null 2>&1 || \
      echo "[multica] login failed — check token validity."

    multica daemon stop >/dev/null 2>&1 || true
    if multica daemon start >/dev/null 2>&1; then
      echo "[multica] daemon running (logs: $HOME/.multica/daemon.log)"
    else
      echo "[multica] WARNING: daemon failed to start — see $HOME/.multica/daemon.log"
    fi
  fi
else
  echo "[multica] disabled (no per-project or global .env.multica with content)."
fi

exec "$@"
