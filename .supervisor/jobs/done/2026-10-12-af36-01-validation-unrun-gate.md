# Supervisor Job: An unrun must-pass running-system Validation step blocks READY (`validation_unrun`)

## Environment
- **Project:** automate-2026-10-12-181635/L1 (lane clone of ai-agent-manager)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/af36-remainder/01-validation-unrun-gate.md
- **Base commit:** 3e354b5adf831a4c1f49e3bad47edec6e624cc90

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2-safe scripts + markdown skill prose, the repo's own stack |
| 2 | Dependency Availability | GO | gh, jq, awk only — already used by `lanes_readiness` |
| 3 | Architecture Fit | GO | extends the existing advisory reader (`lane-readiness`) and the existing `escalation_cause` writer; no new state file |
| 4 | Scope vs Supervisor Capability | CAUTION | ~18 files; split `context-bound` (> 12 files) into 3 subtasks |
| 5 | Hard Blockers | GO | none |

**Overall Verdict:** CAUTION

## Task
**Goal:** Before an item's READY park (`awaiting_merge`, or `ready_for_release` in a lane), the engine checks that every "Running system" step of the item's `## Validation (must pass before merge)` section has pasted evidence in the PR body; an unrun step parks the item `escalated` with `escalation_cause: validation_unrun` naming the step, until the step is evidenced or the owner explicitly waives it.

**Problem Statement:**
The owner needs a lane (or sequential `/automate` item) to be unable to park READY with a must-pass running-system check it did not run, because wave 2's #402 (pa/16) parked READY with its own three-clone `ci-local` check listed under "Not verified", and that check FAILED when the operator ran it (load1 63.6).
Currently, `lane-readiness` only reports such a step as NOT-RUN in an advisory file after the park. This causes READY to mean "unverified" with no engine stop.
Success looks like: replaying #402's park gives `escalated` / `validation_unrun`; a fully evidenced PR parks exactly as before; an owner waiver is recorded with the step and the owner's words; a non-interactive run never waives.

## Acceptance Criteria
- [ ] AC1 — Given pa/16's `## Validation` section (copied verbatim from `.supervisor/requirements/parallel-automate/16-machine-load-guard.md` into a fixture under `loomwright/scripts/fixtures/validation-gate/` — `.supervisor/` is gitignored, so tests read ONLY fixtures; it uses `- ` bullets with a `**Running system:**` entry) and PR #402's body (the step listed under `## Not verified`, also captured as a fixture), when the new gate runs, then it prints the `unrun` verdict naming the Running system step, and the documented GATE step parks `escalated` with `escalation_cause: validation_unrun`, not READY.
- [ ] AC2 — Given a READY drain whose PR body pastes fenced output for every running-system step, when the gate runs, then it prints `ok` and the park is `awaiting_merge` (sequential) or `ready_for_release` (lane) exactly as before.
- [ ] AC3 — Given a recorded owner waiver for the step (a `## Progress` line naming the step and the owner's words, written by the gate's own waive form after the last `picked <item>` line), when the gate runs, then it prints `waived` and the item parks READY; the waiver line is in `## Progress`.
- [ ] AC4 — Given a run that cannot ask (`--non-interactive-fallback`, or a lane question with no owner answer), when the gate prints `unrun`, then the item stays `escalated` — the waiver ask is never auto-answered and the waiver gate is a `human-only` catalog row, never `allowed`.
- [ ] AC5 — Given an item with no running-system Validation step (or no `## Validation` section at all), when the gate runs, then it prints `none` and every park is unchanged.
- [ ] AC6 — Given an unreadable PR body (gh fails) or an unreadable item file, when the gate runs, then it prints `unrun` (fail CLOSED — never `ok`).
- [ ] AC7 — `lane-readiness` and the new gate read Validation steps through ONE shared reader in `automate-lanes.sh` (no second parser); the reader parses numbered (`1. `) AND bullet (`- `) entries, and treats a step whose evidence sits under a "Not verified" / "Not run" PR-body heading as NOT-RUN.
- [ ] AC8 — `validation_unrun` is accepted by `current-escalation` (`ESCALATION_CAUSE_ENUM`) and documented in every closed list (§"Closed enumerations touched"); the merge watcher never reports a `validation_unrun` escalation as `now mergeable` (pinned by a test).
- [ ] AC9 — Mutation control: replacing the gate's verdict with an unconditional `ok` turns the AC1 test leg red (shown in the PR body).

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.
  - id: process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Design (decided at planning — workers implement, do not re-decide)
