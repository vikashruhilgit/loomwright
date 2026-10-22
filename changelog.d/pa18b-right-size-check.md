<!-- bump: minor -->
right-size says whether a requirement item is too small to pay a run or too big for one PR, and merge-items does the lossless hand merge
`automate-helpers.sh right-size <item|dir|item-list|plan doc>` prints one advisory line per item: `small`, `ok`,
`large` or `unknown`. It counts the companion-expanded Touches set the planner reserves (`plan-waves --touches`,
with a directory counting its files), so the size check and the planner can never read one item two ways. A
`small` item names up to three merge candidates (shared files, the same Depends on chain, or the same folder). A
candidate is never a parked, proposed, done or `operator-run/` item, and never one whose merge would make a
dependency cycle. A `large` item says `will not fit one PR: split by Part`, and a Touches-unknown item reads
`unknown`, never `small`. A plan doc also gets its section check against the skill's template, and `--json`
prints one array for a board to read. The thresholds are `right_size_small` (3), `right_size_large_files` (30)
and `right_size_max_parts` (7) in `.supervisor/config.json`, set by the owner on 2026-10-22. The evidence: S2's
five lanes cost about $17 and 4 owner questions for a small fix, up to about $40 and 8 for a large one, plus 2 to 4
hours each, so the floor is paid even by a one-file change. Of 138 past agent PRs the median touched 13 files and
90% touched 29 or fewer, and Plan Review fails a brief with more than 7 subtasks. `merge-items` replaces the
copy, park, re-point and no-line-lost steps each hand merge repeated (af/33, ms/08, af/32). It copies each original
verbatim as a Part, folds the Depends on and Touches sections, parks each original and re-points its dependents.
It writes nothing unless every original line survives; the af/33 fixture shows the four-line blockquote that hand
merge dropped. The size line now prints at folder and backlog intake in every mode, in `plan-waves --explain`
for every small placed item, after each requirement draft `pc_guarded_write` writes (stderr, fail-safe), and in
the Product Owner's persist step. The user-story-writing skill no longer says "count by hand". Nothing is blocked
and nothing is merged without the owner. Evidence: `docs/evidence/pa18b-right-size-check.md`.
