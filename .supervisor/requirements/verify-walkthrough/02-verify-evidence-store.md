# 02 — Evidence store: append-only `evidence.jsonl`, derived summary, validator

## Problem
The QA lane's accounting layer is what stalled it (memory `qa-l1-validated-on-sports-management`):
`coverage.json` was agent-written and reported a `failed` scope as `completed`; per-scope result files had no
schema (key counts 8–19, 5 of 16 without `status`); `.qa-summary.md` was overwritten per scope so no campaign
report existed. D5 already fixed the same class for Supervisor state ("one writer, derived from the append-only
log"). `/verify`'s "add everything to the result summary" must be built on that rule from day one or it will
lie the same way.

## Goal
Every fact `/verify` learns is one appended JSONL line at the moment it is learned; every human-readable
summary is derived from those lines by a script; nothing is ever rewritten.

## Scope
1. **Layout — `.supervisor/verify/<run_id>/`** (gitignored via the existing `.supervisor/` ignore):
   `evidence.jsonl` (append-only), `artifacts/<ac_id>/` (Playwright screenshots, traces, response bodies),
   `summary.md` (DERIVED — regenerated on every append, never hand-edited; a header line says so),
   `run.md` (item 07; single-ticket runs still write it with a one-item queue).
2. **Schema — `RESULT_SCHEMAS.md` §`VERIFY_EVIDENCE`**, `schema_version: 1`. One record shape with `event`
   discriminator: `run_start` (ticket path, ticket kind `requirement|brief`, branch, head sha, base sha,
   env contract hash), `env` (`non_prod_assert` result, start/health outcome, seed/reset outcome),
   `auth` (`authenticated|anonymous|needs_auth|expired`), `ac` (per acceptance criterion: `ac_id`, the AC text
   verbatim, `scope: ticket|impact`, `verdict: PASS|FAIL|BLOCKED|NOT_VERIFIABLE`, `classification`
   for FAIL/BLOCKED reusing qa-executor's `REAL_BUG|DISCOVERY_GAP|ENVIRONMENT_ISSUE`, `steps` (the Playwright
   actions taken), `artifacts` (relative paths), `reason` mandatory for every non-PASS), `issue` (free-form
   finding not tied to an AC — a 500 seen in passing), `pause` / `resume` (reason), `run_end` (counts BY
   DERIVATION ONLY — see §4). Frozen example values per the `check-doc-currency.sh` convention.
3. **`scripts/verify-helpers.sh`** — `evidence-append <run_dir> <json>` (validates the line against §2 BEFORE
   appending; a malformed line is refused with exit 1 and written to `<run_dir>/rejected.jsonl` so the fact
   is not lost; `O_APPEND` single write, never read-modify-write), `summary-build <run_dir>` (derives
   `summary.md`: per-AC table, verdict counts, issues, pauses, artifacts index — computed from the lines,
   with a `derived_from: N lines, sha256 <hash>` trailer), `run-id` (`verify-<UTC ts>-<slug>`).
4. **Counts are never written, only derived.** `run_end` carries **no** totals; `summary-build` computes
   them. A `run_end` line that includes a `counts` key is rejected by the validator.
5. **`scripts/validate-verify-evidence.py`** — sibling of `validate-qa-result.py`: validates one line or a
   whole file; non-PASS without `reason` is invalid; unknown `verdict` invalid; `run_end.counts` invalid.
6. **`scripts/test-verify-evidence.sh`** — round-trip fixture; rejected line lands in `rejected.jsonl`;
   `summary-build` on a file with one FAIL and one PASS yields counts 1/1; **mutation control:** hand-edit
   `summary.md` to claim 2/0, re-run `summary-build`, it must be overwritten back to 1/1; delete the FAIL line
   and the summary must change — a summary that survives its evidence changing is the bug this item exists to prevent.

## Non-goals
No Playwright, no ticket parsing, no queue (07), no drafts (05). No `state.md` write. No new hook.

## Acceptance criteria
- `evidence-append` refuses a line missing `reason` on a `FAIL` verdict (exit 1, line in `rejected.jsonl`,
  `evidence.jsonl` byte-unchanged).
- `summary.md` is regenerated from the lines on every append; a manual edit does not survive the next append.
- `run_end` with a `counts` key is rejected; counts in `summary.md` equal the line-derived counts on a fixture
  of 5 ACs (2 PASS / 1 FAIL / 1 BLOCKED / 1 NOT_VERIFIABLE).
- Appending is a single write per line (`strace`/`dtruss` not required — the helper contains no read of
  `evidence.jsonl` before its write; assert by grep on the helper).
- Schema + validator + doc-currency green; `test-emit-block-parses.sh` / result-validator fixtures extended if
  the parser registry requires it.

## Outcomes Rubric
- One writer per fact, append-only, validated before append
- Summary derived, never authored; mutation control proves it
- Totals impossible to write, only to derive
- Non-PASS always carries a reason
- Schema documented with frozen examples

## Status: pending

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-09-14T10:15:32Z
- **Brief:** .supervisor/jobs/done/2026-09-14-verify-evidence-store.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/222
