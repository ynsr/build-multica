#!/usr/bin/env bash
# =============================================================================
# idempotent-setup-all.sh — Consolidated Idempotent Squad Setup
#
# Replaces: 01-setup-multica-v1-instructions.sh through 06-setup-review-v1.sh
# Features:
#   ✅ Idempotent — re-running catches existing items and updates them
#   ✅ Placeholder resolution — <agent-uuid> replaced with actual UUIDs
#   ✅ Local instruction cache at CACHE_DIR
#   ✅ Cross-squad agent references handled
#
# Usage:
#   export RUNTIME_ID="9caa8431-d35e-4463-9e4a-0a572e0d9a6a"  # optional
#   bash idempotent-setup-all.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export PATH="/home/linuxbrew/.linuxbrew/bin:$PATH"

# ── Config ───────────────────────────────────────────────────────────────────
RUNTIME_ID="${RUNTIME_ID:-9caa8431-d35e-4463-9e4a-0a572e0d9a6a}"
CACHE_DIR="/home/bs/.hermes/cache/build-multica-instructions"
BASE_URL="https://raw.githubusercontent.com/jefflunt/build-multica/main"

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  build-multica → Projectx — Idempotent Squad Setup                   ║"
echo "║  Runtime: $RUNTIME_ID"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

# ── Load shared library ─────────────────────────────────────────────────────
source "${SCRIPT_DIR}/shared.sh"

# ── Prime the agent + squad maps ───────────────────────────────────────────
echo "📡 Step 0: Pre-fetching workspace state..."
echo "──────────────────────────────────────────────────────────"
init_agent_map
init_squad_map
echo ""

# ── Fetch any missing cached instructions ──────────────────────────────────
echo "💾 Step 0.5: Ensuring cached instructions..."
echo "──────────────────────────────────────────────────────────"
mkdir -p "$CACHE_DIR"

CACHE_FILES=(
  "exec-v1 squad-instructions.md exec-v1.md"
  "exec-v1 exec-leader-v1.md"
  "build-v3 squad-instructions.md build-v3.md"
  "build-v3 build-pm-v3.md"
  "build-v3 build-developer-v3.md"
  "build-v3 build-verifier-v3.md"
  "build-v3 build-cleaner-v3.md"
  "build-v3 build-commiter-v3.md"
  "design-v1 squad-instructions.md design-v1.md"
  "design-v1 leader.md design-leader.md"
  "design-v1 analyst.md design-analyst.md"
  "design-v1 planner.md design-planner.md"
  "doc-v1 squad-instructions.md doc-v1.md"
  "doc-v1 doc-leader-v1.md"
  "doc-v1 doc-auditor-v1.md"
  "doc-v1 doc-writer-v1.md"
  "doc-v1 doc-verifier-v1.md"
  "review-v1 squad-instructions.md review-v1.md"
  "review-v1 review-leader-v1.md"
  "review-v1 review-describer-v1.md"
  "review-v1 review-defender-v1.md"
  "review-v1 review-critiquer-v1.md"
  "review-v1 review-conflict-resolver-v1.md"
  "multica-v1 squad-instructions.md multica-v1.md"
  "multica-v1 leader.md multica-leader.md"
  "multica-v1 analyst.md multica-analyst.md"
)
for entry in "${CACHE_FILES[@]}"; do
  read -r squad gh_file local_file <<< "$entry"
  local_path="${CACHE_DIR}/${squad}/${local_file}"
  if [[ ! -f "$local_path" ]]; then
    mkdir -p "${CACHE_DIR}/${squad}"
    echo "  → Fetching ${squad}/${gh_file}..."
    curl -sL --max-time 30 "${BASE_URL}/${squad}/${gh_file}" -o "$local_path" 2>&1 || echo "  ⚠ Failed to fetch ${squad}/${gh_file}"
  fi
