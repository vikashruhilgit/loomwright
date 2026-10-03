# Supervisor Job: Vendor-coupling ratchet — LOOMWRIGHT_ROOT indirection + fail-closed CI gate

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main @ 3f87e81
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (10 stale worktrees under `.claude/worktrees/` + 3 prunable `/private/tmp` entries — pre-existing, unrelated to this job; do NOT clean them as part of this work)
- **Source requirement:** .supervisor/requirements/2026-08-22-092036-vendor-coupling-ratchet.md

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Repo already runs 7 bash CI gates (5 using jq) from root `scripts/`. This adds an 8th in the same idiom. bash 3.2 / BSD-userland constraints apply (macOS dev, ubuntu CI). |
| 2 | Dependency Availability | GO | `jq` already a hard dependency of `check-token-budget.sh`; no new deps. |
| 3 | Architecture Fit | GO | `check-token-budget.sh` + `loomwright/docs/prompt-token-budgets.json` is an exact structural precedent: JSON-declared allowances, fail-CLOSED gate, raise-visible-in-diff rule. Mirror it. |
| 4 | Scope vs Supervisor Capability | GO | 6 files, est. ~700–850 changed lines — straddling the `context-bound` bound (>12 files OR >800 lines). No split is taken: `context-bound` is permission-to-split, not a mandate, and neither other reason fires. `file-conflict` does not fire (no two groups share a file). `genuine-parallelism` cannot fire — the only zero-overlap split is manifest+gate+test (3 files) vs resolver+resolver-test (2 files), and the second group is below the ≥3-files-per-group bound. Single-agent; `Split reason:` correctly omitted. |
| 5 | Hard Blockers | GO | None. No migrations, no credentials, no missing modules. |

**Overall Verdict:** GO

## Task
**Goal:** Make vendor-neutrality a mechanically enforced ratchet — a committed CORE/ADAPTER/COUPLED manifest plus a fail-closed CI gate that lets the core's vendor-coupling count fall or stay flat but never rise without a reviewed manifest edit — and introduce the `LOOMWRIGHT_ROOT` indirection the core will migrate onto.

**Problem Statement:**
The plugin's portability is asserted in a memory and a requirement doc, but no check enforces it, so every release is free to weld more Claude-specific coupling onto the vendor-neutral core — and did. Between 2026-07-23 (v15.13.0) and 2026-08-22, prompt-layer `CLAUDE_PLUGIN_ROOT` references rose 31% (150 → 197) and `loomwright/scripts/*.sh` portability fell from 82% to 70% of files carrying zero Claude references. Re-measured on this branch's base (2026-08-30, v15.37.0): **278** references repo-wide and **71%** script portability (81 of 114 `.sh` files clean) — the regression is real and still standing. This causes the Cursor-adapter spike (twin-remediation item 10 §5) to be porting a moving target, and it makes item 10's one-shot inventory stale the week it is published. Success looks like: a CI gate that fails a PR adding a vendor reference to a CORE-classified path, passes one adding references to an ADAPTER path, and whose own mutation test proves it is not vacuous.

**Verified finding that changes the manifest's shape (the requirement flagged this assumption "Not yet verified"):** the requirement assumed the refs "are dominated by legitimately-adapter surfaces (commands/hooks/agent frontmatter)". Measured on base: adapter-ish surfaces (`commands` 77 + `agents` 36 + `hooks` 18) = **131/278 = 47%**; core-ish surfaces (`scripts` 56 + `skills` 59 + `docs` 24) = **139/278 = 50%**. **The assumption is REFUTED — adapter surfaces are not dominant.** The mitigating measurement is that the CORE allowance table is nonetheless small: only **16 files** under `loomwright/scripts/` carry any reference (56 refs total, top offender `test-build-handoff.sh` at 11). Record this refutation in the manifest's `_comment`; do not silently plan as though the assumption held.

