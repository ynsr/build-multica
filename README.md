# Multica Agent Workspace

This repository serves as the central configuration, design, and instruction hub for managing **Multica** agents, squads, and workflows. Using Multica's declarative, markdown-based message-passing routing, these specialized squads collaborate autonomously to plan, design, implement, document, and review software engineering projects.

* each folder is the name of a squad
* create the agents in each squad folder
* then create the squads with the instructions
* the leader agent for each squad is named as such

---

## 🚀 How It Works: Declarative Routing

Rather than relying on complex runtime orchestration libraries, Multica squads utilize a standard message-passing protocol. Agents pass execution control to one another by posting a comment containing an explicit, URI-formatted Markdown mention:

```text
[@AgentName](mention://agent/<agent-uuid>)
```

When the Multica parser detects this mention format, it halts the current agent's execution, enqueues the target agent with the conversation's comment history, and seamlessly transitions control.

---

## 👥 The Agent Squads

The workspace is organized into six highly specialized squads. Each directory contains a `squad-instructions.md` routing guide and an `agents/` subdirectory defining the roles, permissions, and behaviors of its members.

### 1. `exec-v1` — Daily Executive Check-In Squad
The executive squad is designed to bridge the gap between human workspace owners and automated development pipelines, providing daily touchpoints and on-demand technical assistance.
*   **Directory**: `exec-v1/`
*   **Squad Members**:
    *   **`exec-leader-v1` (Primary)**: Possesses full execution privileges (`bash: allow`, `edit: allow`, `write: allow`) to act as a powerful co-pilot.
*   **Core Workflow**:
    *   **Morning Briefing**: Triggers daily at **6:00 AM** to scan active project boards and compile a high-level executive summary:
        *   *Active Priorities*: What's on deck across squads today.
        *   *Progress Highlights*: Completed features and merges from yesterday.
        *   *Blockers & Key Decisions*: Items requiring immediate human input.
        *   *Daily TODOs*: A rolling checklist carried forward day-to-day.
    *   **Interactive Assistance**: Remains available during active chats to perform technical tasks upon command (e.g., "Run the latest build", "Analyze test failures on task X", "Draft a design for feature Y").
    *   **Evening Wrap**: Summarizes today's progress and proposes tomorrow's objectives before closing the daily loop.

### 2. `build-v3` — Adaptive Project Management & Execution
A comprehensive software development squad that merges continuous agile project management with autonomous code generation and QA.
*   **Directory**: `build-v3/`
*   **Squad Members**:
    *   **`build-pm-v3` (Primary / Leader)**: Monitors project boards, prioritizes tasks hourly, and delegates work.
    *   **`build-developer-v3` (Primary)**: Researches the codebase, implements code changes, and writes robust tests.
    *   **`build-verifier-v3` (Primary)**: Compiles the codebase, executes test suites, and audits test coverage.
*   **Core Workflow**: The PM prioritizes open backlog issues, routes ready steps to the Developer, hands off completed implementations to the Verifier, and presents verified deliverables to the human user for final sign-off.

### 3. `multica-v1` — Squad Creator & Modifier
The meta-squad responsible for technical interviewing and directly writing the workspace's agent configurations.
*   **Directory**: `multica-v1/`
*   **Squad Members**:
    *   **`leader` (Primary)**: Acts as the entry-point coordinator and user facilitator.
    *   **`analyst` (Primary)**: Technical interviewer conducting requirements gathering.
*   **Core Workflow**: When a new squad or agent edit is proposed, the Analyst conducts the **"Grill Me" protocol** to design the state machine and roster, and then directly writes the markdown configuration files upon user approval.

### 4. `design-v1` — Conversational Planning & Breakdown
A dedicated design squad that aligns user requirements and produces detailed, implementation-ready execution backlogs before any coding begins.
*   **Directory**: `design-v1/`
*   **Squad Members**:
    *   **`leader` (Primary)**: Directs transitions and manages human design approvals.
    *   **`analyst` (Primary)**: Gathers requirements and designs the high-level system architecture.
    *   **`planner` (Primary)**: Decomposes approved designs into fine-grained step files.
*   **Core Workflow**: Gathers requirements $\rightarrow$ generates a unified `design.md` $\rightarrow$ halts for human design approval $\rightarrow$ decomposes the approved design into chronological, atomic step-files in `steps/*.md`.

### 5. `doc-v1` — Documentation Backfill Squad
Focuses on technical writing, gap analysis, and keeping codebase reference documentation fresh and technically accurate.
*   **Directory**: `doc-v1/`
*   **Squad Members**:
    *   **`doc-leader-v1` (Primary)**: Entry intake and final deliverable presentation.
    *   **`doc-auditor-v1` (Primary)**: Explores codebases to find missing documentation gaps.
    *   **`doc-writer-v1` (Primary)**: Drafts and updates markdown documentation files.
    *   **`doc-verifier-v1` (Primary)**: Audits written documentation for formatting and accuracy.

### 6. `review-v1` — PR Analysis & Defense Squad
An advanced review squad that assists developers during the pull request phase, handling explanations, reviews, and conflict resolution.
*   **Directory**: `review-v1/`
*   **Squad Members**:
    *   **`review-leader-v1` (Primary)**: Coordinates PR checks and presents recommendations.
    *   **`review-describer-v1` (Primary)**: Generates detailed PR descriptions and reviewer guides from git diffs.
    *   **`review-defender-v1` (Primary)**: Responds to code reviewer feedback and comments collaboratively.
    *   **`review-critiquer-v1` (Primary)**: Plays devil's advocate to identify potential edge cases in PR revisions.
    *   **`review-conflict-resolver-v1` (Primary)**: Recommends precise resolutions for git merge conflicts.

---

## 🔒 Security & Permissions Model

To ensure security and prevent accidental modifications, agents are governed by a strict permissions frontmatter block:

```yaml
---
permission:
  bash: allow | ask | deny
  edit: allow | ask | deny
  write: allow | ask | deny
---
```

*   **Design-focused agents** (Analysts, Planners) are typically granted `bash: allow` (for directory reading), `edit: deny/ask` (to prevent codebase mutation), and `write: allow` (to write new markdown design artifacts).
*   **Implementation-focused agents** (Developers, Executives) are typically granted `edit: allow` or `edit: ask` to safely implement requested changes in codebase files.
