#!/usr/bin/env bash
# =============================================================================
# setup.sh — Idempotent Multica Squad Installer
#
# Reads squad/agent instructions directly from this repository (the repo IS
# the source of truth — no cache, no network fetch beyond bootstrapping the
# repo itself) and creates or updates every squad/agent so that Multica
# always matches what's checked in.
#
# Nothing squad-specific is hardcoded in this script. `install/squads.yaml`
# lists which squad folders to process; everything else (squad description,
# leadership, member roles, agent descriptions) is inferred directly from
# each squad's own `squad-instructions.md` + `agents/*.md` files — see
# `install/squads.yaml` and `install/lib.sh` for the exact inference rules.
#
# Features:
#   ✅ Idempotent    — safe to re-run any number of times (updates in place)
#   ✅ Local-first   — reads squad-instructions.md / agents/*.md from this repo
#   ✅ Data-driven   — adding/removing a squad never requires editing this file
#   ✅ Self-bootstrapping — `curl | bash` clones the full repo automatically
#   ✅ Dry-run mode  — preview every change with zero mutating API calls
#
# Usage:
#   bash install/setup.sh [--dry-run] [-h|--help]
#
#   # One-liner (bootstraps a full checkout into ~/build-multica if needed):
#   curl -fsSL https://raw.githubusercontent.com/jefflunt/build-multica/main/install/setup.sh | bash
#
# Environment variables:
#   RUNTIME_ID                 Pin the runtime UUID (skips the interactive prompt)
#   MULTICA_HTTP_TIMEOUT       HTTP timeout for large instruction payloads (default: 180s)
#   MULTICA_SETUP_VERBOSE=1    Print extra debug-level log lines
#   BUILD_MULTICA_REPO_URL     Override the git URL used when bootstrapping
#   BUILD_MULTICA_INSTALL_DIR  Override the local clone destination (default: ~/build-multica)
# =============================================================================
set -euo pipefail

# ── Bootstrap: make sure we have a full local checkout ──────────────────────
# This block intentionally has ZERO dependency on lib.sh (it may not exist
# yet locally when this file is fetched standalone via `curl | bash`).
DEFAULT_REPO_URL="https://github.com/jefflunt/build-multica"
DEFAULT_INSTALL_DIR="${HOME}/build-multica"
BUILD_MULTICA_REPO_URL="${BUILD_MULTICA_REPO_URL:-$DEFAULT_REPO_URL}"
BUILD_MULTICA_INSTALL_DIR="${BUILD_MULTICA_INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"

_script_source="${BASH_SOURCE[0]:-$0}"
_script_dir="$(cd "$(dirname "$_script_source")" 2>/dev/null && pwd || true)"

_have_local_checkout=0
if [[ -n "$_script_dir" && -f "${_script_dir}/squads.yaml" && -f "${_script_dir}/lib.sh" ]]; then
  _have_local_checkout=1
fi

if [[ "$_have_local_checkout" -eq 0 ]]; then
  echo "[build-multica] No local checkout detected next to this script (likely running via curl | bash)." >&2
  echo "[build-multica] Bootstrapping a full copy of the repository..." >&2

  if ! command -v git >/dev/null 2>&1; then
    echo "[build-multica] ✗ ERROR: git is required to bootstrap the installer but was not found on PATH." >&2
    echo "[build-multica]   Install git, or clone the repo yourself and run: bash install/setup.sh" >&2
    exit 1
  fi

  if [[ -d "${BUILD_MULTICA_INSTALL_DIR}/.git" ]]; then
    echo "[build-multica] Found an existing checkout at ${BUILD_MULTICA_INSTALL_DIR} — pulling latest..." >&2
    if ! git -C "${BUILD_MULTICA_INSTALL_DIR}" pull --ff-only; then
      echo "[build-multica] ⚠ WARNING: could not fast-forward the existing checkout; continuing with it as-is." >&2
    fi
  elif [[ -e "${BUILD_MULTICA_INSTALL_DIR}" ]]; then
    echo "[build-multica] ✗ ERROR: ${BUILD_MULTICA_INSTALL_DIR} already exists and is not a git checkout." >&2
    echo "[build-multica]   Refusing to overwrite it. Remove/rename it, or set BUILD_MULTICA_INSTALL_DIR" >&2
    echo "[build-multica]   to a different path, then re-run this command." >&2
    exit 1
  else
    echo "[build-multica] Cloning ${BUILD_MULTICA_REPO_URL} into ${BUILD_MULTICA_INSTALL_DIR}..." >&2
    git clone "${BUILD_MULTICA_REPO_URL}" "${BUILD_MULTICA_INSTALL_DIR}"
  fi

  echo "[build-multica] Continuing setup from ${BUILD_MULTICA_INSTALL_DIR}/install/setup.sh" >&2
  echo "" >&2
  exec bash "${BUILD_MULTICA_INSTALL_DIR}/install/setup.sh" "$@"
fi

