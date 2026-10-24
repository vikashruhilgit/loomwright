# backlog-state fixtures

Hermetic inputs for `test-automate-helpers.d/18-backlog.sh` (parallel-automate/18a: `item-state`,
`backlog`, `backlog-stamp`). The test copies `tree/` into a `mktemp -d` root, renaming `dot-supervisor`
to `.supervisor` (the repo ignores dot-paths in fixtures, the `automate-golden` convention); no test
reads the live `.supervisor/requirements/`.

Every file is synthetic: written for these tests, not copied from a real requirement, with no home path
and no harness-specific wording.

- `tree/dot-supervisor/requirements/` — the items below, plus five files the item set skips
  (`bl/00-index.md`, `bl/_notes.md`, `bl/README.md`, `operator-run/op-01.md`, the top-level task plan
  `bl-plan.md`), so 28 files make 23 items.
- `tree/dot-supervisor/automate/` — five run files: `automate-2026-09-01-100000` (done: a plain
  check-off and four `# abandoned:` rows), `automate-2026-10-01-100000` (done: a later `# skipped:` row
  and a `fleet closeout` line), and three unfinished runs whose `## Current` names `bl/03-parked`
  (paused), `bl/09-pr-open` (an open PR) and `bl/17-in-flight` (no PR).
- `tree/dot-supervisor/jobs/done/` — one done brief pointing at `bl/14-open` (the `- **Brief:**` line
  `backlog-stamp done` writes).
- `gh/merged.json`, `gh/open.json` — what the stubbed `gh pr list --state merged|open` prints. Two
  merged PRs are decoys that a substring match would wrongly take as merge evidence: #901 (title
  `feat(verify): spec replay`, which contains the id-less basename `spec`) and #902 (head
  `feature/x11-conflict`, title `fix: x11-conflict cleanup`: both hold `11-conflict`, but not at a
  token boundary).
- `lane-status.json` — what the stubbed `lane-status --json` prints: a running lane L2 on `bl/10-lane`
  and a removed lane L3 on `bl/14-open` (a removed lane is no claim).

The state each item must read. The test parses this table, so it is the expected answer.

| Item | State | Why |
|---|---|---|
| `bl/01-done-appended` | `done` | first line `pending`, a closeout done stamp appended below |
| `bl/02-abandoned` | `abandoned` | `## Status: done_with_escalation — ABANDONED (…)` |
| `bl/03-parked` | `parked` | `## Status: parked`; the paused run naming it is listed `stale_run` |
| `bl/04-proposed` | `proposed` | `## Status: proposed` |
| `bl/05-brief-shipped` | `brief_shipped` | `## Status: brief-shipped`; merged PR #105 is a candidate, not a match |
| `bl/06-merged-unstamped` | `merged_unstamped` | a plain `- [x]` row in the 09-01 run |
| `bl/07-merged-pr` | `merged_unstamped` | merged PR #107's head branch ends with `-<slug>` (an id-prefixed slug) |
| `bl/08-fleet` | `merged_unstamped` | a `fleet closeout: L1 … done (PR …)` line |
| `bl/09-pr-open` | `pr_open` | named by an unfinished run's `## Current`, PR #109 in the open list |
| `bl/10-lane` | `in_flight` | lane L2 in `lane-status.json` |
| `bl/11-conflict` | `conflict` | `pending`, abandoned by the 09-01 run, no Kept-open marker; decoy PR #902 must not mask it |
| `bl/12-kept-open` | `open` | abandoned by the 09-01 run, kept open on 2026-09-01 (the same date) |
| `bl/13-kept-reraised` | `conflict` | kept open on 2026-09-01, then skipped by the later 10-01 run |
| `bl/14-open` | `open` | `## Status: ready`; the only item with a `## Touches` section |
| `bl/15-unknown` | `unknown` | no status line |
| `bl/16-off-enum` | `unknown` | `## Status: in review — PR #9` |
| `bl/17-in-flight` | `in_flight` | named by an unfinished run's `## Current`, no PR |
| `bl/spec` | `open` | `## Status: pending`; decoy PR #901's title contains `spec`, an id-less basename (no evidence) |
| `pk/01-merged-into` | `done` | `parked (merged … into \`pk/02-target.md\` …)`, and that target is done |
| `pk/02-target` | `done` | `## Status: done (PR #102, …)` |
| `pk/03-cycle-a` | `unknown` | parked into `pk/04-cycle-b`, which is parked back into it |
| `pk/04-cycle-b` | `unknown` | the other half of the cycle |
| `proposed/bl-draft` | `proposed` | a file under `proposed/`, no status line |
