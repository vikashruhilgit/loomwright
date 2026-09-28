# Supervisor Job: Every self-test is hermetic for egress — one sourced scrub-and-shim helper, a CI lint ratchet, and a runner-level export

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** code tree clean apart from `.supervisor/` run-trail edits; branch: main == origin/main
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (the owner's `~/.zshrc` exports `LOOMWRIGHT_WEBHOOK_URL` to a real ntfy topic, so every terminal-run suite can reach it today. The worker's own test runs are exposed until the helper lands. Run the suite with `env -u LOOMWRIGHT_WEBHOOK_URL LOOMWRIGHT_DESKTOP_NOTIFICATIONS=0` while developing.)
- **Source requirement:** .supervisor/requirements/automate-followups/04-hermetic-test-notifier-egress.md
- **Base commit:** d9d8d4017b08b2a7f7d15ab8697a6fa2dab6267c (re-based 2026-09-28 after #289 merged; original 4fd9baa)

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Bash helper + bash lint + one-line edits to bash tests; macOS bash 3.2 compatible. |
| 2 | Dependency Availability | GO | No new dependency. |
| 3 | Architecture Fit | GO | Mirrors the existing `scripts/check-*.sh` + `scripts/test-check-*.sh` pair convention and the `run-self-tests.sh` runner. |
| 4 | Scope vs Supervisor Capability | CAUTION | About 117 test files get a mechanical one-line edit, plus a helper, a lint, and ~4 targeted test fixes. The `context-bound` file-count predicate is met, but the split is declined. The 117 edits are ONE scripted edit with near-zero context cost; the non-mechanical work is about 10 files. Splitting would put `test-propose-from-verify.sh` / `test-notify-desktop.sh` in both the mechanical and targeted groups, forcing a file-conflict chain and serial execution anyway. |
| 5 | Hard Blockers | GO | None. |

**Overall Verdict:** CAUTION (scope size — mitigated by a scripted edit + the lint proving coverage)

## Task
**Goal:** No test under `loomwright/scripts/test-*.sh`, `scripts/test-*.sh` or `loomwright/scripts/adapters/*/test-*.sh` can reach a real webhook, telemetry endpoint, or OS notification. This must hold however the test is invoked (`run-self-tests.sh`, the hand-rolled `for t in …/test-*.sh; do bash "$t"; done` loop, or `bash test-x.sh` alone), and a new test must be covered without anyone opting in.

**Problem Statement:** Tests fake `HOME` but not the environment or the OS notifier. `LOOMWRIGHT_WEBHOOK_URL` has the highest precedence in `resolve-egress-config.sh`, so a terminal-run suite (which inherits the owner's `~/.zshrc` export) posts fixture events to the owner's real ntfy topic. `test-dispatch-pr-review.sh` case 37, its mutation-control rerun, and `test-worktree-salvage.sh`'s `run_real` all reach the real `drain_died` notify+webhook through `dispatch-pr-review.sh`'s detached `trap_cleanup`. `test-propose-from-verify.sh` AC9 symlinks the REAL `notify-desktop.sh`, which ends in `osascript display notification`. Only 4 tests scrub the env var at all.

## Design decisions (owner chose option C on 2026-09-28; the rest is settled here so the worker does not choose)
1. **Option C (owner decision):**
   - every covered test sources the helper;
   - a CI lint fails any covered test that does not (the ratchet);
   - `run-self-tests.sh` ALSO sources/exports the helper's effect for its workers, as a second layer.
2. **Helper location and name:** `loomwright/scripts/hermetic-test-env.sh`. It must NOT be named `test-*.sh`: `run-self-tests.sh` would execute it as a test, and `test-suite-helpers-defined.sh` / `test-no-pipefail-grep-q.sh` scan that glob. It is a plain script that is safe to `source` (no `set -e`, no `exit`, idempotent when sourced twice).
3. **What the helper does when sourced:**
   - **(a)** `unset` every env var that routes data out. The list is DERIVED in a comment next to the `unset` line, citing the readers by anchor:
     - `LOOMWRIGHT_WEBHOOK_URL` and `LOOMWRIGHT_WEBHOOK_FORMAT` (read by `resolve-egress-config.sh` / `send-webhook.sh`);
     - `LOOMWRIGHT_TELEMETRY_REPO` (read by `resolve-egress-config.sh`).
     - Consent itself cannot come from env, per the resolver.
   - **(b)** `export LOOMWRIGHT_DESKTOP_NOTIFICATIONS=0`, the existing first gate in `notify-desktop.sh`.
   - **(c)** Create a per-process shim dir under `${TMPDIR:-/tmp}` via `mktemp -d`, and PREPEND it to `PATH` with recording stubs:
     - the stubs are `osascript`, `notify-send`, `terminal-notifier` and `curl`;
     - each one appends its argv to `$HERMETIC_EGRESS_LOG` (exported; default `<shimdir>/egress.log`) and exits 0;
     - `wget` is also stubbed for completeness; the survey found no caller.
     - `gh` is deliberately NOT shimmed globally, because tests stub `gh` themselves and a global stub could mask a test's own stub ordering. The telemetry route is covered by decision 7's probe instead.
   - **Shim-dir lifecycle (idempotency rule):**
     - **(a) Reuse check.** Reuse an exported `HERMETIC_SHIM_DIR` ONLY if it exists AND every stub file in it is present and executable. Otherwise create a fresh dir, so a user-shell export or a half-built dir can never silently drop the stubs.
     - **(b) PATH on reuse.** On reuse or creation alike, prepend the shim dir to `PATH` unless it is already the FIRST entry, so the helper's stubs always win over any shims placed earlier.
     - **(c) Log path at run time.** Each stub resolves its log at RUN time as `${HERMETIC_EGRESS_LOG:-<its own dir>/egress.log}` (never a path baked in at creation), so a test can redirect the reused stubs.
     - **(d) Private log for asserting tests.** Any test that asserts on the egress log's content or emptiness first sets its OWN private `HERMETIC_EGRESS_LOG`. Under `run-self-tests.sh` the parallel workers share one dir and one default log: concurrent `>>` appends are fine for diagnostics, but that shared log cannot be asserted on. The helper NEVER deletes its shim dir and never installs an EXIT trap, because tests install their own traps, and `dispatch-pr-review.sh`'s detached `nohup bash -c` child can outlive the test and still resolve `curl` through `PATH`. A standalone run leaving one temp dir behind is accepted.
   - **(d)** Export `HERMETIC_TEST_ENV=1` as the marker the lint's runtime self-check and the runner test can read.
   - **(e)** No `HOME` change. Tests keep their own `HOME` isolation where they have it.
4. **Where each test sources it.** Apply the line with ONE scripted loop (`sed`/`awk` over the three globs), never by hand-editing 117 files; this avoids the subagent turn-limit risk. The lint is the coverage proof. On the first non-comment line after the shebang's comment block, and BEFORE the test's `set` line, as one statement that resolves the path from the test's own location:
   - `loomwright/scripts/test-*.sh`: `. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"`
   - `scripts/test-*.sh`: `…/../loomwright/scripts/hermetic-test-env.sh`
   - `loomwright/scripts/adapters/*/test-*.sh`: `…/../../hermetic-test-env.sh`

   The requirement's "line 2" is read as "the first executable line". Shebang comment blocks are long in this repo, and moving a comment block would churn every file for no gain.
5. **The lint:** `scripts/check-test-hermetic.sh` plus its paired `scripts/test-check-test-hermetic.sh` (the existing root `check-*`/`test-check-*` pair convention).
   - It fails, naming each offender, on any covered test whose first executable line is not a source of `hermetic-test-env.sh`.
   - It is wired into `.github/workflows/ci.yml` the same way the sibling check pairs are (`bash scripts/test-X.sh; bash scripts/check-X.sh`).
   - Root `scripts/test-*.sh` are not auto-run by `run-self-tests.sh`, which is why the CI line is needed.
6. **Deliberate notifier tests re-enable only what they assert on, inside their own subshell:**
   - `test-notify-desktop.sh`: `env -u LOOMWRIGHT_DESKTOP_NOTIFICATIONS` for the cases that expect a fire. It already REPLACES `PATH`, so the shim dir is irrelevant there.
   - `test-webhook.sh` cases 7–8 already use their own curl stub, so they must keep passing.
   - `test-propose-from-verify.sh` AC8-notify is unchanged.
   - **AC9 (the known leak site): replace ONLY the `notify-desktop.sh` symlink with a recording stub. Keep `send-webhook.sh` as the REAL symlink.** AC9 relies on the real webhook script plus its own NETSHIM curl/wget/nc denier to OBSERVE zero network calls. Stubbing `send-webhook.sh` too, as AC8-notify does, would make that assertion vacuous. Update AC9's header comment, which currently says the notifier is "not faked". The stub carries the literal comment marker `AC9 stub notifier` (0 hits in that file at base), so the outputs gate can confirm the stub itself was written, not just the source line.
   - `test-dispatch-pr-review.sh` case 37, its mutation rerun, and `test-worktree-salvage.sh` need no special handling once the helper is sourced: the survey confirms the detached child inherits env and PATH.
7. **The hermeticity probe is a new test**, `loomwright/scripts/test-hermetic-egress.sh` (it also sources the helper). It re-establishes the dangerous environment INSIDE its own sandbox:
   - a local TCP listener stands in for the ntfy host: `LOOMWRIGHT_WEBHOOK_URL=http://127.0.0.1:<port>`;
   - it uses its OWN outer recording `osascript` / `notify-send` / `terminal-notifier` / `gh` shims;
   - it then runs the leak sites with the helper sourced, and asserts zero listener hits and zero outer-shim records;
   - the leak sites are: `test-dispatch-pr-review.sh` case 37 (or the minimal `run_real` path it exercises), `test-propose-from-verify.sh` AC9, and one `send-telemetry-core.sh` non-dry-run path under a sandbox HOME.

   Running the WHOLE suite inside a test is NOT required: AC1 below is a one-off operator check recorded in the PR body. The mutation control (AC6) proves the helper is load-bearing.
8. **Out of scope:** `LOOMWRIGHT_WEBHOOK_URL`'s production precedence (a red-team-02 decision), the owner's `~/.zshrc`, `loomwright/sdk-spike/test/*` (Node-driven, run separately in CI, no notifier path), and HOME isolation for tests that lack it.

## Acceptance Criteria
- [ ] **AC1 (operator check — NON-GATING evidence, recorded in the PR body)**: With `LOOMWRIGHT_WEBHOOK_URL=http://127.0.0.1:<port>` pointed at a local listener and a PATH-first recording `osascript`/`notify-send`/`terminal-notifier`, the FULL suite run through `run-self-tests.sh` produces zero listener hits and zero recorded notifier calls. The only exceptions are calls a notifier's own tests assert on, which go to their own stubs. The same holds for a hand-rolled `for t in loomwright/scripts/test-*.sh; do bash "$t"; done`. Record the exact commands and counts in the PR body. AC4 (lint coverage) + AC6 (mutation) + the decision-7 probe are the GATING proof. A missing PR-body transcript is not a blocker on its own.
- [ ] **AC2**: `test-dispatch-pr-review.sh` case 37 run alone with the env var set sends nothing to the listener, and its `.died`-marker + `DRAIN_DIED` assertions still pass (covered by the probe in decision 7).
- [ ] **AC3**: `test-propose-from-verify.sh` AC9 run alone produces no recorded `osascript` call, and AC9 still passes, now with a stub notifier.
- [ ] **AC4 (lint ratchet)**: `scripts/check-test-hermetic.sh` is green on the tree. `scripts/test-check-test-hermetic.sh` proves its discrimination: a fixture test missing the source line ⇒ the lint exits non-zero naming it; adding the line ⇒ green; a source line placed AFTER `set -u` or after other code ⇒ red. Wired in `ci.yml` beside the sibling check pairs.
- [ ] **AC5 (coverage)**: every file matching the three covered globs sources the helper. The lint is the proof, and the count it reports is recorded in the PR body, never restated in docs.
- [ ] **AC6 (mutation control — one mutant per layer, because the curl stub masks the unset layer)**: two sed-built mutants of `hermetic-test-env.sh`, each with its own observable, run against the decision-7 probe:
  - **(i) both layers removed** (the `unset` line AND the `curl`/`wget` stubs) ⇒ the probe records listener hits. This proves the helper as a whole is load-bearing.
  - **(ii) only the `unset` line removed** ⇒ zero listener hits, but the probe's PRIVATE `HERMETIC_EGRESS_LOG` records a `curl` call naming the listener URL. This proves the stub layer catches what the scrub layer would have caught, on its own.
  - The unmutated helper records neither a listener hit nor a `curl` egress-log entry.
  - Every mutant is gated on non-empty, differs from the original, `bash -n`, and override actually injected, with a positive control (lesson fa32a308).
- [ ] **AC7 (runner layer)**: `run-self-tests.sh` applies the helper for its workers. A test assertion shows a worker sees `HERMETIC_TEST_ENV=1` and an unset `LOOMWRIGHT_WEBHOOK_URL` even when the parent shell exports it.
- [ ] **AC8 (docs)**: one short subsection in `AGENT_GUIDELINES.md` (the development-standards surface) says new tests must source the helper and that CI enforces it. It references the helper and lint by name and states no count. One CHANGELOG paragraph; plugin patch/minor bump in `plugin.json` + `marketplace.json`; counts unchanged (14/24/42; `hooks.json` byte-unchanged).
- [ ] **AC9 (full loop green)**: every `loomwright/scripts/test-*.sh` + `loomwright/scripts/adapters/*/test-*.sh` + root `scripts/test-*.sh` + `scripts/check-vendor-coupling.sh` + `scripts/check-doc-currency.sh` + `scripts/check-skills-index-sync.sh` + `scripts/check-token-budget.sh` + `loomwright/scripts/test-citation-drift.sh` + the new `scripts/check-test-hermetic.sh`, all run under `bash`. Run it with `env -u LOOMWRIGHT_WEBHOOK_URL` until the helper lands.
- [ ] **Invariants**: the `gh pr merge --squash` positive grep resolves to the same 5 surfaces. No new agent/command/skill/hook. `scripts/check-vendor-coupling.sh` stays green without new allowances. Read its real token source (`loomwright/docs/vendor-coupling-manifest.json` / the script) before writing the helper and lint; the check result is the proof, not any quoted list.

## Non-goals
- Changing `LOOMWRIGHT_WEBHOOK_URL`'s production precedence; the owner's `~/.zshrc`.
- `loomwright/sdk-spike/test/*`.
- Adding HOME isolation to tests that lack it.
- Refactoring the tests' own harnesses beyond the source line and the AC9 stub.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Hermetic egress helper + per-test source line + lint ratchet + runner layer + AC9 stub + probe test + docs/version | AC1–AC9, Invariants | ~125 modify, 4 create | quality-checklist, unit-testing | LAUNCHABLE |

## Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/scripts/hermetic-test-env.sh"}
  - {kind: "file", path: "scripts/check-test-hermetic.sh"}
  - {kind: "file", path: "scripts/test-check-test-hermetic.sh"}
  - {kind: "file", path: "loomwright/scripts/test-hermetic-egress.sh"}
  - {kind: "symbol", path: "loomwright/scripts/run-self-tests.sh", name: "hermetic-test-env.sh"}
  - {kind: "symbol", path: ".github/workflows/ci.yml", name: "check-test-hermetic.sh"}
  - {kind: "symbol", path: "loomwright/scripts/test-propose-from-verify.sh", name: "hermetic-test-env.sh"}
  - {kind: "symbol", path: "loomwright/scripts/test-propose-from-verify.sh", name: "AC9 stub notifier"}
  - {kind: "symbol", path: "AGENT_GUIDELINES.md", name: "hermetic-test-env.sh"}
requires: []
lanes:
  - "loomwright/scripts/hermetic-test-env.sh"
  - "loomwright/scripts/test-*.sh"
  - "loomwright/scripts/adapters/*/test-*.sh"
  - "loomwright/scripts/run-self-tests.sh"
  - "scripts/test-*.sh"
  - "scripts/check-test-hermetic.sh"
  - ".github/workflows/ci.yml"
  - "AGENT_GUIDELINES.md"
  - "CHANGELOG.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
external_requires: []
```

## Parallelism Analysis
single-agent (no fan-out)
- **Recommended workers:** 1
- **Estimated batches:** 1

## Configuration
- **Mode:** single-agent
- **Recommended workers:** 1

## File Impact Map
| Group | Files to Modify | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| helper | — | `loomwright/scripts/hermetic-test-env.sh` | HIGH |
| per-test source line | all `loomwright/scripts/test-*.sh` (110), `loomwright/scripts/adapters/*/test-*.sh` (3), `scripts/test-*.sh` (4) | `loomwright/scripts/test-hermetic-egress.sh` | HIGH |
| targeted test fixes | `loomwright/scripts/test-propose-from-verify.sh` (AC9 stub notifier), `loomwright/scripts/test-notify-desktop.sh` (`env -u` on fire-expecting cases, if needed) | — | MEDIUM |
| lint + CI | `.github/workflows/ci.yml` | `scripts/check-test-hermetic.sh`, `scripts/test-check-test-hermetic.sh` | HIGH |
| runner | `loomwright/scripts/run-self-tests.sh` | — | HIGH |
| docs + release | `AGENT_GUIDELINES.md`, `CHANGELOG.md`, `loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` | — | HIGH |

## Skill References
| Skill | Justification |
|---|---|
| quality-checklist | Standard pre/post-implementation gates. |
| unit-testing | Lint discrimination fixtures, probe test with local listener + recording shims, validated mutant. |

## Risk Assessment
| Risk | Impact | Source | Mitigation |
|---|---|---|---|
| **Global `curl` shim silently changes a test that relies on real curl** (e.g. a verify-env probe or a test expecting curl to fail against a closed port). | HIGH | Design | AC9 full loop; any test that genuinely needs real curl restores `PATH` in its own subshell and says why in a comment. The worker lists every such exception in the PR body. |
| **`LOOMWRIGHT_DESKTOP_NOTIFICATIONS=0` turns fire-expecting notifier assertions into false passes/fails** (lesson ef916b74: OFF-path fixtures must scrub the gating flag). | HIGH | Lesson | Decision 6: `test-notify-desktop.sh` fire cases run under `env -u LOOMWRIGHT_DESKTOP_NOTIFICATIONS`; the AC9 full loop proves they still assert real behaviour. |
| **Source line placed where it breaks a test's own setup** (before `HERE=` is defined, after `set -u` with an unbound var, or inside a heredoc-heavy header). | MEDIUM | Scope size | Decision 4's self-resolving path statement needs no `HERE`. The helper must be `set -u`-safe (`${VAR:-}` everywhere). The lint's placement rule catches drift. |
| **Workflow file edit makes `claude-review` self-skip on this PR** (green check, no comments). | MEDIUM | Machine lesson | Expected. The drain's earned fallback review (`no_review_lens_posted`) supplies the second lens. |
| **Vendor-coupling violation** in the helper or lint (token list defined by the manifest, not the script body). | MEDIUM | Survey + Plan Review | Invariant AC: read the manifest first; `check-vendor-coupling.sh` green is the proof. The helper never touches egress.json, so no user-scope path literal is needed. |
| **User-scope telemetry consent exists for this repo** (`egress.json` has a `telemetry` entry for `vikashruhilgit/loomwright`), so a non-dry-run `send-telemetry-core.sh` from the repo cwd with the real HOME could `gh issue create`. | MEDIUM | Environment check 2026-09-28 | Decision 7's probe exercises the telemetry path under a recording `gh`; existing `test-send-telemetry-core.sh` already shims gh + sandboxes HOME. |
| Worker's own dev runs leak before the helper lands. | LOW | Environment | Warning in `## Environment`. |

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-09-28-hermetic-test-egress.md

## Carried Plan Review Advisories (attempt 3/3 PASS — owner chose save-and-carry; REQUIRED design detail for the worker)
- **M1 (probe mutant isolation):** each AC6 mutant runs in a subshell that first strips the real helper's shim dir from `PATH` and unsets `HERMETIC_SHIM_DIR` / `HERMETIC_TEST_ENV`, then sets `LOOMWRIGHT_WEBHOOK_URL` + a private `HERMETIC_EGRESS_LOG`, then sources the mutant. It then invokes `dispatch-pr-review.sh`'s minimal `run_real` path directly. Never run a whole test file for a mutant: it re-sources the real helper and masks the mutant.
- **M2 (log preservation):** the helper sets `export HERMETIC_EGRESS_LOG="${HERMETIC_EGRESS_LOG:-$HERMETIC_SHIM_DIR/egress.log}"`, so it never overwrites an already-set value.
- **L1:** run EVERY probe leak site under a sandbox `HOME`, not only the telemetry one.
- **L2:** the probe's outer notifier-shim assertion is a regression guard, not evidence. Label it so, or add a third mutant dropping the notifier stubs and the `LOOMWRIGHT_DESKTOP_NOTIFICATIONS` export.
- **L3:** poll for the `.died` marker, as case 37 does, before reading the listener and the private egress log. The `drain_died` webhook fires from the detached trap child asynchronously.
- **Preflight note (2026-09-28):** the first attempt was aborted at Phase 1.5 on OVERLAP with open PR #289 (relicense: CHANGELOG.md / plugin.json / marketplace.json). If #289 is still open on resume, the overlap is release-file-only.


## Outcome
- **Status:** completed
- **Completed:** 2026-09-28T05:52:51Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/290
- **Branch:** feature/automate-followups-04-hermetic-test-egress
- **Files changed:** 127
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** Egress-hermetic helper sourced by every covered test + CI lint ratchet + run-self-tests runner layer (fails closed on missing helper / missing shim dir) + AC9 stub notifier + probe with per-layer mutants; v15.108.4. Phase 4.5 consistency_audit PASS on first review (0 HIGH; 2 MEDIUM + 1 LOW advisory addressed in 03af207: egress claim narrowed to env/PATH routes with explicit HOME-sandbox obligation for webhook/telemetry resolution, fail-closed runner branch tested (G2/G3), mktemp /tmp retry tested (R/Rm); 1 LOW nit — shim reuse checks presence not content — left). Execution-directive repros all held. risk_classification high_risk=true (*auth* content, *token* test paths). Pre-existing env-only failure: adapters/orca/test-orca-mirror.sh case L (gitignored sdk-spike/node_modules; identical on origin/main).

## Not verified
- **test-hermetic-egress.sh on Linux CI (notify-send + DISPLAY path)** — macOS only locally (subtask 1)
- **drain_died desktop banner** — dispatcher trap runs notify-desktop.sh from the removed worktree cwd, so the banner never fires; pre-existing, out of scope (subtask 1)
