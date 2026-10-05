# Supervisor Job: gate-eval condition 7 pins the checkout to the PR head before trusting the rules verdict

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes-v2/s2-b
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/automate-followups/16-gate-eval-cond7-pin-head.md
- **Base commit:** c1692b091ef1747c6d600cd6cc2073277981f880

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2-portable shell + jq + git, same as the rest of `automate-helpers.sh` |
| 2 | Dependency Availability | GO | only `git rev-parse` / `git status --porcelain` — git is already a hard dependency of cond 6 (`classify-risk.sh`) |
| 3 | Architecture Fit | GO | mirrors cond 6, which already pins `live_head` (`classify-risk.sh main "$live_head" --root "$root"`); a fail-CLOSED PARK with a named reason is the gate's established shape |
| 4 | Scope vs Supervisor Capability | GO | one function + its test section + one skill paragraph — single subtask |
| 5 | Hard Blockers | CAUTION | the existing Section E/R test harness passes `--root "$WD"` where `$WD` is NOT a git checkout and the stubbed `headRefOid` is the fake `abc123`; every pre-existing MERGE-expecting case will PARK on the new pin unless the harness gains a real git checkout whose HEAD the stub reports |

**Overall Verdict:** CAUTION

## Task
**Goal:** Make `gate-eval` condition 7 fail CLOSED unless the `--root` checkout it hands `rules-gate-verdict.sh` is AT the live PR head SHA and has no uncommitted changes, so the plugin's sole `gh pr merge --squash` executor can never merge on a rules verdict computed against different bytes.

**Problem Statement:**
The `--auto-merge` operator needs condition 7 (no stamped, gate-countable `must`-rule check fails) to judge the exact commit being merged, because that gate is the only thing standing between a failing bound house-rule check and an unattended squash-merge.
Currently, `gate_eval` in `loomwright/scripts/automate-helpers.sh` runs `rules-gate-verdict.sh --root "$root"` on whatever is checked out at `--root` (default `.`): nothing compares `git -C "$root" rev-parse HEAD` to `live_head` and nothing checks the tree is clean (the only `root` lines are `local root="."` and the `--root)` arg parse). Condition 6 pins the head; condition 7 does not. This causes a stale checkout (still on an older commit, or on `main`) or a dirty one (a local un-pushed fix to a bound file) to answer `ok` for a head whose bound files would fail — and the gate then MERGEs.
Success looks like: a stale-HEAD checkout and a dirty-tree checkout each PARK with a named reason and 0 merges, while an at-head, clean checkout keeps today's verdict behaviour exactly (every existing condition-7 case unchanged), proved by tests with a control.

