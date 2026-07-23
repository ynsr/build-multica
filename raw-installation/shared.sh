#!/usr/bin/env bash
# =============================================================================
# shared.sh — Idempotent Multica Setup Library
#
# Usage: source shared.sh
# Requires: bash 4+, jq, multica CLI authenticated, PATH includes multica
#
# Functions:
#   init_agent_map              — Build global AGENT_MAP from multica agent list
#   get_agent_id <name>         — Lookup agent UUID by name from AGENT_MAP
#   upsert_agent <args>         — Idempotent agent create-or-update
#   upsert_squad <args>         — Idempotent squad create-or-update
#   upsert_squad_member <args>  — Idempotent squad member add-or-skip
#   resolve_placeholders        — Replace agent-mention placeholders with UUIDs
#   load_cached_instruction     — Load a cached .md file from disk
# =============================================================================

set -euo pipefail

# ── Global AGENT_MAP (name → UUID) ──────────────────────────────────────────
declare -A AGENT_MAP=()
declare -A SQUAD_MAP=()
CACHE_DIR="${CACHE_DIR:-/home/bs/.hermes/cache/build-multica-instructions}"
BASE_URL="https://raw.githubusercontent.com/jefflunt/build-multica/main"

# ── init_agent_map: Build AGENT_MAP from live multica list ───────────────────
init_agent_map() {
  echo "  → Fetching current agent list..."
  local raw
  raw=$(multica agent list --output json 2>&1)
  AGENT_MAP=()
  while IFS=$'\t' read -r name id; do
    [[ -n "$name" && -n "$id" ]] && AGENT_MAP["$name"]="$id"
  done < <(echo "$raw" | jq -r '.[] | "\(.name)\t\(.id)"')
  echo "  ✓ ${#AGENT_MAP[@]} agents indexed."
}

# ── get_agent_id: Lookup an agent UUID by name ───────────────────────────────
get_agent_id() {
  local name="$1"
  echo "${AGENT_MAP[$name]:-}"
}

# ── init_squad_map: Build SQUAD_MAP from live multica list ───────────────────
init_squad_map() {
  echo "  → Fetching current squad list..."
  local raw
  raw=$(multica squad list --output json 2>&1)
  SQUAD_MAP=()
  while IFS=$'\t' read -r name id; do
    [[ -n "$name" && -n "$id" ]] && SQUAD_MAP["$name"]="$id"
  done < <(echo "$raw" | jq -r '.[] | "\(.name)\t\(.id)"')
  echo "  ✓ ${#SQUAD_MAP[@]} squads indexed."
}

# ── resolve_placeholders: Replace agent-mention <> with UUIDs ────────────────
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

  # ── Squad-ambiguous mapping ────────────────────────────────────────────
  local leader="${AGENT_MAP[${squad}-leader]:-}"
  local analyst="${AGENT_MAP[${squad}-analyst]:-}"
  local planner="${AGENT_MAP[${squad}-planner]:-}"

  # Special case: multica-v1 uses multica-v1-leader / multica-v1-analyst
  if [[ "$squad" == "multica-v1" ]]; then
    leader="${AGENT_MAP[multica-v1-leader]:-}"
    analyst="${AGENT_MAP[multica-v1-analyst]:-}"
    # multica-v1 has no planner
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

  # ── Replace all named agent placeholders ───────────────────────────────
  # Pattern: <(agent-name)-(v\d-)?uuid> → AGENT_MAP["agent-name"]
  # We iteratively resolve all known agents
  while IFS=$'\t' read -r name uuid; do
    local placeholder="${name}-uuid"
    result="${result//<$placeholder>/$uuid}"
  done < <(for key in "${!AGENT_MAP[@]}"; do
    echo -e "$key\t${AGENT_MAP[$key]}"
  done)

  echo "$result"
}

# ── load_cached_instruction: Read cached .md file or fetch from GitHub ───────
# Returns: content on stdout
load_cached_instruction() {
  local squad="$1"
  local filename="$2"
  local cache_path="${CACHE_DIR}/${squad}/${filename}"

  if [[ -f "$cache_path" ]]; then
    cat "$cache_path"
  else
    # Fetch from GitHub
    local url="${BASE_URL}/${squad}/${filename}"
    curl -sL --max-time 30 "$url"
  fi
}

