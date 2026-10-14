# Supervisor Job: An unanswered owner question never holds a parked or curated /automate run (automate-speed/01)

## Environment
- **Project:** ai-agent-manager-lanes/automate-2026-10-14-041009/L1 (a `--parallel` lane clone of the loomwright repo)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/automate-speed/01-question-gates-dont-stall.md
- **Base commit:** 1908111687788abfaa4b838902494b5d6d642ebf

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2-safe helper subcommands + markdown protocol prose, same as every other `/automate` change |
| 2 | Dependency Availability | GO | `jq`, `gh` (stubbed in tests), `awk` — all already used by `automate-helpers.sh` |
| 3 | Architecture Fit | GO | §1.5 rule: scriptable steps live in `automate-helpers.sh` subcommands, prose is the spec; this adds two read-only subcommands and reorders prose |
| 4 | Scope vs Supervisor Capability | GO | one coherent change, single worker |
| 5 | Hard Blockers | GO | none; no overlap with sibling lane L2 (its Touches are agents/, self-heal-advisory, async-orchestration, supervisor-readiness, run-pin-mutations, ci-local) |

**Overall Verdict:** GO

## Task
**Goal:** Make `/automate` (a) skip the `AUT-QUEUE` confirm for a `--backlog` source whose resolved Queue is not longer than `--limit` (owner decision D1), and (b) at a READY GATE write the `awaiting_merge` park, arm the merge watcher, notify and release the run lock BEFORE asking the dismissed-findings decisions, with fix-now offered only while the PR is still OPEN and a late fix-now answer turned into a follow-up (owner decisions D2, D3).

**Problem Statement:**
The owner running `/automate` unattended needs the run not to sit on a question whose answer changes nothing that is waiting.
Currently, run `automate-2026-10-13-181331` waited 2h48m on `AUT-QUEUE` for a backlog doc the owner had already curated, and 4h56m on the dismissed-findings decision step, which runs before the park is written — so the PR was mergeable but `## Current` did not read `awaiting_merge`, no merge watcher was armed and no ready notification fired. Together ≈ 63% of a 12h20m item.
Success looks like: a curated short backlog starts processing without asking; a READY PR is parked, watched and announced before any decision question, and a merge while a question is pending closes the item out normally.