SCRIPT_DIR="$_script_dir"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
export REPO_ROOT
export PATH="/home/linuxbrew/.linuxbrew/bin:$PATH"

# ── Load shared library ─────────────────────────────────────────────────────
source "${SCRIPT_DIR}/lib.sh"

# ── Parse CLI flags ──────────────────────────────────────────────────────────
DRY_RUN="${DRY_RUN:-0}"
for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=1
      ;;
    -h|--help)
      cat <<EOF
Usage: setup.sh [--dry-run] [-h|--help]

Installs/updates every squad listed in install/squads.yaml.

Flags:
  --dry-run     Preview every create/update without making any changes.
  -h, --help    Show this help text.

Environment variables:
  RUNTIME_ID                 Pin the runtime UUID (skips the interactive prompt)
  MULTICA_HTTP_TIMEOUT       HTTP timeout for large instruction payloads (default: 180s)
  MULTICA_SETUP_VERBOSE=1    Print extra debug-level log lines
  BUILD_MULTICA_REPO_URL     Override the git URL used when bootstrapping
  BUILD_MULTICA_INSTALL_DIR  Override the local clone destination (default: ~/build-multica)
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done
export DRY_RUN

echo "╔══════════════════════════════════════════════════════════════════════╗"
if [[ "$DRY_RUN" == "1" ]]; then
echo "║  build-multica — Idempotent Squad Setup            [DRY-RUN MODE]     ║"
else
echo "║  build-multica — Idempotent Squad Setup                              ║"
fi
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

# ── Step 0: Preflight — require the multica CLI ─────────────────────────────
log_step "Step 0: Preflight checks"
require_multica_installed
echo ""

# ── Step 1: Resolve the runtime to run every agent on ───────────────────────
log_step "Step 1: Resolving runtime..."
RUNTIME_ID="$(select_runtime)"
echo ""

# ── Step 2: Prime the agent + squad maps ────────────────────────────────────
log_step "Step 2: Pre-fetching workspace state..."
init_agent_map
init_squad_map
echo ""

# ── Step 3: Read the squad list ──────────────────────────────────────────────
CONFIG_FILE="${REPO_ROOT}/install/squads.yaml"
log_step "Step 3: Reading squad list from ${CONFIG_FILE}..."
mapfile -t SQUAD_DIRS < <(read_squad_list "$CONFIG_FILE")
if [[ "${#SQUAD_DIRS[@]}" -eq 0 ]]; then
  log_error "No squads found in ${CONFIG_FILE}. Nothing to do."
  exit 1
fi
log_info "Found ${#SQUAD_DIRS[@]} squad(s): ${SQUAD_DIRS[*]}"
echo ""

# ── ensure_agent_exists: pass-1 helper — create the agent if missing using
#    its raw (not-yet-placeholder-resolved) content, purely to reserve a
#    UUID. Pass 2 immediately overwrites it with fully resolved instructions
#    once every agent in the squad is known, so mentions resolve correctly
#    on the very first run (no "run it twice" needed).
ensure_agent_exists() {
  local name="$1" file="$2"
  local existing_id
  existing_id="$(get_agent_id "$name")"
  if [[ -n "$existing_id" ]]; then
    echo "$existing_id"
    return 0
  fi
  local desc
  desc="$(frontmatter_field "$file" "description")"
  upsert_agent "$name" "$RUNTIME_ID" "$desc" "$(cat "$file")"
}

PROCESSED_SQUADS=()
PROCESSED_AGENTS=()

