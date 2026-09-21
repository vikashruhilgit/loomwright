# Supervisor Job: One shared extractor for the brief's source-requirement pointer

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — modified 2026-09-06)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 2
- **Source requirement:** .supervisor/requirements/reconciler-repair/01-brief-pointer-extraction.md
- **Base commit:** 2cf4609378e1c151d5d644b3cf72a7545892138f

**Warnings (non-blocking):**
1. A sibling git worktree (`~/Documents/work/AI/loomwright-stateloop`) holds the already-merged branch `fix/floor-reprinted-a-lines-evidence-per-path`. It cannot take `main`, and `.supervisor/` scratch is absent there. Not orphaned; no action needed for this run.
2. The source requirement is **gitignored** (`.gitignore:78` — `.supervisor/*`), so it is untracked rather than merely uncommitted. Its provenance/staleness is therefore unverifiable from version control. This is the normal state for this repo's requirement store, but it means the plan rests on a document with no committed history.

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Pure POSIX/bash shell change inside `loomwright/scripts/`, the repo's established deliverable form. No new language or runtime. |
| 2 | Dependency Availability | GO | No new dependency. Uses `grep`/`sed`/`cd`/`pwd -P` already used by both target scripts. |
| 3 | Architecture Fit | GO | A sourced shared helper in `loomwright/scripts/` is an established form here. **It is located by a plain `dirname "$0"` sibling lookup** — the allowance-0, vendor-neutral idiom `session-resume.sh` already uses in five places. The `validate-entry.sh` / `add-rule.sh` `${CLAUDE_PLUGIN_ROOT}` ladder is explicitly **NOT** the model: those files carry grandfathered vendor-coupling allowances (8 and 3), while every file this brief touches sits at allowance 0 under a hard CI gate. See AC-10 and Risk #7. |
| 4 | Scope vs Supervisor Capability | GO | 2 created (`brief-pointer.sh`, `test-brief-pointer.sh`) + 9 modified (2 scripts, 2 tests, `PITFALLS.md`, `ARCHITECTURE_CONTRACTS.md`, `CHANGELOG.md`, `plugin.json`, `marketplace.json`) = 11 total, under the `context-bound` split threshold. Single subtask. |
| 5 | Hard Blockers | GO | Both target scripts exist and were read. The three AC-9 corpus briefs exist in `.supervisor/jobs/in-progress/` on this checkout. CI's anti-drift loop globs `loomwright/scripts/test-*.sh`, so a new co-located test is picked up with **no `ci.yml` change** (verified at `ci.yml` anti-drift loop step). |

**Overall Verdict:** GO

## Task

**Goal:** Replace the two divergent `- **Source requirement:**` pointer parsers with one shared extractor that tolerates every pointer shape the real brief corpus carries, while preserving in full the containment hardening `stamp-requirement-status.sh` already has.

**Problem Statement:**
Two lifecycle reconcilers need the same field off a Supervisor brief and each parses it differently. `reconcile-jobs.sh` strips only the label, so a backticked pointer fails its very first containment guard and the brief is classified `unknown`. `stamp-requirement-status.sh` strips surrounding delimiters but only at the very end of the line, so a pointer ending in a parenthetical annotation survives the strip, passes containment, and then fails `-f`.

Measured on this checkout against the three briefs currently in `.supervisor/jobs/in-progress/`: the Sep 3 brief (backticks **plus** trailing prose) resolves in **neither** consumer; the Sep 5 brief (backticks only) resolves in `stamp-requirement-status.sh` but **not** `reconcile-jobs.sh`; only the Sep 4 brief (bare path) resolves in both.

This causes real, durable damage. `2026-09-05-floor-ui-redesign.md` corresponds to PR #185, merged 2026-09-05 — genuinely shipped, and stranded in `in-progress/` for five days because of a backtick. A stale `in-progress/` entry is read by four independent consumers as "Supervisor is mid-run", and because `stamp-requirement-status.sh` reads `jobs/done/` exclusively, a brief stranded in `in-progress/` structurally blocks requirement close-out too.

