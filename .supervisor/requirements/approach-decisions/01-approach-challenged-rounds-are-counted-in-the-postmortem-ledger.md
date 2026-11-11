# Approach-challenged rounds are counted in the postmortem ledger

## Status: done
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/891

Source: the approach-decisions gap analysis against main `8ec200e` / v17.35.1 (2026-11-10, owner Vikash: "Yes, write it" — approves writing, not building). Sibling of `02-briefs-record-the-chosen-approach-and-the-alternatives-it-beat.md` in this folder; index in `00-overview.md`. This story is the BASELINE the owner's rule requires before story `02` may be queued ("no item without a baseline").

**As the** owner (Vikash), reading `/pr-postmortem` reports and the churn ledger to decide where the pipeline loses review rounds,
**I want** every categorized review round to carry a per-round boolean `approach_challenged` — true when the reviewer questioned the chosen approach, library or tool rather than the code's correctness — tallied by the existing readers, plus a one-shot read-only script that estimates the same flag over the 232 records already in the ledger,
**so that** approach-caused rework has a measured rate before and after story `02` ships, instead of being filed invisibly under `missing_context` or `plan_gap`.

### Problem (read on main `8ec200e`)

- **The six classes have no approach bucket.** `skills/pr-postmortem/SKILL.md` §"The 6 Root-Cause Classes" (lines 27–38) defines `plan_gap`, `missing_context`, `convention_mismatch`, `execution_bug`, `quality_gap`, `scope_too_large`. A reviewer saying "why not use X" or "the platform already provides this" matches `missing_context` ("we already have X" / "this duplicates Y") or `plan_gap` ("missing intent") by the Step 3 heuristics (lines 100–108), so a round caused by a wrong approach is indistinguishable from one caused by an unseen helper.
- **The per-round boolean precedent is explicit and says "not a 7th class".** §"Optional `dismissed_then_raised` flag" (line 44–46): "**Not a 7th root-cause class.** `categories[]`'s `class` field has NO closed JSON-schema enum … so this signal is an ADDITIVE PER-ROUND BOOLEAN, mirroring `self_heal_miss` exactly, never a new string value for `class`." Step 5 (line 163) builds `CATEGORIES_JSON` as `[{round, class, self_heal_miss, dismissed_then_raised, flow_stage, evidence}]` with `dismissed_then_raised` "`false` on every round where the check did not trigger, never omitted".
- **The schema is additive at `schema_version: 1`.** `docs/result-schemas/postmortem-result.md`: the example line 28 shows `categories: [{"round": 1, "class": "quality_gap", "self_heal_miss": true, "flow_stage": "self_heal", "evidence": …}]`; line 29 `"self_heal_misses": 3`; the field contract (lines 59–66) documents `categories` as per-round objects and `self_heal_misses` as "count of rounds flagged `self_heal_miss`". `docs/result-schemas/schema-versioning.md` records every prior additive optional field as "no `schema_version` bump" (e.g. line 13 `CODE_REVIEW_RESULT additive cannot_determine`, line 14 `house_rule_verdicts`).
- **The reader already tallies `self_heal_miss`.** `scripts/read-postmortem.sh` line 183 collects `shm: (($e.self_heal_misses) // 0)`, lines 199–201 compute `$any_shm` from `categories[].self_heal_miss` or the counter, line 255 prints `- any self_heal_miss in prior rounds: …`. `test-read-postmortem.sh` line 79 pins that output line (`self_heal_miss in prior rounds: yes`). No line tallies anything approach-shaped.
- **The gather already carries the evidence.** `scripts/pr-postmortem-gather.sh` header line 17 documents `"review_comments": [{"author": "...", "snippet": "..."}]`; its `def snippet` (lines 340–348) strips control characters, collapses whitespace and caps at 200 characters — the text a heuristic phrase match needs is already produced, read-only, from `gh`.
- **The ledger has 232 records and no approach signal.** `wc -l .supervisor/postmortem/results.jsonl` = 232 (2026-11-10). Its sole data writer is `/pr-postmortem` Step 5's jq-built append; its sole curator is `curate-postmortem.sh` (header: "the SOLE CURATOR WRITER … Append-only … NEVER rewrite, edit, or remove an existing ledger line"). Nothing may rewrite old records to add the flag.
- **`build-floor.sh` does not read `categories[]`.** Its only `classified` symbol (lines 318–360) is its own session-log classification; grep for `self_heal`/`categories` on 2026-11-10 returned nothing postmortem-shaped, so it needs no change (confirmed in Scope, re-checked at implementation).
- **`/insights` does not read the churn ledger's per-round flags.** `build-insights.sh` reads `.supervisor/heal-signal/results.jsonl` (line 388, written by `measure-heal-signal.sh`) and only counts the churn ledger's lines for curation (line 1088). The per-path reader is `read-postmortem.sh`; that is where a new line belongs (PO default below).

