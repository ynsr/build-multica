#!/usr/bin/env bash
# =============================================================================
# lib.sh — Idempotent Multica Setup Library
#
# Usage: source lib.sh
# Requires: bash 4+, awk, jq, multica CLI authenticated, PATH includes multica
#
# Design principle: NOTHING squad-specific is hardcoded here. Squad/agent
# names, descriptions, leadership, and member roles are all inferred at
# runtime directly from each squad's folder contents:
#
#   <squad>/squad-instructions.md   → the ONE *.md file in the squad root
#   <squad>/agents/<name>.md        → one file per agent (name = filename)
#       frontmatter `description:`  → agent description
#       frontmatter `leader: true`  → marks the squad's leader agent
#       (everything else in agents/ is a member; its display role is
#        derived from its filename — see derive_role_label)
#
# Functions:
#   log_step / log_info / log_warn / log_error / log_debug — contextual logging
#   require_multica_installed    — hard-fail with install docs link if missing
#   read_squad_list <yaml>       — list of squad dirs from install/squads.yaml
#   frontmatter_field <f> <key>  — read a top-level YAML frontmatter field
#   derive_role_label <squad> <agent-name> — infer a human role label
#   init_agent_map / init_squad_map        — build name→UUID maps
#   get_agent_id <name>          — lookup agent UUID by name from AGENT_MAP
#   select_runtime                — dynamically discover/select a runtime ID
#   resolve_placeholders          — replace agent-mention placeholders with UUIDs
#   upsert_agent / upsert_squad / upsert_squad_member — idempotent, DRY_RUN-aware
#
# IMPORTANT: every function that is meant to be used via command substitution
# (i.e. called as `VAR=$(fn ...)`) must send *all* human-readable progress
# messages to stderr (log_* helpers already do this) and only ever put the
# actual return value on stdout.
# =============================================================================

set -euo pipefail

# ── Global AGENT_MAP / SQUAD_MAP (name → UUID) ──────────────────────────────
declare -A AGENT_MAP=()
declare -A SQUAD_MAP=()

# Per-squad role → UUID map, rebuilt by setup.sh for each squad before
# resolving that squad's instruction placeholders.
declare -A CURRENT_SQUAD_ROLE_MAP=()

# Multica's default HTTP timeout can be too short for large instruction
# payloads (multi-KB markdown files), which makes `agent update` / `squad
# update` calls fail with "Request timed out" even though the command itself
# is correct. Give it a generous default, overridable by the caller.
export MULTICA_HTTP_TIMEOUT="${MULTICA_HTTP_TIMEOUT:-180s}"

# DRY_RUN=1 skips every *mutating* multica call (create/update/add) and logs
# what would have happened instead. Read-only calls (list) still run so the
# plan reflects real current state.
export DRY_RUN="${DRY_RUN:-0}"

# ── Contextual logging ──────────────────────────────────────────────────────
_log_ts() { date '+%H:%M:%S'; }
log_step()  { printf '[%s] ▶ %s\n' "$(_log_ts)" "$*" >&2; }
log_info()  { printf '[%s]   %s\n' "$(_log_ts)" "$*" >&2; }
log_warn()  { printf '[%s] ⚠ %s\n' "$(_log_ts)" "$*" >&2; }
log_error() { printf '[%s] ✗ %s\n' "$(_log_ts)" "$*" >&2; }
log_debug() { [[ "${MULTICA_SETUP_VERBOSE:-0}" == "1" ]] && printf '[%s] · %s\n' "$(_log_ts)" "$*" >&2 || true; }

# ── require_multica_installed: hard preflight check ─────────────────────────
require_multica_installed() {
  if ! command -v multica >/dev/null 2>&1; then
    log_error "The 'multica' CLI was not found on PATH."
    {
      echo ""
      echo "  Install Multica first, then re-run this script:"
      echo "    • Multica Cloud:      https://www.multica.ai/docs/cloud-quickstart"
      echo "    • Self-hosted:        https://www.multica.ai/docs/self-host-quickstart"
      echo "    • CLI install guide:  https://github.com/multica-ai/multica/blob/main/CLI_INSTALL.md"
      echo ""
    } >&2
    return 1
  fi
  log_info "multica CLI found: $(command -v multica)"
}

# ── multica_supports_flag: capability probe (forward-compatible dry-run) ───
# Usage: multica_supports_flag "--dry-run" agent create
declare -A _MULTICA_HELP_CACHE=()
multica_supports_flag() {
  local flag="$1"; shift
  local key="$*"
  if [[ -z "${_MULTICA_HELP_CACHE[$key]+set}" ]]; then
    _MULTICA_HELP_CACHE["$key"]="$(multica "$@" --help 2>&1 || true)"
  fi
  [[ "${_MULTICA_HELP_CACHE[$key]}" == *"$flag"* ]]
}

