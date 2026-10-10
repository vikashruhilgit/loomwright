# 00 — Throughput overview (index/policy doc — NOT an implementable item)

## Status: done (index document — nothing to implement; the done stamp keeps `resolve-folder` from enqueuing it)

**Origin:** 2026-10-09, session 9768c6f2. A throughput analysis of `/automate` run `automate-2026-10-08-121222`
(parallel-automate/24, PR vikashruhilgit/loomwright#435: **5 h 12 m** pick→park for ~700 changed lines) was
validated claim-by-claim against the run file, `.supervisor/logs/auto-2026-10-08-123152.jsonl`, the ci-local run
logs and `gh run list`, then red-teamed (`/loomwright:red-team-reviewer`, verdict SHIP_BLOCKED on the original
F1–F7: 2 FATAL, 3 CRITICAL). Every item below is the reshaped version. **Re-check each item's evidence before
starting — `main` moves.**

**Sibling (not duplicate):** `implementation-quality/01` reduces HOW MANY fix cycles happen (11 of #435's 14
findings were reviewer-checklist classes the worker never checks); this queue reduces what each cycle COSTS.
iq/01 runs first.

## Owner decisions (2026-10-09, binding on every item)
- **D1 — pre-push rule stays.** `bash scripts/ci-local.sh` (full) before every push, drain pushes included. No
  "GitHub CI is the full run" exemption. Speed comes from failing early and shrinking the run, never skipping it.
- **D2 — fix-now shows its cost.** The dismissed-findings ask states the estimated cost of fix-now (one fix
  pass + re-drain), derived from this repo's recorded fix-now spans (6 so far: 14 m – 2 h 53 m, median ≈ 66 m);
  the owner still decides per finding (fix-now / follow-up / drop).
- **Reading B stays** (pre-existing, re-affirmed): every validated finding at every severity is fixed;
  batching sub-floor findings into follow-ups is the FORBIDDEN reading A (`skills/review-heal/SKILL.md`
  PINNED SEMANTICS block). Owner framing: "make implementation produce fewer findings", not "defer them".

## Measured baseline (PR #435)
| Where the time went | Wall | Evidence |
|---|---|---|
| pick → `autonomous_start` | 19 m | plan review 12:12:59–12:21:02Z, then ~10 m waiting on the owner (asked 12:21:08Z, next activity 12:31:13Z) — events sit in the session-id log, not the `auto-…` log (item 04 joins them) |
| `/autonomous` → PR, Phase 4.5 PASS (3 iterations) | 1 h 44 m | session log; iteration 3 (~5.5 m incl. a 32 s fix) only re-reviewed a deviation relabel |
| drain #1 → READY | 2 m | 14:15:58Z → 14:17:25Z |
| **post-READY: fix-now pass + re-drain (2 rounds) + park** | **3 h 07 m (60%)** | READY 14:17:25Z → 14:20:07Z owner fix-now on 4 drafts → fix pass 48 m → re-drain 15:08:30Z–16:41:29Z (1 h 33 m) → 17:24:50Z parked |
| full ci-local runs | 9 runs, 639–836 s, ~102 min | ci-slot run logs (shared across sessions — a #438 run sat in the window; attributed by tree key) |
| failed ci-local runs | 4 (≈46 min) | 3× vendor-coupling (+ help golden, citation-drift, stale capabilities.json) · 1× S6 `sleep 0.3` race |
| serial tail per full run | 181 s local · 145 s on CI | 3 `# run-self-tests: serial` tests run alone after the pool (CI: 103+24+18 s) |
| GitHub CI per push | 11 m 31 s – 14 m 51 s × 5 | suite step ~10 min; `ci` on the critical path every push |
| re-drain overran its stop rule | ~33 m | round 1 was sub-floor-eligible; a second round ran |

**Superseded queue (owner decision, 2026-10-09, later the same day):** items 01–09 below and `implementation-quality/01` were merged into ONE requirement / ONE PR — `.supervisor/requirements/implementation-quality/02-iq01-and-throughput-merged.md` (each source kept verbatim as a labelled Part; each source file stamped `parked — superseded by` it). The table below is the history of that merge.

## The queue (run in this order — `.supervisor/iq01-backlog.md` lists them after iq/01)
| Item | Delivers | Est. saving / item |
|---|---|---|
| 01 sub-floor-stop-decision-scripted | `sub_floor_eligible` + terminal decision as a fail-closed script, not prose; fix `sub_floor_fixed` bookkeeping | ~33 m when the prose is misapplied |
| 02 fix-now-cost-at-decision | D2: cost estimate on every dismissed-finding ask, derived from recorded re-drains | owner-chosen; makes the 60% visible |
| 03 check-wait-under-bash-cap | `wait-for-checks.sh` bounded per call ≤ the 600 s Bash cap, total bound kept | latent drain death (not yet hit) |
| 04 phase-timing | per-phase + owner-wait timestamps, `/insights` wall-clock and machine-vs-owner split | measurement for everything else |
| 05 ci-local-early-gates | cheap gates + `early`-marked self-tests first, fail before the pool; `--affected` gets capabilities `--check` | ~35 m on this item |
| 06 remove-serial-tail | serial tests made pool-safe; full run ≤ 540 s (fits the Bash cap) | ~27 m local + ~2.5 m per CI push |
| 07 fixed-sleep-test-races | S6 + every fixed-sleep-then-assert test waits on a condition; guard against new ones | ~11 m per flake |
| 08 ci-suite-shard | GitHub CI suite step as a matrix, required `ci` context preserved | several min per push × pushes |
| 09 vendor-coupling-shift-left | gate prints ready-to-paste reasoned raise row / adapter route; never auto-raises | fewer late ratchet trips |

## Considered and NOT queued (so nobody re-proposes them without new evidence)
- **F2 drain-push exemption** — dropped by D1. A red push in a sub-floor terminal round ESCALATES the drain
  (`review-heal` NEVER-READY-on-red rule). The worker half ("`--affected` while iterating, one full run before
  push") already exists in `agents/worker.md` and changed nothing: all 9 runs were legitimate pre-push runs.
- **F3 batching sub-floor findings** — FORBIDDEN reading A; see Reading B above. Only the decision-scripting half
  survives (item 01).
- **F4 script replacing Context-Keeper writes** — Context-Keeper is the sole state.md writer on the parallel path
  (`ARCHITECTURE_CONTRACTS.md`); `/automate` already writes its run file via `runfile-write` / `progress-append` /
  `current-set`, and the three Context-Keeper spawns cost ~16 s each. `drain-read` / `park` subcommands are a
  low-priority reliability idea — revisit only after `parallel-automate/22` (engine split) lands.
- **F7 sharing findings between Phase 4.5 and `claude-review`** — collapses the two-independent-lens invariant
  (CLAUDE.md "Two review lenses"; `claude-code-review.yml` "do not try to match or converge"). The per-push
  trickle was corroboration (claude-review independently found siblings Phase 4.5 had dismissed). A deterministic
  re-review scope (842cbe7 got "new commit only", 77fc06b/783b00b got whole-PR) is an owner decision not yet
  taken — and a PR editing the review workflow cannot review itself.
- **Raising slot count / jobs** — two concurrent full runs took ~830 s vs ~650 s solo; throughput, not latency.
  Leave `ci-slot.sh`'s default.

## Revisit once item 04 has data
- owner-wait inside the item (the 19-minute pick→`autonomous_start` gap was ~8 m plan review + ~10 m owner wait);
- Phase 4.5 iterations that only re-review a non-code relabel (~5.5 m here);
- subagent `output_tokens`: 89% of message ids in session 33e9ed8c's subagent transcripts carry only the
  stream-start placeholder (no final `stop_reason` line), so TELEMETRY.md's F8 "under-counted when the final line
  is absent" is the common case — a separate follow-up on the output-token source, relevant now that
  `--max-tokens` ceilings go live with the held release.

## Ordering constraints with pending work
- iq/01 first (worker.md, launch-pad, build-insights.sh, RESULT_SCHEMAS.md — item 04 depends on it).
- Item 05 and `automate-followups/34` Part B both edit `scripts/ci-local.sh` — sequential only, never parallel.
- `automate-followups/36` Part C (ci-local under the 600 s limit) should be re-scoped against #438's `--wait` and
  item 06 before it runs.
- Item 04 extends closed enums — land with/after `automate-followups/20` and `/27`.
- Item 09 touches `vendor-coupling-manifest.json`, a merge-conflict hotspot (#410/#412/#417) — never in a
  parallel wave with another manifest editor.
