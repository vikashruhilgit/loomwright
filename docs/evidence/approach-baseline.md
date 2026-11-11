# Evidence — approach-challenged rounds: the baseline number and the flag on a real postmortem

Requirement: `.supervisor/requirements/approach-decisions/01-approach-challenged-rounds-are-counted-in-the-postmortem-ledger.md`
(Validation 3 and 4). Captured 2026-11-11 on macOS (Darwin 25.6.0), branch
`feature/approach-challenged-postmortem-baseline`, base `a2d9594`. The baseline script is the one
committed in `b7f241a`; its logic is unchanged at every later commit of this branch (the review-fix commit
edits only its header comment). Real `gh` (authenticated, read-only
calls only), real ledger.

## Validation 3 — the baseline number over the real ledger

### Command

```bash
wc -l .supervisor/postmortem/results.jsonl
cp .supervisor/postmortem/results.jsonl <scratch>/ledger-before.jsonl
bash loomwright/scripts/postmortem-approach-baseline.sh > <scratch>/v3.tsv 2> <scratch>/v3.err   # gh available
cmp <scratch>/ledger-before.jsonl .supervisor/postmortem/results.jsonl                          # exit 0
```

Run window 2026-11-11T13:13:25Z → 2026-11-11T13:21:17Z (one read-only gather per PR, about 2.5 s each).
Exit 0. stderr held only the 19 `gather <i>/192` progress lines.

### Ledger size

```text
237 .supervisor/postmortem/results.jsonl
```

No curation record exists in this ledger yet, so no entry was excluded. 213 live entries carry at least one
categorized round, 423 rounds in all: 159 `automate_drain` entries (212 rounds, the synthetic `drain_churn` /
`self_heal_churn` / `drain_escalation` classes), 44 `github_postmortem` entries (173 rounds) and 10
`manual_postmortem` entries (38 rounds).

### Output

`v3.tsv` holds 424 lines: one TSV row per categorized round (423) and the summary line. Every row's
`approach_challenged_guess` column is `false`; no entry carries a recorded flag yet. The summary line:

```text
approach_challenged: 0 of 423 categorized rounds (guess; 213 entries, 203 gathered, 10 gather-unavailable)
```

The 10 gather-unavailable entries are older lines with no `pr_url` (PRs #43, #47, #48, #60, #61, #62, #67,
#68, #69; #67 has two entries), so the gather had nothing to read. The evidence-only pass
(`--no-gh`, same ledger) prints the same rate:
`approach_challenged: 0 of 423 categorized rounds (guess; 213 entries, 0 gathered, 213 gather-unavailable)`.

The ledger was byte-identical before and after (`cmp` exit 0).

### Honest limits of this number (read before citing it)

The raw guess is 0. The hand checks below put it in context. This number is the baseline story `02` cites.

1. **The gather OR sees only each comment's first 200 characters.** `pr-postmortem-gather.sh` caps every
   `review_comments[].snippet` at 200 characters (its `def snippet`). For this repo's bot reviews that is the
   opening summary ("Reviewed <sha>. This PR adds …"), not the findings. A probe of PR #472 returned 8
   snippets, all exactly 200 characters long. Changing the gather is a non-goal of this item.
2. **Same phrases over the FULL review text: 5 hits in 192 PRs, all false positives.** A one-off read-only
   probe fetched every issue comment, review body and inline review comment of the 192 ledger PRs that have
   a `pr_url` (`gh api …/issues/<n>/comments`, `…/pulls/<n>/reviews`, `…/pulls/<n>/comments`). It matched
   the script's own phrase array line by line. The 5 hits are #55 (`to disable use` instead of the real
   text, a correctness bug), #301 (the contract is "restated, not reinvented", praise), #440 (a dedupe keeps a
   stale duplicate "instead of" the latest one, a correctness bug), #538 (a PR summary sentence) and #548
   ("reusing the existing seam … rather than reinventing it", praise). Hand-corrected: 0 of 5 are approach
   challenges.
3. **The phrase list misses some real approach challenges.** A wider hand scan of the same full text, using
   "re-implements", "hand-rolls … instead of", "instead of reusing" and "duplicates existing helpers", found
   at least three. In #440 (finding 3), `pty_feed` "reimplements the exact anti-pattern this same PR's
   `wait-lib.sh` exists to eliminate"; it was fixed in a later round by switching to `wait_for_cmd`. In #632
   (finding 2, nit), `ns_valve_report` "duplicates existing helpers instead of reusing them"; it was dismissed
   below the fix floor. In #822, `defer` "re-implements lane removal instead of reusing `lane-remove`"; it was
   dismissed below the severity floor. Only #440's was a fixed review round. In the ledger, all three PRs are
   `automate_drain` entries whose synthetic rounds carry no finding text.

