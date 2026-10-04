# 05 — Branch mode: carry every store the agents learn from, and prove it with a committed rehearsal

## Depends on
01
02
03

## Touches
loomwright/scripts/meta-sync.sh
loomwright/scripts/test-meta-sync.sh
loomwright/scripts/setup-memory.sh
loomwright/scripts/test-setup-memory.sh
loomwright/commands/setup.md
loomwright/skills/setup/SKILL.md
.agent/meta-allowlist.txt
loomwright/commands/dreaming.md
loomwright/commands/agent-help.md
loomwright/scripts/meta-sync-rehearsal.sh
loomwright/scripts/test-meta-sync-rehearsal.sh
loomwright/docs/ARCHITECTURE_CONTRACTS.md
loomwright/skills/automate-loop/SKILL.md
.github/workflows/ci.yml
loomwright/docs/vendor-coupling-manifest.json
changelog.d/meta-sync-followups-05-carry-the-learning-stores.md

## Notes on the touched files (conditions moved out of the machine-read section)
- Part B: `meta-sync.sh`, `test-meta-sync.sh`. Part A (and part B's consent text): `setup-memory.sh`, `test-setup-memory.sh`, `commands/setup.md`; `skills/setup/SKILL.md` line saying the allowlist "does not travel".
- Part C: `commands/dreaming.md` plus every prompt restating its PR-path rule — grep found only `commands/dreaming.md` and `commands/agent-help.md`.
- Part D: a new rehearsal script + self-test (proposed names `meta-sync-rehearsal.sh` / `test-meta-sync-rehearsal.sh`); D.3 CI pull step in `.github/workflows/ci.yml`; `vendor-coupling-manifest.json` because the setup-memory scripts carry ratcheted allowances.
- Docs stating the managed set: the `meta-sync.sh` header, `ARCHITECTURE_CONTRACTS.md`, `automate-loop/SKILL.md` (HOOKS.md never mentions branch mode).
- Metadata-branch edits, not part of the code PR: M1 runbook Rollback section and a new `operator-run/M2-carry-learning-stores.md`.
- "Ships in one PR with 04" cannot be expressed in this grammar; it stays in Scope prose. M1 (complete, #361 merged) dropped from Depends.

## Problem
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

## Goal
Every store that improves how the agents work travels with the repo, guarded by the same scrub and consent as run history. Session and runtime state stays local. Every claim is proven by a committed, re-runnable rehearsal, not by hand.

## Scope

### A. The allowlist travels, but a repo can only request entries, never grant them
1. Add a tracked request file (proposed: `.agent/meta-allowlist.txt`, one `owner/repo` per line, `#` comments) that `setup-memory.sh allowlist` reads as a new layer, below `--allow` / env / `config.json` and above the current-remote default.
2. **Grant rule (security — do not drop):** an entry from the tracked file counts ONLY when it resolves to the same repository as `origin`. Check with `gh api repos/<slug> --jq .id`, which follows GitHub's rename redirect, against the id of `origin`'s slug. The current remote's own slug is always granted. Any other entry is ignored and named in one status line (`allowlist: ignored <slug> — not this repository`).
   - Why: the findings ledger collects records about OTHER repos analysed from this checkout. A committed allowlist that a clone's owner controls could otherwise list your private repos and publish their ledger records to a public metadata branch. This is the same rule as telemetry consent (v15.87.0): a repo-relative file can at most request, never grant.
   - When `gh` is unavailable or fails, tracked-file entries are NOT granted (fail closed), and the status line says so. `config.json` and `--allow` keep working offline, unchanged.
3. Seed this repo's request file with its two slugs. Update `/setup memory`'s disclosure to describe the request/grant split.

### B. meta-sync carries the learning stores
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

### C. /dreaming offers one memory PR
1. After its per-item Accepts, `/dreaming` offers ONE PR carrying only `.supervisor/memory/` and `.claude/agent-memory/` changes it wrote in this run. Paths are staged explicitly (never `git add -A`), and it refuses when those paths already held uncommitted changes it did not author, matching the rules PR.
2. Two gates, as for the rules PR: per-item Accept (content), then a separate Pre-push confirmation (push). It never merges: `gh pr create`, then stop.
3. Amend the documented PR-path rule in `commands/dreaming.md` (today: "carries **only** `.agent/rules/*.json` … never any other store"), and every prompt that restates it. Decide and state whether the memory PR and the rules PR are one branch or two. `CLAUDE.md` stays out of scope: its edits remain a hand PR, and the doc says so.

### D. Committed rehearsal harness + M2 runbook (the testing method, made repeatable)
1. A rehearsal script under `loomwright/scripts/` that, given a checkout, builds a scratch clone and a local bare remote and runs the full migration and drill against them. Nothing reaches the real remote. It copies `config.json` (the allowlist) by default and can run without it (`--no-config`). It runs:
   - `init` → `push` → verify: every managed path present, blob-identical, nothing extra, file types as declared;
   - a second checkout: `git pull` removes the copies, `meta-sync pull` restores them byte-identical;
   - the corrected rollback (#361's PR body) after a post-migration edit, add and delete: all kept, `.gitignore` back to the pre-migration content;
   - the twin reader verifying the same contract count after a round trip.

   It prints one PASS/FAIL line per check, exits non-zero on any FAIL, and cleans up after itself.
2. Its self-test proves each check can go red (mutants: a dropped file, a changed blob, the runbook's old rollback order, a contract without provenance).
3. **CI sees run history again (M1 Verify follow-up, owner 2026-10-03).** Since M1, CI's checkout has no
   `.supervisor/jobs/done/`, so `loomwright/sdk-spike/test/digest-lanes.test.sh`'s optional corpus sweep prints
   `SKIP` (before M1 it swept 132 real briefs). Add a CI step that runs `meta-sync.sh pull` before the suite.
   Read-only: CI never pushes, and a failed pull is reported and leaves the suite as today. The PR edits a workflow
   file, so `claude-review` skips itself on it; the owner reviews that PR by hand.
4. Fix M1's Rollback section to the corrected recipe (the runbook's own recipe silently loses post-migration edits — drill evidence 2026-10-03). Write `operator-run/M2-carry-learning-stores.md`, with the same shape as M1: backup → rehearsal (this script) → real push → verify → consent recorded. Pause for the owner at each step.

## Stays local (non-goals — decided 2026-10-03, owner: "session-level things we can ignore")
- Session traces: `.supervisor/logs/` (683 files, 13 MB, 35 with home paths, prompt traces), `state.md`, `.current-session*`, `history/`. Their durable output (worker summaries, ledger lines, lessons, memory) travels instead. Honest cost: a second machine's `/dreaming` reflects only on that machine's own logs.
- Per-run machinery: `autonomous/`, `drain-rounds/`, `review-dispatch/`, `postmortem-dispatch/`, `guard/`, `jobs/pending`, `jobs/in-progress`, `jobs/context-digests`, the automate sidecars (`*.config-backup.json`, `*.merge-watch*`, `*.trail-staged`), the nudge markers.
- Regenerated views: `insights/`, `floor/`, `handoff/`, `heal-signal/`.
- Per-machine settings: `curation-state.json` (its consumed-log ids exist only on the machine that has those logs), `notify-config.json` (webhook settings, may hold secrets), `scratch/`, `salvage/`, `worktrees/`.
- **Separate follow-ups, not in this item:** writing orientation notes (`.agent/orientation/` holds only its README); seeding agent memory for launch-pad, product-owner and qa-strategist (6 agents declare `memory: project`, only 3 have stores).

## Acceptance criteria
- **A1** Given a fresh clone with no `.supervisor/config.json` and the seeded request file, when `meta-sync.sh pull` then a `push` that adds a ledger line and edits a file citing the old slug runs, then the push succeeds, because the old slug resolves to this repo's id.
- **A2** Given a request file listing a slug that resolves to a DIFFERENT repository, when the allowlist is resolved, then that slug is not granted, it is named in the status line, and a ledger record under it is refused by the scrub. The test fails when the id comparison is removed (mutant).
- **A3** Given `gh` is unavailable, when the allowlist is resolved, then tracked-file entries are not granted, `config.json` entries still are, and the status line says why.
- **B1** Given a contract whose provenance line is missing on either side, when `push` or `pull` runs, then it refuses as a whole, names the contract, and changes neither side. The leg goes red when the pair check is removed.
- **B2** Given both sides appended to `.provenance.jsonl` since the meta-base, when `push` runs, then it reports `conflict` for that file and writes nothing. No line-union.
- **B3** Given a round trip into a fresh clone, then `read-system-contract.sh` verifies the same contracts as the source, and worker summaries, proposals, dismissed ledgers and eval files are byte-identical.
- **B4** Given an injected home path or token in a `.jsonl` file and in a `.dismissed-decisions` file, when `push` runs, then the scrub refuses it (exit 2) and nothing is pushed.
- **B5** Given no recorded consent, when `push` would add part-B paths, then it asks (or, non-interactively, skips and names them), and run history still syncs.
- **C1** Given an accepted memory change and no Pre-push confirmation, then no branch is created and nothing is pushed. Given both gates, then the PR carries only `.supervisor/memory/` and `.claude/agent-memory/` paths, and `/dreaming` never merges it.
- **D1** The rehearsal script passes on this repo with config and with `--no-config` + the request file. Its self-test shows each check going red under its mutant, including the old rollback order losing a post-migration edit.
- **D3** On `main`'s CI after this lands, the corpus sweep reports `parseBrief threw on …/N` (or its NOTE) instead of `SKIP`, and the self-test count of real skips is back to the pre-M1 one (the Linux-host Darwin cases only).
- **D2** M1's Rollback section is the corrected recipe. M2's runbook names only commands and flags that exist in the shipped scripts' `--help`.
- `bash scripts/ci-local.sh` is green. Bump with a `changelog.d/` fragment + `scripts/bump-version.sh` as the last commit, never by hand.

## Provenance
Owner direction, 2026-10-03, session cc4eaee3 (after M1): carry everything that makes the plugin perform best on the metadata branch; ignore session-level state. Same session: test it the way M1 was tested, step by step. Store inventory and counts were verified in the primary checkout on 2026-10-03, after M1 step 7. The allowlist failure (218 hits without `config.json`) and the rollback defect come from the M1 rehearsal and drill the same day. The draft prompt the owner supplied was reviewed first; its counts held, and its design gaps (allowlist grant rule, curation-state, new file types, chain conflicts, consent, the rules-only PR rule) are resolved above.

## Status: pending
