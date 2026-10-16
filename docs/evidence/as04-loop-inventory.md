# Evidence — as04: loop inventory + `test-loop-inventory.sh` (AC9)

Captured 2026-10-15T12:19:51Z on macOS (Darwin 25.6.0, BSD awk 20200816, bash 3.2), in the subtask-5 worktree on
branch `feature/as04-loop-inventory-5-dep` at `af57066` (the four inventory files merged in) plus this subtask's
staged changes (the test, the manifest entries, the fragment). Paths are redacted to `<worktree>` and `<mktemp -d>`;
nothing else in the transcripts was edited.

Refreshed 2026-10-15 on branch `feature/as04-loop-inventory` at `b431319` (review iteration 1, which added the
indent-34 fixture leg to `test-loop-inventory.sh` and the `--exclude-dir=loop-inventory` to
`test-closed-enum-pins-seam.sh`): every command in the results table was re-run there, the full test run below was
re-captured from that run, and the counts in this file match it.

## Results

| Command | Result | Exit |
|---|---|---|
| `bash loomwright/scripts/test-loop-inventory.sh` | **39/39** passed (real tree green: 2182 rows across 4 groups; 2 real-tree checks, 1 precondition, 36 fixture legs) | 0 |
| `bash loomwright/scripts/test-closed-enum-pins-seam.sh` | **79/79** passed (`test-closed-enum-pins-seam.sh: 79 passed, 0 failed`) | 0 |
| `bash loomwright/scripts/test-citation-drift.sh` | **26/26** passed (`citation-drift: 26 passed, 0 failed`) | 0 |
| `bash scripts/check-doc-currency.sh` | **9/9** surfaces clean (`Scanning 9 surfaces...`, no drift line; the script prints no per-check count, so the surface count is the total) | 0 |
| `bash scripts/check-vendor-coupling.sh` | **706/706** counted paths at or under allowance (`files scanned: 712 (counted: 706 …) … breaches: 0 \| errors: 0`); `raise_check` against `origin/main`: 4 new allowances, 0 without an added reason | 0 |
| `bash scripts/test-check-vendor-coupling.sh` | **338/338** passed (`test-check-vendor-coupling: 338 passed, 0 failed`) | 0 |

The four new `allowances` were measured by the gate itself (`bash scripts/check-vendor-coupling.sh
--print-allowances`, run after the inventory files and the test were tracked): automate-loop 12, launch-pad-autonomous
2, review-heal 10, supervisor 35. `test-loop-inventory.sh` measures 0 and has no entry; the manifest's own count is
unchanged (the four reasons name no token).

## Per-group counts

Each count is computed from the table by `test-loop-inventory.sh` and enforced against the file's `## Counts` block.

| Group | rows | deterministic | judgment | rule | story | GAP |
|---|---|---|---|---|---|---|
| automate-loop | 552 | 385 | 12 | 129 | 26 | 147 |
| supervisor | 736 | 381 | 31 | 303 | 21 | 542 |
| review-heal | 374 | 183 | 16 | 164 | 11 | 231 |
| launch-pad-autonomous | 520 | 330 | 46 | 119 | 25 | 418 |
| **total** | **2182** | 1279 | 105 | 715 | 83 | 1338 |

## Mutation-control transcript (AC4: a heading deleted from a scratch copy of `per-item-loop.md`)

From the test's own fixture leg. The leg picks the first prose `h:` row anchored on a heading that occurs exactly once in
`skills/automate-loop/per-item-loop.md`, deletes that heading line from a scratch copy, checks the mutant is non-empty
and differs from the original, and runs the checker on the scratch tree:

```text
  (deleted '### Rate-limit park (end of RUN, before DRAIN)' from a scratch copy of per-item-loop.md; its row is AL-001)
  ok: AC4 (anchored heading deleted) red — FAIL AL-001: anchor not found in skills/automate-loop/per-item-loop.md
```

## Full test run

