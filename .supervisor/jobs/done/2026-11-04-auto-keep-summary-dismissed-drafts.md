# Supervisor Job: Stop asking about summary dismissed-finding drafts — record every summary draft `follow-up` automatically

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (stale worktrees under `.claude/worktrees/` and one prunable scratchpad worktree; none touch this work)
- **Source requirement:** .supervisor/requirements/2026-11-03-102217-stop-asking-about-summary-dismissed-finding-drafts.md
- **Base commit:** e8342b9a855539080e05714cd9ca7ee5e0704466

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2 + python3 + jq scripts and Markdown prose, all existing |
| 2 | Dependency Availability | GO | no new dependency; reuses `dismissed_decide` and `pc_guarded_write` |
| 3 | Architecture Fit | GO | `automate-dismissed.sh` already owns every draft and ledger write; the driver already calls `dismissed-decide` through `ns_call_writer_helper` |
| 4 | Scope vs Supervisor Capability | GO | one coherent change, single worker; many touched files are regenerated golden fixtures and one-line doc edits |
| 5 | Hard Blockers | GO | none |

**Overall Verdict:** GO

## Task
**Goal:** When `dismissed-drafts` writes or leaves a summary draft, it records that draft `follow-up` itself (ledger rows, draft rewrite and one `## Progress` line saying it was kept automatically), so no `AUT-SUMMARY` question reaches the PICK-time ask or the park decision step, while per-finding drafts are asked exactly as today.

**Problem Statement:**
The plugin owner answering `/automate` questions needs to be asked only about dismissed findings that might change the PR, because a summary question costs a turn and nearly never changes anything.
Currently, every item's below-threshold findings go into one summary draft (`…--dismissed-summary*.md`), and the owner is asked about it with gate `AUT-SUMMARY` (Keep summary / Drop summary) at PICK and at the park. The decision ledgers show summary drafts kept 185 of 194 times, and in loomwright-studio summary questions were 120 of 317 asks.
Success looks like zero `AUT-SUMMARY` asks in normal runs, an unchanged per-finding (`AUT-DISMISS` / `AUT-PENDING`) ask count, and the `AUT-SUMMARY` ask surviving only as the fallback when the auto-record could not be written.

**Design decisions (from the requirement, made concrete here):**
- **One mechanism, reused.** `dismissed_decide` gains an optional trailing `--auto` flag, accepted only together with `follow-up` on a summary draft (any other combination is refused, touching nothing). It does exactly what `dismissed-decide … follow-up` does today (ledger `summary-member` rows then the `follow-up` row FIRST, then the `- **Decision:**` rewrite through `pc_guarded_write`). Only the `## Progress` line differs: `dismissed: follow-up <name> — kept automatically (summary below the tracking threshold, no question)`. It does not copy the ledger, rewrite or progress logic.
- **Where it fires in `dismissed-drafts`.** After the manifest loop (every write and retire done), before the final `dismissed-drafts: <n> per-finding + <s> summary (…)` line: every UNDECIDED summary slot of THIS item's prefix on disk is passed to `dismissed_decide … follow-up --auto`. That covers the slot written in this pass, plus an older undecided slot the pass left on disk. The call is the single line `dismissed_decide "$runfile" "$out_abs/$name" follow-up --auto >/dev/null 2>&1`, and its stdout is not printed. Refusal is detected afterwards by re-reading the slot's on-disk `- **Decision:**` value. If it still starts with `undecided`, the auto-record failed: the slot stays undecided and one message line `dismissed-drafts: auto-keep refused <name> — its Decision is still undecided` is printed, still before the summary line. The summary line stays LAST (`ns_dismissed` reads it with `tail -n 1`).
- **Resume (a run started before this change).** The driver's PICK `pending` step, BEFORE its `ns_interactive` early return (so `--non-interactive-fallback` runs decide too), calls `dismissed-decide "$RF" <path> follow-up --auto` once per undecided summary draft of this run. It finds them with `ns_run_undecided`'s `summary` rows, goes through `ns_call_writer_helper`, and wraps each call in an `ns_once` key so a re-entered step never repeats it. It then reads `dismissed-pending` as today.
- **`dismissed-pending` keeps its counting rule (deliberate interpretation of the Scope bullet).** It still counts every draft whose Decision starts with `undecided`. A summary draft is decided `follow-up` by the time it would be counted, so it reports zero for it (AC 4). The one exception is a summary whose auto-record failed, and that one keeps counting. That is the requirement's own error-scenario fallback (AC 8): if the count excluded it, the PICK-time fallback ask could never fire. No summary-name filter is added to `dismissed-pending`.
- **`AUT-SUMMARY` stays in the catalog and in the driver** as that fallback, with its labels unchanged. Only its description text changes.

