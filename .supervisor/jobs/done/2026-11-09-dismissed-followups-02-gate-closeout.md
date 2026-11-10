# Supervisor Job: Dismissed follow-ups 02 — merge gate, close-out, salvage, guards and small CLI validators (24 findings)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (an unrelated worktree `wt-842` on `fix-842` in another session's scratchpad — not touched by this job)
- **Source requirement:** .supervisor/requirements/dismissed-followups/02-gate-closeout-and-guard-correctness.md
- **Base commit:** 8ec200e06dce87c947aadf302a20df0102e699ce

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Bash 3.2 scripts, awk, jq, one GitHub Actions step name; no new stack |
| 2 | Dependency Availability | GO | Every fix edits an existing script; tests stub `gh`/`lsof` on PATH as the suites already do |
| 3 | Architecture Fit | GO | Each fix is local to one script's argument/guard code; fail-safe emitters stay exit 0, the gate-eval park stays fail-CLOSED |
| 4 | Scope vs Supervisor Capability | CAUTION | 24 findings over ~33 files (≈18 scripts + their tests + 3 evidence files): past one worker's context, so split `context-bound` into 3 zero-overlap groups |
| 5 | Hard Blockers | CAUTION | Regression legs land in test files outside the requirement's `## Touches` (which names only `test-automate-loop-split.sh`), and F292's fix is in `.github/workflows/ci.yml` (also outside Touches) — asked once at Phase 6 (`LP-SCOPE`) |

**Overall Verdict:** CAUTION

## Task
**Goal:** Close the 24 owner-deferred review findings of `dismissed-followups/02`: re-verify each on the base commit, fix it with a regression leg that fails on the pre-fix code, or record a one-line reason it is not reproducible / not worth fixing.

**Problem Statement:**
The owner needs the 24 `follow-up` findings bundled from 20 `/automate` dismissed drafts acted on, because "follow-up" decisions were never turned into work.
Currently each one is still present on `main` (re-verified at 8ec200e by Launch Pad: every quoted anchor below greps in its file). They are argument-validation holes (`--session-id --no-trail`, `--pid ''`, `POLL=.`, `--bound 08`), honest-limit overclaims in script headers, scratch dirs that can land in the user's tree, a merge watcher whose rollup read can hide a merge, and a gate that can park a clean checkout or read the wrong tree.
Success looks like: every finding has one disposition (fixed + regression leg, or recorded with a reason) in a committed evidence file, and CI is green.

**Design (chosen at planning; the evidence file records any deviation with its reason):**
- **Dispositions live in committed evidence files, not in the requirement file.** `.supervisor/requirements/` is gitignored (`.gitignore` rule `.supervisor/*`), so a record written there is not in the PR diff. Each subtask writes `docs/evidence/dismissed-followups-02-<group>.md` with one row per finding it owns: `F<id> | fixed | <test file> :: <leg name>` or `F<id> | recorded | <one-line reason>`, plus the re-verify command it ran on the base commit.
- **Doc-only findings are fixed by honest wording, not new enforcement** (narrowest fix the hint allows): F075 (header states the finalize-gate marker's no-hand-Write rule is a convention nothing enforces), F099 (`_lw_under_any` header narrowed to "lexical ancestors, each compared by identity"), F157 (watcher header names the lock-free `progress-append` lost-update window). No regression leg for a comment change.
- **F034 reuses the existing park:** when the physical `--root` is neither the physical `rev-parse --show-toplevel` nor beneath it (an ancestor-or-self identity walk — gate-eval's own `_ge_inside` device+inode style applied to the root), gate-eval takes the same branch a failed toplevel read takes today (`root_dirt_rc=1` ⇒ `PARK: rules_gate_dirty_tree`). A subdirectory `--root` (which `07-rules-gate.sh`'s R11 legs deliberately use) is beneath the toplevel and still decides. No new park reason, so no closed enumeration grows for F034.
- **F035:** when `HOME` and `XDG_CONFIG_HOME` are both empty, the `--global` read is skipped and treated as key-unset (rc 1 path), never read as rc 128.
- **F062:** the poll reads `--json state,headRefOid` first; `statusCheckRollup` is fetched in a second `gh pr view` only when an escalation re-check line is armed, and its failure never gates MERGED detection. The pinned "no extra call" leg (E9) is updated to the new contract, not deleted.
- **F002:** the bump scratch dir moves under `$(git rev-parse --absolute-git-dir)` (inside Touches), not a `.gitignore` edit (outside Touches).
- **F038:** `closeout_classify` counts `trail-pr: opened` / `trail-pr: pushed` lines as a change. `closeout: synced — ` stays uncounted (by design per `per-item-loop.md`, as the finding itself notes).
- **F350:** each of the leak gate's three `lsof` calls (before-suite listener read, after-suite listener read, `-t` fd-holder probe) runs in the background into a file and is bounded with `ci-local.sh`'s own `finish_log` idiom — a `kill -0` poll with a counter, then `kill -KILL` (bash 3.2, macOS has no `timeout`); on timeout it reports `listeners unchecked` and goes on. Each bounded `lsof` runs with the run marker removed (`env -u LOOMWRIGHT_CI_LOCAL_RUN`), so an unkillable `lsof` (uninterruptible sleep on a stale mount) is never counted as a leaked survivor. `loomwright/scripts/run-self-tests.sh`'s watchdog is not copied (outside every lane). `-b` is added only if the fd-holder probe still detects a holder with it (the existing leak legs in `scripts/test-ci-local.sh` must stay green).
- **F158 / F175 are trace-then-decide:** F158 — trace `automate-next-step.sh` fix-now → escalated park; if the run lock is held across the decide-first ask, add one sentence to `per-item-loop.md` naming the exception (no history reference — `check-prompt-history-refs.sh`), else record "not reproducible" with the trace. F175 — model compliance at runtime; look for a split-file pointer back to `SKILL.md`/`per-item-loop.md` that lacks "already loaded" inside `per-item-loop.md` only; else record "not fixable as code (runtime compliance; no pointer found)".

## Acceptance Criteria

**Every finding (all subtasks)**
- [ ] AC1. Given a finding this brief assigns to a subtask, when the worker starts, then it re-runs the finding's anchor check on its own base (the `grep -nF` of the quoted anchor in `## Touched-file invariants`, or the finding's repro) and a committed evidence file `docs/evidence/dismissed-followups-02-<group>.md` (`engine` / `validators` / `repo-scripts`) contains, per finding, the check run and exactly one disposition: `fixed` naming the test file and leg, or `recorded` with a one-line reason; the PR body links to the three files.
- [ ] AC2. Given every finding dispositioned `fixed` that changes behavior (all except F075, F099, F157, F292, and F158/F175 when they resolve to wording or recorded), when its new regression leg runs against the base-commit version of the script (scratch copy), then the leg fails, and it passes on the fixed script — the leg name and the pre-fix red result are listed in the evidence file.