# ── read_squad_list: parse install/squads.yaml's flat `squads:` list ───────
# Usage: read_squad_list <path-to-squads.yaml>
# Returns: one squad directory name per line on stdout
read_squad_list() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    log_error "Config file not found: $file"
    return 1
  fi
  awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*-[[:space:]]*/ {
      line = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", line)
      sub(/[[:space:]]*#.*$/, "", line)
      gsub(/^[\x27"]|[\x27"]$/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line != "") print line
    }
  ' "$file"
}

# ── frontmatter_field: read a top-level key from a file's YAML frontmatter ─
# Usage: frontmatter_field <file> <key>
# Returns: the trimmed scalar value on stdout (empty if absent/no frontmatter)
frontmatter_field() {
  local file="$1" key="$2"
  awk -v key="${key}:" '
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    index($0, key) == 1 {
      val = substr($0, length(key) + 1)
      sub(/^[ \t]+/, "", val)
      sub(/[ \t]+$/, "", val)
      gsub(/^["\x27]|["\x27]$/, "", val)
      print val
      exit
    }
  ' "$file"
}

# ── derive_role_label: infer a human-readable squad-member role from a
#    filename, e.g. build-developer-v3 (in build-v3) → "Developer",
#    review-conflict-resolver-v1 (in review-v1) → "Conflict Resolver".
# Usage: derive_role_label <squad-dir> <agent-name>
derive_role_label() {
  local squad_dir="$1" agent_name="$2"
  local squad_base stripped
  squad_base="$(printf '%s' "$squad_dir" | sed -E 's/-v[0-9]+$//')"
  stripped="$agent_name"

  if [[ "$stripped" == "${squad_dir}-"* ]]; then
    stripped="${stripped#"${squad_dir}"-}"
  elif [[ "$stripped" == "${squad_base}-"* ]]; then
    stripped="${stripped#"${squad_base}"-}"
  fi
  stripped="$(printf '%s' "$stripped" | sed -E 's/-v[0-9]+$//')"

  local result="" word
  IFS='-' read -ra _words <<< "$stripped"
  for word in "${_words[@]}"; do
    [[ -z "$word" ]] && continue
    result+="${result:+ }$(printf '%s' "${word:0:1}" | tr '[:lower:]' '[:upper:]')${word:1}"
  done
  printf '%s' "$result"
}

# ── init_agent_map: Build AGENT_MAP from live multica list ─────────────────
init_agent_map() {
  log_info "Fetching current agent list..."
  local raw
  raw=$(multica agent list --output json 2>&1)
  AGENT_MAP=()
  while IFS=$'\t' read -r name id; do
    [[ -n "$name" && -n "$id" ]] && AGENT_MAP["$name"]="$id"
  done < <(echo "$raw" | jq -r '.[] | "\(.name)\t\(.id)"')
  log_info "${#AGENT_MAP[@]} agents indexed."
}

# ── get_agent_id: Lookup an agent UUID by name ──────────────────────────────
get_agent_id() {
  local name="$1"
  echo "${AGENT_MAP[$name]:-}"
}

# ── init_squad_map: Build SQUAD_MAP from live multica list ─────────────────
init_squad_map() {
  log_info "Fetching current squad list..."
  local raw
  raw=$(multica squad list --output json 2>&1)
  SQUAD_MAP=()
  while IFS=$'\t' read -r name id; do
    [[ -n "$name" && -n "$id" ]] && SQUAD_MAP["$name"]="$id"
  done < <(echo "$raw" | jq -r '.[] | "\(.name)\t\(.id)"')
  log_info "${#SQUAD_MAP[@]} squads indexed."
}

# ── select_runtime: Dynamically discover/select a runtime at install time ──
# Usage: RUNTIME_ID=$(select_runtime)
select_runtime() {
  if [[ -n "${RUNTIME_ID:-}" ]]; then
    log_info "Using RUNTIME_ID from environment: $RUNTIME_ID"
    echo "$RUNTIME_ID"
    return 0
  fi

  log_info "Discovering available runtimes..."
  local raw count
  raw=$(multica runtime list --output json 2>&1)
  count=$(echo "$raw" | jq -r 'length' 2>/dev/null || echo 0)

  if [[ "$count" -eq 0 ]]; then
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
      log_warn "No runtimes found in this workspace. Continuing in dry-run with a placeholder runtime."
      echo "DRYRUN-RUNTIME"
      return 0
    fi
    log_error "No runtimes found in this workspace."
    log_error "Create one first (multica runtime create ...) or pass RUNTIME_ID explicitly."
    return 1
  fi

  if [[ "$count" -eq 1 ]]; then
    local id name
    id=$(echo "$raw" | jq -r '.[0].id')
    name=$(echo "$raw" | jq -r '.[0].name')
    log_info "Auto-selected the only available runtime: ${name} (${id})"
    echo "$id"
    return 0
  fi

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

  log_info "Selected: ${names[$choice]} (${ids[$choice]})"
  echo "${ids[$choice]}"
}

