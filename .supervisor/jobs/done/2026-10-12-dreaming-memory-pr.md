# Supervisor Job: /dreaming offers one memory PR (.supervisor/memory/ + .claude/agent-memory/) behind Accept + Pre-push

## Environment
- **Project:** ai-agent-manager-lanes/automate-2026-10-12-181635/L3 (lane clone of ai-agent-manager)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/af36-remainder/04-dreaming-memory-pr.md
- **Base commit:** 3e354b5adf831a4c1f49e3bad47edec6e624cc90

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Prompt-as-program change to a markdown command body; no new tool. |
| 2 | Dependency Availability | GO | Uses only `git`, `gh` and the existing sole writers `/dreaming` already calls. |
| 3 | Architecture Fit | GO | Mirrors the existing rules-PR delivery sequence in `loomwright/commands/dreaming.md` (two gates, explicit staging, HEAD-in-base pre-flight, never merges). |
| 4 | Scope vs Supervisor Capability | GO | 2 doc files modified + 1 fragment created; single-agent. |
| 5 | Hard Blockers | GO | Both stores are git-tracked on main (`git ls-files .supervisor/memory .claude/agent-memory` lists them; `git check-ignore` reports neither ignored). |

**Overall Verdict:** GO

## Task
**Goal:** Give `/dreaming` ONE optional pull request that carries only the `.supervisor/memory/` and `.claude/agent-memory/` changes it wrote in this run, behind the same two-gate shape as the rules PR (per-item Accept, then a separate Pre-push confirmation), and amend every prompt that restates the old rules-only PR-path rule.

