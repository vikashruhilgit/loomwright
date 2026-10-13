# af36-remainder/03 — meta-sync carries the learning stores (with consent before first publish)

## Status: pending

## Split from
`automate-followups/36-s3-engine-fixes.md` Part C §B (originally `meta-sync-followups/05` §B), split 2026-10-12
per that file's Re-scope section. Scope and acceptance text below is carried VERBATIM; only Depends on / Touches /
Validation are rewritten for today's tree (main 3e354b5). **Security-sensitive** — human merge only. Owner rule from
the Re-scope: ship B5 consent in the SAME PR as the B1 stores, never after; line-union must never touch
`.provenance.jsonl`.

## Depends on
02

## Touches
loomwright/scripts/meta-sync.sh
loomwright/scripts/test-meta-sync.sh
loomwright/scripts/setup-memory.sh
loomwright/scripts/test-setup-memory.sh
loomwright/commands/setup.md
loomwright/skills/setup/SKILL.md
loomwright/skills/automate-loop/branch-mode.md
loomwright/docs/ARCHITECTURE_CONTRACTS.md
changelog.d/af36-03-meta-sync-learning-stores.md

## Problem
After M1, run history travels on `loomwright-meta`, and the memory stores (`.supervisor/memory/`,
`.claude/agent-memory/`, `.agent/`, `CLAUDE.md`) travel on `main`. Several stores the agents read back to make better
decisions travel nowhere: they live on one machine, and a second machine, a fresh clone or a lost disk starts without
them. Verified 2026-10-03 in the primary checkout:

| Store | Size | Written by | Read by (what it improves) |
|---|---|---|---|
| `.supervisor/twin/contracts/*.md` + `.supervisor/twin/.provenance.jsonl` | 38 files + 69 lines | Phase 4.5 twin builder via `write-system-contract.sh` | `read-system-contract.sh`, then Launch Pad (advisory invariants in briefs), rubric-grader, self-heal-advisory, session-resume, `/dreaming`, `build-insights.sh`, `/obsidian` |
| `.supervisor/worker-summaries/*.md` | 134 | the worker (`agents/worker.md`), checked by `validate-worker-result.py` | `/dreaming` (its main distillation input), the Floor's churn rules |
| `.supervisor/agent-memory-proposals/*.md` | 1 | code-reviewer (§ "To propose") | `/dreaming` (agent-memory review queue) |
| `.supervisor/automate/<run_id>.dismissed-decisions` | 2 ledgers (TSV: draft, decision, ts) | `automate-dismissed.sh` | `/automate` — without it a run continued elsewhere re-asks decided findings |
| `.supervisor/eval/results.jsonl`, `brain-baseline.jsonl` | 2 | `run-eval.sh`, `brain-baseline-eval.sh` | `/insights`, release-over-release eval trend |

Scrub exposure today: 0 of 38 contracts, 0 of 69 provenance lines and 0 of 134 worker summaries contain a home path;
0 worker summaries contain an e-mail address.

**Already done (2026-10-12 Re-scope):** `.supervisor/automate/?*.dismissed-decisions` is already in `is_managed`
(pa/05 D9, e8b213d) — but with the default 3-way rule (both changed ⇒ conflict), not the line-union rule Scope 3
asks for. Scope 1 therefore adds the other six; Scope 3's dismissed-decisions rule still applies.

## Scope (verbatim from af/36 Part C §B)
1. Extend the managed set with:
   - `.supervisor/twin/contracts/*.md`
   - `.supervisor/twin/.provenance.jsonl`
   - `.supervisor/worker-summaries/*.md`
   - `.supervisor/agent-memory-proposals/*.md`
   - `.supervisor/automate/*.dismissed-decisions` (already managed — see above)
   - `.supervisor/eval/results.jsonl`, `.supervisor/eval/brain-baseline.jsonl`

   Same exclusions as today: nested `.supervisor/` trees, non-canonical paths, symlinks.
2. **Twin pair rule:** a push or pull that would leave any contract without its chain-valid provenance entry on either
   side (branch or local) is refused as a whole. Nothing is half-applied, and every offending contract is named. The
   test: after any push or pull, `read-system-contract.sh` verifies exactly the contracts present.
3. **Merge semantics per file, stated in the header and tested:**
   - `.provenance.jsonl` is a hash chain, so line-union is WRONG for it. When both sides appended since the
     meta-base: refuse with `conflict` and name the file. Never auto-merge. The header gives the manual resolution
     (re-run the twin builder on one side, or `reprovenance-twin-contracts.sh` if that is its documented use — check
     before citing it).
   - `*.dismissed-decisions` is append-only TSV, so line-union is acceptable. Rows are keyed by draft name, and later
     rows win in time order. State that ordering rule and test it.
   - `eval/*.jsonl` is append-only history, so line-union is acceptable, the same as `results.jsonl`.
   - Each `.md` store keeps today's per-file 3-way rules.