```text
== the real tree (<worktree>/loomwright)
GAP automate-loop: 147
GAP supervisor: 542
GAP review-heal: 231
GAP launch-pad-autonomous: 418
loop-inventory: OK — 2182 rows across 4 groups
  ok: real tree: every check green
  ok: AC7: one informational GAP line per group (4)
== fixture legs (scratch copies under <mktemp -d>)
  ok: unmutated scratch copy green
  ok: AC2 (new heading) red — FAIL skills/automate-loop/per-item-loop.md: heading has no h: row: ### Fixture heading with no inventory row
  ok: exemption: heading inside a fenced block green
  ok: exemption: heading inside a split-index block green
  ok: fence union (live under CommonMark only) red — FAIL skills/automate-loop/per-item-loop.md: heading has no h: row: ### Fixture heading with no inventory row
  ok: fence union (live under the toggle only) red — FAIL skills/automate-loop/per-item-loop.md: heading has no h: row: ### Fixture heading with no inventory row
  ok: fence union (list-item fence, opener 3 / closer 4 spaces) red — FAIL skills/automate-loop/per-item-loop.md: heading has no h: row: ### Fixture heading with no inventory row
  ok: fence never closes red — FAIL skills/automate-loop/per-item-loop.md: a fenced block never closes, so headings after it were not checked
  (deleted '### Rate-limit park (end of RUN, before DRAIN)' from a scratch copy of per-item-loop.md; its row is AL-001)
  ok: AC4 (anchored heading deleted) red — FAIL AL-001: anchor not found in skills/automate-loop/per-item-loop.md
  ok: exemption: home step-scoped, anchor gone green
  ok: AC5: row AL-026 reads script:automate-helpers.sh gate-eval and passes on the real tree
  ok: AC5 (row renamed to a missing subcommand) red — FAIL AL-026: implemented by automate-helpers.sh has no case arm for 'gate-eval-no-such-arm'
  ok: AC5 (case arm renamed in the script) red — FAIL AL-026: implemented by automate-helpers.sh has no case arm for 'gate-eval'
  ok: AC6 (duplicate id in one file) red — FAIL AL-001: duplicate id (automate-loop and automate-loop)
  ok: AC6 (duplicate id across files) red — FAIL AL-001: duplicate id (automate-loop and supervisor)
  ok: AC7 (wrong count value) red — FAIL supervisor: ## Counts says '- rows: 9736' but the table has 736
  ok: AC7 (missing GAP count line) red — FAIL review-heal: ## Counts has no '- GAP:' line (the table has 231)
  ok: AC7 (gap-list line deleted) red — FAIL RH-163: GAP row missing from the review-heal ## Gap list
  ok: AC7b (test cell names a missing file) red — FAIL AL-011: test cell names no existing test-*.sh under loomwright/scripts/ or scripts/: test-does-not-exist.sh
  ok: shape-kind red — FAIL AL-001: unknown kind 'maybe'
  ok: shape-home red — FAIL AL-001: unknown home 'elsewhere'
  ok: shape-q-short red — FAIL AL-001: q: anchor shorter than 12 characters: q: too short
  ok: shape-anchor-form red — FAIL AL-001: anchor must start with 'h: #' or 'q: ': x: not an anchor form
  ok: shape-impl-missing red — FAIL AL-001: implemented by names a script missing from scripts/: no-such-script.sh
  ok: shape-impl-form red — FAIL AL-001: implemented by must be '-' or script:<file>[ <sub>], got 'maybe later'
  ok: shape-file red — FAIL AL-001: file 'commands/supervisor.md' is not a source of the automate-loop group
  ok: shape-id-prefix red — FAIL SV-999: id prefix is not the automate-loop group's AL
  ok: shape-id-form red — FAIL automate-loop row #1: malformed id 'AL-1' (want AL-NNN)
  ok: gap-not-gap red — FAIL AL-210: in the automate-loop ## Gap list but not a GAP row of its table
  ok: shape-cells red — FAIL automate-loop row #1: malformed row (10 cells, want 9): | AL-001 | skills/automate-loop/per-item-loop.md | h: ### Rate-limit park (end o
  ok: shape-sources red — FAIL automate-loop: ## Sources is missing commands/automate.md
  ok: shape-header red — FAIL automate-loop: the ## Inventory table header is not the contract header: | id | file | anchor | condition | action | kind | home | impl | test |
  ok: shape-sections red — FAIL automate-loop: ## sections must be exactly Sources / Inventory / Gap list (ordered by risk) / Counts, found: Sources / Inventory / Gap list (ordered by risk) / Totals
  ok: shape-count-line red — FAIL automate-loop: malformed ## Counts line: - rows: many
  ok: shape-count-dup red — FAIL review-heal: ## Counts has two '- GAP:' lines
  ok: shape-gap-line red — FAIL review-heal: malformed ## Gap list line (want `N. <id> — <reason>`): 1. RH-163 - the drain's central READY test is prose-only; a bad edit declares READY with a finding or a red check still open.
  ok: split-unclosed red — FAIL skills/automate-loop/SKILL.md: a split:begin block never closes, so headings after it were not checked
RESULT: 39/39 passed
```

