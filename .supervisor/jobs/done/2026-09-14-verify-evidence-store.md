# Supervisor Job: Verify evidence store — append-only `evidence.jsonl`, `VERIFY_EVIDENCE` schema, line validator, derived `summary.md`, seam test with mutation controls

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — version-free by design; plugin.json is 15.73.1)
- **Git:** dirty (1 file — `.supervisor/postmortem/results.jsonl`, engine-native ledger line for PR #220 left uncommitted by the 2026-09-14 `/automate` tick; precedent commit `504ff63` folded the same class into a `chore(postmortem)` commit on `main`), branch: main @ origin/main
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 2 (dirty ledger above; 3 stale briefs in `.supervisor/jobs/in-progress/` from 2026-09-03..05 — unrelated, do not touch)
- **Source requirement:** .supervisor/requirements/verify-walkthrough/02-verify-evidence-store.md
- **Base commit:** a2891df56d9030121294f68a3127f3d2d7144f9a

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2 + `jq` for the helper (the `automate-helpers.sh` / `emit-*.sh` append-only JSONL precedent), python3 stdlib for the validator (the six existing `validate-*.py` siblings). No new runtime, no new dependency. |
| 2 | Dependency Availability | GO | `jq` and `python3` are both already hard requirements of sibling scripts (`validate-qa-result.py`, `read-verify.sh`). `sha256sum`/`shasum` for the derived trailer — use `shasum -a 256` with a `sha256sum` fallback (both present on macOS + ubuntu CI). |
| 3 | Architecture Fit | GO | Applies owner decision D5 ("one writer, derived from the append-only log") and V5 (`.supervisor/verify/<run_id>/` own store) verbatim. Same shape as the `.supervisor/logs/*.jsonl` + `build-state.sh` projector pair already in the plugin. Bimodal failure philosophy preserved: the validator/append gate fails CLOSED (a line it cannot validate is never appended), the derived summary is advisory output. |
| 4 | Scope vs Supervisor Capability | GO (split) | 4 modify + 3 create = 7 files, but validator (~250) + helper (~300) + seam test (~350) + schema section (~150) exceed the 800-changed-line `context-bound` bound. Split reason `context-bound` → 2 sequential subtasks: the contract (schema + validator) first, the consumer (helper + derivation + mutation controls) second. |
| 5 | Hard Blockers | GO | No migrations, no credentials (V8), no new agent (V1), no hook (requirement Non-goals), no `state.md` write. The store is under `.supervisor/` which `.gitignore:78` (`.supervisor/*`) already excludes. |

**Overall Verdict:** GO

## Task
**Goal:** Ship the `/verify` evidence store — a `RESULT_SCHEMAS.md` §VERIFY_EVIDENCE line schema (`schema_version: 1`, `event`-discriminated), a `validate-verify-evidence.py` line/file validator whose exit status is the gate, a `verify-helpers.sh` with `evidence-append` (validate-then-single-`O_APPEND`-write, refused lines land in `rejected.jsonl`), `summary-build` (derives `summary.md` from the lines with a `derived_from` trailer) and `run-id`, and a `test-verify-evidence.sh` whose three mutation controls (a, b, c) prove the summary cannot survive its evidence changing and the appender never reads — so items 03–07 write facts once and never author a roll-up.

**Problem Statement:**
The QA lane's accounting layer is what stalled it (memory `qa-l1-validated-on-sports-management`): `coverage.json` was agent-written and reported a `failed` scope as `completed`; per-scope result files had no schema; `.qa-summary.md` was overwritten per scope so no campaign report existed. Nothing today gives `/verify` (items 03–07) a place to record a verdict that cannot lie the same way.
Currently, a verdict would be written straight into a hand-authored summary. This causes totals that disagree with the facts under them and reports that survive their evidence changing.
Success looks like: every fact is one appended, validated JSONL line at the moment it is learned; every human-readable summary is derived from those lines by a script on every append; a `run_end` cannot carry totals; a non-PASS verdict cannot omit its reason; and a test proves a hand-edited summary is overwritten and a deleted FAIL line changes the counts.

## Acceptance Criteria
- [ ] AC1 Given a valid `evidence.jsonl` under `<run_dir>`, when `verify-helpers.sh evidence-append <run_dir> '<ac line with verdict FAIL and no reason>'` runs, then exit is 1, the line is appended to `<run_dir>/rejected.jsonl` (wrapped `{"rejected_at","reason","line"}` via `jq --arg`, so the file is valid JSONL even when the input was not), and `<run_dir>/evidence.jsonl` is byte-identical before and after (`cmp`).
- [ ] AC2 Given any successful `evidence-append`, when it returns, then `<run_dir>/summary.md` has been regenerated from the lines (its second line is the blockquote header containing BOTH the literal `DERIVED by \`verify-helpers.sh summary-build\`` AND the literal `do not edit`, asserted as two separate greps); given a hand-edit to `summary.md` replacing the counts row `PASS: 1 · FAIL: 1 · BLOCKED: 0 · NOT_VERIFIABLE: 0 · total: 2` with `PASS: 2 · FAIL: 0 · BLOCKED: 0 · NOT_VERIFIABLE: 0 · total: 2` over a store holding 1 PASS + 1 FAIL, when the next `evidence-append` (or a bare `summary-build`) runs, then the counts row reads `PASS: 1 · FAIL: 1 · BLOCKED: 0 · NOT_VERIFIABLE: 0 · total: 2` again (mutation control a). Every mutation control is gated on "the mutant differs from the original"; an edit that matched nothing is reported `UNPROVEN` and counts as `no()` (the suite exits 1).
- [ ] AC3 Given a `run_end` line carrying a `counts` (or `totals`) key at any depth, when `evidence-append` or `validate-verify-evidence.py` sees it, then it is rejected (`run_end_carries_counts`); given a fixture of 5 `ac` lines (2 PASS / 1 FAIL / 1 BLOCKED / 1 NOT_VERIFIABLE), when `summary-build` runs, then the counts row reads `PASS: 2 · FAIL: 1 · BLOCKED: 1 · NOT_VERIFIABLE: 1 · total: 5` exactly; given the FAIL line is then deleted from `evidence.jsonl` and `summary-build` re-runs, then the summary changes to `FAIL: 0 · total: 4` (mutation control b).
- [ ] AC4 Given `verify-helpers.sh`, when the `evidence_append()` function body is extracted (awk from the `evidence_append() {` line to its closing `}` at column 0), then (positive control first) the extracted body is NON-EMPTY and contains EXACTLY ONE line naming `evidence.jsonl`, and that line contains `>>`; and it contains NO read of `evidence.jsonl` (no `cat`, `<`, `jq`, `grep`, `wc`, `tail`, `head`, `read` token whose operand is `evidence.jsonl`) — asserted by grep in the test; given a COPY of the helper with `cat "$run_dir/evidence.jsonl"` inserted into that function body, when the same grep runs against the copy, then it FAILS (mutation control c, gated on copy-differs-from-original + `bash -n`); `summary-build` (a different function) is the reader.
- [ ] AC5 Given `RESULT_SCHEMAS.md`, when `## VERIFY_EVIDENCE` is added immediately after `## VERIFY_ENV` and before `## Validation Location`, with `schema_version: 1` and frozen example values per the `check-doc-currency.sh` header convention, PLUS a dated `- **VERIFY_EVIDENCE (schema_version 1)** (2026-09-14): …` bullet under `### Version History` and a `VERIFY_EVIDENCE at \`schema_version: 1\`` mention on the intro `Current versions:` line (the convention every schema_version-carrying schema in the file follows — FLOOR_PROJECTION, POSTMORTEM_RESULT, REVIEW_HEAL_RESULT…), then `bash scripts/check-doc-currency.sh` is green; `test-emit-block-parses.sh` and `result_block_parser.py` need NO change (VERIFY_EVIDENCE is a JSONL state-file line, not an emitted result block — verified: neither file enumerates RESULT_SCHEMAS sections) and the brief records that as the reason.
- [ ] AC6 Given `validate-verify-evidence.py`, when invoked as `--line '<json>'` or `<file>` (whole-file mode validates every line and reports the first offending line number), then exit 0 = valid, 1 = invalid (stdout `{"ok":false,"reason":"<snake_case>","line":<n|null>}`), 2 = usage/unreadable input; the reason set is EXACTLY: `not_json`, `not_object`, `schema_version_mismatch` (missing or ≠ 1), `missing_key:<k>` (a per-event required key absent — incl. `env.reason` on `outcome: fail`, `pause`/`resume` `reason`), `bad_type:<k>`, `unknown_event`, `unknown_verdict`, `unknown_enum:<k>` (any other enum field), `non_pass_without_reason` (an `ac` line with non-PASS verdict and empty/missing `reason`), `missing_classification` (`FAIL`/`BLOCKED` without `classification` ∈ {REAL_BUG, DISCOVERY_GAP, ENVIRONMENT_ISSUE}), `classification_on_pass` (a non-null `classification` on PASS/NOT_VERIFIABLE), `run_end_carries_counts`; the validator's docstring lists the same set and the test provokes EVERY one of them at least once.
- [ ] AC7 Given `verify-helpers.sh run-id <slug>`, when run, then stdout is exactly `verify-<YYYYMMDDTHHMMSSZ>-<slug>` with the slug lower-cased and `[^a-z0-9-]` collapsed to `-`; given `evidence-append` on a `<run_dir>` that does not yet exist, then it creates `<run_dir>/` and `<run_dir>/artifacts/` (`mkdir -p`) before the write.
- [ ] AC8 Given `test-verify-evidence.sh`, when run, then it covers: validator accept/reject per AC6 (line mode AND file mode); AC1 refusal + `rejected.jsonl` + byte-unchanged; AC3 `counts` rejection + 5-AC fixture counts; both mutation controls (a: hand-edited summary overwritten; b: deleted FAIL line changes counts); AC4 no-read grep; AC7 run-id shape; every validator reason in AC6 provoked once (line mode) plus file mode; one `evidence-append <run_dir> -` stdin round-trip; `summary-build` on an absent/empty store yields the `derived_from: 0 lines` summary; the trailer's `N` equals `wc -l < evidence.jsonl` and its sha256 equals `shasum -a 256` of the file, and appending one more line changes the hash; mutation control c (AC4); `evidence-append` with `python3` stubbed absent on PATH refuses (exit 1, `validator_unavailable`, line in `rejected.jsonl`); a validator rejection carries the validator's own `.reason` in `rejected.jsonl` (e.g. `non_pass_without_reason`); latest-per-`ac_id` semantics (two `ac` lines for the same `ac_id`, PASS then FAIL → counts show 1 FAIL, 0 PASS for that id). Every fixture under `mktemp -d`; exit 0/1 with `ok()/no()` counters.
- [ ] AC9 Given the full `for t in loomwright/scripts/test-*.sh` loop plus root `scripts/test-*.sh` and `scripts/check-vendor-coupling.sh`, when run, then all are green (the three new files carry ZERO vendor tokens — no `CLAUDE_PLUGIN_ROOT`, no `~/.claude` — so no manifest allowance change is needed).

## Outcomes Rubric
- One writer per fact, append-only, validated before append
- Summary derived, never authored; mutation control proves it
- Totals impossible to write, only to derive
- Non-PASS always carries a reason
- Schema documented with frozen examples

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | VERIFY_EVIDENCE schema section + `validate-verify-evidence.py` + seam test (validator cases, line + file mode) | AC5, AC6 | 1 modify, 2 create | `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md` | LAUNCHABLE |
| 2 | `verify-helpers.sh` (`evidence-append` / `summary-build` / `run-id`) + helper cases appended to the seam test (refusal, derivation, three mutation controls a/b/c, no-read grep) + release entry (CHANGELOG + version bump) | AC1, AC2, AC3, AC4, AC7, AC8, AC9 | 4 modify, 1 create | `skills/quality-checklist/SKILL.md`, `skills/error-handling/SKILL.md` | BLOCKED (by #1) |

### Subtask Contracts

```yaml
# Subtask 1 — schema + validator + validator half of the seam test (LAUNCHABLE)
provides:
  - {kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "## VERIFY_EVIDENCE"}
  - {kind: "file", path: "loomwright/scripts/validate-verify-evidence.py"}
  - {kind: "file", path: "loomwright/scripts/test-verify-evidence.sh"}
requires: []
lanes:
  - "loomwright/docs/RESULT_SCHEMAS.md"
  - "loomwright/scripts/validate-verify-evidence.py"
  - "loomwright/scripts/test-verify-evidence.sh"
external_requires:
  - "python3 (stdlib only — already required by every sibling validate-*.py)"

# Subtask 2 — helper + helper cases + release entry (BLOCKED by #1)
provides:
  - {kind: "file", path: "loomwright/scripts/verify-helpers.sh"}
  - {kind: "symbol", path: "loomwright/scripts/test-verify-evidence.sh", name: "== (AC2) mutation control a"}
  - {kind: "symbol", path: "CHANGELOG.md", name: "verify-helpers.sh"}
requires:
  - {from: "1", kind: "file", path: "loomwright/scripts/validate-verify-evidence.py"}
  - {from: "1", kind: "file", path: "loomwright/scripts/test-verify-evidence.sh"}
  - {from: "1", kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "## VERIFY_EVIDENCE"}
lanes:
  - "loomwright/scripts/verify-helpers.sh"
  - "loomwright/scripts/test-verify-evidence.sh"
  - "CHANGELOG.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
external_requires:
  - "jq (line construction + summary derivation; already required by every sibling helper)"
  - "shasum -a 256 or sha256sum (the derived_from trailer; try shasum first, fall back)"
```

**Shared-file note (`test-verify-evidence.sh`):** Subtask 2 is reachable from Subtask 1 in the `requires` DAG, so the shared lane is sequential and legal. Sequential sharing grants visibility, not preservation — Subtask 2 MUST re-run the whole suite after appending its cases and confirm Subtask 1's validator cases still pass (never edit or delete Subtask 1's cases).

## Implementation notes (per subtask — the precedent to copy, not re-invent)

**Subtask 1**
- `RESULT_SCHEMAS.md` `## VERIFY_EVIDENCE`: a JSONL state-file schema (like §`session_end` and §QA_SESSION — NOT a hook-validated emitted block; say so in the first paragraph, and say the validator is a CLI gate consumed by `verify-helpers.sh evidence-append`, not a `SubagentStop` hook, which is why `## Validation Location` is unchanged). Layout paragraph: `.supervisor/verify/<run_id>/` holds `evidence.jsonl` (append-only, one fact per line), `artifacts/<ac_id>/` (Playwright screenshots/traces/bodies — written by item 03, referenced here by relative path), `summary.md` (DERIVED by `summary-build` on every append — never hand-edited), and `run.md` (item 07; named here so the layout is complete, not created by this item). Then the record shape — **one shape, `event`-discriminated**, common keys on every line: `schema_version: 1` (integer, required), `ts` (ISO-8601 UTC, required), `run_id` (required, `verify-…`), `event` enum `[run_start, env, auth, ac, issue, pause, resume, run_end]` (required). Per-event required keys:
  - `run_start`: `ticket_path` (string), `ticket_kind` enum `[requirement, brief]`, `branch`, `head_sha`, `base_sha` (strings), `env_contract_hash` (sha256 of `.agent/verify.json` or `null` when absent).
  - `env`: `step` enum `[non_prod_assert, start, health, seed, reset, stop]`, `outcome` enum `[pass, fail, skipped]`, `reason` (required non-empty when `outcome` is `fail`).
  - `auth`: `state` enum `[authenticated, anonymous, needs_auth, expired]`.
  - `ac`: `ac_id` (string, e.g. `AC3`), `text` (the AC verbatim), `scope` enum `[ticket, impact]`, `verdict` enum `[PASS, FAIL, BLOCKED, NOT_VERIFIABLE]`, `classification` enum `[REAL_BUG, DISCOVERY_GAP, ENVIRONMENT_ISSUE]` — REQUIRED when verdict is `FAIL` or `BLOCKED`, must be `null`/absent otherwise; `steps` (array of strings, may be empty), `artifacts` (array of relative paths under `<run_dir>/`, may be empty), `reason` (REQUIRED non-empty for every non-PASS verdict; optional on PASS).
  - `issue`: `text` (required), `severity` enum `[BLOCKING, HIGH, MEDIUM, LOW]` (required), `route` (optional string), `artifacts` (optional array).
  - `pause` / `resume`: `reason` (required non-empty).
  - `run_end`: `status` enum `[completed, aborted]` — and **no `counts`/`totals` key at any depth** (the validator rejects it; counts exist only in the derived summary).
  Unknown additive keys are TOLERATED (forward-compat) except the forbidden `counts`/`totals` on `run_end`. Document the **latest-per-`ac_id` rule**: when a run re-verifies an AC (resume, retry), the newest `ac` line for that `ac_id` is the one the summary counts — earlier lines stay in the file as history. Document the `rejected.jsonl` wrapper shape `{"rejected_at": "<ts>", "reason": "<validator reason>", "line": "<raw input string>"}`. Frozen example block: one line per event with fixed sample values (`"ts": "2026-09-14T10:00:00Z"`, `"run_id": "verify-20260914T100000Z-example"`, `"head_sha": "0123456789abcdef0123456789abcdef01234567"`); these are format illustrations and MUST NOT be "fixed" on a version bump (the `check-doc-currency.sh` header convention). Do NOT extend the `schema_version` exception blockquote — this schema DOES carry `schema_version: 1`. DO follow the file's convention for a versioned schema: append `- **VERIFY_EVIDENCE (schema_version 1)** (2026-09-14): New \`## VERIFY_EVIDENCE\` JSONL state-file schema for \`.supervisor/verify/<run_id>/evidence.jsonl\` — no hook validator; CLI gate \`validate-verify-evidence.py\` consumed by \`verify-helpers.sh evidence-append\`. Additive — all other schemas unchanged.` under `### Version History` (near the end of the file), and add `VERIFY_EVIDENCE at \`schema_version: 1\` (JSONL state-file line; CLI-gated, no hook validator)` to the intro `Current versions:` line in the FLOOR_PROJECTION style.
- `validate-verify-evidence.py`: model the module header and the rule-list style on `validate-qa-result.py` but **do NOT import `result_block_parser`** (that module parses YAML result blocks; this validator reads JSON lines with stdlib `json` only) and **do NOT copy the ALWAYS-exit-0 invariant** — state the deviation in the docstring: sibling validators are hook emitters and must exit 0; this one is a CLI GATE consumed by `verify-helpers.sh evidence-append`, so its EXIT STATUS is the decision (0 valid · 1 invalid · 2 usage / unreadable input), with the JSON decision still on stdout (`{"ok": true}` / `{"ok": false, "reason": "...", "line": <n|null>}`). Reasons are snake_case and grep-stable: `not_json`, `not_object`, `schema_version_mismatch`, `missing_key:<k>`, `unknown_event`, `unknown_verdict`, `unknown_enum:<k>`, `non_pass_without_reason`, `missing_classification`, `classification_on_pass`, `run_end_carries_counts`, `bad_type:<k>`. Modes: `--line '<json>'` (one record) or `<file>` (every line; blank lines skipped; the FIRST invalid line's 1-based number in `line`). `counts`/`totals` detection walks the `run_end` object recursively. No third-party imports.
- `test-verify-evidence.sh`: model on `test-verify-seam.sh` — `set -uo pipefail`, `ok()/no()` counters, every fixture under `mktemp -d`, PATH stubs, exit 0/1. Validator cases: one valid line per event accepted (line mode); each reason in AC6 provoked once; file mode over a 3-line file with line 2 broken reports `"line": 2`; exit codes 0/1/2 asserted explicitly (`$?`, never `grep -q` on the right of a pipe under `pipefail` — memory `bash-grep-pipefail-nul-traps`). Leave a clearly marked `# --- helper cases (Subtask 2 appends below this line) ---` anchor at the end, before the final summary/exit. Do NOT emit the literal `== (AC2) mutation control a` anywhere in this file — that case-header string is Subtask 2's `provides` token and must first appear with Subtask 2's helper cases.

**Subtask 2**
- `verify-helpers.sh`: model on `automate-helpers.sh` (subcommand dispatch, `set -uo pipefail`, `diag()` to stderr, jq-only JSON construction, atomic temp+`mv` for the derived file). No comment inside `evidence_append()` may name `evidence.jsonl` (AC4's positive control counts EXACTLY ONE such line — the write); put the "never reads" note on the line ABOVE the function. Locate the validator as `"$(dirname "$0")/validate-verify-evidence.py"` (sibling path — never a plugin-root variable; the file is core and must stay vendor-neutral, memory `run-full-ci-suite-loop-before-push`). Subcommands:
  - `run-id <slug>` → `verify-$(date -u +%Y%m%dT%H%M%SZ)-<slug>` with the slug normalised (`tr 'A-Z' 'a-z' | sed 's/[^a-z0-9-]\{1,\}/-/g; s/^-//; s/-$//'`).
  - `evidence-append <run_dir> <json|->` (`-` = read the one record from stdin): `mkdir -p "$run_dir/artifacts"`; run `python3 validate-verify-evidence.py --line "$json"`; capture `rc=$?` (`if ! rc=…` patterns lose the status — memory `exit-status-lost-across-subshell-and-or-true`; assign the output in one statement and the status in the next, or use `set +e` around the call). `rc=0` → ONE `printf '%s\n' "$json" >> "$run_dir/evidence.jsonl"` (the shell's `>>` is `O_APPEND`; one write per line; the function body NEVER reads `evidence.jsonl` — AC4 greps for this) then call `summary_build "$run_dir"`; exit 0. `rc≠0` → reason mapping: `rc=1` → the `.reason` parsed from the validator's stdout JSON (fallback `validator_rejected` if stdout is unparseable); `rc=127` (python3 absent) → `validator_unavailable`; any other non-zero → `validator_error:<rc>`; then `jq -cn --arg ts … --arg reason … --arg line "$json" '{rejected_at:$ts,reason:$reason,line:$line}' >> "$run_dir/rejected.jsonl"`, reason to stderr, exit 1, `evidence.jsonl` untouched. Never read-modify-write.
  - `summary-build <run_dir>`: the ONLY reader. `jq -s` over `evidence.jsonl` (empty/absent file ⇒ a summary that says "0 lines"). Sections: line 1 `# Verify run <run_id> — summary`, line 2 EXACTLY `> DERIVED by \`verify-helpers.sh summary-build\` from evidence.jsonl on every append — do not edit; edits are overwritten.` (AC2 greps the two literals `DERIVED by \`verify-helpers.sh summary-build\`` and `do not edit` separately); run header from the last `run_start` (ticket, kind, branch, head/base sha, env contract hash); env table (step / outcome / reason, latest per step); auth (latest `state`); per-AC table (ac_id, scope, verdict, classification, reason, artifacts — **latest line per `ac_id` wins**, `group_by(.ac_id) | map(last)` after sorting by input order); verdict counts row EXACTLY `PASS: <n> · FAIL: <n> · BLOCKED: <n> · NOT_VERIFIABLE: <n> · total: <n>` (over the latest-per-ac_id set); issues list; pauses/resumes list; artifacts index (every `artifacts[]` path, deduped); `run_end` status if present; trailer `derived_from: <N> lines, sha256 <hash of evidence.jsonl>` (`shasum -a 256` → fallback `sha256sum`). Write to `<run_dir>/summary.md.tmp.$$` then `mv -f` (atomic; a crash never leaves a half summary). No agent ever writes this file.
- Append helper cases to `test-verify-evidence.sh` after the anchor, each under an `echo "== (ACn) <name> =="` case header — the mutation-control-a block MUST be headed exactly `echo "== (AC2) mutation control a =="` (this literal is the subtask's `provides` token): AC1 (FAIL-without-reason → exit 1, `rejected.jsonl` has one wrapped line whose `.line` round-trips the raw input, `cmp` evidence before/after); AC2 (summary regenerated after append — header line present; mutation control a: `sed`/`printf` the counts row to `PASS: 2 · FAIL: 0`, run `summary-build`, assert `PASS: 1 · FAIL: 1`); AC3 (`run_end` with `counts` and with nested `{"meta":{"totals":…}}` both rejected `run_end_carries_counts`; the 5-AC fixture counts line exact; mutation control b: delete the FAIL line with `grep -v`, re-run, assert `FAIL: 0 · total: 4`); AC4 (awk-extract the `evidence_append()` body from the line matching `^evidence_append\(\) \{` to the first `^\}` — the helper MUST spell the function exactly that way; positive control: body non-empty AND exactly one `evidence\.jsonl` line AND that line has `>>`; negative: zero `evidence\.jsonl` matches on lines without `>>`; mutation control c: `sed` a `cat "$run_dir/evidence.jsonl"` line into a COPY after the `mkdir -p`, gate on copy-differs + `bash -n`, assert the grep now FAILS); trailer: `derived_from: N lines` where N equals `wc -l < evidence.jsonl`, sha256 equals `shasum -a 256 evidence.jsonl | cut -d' ' -f1`, and appending one more line changes it; stdin: `printf '%s' "$line" | verify-helpers.sh evidence-append "$d" -` round-trips; empty store: `summary-build` on a fresh `mktemp -d` (no `evidence.jsonl`) yields the trailer `derived_from: 0 lines, sha256 e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` (the sha256 of empty input — hash `/dev/null`, never skip the hash); the AC2 fixture uses TWO DISTINCT ids (`AC1` PASS, `AC2` FAIL) so latest-per-ac_id yields `total: 2`; AC7 (run-id regex `^verify-[0-9]{8}T[0-9]{6}Z-[a-z0-9-]+$`; slug `My Ticket!` → `my-ticket`; `run_dir` auto-created with `artifacts/`); AC8 latest-per-ac_id (append `AC1 PASS` then `AC1 FAIL` with reason+classification → counts `PASS: 0 · FAIL: 1 · … total: 1`); python3-absent PATH stub → `validator_unavailable`, exit 1, line in `rejected.jsonl`. Gate every mutation (a, b, c) on "the mutant differs from the original" (report `UNPROVEN` when the edit matched nothing — lesson `fa32a308`) — and an `UNPROVEN` is a `no()`: the suite MUST exit 1 on it, never treat an unproven mutation as a pass. Re-run the FULL suite and confirm Subtask 1's cases still pass.
- Release: read the LIVE `loomwright/.claude-plugin/plugin.json` version at execution time (lesson `16ffd26d`) and bump the minor (15.73.1 → 15.74.0 if unchanged) in BOTH `plugin.json` and `.claude-plugin/marketplace.json` (the `vX.Y.Z` in each `description` in place — never append a clause); add ONE `**v15.74.0 — …:**` paragraph directly after the historical-entries blockquote in `CHANGELOG.md` (before the `v15.73.1` paragraph), naming `verify-helpers.sh`, and ending with "Counts unchanged: 14 agents, 23 commands, 41 skills, 36 hooks." Do NOT touch README.md / CLAUDE.md (memory `release-surfaces-readme-claude-md-no-longer-bump`).
- Run `bash scripts/check-doc-currency.sh`, `bash scripts/check-vendor-coupling.sh`, root `scripts/test-*.sh`, and the full `for t in loomwright/scripts/test-*.sh` loop before declaring done (memory `run-full-ci-suite-loop-before-push`).

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | `loomwright/scripts/test-verify-evidence.sh` | YES (already ordered by `requires`) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after Subtask 1)
- **Recommended workers:** 1
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md` |
| 2 | `skills/quality-checklist/SKILL.md`, `skills/error-handling/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Prior churn (postmortem ledger): `CHANGELOG.md`, both manifests, `RESULT_SCHEMAS.md` are the four most-churned files in the ledger; recurring classes `convention_mismatch` / `quality_gap`; `self_heal_miss` recurred on #220 (drain fixed a 3xx-health + env-var name-parity finding Phase 4.5 passed) | HIGH | Source: "Prior churn (postmortem ledger)". Reviewers apply the miss-class checklist as a DIFFERENT lens (lesson `d8f68195`): a green `heal_decision: PASS` is not evidence. Re-check: CHANGELOG entry shape (single `**vX.Y.Z — title:**` paragraph, no `##`), `description` version in place in BOTH manifests, the schema section sits between `## VERIFY_ENV` and `## Validation Location`, name-parity between the schema's enum values and the validator's constants and the summary's column labels (one source, three surfaces). |
| Summary that survives its evidence (the whole reason for the item) | HIGH | Two mutation controls (AC2a, AC3b) are part of the suite, both gated on "mutant differs from original"; `summary-build` is the ONLY reader and the only writer of `summary.md`; the header says DERIVED; no agent prompt in this item writes the file. |
| `evidence-append` reads-then-writes (a read-modify-write would race a concurrent appender and defeat `O_APPEND`) | HIGH | The append is exactly one `printf … >>`; AC4 greps the extracted function body for any `evidence.jsonl` read token; derivation lives in a separate function. |
| Validator exit-status deviation from the sibling ALWAYS-exit-0 convention confuses a future hook author | MEDIUM | Docstring states the deviation and WHY (CLI gate, not a hook emitter); `## VERIFY_EVIDENCE` says the same; `## Validation Location` is explicitly left unchanged because this is not hook-layer validation. |
| Exit status lost across `local x="$(…)"` / `\|\| true` / command-substitution (memory `exit-status-lost-across-subshell-and-or-true`) | HIGH | Capture the validator's stdout and `$?` in two separate statements (or `set +e` around the call); test asserts the python3-absent case is REFUSED (exit 1 + `rejected.jsonl`), which is exactly the case a swallowed status would let through. |
| macOS bash 3.2 / BSD userland (`sha256sum` absent on macOS; `sed -i` divergence; `${empty[@]}` under `set -u`) | MEDIUM | `shasum -a 256` first with a `sha256sum` fallback; never `sed -i` (temp + `mv`); `"$@"` not `"${arr[@]}"` on possibly-empty arrays; macOS-green ≠ CI-green. |
| `producer \| grep -q` SIGPIPE under `pipefail`; `grep -c … \|\| echo 0` double line | MEDIUM | Memory `bash-grep-pipefail-nul-traps`: capture to a variable then test; count with `grep -c` into a variable and default separately. |
| Root `scripts/check-vendor-coupling.sh` ratchet trips on a `${CLAUDE_PLUGIN_ROOT}` / `~/.claude` mention in a core script COMMENT | MEDIUM | All three new files are core and must carry zero vendor tokens (locate the validator by `dirname "$0"`); word comments neutrally; run the root gate before pushing. |
| `jq` `//` collapses a legal `null` (`classification: null` on PASS is legal; `env_contract_hash: null` is legal) into "missing" | MEDIUM | Validator is python (explicit `in` checks); in the summary jq use `has()`/`if . == null` — never `.key // "x"` to decide presence (memory `nullable-required-field-needs-presence-check`). |
| `provides` symbol `## VERIFY_EVIDENCE` must match the file's H2 convention; the test-file token must not pre-exist | LOW | RESULT_SCHEMAS.md uses `## NAME` for every schema; the `== (AC2) mutation control a` literal is forbidden in Subtask 1's half by instruction (memory `provides-token-zero-hit-is-not-enough`). |
| Concurrent writer on this checkout sweeps uncommitted edits | LOW | Single `/automate` run; no other session was found working this repo at brief time (the `.claude/worktrees/*` entries are idle desktop worktrees). Workers commit per subtask. |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-09-14-verify-evidence-store.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-09-14T10:15:32Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/222
- **Branch:** feature/verify-evidence-store
- **Files changed:** 7
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** Verify evidence store shipped — §VERIFY_EVIDENCE (schema_version 1, event-discriminated, 12-code reason set, frozen examples), validate-verify-evidence.py (exit-status CLI gate), verify-helpers.sh (evidence-append validate-then-single->> write with rejected.jsonl, summary-build sole reader/derived writer, run-id), test-verify-evidence.sh 245/245 with five mutation controls (a–e); Phase 4.5 iteration 1 FAIL (HIGH: pretty-printed record stored as N lines + same-class dead die-fallback) → fixed 14c7e07 → iteration 2 PASS (2 MEDIUM + 4 LOW carried forward, non-gating); rubric 5/5; ground_truth 2/2 pass; contract_conformance advisory_violations 1 (Validation-Location spec lacks the writer-side CLI-gate mode); risk_classification high_risk=true (advisory); release v15.74.0. Default until-mergeable dispatch suppressed by the /automate engine (owned inline drain follows).