done
echo "  ✓ All cached instructions ready."
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# SQUAD 1: multica-v1 — Meta-Squad
# ═══════════════════════════════════════════════════════════════════════════
echo "📦 Squad 1/6: multica-v1 — Squad Creator & Modifier"
echo "──────────────────────────────────────────────────────────"

# Resolve instructions with placeholders
INSTR_LEADER_MV1=$(cat "${CACHE_DIR}/multica-v1/multica-leader.md" 2>/dev/null || load_cached_instruction "multica-v1" "leader.md")
INSTR_LEADER_MV1=$(resolve_placeholders "$INSTR_LEADER_MV1" "multica-v1")

INSTR_ANALYST_MV1=$(cat "${CACHE_DIR}/multica-v1/multica-analyst.md" 2>/dev/null || load_cached_instruction "multica-v1" "analyst.md")
INSTR_ANALYST_MV1=$(resolve_placeholders "$INSTR_ANALYST_MV1" "multica-v1")

INSTR_SQUAD_MV1=$(cat "${CACHE_DIR}/multica-v1/multica-v1.md" 2>/dev/null || load_cached_instruction "multica-v1" "squad-instructions.md")
INSTR_SQUAD_MV1=$(resolve_placeholders "$INSTR_SQUAD_MV1" "multica-v1")

# Create agents
AGENT_MV1_LEADER=$(upsert_agent "multica-v1-leader" "$RUNTIME_ID" "Coordinator for squad creation squad" "$INSTR_LEADER_MV1")
AGENT_MV1_ANALYST=$(upsert_agent "multica-v1-analyst" "$RUNTIME_ID" "Technical interviewer — writes squad/agent configs" "$INSTR_ANALYST_MV1")

# Create / update squad
SQUAD_MV1_ID=$(upsert_squad "multica-v1" "$AGENT_MV1_LEADER" "Squad creator & modifier — Grill Me protocol for designing squads" "$INSTR_SQUAD_MV1")

# Add non-leader member
if [[ -n "$SQUAD_MV1_ID" ]]; then
  upsert_squad_member "$SQUAD_MV1_ID" "$AGENT_MV1_ANALYST" "Analyst"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# SQUAD 2: exec-v1 — Daily Executive Check-In
# ═══════════════════════════════════════════════════════════════════════════
echo "📦 Squad 2/6: exec-v1 — Daily Executive Check-In"
echo "──────────────────────────────────────────────────────────"

INSTR_LEADER_EXEC=$(cat "${CACHE_DIR}/exec-v1/exec-leader-v1.md" 2>/dev/null || load_cached_instruction "exec-v1" "agents/exec-leader-v1.md")
INSTR_LEADER_EXEC=$(resolve_placeholders "$INSTR_LEADER_EXEC" "exec-v1")

INSTR_SQUAD_EXEC=$(cat "${CACHE_DIR}/exec-v1/exec-v1.md" 2>/dev/null || load_cached_instruction "exec-v1" "squad-instructions.md")
INSTR_SQUAD_EXEC=$(resolve_placeholders "$INSTR_SQUAD_EXEC" "exec-v1")

AGENT_EXEC_LEADER=$(upsert_agent "exec-leader-v1" "$RUNTIME_ID" "Executive leader — daily briefings, on-demand execution, evening wraps" "$INSTR_LEADER_EXEC")
SQUAD_EXEC_ID=$(upsert_squad "exec-v1" "$AGENT_EXEC_LEADER" "Daily executive check-in squad (briefings, interactive help, wraps)" "$INSTR_SQUAD_EXEC")
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# SQUAD 3: design-v1 — Conversational Planning & Breakdown
# ═══════════════════════════════════════════════════════════════════════════
echo "📦 Squad 3/6: design-v1 — Conversational Planning & Breakdown"
echo "──────────────────────────────────────────────────────────"

INSTR_LEADER_DESIGN=$(cat "${CACHE_DIR}/design-v1/design-leader.md" 2>/dev/null || load_cached_instruction "design-v1" "agents/leader.md")
INSTR_LEADER_DESIGN=$(resolve_placeholders "$INSTR_LEADER_DESIGN" "design-v1")