## Pin mutations (brief `## Pin mutations`, one line per pin)

`bash loomwright/scripts/run-pin-mutations.sh <brief> --root <worktree>` exited 2: `4 held, 0 not_held, 4 unverified`.
The four `unverified` rows are `mutation_does_not_apply` — their literal occurs more than once in the target file
(the runner applies only single-match rows). The brief says to apply them at the first occurrence, so each was
applied there by hand on a `mktemp -d` copy of `loomwright/` + `scripts/`. Each mutant was checked non-empty and
different from its original, then the test was run in its default mode:

| # | Pin mutation | How applied | Verdict | First red line |
|---|---|---|---|---|
| 1 | delete `AL-001` in `automate-loop.md` (heading coverage) | first occurrence (the table row) | held (exit 1) | `FAIL skills/automate-loop/per-item-loop.md: heading has no h: row: ### Rate-limit park (end of RUN, before DRAIN)` |
| 2 | delete `### Rate-limit park (end of RUN, before DRAIN)` in `per-item-loop.md` (live anchor) | runner | held | (runner verdict) |
| 3 | flip `    gate-eval)` → `    gate-evalx)` in `automate-helpers.sh` (subcommand) | runner | held | (runner verdict) |
| 4 | flip `AL-002` → `AL-001` in `automate-loop.md` (duplicate id) | first occurrence (the table row) | held (exit 1) | `FAIL AL-001: duplicate id (automate-loop and automate-loop)` |
| 5 | delete `- GAP:` in `review-heal.md` (missing count line) | runner | held | (runner verdict) |
| 6 | delete `1. RH-` in `review-heal.md` (gap-list drift) | first occurrence (gap-list line 1, RH-163) | held (exit 1) | `FAIL RH-163: GAP row missing from the review-heal ## Gap list` |
| 7 | flip `- rows: ` → `- rows: 9` in `supervisor.md` (wrong count) | runner | held | (runner verdict) |
| 8 | flip `test-automate-helpers.sh` → `test-does-not-exist.sh` in `automate-loop.md` (test cell) | first occurrence (AL-011's test cell) | held (exit 1) | `FAIL AL-011: test cell names no existing test-*.sh under loomwright/scripts/ or scripts/: test-does-not-exist.sh` |

## Honest limits

- AC3 (every branch- or rule-bearing list item has its own row) is a reviewer's check; the test checks headings only.
- A `q:` anchor is checked to exist, not to be unique in its file or to say what its row claims.
- The case-arm rule accepts any `case` arm in the named script, not only the dispatcher's.
- Portability: run on BSD awk only. The awk programs avoid interval expressions and octal escapes inside
  regexes (a literal `\|` is handled with `index()`/`substr()`), so gawk and mawk should read them the same way,
  but no Linux run was observed here; CI is the first.

## Scope exception (AC11)

AC11 allows changes only to the six created files, this evidence file, and
`loomwright/docs/vendor-coupling-manifest.json`. One edit falls outside that set, made in `b431319`, and needs the
owner's explicit acceptance:

- `loomwright/scripts/test-closed-enum-pins-seam.sh`: the sibling-grep hit set (`HITS`) gained
  `--exclude-dir=loop-inventory`. Reason: the new `docs/loop-inventory/` inventories quote the authoritative prose
  verbatim, including a sibling closed-enum value, so they became grep hits that the fixture brief does not list,
  which broke the test's listed-files == grep-hits equality and turned the required `ci` check red. The inventories
  are a derived restatement (like `CHANGELOG.md`, already excluded), not a site that implements the enum, and they
  post-date the fixture's notional base. The assertion and its positive control are unchanged; the test passes
  79/79 (results table above).

The other file `b431319` touched, `loomwright/scripts/test-loop-inventory.sh`, is one of the six created files.
