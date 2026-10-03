# Review Remediation Plan — 2026-07-05 full-repo review of Loomwright v15.1.0

Master overview for the 8 work items in `.supervisor/requirements/review-remediation/`.
Source: 4-agent audit (manifests/docs/roadmap · agents/commands · skills/hooks/schemas · scripts/tests/security), synthesized 2026-07-05.

**This file is the overview only — do NOT feed it to /automate.** The per-item
requirement files live in the `review-remediation/` subfolder, one item per file,
each self-contained (goal, evidence, scope, invariants, acceptance criteria, test plan).

## Execution order & batching

| # | File | Priority | Size | Depends on |
|---|------|----------|------|-----------|
| 01 | 01-command-clarity.md | P0 | M (docs-only) | — |
| 02 | 02-telemetry-core-tests.md | P0 | M (tests-only) | — |
| 03 | 03-doc-hygiene-index-roadmap.md | P0 | S | — |
| 04 | 04-state-resume-validation.md | P0 | S | — |
| 05 | 05-supervisor-prompt-refactor.md | P1 | L | 01 (flag tables land first) |
| 06 | 06-script-test-gaps-and-roadmap-remainders.md | P1 | M | — |
| 07 | 07-tech-stack-skills-spinoff.md | P1/P2 | L | 03 (index parity check exists first) |
| 08 | 08-curation-half-and-counterfactual-eval.md | P2 | XL | 05–07 landed |
| 09 | 09-fable-parity-sdk-spike.md | P2 | XL | 01–05 merged (hard precondition) |
| 10 | 10-design-system-substrate.md | P1 (product bet) | L | Part A: none; Part B: after 05 (edits the same spawn-seam prose 05 relocates); C/D independent. frontend-ui excluded from 07's move list because of this item. |

**Pre-batch: DONE** — the `--cheap` forwarding job landed as v15.2.0 / PR #89 (merged
2026-07-06). Items were REBASELINED against v15.2.0 on 2026-07-06: 01 narrowed (flag
tables now exist; auto-merge conditions deliberately NOT inlined per automate.md's
anti-drift design — remaining core is the decision table + completeness audit), 03
narrowed (only supervisor-readiness row still drifted), 06 narrowed (red-team already
`effort: xhigh`; RED_TEAM_RESULT already documented), 05 gained the hard
agents↔commands supervisor mirror constraint, 09 Part B gated behind an opt-in flag.
Execute items from CURRENT file contents; re-verify evidence lines at execution time.

01–04 are independent → safe to run as one /automate queue (4 items, `--limit 4`).
05 and 07 each change counts/version → run individually via /autonomous, one at a time.
08 and 09 are strategic bets → run through /product-owner + /launch-pad first, not straight
to execution. 09 Part D's eval extends 08's harness — sequence 08 Part A before 09 Part D
if both are active; 09 Parts A–C don't depend on 08.

## Cross-cutting constraints (apply to every item)

- **Doc-currency gate:** any count/version change must update all current-claim surfaces
  in the same change (`scripts/check-doc-currency.sh` is a CI hard gate). Also grep the
  OLD value repo-wide — the gate does not scan Supervisor phase enumerations,
  SKILLS_INDEX version cells, or budget numbers (CLAUDE.md §Doc currency).
- **Bimodal failure invariant:** gates fail CLOSED, emitters fail SAFE / exit 0. Never invert.
- **Single merge executor invariant:** nothing new may execute `gh pr merge --squash`
  (only automate-loop's gate-eval). Run the positive-form grep check after every item.
- **Description anti-rebloat:** plugin.json / marketplace.json descriptions are updated
  in place, never appended.
- **Illustrative example values** (sample JSONL, `e.g. "X.Y.Z"` placeholders) stay frozen —
  do not "fix" them to the current version.
- Versioning: docs-only items (01, 03) = patch bump; behavior/test items (02, 04, 06) =
  minor bump; refactor items (05, 07) = minor bump with schema_version untouched.

## Findings dismissed during verification (do NOT re-open)

- "57 skills is wrong (58)" — false; the 58th entry is `SKILL_TEMPLATE.md`, a file.
- "9 hooks lack `|| true` and can block agents" — overstated; every hook script terminates
  with unconditional `exit 0` (verified). Item 06 adds `|| true` as optional belt-and-suspenders only.
- Hook count 21 — verified correct.