INSTR_ANALYST_DESIGN=$(cat "${CACHE_DIR}/design-v1/design-analyst.md" 2>/dev/null || load_cached_instruction "design-v1" "agents/analyst.md")
INSTR_ANALYST_DESIGN=$(resolve_placeholders "$INSTR_ANALYST_DESIGN" "design-v1")

INSTR_PLANNER_DESIGN=$(cat "${CACHE_DIR}/design-v1/design-planner.md" 2>/dev/null || load_cached_instruction "design-v1" "agents/planner.md")
INSTR_PLANNER_DESIGN=$(resolve_placeholders "$INSTR_PLANNER_DESIGN" "design-v1")

INSTR_SQUAD_DESIGN=$(cat "${CACHE_DIR}/design-v1/design-v1.md" 2>/dev/null || load_cached_instruction "design-v1" "squad-instructions.md")
INSTR_SQUAD_DESIGN=$(resolve_placeholders "$INSTR_SQUAD_DESIGN" "design-v1")

AGENT_DESIGN_LEADER=$(upsert_agent "design-leader" "$RUNTIME_ID" "Design leader — facilitates design approval & step breakdown" "$INSTR_LEADER_DESIGN")
AGENT_DESIGN_ANALYST=$(upsert_agent "design-analyst" "$RUNTIME_ID" "Analyst — Grill Me interview, writes design.md" "$INSTR_ANALYST_DESIGN")
AGENT_DESIGN_PLANNER=$(upsert_agent "design-planner" "$RUNTIME_ID" "Planner — decomposes approved design into steps/*.md" "$INSTR_PLANNER_DESIGN")

SQUAD_DESIGN_ID=$(upsert_squad "design-v1" "$AGENT_DESIGN_LEADER" "Conversational planning & breakdown squad" "$INSTR_SQUAD_DESIGN")

if [[ -n "$SQUAD_DESIGN_ID" ]]; then
  upsert_squad_member "$SQUAD_DESIGN_ID" "$AGENT_DESIGN_ANALYST" "Analyst"
  upsert_squad_member "$SQUAD_DESIGN_ID" "$AGENT_DESIGN_PLANNER" "Planner"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# SQUAD 4: build-v3 — Adaptive Project Management & Execution
# ═══════════════════════════════════════════════════════════════════════════
echo "📦 Squad 4/6: build-v3 — Adaptive Project Management & Execution"
echo "──────────────────────────────────────────────────────────"

INSTR_PM_BUILD=$(cat "${CACHE_DIR}/build-v3/build-pm-v3.md" 2>/dev/null || load_cached_instruction "build-v3" "agents/build-pm-v3.md")
INSTR_PM_BUILD=$(resolve_placeholders "$INSTR_PM_BUILD" "build-v3")

INSTR_DEV_BUILD=$(cat "${CACHE_DIR}/build-v3/build-developer-v3.md" 2>/dev/null || load_cached_instruction "build-v3" "agents/build-developer-v3.md")
INSTR_DEV_BUILD=$(resolve_placeholders "$INSTR_DEV_BUILD" "build-v3")

INSTR_VERIFIER_BUILD=$(cat "${CACHE_DIR}/build-v3/build-verifier-v3.md" 2>/dev/null || load_cached_instruction "build-v3" "agents/build-verifier-v3.md")
INSTR_VERIFIER_BUILD=$(resolve_placeholders "$INSTR_VERIFIER_BUILD" "build-v3")

INSTR_CLEANER_BUILD=$(cat "${CACHE_DIR}/build-v3/build-cleaner-v3.md" 2>/dev/null || load_cached_instruction "build-v3" "agents/build-cleaner-v3.md")
INSTR_CLEANER_BUILD=$(resolve_placeholders "$INSTR_CLEANER_BUILD" "build-v3")

