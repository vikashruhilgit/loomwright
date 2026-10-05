# Supervisor Job: A `provides` name containing a quote is read correctly by verify-provides.sh, and an unreadable one is blocked at Plan Review

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes-v2/s2-c
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/automate-followups/24-provides-name-quote-parsing.md
- **Base commit:** c1692b091ef1747c6d600cd6cc2073277981f880

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2 + BSD awk script with a co-located static test suite; no new dependency |
| 2 | Dependency Availability | GO | awk, grep, sed, jq already required by the script |
| 3 | Architecture Fit | GO | `verify-provides.sh` is the ONE parser of `provides:`; fixing `field()` there fixes every consumer (worker Step 5.5, Execute Manager gate, Supervisor gates, Launch Pad `--parse-only`) |
| 4 | Scope vs Supervisor Capability | GO | 4 files, one domain, single subtask (no split reason fires) |
| 5 | Hard Blockers | GO | none |

**Overall Verdict:** GO

## Task
**Goal:** `verify-provides.sh` reads a double-quoted `provides` name with `\"` / `\\` escapes correctly, and a name it still cannot read faithfully surfaces as a BLOCKING Plan Review finding showing the parser's reading, never as a false "missing" after the work is done.

**Problem Statement:**
Workers and owners need the fail-closed `outputs_verified` gate to judge what the brief meant, because a false "missing" stops a green worker and costs an owner question.
Currently, `field()` in `verify-provides.sh` ends a quoted value at the FIRST matching quote and has no escape handling, so v2-b's entry `name: "PINS=\"1 2 3 4 5 6 7 8 9 10\""` was searched as `PINS=\` and reported missing although the line `PINS="1 2 3 4 5 6 7 8 9 10"` exists in `loomwright/scripts/test-rules-gate-seams.sh`. Plan Review flagged it only as a LOW note.
Success looks like that entry reporting `present` (6 of 6 for v2-b's contract), and any name the parser still cannot read being refused at Plan Review with the parser's reading quoted.

## Acceptance Criteria
- [ ] AC1 — Given a double-quoted name containing `\"`, when `verify-provides.sh` parses it, then `\"` is read as a literal `"` and the value ends at the first UNESCAPED `"`.
- [ ] AC2 — Given a double-quoted name containing `\\`, when parsed, then `\\` is read as ONE literal backslash; any other backslash sequence (`\b`, `\n`, a lone `\`) is kept byte-for-byte (so the existing `it's\back\nslash` fixture is unchanged).
- [ ] AC3 — Given a single-quoted name, when parsed, then nothing inside is escaped (YAML-like) and a `"` inside it is literal; the value ends at the next `'`.
- [ ] AC4 — Given an unterminated quote, when parsed, then the value is "the rest, trimmed" exactly as today.
- [ ] AC5 — Given v2-b's original entry verbatim `{kind: "symbol", path: "loomwright/scripts/test-rules-gate-seams.sh", name: "PINS=\"1 2 3 4 5 6 7 8 9 10\""}`, when checked with `--root` at the repo root on this branch, then it reports `present` (check_run exit 0).
- [ ] AC6 — Given a name with regex metacharacters (`=`, `"`, spaces, `.`), when the symbol check runs, then it matches LITERALLY (fixed-string semantics) and a one-character mutation of the name reports `missing`.
- [ ] AC7 — Given `--parse-only`, when an entry's name is one the parser cannot read faithfully (an unterminated quote, or non-whitespace text between a value's closing quote and the next `,`/`}`), then the JSON line carries an additive `parse_warnings` array, each item naming the entry's path and the parser's reading (e.g. `checked as \`PINS=\\\``); a brief with no such entry prints the `--parse-only` object byte-identical to today (no `parse_warnings` key).
- [ ] AC8 — Given `agents/plan-reviewer.md` Criterion 12, when a `--- GATE PARSE ---` line carries `parse_warnings`, then the reviewer is instructed to raise a BLOCKING `dep_graph` finding that quotes the parser's reading ("this entry would be checked as `…`"), not a LOW note.
- [ ] AC9 — Given the existing `test-verify-provides.sh` cases, when run unedited against the change, then every one passes; and the new cases cover `\"` match, `\\` round-trip, single-quoted `"`, the v2-b entry verbatim, unterminated quote, `parse_warnings` present/absent, and a mutation control proving that dropping the escape handling turns the `\"` case red.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## House Rules

> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.
  - id: process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

## Implementation Notes (for the worker)

- **Where:** the awk `field(entry, key)` function inside `parse_brief()` in `loomwright/scripts/verify-provides.sh` (the function commented "value of `key: value` inside a flow mapping; quotes optional"). Replace the `index(substr(rest, 2), q)` first-quote lookup with a character scan: for `q == "\""`, `\\` ⇒ `\`, `\"` ⇒ `"`, any other `\x` kept as both characters, an unescaped `"` ends the value; for `q == "'"`, no escapes, the next `'` ends it. No closing quote ⇒ `trim(substr(rest, 2))` (today's behaviour). Portable awk only (BSD awk on macOS; no gawk-isms).
- **Entry trimming interplay:** the entry is cut at `}` before `field()` sees it (the `match(entry, /\}[[:space:]]*#/)` / `/\}[^}]*$/` lines). Keep that as is; do not widen scope to names containing `}`.
- **Parse warnings (AC7):** `field()` (or its caller) records, per entry, when the value was unterminated or when the text after the closing quote up to the next `,`/`}` is not whitespace. Carry it out of awk as an extra field on the entry line (e.g. a 4th TAB column) and, in `--parse-only` mode ONLY, build `parse_warnings` with `jq --arg` (never shell-templated JSON). The non-`--parse-only` output object is unchanged. Update the script header's `--parse-only` paragraph to name the additive key.
- **Fixed-string symbol check (scope item 2):** the requirement says the check "keeps using the unescaped name as a fixed string (`grep -F`)". The current code is `grep -nE` over `ere_escape`d text, which is literal-match equivalent and is what `--kind-table` and the byte-for-byte `docs/RESULT_SCHEMAS.md` kind-table copy document. KEEP the escaped-ERE implementation (do not switch to `grep -F`, which would force a kind-table + RESULT_SCHEMAS change outside this item's Touches); prove fixed-string semantics with the AC6 test instead.
- **Plan Reviewer (AC8):** one bullet/clause in Criterion 12 next to the existing "Gate-parseable anchor" bullet and the BLOCKING severity list; keep it short (plan-reviewer has ~1000 proxy tokens of headroom under `loomwright/docs/prompt-token-budgets.json`; `scripts/check-token-budget.sh` must stay OK — do not raise the budget).
- **Changelog:** add `changelog.d/automate-followups-24-provides-name-quote-parsing.md` (patch-level; format in `changelog.d/README.md`). Do NOT hand-edit `plugin.json` / `marketplace.json` / `CHANGELOG.md` and do not run `bump-version.sh`.
- **Tests:** add a new `echo "--- script: quoted names (escapes) ---"` section with its own fixture brief; use `ok()/no()` like the rest of the file; put the AC5 fixture's target file in the temp dir as a copy of the real `PINS=` line AND add one case that checks the entry against the real `$PLUGIN_ROOT/scripts/test-rules-gate-seams.sh`. Mutation control (AC9): copy the script, replace the escape-aware scan with the old first-quote `index()` form in the COPY, gate the mutant on non-empty + differs-from-original + `bash -n`, and assert the `\"` case reports `missing` against it.
- **Pre-push:** `bash scripts/ci-local.sh` (the only sanctioned pre-push run).

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Escape-aware `field()`, `--parse-only` parse warnings, Plan Review BLOCKING rule, tests, changelog fragment | AC1–AC9 | 3 modify, 1 create | `skills/unit-testing/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/scripts/verify-provides.sh", name: "parse_warnings"}
  - {kind: "symbol", path: "loomwright/scripts/test-verify-provides.sh", name: "quoted names"}
  - {kind: "symbol", path: "loomwright/agents/plan-reviewer.md", name: "parse_warnings"}
  - {kind: "file", path: "changelog.d/automate-followups-24-provides-name-quote-parsing.md"}
requires: []
lanes:
  - "loomwright/scripts/verify-provides.sh"
  - "loomwright/scripts/test-verify-provides.sh"
  - "loomwright/agents/plan-reviewer.md"
  - "changelog.d/automate-followups-24-provides-name-quote-parsing.md"
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 (independent)
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | — | none | NO |

### Batch Plan
- **Batch 1:** Subtask 1
- **Recommended workers:** 1
- **Estimated batches:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| BSD awk differences (no gawk escapes, `substr`/`index` edge cases) break the char scan on macOS | MEDIUM | Char-by-char loop with `substr(s, i, 1)` only; run `test-verify-provides.sh` on macOS and via `scripts/ci-local.sh` |
| Changing `field()` alters how an existing brief's name is read (a `\\` in a double-quoted name now reads as one backslash) | MEDIUM | AC2 keeps every non-`\"`/`\\` backslash sequence byte-for-byte; AC9 requires every existing case to pass unedited |
| Requirement scope item 2 says "keeps using `grep -F`", but the code uses escaped ERE (`grep -nE` + `ere_escape`) | LOW | Keep the ERE form (literal-equivalent, and what the kind-table + RESULT_SCHEMAS copy document); prove fixed-string behaviour with AC6 |
| `--parse-only` JSON gains a key that a consumer might parse strictly | LOW | The key is additive and present ONLY when a warning exists; the only consumer is Launch Pad action 1b, which pastes the line verbatim |
| plan-reviewer prompt growth exceeds its token budget | LOW | Keep the Criterion 12 addition to one short clause; `check-token-budget.sh` must stay OK |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-05-provides-name-quote-parsing.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-10-05T01:05:14Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/381
- **Branch:** feature/automate-followups-24-provides-name-quote-parsing
- **Files changed:** 4
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** field() in verify-provides.sh reads \" and \\ escapes in double-quoted names (single quotes unescaped, unterminated unchanged); --parse-only adds parse_warnings for an unreadable name; Plan Reviewer Criterion 12 blocks on it. test-verify-provides 133/0 -> 156/0; ground truth 2/2; Phase 4.5 review PASS on first pass (2 dismissed: MEDIUM drift launch-pad 1b, LOW pre-existing path-quote gap).

## Not verified
- **Plan Reviewer raising the BLOCKING dep_graph finding on a parse_warnings GATE PARSE line** — prompt behaviour, observable only on the next Launch Pad review after reinstall (subtask 1)
