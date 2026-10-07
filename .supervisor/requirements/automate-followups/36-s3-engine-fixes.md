# 36 — S3 engine fixes: wave-1 review leftovers, lane-run hygiene, and carrying the learning stores

## Status: pending

## Merged from (2026-10-07, owner decision relayed by S3 session 2216aefd: merge the serialized tail into fewer, larger items — every remaining item except pa/14 shares `automate-loop/SKILL.md` with every other, so separate items buy no parallelism and cost a wave each)
- Part A: `automate-followups/35-wave1-review-leftovers.md` — 35 — Wave-1 review leftovers: the seven open notes from the #397 review
- Part B: `parallel-automate/20-lane-run-hygiene.md` — 20 — Lane-run hygiene: an unrun running-system check blocks READY, run files carry no home paths, ci-local fits a lane's command limit
- Part C: `meta-sync-followups/05-carry-the-learning-stores.md` — 05 — Branch mode: carry every store the agents learn from, and prove it with a committed rehearsal

The originals are parked with a pointer here. Their text is kept below VERBATIM as parts (headings
demoted, their Status / Depends on / Touches folded into this file's own sections). Nothing was paraphrased.
Their changelog.d fragment names are replaced by this item's one fragment.

## Depends on
31-transient-escalation-recheck.md
../meta-sync-followups/01-untested-push-and-base-fallbacks.md
../meta-sync-followups/08-meta-sync-hardening.md

## Touches
loomwright/scripts/automate-helpers.d/resume.sh
loomwright/scripts/automate-helpers.d/runfile.sh
loomwright/scripts/test-automate-helpers.sh
loomwright/scripts/automate-trail.sh
loomwright/scripts/test-automate-trail.sh
loomwright/scripts/session-resume.sh
loomwright/scripts/test-session-resume.sh
loomwright/scripts/test-meta-sync.sh
loomwright/docs/result-schemas/execute-result.md
loomwright/skills/automate-loop/SKILL.md
loomwright/scripts/automate-helpers.sh
loomwright/scripts/automate-helpers.d/reconcile-status.sh
loomwright/scripts/fixtures/automate-helpers-help.golden
loomwright/skills/review-heal/SKILL.md
loomwright/commands/automate.md
loomwright/docs/result-schemas/automate-run.md
scripts/ci-local.sh
scripts/test-ci-local.sh
AGENT_GUIDELINES.md
CLAUDE.md
loomwright/scripts/meta-sync.sh
loomwright/scripts/setup-memory.sh
loomwright/scripts/test-setup-memory.sh
loomwright/commands/setup.md
loomwright/skills/setup/SKILL.md
.agent/meta-allowlist.txt
loomwright/commands/dreaming.md
loomwright/commands/agent-help.md
loomwright/docs/ARCHITECTURE_CONTRACTS.md
loomwright/docs/vendor-coupling-manifest.json
changelog.d/36-s3-engine-fixes.md

## Goal
One change set for the engine fixes S3 surfaced: the seven open #397 review notes (A), lane-run hygiene — an unrun must-pass running-system step blocks READY, no home paths in run files, ci-local within a lane's command limit (B, keeps its dependency on automate-followups/31 for `escalation_cause`), and carrying every learning store to the metadata branch with a committed rehearsal (C).

## Acceptance criteria
- Every part's own acceptance criteria hold, on one branch and one PR.

## Validation (must pass before merge)
1. Baseline full loop once for the merged branch, `<passed>/<total>` and `SKIP` counts, base and branch.
2. Every part's own Validation steps, labelled by part in the PR body. A part with no Validation section is
   checked by running its acceptance criteria, and the PR body says so.
3. Any "Running system" step a part names is run, or listed under "Not verified" with the reason.
4. Rollback: `git revert`.

## Parts

### Part A — 35 — Wave-1 review leftovers: the seven open notes from the #397 review

#### Problem
The locally recovered review of wave PR #397 (S3 wave 1) left seven small notes. Each is small; together they are
a recurring source of owner questions, silent drift and untested refusals:
1. **A lock held by a live lane reads as a leftover.** `closeout-classify` maps `skipped — run lock held by *` to
   `leftover|lock` (`automate-helpers.d/resume.sh`, the classification table). Under `closeout-others` the lock is
   often held by a different live lane in the same checkout, so a non-interactive start parks `closeout_leftover`
   for a run that is merely busy.
2. **The SessionStart probe can stall resumes.** `session-resume.sh`'s `sr_pr_state` makes up to 5 sequential `gh`
   calls, each with a 5 s timeout, and no overall deadline: with `gh` offline or unauthenticated about 25 s is added
   to every resume, clear or compact (it still exits 0 and stays quiet).
3. **`current-rebuild` contradicts itself.** It sets `status: running` (the `current_set` call in
   `automate-helpers.d/runfile.sh`'s `current_rebuild` passes no `--pause-reason`) but keeps the stale `pause_reason`
   (often `awaiting_go`), so `## Current` disagrees with itself until the owner's ask.
4. **`finalize-empty` writes `done` before `trail-pr`** (`automate-trail.sh`), so a failed `trail-pr` is never
   retried. This matches the live Termination exit but is undocumented at the call site.
5. **Home-path examples remain in a result schema.** `docs/result-schemas/execute-result.md` (moved there from
   `RESULT_SCHEMAS.md` by pa/11) still shows `path: /Users/<name>/myapp-…` twice, so the changelog's "no home-path
   examples" is not true across the tree.
6. **An untested refusal in meta-sync.** `load_base`'s unreadable meta-base branch (`[ ! -r "$META_BASE" ]` →
   `base_branch_mismatch`, `meta-sync.sh`) has no test leg, unlike the other new refusals; it needs a root guard.
7. **A misleading test title.** `test-meta-sync.sh` test 38's title says symlinked non-managed files "sync"; per the
   code and header they are ignored (never synced, no longer refused). The released `CHANGELOG.md` headline carries
   the same wording — do NOT edit the released entry.

#### Goal
Each note is fixed or explicitly documented, with a test where behaviour changes, in one change set.

#### Scope
1. **Lock held by a live lane:** map `skipped — run lock held by …` to a non-leftover class (recommended:
   `run_lock_held`, retried at the next start) when the holder is live; a dead holder stays `leftover|lock`. Pick
   after reading `closeout_classify` and the `closeout_leftover` park in `automate-loop/SKILL.md`.
2. **One overall deadline for `sr_pr_state`** (or stop after the first `unverified`); the probe stays fail-SAFE
   (exit 0, quiet).
3. **`current-rebuild` clears or rewrites `pause_reason`** consistently with `status: running` (through
   `current_set`, the only writer of `## Current`).
4. **`finalize-empty` order:** reorder so a failed `trail-pr` is retried, or keep the order and add the comment
   explaining why `done` comes first. State which in the PR.
5. **Home-path examples:** replace the two `/Users/<name>/…` examples in `result-schemas/execute-result.md` with
   `~/…` or a repo-relative form.
6. **Test leg** for `load_base`'s unreadable-meta-base refusal (skip under root, as the other permission legs do).
7. **Retitle `test-meta-sync.sh` test 38** to say symlinked non-managed files are ignored. Leave `CHANGELOG.md`'s
   released entry as is.

#### Non-goals
The five #397 findings (done in #400). Any new closeout behaviour beyond the lock classification. Editing released
changelog entries.

#### Acceptance criteria
- A fixture where `closeout-others` meets a run lock held by a LIVE process classifies it as non-leftover and parks
  nothing; a dead holder still reads `leftover|lock`.
- `sr_pr_state` with a stubbed `gh` that hangs returns within the overall deadline.
- After `current-rebuild`, `## Current` never shows `status: running` with a pause-only `pause_reason`.
- `grep -rn '/Users/<name>' loomwright/docs/` returns nothing.

#### Validation (must pass before merge)
1. Baseline full loop (`bash scripts/ci-local.sh`), `<passed>/<total>` and `SKIP` counts, base and branch.
2. Unchanged path: existing `closeout-classify`, `session-resume` and `meta-sync` assertions pass with no assertion
   edited (test 38's title is a title, not an assertion).
3. Running system: one real `/automate --resume` start with another live run holding the lock; paste the
   classification line.
4. A failure this must catch: reverting Scope 1's live-holder check makes its new test fail; removing Scope 6's
   refusal makes the new leg fail.
5. Rollback: `git revert`.

#### Evidence
`proposed/s3w1-wave-pr-397-review.md` §"Questions and smaller notes" (static review of #397's merge commit
`f0b4b66`; nothing executed). Code anchors re-checked 2026-10-07 on `main` `f4b0732`: `resume.sh` maps
`leftover|lock|skipped — run lock held by *`; `runfile.sh`'s `current_rebuild` calls `current_set … --status
running` with no `--pause-reason`; `execute-result.md` carries two `/Users/<name>/myapp-…` paths; `meta-sync.sh`'s
`load_base` has the `[ ! -r "$META_BASE" ]` branch.

### Part B — 20 — Lane-run hygiene: an unrun running-system check blocks READY, run files carry no home paths, ci-local fits a lane's command limit

#### Problem
- **A. An unrun "Running system" check passes as READY.** Wave 2's #402 (pa/16) listed its own three-clone
  `ci-local` check under "Not verified". The lane parked READY. The operator ran it and it FAILED: load1 63.6 (fixed
  on the PR in `cd5f400`). In wave 1 every PR's "Not verified" list hid something the operator then found. Nothing in
  the engine stops a lane from parking READY with a must-pass Validation step not run.
- **B. Lane metadata pushes fail the home-path scrub on the engine's own lines.** `reconcile-status` writes absolute
  home paths into run files, so a lane's metadata push fails the `home_path` scrub: s3-c and s3-d in wave 1, s3-f in
  wave 2 (its records were carried to `loomwright-meta` by hand, `f7709f0`). The scrub is right; the writer is wrong.
- **C. A lane's full `ci-local` exceeds its single-command limit.** A full `ci-local` takes ~620 s in a lane; the
  lane's Bash tool caps a foreground command at 600 s. s3-e was cut off and re-ran it (wave 2, gap 4).

#### Goal
A lane cannot park READY with a must-pass running-system check it did not run; the engine's own run-file lines
pass the scrub; and the pre-push suite can be run by a lane without hitting the command limit.

#### Scope
##### Part A — an unrun must-pass running-system step blocks READY (owner policy)
1. Before the READY / `awaiting_merge` park, the engine compares the item's `## Validation (must pass before merge)`
   "Running system" step(s) with the PR body's evidence. A step listed as "Not verified" / not run, or with no pasted
   output, BLOCKS READY: the item parks `escalated` with a named cause (recommended: `automate-followups/31`'s
   `escalation_cause`, new value `validation_unrun`), naming the step.
2. It stays parked until the step is run (evidence pasted, re-checked) or the owner explicitly waives it; the waiver
   is recorded in `## Progress` with the step and the owner's words. No silent default.
3. Can't-ask branch (CLAUDE.md §"Failure-Mode Invariants": every question gate has a named can't-ask branch):
   non-interactive ⇒ stays parked `escalated`, never waived.
4. Relation to `parallel-automate/05` Scope 15a: that report shows NOT-RUN advisorily; this part makes the same
   condition blocking for the park itself. Keep one reader for both.
5. **Tests:** a fixture PR body listing a running-system step under "Not verified" ⇒ `escalated`
   `validation_unrun`; pasted evidence ⇒ READY as today; a recorded waiver ⇒ READY with the waiver line; an item with
   no running-system step ⇒ unchanged. **Mutation control:** skipping the check must fail the first leg.

##### Part B — `reconcile-status` writes no absolute home paths
1. Trace which `reconcile-status` output reaches a run file with an absolute path (the `plan` / `stamped` rows and
   their justification, appended through `progress-append` per `automate-loop/SKILL.md` RESUME step 7) and fix the
   WRITER: repo-relative paths, or `~/` where a home path is unavoidable. Do not weaken the scrub.
2. **Tests:** a fixture run under a home-like root ⇒ no `/Users/` or `/home/` path in any appended line; the
   existing scrub test still refuses a planted absolute path.

##### Part C — `ci-local` fits a lane's 600 s command limit
1. Either `ci-local` supports a detached run plus a poll (e.g. a background mode that writes the verdict where
   `--last` reads it), or the engine / project guidance says to run it backgrounded and poll its log. Pick one; the
   brief records why. The pass cache, slot and machine gate behave as today.
2. Update the pre-push guidance that names `bash scripts/ci-local.sh` (`AGENT_GUIDELINES.md` §"Pre-push: one
   command", `CLAUDE.md` §"Pre-push test run?") in the same change.
3. **Tests:** a stubbed slow suite completes through the new path with the verdict readable afterwards; a foreground
   run is unchanged.

#### Non-goals
Running any validation step automatically. Changing the home-path scrub. Making `ci-local` faster.

#### Acceptance criteria
- Replaying #402's park (its PR body's "Not verified" three-clone step) gives `escalated` `validation_unrun`, not
  READY.
- A lane metadata push after `reconcile-status` passes the scrub with no hand edit.
- A lane runs the full `ci-local` to a verdict without a timeout cut-off.

#### Validation (must pass before merge)
1. Baseline full loop, `<passed>/<total>` and `SKIP` counts, base and branch.
2. Unchanged path: a READY drain whose PR body pastes every running-system step parks `awaiting_merge` as before; a
   foreground `ci-local` behaves as before.
3. Running system: one real lane run (or sequential `/automate` item) that parks on an unrun step, then READY after
   the step is run; paste both `## Current`s. One real lane metadata push after `reconcile-status`; paste its line.
4. A failure this must catch: the Part A mutation control.
5. Rollback: `git revert`.

#### Evidence
S3 record §"Wave 2 result" (pa/16 failed its own running-system Validation; records carried by hand: home paths;
new gap 4) and §"Wave 1 result" / §"Lessons from wave 1" (merge checks found real gaps the PR bodies left open; s3-c,
s3-d meta-push scrub failures).

### Part C — 05 — Branch mode: carry every store the agents learn from, and prove it with a committed rehearsal

#### Notes on the touched files (conditions moved out of the machine-read section)
- Part B: `meta-sync.sh`, `test-meta-sync.sh`. Part A (and part B's consent text): `setup-memory.sh`, `test-setup-memory.sh`, `commands/setup.md`; `skills/setup/SKILL.md` line saying the allowlist "does not travel".
- Part C: `commands/dreaming.md` plus every prompt restating its PR-path rule — grep found only `commands/dreaming.md` and `commands/agent-help.md`.
- Part D: moved to `07-onboard-any-repo-to-branch-mode.md` (2026-10-06).
- Docs stating the managed set: the `meta-sync.sh` header, `ARCHITECTURE_CONTRACTS.md`, `automate-loop/SKILL.md` (HOOKS.md never mentions branch mode).
- Metadata-branch edits, not part of the code PR: M1 runbook Rollback section and a new `operator-run/M2-carry-learning-stores.md`.
- "Ships in one PR with 04" cannot be expressed in this grammar; it stays in Scope prose. M1 (complete, #361 merged) dropped from Depends.

#### Problem
After M1, run history travels on `loomwright-meta`, and the memory stores (`.supervisor/memory/`, `.claude/agent-memory/`, `.agent/`, `CLAUDE.md`) travel on `main`. Several stores the agents read back to make better decisions travel nowhere: they live on one machine, and a second machine, a fresh clone or a lost disk starts without them. Verified 2026-10-03 in the primary checkout:

| Store | Size | Written by | Read by (what it improves) |
|---|---|---|---|
| `.supervisor/twin/contracts/*.md` + `.supervisor/twin/.provenance.jsonl` | 38 files + 69 lines | Phase 4.5 twin builder via `write-system-contract.sh` | `read-system-contract.sh`, then Launch Pad (advisory invariants in briefs), rubric-grader, self-heal-advisory, session-resume, `/dreaming`, `build-insights.sh`, `/obsidian` |
| `.supervisor/worker-summaries/*.md` | 134 | the worker (`agents/worker.md`), checked by `validate-worker-result.py` | `/dreaming` (its main distillation input), the Floor's churn rules |
| `.supervisor/agent-memory-proposals/*.md` | 1 | code-reviewer (§ "To propose") | `/dreaming` (agent-memory review queue) |
| `.supervisor/automate/<run_id>.dismissed-decisions` | 2 ledgers (TSV: draft, decision, ts) | `automate-dismissed.sh` | `/automate` — without it a run continued elsewhere re-asks decided findings |
| `.supervisor/eval/results.jsonl`, `brain-baseline.jsonl` | 2 | `run-eval.sh`, `brain-baseline-eval.sh` | `/insights`, release-over-release eval trend |
| repo allowlist (`.supervisor/config.json` → `setup_memory.repo_allowlist`) | 2 slugs | `/setup memory` | `meta-sync.sh` scrub (ledger_repo, forge_slug) |

Scrub exposure today: 0 of 38 contracts, 0 of 69 provenance lines and 0 of 134 worker summaries contain a home path; 0 worker summaries contain an e-mail address.

The allowlist gap breaks branch mode on any second machine. Without `config.json`, `setup-memory.sh allowlist` falls back to the current remote only (precedence layer 4). 42 of the 126 ledger records carry the pre-rename slug `vikashruhilgit/ai-agent-manager`, and 51 files on `loomwright-meta` cite it in a forge context. On 2026-10-03, a scratch clone with no `config.json` reported 218 scrub hits. So every trail push that adds a ledger line, or edits an old-slug file, is refused there.

Curated memory reaches `main` only when someone opens a memory PR by hand (the last was #344). `/dreaming`'s documented PR path carries `.agent/rules/*.json` only ("never any other store", `commands/dreaming.md`).

All of today's evidence for branch mode comes from rehearsal and drill scripts typed into a scratch directory: init/push/verify, the two-checkout restore, and the rollback drill that caught the runbook's data-losing rollback. They are not in the repo, so the next migration (M2, for the stores above) would rely on someone retyping them correctly.

#### Goal
Every store that improves how the agents work travels with the repo, guarded by the same scrub and consent as run history. Session and runtime state stays local. Every claim is proven by a committed, re-runnable rehearsal, not by hand.

#### Scope

##### A. The allowlist travels, but a repo can only request entries, never grant them
1. Add a tracked request file (proposed: `.agent/meta-allowlist.txt`, one `owner/repo` per line, `#` comments) that `setup-memory.sh allowlist` reads as a new layer, below `--allow` / env / `config.json` and above the current-remote default.
2. **Grant rule (security — do not drop):** an entry from the tracked file counts ONLY when it resolves to the same repository as `origin`. Check with `gh api repos/<slug> --jq .id`, which follows GitHub's rename redirect, against the id of `origin`'s slug. The current remote's own slug is always granted. Any other entry is ignored and named in one status line (`allowlist: ignored <slug> — not this repository`).
   - Why: the findings ledger collects records about OTHER repos analysed from this checkout. A committed allowlist that a clone's owner controls could otherwise list your private repos and publish their ledger records to a public metadata branch. This is the same rule as telemetry consent (v15.87.0): a repo-relative file can at most request, never grant.
   - When `gh` is unavailable or fails, tracked-file entries are NOT granted (fail closed), and the status line says so. `config.json` and `--allow` keep working offline, unchanged.
3. Seed this repo's request file with its two slugs. Update `/setup memory`'s disclosure to describe the request/grant split.

##### B. meta-sync carries the learning stores
1. Extend the managed set with:
   - `.supervisor/twin/contracts/*.md`
   - `.supervisor/twin/.provenance.jsonl`
   - `.supervisor/worker-summaries/*.md`
   - `.supervisor/agent-memory-proposals/*.md`
   - `.supervisor/automate/*.dismissed-decisions`
   - `.supervisor/eval/results.jsonl`, `.supervisor/eval/brain-baseline.jsonl`

   Same exclusions as today: nested `.supervisor/` trees, non-canonical paths, symlinks.
2. **Twin pair rule:** a push or pull that would leave any contract without its chain-valid provenance entry on either side (branch or local) is refused as a whole. Nothing is half-applied, and every offending contract is named. The test: after any push or pull, `read-system-contract.sh` verifies exactly the contracts present.
3. **Merge semantics per file, stated in the header and tested:**
   - `.provenance.jsonl` is a hash chain, so line-union is WRONG for it. When both sides appended since the meta-base: refuse with `conflict` and name the file. Never auto-merge. The header gives the manual resolution (re-run the twin builder on one side, or `reprovenance-twin-contracts.sh` if that is its documented use — check before citing it).
   - `*.dismissed-decisions` is append-only TSV, so line-union is acceptable. Rows are keyed by draft name, and later rows win in time order. State that ordering rule and test it.
   - `eval/*.jsonl` is append-only history, so line-union is acceptable, the same as `results.jsonl`.
   - Each `.md` store keeps today's per-file 3-way rules.
4. **Scrub covers the new file types:** the prose rules (home path, e-mail, tokens, forge slug, deny file) run over the `.jsonl` files and the extensionless ledgers too. Add a test leg per new type, each proven red with an injected hit.
5. **Consent before first publish:** `loomwright-meta` can be a PUBLIC branch. The first `push` that would add any part-B path asks once and records the answer, in the same shape as `/setup memory`'s consent. It names the stores and says they hold internal reasoning that the scrub only pattern-checks. Without consent, part-B paths are skipped and named, and run history still syncs.
6. Update every doc and check that states the managed set or the ".md + results.jsonl only" rule: the `meta-sync.sh` header, M1's Verify step, `test-meta-sync.sh`, and any doc-currency surface.

##### C. /dreaming offers one memory PR
1. After its per-item Accepts, `/dreaming` offers ONE PR carrying only `.supervisor/memory/` and `.claude/agent-memory/` changes it wrote in this run. Paths are staged explicitly (never `git add -A`), and it refuses when those paths already held uncommitted changes it did not author, matching the rules PR.
2. Two gates, as for the rules PR: per-item Accept (content), then a separate Pre-push confirmation (push). It never merges: `gh pr create`, then stop.
3. Amend the documented PR-path rule in `commands/dreaming.md` (today: "carries **only** `.agent/rules/*.json` … never any other store"), and every prompt that restates it. Decide and state whether the memory PR and the rules PR are one branch or two. `CLAUDE.md` stays out of scope: its edits remain a hand PR, and the doc says so.

##### D. Moved 2026-10-06 to `07-onboard-any-repo-to-branch-mode.md` (Part D there, verbatim)
Owner decision (owner decision: fewer, larger items — a run costs ~$17–20 plus 4+ owner questions even for a tiny change): the rehearsal harness and the M2 runbook belong to onboarding, which already
uses the harness (its Scope 2c). Parts A–C stay here.

#### Stays local (non-goals — decided 2026-10-03, owner: "session-level things we can ignore")
- Session traces: `.supervisor/logs/` (683 files, 13 MB, 35 with home paths, prompt traces), `state.md`, `.current-session*`, `history/`. Their durable output (worker summaries, ledger lines, lessons, memory) travels instead. Honest cost: a second machine's `/dreaming` reflects only on that machine's own logs.
- Per-run machinery: `autonomous/`, `drain-rounds/`, `review-dispatch/`, `postmortem-dispatch/`, `guard/`, `jobs/pending`, `jobs/in-progress`, `jobs/context-digests`, the automate sidecars (`*.config-backup.json`, `*.merge-watch*`, `*.trail-staged`), the nudge markers.
- Regenerated views: `insights/`, `floor/`, `handoff/`, `heal-signal/`.
- Per-machine settings: `curation-state.json` (its consumed-log ids exist only on the machine that has those logs), `notify-config.json` (webhook settings, may hold secrets), `scratch/`, `salvage/`, `worktrees/`.
- **Separate follow-ups, not in this item:** writing orientation notes (`.agent/orientation/` holds only its README); seeding agent memory for launch-pad, product-owner and qa-strategist (6 agents declare `memory: project`, only 3 have stores).

#### Acceptance criteria
- **A1** Given a fresh clone with no `.supervisor/config.json` and the seeded request file, when `meta-sync.sh pull` then a `push` that adds a ledger line and edits a file citing the old slug runs, then the push succeeds, because the old slug resolves to this repo's id.
- **A2** Given a request file listing a slug that resolves to a DIFFERENT repository, when the allowlist is resolved, then that slug is not granted, it is named in the status line, and a ledger record under it is refused by the scrub. The test fails when the id comparison is removed (mutant).
- **A3** Given `gh` is unavailable, when the allowlist is resolved, then tracked-file entries are not granted, `config.json` entries still are, and the status line says why.
- **B1** Given a contract whose provenance line is missing on either side, when `push` or `pull` runs, then it refuses as a whole, names the contract, and changes neither side. The leg goes red when the pair check is removed.
- **B2** Given both sides appended to `.provenance.jsonl` since the meta-base, when `push` runs, then it reports `conflict` for that file and writes nothing. No line-union.
- **B3** Given a round trip into a fresh clone, then `read-system-contract.sh` verifies the same contracts as the source, and worker summaries, proposals, dismissed ledgers and eval files are byte-identical.
- **B4** Given an injected home path or token in a `.jsonl` file and in a `.dismissed-decisions` file, when `push` runs, then the scrub refuses it (exit 2) and nothing is pushed.
- **B5** Given no recorded consent, when `push` would add part-B paths, then it asks (or, non-interactively, skips and names them), and run history still syncs.
- **C1** Given an accepted memory change and no Pre-push confirmation, then no branch is created and nothing is pushed. Given both gates, then the PR carries only `.supervisor/memory/` and `.claude/agent-memory/` paths, and `/dreaming` never merges it.
- **D1–D3:** moved with Part D to `07-onboard-any-repo-to-branch-mode.md`.
- `bash scripts/ci-local.sh` is green. Bump with a `changelog.d/` fragment + `scripts/bump-version.sh` as the last commit, never by hand.

#### Provenance
Owner direction, 2026-10-03, session cc4eaee3 (after M1): carry everything that makes the plugin perform best on the metadata branch; ignore session-level state. Same session: test it the way M1 was tested, step by step. Store inventory and counts were verified in the primary checkout on 2026-10-03, after M1 step 7. The allowlist failure (218 hits without `config.json`) and the rollback defect come from the M1 rehearsal and drill the same day. The draft prompt the owner supplied was reviewed first; its counts held, and its design gaps (allowlist grant rule, curation-state, new file types, chain conflicts, consent, the rules-only PR rule) are resolved above.