INSTR_COMMITER_BUILD=$(cat "${CACHE_DIR}/build-v3/build-commiter-v3.md" 2>/dev/null || load_cached_instruction "build-v3" "agents/build-commiter-v3.md")
INSTR_COMMITER_BUILD=$(resolve_placeholders "$INSTR_COMMITER_BUILD" "build-v3")

INSTR_SQUAD_BUILD=$(cat "${CACHE_DIR}/build-v3/build-v3.md" 2>/dev/null || load_cached_instruction "build-v3" "squad-instructions.md")
INSTR_SQUAD_BUILD=$(resolve_placeholders "$INSTR_SQUAD_BUILD" "build-v3")

AGENT_BUILD_PM=$(upsert_agent "build-pm-v3" "$RUNTIME_ID" "Project manager — backlog triage, delegation, sign-off" "$INSTR_PM_BUILD")
AGENT_BUILD_DEV=$(upsert_agent "build-developer-v3" "$RUNTIME_ID" "Developer — research-first implementation + full test coverage" "$INSTR_DEV_BUILD")
AGENT_BUILD_VERIFIER=$(upsert_agent "build-verifier-v3" "$RUNTIME_ID" "Verifier — independent build/test/coverage audit" "$INSTR_VERIFIER_BUILD")
AGENT_BUILD_CLEANER=$(upsert_agent "build-cleaner-v3" "$RUNTIME_ID" "Cleaner — detects tech stack, updates .gitignore" "$INSTR_CLEANER_BUILD")
AGENT_BUILD_COMMITER=$(upsert_agent "build-commiter-v3" "$RUNTIME_ID" "Committer — stages, commits, pushes issue-prefixed changes" "$INSTR_COMMITER_BUILD")

SQUAD_BUILD_ID=$(upsert_squad "build-v3" "$AGENT_BUILD_PM" "Adaptive project management & execution squad" "$INSTR_SQUAD_BUILD")

if [[ -n "$SQUAD_BUILD_ID" ]]; then
  upsert_squad_member "$SQUAD_BUILD_ID" "$AGENT_BUILD_DEV"      "Developer"
  upsert_squad_member "$SQUAD_BUILD_ID" "$AGENT_BUILD_VERIFIER" "Verifier"
  upsert_squad_member "$SQUAD_BUILD_ID" "$AGENT_BUILD_CLEANER"  "Cleaner"
  upsert_squad_member "$SQUAD_BUILD_ID" "$AGENT_BUILD_COMMITER" "Commiter"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# SQUAD 5: doc-v1 — Documentation Backfill
# ═══════════════════════════════════════════════════════════════════════════
echo "📦 Squad 5/6: doc-v1 — Documentation Backfill"
echo "──────────────────────────────────────────────────────────"

INSTR_LEADER_DOC=$(cat "${CACHE_DIR}/doc-v1/doc-leader-v1.md" 2>/dev/null || load_cached_instruction "doc-v1" "agents/doc-leader-v1.md")
INSTR_LEADER_DOC=$(resolve_placeholders "$INSTR_LEADER_DOC" "doc-v1")

INSTR_AUDITOR_DOC=$(cat "${CACHE_DIR}/doc-v1/doc-auditor-v1.md" 2>/dev/null || load_cached_instruction "doc-v1" "agents/doc-auditor-v1.md")
INSTR_AUDITOR_DOC=$(resolve_placeholders "$INSTR_AUDITOR_DOC" "doc-v1")

INSTR_WRITER_DOC=$(cat "${CACHE_DIR}/doc-v1/doc-writer-v1.md" 2>/dev/null || load_cached_instruction "doc-v1" "agents/doc-writer-v1.md")
INSTR_WRITER_DOC=$(resolve_placeholders "$INSTR_WRITER_DOC" "doc-v1")