- **Shared reader** — factor the Validation-entry parse + PR-body match out of `lanes_readiness` (the `# ---- a + e: Validation entries` block and `_lanes_rd_section`) into one function in `automate-lanes.sh`, e.g. `_lanes_validation_rows <item_file> <body_file> <gh_ok>`, printing one TSV row per entry: `n<TAB>title<TAB>kind<TAB>status<TAB>evidence`, `kind` ∈ `running-system|repro|other`, `status` ∈ `PASS|FAIL|NOT-RUN`. `lanes_readiness` keeps its report text and score byte-identical for numbered-entry fixtures (existing U1/Z-F5 legs stay green). Entries: a numbered line (`N. `) OR a top-level `- ` bullet in the `## Validation` section, continuation lines joined; bullet entries are numbered 1..k in order. Title: the first `**…**` span (trailing `:` stripped) else the first 60 chars; the title is then cleaned — every `|` replaced by `/`, tabs/newlines collapsed to one space — so `V<n> <title>` is always a legal `current-escalation --check` value (a test leg pins a `|`-bearing fallback title). Classification: `repro` keeps today's rule on the entry's FIRST line only (so existing numbered-entry reports stay byte-identical); `running-system` reads the title or the full joined entry text. `running-system` = title or entry text contains "running system" (case-insensitive). NOT-RUN additionally when the matched PR-body lines sit under a heading containing "not verified" or "not run" (case-insensitive).
- **New subcommand** `validation-gate <runfile> <item> <pr_url> [--waive <n> --words <text>]` in `automate-lanes.sh`, dispatched from `automate-helpers.sh` like `lane-readiness` (works in a lane AND in a sequential run — it takes the run file and item explicitly, never `_lane_ctx`). Read-only form prints EXACTLY one line, always exit 0 (stdout IS the verdict):
  - `validation-gate: none — no running-system step in <item>` (no `## Validation` section, or none of its entries is running-system)
  - `validation-gate: ok — <k> running-system step(s) evidenced`
  - `validation-gate: waived — V<n> <title>` (every non-PASS running-system step has a waiver line)
  - `validation-gate: unrun — V<n> <title>: <evidence>` (first non-PASS, un-waived running-system step; also an unreadable item file or PR body — fail CLOSED)
  The caller treats anything but `none`/`ok`/`waived` as `unrun`. A FAIL status counts as not evidenced (blocks too).
- **Waiver record** — `--waive <n> --words <text>` appends ONE `## Progress` line through `progress-append`: `validation waived: V<n> <title> — owner: "<text>"` (refuses empty words, a `|`/newline, or an `<n>` that is not a running-system entry; exit 1, nothing written). Waiver lines count only after the LAST `picked <item>` line of the run file. The engine calls the waive form ONLY with an interactive owner's answer; it is never called on a can't-ask path.
- **Owner gate** — new catalog row `AUT-WAIVE`, policy `human-only`, labels `Waive this step|Keep parked` (the owner's words come from the answer's free-text note; "Waive" with no note is re-asked once, then treated as Keep parked). Asked with NO code in its header (human-only convention). Can't-ask ⇒ not asked, stays `escalated`.
- **Park wiring (prose in `per-item-loop.md` §6 step 4 GATE + `lanes.md` Terminal park + `modes-and-merge-gate.md` §9)** — on a drain `READY`, BEFORE the dismissed-findings step and before any `awaiting_merge` / `ready_for_release` park or `gate-eval`: run `validation-gate`; `unrun` ⇒ (interactive) ask AUT-WAIVE; waived ⇒ continue to the normal park; otherwise the item takes the §9 `escalated` park tail with `current-escalation <rf> --cause validation_unrun --check "V<n> <title>"` (sha = PR head). **Re-check:** on `--resume`, RECONCILE re-runs `validation-gate` for a `## Current` item `status: escalated` with `escalation_cause: validation_unrun` whose PR reads OPEN; `ok`/`waived` ⇒ write the READY park the GATE would have written (item-form `current-set`, which drops the escalation line). Document this re-check in `per-item-loop.md` (the GATE subsection), plus a one-line pointer in §6 step 1 RECONCILE of the same file naming the exact conditions (`## Current` `status: escalated`, `escalation_cause: validation_unrun`, PR OPEN) — `resume.md` is NOT edited.

