# Supervisor Job: Version-bump script + changelog fragments (parallel-automate/01)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (1 untracked: this run's automate run file), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (installed plugin 15.115.0, repo main at 15.115.4 — sessions run the installed plugin; this item only adds maintainer tooling, so no engine behaviour is affected)
- **Source requirement:** .supervisor/requirements/parallel-automate/01-version-bump-script.md
- **Base commit:** 47d833ec9966eb6b1539a86f554ca7247ebead91

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash + jq maintainer script beside `scripts/validate-version.sh` / `scripts/check-doc-currency.sh`; same stack. |
| 2 | Dependency Availability | GO | `jq`, `git`, `bash` present; `loomwright/scripts/write-lessons.sh supersede` exists with `--replacement`/`--confirm`. |
| 3 | Architecture Fit | GO | Root `scripts/` is maintainer tooling (not shipped in the plugin); root tests are wired as explicit `ci.yml` steps. |
| 4 | Scope vs Supervisor Capability | CAUTION | ~20 files, but most are one-line mechanical appends; ONE subtask (the inline Single-Agent Path, chosen by subtask count — the only path that works under `/automate`, since `/autonomous` does not forward `--sequential`). |
| 5 | Hard Blockers | CAUTION | `write-lessons.sh` refuses to run from a linked git worktree (exit 3, its F1 safety invariant) (Feasibility (Phase 2.5) #5) | HIGH | ONE subtask ⇒ Supervisor's Single-Agent Path (selected by subtask count, no flag needed — `/autonomous` forwards only `--base-branch`/`--non-interactive`/`--cheap`/`--max-tokens`), which runs inline in the primary checkout, not a linked worktree. Tripwire: if `write-lessons.sh` still exits 3, STOP and report — never hand-edit `LESSONS.md` (a hand edit is dropped by `read-lessons.sh`), never bump. |
| ~20 changed files in one worker context (Feasibility (Phase 2.5) #4) | MEDIUM | Most are one-line appends; the fixed in-subtask order commits after each step, so a context-limit stop resumes from a clean, committed point (resume the worker, never respawn). |
**Overall Verdict:** CAUTION

## Task
**Goal:** Add `scripts/bump-version.sh` + `changelog.d/` fragments so one deterministic script performs every version bump, sweep the real bump-instruction sites to point at it, guard against a bump that skipped the script, and bump this PR with the new script.

**Problem Statement:**
The maintainer and every `/automate` worker need a version bump that cannot collide, because two open PRs that each hand-edit `plugin.json`, `marketplace.json` and `CHANGELOG.md` conflict and can claim the same number (2026-09-27: #284 took v15.107.0, the next PR was renumbered to v15.108.0).
Currently the bump is a hand edit; `scripts/validate-version.sh` only checks that the three files agree, and the instruction to bump lives in `.supervisor/memory/LESSONS.md` (`[16ffd26d]`, `[a642885b]`) and pending requirements' Scope lines, not in any agent prompt.
Success looks like: feature PRs carry only a `changelog.d/<slug>.md` fragment, and one `bash scripts/bump-version.sh` produces the whole bump (two manifests + one CHANGELOG entry, fragments removed), refusing loudly on any inconsistency.

## Acceptance Criteria
- [ ] AC1: Given a tree with one `changelog.d/<slug>.md` fragment, when `bash scripts/bump-version.sh` runs, then the diff touches exactly `loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `CHANGELOG.md` and the removed fragment, and `git diff` of `marketplace.json` is ONE changed line (the loomwright entry's `"version"`); the stackpack and mysql-mcp entries are byte-unchanged (targeted in-place replacement, never a `jq .` round-trip — verified at base commit: `marketplace.json` stores the stackpack and mysql-mcp description dashes as the six-character JSON escape backslash-u-2014, and `jq .` re-encodes both as a raw em-dash, changing two unrelated lines).
- [ ] AC2: Given `patch|minor|major` (or no argument), when the script runs, then the version is incremented per semver (no argument ⇒ the highest `<!-- bump: X -->` any fragment requests, default `patch`), every fragment except `changelog.d/README.md` is folded in filename order into ONE new top entry of `CHANGELOG.md` in the existing `**vX.Y.Z — <headline>:** <body>` shape (inserted above the current newest entry, below the header paragraphs), and the folded fragments are deleted.
- [ ] AC3: Given no fragment, OR the three files disagree before the bump, when the script runs, then it exits 1 and all three files are byte-unchanged; `--dry-run` prints the planned version + entry and writes nothing.
- [ ] AC4: Given any failure mid-bump (including a read-only `.claude-plugin/` DIRECTORY — a read-only file does not block a rename), when the script runs, then `plugin.json`, `marketplace.json`, `CHANGELOG.md` AND every folded fragment are restored byte-identical and it exits 1. Order is fixed: back up the three files and the fragments → write all three to temp files → rename → delete the folded fragments → run `scripts/validate-version.sh` and `scripts/check-doc-currency.sh` (fragments are already gone, so the AC5 guard cannot trip on the script's own bump) → a failure of either validator restores the three files AND re-creates the fragments, exits 1.
- [ ] AC5: Given the WORKING-TREE `plugin.json` version (so an uncommitted hand bump is caught locally) differs from the version at `git merge-base HEAD origin/main` (i.e. THIS branch changed the version) AND a `changelog.d/*.md` fragment other than `README.md` is still present, when `scripts/check-doc-currency.sh` runs, then it fails (a bump that did not go through the script). A branch that is merely BEHIND main (main bumped after the fork, branch carries only a fragment) stays green. When `origin/main` or the merge base is unresolvable it skips this one check with a visible note rather than failing. The header states the honest limits: a hand bump with no fragment is undetectable, and the requirement's literal 'differs from origin/main' wording was narrowed to the merge base so a stale-but-unbumped branch is not a false positive.
- [ ] AC6: Given `scripts/test-bump-version.sh` (hermetic temp repo), when run under `/bin/bash` 3.2 on macOS and GNU bash, then it covers: patch/minor/major arithmetic; three-file agreement; the other two marketplace entries byte-unchanged; the `marketplace.json` diff is exactly one line; fragments folded+removed in filename order; the highest `<!-- bump: X -->` wins; no-fragment refusal byte-unchanged; pre-existing disagreement refused; `--dry-run` writes nothing; the read-only-`.claude-plugin/`-directory mutation control (all three files AND the fragments unchanged); a validator failure after the rename restores the three files AND the fragments; **two branches cut from the same base, each adding only its own fragment, merge into each other with no conflict**; the AC5 guard fires on a branch that changed the version with a fragment present and stays green on a merely-behind branch (with a control that turns red when the guard is removed); and a **`jq .` mutation control** — swapping the targeted edit for a `jq .` round-trip makes the one-changed-line and byte-unchanged assertions fail (a self-check inside the test, not a manual step). The script exposes a test seam for its post-write validators (e.g. an env var naming the validator commands, defaulting to the real `scripts/validate-version.sh` + `scripts/check-doc-currency.sh`) so the hermetic test can inject a failing validator; the PR body states the seam.
- [ ] AC7: Given the instruction sites, when the sweep is done, then the two LESSONS entries `[16ffd26d]` and `[a642885b]` are superseded via `loomwright/scripts/write-lessons.sh supersede --hash <h> --replacement "…" --confirm` (provenance-chained, never a hand edit), `AGENT_GUIDELINES.md`'s doc-currency paragraph and `CLAUDE.md`'s "Doc currency is CI-enforced" paragraph each gain a one-line, version-free pointer to `scripts/bump-version.sh` + `changelog.d/` (no literal version — advisory house rule); `changelog.d/README.md` documents the fragment format, the optional `<!-- bump: X -->` first line and the P7 who-runs-it rule (sequential PR: the author bumps as the LAST commit; parallel wave: lanes write fragments only and the release lane bumps; an unfolded fragment merged without a bump is legal and folds into the next bump); and exactly these six pending/parked requirement files gain the appended line `bump = write a \`changelog.d/\` fragment and run \`scripts/bump-version.sh\`` once (idempotent): `agnostic-phase1/01-ratchet-hardening.md`, `agnostic-phase1/02-completion-evidence-integrity.md`, `agnostic-phase1/03-silent-script-failures.md`, `agnostic-phase1/04-non-interactive-gates.md`, `agnostic-phase1/05-docs-and-hygiene-sweep.md`, `token-economy/07-verify-spec-replay.md` (all under `.supervisor/requirements/`). Excluded with the reason named in the PR body: any file with a done heading anywhere; `brief-shipped` files; files whose only match is `schema_version bump`; `selvedge-extraction/_BACKLOG.md` (versions other plugins — a non-goal); `token-economy-overview.md` and `auto-2026-06-18-…` (no Scope line, historical); `token-economy/06-model-router-gate.md` (owner-abandoned 2026-08-30 — `# abandoned:` Queue row in run `automate-2026-07-14-151145`; it has no status heading, so the run file is the record); this queue's own 01 and 06. The two supersedes pass the FULL 64-char `content_hash` from `.supervisor/memory/.lessons-provenance.jsonl` (`16ffd26d009e7b21103f800299d2e6c057b901558db34b0e3a565e8b75a655b0`, `a642885b06877f53c27b9e65244ea1983a9ed848309ec7382c720cda646199b0` — `--hash` rejects 8-char ids), and each `--replacement` text contains the literal `bump-version.sh`.
- [ ] AC8: Given this PR, when it is finalized, then its LAST commit is the output of running `bash scripts/bump-version.sh` with this item's own fragment (`<!-- bump: minor -->`), so the PR carries the new version in all three files and no fragment remains.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | bump-version.sh + fragments + doc-currency guard + tests, instruction-site sweep, and this PR's own bump | all | 15 modify (scripts/check-doc-currency.sh, scripts/test-check-doc-currency.sh, 6 requirement files, LESSONS.md + .lessons-provenance.jsonl, AGENT_GUIDELINES.md, CLAUDE.md, CHANGELOG.md, 2 manifests), 3 create (scripts/bump-version.sh, scripts/test-bump-version.sh, changelog.d/README.md) + 1 fragment created then folded | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md`, `skills/commit/SKILL.md` | LAUNCHABLE |

**Fixed in-subtask order (commit after each step):** (a) `scripts/bump-version.sh` + `scripts/test-bump-version.sh` + `changelog.d/README.md` (fragment format, `<!-- bump: X -->`, P7 rule) + the AC5 guard in `scripts/check-doc-currency.sh` and its test → full test loop green; (b) AGENT_GUIDELINES.md / CLAUDE.md pointers + the six requirement-file amendments; (c) both `write-lessons.sh supersede` calls (if either exits 3, STOP and report — never hand-edit LESSONS.md, never bump); (d) write `changelog.d/parallel-automate-01-version-bump-script.md` with `<!-- bump: minor -->`; (e) `bash scripts/bump-version.sh` — its result is the PR's LAST commit.

### Subtask Contracts

```yaml
# Subtask 1 — whole item, single-agent (LAUNCHABLE)
provides:
  - {kind: "file", path: "scripts/bump-version.sh"}
  - {kind: "file", path: "scripts/test-bump-version.sh"}
  - {kind: "file", path: "changelog.d/README.md"}
  - {kind: "symbol", path: "scripts/check-doc-currency.sh", name: "changelog.d"}
  - {kind: "symbol", path: "AGENT_GUIDELINES.md", name: "bump-version.sh"}
  - {kind: "symbol", path: "CLAUDE.md", name: "bump-version.sh"}
  - {kind: "symbol", path: ".supervisor/memory/LESSONS.md", name: "bump-version.sh"}
requires: []
lanes:
  - "scripts/bump-version.sh"
  - "scripts/test-bump-version.sh"
  - "changelog.d/*.md"            # new top-level directory created by this subtask
  - "scripts/check-doc-currency.sh"
  - "scripts/test-check-doc-currency.sh"
  - "AGENT_GUIDELINES.md"
  - "CLAUDE.md"
  - ".supervisor/memory/LESSONS.md"
  - ".supervisor/memory/.lessons-provenance.jsonl"
  - ".supervisor/requirements/agnostic-phase1/*.md"
  - ".supervisor/requirements/token-economy/07-verify-spec-replay.md"
  - "CHANGELOG.md"
  - ".claude-plugin/marketplace.json"
  - "loomwright/.claude-plugin/plugin.json"
external_requires:
  - "jq, git, bash 3.2 (macOS) and GNU bash (CI)"
```

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md`, `skills/commit/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| `write-lessons.sh` refuses to run from a linked git worktree (exit 3, its F1 safety invariant) (Feasibility (Phase 2.5) #5) | HIGH | ONE subtask ⇒ Supervisor's Single-Agent Path (selected by subtask count, no flag needed — `/autonomous` forwards only `--base-branch`/`--non-interactive`/`--cheap`/`--max-tokens`), which runs inline in the primary checkout, not a linked worktree. Tripwire: if `write-lessons.sh` still exits 3, STOP and report — never hand-edit `LESSONS.md` (a hand edit is dropped by `read-lessons.sh`), never bump. |
| ~20 changed files in one worker context (Feasibility (Phase 2.5) #4) | MEDIUM | Most are one-line appends; the fixed in-subtask order commits after each step, so a context-limit stop resumes from a clean, committed point (resume the worker, never respawn). |
| CI `actions/checkout` default depth 1 — `origin/main` is not resolvable on a PR run, so the AC5 guard would be silently absent or falsely fail | MEDIUM | The guard skips with a visible note when `origin/main` does not resolve (fail-safe for a doc gate) and the header names this limit; the ci.yml wiring is a separate follow-up PR anyway (requirement Scope 7). |
| Premise drift: `CLAUDE.md`, `AGENT_GUIDELINES.md` and `PROJECT_MEMORY.md` carry no "~8 doc surfaces" pointer today (verified by grep at base commit); only `LESSONS.md` does (Cited-line premise / Phase 3) | MEDIUM | AC7 adds a one-line pointer to the existing doc-currency paragraphs instead of editing a pointer that does not exist; `PROJECT_MEMORY.md` is left unchanged (nothing to correct) and the PR body says so. |
| "Pending" requirement detection: several files carry an early `## Status: pending` and a LATER closeout `## Status: done` heading (e.g. `automate-followups/13-…`) | MEDIUM | Use the `is_done` predicate (any `^## Status: (done|done_with_escalation)` heading anywhere in the file), not the first status line. |
| CHANGELOG entry insertion point and shape — the top entry is a single long `**vX.Y.Z — headline:** body` paragraph after two header paragraphs | MEDIUM | Insert before the first line matching `^\*\*v[0-9]+\.[0-9]+\.[0-9]+ — `; test asserts the header paragraphs are byte-unchanged. |
| bash 3.2 / BSD vs GNU userland (`sed -i`, `mktemp`, `stat`) | MEDIUM | No `sed -i`; write via temp file + `mv`; run the test under `/bin/bash` on macOS and note CI (Ubuntu) parity; avoid `${var//[[:space:]]/}` on large strings. |
| `ci.yml` step for `test-bump-version.sh` must NOT be in this PR (a workflow edit makes `claude-code-action` skip its review) | LOW | Out of scope here; the PR body names the one-line follow-up PR. |
| The version this PR bumps to depends on `main` at bump time (lesson `[16ffd26d]`) | LOW | The bump is the LAST commit and reads the live `plugin.json`; if `main` moves before merge: revert/drop the bump commit (which restores the fragment), rebase onto `main`, then re-run `bash scripts/bump-version.sh` — a bare re-run after the fold hits AC3's no-fragment refusal by design. |

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
/supervisor job: .supervisor/jobs/pending/2026-10-01-parallel-automate-01-version-bump-script.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-10-01T15:47:54Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/327
- **Branch:** feature/parallel-automate-01-version-bump-script
- **Files changed:** 17
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** bump-version.sh + changelog.d fragments + bump-without-script guard + instruction-site sweep; PR bumped to v15.116.0 by its own script. Phase 4.5 consistency_audit PASS on iteration 1 (1 MEDIUM + 1 LOW dismissed below the fix floor); ground_truth 2/2; risk high_risk=true (size/content heuristics). Default drain suppressed by /automate (auto_review=false) — the engine owns the drain.

## Not verified
- **scripts/test-bump-version.sh and the bump-fragment guard on Ubuntu/GNU userland CI** — ci.yml step deliberately left to a follow-up PR; ran on macOS /bin/bash 3.2 and GNU bash 5.3 only (subtask 1)
- **bump-fragment guard on a shallow CI checkout** — no CI run; skip-with-NOTE path covered by the hermetic test only (subtask 1)