**Subtask 1 — automate engine (`engine`)**
- [ ] AC3 (F100, MEDIUM). Given `closeout <runfile> <item> <pr> --session-id --no-trail` (or `--session-id ''`, or `--session-id` last), when `closeout` parses its arguments, then it prints `closeout: skipped — --session-id needs a value` and returns 0 without running the trail, and `closeout-classify` classifies that line `leftover` with step `guard` (not `unknown`) — leg in `loomwright/scripts/test-automate-trail.d/02-closeout.sh`.
- [ ] AC4 (F102). Given a requirement whose close-out sentinel line carries trailing blanks, when `_co_stamped` runs, then it reads stamped; and given `## Status: done-ish` or `## Status: done.` after the sentinel, then it reads not stamped (heading anchored `done(_with_escalation)?[[:space:]]*$`) — legs in `02-closeout.sh`.
- [ ] AC5 (F038). Given closeout output whose only change is a `trail-pr: opened …` or `trail-pr: pushed …` line, when `closeout-classify --record <runfile>` runs, then it does NOT append `closeout: nothing to close out — <item>`; a `closeout: synced — ` only result is unchanged — leg in `02-closeout.sh`.
- [ ] AC6 (F062, MEDIUM). Given a watched PR whose `gh pr view --json state,headRefOid` reads `MERGED` while any read naming `statusCheckRollup` fails, when the watcher polls, then it detects the merge and runs closeout; and given no armed escalation line, then no poll requests `statusCheckRollup` — legs in `loomwright/scripts/test-automate-trail.d/04-watcher-branch-mode.sh`, with leg E9 rewritten to assert the new call shape (rollup only on an armed re-check) and every `gh pr view … statusCheckRollup` stub the suites carry for the watcher updated to match (including the `MW_GH_BODY` stub in `loomwright/scripts/test-automate-next-step.sh`, which starts the real watcher and matches that exact argv).
- [ ] AC7 (F157). Given `automate-merge-watch.sh`'s header, when read, then its honest limits name that `progress()` appends through `progress-append` without the run lock, so a concurrent writer can lose one line.
- [ ] AC8 (F063). Given `current-escalation` or `current-set` with a value carrying a CR, tab or any other `[[:cntrl:]]` byte, or a `--sha` that is not hex, when it runs, then it dies with its existing `… left unchanged` refusal and the run file is byte-identical — legs in `loomwright/scripts/test-automate-helpers.d/14-escalation.sh` (escalation) and `02-runfile.sh` (current-set).
- [ ] AC9 (F035). Given `HOME` and `XDG_CONFIG_HOME` both unset and a clean at-head checkout, when `gate-eval` runs the rules-gate dirt reads, then it does not print `PARK: rules_gate_dirty_tree` — leg in `loomwright/scripts/test-automate-helpers.d/07-rules-gate.sh`.
- [ ] AC10 (F034). Given a repo whose `.git/config` sets `core.worktree` to another (clean) tree while `--root` is dirty, when `gate-eval` runs, then it prints `PARK: rules_gate_dirty_tree` (the physical root is not the toplevel or beneath it); and a subdirectory `--root` of a clean checkout still decides (no-park control) — the existing R11 subdirectory legs (`E_GATE_ROOT="$E_ROOT/sub"`) stay green unchanged — legs in `07-rules-gate.sh`.
- [ ] AC11 (F168, MEDIUM). Given `loomwright/commands/automate.md`'s Step 0 intake row and `loomwright/skills/automate-loop/resume.md`'s Start order, when `loomwright/scripts/test-automate-loop-split.sh` runs, then a new leg asserts both carry `mkdir -p .supervisor/automate` before `pick-guard`, and fails if either surface drops it or reverses the order (mutation control in the leg).
- [ ] AC12 (F158, F175). Given the trace/search described in Design, when done, then the evidence file records the outcome for each (wording added to `per-item-loop.md` with the traced path, or `recorded` with the reason).