**Problem Statement:**
The repo owner needs curated memory to reach `main` without a hand-opened PR (the last was #344), because today `/dreaming` writes accepted project-memory facts, LESSONS and agent-memory promotions in place and leaves them uncommitted.
Currently, `commands/dreaming.md` says the PR path "carries **only** `.agent/rules/*.json` … never any other store", and `commands/agent-help.md` restates it twice. This causes accepted memory to sit uncommitted until someone remembers to open a PR.
Success looks like a documented memory-PR delivery sequence that is reachable only after both gates, stages its two prefixes explicitly, refuses on pre-existing dirt it did not author, never merges, and an agreed one-branch-or-two decision stated in `commands/dreaming.md` with every restatement agreeing.

## Acceptance Criteria
- [ ] **C1 (no push without Pre-push):** Given an accepted memory change and no Pre-push confirmation (declined or ambiguous), when `/dreaming` finishes Phase 4, then the documented flow runs no `git checkout -b`, no commit, no push and no `gh pr create` for memory, and the accepted writes stay in place uncommitted (today's behaviour).
- [ ] **C1 (scope with both gates):** Given both gates passed, when the memory delivery sequence runs, then it stages ONLY the prefixes among `.supervisor/memory` and `.claude/agent-memory` that `git status --porcelain -- <prefix>` shows changed (a store with no changes, or absent from the project, is never named in a pathspec — a literal pathspec on an absent path fails "pathspec did not match"), by explicit pathspec (never `git add -A` / `git add .`), commits with a pathspec-limited `git commit -m … -- <changed prefixes>` so no unrelated pre-staged index entry rides along, verifies `git show --name-only --format= HEAD` holds only those prefixes (else abort before push), and ends at `gh pr create` — it never merges.
- [ ] **Untracked / ignored store ⇒ not offered:** Given a store with changes that is gitignored (`git check-ignore -q <prefix>/<a changed file>`) or otherwise cannot be staged (common in user projects where `.claude/` is ignored without `/setup memory`'s negation), when the memory PR would be offered, then the pre-flight refuses BEFORE any branch exists, naming the store and the reason; nothing is staged, branched or pushed.
- [ ] **One Pre-push question per run:** the memory Pre-push confirmation is ONE question per run, asked after every memory Accept is collected (not per item), defaulting to NOT pushing, an ambiguous answer = no. The section states why: memory Accepts write in place into shared files (`LESSONS.md`, `PROJECT_MEMORY.md`, the provenance JSONL files, the writer-regenerated agent-memory `MEMORY.md`), so a per-item push selection is not expressible with path staging. The dreaming.md header note's "both are per-item" is scoped to the rules PR.
- [ ] **Order when both PRs run:** the rules delivery runs FIRST (its sequence stays byte-identical; dirty memory files carry across its `checkout -b` / `checkout -` untouched because it stages `.agent/rules` only), then the memory delivery. Stated in the section and traced as case (c).
- [ ] **Refusal on foreign dirt:** Given `.supervisor/memory/` or `.claude/agent-memory/` already carried uncommitted changes BEFORE `/dreaming`'s first Phase 4 write (a snapshot of `git status --porcelain -- .supervisor/memory .claude/agent-memory` taken before any Accept writes), when the memory PR would be offered, then `/dreaming` does not offer it, reports why, and writes nothing to git — matching the rules PR's `.agent/rules` refusal.
- [ ] **Section heading:** the memory delivery lives in a new subsection headed exactly `### Memory PR (delivery queue)` in `commands/dreaming.md`, placed after the harvested-rules delivery section.
- [ ] **Pre-flight parity:** the memory delivery reuses the rules PR's pre-flight — `gh` authenticated, `$BASE` resolved from `gh repo view` (never assumed `main`), HEAD contained in `origin/$BASE` (`git merge-base --is-ancestor`), the original branch recorded and restored with `git checkout -` on success AND failure, an existing `dreaming/memory-<slug>` branch (local or remote) aborts, no force push, no reset.
- [ ] **One-branch-or-two decision stated:** `commands/dreaming.md` states that the memory PR and the rules PR are TWO branches (`dreaming/memory-<session_id>` and the unchanged `dreaming/rules-<session_id>`) and gives the reason (the rules PR writes its files ON the delivery branch, the memory PR commits writes already made in place before any branch exists; separate branches let a reviewer merge one without the other and keep the rules sequence byte-identical).
- [ ] **Restatements agree:** every one of these in `commands/dreaming.md` describes both PR paths consistently — the header note "Read-only-until-Accept contract — and the ONE remote-affecting action" (also correct its stale clause "legacy `.claude/agent-memory/` proposals remain paste-to-apply", contradicted by the v15.33.0 sole-writer text elsewhere in the file), the header note "What the PR path may and may not touch", the Phase 4 Accept bullet "are the one path in this command that takes **two** per-item gates", the agent-memory queue's "Nothing here creates a branch: … only the `.agent/rules/` queue below has a PR path", the "Read-Only Contract" bullets ("Git and the remote have exactly ONE reachable action", "User must explicitly approve each proposed item" — noting the memory push gate is one per-run question layered on per-item Accepts — and "Aborting before Accept is always safe — and for the rules PR") and its closing "This contract is non-negotiable" paragraph (per-item Pre-push for rules, one per-run Pre-push for memory), the Approval Option Contract tables (a new gate row for the memory Pre-push confirmation, header `Push`, options `Do not push` · `Push and open a PR`, never recommended), the Example Output's promotion-queue block, and the "When NOT to Use" line; and in `commands/agent-help.md` the `/dreaming` entry's **Purpose:** paragraph ("It is not read-only on the *remote*: an accepted rule proposal can reach a branch…"), its "One remote-affecting action" bullet, its "its one PR carries `.agent/rules/*.json`" line and its "Learn More" line. None still claims the PR path carries `.agent/rules/*.json` only.
- [ ] **Gate inventory:** `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Question-gate inventory" row for `/dreaming` is checked; extend its can't-ask cell to say it also pushes nothing without a Pre-push confirmation (or leave it, recording in the PR body why the existing row already covers the memory gate). Keep whatever `test-non-interactive-gates-seam.sh` pins in that section.
- [ ] **CLAUDE.md stays out:** `commands/dreaming.md` says in the memory-PR section that `CLAUDE.md` edits remain a hand PR (paste-to-apply), and that `.agent/orientation/` promotions and the harness-memory pointer are not carried by the memory PR.
- [ ] **Local-copy honesty:** the memory delivery section states that after `git checkout -` the accepted memory files read the original branch's content again (they live on the delivery branch until the PR merges and is pulled).
- [ ] **No new merge surface:** `gh pr merge` appears nowhere in new `/dreaming` text, and `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` still resolves to exactly the five surfaces CLAUDE.md §"Failure-Mode Invariants" names.
- [ ] A `changelog.d/af36-04-dreaming-memory-pr.md` fragment exists (`<!-- bump: minor -->`, headline, prose body); no hand edit of `plugin.json`, `marketplace.json` or `CHANGELOG.md`, and no `bump-version.sh` run (lane PRs carry fragments only; `wave-build` bumps).
- [ ] The PR body pastes the state trace (a) memory-only, (b) rules-only, (c) both, (d) dirty pre-existing memory path ⇒ refuse, (e) Pre-push declined ⇒ no branch, nothing pushed, (f) a changed store that is gitignored ⇒ refused before any branch — each as the git/gh commands the documented flow runs, in order.

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

> Grounded at base `3e354b5adf831a4c1f49e3bad47edec6e624cc90`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/commands/dreaming.md`** — keep: the rules-PR delivery sequence byte-for-byte (its pre-flight `git merge-base --is-ancestor HEAD "origin/$BASE"`, its branch `dreaming/rules-<session_id>`, its `git add .agent/rules` — **explicitly scoped, never `git add -A`**, and step 7's `**`/dreaming` never merges the PR it opens**`); the Approval Option Contract's 4-option cap and the "never recommended" exclusion for push gates (`**Neither harvested-rule gate may ever carry a recommendation *toward* the remote-affecting action.**`); the frontmatter `description:` line unchanged (it is still true and `loomwright/capabilities.json` is generated from it — changing it forces a `build-capabilities.sh` regen); reuse: the rules sequence's own pre-flight and failure-path wording (`**If a step fails, restore the original branch before reporting`) rather than a new idiom; mirror: `commands/agent-help.md`'s `/dreaming` entry restates the PR-path rule (`**One remote-affecting action, behind two gates.**`) and must agree in the same change; pinned by: `loomwright/scripts/test-curation-status.sh` greps this file for `curation-status.sh record dreaming`, a `| \`--force\`` Parameters row, `unvalidated`, and the `| \`--sessions N\` |` row default — keep all four; `loomwright/scripts/test-add-rule.sh` and `loomwright/scripts/test-harvest-conventions.sh` mirror delivery step 3's WITH-check shape (`CANDIDATE="$(cat <<'LOOMWRIGHT_CHECK_CANDIDATE'`) — keep step 3 unchanged; `loomwright/scripts/test-citation-drift.sh` fails any new bare unpinned `file.ext:<N>` citation.
- **`loomwright/commands/agent-help.md`** — keep: the `/dreaming` entry's `--force` mirror that `test-curation-status.sh` (k) pins (`agent-help.md mirrors /dreaming's --force flag`) and the `/insights` entry's `--force` mention; reuse: the entry's existing bullet style; mirror: whatever `commands/dreaming.md` now states about the two PR paths (branch names, gates, never merges).

- **`loomwright/docs/ARCHITECTURE_CONTRACTS.md`** — keep: the Question-gate inventory table's column shape and the `/dreaming` row anchor (`| \`/dreaming\` per-item gate | \`commands/dreaming.md\``); pinned by: `loomwright/scripts/test-non-interactive-gates-seam.sh` (g) reads that section — run it after any edit.

## Closed enumerations touched

> Sibling grep at base `3e354b5`: `grep -rnF 'Push and open a PR' --exclude=CHANGELOG.md .` → 2 hits in 1 file (`loomwright/commands/dreaming.md`).

- **memory PR — Pre-push confirmation** (sibling: `harvested rule — gate 2 (Pre-push confirmation)`) — must be named in:
  - `loomwright/commands/dreaming.md` — the "Per-class option sets" table (`| harvested rule — gate 2 (Pre-push confirmation) | \`Do not push\` · \`Push and open a PR\` |`) — extend with a memory-PR row using the same two labels in the same order.
  - `loomwright/commands/dreaming.md` — the "Recommendation" table (`| harvested rule — **all three** gate-1/gate-2 choices`) — extend: the memory Pre-push gate is **never** recommended, either option.
  - `loomwright/commands/dreaming.md` — "The one exclusion that is load-bearing" paragraph — extend to cover the memory Pre-push gate (no marker toward the push).
  - `loomwright/commands/dreaming.md` — the `header` list (`` `Rule`, `Push` ``) — no change: the memory gate reuses `Push`.
  - `loomwright/docs/ARCHITECTURE_CONTRACTS.md` — §"Question-gate inventory" row `| \`/dreaming\` per-item gate |` — extend its can't-ask cell (or record "no change: the row already covers every /dreaming ask") — see the Gate inventory AC.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Document the /dreaming memory PR and amend every rules-only restatement | all | 3 modify, 1 create | `skills/quality-checklist/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/commands/dreaming.md", name: "dreaming/memory-<session_id>"}
  - {kind: "symbol", path: "loomwright/commands/dreaming.md", name: "Memory PR (delivery queue)"}
  - {kind: "symbol", path: "loomwright/commands/agent-help.md", name: "dreaming/memory-<session_id>"}
  - {kind: "file", path: "changelog.d/af36-04-dreaming-memory-pr.md"}
requires: []
lanes:
  - "loomwright/commands/dreaming.md"
  - "loomwright/commands/agent-help.md"
  - "changelog.d/af36-04-dreaming-memory-pr.md"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
external_requires:
  - "git and gh CLIs (documented, not executed by this change)"
```

## Parallelism Analysis

single-agent (no fan-out)

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
| 1 | `skills/quality-checklist/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| A delivery sequence that reads correct but sweeps unrelated staged index entries into the memory commit | HIGH | Commit with a pathspec of only the changed prefixes (`git commit -m … -- <changed prefixes>`) and verify `git show --name-only --format= HEAD` lists only the changed prefixes before any push; abort (restore branch, keep the local branch, report) otherwise. |
| Memory writes made in place leave the user's working tree after `git checkout -` | MEDIUM | State it in the section (the content reads the original branch's version until the PR merges and is pulled); do not "fix" it by skipping the checkout. |
| The rules sequence drifts while editing nearby text | MEDIUM | Leave rules delivery steps 1–7 byte-identical; add the memory sequence as its own subsection; `test-add-rule.sh` / `test-harvest-conventions.sh` pin step 3. |
| Another restatement of the rules-only rule is missed | MEDIUM | Before hand-back, `grep -rnE "dreaming/rules-\|its one PR\|only branch-and-PR path\|ONE remote-affecting\|One remote-affecting\|never any other store\|has a PR path\|one path in this command\|for the rules PR\|Nothing here creates a branch\|rules PR delivery queue\|read-only on the \*remote\*\|per-item Pre-push" --include='*.md' --include='*.json' . ` (excluding `.supervisor/` and `CHANGELOG.md`) and reconcile every hit. |
| A user project with an absent or gitignored memory store breaks the delivery after the branch exists | MEDIUM | Pre-flight computes the changed-prefix set and refuses on an ignored/unstageable store BEFORE `git checkout -b`; pathspecs name only changed prefixes. Trace it as case (f). |
| Prompt-as-program edits are only checkable by reading | MEDIUM | The PR body carries the state trace (a)–(f); the running-system validation (a real `/dreaming` in a scratch clone) is listed under "Not verified" if it cannot run inside the lane. |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-12-dreaming-memory-pr.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-10-12T14:07:31Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/499
- **Branch:** feature/af36-04-dreaming-memory-pr
- **Files changed:** 4
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** /dreaming documents a separate dreaming/memory-<session_id> PR (write record kept at Accept, one per-run Pre-push, per-file staging + equality verify, dirt/ignored/pointer refusals, never merges) and every rules-only restatement is aligned. 3 heal iterations, all findings fixed; the final fix (964d3fb, out-of-repo pointer exclusion) was not re-reviewed (bound reached). Ground truth 2/2 pass.

## Not verified
- **interactive /dreaming run in a scratch clone (accept memory, decline Pre-push, re-run and confirm)** — prompt-as-program change; lane cannot drive interactive /dreaming against a throwaway remote (subtask 1)
