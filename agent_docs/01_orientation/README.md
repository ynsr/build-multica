# Build Multica — Orientation & Documentation Index

Welcome! This workspace contains the official squad and agent definitions for **Multica** (https://multica.ai/). These configurations govern how agents coordinate, specialize, and collaborate with the user.

---

## Workspace Squads

This workspace contains two distinct squads, each tailored to a specific phase of the product lifecycle:

### 1. `build-v1` (The Development Squad)
- **Phase**: Implementation & Testing.
- **Mission**: Move highly specified designs into production.
- **Roles**:
  - **Boss**: Orchestrates routing and workflow.
  - **Architect**: Translates requirements into technical designs.
  - **Developer**: Implements clean application code.
  - **Tester**: Writes robust unit tests.
  - **Lead Engineer**: Resolves developer/tester deadlocks.
  - **Stakeholder**: Performs final verification and approvals.
  - **Sweeper**: Keeps the Git workspace and ignore lists clean.

### 2. `design-v1` (The Conversational Brainstorming & Design Squad)
- **Phase**: Requirements Gathering, Brainstorming, and Task Decomposition.
- **Mission**: Engage the human user in deep conversation to define high-level goals, design the architecture, and produce structured `steps/*.md` backlogs, without writing any application code.
- **Roles**:
  - **Leader** (`design-v1/agents/leader.md`): Facilitator and coordinator of the design process.
  - **Analyst** (`design-v1/agents/analyst.md`): Researches codebase patterns and interviews the user via a comprehensive, efficient questioning protocol to draft a high-level `design.md`.
  - **Breakdown Planner** (`design-v1/agents/planner.md`): Decomposes approved high-level designs into fine-grained, dependency-ordered, actionable implementation step files in `steps/*.md`.

---

## Workspace Structure

```text
build-multica/
├── agent_docs/                 ← Standardized documentation & planning outputs
│   ├── 01_orientation/         ← Workspace and architectural overview
│   └── 04_plans/               ← Historical and active feature designs
│       └── design-squad/       ← Planning files for the creation of `design-v1`
├── build-v1/                   ← Configuration and instructions for the development squad
│   ├── squad-instructions.md
│   └── agents/
└── design-v1/                  ← Configuration and instructions for the design/brainstorming squad
    ├── squad-instructions.md
    └── agents/
```

---

## Key Operating Guidelines

1. **Human-in-the-Loop Sign-off**: In both squads, final design approvals and execution milestones require explicit approval from the Human Participant.
2. **Read-Analyze-Explain-Propose-HALT!**: All implementation agents must follow this rigorous protocol to ensure the user retains complete control over code modifications.
3. **Living Documentation**: Designs, backlogs, and patterns must be updated in real-time as tasks progress.