## Acceptance Criteria
- [ ] Given a CORE-classified path at its declared allowance, when a new vendor reference is added to it, then `scripts/check-vendor-coupling.sh` exits non-zero and prints the offending path with its declared-vs-actual counts.
- [ ] Given an ADAPTER-classified path, when vendor references are added to it, then the gate exits 0 (adapters may exploit every primitive their harness offers).
- [ ] Given a CORE path's allowance is raised in the manifest in the same commit that adds the reference, then the gate exits 0 (the raise is visible in review rather than silent).
- [ ] Given a CORE path whose actual count is BELOW its declared allowance, then the gate exits 0 (the ratchet permits improvement; it does not pin counts to an exact value).
- [ ] Given `CLAUDE_PLUGIN_ROOT` is set, when the resolver runs, then `LOOMWRIGHT_ROOT` resolves to exactly that path; given `CLAUDE_PLUGIN_ROOT` is unset and the layout is a dev checkout, then resolution still succeeds and points at the plugin root (`loomwright/`).
- [ ] Mutation control: a test asserts, by executing the gate against a fixture tree with an injected vendor reference in a CORE path, that the gate exits non-zero — the proof is an executed assertion, not inspection.
- [ ] The gate carries no `|| true` anywhere, and no invocation of it in CI carries `|| true`.
- [ ] Declared allowances equal the counts the gate itself measures on this branch's base commit (no silent grandfathering of a wrong baseline): running the gate on an unmodified checkout exits 0 with zero breaches.
- [ ] No regression: `bash scripts/validate-version.sh`, `bash scripts/check-doc-currency.sh`, `bash scripts/check-command-sync.sh`, `bash scripts/check-contract-parity.sh`, `bash scripts/check-token-budget.sh`, and `bash scripts/check-skills-index-sync.sh` all still exit 0.

## Outcomes Rubric
- Machine-readable CORE/ADAPTER/COUPLED manifest committed
- `LOOMWRIGHT_ROOT` indirection with verified Claude-path compatibility
- Ratchet gate fails closed on new core coupling, passes on adapter coupling
- Mutation control proves the gate is not vacuous
- Declared allowances match today's measured counts (no silent grandfathering of a wrong baseline)

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Vendor-coupling manifest + fail-closed ratchet gate + mutation control + `LOOMWRIGHT_ROOT` resolver, wired into CI | all | 1 modify, 5 create | `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md`, `skills/ci-cd/SKILL.md` | LAUNCHABLE |

### Subtask 1 contract