## Touched-file invariants

> Grounded at base `3e354b5adf831a4c1f49e3bad47edec6e624cc90`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/automate-lanes.sh`** — keep: observation fails SAFE, exit 0 (`# Observation (lane-status, lane-feed, lane-readiness) fails SAFE`); every optional report row is an `if`, never `[ -n … ] &&` (`The group's status is its LAST command's, so every optional row is an \`if\``); the gh seam `"$LANES_GH"`; reuse: `_lanes_rd_section`, `_lanes_clip`, `now_utc`, `die`; mirror: the readiness report format `echo "- $vline"` and summary `summary="ready ($pass/$total)"` (consumed by `lane-status`'s `readiness:` row, `rdsum`); dispatch: the `case` arm `lane-readiness) lanes_readiness "$@" ;;`; pinned by: `test-automate-lanes.sh` (`U1 lane-readiness exits 0 and writes the report`, `Z-F5 lane-readiness writes its report when the Validation names no repro`).
- **`loomwright/scripts/automate-helpers.sh`** — keep: the delegation arm `lane-status|lane-feed|lane-readiness|lane-park-notify|lane-wait) exec bash "$(dirname "$0")/automate-lanes.sh" "$cmd" "$@" ;;` (add the new subcommand to it); the help contract `ADDING A SUBCOMMAND? Add its \`#:  \` line beside its`; pinned by: `fixtures/automate-helpers-help/hdr-lanes.golden` (the `#:  ` help line) and `test-automate-helpers-dispatch.sh`.
- **`loomwright/scripts/automate-helpers.d/runfile.sh`** — keep: `ESCALATION_CAUSE_ENUM=" check_pending check_red_unrelated check_red findings other null "` as the ONE enum (add `validation_unrun`); refusals exit 1 with the file byte-unchanged (`current-escalation: refused —`); `--check` refuses `|`/newline only, so `V<n> <title>` is a legal value; pinned by: `test-automate-helpers.sh` current-escalation legs and `fixtures/automate-helpers-help/runfile.golden` (the `current-escalation` help line lists the causes — it gains `validation_unrun`, so regenerate the golden in the same change).
- **`loomwright/scripts/automate-merge-watch.sh`** — keep: the settle re-check runs ONLY for `case "$cause" in check_pending|check_red_unrelated) ;; *) recheck_done=1; return 0 ;; esac` — `validation_unrun` must fall in the `*)` arm (no code change expected; a pin is added); keep: it never reruns, merges, pushes or approves; pinned by: `test-automate-trail.sh` (`we_park check_pending --check ci --run-id 555 --attempt 1 --sha "$ESHA"` legs).
- **`loomwright/scripts/lane-policy.sh`** — keep: `(free text)` gates can never be `allowed`; codes ≤ 12 chars; the catalog is the ONE authority (`Adding, removing or relabelling a row: regenerate loomwright/docs/LANE_GATES.md's table in the SAME`); the decide-time check `policy != "allowed"`; pinned by: `test-lane-policy.sh` (catalog ↔ LANE_GATES.md drift leg).
- **`loomwright/skills/automate-loop/per-item-loop.md` / `modes-and-merge-gate.md` / `lanes.md` / `SKILL.md`** — keep: split-file layout (`scripts/test-automate-loop-split.sh` keeps the index and files in step — edit only inside existing sections, never a heading of a moved section); `§11`'s positive-form grep `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` must still resolve to the same surfaces (add no new positive mention); citations follow `test-citation-drift.sh` (no new bare `file:N`).