## Acceptance Criteria
- [ ] 1. Given a drain whose dismissed findings include below-threshold items, when `dismissed-drafts` runs, then the summary draft exists in `proposed/` with `- **Decision:** follow-up`, the ledger `<run_id>.dismissed-decisions` has one `summary-member` row per listed entry followed by a `follow-up` row for it, `## Progress` has exactly one line naming it that contains `kept automatically`, and the final output line is still the `dismissed-drafts: <n> per-finding + <s> summary (<m> listed in summary)` count line (pinned in `test-automate-dismissed.sh`).
- [ ] 2. Given that state, when the driver reaches the park decision step and the next PICK, then no ask with `gate: "AUT-SUMMARY"` is emitted (pinned in the driver tests: the updated golden fixtures plus a leg run by `test-automate-next-step.sh`).
- [ ] 3. Given a per-finding draft over the threshold in the same item, when the decision step runs, then the `AUT-DISMISS` ask is still emitted with its options unchanged (`Follow-up (keep draft)` · `Fix now on this PR` · `Drop`, or without fix-now exactly when it is offered today), and the PICK-time `AUT-PENDING` ask is unchanged.
- [ ] 4. Given an item with only below-threshold findings, when the decision step runs, then no question is asked and `dismissed-pending` reports `0` for that item.
- [ ] 5. Given a second drain on the same item that adds new below-threshold findings, when `dismissed-drafts` runs, then they land in the next summary slot (`…--dismissed-summary-2.md`), which is also recorded `follow-up` automatically, and the earlier summary's file bytes and `summary-member` rows are unchanged. A third run with no new finding writes nothing and appends no ledger row (idempotent).
- [ ] 6. Given a run started before this change with an undecided summary draft already in `proposed/`, when the next PICK runs (interactive or `--non-interactive-fallback`), then that draft is recorded `follow-up` without a question (ledger row plus the `kept automatically` Progress line), and no `AUT-SUMMARY` ask is emitted on that resume.
- [ ] 7. Given the owner deletes a kept summary draft from `proposed/`, when the next `dismissed-drafts` runs, then it does not recreate it (decisions are never reset).
- [ ] 8a. Given the ledger write fails (the ledger exists and is readable but cannot be appended to, e.g. mode 0444, or a missing ledger in an unwritable directory), when `dismissed-drafts` runs, then it still exits 0, the summary stays `undecided`, one `dismissed-drafts: auto-keep refused <name> — …` line precedes the count line, and the existing `AUT-SUMMARY` ask is emitted at the decision step as the fallback.
- [ ] 8b. Given the ledger exists but is unreadable, when `dismissed-drafts` runs, then its behaviour is UNCHANGED: one `dismissed-drafts: skipped — unreadable ledger <path>` line, nothing written, retired or appended, and no auto-keep attempted. `dismissed-pending` prints `unknown`, and an undecided summary already on disk is still asked under `AUT-SUMMARY` (pinned as unchanged).
- [ ] 9. Given `dismissed-decide` is called with `--auto`, when the decision is not `follow-up` or the draft is not a summary draft, then it prints `dismissed-decide: refused — …` and writes nothing (no ledger row, no rewrite, no Progress line).
- [ ] 10. Given the docs, when this change lands, then every surface that describes the `AUT-SUMMARY` ask says summaries are recorded `follow-up` automatically (the ask remaining only as the auto-record fallback) and that the owner drops one by deleting the draft from `proposed/`. Those surfaces are `skills/automate-loop/per-item-loop.md` (PICK-time ask and decision step), `skills/automate-loop/helpers.md` (`dismissed-drafts` / `dismissed-decide` rows), `docs/result-schemas/automate-run.md` (the `ask` gate list), the driver header comment in `scripts/automate-next-step.sh`, `scripts/lane-policy.sh`'s `AUT-SUMMARY` purpose text (containing the phrase `recorded follow-up automatically`) with `docs/LANE_GATES.md` regenerated from it, and the `docs/loop-inventory/automate-loop.md` rows AL-039, AL-251, AL-567, AL-317.
- [ ] 11. Given the PR, when validated, then `bash scripts/ci-local.sh --affected` passes (including `check-token-budget.sh`, `check-doc-currency.sh`, `check-prompt-history-refs.sh`, `test-loop-inventory.sh`, `test-lane-policy.sh`, `test-automate-golden.sh`, `test-automate-helpers-dispatch.sh`), and `bash scripts/check-version-bump.sh` passes with a `changelog.d/` fragment and no hand-edited version file.

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