# ── resolve_placeholders: Replace agent-mention <> with UUIDs ──────────────
# Usage: resolve_placeholders <content> <squad-folder-name>
# Returns: rewritten content on stdout
#
# Two substitution passes, both fully generic (no squad names hardcoded):
#   1. Role-based placeholders (e.g. <leader-uuid>, <analyst-uuid>,
#      <conflict-resolver-uuid>) resolved from CURRENT_SQUAD_ROLE_MAP, which
#      the caller (setup.sh) rebuilds for each squad right before calling
#      this function.
#   2. Full-name placeholders (e.g. <build-developer-v3-uuid>) resolved
#      directly from the global AGENT_MAP.
resolve_placeholders() {
  local content="$1"
  local result="$content"
  local role uuid name

  for role in "${!CURRENT_SQUAD_ROLE_MAP[@]}"; do
    uuid="${CURRENT_SQUAD_ROLE_MAP[$role]}"
    [[ -n "$uuid" ]] && result="${result//<${role}-uuid>/$uuid}"
  done

  for name in "${!AGENT_MAP[@]}"; do
    uuid="${AGENT_MAP[$name]}"
    result="${result//<${name}-uuid>/$uuid}"
  done

  echo "$result"
}

# ── upsert_agent: Idempotent agent create-or-update (DRY_RUN aware) ────────
# Usage: upsert_agent <name> <runtime_id> <description> <instructions>
# Returns: agent UUID on stdout (real, or a DRYRUN-<name> placeholder)
upsert_agent() {
  local name="$1" runtime_id="$2" description="$3" instructions="$4"
  local existing_id
  existing_id=$(get_agent_id "$name")

  local -a extra_flags=()
  local native_dry_run=0
  if [[ "${DRY_RUN:-0}" == "1" ]] && multica_supports_flag "--dry-run" agent create; then
    native_dry_run=1
    extra_flags=(--dry-run)
  fi

  if [[ -n "$existing_id" ]]; then
    if [[ "${DRY_RUN:-0}" == "1" && "$native_dry_run" -eq 0 ]]; then
      log_info "[DRY-RUN] Would update agent '$name' (${existing_id:0:8}...)"
      echo "$existing_id"
      return 0
    fi
    log_step "Agent '$name' exists → updating (${existing_id:0:8}...)"
    if ! multica agent update "$existing_id" \
      --instructions "$instructions" \
      --description "$description" \
      "${extra_flags[@]}" \
      --output json > /dev/null 2>/dev/null; then
      log_warn "Update timed out/failed for agent '$name'. Retrying once..."
      sleep 2
      if ! multica agent update "$existing_id" \
        --instructions "$instructions" \
        --description "$description" \
        "${extra_flags[@]}" \
        --output json > /dev/null; then
        log_error "Failed to update agent '$name' (${existing_id}) after retry. It may be out of date."
      fi
    fi
    echo "$existing_id"
    return 0
  fi

  if [[ "${DRY_RUN:-0}" == "1" && "$native_dry_run" -eq 0 ]]; then
    log_info "[DRY-RUN] Would create agent '$name' (runtime ${runtime_id:0:8}...)"
    local fake_id="DRYRUN-${name}"
    AGENT_MAP["$name"]="$fake_id"
    echo "$fake_id"
    return 0
  fi

  log_step "Creating agent '$name'..."
  local result id
  result=$(multica agent create \
    --name "$name" \
    --runtime-id "$runtime_id" \
    --description "$description" \
    --instructions "$instructions" \
    --permission-mode private \
    "${extra_flags[@]}" \
    --output json 2>&1) || true
  id=$(echo "$result" | jq -r '.id // empty' 2>/dev/null || echo "")

  if [[ -z "$id" ]]; then
    log_warn "Agent '$name' creation may have failed (${result}). Retrying once..."
    sleep 2
    result=$(multica agent create \
      --name "$name" \
      --runtime-id "$runtime_id" \
      --description "$description" \
      --instructions "$instructions" \
      --permission-mode private \
      "${extra_flags[@]}" \
      --output json 2>&1) || true
    id=$(echo "$result" | jq -r '.id // empty' 2>/dev/null || echo "")
  fi

  if [[ -z "$id" ]]; then
    log_error "Agent '$name' creation failed: ${result}"
    return 1
  fi

  AGENT_MAP["$name"]="$id"
  echo "$id"
}

