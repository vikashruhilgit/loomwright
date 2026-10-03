# 00 — Harness-port overview (index/policy doc — NOT an implementable item)

## Status: done (index document — nothing to implement; this stamp is the ONLY thing `resolve-folder` honours today — item 02 adds `proposed|parked` — so it is what keeps `/automate` from enqueuing this file)

**Origin:** 2026-09-21. Seven generic improvements learned in a repo-local unsupervised-worker harness, ported into
the plugin. The owner's first draft was red-teamed inline (`/red-team-reviewer review these`) against `main @ 05823bf`;
the owner independently re-verified every FATAL/CRITICAL row and produced a corrected draft; that draft was checked
again and six further corrections were folded in. **Every item below is the third revision, and every premise in it
was read from the actual file — re-check the "Verified premises" block of each item before starting, because
`main` moves.**

**Portability rule (binding on every item):** no product, vendor, tool, host, port number or label name from any
consuming repo may appear in plugin text — placeholders only (`<service>`, `<route>`, `<provider>`, `<PORT_ENV>`);
concrete values are read from the host project's `CLAUDE.md` at runtime. Every new field/line/section is OPTIONAL
and, when absent, behaviour is **byte-identical** — the convention is `Source requirement` in
`loomwright/agents/launch-pad.md` Phase 5 step 3a, INCLUDING its wording "do NOT emit an empty or 'none' placeholder".

**Authority above this queue:** `loomwright/docs/SPIKES/FINAL_STATE_GOAL.md` (D1–D11), `NORTH_STAR_DIRECTION.md`
§"Explicit NOs", CLAUDE.md §"Failure-Mode Invariants" (bimodal fail-CLOSED / fail-SAFE; sole merge executor; two
review lenses). Nothing here adds an agent (count stays 14), adds a merge path, changes `heal_decision`, or
renumbers an existing criterion or phase.

## The seven items (+ one parked design)
| Item | Delivers | Owner's original # |
|---|---|---|
| 01 worker-rules | ONE worker.md edit carrying the three worker-side rules (honest limits, no self-promotion, shared services read-only) + the WORKER_RESULT `not_verified` schema line + validator shape check + the single prompt-budget raise | 2 / 4 / 5 (worker halves) |
| 02 not-ready-stamp | `automate-helpers.sh` `is_not_ready()` — `## Status: proposed|parked` is skipped by `resolve-folder` / `resolve-backlog-dir`; `is_done` and `resume-glob` untouched | 4 |
| 03 cited-line-premise | Launch Pad Phase 3 + Phase 1.5 signal (d): re-verify every cited `path:line` against `origin/$BASE_BRANCH`, advisory, with an honest age column | 1 |
| 04 not-verified-transport | the full route WORKER_RESULT → Context-Keeper → state.md → PR body AND done brief → `verify-run.sh acs` as `scope: impact` rows | 2 (transport half) |
| 05 dismissed-findings | itemised `dismissed[]` + one marker-tagged PR comment the drain skips and `/pr-postmortem` reads | 3 |
| 06 shared-local-services | optional `## Shared local services` in host CLAUDE.md → brief `## Environment` → spawn paste (bounded); also fixes the pre-existing `Base commit` template drift | 5 |
| 07 ci-trust-probe | live per-red-required-check infra probe → `checks_untrusted[]`, terminal `ESCALATED`/`ci_untrusted`, never READY | 6 (rewritten) |
| `proposed/external-review-lens-required.md` | DESIGN ONLY — fail-SAFE → fail-CLOSED policy inversion of the already-shipped provider seam on high-risk diffs | 7 |

## Order
**01 → 04 → 06** (04 and 06 exercise worker text 01 adds; 01 also owns the only `worker` budget raise).
**02 first among the rest** — it is what makes a `proposed`/`parked` stamp mean anything.
**03** is independent. **05 → 07** (both edit `skills/review-heal/SKILL.md` and `docs/RESULT_SCHEMAS.md` §REVIEW_HEAL_RESULT).
Run order: 01, 02, 03, 04, 05, 06, 07. Each item is one PR against `main`; pull `main` after each merge (the engine
already does this — no stacking).