## Closed enumerations touched

> Sibling grep at base `3e354b5`: `git grep -n 'check_red_unrelated' -- . ':!CHANGELOG.md'` → 16 files.

- **`validation_unrun`** (sibling: `check_red_unrelated`) — must be named in:
  - `loomwright/scripts/automate-helpers.d/runfile.sh` — `ESCALATION_CAUSE_ENUM=" check_pending check_red_unrelated check_red findings other null "` — extend.
  - `loomwright/scripts/automate-helpers.d/runfile.sh` — the `#:  current-escalation` help line, which lists `check_pending|check_red_unrelated|check_red|findings|other|null` — extend; and `loomwright/scripts/fixtures/automate-helpers-help/runfile.golden` (its mirror) — regenerate in the same change, or the help-golden leg goes red.
  - `loomwright/docs/result-schemas/automate-run.md` — the template line `- escalation_cause: check_pending|check_red_unrelated|check_red|findings|other` and the field table row `` `escalation_cause` | `check_pending` \| `check_red_unrelated` `` — extend both.
  - `loomwright/skills/automate-loop/SKILL.md` — §3 template line `- escalation_cause: check_pending|check_red_unrelated|check_red|findings|other` — extend.
  - `loomwright/skills/automate-loop/per-item-loop.md` / `modes-and-merge-gate.md` — prose naming causes at the escalated park — extend where the causes are listed.
  - `loomwright/docs/result-schemas/review-heal-result.md`, `loomwright/skills/review-heal/SKILL.md` — the DRAIN's own `escalation_cause` enum — no change: `validation_unrun` is an engine-side park cause, never a `REVIEW_HEAL_RESULT` value (state this in the automate-run.md row).
  - `loomwright/scripts/automate-helpers.d/escalation.sh`, `fixtures/automate-helpers-help/escalation.golden`, `incidental.golden`, `fixtures/escalation-cause/README.md` — the check-driven classifier — no change: it never emits `validation_unrun`.
  - `loomwright/scripts/automate-merge-watch.sh` — re-check `case` arm — no change (falls in `*)`), pinned.
  - `loomwright/docs/TELEMETRY.md` — `automate_escalation_recheck` names only re-checked causes — no change.
  - `loomwright/scripts/test-automate-helpers.sh`, `test-automate-trail.sh` — tests — add pins (see below).
