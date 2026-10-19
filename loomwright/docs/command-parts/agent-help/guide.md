## Daily Workflow Example

### Morning: Plan Your Work
```bash
cd /path/to/my-app
/orchestrator goal: "Add dark mode UI to settings page"
```
→ Agent creates task(s) per the Decomposition Threshold (default one task; a review-gate task is added only above the threshold — see `skills/supervisor-readiness/SKILL.md` §"Decomposition Threshold")

### Start Work: Claim Task
```bash
bd claim BD-21  # Claim the implementation task
```
→ Start working on the task

### During Work: Code & Review
```bash
# 1. Implement feature...

# 2. Review your code
/code-reviewer src/components/Settings.tsx
```
→ Agent flags issues and outputs PASS/FAIL/NEEDS_HUMAN

### Before Committing: Create Conventional Commits
```bash
git add src/components/Settings.tsx src/hooks/useDarkMode.ts
# Use commit skill for proper formatting
```
→ Commits linked to Beads tasks

### Complete Task: Close in Beads
```bash
bd close BD-21
```
→ Task marked complete, next task unblocked

---

## Common Scenarios

### Scenario 1: Fix a Bug
```
/orchestrator goal: "Fix login button not working on mobile"
→ Creates Beads tasks: BD-30 (fix), BD-31 (commit) — no per-subtask review task at any threshold (see agents/orchestrator.md §"Review Gate Policy")
→ bd claim BD-30, implement fix
→ Supervisor's Phase 4.5 integrated review is the gate (only when executed via `/supervisor`); hand-executing the plan? run `/code-reviewer` yourself first
→ Commit and bd close BD-31
```

### Scenario 2: Add a Feature
```
/orchestrator goal: "Add dark mode to application"
→ Creates EPIC — one task by default; splits only above the Decomposition Threshold. No per-subtask review task is ever generated (see Review Gate Policy)
→ Below threshold: BD-40: Implement → BD-41: Commit (Supervisor's Phase 4.5 integrated review is the gate, no per-task reviewer — **only when executed via `/supervisor`**; a plan you hand-execute has no Phase 4.5, so run `/code-reviewer` yourself before committing)
→ Above threshold (example): BD-40: Implement → BD-41: Tests → BD-42: Commit (same gate as below threshold — task-to-task dependencies only, no per-task reviewer)
→ bd close each task when done
```

### Scenario 3: Refactor Code
```
/orchestrator goal: "Refactor Settings component to use hooks"
→ Creates task(s) per the Decomposition Threshold — no per-subtask review task at any threshold (see Review Gate Policy)
→ /code-reviewer checks pattern consistency (or Supervisor's Phase 4.5 integrated review, when run via `/supervisor`)
→ Commit with Beads linking
```

### Scenario 4: Review Someone Else's Code
```
cd /path/to/pull-request-repo
/code-reviewer src/  # Review the changes
```
→ Agent flags issues and outputs PASS/FAIL/NEEDS_HUMAN

### Scenario 5: Pre-Launch Security Review
```
/red-team-reviewer --focus security
→ Red Team attacks auth, inputs, data exposure
→ Reports FATAL issues that must be fixed
→ Provides "what would convince hostile expert"
→ Prioritized fixes before launch
```

### Scenario 6: Stress-Test Before Scale
```
/red-team-reviewer src/api/ --focus scale,cost
→ Red Team attacks scalability, cost assumptions
→ Finds N+1 queries, unbounded operations
→ Reports what breaks at 10x/100x load
→ Prioritized fixes by real-world impact
```

---

## Key Concepts

### Agent Frontmatter (Native Configuration)

Every agent has YAML frontmatter that configures its behavior automatically:

| Setting | What It Does | Example |
|---------|-------------|---------|
| `name` | Agent identifier | `loomwright:supervisor-runner` |
| `tools` | Byte-identical superset allowlist across all 14 agents | Same line everywhere; per-agent restriction lives in `disallowedTools` |
| `disallowedTools` | The actual per-agent restriction | Workers can't spawn subagents (`Task` denied, though the superset declares it) |
| `model` | Sets model for the agent | Context-Keeper uses haiku (fast, cheap) |
| `maxTurns` | Limits API round-trips | Context-Keeper: 3 turns max |
| `memory: project` | Persistent memory across sessions | Code Reviewer remembers past patterns |
| `skills` | Pre-loads skill content | Code Reviewer gets quality-checklist pre-injected |

**Agent Model Assignments:**
| Agent | Model | Why |
|-------|-------|-----|
| Supervisor | inherit | Respects user's model choice (Sonnet+ recommended) |
| Context-Keeper | haiku | Simple state read/write |
| Worker | inherit | Matches user's choice |
| Code Reviewer | inherit | Matches user's choice + memory |
| Red Team Reviewer | inherit | Matches user's choice + memory |