## Decisions taken (owner, 2026-09-21 — "go")
| # | Decision | Why |
|---|---|---|
| H1 | **One worker.md PR, one budget raise.** Items 2/4/5's worker-side text merge into item 01. | `bash scripts/check-token-budget.sh` → `worker 5876/5905, 29 headroom` (≈116 bytes). Three PRs each breach alone; whichever lands first eats the raise and the other two re-breach. `raise_rule` in `loomwright/docs/prompt-token-budgets.json` requires the JSON + the `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" mirror row in the SAME PR. |
| H2 | **A stamp is only a skip once the intake honours it.** `is_not_ready()` is a NEW predicate used by `resolve_folder` / `resolve_backlog_dir` ONLY — never folded into `is_done`, which `resume-glob` shares (run files, different vocabulary). The `proposed/` subfolder stays the other skip (it works today because `"$dir"/*.md` does not recurse). Item 7 goes in `proposed/` because item 02 has not landed. | `automate-helpers.sh` `is_done()` matches only `^## Status:\s*done(_with_escalation)?\b`; memory `orca-derived-queue` recorded the same fact on 2026-09-12. |
| H3 | **CI-trust is a live probe, fail-CLOSED — never a dated note, never a READY exemption.** A red required check whose run shows `steps_count == 0` / no runner / an account-billing-quota annotation is `untrusted_infra`: listed, surfaced, and the drain terminates `ESCALATED` with `termination_reason: ci_untrusted`. It is NEVER excluded from READY-blocking and green checks are never re-classified. | The owner's own machine notes record the note going wrong twice within hours ("Actions worked an hour ago is not evidence"); a billing block means the verdict is UNKNOWN, not green. Excluding it from READY would invert review-heal §U2's fail-CLOSED posture and fire the "ready to merge" notification on a PR whose required check never ran. |
| H4 | **Consumers are named with their transport.** `not_verified` travels WORKER_RESULT → Execute Manager → Context-Keeper `record_worker_result` → `state.md ## Worker Results` → FINALIZE → PR body + done brief; `/verify` reads the BRIEF (it resolves tickets by PATH, never a PR body). `dismissed[]` reaches `/pr-postmortem` ONLY as a PR comment (the gather script reads `gh pr view` and nothing else). | Memory `verify-consumer-contract-before-for-free`; EXECUTE_RESULT carries no per-worker optional fields (RESULT_SCHEMAS §EXECUTE_RESULT `out_of_lane` note). |
| H5 | **Advisory means it cannot change the outcome by any route — including budget contention and the Plan Reviewer matrix.** Phase 1.5 signal (d) runs LAST, in ONE Bash call, and is skipped silently when the ≤6-call budget has no room; a STALE row is a LOW Criterion-1 finding and the text states it never moves PASS → NEEDS_HUMAN on its own. | `preflight-sync/SKILL.md` Bounded budget: hitting the cap ⇒ `unverified`; `plan-reviewer.md` Decision Matrix: MEDIUM/LOW + ambiguous ⇒ NEEDS_HUMAN ⇒ save disabled ⇒ unattended runs fail closed. |
| H6 | **Honest measurements.** `git log -1 --format=%cr origin/$BASE` is TIP age, not fetch age (verified: FETCH_HEAD mtime 14:10 today vs `%cr` "5 hours ago"). Launch Pad adds no `git fetch` (it makes no network calls today); the column is labelled `tip age (lower bound on staleness)` and fetch age is read portably with `find .git/FETCH_HEAD -mmin +N` (BSD and GNU both have `-mmin`) — never `stat` (memory `stat-flavor-setu-arithmetic-trap`), never `date -d`/`date -j`. | The check exists to catch "a merged commit already changed it"; a false HOLDS against a stale ref is the exact failure it targets. |
| H7 | **`/verify` gets `not_verified` rows as `scope: impact, source: "not_verified"`, not a new `ac_id` shape.** | `verify-walkthrough/SKILL.md` §impact scope: `summary-build` filters the ticket score to `scope: "ticket"` — "the load-bearing invariant of this section". A new id family either inflates the ticket score or needs a third table. |
| H8 | **Name the numeric spawn field `subtask_ordinal`.** | `async-orchestration/SKILL.md` already uses the prose term "Subtask index" for the ids/titles/deps LIST in the spawn contract. |
| H9 | **Item 7's premise is stale — it is a policy inversion, not a new seam.** `scripts/adapters/providers/lens-run.sh` + `provider-{claude,codex,cursor,gemini}.sh` + `--voter-provider` / `.voter_provider` shipped in PR #239 (`.supervisor/requirements/orca-derived/07-provider-lens.md`, `## Status: done`). Its contract is fail-SAFE (`provider_unavailable` ⇒ single Claude voter). The design story must be framed as inverting that for ONE case and must read that file's "Probe result — DEFERRED" / lens-run's SAFETY POSTURE (isolation is DETECTED, not enforced) first. | A design that contradicts a live invariant unknowingly is worse than none. |

