#!/bin/bash
#ddev-generated
# =============================================================================
# Transparent `opencode` wrapper — human token-usage telemetry
# =============================================================================
# For HUMAN interactive sessions only, this points the OpenCode OTEL plugin
# (@devtheops/opencode-plugin-otel) at the Atlas human-usage endpoint, so the
# tokens a person spends working directly in this container are attributed to
# the SAME runtime the Multica daemon already registers (matched by device.name).
#
# Daemon-spawned invocations are detected and left untouched: the daemon reports
# its own usage via its API, so forwarding here would double-count. The plugin
# is inert unless OPENCODE_ENABLE_TELEMETRY is set, and only this wrapper sets
# it (for a human session), so a daemon CLI never forwards even if it bypasses
# the wrapper.
#
# The wrapper is fully transparent: it always exec's the real binary with the
# original arguments (including `opencode --version` probes). It only exports
# telemetry env when ALL of these hold:
#   * the human-usage channel is configured (config file written by entrypoint),
#   * this invocation is NOT a Multica daemon child (origin detection below).
# Any uncertainty falls back to "do not forward" to protect against double
# counting.

REAL="$HOME/.npm-global/bin/opencode-real"
CONFIG="$HOME/.config/atlas/human-usage.env"

# ---- origin detection: is an ancestor the Multica daemon? --------------------
# Returns 0 (true) for a daemon-spawned invocation, 1 for a human one. On any
# uncertainty it returns 0 (treat as daemon => do not forward).
_atlas_is_daemon_invocation() {
  # Secondary signal: the daemon injects a per-task token into the CLI it
  # spawns. Harmless if absent — process ancestry below is the primary signal.
  [ -n "${MULTICA_TASK_TOKEN:-}" ] && return 0

  # Primary signal: walk the process tree. A daemon-run CLI descends from the
  # `multica` daemon; a human one from an interactive shell / docker exec.
  local pid="$PPID" comm rest
  while [ "${pid:-0}" -gt 1 ]; do
    comm=$(cat "/proc/$pid/comm" 2>/dev/null) || return 0
    case "$comm" in *multica*) return 0 ;; esac
    # PPID is field 4 of /proc/<pid>/stat. comm (field 2) is paren-wrapped and
    # the kernel does not escape it, so it may itself contain ')' or spaces —
    # strip through the LAST ')', after which the fields are fixed-format.
    rest=$(cat "/proc/$pid/stat" 2>/dev/null) || return 0
    rest=${rest##*)}
    # rest = " <state> <ppid> <pgrp> ..." -> ppid is the 2nd field.
    # shellcheck disable=SC2086
    set -- $rest
    pid="$2"
  done
  return 1
}

if [ -s "$CONFIG" ] && ! _atlas_is_daemon_invocation; then
  # shellcheck disable=SC1090
  . "$CONFIG"  # ATLAS_HUMAN_USAGE_TOKEN, ATLAS_USAGE_ENDPOINT, device name, interval
  if [ -n "${ATLAS_HUMAN_USAGE_TOKEN:-}" ] && [ -n "${ATLAS_USAGE_ENDPOINT:-}" ]; then
    export OPENCODE_ENABLE_TELEMETRY=1
    export OPENCODE_OTLP_ENDPOINT="${ATLAS_USAGE_ENDPOINT%/}"  # plugin appends /v1/metrics
    export OPENCODE_OTLP_PROTOCOL=http/json
    export OPENCODE_OTLP_HEADERS="Authorization=Bearer ${ATLAS_HUMAN_USAGE_TOKEN}"
    export OPENCODE_RESOURCE_ATTRIBUTES="device.name=${MULTICA_DAEMON_DEVICE_NAME},atlas.origin=human"
    # Metrics only — no traces/logs.
    export OPENCODE_DISABLE_TRACES=all
    export OPENCODE_DISABLE_LOGS=1
    # Short-lived sessions: flush more often (no flush-on-exit guarantee).
    export OPENCODE_OTLP_METRICS_INTERVAL="${ATLAS_USAGE_INTERVAL:-10000}"
  fi
fi

exec "$REAL" "$@"