## Acceptance Criteria
- [ ] AC1 — Given `automate-helpers.sh queue-confirm backlog <n> <limit>` with integer `n ≤ limit`, when it runs, then it prints exactly `skip — backlog queue <n> ≤ limit <limit>` and exits 0; with `n > limit` it prints `ask`; for source `folder` or `prompt` it prints `ask` at any count; with `--lane-backlog` it prints exactly `skip — lane backlog written by lane-create from the owner's --parallel command`; a non-integer `n`/`limit` or unknown source prints `ask` (fail toward asking); a missing argument exits 1 (usage).
- [ ] AC2 — Given the D1 choice, when the engine's intake prose (`skills/automate-loop/intake.md` §"`--limit N`") is read, then it calls `queue-confirm` once the Queue is resolved, asks `AUT-QUEUE` only on `ask`, and on `skip — <reason>` appends ONE `## Progress` line `skipped AUT-QUEUE: <reason>` (so a backlog skip reads `skipped AUT-QUEUE: backlog queue <n> ≤ limit <N>`, and the lane line stays byte-identical to today's); `--non-interactive-fallback` behaviour is unchanged.
- [ ] AC3 — Given `automate-helpers.sh park-ask-gate <runfile> <item> <pr_url> [--wait <seconds>]` (read-only, run file byte-unchanged, exit 0 except a usage error exit 1), when `## Current` names this item and PR with item `status: awaiting_merge` and a `<run_id>.merge-watch` marker beside the run file carries this `pr_url`, then it prints `ask — fix-now allowed …` only when `gh pr view <pr> --json state` reads `OPEN`, and `ask — fix-now unavailable: …` when it reads `MERGED`, `CLOSED`, anything else, or the read fails (fail closed toward no fix-now push); when the item reads `status: done` (closed out) it prints `ask — fix-now unavailable: closed out`. **Marker race:** the detached watcher writes its marker asynchronously, after its single-instance block (up to 60s when it replaces a live watcher for another PR), so `--wait <s>` polls (1s interval) for a marker carrying THIS `pr_url` for up to `<s>` seconds before judging; the engine passes `--wait 75` (longer than the watcher's 60s replace wait); the default `--wait 0` judges once (tests).
- [ ] AC4 — Given `park-ask-gate` where `## Current`'s item `status` is anything other than `awaiting_merge`/`done` (e.g. `running` — the park not yet written), OR the item status is `awaiting_merge` but no marker carrying this PR appeared within `--wait`, OR `## Current` names another item or PR, OR the run file is missing/unreadable, when it runs, then it prints one `refuse — <reason>` line and the engine never asks (the "park before ask" leg); a refuse leaves the drafts `undecided` with `pending_decisions` set, so the next interactive PICK asks them — the intended outcome also when the watcher already exited (PR CLOSED: marker removed; PR merged and closed out: `## Current` reads `done` and the gate answers `ask — fix-now unavailable: closed out`).
- [ ] AC5 — Given a READY drain with ≥1 drafted dismissed finding in a SEQUENTIAL interactive run (not a lane, not `--non-interactive-fallback`) — BOTH the safe-mode `awaiting_merge` park AND the `--auto-merge` fail-closed park (`gate-eval` printed `PARK: <reason>`, which also parks `awaiting_merge` with the PR open) — when GATE runs, then the prose in `skills/automate-loop/per-item-loop.md` §6 "Dismissed-findings decision step (before the park)" and `modes-and-merge-gate.md` §9 (safe-mode AND `--auto-merge` bullets) orders it: `dismissed-drafts` → write the `awaiting_merge` park (`## Status: paused`, `current-set … --status awaiting_merge --pause-reason awaiting_merge`, `pending_decisions: <n>` / `fix_now_reentered` on `## Current`) → arm the merge watcher → notify → `run-lock.sh release` → `park-ask-gate --wait 75` → ask; and each step writes or relies on a `## Progress` line naming it (`parked awaiting_merge …`, then `dismissed decisions asked after the park — <gate line>`). The `escalated` park keeps today's decide-then-park order.
- [ ] AC6 — Given a `Fix now on this PR` answer, when the engine handles it, then it re-runs `park-ask-gate`: on `ask — fix-now allowed` it re-acquires the run lock (`run-lock.sh acquire --owner automate:<run_id> --session-id <sid>`), writes `## Status: running` and item `status: running`, and runs the ONE fix-now DRAIN → GATE re-pass exactly as today (`fix_now_reentered: true`, at most once per item, re-park); on any other gate line OR a refused lock acquire it records `dismissed-decide <runfile> <draft> follow-up` plus ONE `## Progress` line `fix-now became follow-up: <draft_name> — <reason>` (D3 — never silently dropped, no push after a merge).
- [ ] AC7 — Given the owner merges while a decision question is pending, when the merge watcher's `closeout` runs, then it is not blocked by the engine (the run lock was released before the ask), the item closes out, and the still-unanswered drafts stay `undecided` with `pending_decisions` set; the next interactive PICK asks them (Follow-up / Drop) as today.
- [ ] AC8 — `--non-interactive-fallback` (drafts written, nothing asked, `pending_decisions` recorded, then the park) and lane behaviour (the decision step before the `ready_for_release` park; `escalated` parks) are unchanged; the prose says so explicitly.
- [ ] AC9 — `test-automate-helpers.sh` gains legs for AC1, AC3 and AC4 (with stubbed `gh`; including a delayed-marker leg where the marker appears ~2s after a `--wait 5` call and the gate answers `ask`, and a `--wait 1` leg where it never appears and the gate refuses) plus a prose-order leg that extracts the READY-park ordered list from `per-item-loop.md` and asserts the park write and the watcher precede `park-ask-gate`, which precedes the ask; every new leg has a gated, validated mutant (non-empty, differs from the original, `bash -n` clean) that turns it red; the `--help` goldens `intake.golden` and `resume.golden` carry the two new usage lines; `bash scripts/ci-local.sh` (repo root) is green.
- [ ] AC10 — A changelog fragment `changelog.d/automate-speed-01-question-gates.md` (format: `changelog.d/README.md`, `<!-- bump: minor -->`) is committed; NO version files are edited (parallel wave: the wave's release lane folds fragments).

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

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

## Touched-file invariants

> Grounded at base `1908111687788abfaa4b838902494b5d6d642ebf`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/automate-helpers.sh`** — keep: the dispatcher's closed `case` with the fail-closed default `*) die "unknown subcommand: $cmd (try --help)" ;;`; keep `_AH_HELP_SEGMENTS="config runfile intake resume hdr-gate learning escalation reconcile-status hdr-trail meta plan-waves hdr-lanes"` unchanged (no new family — the two subcommands join the existing `intake` and `resume` families); reuse: `GH="${LOOMWRIGHT_GH_BIN:-gh}"` and `JQ="${LOOMWRIGHT_JQ_BIN:-jq}"` (the test seams) for every `gh`/`jq` call; mirror: the header's READ-ONLY promise (`is READ-ONLY toward the work it`) — both new subcommands write nothing; pinned by: `scripts/test-automate-helpers-dispatch.sh` (`GOLDEN_DIR="$HERE/fixtures/automate-helpers-help"` — --help is the concatenation of the per-segment goldens).
- **`loomwright/scripts/automate-helpers.d/intake.sh`** — keep: every usage line uses the `#:  ` marker (`#:  resolve-backlog  <backlog.md>`), never `#   `; the family's header line `fixture: fixtures/automate-helpers-help/intake.golden` — the new `#:  queue-confirm` line must also be added to `scripts/fixtures/automate-helpers-help/intake.golden` (`  ` prefix, same text); reuse `die` for the usage error (exit 1); bash 3.2-safe (no `${var,,}`, no associative arrays).
- **`loomwright/scripts/automate-helpers.d/resume.sh`** — keep: `reconcile_item` unchanged — its `# Unreadable ⇒ fail closed to the safe non-merged belief.` maps an unreadable read to `awaiting_merge`, which is the WRONG direction for a fix-now push, so `park_ask_gate` must make its OWN `"$GH" pr view "$url" --json state` read and allow fix-now ONLY on the exact `OPEN`; reuse `_resume_title_run_id`'s awk style for reading the run file; the new `#:  park-ask-gate` usage line goes to `scripts/fixtures/automate-helpers-help/resume.golden` too.
- **`loomwright/scripts/test-automate-helpers.sh`** — keep: its harness (`ok() { echo "  ok: $1"; pass=$((pass+1)); }`, `no() { echo "  FAIL: $1"; fail=$((fail+1)); }`, `run_h() { RUN_OUT="$( "$@" 2>/dev/null )"; RUN_RC=$?; }`) and the stubbed-`gh` convention (`Puts a STUBBED`); keep the header's "Covers" list current with the new legs; mutants follow the project lesson: gate every mutant on non-empty + differs-from-original + `bash -n` before trusting it.
- **`loomwright/skills/automate-loop/per-item-loop.md`** — besides §6's dismissed-findings subsection, step 4 GATE restates the order (`run the §6 "Dismissed-findings decision step (before the park)" FIRST: the owner's decisions (and a fix-now re-pass) come before the park state is written`) and the PICK-time pending-decisions ask says fix-now is offered `only at the park … before the merge watcher is armed`; update every restatement in the same change. Keep the heading text `### Dismissed-findings decision step (before the park)` BYTE-UNCHANGED: it is a cited anchor (30 citations repo-wide, including `skills/self-heal-advisory/SKILL.md`, which sibling lane L2 edits); change the body only, saying plainly that a sequential READY park is now written FIRST. Target shape: the existing `**Order — for every GATE outcome that parks with an open PR` list keeps the `escalated` (decide-then-park) order and the non-interactive / lane notes; ADD a separate ordered list right below it under its own bold lead line `**Order — sequential interactive READY park (park first, then ask):**` covering the safe-mode `awaiting_merge` park and the `--auto-merge` fail-closed park — the prose-order test anchors on that lead line and reads only that list; keep fix-now "at most ONCE per item" and the single-open-PR invariant.
- **`loomwright/skills/automate-loop/modes-and-merge-gate.md`** — §9 safe mode currently reads `run the §6 "Dismissed-findings decision step (before the park)" FIRST (owner decisions, and at most one fix-now re-pass, before the park state is written)`, and the `--auto-merge` bullet reads `with the §6 "Dismissed-findings decision step (before the park)" run before that park is written`; update BOTH to the park-first order; keep `` `ESCALATED` never merges and PARKS the run `` and its existing decide-then-park order unchanged.
- **`loomwright/skills/automate-loop/intake.md`** — the opening paragraph restates the Queue-confirm skip contexts (`Under \`--non-interactive-fallback\` the confirmation prompt is skipped`, `inside a lane on its own \`lane-create\` backlog it is skipped too`); add the curated-backlog skip (or point to "`--limit N`") in the same change. Keep `**The Queue confirm is gate \`AUT-QUEUE\`.**` with exactly the options `Process` · `Stop`, and the lane bullet `**Not asked inside a lane on its own backlog (parallel-automate/21 B8).**` (its Progress line text is reused verbatim by `queue-confirm --lane-backlog`, and `scripts/automate-lanes.sh`'s timeline regex matches the `skipped AUT-QUEUE` prefix).
- **`loomwright/skills/automate-loop/SKILL.md`** — the Anti-Patterns bullet `**Parking with dismissed findings nobody decided on.**` (it says the asks come `BEFORE the park is written and the merge watcher is armed` and calls offering fix-now where it `could race an armed watcher or a human merge` the anti-pattern) directly contradicts park-first: rewrite it to name the new guard (ask only after `park-ask-gate`; fix-now only on its `fix-now allowed` line AND a re-acquired run lock; a late fix-now becomes a follow-up). Also §1.5's subcommand table is the closed list of subcommands: add one row each for `queue-confirm` (§2) and `park-ask-gate` (§6); the Quality Gates bullets that restate the `AUT-QUEUE` skip and the dismissed-findings order (`human-confirmed before processing (gate \`AUT-QUEUE\``, `one decision per drafted finding is asked BEFORE the park state is written`) are updated in the same change; `scripts/test-automate-loop-split.sh` keeps the index and split files in step — add no new headings.
- **`loomwright/commands/automate.md`** — step 3 `CONFIRM the Queue` and the `**Dismissed findings:**` bullet restate the behaviour; update both; keep `<!-- split:begin ../skills/automate-loop/command-lanes.md -->` markers intact.
- **`loomwright/docs/ARCHITECTURE_CONTRACTS.md`** — §"Question-gate inventory" row for the `/automate` dismissed-findings decision enumerates its no-ask contexts (`asks nothing; \`pending_decisions: <n>\``); add the `park-ask-gate` `refuse` branch (interactive run, nothing asked, drafts stay undecided, the next interactive PICK asks) in the same change.
- **`loomwright/docs/result-schemas/automate-run.md`** — the `pending_decisions` row says `The count of this run's drafts still \`undecided\` after the gate's decision step`; update it for park-first (written with the park, rewritten after the asks; still undecided drafts stay counted when the PR merged mid-question).

## Closed enumerations touched

> Sibling grep at base `1908111`: `grep -rnF 'resolve-backlog' --exclude=CHANGELOG.md loomwright` → the closed lists among the hits:

- **`queue-confirm`** and **`park-ask-gate`** (sibling: `resolve-backlog` / `reconcile-item`) — must be named in:
  - `loomwright/scripts/automate-helpers.sh` — the `main()` dispatch `case` (`resolve-backlog) resolve_backlog "$@" ;;`) — extend.
  - `loomwright/scripts/fixtures/automate-helpers-help/intake.golden` / `resume.golden` — the --help segment goldens — extend.
  - `loomwright/skills/automate-loop/SKILL.md` — §1.5 table (`| \`resolve-backlog\` | §2 |`) — extend.
  - `loomwright/scripts/automate-helpers.d/reconcile-status.sh`, `automate-trail.sh`, `test-requirement-shape.sh`, `ground-truth-json.md`, `self-heal-advisory/SKILL.md`, `per-item-loop.md` — prose mentions of `resolve-backlog`, not closed lists — no change.
- No new `pause_reason`, item `status` or `## Current` field is added (the park reuses `awaiting_merge`; `pending_decisions`/`fix_now_reentered` already exist).

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `test-automate-helpers.sh` — queue-confirm backlog skip leg | flip the `-le` comparison of count vs limit to `-lt` in `queue_confirm` (n == limit then asks) |
| `test-automate-helpers.sh` — queue-confirm folder/prompt ask leg | delete the source check so any source with `n ≤ limit` skips |
| `test-automate-helpers.sh` — park-ask-gate "park not written" refuse leg | delete the item-status check in `park_ask_gate` (a `running` item then prints `ask …`) |
| `test-automate-helpers.sh` — park-ask-gate watcher-marker refuse leg | delete the merge-watch marker check |
| `test-automate-helpers.sh` — park-ask-gate unreadable-gh leg | treat a failed `gh pr view` as `OPEN` |
| `test-automate-helpers.sh` — prose-order leg (watcher) | move the "arm the merge watcher" step after the `park-ask-gate` step in `per-item-loop.md`'s ordered list |
| `test-automate-helpers.sh` — prose-order leg (park write, requirement V2) | move the `current-set … --status awaiting_merge` park-write step after the `park-ask-gate` / ask step in `per-item-loop.md`'s ordered list |
| `test-automate-helpers.sh` — queue-confirm `--lane-backlog` leg | change one word of the lane skip text in `queue_confirm` |
| `test-automate-helpers.sh` — queue-confirm bad-number / unknown-source leg | drop the integer check so `abc` reaches the arithmetic test (error or skip, not `ask`) |
| `test-automate-helpers.sh` — queue-confirm usage leg | delete the argument-count `die` so a missing argument prints `ask` with exit 0 |
| `test-automate-helpers.sh` — park-ask-gate MERGED/CLOSED legs | allow fix-now on any readable state (drop the exact-`OPEN` comparison) |
| `test-automate-helpers.sh` — park-ask-gate closed-out leg | delete the `done` arm so a `done` item refuses |
| `test-automate-helpers.sh` — park-ask-gate foreign item/PR leg | delete the item/PR match check |
| `test-automate-helpers.sh` — park-ask-gate delayed-marker leg (`--wait`) | ignore `--wait` (judge once) — a marker written 2s after the call then refuses |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | queue-confirm + park-ask-gate helpers, park-first prose, tests, fragment | AC1–AC10 | 14 modify, 1 create | `skills/automate-loop/SKILL.md`, `skills/unit-testing/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.d/intake.sh", name: "queue_confirm"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.d/resume.sh", name: "park_ask_gate"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "queue-confirm)"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "park-ask-gate)"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/per-item-loop.md", name: "park-ask-gate"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/intake.md", name: "queue-confirm"}
  - {kind: "file", path: "changelog.d/automate-speed-01-question-gates.md"}
requires: []
lanes:
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/automate-helpers.d/intake.sh"
  - "loomwright/scripts/automate-helpers.d/resume.sh"
  - "loomwright/scripts/fixtures/automate-helpers-help/intake.golden"
  - "loomwright/scripts/fixtures/automate-helpers-help/resume.golden"
  - "loomwright/scripts/test-automate-helpers.sh"
  - "loomwright/scripts/test-automate-dismissed.sh"
  - "loomwright/skills/automate-loop/intake.md"
  - "loomwright/skills/automate-loop/per-item-loop.md"
  - "loomwright/skills/automate-loop/modes-and-merge-gate.md"
  - "loomwright/skills/automate-loop/SKILL.md"
  - "loomwright/commands/automate.md"
  - "loomwright/docs/result-schemas/automate-run.md"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/docs/LANE_GATES.md"
  - "changelog.d/automate-speed-01-question-gates.md"
external_requires: []
```

### File Impact Map

| Group | Files to Modify | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| helpers | `loomwright/scripts/automate-helpers.sh`, `loomwright/scripts/automate-helpers.d/intake.sh`, `loomwright/scripts/automate-helpers.d/resume.sh`, `loomwright/scripts/fixtures/automate-helpers-help/intake.golden`, `loomwright/scripts/fixtures/automate-helpers-help/resume.golden` | — | HIGH |
| tests | `loomwright/scripts/test-automate-helpers.sh` | — | HIGH |
| protocol prose | `loomwright/skills/automate-loop/intake.md`, `loomwright/skills/automate-loop/per-item-loop.md`, `loomwright/skills/automate-loop/modes-and-merge-gate.md`, `loomwright/skills/automate-loop/SKILL.md`, `loomwright/commands/automate.md`, `loomwright/docs/result-schemas/automate-run.md`, `loomwright/docs/ARCHITECTURE_CONTRACTS.md` | — | HIGH |
| gate catalog | `loomwright/docs/LANE_GATES.md` (only its hand-written prose, never the generated catalog block — the `AUT-QUEUE` purpose text is generated from `scripts/lane-policy.sh catalog`; leave both untouched unless the purpose text becomes wrong, in which case edit `_lp_row AUT-QUEUE` in `lane-policy.sh` and regenerate) | — | LOW |
| release | — | `changelog.d/automate-speed-01-question-gates.md` | HIGH |

> **Validator-owned surfaces:** `scripts/check-doc-currency.sh` scans `commands/` and `skills/`; `scripts/test-automate-loop-split.sh` checks the automate-loop index against its split files; `scripts/test-citation-drift.sh` fails any new bare `file:N` citation — use descriptive anchors in committed prose.

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 (independent)
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | — | none | NO |

### Batch Plan
- **Batch 1:** Subtask 1
- **Recommended workers:** 1
- **Estimated batches:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/automate-loop/SKILL.md` (+ its split files), `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Releasing the run lock before the ask lets the watcher's `closeout` and a fix-now re-pass race | MEDIUM | fix-now re-acquires the lock and re-runs `park-ask-gate` first; a refused acquire or a non-OPEN PR turns the answer into a follow-up (AC6). Honest limit stated in prose: a merge landing between the last gate read and the fix worker's push is not prevented (GitHub accepts a push to a merged PR's branch while it exists) |
| Renaming the cited heading breaks 30 anchors, one in sibling lane L2's file | MEDIUM | heading kept byte-unchanged (Touched-file invariants) |
| `reconcile-item` fails toward `awaiting_merge` on an unreadable read, which would allow a fix-now push | HIGH | `park-ask-gate` makes its own `gh pr view --json state` read and allows fix-now only on exact `OPEN` (AC3, pin mutation row 5) |
| Lane / non-interactive behaviour drifts | MEDIUM | AC8 states both unchanged; the reorder is scoped to the sequential interactive READY park |
| A prose-order test pinned to wording breaks on harmless edits | LOW | anchor the leg on step keywords (`current-set`, `automate-merge-watch.sh`, `park-ask-gate`, `AskUserQuestion`) inside the one ordered list, not on whole sentences |
| Running-system Validation step V3 cannot be evidenced before release (the installed plugin is the old version) | MEDIUM | expected: the GATE's `validation-gate` reports it `unrun` and the owner decides (`AUT-WAIVE`); the PR body lists it under "Not verified" rather than claiming it |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-14-automate-speed-01-question-gates.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-10-14T06:25:15Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/537
- **Branch:** feature/automate-speed-01-question-gates
- **Files changed:** 16
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** queue-confirm + park-ask-gate helpers and park-first READY-park prose (D1–D3); 3 heal iterations fixed 5 findings; the final iteration's fix (D3 batch form) is un-re-reviewed; ground truth 2/2.

## Not verified
- **/automate --backlog running system (requirement Validation V3)** — needs a released plugin; park-then-ask Progress lines not observed in a real run (subtask 1)
- **engine prose execution: park write, notify, lock release, lock re-acquire on fix-now** — inline-loop prose; only helper legs and prose-order pins were run (subtask 1)