The root cause is **mirror drift, not a typo**: one producer (Launch Pad Phase 5), two consumers written a month apart, and a producer contract that says "repo-root-relative path" while saying nothing about styling. Briefs are agent-written prose, so tightening the producer cannot retire the existing corpus.

Success looks like: exactly one parsing rule in the repo, both call sites going through it, every containment guard still firing, and `did not resolve` gone from the output for all three real briefs.

## Acceptance Criteria

- [ ] **AC-1 (bare path, regression).** Given a brief whose pointer is an unstyled repo-root-relative path, when either call site resolves it, then it resolves exactly as it does today — this shape already works and must not change.
- [ ] **AC-2 (backticks).** Given a brief whose pointer is wrapped in backticks, when `reconcile-jobs.sh` resolves it, then it yields the same path as the identical unstyled pointer. Fixture-based, asserted through `reconcile-jobs.sh` — the call site that fails today.
- [ ] **AC-3 (backticks plus trailing annotation).** Given a brief whose pointer is wrapped in backticks and followed by a parenthetical annotation, when **both** call sites resolve it, then each yields the path alone. Asserted through both, because both fail this shape today.
- [ ] **AC-4 (label variants).** Given pointers differing only in label capitalisation, leading whitespace, or presence of the leading `- `, when resolved, then all resolve identically.
- [ ] **AC-5 (absent pointer).** Given a brief with no pointer line, when either call site processes it, then it is a silent no-op — no verdict, no stamp, no error. Pre-feature briefs and direct `/supervisor task:` runs carry no pointer and must stay unaffected.
- [ ] **AC-6 (containment preserved, one case per guard, ASSERTED THROUGH EACH CALL SITE).** Given each of: an absolute path; a path containing a `..` segment; a path outside `.supervisor/requirements/`; a symlinked final component; a symlinked directory component whose target is outside the containment root — when resolved **through `reconcile-jobs.sh` AND, separately, through `stamp-requirement-status.sh`** (five guards × two call sites = ten assertions, exercised through the scripts, never through the helper in isolation), then each is refused, with the refusal distinguishable from "resolved". **The two symlink cases must additionally assert the target file is byte-unmodified**, not merely that the call returned non-zero.

      **Why the call-site binding is load-bearing:** `stamp-requirement-status.sh` already passes all five guards today. A criterion that says only "when resolved" is fully satisfiable through that consumer alone while `reconcile-jobs.sh` keeps its weaker guard set — which is exactly the outcome Risk #3 forbids. `reconcile-jobs.sh` is the call site that must *gain* guards; assert it there.

      **The refusal discriminator is PINNED, because the obvious one collides.** `reconcile-jobs.sh`'s `classify()` emits state `unknown` in **two** different cases: the pointer was refused, and the pointer resolved but carries no evidence. A test asserting `state == unknown` therefore passes with **every containment guard removed** — and AC-9 explicitly licenses `unknown` as a legitimate outcome, so the collision is live, not theoretical. Discriminate on the `--porcelain` **evidence string**: a refusal must carry `did not resolve under`, and the resolved-but-unevidenced case must carry `carries no done stamp`. **Unification MUST preserve those two distinct evidence strings** — a helper collapsing both onto one failure code would flatten the only available discriminator.

      **Scope of the byte-unmodified clause:** it binds **`stamp-requirement-status.sh` only**, which is the sole writer to a requirement file. `reconcile-jobs.sh` never writes one (it reads for the done-stamp and moves the *brief*), so "victim file unmodified" is trivially true there even with every guard deleted — a no-op assertion. For `reconcile-jobs.sh` the symlink refusal is asserted via the evidence-string discriminator above **plus** "the brief was NOT moved into `done/` under `--repair`".
