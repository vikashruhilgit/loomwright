# Supervisor Job: Approach-challenged rounds are counted in the postmortem ledger

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** dirty (6 files — unrelated in-flight `fix/890` lane edits under `loomwright/scripts/automate-lanes.d/`, `skills/automate-loop/lanes.md`, `changelog.d/890-*.md`; none in this brief's File Impact Map), branch: fix/890-escalated-lane-closed-pr-gone
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 2 (dirty tree; 2 orphaned-looking worktrees from other sessions)
- **Source requirement:** .supervisor/requirements/approach-decisions/01-approach-challenged-rounds-are-counted-in-the-postmortem-ledger.md
- **Base commit:** a2d959448b3cada018961fe5903c97745ea412b9

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2 + jq + `gh` — the stack every sibling reader (`read-postmortem.sh`, `pr-postmortem-gather.sh`) already uses |
| 2 | Dependency Availability | GO | no new dependency; `pr-postmortem-gather.sh` and the PATH-stub `gh` test pattern exist on base |
| 3 | Architecture Fit | GO | additive per-round boolean mirroring `self_heal_miss` / `dismissed_then_raised`; one more advisory reader line; one read-only script — no gate reads the flag |
| 4 | Scope vs Supervisor Capability | GO | 12 files, est. < 800 changed lines → single-agent default (no split reason fires) |
| 5 | Hard Blockers | CAUTION | the requirement's premise "`build-floor.sh` has nothing postmortem-shaped for `categories`" is stale: `build-floor.sh` reads the churn ledger (`PM=".supervisor/postmortem/results.jsonl"`), builds a class distribution (`class_basis: ".categories[].class"`) and projects each `categories[]` entry through a fixed allowlist — `class`, `flow_stage`, `round`, `self_heal_miss` (`then {self_heal_miss: .c.self_heal_miss}`), `evidence` — that already omits `dismissed_then_raised`. `approach_challenged` will be absent from its `entries[]` the same way. No change: `build-floor.sh` is a requirement non-goal; the evidence file records the actual grep output |

**Overall Verdict:** CAUTION

## Task
**Goal:** Give every categorized `/pr-postmortem` review round an optional per-round boolean `approach_challenged` (plus a top-level `approach_challenges` counter), tally it in `read-postmortem.sh`, and ship a one-shot, read-only `postmortem-approach-baseline.sh` that estimates the same flag over the existing ledger — recording the baseline number in a committed evidence file.

**Problem Statement:**
The owner, reading `/pr-postmortem` reports and the churn ledger, needs approach-caused rework (a reviewer questioning the chosen approach/library/tool rather than the code's correctness) to be a measured rate because story `02` (briefs record the chosen approach) may not be queued without a baseline.
Currently, the six root-cause classes have no approach bucket, so "why not use X" / "the platform already provides this" rounds are filed invisibly under `missing_context` or `plan_gap`, and the 237-line ledger carries no approach signal.
Success looks like: new ledger lines carry `approach_challenged` per round and `approach_challenges` overall (schema stays 1), `read-postmortem.sh` prints `- approach-challenged rounds: N of M prior rounds`, and a committed `docs/evidence/approach-baseline.md` records the baseline script's summary line over the real ledger.

## Acceptance Criteria

Every script case runs in a `mktemp -d` fixture dir with its own `results.jsonl`; no network; `gh` is a PATH stub; every new test sources `hermetic-test-env.sh` as its first executable line (`scripts/check-test-hermetic.sh` passes).

1. - [ ] **Flag and counter are additive, schema stays 1:** Given the jq object literal of `skills/pr-postmortem/SKILL.md` Step 5's fenced append block (the test extracts it from the SKILL — from the line `        '{` through the line starting `         }'` — and runs it with `jq -c`, fixture `--arg`/`--argjson` values and a fixture `$GATHERED`, so the test executes the SKILL's own program, not a copy), when `CATEGORIES_JSON` holds three rounds with `approach_challenged: true` on one and `--argjson approach_challenges 1`, then the produced line carries `approach_challenges: 1`, `schema_version: 1` and the per-round `approach_challenged` booleans (Test: `loomwright/scripts/test-postmortem-approach-baseline.sh`); and given a pre-existing line without either field, when `read-postmortem.sh` reads it, then every existing `test-read-postmortem.sh` case passes unchanged (Test: `loomwright/scripts/test-read-postmortem.sh`).
2. - [ ] **Reader tallies the flag:** Given a fixture ledger whose hit entries hold 3 categorized rounds with 1 flagged, when `read-postmortem.sh <hit path>` runs, then output carries `- approach-challenged rounds: 1 of 3 prior rounds`; given the same ledger with no flag on any round, then `- approach-challenged rounds: 0 of 3 prior rounds`; given a ledger with no hits, then output is empty (no such line). Test: `test-read-postmortem.sh`.
3. - [ ] **Reader output order and existing lines unchanged:** Given any hit, when the reader runs, then every existing pinned line (`prior churn rounds:`, `any self_heal_miss in prior rounds:`, the attribution caveat) still appears and the new line sits immediately after the `self_heal_miss` line. Test: `test-read-postmortem.sh`.
4. - [ ] **Baseline script — phrase match on `evidence`:** Given a fixture ledger with one entry of 4 categorized rounds whose `evidence` strings are "why not use the SDK's retry here", "off-by-one in the loop", "the harness already provides a lock — reinventing it", "missing test for the empty case", when `postmortem-approach-baseline.sh --fixture <dir> --no-gh` runs, then rows 1 and 3 print `true` in the `approach_challenged_guess` column, rows 2 and 4 `false`, and the last stdout line is `approach_challenged: 2 of 4 categorized rounds (guess; 1 entries, 0 gathered, 1 gather-unavailable)`. Test: `loomwright/scripts/test-postmortem-approach-baseline.sh`.
5. - [ ] **Baseline script — recorded flag wins over the guess:** Given an entry already carrying `approach_challenged: false` on a round whose evidence says "why not", when the script runs, then that row prints `recorded:false` and is counted as recorded, not guessed. Test: `test-postmortem-approach-baseline.sh`.
6. - [ ] **Baseline script — gather OR:** Given a PATH-stubbed `gh` (the `test-pr-postmortem-gather.sh` stub pattern) serving a PR whose `review_comments[].snippet` contains "simpler to use the platform's queue" and an entry whose round evidence is "null check", when the script runs without `--no-gh`, then the row prints `true` and the summary counts `1 gathered`. Test: `test-postmortem-approach-baseline.sh`.
7. - [ ] **Baseline script never writes:** Given any case above, when the script runs, then the fixture `results.jsonl` is byte-identical before and after (`cmp`), no file is created under the fixture dir, and the `gh` stub's call log shows only read calls — `pr view`, `api …/comments` and the gather's own `api user` login read — never `pr comment`/`pr edit`/`api -X POST|PATCH|PUT|DELETE`. Under `--no-gh`, a stub that fails the test if called is placed first on PATH and is never called. Test: `test-postmortem-approach-baseline.sh`.
8. - [ ] **Baseline script is fail-safe:** Given an absent ledger, when the script runs, then it exits 0, prints no rows, prints `approach_challenged: 0 of 0 categorized rounds (ledger unreadable: absent)` and the reason on stderr; given a ledger with one malformed line among valid ones, then the valid rounds print and the malformed line is skipped; given a well-formed curation record retracting an entry (by `pr_url` or `automate_key`), then that entry's rounds are excluded and the curation record itself prints no row; given a `PATH` without `jq`, then stdout is empty, exit 0, reason on stderr. **Curation parity case** (fixture recipe: a temp git repo with NO remote, so the reader is unscoped; the ledger at that repo's `.supervisor/postmortem/results.jsonl`; entries with no `ts`, so staleness keeps them; every entry's `changed_paths` holds one shared path; every entry a unique `class`; the baseline run with `--ledger <that path>`, the script's `--ledger <path>` option from the requirement): given ONE fixture ledger with an entry retracted by `pr_url`, one retracted by `automate_key`, and one targeted by a malformed curation record (`target_key` missing / `""` / non-string — that entry stays LIVE), when both `read-postmortem.sh <shared path>` and the baseline script run over it, then both exclude exactly the same entries (the reader's classes and the baseline's rows name the same live entries). Test: `test-postmortem-approach-baseline.sh`.
9. - [ ] **No injection through evidence text:** Given an `evidence` string containing `$(touch <marker>)`, backticks and a tab, when the script runs, then no marker file is created and the row's snippet column holds the text with the tab replaced by a space (one TSV row per round). Test: `test-postmortem-approach-baseline.sh`.
10. - [ ] **Mutants each fail a case:** Given (a) a copy of the baseline script with the phrase array emptied, then the AC 4 case prints `0 of 4`; (b) a copy that appends the summary line to the ledger, then the AC 7 byte-identical check fails; (c) a copy of `read-postmortem.sh` that omits the new line, then the AC 2 tally case fails — each mutant gated on "the mutant differs from the original" (`! cmp`). Test: `test-postmortem-approach-baseline.sh`, `test-read-postmortem.sh`.
11. - [ ] **Prompt surfaces (prompt-surface arms):** Given the change, then `skills/pr-postmortem/SKILL.md` carries the H3 `### Optional \`approach_challenged\` flag (boolean, per round)` whose section opens with "**Not a 7th root-cause class.**", the Step 4 per-round token `approach_challenged=`, the `approach_challenges` counter in Step 5's builder list and in the trend-line schema table, and the field in Step 5's `CATEGORIES_JSON` shape; `commands/pr-postmortem.md` names `approach_challenged`; `docs/result-schemas/postmortem-result.md` documents both fields and still says `schema_version` is always `1`; and the SKILL's §"The 6 Root-Cause Classes" table (the lines from `## The 6 Root-Cause Classes` up to the next `### ` heading) is byte-identical to the base commit's — exactly six class rows, no definition changed (the arm compares that extracted block against a copy captured from base at test-authoring time and committed as a fixture string in the test; the new H3 and the Step 3 heuristic bullet may name a class such as `missing_context` without tripping it). Test: `test-postmortem-approach-baseline.sh`.
12. - [ ] **Schema docs consistent:** Given the change, when `bash loomwright/scripts/test-result-schemas-split.sh` runs, then it passes, and `docs/result-schemas/schema-versioning.md` carries a `POSTMORTEM_RESULT additive \`approach_challenged\` + \`approach_challenges\`` entry in its existing one-paragraph form saying no `schema_version` bump; the committed evidence file `docs/evidence/approach-baseline.md` records that grep, and the PR body links it. Test: that command + the evidence file.
13. - [ ] **Gates:** Given the change, when `bash scripts/check-token-budget.sh` runs, then it passes (re-baseline the `pr-postmortem` skill/command rows in `loomwright/docs/prompt-token-budgets.json` and their `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" mirror rows to measured + ~10% only if it trips); `bash scripts/check-prompt-history-refs.sh` passes with `loomwright/skills/pr-postmortem/SKILL.md` at ≤ 6 and `loomwright/commands/pr-postmortem.md` at ≤ 2 (the new H3 cites no PR number, item slug or version); `bash scripts/check-version-bump.sh` passes with `changelog.d/approach-baseline.md` present and NOT folded (no version bump in this PR — an unfolded fragment is legal, `changelog.d/README.md`; the bump's files are outside this item's Touches).
14. - [ ] **Running system — the baseline number (Validation 3):** Given the real `.supervisor/postmortem/results.jsonl`, when `bash loomwright/scripts/postmortem-approach-baseline.sh` runs from the repo root with `gh` available, then it prints one row per categorized round and a final `approach_challenged: N of M categorized rounds (guess; …)` line; and a committed evidence file `docs/evidence/approach-baseline.md` contains the command, that summary line, the date, `wc -l` of the ledger, the `build-floor.sh` re-grep (`grep -nE 'categories|self_heal_miss|approach_challenged' loomwright/scripts/build-floor.sh`) with its ACTUAL output pasted — at base it shows the per-round allowlist projection (`class`/`flow_stage`/`round`/`self_heal_miss`/`evidence`) and no `approach_challenged`; the file states that the new field is therefore absent from `build-floor.sh`'s `entries[]` exactly as `dismissed_then_raised` already is, and that `build-floor.sh` is unchanged as a requirement non-goal — and the column-0 line `Verdict: PASS for Validation 3`; the PR body links it.
15. - [ ] **Running system — the flag on a real postmortem (Validation 4):** Given a merged loomwright PR whose review asked for a different approach (picked from the AC 14 TSV), when the BRANCH's modified skill runs on it — from the worktree root, `claude -p --plugin-dir <worktree>/loomwright "/loomwright:pr-postmortem <that PR URL>"` (the `--plugin-dir` copy replaces the installed plugin, which lacks the flag; the namespaced command is required headless) — then its Step 4 report prints a per-round line carrying `approach_challenged=true` and appends one line with `approach_challenges: 1` to the WORKTREE's own `.supervisor/postmortem/results.jsonl` (gitignored, absent in a fresh worktree, so the run creates it and the live checkout's ledger is not touched), and `bash loomwright/scripts/read-postmortem.sh <a path that PR changed>`, run in the worktree, prints `- approach-challenged rounds: 1 of …`. The committed evidence file `docs/evidence/approach-baseline.md` contains the exact command (naming the `--plugin-dir` copy that ran), the PR, the per-round line, the appended ledger line, the reader line and the column-0 line `Verdict: PASS for Validation 4`; the PR body links it. If no such PR can be identified, or the headless run cannot be made, the file says so with `Verdict: BLOCKED for Validation 4` and the reason — never a fabricated PASS — and a BLOCKED Validation 4 leaves the PR NOT merge-ready: the PR body raises it to the owner as an open decision, never treated as passed.

**Evidence rule:** every running-system result lives in the committed `docs/evidence/approach-baseline.md` (Markdown, never `*.log`), never only in the PR body.

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

## File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| flag contract (prompt + schema docs) | `loomwright/skills/pr-postmortem/SKILL.md` (216), `loomwright/commands/pr-postmortem.md` (79), `loomwright/docs/result-schemas/postmortem-result.md` (259), `loomwright/docs/result-schemas/schema-versioning.md` (71) | — | HIGH |
| reader tally | `loomwright/scripts/read-postmortem.sh` (261), `loomwright/scripts/test-read-postmortem.sh` (218) | — | HIGH |
| baseline script | — | `loomwright/scripts/postmortem-approach-baseline.sh`, `loomwright/scripts/test-postmortem-approach-baseline.sh` | HIGH |
| budgets / release / evidence | `loomwright/docs/prompt-token-budgets.json` (93, only if `check-token-budget.sh` trips), `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (1066 — mirror-row edit only, conditional with the budget row; no new responsibility lands here) | `changelog.d/approach-baseline.md`, `docs/evidence/approach-baseline.md` | HIGH |

**Module layout** (`skills/supervisor-readiness/SKILL.md` §"Module layout"):
- New responsibility "estimate the flag over old ledger lines (phrase match + gather OR + TSV/summary)" → CREATE `loomwright/scripts/postmortem-approach-baseline.sh` (separate concern; never appended to `read-postmortem.sh`, which is a per-path advisory reader with a different output contract).
- New responsibility "tally `approach_challenged` per hit" → existing home `loomwright/scripts/read-postmortem.sh` (261, below threshold; the same jq aggregation that tallies `self_heal_miss`).
- Tests for the new script → CREATE `loomwright/scripts/test-postmortem-approach-baseline.sh`; reader tests stay in `test-read-postmortem.sh` (218).
- Only MODIFY path at/over the threshold: `ARCHITECTURE_CONTRACTS.md` (1066) — mirror-row edit only, the single authority's mirror table.
- **Copied helper — curation exclusion (recorded, not extracted):** the "skip `source:"curation"` records and data entries whose `automate_key`/`pr_url` a well-formed curation record targets" jq filter already exists inline in `read-postmortem.sh` and (partially) in `build-insights.sh` / `build-loop-evidence.sh`; there is no shared module to reuse. The source requirement asks for "the same exclusion `read-postmortem.sh` applies, reimplemented by reading, never by sourcing a writer". Reason for a third inline copy rather than an extract row: `read-postmortem.sh` is an executable reader with side effects (it `cd`s to the git root, writes `.supervisor/logs/memory.log`, prints advisory markdown), not a sourceable function, and extracting a shared lib would modify `build-insights.sh` / `build-loop-evidence.sh`, which are outside this item's `## Touches`. Drift is prevented mechanically, not by discipline: AC 8's **curation parity case** runs `read-postmortem.sh` and the baseline script over one curation fixture and asserts they exclude the same entries. A shared-lib extract is listed as a follow-up in Risk Assessment.

**Validator-owned surfaces:** `scripts/check-token-budget.sh` scans `loomwright/docs/prompt-token-budgets.json` + the `ARCHITECTURE_CONTRACTS.md` mirror rows (both already in the map); `scripts/check-prompt-history-refs.sh` scans `loomwright/docs/prompt-history-refs-baseline.json` (no change — counts may only go down); `scripts/check-test-hermetic.sh` scans every `loomwright/scripts/test-*.sh` (the new test must source the helper first); `scripts/check-doc-currency.sh` scans the doc surface (no count/version claim is added).

## Touched-file invariants

> Grounded at base `a2d959448b3cada018961fe5903c97745ea412b9`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/read-postmortem.sh`** — keep: always-exit-0 fail-safe (`set -uo pipefail   # \`set -e\` intentionally omitted`), the NO-HIT ⇒ empty-output contract (`if [ "$summary" = "EMPTY" ]; then`), jq-only parsing (`--rawfile / --slurpfile / --argjson only`), the curation presence discipline (`select(has("target_key") and ((.target_key | type) == "string") and (.target_key != ""))`); reuse: the hit-object idiom (`{overlap: $overlap, cats: (($e.categories) // []), shm: (($e.self_heal_misses) // 0)}`), the tab-delimited KEY/val summary and its `case "$key" in` parser (add one key, e.g. `APPR`), and `$rounds` (`([ $hits[].cats[]? ] | length) as $rounds`) as M; count N with `select(.approach_challenged == true)` — never `// empty` on the boolean (project memory: `.field // empty` collapses `false`); mirror: the reader line consumed advisory-only by Launch Pad action 0b and Supervisor Phase 4.5 `prior_churn` — the new line is printed only on a hit, after `printf '%s\n' "- any self_heal_miss in prior rounds: $churn_shm"` and before the attribution caveat; pinned by: `test-read-postmortem.sh` (`self_heal_miss in prior rounds: yes`, `prior churn rounds: 2`, `recurring root-cause classes: (none recorded)`), `test-curate-postmortem.sh` (`READ="$HERE/read-postmortem.sh"`), `test-automate-helpers.d/08-learning-emit.sh` F14–F19 (the `shr_ac1_holds` predicate; asserts through the REAL `read-postmortem.sh` output by content — `grep -qxF` / `grep -qE`, never line count).
- **`loomwright/scripts/test-read-postmortem.sh`** — keep: first executable line `. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"`, isolated `newrepo()` temp repos, `write_fixture` built with `jq -cn` (so add the flag to a NEW fixture entry or a dedicated fixture, never change existing entries' expected outputs), `pass`/`fail` counters with `RESULT: $pass passed, $fail failed`; reuse: `ok`/`no` helpers and the `grep -q … < <(echo "$out")` idiom.
- **`loomwright/skills/pr-postmortem/SKILL.md`** (prompt, pinned) — keep: the six class names exactly once each in the class table, the "**Not a 7th root-cause class.**" precedent wording, `flow_stage` attribution unchanged, Hard Invariant 2 (`no extra model/API calls`), Step 5's injection-safety (`every value flows through \`--arg\`/\`--argjson\``) — add `--argjson approach_challenges "$APPROACH_CHALLENGES"` and the `approach_challenges: $approach_challenges` key beside `self_heal_misses`; pinned by: `test-brief-conformance-seam.sh` (`grep -F 'Set \`self_heal_miss: true\`' "$POSTMORTEM"` — keep that sentence intact).
- **`loomwright/commands/pr-postmortem.md`** (prompt, pinned) — keep: the no-decline statement (`**it never declines and has no \`--force\` flag.**`) and add no `--force` / decline Parameters row; the step 3 class list `plan_gap | missing_context | convention_mismatch | execution_bug | quality_gap | scope_too_large` unchanged; pinned by: `test-curation-status.sh` section (k) (`/pr-postmortem's no-decline statement`, `never declines`); mirror: the SKILL Step 3 field list (name `approach_challenged` beside `self_heal_miss` and `dismissed_then_raised`).
- **`loomwright/docs/prompt-token-budgets.json` + `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets"** (conditional — only if `check-token-budget.sh` trips) — keep: the `{"budget": N, "measured": N, "note": "…"}` object shape of `"pr-postmortem": {"budget": 7015, "measured": 6377,` (skills) and `"pr-postmortem": {"budget": 2215, "measured": 2013,` (commands), and the 3-column mirror rows `| \`pr-postmortem\` | 7015 | 6377 |` / `| \`pr-postmortem\` | 2215 | 2013 |`; the JSON entry and its mirror row change together or not at all; pinned by: `scripts/check-token-budget.sh` (reads both, including the mirror-table sync).
- **`loomwright/docs/result-schemas/postmortem-result.md`** — keep: `- \`schema_version\` — integer, required, always \`1\`.`; mirror: the SKILL's Step 5 jq object and trend-line table (house rule: restated copies updated in the same change) — the example line, the `categories` field-contract object list and a new `approach_challenges` bullet beside `- \`self_heal_misses\` — integer; count of rounds flagged`.

## Closed enumerations touched

> Sibling grep at base `a2d9594`: `grep -rnF 'dismissed_then_raised' --exclude=CHANGELOG.md loomwright/ docs/ scripts/` → 9 hits in 2 files (`.git/rr-cache` and `.supervisor/` excluded). `grep -rlF 'self_heal_misses' --exclude=CHANGELOG.md loomwright/ docs/ scripts/` → 18 files.

- **`approach_challenged`** (sibling: `dismissed_then_raised`) — must be named in:
  - `loomwright/skills/pr-postmortem/SKILL.md` — Step 3 field list (`- the optional **\`dismissed_then_raised\`** boolean`), Step 5 `CATEGORIES_JSON` shape (`[{round, class, self_heal_miss, dismissed_then_raised, flow_stage, evidence}]`), trend-line table `categories` row — extend.
  - `loomwright/commands/pr-postmortem.md` — step 3 (`set the optional \`self_heal_miss\` and \`dismissed_then_raised\` flags`) — extend.
  - `loomwright/docs/result-schemas/postmortem-result.md` — field contract `{round, class, self_heal_miss, flow_stage, evidence}` (a restated list that already lacks `dismissed_then_raised`) — extend with `approach_challenged`; adding the missing `dismissed_then_raised` in the same edit is permitted (same list, same file, the house rule) but not required.
  - `loomwright/scripts/build-floor.sh` — found by the second sibling grep `grep -nF 'self_heal_miss' loomwright/scripts/build-floor.sh` (the `dismissed_then_raised` grep misses it because that key is absent there too): its per-round entry allowlist (`then {self_heal_miss: .c.self_heal_miss}` beside `class`/`flow_stage`/`round`/`evidence`) is a closed per-round key list — no change: requirement non-goal ("Changing … `build-floor.sh`"); the field is dropped from `build-floor.sh`'s `entries[]` exactly as `dismissed_then_raised` already is, and AC 14's evidence file records this.
- **`approach_challenges`** (sibling: `self_heal_misses`) — must be named in:
  - `loomwright/skills/pr-postmortem/SKILL.md` — Step 5 jq object, builder list (`- \`SELF_HEAL_MISSES\` — integer count`), trend-line table — extend.
  - `loomwright/docs/result-schemas/postmortem-result.md` — example line and field contract — extend.
  - `loomwright/docs/result-schemas/schema-versioning.md` — one additive entry — extend.
  - `loomwright/scripts/automate-helpers.d/learning.sh` (second ledger writer, `automate_drain` lines), `measure-heal-signal.py`, `build-reviewer-replay-case.sh`, `build-loop-evidence.sh`, `harvest-conventions` / replay tests, `docs/RULES_BASELINE.md`, `docs/SPIKES/*`, `docs/evidence/phase45-reviewer-replay.md` — no change: none is a closed key set that must name every ledger field; they read named fields with `// 0` defaults, an absent counter reads as 0, and the requirement's non-goals exclude other writers/readers.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-read-postmortem.sh` — `approach-challenged rounds: 1 of 3 prior rounds` | delete `"- approach-challenged rounds: ` in `loomwright/scripts/read-postmortem.sh` |
| `loomwright/scripts/test-read-postmortem.sh` — new line follows the `self_heal_miss` line | move the new `printf` above the `- any self_heal_miss in prior rounds:` printf in `loomwright/scripts/read-postmortem.sh` (reviewer-applied) |
| `loomwright/scripts/test-postmortem-approach-baseline.sh` — AC 4 rows 1 and 3 `true` | flip `"why not"` → `"zz-no-match"` in `loomwright/scripts/postmortem-approach-baseline.sh` (the phrase array must hold the only `"why not"` literal) |
| `loomwright/scripts/test-postmortem-approach-baseline.sh` — AC 5 `recorded:false` | make the script ignore a present `approach_challenged` key (always guess) in `loomwright/scripts/postmortem-approach-baseline.sh` (reviewer-applied) |
| `loomwright/scripts/test-postmortem-approach-baseline.sh` — AC 8 absent-ledger summary | flip `ledger unreadable` → `ledger unreadablX` in `loomwright/scripts/postmortem-approach-baseline.sh` |
| `loomwright/scripts/test-postmortem-approach-baseline.sh` — AC 8 curation exclusion | drop the curated-target `select(... | not)` from the baseline script's jq (reviewer-applied) |
| `loomwright/scripts/test-postmortem-approach-baseline.sh` — AC 9 tab→space | remove the tab/newline replacement from the snippet column in `loomwright/scripts/postmortem-approach-baseline.sh` (reviewer-applied) |
| `loomwright/scripts/test-read-postmortem.sh` — AC 2 `0 of 3 prior rounds` (unflagged ledger) | count every round as flagged (drop the `== true` test from the N tally) in `loomwright/scripts/read-postmortem.sh` (reviewer-applied) |
| `loomwright/scripts/test-read-postmortem.sh` — AC 2 no-hit ⇒ empty output | move the new `printf` above the `if [ "$summary" = "EMPTY" ]; then` guard in `loomwright/scripts/read-postmortem.sh` (reviewer-applied) |
| `loomwright/scripts/test-postmortem-approach-baseline.sh` — AC 1 Step 5 execution arm (`approach_challenges: 1`) | delete `approach_challenges: $approach_challenges` in `loomwright/skills/pr-postmortem/SKILL.md` |
| `loomwright/scripts/test-postmortem-approach-baseline.sh` — AC 6 gather OR (`true`, `1 gathered`) | drop the gather-snippet OR so only `evidence` is matched in `loomwright/scripts/postmortem-approach-baseline.sh` (reviewer-applied) |
| `loomwright/scripts/test-postmortem-approach-baseline.sh` — AC 8 malformed line skipped | parse the ledger with `jq -s .` instead of the per-line `fromjson?` in `loomwright/scripts/postmortem-approach-baseline.sh` (reviewer-applied) |
| `loomwright/scripts/test-postmortem-approach-baseline.sh` — AC 8 jq absent ⇒ empty stdout, exit 0 | delete the `command -v jq` guard's `exit 0` in `loomwright/scripts/postmortem-approach-baseline.sh` (reviewer-applied) |
| `loomwright/scripts/test-postmortem-approach-baseline.sh` — AC 8 curation parity | treat a malformed `target_key` as a target (drop the `has("target_key")` presence check) in `loomwright/scripts/postmortem-approach-baseline.sh` (reviewer-applied) |
| `loomwright/scripts/test-postmortem-approach-baseline.sh` — AC 9 no marker file | build the summary/row with `eval` / an interpolated `printf "$evidence"` in `loomwright/scripts/postmortem-approach-baseline.sh` (reviewer-applied) |
| `loomwright/scripts/test-postmortem-approach-baseline.sh` — AC 11 H3 arm | delete `### Optional \`approach_challenged\` flag` in `loomwright/skills/pr-postmortem/SKILL.md` |
| `loomwright/scripts/test-postmortem-approach-baseline.sh` — AC 11 Step 4 token arm | delete `approach_challenged=<bool>` in `loomwright/skills/pr-postmortem/SKILL.md` |
| `loomwright/scripts/test-postmortem-approach-baseline.sh` — AC 11 command arm | flip `approach_challenged` → `approach_challengeX` in `loomwright/commands/pr-postmortem.md` |
| `loomwright/scripts/test-postmortem-approach-baseline.sh` — AC 11 schema-doc arm | delete the `approach_challenges` field-contract bullet in `loomwright/docs/result-schemas/postmortem-result.md` (reviewer-applied) |
| `loomwright/scripts/test-postmortem-approach-baseline.sh` — AC 11 class-table byte-identity arm | flip `` | `scope_too_large` | `` → `` | `scope_too_largeX` | `` in `loomwright/skills/pr-postmortem/SKILL.md` (any one-byte change inside the class table turns the byte-identity compare red) |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | approach_challenged flag, reader tally, read-only baseline script + evidence | all | 8 modify, 4 create | `skills/pr-postmortem/SKILL.md`, `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/skills/pr-postmortem/SKILL.md", name: "Optional `approach_challenged` flag (boolean, per round)"}
  - {kind: "symbol", path: "loomwright/skills/pr-postmortem/SKILL.md", name: "approach_challenges"}
  - {kind: "symbol", path: "loomwright/commands/pr-postmortem.md", name: "approach_challenged"}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/postmortem-result.md", name: "approach_challenges"}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/schema-versioning.md", name: "approach_challenged"}
  - {kind: "symbol", path: "loomwright/scripts/read-postmortem.sh", name: "approach-challenged rounds"}
  - {kind: "file", path: "loomwright/scripts/postmortem-approach-baseline.sh"}
  - {kind: "file", path: "loomwright/scripts/test-postmortem-approach-baseline.sh"}
  - {kind: "file", path: "changelog.d/approach-baseline.md"}
  - {kind: "file", path: "docs/evidence/approach-baseline.md"}
  - {kind: "symbol", path: "docs/evidence/approach-baseline.md", name: "Verdict: PASS for Validation 3"}
requires: []
lanes:
  - "loomwright/skills/pr-postmortem/SKILL.md"
  - "loomwright/commands/pr-postmortem.md"
  - "loomwright/docs/result-schemas/postmortem-result.md"
  - "loomwright/docs/result-schemas/schema-versioning.md"
  - "loomwright/scripts/read-postmortem.sh"
  - "loomwright/scripts/test-read-postmortem.sh"
  - "loomwright/scripts/postmortem-approach-baseline.sh"
  - "loomwright/scripts/test-postmortem-approach-baseline.sh"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "docs/evidence/approach-baseline.md"
  - "changelog.d/approach-baseline.md"
external_requires:
  - "jq (already required by every ledger reader)"
  - "gh CLI authenticated for the AC 14 real-ledger gather run (the script degrades to gather-unavailable without it)"
```

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/pr-postmortem/SKILL.md` (the contract being extended), `skills/quality-checklist/SKILL.md` (Self-Heal Miss-Class Checklist precedent), `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Requirement premise stale: `build-floor.sh` does read the churn ledger — a class distribution and a per-round allowlist projection that includes `self_heal_miss` (source: Feasibility (Phase 2.5)) | LOW | The allowlist already omits `dismissed_then_raised`; `approach_challenged` is dropped from its `entries[]` the same way. `build-floor.sh` stays unchanged (requirement non-goal); AC 14's evidence file pastes the actual re-grep output instead of the requirement's "nothing postmortem-shaped" claim |
| Validation 4 run evidence comes from the wrong skill copy (the installed plugin lacks the flag) or pollutes the live ledger | MEDIUM | AC 15 pins the mechanism: `claude -p --plugin-dir <worktree>/loomwright "/loomwright:pr-postmortem …"` from the worktree root, so the branch's SKILL runs and the append lands in the worktree's own gitignored ledger; the evidence file names the copy that ran. Any line that does reach the live append-only ledger is permanent by design and is curated only via `curate-postmortem.sh` |
| The phrase heuristic over/under-counts ("why not null-check here?" is a correctness question) | MEDIUM | The TSV carries the snippet per round; the number is a labelled `guess` baseline, never a gate; the evidence file may record a hand-corrected figure beside the raw one |
| A real-ledger gather over ~230 PRs is slow and rate-limited | MEDIUM | `--no-gh` evidence-only pass exists; summary reports `gathered` / `gather-unavailable` so coverage is stated; evidence file names the mode that produced the number |
| A third inline copy of the curation-exclusion jq filter can drift from `read-postmortem.sh` | MEDIUM | AC 8's curation parity case runs both scripts over one fixture (retract by `pr_url`, by `automate_key`, malformed `target_key`) and asserts identical exclusion; a shared-lib extract (touching `build-insights.sh` / `build-loop-evidence.sh`) is a follow-up outside this item's Touches |
| `.approach_challenged // false`-style falsy coercion or `set -u` on an empty bash array (macOS bash 3.2) breaks the tally or the phrase loop | MEDIUM | Count with `select(.approach_challenged == true)`; keep the phrase list as a jq `--argjson` array (no bash array expansion under `set -u`); test `PATH`-without-jq and empty-ledger cases |
| Gather call log includes `gh api user` (the gather's operator-login read) — the requirement's AC said "only pr view / api … comments" | LOW | AC 7 is written as "read calls only" and names `api user` explicitly; any mutating verb fails the case |
| New reader line breaks a consumer pinning line count | LOW | All known pins match by content (`test-read-postmortem.sh`, `test-curate-postmortem.sh`, `test-automate-helpers.sh` F14–F19); the line is appended after the `self_heal_miss` line and never replaces one |
| Prompt growth trips `check-token-budget.sh` (skill headroom ~638 proxy tokens) | LOW | Re-baseline the `pr-postmortem` skill/command rows + mirror rows to measured + ~10% only if the gate trips (AC 13) |
| Validation 4 needs a real merged PR whose review asked for a different approach; one may not be identifiable | MEDIUM | AC 15 allows a recorded `BLOCKED` verdict with the reason; never a fabricated PASS |
| Owner decision on the source requirement reads "Not approved to build — requirements only" (2026-11-10), and `00-overview.md` says "Not run here: nothing is approved" beside the `/automate --folder .supervisor/requirements/approach-decisions` command it hands the owner | LOW | The build go is the owner running that command: run file `.supervisor/automate/automate-2026-11-11-173032.md` (`# Automate Run: approach-decisions (01, 02)`, `- folder .supervisor/requirements/approach-decisions`, mode `safe`, no `--auto-merge`) picked this item at `2026-11-11T12:00:56Z`. Safe mode never merges — the owner merges the PR, so the final consent stays with the owner |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-11-approach-challenged-postmortem-baseline.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-11-11T14:36:00Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/891
- **Branch:** feature/approach-challenged-postmortem-baseline
- **Files changed:** 12
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** armed
- **Summary:** approach_challenged per-round flag + approach_challenges counter (schema stays 1), read-postmortem.sh tally line, read-only postmortem-approach-baseline.sh with a 74-case hermetic suite. Validation 3 PASS (0 of 423 guessed, limits documented). Validation 4 recorded PASS on hand-picked PR #440 (round 4 approach_challenged=true, approach_challenges: 1, reader "1 of 6") after self-heal added the mixed-round rule and the literal Step 4 line format; the substitution outside the AC 14 TSV is an open owner decision. The final heal iteration's evidence-wording fix (f6d59d6) was not re-reviewed.

## Not verified
- **/pr-postmortem recording approach_challenged=true on a TSV-picked PR (AC 15 literal path)** — the AC 14 TSV had 0 true rows; true was recorded on hand-picked PR #440 under the mixed-round rule; owner decision open (subtask 1)
- **postmortem_classifier routed seat on a non-Claude provider** — out of scope per the requirement; a missing flag reads as false (subtask 1)