```yaml
provides:
  - {kind: "file", path: "loomwright/docs/vendor-coupling-manifest.json"}
  - {kind: "file", path: "scripts/check-vendor-coupling.sh"}
  - {kind: "file", path: "scripts/test-check-vendor-coupling.sh"}
  - {kind: "file", path: "loomwright/scripts/resolve-loomwright-root.sh"}
  - {kind: "file", path: "loomwright/scripts/test-resolve-loomwright-root.sh"}
  - {kind: "symbol", path: "loomwright/scripts/resolve-loomwright-root.sh", name: "LOOMWRIGHT_ROOT"}
  # Both names are DIRECTORY-PREFIXED on purpose. The worker's Step 5.5 `symbol` check is an
  # unanchored `grep -nE`, and a bare "check-vendor-coupling.sh" is a substring of
  # "test-check-vendor-coupling.sh" — so unprefixed, a ci.yml wiring ONLY the test would satisfy
  # BOTH provides and the ratchet would never run in CI. "scripts/check-vendor-coupling.sh" does
  # NOT occur inside "scripts/test-check-vendor-coupling.sh", so each provide is independently
  # falsifiable. Do not shorten these names.
  - {kind: "symbol", path: ".github/workflows/ci.yml", name: "scripts/check-vendor-coupling.sh"}
  - {kind: "symbol", path: ".github/workflows/ci.yml", name: "scripts/test-check-vendor-coupling.sh"}
requires: []
lanes:
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "scripts/check-vendor-coupling.sh"
  - "scripts/test-check-vendor-coupling.sh"
  - "loomwright/scripts/resolve-loomwright-root.sh"
  - "loomwright/scripts/test-resolve-loomwright-root.sh"
  - ".github/workflows/ci.yml"
external_requires:
  - "jq (already a hard dependency of scripts/check-token-budget.sh)"
```

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md`, `skills/ci-cd/SKILL.md` |

## Implementation Notes (binding design decisions — do not re-litigate)

**File placement — this repo has TWO scripts directories and they are not interchangeable:**
- Root `scripts/` = 9 explicitly-invoked repo-level scripts (7 gates + 2 self-tests: `check-doc-currency.sh`, `check-token-budget.sh`, `test-check-token-budget.sh`, …), each named *explicitly* in a `run:` step in `.github/workflows/ci.yml` (9 scripts across 7 steps — some steps name a gate and its self-test together). **The new gate and its test go here.**
- `loomwright/scripts/` = 122 plugin-runtime scripts (114 `.sh` + 8 `.py`). CI runs `loomwright/scripts/test-*.sh` in an anti-drift loop that auto-includes new tests. **The `LOOMWRIGHT_ROOT` resolver and its test go here** (the resolver is plugin runtime, and its test is then auto-run by that loop).
- **TRAP:** the anti-drift loop — the full-self-test-suite step, identifiable by its `tests=(loomwright/scripts/test-*.sh)` glob — matches `loomwright/scripts/` ONLY. A test placed in root `scripts/` is NOT auto-run: `scripts/test-check-vendor-coupling.sh` MUST be added to `ci.yml` explicitly, exactly as `test-check-token-budget.sh` and `test-check-shared-prefix.sh` already are. Mirror the shape of the per-agent token-budget step, which names both `check-token-budget.sh` and its self-test inside one `run:` block. A test that is committed but never invoked is precisely the "claim no check backs" failure this job exists to end. **This is why the contract declares BOTH the gate and its test as directory-prefixed `provides` symbols in `ci.yml`** — see the comment in the contract block for why the `scripts/` prefix is load-bearing rather than cosmetic.

> **Citation convention:** the bullets above deliberately use *descriptive* anchors (the glob text, the step's identity) rather than `ci.yml:NN` line numbers. The worker is about to insert a step into this very file, which would invalidate any absolute line reference it was handed — the recorded `absolute-line-refs-drift-in-prose-edits` failure. Keep it that way when editing this brief.

**Structural precedent to mirror:** `scripts/check-token-budget.sh` + `loomwright/docs/prompt-token-budgets.json`. Read both before writing. Adopt their conventions: JSON is the single source of truth the gate reads; a raise requires editing the JSON in the same PR; the header comment states WHY, the exit-code contract, and the portability constraints.

**Classification policy (record it in the manifest, and justify each in its `note`):**
- **ADAPTER** (may name any harness freely; not counted): `loomwright/commands/**`, `loomwright/agents/**`, `loomwright/hooks/**`, `.claude-plugin/**`, and `loomwright/scripts/resolve-loomwright-root.sh`. The last one is deliberate and load-bearing: the resolver's whole job is to name the vendor once so nothing else has to — a gate that flagged it would flag the seam it exists to create.
- **CORE** (must be vendor-neutral; ratcheted): `loomwright/scripts/**` except the resolver. 16 files currently carry refs; every other file's allowance is 0, which is what makes a NEW ref in a currently-clean script fail.
- **COUPLED** (grandfathered debt, per-path allowance): `loomwright/skills/**`, `loomwright/docs/**`.
- Paths matched by nothing are unclassified. **Decide and document the unclassified default explicitly in the manifest** — recommended: treat unclassified as CORE with allowance 0 so a brand-new directory cannot silently become a coupling haven. If you choose otherwise, state the reason in the manifest `_comment`.

**Vendor token set:** declare it IN the manifest (not hard-coded in the gate) so it is tunable and reviewable. Seed it with `CLAUDE_PLUGIN_ROOT`, `CLAUDE_CODE_`, `claude -p`, `.claude/`. Measure each path's allowance with the gate's own counter and commit that number — never a hand-typed one.

**Allowances are per-path counts, and the ratchet is one-directional:** breach = actual **>** declared. actual **<** declared MUST pass (that is debt being paid down). Do not require exact equality — that would make every improvement a CI failure.

**Fail CLOSED (CLAUDE.md §"Failure-Mode Invariants"):** this is a correctness gate, not a runtime emitter. No `|| true` on the gate or on its CI invocation. An unreadable/malformed manifest is a FAILURE (non-zero), never a silent pass — assert that case in the test too.

**Portability (this repo's standing constraints):** bash 3.2 + BSD userland on the dev machine, GNU on CI. No `timeout`. No `${var//[[:space:]]/}` on large strings. `stat -f %m` is BSD-only and succeeds with garbage on Linux. Beware `producer | grep -q` returning 141 under `pipefail` even on a match, and `grep -c … || echo 0` emitting two lines. Prefer `wc -l` / `grep -c` with explicit rc handling.

**Explicitly NOT in scope:** migrating any of the 278 existing references onto `LOOMWRIGHT_ROOT` (that is twin-remediation item 10's inventory work). This job creates the seam and stops the growth. Also NOT in scope: bumping `plugin.json` / `marketplace.json` / adding a `CHANGELOG.md` entry / editing CLAUDE.md's "Latest change" banner — verified convention on this repo is that feature commits do not bump the version; separate `release:` commits own the version surface (see `0e73d3e`, `06c7101`). Touching it here would fail `validate-version.sh` or create drift.

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Gate is vacuous — matches nothing, silently passes forever | HIGH (worst outcome; the exact class this job exists to end) | Mandatory mutation control: the test injects a vendor ref into a CORE path in a fixture tree and asserts non-zero exit. Also assert the inverse (ADAPTER injection ⇒ exit 0) so the test cannot pass by the gate simply failing everything. |
| Grep-based detection misses computed/derived references | MEDIUM (false sense of coverage) | Memory `derived-pin-invisible-to-literal-grep`: a path assembled at runtime contains no literal token. State this limit honestly in the gate header — it counts LITERAL occurrences and cannot see a derived one. Do not claim coverage the mechanism lacks. |
| Classification is wrong; the gate blocks legitimate work | MEDIUM (friction → gate gets disabled) | Allowances start at measured counts, so nothing fails on day one. Ratcheting down is separate, later work. |
| Test placed in root `scripts/` is never invoked by CI | HIGH (a mutation control that never runs is not a control) | The worker's Step 5.5 outputs verification greps `ci.yml` for the wiring; a missing match forces `outputs_gap` non-empty, which rule 8 of `validate-worker-result.py` refuses to reconcile with `status: completed` (the subtask lands `partial`). **Honest limit:** this is a worker self-report, not an independent re-check — rule 7 validates the entry shape only and never re-runs the grep, and a worker that dies before emitting `WORKER_RESULT` is not covered at all. |
| The resolver is itself flagged by the gate it ships with | MEDIUM (self-contradictory PR) | Resolver is ADAPTER-classified by design; assert this in the test (gate exits 0 on an unmodified tree). |
| macOS-green ≠ CI-green (`stat`/`sed -i`/`date` flavor drift) | MEDIUM | Use only POSIX-portable constructs; memory `stat-flavor-setu-arithmetic-trap`. Validate numeric before arithmetic under `set -u`. |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-08-30-vendor-coupling-ratchet.md
```

---

## Outcome

**Status:** completed
**PR:** https://github.com/vikashruhilgit/loomwright/pull/160 — MERGED 2026-08-31T03:55:26Z (merge commit `dc03cc4`)
**Shipped in:** v15.38.0
**Automate run:** `.supervisor/automate/automate-2026-08-30-101743.md` (`## Status: done`, `remaining: 0`)

Verified on `main` rather than on the PR branch: `scripts/check-vendor-coupling.sh` rc=0 —
340 files scanned / 300 counted / 40 adapter-exempt, 71 files carrying references, 574 references,
**0 breaches, 0 errors**; `test-check-vendor-coupling.sh` 71/71; `test-resolve-loomwright-root.sh` 15/15.

### Why this brief sat in `in-progress/` after its PR merged

The move to `done/` is the Supervisor completion tail's job (`skills/supervisor-readiness/SKILL.md`
§"After Supervisor completes successfully"). On this run the Phase 4.5 code-reviewer failed **4×**
with `server_error` ("computer went to sleep mid-response"). That was recorded at the time as a
missing `heal_decision` — honestly, but **incompletely**: the same infrastructure failure also cut
the completion tail short, so the lifecycle move never ran. The brief was then stranded here
through the safe-mode park and the owner's out-of-band merge.

Moved to `done/` manually on 2026-08-31 after reconciling against ground truth.

### The gap this exposes (open — no fix applied)

Nothing cross-checks a brief in `in-progress/` against its PR state. The SessionStart probe *does*
surface the file, but classifies it as **"In-progress briefs (Supervisor was mid-run)"** and points
at `/supervisor --continue` — for a brief whose PR has already merged that is a false signal
recommending a wrong action, and it re-appears every session until someone moves the file by hand.
An infrastructure failure anywhere in the completion tail reproduces this. Two candidate fixes,
neither applied here: make the completion tail crash-safe, or have the SessionStart probe reconcile
an `in-progress/` brief against its PR before calling it mid-run.