- [ ] **AC-6b (no surviving weak guard set).** Given `reconcile-jobs.sh` after the change, when grepped, then it contains **no local `safe_requirement_path()` definition and no remaining call site of that name** (the function is invoked at two sites today — `classify()` and the repair status lookup — so asserting only "no definition" would leave a dangling call). The weak implementation is deleted, not left below the source line as dead code. `provides` can assert presence but never absence, so this deletion obligation is asserted here and pinned in the test.

      **This criterion is grep-only, deliberately.** An earlier draft additionally asked the test to *source* `reconcile-jobs.sh` and check the effective resolver. That is not implementable and **fails OPEN**: `reconcile-jobs.sh` is not a sourceable library — its main body runs at top level, its early-out fires whenever the sandbox has no `.supervisor/jobs/in-progress`, and it terminates with `exit 0`. Sourcing it from a test **exits the test shell with status 0**, so the suite reports green having run no assertion and having silently truncated every test after it. AC-6's behavioural assertions, executed *through* the script as a subprocess, already cover the symlinked-final-component case.
- [ ] **AC-7 (single parsing rule — the predicate is itself mutation-controlled).** Given a detector grep over `loomwright/scripts/` that finds independent label-parsing implementations (excluding `brief-pointer.sh`, the one sanctioned implementation, and excluding `test-*.sh` fixture strings), then the test asserts **BOTH ends**:
      - **(a) Baseline arm — the predicate demonstrably detects what it exists to detect.** Run against the **pre-change content of both scripts, committed as fixtures**, the predicate must find **all three known label-touching parse lines**: `reconcile-jobs.sh`'s label-stripping `sed -n` (its `brief_source_requirement` body), and `stamp-requirement-status.sh`'s two — the `grep -m1 -iE` that captures the raw line and the `sed -E` that strips the label. A predicate finding fewer than three **fails the test**.
      - **(b) Post-change arm.** Run against the working tree after the change, the match count is **zero**.

      **The exact regex is the implementer's to derive; this criterion pins the obligation, not the pattern — deliberately.** Two predicates have already been proposed for this and both were silently vacuous: a naive literal `Source requirement` grep matches its own fixture strings, and an ERE of the form `\*\*[Ss]ource [Rr]equirement:\*\*` matches **none** of the three real lines (in all three the asterisks are backslash-escaped in the source, so the literal text is `\*\*Source`, and one uses the bracket-class spelling `[Ss]ource` whose literal fourth character is `]`). Measured at base commit `2cf4609`, that ERE matches only two **comment** lines. Without arm (a), "match count is zero" is **already true on the unmodified tree** and AC-7 passes with the weak parser fully intact. Arm (a) is what makes the assertion mean anything.
- [ ] **AC-8 (mutation control, with a validated mutant).** Given the delimiter-stripping logic is reverted, when the suite runs, then AC-2 and AC-3 turn red. Asserted explicitly — a fixture corpus containing only unstyled pointers would pass every criterion above with the mechanism deleted. **The mutant itself must be gated before the run is trusted:** non-empty, byte-differs from the original, and `bash -n` clean. (Verified lesson `fa32a308`: `perl -0pi -e` interpolates `$VAR` inside the pattern even under `\Q…\E` so the mutation no-ops, and a `sed` delimiter colliding with the target line yields an EMPTY mutant — both pass every fail-open assertion.)
- [ ] **AC-9 (real corpus — a MANUAL measurement, deliberately not a suite assertion).** Given the three briefs in `.supervisor/jobs/in-progress/` on this checkout, when `reconcile-jobs.sh` is run **by hand from the main checkout**, then all three pointers **resolve** (`did not resolve` disappears for every one). Their final verdicts are **not** asserted — a brief may legitimately remain `unknown` for want of evidence. Record the run's output and the resulting verdicts in the PR body as measured evidence, not as a pass condition.

      **This criterion MUST NOT land in the CI-globbed suite.** `.supervisor/**` is gitignored (Warning 2), so it is absent from a fresh clone; CI's anti-drift loop auto-globs `loomwright/scripts/test-*.sh`, so an AC-9 assertion placed there would self-skip and become a permanent vacuous pass in the only environment that runs the suite on every PR. **Instead:** commit the three pointer LINES, sanitised, as in-repo fixtures in `test-brief-pointer.sh`, so the real corpus's *shape coverage* survives a fresh clone even though the corpus itself does not.