- **`AUT-WAIVE`** (sibling: `AUT-LEFTOVER`) — must be named in: `loomwright/scripts/lane-policy.sh` catalog rows — extend; `loomwright/docs/LANE_GATES.md` table (regenerated by `catalog --markdown`) — extend; `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Question-gate inventory" (lists per-gate rows) — add one row: Contexts `MI; MN; HP`, Current cell `new gate (af36-remainder/01)` (as the wave-policy row does), last cell a named outcome — `not asked; the item stays escalated, escalation_cause: validation_unrun` (never the word undefined); the section must stay immediately before `## Failure Escalation Summary` (`test-non-interactive-gates-seam.sh` test (g)).

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `test-automate-lanes.sh` — AC1 #402 replay ⇒ `unrun` | make the gate print its `ok` line unconditionally (replace the verdict computation in `validation-gate` with the `ok` branch) |
| `test-automate-lanes.sh` — "Not verified" heading ⇒ NOT-RUN | delete the not-verified/not-run heading check in the shared reader |
| `test-automate-lanes.sh` — bullet-form Validation parsed | revert the entry parser to the numbered-only `^[0-9]+\. ` match |
| `test-automate-lanes.sh` — `|`-bearing fallback title is cleaned | delete the `|` → `/` replacement in the title cleaner |
| `test-automate-lanes.sh` — gh unreadable ⇒ `unrun` | flip the `gh_ok = 0` branch to PASS |
| `test-automate-lanes.sh` — waiver after last `picked` only | drop the "after the last `picked <item>` line" scoping |
| `test-automate-helpers.sh` — `current-escalation --cause validation_unrun` accepted | delete `validation_unrun` from `ESCALATION_CAUSE_ENUM` |
| `test-automate-trail.sh` — no `now mergeable` for `validation_unrun` | add `validation_unrun` to the merge watcher's `check_pending\|check_red_unrelated` re-check arm |
| `test-lane-policy.sh` — `AUT-WAIVE` is human-only and `decide` answers `human` | flip `AUT-WAIVE`'s policy to `allowed` |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Shared Validation reader + `validation-gate` subcommand + `validation_unrun` enum + tests | AC1, AC2, AC3, AC5, AC6, AC7, AC8, AC9 | 8 modify, 0-2 create | `skills/unit-testing/SKILL.md` | LAUNCHABLE |
| 2 | `AUT-WAIVE` human-only catalog gate + LANE_GATES mirror + test | AC4 | 3 modify | — | LAUNCHABLE |
| 3 | Engine prose + schema docs + gate inventory + changelog fragment | AC1–AC5 (documented park/re-check), AC8 (docs) | 6 modify, 1 create | `skills/automate-loop/SKILL.md` | BLOCKED (by #1, #2) |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "validation-gate"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "_lanes_validation_rows"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.d/runfile.sh", name: "validation_unrun"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "validation-gate"}
  - {kind: "symbol", path: "loomwright/scripts/fixtures/automate-helpers-help/hdr-lanes.golden", name: "validation-gate"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-lanes.sh", name: "validation-gate"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-helpers.sh", name: "validation_unrun"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-trail.sh", name: "validation_unrun"}
requires: []
lanes:
  - "loomwright/scripts/automate-lanes.sh"
  - "loomwright/scripts/test-automate-lanes.sh"
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/automate-helpers.d/runfile.sh"
  - "loomwright/scripts/test-automate-helpers.sh"
  - "loomwright/scripts/fixtures/automate-helpers-help/"
  - "loomwright/scripts/automate-merge-watch.sh"
  - "loomwright/scripts/test-automate-trail.sh"
  - "loomwright/scripts/fixtures/validation-gate/"
external_requires:
  - "gh pr view 402 --json body (captured once into a fixture; tests never call gh)"

# Subtask 2
provides:
  - {kind: "symbol", path: "loomwright/scripts/lane-policy.sh", name: "AUT-WAIVE"}
  - {kind: "symbol", path: "loomwright/docs/LANE_GATES.md", name: "AUT-WAIVE"}
  - {kind: "symbol", path: "loomwright/scripts/test-lane-policy.sh", name: "AUT-WAIVE"}
requires: []
lanes:
  - "loomwright/scripts/lane-policy.sh"
  - "loomwright/scripts/test-lane-policy.sh"
  - "loomwright/docs/LANE_GATES.md"
external_requires: []

# Subtask 3
provides:
  - {kind: "symbol", path: "loomwright/skills/automate-loop/per-item-loop.md", name: "validation-gate"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/modes-and-merge-gate.md", name: "validation_unrun"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/lanes.md", name: "validation-gate"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/SKILL.md", name: "validation_unrun"}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/automate-run.md", name: "validation_unrun"}
  - {kind: "symbol", path: "loomwright/docs/ARCHITECTURE_CONTRACTS.md", name: "AUT-WAIVE"}
  - {kind: "file", path: "changelog.d/af36-01-validation-unrun-gate.md"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "validation-gate"}
  - {from: "2", kind: "symbol", path: "loomwright/scripts/lane-policy.sh", name: "AUT-WAIVE"}
lanes:
  - "loomwright/skills/automate-loop/per-item-loop.md"
  - "loomwright/skills/automate-loop/modes-and-merge-gate.md"
  - "loomwright/skills/automate-loop/lanes.md"
  - "loomwright/skills/automate-loop/SKILL.md"
  - "loomwright/docs/result-schemas/automate-run.md"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "changelog.d/af36-01-validation-unrun-gate.md"
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 3
Subtask 2 ──→ Subtask 3
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none | NO |
| Subtask 1 | Subtask 3 | none (3 documents 1's interface) | YES (requires) |
| Subtask 2 | Subtask 3 | none (3 documents 2's gate) | YES (requires) |

### Batch Plan
- **Batch 1:** Subtask 1, Subtask 2 (parallel)
- **Batch 2:** Subtask 3 (after 1 and 2)
- **Recommended workers:** 2
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md` (static-only tests: stub gh via `LOOMWRIGHT_GH_BIN`, as the U1 legs do) |
| 2 | — |
| 3 | `skills/automate-loop/SKILL.md` (split-file layout; edit sections in place); after editing run `test-automate-loop-split.sh`, `test-non-interactive-gates-seam.sh`, `check-doc-currency.sh`, `test-citation-drift.sh` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Scope vs capability — ~18 files (Feasibility (Phase 2.5)) | MEDIUM | `context-bound` split into 3 subtasks with disjoint lanes |
| Shared-reader refactor changes `lane-readiness` output for existing fixtures | MEDIUM | keep report text byte-identical for numbered entries; existing U1 / Z-F5 legs must stay green unchanged |
| Bullet-entry parsing over-matches nested bullets as steps | MEDIUM | only top-level `- ` at column 0 in `## Validation` starts an entry; indented lines are continuation |
| `--help` golden drift (new `#:  ` line) | LOW | regenerate `hdr-lanes.golden` in the same change; `test-automate-helpers.sh` help leg |
| Skill prose growth breaks a token budget or the split test | LOW | run `check-token-budget.sh` and `test-automate-loop-split.sh` after `git add` |
| `gate-eval` itself does not run the validation gate (a caller that skips the GATE prose bypasses it) | MEDIUM | honest limit stated in `per-item-loop.md`; the GATE prose runs `validation-gate` before `gate-eval` and before every READY park |
| Lane full suite not run (owner rule 2026-10-12) | LOW | targeted suites only; full `ci-local.sh` runs at `wave-build` |
| Real lane running-system run (Validation 3) may be impossible inside this lane | MEDIUM | list under "Not verified" with the reason if not run; owner runs it at wave close |

## Configuration
- **Workers:** 2
- **Mode:** parallel
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-12-af36-01-validation-unrun-gate.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-10-12T18:29:05Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/502
- **Branch:** feature/af36-01-validation-unrun-gate
- **Files changed:** 20
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** validation-gate subcommand + shared Validation reader, validation_unrun escalation cause, human-only AUT-WAIVE gate, engine prose. Phase 4.5 found and fixed 8 reader gaps over 3 rounds; the final fix (207abcd) is unreviewed and one residual shape (a never-run step worded without a listed not-run phrase, followed by an AC2-shaped fence) is disclosed.

## Not verified
- **validation-gate inside a real READY park** — engine prose wiring; the owner runs Validation 3 at wave close (subtask 1)
- **validation-gate live gh pr view call in tests** — tests read only the captured fixture by design (subtask 1)
- **engine AUT-WAIVE ask at the READY park** — only the catalog and the lane decide path were exercised (subtask 2)
- **/automate GATE + RECONCILE re-check executed by a real run** — prose only; the commands were repro'd in a scratch run file (subtask 3)
- **lane AUT-WAIVE relay via a lane-answer note** — needs a live --parallel lane (subtask 3)