## Acceptance Criteria
- [ ] AC1 — Given every condition 1–6 holds and `git -C "$root" rev-parse HEAD` differs from the live `headRefOid` condition 2 confirmed, when `gate-eval` reaches condition 7, then it prints `PARK: rules_gate_head_mismatch`, runs no `gh pr merge`, and does NOT invoke `rules-gate-verdict.sh` (the pin runs before the helper call).
- [ ] AC2 — Given `--root` is not a git checkout, or `git rev-parse HEAD` fails / prints nothing, when condition 7 runs, then it PARKs `rules_gate_head_mismatch` (unreadable HEAD fails CLOSED, never treated as a match).
- [ ] AC3 — Given HEAD == live head but `git -C "$root" status --porcelain` reports any tracked modification, staged change, or untracked non-ignored file OUTSIDE the engine-owned paths `.supervisor/` and `.claude/agent-memory/`, when condition 7 runs, then it prints `PARK: rules_gate_dirty_tree`, runs no merge, and does not invoke the helper; a failing `git status` also PARKs `rules_gate_dirty_tree`.
- [ ] AC4 — Given HEAD == live head and the only changes are under `.supervisor/` (the engine's own run file / sidecars, which the loop legitimately rewrites mid-item and which are TRACKED in repos not in branch mode) or `.claude/agent-memory/` (agents with `memory: project` — code-reviewer among them, which runs in Phase 4.5 and the drain — write there, and `setup-memory.sh`'s managed block can make it tracked), when condition 7 runs, then the cleanliness check passes and the verdict is evaluated exactly as today.
- [ ] AC5 — Given an at-head, clean checkout, when condition 7 runs, then every existing Section R outcome (R1–R10: fail/ok/unresolved/unstamped variants/cmd_disabled/unreadable shapes/refused ctx keys/precedence/mutants/end-to-end) is unchanged, and condition 6 still takes precedence over condition 7.
- [ ] AC6 — Given the new pin, when `loomwright/scripts/test-automate-helpers.sh` runs, then it contains a stale-HEAD leg and a dirty-tree leg that each assert PARK + 0 merges + helper not called, a `.supervisor/`-only-dirty leg and a `.claude/agent-memory/`-only-dirty leg that each assert the verdict still decides, and a gated mutation control (mutant non-empty, differs from original, `bash -n` clean) proving that deleting the pin turns the stale-HEAD leg into a MERGE (i.e. the leg can fail).
- [ ] AC7 — Given the new reasons, when a reader opens `loomwright/skills/automate-loop/SKILL.md` §10 condition 7 and the `gate_eval` header comment's PARK-reason list in `automate-helpers.sh`, then both name `rules_gate_head_mismatch` and `rules_gate_dirty_tree`, state the pin is fail-CLOSED with no override, and state the `.supervisor/` + `.claude/agent-memory/` exclusions and their honest limit, and state that the normal path passes the pin because the owned inline `/review-pr` drain checks the PR branch out on the main-thread checkout (so the checkout is at the PR head when GATE runs); the `test-rules-gate-seams.sh` P6 pin set (automate-loop §10 carries condition 7) still passes, extended if needed to pin the new reason.
- [ ] AC8 — Given the release convention, when the PR is opened, then it carries `changelog.d/automate-followups-16-gate-eval-cond7-pin-head.md` and does NOT hand-edit `plugin.json`, `marketplace.json`, or `CHANGELOG.md`; `bash scripts/ci-local.sh` is green.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Pin cond 7 to the PR head + clean tree, with tests, docs and changelog fragment | AC1–AC8 | 4 modify, 1 create | `skills/unit-testing/SKILL.md`, `skills/automate-loop/SKILL.md`, `skills/error-handling/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "rules_gate_head_mismatch"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "rules_gate_dirty_tree"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-helpers.sh", name: "rules_gate_head_mismatch"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-helpers.sh", name: "rules_gate_dirty_tree"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/SKILL.md", name: "rules_gate_head_mismatch"}
  - {kind: "file", path: "changelog.d/automate-followups-16-gate-eval-cond7-pin-head.md"}
requires: []
lanes:
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/test-automate-helpers.sh"
  - "loomwright/scripts/test-rules-gate-seams.sh"
  - "loomwright/skills/automate-loop/SKILL.md"
  - "changelog.d/automate-followups-16-gate-eval-cond7-pin-head.md"
external_requires:
  - "git (rev-parse, status --porcelain with a :(exclude) pathspec) — already required by classify-risk.sh"
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

## Implementation Notes (for the worker)
- **Where:** `gate_eval` in `loomwright/scripts/automate-helpers.sh`, at the top of the condition-7 block (after condition 6's PARK, BEFORE the `rules-gate-verdict.sh` invocation). Use the gate's existing `cmd || rc=$?` shape for every git call (a failing command substitution in a plain assignment aborts under `set -e` with no line printed — the comment beside the cond-7 helper call already explains this).
- **Head pin:** `root_head="$(git -C "$root" rev-parse HEAD 2>/dev/null)" || rc=$?`; PARK `rules_gate_head_mismatch` unless rc==0, non-empty, and `== "$live_head"` (`live_head` is the value condition 2 already confirmed equals `ready_sha`).
- **Clean tree:** `git -C "$root" status --porcelain -- . ':(exclude).supervisor' ':(exclude).claude/agent-memory'` (pathspec relative to `$root`'s top level — verify it behaves the same when `$root` is a subdirectory, or resolve `--show-toplevel` first). Any output line ⇒ PARK `rules_gate_dirty_tree`; non-zero exit ⇒ PARK `rules_gate_dirty_tree`. Untracked non-ignored files count as dirty (an untracked file can be read by a bound check); gitignored files do not.
- **Test harness:** the Section E/R harness currently passes `--root "$WD"` (a plain temp dir holding ctx/fixture files) and stubs `headRefOid: "abc123"`. Give the harness a real git checkout (e.g. a `$WD/checkout` repo with one commit, its fixture files outside it or ignored) and make `reset_live` write that checkout's real HEAD sha into `pr-view.json` and `pass_ctx`'s `ready_sha`, so every pre-existing case keeps its outcome; update `R_EXP_ROOT` and R10's end-to-end roots accordingly (R10 already runs against real checkouts — confirm each is at the stubbed head and clean). Keep the existing `J_MOVE_SHA` (cond 2) case meaningful.
- **Mutation control:** follow the file's existing gated-mutant pattern (Section R's R9 / the cond-6 control): mutant non-empty, differs from the original, `bash -n` clean, and the UNMUTATED copy passes first.
- **Docs:** `loomwright/skills/automate-loop/SKILL.md` §10 condition 7 (add the pin as a sub-bullet before the verdict list: both reasons, no override, the `.supervisor/` + `.claude/agent-memory/` exclusions and their honest limit, and the at-head premise — the owned inline `/review-pr` drain leaves the main-thread checkout on the PR branch, so the normal path passes the pin) and the `gate_eval` header comment's "New reasons added by condition 7" list. Do NOT add a bare unpinned `file:N` citation in committed prose (`test-citation-drift.sh` fails it).
- **Changelog:** one `changelog.d/automate-followups-16-gate-eval-cond7-pin-head.md` fragment in the format `changelog.d/README.md` documents; never run `bump-version.sh` in this PR.

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md`, `skills/automate-loop/SKILL.md` (§10 condition 7 — the spec the helper conforms to), `skills/error-handling/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): existing gate tests use a non-git `--root` with a fake head SHA, so the new pin would turn every MERGE-expecting case into a PARK | HIGH | Re-baseline the harness onto a real git checkout whose HEAD the `gh` stub reports (Implementation Notes); run the whole file and confirm every pre-existing `ok` line still prints before adding the new legs |
| Over-strict cleanliness: in non-branch-mode repos `.supervisor/automate/<run_id>.md` and its sidecars are TRACKED and rewritten mid-item, so a whole-tree check would park every `--auto-merge` | HIGH | Exclude `.supervisor/` from the porcelain check (AC4) and test it; honest limit documented in §10: a rule `binds` path under `.supervisor/` is not covered by the cleanliness pin |
| Over-strict cleanliness (plan review): agents with `memory: project` (code-reviewer runs in Phase 4.5 and in the drain) write `.claude/agent-memory/`, which `setup-memory.sh`'s managed block can make TRACKED — a memory write mid-item would park every `--auto-merge` `rules_gate_dirty_tree` | MEDIUM | Also exclude `.claude/agent-memory/` (AC3/AC4) and test it; any OTHER engine/agent write outside both paths still fails CLOSED by design — documented as a deliberate limit in §10 |
| Unstated premise (plan review): the pin assumes the checkout is at `live_head` at GATE | LOW | True on the normal path — the owned inline `/review-pr` drain checks the PR branch out on the main-thread checkout (`skills/review-heal/SKILL.md`, PR-URL→branch resolution); §10 states it (AC7) so a later change to that checkout behaviour is visibly coupled to this pin |
| Under-strict cleanliness: ignoring untracked files would let an untracked file read by a bound check change the verdict | MEDIUM | Count untracked non-ignored files as dirty (AC3) |
| `git` pathspec `:(exclude)` semantics differ when `--root` is a subdirectory of the repo | MEDIUM | Resolve the top level or test a subdirectory root; keep bash 3.2 / BSD-portable |
| A pin placed after the helper call would still execute the helper on a stale tree (wasted check + a misleading `rules-called.log`) | LOW | Pin first; AC1/AC3 assert the helper is NOT called |
| Merge-gate surface is high-risk per `classify-risk.sh` — `--auto-merge` will (correctly) park this PR | LOW | Expected: safe-mode run, human merge |
| Lesson (testing): a mutation control is evidence only if the mutant is valid | MEDIUM | Gate the mutant on non-empty + differs + `bash -n` before trusting it |

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

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-05-gate-eval-cond7-pin-head.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-10-05T03:16:44Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/384
- **Branch:** feature/automate-followups-16-gate-eval-cond7-pin-head
- **Files changed:** 6
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** gate-eval cond 7 now parks rules_gate_head_mismatch (HEAD at --root ≠ live PR head / unreadable) and rules_gate_dirty_tree (local state diverging from the PR head outside .supervisor/ and .claude/agent-memory/, incl. hidden index flags, non-committed/non-global ignore sources, hostile git env) before calling rules-gate-verdict.sh; harness on a real checkout, R11 legs + gated mutants; Phase 4.5 PASS after 2 fix iterations, 10 findings dismissed (3 MEDIUM it-3 gaps recorded as follow-up candidates).

## Not verified
- **live /automate --auto-merge GATE against a real PR** — no live PR/runtime; behaviour proven only with a stubbed gh and real local git checkouts (subtask 1)
