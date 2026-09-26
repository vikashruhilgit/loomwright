# Supervisor Job: Executable rule candidates — proposal, human-gated acceptance, content-keyed replay

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: automate-hardening-2026-09-22 (worktree; the run's isolation branch, base main @ 4348036)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/twin-loop/08-executable-rule-candidates.md

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Bash script edits + one new stamp-write/verify path in `rules-check.sh` + markdown doc edits — matches the plugin's existing tech stack exactly. |
| 2 | Dependency Availability | GO | No new dependency; reuses `jq`, `sha256sum`/`shasum`/`openssl` (already used by `exec-acceptance-lib.sh` for an analogous hash), the existing `~/.claude/loomwright/` user-scope directory convention (established by red-team-hardening/02's `egress.json` and the pre-existing `trusted-actors.json`). |
| 3 | Architecture Fit | GO | Extends TWO already-shipped precedents exactly: (a) the harvester's existing DATA-not-EXECUTED proposal discipline (`check: null`, AC9b), adding a sibling `check_candidate` DATA field, never touching `check`; (b) the content-keyed stamp PATTERN red-team-hardening/05 established for brief `cmd:` bullets — but explicitly a NEW, separate stamp file in user scope (NOT the brief-embedded `sha256:` line that mechanism uses), because `.agent/rules/*.json` is repo-committed and model-writable inside a PR (decision R2), unlike a Launch-Pad-authored brief that only saves after an explicit human Phase 6 confirmation. |
| 4 | Scope vs Supervisor Capability | GO | 12-file, single cohesive transport-chain change (harvester proposal → human accept-with-check → human-confirmed user-scope stamp → Phase 4.5 advisory replay). Every file depends on the same `check_candidate`/stamp shapes — splitting would only add coordination overhead, and 12 stays at/under the `>12`-file context-bound split threshold (`skills/supervisor-readiness/SKILL.md` §Decomposition Threshold). |
| 5 | Hard Blockers | GO | No migration, no credentials. Both stated dependencies (red-team-hardening/02's user-scope location, red-team-hardening/05's stamp-hash pattern) are already merged to `main`. |

**Overall Verdict:** GO

## Task
**Goal:** A convention an LLM reviewer catches once should not need an LLM review to catch it again when it's grep-shaped. `harvest-conventions.sh` proposes a `check_candidate` STRING as pure DATA (never executed, never written into the live `check` field) for findings whose evidence shares a literal grep-able token/path across ≥3 supporting findings. `/dreaming`'s Accept step gains a second button ("Accept rule WITH check") that calls the byte-unchanged `add-rule.sh --check <candidate> --confirm`. A human who wants checks to actually run explicitly executes `/rules check --confirm` once, which writes a content-keyed stamp OUTSIDE the repo (user scope — never a file the repo or a worker can write). Phase 4.5 then replays ONLY checks matching that stamp, non-interactively, reporting one advisory `rules_check:` line that NEVER changes `heal_decision`.

**Problem Statement:**
`.agent/rules/` holds 3 rules, all `check: null` — `harvest-conventions.sh` deliberately never synthesises a shell command into `check` (AC9b), `rules-check.sh` (the sole execution path for `must`-rule checks) is human-invoked only and reached by no runtime seam, and Phase 4.5 runs `run-ground-truth.sh` for a brief's `cmd:` bullets but never `rules-check.sh`. A convention a reviewer discovers once therefore gets re-caught by an LLM review every single time it recurs, costing a review turn it may not get.

## Acceptance Criteria
- [ ] **`loomwright/scripts/harvest-conventions.sh`** — when ≥3 supporting findings of one proposal carry the SAME literal token or path in their evidence, emit `check_candidate: <string>` in the human-facing proposal block AND as a `check_candidate` key in the proposal JSON; `check` stays `null` (the existing AC9b line is kept, reworded to note a candidate MAY be shown beside it). Build the candidate from a FIXED TEMPLATE ALLOWLIST ONLY — `! grep -rnE '<pattern>' <paths>` (absence) and `test "$(grep -rlE '<pattern>' <paths> | wc -l)" -le <N>` (bound) — where the finding's literal text appears ONLY inside the single-quoted pattern. **Reject, never escape:** any finding text containing `'`, `$(`, a backtick, `;`, `|`, `&`, or a newline yields NO candidate (the proposal is emitted without one) — the harvester must never become a shell-quoting engine. `<paths>` come from the finding's own `changed_paths`/file fields, never from free text.
- [ ] **`loomwright/commands/dreaming.md`** (and the underlying Accept flow it documents) — Accept gains a SECOND button/option alongside the existing "Accept rule": **"Accept rule WITH check"**, which shows the candidate VERBATIM and, only on that explicit second choice, calls `add-rule.sh --check "<candidate>" --confirm`. The default "Accept rule" path is BYTE-UNCHANGED (still `check: null`). `add-rule.sh` itself is NOT modified — it already supports `--check` (verified: line ~211).
- [ ] **`loomwright/scripts/rules-check.sh`** gains a stamp WRITE on a successful `--confirm` run (interactive `y` or the existing `--confirm`/`RULES_CHECK_CONFIRM=1` path): write `{repo_root, hash, ts}` to the SAME user-scope directory red-team-hardening/02 established (`~/.claude/loomwright/`, verified: `resolve-egress-config.sh:131` — a NEW file there, e.g. `rules-check-stamp.json`, NOT `egress.json` itself, which is telemetry-specific) — `hash` = sha256 over the sorted `id\tcheck\n` lines of the must-rules the SAME selection jq chose (reuse that exact selection query so stamp and execution can never disagree on the set covered). **New flag `--if-stamped` (non-interactive, no prompt):** compute the live hash the same way, compare to the stamp for this `repo_root`; equal ⇒ run the checks with no prompt, same output shape as `--confirm`; unequal or absent ⇒ print `[SKIP] all (unstamped)` and `Checks passed: 0/0`, exit 0. `--no-cmd` still wins over `--if-stamped` exactly as it wins over `--confirm` today (verified precedence order: `--no-cmd > (--confirm | TTY-yes) > default-skip`; add `--if-stamped` into that same precedence chain, above default-skip, below `--no-cmd`).
- [ ] **`loomwright/skills/self-heal-advisory/SKILL.md`** — add a new step beside the existing `run-ground-truth.sh` step in Part 1 advisory machinery (NOT Part 2's gating loop): `bash ${CLAUDE_PLUGIN_ROOT}/scripts/rules-check.sh --if-stamped $NO_CMD_FLAG` (reuse the SAME `NO_CMD_FLAG` variable already computed at `~line 477` for `run-ground-truth.sh` — verified it exists), capture the summary line, emit exactly ONE advisory line `rules_check: passed n/m | unstamped | cmd_disabled` into the Phase 4.5 report and the PR body's advisory section. State explicitly, verbatim: this is SURFACED, not a new review pass — it never enters the review-and-fix loop and never changes `heal_decision` (matching CLAUDE.md's own Failure-Mode Invariants, which this item's brief must not weaken).
- [ ] **Worker spawn contract: explicitly UNCHANGED.** State in the brief/PR why: linked worktrees cannot see `.supervisor/` (a pre-existing, documented constraint), and running model-writable shell inside a worker is exactly the R2 trap this item's own design section names. No file in `skills/async-orchestration/SKILL.md`'s spawn contract changes.
- [ ] **Docs:** `commands/rules.md` + `loomwright/skills/rules/SKILL.md` gain a stamp-semantics section (the R2 reasoning verbatim: `.agent/rules/*.json` is repo-committed and model-writable, so execution is keyed to a human act recorded OUTSIDE the repo; "a rule edit invalidates the stamp — re-run `/rules check --confirm`"). `commands/dreaming.md` documents the two-button Accept flow. `docs/RESULT_SCHEMAS.md` is NOT touched (no result-block field is planned — the `rules_check:` line is PR-body/report prose only, verify this stays true during implementation; if a genuine need for a schema field emerges, treat that as a scope question to flag, not to silently add). CHANGELOG paragraph; version bump (`plugin.json` + `marketplace.json` + CHANGELOG only — no agent/command/skill/hook count changes).
- [ ] Fixture: a ledger with 3 findings sharing one literal path under one proposal ⇒ the harvester's proposal output shows `check_candidate:` in both the human-facing block and the JSON; `check` is `null` in both.
- [ ] Fixture: a shared token containing `'`, and a SEPARATE fixture with `$(` ⇒ NO candidate in either, proposal otherwise identical to the no-candidate case.
- [ ] **Mutation control, non-execution:** a fixture whose shared token is `; touch <tmpdir>/pwned` ⇒ the candidate is shown as inert text (or omitted per the rejection rule above) and `<tmpdir>/pwned` does NOT exist after the harvest run completes — assert the file's absence directly, don't just assert the harvester's exit code.
- [ ] `add-rule.sh` diff against `main` is EMPTY (verify with `git diff main -- loomwright/scripts/add-rule.sh` — zero lines). Accept-with-check produces a stored rule whose `check` equals the candidate string exactly; accept-without-check produces `check: null` — both via the existing, unmodified `add-rule.sh --check`/no-`--check` paths.
- [ ] Fixture: `rules-check.sh --confirm` with `y` piped writes the stamp to the user-scope file, and the stamp's `hash` equals an independently-computed sha256 of the sorted `id\tcheck` lines (compute it two ways in the test — once via the script's own code path, once via an independent jq+sha256 one-liner in the test itself — and assert they match, so the test can't just echo the script's own output back at itself).
- [ ] Fixture: `--if-stamped` after a valid stamp runs without prompting and prints `Checks passed: n/m` with `n/m > 0/0`.
- [ ] Fixture: edit ONE accepted `check` value by a single byte after stamping ⇒ `--if-stamped` prints `[SKIP] all (unstamped)`, `Checks passed: 0/0`, exit 0. `--no-cmd --if-stamped` together ⇒ `[SKIP] … (cmd execution disabled)` regardless of stamp validity.
- [ ] `git status --porcelain` in the repo shows NO new or modified file after a `--confirm` stamp-writing run (the stamp genuinely never lands under the repo root — this is the load-bearing security property of the whole design; test it directly, not just by code inspection).
- [ ] **Mutation control:** deleting the hash-comparison line in `--if-stamped`'s implementation must make the "edit one byte" fixture above start incorrectly reporting the checks as stamped/passing — construct this mutation test the same way this repo's other mutation controls prove a check is load-bearing, not vacuous.
- [ ] `self-heal-advisory/SKILL.md`'s advisory-line prose is state-traced for all three states (`passed n/m` with n>0, `unstamped`, `cmd_disabled`) and explicitly states `heal_decision` stays byte-identical regardless of which state fires or whether n<m (a failing stamped check still never gates).
- [ ] `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` → the same five sanctioned surfaces (this item touches none of them). `hooks.json` byte-unchanged (`git diff main -- loomwright/hooks/hooks.json` empty — this item adds NO hook). Agent/command/skill counts unchanged (14/24/42).
- [ ] Full test loop (`loomwright/scripts/test-*.sh` + root `scripts/test-*.sh` + `scripts/check-vendor-coupling.sh` + `scripts/check-doc-currency.sh`) green — watch for a literal `${CLAUDE_PLUGIN_ROOT}` inside a core-script COMMENT tripping the vendor-coupling ratchet (the source requirement explicitly warns about this); reword neutrally if it happens rather than adding an allowance.

## Non-goals (from the source requirement — do not implement)
No worker-seam execution of any kind (linked worktrees can't see `.supervisor/`; this is the R2 trap by design, not an oversight). No semantic/non-grep-shaped checks — only literal, template-bounded patterns. No new hook, no new result-block field (unless a genuine implementation-time need surfaces — flag it, don't silently add one). No CI/cross-machine stamp sharing — the stamp is deliberately per-user-per-machine (R2): CI and every teammate run `unstamped` until each human confirms once on their own machine. **No `## Result` section recording 10 real Phase 4.5 runs' `rules_check:` lines** — the source requirement's own "Honest limits" section asks for this before the ORIGINAL requirement file itself is marked done, but that is an inherently POST-MERGE, multi-run observability task (it requires 10 actual future Phase 4.5 runs across later PRs to accumulate), not something achievable within this single implementation PR. This brief's Acceptance Criteria cover the MECHANISM only (AC1-AC10 equivalents above); the requirement file itself should be left at whatever status accurately reflects "code shipped, observation period pending" rather than fully `done` — confirm the right requirement-file stamp with the worker's actual understanding of this repo's `## Status:` conventions (likely `done` for the code, with the D11 observability task tracked as a separate follow-up note, not blocking this PR).

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Parallelism Analysis
- **Mode:** single-agent (no fan-out) — one LAUNCHABLE subtask, no dependents, no file-conflict/context-bound/genuine-parallelism reason to split (see Feasibility #4).
- **Recommended workers:** 1

## Skill References
| Skill | Justification |
|---|---|
| quality-checklist | Standard pre/post-implementation quality gates for any worker task. |
| rules | Authority for the `.agent/rules/` house-rules substrate, `add-rule.sh`/`rules-check.sh` mechanics, and the stamp semantics this item extends. |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Executable rule candidates: harvester proposal → two-button accept → human-confirmed user-scope stamp → Phase 4.5 advisory replay | all | 12 modify, 0 create | quality-checklist, rules | LAUNCHABLE |

```yaml
# Subtask 1 — executable rule candidates, end-to-end (LAUNCHABLE)
subtask_id: executable-rule-candidates-01
title: "Executable rule candidates: proposal DATA + two-button accept + user-scope stamp + Phase 4.5 advisory replay"
lanes:
  - loomwright/scripts/harvest-conventions.sh
  - loomwright/scripts/test-harvest-conventions.sh
  - loomwright/scripts/rules-check.sh
  - loomwright/scripts/test-rules-check.sh
  - loomwright/scripts/test-add-rule.sh
  - loomwright/commands/dreaming.md
  - loomwright/commands/rules.md
  - loomwright/skills/rules/SKILL.md
  - loomwright/skills/self-heal-advisory/SKILL.md
  - CHANGELOG.md
  - loomwright/.claude-plugin/plugin.json
  - .claude-plugin/marketplace.json
requires: []
external_requires: []
provides:
  - {kind: "symbol", path: "loomwright/scripts/harvest-conventions.sh", name: "check_candidate"}
  - {kind: "symbol", path: "loomwright/scripts/rules-check.sh", name: "--if-stamped"}
  - {kind: "symbol", path: "loomwright/skills/self-heal-advisory/SKILL.md", name: "rules_check"}
  - {kind: "symbol", path: "loomwright/skills/rules/SKILL.md", name: "stamp"}
out_of_lane: []
```

## File Impact Map
- **Modify:** harvest-conventions.sh, test-harvest-conventions.sh, rules-check.sh, test-rules-check.sh, test-add-rule.sh (assert byte-unchanged + the two accept shapes — no code change to add-rule.sh itself), dreaming.md, rules.md, rules/SKILL.md, self-heal-advisory/SKILL.md, CHANGELOG.md, plugin.json, marketplace.json.
- **Create:** none.

## Risk Assessment
- **The candidate-generation allowlist is the whole security boundary.** Risk: a permissive template or an escaping bug lets arbitrary shell land in a "candidate" a human might rubber-stamp-accept. Mitigation: the AC's own mutation-control fixture (`; touch <tmpdir>/pwned`) is a hard, non-negotiable gate — reject-don't-escape is the stated design, and the worker must prove the rejection actually fires, not just that the harvester doesn't crash.
- **Stamp-outside-repo is the second security boundary.** Risk: a bug writes the stamp (or any trace of it) into the repo, making it model-writable again — exactly what R2 exists to prevent. Mitigation: the `git status --porcelain` AC is a direct, mechanical proof, not a code-review inference.
- **Hash-comparison mutation control** proves the stamp-invalidation check is load-bearing, not vacuous (mirrors this repo's established mutation-control convention for security-critical gates).
- **Scope discipline:** this item touches TWO already-hardened seams (the harvester's DATA-not-EXECUTED discipline, and the content-keyed-stamp pattern) — the worker should mirror existing precedent exactly rather than re-deriving new conventions, to avoid introducing a THIRD, subtly-different security pattern into the codebase.

## Configuration
- **Mode:** single-agent
- **Recommended workers:** 1

## Handoff
Run: `/supervisor job: .supervisor/jobs/pending/2026-09-25-executable-rule-candidates.md`

## Environment Validation
- ✓ `gh` authenticated, ✓ `jq` available, ✓ `sha256sum`/`shasum`/`openssl` available (exec-acceptance-lib.sh already depends on one), ✓ existing `test-harvest-conventions.sh`/`test-rules-check.sh`/`test-add-rule.sh` present as extension points, ✓ both stated dependencies (red-team-hardening/02, /05) already merged to `main`.

---

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/267
- **Reconciled:** lifecycle move completed by reconcile-jobs.sh, not by the completion tail
- **Evidence:** automate engine supplied merge evidence for .supervisor/requirements/twin-loop/08-executable-rule-candidates.md (https://github.com/vikashruhilgit/loomwright/pull/267) — the engine verified the PR merged against the forge; this reconciler stayed offline
- **Caveat:** fields the completion tail would have recorded (files changed, heal decision and iterations, red-team advisory) are NOT recoverable after the fact and are deliberately omitted rather than invented.
