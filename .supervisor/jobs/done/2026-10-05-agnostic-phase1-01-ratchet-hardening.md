# Supervisor Job: Vendor-coupling ratchet hardening — count the coupling that actually locks us in

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes-v2/s2-a
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1
- **Source requirement:** .supervisor/requirements/agnostic-phase1/01-ratchet-hardening.md
- **Base commit:** c1692b091ef1747c6d600cd6cc2073277981f880

> **Warning (1):** this checkout is one of several sibling lane checkouts of the same repo, and run history lives on a
> metadata branch (branch mode). Other lanes may run concurrently. Never `cd` outside this checkout; never use bare
> `git stash` (the stash stack is shared across worktrees). The source requirement is gitignored run history
> (`.supervisor/*`), so "uncommitted" is its normal state here, not a provenance problem.

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Pure bash 3.2 + `jq` + `git` — exactly the gate's existing surface. No new dependency. |
| 2 | Dependency Availability | GO | `jq`, `git`, `awk`, `grep -oF` already required by the gate. |
| 3 | Architecture Fit | GO | Extends the existing manifest-driven, fail-CLOSED correctness gate; tokens stay manifest-only. |
| 4 | Scope vs Supervisor Capability | CAUTION | One cohesive subtask, but the re-baseline adds allowance entries for every agent/command BODY (≈38 files) and the raise-check bootstraps against a base manifest that has no class structure. |
| 5 | Hard Blockers | CAUTION | CI's `actions/checkout@v7` uses the default shallow, single-ref fetch, so `origin/main` is NOT resolvable in CI today — the raise check would print `skipped (no base)` there forever unless `.github/workflows/ci.yml` fetches the base. Editing a workflow file makes `claude-code-action` self-skip this PR's own review (exit 0, no comments). |

**Overall Verdict:** CAUTION (2 findings carried into Risk Assessment)

## Task
**Goal:** Make `scripts/check-vendor-coupling.sh` measure the real Claude Code coupling classes, count agent/command BODIES (only their YAML frontmatter is the adapter surface), and refuse any allowance raise that lands without a stated reason.

**Problem Statement:**
The plugin's portability ratchet needs to see the coupling that actually locks the plugin to Claude Code, because today it passes while that coupling grows unchecked.
Currently the gate counts only 4 literal tokens (`install_root`-style paths and `claude -p`), classifies `loomwright/agents/*`, `loomwright/commands/*`, `loomwright/hooks/*` as whole-file ADAPTER (bodies uncounted), and accepts any same-PR allowance raise with no reason. The allowance sum has grown 574 (`bfa5716`, 2026-08-31) → 806 (`a262d00`, requirement authoring) → **857 / 118 entries at this brief's base commit `c1692b0`** — still growing, every raise automatic.
This causes subagent orchestration (`subagent_type`, `TaskOutput`, `SendMessage`, `run_in_background`), ask-user (`AskUserQuestion`), hook protocol fields, runtime identity, the SDK binding (`@anthropic-ai`) and model names to be invisible to the only gate that claims to guard portability.
Success looks like: a per-class table and total, a new `AskUserQuestion` in an agent body fails CI, and an allowance raise without an `allowance_reasons` entry fails CI.

