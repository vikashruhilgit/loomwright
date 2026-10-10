# Supervisor Job: Requirement `## Status: done` is written only by the post-merge closeout

## Environment
- **Project:** ai-agent-manager-lanes/automate-2026-10-09-174540/L1 (lane L1 clone of the loomwright repo)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (parallel lane: sibling lanes L2/L3 run concurrently on other items; stay inside the File Impact Map)
- **Source requirement:** .supervisor/requirements/automate-followups/37-done-stamp-before-merge.md
- **Base commit:** e41f657bbd4a29488db42ed3ceb902b15af4a598

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Markdown skill prose + bash scripts + bash self-tests — the repo's native stack |
| 2 | Dependency Availability | GO | git, gh stub, jq already used by `test-automate-trail.sh` fixtures |
| 3 | Architecture Fit | GO | Moves the done claim to the one evidence-gated writer (`closeout`) that already exists |
| 4 | Scope vs Supervisor Capability | GO | One coherent change across ~8 files; single-agent default |
| 5 | Hard Blockers | GO | none |

**Overall Verdict:** GO

## Task
**Goal:** Remove every pre-merge writer of a requirement's `## Status: done`/`done_with_escalation` so the post-merge `closeout` (evidence: PR reads `MERGED`) is the only thing that stamps a requirement done.

**Problem Statement:**
The `/automate` owner needs a requirement's `## Status: done` to mean "its PR merged" because `is_done` drives folder intake, `plan-waves`, `resolve-backlog` and `reconcile-status`.
Currently, Supervisor Phase 4.5's completion tail (step 2.5 "Requirement close-out" in `loomwright/skills/self-heal-advisory/SKILL.md`) stamps the sentinel-led `## Status: done` block while the PR is still OPEN (pa/05 Validation 4, finding F7). The `trail-pr` evidence gate keeps it off `main`, but any other push path (a whole-lane `meta-sync.sh push`) carried a done claim for two never-merged items to `loomwright-meta` (hand-corrected, meta `b8697aa`), and any clone holding the early stamp reads the item as done locally.
Success looks like: after Supervisor + the owned drain with the PR open, the requirement has no `## Status: done` line; `closeout` on `MERGED` writes the same block byte for byte.

**Writers found (Scope 1 — carry this list into the PR body):**
- `loomwright/skills/self-heal-advisory/SKILL.md` Part 2 completion tail, step `2.5. **Requirement close-out (Beads-absent only — fail-safe side-effect):**` — the ONLY pre-merge writer (prose-instructed; runs on PASS / loop-skipped / ESCALATED, before any merge).
- `loomwright/scripts/automate-trail.sh` `closeout` step 5 (`printf '\n<!-- loomwright:requirement-closeout -->\n## Status: done\n…'`) — post-merge, evidence-gated; KEEP byte-for-byte.
- `loomwright/scripts/automate-trail.sh` / `automate-lanes.sh` ABANDONED headings (`done_with_escalation — ABANDONED`) — owner decisions, not done claims for work; untouched.
- `loomwright/scripts/stamp-requirement-status.sh` — writes `## Status: brief-shipped` (deliberately NOT a done value; `is_done` does not match it); untouched except its header comment, which claims the completion tail "is SUPPOSED to stamp `## Status: done`".
- Prose describing the pre-merge stamp as current behaviour: `loomwright/skills/automate-loop/SKILL.md` (Trail-PR "When" bullet: "yet Phase 4.5's completion tail has already stamped its requirement"; Anti-Patterns bullet "Committing a done stamp for unmerged work."), `loomwright/docs/result-schemas/ground-truth-json.md` §"`## Status` (requirement-file close-out convention …)" ("**Who writes it:** Supervisor Phase 4.5 SELF_HEAL completion-tail step 2.5"), `loomwright/docs/PITFALLS.md` (stranded-brief pitfall: "the originating-requirement stamp is **step 2.5**"), `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Agent Invariants" Supervisor row ("completion-tail also stamps an idempotent `## Status: done` close-out on the originating requirement file"), and `loomwright/skills/automate-loop/SKILL.md` §"Post-merge close-out" Steps bullet ("stamp the requirement with the PASS-shape footer of `skills/self-heal-advisory/SKILL.md`'s completion tail" — re-point it at the `closeout` printf in `automate-trail.sh` as the shape's authority).

