# Task Plan — verify-env-contract

Source brief: `.supervisor/jobs/pending/2026-09-14-verify-env-contract.md` (AC1–AC10, Subtask Contracts, Implementation notes — authoritative; this plan confirms the decomposition, orders the work, and records what the brief omits. It does not restate the criteria). NOTE: the spawn prompt cited `in-progress/`; the brief is still in `pending/` at plan time — the Supervisor moves it at Phase 3 start.
Persistence: file fallback (no `.beads`). Base: `main` @ 504ff63 (c30a1db + the ledger `chore(postmortem)` commit; v15.72.0 live in both manifests, verified). Planned 2026-09-14.

## EPIC: verify-env-contract
Ship the committed `.agent/verify.json` contract: `## VERIFY_ENV` schema, fail-SAFE `read-verify.sh`, propose-only `--confirm`-gated `propose-verify.sh` (never guesses `non_prod_assert`), `verify-env.sh` executor gated on `assert-non-prod` in the same invocation, `test-verify-seam.sh` with mutation control; release v15.73.0.

### Decomposition decision
**CONFIRMED: 2 sequential subtasks, split reason `context-bound`, contracts unchanged.** Verified against `skills/supervisor-readiness/SKILL.md` §"Decomposition Threshold" (reason 2: > 800 changed lines). The four precedent files the brief says to copy (`read-product.sh`, `propose-product.sh`, `test-read-product.sh`, `test-propose-product.sh`) total **1,837 lines on disk** (measured), and this item adds a fourth script (the executor) on top — one worker would exceed its turn budget before emitting a result block (memory: subagents hit turn limit). Unlike items 02/03 of the prior queue (deviated to one task; ~few hundred lines), the bound is genuinely crossed here. The shared `test-verify-seam.sh` lane is legal because Subtask 2 is downstream in the `requires` DAG. No paired review subtask (Review Gate Policy).

