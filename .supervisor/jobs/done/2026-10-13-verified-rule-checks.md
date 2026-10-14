# Supervisor Job: A rule's `check` must prove it can fail before it becomes a `must` rule

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** dirty (1 untracked file: `AI-Radar-All.md`, unrelated), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 2 (orphaned worktrees of merged PRs; unrelated untracked file)
- **Source requirement:** .supervisor/requirements/verified-rule-checks.md
- **Base commit:** 4c1b594d56d824a929db1e7e0c6aa17d93712a23

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2 + jq + git, same as every sibling script (`add-rule.sh`, `rules-check.sh`) |
| 2 | Dependency Availability | GO | `git worktree`, `git apply`, `jq`, a sha256 tool (`shasum`/`sha256sum`/`openssl`) — all already required by sibling scripts |
| 3 | Architecture Fit | GO | One new standalone script plus a new optional flag on the existing sole writer; no new store, no schema member (D4) |
| 4 | Scope vs Supervisor Capability | CAUTION | ~12 files; D2 forces two files beyond the requirement's `## Touches` (`harvest-conventions.sh` + its test — see Risk Assessment) |
| 5 | Hard Blockers | CAUTION | The requirement's Validation step 3 assumes "one real existing `must` rule from `.agent/rules/`" — the store holds none (all 3 rules are `advisory`, `check: null`). Substituted, see Acceptance Criteria 11 |

**Overall Verdict:** CAUTION

## Task
**Goal:** Add `prove-rule-check.sh`, which shows a rule's `check` passes on the current tree and fails on a counterexample patch applied in a throwaway worktree, and make `add-rule.sh` refuse a `must` rule with a `check` unless it carries a `PROVEN` proof file for that exact check string.

**Problem Statement:**
The owner needs every gate-countable `must` rule to be backed by a check that can actually fail, because a stamped, countable must-check feeds Phase 4.5, the drain and `gate-eval` condition 7.
Currently, `/rules add` and `/dreaming`'s "Accept rule WITH check" write a `must` rule whose `check` has never run; `add-rule.sh` validates shape and wording only, and the first execution (`/rules check --confirm`) proves only that it passes today. This causes a vacuous check (`true`, an always-present token, a path typo) to count as a green gate forever.
Success looks like: a `must` + `check` rule cannot be written without a `PROVEN` proof, and the proof run leaves the user's tree and worktree list exactly as it found them.

