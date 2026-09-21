# 05 — Itemised dismissed findings, persisted where the postmortem can read them

## Status: pending

## Problem
Phase 4.5 self-heal (`skills/self-heal-advisory/SKILL.md`) and the `/review-pr` drain (`skills/review-heal/SKILL.md`
§U3.5 Validate-Then-Fix) fix findings they confirm and COUNT the rest — `findings_dismissed: int` already exists in
`REVIEW_HEAL_RESULT` — but nothing records WHICH findings were dismissed or why. Dismissals are where post-merge churn
originates, and `/pr-postmortem` cannot see them: its only input is `scripts/pr-postmortem-gather.sh` (= `gh pr view` /
`gh api` JSON), and `REVIEW_HEAL_RESULT` is never persisted by `dispatch-pr-review.sh` (the marker holds URL +
timestamp). A result-block field alone has no transport to the postmortem (decision H4).

## Goal
Every dismissed finding is itemised in the result block AND posted once to the PR as a marker-tagged comment that the
drain recognises as its own (never re-ingested) and `/pr-postmortem` reads as a classification input. Zero dismissals
⇒ no field, no comment, byte-identical.

## Scope
1. **`loomwright/docs/RESULT_SCHEMAS.md`:** keep `findings_dismissed: int`. Add optional additive
   `dismissed: [{finding: string, reason: string, source: string}]` to §REVIEW_HEAL_RESULT (v2, drain fields group)
   and to §SUPERVISOR_RESULT's self-heal block (`heal_dismissed: […]`, same item shape — different name because the
   block is flat and already prefixes `heal_*`). `source` is the review channel that produced the finding
   (`reviews | reviewThreads | issue_comments | check_outputs | code_reviewer | red_team | voter:<provider>` — read the
   existing channel enum in §"All-Channel Read" and reuse its spellings). `schema_version` unchanged (2 / 1).
   "Empty ⇒ absent" rule stated.
2. **`skills/review-heal/SKILL.md`:** §U3.5 case 4 records `{finding, reason, source}` into the `dismissed[]`
   accumulator the pseudocode already carries (`dismissed = []` … `dismissed += […]`) — it exists but is never
   emitted; emit it. **Marker comment:** at the end of each round with ≥1 new dismissal, post ONE
   `gh pr comment` whose body starts with `<!-- loomwright:dismissed round=<n> -->` followed by the itemised list.
   **Self-skip (MUST):** §U1's `classify(issue_comments)` drops any comment whose body starts with that marker
   BEFORE classification — the drain runs under the operator's own `gh` login, so §U3 would otherwise classify its
   own comment as HUMAN-authored and surface it every round. Mechanise the drop in
   `scripts/classify-bot-review.sh` (a `--skip-marker '<!-- loomwright:'` prefix filter, default ON) so the model
   does not have to remember it. `review-pr` budget 1737 headroom — re-measure.
3. **`skills/self-heal-advisory/SKILL.md`** Part 2 loop: the same itemisation for Phase 4.5's code-reviewer /
   red-team / voter findings the fix worker judged wrong or noise (the "Do NOT touch pre_existing issues or nits"
   step is where the judgment already happens); emit `heal_dismissed` in SUPERVISOR_RESULT; post the same marker
   comment on the PR once at completion-tail time. `supervisor` budget 2412 — re-measure.
4. **`loomwright/scripts/pr-postmortem-gather.sh`:** extract marker comments into a new top-level key
   `dismissed_findings: [{round, finding, reason, source}]` (jq-built, `[]` when none; fail-safe). Parse ONLY the
   fixed marker + `- **<finding>** — <reason> (<source>)` bullet shape you emit in 2/3; anything else ⇒ `[]`.
5. **`loomwright/commands/pr-postmortem.md`:** the classifier gains one input: a dismissed finding whose text
   later appears (normalised substring match) in a HUMAN-authored review comment is its own root-cause signal
   `dismissed_then_raised` (attribute to flow stage `self_heal`); document it beside the existing six classes
   WITHOUT renumbering them (it is a sub-signal, not a seventh class, unless `POSTMORTEM_RESULT`'s class enum is
   open — read §POSTMORTEM_RESULT first and record the choice).
6. **`loomwright/scripts/result_block_parser.py` tests:** a `REVIEW_HEAL_RESULT` fixture whose `dismissed:` list
   has a flow-map item containing `: ` inside a quoted string (`{finding: "missing: null check", …}`) parses to
   the right three fields; and the SUPERVISOR_RESULT validator accepts a block with and without `heal_dismissed`.
7. **Docs:** review-heal §"Pinned Canonical Names" if it enumerates fields; CHANGELOG paragraph; version bump.

## Non-goals
No change to what is dismissed (§U3.5's four cases stand). Dismissed findings still do not block READY and are not
fixed. No `schema_version` bump. No change to `/pr-postmortem`'s read-only / append-only posture. No second comment
per round; no edit of earlier marker comments.

## Acceptance criteria
- Fixture drain round with one rejected finding ⇒ `dismissed` has one entry, `findings_dismissed: 1`, and exactly
  one marker comment (assert via `gh pr view --json comments` in the PR's own test log or a stubbed `gh`).
- The NEXT round's `classify(issue_comments)` yields 0 candidates from that comment (`classify-bot-review.sh`
  fixture with the marker body ⇒ `[]`; mutation control: with `--no-skip-marker` the same fixture is classified).
- Zero rejections ⇒ no `dismissed` key, no `heal_dismissed` key, no comment.
- `pr-postmortem-gather.sh` fixture with one marker comment ⇒ `dismissed_findings` length 1; malformed body ⇒ `[]`.
- Parser test with the `: `-inside-quotes item passes.
- `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` → the same five surfaces.
- Full test loop + root checks green.

## Verified premises (re-check before starting)
- `review-heal/SKILL.md` §U3.5 cases 1–4 and the `dismissed = []` / `dismissed += …` pseudocode lines; §U1
  `∪ classify(issue_comments)`; §U3 "Human-authored — or unknown — … NEVER block READY"; `gh pr comment` usage in
  §Step 2 / §U4.
- RESULT_SCHEMAS §REVIEW_HEAL_RESULT `findings_dismissed` field note; §SUPERVISOR_RESULT `heal_*` field family.
- `pr-postmortem-gather.sh` header output shape (`review_comments: [{author, snippet}]`) and fail-safe contract.
- `classify-bot-review.sh` exists with `[]` fail-safe (red-team-hardening/01 also edits it — coordinate if both
  queues run; this item's flag is additive).