INSTR_VERIFIER_DOC=$(cat "${CACHE_DIR}/doc-v1/doc-verifier-v1.md" 2>/dev/null || load_cached_instruction "doc-v1" "agents/doc-verifier-v1.md")
INSTR_VERIFIER_DOC=$(resolve_placeholders "$INSTR_VERIFIER_DOC" "doc-v1")

INSTR_SQUAD_DOC=$(cat "${CACHE_DIR}/doc-v1/doc-v1.md" 2>/dev/null || load_cached_instruction "doc-v1" "squad-instructions.md")
INSTR_SQUAD_DOC=$(resolve_placeholders "$INSTR_SQUAD_DOC" "doc-v1")

AGENT_DOC_LEADER=$(upsert_agent "doc-leader-v1" "$RUNTIME_ID" "Doc leader — intake, coordination, final approval" "$INSTR_LEADER_DOC")
AGENT_DOC_AUDITOR=$(upsert_agent "doc-auditor-v1" "$RUNTIME_ID" "Auditor — codebase gap analysis, backfill plan" "$INSTR_AUDITOR_DOC")
AGENT_DOC_WRITER=$(upsert_agent "doc-writer-v1" "$RUNTIME_ID" "Writer — drafts/updates agent_docs markdown" "$INSTR_WRITER_DOC")
AGENT_DOC_VERIFIER=$(upsert_agent "doc-verifier-v1" "$RUNTIME_ID" "Verifier — formatting, links, accuracy audit" "$INSTR_VERIFIER_DOC")

SQUAD_DOC_ID=$(upsert_squad "doc-v1" "$AGENT_DOC_LEADER" "Documentation backfill squad" "$INSTR_SQUAD_DOC")

if [[ -n "$SQUAD_DOC_ID" ]]; then
  upsert_squad_member "$SQUAD_DOC_ID" "$AGENT_DOC_AUDITOR"  "Auditor"
  upsert_squad_member "$SQUAD_DOC_ID" "$AGENT_DOC_WRITER"   "Writer"
  upsert_squad_member "$SQUAD_DOC_ID" "$AGENT_DOC_VERIFIER" "Verifier"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# SQUAD 6: review-v1 — PR Analysis & Defense
# ═══════════════════════════════════════════════════════════════════════════
echo "📦 Squad 6/6: review-v1 — PR Analysis & Defense"
echo "──────────────────────────────────────────────────────────"

INSTR_LEADER_REVIEW=$(cat "${CACHE_DIR}/review-v1/review-leader-v1.md" 2>/dev/null || load_cached_instruction "review-v1" "agents/review-leader-v1.md")
INSTR_LEADER_REVIEW=$(resolve_placeholders "$INSTR_LEADER_REVIEW" "review-v1")

INSTR_DESCRIBER_REVIEW=$(cat "${CACHE_DIR}/review-v1/review-describer-v1.md" 2>/dev/null || load_cached_instruction "review-v1" "agents/review-describer-v1.md")
INSTR_DESCRIBER_REVIEW=$(resolve_placeholders "$INSTR_DESCRIBER_REVIEW" "review-v1")

INSTR_DEFENDER_REVIEW=$(cat "${CACHE_DIR}/review-v1/review-defender-v1.md" 2>/dev/null || load_cached_instruction "review-v1" "agents/review-defender-v1.md")
INSTR_DEFENDER_REVIEW=$(resolve_placeholders "$INSTR_DEFENDER_REVIEW" "review-v1")

INSTR_CRITIQUER_REVIEW=$(cat "${CACHE_DIR}/review-v1/review-critiquer-v1.md" 2>/dev/null || load_cached_instruction "review-v1" "agents/review-critiquer-v1.md")
INSTR_CRITIQUER_REVIEW=$(resolve_placeholders "$INSTR_CRITIQUER_REVIEW" "review-v1")

