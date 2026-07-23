#!/usr/bin/env bash
# =============================================================================
# lib.sh — Idempotent Multica Setup Library
#
# Usage: source lib.sh
# Requires: bash 4+, jq, multica CLI authenticated, PATH includes multica
#
# Functions:
#   init_agent_map              — Build global AGENT_MAP from multica agent list
#   init_squad_map               — Build global SQUAD_MAP from multica squad list
#   get_agent_id <name>          — Lookup agent UUID by name from AGENT_MAP
#   select_runtime                — Dynamically discover/select a runtime ID
#   load_instruction <squad> <f> — Read an instruction file from this repo
#   resolve_placeholders          — Replace agent-mention placeholders with UUIDs
#   upsert_agent <args>            — Idempotent agent create-or-update
#   upsert_squad <args>             — Idempotent squad create-or-update
#   upsert_squad_member <args>       — Idempotent squad member add-or-skip
#
# IMPORTANT: every function that is meant to be used via command substitution
# (i.e. called as `VAR=$(fn ...)`) must send *all* human-readable progress
# messages to stderr (`>&2`) and only ever put the actual return value on
# stdout. Mixing the two was the root cause of the original script silently
# corrupting UUIDs (the captured "id" ended up containing log text).
# =============================================================================

set -euo pipefail

# ── Global AGENT_MAP / SQUAD_MAP (name → UUID) ──────────────────────────────
declare -A AGENT_MAP=()
declare -A SQUAD_MAP=()

# Multica's default HTTP timeout can be too short for large instruction
# payloads (multi-KB markdown files), which makes `agent update` / `squad
# update` calls fail with "Request timed out" even though the command itself
# is correct. Give it a generous default, overridable by the caller.
export MULTICA_HTTP_TIMEOUT="${MULTICA_HTTP_TIMEOUT:-180s}"

# ── init_agent_map: Build AGENT_MAP from live multica list ─────────────────
init_agent_map() {
  echo "  → Fetching current agent list..." >&2
  local raw
  raw=$(multica agent list --output json 2>&1)
  AGENT_MAP=()
  while IFS=$'\t' read -r name id; do
    [[ -n "$name" && -n "$id" ]] && AGENT_MAP["$name"]="$id"
  done < <(echo "$raw" | jq -r '.[] | "\(.name)\t\(.id)"')
  echo "  ✓ ${#AGENT_MAP[@]} agents indexed." >&2
}

# ── get_agent_id: Lookup an agent UUID by name ──────────────────────────────
get_agent_id() {
  local name="$1"
  echo "${AGENT_MAP[$name]:-}"
}

# ── init_squad_map: Build SQUAD_MAP from live multica list ─────────────────
init_squad_map() {
  echo "  → Fetching current squad list..." >&2
  local raw
  raw=$(multica squad list --output json 2>&1)
  SQUAD_MAP=()
  while IFS=$'\t' read -r name id; do
    [[ -n "$name" && -n "$id" ]] && SQUAD_MAP["$name"]="$id"
  done < <(echo "$raw" | jq -r '.[] | "\(.name)\t\(.id)"')
  echo "  ✓ ${#SQUAD_MAP[@]} squads indexed." >&2
}

# ── select_runtime: Dynamically discover/select a runtime at install time ──
# Usage: RUNTIME_ID=$(select_runtime)
# Behavior:
#   - If $RUNTIME_ID is already set in the environment, use it as-is.
#   - Otherwise, query `multica runtime list` live (never cached):
#       0 runtimes  → error out with guidance
#       1 runtime   → auto-select it
#       2+ runtimes → print the full list and prompt the user to choose
# Returns: runtime UUID on stdout
select_runtime() {
  if [[ -n "${RUNTIME_ID:-}" ]]; then
    echo "  → Using RUNTIME_ID from environment: $RUNTIME_ID" >&2
    echo "$RUNTIME_ID"
    return 0
  fi

  echo "  → Discovering available runtimes..." >&2
  local raw count
  raw=$(multica runtime list --output json 2>&1)
  count=$(echo "$raw" | jq -r 'length' 2>/dev/null || echo 0)

  if [[ "$count" -eq 0 ]]; then
    echo "  ✗ No runtimes found in this workspace." >&2
    echo "    Create one first (multica runtime create ...) or pass RUNTIME_ID explicitly." >&2
    return 1
  fi

  if [[ "$count" -eq 1 ]]; then
    local id name
    id=$(echo "$raw" | jq -r '.[0].id')
    name=$(echo "$raw" | jq -r '.[0].name')
    echo "  ✓ Auto-selected the only available runtime: ${name} (${id})" >&2
    echo "$id"
    return 0
  fi

  # Multiple runtimes → show them all and prompt for an explicit choice.
  echo "" >&2
  echo "  Multiple runtimes are available in this workspace:" >&2
  echo "" >&2
  local -a ids names
  local i=1
  while IFS=$'\t' read -r id name; do
    ids[i]="$id"
    names[i]="$name"
    printf "    %2d) %-40s %s\n" "$i" "$name" "$id" >&2
    i=$((i + 1))
  done < <(echo "$raw" | jq -r '.[] | "\(.id)\t\(.name)"')
  local max=$((i - 1))
  echo "" >&2

  local choice
  while true; do
    read -r -p "  Select a runtime [1-${max}]: " choice </dev/tty
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= max )); then
      break
    fi
    echo "  ⚠ Invalid selection. Enter a number between 1 and ${max}." >&2
  done

  echo "  ✓ Selected: ${names[$choice]} (${ids[$choice]})" >&2
  echo "${ids[$choice]}"
}