- [ ] **AC-10 (vendor-coupling ratchet stays green — BLOCKING constraint, not a nicety).** Given the change, when `bash scripts/check-vendor-coupling.sh` runs, then it exits 0. Concretely: **none of `reconcile-jobs.sh`, `stamp-requirement-status.sh`, their two test files, or the new `brief-pointer.sh` may contain any vendor token** — `CLAUDE_PLUGIN_ROOT`, `CLAUDE_CODE_`, `claude -p`, or `.claude/`. All five sit at **allowance 0** in `loomwright/docs/vendor-coupling-manifest.json`, breach is `actual > allowance`, and `check-vendor-coupling.sh` runs in `.github/workflows/ci.yml` as a hard gate with no `|| true`. `reconcile-jobs.sh`'s own header states its vendor-neutrality as a deliberate design property, not an accident.

      **Therefore the helper is located by a plain sibling lookup, NOT by `${CLAUDE_PLUGIN_ROOT}`.** Both consumers already live in `loomwright/scripts/` and so does the helper, and both are invoked by absolute path (`hooks.json` for the stamper, `$SR_DIR` for the reconciler), so `dirname "$0"` resolves correctly under every invocation path. Follow the in-repo, allowance-0 idiom already used repeatedly in `session-resume.sh`: `script_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo .)"`. **Do not import the `validate-entry.sh` resolution ladder** — `add-rule.sh` (allowance 3) and `validate-entry.sh` (allowance 8) are *grandfathered debt*, not the current sanctioned idiom, and copying them here would redden CI. If a neutral root is ever genuinely needed, the adapter-exempt `resolve-loomwright-root.sh` publishes `LOOMWRIGHT_ROOT`; the sibling lookup is simpler and is what this change uses.
