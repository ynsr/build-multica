#!/usr/bin/env bash
# Non-interactively compact an omp session via RPC mode.
#
# Usage:
#   ./omp-compact.sh "focus instructions" [omp CLI args...]
#
# Examples:
#   ./omp-compact.sh "Retain unresolved bugs" -c
#   ./omp-compact.sh "Retain unresolved bugs" --session /path/to/session.jsonl --provider bifrost --model deepseek-v4-flash
#
# Env vars:
#   OMP_COMPACT_VERBOSE=1   also print every streamed RPC frame to stderr live (debugging)
#   OMP_COMPACT_LOG=<path>  use this path instead of an auto-generated temp file
#
# Requires: bash 4+ (coproc), jq
#
# Non-final output (omp's own stderr diagnostics + every intermediate RPC
# frame) is written to a temp log file by default, not discarded. Its path
# is printed to stderr at the end. stdout only ever gets the final response
# JSON.

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required but not found in PATH" >&2
  exit 1
fi

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <focus instructions> [omp CLI args...]" >&2
  exit 1
fi

FOCUS="$1"
shift
EXTRA_ARGS=("$@")
VERBOSE="${OMP_COMPACT_VERBOSE:-0}"
LOG_FILE="${OMP_COMPACT_LOG:-$(mktemp /tmp/omp-compact.XXXXXX.log)}"

# Build the request frame safely — jq handles all escaping (quotes, backslashes,
# newlines, unicode, whatever the caller's instructions/prompt contain).
REQUEST_JSON=$(jq -nc --arg id "compact_1" --arg msg "$FOCUS" \
  '{id: $id, type: "compact", customInstructions: $msg}')

# 1. Start omp in RPC mode as a coprocess.
#    omp writes some diagnostics (e.g. stale-session recovery notices)
#    straight to its own stderr, which coproc does NOT capture — it passes
#    through to our terminal untouched unless we redirect it ourselves.
log() {
  echo "$1" >>"$LOG_FILE"
  [[ "$VERBOSE" == "1" ]] && echo "$1" >&2
  return 0
}

coproc OMP { omp --mode rpc "${EXTRA_ARGS[@]}" 2>>"$LOG_FILE"; }

# 2. Wait for the initial {"type":"ready"} frame
while IFS= read -r -u "${OMP[0]}" line; do
  # log "$line"
  type=$(jq -r '.type // empty' <<<"$line" 2>/dev/null || true)
  [[ "$type" == "ready" ]] && break
done

# 3. Send the compact command
echo "$REQUEST_JSON" >&"${OMP[1]}"

# 4. Read frames silently (unless VERBOSE) until we get the response that
#    matches our request id. The "compact" command's completion IS this
#    response frame — unlike "prompt", there is no separate later event to
#    wait for.
SUCCESS=""
RESPONSE_LINE=""
while IFS= read -r -u "${OMP[0]}" line; do
  log "$line"

  resp_type=$(jq -r '.type // empty' <<<"$line" 2>/dev/null || true)
  resp_id=$(jq -r '.id // empty' <<<"$line" 2>/dev/null || true)
  resp_cmd=$(jq -r '.command // empty' <<<"$line" 2>/dev/null || true)

  if [[ "$resp_type" == "response" && "$resp_id" == "compact_1" && "$resp_cmd" == "compact" ]]; then
    SUCCESS=$(jq -r '.success' <<<"$line")
    RESPONSE_LINE="$line"
    break
  fi
done

# 5. Close stdin so the omp process exits cleanly (exit code 0 on stdin close)
exec {OMP[1]}>&-

# Give it a moment to exit gracefully, then force-kill as a fallback
( sleep 5; kill -TERM "$OMP_PID" 2>/dev/null || true ) &
WATCHDOG_PID=$!
wait "$OMP_PID" 2>/dev/null || true
kill "$WATCHDOG_PID" 2>/dev/null || true

echo "log: $LOG_FILE" >&2

if [[ -z "$RESPONSE_LINE" ]]; then
  echo "{\"success\":false,\"error\":\"no response received from omp, see $LOG_FILE\"}"
  exit 1
fi

echo "$RESPONSE_LINE"
[[ "$SUCCESS" == "true" ]]