**Subtask 2 — standalone script validators (`validators`)**
- [ ] AC13 (F027). Given `LOOMWRIGHT_CI_SLOT_POLL` set to `.`, `1.2.3`, `0` or empty, when `ci-slot.sh` starts, then POLL falls back to 2 (validated `^[0-9]+(\.[0-9]+)?$` and > 0) — leg in `loomwright/scripts/test-ci-slot.sh`.
- [ ] AC14 (F028). Given a waiting `ci-slot.sh` receiving TERM, when its INT/TERM trap runs, then the background poll `sleep` it started is killed too (no `sleep` child of it survives) — leg in `test-ci-slot.sh`, or `recorded` with the reason if a reliable leg is not possible on bash 3.2.
- [ ] AC15 (F090). Given `--bound 08` (and `--call-max 08`), when `wait-for-checks.sh` runs, then no `value too great for base` error occurs and the resumable DEADLINE path is used (values normalised with `10#`); and the per-call ceiling caps the final sleep at the remaining `CALL_MAX` budget — legs in `loomwright/scripts/test-wait-for-checks.sh`.
- [ ] AC16 (F139). Given an ignored salvage-list entry that is a symlink, when `worktree-salvage.sh --ignored` runs, then the verdict fails naming that entry (never a passing `diff -r` over a link that will dangle) — leg in `loomwright/scripts/test-worktree-salvage.sh`.
- [ ] AC17 (F145). Given `run-lock.sh liveness --pid ''`, when it parses, then it exits with its usage error (`''|*[!0-9]*) die_usage`) — leg in `loomwright/scripts/test-run-lock.sh`.
- [ ] AC18 (F147). Given `TMPDIR` inside the repo, when `prove-rule-check.sh` creates its scratch dir, then the scratch dir is not inside TOP (falls back to `/tmp`, or refuses) and `git status --porcelain` in the repo shows no `prove-rule-check.` path — leg in `loomwright/scripts/test-prove-rule-check.sh`.
- [ ] AC19 (F148). Given cwd inside `.git` (`--git-dir` succeeds, `--show-toplevel` fails), when `prove-rule-check.sh` resolves containment, then `OUT_INSIDE=1` and no proof file is written into the repo's working tree — leg in `test-prove-rule-check.sh`.
- [ ] AC20 (F075, F099). Given `guard-finalize-publish.sh`'s WHY block and `host-mode.sh`'s `_lw_under_any` / `_lw_in_worktree` headers, when read, then the first states the marker's no-hand-Write rule is a convention no hook enforces, and the second says lexical ancestors, each compared by identity (a symlink to a descendant is not seen).

**Subtask 3 — repo-root scripts + release (`repo-scripts`)**
- [ ] AC21 (F002). Given `scripts/bump-version.sh` creating either scratch dir, when it runs, then the dir is under `$(git rev-parse --absolute-git-dir)`, not the repo root, and a run that keeps its backups leaves `git status --porcelain --untracked-files=all` without a `.bump-version.` path — leg in `scripts/test-bump-version.sh`.
- [ ] AC22 (F070). Given a stale committed `loomwright/capabilities.json`, when `bump-version.sh --dry-run` runs, then it reports the contract is stale (renders to its scratch dir and runs the capabilities half of `verify_rendered`) instead of `also regenerates: … (plugin_version only)`; a fresh contract still prints the plugin_version-only line — legs in `test-bump-version.sh`.
- [ ] AC23 (F350). Given an `lsof` stub on PATH that hangs — in three variants: on every call, only on the after-suite listener read, and only on the `-t` fd-holder probe — when `ci-local.sh`'s leak gate runs, then in each variant it returns within its bound, reports the hung read unchecked, and reports no survivor and no leak verdict (the hang stub does `exec sleep`); the existing leak legs stay green — legs in `scripts/test-ci-local.sh`.
- [ ] AC24 (F292). Given `.github/workflows/ci.yml`, when read, then the token-budget step is named `Check prompt token budgets (agents, skills, commands)`.

**Validation**
- [ ] V1. `bash scripts/ci-local.sh --affected` passes for each subtask's files, including `check-prompt-history-refs.sh` (no finding id, PR number or incident story added to `per-item-loop.md` or any other prompt), `test-citation-drift.sh` (no bare `file:N` in new prose) and `check-token-budget.sh` if `per-item-loop.md` changes.
- [ ] V2. `bash scripts/check-version-bump.sh` passes; the PR carries `changelog.d/dismissed-followups-02-gate-closeout-and-guard-correctness.md` and no hand-edited version file.


## Scope widening
- .github/workflows/ci.yml
- docs/evidence/dismissed-followups-02-engine.md
- docs/evidence/dismissed-followups-02-repo-scripts.md
- docs/evidence/dismissed-followups-02-validators.md
- loomwright/scripts/test-automate-helpers.d/02-runfile.sh
- loomwright/scripts/test-automate-helpers.d/07-rules-gate.sh
- loomwright/scripts/test-automate-helpers.d/14-escalation.sh
- loomwright/scripts/test-automate-next-step.sh
- loomwright/scripts/test-automate-trail.d/02-closeout.sh
- loomwright/scripts/test-automate-trail.d/04-watcher-branch-mode.sh
- loomwright/scripts/test-ci-slot.sh
- loomwright/scripts/test-prove-rule-check.sh
- loomwright/scripts/test-run-lock.sh
- loomwright/scripts/test-wait-for-checks.sh
- loomwright/scripts/test-worktree-salvage.sh
- scripts/test-bump-version.sh
- scripts/test-ci-local.sh
- accepted: LP-SCOPE 2026-11-09