A defensible hand-corrected baseline is therefore **at most 1 approach-challenged fixed round across 192 PRs**
(#440). The script's phrase-match rate is **0 of 423**. This is a low rate, and it is measured only within the
reach stated above.

### `build-floor.sh` re-grep (unchanged, a non-goal of this item)

```bash
grep -nE 'categories|self_heal_miss|approach_challenged' loomwright/scripts/build-floor.sh
```

```text
686:  # `flow_stage` field per element of `categories[]`. `learning-emit` derives the counter from
689:  # `categories[]` holds one or two entries (and a self-heal-only line reads counter 0 against
699:  #   jq -s '[.[]|select((.flow_stages//{}) != (reduce (.categories[]?.flow_stage) as $s
703:  # The basis is PINNED to `.categories[].flow_stage`, and the reason is DENOMINATOR COHERENCE,
709:  # category objects, `categories_total` names that denominator, and `flow_stage_basis` /
717:  # line with an empty `categories[]` is counted separately rather than attributed anywhere.
730:        | (if (($r.o.categories) | type) == "array"
731:           then ($r.o.categories | to_entries
740:    | ($good | map(select((((.o.categories) | type) != "array")
741:                          or (((.o.categories) | length) == 0))) | length) as $nocat
747:        | (if ((.o.categories) | type) == "array"
748:           then (.o.categories | map(select(type == "object") | .flow_stage)
758:        + (if ((.c.self_heal_miss) | type) == "boolean" then {self_heal_miss: .c.self_heal_miss} else {} end)
763:       ({categories_total: ($catobjs | length),
764:       class_basis: ".categories[].class",
765:       flow_stage_basis: ".categories[].flow_stage",
766:       lines_without_categories: $nocat,
```

The requirement assumed `build-floor.sh` has nothing postmortem-shaped for `categories`. That premise is
stale. `build-floor.sh` reads the churn ledger, builds a class distribution (`class_basis:
".categories[].class"`) and projects each `categories[]` entry through a fixed allowlist: `class`,
`flow_stage`, `round`, `self_heal_miss` (the hit at line 758 above) and `evidence`. No `approach_challenged`
appears. The new per-round field is therefore absent from `build-floor.sh`'s `entries[]`, exactly as
`dismissed_then_raised` already is. `build-floor.sh` is unchanged, as a requirement non-goal.

### Schema-doc grep (AC 12)

```bash
grep -cF 'POSTMORTEM_RESULT additive `approach_challenged` + `approach_challenges`' loomwright/docs/result-schemas/schema-versioning.md
```

```text
1
```

The entry is in the file's one-paragraph form and says no `schema_version` bump (stays 1).
`bash loomwright/scripts/test-result-schemas-split.sh` passes (14 passed, 0 failed).

Verdict: PASS for Validation 3

## Validation 4 — the flag on a real postmortem

### PR choice

The AC 14 TSV holds no `true` row, so the candidate could not be picked from it. The wider hand scan above
found one fixed review round with an approach challenge in it: PR #440
(https://github.com/vikashruhilgit/loomwright/pull/440, merged). The CI review's finding 3 says `pty_feed`
"reimplements the exact anti-pattern this same PR's `wait-lib.sh` exists to eliminate", and a later round fixed
it by switching to `wait_for_cmd`. That was the best candidate available, so the run used it.

### Run 1 — before the mixed-round rule (superseded)

The first run used this branch at `5966a1f`, where the SKILL did not yet say how to flag a round that mixes an
approach challenge with correctness findings. Its report showed `**true**` in round 4's `self_heal_miss`
column and the appended line recorded every round `approach_challenged: false` (`approach_challenges: 0`,
reader `- approach-challenged rounds: 0 of 6 prior rounds`). The model left round 4 at `false` because the
SKILL said nothing about mixed rounds. That run recorded `Verdict: BLOCKED`. Review then found the gap: the
SKILL never stated a rule for mixed rounds, and the evidence had leaned on one it did not state. The SKILL now
does: **a round is flagged when ANY of its findings challenges the approach, even alongside correctness
findings** (§"Optional `approach_challenged` flag"). `false` is the default only for a genuinely unclear
round. Run 2 re-ran the same mechanism under that rule.

### Run 2 — command (the committed review-fix branch)

```bash
git worktree add --detach <scratch>/v4wt HEAD          # the commit carrying the mixed-round rule; .supervisor/postmortem/ absent there
cp .supervisor/postmortem/results.jsonl <scratch>/ledger-before-v4.jsonl
cd <scratch>/v4wt
claude -p "/loomwright:pr-postmortem https://github.com/vikashruhilgit/loomwright/pull/440" \
  --plugin-dir "<scratch>/v4wt/loomwright" \
  --permission-mode dontAsk --allowedTools "Read,Bash" \
  --disallowedTools "Edit,Write,NotebookEdit,WebFetch,WebSearch,Task"
bash loomwright/scripts/read-postmortem.sh .claude-plugin/README.md   # a path PR #440 changed, run in the worktree
cmp <scratch>/ledger-before-v4.jsonl <main checkout>/.supervisor/postmortem/results.jsonl   # exit 0
git worktree remove --force <scratch>/v4wt
```

The run used Claude Code 2.1.319 and ran 2026-11-11T13:49:33Z → 13:51:11Z (the appended line's `ts`). It
exited 0 with stderr empty. The `--plugin-dir` copy is this branch's `loomwright/` at the review-fix commit,
the one that adds the mixed-round rule. The installed plugin has no `approach_challenged` column and no
`approach_challenges` field, so their presence shows the branch copy ran.

### Run 2 — Step 4 report: the per-round lines

The report again printed the per-round breakdown as a Markdown table, not the SKILL's
`round N: class=…  approach_challenged=<bool> …` line format. The columns are round, class, missed by
self-heal, approach challenged, stage and evidence. Round 4 is the one flagged:

```text
| 4 | execution_bug | **yes** | **yes** | self_heal | CI bot on `a3736394`: the `owner_wait` interval end wasn't clamped to the window, the `item_timing` dedupe depended on glob order, and `pty_feed` re-built a tick-counted wait instead of using this PR's own `wait-lib.sh` |
```

The other five rounds read `no` in the approach column. The report's run summary says "1 approach challenge".
The `class` stays `execution_bug`: the flag did not change the class or `flow_stage`.

### Run 2 — the appended ledger line (worktree ledger, 1 line, 7361 bytes)

Projection (`jq -c '{schema_version, ts, number, review_rounds, approach_challenges, self_heal_misses, flow_stages, plugin_version, cats:[.categories[]|{round,class,approach_challenged,flow_stage}]}'`):

```json
{"schema_version":1,"ts":"2026-11-11T13:51:11Z","number":440,"review_rounds":6,"approach_challenges":1,"self_heal_misses":2,"flow_stages":{"launch_pad":0,"worker":4,"self_heal":2,"unknowable":0},"plugin_version":"17.36.2","cats":[{"round":1,"class":"execution_bug","approach_challenged":false,"flow_stage":"worker"},{"round":2,"class":"execution_bug","approach_challenged":false,"flow_stage":"worker"},{"round":3,"class":"execution_bug","approach_challenged":false,"flow_stage":"worker"},{"round":4,"class":"execution_bug","approach_challenged":true,"flow_stage":"self_heal"},{"round":5,"class":"execution_bug","approach_challenged":false,"flow_stage":"worker"},{"round":6,"class":"quality_gap","approach_challenged":false,"flow_stage":"self_heal"}]}
```

Round 4 in full:

```json
{"round":4,"class":"execution_bug","self_heal_miss":true,"dismissed_then_raised":false,"approach_challenged":true,"flow_stage":"self_heal","evidence":"claude[bot] on a3736394: phase-timing owner_wait end never clamped to window hi; item_timing dedupe keeps glob-order last; pty_feed reimplements tick-counted wait instead of this PR own wait-lib.sh"}
```

### Run 2 — reader line (run in the worktree)

```text
- approach-challenged rounds: 1 of 6 prior rounds
```

The live checkout's ledger was byte-identical before and after (`cmp` exit 0). The worktree, and the
worktree-only ledger with it, was removed afterwards. The appended line exists only in that removed worktree;
the live ledger was not touched (the report offered to append it there; that was not done).

### Result

AC 15 asks for a round recorded `approach_challenged=true`, `approach_challenges: 1`, and a reader line
`1 of …`. Run 2 produced all three on PR #440: round 4 `approach_challenged: true`, `approach_challenges: 1`,
and `- approach-challenged rounds: 1 of 6 prior rounds`. N is 1, as AC 15 expects.

Honest limits:

- The flagged round is a mixed round. Its approach finding (`pty_feed` re-implementing the wait this PR's
  `wait-lib.sh` replaces) shares round 4 with two correctness findings. It is flagged under the mixed-round
  rule above. Run 1 on the same PR, before the rule existed, left it `false`.
- The flag is a model judgment. One run on one PR shows the rule is followed; it does not measure agreement
  across runs.
- Step 4 printed a table rather than the `round N:` line format, both times. Each row still carries the flag.
- The run also recorded round 5 at `flow_stage: worker` where Run 1 recorded `self_heal`, so `flow_stages`
  differs between the runs. That is run-to-run variance in the stage attribution and is not part of this item.

Verdict: PASS for Validation 4 — under the stated mixed-round rule, PR #440 round 4 recorded `approach_challenged: true`, the line carries `approach_challenges: 1`, and the reader printed `1 of 6 prior rounds`
