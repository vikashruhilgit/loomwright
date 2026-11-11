# Evidence — approach-challenged rounds: the baseline number and the flag on a real postmortem

Requirement: `.supervisor/requirements/approach-decisions/01-approach-challenged-rounds-are-counted-in-the-postmortem-ledger.md`
(Validation 3 and 4). Captured 2026-11-11 on macOS (Darwin 25.6.0), branch
`feature/approach-challenged-postmortem-baseline`, base `a2d9594`. The baseline script is the one
committed in `b7f241a`; its logic is unchanged at every later commit of this branch (the review-fix commits
edit only its comments). Real `gh` (authenticated, read-only
calls only), real ledger.

**Status in one line:** Validation 3's artifacts are recorded, and its number is a phrase-match guess with
the limits stated below. Validation 4 is PASS by owner decision: AC 15 asks for a PR picked from the AC 14
TSV, that TSV has 0 `true` rows, and the run used a hand-picked PR (#440) instead. The owner accepted the
substitution on 2026-11-12 as proof the flag works end to end, not as proof it classifies well. See "Owner
decision" under Validation 4's verdict.

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
Scope of this verdict: AC 14 asks for the run, its summary line, the ledger size, the `build-floor.sh`
re-grep and the schema-doc grep, and all of them are recorded above. The PASS does not claim the measured
rate. The script's guess is 0 of 423. The hand-corrected figure is at most 1 fixed round in 192 PRs. Which
of the two story `02` cites is for the owner to decide.

## Validation 4 — the flag on a real postmortem

### PR choice

The AC 14 TSV holds no `true` row, so the candidate could not be picked from it. The wider hand scan above
found one fixed review round with an approach challenge in it: PR #440
(https://github.com/vikashruhilgit/loomwright/pull/440, merged). The CI review's finding 3 says `pty_feed`
"reimplements the exact anti-pattern this same PR's `wait-lib.sh` exists to eliminate", and a later round fixed
it by switching to `wait_for_cmd`. That was the best candidate available, so the run used it. This
departs from AC 15. AC 15 says to pick the PR from the AC 14 TSV, and where no such PR can be identified
its own fallback is `Verdict: BLOCKED for Validation 4` plus an owner decision. Whether this substitution
satisfies AC 15 was put to the owner, whose decision is recorded under the verdict below.

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

### Run 2 — the mixed-round rule, but a table report (superseded)

Run 2 used the same mechanism as Run 3 below on the first review-fix commit, which adds the mixed-round
rule. It recorded round 4 `approach_challenged: true`, `approach_challenges: 1` and the reader line
`- approach-challenged rounds: 1 of 6 prior rounds`. But its Step 4 report printed the rounds as a Markdown
table (round 4's row read `**yes**` in an "approach challenged" column), not the SKILL's
`round N: … approach_challenged=<bool> …` line format, and Run 1 had done the same. AC 15 asks for that
per-round line, so Run 2 did not meet that clause. Review flagged it. Step 4 now says to print each round
literally in the `round N:` form with `true`/`false` values and **never as a Markdown table**. Run 3 re-ran
the same mechanism under that wording.

### Run 3 — command (the committed second review-fix branch)

```bash
git worktree add --detach <scratch>/v4wt HEAD          # the commit carrying the Step 4 line-format rule; .supervisor/postmortem/ absent there
cp .supervisor/postmortem/results.jsonl <scratch>/ledger-before-v4b.jsonl
cd <scratch>/v4wt
claude -p "/loomwright:pr-postmortem https://github.com/vikashruhilgit/loomwright/pull/440" \
  --plugin-dir "<scratch>/v4wt/loomwright" \
  --permission-mode dontAsk --allowedTools "Read,Bash" \
  --disallowedTools "Edit,Write,NotebookEdit,WebFetch,WebSearch,Task"
bash loomwright/scripts/read-postmortem.sh .claude-plugin/README.md   # a path PR #440 changed, run in the worktree
cmp <scratch>/ledger-before-v4b.jsonl <main checkout>/.supervisor/postmortem/results.jsonl   # exit 0
git worktree remove --force <scratch>/v4wt
```

The run used Claude Code 2.1.319 and ran 2026-11-11T14:14:27Z → 14:16:39Z. It exited 0 with stderr empty.
The `--plugin-dir` copy is this branch's `loomwright/` with the Step 4 line-format wording that this
evidence is about; the commit that wording ships in leaves `pr-postmortem/SKILL.md` byte-identical to the
copy that ran. The installed plugin has no `approach_challenged` token and no `approach_challenges` field,
so their presence shows the branch copy ran.

### Run 3 — Step 4 report: the per-round lines (verbatim)

The report printed six plain-text lines in a fenced block, one per round, in the SKILL's format:

```text
round 1: class=execution_bug  self_heal_miss=false  approach_challenged=false  flow_stage=worker     evidence="iteration 1 — phase-timing.sh unguarded `shift 2` spins forever when a value flag is last"
round 2: class=execution_bug  self_heal_miss=false  approach_challenged=false  flow_stage=worker     evidence="iteration 2 — fixed-sleep counter leaked do/heredoc state from quoted text; item_timing append not idempotent"
round 3: class=execution_bug  self_heal_miss=false  approach_challenged=false  flow_stage=worker     evidence="iteration 3 — drain-subfloor-decision split check names on whitespace (`build (ubuntu-latest)`)"
round 4: class=execution_bug  self_heal_miss=true   approach_challenged=true   flow_stage=self_heal  evidence="claude[bot]: owner_wait never clamped to hi; capabilities.json writes[]; pty_feed reimplements what wait-lib.sh replaces; item_timing dedupe by glob order"
round 5: class=execution_bug  self_heal_miss=true   approach_challenged=false  flow_stage=self_heal  evidence="fix-now, owner decision — Phase 4.5 round-3 findings dismissed below_severity_floor (--call-max fails open, empty flag swallows next flag, one bad date / one malformed line aborts the reader)"
round 6: class=quality_gap    self_heal_miss=true   approach_challenged=false  flow_stage=self_heal  evidence="claude[bot]: rule 14 heal_loop_ran=false branch untested; README missing the answered-hook bullet"
```

The per-round line AC 15 asks for is round 4's:

```text
round 4: class=execution_bug  self_heal_miss=true   approach_challenged=true   flow_stage=self_heal  evidence="claude[bot]: owner_wait never clamped to hi; capabilities.json writes[]; pty_feed reimplements what wait-lib.sh replaces; item_timing dedupe by glob order"
```

The `class` stays `execution_bug`: the flag did not change the class or `flow_stage`. The report's run
summary says "1 approach challenge".

### Run 3 — the appended ledger line (worktree ledger, 1 line, 7470 bytes)

Projection (`jq -c '{schema_version, ts, number, review_rounds, approach_challenges, self_heal_misses, flow_stages, plugin_version, cats:[.categories[]|{round,class,approach_challenged,flow_stage}]}'`):

```json
{"schema_version":1,"ts":"2026-11-11T14:16:12Z","number":440,"review_rounds":6,"approach_challenges":1,"self_heal_misses":3,"flow_stages":{"launch_pad":0,"worker":3,"self_heal":3,"unknowable":0},"plugin_version":"17.36.2","cats":[{"round":1,"class":"execution_bug","approach_challenged":false,"flow_stage":"worker"},{"round":2,"class":"execution_bug","approach_challenged":false,"flow_stage":"worker"},{"round":3,"class":"execution_bug","approach_challenged":false,"flow_stage":"worker"},{"round":4,"class":"execution_bug","approach_challenged":true,"flow_stage":"self_heal"},{"round":5,"class":"execution_bug","approach_challenged":false,"flow_stage":"self_heal"},{"round":6,"class":"quality_gap","approach_challenged":false,"flow_stage":"self_heal"}]}
```

Round 4 in full:

```json
{"round":4,"class":"execution_bug","self_heal_miss":true,"dismissed_then_raised":false,"approach_challenged":true,"flow_stage":"self_heal","evidence":"claude[bot] on a3736394/7a89c8f5: phase-timing owner_wait never clamped to hi; capabilities.json answered writes[]; pty_feed reimplements the anti-pattern wait-lib.sh exists to eliminate; item_timing dedupe by glob order"}
```

The ledger's round-4 `evidence` is a longer wording of the same finding than the report line's snippet; the
two are written by the same run in Step 4 and Step 5.

### Run 3 — reader line (run in the worktree)

```text
- approach-challenged rounds: 1 of 6 prior rounds
```

The live checkout's ledger was byte-identical before and after (`cmp` exit 0). The worktree, and the
worktree-only ledger with it, was removed afterwards (`git worktree list` no longer names it). The appended
line exists only in that removed worktree; the live ledger was not touched (the report offered to append it
there; that was not done).

### Result

AC 15 asks for a per-round line carrying `approach_challenged=true`, an appended line with
`approach_challenges: 1`, and a reader line `1 of …`. Run 3 produced all three on PR #440: the round 4 line
above, `approach_challenges: 1`, and `- approach-challenged rounds: 1 of 6 prior rounds`. N is 1, as AC 15
expects. These three outputs hold only on a PR chosen outside AC 15's pick rule (see "PR choice" and the
owner decision below the verdict).

Honest limits:

- The flagged round is a mixed round. Its approach finding (`pty_feed` re-implementing the wait this PR's
  `wait-lib.sh` replaces) shares round 4 with correctness findings. It is flagged under the mixed-round rule
  above. Run 1 on the same PR, before the rule existed, left it `false`. Run 3's own report calls the flag
  "a judgment call": the finding swaps the mechanism for one function rather than challenging the PR's
  overall approach.
- The flag and the report layout are model behaviour. Runs 2 and 3 show the current wording is followed once
  each; they do not measure agreement across runs.
- `self_heal_misses` and `flow_stages` differ across the runs (Run 2: 2 misses, round 5 at `worker`; Run 3:
  3 misses, round 5 at `self_heal`). That is run-to-run variance in the attribution and is not part of this
  item.

Verdict: PASS for Validation 4 — under the stated mixed-round rule and the Step 4 line format, PR #440's report printed `round 4: class=execution_bug  self_heal_miss=true   approach_challenged=true …`, the appended line carries `approach_challenges: 1`, and the reader printed `1 of 6 prior rounds`
Owner decision (2026-11-12): the substitution satisfies AC 15. PR #440 was hand-picked from a wider read-only scan of full review text, outside the AC 14 TSV, which had 0 `true` rows; AC 15's literal fallback for that case was `Verdict: BLOCKED for Validation 4`, and the owner accepted #440 instead.
Scope of this verdict: it proves the mechanism end to end — the SKILL records the per-round flag, the ledger line carries the counter, and the reader prints the tally. It does NOT prove the flag classifies rounds well: the mixed-round rule that flags round 4 was added to the SKILL after Run 1 on this same PR returned `false`, and Run 3's own report calls the flag "a judgment call". Story `02` must not treat `approach_challenged` as a calibrated signal on this evidence; accuracy needs rounds recorded after this ships.