## Acceptance Criteria
- [ ] Given a Supervisor run reaching the Phase 4.5 completion tail (PASS, loop-skipped or ESCALATED), when the tail runs, then `skills/self-heal-advisory/SKILL.md` instructs NO write of any `## Status:` line (and no `<!-- loomwright:requirement-closeout -->` block) to the source requirement; step 2.5 instead states that the requirement close-out is deferred to the post-merge `closeout` (`automate-helpers.sh closeout`, evidence `MERGED`), that Phase 4.5's verdict is recorded on the brief's `## Outcome` block (and the run file), never on the requirement, and names the honest limit for runs outside `/automate` (no automatic done stamp until a human runs `reconcile-status --apply`, or `/automate --resume`/the merge watcher closes it out; `stamp-requirement-status.sh` still records `brief-shipped`).
- [ ] Given the step-2.5 removal, when a reader greps `grep -A1 -F '<!-- loomwright:requirement-closeout -->' loomwright/skills/self-heal-advisory/SKILL.md | grep '## Status'`, then it prints nothing.
- [ ] Given `closeout` with the PR `MERGED`, when it stamps, then the bytes it appends are unchanged: `printf '\n<!-- loomwright:requirement-closeout -->\n## Status: done\n- **Completed:** %s\n- **Brief:** %s\n- **PR:** %s\n'` stays exactly as is in `automate-trail.sh` (only the step-5 comment that cites "self-heal-advisory tail" as the shape's source is reworded so it no longer points at a block that no longer exists).
- [ ] Given a new leg in `loomwright/scripts/test-automate-trail.sh` (appended as a new section before the final summary; no existing assertion edited), when it runs a fixture that mirrors the end state of a sequential `/autonomous` + owned drain (requirement at `## Status: pending`, its done brief in `.supervisor/jobs/done/` pointing at it, the PR stubbed `OPEN`) and calls `closeout`, then the requirement file is byte-identical and carries no `## Status: done`; when the stub flips to `MERGED` and `closeout` runs again, then the requirement carries exactly one sentinel-led block whose bytes match the `closeout` printf shape (Completed timestamp normalised), and a contract assertion in the same leg checks the self-heal-advisory skill instructs no requirement `## Status:` stamp. The leg FAILS on the base commit (the skill still carries the stamp blocks) and PASSES on the branch — show both in the PR.
- [ ] Given `loomwright/scripts/test-reconcile-jobs.sh` leg 11 (it extracts stamp headings FROM the self-heal skill and asserts `n_stamps -ge 2`), when the skill no longer carries them, then leg 11 extracts the done-claim headings from the remaining writer(s) instead (the `closeout` printf in `automate-trail.sh`, plus the ABANDONED heading the evidence gate exempts) and still proves `is_done` reads each one as done, with its "extractor found something" control kept non-vacuous.
- [ ] Given the existing suites, when `bash scripts/ci-local.sh` runs, then it is green and every pre-existing `test-automate-trail.sh` assertion passes unchanged.
- [ ] Given the doc surfaces listed under "Writers found", when the change lands, then none describes Phase 4.5 as stamping the requirement as current behaviour (historical incident text may stay, reworded as history); `ground-truth-json.md`'s `## Status` section documents only the `closeout` heading-shape block as current and marks the ESCALATED `done_with_escalation` + `- **Heal:**` variant (and the stale `- **Status:**` bullet shape) as historical.
- [ ] Given the release process for a `--parallel` lane, when the PR is opened, then it carries `changelog.d/automate-followups-37-done-stamp-before-merge.md` (`<!-- bump: patch -->` or `minor`) and does NOT run `scripts/bump-version.sh` or edit `plugin.json` / `marketplace.json` / `CHANGELOG.md`.

## Touched-file invariants

> Grounded at base `e41f657bbd4a29488db42ed3ceb902b15af4a598`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/automate-trail.sh`** — keep: the step-5 stamp bytes `printf '\n<!-- loomwright:requirement-closeout -->\n## Status: done\n- **Completed:** %s\n- **Brief:** %s\n- **PR:** %s\n'` and the idempotency guard `elif grep -qF '<!-- loomwright:requirement-closeout -->' "$item"` (`closeout: skipped — already stamped`); keep every `closeout:` output string unchanged — `test-automate-trail.sh` leg CL1 (`co_templates`) requires every template to match a `CLOSEOUT_TABLE` row, so changing or adding a string breaks it; comment-only edit here. pinned by: `scripts/test-automate-trail.sh` `ok "stamp: PASS-shape footer with the done/ brief"`.
- **`loomwright/scripts/test-automate-trail.sh`** — keep: the shadow tally (`_tally_ok` / `_tally_no` cross-check — never reuse `pass`/`fail` as a variable) and the final `echo "test-automate-trail: $pass passed, $fail failed"`; reuse: `closeout_fixture`, `run_closeout`, `ok` / `no`, and the gh stub's `$GH_STUB_DIR/prs.json` (`jq -n … '[{number:7,url:$u,state:"MERGED",…}]'`) — set `state:"OPEN"` for the open phase; add a new section only, do not edit existing assertions.
- **`loomwright/scripts/test-reconcile-jobs.sh`** — keep: leg 11's control rows `11c`–`11f` (`c-handwritten`, `d-open`, `e-lookalike` "donezo", `f-brief-shipped`) and the non-vacuous extractor control `11a`; mirror: the extracted headings must come from the live writer's text (`grep` the file), never hand-typed — the leg's own comment "The stamp fixtures are EXTRACTED FROM THE CONTRACT, never hand-typed". The `closeout` printf is one line with literal `\n` escapes and the ABANDONED heading is built from `AB_PREFIX` with a `$'\xe2\x80\x94'` em dash, so derive the byte-exact headings by evaluating the extracted format/string (e.g. `printf` the extracted format), not by `grep -A1`; keep 11a's `-ge 2` (one closeout `done` heading + one ABANDONED heading).
- **`loomwright/scripts/stamp-requirement-status.sh`** — header-comment edit ONLY. keep: the `brief-shipped` append and the `^## Status` idempotency guard byte-for-byte, and the always-exit-0 fail-safe; fired by: `SessionStart` (via `session-resume.sh`) and `SubagentStop[loomwright:supervisor-runner]` (`hooks.json`); pinned by: `scripts/test-stamp-requirement-status.sh` and `test-reconcile-jobs.sh` `f-brief-shipped`.
- **`loomwright/docs/ARCHITECTURE_CONTRACTS.md`** — sentence-level edit to the Supervisor row only (`completion-tail also stamps an idempotent`); keep the table shape and every other row; check `scripts/check-doc-currency.sh` / `check-token-budget.sh` still pass.
- **`loomwright/skills/self-heal-advisory/SKILL.md`** — keep: completion-tail numbering (steps `2.`, `2.5.`, `2.6.`, `3.` — keep a `2.5.` entry, rewritten, so cross-references such as `docs/PITFALLS.md` "step 2.5" still resolve) and step 2's brief `## Outcome` block (`**Status:** completed_with_escalation`, `**Heal reason:**`); bump frontmatter `version:` / `lastUpdated:` per repo convention (commit `b654cc9` "bump version/lastUpdated on the seven skills this item changed; SKILLS_INDEX regenerated by check-skills-index-sync --write").
- **`loomwright/skills/automate-loop/SKILL.md`** — keep: the Anti-Patterns bold title `- **Committing a done stamp for unmerged work.**` VERBATIM (pinned by `test-automate-trail.sh` `anti-pattern missing`; reword only its body), and every other trail-section phrase `test-automate-trail.sh` greps from this skill (check its `$SKILL` assertions before editing); keep the trail-PR "When" trigger list `Exactly three triggers` and its park list unchanged in substance — only the clause that says Phase 4.5 already stamped the requirement becomes history ("before automate-followups/37 …"); bump `version:` / `lastUpdated:` likewise.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Defer the requirement done stamp to post-merge closeout + pinning test | all | 10 modify, 1 create | `skills/automate-loop/SKILL.md`, `skills/self-heal-advisory/SKILL.md`, `skills/quality-checklist/SKILL.md` | LAUNCHABLE |

### Subtask 1 contract

```yaml
provides:
  - {kind: "file", path: "changelog.d/automate-followups-37-done-stamp-before-merge.md"}
  - {kind: "symbol", path: "loomwright/skills/self-heal-advisory/SKILL.md", name: "Requirement close-out"}
  - {kind: "file", path: "loomwright/scripts/test-automate-trail.sh"}
requires: []
lanes:
  - "loomwright/skills/self-heal-advisory/SKILL.md"
  - "loomwright/skills/automate-loop/SKILL.md"
  - "loomwright/skills/SKILLS_INDEX.md"
  - "loomwright/scripts/automate-trail.sh"
  - "loomwright/scripts/test-automate-trail.sh"
  - "loomwright/scripts/test-reconcile-jobs.sh"
  - "loomwright/scripts/stamp-requirement-status.sh"
  - "loomwright/docs/result-schemas/ground-truth-json.md"
  - "loomwright/docs/PITFALLS.md"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/reconcile-jobs.sh"
  - "loomwright/scripts/test-not-verified-transport-seam.sh"
  - "changelog.d/automate-followups-37-done-stamp-before-merge.md"
external_requires: []
```

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
| 1 | `skills/automate-loop/SKILL.md`, `skills/self-heal-advisory/SKILL.md`, `skills/quality-checklist/SKILL.md` |

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

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| A plain `/supervisor` / `/autonomous` run outside `/automate` no longer auto-stamps `done` on its requirement; `stamp-requirement-status.sh` stamps `brief-shipped` instead, so `resolve-folder` keeps listing it until a human runs `reconcile-status --apply` | MEDIUM | Deliberate (a missed done stamp is recoverable, a false one is not — the evidence-gate rule already in `automate-loop` §6); document as the honest limit in step 2.5 and the PR |
| With step 2.5 gone, `stamp-requirement-status.sh` (SessionStart) may now write `## Status: brief-shipped` on an open-PR requirement; `closeout` later appends the sentinel `## Status: done` block below it (two `## Status:` headings) | LOW | `is_done` matches any `## Status:` line, so the item reads done after merge; note it in the PR; changing either writer is out of scope (closeout bytes must not change) |
| `test-reconcile-jobs.sh` leg 11 becomes vacuous or red once the skill blocks are gone | MEDIUM | Re-point the extractor at the live writers in the same change (AC 5) |
| Parallel lanes: editing files outside the requirement's declared `## Touches` (test-reconcile-jobs.sh, stamp-requirement-status.sh, ground-truth-json.md, PITFALLS.md, SKILLS_INDEX.md) could conflict with a sibling lane | LOW | Keep those edits minimal (comment/sentence level); list them in the PR body |
| Running-system validation 3 (real `/automate` item parked then merged) cannot be produced by the worker | LOW | This item's own lane run is that evidence; the PR states it is pending the owner's merge and shows the base behaviour (the installed plugin's Phase 4.5 still stamps early) as the "before" |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-09-done-stamp-before-merge.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-10-10T03:47:44Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/446
- **Branch:** feature/automate-followups-37-done-stamp-before-merge
- **Files changed:** 14
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** Step 2.5 of self-heal-advisory no longer stamps the requirement; closeout is the sole done writer (printf unchanged). New DS leg (red on e41f657, green on branch), leg 11 re-pointed, docs reworded. Heal fixed two inaccurate honest-limit recovery claims; iteration 3 exposed that --auto-merge gate-merged items (and, by the same class, --parallel lane items) now get no done stamp — documented as a named honest limit in e787cdb, NOT fixed (a SYNC-time closeout would park unattended runs on trail_pr_open). Final fix unreviewed. Owner decision posted on the PR.

## Not verified
- **real /automate item parked with PR OPEN then merged (Phase 4.5 prose executed by a live agent on the new skill)** — needs a live multi-step run on the installed change; this lane's run is the "before" evidence, pending the owner's merge (subtask 1)