## File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| engine (Subtask 1) | `loomwright/scripts/automate-trail.d/closeout.sh` (439), `loomwright/scripts/automate-merge-watch.sh` (479), `loomwright/scripts/automate-helpers.d/runfile.sh` (733 — the single home of `current-escalation`/`current-set`; the cntrl check edits their existing value `case`s in place), `loomwright/scripts/automate-helpers.d/resume.sh` (401), `loomwright/scripts/automate-helpers.sh` (1239 — the single home of `gate-eval`; two guards edited in place in its dirt-read block), `loomwright/scripts/automate-next-step.sh` (3966 — read for the F158 trace; edited only if the trace shows a lock held across an ask and a release-before-ask is the fix), `loomwright/skills/automate-loop/per-item-loop.md` (123), `loomwright/scripts/test-automate-loop-split.sh` (671 — the suite that already pins the automate-loop split surfaces; one leg appended), `loomwright/scripts/test-automate-trail.d/02-closeout.sh` (421), `loomwright/scripts/test-automate-trail.d/04-watcher-branch-mode.sh` (816 — the watcher's own suite with the gh argv-log fixture E9 uses; legs appended, E9 rewritten in place), `loomwright/scripts/test-automate-next-step.sh` (2773 — the `MW_GH_BODY` watcher stub's argv arms only), `loomwright/scripts/test-automate-helpers.d/14-escalation.sh` (398), `loomwright/scripts/test-automate-helpers.d/02-runfile.sh` (650 — the existing home of `current-set` legs; one leg appended), `loomwright/scripts/test-automate-helpers.d/07-rules-gate.sh` (859 — the existing home of the gate-eval dirt-read legs and their repo fixture; two legs appended) | `docs/evidence/dismissed-followups-02-engine.md` | HIGH |
| validators (Subtask 2) | `loomwright/scripts/ci-slot.sh` (662 — single home of POLL and the waiter trap), `loomwright/scripts/wait-for-checks.sh` (588 — single home of the bound parsing), `loomwright/scripts/host-mode.sh` (296), `loomwright/scripts/worktree-salvage.sh` (566 — single home of the ignored-entry copy/verify), `loomwright/scripts/run-lock.sh` (530 — one `case` arm), `loomwright/scripts/prove-rule-check.sh` (524 — single home of the scratch/containment resolution), `loomwright/scripts/guard-finalize-publish.sh` (723 — header comment only), `loomwright/scripts/test-ci-slot.sh` (857), `loomwright/scripts/test-wait-for-checks.sh` (930), `loomwright/scripts/test-worktree-salvage.sh` (1283), `loomwright/scripts/test-run-lock.sh` (1044), `loomwright/scripts/test-prove-rule-check.sh` (735) — each test file is its script's own suite with the fixtures the new leg needs; legs appended | `docs/evidence/dismissed-followups-02-validators.md` | HIGH |
| repo-scripts (Subtask 3) | `scripts/bump-version.sh` (770 — single home of the scratch dirs and dry-run), `scripts/ci-local.sh` (887 — single home of the leak gate and of the `finish_log` bounded-wait idiom the fix reuses), `.github/workflows/ci.yml` (373 — one step name), `scripts/test-bump-version.sh` (727), `scripts/test-ci-local.sh` (1139) — each its script's own suite (both already run by name from ci.yml); legs appended | `docs/evidence/dismissed-followups-02-repo-scripts.md`, `changelog.d/dismissed-followups-02-gate-closeout-and-guard-correctness.md` | HIGH |

New responsibilities get no new module: every fix is a guard or argument check inside the one function that owns that input, so appending to the large files is the single-authority form noted above. No helper is copied: F034 reuses gate-eval's existing `_ge_phys`/`cd -P` resolution, F147 reuses prove-rule-check's own `same_file_or_ancestor`, F350 reuses ci-local's own `finish_log` bounded `kill -0` / `kill -KILL` wait.

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

