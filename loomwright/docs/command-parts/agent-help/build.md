### 0️⃣ /product-owner — Define Requirements

**Purpose:** Translate business problems into user stories with acceptance criteria

**Usage:**
```
/product-owner feature: "staff scheduling for venue events"
/product-owner problem: "we keep double-booking shifts"
/product-owner feature: "order history" --mvp-only
/product-owner problem: "low retention" --brainstorm
/product-owner feature: "new pricing model" --brainstorm deep
```

**What it does:**
- Reads domain context from CLAUDE.md
- **Runs Assumption Check (standard flow)** — grounded feasibility against codebase (domain entities, architecture alignment, prerequisites). If flags exist, asks user confirmation before `bd create` (Proceed/Refine/Abort)
- Runs multi-mind brainstorm (5 expert lenses) when `--brainstorm` flag is used — generates options, debates, scores, and recommends a winner before writing stories
- **Runs Reality Check (brainstorm flow)** — for top 2-3 scored ideas, grounded codebase validation with VIABLE/NEEDS_FOUNDATION/BLOCKED verdicts. Caps Feasibility scores (NEEDS_FOUNDATION ≤ 5, BLOCKED ≤ 2), re-ranks before recommendation
- Runs product discovery to understand the problem
- Writes user stories (As a... I want... So that...)
- Defines acceptance criteria (Given/When/Then)
- Prioritizes scope (MVP / Phase 2 / Nice-to-have)
- Creates Beads stories (type: story)
- Provides handoff to `/orchestrator`

**Example Output:**
```
## BD-15: Staff Shift Assignment (type: story)

**As a** Staff Supervisor at a sports venue,
**I want** to assign staff members to shifts,
**so that** I have adequate coverage.

### Acceptance Criteria
- [ ] Given an event, when I open assignment, then I see available staff
- [ ] Given a conflict, when I double-book, then I see a warning

### Priority: MVP
### Handoff: /orchestrator goal: "BD-15"
```

**When to Use:**
- Starting a new feature
- When requirements are vague
- Before running /orchestrator
- When you need user stories
- When exploring multiple directions (`--brainstorm`) before committing to one

**Learn More:** `/product-owner --help`

---

### 1️⃣ /orchestrator — Plan Your Work

**Purpose:** Break a goal into minimal, actionable tasks

**Usage:**
```
/orchestrator goal: "add dark mode to UI"
/orchestrator goal: "fix login bug" --project /path/to/project
```

**What it does:**
- Understands your goal
- Reads project context (CLAUDE.md, Beads issue tracker state)
- Defaults to one Beads task per `skills/supervisor-readiness/SKILL.md` §"Decomposition Threshold" (split only for a named reason); applies the Review Gate Policy
- No per-subtask review subtask is generated at any threshold — the deterministic `outputs_verified`/tests-lint gate plus Supervisor's Phase 4.5 integrated review is the gate throughout (see `agents/orchestrator.md` §"Review Gate Policy")
- Identifies dependencies (task-to-task only — no review subtask ever blocks the next task)
- Provides clear acceptance criteria and skill references

**Example Output:**
- BD-20: Dark Mode Toggle (EPIC)
- BD-21: Implement dark mode toggle (TASK)
- BD-22: Add tests (TASK)
- BD-23: Commit & Link (TASK)

**When to Use:**
- Start of new work
- When goal is unclear or large
- When you need task breakdown
- When planning feature work

**Learn More:** `/orchestrator --help`

---

### 2️⃣ /code-reviewer — Review Code Changes

**Purpose:** Review code against patterns, flag issues, detect new patterns

**Usage:**
```
/code-reviewer                              # Review git changes
/code-reviewer src/components/Dark.tsx      # Review specific file
/code-reviewer src/components/              # Review folder
/code-reviewer --project /path/to/project   # Auto-detect files
```

**What it does:**
- Reads project patterns (CLAUDE.md)
- Reviews your code for:
  - Type safety issues
  - Security problems
  - Performance issues
  - Pattern violations
  - Test coverage
- Flags issues with severity (HIGH, MEDIUM, LOW)
- Detects new patterns worth documenting
- Provides specific fixes

**Example Feedback:**
- ✅ Good: 87% test coverage (above 80% threshold)
- ⚠️ HIGH: Missing type annotation on theme parameter
- 📋 PATTERN: New dark mode pattern detected, ready for CLAUDE.md

**When to Use:**
- After writing code
- Before committing
- To learn project patterns
- To catch bugs early

**Learn More:** `/code-reviewer --help`

---

### 3️⃣ /commit — Create Commits

**Purpose:** Stage changes and create conventional commit messages with Beads linking

**Usage:**
```
/commit                          # Stage and commit with Beads linking
```

**What it does:**
- Groups changes into logical commits
- Writes conventional commit messages (feat, fix, test, etc)
- Links commits to Beads tasks (`Closes BD-XX`)
- Verifies repo cleanliness (no debug code, secrets, etc)

**Example Commits:**
```
feat(theme): add dark mode toggle to Settings

Closes BD-46

test(theme): add dark mode tests (89% coverage)
security(hooks): validate localStorage input
```

**When to Use:**
- When you're done coding (after code review)
- At the end of each task
- When you want to organize commits

---

### 4️⃣ /red-team-reviewer — Attack Your Work (Adversarial)

**Purpose:** Break, stress-test, and ruthlessly critique work under real-world conditions

**Usage:**
```
/red-team-reviewer                              # Attack entire project
/red-team-reviewer src/auth/                    # Attack specific directory
/red-team-reviewer --focus security             # Focus on security
/red-team-reviewer src/api/ --focus cost,scale  # Focus on cost and scale
```

**What it does:**
- Identifies attack surface (entry points, trust boundaries, assumptions)
- Reality-checks claims using Context7 MCP against current docs
- Explores 6 attack vectors:
  - Core flaws & blind spots
  - Real-world operational failures
  - Security, abuse & misuse
  - Scalability & reliability
  - Human & organizational failures
  - Integration & ecosystem
- Reports findings by severity (FATAL, CRITICAL, WARNING, WEAKNESS)
- Provides: Top 3 fatal issues + what convinces hostile expert + prioritized fixes
- Asks if you want findings saved to file

**Example Output:**
- FATAL: JWT algorithm confusion — attacker bypasses auth with alg:none
- CRITICAL: No rate limiting — one user can DoS the system
- Top 3 Fatal Issues + What Would Convince Hostile Expert
- Prioritized Fixes by real-world impact

**Severity Levels:**
| Level | Meaning |
|-------|---------|
| **FATAL** | Production will fail. Showstopper. |
| **CRITICAL** | Serious pain coming. Not death, but bad. |
| **WARNING** | Future pain. Tech debt with teeth. |
| **WEAKNESS** | Exploitable attack surface exists. |

**When to Use:**
- Before production launches
- After major features
- Security reviews
- Architecture decisions
- When you need brutal honesty (not encouragement)

**When NOT to Use:**
- Regular code changes → Use `/code-reviewer` instead
- Quick pattern checks → Use `/code-reviewer` instead
- Learning codebase conventions → Use `/code-reviewer` instead
- When you want constructive feedback → Use `/code-reviewer` instead

**Key Difference from Code Reviewer:**
| Code Reviewer | Red Team Reviewer |
|---------------|-------------------|
| Constructive | Adversarial |
| Follow patterns | Attack assumptions |
| Helpful tone | Blunt, unsentimental |
| Part of workflow | Independent audit |

**Learn More:** `/red-team-reviewer --help`

---

