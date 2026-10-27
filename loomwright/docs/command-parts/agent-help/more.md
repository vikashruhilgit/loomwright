### 🧩 /setup — Optional-Capability Dashboard & Guided Configuration

**Purpose:** Single entry point for checking and configuring every optional plugin capability — one module per row of the `setup` skill's module registry (`/setup --help` prints them all) — **observability** (local Langfuse v3 + bundled OTel collector; `init | status | remove`), **telemetry** (delegates to `/telemetry`), **notifications**, **webhook**, **Beads**, **MySQL MCP**, **rules** (`status | (no-arg → seed)`; `remove` is N/A — retracting a rule is `/rules` territory, not a module teardown — seeds a cold-start repo's `.agent/rules/` store with a small set of **portable** conventions, stamped `provenance.source=setup:rules-seed` so a shipped default is never mistaken for something the tool learned here; every seed is repo-wide with `check: null`, rules stay DATA and advisory, and the module adds **no gate**), **statusline** (`status | apply | remove` — wires the one-line run report (phase · branch · N/M subtasks · age of the last event) into the user-scope settings document; backup-first, parse-gated, byte-compare idempotent, and the **only** module that writes user-scope settings from a script. A `statusLine` this plugin did not write is **preserved and reported**, never overwritten — replacing it takes an explicit flag and the previous value is recorded so `remove` restores it verbatim. The line carries **no active-agent field**: there is no spawn event in any log to read, so inferring liveness from another record's recency would be a guess, and it is omitted rather than guessed), **base-branch** (`status | set <branch> | remove` — views and pins the base (integration) branch in `.supervisor/config.json` `.base_branch`, the value `resolve-base-branch.sh` reads before origin/HEAD; backup-first, parse-gated, and every other key preserved), and **memory** (`status | apply | remove | migrate` — puts `.claude/agent-memory/` + `.supervisor/memory/` + the findings ledger `.supervisor/postmortem/results.jsonl` under version control IN PLACE via gitignore negation, plus the repo allowlist; consent-bearing, and `remove` states plainly that git history retains anything already pushed). **The ledger is the third store and it is GATED**: it is structurally cross-repo (a postmortem append lands in the CURRENT working `.supervisor/`, not the analysed repo's), so `apply` fails CLOSED — it withholds the ledger negation, names the offending repo slugs and reports the third verdict `gated` whenever any record's `.repo` is outside the repo allowlist, while still exiting 0. No-arg invocation prints a status dashboard (one real check per module) then offers configuration via multi-select. Every module follows the same contract: check → report → offer → apply → verify — idempotent, never blind-overwrite (settings.json changes are jq-deep-merged with a timestamped backup, aborting on parse failure; the memory module's `.gitignore` block is backup-first, atomic, and ABORTS without writing on an unparseable file).

**Usage:**
```
/setup                      # status dashboard + multi-select configuration
/setup observability        # observability module directly: init | status | remove
/setup rules                # seed a cold-start .agent/rules/ store (status = read-only report)
/setup memory               # memory stores in version control: status | apply | remove | migrate
/setup telemetry            # delegates to /telemetry
/setup base-branch          # base branch: status | set <branch> | remove
/setup --help               # every module + subcommands (also -h, help)
```

**Learn More:** see `loomwright/commands/setup.md` and the `setup` skill (the module-contract authority); the observability architecture reference is `loomwright/docs/OBSERVABILITY.md`

---

### 🩺 /review-pr — Standalone PR Review-and-Heal

**Purpose:** Run the bounded review→fix→re-review loop against an *existing* PR URL — decoupled from a full Supervisor run, so any open PR (human- or agent-authored) can be reviewed and auto-healed in place. Resolves the PR's head branch (`gh pr view --json headRefName`), checks it out, then orchestrates a `code-reviewer` pass + a `general-purpose` fix worker (default 3 iterations) until the diff is clean (`PASS`) or escalates (`ESCALATED`). Pushes fixes (never `--force`); **never auto-merges** — the PR is always left open for a human, and `NEEDS_HUMAN` stops + notifies + posts findings to the PR.

> **Inline main-thread command.** `/review-pr` runs inline; the `loomwright:review-pr-runner` agent is for `claude --agent` agent-owned sessions and is NEVER `Task`-spawned (AC9 — it spawns its own `code-reviewer` + fix-worker children; Claude Code now allows that nesting, so the rule is retained pending owner review — `docs/ARCHITECTURE_CONTRACTS.md` §"Subagent nesting"). Plain `/supervisor` can optionally auto-dispatch it from the completion tail (`--auto-review` / `--no-auto-review`, off by default); `/autonomous` chains it as a Task step in EVALUATE.

**Usage:**
```bash
/review-pr <pr-url>                                                       # review-and-heal an existing PR
```

**Learn More:** see `loomwright/commands/review-pr.md` for the workflow and the `REVIEW_HEAL_RESULT` output; the loop contract lives in `loomwright/skills/review-heal/SKILL.md`.

---

### QA Workflow Diagram

```
/qa-strategist src/ → Risk Classification + Coverage Targets
    ↓
/qa-executor → Discovery → Tests → Execute → Coverage → Bugs
    ↓
/qa-strategist --audit .qa-summary.md → STRATEGIST_VERDICT
    ↓
approved: QA complete | rejected: re-run with gaps addressed
```

---