Use `/supervisor --cheap` to override the execution-shaped roles (orchestrator, execute-manager, worker, code-reviewer, Phase 4.5 fix tasks, and — when `--multi-voter-heal` is ON — the multi-voter verification voters/refute spawn) to Sonnet at spawn time. See `docs/ARCHITECTURE_CONTRACTS.md` §"Cost Profiles" for the full profile table and Haiku-session caveat. Since v15.2.0, `/autonomous` and `/automate` also forward `--cheap` down the chain to every inlined `/supervisor` run.

**Agents with Persistent Memory:**
- Code Reviewer — remembers past review patterns, recurring issues
- Red Team Reviewer — remembers past vulnerabilities, attack patterns
- Product Owner — remembers domain context, terminology, stakeholder preferences

### Plugin Hooks (Quality Gates)

The plugin centralizes its hooks in `hooks/hooks.json`, which automatically enforce quality and surface notifications (`hooks.json` is authoritative for the wiring and the count; the authoritative table lives in `loomwright/docs/HOOKS.md` §"Hook Table"):

| Hook | When It Fires | What It Checks / Does |
|------|---------------|----------------|
| **SubagentStop** (worker, execute-manager, code-reviewer, supervisor-runner, qa-executor, plan-reviewer, launch-pad-runner) | The matching agent completes | Validates its result block (WORKER_RESULT, EXECUTE_*, CODE_REVIEW_RESULT v3, SUPERVISOR_RESULT, QA_RESULT, PLAN_REVIEW_RESULT, LAUNCH_PAD_RESULT). All of these are `type: command` validator scripts (five since v15.17.0; `code-reviewer`'s since the 2026-09-27 SubagentHandback probe). Plus 3 telemetry + 1 webhook + 1 progress-event `type: command` hooks |
| **PreToolUse (AskUserQuestion)** | Plugin about to block on a user question | Desktop banner (`notify-desktop.sh`) + paused-event webhook (v14.1.0) |
| **Notification** | Claude Code signals attention (permission / idle / elicitation) | Desktop banner (v14.1.0) |
| **PostToolUse (Bash)** | A Bash tool call completes (e.g. `gh pr create`) | Backstops the until-mergeable review drain on PR creation (`hook-dispatch-on-pr-create.sh`); session-scope gated, fail-safe (v14.34.0). PLUS a second entry (`reproject-state-on-terminal.sh`, PR #116 review round) that mechanically re-invokes `build-state.sh` once `session_end` lands in the session log. PLUS a third leaf on the existing Bash matcher (v15.66.0): the worktree observer `worktree-audit.sh record` — records worktrees added through the Bash tool in a repo the plugin has run in, and its read-only `report` lists the ones never seen removed that git still lists |
| **SessionStart** | Session resume / clear / compact | Injects bounded recovery context (`session-resume.sh`, v14.2.0); also maintains per-project OpenTelemetry resource attributes (`set-otel-resource-attrs.sh`, telemetry-gated, fail-safe, v14.47.0) |
| **Stop / TaskCompleted / StopFailure** | Various | Completeness gate, task-done check, failure logging (the `WorktreeCreate`/`WorktreeRemove` hooks were removed in v15.66.0) |

These hooks run automatically — no configuration needed. Most are `type: command` scripts that cost no model call; only one still uses prompt-based validation (haiku model, 30s timeout): `TaskCompleted`.

### Agent Teams (Experimental)

For research or exploration tasks, Claude Code Agent Teams provides native multi-agent coordination:

```bash
# Enable Agent Teams
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
```

**Best for:** Research across multiple areas, competing hypotheses, cross-layer changes.
**Not for:** Sequential tasks, same-file edits (use Supervisor v4 with git worktrees instead).

See `skills/agent-teams/SKILL.md` for full patterns and decision matrix.

### Project Context
Each agent automatically finds your project by looking for `CLAUDE.md`:
- Starts in current directory
- Searches parent directories
- Uses `/path/to/project` if you provide it

### Task Management
Task management supports two modes:

**With Beads (optional):**
- **`bd list`** — View open/in-progress/completed tasks
- **`bd claim BD-XX`** — Start working on a task
- **`bd close BD-XX`** — Mark task complete
- **`bd comment BD-XX "note"`** — Add notes to task

**Without Beads:**
- State tracked in `.supervisor/state.md` (auto-created)
- Task descriptions provided directly to Supervisor
- **CLAUDE.md** — Codebase knowledge, patterns (still user-maintained)

### Approval Workflow
- ✅ Code Reviews: Agent outputs PASS/FAIL/NEEDS_HUMAN
- ✅ CLAUDE.md Updates: Agent proposes, you approve
- ✅ Commits: Conventional format with Beads linking
- ✅ Pushes: Only with explicit request

---

## Tips & Tricks

### Tip 1: Use Agents Flexibly
You don't have to follow strict order. For example:
- Run `/code-reviewer` first to understand patterns before coding
- Run `/code-reviewer` multiple times during development
- Use `/red-team-reviewer` for adversarial audits before launch

### Tip 2: Combine with Git
```bash
# Review changes before code-reviewer
git diff src/

# See commits after /commit
git log --oneline -5

# Push after /commit
git push
```

### Tip 3: Multi-Project Workflows
```bash
# Work on project A
cd /path/to/project-a
/orchestrator goal: "Fix bug in A"

# Switch to project B
cd /path/to/project-b
/orchestrator goal: "Add feature to B"  # Auto-detects B's context
```

### Tip 4: Review Before Committing
```bash
# Code first
/code-reviewer src/

# Fix issues
/code-reviewer src/  # Re-review

# When satisfied, commit with Beads linking
git commit -m "feat(theme): add dark mode

Closes BD-21"
```

### Tip 5: Daily Routine
```bash
# Morning: Plan
/orchestrator goal: "Today's goal"

# Claim task
bd claim BD-XX

# During: Code and review
/code-reviewer (as needed)

# Complete: Close task
bd close BD-XX
```

---

## Files & Directories

### Plugin Files
```
.claude-plugin/
├── marketplace.json                  # Marketplace manifest (root)
└── README.md                         # Plugin-facing usage guide

loomwright/              # Nested plugin root
├── .claude-plugin/
│   └── plugin.json                   # Plugin metadata
├── commands/                         # Slash commands (23)
│   ├── launch-pad.md                 # Supervisor readiness
│   ├── supervisor.md                 # Parallel orchestrator (v4)
│   ├── autonomous.md                 # Continuous autonomous loop, stacked PRs (v14)
│   ├── automate.md                   # Generic automation engine — source → Queue → per-item loop (v14.41.0)
│   ├── product-owner.md              # Requirements definition
│   ├── orchestrator.md
│   ├── code-reviewer.md
│   ├── red-team-reviewer.md          # Adversarial auditor
│   ├── review-pr.md                  # Standalone PR review-and-heal loop (never auto-merges)
│   ├── qa-strategist.md              # Risk-based QA strategy
│   ├── qa-executor.md                # Automated QA testing
│   ├── verify.md                     # Walk a ticket through the running app (advisory)
│   ├── dreaming.md                   # Read-only reflection over session logs (proposes memory + CLAUDE.md updates)
│   ├── capability-check.md           # Read-only scan for new Claude Code capabilities vs tracked baseline
│   ├── insights.md                   # Local Obsidian-friendly insights dashboard from session logs
│   ├── obsidian.md                   # Read-only linked Obsidian vault projection (logs + Twin contracts + memory)
│   ├── pr-postmortem.md              # Read-only on-demand PR review-churn root-cause analyzer
│   ├── telemetry.md                  # Opt-in GitHub Issues telemetry (status/enable/disable/test)
│   ├── setup.md                      # Optional-capability dashboard + guided configuration (incl. observability)
│   └── agent-help.md
├── agents/                           # Agent implementations (14 roles)
│   ├── launch-pad.md                 # Supervisor readiness agent
│   ├── supervisor.md                 # Parallel orchestrator (v4)
│   ├── execute-manager.md            # Phase 3 execution manager
│   ├── context-keeper.md             # State management agent
│   ├── worker.md                     # Implementation worker
│   ├── plan-reviewer.md              # Brief validation gate
│   ├── rubric-grader.md              # Phase 4.5 read-only Haiku scorer (v12.2.0)
│   ├── product-owner.md              # Requirements definition
│   ├── orchestrator.md
│   ├── code-reviewer.md
│   ├── red-team-reviewer.md
│   ├── review-pr.md                  # Standalone PR review-and-heal runner
│   ├── qa-strategist.md
│   └── qa-executor.md
├── hooks/                            # Plugin quality gate hooks
│   └── hooks.json                    # SubagentStop + TaskCompleted validation
├── docs/                             # Architecture + schemas
│   ├── RESULT_SCHEMAS.md
│   ├── FAILURE_ESCALATION.md
│   ├── ARCHITECTURE_CONTRACTS.md
│   ├── ARCHITECTURE.md
│   ├── QA_SYSTEM_BLUEPRINT.md
│   └── SPIKES/                       # Capability spike investigations + deferral records
└── skills/                           # Skill files (42 skills; 18 tech-stack skills moved to stackpack@atelier)
    ├── SKILLS_INDEX.md               # Skill catalog with agent mapping
    ├── supervisor-readiness/         # Pre-flight checklist & brief template
    ├── agent-teams/                  # Agent Teams patterns (experimental)
    ├── async-orchestration/          # Parallel dispatch patterns
    ├── state-management/             # State file schema
    ├── workflow-management/          # Supervisor workflow patterns
    ├── context-summarization/
    ├── commit/
    ├── quality-checklist/
    ├── error-handling/
    ├── unit-testing/
    └── ...                           # (tech-stack skills: stackpack@atelier)
```

### Project Files
```
your-project/
├── CLAUDE.md                # Codebase knowledge, patterns
├── .supervisor/             # Supervisor state (auto-created, gitignored)
│   ├── state.md             # Current session state
│   ├── history/             # Completed session summaries
│   └── jobs/                # Supervisor-Ready Briefs from Launch Pad
└── .beads/                  # Beads issue tracker (optional)
    ├── issues/              # Issue files
    └── ...
```

---

## Getting Help

### Need Help with a Specific Agent?
```
/supervisor --help         # Help for Supervisor (autonomous workflow)
/orchestrator --help       # Help for Orchestrator
/code-reviewer --help      # Help for Code Reviewer
/red-team-reviewer --help  # Help for Red Team Reviewer
```

### Questions About the Plugin?
Check the plugin README:
```
cat /path/to/loomwright/.claude-plugin/README.md
```

### Issues or Suggestions?
Contribute to the Loomwright project:
```
https://github.com/your-org/loomwright
```

---

## Keyboard Shortcuts

These are Claude Code slash commands, so you can type them directly:
- Type `/launch` + Tab → Auto-completes to `/launch-pad`
- Type `/super` + Tab → Auto-completes to `/supervisor`
- Type `/orchestr` + Tab → Auto-completes to `/orchestrator`
- Type `/code-r` + Tab → Auto-completes to `/code-reviewer`
- Type `/red-t` + Tab → Auto-completes to `/red-team-reviewer`
- Type `/comm` + Tab → Auto-completes to `/commit`

---

## Summary

### Readiness Pipeline (Prepare for Autonomous Execution)

| Agent | Purpose | When | Input | Output |
|-------|---------|------|-------|--------|
| **Launch Pad** | Supervisor readiness | Complex tasks, plan review | Raw goal + codebase | Supervisor-Ready Brief in `.supervisor/jobs/pending/` |

### Autonomous Workflow (End-to-End Automation — 4 Roles)

| Agent | Purpose | When | Input | Output |
|-------|---------|------|-------|--------|
| **Supervisor** | Parallel orchestration | Autonomous task completion | Task description or Launch Pad brief | Completed tasks with PRs |
| **Execute Manager** | Phase 3 execution | Delegated by Supervisor | Brief pointer + subtask index + config | EXECUTE_RESULT / EXECUTE_CHECKPOINT |
| **Context-Keeper** | State management | On-demand (Supervisor/EM calls) | State operations | State file updates |
| **Worker** | Implementation | Background (parallel) | Subtask + worktree path | WORKER_RESULT + .worker-summary.md |

### Requirements Pipeline (Define What to Build)

| Agent | Purpose | When | Input | Output |
|-------|---------|------|-------|--------|
| **Product Owner** | Define requirements | New feature, vague requirements | Feature/problem | User stories with acceptance criteria |

### Constructive Pipeline (Build Correctly)

| Agent | Purpose | When | Input | Output |
|-------|---------|------|-------|--------|
| **Orchestrator** | Plan work | Start of task | Goal or story | Beads tasks, default one task, no per-subtask review gate at any threshold |
| **Code Reviewer** | Review code | During development | Files/diff | PASS/FAIL/NEEDS_HUMAN + issues |
| **/commit** (skill) | Create commits | When done coding | Staged changes | Conventional commits + Beads links |

### Independent Auditor (Break Safely)

| Agent | Purpose | When | Input | Output |
|-------|---------|------|-------|--------|
| **Red Team Reviewer** | Attack work | Pre-launch, security review | Target scope | Fatal issues + fixes |

### QA Pipeline (Test Automatically)

| Agent | Purpose | When | Input | Output |
|-------|---------|------|-------|--------|
| **QA Strategist** | Plan test strategy | Before QA, or audit after | Source code or .qa-summary.md | Risk classification + STRATEGIST_VERDICT |
| **QA Executor** | Run automated QA | After implementation | Running app + Playwright config | QA_RESULT + test files |

---

**Ready to get started?**
- Prepare for execution: `/launch-pad goal: "your goal here"` (codebase analysis, brief, clean handoff)
- Autonomous workflow: `/supervisor` (picks up tasks, runs agents, creates PRs)
- Plan-first workflow: `/launch-pad` → `/supervisor job: .supervisor/jobs/pending/{brief}.md`
- Define requirements: `/product-owner feature: "your feature here"`
- Plan work: `/orchestrator goal: "your goal here"`
- Review code: `/code-reviewer src/`
- Attack work: `/red-team-reviewer` (adversarial audit)
