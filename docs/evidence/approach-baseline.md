# Evidence — approach-challenged rounds: the baseline number and the flag on a real postmortem

Requirement: `.supervisor/requirements/approach-decisions/01-approach-challenged-rounds-are-counted-in-the-postmortem-ledger.md`
(Validation 3 and 4). Captured 2026-11-11 on macOS (Darwin 25.6.0), branch
`feature/approach-challenged-postmortem-baseline`, base `a2d9594`. The baseline script is the one
committed in `b7f241a`, byte-identical at every later commit of this branch. Real `gh` (authenticated, read-only
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

### Command

```bash
git worktree add --detach <scratch>/v4wt 5966a1f        # this branch's head; gitignored .supervisor/postmortem/ absent there
cp .supervisor/postmortem/results.jsonl <scratch>/ledger-before-v4.jsonl
cd <scratch>/v4wt
claude -p "/loomwright:pr-postmortem https://github.com/vikashruhilgit/loomwright/pull/440" \
  --plugin-dir "<scratch>/v4wt/loomwright" \
  --permission-mode dontAsk --allowedTools "Read,Bash" \
  --disallowedTools "Edit,Write,NotebookEdit,WebFetch,WebSearch,Task"
bash loomwright/scripts/read-postmortem.sh .claude-plugin/README.md   # a path PR #440 changed, run in the worktree
cmp <scratch>/ledger-before-v4.jsonl <main checkout>/.supervisor/postmortem/results.jsonl   # exit 0
git worktree remove <scratch>/v4wt
```

The run used Claude Code 2.1.319 and ran 2026-11-11T13:34:54Z → 13:36:22Z (the appended line's `ts`). It exited 0 with stderr empty. The `--plugin-dir` copy is
this branch's `loomwright/` at `5966a1f`. Two things show that copy ran: the report has an `approach_challenged`
column, and the appended line carries `approach_challenges`. Neither exists in the installed plugin.

### Step 4 report: the per-round lines

The report printed the per-round breakdown as a Markdown table rather than the SKILL's
`round N: class=…  approach_challenged=<bool> …` line format. Every round carries the flag. The round that
holds the approach finding:

```text
| 4 | execution_bug | **true** | false | self_heal | CI bot (`claude[bot]`): the owner-wait interval in `phase-timing.sh` is not clamped to the window end, so `machine_seconds` can go negative; wrong `writes[]` in `capabilities.json`; `pty_feed` still uses tick polling even though this PR adds `wait-lib.sh` to replace it |
```

The columns are round, class, self_heal_miss, approach_challenged, flow_stage and evidence. All six rounds
read `approach_challenged` `false`.

### The appended ledger line (worktree ledger, 1 line, 7440 bytes)

Projection (`jq -c '{schema_version, ts, number, review_rounds, approach_challenges, self_heal_misses, flow_stages, plugin_version, cats:[.categories[]|{round,class,approach_challenged,flow_stage}]}'`):

```json
{"schema_version":1,"ts":"2026-11-11T13:36:22Z","number":440,"review_rounds":6,"approach_challenges":0,"self_heal_misses":2,"flow_stages":{"launch_pad":0,"worker":3,"self_heal":3,"unknowable":0},"plugin_version":"17.36.2","cats":[{"round":1,"class":"execution_bug","approach_challenged":false,"flow_stage":"worker"},{"round":2,"class":"execution_bug","approach_challenged":false,"flow_stage":"worker"},{"round":3,"class":"execution_bug","approach_challenged":false,"flow_stage":"worker"},{"round":4,"class":"execution_bug","approach_challenged":false,"flow_stage":"self_heal"},{"round":5,"class":"execution_bug","approach_challenged":false,"flow_stage":"self_heal"},{"round":6,"class":"quality_gap","approach_challenged":false,"flow_stage":"self_heal"}]}
```

Round 4 in full:

```json
{"round":4,"class":"execution_bug","self_heal_miss":true,"dismissed_then_raised":false,"approach_challenged":false,"flow_stage":"self_heal","evidence":"claude[bot] on a3736394: phase-timing.sh owner_wait end never clamped to window hi (machine_seconds negative); capabilities.json writes[]; pty_feed tick-polling despite this PR's wait-lib.sh"}
```

### Reader line (run in the worktree)

```text
- approach-challenged rounds: 0 of 6 prior rounds
```

The live checkout's ledger was byte-identical before and after (`cmp` exit 0).

### Result

The flag's mechanics hold on a real postmortem. The branch's SKILL produced a per-round `approach_challenged`
on every round and a top-level `approach_challenges` (`schema_version` 1). The reader printed the
`approach-challenged rounds` line right after the `self_heal_miss` line. The acceptance criterion needs more:
a round recorded `approach_challenged=true`, `approach_challenges: 1`, and a reader line `1 of …`. This run
did not produce them.

- PR #440 has no round dominated by an approach challenge. The approach finding shares round 4 with two
  correctness findings (an unclamped interval and wrong `writes[]`). The model classified that round
  `execution_bug` and left the flag at its documented default, `false`, for a round that is not clearly a
  challenge to the approach.
- The ledger has no other candidate. The AC 14 TSV and both hand probes found no PR whose fixed review round
  is mainly an approach challenge.

So no PR meeting AC 15's premise could be identified. This is not a PASS. The owner has to decide what
happens next. The options are: run `/pr-postmortem` on a merged PR outside the ledger whose review mainly
asked for a different approach, accept the mechanics evidence above, or widen the gather's 200-character
snippet cap in a separate item. The PR stays not merge-ready until the owner picks one.

Verdict: BLOCKED for Validation 4 — no merged PR in the ledger has a review round dominated by an approach challenge; the closest one (#440, round 4) was recorded `approach_challenged=false`, the documented default for a mixed round