> Grounded at base `8ec200e06dce87c947aadf302a20df0102e699ce`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/automate-trail.d/closeout.sh`** — keep: every refusal is a `closeout: skipped — <reason>` line with return 0 (`local S="closeout: skipped —"`); the parser arm being fixed is `--session-id) sid="${2:-}"; shift 2 || shift ;;`; the stamped check reads unfenced text (`<<<"$(_unfenced_text "$1")"`). Pinned by: `loomwright/scripts/test-automate-trail.d/02-closeout.sh`.
- **`loomwright/scripts/automate-merge-watch.sh`** — keep: always exits 0 (`and always exits 0.`); backoff + failure-notify on a failed state read (`echo "merge-watch: gh pr view failed — next poll in ${wait_s}s ($detail)"`); `esc_recheck` still prefix-compares the recorded sha to the PR's CURRENT head (`case "$head" in "$sha"*)`). The call being split: `view="$("$GH" pr view "$pr_url" --json state,headRefOid,statusCheckRollup 2>"$GH_ERR")"; rc=$?`. The armed rollup call requests `headRefOid,statusCheckRollup` and `esc_recheck` prefix-compares THAT call's head (never a head from the state call against a rollup from the second call); the comments describing the single-call shape (`carries headRefOid + statusCheckRollup for the settle re-check below`, and `(no extra call)` in the `esc_recheck` comment) are updated to the two-call contract. Pinned by: `loomwright/scripts/test-automate-trail.d/04-watcher-branch-mode.sh` (`--json state,headRefOid,statusCheckRollup`, leg E9).
- **`loomwright/scripts/automate-helpers.d/runfile.sh`** — keep: refusals leave the run file untouched (`value contains '|' or a newline; $out left unchanged`) — extend that same `case`, keep the message family. Pinned by: `loomwright/scripts/test-automate-helpers.d/14-escalation.sh`, `02-runfile.sh`.
- **`loomwright/scripts/automate-helpers.d/resume.sh`** — keep: `brief-repair: ` handling (`"brief-repair: "*) case "$line" in *"skipped —"*) ;; *) changed=1 ;; esac; continue ;;`) and the anchored partial-removal rule (`case "$t" in "removed — worktree "*"; kept "*) cls=leftover ;; esac`); a `trail-pr:` line must not be counted as a `closeout:` row (it changes `changed` only, never `n` or `rows`). Pinned by: `loomwright/scripts/test-automate-trail.d/02-closeout.sh`, `05-finalize-closeout-others.sh`.
- **`loomwright/scripts/automate-helpers.sh`** — keep: gate-eval fails CLOSED (`echo "PARK: rules_gate_dirty_tree"; return 0`); rc 1 = key unset (`if [ "$ge_xf_rc" -eq 1 ]; then`); git runs through `_ge_git` (env-scrubbed) and paths are resolved physically (`root_top="$(CDPATH='' cd -P -- "$root_top" 2>/dev/null && pwd -P)" || root_top=""`). `gh pr merge --squash` stays this file's only executor — no merge logic is touched. Pinned by: `loomwright/scripts/test-automate-helpers.d/07-rules-gate.sh` (`rules_gate_dirty_tree`).
- **`loomwright/scripts/automate-next-step.sh`** — keep: read-only for F158 unless the trace proves a lock is held across an ask; any edit must keep "each call prints exactly ONE JSON instruction" (`per-item-loop.md`: `Each call prints exactly ONE JSON instruction`). Pinned by: `loomwright/scripts/test-automate-next-step.sh`.
- **`loomwright/skills/automate-loop/per-item-loop.md`** — keep: the `## Touches`-style prose stays history-free (`scripts/check-prompt-history-refs.sh` baseline may only go down); any sentence added sits beside `A fix-now answer runs ONE owner-requested fix pass and full re-drain`. Pinned by: `loomwright/scripts/test-automate-loop-split.sh`.
- **`loomwright/scripts/test-automate-loop-split.sh`** — keep: its mutation-copy idiom (`M10="$TMP/m10"; mkdir -p "$M10"; cp "$REPO/$SKILL_DIR"/*.md "$M10/"`) for the new leg's control.
- **`loomwright/scripts/test-automate-trail.d/04-watcher-branch-mode.sh`** — keep: the WF1 mutation control still mutates the state read's stderr redirect, re-anchored from `sed 's#statusCheckRollup 2>"\$GH_ERR")"#statusCheckRollup 2>/dev/null)"#'` onto the new `--json state,headRefOid` call (the mutant must still differ from the original — gate it on non-empty + differs + `bash -n`); E9 (`head + rollup come from the poll's own gh pr view`) is rewritten to the new call shape, never deleted.
- **`loomwright/scripts/test-automate-next-step.sh`** — keep: no watcher argv reaches the real gh (`exec gh "$@"` — network locally, absent in CI): the `MW_GH_BODY` stub gets one arm for the state-only call and one for the armed rollup call.
- **Appended-only test files** (`02-closeout.sh`, `14-escalation.sh`, `02-runfile.sh`, `07-rules-gate.sh`, `test-ci-slot.sh`, `test-wait-for-checks.sh`, `test-worktree-salvage.sh`, `test-run-lock.sh`, `test-prove-rule-check.sh`, `scripts/test-bump-version.sh`, `scripts/test-ci-local.sh`) — keep: legs appended; existing legs unchanged; each new leg reuses its suite's own fixture/stub helpers (e.g. `07-rules-gate.sh`'s `rules_gate_dirty_tree` assertions) rather than a new harness.
- **`loomwright/scripts/ci-slot.sh`** — keep: INT/TERM trap releases everything it holds (`trap 'drop_my_ticket; [ -n "$CLAIMING" ] && rm -rf "$CLAIMING"; drop_machine_rec; link_unlock "$MLK"; mutex_unlock; exit 1' INT TERM`); the sleep is output-redirected (`sleep "$POLL" >/dev/null 2>&1 &`). Lines fixed: `case "$POLL" in ''|*[!0-9.]*) POLL=2 ;; esac`. Pinned by: `loomwright/scripts/test-ci-slot.sh`.
- **`loomwright/scripts/wait-for-checks.sh`** — keep: the 570 s per-call cap (`[ "$CALL_MAX" -gt 570 ] && CALL_MAX=570`) and the sleep fallback (`sleep "$INTERVAL" 2>/dev/null || sleep 1`); fix site `DEADLINE=$((_now + BOUND))`. Pinned by: `loomwright/scripts/test-wait-for-checks.sh`.
- **`loomwright/scripts/host-mode.sh`** — keep: `_lw_under_any() {` behavior unchanged (header-only change). Pinned by: `loomwright/scripts/test-host-mode.sh`.
- **`loomwright/scripts/worktree-salvage.sh`** — keep: symlinked directories are already refused in the tracked walk (`[ -d "$WT_TOP/$p" ] && [ ! -L "$WT_TOP/$p" ] || return 1`); the verify stops at the first failure naming the entry (`if ! diff -r "$WT_TOP/$IGN_REL" "$IGN_DST" >/dev/null 2>&1; then`). Pinned by: `loomwright/scripts/test-worktree-salvage.sh`.
- **`loomwright/scripts/run-lock.sh`** — keep: the fix site `case "$EXPECT_PID" in *[!0-9]*) die_usage ;; esac` stays the only `--pid` validation. Pinned by: `loomwright/scripts/test-run-lock.sh`.
- **`loomwright/scripts/prove-rule-check.sh`** — keep: unknown containment falls back (`if [ -n "$TOP_ERR" ]; then`), `same_file_or_ancestor "$out_dir" "$TOP" && OUT_INSIDE=1`, and the explicit mktemp template (`s_raw="$(mktemp -d "${TMPDIR:-/tmp}/prove-rule-check.XXXXXX" 2>/dev/null)" || s_raw=""`). Pinned by: `loomwright/scripts/test-prove-rule-check.sh`.
- **`loomwright/scripts/guard-finalize-publish.sh`** — keep: it is a fail-CLOSED `PreToolUse[Bash]` leaf with no `|| true` in `hooks.json`; header-only change at `by a hand \`Write\` (which would let the same agent forge it).` Pinned by: `loomwright/scripts/test-guard-finalize-publish.sh`.
- **`scripts/bump-version.sh`** — keep: restore-every-file-on-failure; both scratch sites (`WORK="$(mktemp -d "$repo_root/.bump-version.XXXXXX")"`) move together; dry-run fix site `also regenerates: $CAPS_JSON (plugin_version only)`. Pinned by: `scripts/test-bump-version.sh` (run by name in ci.yml: `bash scripts/test-bump-version.sh`).
- **`scripts/ci-local.sh`** — keep: lsof absence is tolerated (`if command -v "$leak_lsof" >/dev/null 2>&1; then leak_have_lsof=1;`) and fd 9 is closed for lsof (`9<&- || true`); fix site `"$leak_lsof" -nP -iTCP -sTCP:LISTEN -Fp` (and the fd-holder probe `"$leak_lsof" -nP -t -- "$tmpd/leak.fd"`); reuse: `finish_log`'s bounded wait (`while kill -0 "$p" 2>/dev/null && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done`, then `kill -KILL "$p" 2>/dev/null || true`). Pinned by: `scripts/test-ci-local.sh` (run by name in ci.yml: `run: bash scripts/test-ci-local.sh`).
- **`.github/workflows/ci.yml`** — keep: only the step `name:` changes, no line inserted (a shifted line breaks pinned `ci.yml:NN` citations — `test-citation-drift.sh`); fix site `- name: Check per-agent prompt token budgets (prompt-inventory ratchet)`.