## Cross-cutting facts every item must respect (each read on 2026-09-21 at `05823bf`)
- Live budgets (`bash scripts/check-token-budget.sh`, run from repo root): worker 29 headroom · rubric-grader 189 ·
  context-keeper 319 · orchestrator 634 · red-team-reviewer 606 · qa-executor 716 · plan-reviewer 777 ·
  product-owner 776 · review-pr 1737 · qa-strategist 1964 · code-reviewer 2133 · supervisor 2412 ·
  execute-manager 3216 · launch-pad 4566. Any raise: JSON `.agents[<stem>].budget` + `note` justification + the
  mirror row in `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets", same PR. Preloaded skills count against
  their agent (review-heal → review-pr; async-orchestration → execute-manager).
- `result_block_parser.py` / the `validate-*-result.py` family IGNORE unknown keys (parser docstring: "an unknown
  key is ignored by the validators"). An optional field is therefore invisible to the gate unless its shape is
  validated explicitly — precedent `out_of_lane` in `validate-worker-result.py` rules (9), which the file's own
  comment contrasts with the never-validated `memory_candidates`.
- **SubagentStop command-hook block shape (verified 2026-09-21, Claude Code v2.1.278):** a command hook blocks via
  top-level `{"decision":"block","reason":"…"}` or `exit 2`; `{"ok": false}` blocks NOTHING. Any validator change
  in this queue emits the documented shape and its test asserts THAT shape.
- Brief template canonical home is `loomwright/skills/supervisor-readiness/SKILL.md` §"Supervisor-Ready Brief
  Template" (it documents `Source requirement`; it is ALREADY missing `Base commit` — pre-existing drift, fixed in
  item 06). `launch-pad.md` §"Output Format (Complete Example)" mirrors it. Both change together or neither.
- Workers in linked worktrees cannot see `.supervisor/` (gitignored, absent in worktrees). The spawn contract is
  pointers-not-payloads (`async-orchestration/SKILL.md` §"Pointers, not payloads"); a deliberate paste is
  enumerated in `loomwright/docs/POINTER_AUDIT.md` with a justification.
- The detached drain (`dispatch-pr-review.sh` → `review-pr-runner`) is keyed off a PR URL and has NO brief; it
  runs in a sibling worktree where committed files (CLAUDE.md) exist and `.supervisor/` does not. It runs under the
  operator's own `gh` login, so anything it posts is classified HUMAN-authored by review-heal §U3 (surfaced, never
  blocking) unless a marker says otherwise. It already posts via `gh pr comment` (§Step 2 / §U4).
- `/pr-postmortem` input = `scripts/pr-postmortem-gather.sh` = `gh pr view`/`gh api` JSON, nothing else.
  `REVIEW_HEAL_RESULT` is never persisted by `dispatch-pr-review.sh` (the marker holds URL + timestamp).
- `/verify` = `verify-run.sh acs <ticket>`; `ticket_kind` decided by PATH (`.supervisor/requirements/` |
  `.supervisor/jobs/`), ACs = top-level bullets under the first `## Acceptance Criteria` header. Impact scope
  already locates a matching `.supervisor/jobs/done/*.md` brief.
- Full test loop before any push: `loomwright/scripts/test-*.sh` AND root `scripts/test-*.sh` AND
  `scripts/check-vendor-coupling.sh` (memory `run-full-ci-suite-loop-before-push`). A literal
  `${CLAUDE_PLUGIN_ROOT}` or `~/.claude/plugins/cache` in a core COMMENT trips vendor-coupling — reword.