# ── upsert_squad: Idempotent squad create-or-update (DRY_RUN aware) ────────
# Usage: upsert_squad <name> <leader_id> <description> <instructions>
# Returns: squad UUID on stdout (real, or a DRYRUN-SQUAD-<name> placeholder)
upsert_squad() {
  local name="$1" leader_id="$2" description="$3" instructions="$4"
  local existing_id="${SQUAD_MAP[$name]:-}"

  local -a extra_flags=()
  local native_dry_run=0
  if [[ "${DRY_RUN:-0}" == "1" ]] && multica_supports_flag "--dry-run" squad create; then
    native_dry_run=1
    extra_flags=(--dry-run)
  fi

  if [[ -n "$existing_id" ]]; then
    if [[ "${DRY_RUN:-0}" == "1" && "$native_dry_run" -eq 0 ]]; then
      log_info "[DRY-RUN] Would update squad '$name' (${existing_id:0:8}...)"
      echo "$existing_id"
      return 0
    fi
    log_step "Squad '$name' exists → updating (${existing_id:0:8}...)"
    if ! multica squad update "$existing_id" \
      --leader "$leader_id" \
      --description "$description" \
      --instructions "$instructions" \
      "${extra_flags[@]}" \
      --output json > /dev/null 2>/dev/null; then
      log_warn "Update timed out/failed for squad '$name'. Retrying once..."
      sleep 2
      if ! multica squad update "$existing_id" \
        --leader "$leader_id" \
        --description "$description" \
        --instructions "$instructions" \
        "${extra_flags[@]}" \
        --output json > /dev/null; then
        log_error "Failed to update squad '$name' (${existing_id}) after retry. It may be out of date."
      fi
    fi
    echo "$existing_id"
    return 0
  fi

  if [[ "${DRY_RUN:-0}" == "1" && "$native_dry_run" -eq 0 ]]; then
    log_info "[DRY-RUN] Would create squad '$name' (leader ${leader_id})"
    local fake_id="DRYRUN-SQUAD-${name}"
    SQUAD_MAP["$name"]="$fake_id"
    echo "$fake_id"
    return 0
  fi

  log_step "Creating squad '$name'..."
  local result id
  result=$(multica squad create \
    --name "$name" \
    --leader "$leader_id" \
    --description "$description" \
    "${extra_flags[@]}" \
    --output json 2>&1) || true
  id=$(echo "$result" | jq -r '.id // empty' 2>/dev/null || echo "")

  if [[ -z "$id" ]]; then
    log_warn "Squad '$name' creation may have failed (${result}). Retrying once..."
    sleep 2
    result=$(multica squad create \
      --name "$name" \
      --leader "$leader_id" \
      --description "$description" \
      "${extra_flags[@]}" \
      --output json 2>&1) || true
    id=$(echo "$result" | jq -r '.id // empty' 2>/dev/null || echo "")
  fi

  if [[ -z "$id" ]]; then
    log_error "Squad '$name' creation failed: ${result}"
    return 1
  fi

  if [[ -n "$instructions" ]]; then
    log_step "Applying squad instructions..."
    if ! multica squad update "$id" \
      --instructions "$instructions" \
      --output json > /dev/null; then
      log_warn "Failed to apply instructions to new squad '$name' (${id})."
    fi
  fi

  SQUAD_MAP["$name"]="$id"
  echo "$id"
}

# ── upsert_squad_member: Idempotent squad member add-or-skip (DRY_RUN aware)
# Usage: upsert_squad_member <squad_id> <member_id> <role>
upsert_squad_member() {
  local squad_id="$1" member_id="$2" role="$3"

  if [[ -z "$member_id" || "$member_id" == "null" ]]; then
    log_warn "Skipping member with empty ID (role=$role)"
    return 0
  fi

  if [[ "${DRY_RUN:-0}" == "1" && "$squad_id" == DRYRUN-* ]]; then
    log_info "[DRY-RUN] Would add member (role=$role) to new squad"
    return 0
  fi

  local members_json exists
  members_json=$(multica squad member list "$squad_id" --output json 2>&1 || echo "[]")
  exists=$(echo "$members_json" | jq -r --arg mid "$member_id" \
    'if type == "array" then .[] | select(.member_id == $mid) | .member_id else empty end' 2>/dev/null || echo "")

  if [[ -n "$exists" ]]; then
    log_info "Member '$member_id' already in squad (role=$role) → skipping."
    return 0
  fi

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    log_info "[DRY-RUN] Would add member (role=$role)."
    return 0
  fi

  log_step "Adding member (role=$role)..."
  local result
  result=$(multica squad member add "$squad_id" \
    --member-id "$member_id" \
    --type agent \
    --role "$role" \
    --output json 2>&1) || true

  if echo "$result" | grep -qi "conflict\|already\|exists\|409" 2>/dev/null; then
    log_info "Already a member (conflict) → skipping."
    return 0
  fi

  log_info "Member added (role=$role)."
  return 0
}