## Closed enumerations touched

> Sibling grep at base `8ec200e06dce87c947aadf302a20df0102e699ce`: `grep -rnF 'skipped — missing argument' loomwright/scripts` → hits in `automate-trail.d/closeout.sh` (the emitter: `echo "$S missing argument"`) and `automate-helpers.d/resume.sh` (the classifier row).

- **`closeout: skipped — --session-id needs a value`** (sibling: `closeout: skipped — missing argument`) — must be named in:
  - `loomwright/scripts/automate-helpers.d/resume.sh` — `CLOSEOUT_TABLE` (header: `EVERY \`closeout: …\` line automate-trail.sh's closeout can print`), anchor `leftover|guard|skipped — missing argument` — extend with `leftover|guard|skipped — --session-id needs a value` beside it.
  - `loomwright/scripts/automate-trail.d/closeout.sh` — the emitter — extend (new refusal line, same `$S` prefix).

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-automate-trail.d/02-closeout.sh` — F100 `--session-id --no-trail` refused | restore `--session-id) sid="${2:-}"; shift 2 \|\| shift ;;` in `loomwright/scripts/automate-trail.d/closeout.sh` (remove the empty/`--*` value check) |
| `loomwright/scripts/test-automate-trail.d/02-closeout.sh` — F102 `done-ish` not stamped / trailing-blank sentinel stamped | revert the `_co_stamped` heading regex to `done(_with_escalation)?([^A-Za-z0-9_]\|$)` and the sentinel compare to `prev = ($0 == s)` in `closeout.sh` |
| `loomwright/scripts/test-automate-trail.d/02-closeout.sh` — F100 refusal classified `guard` | delete `leftover\|guard\|skipped — --session-id needs a value` in `loomwright/scripts/automate-helpers.d/resume.sh` |
| `loomwright/scripts/test-automate-trail.d/02-closeout.sh` — F038 trail-pr-only change appends no "nothing to close out" | delete the `trail-pr: opened\|pushed` arm in `closeout_classify` in `loomwright/scripts/automate-helpers.d/resume.sh` |
| `loomwright/scripts/test-automate-trail.d/04-watcher-branch-mode.sh` — F062 merge seen while the rollup read fails; no rollup without an armed line | restore the single `--json state,headRefOid,statusCheckRollup` poll call in `loomwright/scripts/automate-merge-watch.sh` |
| `loomwright/scripts/test-automate-helpers.d/14-escalation.sh` / `02-runfile.sh` — F063 cntrl / non-hex refused | delete the `[[:cntrl:]]` arm from the value `case` in `current-escalation` (resp. `current-set`) in `loomwright/scripts/automate-helpers.d/runfile.sh` |
| `loomwright/scripts/test-automate-helpers.d/07-rules-gate.sh` — F035 HOME-unset clean checkout not parked | delete the HOME/XDG-empty skip before the `config --global` read in `loomwright/scripts/automate-helpers.sh` |
| `loomwright/scripts/test-automate-helpers.d/07-rules-gate.sh` — F034 core.worktree redirect parks | delete the root-beneath-toplevel identity check in gate-eval in `loomwright/scripts/automate-helpers.sh` |
| `loomwright/scripts/test-automate-loop-split.sh` — F168 mkdir-before-pick-guard on both surfaces | delete `mkdir -p .supervisor/automate` from the Start order in `loomwright/skills/automate-loop/resume.md` (scratch copy) |
| `loomwright/scripts/test-ci-slot.sh` — F027 POLL `.`/`1.2.3` fall back to 2 | flip `''\|*[!0-9]*` back to `''\|*[!0-9.]*` in the POLL validation in `loomwright/scripts/ci-slot.sh` |
| `loomwright/scripts/test-ci-slot.sh` — F028 poll sleep killed on TERM | delete the sleep-pid kill from the INT/TERM trap in `ci-slot.sh` |
| `loomwright/scripts/test-wait-for-checks.sh` — F090 `--bound 08` | delete the `BOUND=$((10#$BOUND))` normalisation in `loomwright/scripts/wait-for-checks.sh` |
| `loomwright/scripts/test-wait-for-checks.sh` — F090 final sleep capped at the remaining `CALL_MAX` budget | delete the line that clamps the poll sleep to `CALL_MAX - SECONDS` in `loomwright/scripts/wait-for-checks.sh` |
| `loomwright/scripts/test-automate-trail.d/04-watcher-branch-mode.sh` — WF1 re-anchored mutation control (state read's stderr redirect) | flip `2>"$GH_ERR"` → `2>/dev/null` on the `--json state,headRefOid` poll call in `loomwright/scripts/automate-merge-watch.sh` (the control must then see the mutant go red) |
| `loomwright/scripts/test-worktree-salvage.sh` — F139 symlinked ignored entry fails the verdict | delete the symlink refusal for ignored entries in `loomwright/scripts/worktree-salvage.sh` |
| `loomwright/scripts/test-run-lock.sh` — F145 `--pid ''` usage error | flip `''\|*[!0-9]*) die_usage` → `*[!0-9]*) die_usage` in `loomwright/scripts/run-lock.sh` |
| `loomwright/scripts/test-prove-rule-check.sh` — F147 in-repo TMPDIR leaves the tree clean | delete the scratch-inside-TOP check in `loomwright/scripts/prove-rule-check.sh` |
| `loomwright/scripts/test-prove-rule-check.sh` — F148 cwd in `.git` writes no proof into the tree | delete the `--git-dir ok, --show-toplevel failed ⇒ OUT_INSIDE=1` branch in `prove-rule-check.sh` |
| `scripts/test-bump-version.sh` — F002 no `.bump-version.` path in `git status` | flip `$(git rev-parse --absolute-git-dir)` back to `$repo_root` in a scratch `mktemp -d` site in `scripts/bump-version.sh` |
| `scripts/test-bump-version.sh` — F070 dry-run reports a stale contract | delete the dry-run render + capabilities verify in `scripts/bump-version.sh` |
| `scripts/test-ci-local.sh` — F350 hung lsof bounded (all three variants) | delete the `finish_log`-style bounded wait around the before-suite / after-suite listener read / `-t` fd-holder probe (one row per variant leg) in `scripts/ci-local.sh` |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Automate engine: closeout, merge watcher, run-file values, gate-eval, split-test drift leg (F100 F062 F168 F035 F063 F102 F034 F038 F157 F158 F175) | AC1, AC2, AC3–AC12, V1 | 14 modify, 1 create | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` | LAUNCHABLE |
| 2 | Standalone script validators: ci-slot, wait-for-checks, salvage, run-lock, prove-rule-check, two honest headers (F027 F028 F090 F099 F139 F145 F147 F148 F075) | AC1, AC2, AC13–AC20, V1 | 12 modify, 1 create | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` | LAUNCHABLE |
| 3 | Repo-root scripts + release: bump-version, ci-local leak gate, ci.yml step name, changelog fragment (F002 F070 F350 F292) | AC1, AC2, AC21–AC24, V1, V2 | 5 modify, 2 create | `skills/unit-testing/SKILL.md`, `skills/ci-cd/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "docs/evidence/dismissed-followups-02-engine.md"}
  - {kind: "symbol", path: "loomwright/scripts/automate-trail.d/closeout.sh", name: "--session-id needs a value"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.d/resume.sh", name: "trail-pr: opened"}
requires: []
lanes:
  - "loomwright/scripts/automate-trail.d/closeout.sh"
  - "loomwright/scripts/automate-merge-watch.sh"
  - "loomwright/scripts/automate-helpers.d/runfile.sh"
  - "loomwright/scripts/automate-helpers.d/resume.sh"
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/automate-next-step.sh"
  - "loomwright/skills/automate-loop/per-item-loop.md"
  - "loomwright/scripts/test-automate-loop-split.sh"
  - "loomwright/scripts/test-automate-trail.d/02-closeout.sh"
  - "loomwright/scripts/test-automate-trail.d/04-watcher-branch-mode.sh"
  - "loomwright/scripts/test-automate-next-step.sh"
  - "loomwright/scripts/test-automate-helpers.d/14-escalation.sh"
  - "loomwright/scripts/test-automate-helpers.d/02-runfile.sh"
  - "loomwright/scripts/test-automate-helpers.d/07-rules-gate.sh"
  - "docs/evidence/dismissed-followups-02-engine.md"
external_requires: []

# Subtask 2
provides:
  - {kind: "file", path: "docs/evidence/dismissed-followups-02-validators.md"}
  - {kind: "symbol", path: "loomwright/scripts/run-lock.sh", name: "''|*[!0-9]*) die_usage"}
requires: []
lanes:
  - "loomwright/scripts/ci-slot.sh"
  - "loomwright/scripts/wait-for-checks.sh"
  - "loomwright/scripts/host-mode.sh"
  - "loomwright/scripts/worktree-salvage.sh"
  - "loomwright/scripts/run-lock.sh"
  - "loomwright/scripts/prove-rule-check.sh"
  - "loomwright/scripts/guard-finalize-publish.sh"
  - "loomwright/scripts/test-ci-slot.sh"
  - "loomwright/scripts/test-wait-for-checks.sh"
  - "loomwright/scripts/test-worktree-salvage.sh"
  - "loomwright/scripts/test-run-lock.sh"
  - "loomwright/scripts/test-prove-rule-check.sh"
  - "docs/evidence/dismissed-followups-02-validators.md"
external_requires: []

# Subtask 3
provides:
  - {kind: "file", path: "docs/evidence/dismissed-followups-02-repo-scripts.md"}
  - {kind: "file", path: "changelog.d/dismissed-followups-02-gate-closeout-and-guard-correctness.md"}
  - {kind: "symbol", path: ".github/workflows/ci.yml", name: "Check prompt token budgets (agents, skills, commands)"}
requires: []
lanes:
  - "scripts/bump-version.sh"
  - "scripts/ci-local.sh"
  - ".github/workflows/ci.yml"
  - "scripts/test-bump-version.sh"
  - "scripts/test-ci-local.sh"
  - "docs/evidence/dismissed-followups-02-repo-scripts.md"
  - "changelog.d/dismissed-followups-02-gate-closeout-and-guard-correctness.md"
external_requires: []
```

Subtask 3's fragment is the PR's only `changelog.d/` entry and covers all three groups (it summarises the dispositions this brief assigns; the version bump itself is folded by `bash scripts/bump-version.sh` at release, never hand-edited).

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 (independent)
Subtask 2 (independent)
Subtask 3 (independent)
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none | NO |
| Subtask 1 | Subtask 3 | none | NO |
| Subtask 2 | Subtask 3 | none | NO |

### Batch Plan
- **Batch 1:** Subtask 1, Subtask 2, Subtask 3 (parallel)
- **Recommended workers:** 3
- **Estimated batches:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` |
| 2 | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` |
| 3 | `skills/unit-testing/SKILL.md`, `skills/ci-cd/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): 24 findings over ~33 files exceed one worker's context | MEDIUM | `context-bound` split into 3 zero-overlap groups; each group writes its own evidence file so no shared file exists |
| Feasibility (Phase 2.5): regression legs and the ci.yml step sit outside the requirement's `## Touches` | MEDIUM | Asked once at Launch Pad Phase 6 (`LP-SCOPE`) before save |
| F062 changes the watcher's gh call shape, which leg E9 and other suites' `gh` stubs match exactly (`--json state,headRefOid,statusCheckRollup`) | HIGH | Subtask 1 greps every stub of that exact argv (`grep -rn 'state,headRefOid,statusCheckRollup' loomwright/scripts/test-*`) AND the WF1 `sed` control (`grep -rn 'statusCheckRollup 2>' loomwright/scripts/test-*`), and updates each that serves the watcher (Plan Review found only `04-watcher-branch-mode.sh` and `test-automate-next-step.sh`'s `MW_GH_BODY`; `test-automate-lanes.d/04-fleet-closeout-to-optout.sh`'s `ws-gh` matches `pr view` alone and needs no change); E9 is rewritten to the new contract, not deleted; the test-integrity guard is honored (no assertion removed without a replacement) |
| F034/F035 edit gate-eval, the auto-merge gate's own condition-7 reads — a wrong edit could make the gate fail OPEN | HIGH | Both fixes only add a path to the existing `PARK: rules_gate_dirty_tree` branch or skip a read that would otherwise park; no condition is removed; `07-rules-gate.sh` legs cover both the park and the no-park side |
| F350's `lsof -b` can stop the fd-holder probe from matching a file path | MEDIUM | Time-bound first via `finish_log`'s bounded-wait idiom; add `-b` only if `test-ci-local.sh`'s existing leak legs stay green with it |
| F028's "no orphan sleep" leg may be flaky on bash 3.2 (trap timing) | LOW | AC14 allows `recorded` with a reason if a deterministic leg is not possible |
| Pre-fix-red proof (AC2) needs the base-commit script; a worktree has it at its base | LOW | Run each new leg against `git show 8ec200e…:<path>` copied to a scratch dir; record the red line in the evidence file |
| A concurrent session in this checkout can sweep uncommitted edits (project memory) | LOW | Workers run in their own worktrees; commit per finding group |

## Configuration
- **Workers:** 3
- **Mode:** parallel
- **Estimated batches:** 1
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-09-dismissed-followups-02-gate-closeout.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-11-09T17:34:04Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/863
- **Branch:** feature/dismissed-followups-02-gate-closeout
- **Files changed:** 36
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 0
- **Heal reason:** needs_human
- **Heal remaining issues:** 3
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** unknown (no_driver_handover)
- **Summary:** 24 findings dispositioned across three evidence files (20 fixed with regression legs, F028 and F099 recorded, F157/F075/F292 wording, F158 worded after trace). Phase 4.5 reviewer NEEDS_HUMAN on iteration 1: (1) F099 host-mode.sh wording blocked by test-integrity guard; needs a human edit or acceptance of 'recorded'; (2) comment-only guard-finalize-publish.sh edit trips the guard-*.sh HIGH lens; owner to confirm keeping it; (3) fixable: validators evidence's AC2 red results come from in-suite mutants, not base-copy re-runs (F027 F090 F139 F145 F147 F148). Every executed repro held (gate-eval F034/F035, merge-watch F062, closeout F102, ci-local lsof bound). Driver parked on an interim EXECUTE_CHECKPOINT, so the run resumed in-session and finished Phase 4 on the legacy path.

## Not verified
- **_co_stamped em-dash regex under gawk/mawk (Linux CI)** — only macOS awk is installed locally (subtask 1)
- **real D-state lsof on stale mount** — not reproducible locally; stub-based (subtask 3)
- **ci-local.sh --affected by the validators worker** — not run by the worker; the merged branch's --affected run passed (subtask 2)