- [ ] **AC-11 (the documented limit has a subject).** Given `loomwright/docs/PITFALLS.md`'s stranded-brief entry and `loomwright/docs/ARCHITECTURE_CONTRACTS.md`'s `.supervisor/jobs/in-progress/` + `jobs/done/` rows, when read after the change, then each states which pointer shapes the shared extractor **does** tolerate (bare, backtick/quote-wrapped, whitespace-separated trailing annotation, label case and `- `-prefix variants) and names the **honest limit**: a pointer whose annotation is **not whitespace-separated** from the path (e.g. `…05-archive-views.md(amended)`) is not readable by the first-token rule, no such brief exists in the corpus, and **no heuristic guesses around it**. Correspondingly, `PITFALLS.md` must no longer imply the pointer is read literally.

      This criterion exists because two of the nine modified files were otherwise mandated by no AC at all, and because Outcomes Rubric bullet 7 ("The unreadable-pointer limit is documented rather than guessed around") had **no subject anywhere else in the brief** — leaving the Rubric Grader nothing to score against. Any new `file.ext:N` in this prose must use a descriptive anchor or carry `` [pins: `<literal>`] `` (Risk #6).

## Outcomes Rubric

- One parsing rule exists where there were two, and the weaker one is gone rather than patched.
- Every containment guard the hardened consumer had is still present and still demonstrably fires.
- The tolerated shapes are the ones the real corpus carries, established by measurement rather than by imagination.
- The delimiter handling is mutation-controlled, so the suite cannot pass with the fix removed.
- A brief that resolves but lacks evidence still reports `unknown`; nothing became more confident than the disk warrants.
- Nothing in the change can block a run, and no forge call entered the resume path.
- The unreadable-pointer limit is documented rather than guessed around.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | One shared brief-pointer extractor, both call sites converted, containment preserved | AC-1 … AC-11 | 9 modify, 2 create | `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md` | LAUNCHABLE |

**Single-subtask rationale:** no Decomposition Threshold reason fires. The extractor and both call sites must change in one commit or **AC-7 fails by construction** (a half-converted repo still has two parsers), so `genuine-parallelism` is unavailable and splitting would be actively harmful.

### Subtask Contracts

```yaml
# Subtask 1
provides:
  # The artifact
  - {kind: "file", path: "loomwright/scripts/brief-pointer.sh"}
  - {kind: "symbol", path: "loomwright/scripts/brief-pointer.sh", name: "brief_requirement_pointer"}
  - {kind: "symbol", path: "loomwright/scripts/brief-pointer.sh", name: "brief_requirement_path"}
  - {kind: "file", path: "loomwright/scripts/test-brief-pointer.sh"}
  # The MUTATION — both call sites must actually go through the shared extractor.
  # Without these, the gate is satisfied by a worker that writes the helper and
  # never touches either consumer. Both entries are `symbol` with a real identifier
  # as `name` (a filename is NOT a symbol — RESULT_SCHEMAS requires symbol/type
  # entries to carry an identifier).
  - {kind: "symbol", path: "loomwright/scripts/reconcile-jobs.sh", name: "brief_requirement_path"}
  - {kind: "symbol", path: "loomwright/scripts/stamp-requirement-status.sh", name: "brief_requirement_path"}
requires: []
lanes:
  - "loomwright/scripts/brief-pointer.sh"
  - "loomwright/scripts/test-brief-pointer.sh"
  - "loomwright/scripts/reconcile-jobs.sh"
  - "loomwright/scripts/stamp-requirement-status.sh"
  - "loomwright/scripts/test-reconcile-jobs.sh"
  - "loomwright/scripts/test-stamp-requirement-status.sh"
  - "loomwright/docs/PITFALLS.md"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "CHANGELOG.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
external_requires: []
```

> **`outputs_verified` is grep-shaped and worker-self-reported — the two call-site `provides` entries are NECESSARY BUT NOT SUFFICIENT.** A line reading `# TODO: route through brief_requirement_path` in `reconcile-jobs.sh` satisfies its entry without converting anything. **The conversion is therefore evidenced behaviourally, by AC-6 executed through each script as a subprocess, not by the presence of the token.** A comment mention does not satisfy these entries; if the token is present but AC-6 does not pass through that call site, the subtask is not done.
>
> **Function-name rule (root-cause fix, not a preference):** the shared helper exports `brief_requirement_pointer` (extract + delimiter-strip) and `brief_requirement_path` (extract + full containment → validated path). It **MUST NOT** export `safe_requirement_path` — that is the name `reconcile-jobs.sh` uses today for its *weaker* containment function, and reusing it would make the failure mode silent: bash's last-definition-wins means a surviving local definition below the source line would restore the weak containment while every parsing criterion stayed green (`brief_requirement_pointer` is differently named, so AC-1…AC-5 would not notice). Choosing distinct names makes that shadowing **structurally impossible**. `reconcile-jobs.sh`'s local `safe_requirement_path` must still be **deleted** rather than left as dead code — asserted by AC-6b, since `provides` can assert presence but never absence.

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 (independent — the only subtask)
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | — | n/a (single subtask) | NO |

### Batch Plan
- **Batch 1:** Subtask 1
- **Recommended workers:** 1
- **Estimated batches:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Prior churn on the touched surfaces, with a recorded `self_heal_miss`.** The postmortem ledger reports 83 prior churn rounds across 48 entries on these paths — `CHANGELOG.md` (48), `plugin.json` (47), `ARCHITECTURE_CONTRACTS.md` (16), `PITFALLS.md` (1), `stamp-requirement-status.sh` (1) — with recurring classes `drain_churn` (33), `convention_mismatch` (25), `quality_gap` (16), and at least one prior `self_heal_miss`. Source: prior churn (postmortem ledger). | HIGH | The dominant class is `convention_mismatch` on the release surfaces, not on the logic. Before declaring done, diff the version/count surfaces explicitly rather than trusting a green `check-doc-currency.sh` — that gate verifies claims that ARE made and cannot tell you a claim should not have been made. Treat a green Phase 4.5 `heal_decision` as unverified on this area. |
| **`reconcile-jobs.sh` runs on every SessionStart via `session-resume.sh`, so a regression wedges every new session.** It is offline by construction for exactly this reason. | HIGH | Introduce no forge call and no network call. The added symlink guard does `cd`/`pwd -P` only. Keep the script's fail-safe posture: a pointer that cannot be resolved must remain a silent skip, never an error exit. |
| **Unifying could silently WEAKEN containment.** `reconcile-jobs.sh`'s `safe_requirement_path` today lacks the `-L` symlink check and the physical parent-resolution check that `stamp-requirement-status.sh` has inline. Unification must move `reconcile-jobs.sh` **up** to the hardened guard set, never average the two. | HIGH | AC-6 asserts one case per guard, and the two symlink cases assert the target file is byte-unmodified — not merely a non-zero return. The original suite was 17/17 green precisely because it tested the attacks that were thought of. |
| **A mutation control can be silently invalid.** Verified lesson `fa32a308`: `perl -0pi -e` interpolates `$VAR` inside the pattern even under `\Q…\E` (mutation no-ops), and a `sed` delimiter colliding with the target line yields an EMPTY mutant. Both pass every fail-open assertion. | HIGH | AC-8's mutant must be gated on **non-empty + differs-from-original + `bash -n` clean** before the run is trusted. |
| **The version-bump surface list is contested.** Verified lesson `a642885b` claims ~8 doc surfaces move in lockstep; the requirement's own Release-surface obligations name only `CHANGELOG.md` + `plugin.json` (+ `marketplace.json` description mirror). | MEDIUM | Follow the requirement, which is the more recent and more specific authority, and let `check-doc-currency.sh` arbitrate. Update the `description` counts **in place**; never append another version clause. Counts do not move — no agent, command, skill, or hook is added. |
| **New `file.ext:N` citations in committed prose drift.** `test-citation-drift.sh` fails any new bare, unpinned citation. | MEDIUM | Use descriptive anchors, or pin as `` file.sh:N [pins: `<literal>`] ``. The line numbers in the source requirement (`reconcile-jobs.sh:133`, `stamp-requirement-status.sh:130-135`) are intake evidence — **do not copy them into committed prose unpinned.** |
| **Sourced-helper path resolution is constrained on BOTH axes at once — vendor-coupling AND failure mode — and the obvious precedent is wrong on both.** `stamp-requirement-status.sh` is invoked from `hooks.json` at `SubagentStop` and `SessionStart`; `reconcile-jobs.sh` is invoked by `session-resume.sh` via a `$SR_DIR`-relative path. | HIGH | **Axis 1 — location (see AC-10, BLOCKING).** Use a plain sibling lookup, `script_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd \|\| echo .)"`, the allowance-0 idiom already used in `session-resume.sh`. **Never `${CLAUDE_PLUGIN_ROOT}`** — it is a vendor token and all five touched scripts sit at allowance 0 under a hard CI gate. **Axis 2 — failure mode.** ❌ Do **not** import `add-rule.sh`'s load guard. That guard deliberately refuses when the helper is absent (and forbids `\|\| true` on that line) because it is a *writer* whose purpose is validated appends — an unvalidated append is the harm it exists to prevent. Both consumers here are the opposite shape: a missing helper means **no stamp and no reclassification, i.e. no write at all**, so a silent skip IS the correct outcome. Per CLAUDE.md's bimodal rule these are runtime side-effect reconcilers, not correctness gates — they fail **SAFE** and both already `exit 0` throughout. Copying the refusal path into `reconcile-jobs.sh` would add an error exit to a script that runs on every SessionStart — precisely the wedge Risk #2 exists to prevent. **Both divergences are deliberate; record them in the helper's header so neither is "corrected" later.** |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-09-10-brief-pointer-extraction.md
```

---

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/208
- **Reconciled:** lifecycle move completed by reconcile-jobs.sh, not by the completion tail
- **Evidence:** automate engine supplied merge evidence for .supervisor/requirements/reconciler-repair/01-brief-pointer-extraction.md (https://github.com/vikashruhilgit/loomwright/pull/208) — the engine verified the PR merged against the forge; this reconciler stayed offline
- **Caveat:** fields the completion tail would have recorded (files changed, heal decision and iterations, red-team advisory) are NOT recoverable after the fact and are deliberately omitted rather than invented.
