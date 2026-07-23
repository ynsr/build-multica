#!/usr/bin/env bash
# =============================================================================
# setup.sh — Idempotent Multica Squad Installer
#
# Reads squad/agent instructions directly from this repository (the repo IS
# the source of truth — no cache, no network fetch) and creates or updates
# every squad/agent defined here so that Multica always matches what's
# checked in.
#
# Features:
#   ✅ Idempotent   — safe to re-run any number of times (updates in place)
#   ✅ Local-first  — reads squad-instructions.md / agents/*.md from this repo
#   ✅ Placeholder resolution — <agent-name-uuid> replaced with real UUIDs
#   ✅ Dynamic runtime discovery — queried live at install time, never cached
#
# Usage:
#   bash install/setup.sh
#
#   # Optional: skip the runtime prompt by pinning a runtime explicitly
#   RUNTIME_ID="<runtime-uuid>" bash install/setup.sh
#
#   # Optional: override the HTTP timeout used for large instruction payloads
#   MULTICA_HTTP_TIMEOUT="180s" bash install/setup.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
export REPO_ROOT
export PATH="/home/linuxbrew/.linuxbrew/bin:$PATH"

# ── Load shared library ─────────────────────────────────────────────────────
source "${SCRIPT_DIR}/lib.sh"

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  build-multica — Idempotent Squad Setup                              ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

# ── Step 0: Resolve the runtime to run every agent on ───────────────────────
echo "🔧 Step 0: Resolving runtime..."
echo "──────────────────────────────────────────────────────────"
RUNTIME_ID="$(select_runtime)"
echo ""

# ── Step 1: Prime the agent + squad maps ────────────────────────────────────
echo "📡 Step 1: Pre-fetching workspace state..."
echo "──────────────────────────────────────────────────────────"
init_agent_map
init_squad_map
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# SQUAD 1: multica-v1 — Meta-Squad
# ═══════════════════════════════════════════════════════════════════════════
echo "📦 Squad 1/6: multica-v1 — Squad Creator & Modifier"
echo "──────────────────────────────────────────────────────────"

INSTR_LEADER_MV1=$(load_instruction "multica-v1" "agents/leader.md")
INSTR_LEADER_MV1=$(resolve_placeholders "$INSTR_LEADER_MV1" "multica-v1")

INSTR_ANALYST_MV1=$(load_instruction "multica-v1" "agents/analyst.md")
INSTR_ANALYST_MV1=$(resolve_placeholders "$INSTR_ANALYST_MV1" "multica-v1")

INSTR_SQUAD_MV1=$(load_instruction "multica-v1" "squad-instructions.md")
INSTR_SQUAD_MV1=$(resolve_placeholders "$INSTR_SQUAD_MV1" "multica-v1")

AGENT_MV1_LEADER=$(upsert_agent "multica-v1-leader" "$RUNTIME_ID" "Coordinator for squad creation squad" "$INSTR_LEADER_MV1")
AGENT_MV1_ANALYST=$(upsert_agent "multica-v1-analyst" "$RUNTIME_ID" "Technical interviewer — writes squad/agent configs" "$INSTR_ANALYST_MV1")

SQUAD_MV1_ID=$(upsert_squad "multica-v1" "$AGENT_MV1_LEADER" "Squad creator & modifier — Grill Me protocol for designing squads" "$INSTR_SQUAD_MV1")

if [[ -n "$SQUAD_MV1_ID" ]]; then
  upsert_squad_member "$SQUAD_MV1_ID" "$AGENT_MV1_ANALYST" "Analyst"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# SQUAD 2: exec-v1 — Daily Executive Check-In
# ═══════════════════════════════════════════════════════════════════════════
echo "📦 Squad 2/6: exec-v1 — Daily Executive Check-In"
echo "──────────────────────────────────────────────────────────"

INSTR_LEADER_EXEC=$(load_instruction "exec-v1" "agents/exec-leader-v1.md")
INSTR_LEADER_EXEC=$(resolve_placeholders "$INSTR_LEADER_EXEC" "exec-v1")

INSTR_SQUAD_EXEC=$(load_instruction "exec-v1" "squad-instructions.md")
INSTR_SQUAD_EXEC=$(resolve_placeholders "$INSTR_SQUAD_EXEC" "exec-v1")

AGENT_EXEC_LEADER=$(upsert_agent "exec-leader-v1" "$RUNTIME_ID" "Executive leader — daily briefings, on-demand execution, evening wraps" "$INSTR_LEADER_EXEC")
SQUAD_EXEC_ID=$(upsert_squad "exec-v1" "$AGENT_EXEC_LEADER" "Daily executive check-in squad (briefings, interactive help, wraps)" "$INSTR_SQUAD_EXEC")
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# SQUAD 3: design-v1 — Conversational Planning & Breakdown
# ═══════════════════════════════════════════════════════════════════════════
echo "📦 Squad 3/6: design-v1 — Conversational Planning & Breakdown"
echo "──────────────────────────────────────────────────────────"

