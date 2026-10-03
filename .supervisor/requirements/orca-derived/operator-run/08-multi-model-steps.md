# 08 — Different models for different steps (planning/eval item — blocked on 07's measurement; lives in `operator-run/` so `/automate`'s non-recursive folder intake never enqueues it)

## The ask
"Use multiple AIs — Claude, Codex, Grok… — for different steps, or compare / analyse / review."

## What is possible, by step class (verified constraints, 2026-09-11)
| Step class | Examples | Non-Claude feasible? | How | What breaks |
|---|---|---|---|---|
| **Read-only judgment** | review vote, plan critique, rubric second opinion, `/propose --domain` research, red-team lens | **Yes, now** | item 07's `lens-run.sh` with `--role review|critique|grade` | nothing — output is advisory JSON |
| **Compare** | two families review the same diff; report agreement/disagreement as a signal | **Yes, now** | two `lens-run.sh` calls + a diff of finding sets | cost ×2 per compared step |
| **Write steps** | worker implementing a subtask, heal fix task | Possible, **blind** | vendor CLI in a worktree | ALL plugin hooks are Claude Code hooks: no `agent_identity`, no lifecycle (01), no `token_ledger`, no SubagentStop validation — the run's ledger goes dark for that step |
| **Orchestration** | Supervisor/Execute Manager | No | — | they ARE Claude Code agents; D2's SDK runner is Claude Agent SDK |

Two honest routes for write steps, both outside this item's execution: (a) **the SDK runner (D1)** —
it composes each spawn's prompt and could call a provider CLI as a tool WITH a dispatch record, so the
ledger stays lit; (b) **Orca orchestration** (`worker-start --agent codex`, dispatch ids, `worker_done`
receipts) — an adapter, external dependency. Neither is chosen here.

## Scope of THIS item (planning + eval, operator-run)
1. Extend 07's `--role` to `critique` (plan-reviewer second opinion on a brief, advisory line in the
   brief's Plan Review block) and `grade` (rubric second opinion, reported beside `rubric_score`, never
   replacing it) — only if 07's review role measured positive.
2. **Compare mode:** `lens-run.sh --compare cursor:gpt-5,claude` → agreement set / disagreement set;
   the disagreement set is the "hard part" and is what gets surfaced, not a merged list.
3. **Eval design (D11):** two arms on the FABLE_PARITY corpus entry that 07 used — same-family second
   voter vs cross-family second voter; comparator = cost, outcome = post-merge defects + review rounds;
   abort rows stay, re-runs are second rows.
4. **Decision record:** which step classes adopt a non-Claude family by default, written to
   `FINAL_STATE_GOAL.md` as a D4 note — never here.

## Non-goals
No non-Claude worker in this item. No "race N implementations" (D3: fan-out is the exception; NOT-doing
list). No model IDs hardcoded in core; provider:model strings live in config/flags only.

## Acceptance criteria
- 07 measured and recorded before any code here starts (`Status` of 07 = done with the eval row cited).
- Compare mode output has three sections (agree / only-A / only-B) with evidence per finding.
- Eval rows recorded per D11; decision written to the goal file.

## Outcomes Rubric
- Step-class matrix kept current with verified constraints
- Compare surfaces disagreement, never a merged ranking
- Eval honest; decision lives in the goal file

## Results (2026-09-20)

**Step 1 — `--role critique`/`grade` extension: NOT done.** Its own AC gated this on "07's review-role
measured positive." Evidence as of this run: `FABLE_PARITY_EVAL.md`'s provider-lens row is n=1,
`ESCALATED` (not `PASS`), unmerged — mechanism-reachable, not outcome-positive, and 07's own note requires
≥2 more isolating runs before any per-layer verdict. Extending to new roles on top of an unproven role
would compound, not reduce, the uncertainty. Decision + citation also recorded in `FINAL_STATE_GOAL.md`'s
new D4 note.

**Step 2 — Compare mode: DONE.** `loomwright/scripts/adapters/providers/lens-compare.sh` + 18-case
`test-lens-compare.sh` (all passing). Composes two `lens-run.sh` calls on the same diff/prompt/commit,
outputs `{compare_status, provider_a, provider_b, agree[], only_a[], only_b[]}` — agreement keyed on exact
(file, line), never severity/text (an agreement signal, not a merge). Adds no new safety surface: every
subprocess is a plain, already-reviewed `lens-run.sh` invocation. Wired into nothing — on-demand only, per
this item's own non-goals ("no new default").

**Step 3 — Eval design (D11): partially executed, honestly.** Same-family arm = the existing provider-lens
row (PR #239, Claude `red-team-reviewer` voter). Cross-family arm = a real, one-off `cursor:gpt-5` lens
call against the IDENTICAL diff (`git diff 2c63cad^1..2c63cad^2`), run manually outside the loop (not via
`--voter-provider`, since the shipped adapter cannot currently produce a real `ok` result at all — see
item 07's "Probe result" update). Row recorded in `FABLE_PARITY_EVAL.md`. Findings: the cross-family lens
caught 2 real, previously-missed defects (the `${CLAUDE_PLUGIN_ROOT}` wiring bug — fixed in this item's own
PR — and the `--commit` fetch-injection gap — recorded, not fixed) that the same-family voter's FAIL did
NOT surface in #239's own review; it also made one confident, unverified "empirically succeeds" claim that
an independent repo audit did not corroborate. n=1; not KEEP/CUT-eligible per D11's own ≥3-requirements
bar. Getting a *real* (non-ad-hoc) cross-family result via `--voter-provider` requires a separate decision
(drop `PROVIDER_HOME_SCRUB` for cursor, and/or pass `-f`/`--trust` by default) that is a security-posture
change, not an eval-config change — explicitly NOT made here.

**Step 4 — Decision record: DONE.** Written to `loomwright/docs/SPIKES/FINAL_STATE_GOAL.md` as a new "D4
note (2026-09-20)" section (this file, not just here, per the AC's own instruction). Summary: no step class
adopts a non-Claude family by default yet; revisit when the review-role layer clears its ≥3-run bar, or
when someone deliberately resolves the isolation-barrier tradeoff for a real cursor-provider default.

**Acceptance criteria — honest status:**
- 07 measured/recorded before this item started: YES (Status=done, PR #239 merged, cited above).
- Compare mode's three-section, evidence-per-finding output: YES (`lens-compare.sh`, tested).
- Eval rows recorded per D11, decision in the goal file: YES, with the cross-family arm's scope limits
  (ad hoc, n=1, not via the shipped wiring) stated plainly rather than glossed over.

**Non-goals held:** no non-Claude worker; no race-N; no model IDs hardcoded in core (`lens-compare.sh`
takes providers as CLI args, same as `lens-run.sh`); no unauthorized default change.

## Status: done (2026-09-20) — see `07-provider-lens.md` §"Post-merge findings" and
`FABLE_PARITY_EVAL.md`'s D11 row for full detail; two follow-up items recorded but NOT queued
(`--commit` fetch-injection validation, FETCH_HEAD leak scrub) — a human decides whether/when to open them.