## Acceptance Criteria
- [ ] Given the manifest, when the gate runs, then it reads named token classes from the manifest only — the gate script hard-codes no token string — and prints a per-class reference total plus a flat total; exit 0 at the new baseline. Minimum classes and tokens (from the source requirement's Scope item 1):
  - `install_root`: `CLAUDE_PLUGIN_ROOT`, `CLAUDE_CODE_`, `claude -p`, `.claude/` (the existing four)
  - `orchestration`: `subagent_type`, `TaskOutput`, `SendMessage`, `run_in_background`
  - `ask_user`: `AskUserQuestion`
  - `hook_protocol`: `SubagentStop`, `hookSpecificOutput`, `agent_transcript_path`, `last_assistant_message`, `stop_hook_active`
  - `runtime_identity`: `CLAUDE_PID`, `CLAUDECODE`, `CLAUDE_CODE_SESSION_ID`
  - `sdk_binding`: `@anthropic-ai`
  - `model_names`: fixed strings for Claude model aliases as they appear in code/frontmatter-shaped text (candidates: `model: haiku`, `model: sonnet`, `model: opus`, `"sonnet"`, `"haiku"`) — the exact strings chosen by measurement (see AC-9), documented in the manifest `note`.
- [ ] Given a file containing `CLAUDE_CODE_SESSION_ID` once, when counted, then it contributes exactly ONE reference in total and exactly one class (no double count across `install_root`'s `CLAUDE_CODE_` and `runtime_identity`'s `CLAUDE_CODE_SESSION_ID`, and none from counting per class with one grep each). The overlap rule is EXPLICIT in the gate or manifest — longest-match-wins resolved deterministically (e.g. in awk), or the overlap removed from the manifest — never left to which `-e` pattern `grep -oF` happens to prefer (BSD and GNU grep need not agree). Documented in the manifest and asserted by a test that must pass on GNU CI.
- [ ] Given `loomwright/agents/*.md` and `loomwright/commands/*.md`, when counted, then the first `---` … `---` YAML frontmatter block is excluded and everything after it is counted; this is a manifest-declared mode (e.g. class `adapter_frontmatter` with its own globs), not a hard-coded path. `loomwright/hooks/*` stays whole-file ADAPTER.
- [ ] Given a fixture where a new `AskUserQuestion` appears in an agent BODY with no allowance change, when the gate runs, then exit 1 (mutation control); and given the same token inside that file's frontmatter, then the count is unchanged.
- [ ] Given `origin/main` (or `$VENDOR_COUPLING_BASE`) resolvable, when any allowance is raised or newly added versus the base manifest, then it passes ONLY if `allowance_reasons["<path>"]` is a non-empty one-line reason that is ADDED or CHANGED versus the base manifest (absent in base, or a different string from base's) — an INHERITED, unchanged reason does not justify a new raise. Tests: raise without reason ⇒ exit 1; raise with an inherited unchanged reason ⇒ BREACH / exit 1; raise with a new/changed reason ⇒ exit 0. An `allowance_reasons` key with no matching `allowances` entry is an ERROR (mirrors the existing orphaned-allowance loop), so the reasons map stays self-cleaning.
- [ ] Given the base-manifest location rule — the base manifest is the manifest's path RELATIVE TO the scan root's git work tree, read via `git show <base>:<relpath>` (object store, so `ci-local.sh`'s temporary `GIT_INDEX_FILE` does not affect it) — when the base is unresolvable (shallow clone, no remote, ref missing) OR the manifest lies outside the scan root's work tree (the hermetic test's `VENDOR_COUPLING_MANIFEST` case) OR the path does not exist at the base, then the gate prints `raise_check: skipped (<reason>)` (`raise_check: skipped (no base)` for the unresolvable-base case) and does not fail on that account; each case pinned by a test.
- [ ] Given the CI workflow, when this PR's `ci` job runs, then the raise check actually EXECUTES there (not `skipped`) — verified from the job log; if that required a `.github/workflows/ci.yml` change, the PR body says so and names that `claude-review` self-skips on this PR.
- [ ] Given `loomwright/sdk-spike/package.json`, when counted, then it scores ≥1 under `sdk_binding`.
- [ ] Given the re-baseline, when the PR is opened, then its body carries the before/after total PER CLASS, the exact `--print-allowances` command used, and the `model_names` measurement that justified the chosen strings — for each candidate, its occurrences in COUNTED surfaces (agent/command bodies, skills, docs, scripts) split into true model references vs prose false positives, since frontmatter (where `model: haiku` mostly lives) is now excluded; no existing reference is removed.
- [ ] Given the whole change, when `bash scripts/ci-local.sh` runs, then every gate and every `test-*.sh` is green; the script header's "WHAT IT CANNOT SEE" section and the manifest `_comment`/notes are updated; a `changelog.d/` fragment is added and the version is bumped ONLY via `bash scripts/bump-version.sh` as the last commit. CLAUDE.md is not edited for counts.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Token classes, frontmatter-only adapter mode, reason-required raises, re-baseline, tests, docs, version bump | ALL (AC-1 … AC-10) | 8 modify, 1 create | `quality-checklist`, `unit-testing`, `ci-cd` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1 — the whole change (LAUNCHABLE; no siblings)
provides:
  - {kind: "file",   path: "changelog.d/agnostic-phase1-01-ratchet-hardening.md"}
  - {kind: "symbol", path: "loomwright/docs/vendor-coupling-manifest.json", name: "allowance_reasons"}
  - {kind: "symbol", path: "loomwright/docs/vendor-coupling-manifest.json", name: "sdk_binding"}
  - {kind: "symbol", path: "loomwright/docs/vendor-coupling-manifest.json", name: "adapter_frontmatter"}
  - {kind: "symbol", path: "scripts/check-vendor-coupling.sh",              name: "raise_check"}
  - {kind: "symbol", path: "scripts/check-vendor-coupling.sh",              name: "VENDOR_COUPLING_BASE"}
  - {kind: "symbol", path: "scripts/test-check-vendor-coupling.sh",         name: "adapter_frontmatter"}
requires: []
lanes:
  - "scripts/check-vendor-coupling.sh"
  - "scripts/test-check-vendor-coupling.sh"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - ".github/workflows/ci.yml"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "changelog.d/agnostic-phase1-01-ratchet-hardening.md"
  - "CHANGELOG.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
external_requires:
  - "GitHub Actions `actions/checkout` fetch behaviour (shallow single-ref by default)"
```

**Exact-name mandate:** `allowance_reasons` (the manifest map), `sdk_binding` (a token-class name), `adapter_frontmatter` (the manifest class/mode name, also exercised by name in the test file), `raise_check` (the literal prefix of the gate's raise-check status line, e.g. `raise_check: skipped (no base)`), and `VENDOR_COUPLING_BASE` (the base-ref override env var) are the literal identifiers the implementation MUST use — renaming any silently voids the `outputs_verified` gate. `.github/workflows/ci.yml` is in `lanes` because it MAY need a base fetch; touch it only if the CI log shows the raise check skipping otherwise. `CHANGELOG.md` and both manifests change ONLY through `bash scripts/bump-version.sh`.

## Parallelism Analysis

### Dependency Graph
Single subtask — no graph.

### File Overlap Matrix
Not applicable (one subtask). Script, manifest and test are one contract: the manifest schema change, the gate that reads it and the fixtures that pin it must move together, and the re-baseline depends on the finished gate. Any split would manufacture a file conflict.

### Batch Plan
One batch, one worker.

## Skill References

| Skill | Why |
|---|---|
| `skills/quality-checklist/SKILL.md` | Pre/post-implementation gates |
| `skills/unit-testing/SKILL.md` | Hermetic fixture assertions + mutation controls in the existing test file's style |
| `skills/ci-cd/SKILL.md` | Checkout fetch depth / base-ref availability in GitHub Actions |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| CI's shallow checkout makes `origin/main` unresolvable, so the raise check silently always `skipped` in CI — a gate that never runs where it matters (Feasibility (Phase 2.5), check 5) | HIGH | AC-7 requires proof from the CI job log that the check EXECUTED. Use an explicit refspec — `git fetch --depth=1 origin +refs/heads/main:refs/remotes/origin/main` before the gate step — or `fetch-depth: 0` (a bare `git fetch origin main` after `actions/checkout` may not create `refs/remotes/origin/main`); state in the PR body that `claude-review` self-skips on a workflow-editing PR and must be verified on the next non-workflow PR |
| Bootstrap: the base manifest has no class structure and the re-baseline raises/adds ≈40+ allowances, so the PR's own raise check fails unless every raised/new path carries a reason | MEDIUM | Re-baseline entries get honest one-line reasons (e.g. "re-baseline: agent body now counted"). Do NOT add a wildcard/blanket bypass — that would defeat AC-5 permanently. Because AC-5 requires an ADDED-or-CHANGED reason, these bootstrap reasons do not pre-authorise any later raise |
| Reasons inherited from the base silently re-authorise later raises (the gap Plan Review attempt 1 found in the source requirement's Scope item 4) | HIGH | AC-5's added-or-changed rule + the "inherited unchanged reason ⇒ exit 1" test. Record in the PR body that this tightens the requirement as written |
| The existing "allowance for an ADAPTER-classified path is an ERROR" rule collides with frontmatter-mode files that now legitimately carry allowances | MEDIUM | Treat `adapter_frontmatter` as counted (not adapter) for that rule; keep the error for whole-file adapters (`hooks/*`); test both arms |
| Overlapping tokens double-count (`CLAUDE_CODE_` ⊂ `CLAUDE_CODE_SESSION_ID`) or overlapping class membership double-counts one occurrence | MEDIUM | AC-2 + a dedicated fixture; count non-overlapping matches once per position |
| `model_names` strings over-match prose ("sonnet" in narrative text), inflating allowances with noise | MEDIUM | Measure candidates against the tree first and record the measurement in the manifest `note` and the PR body; prefer frontmatter/code-shaped forms (`model: haiku`, quoted `"sonnet"`) |
| Mutation control is vacuous (mutant identical, empty, or token assembled so `grep -F` misses it) | MEDIUM | Lesson [fa32a308]: gate every mutant on non-empty + differs-from-original before trusting it; keep fixture tokens FICTIONAL so the test file itself stays at allowance 0 (existing header convention) |
| The test file or manifest itself starts containing real tokens and needs its own allowance | LOW | Keep the existing "fictional token, copy real tokens with jq at run time" pattern; the manifest's own self-count entry is re-measured, not hand-typed |
| Frontmatter detection mis-parses a file with no frontmatter or a body `---` horizontal rule | LOW | Only a `---` on LINE 1 opens frontmatter; the first subsequent `---` closes it; a file without line-1 `---` is counted whole — test all three |
| `ci-local.sh` runs this gate with a temporary `GIT_INDEX_FILE` | LOW | Confirm the base comparison reads the base manifest via `git show <base>:<path>` (object store), unaffected by the temp index; run `bash scripts/ci-local.sh` |
| Version bump hand-edited or bumped before rebase | LOW | Lesson [6e0baac1]/[71cbd7e2]: fragment in `changelog.d/`, `bash scripts/bump-version.sh` as the LAST commit |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-05-agnostic-phase1-01-ratchet-hardening.md
```

---

## Outcome
- **Status:** completed
- **Completed:** 2026-10-05T02:43:10Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/385
- **Branch:** feature/agnostic-phase1-01-ratchet-hardening
- **Files changed:** 6
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** Schema-2 vendor-coupling ratchet: 7 manifest token classes with per-class + flat totals, leftmost-longest overlap counting in awk, adapter_frontmatter (agent/command bodies counted), raise_check requiring an added/changed allowance_reasons entry vs base (inherited reason fails), wrong-typed manifest values fail CLOSED (heal iteration 1). Re-baselined 857 → 2439 refs (236 entries, 169 reasons). Phase 4.5: iteration 1 FAIL (2 HIGH: string-allowance raise_check bypass; stale classes.core.note) → fixed in 59db851 → iteration 2 PASS. AC-7 evidenced in CI run 37252976836 (raise_check executed). Ground truth 2/2 (doc-currency-green, version-consistent). Version bump deferred to the release lane (changelog.d/README.md P7 parallel wave). risk_classification: high_risk=true (workflow file, size, token/orchestration content). contract_conformance: skipped (no twin contracts for touched paths — UNVERIFIED, not clean).

## Not verified
- **claude-review on this PR** — RESOLVED at drain time: it did not self-skip; it posted a review on a2d9245 (finding fixed in 59db851) and a clean re-review on 59db851 (static-only, execution: none) (subtask 1)
- **ci.yml sdk-spike step** — ci-local does not run it locally (npm build); CI runs it (subtask 1)