## Acceptance Criteria
- [ ] 1. Given `--check 'true'` and any applicable counterexample patch, when `prove-rule-check.sh --confirm` runs, then it prints verdict `VACUOUS`, exits non-zero, and no `must` rule can be written from its proof file.
- [ ] 2. Given a check that greps for a token present on the current tree and a patch deleting that token, when `prove-rule-check.sh --confirm` runs, then it prints `PROVEN`, exits 0, and `add-rule.sh --enforcement must --check <same> --proof <file> --confirm` writes the rule.
- [ ] 3. Given a check that fails on the current tree, when `prove-rule-check.sh --confirm` runs, then it prints `FAILS_NOW`, exits non-zero, never runs the counterexample leg, and nothing is written.
- [ ] 4. Given a patch that does not apply, OR no usable `git worktree` (not a git repo / `git worktree add` fails), OR a check exceeding the timeout, when `prove-rule-check.sh --confirm` runs, then it prints `UNPROVABLE (<reason>)` and exits non-zero (2); every error path is `UNPROVABLE`, never `PROVEN`.
- [ ] 5. Given no `--confirm` on argv and no interactive TTY (stdin and stdout not both TTYs), when `prove-rule-check.sh` runs with a canary check (`touch <canary>`), then the canary file does not exist afterwards and the verdict is `UNPROVABLE (needs_confirmation)`; an ambient environment variable never substitutes for `--confirm`.
- [ ] 6. Given any verdict (all four) and a check that does not itself write files, when the run ends, then `git worktree list --porcelain` and `git status --porcelain` of the user's repo are byte-identical to their state before the run (the prover's OWN steps — scratch dir, worktree, patch apply, proof file — never touch the user's tree), and the scratch directory no longer exists; a scratch worktree that cannot be removed and verified gone is itself `UNPROVABLE (scratch_leak)`. Honest limit, stated in the script header: leg 1 runs the check in the user's working tree, so a check that writes there (as AC 5's `touch` canary would if confirmed) changes the tree; the prover does not sandbox the check itself.
- [ ] 7. Given any prove run, when it ends, then the user-scope rules stamp file (`~/.claude/loomwright/rules-check-stamp.json`, under a test `HOME`) is not created or changed.
- [ ] 8. Given `add-rule.sh --enforcement must --check X` with no `--proof`, OR a `--proof` file that is missing / not JSON / verdict not `PROVEN` / recorded `check_sha256` ≠ sha256 of `X`, when it runs (with or without `--confirm`), then it refuses (non-zero, `rejected:` message, nothing written); `--proof` combined with `--retract` is refused like every other add-only flag; advisory adds and adds without `--check` behave exactly as before.
- [ ] 9. Given the harvester's `invocation (Accept rule WITH check):` line, when `/dreaming` delivery step 3 runs it with `$CANDIDATE` and `$PROOF` loaded as documented, then the rule is written; and `commands/dreaming.md` documents producing the proof (counterexample patch shown to the human beside the candidate, prove run, verdict + both check outputs in the rules PR body) and the D3 fallback (a non-`PROVEN` candidate is offered as `advisory` with the check kept as data).
- [ ] 10. Given `/rules add --enforcement must --check …`, when the command runs, then `commands/rules.md` documents the proof step before `add-rule.sh`, the D3 advisory fallback, and that proving writes no stamp; `skills/rules/SKILL.md` §7 lists the proof requirement and §9 names `prove-rule-check.sh` as a confirm-gated runner of a CANDIDATE check string that never reads the store, while `rules-check.sh` stays the sole executor of a stored rule's check.
- [ ] 11. Given this repo, when V3 is run, then a committed evidence file `docs/evidence/verified-rule-checks.md` contains (a) one realistic candidate check proved `PROVEN` against this repo with a hand-written counterexample patch — both check outputs and the verdict — standing in for the "existing must rule" the requirement assumed (the store holds none), and (b) the same run with `check: true` showing `VACUOUS`; and the PR body links to it.
- [ ] 12. Given the CLAUDE.md bimodal-failure invariant, when any input is malformed or any step cannot complete, then `prove-rule-check.sh` and the new `add-rule.sh` proof check fail CLOSED (non-zero, nothing written) — never a silent pass.

## Touched-file invariants

> Grounded at base `4c1b594d56d824a929db1e7e0c6aa17d93712a23`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/add-rule.sh`** — keep: `set -euo pipefail`; the three-clause validator load guard (`# ---- LOAD GUARD BEGIN` … `# ---- LOAD GUARD END`) and the validator call placed BEFORE the confirm gate (`THE VALIDATOR CALL SITE`) — the new proof check also runs before the confirm gate so a dry-run never plans a write the real run would refuse; the worktree guard (`refusing to write from a non-primary checkout`); the R1 mutual-exclusion message `rejected: --retract cannot be combined with add-only flags` — extend its flag list with `--proof`; JSON built only with `jq -n --arg` (`never string-interpolate untrusted values into JSON`); bash 3.2 (no empty `"${arr[@]}"` under `set -u`). reuse: hash the check string with the same fallback chain `rules-check.sh` uses (`_rc_sha256_file`: `shasum -a 256` → `sha256sum` → `openssl dgst -sha256`), over the exact bytes (`printf '%s'`), no trailing newline added; no sha256 tool ⇒ refuse (fail CLOSED). pinned by: `loomwright/scripts/test-add-rule.sh` cases `(G4c)` and `(G4d)` (`candidate round trip`, `bound candidate round trip`) — both add `--enforcement must --check`; they must now pass a proof and keep their byte-exact round-trip assertions.
- **`loomwright/scripts/test-add-rule.sh` (G4c)/(G4d) — security pin, do NOT weaken:** `(G4d)` asserts `the embedded $( … ) was NOT executed at delivery (marker absent)`, and its candidate contains `touch $MARKER_G7`, so a real `prove-rule-check.sh --confirm` run on it DOES create the marker. Required order: run the prove leg first, then `rm -f "$MARKER_G7"`, then run the documented delivery, then assert the marker is absent — the assertion stays exactly as strong. The `new_repo` fixture commits only `f` (no `src/a/`), so both cases' fixtures must commit a `src/a/` file carrying the shape their candidate needs, or leg 1 reads `FAILS_NOW` and no `PROVEN` proof exists. Fix the now-false `(G4c)` comment `with NO code change to this file` in the same change.
- **`loomwright/scripts/harvest-conventions.sh`** — keep: the candidate is never spliced into the composed string (`the candidate itself is never spliced into this string`); the plain `ADD_RULE_CMD` is byte-unchanged and never carries `--check`; `ADD_RULE_CMD_WITH_CHECK=` keeps `--enforcement must` and the literal `--check \"\$CANDIDATE\"`, and gains the literal `--proof \"\$PROOF\"` before `< /dev/null`. Fix the comment `add-rule.sh has always accepted it — the writer is unmodified` (no longer true). pinned by: `loomwright/scripts/test-harvest-conventions.sh` `(cc2c)` (`--check "$CANDIDATE" < /dev/null`) — update the needle to the new tail; `(u2a)`–`(u2e)` end-to-end delivery (`the documented WITH-check delivery wrote the rule`) — must now produce `$PROOF` with `prove-rule-check.sh --confirm` and a fixture counterexample patch.
- **`loomwright/scripts/test-add-rule.sh`, `loomwright/scripts/test-harvest-conventions.sh`** — keep: the first executable line is the hermetic source line (`hermetic-test-env.sh`, enforced by `scripts/check-test-hermetic.sh`); `ok`/`no` counters; fixtures via `new_repo` (test-add-rule) — no network, no real `HOME` writes.
- **`loomwright/commands/dreaming.md`** — fix the two now-false claims `add-rule.sh` itself is **byte-unchanged** by this feature and `add-rule.sh` itself is unmodified by this; keep the quoted-heredoc `CANDIDATE` delivery shape (`LOOMWRIGHT_CHECK_CANDIDATE`) and `< /dev/null`. Also reconcile the Read-Only Contract's `It never creates a worktree` claim: reword it so `/dreaming` creates no worktree of its own and `prove-rule-check.sh`'s transient scratch worktree is created and removed by that script; state that the counterexample patch file, the proof file and the scratch dir all live under `mktemp -d` OUTSIDE the repo, so `/dreaming` creates no file in the tree (AC 6). Load the patch text the same way as the candidate (quoted heredoc, never spliced).
- **`loomwright/skills/rules/SKILL.md`, `loomwright/commands/rules.md`** — keep the phrasing `scripts/test-rules-docs.sh` pins in BOTH files: `rules-check.sh` named as the sole executor (regex `rules-check\.sh.{0,40}(is|stays|remains|—).{0,25}sole executor`), the reader-never-executes phrasing, and the audit-vs-check lines; state that `prove-rule-check.sh` runs a candidate string passed on argv and never reads `.agent/rules/`.

## Closed enumerations touched

> Sibling grep at base `4c1b594`: `grep -rnF -- '--supersedes' loomwright/scripts/add-rule.sh loomwright/skills/rules/SKILL.md loomwright/commands/rules.md` → the add-only flag list appears in add-rule.sh's R1 runtime message, its header R1 comment and its header Usage line, in SKILL.md §7.5 item 1, and in the rules.md `add` usage block.

- **`--proof`** (sibling: `--supersedes`, an add-only flag) — must be named in:
  - `loomwright/scripts/add-rule.sh` — R1 runtime guard: the condition (`[ "$supersedes_set" -eq 1 ]`) gains a proof-set clause AND the message `(--category/--statement/--check/--supersedes/--applies-to)` gains `--proof` — extend both.
  - `loomwright/scripts/add-rule.sh` — header comment `R1. \`--retract\` is mutually exclusive with every add-only flag` — extend.
  - `loomwright/scripts/add-rule.sh` — header `# Usage:` line — extend.
  - `loomwright/skills/rules/SKILL.md` — §7.5 item 1 (`any add-only flag`) — already stale (lacks `--applies-to`); replace the restated list with a pointer to add-rule.sh's R1 message (advisory restated-list rule).
  - `loomwright/commands/rules.md` — the `add-rule.sh` usage block under `add` — extend.
  - `loomwright/scripts/add-rule.sh` — the ADD-action rejection `rejected: --target/--reason/--replacement are only valid together with --retract` — no change: it lists retract-only flags, and `--proof` is add-only.
  - `loomwright/commands/rules.md` frontmatter `description`, `loomwright/capabilities.json` (its mirror) and `loomwright/commands/agent-help.md` — each reads `add` (with optional `--supersedes` and repeatable `--applies-to` path routing) — no change, deliberately: they describe OPTIONAL flags and are not closed lists, and `--proof` is required (not optional) for must+check. If the rules.md frontmatter description is edited anyway, `capabilities.json` must change in the same commit — it is not in `lanes:`, so do not edit that description.
- **Verdicts `PROVEN` / `VACUOUS` / `FAILS_NOW` / `UNPROVABLE`** — a new closed set, owned by `prove-rule-check.sh`'s header; `add-rule.sh` accepts only `PROVEN`; docs reference, never restate a different set.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `test-prove-rule-check.sh` — VACUOUS case (`true` check) | replace the counterexample leg's check run with a no-op that reports exit 1 (requirement Validation 2) ⇒ the VACUOUS test must go red |
| `test-prove-rule-check.sh` — needs-confirmation canary | delete the confirmation guard so the check runs without `--confirm` ⇒ canary created, test red |
| `test-prove-rule-check.sh` — no-leak (worktree list / status identical) | delete the scratch `git worktree remove` line ⇒ leak test red |
| `test-add-rule.sh` — must+check without `--proof` refused | delete the proof-required check in `add-rule.sh` ⇒ refusal test red |
| `test-add-rule.sh` — proof for a different check refused | drop the `check_sha256` comparison in `add-rule.sh` ⇒ mismatched-proof test red |
| `test-harvest-conventions.sh` `(cc2c)` | delete `--proof \"\$PROOF\"` from `ADD_RULE_CMD_WITH_CHECK` ⇒ `(cc2c)` red |
| `test-prove-rule-check.sh` — FAILS_NOW, leg 2 skipped (AC 3) | make leg 1's result always 0 ⇒ FAILS_NOW test red; run leg 2 unconditionally ⇒ the "leg 2 not run" assertion (scratch never created / counterexample exit absent) red |
| `test-prove-rule-check.sh` — `UNPROVABLE (patch_does_not_apply)` | ignore the `git apply` exit status ⇒ test red |
| `test-prove-rule-check.sh` — `UNPROVABLE` when `git worktree add` fails / not a git repo | ignore the `git worktree add` exit status ⇒ test red |
| `test-prove-rule-check.sh` — `UNPROVABLE (timeout)` (test passes `--timeout 1` with a `sleep` check) | delete the watchdog kill ⇒ the run hangs past the test's own bound / verdict wrong ⇒ test red |
| `test-prove-rule-check.sh` — `UNPROVABLE (scratch_leak)` (test stubs worktree removal to fail) | delete the verify-gone step ⇒ verdict reads PROVEN ⇒ test red |
| `test-prove-rule-check.sh` — stamp file untouched (AC 7, test `HOME`) | add a write to `$HOME/.claude/loomwright/rules-check-stamp.json` in the prover ⇒ test red |
| `test-add-rule.sh` — non-`PROVEN` proof refused | delete the `verdict == PROVEN` comparison in `add-rule.sh` ⇒ VACUOUS-proof test red |
| `test-add-rule.sh` — missing / non-JSON proof file refused | treat an unreadable proof as absent-OK ⇒ test red |
| `test-add-rule.sh` — `--proof` with `--retract` refused | drop the proof-set clause from the R1 guard ⇒ test red |
| `test-harvest-conventions.sh` `(u2a)`–`(u2e)` | drop `--proof \"\$PROOF\"` from `ADD_RULE_CMD_WITH_CHECK` ⇒ the documented delivery is refused by `add-rule.sh` ⇒ `(u2b)` red |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Proof gate: `prove-rule-check.sh` + `add-rule.sh --proof` + callers/docs | all | 7 modify, 4 create | `skills/rules/SKILL.md`, `skills/unit-testing/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/scripts/prove-rule-check.sh"}
  - {kind: "symbol", path: "loomwright/scripts/prove-rule-check.sh", name: "VACUOUS"}
  - {kind: "symbol", path: "loomwright/scripts/prove-rule-check.sh", name: "UNPROVABLE"}
  - {kind: "file", path: "loomwright/scripts/test-prove-rule-check.sh"}
  - {kind: "symbol", path: "loomwright/scripts/add-rule.sh", name: "--proof"}
  - {kind: "symbol", path: "loomwright/scripts/harvest-conventions.sh", name: "$PROOF"}
  - {kind: "symbol", path: "loomwright/commands/dreaming.md", name: "prove-rule-check.sh"}
  - {kind: "symbol", path: "loomwright/commands/rules.md", name: "prove-rule-check.sh"}
  - {kind: "symbol", path: "loomwright/skills/rules/SKILL.md", name: "prove-rule-check.sh"}
  - {kind: "file", path: "changelog.d/verified-rule-checks.md"}
  - {kind: "file", path: "docs/evidence/verified-rule-checks.md"}
requires: []
lanes:
  - "loomwright/scripts/prove-rule-check.sh"
  - "loomwright/scripts/test-prove-rule-check.sh"
  - "loomwright/scripts/add-rule.sh"
  - "loomwright/scripts/test-add-rule.sh"
  - "loomwright/scripts/harvest-conventions.sh"
  - "loomwright/scripts/test-harvest-conventions.sh"
  - "loomwright/skills/rules/SKILL.md"
  - "loomwright/commands/rules.md"
  - "loomwright/commands/dreaming.md"
  - "changelog.d/verified-rule-checks.md"
  - "docs/evidence/verified-rule-checks.md"
external_requires:
  - "git >= 2.17 (git worktree add --detach / remove)"
  - "jq"
  - "a sha256 tool: shasum, sha256sum or openssl"
```

### Design notes for the worker (decided here; do not re-open)
- **Interface:** `prove-rule-check.sh --check <str> --counterexample <patch-file> [--out <proof-file>] [--confirm] [--timeout <secs>]` (default timeout 60, env override allowed for the timeout only). Runs from the repo root (`git rev-parse --show-toplevel`). The check string comes ONLY from argv — the script never reads `.agent/rules/`.
- **Confirmation (scope 2/3):** print the check and the patch text, then run only on argv `--confirm` or an interactive TTY `y` (stdin AND stdout TTYs). No env var confirms. Otherwise: nothing runs, verdict `UNPROVABLE (needs_confirmation)`.
- **Order:** leg 1 runs `bash -c "<check>" </dev/null` in the repo root → non-zero ⇒ `FAILS_NOW` (leg 2 skipped). Leg 2: `mktemp -d` scratch, `git worktree add --detach <scratch>/wt HEAD`, `git apply` the patch there (fails ⇒ `UNPROVABLE (patch_does_not_apply)`), run the check in `<scratch>/wt` → exit 0 ⇒ `VACUOUS`, non-zero ⇒ `PROVEN`. Cleanup in a trap: `git worktree remove --force <scratch>/wt`, `git worktree prune`, `rm -rf <scratch>`, then VERIFY (`git worktree list --porcelain` has no entry for it and the dir is gone) — a failed verify overrides the verdict with `UNPROVABLE (scratch_leak)`. The scratch tree is the script's own (nothing of the user's lives there), so `--force` is correct here.
- **Timeout:** no `timeout(1)` on macOS — reuse the background-process + watchdog idiom from `loomwright/scripts/run-self-tests.sh` (`no \`timeout(1)\` (absent on stock macOS)`); a timed-out leg ⇒ `UNPROVABLE (timeout)`.
- **Output:** both legs' exit codes and (bounded) stdout/stderr printed, then ONE final line `verdict: <VERDICT>[ (<reason>)]`. Exit: 0 `PROVEN`, 1 `VACUOUS`/`FAILS_NOW` (examined, failed), 2 `UNPROVABLE` (could not examine) — the repo's 0/1/2 convention.
- **Proof file (D2/D4):** with `--out`, written for every verdict via `jq -n --arg`: `{"schema":"rule-check-proof/1","verdict":…,"check_sha256":…,"counterexample_sha256":…,"now_exit":…,"counterexample_exit":…|null,"ts":…}`. Not a rule-schema member; recorded in commit/PR body only. Honest limit (state it in the header): a hand-forged proof file is not prevented — the gate makes the proof step a required, recorded act, not a cryptographic one.
- **Dirty tree honest limit:** leg 1 runs on the working tree, leg 2 on `HEAD` + patch; document that uncommitted edits are not carried into the scratch copy.

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/rules/SKILL.md`, `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Scope beyond the requirement's `## Touches`: D2 makes `add-rule.sh` refuse the harvester's current WITH-check invocation and the existing `test-add-rule.sh` (G4c/G4d) + `test-harvest-conventions.sh` (cc2c, u2a–u2e) must-adds (Feasibility (Phase 2.5)) | HIGH | `harvest-conventions.sh` + `test-harvest-conventions.sh` added to lanes; tests produce real proofs via `prove-rule-check.sh --confirm` on fixtures, never hand-written proof JSON |
| Requirement Validation 3 assumes an existing `must` rule; the store has none (Feasibility (Phase 2.5)) | MEDIUM | AC 11: prove a realistic candidate check against this repo with a hand-written patch; record the substitution in the PR body |
| A second code path now executes a check string; the "rules-check.sh is the sole executor" invariant is pinned in docs and tests | MEDIUM | Define it as "sole executor of a STORED rule's check"; `prove-rule-check.sh` takes the check from argv only, is confirm-gated, writes no stamp; keep the `test-rules-docs.sh`-pinned phrasing |
| Prior churn (postmortem ledger): `skills/rules/SKILL.md` (11), `add-rule.sh` (2), `harvest-conventions.sh` (1); recurring drain_churn / self_heal_churn / convention_mismatch, self_heal_miss: yes | HIGH | Workers run every touched test plus `test-rules-docs.sh`, `test-citation-drift.sh`, `check-doc-currency.sh`; prose edits use descriptive anchors, never bare `file:N` |
| Leaked scratch worktree or a touched user tree (the worktree-removal lesson) | MEDIUM | Cleanup in a trap + verify-gone; AC 6 asserts worktree list and status are byte-identical across all four verdicts |
| Vendor-coupling ratchet / hermetic gate on new files | LOW | New test sources `hermetic-test-env.sh` first; run `scripts/check-vendor-coupling.sh` after `git add` |

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
/supervisor job: .supervisor/jobs/pending/2026-10-13-verified-rule-checks.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-10-13T17:51:23Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/533
- **Branch:** feature/verified-rule-checks-proof-gate
- **Files changed:** 11
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** prove-rule-check.sh + add-rule.sh --proof gate shipped (D1–D4); 3 heal iterations fixed 5 reproduced findings (3 HIGH, 2 MEDIUM), the final fix fc1e826 is unreviewed; stand-in reviewer (installed 17.0.0 lacks the code-reviewer agent; owner-approved); ground_truth 2/2 pass; contract_conformance skipped (no touched contracts); risk high_risk=true (advisory).

## Not verified
- **/dreaming live proof step** (counterexample at gate 1, prove between the gates, PR-body record) — only the scripted delivery in test-harvest-conventions (u2a–u2e) exercises it (subtask 1)
- **prove-rule-check.sh interactive TTY y confirmation** — needs a real terminal (subtask 1)
- **jq_missing / scratch_create_failed / patch_no_effect branches** — untested (subtask 1)
- **Linux CI behaviour** (sha256sum path, GNU mktemp; the case-insensitive (l) tests skip on Linux) — only run on macOS (subtask 1)