Verified provides tokens (all 0-hit today, all match their file's convention): `## VERIFY_ENV` (RESULT_SCHEMAS is all-H2), `propose-verify.sh` in AGENT_GUIDELINES.md, `verify-env.sh` in CHANGELOG.md, `== (AC3) assert-non-prod` (file does not exist yet; Subtask 1 is told not to emit it). `verify-provides.sh` matches `symbol` by literal `grep -nE` over the whole file — so Subtask 2's CHANGELOG token is NOT self-satisfied by Subtask 1's RESULT_SCHEMAS prose (different file).

## TASK 1 — schema + reader + bootstrap + seam test  (AC1, AC2, AC5, AC6, AC7, AC8)  [blocked by: nothing]
Skills: `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md`. Lanes/provides: brief Subtask 1 contract verbatim.
Gate: deterministic `outputs_verified` (5 provides) + `bash loomwright/scripts/test-verify-seam.sh` + `bash scripts/check-doc-currency.sh` + `bash scripts/check-vendor-coupling.sh`.

- [ ] `[TO BE CREATED]` `loomwright/scripts/read-verify.sh` — per brief notes. Presence of the 4 nullable-required keys via jq `has()`, never `//`. Never executes any contract string. Zero vendor tokens.
- [ ] `[TO BE CREATED]` `loomwright/scripts/propose-verify.sh` — per brief notes, PLUS what the brief omits: **inherit `propose-product.sh`'s non-primary-checkout guard** (top-level `.git` is a FILE ⇒ refuse, exit 3, propose-product.sh ~line 142–147). Reason: the Supervisor may run the worker from a worktree; dropping the guard silently lets a `--confirm` write land in a linked worktree and vanish on `git worktree remove`. Exit codes mirror the precedent: 0 ok/dry-run · 1 refused (incl. missing `--non-prod`) · 2 shape invalid · 3 non-primary checkout.
- [ ] `loomwright/docs/RESULT_SCHEMAS.md` (verified: `## PRODUCT_CONTEXT` at line 2326, `## Validation Location` at 2414, exception blockquote at line 6) — insert `## VERIFY_ENV` between them; extend the line-6 blockquote to name `VERIFY_ENV`. Include the TRUST SURFACE paragraph and the sibling-locate contract (executor finds the reader via its own `dirname`, see Task 2).
- [ ] `AGENT_GUIDELINES.md` §"Sole-writer confirm gates" (verified: "seven sole writers" line 170, "Six of the seven" + "is the seventh" line 186) — add row + bump prose to eight. Then `grep -n "seven" AGENT_GUIDELINES.md` and confirm only unrelated hits remain.
- [ ] `[TO BE CREATED]` `loomwright/scripts/test-verify-seam.sh` — per brief notes, PLUS: **every `--confirm` fixture is `mktemp -d` + `git init`** (the guard above needs a `.git` DIRECTORY for the write to actually happen; `test-propose-product.sh` does this 6×), add the precedent's case (c): `cksum` this repo's real `.agent/` before/after the whole suite ⇒ identical, and `.agent/verify.json` never appears in this repo. **AC5 grep shape:** key on the literal `verify.json` with `mv`, over `loomwright/scripts/*.sh` EXCLUDING `test-*.sh` (the suite itself contains the string) — do NOT key on bare `verify` (`verify-provides.sh` would false-hit). Capture grep output to a variable, then test (never `| grep -q` under pipefail). Trailing anchor comment `# --- executor cases (Subtask 2 appends below this line) ---` before summary/exit. Do not emit `== (AC3) assert-non-prod`.
- [ ] Run `bash loomwright/scripts/test-verify-seam.sh`, `bash scripts/check-doc-currency.sh`, `bash scripts/check-vendor-coupling.sh`. Commit; do NOT stage `.supervisor/postmortem/results.jsonl`.

## TASK 2 — executor + executor cases + release  (AC3, AC4, AC9, AC10)  [blocked by: TASK 1 — requires `read-verify.sh`, `propose-verify.sh`, `test-verify-seam.sh`, `## VERIFY_ENV`]
Skills: `skills/quality-checklist/SKILL.md`, `skills/error-handling/SKILL.md`. Lanes/provides: brief Subtask 2 contract verbatim.
Gate: deterministic `outputs_verified` (3 provides; consumer re-runs them on disk via `verify-provides.sh`) + FULL suite loop + AC10 gate set.

- [ ] `[TO BE CREATED]` `loomwright/scripts/verify-env.sh` — per brief notes. **Locate the reader as a sibling**: `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; "$SCRIPT_DIR/read-verify.sh"` (pattern: `build-handoff.sh` line 75) — NEVER `${CLAUDE_PLUGIN_ROOT}` (core script; vendor-coupling ratchet, AC10). `assert-non-prod` runs first in every subcommand, same process; `non_prod_not_asserted` before any `bash -c`. Health poll: `while`/`sleep 1`/counter — no `timeout` (macOS). `curl` invoked by name so the test can PATH-stub it.
- [ ] `loomwright/scripts/test-verify-seam.sh` — append AFTER the anchor only; the AC3 block headed exactly `echo "== (AC3) assert-non-prod =="`. AC4 needs a free port: pick via a small `python3 -c` socket bind or probe a high range; `ready_timeout_s: 2` for the never-2xx arm; `stop` touches a marker ⇒ assert marker exists. AC9: `start` string touches a marker under a failing `non_prod_assert` ⇒ marker absent. Re-run the FULL suite — Task 1's cases + AC8 mutant must still fail-when-mutated.
- [ ] Release: read the LIVE version at execution time (15.72.0 today ⇒ 15.73.0 if unchanged) in `loomwright/.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json`, `vX.Y.Z` in each `description` in place. ONE `**v15.73.0 — …:**` paragraph after the historical-entries blockquote in `CHANGELOG.md` ending `Counts unchanged: 14 agents, 23 commands, 41 skills, 36 hooks.` (verified as the current entry's exact phrasing). Do NOT touch README.md / CLAUDE.md.
- [ ] `grep -rn "15\.72\.0" --include=*.json --include=*.md . | grep -v CHANGELOG | grep -vE "^\./(\.supervisor|\.claude)"` ⇒ empty.
- [ ] `bash scripts/check-doc-currency.sh && bash scripts/check-vendor-coupling.sh`; then `for t in scripts/test-*.sh loomwright/scripts/test-*.sh; do bash "$t" || echo "RED: $t"; done` — every suite, no early exit. Commit.

## Sequence
```
TASK 1 (schema + reader + bootstrap + seam test) ──→ TASK 2 (executor + cases + release)
```
Each task gated by its own `outputs_verified` + tests/lint; FINALIZE then Phase 4.5 integrated review once over the merged branch. No per-task reviewer.

## Risks (delta over the brief's table)
| Risk | Mitigation |
|---|---|
| Worker drops the non-primary-checkout guard because the brief's notes do not name it, then `--confirm` from a worktree writes a store that vanishes | Task 1 bullet: inherit the guard (exit 3); fixtures `git init`; case (c) hashes the real `.agent/` |
| AC5 sole-writer grep false-hits on the test file or on `verify-provides.sh` | grep `verify.json` + `mv`, exclude `test-*.sh`, capture-then-test |
| `verify-env.sh` reaches the reader via `${CLAUDE_PLUGIN_ROOT}` ⇒ vendor-coupling ratchet red (AC10) | sibling `dirname`/`BASH_SOURCE` locate, precedent `build-handoff.sh` |
| AC4 port collision on CI | choose a free port at test time; never hard-code 8000 |
| Brief path drift (`pending/` vs `in-progress/`) confuses the worker's context read | Supervisor moves it at Phase 3; workers read whichever exists — record the resolved path in the WORKER_RESULT |