INSTR_RESOLVER_REVIEW=$(cat "${CACHE_DIR}/review-v1/review-conflict-resolver-v1.md" 2>/dev/null || load_cached_instruction "review-v1" "agents/review-conflict-resolver-v1.md")
INSTR_RESOLVER_REVIEW=$(resolve_placeholders "$INSTR_RESOLVER_REVIEW" "review-v1")

INSTR_SQUAD_REVIEW=$(cat "${CACHE_DIR}/review-v1/review-v1.md" 2>/dev/null || load_cached_instruction "review-v1" "squad-instructions.md")
INSTR_SQUAD_REVIEW=$(resolve_placeholders "$INSTR_SQUAD_REVIEW" "review-v1")

AGENT_REVIEW_LEADER=$(upsert_agent "review-leader-v1" "$RUNTIME_ID" "Review leader — coordinates PR checks, final status" "$INSTR_LEADER_REVIEW")
AGENT_REVIEW_DESCRIBER=$(upsert_agent "review-describer-v1" "$RUNTIME_ID" "Describer — writes PR description + reviewer guide from diff" "$INSTR_DESCRIBER_REVIEW")
AGENT_REVIEW_DEFENDER=$(upsert_agent "review-defender-v1" "$RUNTIME_ID" "Defender — responds to reviewer comments collaboratively" "$INSTR_DEFENDER_REVIEW")
AGENT_REVIEW_CRITIQUER=$(upsert_agent "review-critiquer-v1" "$RUNTIME_ID" "Critiquer — devil's advocate, edge cases" "$INSTR_CRITIQUER_REVIEW")
AGENT_REVIEW_RESOLVER=$(upsert_agent "review-conflict-resolver-v1" "$RUNTIME_ID" "Conflict resolver — analyzes git conflicts, writes resolution plan" "$INSTR_RESOLVER_REVIEW")

SQUAD_REVIEW_ID=$(upsert_squad "review-v1" "$AGENT_REVIEW_LEADER" "PR analysis & defense squad" "$INSTR_SQUAD_REVIEW")

if [[ -n "$SQUAD_REVIEW_ID" ]]; then
  upsert_squad_member "$SQUAD_REVIEW_ID" "$AGENT_REVIEW_DESCRIBER" "Describer"
  upsert_squad_member "$SQUAD_REVIEW_ID" "$AGENT_REVIEW_DEFENDER" "Defender"
  upsert_squad_member "$SQUAD_REVIEW_ID" "$AGENT_REVIEW_CRITIQUER" "Critiquer"
  upsert_squad_member "$SQUAD_REVIEW_ID" "$AGENT_REVIEW_RESOLVER" "Conflict Resolver"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  ✅ SETUP COMPLETE                                                    ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "  Squads managed:"
echo "    multica-v1  → ${SQUAD_MAP[multica-v1]:-CREATED}"
echo "    exec-v1     → ${SQUAD_MAP[exec-v1]:-CREATED}"
echo "    design-v1   → ${SQUAD_MAP[design-v1]:-CREATED}"
echo "    build-v3    → ${SQUAD_MAP[build-v3]:-CREATED}"
echo "    doc-v1      → ${SQUAD_MAP[doc-v1]:-CREATED}"
echo "    review-v1   → ${SQUAD_MAP[review-v1]:-CREATED}"
echo ""
echo "  Agent mentions (copy these to use in Multica):"
for name in multica-v1-leader multica-v1-analyst exec-leader-v1 \
            design-leader design-analyst design-planner \
            build-pm-v3 build-developer-v3 build-verifier-v3 \
            build-cleaner-v3 build-commiter-v3 \
            doc-leader-v1 doc-auditor-v1 doc-writer-v1 doc-verifier-v1 \
            review-leader-v1 review-describer-v1 review-defender-v1 \
            review-critiquer-v1 review-conflict-resolver-v1; do
  id="${AGENT_MAP[$name]:-}"
  if [[ -n "$id" ]]; then
    echo "    [@${name}](mention://agent/${id})"
  fi
done
echo ""
echo "  Verify: multica squad list && multica agent list"