## File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|--------------------------------|-----------------|------------|
| engine | `loomwright/scripts/automate-dismissed.sh` (1004 — the single authority for draft and ledger writes, per its `SCOPE OF ITS WRITES` header; the auto-keep reuses `dismissed_decide`, so appending is a few lines plus the header) | — | HIGH |
| driver | `loomwright/scripts/automate-next-step.sh` (3305 — the PICK `pending` step and the header step table live here; a few lines in `ns_pending`, no new step arm) | — | HIGH |
| dispatch doc | `loomwright/scripts/automate-helpers.sh` (1181 — only the `#:  dismissed-decide` usage comment gains `[--auto]`; dispatch already passes `"$@"` through), `loomwright/scripts/fixtures/automate-helpers-help/hdr-trail.golden` (13 — the byte-for-byte `--help` copy of that usage line, pinned by `test-automate-helpers-dispatch.sh` check 5) | — | HIGH |
| gate catalog | `loomwright/scripts/lane-policy.sh` (469 — only the `_lp_row AUT-SUMMARY` purpose string), `loomwright/docs/LANE_GATES.md` (100 — regenerated block only, via `lane-policy.sh catalog --markdown`) | — | HIGH |
| tests | `loomwright/scripts/test-automate-dismissed.sh` (1262 — the dismissed-drafts suite's fixtures, `path_of` and the `RF`/ledger setup live here; the new legs extend its A-sections), `loomwright/scripts/test-automate-next-step.sh` (2485 — `leg_*` helpers live in this file, and parts under `test-automate-next-step.d/` only call them; one new leg), `loomwright/scripts/test-automate-next-step.d/04-pick-resume.sh` (83 — the PICK part that calls the new leg) | — | MEDIUM |
| golden fixtures | `loomwright/scripts/fixtures/automate-golden/pick-pending-decisions-ask/` (`next-step.results`, `steps`, `expected.md`, `expected.out`), `…/park-first-decisions-recorded/` (`next-step.results`, `steps`, expected files), and the expected files of `…/reconcile-closeout-merged/`, `…/dismissed-fix-now-re-drain/` and `…/park-first-ready-park/` wherever the auto-keep adds a Progress line or ledger row (regenerated by the suites, never hand-guessed) | — | MEDIUM |
| prose | `loomwright/skills/automate-loop/per-item-loop.md` (106), `loomwright/skills/automate-loop/helpers.md` (61), `loomwright/docs/result-schemas/automate-run.md` (159), `loomwright/docs/loop-inventory/automate-loop.md` (791 — four existing rows edited in place, no new home) | — | HIGH |
| release | — | `changelog.d/auto-keep-summary-dismissed-drafts.md` | HIGH |
| budgets (conditional) | `loomwright/docs/prompt-token-budgets.json` and `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" mirror row — only if `check-token-budget.sh` reports `skills/automate-loop` over its ceiling (measured 48654 vs budget 53519 at base; a few prose sentences should fit) | — | LOW |

> **Validator-owned surfaces:** `docs/LANE_GATES.md`'s catalog block is generated (`<!-- lane-policy catalog: BEGIN (generated by \`lane-policy.sh catalog --markdown\` — do not hand-edit) -->`) and pinned byte-identical by `test-lane-policy.sh` (cat7/cat9): edit `lane-policy.sh`, then regenerate. `docs/loop-inventory/automate-loop.md` is checked by `test-loop-inventory.sh` (LIVE ANCHORS: a row's `q:` anchor must still be found in its prose file, so keep the first words of each edited `per-item-loop.md` paragraph intact). The golden fixtures are compared by `test-automate-golden.sh` and `test-automate-next-step.sh`. `check-doc-currency.sh` and `check-token-budget.sh` scan the prose.

> **No new module:** the one new responsibility (auto-keep a summary draft) has its home in the existing `dismissed_decide` (reused through `--auto`), called from `dismissed_drafts` and the driver's `ns_pending`. No helper is copied.

## Touched-file invariants

> Grounded at base `e8342b9a855539080e05714cd9ca7ee5e0704466`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/automate-dismissed.sh`** — keep: the fail-safe exit `Always exits 0 (a runtime side-effect emitter`, plus `main "$@"` / `exit 0` at the end (every new path returns 0); the write-scope header `SCOPE OF ITS WRITES (the whole list — anything else is a bug)` must name the auto-keep (ledger rows plus the Decision rewrite plus one Progress line per auto-kept summary); ledger-first ordering `Appends the ledger row FIRST` (`--auto` must not reorder it); the unreadable-ledger refuse `if _ledger_unreadable "$ledger"; then echo "$refuse unreadable ledger $ledger"; return 0; fi` and the unwritable refuse `echo "$refuse ledger not writable ($ledger)"; return 0` (the unwritable refuse is AC 8a's fallback); the unreadable-ledger abort in `dismissed_drafts`, `Write nothing, retire nothing, append no ledger row — ONE skipped line`, stays exactly as it is and runs before any auto-keep (AC 8b); the summary fix-now refuse `fix-now is not offered on a summary draft (follow-up|drop)`; the count line stays last `echo "dismissed-drafts: $n per-finding + $s summary ($m listed in summary)"`; idempotence `so an undecided re-run is byte-identical` (now: a decided `follow-up` slot is kept as is, `follow-up` ⇒ kept as is, never rewritten or recreated); bash 3.2 `bash 3.2 / BSD-userland safe`; the summary-slot rule `A summary's decision covers exactly the entries it lists` (in `dismissed_decide`). Reuse: `dismissed_decide` itself (the `summary-member` awk over `- **Key:**` lines, `pc_guarded_write "$prop_abs" "$SELF" "$name"`, the `progress-append` call); never a second copy. Mirror: the TSV/message output contract read by `ns_dismissed` in `automate-next-step.sh` (`sum="$(printf '%s\n' "$out" | tail -n 1)"` and `grep -q "^draft$(printf '\t')"`). Pinned by: `test-automate-dismissed.sh` (`dismissed-pending counts 5 undecided (4 per-finding + summary)`, the A5s block `a decided summary never hides a below-threshold finding it did not list`, `fix-now refused on a summary`). Those assertions change meaning and must be updated to the auto-kept semantics, never deleted without equivalent coverage. Undecided-slot retire legs stay exercised through a pre-seeded undecided slot or the ledger-failure path.
- **`loomwright/scripts/automate-next-step.sh`** — keep: the PICK pending flow `ns_interactive || { NEXT=reconcile; return 0; }` and `[ "$(ns_pending_n)" != 0 ] || { NEXT=reconcile; return 0; }` (the auto-keep goes BEFORE the interactive check); the fallback ask paths `gate=AUT-SUMMARY` and `header: (if .kind == "summary" then "AUT-SUMMARY" else "AUT-DISMISS" end)` stay intact; no new `ns_dispatch` case arm (the schema doc's step list is pinned equal to the arms by `07-doc-mirror.sh`: `one of the driver's \`case\` arms:`). Reuse: `ns_call_writer_helper dismissed-decide "$RF" "$path"`, the `ns_once "once_pd_$(printf '%s' "$path" | cksum | tr -d ' \t')"` idempotence idiom (a distinct key prefix for the auto-keep), and `ns_run_undecided`'s `summary` rows. Mirror: the header step table line `AUT-SUMMARY (one summary draft a call) asks` is the doc of `ns_pending` and changes with it. Pinned by: `test-automate-next-step.d/01-golden-idem-gates.sh` (`Q: AUT-SUMMARY asks carry header AUT-SUMMARY and exactly its two labels`, still true for the fallback), and the golden `pick-pending-decisions-ask` listed in `test-automate-next-step.sh`.
- **`loomwright/scripts/automate-helpers.sh`** — keep: dispatch `dismissed-decide)  exec bash "$(dirname "$0")/automate-dismissed.sh" "$cmd" "$@" ;;` unchanged; only the usage comment `#:  dismissed-decide <runfile> <draft_path> <fix-now|follow-up|drop>` gains `[--auto]`. Mirror: the same line, with `#:  ` replaced by two spaces, in `loomwright/scripts/fixtures/automate-helpers-help/hdr-trail.golden`, updated byte-for-byte at the same position. Pinned by: `test-automate-helpers-dispatch.sh` check 5 (the `--help` output vs the segment goldens).
- **`loomwright/scripts/lane-policy.sh`** — keep: the row's code, policy and labels `_lp_row AUT-SUMMARY  allowed    'Keep summary|Drop summary'` byte-for-byte (pinned by `test-lane-policy.sh`: `'AUT-SUMMARY=Keep summary|Drop summary'`, `(ga9b) an allowed code (AUT-SUMMARY) is not auto-answered`). Only the purpose string changes. Then regenerate `docs/LANE_GATES.md` (`(cat7) LANE_GATES.md drifted from the catalog`).
- **`loomwright/scripts/test-automate-dismissed.sh`, `loomwright/scripts/test-automate-next-step.sh`, `loomwright/scripts/test-automate-next-step.d/04-pick-resume.sh`** — keep: the suites' `ok`/`no` reporting and the `LEG_MSG=""` / `if leg_… "$DRIVER"; then ok …; else no "…: $LEG_MSG"; fi` part idiom; static-only (no network, no `gh`); bash 3.2-safe.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-automate-dismissed.sh` — AC 1: summary draft `Decision: follow-up` + ledger `follow-up` row + one `kept automatically` Progress line | delete `follow-up --auto >/dev/null` in `loomwright/scripts/automate-dismissed.sh` |
| `loomwright/scripts/test-automate-dismissed.sh` — AC 1: the Progress line text | flip `kept automatically (summary` → `kept (summary` in `loomwright/scripts/automate-dismissed.sh` |
| `loomwright/scripts/test-automate-dismissed.sh` — AC 9: `--auto` refused with `drop` / on a per-finding draft | remove the `--auto` guard's refuse branch in `dismissed_decide` (so `--auto` with `drop` deletes the draft) — reviewer-applied |
| `loomwright/scripts/test-automate-dismissed.sh` — AC 8a: unwritable ledger ⇒ summary stays `undecided` + `auto-keep refused` line + exit 0 | delete `auto-keep refused` in `loomwright/scripts/automate-dismissed.sh` |
| `loomwright/scripts/test-automate-dismissed.sh` — AC 8b: unreadable ledger ⇒ unchanged `skipped — unreadable ledger` line, nothing written | move the auto-keep loop above the `abort_line` early return in `dismissed_drafts` — reviewer-applied |
| `loomwright/scripts/test-automate-next-step.sh` — AC 6 leg (pre-existing undecided summary ⇒ recorded at PICK, no AUT-SUMMARY ask) | delete `follow-up --auto` in `loomwright/scripts/automate-next-step.sh` |
| `loomwright/scripts/fixtures/automate-golden/pick-pending-decisions-ask/next-step.results` — no `AUT-SUMMARY` ask at PICK | delete `follow-up --auto` in `loomwright/scripts/automate-next-step.sh` |

> The literals `follow-up --auto >/dev/null` (the auto-keep call in `automate-dismissed.sh`; its stdout is discarded and refusal is read back from the draft's Decision line, per Design decisions), `kept automatically (summary` (the Progress text in `dismissed_decide`), `auto-keep refused` (the refusal message in `automate-dismissed.sh`, on a line that holds only that `printf`) and `follow-up --auto` (the call in `automate-next-step.sh`) must each occur on exactly ONE line of their file, so the machine-applicable rows stay `run-pin-mutations.sh`-appliable. Header comments describe the behaviour without repeating them verbatim.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Auto-keep summary dismissed drafts (engine + driver resume + tests + goldens + docs + changelog fragment) | all | 15 modify (+ regenerated golden fixture files), 1 create | `skills/automate-loop/SKILL.md` (per-item-loop.md, helpers.md), `skills/unit-testing/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/scripts/automate-dismissed.sh", name: "follow-up --auto >/dev/null"}
  - {kind: "symbol", path: "loomwright/scripts/automate-dismissed.sh", name: "kept automatically (summary"}
  - {kind: "symbol", path: "loomwright/scripts/automate-next-step.sh", name: "follow-up --auto"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "[--auto]"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/per-item-loop.md", name: "kept automatically"}
  - {kind: "symbol", path: "loomwright/docs/LANE_GATES.md", name: "recorded follow-up automatically"}
  - {kind: "symbol", path: "loomwright/scripts/fixtures/automate-helpers-help/hdr-trail.golden", name: "[--auto]"}
  - {kind: "file", path: "changelog.d/auto-keep-summary-dismissed-drafts.md"}
requires: []
lanes:
  - "loomwright/scripts/automate-dismissed.sh"
  - "loomwright/scripts/automate-next-step.sh"
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/lane-policy.sh"
  - "loomwright/scripts/test-automate-dismissed.sh"
  - "loomwright/scripts/test-automate-next-step.sh"
  - "loomwright/scripts/test-automate-next-step.d/04-pick-resume.sh"
  - "loomwright/scripts/fixtures/automate-golden/**"
  - "loomwright/scripts/fixtures/automate-helpers-help/hdr-trail.golden"
  - "loomwright/skills/automate-loop/per-item-loop.md"
  - "loomwright/skills/automate-loop/helpers.md"
  - "loomwright/docs/result-schemas/automate-run.md"
  - "loomwright/docs/LANE_GATES.md"
  - "loomwright/docs/loop-inventory/automate-loop.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "changelog.d/auto-keep-summary-dismissed-drafts.md"
external_requires: []
```

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1
- **Estimated batches:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/automate-loop/SKILL.md` (split files `per-item-loop.md`, `helpers.md`), `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| A finding listed in an auto-kept summary whose severity later rises above the threshold inherits the summary's `follow-up` (existing rule: a decided summary that listed it governs it) and so never gets its own `AUT-DISMISS` ask. Before this change the slot was usually still undecided, so the finding moved to its own draft and was asked. | MEDIUM | Out of scope here (the requirement keeps the summary-slot rules unchanged). Name this residual in the changelog fragment and the PR body so the owner can promote a follow-up. Severity changes on the same finding hash across drains are rare. |
| `dismissed-pending` keeps counting an undecided summary, while the requirement's Scope bullet says it "no longer counts a summary draft". This brief's interpretation keeps AC 8's fallback alive and still reports 0 in every normal case (AC 4). | MEDIUM | Stated in Task → Design decisions. Plan Review / the owner can overrule. If overruled, the alternative is a summary-name filter in `dismissed_pending`'s loop, and the park step's fallback still works through `ns_undecided`. |
| The auto-keep's output leaks into `dismissed-drafts`' stdout after the count line, so `ns_dismissed`'s `tail -n 1` records the wrong Progress line. | HIGH | Discard `dismissed_decide`'s stdout in the auto-keep call, print any refusal as a message line BEFORE the count line, and pin "count line is last" in the AC 1 / AC 5 legs. |
| `dismissed-drafts` becomes a run-file writer (its auto-keep `progress-append`), but `ns_dismissed` calls it with a plain `bash "$H" dismissed-drafts …`, not `ns_call_writer_helper`. | LOW | The driver keeps no run-file snapshot across helper calls: `ns_progress` goes through `progress-append`, and `ns_status` re-reads with `cur="$(cat "$RF"; printf x)"`. So the auto-keep line lands before `ns_dismissed`'s own count Progress line and nothing is overwritten. Keep the plain call (its stdout is the TSV ns_dismissed parses), and pin the order (auto-keep line, then the `dismissed-drafts: … summary` line) in the updated goldens. |
| Several golden fixtures change (Progress lines, ledger rows, one fewer ask), and a hand-edited expected file can hide a regression. | MEDIUM | Regenerate every affected golden through its suite's own mechanism and review each diff line. Only the auto-keep lines and the removed `AUT-SUMMARY` round trips may differ. |
| `docs/LANE_GATES.md` hand-edited instead of regenerated fails `test-lane-policy.sh` cat7/cat9. | LOW | Edit `lane-policy.sh`'s purpose string, then regenerate the block with `bash loomwright/scripts/lane-policy.sh catalog --markdown`. |
| Editing the first words of a `per-item-loop.md` paragraph breaks a `docs/loop-inventory/automate-loop.md` `q:` anchor (`test-loop-inventory.sh` LIVE ANCHORS). | LOW | Keep each paragraph's opening (e.g. `**PICK-time pending-decisions ask (automate-followups/12`) and edit only the inventory rows' description cells. Do not add a new history reference (`check-prompt-history-refs.sh` baseline may only go down). |
| Prior lesson: a green `check-doc-currency.sh` is necessary but not sufficient. | LOW | Before hand-back, grep the OLD phrasing (`Keep summary`, `AUT-SUMMARY`, `summary draft`) repo-wide outside `CHANGELOG.md` and `.claude/worktrees/`, and confirm every hit is either updated or describes the fallback. |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-04-auto-keep-summary-dismissed-drafts.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-11-04T10:50:00Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/818
- **Branch:** feature/auto-keep-summary-dismissed-drafts
- **Files changed:** 38
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** armed
- **Summary:** dismissed-drafts now records every undecided summary draft follow-up automatically via dismissed-decide --auto (accepted only with follow-up on a summary draft; refused when the ledger already holds a decision); the driver's PICK resumes pre-change summaries before its non-interactive return; AUT-SUMMARY stays only as the auto-record fallback. Tests, regenerated goldens, docs, LANE_GATES regen and an unfolded changelog fragment. Phase 4.5: round 1 FAIL (2 HIGH fixed in e361692: ledger-decision guard, AC10 wording), round 2 FAIL (test-diagnosis recording only, no code change), round 3 PASS; 7 LOW findings dismissed below the HIGH fix floor.

## Not verified
- **live interactive /automate PICK pending step and park decision step** — exercised only through the driver test harness and goldens; no live session (subtask 1)