### Scope

**Part 1: the flag, its counter, the readers.**
- `docs/result-schemas/postmortem-result.md`: `categories[]` entries gain an OPTIONAL boolean `approach_challenged` (same shape and optionality as `self_heal_miss` and `dismissed_then_raised`; absent in pre-existing lines, which stay valid); a top-level integer `approach_challenges` — the count of rounds flagged `approach_challenged`, mirroring `self_heal_misses`; the example line and the field contract updated; `schema_version` stays `1`. `docs/result-schemas/schema-versioning.md` gains the additive entry in its existing one-paragraph form.
- `skills/pr-postmortem/SKILL.md`: a new H3 `### Optional `approach_challenged` flag (boolean, per round)` beside `dismissed_then_raised`, opening with the same "**Not a 7th root-cause class.**" sentence and the mirror rule. Definition: set `true` when the round's evidence questions the chosen approach, library, tool or mechanism rather than the code's correctness — the reviewer proposes a different way, not a fix (phrases: "why not", "use X instead", "already provides", "simpler to", "reinvent", "the platform / SDK / library / harness already"). The `class` is UNCHANGED (one of the six, by the finding's own language; typically `missing_context` or `plan_gap`) and `flow_stage` is unchanged (typically `launch_pad`, where the approach was chosen). Default `false` when unsure; `false` on every round where the check did not trigger, never omitted. Step 3 gains the one-sentence rule and one heuristic bullet; Step 4's per-round line gains `approach_challenged=<bool>`; Step 5's `CATEGORIES_JSON` shape and the jq append gain the field and the `approach_challenges` counter; the §"POSTMORTEM_RESULT trend-line schema" table gains both rows.
- `commands/pr-postmortem.md` step 3 (line 34) names the third optional flag beside `self_heal_miss` and `dismissed_then_raised`.
- `scripts/read-postmortem.sh`: the jq query collects `approach_challenged` the way it collects `self_heal_miss` (lines 183, 199–201), and the output gains ONE line after line 255's `self_heal_miss` line: `- approach-challenged rounds: N of M prior rounds` (N over `categories[]` entries with the flag true, M the existing `$rounds`), `0 of M` when no entry carries the flag — never omitted when hits exist, so a consumer can tell "none flagged" from "reader predates the flag". `test-read-postmortem.sh` gains a fixture entry with the flag and pins the line.
- `build-floor.sh`: unchanged (verified above); the implementer re-greps `categories\|self_heal_miss\|approach_challenged` in it and records the result in the PR body's evidence file.

**Part 2: the one-shot baseline script (read-only, heuristic, never writes).**
- New `loomwright/scripts/postmortem-approach-baseline.sh [--ledger <path>] [--fixture <dir>] [--no-gh]`: re-reads every data line of the ledger (skipping curation records and lines a well-formed curation record retracts or supersedes — the same exclusion `read-postmortem.sh` applies, reimplemented by reading, never by sourcing a writer), and for each categorized round prints one TSV row `pr\tround\tclass\tapproach_challenged_guess\tsnippet` where `approach_challenged_guess` is `true|false|recorded:true|recorded:false` — `recorded:` when the entry already carries the flag (post-Part-1 lines), a phrase-match GUESS otherwise. The phrase list is ONE array near the top of the script (the Part 1 phrases), case-insensitive, matched against the round's `evidence` string; when `gh` is usable and `--no-gh` is absent, the script additionally runs `pr-postmortem-gather.sh` on the entry's `pr_url` and matches the SAME phrases against that PR's `review_comments[].snippet`, taking the OR. Last line on stdout: `approach_challenged: N of M categorized rounds (guess; E entries, G gathered, U gather-unavailable)`.
- Writes nothing: no ledger write, no file write, no `gh` mutation (only `pr-postmortem-gather.sh`'s read path). The script's header states the sole-writer contract (`/pr-postmortem` emit; curation via `curate-postmortem.sh`) and that `guess` is never copied into the ledger.
- Fail-safe reader: always exit 0; unreadable or absent ledger ⇒ empty rows, the summary line `approach_challenged: 0 of 0 categorized rounds (ledger unreadable: <reason>)`, reason on stderr; a malformed JSONL line is skipped element-locally; `jq` absent ⇒ nothing on stdout, reason on stderr, exit 0. jq-only parsing: evidence and snippet text is never string-interpolated into a shell command or a jq program (`--rawfile` / `--arg` / `--argjson` only, the `read-postmortem.sh` discipline). Snippets are printed with tabs and newlines replaced by spaces so the TSV stays one row per round.
- `--fixture <dir>`: the ledger is `<dir>/results.jsonl` and the gather is served by a PATH-stubbed `gh` the test places first on PATH (`test-pr-postmortem-gather.sh`'s stub pattern — serves `gh pr view … --json` and `gh api …/comments` from fixture files; `test-automate-lanes.sh`'s stub, by contrast, fails the test if called, which is the right stub for the `--no-gh` arm).
- New hermetic `loomwright/scripts/test-postmortem-approach-baseline.sh` (fixtures under `mktemp -d`; no network, `scripts/check-test-hermetic.sh` passes).

**Part 3: docs, budgets, fragment, evidence.**
- `loomwright/docs/prompt-token-budgets.json` `.skills["pr-postmortem"]` (measured 6377 / budget 7015) and `.commands["pr-postmortem"]` (2013 / 2215) re-measured; raised to measured + ~10% only if `check-token-budget.sh` trips; the ARCHITECTURE_CONTRACTS.md §"Prompt Token Budgets" mirror rows (lines 732 and the commands table) updated in the same change.
- `changelog.d/approach-baseline.md`.
- `docs/evidence/approach-baseline.md` (repo root `docs/evidence/`, the existing convention — e.g. `docs/evidence/af39a-sweep.md`): the baseline script's summary line over the real ledger, the command, the date, the ledger line count, and the `build-floor.sh` grep result; the PR body links it (Plan Reviewer Criterion 20: evidence lives in the diff, never only in the PR body).

## Acceptance Criteria

Every script case runs in a `mktemp -d` fixture dir with its own `results.jsonl`; no network; `gh` is a PATH stub (`scripts/check-test-hermetic.sh` passes).

- [ ] **Flag and counter are additive, schema stays 1:** a `/pr-postmortem` line with `approach_challenged: true` on one of three rounds carries `approach_challenges: 1` and `schema_version: 1`; a pre-existing line without the field is read by `read-postmortem.sh` exactly as today (`test-read-postmortem.sh`'s existing cases pass unchanged). Test: `loomwright/scripts/test-read-postmortem.sh`.
- [ ] **Reader tallies the flag:** a fixture ledger whose hit entries hold 3 categorized rounds, 1 flagged ⇒ the output carries `- approach-challenged rounds: 1 of 3 prior rounds`; the same ledger with no flag on any round ⇒ `- approach-challenged rounds: 0 of 3 prior rounds`; a ledger with no hits ⇒ no such line (the reader is quiet, as today). Test: `test-read-postmortem.sh`.
- [ ] **Reader output order and existing lines unchanged:** every existing pinned line (`prior churn rounds:`, `any self_heal_miss in prior rounds:`, the attribution caveat) still appears, and the new line sits after the `self_heal_miss` line. Test: `test-read-postmortem.sh`.
- [ ] **Baseline script: phrase match on `evidence`:** a fixture ledger with 4 categorized rounds whose `evidence` strings are "why not use the SDK's retry here", "off-by-one in the loop", "the harness already provides a lock — reinventing it", "missing test for the empty case" ⇒ rows 1 and 3 print `approach_challenged_guess=true`, rows 2 and 4 `false`; summary `approach_challenged: 2 of 4 categorized rounds (guess; 1 entries, 0 gathered, 1 gather-unavailable)` under `--no-gh`. Test: `loomwright/scripts/test-postmortem-approach-baseline.sh`.
- [ ] **Baseline script: recorded flag wins over the guess:** an entry already carrying `approach_challenged: false` on a round whose evidence says "why not" prints `recorded:false` and is counted as recorded, not guessed. Test: `test-postmortem-approach-baseline.sh`.
- [ ] **Baseline script: gather OR:** with the PATH-stubbed `gh` serving a PR whose `review_comments[].snippet` contains "simpler to use the platform's queue" and an entry whose round evidence is "null check", the row prints `true` and the summary counts `1 gathered`. Test: `test-postmortem-approach-baseline.sh`.
- [ ] **Baseline script never writes:** before and after every case the fixture `results.jsonl` is byte-identical (`cmp`), no file is created under the fixture dir, and the `gh` stub's call log shows only `pr view` / `api … comments` reads. Test: `test-postmortem-approach-baseline.sh`.
- [ ] **Baseline script is fail-safe:** absent ledger ⇒ exit 0, no rows, summary `approach_challenged: 0 of 0 categorized rounds (ledger unreadable: absent)`, reason on stderr; a ledger with one malformed line among valid ones ⇒ the valid rounds are printed and the malformed line is skipped; a curation-retracted entry is excluded; `PATH` without `jq` ⇒ empty stdout, exit 0, reason on stderr. Test: `test-postmortem-approach-baseline.sh`.
- [ ] **No injection through evidence text:** an `evidence` string containing `$(touch <marker>)`, backticks and a tab ⇒ no marker is created and the row's snippet column holds the text with the tab replaced by a space. Test: `test-postmortem-approach-baseline.sh`.
- [ ] **Mutants each fail a case:** (a) a copy of the baseline script with the phrase array emptied prints `0 of 4`; (b) a copy that writes the summary line into the ledger fails the byte-identical check; (c) a copy of `read-postmortem.sh` that omits the new line fails the tally case. Each gated on "the mutant differs from the original". Test: `test-postmortem-approach-baseline.sh`, `test-read-postmortem.sh`.
- [ ] **Prompt surfaces (prompt-surface arms):** `skills/pr-postmortem/SKILL.md` carries the H3 `Optional `approach_challenged` flag`, the sentence "Not a 7th root-cause class", the Step 4 per-round token `approach_challenged=`, the `approach_challenges` counter in Step 5 and in the trend-line schema table; `commands/pr-postmortem.md` names `approach_challenged`; `docs/result-schemas/postmortem-result.md` documents both fields and still says `schema_version` is always `1`; the six class names are unchanged (`grep -c` of each = today's count). Test: `test-postmortem-approach-baseline.sh`.
- [ ] **Schema docs consistent:** `bash loomwright/scripts/test-result-schemas-split.sh` passes; `docs/result-schemas/schema-versioning.md` carries the additive entry. Test: that command plus a grep in the PR body's evidence file.
- [ ] **Gates:** `bash scripts/check-token-budget.sh` passes (re-baseline `pr-postmortem` skill/command rows + mirror rows only if it trips); `bash scripts/check-prompt-history-refs.sh` passes with `loomwright/skills/pr-postmortem/SKILL.md` at ≤ 6 and `loomwright/commands/pr-postmortem.md` at ≤ 2 (the baseline may only go down — the new H3 cites no PR number or version); `bash scripts/check-version-bump.sh` passes with `changelog.d/approach-baseline.md`.

## Non-goals
- Changing any of the six class definitions, adding a seventh class, or changing `flow_stage` attribution.
- Auto-curating, rewriting or back-filling old ledger records: the guess is printed, never written (the ledger's writers stay `/pr-postmortem` emit and `curate-postmortem.sh`).
- Any gate, merge condition, heal-decision input or scorecard row reading the flag (the flag is a ledger signal; story `02` reads its rate by hand through `read-postmortem.sh` and the baseline script).
- A `/insights` section (its heal-signal section reads a different ledger; the reader line is the consumer in v1 — PO default below).
- Changing `pr-postmortem-gather.sh`, `measure-heal-signal.sh`, `build-floor.sh` or `curate-postmortem.sh`.
- The `postmortem_classifier` routed seat (Step 3 "Seat routing"): the flag rides in `categories[]` like the other two booleans; a non-Claude provider's prompt is out of scope.

## Owner decisions
- 2026-11-10 (Vikash): **Not approved to build — requirements only.** "Yes, write it" approves writing this story, not building it.
- 2026-11-10 (Vikash, the gap brief): approach-caused rework must have a baseline before any approach item is queued; this story IS the baseline; the flag is a per-round boolean mirroring `self_heal_miss`, NOT a seventh class; the baseline script is one-shot, read-only, heuristic, prints `guess`, never writes back; the running-system proof is the script run over the real ledger with the number recorded.
- PO default, pending owner review (**where the number is recorded**): the owner's brief says "record the number in the PR body"; the brief template's evidence rule (`skills/supervisor-readiness/SKILL.md` line 161; Plan Reviewer Criterion 20) fails a criterion whose only evidence is the PR body. Default: a committed `docs/evidence/approach-baseline.md` that the PR body links — the number is in the diff AND the body.
- PO default, pending owner review (**which reader gains the line**): `read-postmortem.sh`, not `/insights` — `build-insights.sh` never reads `categories[]` (it reads the heal-signal ledger and counts churn lines for curation), so a `/insights` line would need a new section and a new reader; the per-path reader already tallies `self_heal_miss` at the same spot. Alternative the owner may prefer: a one-line `approach-challenged rounds` row in `/insights`' curation snapshot (lines 1045–1090 of `build-insights.sh`), a second, bounded change.
- PO default, pending owner review (**guess vs recorded**): rows for post-Part-1 entries print `recorded:<bool>` and are counted separately from guessed rows, so the "before" and "after" rates in story `02`'s revisit-when are never mixed in one number.
- PO default, pending owner review (**`--no-gh` and reproducibility**): the gather is reproducible only for PRs `gh` can still read; the summary line reports `gathered` / `gather-unavailable` counts so the baseline states its own coverage. The committed evidence file records the run with `gh` available.
- PO default, pending owner review (**the phrase list**): the Part 1 phrases are the whole heuristic, kept in ONE array in the script and restated in the skill's flag definition as the human rule; no NLP, no model call (the script is a reader, Hard Invariant 2 of the skill — "no extra model/API calls").

## Priority: MVP
**Rationale:** the owner's standing rule — no item without a baseline — makes this story the precondition for `02`; it is small (one boolean, one counter, one reader line, one read-only script) and changes no behaviour of any gate.

## Assumptions
- right-size (run 2026-11-10, `bash loomwright/scripts/automate-helpers.sh right-size <file>`, defaults small ≤ 3 / large > 30): `approach-decisions/01-approach-challenged-rounds-are-counted-in-the-postmortem-ledger: ok (12 files, 13 scope items, 13 criteria)`.
- `read-postmortem.sh`'s jq program reads `categories[]` entries as objects with optional keys (`.self_heal_miss` is read with `any(. == true)` at line 199), so an added optional boolean needs no schema change in the reader beyond the new tally.
- `test-read-postmortem.sh` builds its fixture ledger with jq (line 41) and pins output lines by `grep -q` (lines 74–81); a new fixture field and one new pinned line fit that style.
- `pr-postmortem-gather.sh` can be invoked by a sibling script with `gh` resolved from PATH, as `test-pr-postmortem-gather.sh` does (`PATH="$BIN:$PATH" bash "$GATHER" …`, line 572).
- The `postmortem_classifier` seat (Step 3 "Seat routing") returns `categories[]` from a routed provider; whether that provider's prompt mentions the new flag is NOT in scope — a missing flag reads as `false` (default), which is correct.
- `check-prompt-history-refs.sh` counts PR numbers / version strings; the new H3 names neither (it names `self_heal_miss` and `dismissed_then_raised` as siblings, which carry no history token — to be confirmed by running the gate).
- Shared files with the sibling story `02`: `loomwright/docs/prompt-token-budgets.json` and `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (budget rows only; different rows). A sequential `--folder` run serialises them.
- Unverified (recorded, not asserted): whether `build-floor.sh` reads the churn ledger through any path other than the two greps run on 2026-11-10 (`self_heal|categories|class` and `postmortem`); the implementer re-checks before declaring it unchanged.

## Dependencies
- Depends on: none — `read-postmortem.sh`, `pr-postmortem-gather.sh`, `curate-postmortem.sh`, `test-read-postmortem.sh`, `test-pr-postmortem-gather.sh` all exist on main.
- Blocks: `02-briefs-record-the-chosen-approach-and-the-alternatives-it-beat.md` by owner rule (the baseline must exist), not by a file dependency; `02`'s `## Depends on` says `none` and the overview orders it second.

## Risks
- **The heuristic over- or under-counts.** "why not" also opens ordinary correctness questions ("why not null-check here?"). Mitigation: the row carries the snippet, so a human can read the 232-record TSV and correct the number by hand in the evidence file; the number is a baseline, not a gate.
- **Old records cannot carry the flag.** Intentional (append-only ledger); the guess column is the bridge, and `recorded:` rows are counted apart.
- **A gather over 232 PRs is slow and rate-limited.** Mitigation: `--no-gh` for the evidence-only pass; the summary names how many entries were gathered; the committed evidence file records which mode produced the number.
- **A new reader line could break a consumer that pins the reader's line count.** `test-read-postmortem.sh` pins by content, not count (lines 74–81); Launch Pad action 0b consumes the output as advisory prose. Mitigation: the line is appended after the `self_heal_miss` line and never replaces one.
- **Prompt growth.** The skill has 638 proxy tokens of headroom; the H3 is ~10 lines. Re-baseline only if the gate trips.

## Validation (must pass before merge)
1. **Static — reader and baseline suites:** `bash loomwright/scripts/test-read-postmortem.sh` and `bash loomwright/scripts/test-postmortem-approach-baseline.sh` pass, including the three mutants, the byte-identical ledger check, the injection case, the fail-safe cases and the prompt-surface arms.
2. **Static — repo gates:** `bash scripts/ci-local.sh --affected` passes (including `check-test-hermetic.sh`, `check-token-budget.sh`, `check-prompt-history-refs.sh`, `test-result-schemas-split.sh`); `bash scripts/check-version-bump.sh` passes with `changelog.d/approach-baseline.md`.
3. **Running system — the baseline number:** `bash loomwright/scripts/postmortem-approach-baseline.sh` run from the repo root over the real `.supervisor/postmortem/results.jsonl` (232 lines on 2026-11-10; `gh` available) prints one row per categorized round and a final `approach_challenged: N of M categorized rounds (guess; …)` line; the command, the line, the date and `wc -l` of the ledger are committed in `docs/evidence/approach-baseline.md` with the declared line `Verdict: PASS for Validation 3`, and the PR body links it. This number is the baseline story `02` cites.
4. **Running system — the flag on a real postmortem:** `/pr-postmortem <a merged loomwright PR whose review asked for a different approach>` prints a Step 4 per-round line carrying `approach_challenged=true` and appends one ledger line with `approach_challenges: 1`; `bash loomwright/scripts/read-postmortem.sh <a path that PR changed>` then prints `- approach-challenged rounds: 1 of …`. The PR, the per-round line and the reader line are recorded in the same evidence file (`Verdict: PASS for Validation 4`).

## Depends on
none

## Touches
loomwright/skills/pr-postmortem/SKILL.md
loomwright/commands/pr-postmortem.md
loomwright/docs/result-schemas/postmortem-result.md
loomwright/docs/result-schemas/schema-versioning.md
loomwright/scripts/read-postmortem.sh
loomwright/scripts/test-read-postmortem.sh
loomwright/scripts/postmortem-approach-baseline.sh
loomwright/scripts/test-postmortem-approach-baseline.sh
loomwright/docs/prompt-token-budgets.json
loomwright/docs/ARCHITECTURE_CONTRACTS.md
docs/evidence/approach-baseline.md
changelog.d/approach-baseline.md

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-11-11T19:18:46Z
- **Brief:** .supervisor/jobs/done/2026-11-11-approach-challenged-postmortem-baseline.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/891