INSTR_LEADER_DESIGN=$(load_instruction "design-v1" "agents/leader.md")
INSTR_LEADER_DESIGN=$(resolve_placeholders "$INSTR_LEADER_DESIGN" "design-v1")

INSTR_ANALYST_DESIGN=$(load_instruction "design-v1" "agents/analyst.md")
INSTR_ANALYST_DESIGN=$(resolve_placeholders "$INSTR_ANALYST_DESIGN" "design-v1")

INSTR_PLANNER_DESIGN=$(load_instruction "design-v1" "agents/planner.md")
INSTR_PLANNER_DESIGN=$(resolve_placeholders "$INSTR_PLANNER_DESIGN" "design-v1")

INSTR_SQUAD_DESIGN=$(load_instruction "design-v1" "squad-instructions.md")
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

INSTR_PM_BUILD=$(load_instruction "build-v3" "agents/build-pm-v3.md")
INSTR_PM_BUILD=$(resolve_placeholders "$INSTR_PM_BUILD" "build-v3")

INSTR_DEV_BUILD=$(load_instruction "build-v3" "agents/build-developer-v3.md")
INSTR_DEV_BUILD=$(resolve_placeholders "$INSTR_DEV_BUILD" "build-v3")

INSTR_VERIFIER_BUILD=$(load_instruction "build-v3" "agents/build-verifier-v3.md")
INSTR_VERIFIER_BUILD=$(resolve_placeholders "$INSTR_VERIFIER_BUILD" "build-v3")

INSTR_CLEANER_BUILD=$(load_instruction "build-v3" "agents/build-cleaner-v3.md")
INSTR_CLEANER_BUILD=$(resolve_placeholders "$INSTR_CLEANER_BUILD" "build-v3")

INSTR_COMMITER_BUILD=$(load_instruction "build-v3" "agents/build-commiter-v3.md")
INSTR_COMMITER_BUILD=$(resolve_placeholders "$INSTR_COMMITER_BUILD" "build-v3")

INSTR_SQUAD_BUILD=$(load_instruction "build-v3" "squad-instructions.md")
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

INSTR_LEADER_DOC=$(load_instruction "doc-v1" "agents/doc-leader-v1.md")
INSTR_LEADER_DOC=$(resolve_placeholders "$INSTR_LEADER_DOC" "doc-v1")

INSTR_AUDITOR_DOC=$(load_instruction "doc-v1" "agents/doc-auditor-v1.md")
INSTR_AUDITOR_DOC=$(resolve_placeholders "$INSTR_AUDITOR_DOC" "doc-v1")

INSTR_WRITER_DOC=$(load_instruction "doc-v1" "agents/doc-writer-v1.md")
INSTR_WRITER_DOC=$(resolve_placeholders "$INSTR_WRITER_DOC" "doc-v1")

INSTR_VERIFIER_DOC=$(load_instruction "doc-v1" "agents/doc-verifier-v1.md")
INSTR_VERIFIER_DOC=$(resolve_placeholders "$INSTR_VERIFIER_DOC" "doc-v1")

INSTR_SQUAD_DOC=$(load_instruction "doc-v1" "squad-instructions.md")
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

INSTR_LEADER_REVIEW=$(load_instruction "review-v1" "agents/review-leader-v1.md")
INSTR_LEADER_REVIEW=$(resolve_placeholders "$INSTR_LEADER_REVIEW" "review-v1")

INSTR_DESCRIBER_REVIEW=$(load_instruction "review-v1" "agents/review-describer-v1.md")
INSTR_DESCRIBER_REVIEW=$(resolve_placeholders "$INSTR_DESCRIBER_REVIEW" "review-v1")

INSTR_DEFENDER_REVIEW=$(load_instruction "review-v1" "agents/review-defender-v1.md")
INSTR_DEFENDER_REVIEW=$(resolve_placeholders "$INSTR_DEFENDER_REVIEW" "review-v1")

INSTR_CRITIQUER_REVIEW=$(load_instruction "review-v1" "agents/review-critiquer-v1.md")
INSTR_CRITIQUER_REVIEW=$(resolve_placeholders "$INSTR_CRITIQUER_REVIEW" "review-v1")

INSTR_RESOLVER_REVIEW=$(load_instruction "review-v1" "agents/review-conflict-resolver-v1.md")
INSTR_RESOLVER_REVIEW=$(resolve_placeholders "$INSTR_RESOLVER_REVIEW" "review-v1")

INSTR_SQUAD_REVIEW=$(load_instruction "review-v1" "squad-instructions.md")
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