4. **Scrub covers the new file types:** the prose rules (home path, e-mail, tokens, forge slug, deny file) run over
   the `.jsonl` files and the extensionless ledgers too. Add a test leg per new type, each proven red with an injected
   hit.
5. **Consent before first publish:** `loomwright-meta` can be a PUBLIC branch. The first `push` that would add any
   part-B path asks once and records the answer, in the same shape as `/setup memory`'s consent. It names the stores
   and says they hold internal reasoning that the scrub only pattern-checks. Without consent, part-B paths are skipped
   and named, and run history still syncs.
6. Update every doc and check that states the managed set or the ".md + results.jsonl only" rule: the `meta-sync.sh`
   header, M1's Verify step, `test-meta-sync.sh`, and any doc-currency surface (`ARCHITECTURE_CONTRACTS.md`
   §"Metadata branch", `skills/automate-loop/branch-mode.md`).

## Stays local (non-goals — decided 2026-10-03, owner: "session-level things we can ignore")
- Session traces: `.supervisor/logs/`, `state.md`, `.current-session*`, `history/`. Their durable output (worker
  summaries, ledger lines, lessons, memory) travels instead. Honest cost: a second machine's `/dreaming` reflects only
  on that machine's own logs.
- Per-run machinery: `autonomous/`, `drain-rounds/`, `review-dispatch/`, `postmortem-dispatch/`, `guard/`,
  `jobs/pending`, `jobs/in-progress`, `jobs/context-digests`, the automate sidecars (`*.config-backup.json`,
  `*.merge-watch*`, `*.trail-staged`), the nudge markers.
- Regenerated views: `insights/`, `floor/`, `handoff/`, `heal-signal/`.
- Per-machine settings: `curation-state.json`, `notify-config.json` (may hold secrets), `scratch/`, `salvage/`,
  `worktrees/`.
- The allowlist request file (af36-remainder/02) and the `/dreaming` memory PR (af36-remainder/04).

## Acceptance criteria
- **B1** Given a contract whose provenance line is missing on either side, when `push` or `pull` runs, then it
  refuses as a whole, names the contract, and changes neither side. The leg goes red when the pair check is removed.
- **B2** Given both sides appended to `.provenance.jsonl` since the meta-base, when `push` runs, then it reports
  `conflict` for that file and writes nothing. No line-union.
- **B3** Given a round trip into a fresh clone, then `read-system-contract.sh` verifies the same contracts as the
  source, and worker summaries, proposals, dismissed ledgers and eval files are byte-identical.
- **B4** Given an injected home path or token in a `.jsonl` file and in a `.dismissed-decisions` file, when `push`
  runs, then the scrub refuses it (exit 2) and nothing is pushed.
- **B5** Given no recorded consent, when `push` would add part-B paths, then it asks (or, non-interactively, skips and
  names them), and run history still syncs.

## Validation (must pass before merge)
1. Targeted tests (`test-meta-sync.sh`, `test-setup-memory.sh`) + `scripts/check-doc-currency.sh` +
   `loomwright/scripts/test-citation-drift.sh` (+ token-budget and vendor ratchet after `git add`). The full
   `scripts/ci-local.sh` runs at `wave-build` (owner rule 2026-10-12). Report `<passed>/<total>` per suite.
2. Unchanged path: every existing `test-meta-sync.sh` assertion passes with no assertion edited.
3. Running system: B3's round trip run for real into a scratch clone against a throwaway meta branch (always pass
   `--branch`; never push the real `loomwright-meta` from a test). Paste the `read-system-contract.sh` output from
   both sides. If not possible inside the lane, list it under "Not verified".
4. Failures this must catch: B1's removed pair check ⇒ red; B4's injected hits ⇒ red.
5. Rollback: `git revert`. Note in the PR body whether a revert after a real push needs a branch-side cleanup.

## Provenance
Owner direction, 2026-10-03, session cc4eaee3 (after M1): carry everything that makes the plugin perform best on the
metadata branch; ignore session-level state. Store inventory and counts verified in the primary checkout on
2026-10-03.

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-13T12:39:36Z
- **Brief:** .supervisor/jobs/done/2026-10-13-af36-03-meta-sync-learning-stores.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/528