# ── process_squad: fully generic — no squad-specific logic whatsoever ──────
process_squad() {
  local squad_dir="$1" idx="$2" total="$3"
  local squad_path="${REPO_ROOT}/${squad_dir}"

  log_step "Squad ${idx}/${total}: ${squad_dir}"
  echo "──────────────────────────────────────────────────────────"

  if [[ ! -d "$squad_path" ]]; then
    log_error "Squad folder '${squad_dir}' (listed in squads.yaml) does not exist at ${squad_path}. Skipping."
    return 1
  fi

  # Exactly one *.md file directly in the squad root is the routing file.
  local -a root_md_files=()
  while IFS= read -r -d '' f; do
    root_md_files+=("$f")
  done < <(find "$squad_path" -maxdepth 1 -type f -name '*.md' -print0 | sort -z)

  if [[ "${#root_md_files[@]}" -ne 1 ]]; then
    log_error "Expected exactly one .md file directly in '${squad_dir}/' (found ${#root_md_files[@]}). Skipping squad."
    return 1
  fi
  local squad_instructions_file="${root_md_files[0]}"

  local -a agent_files=()
  while IFS= read -r -d '' f; do
    agent_files+=("$f")
  done < <(find "${squad_path}/agents" -maxdepth 1 -type f -name '*.md' -print0 2>/dev/null | sort -z)

  if [[ "${#agent_files[@]}" -eq 0 ]]; then
    log_error "No agent files found under '${squad_dir}/agents/'. Skipping squad."
    return 1
  fi

  # Identify the leader (frontmatter `leader: true`); everyone else is a member.
  local leader_file="" leader_name="" f name is_leader
  local -a member_files=()
  for f in "${agent_files[@]}"; do
    name="$(basename "$f" .md)"
    is_leader="$(frontmatter_field "$f" "leader")"
    if [[ "$is_leader" == "true" ]]; then
      if [[ -n "$leader_file" ]]; then
        log_error "Squad '${squad_dir}' has more than one agent with 'leader: true' (${leader_name}, ${name}). Skipping squad."
        return 1
      fi
      leader_file="$f"
      leader_name="$name"
    else
      member_files+=("$f")
    fi
  done

  if [[ -z "$leader_file" ]]; then
    log_error "Squad '${squad_dir}' has no agent with 'leader: true' in its frontmatter. Skipping squad."
    return 1
  fi

  log_info "Leader: ${leader_name}  |  Members: ${#member_files[@]} (${member_files[*]##*/})"

  # ---- Pass 1: reserve UUIDs for every agent in this squad -----------------
  local leader_id
  leader_id="$(ensure_agent_exists "$leader_name" "$leader_file")"
  declare -A member_ids=()
  for f in "${member_files[@]}"; do
    name="$(basename "$f" .md)"
    member_ids["$name"]="$(ensure_agent_exists "$name" "$f")"
  done

  # Build this squad's role → UUID map for mention-placeholder resolution.
  CURRENT_SQUAD_ROLE_MAP=()
  CURRENT_SQUAD_ROLE_MAP["leader"]="$leader_id"
  local role_label role_key
  for f in "${member_files[@]}"; do
    name="$(basename "$f" .md)"
    role_label="$(derive_role_label "$squad_dir" "$name")"
    role_key="$(printf '%s' "$role_label" | tr '[:upper:] ' '[:lower:]-')"
    CURRENT_SQUAD_ROLE_MAP["$role_key"]="${member_ids[$name]}"
  done

  # ---- Pass 2: resolve full instructions now that every UUID is known ------
  local leader_desc leader_instructions
  leader_desc="$(frontmatter_field "$leader_file" "description")"
  leader_instructions="$(resolve_placeholders "$(cat "$leader_file")")"
  leader_id="$(upsert_agent "$leader_name" "$RUNTIME_ID" "$leader_desc" "$leader_instructions")"
  PROCESSED_AGENTS+=("$leader_name")

  local desc instr
  for f in "${member_files[@]}"; do
    name="$(basename "$f" .md)"
    desc="$(frontmatter_field "$f" "description")"
    instr="$(resolve_placeholders "$(cat "$f")")"
    member_ids["$name"]="$(upsert_agent "$name" "$RUNTIME_ID" "$desc" "$instr")"
    PROCESSED_AGENTS+=("$name")
  done

  # ---- Squad itself (description is inherited from the leader's) -----------
  local squad_instructions squad_id
  squad_instructions="$(resolve_placeholders "$(cat "$squad_instructions_file")")"
  squad_id="$(upsert_squad "$squad_dir" "$leader_id" "$leader_desc" "$squad_instructions")"
  PROCESSED_SQUADS+=("$squad_dir")

  if [[ -n "$squad_id" ]]; then
    for f in "${member_files[@]}"; do
      name="$(basename "$f" .md)"
      role_label="$(derive_role_label "$squad_dir" "$name")"
      upsert_squad_member "$squad_id" "${member_ids[$name]}" "$role_label"
    done
  fi

  log_step "Squad ${idx}/${total} (${squad_dir}) complete."
  echo ""
}

# ── Step 4: Process every squad ──────────────────────────────────────────────
log_step "Step 4: Installing/updating squads..."
echo ""
TOTAL_SQUADS="${#SQUAD_DIRS[@]}"
i=0
for squad_dir in "${SQUAD_DIRS[@]}"; do
  i=$((i + 1))
  process_squad "$squad_dir" "$i" "$TOTAL_SQUADS" || true
done

# ═══════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
if [[ "$DRY_RUN" == "1" ]]; then
echo "║  ✅ DRY-RUN COMPLETE — no changes were made                          ║"
else
echo "║  ✅ SETUP COMPLETE                                                    ║"
fi
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "  Squads managed:"
for name in "${PROCESSED_SQUADS[@]}"; do
  printf "    %-14s → %s\n" "$name" "${SQUAD_MAP[$name]:-CREATED}"
done
echo ""
echo "  Agent mentions (copy these to use in Multica):"
for name in "${PROCESSED_AGENTS[@]}"; do
  id="${AGENT_MAP[$name]:-}"
  if [[ -n "$id" ]]; then
    echo "    [@${name}](mention://agent/${id})"
  fi
done
echo ""
if [[ "$DRY_RUN" == "1" ]]; then
  echo "  Re-run without --dry-run to apply these changes."
else
  echo "  Verify: multica squad list && multica agent list"
fi
