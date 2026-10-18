# as14 — review-heal carries rules, not stories: evidence

Requirement: `.supervisor/requirements/automate-speed/14-diet-review-heal.md`. Base commit: `3a03dfa66d7de22ff93b0327affa60aa752948d2`. The job runs as three serial subtasks; each appends its own rows below. Subtask 1 covered the rows of `docs/loop-inventory/review-heal.md` anchored in `skills/review-heal/SKILL.md` before `## Until-Mergeable Mode` or from `## Anti-Patterns` onward, plus every `commands/review-pr.md` and `agents/review-pr.md` row. Numbers marked *after subtask 1* are interim; subtask 3 records the final ones. Every command runs from the repo root unless a `cd` is shown.

## Before (base `3a03dfa`)

Drain-round read set (`git show 3a03dfa:<path> | wc -c`):

```
  110754 loomwright/skills/review-heal/SKILL.md
   18297 loomwright/commands/review-pr.md
  129051 total
```

History references (AC3's regex, over the same two files):

```bash
{ git show 3a03dfa:loomwright/skills/review-heal/SKILL.md; git show 3a03dfa:loomwright/commands/review-pr.md; } \
  | grep -oE '#[0-9]{2,4}\b|queue/[0-9]+|20[0-9]{2}-[0-9]{2}-[0-9]{2}|item [0-9]+' | wc -l
```

Before: **41**.

`story` / `rule` rows by home (AC1; the rationale anchor is stripped so one doc counts once):

```bash
AWKC='/^\| RH-[0-9]+ \|/ { n = split($0, c, " \\| "); k = c[6]; h = c[7]; sub(/#.*/, "", h); if (k == "story" || k == "rule") print k "\t" h }'
git show 3a03dfa:loomwright/docs/loop-inventory/review-heal.md | awk "$AWKC" | sort | uniq -c   # before
awk "$AWKC" loomwright/docs/loop-inventory/review-heal.md | sort | uniq -c                     # after
```

Before:

```
 160 rule	prose
   1 rule	script:review-heal-next-step.sh confirm
   1 rule	script:review-heal-next-step.sh decide
   1 rule	script:review-heal-next-step.sh fallback
   1 rule	script:review-heal-next-step.sh probe
   1 rule	script:review-heal-next-step.sh read
   1 rule	script:review-heal-next-step.sh validate
  11 story	prose
```

## After subtask 1 (interim)

`wc -c` (`cd loomwright && wc -c skills/review-heal/SKILL.md commands/review-pr.md`):

```
   91094 skills/review-heal/SKILL.md
    8865 commands/review-pr.md
   99959 total
```

History references over the same two files: **32** (from 41). In subtask 1's ranges two remain: the frontmatter `lastUpdated:` date and `item 04` inside the `background_wait` anti-pattern, whose bold lead is the P-leg pin literal for RH-258 and was kept byte-for-byte rather than loosening the needle. The other 30 sit in the until-mergeable range (subtask 2).

`story` / `rule` rows by home, after subtask 1 (the AWKC command above):

```
  55 rule	global
  63 rule	prose
  20 rule	rationale:docs/rationale/review-heal.md
   1 rule	script:classify-bot-review.sh
   3 rule	script:dispatch-pr-postmortem.sh
   6 rule	script:dispatch-pr-review.sh
   1 rule	script:drain-gh-read.sh review-threads
   1 rule	script:fix-floor.sh meets
   1 rule	script:resolve-egress-config.sh
   1 rule	script:review-heal-next-step.sh confirm
   1 rule	script:review-heal-next-step.sh decide
   1 rule	script:review-heal-next-step.sh fallback
   1 rule	script:review-heal-next-step.sh probe
   2 rule	script:review-heal-next-step.sh read
   1 rule	script:review-heal-next-step.sh validate
   1 rule	script:review-heal-next-step.sh wait
   1 rule	script:wait-for-checks.sh
   1 rule	script:wrap-external-text.sh
   5 rule	step-scoped
   5 story	prose
   6 story	rationale:docs/rationale/review-heal.md
```

The 63 `rule` and 5 `story` rows still in `prose` are all anchored between `## Until-Mergeable Mode` and `## Anti-Patterns` in `SKILL.md` (subtask 2's range); a one-off reader that maps every row's anchor to its line confirmed none of them is in subtask 1's range.

### Subtask 1 — new homes

- `rationale:docs/rationale/review-heal.md#…` — stories RH-052 (`#why-fork-aware-push`), RH-278 (`#related-skills`), RH-295 (`#review-pr-purpose`), RH-296 (`#review-pr-usage`), RH-328 (`#review-pr-see-also`), RH-374 (`#review-pr-runner-related`); restated rules RH-259 … RH-266 (`#restated-anti-patterns`) and RH-280 … RH-291 (`#quality-gates`), each bullet in the doc naming the row that carries its rule; restated deterministic rows RH-322 … RH-325 (`#how-supervisors-auto-run-threads-until-mergeable`, the reader rows being `agents/review-pr.md` RH-357 … RH-360).
- `script:` — RH-004 RH-007 RH-015 RH-026 RH-027 RH-029 RH-030 RH-274 RH-321 (`dispatch-pr-review.sh`); RH-008 RH-276 RH-277 (`dispatch-pr-postmortem.sh`); RH-009 (`wrap-external-text.sh`); RH-010 RH-301 (`ci-run-probe.sh`); RH-028 (`worktree-salvage.sh`); RH-054 (`notify-desktop.sh`); RH-055 (`send-webhook.sh`); RH-267 (`drain-gh-read.sh review-threads`); RH-270 (`classify-bot-review.sh`); RH-271 (`fix-floor.sh meets`); RH-299 (`fix-floor.sh resolve`); RH-273 (`wait-for-checks.sh`); RH-279 (`resolve-egress-config.sh`); RH-257 RH-314 (`review-heal-next-step.sh wait`); RH-269 RH-312 (`… read`); RH-298 RH-318 (`… round`); RH-317 (`… decide`); RH-319 (`… probe`); RH-320 (`… postmortem`). `test-loop-inventory.sh`'s SCRIPT SUBCOMMANDS check confirms every named file and case arm exists.
- `step-scoped` — RH-023 RH-025 RH-040 RH-041 RH-305 (below).
- `global` — every other rule row of the range, including all 18 `agents/review-pr.md` rule rows (that file is not edited, so its rules stay where they are as `global`).
- RH-037 (deterministic, still `prose`) had its anchor re-cut when the `(six-phase-loop-gaps/02)` tag left the guard-arm sentence.

## After subtask 2 (interim)

Subtask 2 covered the rows anchored between `## Until-Mergeable Mode` and `## Anti-Patterns` in `SKILL.md`, and split three path-only parts out of it. Its new homes and the files the split created are listed here; subtask 3 records the final numbers.

`wc -c` (`cd loomwright && wc -c skills/review-heal/SKILL.md commands/review-pr.md`) — the drain-round read set (a drain round that runs neither the Earned Fallback Review nor an escalation reads no split file):

```
   71170 skills/review-heal/SKILL.md
    8865 commands/review-pr.md
   80035 total
```

All modes (`cd loomwright && wc -c skills/review-heal/*.md commands/review-pr.md`):

```
   71170 skills/review-heal/SKILL.md
    8106 skills/review-heal/dispatch.md
    1348 skills/review-heal/escalation.md
    5038 skills/review-heal/fallback-review.md
    8865 commands/review-pr.md
   94527 total
```

History references over the drain-round read set (AC3's regex): **4** (from 32 after subtask 1, 41 at base): the frontmatter `lastUpdated:` date, `item 01` twice (the pinned bold lead of RH-076 and the §"Untrusted-Text Envelope" heading other files cite) and `item 04` (subtask 1's RH-258 pin literal).

`story` / `rule` rows by home after subtask 2 (the AWKC command above):

```
 117 rule	global
  22 rule	rationale:docs/rationale/review-heal.md
   1 rule	script:classify-bot-review.sh
   3 rule	script:dispatch-pr-postmortem.sh
   6 rule	script:dispatch-pr-review.sh
   1 rule	script:drain-gh-read.sh review-threads
   1 rule	script:fix-floor.sh meets
   1 rule	script:resolve-egress-config.sh
   1 rule	script:review-heal-next-step.sh classify
   1 rule	script:review-heal-next-step.sh confirm
   1 rule	script:review-heal-next-step.sh decide
   1 rule	script:review-heal-next-step.sh fallback
   1 rule	script:review-heal-next-step.sh probe
   3 rule	script:review-heal-next-step.sh read
   1 rule	script:review-heal-next-step.sh validate
   2 rule	script:review-heal-next-step.sh wait
   1 rule	script:wait-for-checks.sh
   1 rule	script:wrap-external-text.sh
   9 rule	step-scoped
  11 story	rationale:docs/rationale/review-heal.md
```

No `rule` or `story` row is in `prose`.

### Subtask 2 — the split (AC6)

- `skills/review-heal/fallback-review.md` — §"Earned Fallback Review — `no_review_lens_posted` (AC3, PINNED)": the trigger, the issue-comment rule, the effect, the fail-closed direction and a one-line spawn-legality rule. Read only when the driver prints a `spawn` with `what: "fallback review"`.
- `skills/review-heal/escalation.md` — §"Escalation cause (automate-followups/31)". Read only when the drain ends `ESCALATED`.
- `skills/review-heal/dispatch.md` — §"Until-Mergeable Dispatch Signal (AC7 signal contract — PINNED)" with §"Cardinal guarantee (AC12, R9)", §"Churn gate (AC9/AC10/AC11) — fires only on meaningful churn", §"Opt-out (AC13)" and §"Launch form (R10 — fresh detached process, NEVER a nested Task)". A drain round never reads it.
- Every moved heading stays in `SKILL.md` followed by one `Moved to \`skills/review-heal/<file>.md\` …` line (new rows RH-379 … RH-385, each pinned). The driver's four `contract` citations (§"Step U3.5 — Validate-Then-Fix", §"Earned Fallback Review — `no_review_lens_posted`", §"Step U4 — The bounded drain loop", §"Fork-aware push") were checked against `SKILL.md`'s headings by a scratch script: all four resolve, and the same check on a copy with the fallback stub heading removed flags that one citation.
- Two paragraphs stayed in `SKILL.md` on purpose (AC9 keeps an invariant in a file every drain round reads): the CI-lens paragraph (`**The CI lens is static-only (\`execution: none\`).**`, under the fallback stub — so `test-execution-directive-seam.sh` (f) still reads `SKILL.md` and was not repointed) and `There is **no \`READY\`-that-merges**` (moved up from §"Escalation cause" into §"Terminal states").
- The split files carry no vendor-coupling token (their `vendor-coupling-manifest.json` allowance is 0 and the manifest is outside this job's lanes): `dispatch.md` names the runner form as `--agent loomwright:review-pr-runner "<pr-url>"` in print mode, the postmortem launch as a print-mode (`-p`) process, and the tail's call as `bash "<plugin root>/scripts/dispatch-pr-postmortem.sh"`. `bash scripts/check-vendor-coupling.sh` (new files staged): `breaches: 0`, `SKILL.md` 13 of 24.

### Subtask 2 — new homes

- `rationale:docs/rationale/review-heal.md#…` — stories RH-109 (`#check-wait-default-sizing`), RH-123 (`#why-the-dismissed-findings-marker-is-a-pr-comment`), RH-192 (`#sub-floor-residual-cost`), RH-194 (`#why-the-earned-fallback-exists`), RH-203 (`#why-the-fallback-spawn-is-legal`); restated rules RH-201, RH-202 (`#why-the-fallback-spawn-is-legal` — their rule parts are row RH-016 and `docs/RESULT_SCHEMAS.md`'s schema split). Stories with no row moved there too: `#why-check-output-skips-the-comment-classifier`, `#thread-truncation-escalates`, `#why-the-round-bound-is-a-ledger`, `#why-the-fallback-gate-sits-on-the-sub-floor-path`, `#why-the-postmortem-launches-detached`.
- Split rule: RH-109's rule part (re-measure `ci` before changing the 1200 s default; raise it past ~900 s) is the new `global` row RH-378, anchored on `**Default 1200 s — measured, not guessed.**` in §U2.5.
- `script:` — RH-066 (`review-heal-next-step.sh read`), RH-078 (`… classify`), RH-102 (`… wait`), RH-079 and RH-080 (`classify-bot-review.sh`, deterministic). Their prose left `SKILL.md`; one short line stays for each step (the `read` paragraph, the `classify` actor-allowlist line, the `wait` line).
- `step-scoped` — RH-193, RH-197, RH-200 (`fallback-review.md`), RH-221 (`escalation.md`) — below.
- `global` — every other rule row of the range: the rows still in `SKILL.md`, the stub rows RH-379 … RH-385, and the `dispatch.md` rule rows RH-231, RH-232, RH-239 … RH-244, RH-252, RH-254 (moved with their text; anchor-checked).
- File cell moved with the text: RH-193 … RH-200 to `fallback-review.md`, RH-217 … RH-221 to `escalation.md`, RH-231 … RH-254 to `dispatch.md`.
- `test-loop-inventory.sh`'s `review-heal)` arm, its header comment and the inventory's `## Sources` list the three files; the inventory intro names them.

## Pin mutations

Subtask 1 repointed and added no pin. It deleted the 35 `PROSE_PINS` lines of the 29 rows whose home left `prose`/`global` and whose text left the runtime file: RH-052, RH-259, RH-260, RH-262 … RH-266, RH-269, RH-278, RH-280 … RH-289, RH-291, RH-295, RH-296, RH-322 … RH-325, RH-328, RH-374 (RH-374's text still sits in the unedited `agents/review-pr.md`; its home is the rationale doc). Pins on the two step-scoped rows whose text stayed (RH-025, RH-305) were kept. No needle was loosened: every kept pin's literal is byte-identical.

Each row below rewrote text around a kept pin, so the mutation re-proves the pin still guards it. Every mutation ran on a `mktemp -d` scratch copy of `loomwright/` + `scripts/` (`HOME` relocated), deleting the line that carries the protected text, then running the copied `test-review-heal-next-step.sh` (or `test-loop-inventory.sh --root <scratch>/loomwright`); the original file was restored between runs. `FAIL: 5` = the P miss plus the leg's own four mutation controls, which refuse a copy that already misses a pin.

| Pin | Mutation (one line, applied to the protected text the pin guards) | Red result |
|-----|-------------------------------------------------------------|------------|
| `test-review-heal-next-step.sh` P — RH-020 | delete `The runner is **NEVER Task-spawned**.` from `SKILL.md` (sentence rewritten around it) | rc=1, `P: pinned rule text missing — RH-020 skills/review-heal/SKILL.md: The runner is **NEVER Task-spawned**.`, `PASS: 143 FAIL: 5` |
| `test-review-heal-next-step.sh` P — RH-310 | delete the `**Without \`--until-mergeable\` the behavior above is byte-for-byte …(AC7).**` line from `commands/review-pr.md` | rc=1, `P: pinned rule text missing — RH-310 commands/review-pr.md: …`, `PASS: 143 FAIL: 5` |
| `test-review-heal-next-step.sh` P — RH-275 | delete `- **Blocking READY on a human.**` from `SKILL.md` `## Anti-Patterns` (list cut to five) | rc=1, `P: pinned rule text missing — RH-275 skills/review-heal/SKILL.md: **Blocking READY on a human.**`, `PASS: 143 FAIL: 5` |
| `test-review-heal-next-step.sh` P — RH-012 | delete the `Under \`--until-mergeable\` the block stays **\`schema_version: 2\`**` line (field list replaced by a pointer) | rc=1, `P: pinned rule text missing — RH-012 skills/review-heal/SKILL.md: Under …`, `PASS: 143 FAIL: 5` |
| `test-review-heal-next-step.sh` P — RH-001 | delete the intro line `The **single source of truth** for the standalone PR review-and-heal loop…` (intro rewritten) | rc=1, `P: pinned rule text missing — RH-001 …` and `RH-002 …` (the deleted line carried both rows' rules), `PASS: 143 FAIL: 5` |
| `test-loop-inventory.sh` — RH-268 (new `global` row) | delete `- **Claiming READY when any gated channel signal is unknown.**` from `SKILL.md` (mutant 643 lines vs 644) | rc=1, `FAIL RH-268: anchor not found in skills/review-heal/SKILL.md`, `loop-inventory: FAIL — 1 problem(s)`; control with the original restored: `loop-inventory: OK — 2224 rows across 4 groups` |

The release-refold, rounds-seam and no-self-matching-wait seams read text subtask 1 kept in place (the Fork-aware same-repo bullet lost only its `(#512)` tag; the Step 2 fix-worker prompt is byte-identical); their own mutants stay red: `test-release-refold.sh` `RESULT: 26 passed, 0 failed`, `test-phase45-rounds-seam.sh` `61 passed, 0 failed`, `test-no-self-matching-wait.sh` `5 passed, 0 failed`.

### Subtask 2

Subtask 2 deleted 8 pins whose row left `prose`/`global` and whose text left the runtime file: RH-066 (`script:`), RH-109, RH-123, RH-192, RH-194, RH-203 (stories), RH-201, RH-202 (restatements). It repointed 13 pins to the split files (RH-195 … RH-200 to `fallback-review.md`, RH-219 and RH-220 to `escalation.md`, RH-237, RH-241, RH-243, RH-244 and RH-254 to `dispatch.md`; the two step-scoped rows RH-197 and RH-200 keep theirs) and added 15 (RH-378, and heading + pointer line for RH-379 … RH-385). No needle was loosened: every repointed literal is byte-identical. The P leg's mutation control copies a scratch tree that had to carry the split files for its "unmutated copy already misses a pin" guard to stay meaningful, so its `cp` of `skills/review-heal/SKILL.md` became `skills/review-heal/*.md` (one line, outside the table). The four family mutants stay red (`P mutation: deleting … turns P red` ×4).

Each mutation ran on a `mktemp -d` scratch copy of `loomwright/` + `scripts/` (`HOME` relocated), deleting the line carrying the pinned literal, then the copied test; the file was restored between runs.

| Pin | Mutation (one line, applied to the protected text the pin guards) | Red result |
|-----|-------------------------------------------------------------|------------|
| `test-review-heal-next-step.sh` P — RH-195 (repointed to `fallback-review.md`) | delete the line carrying the pinned literal from `skills/review-heal/fallback-review.md` | rc=1, `P: pinned rule text missing — RH-195 skills/review-heal/fallback-review.md: `bot_findings` (the §U1 UNION across reviews/latestReviews/re`, `PASS: 143 FAIL: 5` |
| `test-review-heal-next-step.sh` P — RH-196 (repointed to `fallback-review.md`) | delete the line carrying the pinned literal from `skills/review-heal/fallback-review.md` | rc=1, `P: pinned rule text missing — RH-196 skills/review-heal/fallback-review.md: every **review-producing** check (§U2.5's classification) is `, `PASS: 143 FAIL: 5` |
| `test-review-heal-next-step.sh` P — RH-197 (repointed to `fallback-review.md`) | delete the line carrying the pinned literal from `skills/review-heal/fallback-review.md` | rc=1, `P: pinned rule text missing — RH-197 skills/review-heal/fallback-review.md: **The issue-comment channel is authoritative for "posted"; nev`, `PASS: 143 FAIL: 5` |
| `test-review-heal-next-step.sh` P — RH-198 (repointed to `fallback-review.md`) | delete the line carrying the pinned literal from `skills/review-heal/fallback-review.md` | rc=1, `P: pinned rule text missing — RH-198 skills/review-heal/fallback-review.md: **Effect — exactly one fallback review per drain run.**`, `PASS: 143 FAIL: 5` |
| `test-review-heal-next-step.sh` P — RH-199 (repointed to `fallback-review.md`) | delete the line carrying the pinned literal from `skills/review-heal/fallback-review.md` | rc=1, `P: pinned rule text missing — RH-199 skills/review-heal/fallback-review.md: **Fail-CLOSED direction is TO RUNNING the review`, `PASS: 143 FAIL: 5` |
| `test-review-heal-next-step.sh` P — RH-200 (repointed to `fallback-review.md`) | delete the line carrying the pinned literal from `skills/review-heal/fallback-review.md` | rc=1, `P: pinned rule text missing — RH-200 skills/review-heal/fallback-review.md: **Why the `Task(loomwright:code-reviewer)` spawn is legal here`, `PASS: 143 FAIL: 5` |
| `test-review-heal-next-step.sh` P — RH-219 (repointed to `escalation.md`) | delete the line carrying the pinned literal from `skills/review-heal/escalation.md` | rc=1, `P: pinned rule text missing — RH-219 skills/review-heal/escalation.md: only human-judgment findings `, `PASS: 143 FAIL: 5` |
| `test-review-heal-next-step.sh` P — RH-220 (repointed to `escalation.md`) | delete the line carrying the pinned literal from `skills/review-heal/escalation.md` | rc=1, `P: pinned rule text missing — RH-220 skills/review-heal/escalation.md: release re-fold refused (#512), required-check metadata unavailable`, `PASS: 143 FAIL: 5` |
| `test-review-heal-next-step.sh` P — RH-237 (repointed to `dispatch.md`) | delete the line carrying the pinned literal from `skills/review-heal/dispatch.md` | rc=1, `P: pinned rule text missing — RH-237 skills/review-heal/dispatch.md: The runner reads these env vars and **translates them into the corres`, `PASS: 143 FAIL: 5` |
| `test-review-heal-next-step.sh` P — RH-241 (repointed to `dispatch.md`) | delete the line carrying the pinned literal from `skills/review-heal/dispatch.md` | rc=1, `P: pinned rule text missing — RH-241 skills/review-heal/dispatch.md: The loop's `decision` is **computed and emitted BEFORE** the tail run`, `PASS: 143 FAIL: 5` |
| `test-review-heal-next-step.sh` P — RH-243 (repointed to `dispatch.md`) | delete the line carrying the pinned literal from `skills/review-heal/dispatch.md` | rc=1, `P: pinned rule text missing — RH-243 skills/review-heal/dispatch.md: `/pr-postmortem` is **read-only** on the analyzed repo and **only app`, `PASS: 143 FAIL: 5` |
| `test-review-heal-next-step.sh` P — RH-244 (repointed to `dispatch.md`) | delete the line carrying the pinned literal from `skills/review-heal/dispatch.md` | rc=1, `P: pinned rule text missing — RH-244 skills/review-heal/dispatch.md: `postmortem_dispatched` is informational, NEVER a gate input`, `PASS: 143 FAIL: 5` |
| `test-review-heal-next-step.sh` P — RH-254 (repointed to `dispatch.md`) | delete the line carrying the pinned literal from `skills/review-heal/dispatch.md` | rc=1, `P: pinned rule text missing — RH-254 skills/review-heal/dispatch.md: The tail's exit status is **ignored**`, `PASS: 143 FAIL: 5` |
| `test-review-heal-next-step.sh` P — RH-378 (new pin, `SKILL.md`) | delete the line carrying the pinned literal from `skills/review-heal/SKILL.md` | rc=1, `P: pinned rule text missing — RH-378 skills/review-heal/SKILL.md: **Default 1200 s — measured, not guessed.**`, `PASS: 143 FAIL: 5` |
| `test-review-heal-next-step.sh` P — RH-379 (new pin, `SKILL.md`) | delete the line carrying the pinned literal from `skills/review-heal/SKILL.md` | rc=1, `P: pinned rule text missing — RH-379 skills/review-heal/SKILL.md: Moved to `skills/review-heal/fallback-review.md` — read it only when t`, `PASS: 143 FAIL: 5` |
| `test-review-heal-next-step.sh` P — RH-380 (new pin, `SKILL.md`) | delete the line carrying the pinned literal from `skills/review-heal/SKILL.md` | rc=1, `P: pinned rule text missing — RH-380 skills/review-heal/SKILL.md: Moved to `skills/review-heal/escalation.md` — read it only when the ru`, `PASS: 143 FAIL: 5` |
| `test-review-heal-next-step.sh` P — RH-381 (new pin, `SKILL.md`) | delete the line carrying the pinned literal from `skills/review-heal/SKILL.md` | rc=1, `P: pinned rule text missing — RH-381 skills/review-heal/SKILL.md: Moved to `skills/review-heal/dispatch.md` — the dispatching side`, `PASS: 143 FAIL: 5` |
| `test-review-heal-next-step.sh` P — RH-382 (new pin, `SKILL.md`) | delete the line carrying the pinned literal from `skills/review-heal/SKILL.md` | rc=1, `P: pinned rule text missing — RH-382 skills/review-heal/SKILL.md: ### Cardinal guarantee (AC12, R9)`, `PASS: 143 FAIL: 5` |
| `test-review-heal-next-step.sh` P — RH-383 (new pin, `SKILL.md`) | delete the line carrying the pinned literal from `skills/review-heal/SKILL.md` | rc=1, `P: pinned rule text missing — RH-383 skills/review-heal/SKILL.md: ### Churn gate (AC9/AC10/AC11) — fires only on meaningful churn`, `PASS: 143 FAIL: 5` |
| `test-review-heal-next-step.sh` P — RH-384 (new pin, `SKILL.md`) | delete the line carrying the pinned literal from `skills/review-heal/SKILL.md` | rc=1, `P: pinned rule text missing — RH-384 skills/review-heal/SKILL.md: ### Opt-out (AC13)`, `PASS: 143 FAIL: 5` |
| `test-review-heal-next-step.sh` P — RH-385 (new pin, `SKILL.md`) | delete the line carrying the pinned literal from `skills/review-heal/SKILL.md` | rc=1, `P: pinned rule text missing — RH-385 skills/review-heal/SKILL.md: ### Launch form (R10 — fresh detached process, NEVER a nested Task)`, `PASS: 143 FAIL: 5` |
| `test-loop-inventory.sh` — the `review-heal)` arm | remove `skills/review-heal/fallback-review.md` from the arm in a scratch copy, then `test-loop-inventory.sh --root <scratch>/loomwright` | rc=1, `FAIL review-heal: ## Sources lists skills/review-heal/fallback-review.md, which is not a source of the group`, then `FAIL RH-193: file 'skills/review-heal/fallback-review.md' is not a source of the review-heal group` (and RH-195 … RH-200), `loop-inventory: FAIL — 8 problem(s)`; control with the arm restored: `loop-inventory: OK — 2232 rows across 4 groups` |
| `test-dispatch-pr-review.sh` drift guard — read repointed to `skills/review-heal/*.md` | append a line naming `` `scripts/not-admitted-probe.sh` `` to `fallback-review.md` in a scratch copy | rc=1, `drain allowlist shape wrong: script-not-admitted:not-admitted-probe.sh`, `RESULT: 51 passed, 1 failed` |

The seams whose text stayed in `SKILL.md` were not repointed: `test-rules-gate-seams.sh` (§U4 rules block, READY clause), `test-automate-dismissed.sh` leg B (the marker bullet), `test-phase45-rounds-seam.sh` and `test-no-self-matching-wait.sh` (the Step 2 and §U4 fix-worker prompts), `test-release-refold.sh` (both `push_fix_to_pr()` call sites) and `test-execution-directive-seam.sh` (f) (the CI-lens paragraph); all stay green with their own mutants (gate table below).

## Step-scoped anchors

`test-loop-inventory.sh` does not anchor-check `step-scoped` rows, so each was checked by hand (`grep -nF` of the anchor in its file):

- RH-023 — `skills/review-heal/SKILL.md` Step 1, detached-drain bullet: `The runner therefore **does NOT run its own \`git checkout "$HEAD_REF"\`**` — ok.
- RH-025 — `skills/review-heal/SKILL.md` Step 1: `The review scope is the PR diff:` — ok.
- RH-040 — `skills/review-heal/SKILL.md` Step 2 fix-worker prompt: `Address ONLY these new review findings at or above the fix floor` — ok.
- RH-041 — `skills/review-heal/SKILL.md` Step 2 fix-worker prompt: ``never `pgrep -f`/`pkill -f <pattern>` with <pattern> in your own command`` — ok.
- RH-305 — `commands/review-pr.md` What This Does, review step: `` `Task(loomwright:code-reviewer)` reviews the PR-branch diff `` — ok.

Subtask 2 (`grep -nF` of the anchor in its file):

- RH-193 — `skills/review-heal/fallback-review.md` heading `### Earned Fallback Review — \`no_review_lens_posted\` (AC3, PINNED)` — ok (line 5).
- RH-197 — `skills/review-heal/fallback-review.md`: `**The issue-comment channel is authoritative for "posted"; never gate on \`--json reviews\` alone.**` — ok (line 16; also P-pinned).
- RH-200 — `skills/review-heal/fallback-review.md`: ``**Why the `Task(loomwright:code-reviewer)` spawn is legal here`` — ok (line 22; also P-pinned).
- RH-221 — `skills/review-heal/escalation.md`: ``The cause is informational — it never changes `decision`, and nothing here reruns a check`` — ok (line 15).

## Subtask 1 gate runs

| Gate | Result |
|---|---|
| `bash loomwright/scripts/test-loop-inventory.sh` | rc=0, `loop-inventory: OK — 2224 rows across 4 groups` |
| `bash loomwright/scripts/test-review-heal-next-step.sh` | rc=0, `PASS: 148 FAIL: 0` |
| `bash loomwright/scripts/test-phase45-rounds-seam.sh` | rc=0, `61 passed, 0 failed` |
| `bash loomwright/scripts/test-no-self-matching-wait.sh` | rc=0, `5 passed, 0 failed` |
| `bash loomwright/scripts/test-release-refold.sh` | rc=0, `RESULT: 26 passed, 0 failed` |
| `bash loomwright/scripts/test-citation-drift.sh` | rc=0, `citation-drift: 26 passed, 0 failed` |
| `bash loomwright/scripts/test-execution-directive-seam.sh` | rc=0, `RESULT: 50 passed, 0 failed` |
| `bash loomwright/scripts/test-rules-gate-seams.sh` | rc=0, `26 passed, 0 failed` |
| `bash loomwright/scripts/test-automate-dismissed.sh` | rc=0, `246 passed, 0 failed` |
| `bash loomwright/scripts/test-dispatch-pr-review.sh` | rc=0, `RESULT: 52 passed, 0 failed` |
| `bash loomwright/scripts/test-closed-enum-pins-seam.sh` | rc=0, `79 passed, 0 failed` |
| `bash loomwright/scripts/test-drain-rounds.sh` | rc=0, `35 passed, 0 failed` |
| `bash scripts/check-doc-currency.sh` | rc=0 |
| `bash scripts/check-token-budget.sh` | rc=0, `breaches: 0` |
| `bash scripts/check-vendor-coupling.sh` | rc=0, `breaches: 0` (the rationale doc names no install-root token: the headless launch is described without the literal CLI form) |

## Subtask 2 gate runs

| Gate | Result |
|---|---|
| `bash loomwright/scripts/test-loop-inventory.sh` | rc=0, `loop-inventory: OK — 2232 rows across 4 groups`, `RESULT: 43/43 passed` |
| `bash loomwright/scripts/test-review-heal-next-step.sh` | rc=0, `PASS: 148 FAIL: 0` (`P: all 219 prose pins present`; `every one of the 173 prose rows that names this test has a pin`) |
| `bash loomwright/scripts/test-execution-directive-seam.sh` | rc=0, `RESULT: 50 passed, 0 failed` |
| `bash loomwright/scripts/test-no-self-matching-wait.sh` | rc=0, `5 passed, 0 failed` |
| `bash loomwright/scripts/test-phase45-rounds-seam.sh` | rc=0, `61 passed, 0 failed` |
| `bash loomwright/scripts/test-release-refold.sh` | rc=0, `RESULT: 26 passed, 0 failed` |
| `bash loomwright/scripts/test-rules-gate-seams.sh` | rc=0, `26 passed, 0 failed` |
| `bash loomwright/scripts/test-automate-dismissed.sh` | rc=0, `246 passed, 0 failed` |
| `bash loomwright/scripts/test-dispatch-pr-review.sh` | rc=0, `RESULT: 52 passed, 0 failed` |
| `bash loomwright/scripts/test-closed-enum-pins-seam.sh` | rc=0, `79 passed, 0 failed` |
| `bash loomwright/scripts/test-drain-rounds.sh` | rc=0, `35 passed, 0 failed` |
| `bash loomwright/scripts/test-citation-drift.sh` | rc=0, `citation-drift: 26 passed, 0 failed` |
| `bash scripts/check-doc-currency.sh` | rc=0 |
| `bash scripts/check-token-budget.sh` | rc=0, `check-token-budget: OK` |
| `bash scripts/check-vendor-coupling.sh` (split files staged) | rc=0, `breaches: 0` |
| `bash scripts/check-skills-index-sync.sh` | rc=0 |

## Behaviour questions

Recorded, not fixed (AC10 — move-only change).

1. *(subtask 1)* `SKILL.md` cited §"Postmortem Dispatch Tail" (Pinned Canonical Names, and one line in the until-mergeable range), but no heading of that name exists in the file; `scripts/dispatch-pr-postmortem.sh`'s header and `docs/result-schemas/review-heal-result.md` cite it too. Subtask 1's table cells now cite §"Churn gate", the postmortem dispatch section; the until-mergeable-range citation is subtask 2's, and the script header and schema doc are outside this job's lanes.
2. *(subtask 1)* Inventory row RH-313's action says check-run output yields findings only when user-scope listed; neither the base nor the new `commands/review-pr.md` text says so (the rule, if it holds, lives in the until-mergeable range). The cell was left as it was.
3. *(subtask 1)* `agents/review-pr.md` is a non-goal, so it still restates what left the command and skill (its env-var table, outcome model, `## Related` list). The runner therefore still reads that restated text on the dispatched path; its rule rows are `global` in place.
4. *(subtask 1)* Who owns the `REVIEW_HEAL_RESULT` v2 field list is stated both ways. At base, `SKILL.md` already said "the authoritative schema text lives in `docs/RESULT_SCHEMAS.md`", while `docs/result-schemas/review-heal-result.md` §"No re-coining" says the v2 fields "match `skills/review-heal/SKILL.md` exactly … (it is authoritative)". Subtask 1 replaced the skill's restated field list with a pointer to `docs/RESULT_SCHEMAS.md`, so `channels_scanned`, `checks_waited`, `escalation_run_id`, `escalation_attempt` and `escalation_sha` are no longer named in `SKILL.md` (the driver writes them; no test reads them from the skill). The schema doc's sentence is outside this job's lanes and was left as it was.
5. *(subtask 2)* Behaviour question 1's in-range citation (`SKILL.md` §U4's `severity_rank` line cited §"Postmortem Dispatch Tail") now cites §"Churn gate" in `skills/review-heal/dispatch.md`, the section that names `repeat_check_failure` and `unresolved_bot_feedback`. `scripts/dispatch-pr-postmortem.sh`'s header and `docs/result-schemas/review-heal-result.md` still cite the missing heading (outside this job's lanes).
6. *(subtask 2)* `agents/review-pr.md` (not editable here) cites the "spawn-depth reachability argument" at `review-heal` §"Earned Fallback Review — `no_review_lens_posted`". That heading is now a `SKILL.md` stub pointing at `fallback-review.md`, which keeps the one-line rule; the full argument moved to `docs/rationale/review-heal.md` §"Why the fallback spawn is legal". The citation resolves through the stub, one hop longer.
7. *(subtask 2)* `dispatch.md` §"Launch form" still shows the bare `/pr-postmortem` in the dispatcher's launch line while row RH-252 notes that the dispatcher test pins the namespaced form; moved as it was, not reconciled.
8. *(subtask 2)* The CI-lens label `CI review lens: static-only (execution: none)` is emitted by the driver's `notify` step (`scripts/review-heal-next-step.sh`) in the terminal comment and the notification, so the `SKILL.md` paragraph restates what that step does. It was kept in `SKILL.md` (AC9 lists the static-only lens among the invariants that must stay in a drain-read file), not given a `script:` home.

## Proposed hooks

None filed under `.supervisor/requirements/proposed/` by subtask 1: every rule row in its range got an existing home (`global`, `step-scoped`, `script:` or a restatement's `rationale:`), so no rule was left in prose waiting on a new hook.

None filed by subtask 2 either: every rule row in its range got an existing home (`global`, `step-scoped`, `script:` or a restatement's `rationale:`).