# ── upsert_agent: Idempotent agent create-or-update ───────────────────────────
# Usage: upsert_agent <name> <runtime_id> <description> <instructions>
# Returns: agent UUID on stdout
upsert_agent() {
  local name="$1"
  local runtime_id="$2"
  local description="$3"
  local instructions="$4"
  local existing_id

  existing_id=$(get_agent_id "$name")

  if [[ -n "$existing_id" ]]; then
    echo "  → Agent '$name' exists → updating (${existing_id:0:8}...)..."
    multica agent update "$existing_id" \
      --instructions "$instructions" \
      --description "$description" \
      --output json > /dev/null 2>&1 || true
    echo "$existing_id"
  else
    echo "  → Creating agent '$name'..."
    local result
    result=$(multica agent create \
      --name "$name" \
      --runtime-id "$runtime_id" \
      --description "$description" \
      --instructions "$instructions" \
      --permission-mode private \
      --output json 2>&1 || true)
    local id
    id=$(echo "$result" | jq -r '.id // empty' 2>/dev/null || echo "")
    if [[ -z "$id" ]]; then
      echo "  ⚠ Agent '$name' creation may have failed. Retrying..."
      sleep 2
      result=$(multica agent create \
        --name "$name" \
        --runtime-id "$runtime_id" \
        --description "$description" \
        --instructions "$instructions" \
        --permission-mode private \
        --output json 2>&1 || true)
      id=$(echo "$result" | jq -r '.id // empty' 2>/dev/null || echo "")
    fi
    # Update our local map
    if [[ -n "$id" ]]; then
      AGENT_MAP["$name"]="$id"
    fi
    echo "$id"
  fi
}

# ── upsert_squad: Idempotent squad create-or-update ───────────────────────────
# Usage: upsert_squad <name> <leader_id> <description> <instructions>
# Returns: squad UUID on stdout
upsert_squad() {
  local name="$1"
  local leader_id="$2"
  local description="$3"
  local instructions="$4"
  local existing_id="${SQUAD_MAP[$name]:-}"

  if [[ -n "$existing_id" ]]; then
    echo "  → Squad '$name' exists → updating (${existing_id:0:8}...)..."
    multica squad update "$existing_id" \
      --leader "$leader_id" \
      --description "$description" \
      --instructions "$instructions" \
      --output json > /dev/null 2>&1 || true
    echo "$existing_id"
  else
    echo "  → Creating squad '$name'..."
    local result
    result=$(multica squad create \
      --name "$name" \
      --leader "$leader_id" \
      --description "$description" \
      --output json 2>&1 || true)
    local id
    id=$(echo "$result" | jq -r '.id // empty' 2>/dev/null || echo "")
    if [[ -z "$id" ]]; then
      echo "  ⚠ Squad '$name' creation failed. Aborting."
      echo ""
      return 1
    fi

    # Apply instructions (squad create doesn't take --instructions)
    if [[ -n "$instructions" ]]; then
      echo "  → Applying squad instructions..."
      multica squad update "$id" \
        --instructions "$instructions" \
        --output json > /dev/null 2>&1 || true
    fi

    SQUAD_MAP["$name"]="$id"
    echo "$id"
  fi
}

# ── upsert_squad_member: Idempotent squad member add-or-skip ─────────────────
# Usage: upsert_squad_member <squad_id> <member_id> <role>
# Returns: 0 on success, 1 on failure
upsert_squad_member() {
  local squad_id="$1"
  local member_id="$2"
  local role="$3"

  if [[ -z "$member_id" || "$member_id" == "null" ]]; then
    echo "  ⚠ Skipping member with empty ID (role=$role)"
    return 0
  fi

  # Check current members
  local members_json
  members_json=$(multica squad member list "$squad_id" --output json 2>&1 || echo "[]")

  # Check if already a member (by member_id)
  local exists
  exists=$(echo "$members_json" | jq -r --arg mid "$member_id" \
    'if type == "array" then .[] | select(.member_id == $mid) | .member_id else empty end' 2>/dev/null || echo "")

  if [[ -n "$exists" ]]; then
    echo "  → Member '$member_id' already in squad (role=$role) → skipping."
    return 0
  fi

  echo "  → Adding member (role=$role)..."
  local result
  result=$(multica squad member add "$squad_id" \
    --member-id "$member_id" \
    --type agent \
    --role "$role" \
    --output json 2>&1 || true)

  # Check for conflict error
  if echo "$result" | grep -qi "conflict\|already\|exists\|409" 2>/dev/null; then
    echo "  → Already a member (conflict) → skipping."
    return 0
  fi

  echo "  ✓ Member added (role=$role)."
  return 0
}
