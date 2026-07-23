# Build Multica — Orientation & Documentation Index

Welcome! This workspace contains the official squad and agent definitions for **Multica** (https://multica.ai/). These configurations govern how agents coordinate, specialize, and collaborate with the user.

---

## How to Use This Documentation

This folder follows the **Progressive Disclosure** principles of the `agent_docs` framework. Start here, and read only the detail files relevant to your task:

| File | What it covers | Read when… |
|------|---------------|------------|
| **This file** | Workspace overview, squad structures, and file maps | Always — start here |
| [`squad_coordination.md`](../02_patterns/squad_coordination.md) | Standard design of multi-agent message-passing routing patterns | Modifying agent hand-offs or adding new squad roles |
| [`squad_permissions.md`](../02_patterns/squad_permissions.md) | Guidelines for YAML frontmatter and permission settings | Adjusting agent access or security boundaries |
| [`conversational_planning.md`](../03_deep_dives/conversational_planning.md) | Deep dive walk-through of the conversational design and breakdown workflow | Optimizing requirements gathering or step breakdown heuristics |

---

## Workspace Squads

> **Note**: This overview currently documents `design-v1` in depth as a reference example. See the root [`README.md`](../../README.md) for the full, up-to-date roster of all squads in this workspace (`exec-v1`, `build-v3`, `multica-v1`, `design-v1`, `doc-v1`, `review-v1`).

### `design-v1` (The Conversational Brainstorming & Design Squad)
- **Phase**: Requirements Gathering, Brainstorming, and Task Decomposition.
- **Mission**: Engage the human user in deep conversation to define high-level goals, design the architecture, and produce structured `steps/*.md` backlogs, without writing any application code.
- **Roles**:
  - **Leader** (`design-v1/agents/design-leader.md`): Facilitator and coordinator of the design process.
  - **Analyst** (`design-v1/agents/design-analyst.md`): Researches codebase patterns and interviews the user via a comprehensive, efficient questioning protocol to draft a high-level `design.md`.
  - **Breakdown Planner** (`design-v1/agents/design-planner.md`): Decomposes approved high-level designs into fine-grained, dependency-ordered, actionable implementation step files in `steps/*.md`.

---

## Workspace Structure

```text
build-multica/
├── agent_docs/                 ← Standardized documentation & planning outputs
│   ├── 01_orientation/         ← Workspace and architectural overview
│   ├── 02_patterns/            ← Reusable design and security patterns
│   ├── 03_deep_dives/          ← Intricate walkthroughs of core complex flows
│   └── 04_plans/               ← Historical and active feature designs
│       └── design-squad/       ← Planning files for the creation of `design-v1`
└── design-v1/                  ← Configuration and instructions for the design/brainstorming squad
    ├── squad-instructions.md
    └── agents/
```

---

## Key Operating Guidelines

1. **Human-in-the-Loop Sign-off**: Across all squads, final design approvals and execution milestones require explicit approval from the Human Participant.
2. **Read-Analyze-Explain-Propose-HALT!**: All implementation agents must follow this rigorous protocol to ensure the user retains complete control over code modifications.
3. **Living Documentation**: Designs, backlogs, and patterns must be updated in real-time as tasks progress.