# ── load_instruction: Read an instruction file directly from this repo ─────
# Usage: load_instruction <squad-dir> <relative-file-path>
# Returns: file content on stdout
load_instruction() {
  local squad="$1"
  local relative_path="$2"
  local full_path="${REPO_ROOT}/${squad}/${relative_path}"

  if [[ ! -f "$full_path" ]]; then
    echo "  ✗ Missing instruction file: ${full_path}" >&2
    return 1
  fi
  cat "$full_path"
}

# ── resolve_placeholders: Replace agent-mention <> with UUIDs ──────────────
# Usage: resolve_placeholders <content> <squad-folder-name>
# Returns: rewritten content on stdout
#
# Rule: Replace <agent-name-uuid> patterns with the actual UUID from AGENT_MAP.
#       Skips placeholders that don't end in -uuid> (those are general code
#       placeholders like <issue-id>, <target-directory>, etc.)
#
# Squad-ambiguous placeholders:
#   <leader-uuid>  → resolved by squad context
#   <analyst-uuid> → resolved by squad context
#   <planner-uuid> → resolved by squad context
resolve_placeholders() {
  local content="$1"
  local squad="$2"
  local result="$content"

  # ── Squad-ambiguous mapping ──────────────────────────────────────────────
  local leader="${AGENT_MAP[${squad}-leader]:-}"
  local analyst="${AGENT_MAP[${squad}-analyst]:-}"
  local planner="${AGENT_MAP[${squad}-planner]:-}"

  # Special case: multica-v1 uses multica-v1-leader / multica-v1-analyst
  if [[ "$squad" == "multica-v1" ]]; then
    leader="${AGENT_MAP[multica-v1-leader]:-}"
    analyst="${AGENT_MAP[multica-v1-analyst]:-}"
    # multica-v1 has no planner
  fi

  # Special case: design-v1 agents are named design-leader / design-analyst / design-planner
  if [[ "$squad" == "design-v1" ]]; then
    leader="${AGENT_MAP[design-leader]:-}"
    analyst="${AGENT_MAP[design-analyst]:-}"
    planner="${AGENT_MAP[design-planner]:-}"
  fi

  # Replace ambiguous generic placeholders
  if [[ -n "$leader" ]]; then
    result="${result//<leader-uuid>/$leader}"
  fi
  if [[ -n "$analyst" ]]; then
    result="${result//<analyst-uuid>/$analyst}"
  fi
  if [[ -n "$planner" ]]; then
    result="${result//<planner-uuid>/$planner}"
  fi

  # ── Replace all named agent placeholders ────────────────────────────────
  # Pattern: <(agent-name)-uuid> → AGENT_MAP["agent-name"]
  while IFS=$'\t' read -r name uuid; do
    local placeholder="${name}-uuid"
    result="${result//<$placeholder>/$uuid}"
  done < <(for key in "${!AGENT_MAP[@]}"; do
    echo -e "$key\t${AGENT_MAP[$key]}"
  done)

  echo "$result"
}

# ── upsert_agent: Idempotent agent create-or-update ─────────────────────────
# Usage: upsert_agent <name> <runtime_id> <description> <instructions>
# Returns: agent UUID on stdout (and ONLY the UUID — see header note)
upsert_agent() {
  local name="$1"
  local runtime_id="$2"
  local description="$3"
  local instructions="$4"
  local existing_id
  existing_id=$(get_agent_id "$name")

  if [[ -n "$existing_id" ]]; then
    echo "  → Agent '$name' exists → updating (${existing_id:0:8}...)..." >&2
    if ! multica agent update "$existing_id" \
      --instructions "$instructions" \
      --description "$description" \
      --output json > /dev/null 2>/dev/null; then
      echo "  ⚠ Update timed out/failed for agent '$name'. Retrying once..." >&2
      sleep 2
      if ! multica agent update "$existing_id" \
        --instructions "$instructions" \
        --description "$description" \
        --output json > /dev/null; then
        echo "  ✗ Failed to update agent '$name' (${existing_id}) after retry. It may be out of date." >&2
      fi
    fi
    echo "$existing_id"
    return 0
  fi

  echo "  → Creating agent '$name'..." >&2
  local result id
  result=$(multica agent create \
    --name "$name" \
    --runtime-id "$runtime_id" \
    --description "$description" \
    --instructions "$instructions" \
    --permission-mode private \
    --output json 2>&1) || true
  id=$(echo "$result" | jq -r '.id // empty' 2>/dev/null || echo "")

  if [[ -z "$id" ]]; then
    echo "  ⚠ Agent '$name' creation may have failed (${result}). Retrying once..." >&2
    sleep 2
    result=$(multica agent create \
      --name "$name" \
      --runtime-id "$runtime_id" \
      --description "$description" \
      --instructions "$instructions" \
      --permission-mode private \
      --output json 2>&1) || true
    id=$(echo "$result" | jq -r '.id // empty' 2>/dev/null || echo "")
  fi

  if [[ -z "$id" ]]; then
    echo "  ✗ Agent '$name' creation failed: ${result}" >&2
    return 1
  fi

  AGENT_MAP["$name"]="$id"
  echo "$id"
}

