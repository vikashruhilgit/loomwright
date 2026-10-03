# Supervisor Job: `/dreaming` triages accumulated knowledge into rules and delivers them as a PR

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** dirty (1 file — `.supervisor/postmortem/results.jsonl`, the engine-native learning line the previous `/automate` tick emitted; committed store, unrelated to this work), branch: main @ 97e721d == origin/main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 2 (dirty ledger line above; 7 pre-existing worktrees from earlier runs — none on this item's base)
- **Source requirement:** `.supervisor/requirements/twin-loop/05-dreaming-triage-to-pr.md`

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2 + jq, the same substrate every sibling writer/reader already uses |
| 2 | Dependency Availability | GO | every consumed surface exists and was read this session: `add-rule.sh` (690L), `read-rules.sh` (524L), `write-agent-memory.sh` (948L), `curation-status.sh` (1019L), `measure-heal-signal.sh` (113L), `.supervisor/postmortem/results.jsonl` (85 records) |
| 3 | Architecture Fit | GO | reuses the sole-writer + confirm-gate + advisory-reader architecture items 01–04b established; adds no new gate |
| 4 | Scope vs Supervisor Capability | CAUTION | exceeds the single-subtask default on the `context-bound` predicate (> 12 files AND > 800 lines) — split into 4 sequential subtasks, see `## Configuration` |
| 5 | Hard Blockers | GO | no credentials, no migration framework, no missing module. `gh` is authenticated and the PR-delivery path is `gh pr create` only |

**Overall Verdict:** CAUTION (scope) — proceeding with a 4-subtask split.

## Task
**Goal:** Make `/dreaming` the distiller — triage ledger `convention_mismatch` findings and pending agent-memory proposals into three destinations, deliver `.agent/rules/` changes as a pull request rather than an in-place write, seed portable rules on a cold-start repo via `/setup rules`, and record a re-runnable baseline so "the rules worked" and "the rules were ignored" stop being indistinguishable.

**Problem Statement:**
The plugin has been recording convention violations for months and never converting them into conventions. Measured on the live ledger **today** (not quoted from the requirement — see `### Measured corrections` below): 85 records, 226 findings, **107 `convention_mismatch` (47%)**, and **60 of 95 self-heal misses (63%)** — the single largest class in both columns, with 29 of those 107 made at the **worker** stage, before review ever sees the code. Meanwhile `.agent/rules/` holds **one** rule. A convention is not a code-structure fact: neither LSP nor a code graph can represent one, so only a conventions store can, and it must reach the DO side. Success looks like a reviewable, deduplicated, path-scoped rule batch delivered as a PR, plus a recorded baseline that can falsify this queue's own premise.

### Measured corrections to the requirement (verified this session — do NOT plan against the requirement's numbers)

These three findings OVERRULE the requirement's own wording. Each was measured against the running system, and each was **independently reproduced by Plan Review** before being relied on.

> **Provenance of the figures, stated so none of them is immortalised unre-verified.** Plan Reviewer is structurally read-only (no Bash), so it could corroborate the load-bearing **107** by string-matching the ledger, but could *not* re-derive the two jq-aggregated figures. Those — **60 of 95** self-heal misses, and **84 of 85** records carrying `agent_generated_guess: true` — were measured by the main thread with jq twice this session and reproduced identically both times. Even so, AC11's `--distribution` mode is the instrument of record: **the worker MUST re-derive all of these from it before writing any of them into `RULES_BASELINE.md`**, rather than copying them out of this brief.

1. **The own-repo / all-repo distinction is MOOT.** The requirement's AC says "104 own-repo, 107 including the work repo — use the own-repo set". Item **01c** already filtered the ledger's 7 foreign records at write time and shipped a committed gate that keeps them out. Measured now: **43 `vikashruhilgit/loomwright` + 42 `vikashruhilgit/ai-agent-manager`, zero foreign**. There is no "own-repo subset" to select any more; the corpus IS the own-repo set, and it is **107**, full stop. **Do not implement a repo filter that assumes contamination.** Follow item 01c's own CI lesson instead — a check asserting a property of committed data must take its expectation from committed source, so the harvester reads the ledger as-is and **NAMES** any out-of-allowlist `.repo` it encounters (advisory cross-check) rather than silently dropping records.
2. **`measure-heal-signal.sh` does NOT compute the distribution §7 asks for.** The requirement says it "already exists for this". It does not: it joins done-brief `## Outcome` blocks to postmortem labels and emits a **confusion matrix (recall / FP / FN)** — the heal *catch-rate*, a different quantity from the per-class findings/misses distribution (its own header states this). It is the right host to EXTEND (Subtask 4 adds a `--distribution` mode) but it cannot be merely "re-run".
3. **Both stores §7 names for the durable record are GITIGNORED.** §7 says "reuse `measure-heal-signal.sh` and item 02's cadence record rather than adding a third store." But `measure-heal-signal.sh` writes to `.supervisor/heal-signal/` and item 02 writes `.supervisor/curation-state.json`, and the only `.supervisor/` negations in `.gitignore` are `!.supervisor/memory/` and the `results.jsonl` trio. A baseline recorded in either does **not** survive a fresh clone and cannot be compared by anyone else — which is exactly what "durable" was asking for. **Settled decision (d)** resolves this.

## Acceptance Criteria

- [ ] **AC1** Given the live ledger, when `harvest-conventions.sh` runs in its default mode, then it reads BOTH intake sources and assigns every candidate to **exactly one** of three buckets (`agent-memory` / `rules` / `project-memory`) with the assigning reason recorded per candidate. The two sources are:
  - **(i) the ledger** — `convention_mismatch` entries in `.supervisor/postmortem/results.jsonl`;
  - **(ii) the existing agent-memory corpus `.claude/agent-memory/**/*.md` (28 entries today, `MEMORY.md` indexes excluded) PLUS any pending files under the gitignored `.supervisor/agent-memory-proposals/`.**
  **The proposals queue is currently EMPTY — the directory does not exist on disk** (verified), so a harvester wired only to it would ship a no-op branch and the three-bucket triage would never be exercised on real data. The **corpus is what the dry run actually exercises**, and it is also what the source requirement means: §1 names `project_self_heal_rubber_stamp.md` as a well-formed candidate, and §2's whole triage table is written about existing entries — `attack_jq_only_json_injection` / `golden_fixture_regen` stay in agent-memory, `attack_failclosed_vs_failsafe_split` **graduates** to `.agent/rules/`. All four exist on disk today (`loomwright-loomwright-code-reviewer/`, `loomwright-loomwright-red-team-reviewer/` ×2, `loomwright-loomwright-qa-executor/`). §2's portability argument — "today red-team's five attack patterns exist on one laptop only" — is about exactly this corpus. Reading only the queue would silently narrow the requirement's central worked example out of scope.
- [ ] **AC2** Given a candidate bucketed to `rules`, when the batch is emitted, then that proposed rule carries a non-empty `applies_to` derived from the `changed_paths` of the findings that motivated it; a repo-wide (`applies_to: null`) proposal is emitted **only** with a stated justification string, never as a silent default.
- [ ] **AC3** Given the harvester runs with no delivery flag, when it completes, then it has created **no branch, no commit and no PR**, has written nothing to `.agent/rules/`, and has printed the full batch — i.e. **dry-run is the DEFAULT**, and PR delivery is opt-in (decision (b)).
- [ ] **AC3b** Given the harvester runs **from an interactive TTY session** (which is how `/dreaming` runs), when it composes `add-rule.sh` for the dry-run batch, then **nothing is written to `.agent/rules/` and no `Confirm write? [y/N]` prompt reaches the user's terminal** — enforced by decision (f)'s mandated stdin-detached invocation shape. This AC exists because a no-`--confirm` call alone does **not** guarantee a dry run: `add-rule.sh`'s `elif [ -t 0 ] && [ -t 1 ]` branch prompts and, on `y`, WRITES. Test it by asserting the invocation shape **and** by running the harvester with a live stdin and asserting the store is byte-unchanged.
- [ ] **AC4** Given a dry run over this repo's real `convention_mismatch` findings (**107**, per correction 1 — not 104), when it reports, then it prints three falsifiable numbers: **coverage** (share of the 107 findings mapping to ≥1 proposed rule, with the unmapped remainder stated not hidden), **dedupe rate** (findings-in per rule-out), and **scope fidelity** (for each rule, whether its derived `applies_to` mechanically matches the paths of its motivating findings — computed, not asserted). The batch is **bounded in size** (an explicit cap, stated in the output) and **every proposed rule is traceable to the finding ids that motivated it**, so the batch can be judged by reading — the three numbers supplement that reading, they do not replace it.
- [ ] **AC4b** Given the dry run of AC4 has been executed against the **real** corpus (not a fixture), when Subtask 1 completes, then its output is committed as **`loomwright/docs/HARVEST_DRYRUN_SAMPLE.md`** — the bounded batch, the per-rule finding-id traceability, and the three numbers — so a reviewer can judge the batch by reading it. **The sample must state the exact harvester invocation that produced it and the input record count it read**, so a reviewer can falsify a hand-written sample by re-running one command — the file is still created by the same subtask, so nothing deterministic can prove it came from the real corpus; the traceability is what makes it spot-checkable. This AC exists because every other Subtask-1 `provides` is a file or a symbol **inside a file the same subtask creates**, i.e. entirely self-satisfiable: without a durable artifact, a worker can make every provide resolve and every AC read as met with a fixture-tested script that has **never produced a reviewable batch** — which is the requirement's central deliverable. (`outputs_verified` is worker-self-reported; this repo has been bitten by that before.)
- [ ] **AC5** Given a batch approaching one rule per finding, when the dedupe rate is computed, then the run reports it as a **failure of distillation** in its own output rather than emitting the batch as if it had distilled anything.
- [ ] **AC6** Given the user accepts a rule batch for delivery, when `/dreaming` proceeds, then an **explicit per-item confirmation fires BEFORE anything is pushed**, separate from the per-item Accept that authorises the content; the branch + `gh pr create` happen only after it, and `/dreaming` **never merges**.
- [ ] **AC7** Given `commands/dreaming.md`, when its contract sentence is read after this change, then it **names the remote-affecting action** — the "Read-only-until-Accept contract" sentence (the file's opening contract callout, verified at `dreaming.md:5`) is amended so a user is not told "read-only until you accept" while a branch push is possible. This is a **contract change, updated at the contract line**, not buried in a phase description.
- [ ] **AC8** Given pending files under `.supervisor/agent-memory-proposals/`, when `/dreaming` runs, then it **surfaces them for per-item promotion** the way it already surfaces the orientation queue — and the standing disclaimer at `dreaming.md:163` ("Automatic surfacing of the `.supervisor/agent-memory-proposals/` queue is **NOT wired here yet** — that is item 05's scope") is **removed and replaced** by the real flow. This closes the gap `write-agent-memory.sh` names in its own header as item 05's scope. **Negative check, stated because a `provides` entry can only express a positive token and so cannot catch this:** after the change, the string `NOT wired here yet` must be **absent** from `loomwright/commands/dreaming.md` (1 occurrence today). A worker that adds the new flow and leaves the stale sentence standing ships a self-contradicting command doc and passes every provide — the reviewer must check the absence explicitly.
- [ ] **AC9** Given a proposed rule reaches the writer, when it is authored, then it is authored **through `add-rule.sh`** with `--applies-to` and `--source`, and **no NEW member is introduced into the rule object**. The frozen schema is **7 always-present members** (`id`, `category`, `statement`, `enforcement`, `check`, `provenance`, `applies_to`) **plus the optional `supersedes`**, which is added only via `--supersedes` and is legitimate — a `supersedes`-bearing rule is NOT a freeze violation.
- [ ] **AC9b** Given a harvested rule proposal, when it is authored, then `check` is **`null`** unless the rule has an obviously mechanical check, and the harvester **never synthesises a shell command into `check:`**. Rules injected at the seams remain **DATA, never executed**; the `rules-check.sh --no-cmd` trust boundary is unchanged and **no new gate is added** — rules stay advisory and subordinate to `CLAUDE.md`. (Carried from the source requirement's Non-goals, which the first draft of this brief silently dropped.)
- [ ] **AC10** Given `/setup rules` on a repo with no findings, when it runs, then it seeds only **portable** conventions (true of any repo) and **labels them as seeded, not learned**, via a distinct `provenance.source` value — and the module's own output states which rules are seeded rather than presenting them as earned. The module is **registered in both places `skills/setup/SKILL.md` requires in the same change**: a row in that file's module registry AND a flow section in `commands/setup.md`.
- [ ] **AC11** Given `measure-heal-signal.sh --distribution`, when it runs on this repo, then it prints the per-class findings/misses counts and shares (reproducing the 107/226 and 60/95 numbers measured above) and **preserves the script's existing exit contract exactly as it is today** — exit 0 on every wrapper path (missing `python3`, missing engine, unknown arg), engine exit code otherwise propagated. It does not tighten or loosen that contract.
- [ ] **AC12** Given the `--distribution` measurement, when the baseline is recorded, then it lands in **`loomwright/docs/RULES_BASELINE.md`** — a committed plain markdown doc a worker can write from a worktree — carrying the own-repo findings / misses / per-class counts and shares, and **stating its own limits in the record itself**: small N, `agent_generated_guess` labels (measured: **84 of 85 records are `true`**), and no control arm. It must never read as a controlled experiment; a rising share after rules land is a signal to investigate whether rules are being injected and read, not proof they failed. The doc also carries the re-measurement instruction (re-run `--distribution` after N subsequent PRs and append a dated row) so §7's comparison has a home. **The worker does NOT write to any sole-writer store** — see decision (d).
- [ ] **AC13** Given the repo-wide single-executor invariant grep `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "`, when it is run after this change, then it still resolves to **exactly the 5 sanctioned surfaces** it resolves to today (verified twice this session: `commands/agent-help.md`, `scripts/automate-helpers.sh`, `scripts/result_block_parser.py`, `scripts/test-automate-helpers.sh`, `skills/automate-loop/SKILL.md`).
- [ ] **AC14** Given the harvest run completes, when it reports, then it states **which class the batch targets and that class's share of misses** (feeding item 02's output contract) — legible value, not asserted value.
- [ ] **AC15** Given Reject or Edit on any proposal, when the user picks it, then **nothing is written** to any store and no branch is created — the existing per-item human gate for non-PR destinations is preserved unchanged.
- [ ] **AC16** Given the full CI glob, when it runs, then every suite is green and `check-doc-currency.sh` is green after the version bump, with the **agent / command / skill / hook counts UNCHANGED** — a `/setup` module is not a command file and adds no skill directory, so the counts must not move (that script computes only version + those four counts and has no notion of `/setup` modules). No stale prior-version string leaks outside `CHANGELOG.md`.

## Outcomes Rubric
- A new `scripts/harvest-conventions.sh` exists and reads both `.supervisor/postmortem/results.jsonl` and the `.claude/agent-memory/**/*.md` corpus (plus any pending `.supervisor/agent-memory-proposals/`), with a per-candidate bucket and reason in its output.
- Every rule the batch proposes carries either a non-empty `applies_to` array or an explicit repo-wide justification string, and a `check` of `null` unless an obviously mechanical check is present — no silent `null` scope, no synthesised shell command.
- `loomwright/docs/HARVEST_DRYRUN_SAMPLE.md` exists and carries the real dry-run batch: coverage, dedupe rate and scope fidelity as computed numbers, with every proposed rule naming the finding ids that motivated it.
- `commands/dreaming.md`'s contract sentence names the remote-affecting (branch-push / PR) action, and a pre-push confirmation distinct from Accept is described in the same file.
- `commands/setup.md` gains a `rules` flow section and `skills/setup/SKILL.md` gains the matching registry row, with seeded rules distinguished from learned ones by `provenance.source` and no new member on the rule object.
- `scripts/measure-heal-signal.sh` gains a `--distribution` mode whose exit behaviour is unchanged from today's.
- `loomwright/docs/RULES_BASELINE.md` exists, carries the per-class baseline, and states its own limits (small N, guessed labels, no control arm) in the record itself.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Settled owner decisions (the worker MUST NOT re-litigate these)

- **(a) No repo filter in the harvester.** Per correction 1 the ledger is already own-repo-only by a committed gate. The harvester reads it whole and NAMES any out-of-allowlist `.repo` as an advisory line. Rationale: a harvester that re-implements a filter takes its expectation from machine-local config (`.supervisor/config.json` is gitignored) and reproduces item 01c's CI failure exactly — passing locally with a 2-entry allowlist, failing in CI with the 1-entry remote default.
- **(b) Dry-run is the DEFAULT; PR delivery is opt-in.** The requirement asks for "a documented dry-run path". Making dry-run the default is strictly stronger and is what keeps AC7's amended contract sentence honest: the ONLY way to reach a push is an explicit opt-in plus AC6's pre-push confirmation.
- **(c) `/dreaming` opens a PR and stops.** No merge, ever. `gh pr create` only. AC13 is the mechanical check.
- **(d) The durable baseline is a COMMITTED DOC, written by the worker — NOT a sole-writer store.** *(This REVERSES the first draft of this brief, which routed it through `write-project-memory.sh --confirm`. Plan Review proved that unexecutable and the reversal is recorded rather than quietly applied.)* Three independent reasons the sole-writer route fails: (1) `write-project-memory.sh` **refuses to run from a git worktree**, and Supervisor workers run in worktrees, so the assigned worker structurally cannot call it; (2) `--confirm` needs a human or a TTY the worker does not have; (3) the store is a **200-line FIFO-evicting** file whose every write is duplicate-scored against the whole corpus at a ~90% overlap threshold, so the *second* record — same phrasing, different numbers — is a plausible `REFUSE_DUPLICATE`, and the first can later be silently evicted. The baseline therefore lands in `loomwright/docs/RULES_BASELINE.md`: committed (so it survives a fresh clone, satisfying §7's actual intent), worktree-writable with an ordinary `Write`, append-friendly for the post-N-PRs row, and not a competing *measurement* store — the computation still lives in `measure-heal-signal.sh --distribution` (AC11) so it stays re-runnable. §7's "no third store" objection is about measurement stores; a committed record doc is the durable place it asked for.
- **(e) The rule object schema is FROZEN — seeded/learned rides in `provenance.source`.** Verified: the object has 7 always-present members **plus an optional `supersedes`** added only via `--supersedes`; `add-rule.sh` **rejects unknown arguments** (`*) die "unknown argument"`), and its header states a sidecar "would violate the freeze". Mandating an `origin:` member would be a create-shaped path with no writer behind it. `/setup rules` therefore passes a distinctive `--source` (e.g. `setup:rules-seed`) and `/dreaming` passes `dreaming:<session_id>`; the seeded/learned distinction is read back off `provenance.source`.
- **(f) The dry-run substrate is `add-rule.sh` invoked with stdin DETACHED — `add-rule.sh … < /dev/null`.** *(Corrected from the first draft, which claimed a bare no-`--confirm` call is a dry run.)* It is not: `add-rule.sh` has three branches — `--confirm` writes; **`elif [ -t 0 ] && [ -t 1 ]` prompts `Confirm write? [y/N]` and WRITES on `y`**; only the fall-through prints `PLANNED WRITE (not written …)` and exits 0. `/dreaming` runs interactively on the main thread with a live TTY, i.e. exactly the prompting case. Redirecting stdin from `/dev/null` makes `[ -t 0 ]` false and the PLANNED-WRITE path the only reachable one — and also prevents N proposals from emitting N prompts at the user's terminal. AC3b is the assertion.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Status |
|---|-------|---------------------------|---------------------------|--------|
| 1 | Harvest + triage engine and its dry-run metrics |  AC1, AC2, AC3, AC3b, AC4, AC4b, AC5, AC9, AC9b, AC14 | 0 modify, 3 create | LAUNCHABLE |
| 2 | Wire into `/dreaming`: proposal queue, PR delivery, contract change | AC6, AC7, AC8, AC13, AC15 | 1 modify, 0 create | BLOCKED (by #1) |
| 3 | `/setup rules` cold-start module | AC10 | 2 modify, 2 create | BLOCKED (by #1) |
| 4 | `--distribution` measurement, committed baseline, release surface | AC11, AC12, AC16 | 8 modify, 2 create | BLOCKED (by #2, #3) |

> Skills per subtask are in `## Skill References` below, which is **authoritative** — the Skills column was removed from this table rather than kept as a second, drifting copy.

### Subtask contracts

```yaml
# Subtask 1 — harvest + triage engine (LAUNCHABLE)
provides:
  - {kind: "file",   path: "loomwright/scripts/harvest-conventions.sh"}
  - {kind: "file",   path: "loomwright/scripts/test-harvest-conventions.sh"}
  - {kind: "file",   path: "loomwright/docs/HARVEST_DRYRUN_SAMPLE.md"}       # AC4b — the ONLY provide here not self-satisfiable inside this subtask's own new files
  - {kind: "symbol", path: "loomwright/docs/HARVEST_DRYRUN_SAMPLE.md", name: "scope fidelity"}
  - {kind: "symbol", path: "loomwright/scripts/harvest-conventions.sh", name: "harvest_convention_findings"}
  - {kind: "symbol", path: "loomwright/scripts/harvest-conventions.sh", name: "triage_bucket"}
  - {kind: "symbol", path: "loomwright/scripts/harvest-conventions.sh", name: "derive_applies_to"}
  - {kind: "symbol", path: "loomwright/scripts/harvest-conventions.sh", name: "scope_fidelity"}
  - {kind: "symbol", path: "loomwright/scripts/harvest-conventions.sh", name: "dedupe_rate"}
  - {kind: "symbol", path: "loomwright/scripts/harvest-conventions.sh", name: "coverage_share"}
requires: []
lanes:
  - "loomwright/scripts/harvest-conventions.sh"
  - "loomwright/scripts/test-harvest-conventions.sh"
  - "loomwright/docs/HARVEST_DRYRUN_SAMPLE.md"
external_requires:
  - "jq (already a hard dependency of every sibling writer)"

# Subtask 2 — /dreaming wiring + contract change (BLOCKED by #1)
# NOTE: the provide tokens below were each grep-verified at 0 hits IN dreaming.md, not merely
# repo-wide. An earlier draft used the token `agent-memory-proposals`, which ALREADY appears at
# dreaming.md:163 — in a sentence saying the work is NOT done — so a worker that changed nothing
# would have passed the deterministic outputs_verified gate.
provides:
  - {kind: "symbol", path: "loomwright/commands/dreaming.md", name: "harvest-conventions.sh"}
  - {kind: "symbol", path: "loomwright/commands/dreaming.md", name: "PROMOTE PENDING PROPOSAL"}
  - {kind: "symbol", path: "loomwright/commands/dreaming.md", name: "Pre-push confirmation"}
requires:
  - {from: "1", kind: "file", path: "loomwright/scripts/harvest-conventions.sh"}
lanes:
  - "loomwright/commands/dreaming.md"
external_requires:
  - "gh CLI (PR creation only — never merge)"

# Subtask 3 — /setup rules module (BLOCKED by #1)
# NOTE: the token is H2 — "## Module: rules" — because EVERY module section in setup.md is an H2
# (## Module: observability / twin / memory / telemetry / notifications / webhook / beads /
# mysql-mcp; `^### Module` is 0-hit, and the H3 level is reserved for the intra-module
# ### Check / ### Report / ### Offer / ### Apply / ### Verify phases). An H3 token would have
# forced the worker to choose between a heading nested one level too deep in a user-facing doc
# and failing the substring gate — which would also block ST4, whose requires names the same
# string. It is NOT the bare word `rules`, which already
# occurs at setup.md:52 / :217 / :236 as ordinary English ("settings-merge rules", "abort rules").
provides:
  - {kind: "file",   path: "loomwright/scripts/seed-rules.sh"}
  - {kind: "file",   path: "loomwright/scripts/test-seed-rules.sh"}
  - {kind: "symbol", path: "loomwright/commands/setup.md",      name: "## Module: rules"}
  - {kind: "symbol", path: "loomwright/skills/setup/SKILL.md",  name: "| `rules` |"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/harvest-conventions.sh", name: "triage_bucket"}
lanes:
  - "loomwright/scripts/seed-rules.sh"
  - "loomwright/scripts/test-seed-rules.sh"
  - "loomwright/commands/setup.md"
  - "loomwright/skills/setup/SKILL.md"
external_requires: []

# Subtask 4 — measurement, committed baseline, release surface (BLOCKED by #2 and #3)
provides:
  - {kind: "file",   path: "loomwright/scripts/test-measure-heal-signal-distribution.sh"}
  - {kind: "file",   path: "loomwright/docs/RULES_BASELINE.md"}
  - {kind: "symbol", path: "loomwright/scripts/measure-heal-signal.sh", name: "--distribution"}
  - {kind: "symbol", path: "loomwright/docs/RULES_BASELINE.md",         name: "agent_generated_guess"}
requires:
  - {from: "2", kind: "symbol", path: "loomwright/commands/dreaming.md", name: "harvest-conventions.sh"}
  - {from: "3", kind: "symbol", path: "loomwright/commands/setup.md",    name: "## Module: rules"}
lanes:
  - "loomwright/scripts/measure-heal-signal.sh"
  - "loomwright/scripts/measure-heal-signal.py"
  - "loomwright/scripts/test-measure-heal-signal-distribution.sh"
  - "loomwright/docs/RULES_BASELINE.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
  - "CLAUDE.md"
  - "CHANGELOG.md"
  - "README.md"
  - "loomwright/commands/agent-help.md"
external_requires:
  - "python3 (measure-heal-signal.py's existing engine — already skip-guarded when absent)"
```

> **Lane / reachability note.** The only mutually-unreachable pair in the `requires` DAG is (Subtask 2, Subtask 3), and their lanes are disjoint, so there is no legal lane collision. No lane path is owned by two subtasks. `loomwright/skills/setup/SKILL.md` is owned by Subtask 3 alone; it is in the lanes because `skills/setup/SKILL.md` itself mandates that a new module appends a registry row there **and** a flow section in `commands/setup.md` **in the same change** — omitting it would ship an unregistered module or force an undeclared out-of-lane write.

> **Out-of-PR step (NOT a worker task, stated so it is not silently lost).** §7's *re-measurement* — re-running `--distribution` after N subsequent PRs and appending the comparison row to `RULES_BASELINE.md` — happens **after** this PR merges and is a main-thread human/operator step. Subtask 4 delivers the instrument and the baseline row; it cannot deliver a post-merge measurement from inside its own PR.

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2 ──→ Subtask 4
         └──→ Subtask 3 ──────┘
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none | YES (dependency, not overlap) |
| Subtask 1 | Subtask 3 | none | YES (dependency, not overlap) |
| Subtask 2 | Subtask 3 | none | NO — mutually unreachable, but lanes are disjoint |
| Subtask 2 | Subtask 4 | none | YES (dependency) |
| Subtask 3 | Subtask 4 | none | YES (dependency) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2, Subtask 3
- **Batch 3:** Subtask 4
- **Recommended workers:** 1
- **Estimated batches:** 3

## Skill References

**This table is authoritative** (the Subtask Structure table carries no Skills column).

| Subtask | Skills |
|---------|--------|
| 1 | `skills/rules/SKILL.md`, `skills/unit-testing/SKILL.md`, `skills/quality-checklist/SKILL.md` |
| 2 | `skills/rules/SKILL.md`, `skills/review-heal/SKILL.md`, `skills/quality-checklist/SKILL.md` |
| 3 | `skills/rules/SKILL.md`, `skills/unit-testing/SKILL.md` |
| 4 | `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| An intake source that is an EMPTY directory, making half of AC1 a satisfiable no-op | HIGH | `.supervisor/agent-memory-proposals/` does not exist on disk; AC1 now names the 28-entry `.claude/agent-memory/` corpus as the source the dry run actually exercises, which is also the requirement's own worked example (`attack_failclosed_vs_failsafe_split` graduating). Caught at Plan Review attempt 2 |
| A `provides` token that is 0-hit but violates the target file's own convention | HIGH | `### Module: rules` was 0-hit yet contradicted setup.md's uniform H2 module heading, forcing a malformed doc or a gate failure. Corrected to `## Module: rules` in both the provide and ST4's mirroring `requires`. This is the same class as the attempt-1 BLOCKING, appearing *inside the fix for it* — re-verify a replacement token against the file's conventions, not only its hit count |
| Every Subtask-1 provide self-satisfiable inside files that subtask itself creates | MEDIUM | AC4b + the `HARVEST_DRYRUN_SAMPLE.md` provide force the dry run to leave durable, readable evidence over the real corpus; without it a fixture-tested script that never produced a batch would pass every gate |
| A `provides` token that already resolves, letting a worker pass `outputs_verified` with zero work | HIGH | Two such tokens were caught at Plan Review (`agent-memory-proposals` at `dreaming.md:163`, the bare word `rules` at `setup.md:52`) and replaced; every replacement was re-verified at 0 hits **in the target file**, not merely repo-wide |
| A no-`--confirm` `add-rule.sh` call assumed to be a dry run, but prompting-and-writing on a TTY | HIGH | Decision (f) mandates `< /dev/null`; AC3b asserts it from a live-stdin session, not only by reading the invocation |
| A baseline routed through a writer the worker structurally cannot call (worktree refusal + `--confirm`) | HIGH | Decision (d) reversed to a committed doc; the reversal and its three reasons are recorded rather than quietly applied |
| Planning against the requirement's stale numbers (104/213 own-repo split) | HIGH | Corrections 1–3 are load-bearing and were independently reproduced at Plan Review; AC4 pins **107**, and decision (a) forbids the repo filter the stale wording implies |
| Adding a member to the rule object to label seeded rules | HIGH | Decision (e) + AC9 — `add-rule.sh` rejects unknown args; the optional `supersedes` is named explicitly so it is not mistaken for a violation |
| `/dreaming` becoming a second `gh pr merge --squash` executor | HIGH | Decision (c) + AC13's mechanical grep, verified green at brief time (5 surfaces) |
| An auto-authored `check:` flowing into `rules-check.sh` | MEDIUM | AC9b — `check` stays `null` absent an obviously mechanical check; rules remain DATA, never executed; no new gate |
| A new `/setup` module registered in only one of its two required places | MEDIUM | AC10 + Subtask 3's lanes include `skills/setup/SKILL.md`, whose own line 53 mandates both edits in the same change |
| Batch quality judged by counting rather than reading | MEDIUM | AC4 requires a size bound and per-rule traceability to finding ids; AC5 makes a near-1:1 dedupe rate a self-reported failure |
| `84/85` ledger records are `agent_generated_guess: true` | MEDIUM | AC12 requires the limitation stated **in the record itself**; a rising share after rules land is a signal to investigate injection/reading, never proof rules failed |
| Scope exceeds the single-subtask default (18 est. files) — the Feasibility table's one CAUTION, mirrored here | MEDIUM | `context-bound` split into 4 dependency-ordered subtasks; see `## Configuration` |
| Concurrent writers on this shared checkout (recurred twice in this run's history) | MEDIUM | Verify `pgrep`/transcript-mtime/`gh pr list` before ACQUIRE; do not fight a live writer for the tree — park instead |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 3
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-08-14-dreaming-triage-to-pr.md
```

---

## Outcome

- **Status:** completed
- **Session:** inline `/supervisor job:` on the main thread, 2026-08-14 → 2026-08-15
- **Branch:** `feature/dreaming-triage-to-pr` (base `main` @ `97e721d`)
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/147 (OPEN — never merged, per decision (c))
- **Version:** 15.34.0 → 15.35.0
- **preflight_sync:** clear
- **Path:** Sequential (4 subtasks, 1 worker, 3 batches) — no worktrees
- **heal_loop_ran:** true
- **heal_decision:** PASS
- **heal_iterations:** 1
- **heal_remaining_issues:** 0 BLOCKING/HIGH; 2 MEDIUM residuals raised at re-review were also fixed
- **until_mergeable_dispatched:** true
- **until_mergeable_log:** `.supervisor/logs/review-pr-dispatch-20260815T031837Z-f989e009f427381e189c183552466c51a3830f7b.log`

### Commits
| SHA | Subtask |
|---|---|
| `b3c2a69` | 1 — harvest + triage engine with dry-run metrics |
| `78ec2a7` | 2 — `/dreaming` wiring, pre-push gate, honest contract |
| `de38b8a` | 3 — `/setup rules` portable seeds |
| `e20c941` | 4 — `--distribution`, committed baseline, release surface |
| `57a09ad` | drain — `pty_run` quoting-safe under GNU `script` (CI-only) |
| `3afc27a` | heal 1 — 2 HIGH + 5 MEDIUM + 4 LOW review findings |
| `d30f572` | heal 1 — regenerated dry-run sample |
| `d0ad299` | heal 1 — fixture that could not detect its own swap |

### Verification (re-verified by the Supervisor on disk, not taken from worker self-report)
- 71/71 CI suites green; new suites 50 + 56 + 35 assertions
- `check-doc-currency.sh` green — 15.35.0 / agents 14 / commands 21 / skills 41 / hooks 24 (**counts unchanged**, as AC16 requires)
- Single-executor invariant grep resolves to exactly the 5 sanctioned surfaces — `/dreaming` adds no merge executor (AC13)
- No `15.34.0` string outside `CHANGELOG.md`
- H1 independently falsified: with `bc` stubbed to exit 127 the harvester prints `226 findings, 95 self-heal misses` / `107/226 (47%)` / `60/95 (63%)` — the dependency is gone, not merely guarded

### Notes for the record
- **Concurrent writer.** The detached until-mergeable drain pushed `57a09ad` while the heal commit was still local; the branches diverged 1↔1 and were rebased cleanly (no conflict), then the full suite was re-run on the merged state. The drain process has since exited, so CI on the final push (`d0ad299`) is **not** covered by it.
- **`--expect-repo` ships unarmed.** Decision (a) forbids reading the repo allowlist from gitignored machine-local config and no committed repo-identity source exists, so the harvester reports the observed `.repo` distribution but flags nothing. Stated rather than faked.
- **Corpus graduation removed as unreachable.** The requirement's worked example (`attack_failclosed_vs_failsafe_split` graduating to `.agent/rules/`) cannot happen: a corpus entry carries no measured violation. It is bucketed `rules` and **corroborates** a ledger-backed theme's rule instead. The requirement file was amended, but `.supervisor/requirements/` is **gitignored**, so that amendment is a local design-record change and does not ship in the PR.
- **PR is `BLOCKED` / `REVIEW_REQUIRED`** by branch protection (1 approving review + required check `ci`). A human must approve; the Supervisor cannot and does not merge.

### Amendment — heal iteration 2 (post-tail; two channels reported after the tail was written)

The completion tail above was written when the Phase 4.5 lens returned PASS. Two further channels
reported afterwards, both with real findings. **`heal_iterations` is 2, not 1.**

| Commit | Fix |
|---|---|
| `5293d06` | separator legibility + scope-fidelity denominator disclosure |
| `f25717d` | baseline row re-measured against a reproducible ledger state and pinned |
| `8137ca0` | sample regenerated from a clean clone at a pinned sha |

- **H1 (drain, HIGH) — the baseline did not reproduce from its own instrument.** Root cause is the
  Supervisor's own instruction: workers were told never to stage `.supervisor/postmortem/results.jsonl`,
  which is git-tracked, so the row was measured against uncommitted records nobody else can see
  (84 committed → 85 when written → 86 later). Corrected to the committed-state figures
  (84 records / 225 findings / 95 misses, 42+42, `convention_mismatch` 107 = 48% / 60 = 63%,
  label quality 83 of 84) and **pinned** to commit `5293d06`, ledger blob `952ff91`. The headline
  claims survived — 107 and 60 are unchanged; only denominators moved. The file's own
  "do not rewrite the baseline row" rule now carries a written exception for the case where a row
  does not reproduce from its own pinned input, and this use of it is recorded rather than silent.
- **H2 (drain, HIGH)** — `CLAUDE.md` + `CHANGELOG.md` restated figures corrected. No gate covers
  these; `check-doc-currency.sh` only scans version and the four counts.
- **M3 (drain, MEDIUM) — the real metric defect.** `scope fidelity` reported the checkable figure
  only. Both are now printed per rule and in aggregate: **98% (54 of 55) checkable vs 72% (54 of 74)
  over all motivating findings**, each exclusion named by count. The gap is NOT mostly deleted files
  as first hypothesised — **18 of 19 are ledger records carrying no `changed_paths` at all**.
- **B1 (CI bot, reported BLOCKING) — FALSE POSITIVE, and the Supervisor confirmed it wrongly.**
  The claim was that `changed_paths` was joined with `""`, dropping 86% of records. The source
  actually contained `join("␟")` — a **raw 0x1F byte typed into the jq program**. Verified by
  `od -c` on `d0ad299`: `j o i n ( " 037 " )`. jq accepts it; the separation always worked, and
  `findings.tsv` is byte-identical before and after the fix. The real defect is **legibility**: an
  invisible byte in a load-bearing position, which no reader, grep, diff or review tool can see. It
  caused two independent channels to file a critical bug against correct code, and a normalising
  editor pass that ate it would have introduced the reported bug with a zero-visible diff. Fixed by
  making the separator explicit (`jq --arg us "$US"` + `join($us)`) — behaviour-preserving, so the
  standing protection is the new (J)/(M5) contract test that goes RED if the separator is destroyed.
  The `(B)` fixture's masking third record was also fixed: it was single-path and cleared the 95%
  cover threshold alone, so `(b1)` passed with every multi-path record dropped.
- **Sample generated from a clean CLONE, not a worktree.** A detached worktree has `.git` as a
  *file*, and `add-rule.sh` refuses to write in that case — so all four proposals printed
  `writer REFUSED (exit 3)` instead of `PLANNED WRITE`, losing the very branch the sample exists to
  demonstrate. The file records this.

**Concurrent-writer note.** The detached drain and this inline heal loop both healed the same
findings, differently, and the drain hit 13 conflict hunks across 4 files on push. It correctly
refused to force-resolve and escalated. That is the single-drain-ownership invariant being violated
by the workflow shape — the drain fired at `gh pr create` while Phase 4.5 was still running — not a
code defect. Worth a follow-up.

**Final:** 71/71 local suites green; GitHub `ci` green; counts unchanged; merge invariant still 5
surfaces; PR still OPEN and unmerged, `BLOCKED`/`REVIEW_REQUIRED` pending human approval.

### Amendment — heal iteration 3 (final; `--heal-iterations 3` bound reached)

A third review channel reported six findings. **All six verified real — no false positive this round.**
Commits `efccaf3`, `25e84f2`, `699e094`.

| # | Finding | Fix |
|---|---|---|
| F1 (HIGH) | `derive_applies_to` emitted a glob that could not match its own source path: a 2-segment path like `loomwright/plugin.json` produced `loomwright/plugin.json/*`, matching only files nested under a directory named `plugin.json`. **No fixture used a 2-segment path.** | Three-way split: `n>=3 → s1/s2/*`, `n==2 → s1/*`, `n==1 → literal`. Fixture (K) feeds the derived glob to the same bash `case` matcher `read-rules.sh` uses and asserts the MATCH, not the glob's textual shape. |
| F2 | The aggregate fidelity figure accumulated only inside the `[ -n "$globs" ]` branch, so a null-scope rule's findings were dropped from its own denominator — self-defeating, since null-scope is exactly what happens to findings with no usable path. | Accumulate for every emitted rule. Fixture (L) moves the figure **down**, 100% (5 of 5) → 55% (5 of 9). |
| F3 | The unmapped-remainder breakdown was keyed on `RULE_THEMES` (populated at triage, before `emit_rule`'s CAP early-return), so a cap-deferred theme vanished from the itemisation while still counting toward the stated total; the "below the support floor" label was also wrong for `unknowable-only` themes. | Keyed on a new `EMITTED_THEMES`; each line carries its real cause. |
| F4 | `for p in $paths` word-split on a `changed_paths` entry containing a space. | Line-wise `while IFS= read -r p`; fixture uses a tracked `my notes.md`. |
| F5 | `seed-rules.sh` guarded only the assignment, not the `shift`, so `seed check --confirm` silently dropped `check` **and proceeded to write**. | Hard `die` (exit 2, verified). Mutation control: the old line exits 0 and writes 5 rules. |
| F-doc | The baseline's flagship reproduction command led with `952ff91^{commit}` — a **blob** sha — which errors and silently fell through, in a file whose premise is "run it rather than trust this file". | Recipe leads with the commit; blob retained as the integrity pin on its own line. |

Five mutation controls, each observed RED.

**The repo's numbers did not move, and that is explained rather than asserted:** coverage `74/107 (69%)`,
dedupe `18.50`, fidelity `98% (54 of 55)` checkable / `72% (54 of 74)` honest — byte-identical. F1 could
not move them because no 2-segment path wins the greedy set cover on this ledger; F2 could not, because
this batch has **zero** null-scope rules, making the two accumulations arithmetically identical. Both
mechanisms are proved on dedicated fixtures instead.

Also landed: `test-seed-rules.sh` asserts the exact seed count (derived from `seed-rules.sh`'s own
`SEEDS` table, not restated), and `/dreaming`'s Pre-push confirmation — the gate the feature calls its
safety property — now states **ambiguous ⇒ do not push**, matching its sibling `/setup rules` Offer.

**Final state:** HEAD `699e094`; GitHub `ci` and `claude-review` both green **against that exact sha**;
71/71 local suites; harvest 71 assertions, seed-rules 59; counts unchanged 14/21/41/24; merge invariant
still exactly 5 surfaces. **PR OPEN and unmerged**, `BLOCKED`/`REVIEW_REQUIRED`.

**Honest limit on the final commit:** `claude-review` went green on `699e094` but **posted no comment**
for it, so that commit set carries green CI without a substantive LLM review — the same silent-pass mode
the drain documented earlier in this run. Green is not evidence of review here.

**Review-lens observation for the backlog.** Three consecutive channels each found real defects in code
the previous one passed, in decreasing depth (2 HIGH → 1 BLOCKING-reported-but-false + 2 HIGH → 1 HIGH +
5 MEDIUM). The earlier PASS verdicts reported a lens's limit, not the code's state. The two defect classes
that survived every lens until the last were both **absence-shaped**: a fixture that used no 2-segment
path, and an accumulator that ran in only one branch. Neither is visible to a reviewer reading what IS
written.

### Amendment — heal iteration 4 (external review, `FAIL`)

A fourth channel returned **FAIL** with two MEDIUM defects sharing one root cause. **All four findings
reproduced by the Supervisor before any fix.** Commit `8310d0f`.

- **F1 (the real defect) — an edited seed put `/setup rules` into a PERMANENT failure state.**
  `seed_present()` matched on the **exact** statement, while `commands/setup.md` tells users a seed
  "is meant to be edited or retracted". After any edit: `check` → `ABSENT`, `seed --confirm` →
  `validate-entry: REFUSE_DUPLICATE — a near-identical entry` → `written: 0 · failed: 1` → **exit 1**,
  reproduced as rc=1 on runs 3 and 4. `setup.md:428` defines exit 1 as "do NOT report success", so a
  correctly-configured repo reported hard failure forever.
  **The script's own header named this exact failure** as the reason the pre-check exists — the
  pre-check is exact-match while `validate-entry` is near-match, so the gap was precisely the case the
  rationale was written for. Fixed by keying presence on the **seeded provenance stamp**
  (`provenance.source == setup:rules-seed` + category, with the frozen `<category>-` id prefix as
  fallback) rather than statement text. **Verified after the fix:** `ALREADY SEEDED`, rc=0 stable over
  three runs, store byte-identical.
  The category key is only faithful because the seed table has one row per category — so that is now a
  **hard startup failure** (exit 2) naming the invariant, verified by injecting a duplicate row.
- **F2 — a retracted seed is silently resurrected.** Reproduced. Not fixable here without a new store
  or schema member, both forbidden (frozen schema; `add-rule.sh`'s header states a sidecar "would
  violate the freeze"). So the **false claims were corrected** instead: `setup.md:29`'s "re-seeding is
  a no-op by design" and the Idempotency note now describe what actually happens, the honest-limits
  block gains the **edit/retract asymmetry** (after F1, editing is durable curation; retracting is
  not), and the suite asserts the limit so docs and behaviour cannot drift apart silently. A real
  opt-out belongs in its own reviewed item.
- **F3** — `measure-heal-signal.sh`'s hard-coded `sed -n '2,38p'` replaced with the awk header scan the
  two new scripts already use; `--help` output byte-identical.
- **F4** — the PR body's stale suite counts (45/45, 56/56) corrected to 71/71 and 76/76 by the
  Supervisor.
- **Observation not reproduced:** `test-write-agent-memory.sh` reported as exiting 1 with 0 failures.
  Five consecutive runs were rc=0 / 170 passed. Recorded, not counted as a defect.

**Final:** HEAD `8310d0f`; 71/71 local suites; seed-rules 76/76; doc-currency green; counts unchanged
14/21/41/24; merge invariant exactly 5 surfaces. **PR OPEN and unmerged.**

**`heal_iterations` reached 4, past the default bound of 3.** Every round was driven by a *different*
review channel finding real defects the previous one passed, in decreasing depth. The defects that
survived longest were all **absence-shaped** — a fixture with no 2-segment path, an accumulator running
in only one branch, a presence check that never considered an edited rule. None is visible to a reviewer
reading what IS written, which is why green suites and successive PASS verdicts did not surface them.

### Amendment — heal iteration 5 (external review, `FAIL`)

Fifth channel, `FAIL` on one HIGH plus two smaller findings. **All three reproduced by the Supervisor
before any fix.** Commit `50e5ac2`.

- **F1 (HIGH) — the protocol authority documented the behaviour the previous commit removed.**
  `skills/setup/SKILL.md:52`'s `rules` registry row still read *"per-seed presence, matched on the
  EXACT statement"* — the exact behaviour `8310d0f` replaced because it caused the permanent
  failure state. `git show --stat 8310d0f` confirms `SKILL.md` was **not** in that commit, leaving it
  the only surface in the repo carrying the pre-fix claim.
  Load-bearing, not a footnote: `commands/setup.md:52` is *"Step 0 — Load the protocol authority
  (every invocation)"*, so `/setup rules` read the wrong presence semantics **every time**; and
  `SKILL.md:54` itself mandates that a module's row and its `commands/setup.md` flow change **in the
  same change** — the fix commit violated the file's own rule.
  This is the repo's signature defect class — **a claim no check backs** — landing *inside* the commit
  that fixed an instance of it. Row rewritten to the real two-branch, provenance-keyed semantics,
  including that **retract is not covered**. Sibling sweep run across `skills/` and `commands/`: the
  only other hits are `setup.md:439` (the correct new description) and `insights.md:26` (ordinary
  English) — clean.
- **F2 (MEDIUM) — the empty-batch message asserted a cause that could be false.** Reproduced: header
  `cap 0; 0 emitted, 10 deferred by cap` immediately above *"no theme reached the support floor"* —
  two contradictory diagnoses one line apart, on a tool whose product is honest numbers. Message now
  branches on the real cause and names the deferred count. New assertions (p1)-(p3) plus mutation
  control **M10** observed RED.
- **F3 (LOW)** — `README.md:114`'s "optional integrations" sentence read as exhaustive while omitting
  `memory` (pre-existing) and `rules`; the sibling row at `README.md:215` had been fixed in `efccaf3`.
  Both now listed.

**Final:** HEAD `50e5ac2`; 71/71 suites; harvest 76/76; doc-currency and skills-index-sync green;
counts unchanged 14/21/41/24; merge invariant exactly 5 surfaces. **PR OPEN and unmerged.**

**Standing gap this round exposes (worth its own item, NOT fixed here).** `skills/*/SKILL.md` module
registry rows are **executed** — read verbatim at Step 0 of every `/setup` invocation — yet no gate
covers their behavioural claims: `check-doc-currency.sh` verifies versions and the four counts only,
and `check-command-sync.sh` covers `agents/` ↔ `commands/` mirroring, not `skills/` ↔ `scripts/`.
F1 passed every gate in the repo. This is the recorded `agent-command-mirror-drift-on-fixes` lesson one
directory over: **when a change alters a helper's observable semantics, grep `skills/*/SKILL.md` for the
old semantics in the same commit.** A prose convention in `CLAUDE.md` would help; a mechanical check
would be better, and neither was added here because it is a new gate and out of this PR's scope.

### Amendment — heal iteration 6 (external review, PASS-with-one-MEDIUM)

Sixth channel. **All five findings reproduced by the Supervisor before any fix.** Commit `3292cea`.

- **F1 (MEDIUM) — `/dreaming`'s delivery branch forks from HEAD while the PR bases on the default
  branch, with no pre-flight tying the two together.** Step 1 checked only `.agent/rules` cleanliness,
  the current branch, and `gh` auth; step 2 branched from **current HEAD**; step 5 based the PR on
  `defaultBranchRef`. **Measured on this very branch:** `git merge-base --is-ancestor HEAD origin/main`
  fails — a delivery branch cut here would have carried **16 unrelated commits**.
  Fixed by resolving `$BASE` **in step 1, before branching**, and adding a fourth pre-flight that
  aborts when HEAD is not contained in `origin/$BASE`. **Abort was chosen over branching from base**,
  for a reason worth recording: step 2 branches from HEAD precisely so checkout changes no
  working-tree file, and the cleanliness pre-flight is scoped to `.agent/rules` only — so
  `checkout -b … origin/$BASE` could fail or carry local edits *after* the gate had already passed.
  Freshness is best-effort with the asymmetry stated: a stale `origin/$BASE` can only make the test
  **stricter**, so staleness yields a spurious abort, never a spurious pass.
  **Precision note.** The review cited two falsified claims; only one exists. There is no "the
  delivery branch carries only `.agent/rules/*.json`" sentence (grepped, 0 hits). The real claim is
  about the **commit** and stays literally true — the actual point, now stated in the file, is that
  **a PR presents the branch-versus-base diff, not the commit**, so a clean rules-only commit on a
  non-descended branch still opens a PR full of unrelated changes.
  **Direction error corrected in the fix, not inherited.** The review's prose (and the Supervisor's
  restatement of it) said "at or descended from" the base while citing the command that tests the
  opposite. Being *ahead of* the base is the FAILING case — those extra commits are what the PR would
  list. The file now calls the direction out explicitly so a future reader cannot re-derive it backwards.
- **F2 (LOW)** — `gh pr create`'s literal omitted `--title`/`--body`; non-interactively it errors
  **after the push already succeeded**, landing in the "pushed branch with no PR" state the next
  paragraph names. Both now in the literal, plus `--body-file` for long bodies.
- **F3 (LOW)** — the engine prints `DO NOT DELIVER THIS BATCH` on DISTILLATION FAILURE while its only
  consumer still offered every item. Resolved by making `/dreaming` **refuse to offer a failed batch
  at all** (no Accept, no Pre-push, no branch, no PR) rather than softening the engine — command flow,
  not a repo gate, so no new gate is added. Leaving the script byte-identical also avoided a
  `HARVEST_DRYRUN_SAMPLE.md` regeneration (checked: the sample's run was `distillation: OK`).
- **F4 (LOW)** — the committed example quoted `scope fidelity 98%` alone, the exact flattering-figure
  behaviour the two-number design exists to prevent. Now quotes both (98% of 55 checkable / 72% over
  all 74), and the batch-queue paragraph states the rule: both figures or neither.
- **F5 (LOW)** — `agent-help.md` rendered `rules` as `(status)` while every sibling lists its full set.
  Verified against `commands/setup.md` rather than the review's assertion, and corrected to
  `status | (no-arg → seed)`.
- **PR description** — two stale figures of the Supervisor's own making corrected: `harvest 71/71` →
  `76/76`, and `84 of 85` → `83 of 84` (the pre-`f25717d` denominators).

**Final:** HEAD `3292cea`; 71/71 suites; doc-currency green; counts unchanged 14/21/41/24; merge
invariant exactly 5 surfaces. **PR OPEN and unmerged.**

### Amendment — heal iteration 7 (CI bot review; the lens that had been going silent)

The `claude[bot]` comment of 2026-08-15T09:48Z carried five findings. Four were live; the fifth
(`skills/setup/SKILL.md` staleness) had already been closed by `50e5ac2`. **All four reproduced by the
Supervisor before any fix.** Commits `de8ba42`, `623c260`.

- **F1 — `ALL_MISSES` crashed on a readable ledger.** `select(.self_heal_miss==true)` indexed every
  `categories[]` element with no type guard, so a single non-object element made jq throw; the
  `2>/dev/null || true` swallowed it, `is_num` failed, and the run died **exit 3** on an otherwise
  perfectly readable ledger. Reproduced directly. Inconsistent with the file's own style —
  `harvest_convention_findings` already guards `select((.value|type)=="object")`, and the sibling
  `ALL_FINDINGS` never indexes so it was immune. **83 of 84 records are model-authored, so a malformed
  element is not theoretical.** Guard added; misses count on the committed ledger **95 before, 95
  after**. Mutation control `(M11)` RED — stripping the guard reproduces the exact `exit 3`.
- **F2 — truncating integer division split the PR's own headline number across two committed
  artifacts.** `$((a*100/b))` truncates while `measure-heal-signal.py` uses `round()`, so `107/225`
  (47.55…) printed **47%** in `HARVEST_DRYRUN_SAMPLE.md` and **48%** in `RULES_BASELINE.md`,
  `CHANGELOG.md` and the `CLAUDE.md` banner. A `pct()` round-half-up helper now serves all seven
  reported shares; sample regenerated from a clean clone at pinned `de8ba42` (ledger blob unchanged,
  so every delta is attributable to rounding). Three moved: **107/225 47→48%**, **54/74 72→73%**,
  **5/8 62→63%**. Verified agreement afterwards: sample, baseline, CLAUDE.md and CHANGELOG all state
  **48%**; the surviving `72%` strings are three *different* ratios (`pw=72%`, `26/36`, and the
  term-overlap prose), not a residual inconsistency.
  **Three threshold sites deliberately left truncating**, each annotated at the site: rounding
  `applies-to-cover` would stop the greedy cover early, rounding the dedupe hundredths would let a
  true 1.995 findings-per-rule ship as a passing 2.00 instead of self-reporting DISTILLATION FAILURE,
  and rounding `pw` would change *which candidates are proposed* for a display reason. None is quoted
  elsewhere. Honest limit recorded in code: half-up differs from Python's banker's rounding at exactly
  .5; no cross-quoted ratio hits that case today.
- **F3 — a section docstring claimed a test that did not exist.** Confirmed: only `bc` was stubbed,
  for an unrelated reason. Added `(q1)`, which empties `PATH` of `jq` and asserts exit 3 — invoking
  the interpreter by **absolute path**, since emptying `PATH` can make `bash` itself unfindable and
  produce a 127 masquerading as the gate firing.
- **F4 — a latent repeat of the permanent-failure class, via category instead of statement.**
  `seed_present()` matched the **raw** `seed_table` category while `add-rule.sh` **slugs** before
  writing; all five current categories happen to be valid slugs, so it was invisible. A future
  `Error Handling` row would be stored as `error-handling`, never match, report ABSENT forever and
  re-invoke the writer every run — the exact class this file was already fixed for once in this PR.
  Startup assertion added, mirroring the duplicate-category guard. `add-rule.sh`'s real `slug()` was
  **mirrored verbatim** rather than approximated by `^[a-z0-9-]+$`, which would have accepted `--foo-`
  and `a--b` that slug() still rewrites. Uses a heredoc, not a pipe — a piped `while` body is a
  subshell where `die`'s `exit` would kill only the subshell. **Verified: rc=2 with a diagnostic
  naming the slug that would have been written.**

**Final:** HEAD `623c260`; 71/71 suites (harvest 80/80, seed-rules 80/80); doc-currency green; counts
unchanged 14/21/41/24; merge invariant exactly 5 surfaces. **PR OPEN and unmerged.**

### Companion PR #148 — why the review lens had been silent

Diagnosed while answering "why is CI review not working". `claude-review` had been going green without
reviewing: **9 runs on this PR, all `success`, only 3 posted.** Cause is `--allowed-tools` REPLACING
the action's defaults, so every absent tool is denied and **each denial burns a turn**; the reviewer
exhausts itself before the mandated final post. Runs that posted sat at **36–46% denials**; silent ones
**53–93%** (`50e5ac2`: 13 denials in 14 turns). Six silent runs cost ~$21 for nothing readable.
`is_error:false` and a green check hid all of it.

PR #148 (separate, off `main`, because a workflow edit would make the action skip THIS PR) widens the
allowlist and adds a step that fails the job when a run posts nothing — **not** a required check, so it
reports "not actually reviewed" without blocking merges. **Its own first run caught a defect in
itself**: the action self-skips workflow PRs and exits 0, which the assertion read as "ran and posted
nothing". Fixed; the skip branch uses `case` over a captured variable rather than `git diff | grep -q`,
which returns 141 under `pipefail` **on a match** and would have made the guard a silent no-op.
**#148 cannot validate itself** — verify on the next non-workflow PR, asserting on a posted comment,
never a green check.

### Amendment — fifth review (`FAIL`), verified STALE: all three findings already resolved

The review was accurate but reviewed `3292cea` and flagged `de8ba42` as unpushed. Since then `de8ba42`
and `623c260` both landed and pushed. Local HEAD = origin = PR head = **`623c260`**. Re-verified each
finding against that head rather than trusting the commit titles:

| # | Finding | Status at `623c260` |
|---|---|---|
| 1 | Integer truncation printed `107/225 (47%)` in the sample while the baseline / CHANGELOG / CLAUDE.md said 48% | **RESOLVED** — all four surfaces read 48%; half-up `pct()` helper, with the threshold comparisons deliberately left truncating (they are decisions, not reported shares) |
| 2 | A bare non-object element in `categories[]` made jq throw, swallowed by `2>/dev/null \|\| true`, killing the run `exit 3` on a readable ledger | **RESOLVED, with a control** — pre-fix script at `3292cea` reproduces `rc=3 "could not count findings/misses"` on a one-line fixture; current head returns `rc=0` and counts correctly |
| 3 | The rounding fix moved three transcript lines and `de8ba42` regenerated no doc | **RESOLVED** — `623c260` regenerated it. Falsified from a **clean clone**: 184 lines vs 184, `diff` clean (paths normalised, as disclosed). Prose line 52's hand-written figure now reads `73% (54 of 74)`, matching the transcript |

The recipe pins `de8ba42` while HEAD is `623c260`; verified harmless and correct in effect — output is
**byte-identical** at both shas, since `623c260` touched only docs, and the pin names the commit that
generated the transcript.

The one surviving `(47%)` string is a **historical citation inside the fix's own rationale** at
`harvest-conventions.sh` (the "WHY ROUNDING" comment), not drift.

**Gates at `623c260`:** 71/71 local suites; doc-currency green; merge invariant exactly 5 surfaces;
GitHub `ci` and `claude-review` both green **against `623c260` itself** (head_sha verified, not assumed).
PR still OPEN, unmerged, `BLOCKED`/`REVIEW_REQUIRED`.

**Two nits the reviewer marked non-blocking, left as-is deliberately:** `harvest-conventions.sh` omits
`set -e` (defensible for a report tool, but it is the only script in this batch that does — worth a
header note), and `scope_fidelity` spawns one `awk` per finding (O(n²) process spawns; fine at 74
findings, would matter at 10k). Neither is a correctness issue; both are recorded here rather than
silently dropped.

### Amendment — sixth review (`FAIL`), all five findings real; heal iterations 5–6

Reviewed the current head and found live defects. **All five reproduced by the Supervisor before any fix.**
Commits `e07ce6f`, `cc61ee6`, `8916bda`.

- **F1 (HIGH) — a THIRD copy of the retired disclaimer, in the most authoritative surface.**
  `AGENT_GUIDELINES.md` — the shared agent contract the six `memory: project` prompts point at — still
  said the promotion queue was unwired, while `dreaming.md` and `write-agent-memory.sh` said it was.
  Worse, `CLAUDE.md` and `CHANGELOG.md` both boasted the sweep caught "**and its second copy**".
  **Fixed at root, not by bumping the count:** both surfaces now name all three places the disclaimer
  was found, note that each was found only after a check scoped to the previous one reported clean, and
  state explicitly that **the sweep is not claimed exhaustive** — because asserting completeness is what
  made the survivor findable.
- **F2 (MEDIUM)** — `grep -c . <empty> || echo 0` emitted `0\n0`, garbling the repo-wide justification
  mid-sentence. Fixed with the `|| true` + `is_num` idiom, and the wording now branches: with zero
  recorded paths the scope is **UNRECORDED, not stale** — the old sentence was wrong in kind, not just
  in format.
- **F3 (MEDIUM)** — a bare scalar or array record drove `exit 3` on a ledger `jq empty` accepts (rc=0),
  while the sibling `ALL_MISSES` guard *deliberately* hardened for that class could never run because
  the extractor died first. Fixed at the extractor **and** at two sibling aggregates the finding did not
  name (`.categories[]?` guards the iteration, not the `.categories` index). All four record shapes now
  exit 0; skipped records are counted and reported **only when > 0**.
- **F4 (LOW)** — jq empty-propagation dropped a stamped rule with no `.statement` before the provenance
  branch was reached. Hoisted at both sites.
- **F5** — PR body counts corrected by the Supervisor (now harvest 97/97, seed-rules 84/84) and the
  lone `98%` fidelity citation replaced with both figures, which every committed surface requires.
- **Prevention implemented, not just noted** (the reviewer's pattern proposal): a guard-coverage facet
  in the existing Read-Before-Write Verification Gate — *when you add a guard for a malformed-input
  class, grep every sibling consumer of the same input at every level and state which are covered; a
  guard a sibling's earlier failure preempts is not a guard.* Verified to appear in **exactly one** place.

**Two things the Supervisor caught that the worker reported incorrectly:**

1. **"The transcript did not move" was wrong in method.** It compared baseline-script vs modified-script
   at the *same* commit — blind to doc changes. The `pw=` percentages are measured against the live
   convention surfaces, and `e07ce6f` edited both `CLAUDE.md` and `AGENT_GUIDELINES.md`. What was
   actually true: the recipe **at its pin** still reproduced byte-for-byte (the doc was never broken),
   but HEAD legitimately differed. Re-pinned to `cc61ee6`; verified reproducing from a clean clone.
   The sample now **states this dependency** — pw is measured against the convention surfaces *at the
   pinned commit*, so drift at HEAD is a property of the instrument, not a defect.
2. **A new self-contradicting reason string, found by the Supervisor.** Once a `normative=0` candidate
   crossed 85%, the triage justification printed "only 86% … (< 85%)" — a hard-coded comparison its own
   number refutes, in the sentence a reviewer reads to judge the triage. The bucketing was correct
   throughout; the stated reason was false. Now branches on the condition that actually excluded the
   candidate. No bucket changed (10 / 22 / 3 before and after).

**Final:** HEAD `8916bda`; 71/71 local suites (harvest 97, seed-rules 84); doc-currency green; counts
unchanged 14/21/41/24; merge invariant exactly 5 surfaces; transcript reproduces from a clean clone at
its pin. **PR OPEN and unmerged.**