# ── upsert_squad: Idempotent squad create-or-update ─────────────────────────
# Usage: upsert_squad <name> <leader_id> <description> <instructions>
# Returns: squad UUID on stdout (and ONLY the UUID — see header note)
upsert_squad() {
  local name="$1"
  local leader_id="$2"
  local description="$3"
  local instructions="$4"
  local existing_id="${SQUAD_MAP[$name]:-}"

  if [[ -n "$existing_id" ]]; then
    echo "  → Squad '$name' exists → updating (${existing_id:0:8}...)..." >&2
    if ! multica squad update "$existing_id" \
      --leader "$leader_id" \
      --description "$description" \
      --instructions "$instructions" \
      --output json > /dev/null 2>/dev/null; then
      echo "  ⚠ Update timed out/failed for squad '$name'. Retrying once..." >&2
      sleep 2
      if ! multica squad update "$existing_id" \
        --leader "$leader_id" \
        --description "$description" \
        --instructions "$instructions" \
        --output json > /dev/null; then
        echo "  ✗ Failed to update squad '$name' (${existing_id}) after retry. It may be out of date." >&2
      fi
    fi
    echo "$existing_id"
    return 0
  fi

  echo "  → Creating squad '$name'..." >&2
  local result id
  result=$(multica squad create \
    --name "$name" \
    --leader "$leader_id" \
    --description "$description" \
    --output json 2>&1) || true
  id=$(echo "$result" | jq -r '.id // empty' 2>/dev/null || echo "")

  if [[ -z "$id" ]]; then
    echo "  ⚠ Squad '$name' creation may have failed (${result}). Retrying once..." >&2
    sleep 2
    result=$(multica squad create \
      --name "$name" \
      --leader "$leader_id" \
      --description "$description" \
      --output json 2>&1) || true
    id=$(echo "$result" | jq -r '.id // empty' 2>/dev/null || echo "")
  fi

  if [[ -z "$id" ]]; then
    echo "  ✗ Squad '$name' creation failed: ${result}" >&2
    return 1
  fi

  # Apply instructions (squad create doesn't take --instructions)
  if [[ -n "$instructions" ]]; then
    echo "  → Applying squad instructions..." >&2
    if ! multica squad update "$id" \
      --instructions "$instructions" \
      --output json > /dev/null; then
      echo "  ⚠ Failed to apply instructions to new squad '$name' (${id})." >&2
    fi
  fi

  SQUAD_MAP["$name"]="$id"
  echo "$id"
}

# ── upsert_squad_member: Idempotent squad member add-or-skip ───────────────
# Usage: upsert_squad_member <squad_id> <member_id> <role>
# Returns: 0 on success, 1 on failure
upsert_squad_member() {
  local squad_id="$1"
  local member_id="$2"
  local role="$3"

  if [[ -z "$member_id" || "$member_id" == "null" ]]; then
    echo "  ⚠ Skipping member with empty ID (role=$role)" >&2
    return 0
  fi

  # Check current members
  local members_json exists
  members_json=$(multica squad member list "$squad_id" --output json 2>&1 || echo "[]")
  exists=$(echo "$members_json" | jq -r --arg mid "$member_id" \
    'if type == "array" then .[] | select(.member_id == $mid) | .member_id else empty end' 2>/dev/null || echo "")

  if [[ -n "$exists" ]]; then
    echo "  → Member '$member_id' already in squad (role=$role) → skipping." >&2
    return 0
  fi

  echo "  → Adding member (role=$role)..." >&2
  local result
  result=$(multica squad member add "$squad_id" \
    --member-id "$member_id" \
    --type agent \
    --role "$role" \
    --output json 2>&1) || true

  if echo "$result" | grep -qi "conflict\|already\|exists\|409" 2>/dev/null; then
    echo "  → Already a member (conflict) → skipping." >&2
    return 0
  fi

  echo "  ✓ Member added (role=$role)." >&2
  return 0
}
