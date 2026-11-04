<!-- bump: minor -->
Dismissed findings are asked only when they can still change the PR
At an `/automate` park the owner no longer answers each dismissed finding one by one. A per-finding draft whose
severity is LOW or INFO, and every draft once no fix-now re-drain is available, is recorded `follow-up` with no
question through `dismissed-decide … follow-up --auto`, which now accepts per-finding drafts as well as summaries.
The MEDIUM-or-higher drafts a fix-now could still change are asked in ONE `AUT-DISMISS` question that lists them
numbered, with the options `Fix none (follow-up all)`, `Fix all listed on this PR` and, when two or more are listed,
`Fix selected on this PR` (the answer's note names the numbers; an empty, non-numeric or out-of-range note is
refused with exit 2 and nothing written). An unspecified or missing severity counts as MEDIUM or higher. At PICK
every undecided draft of the run is recorded `follow-up` automatically, so `AUT-PENDING` asks only about a draft
whose automatic follow-up was refused. Under `--non-interactive` or a `cant_ask` answer the MEDIUM-or-higher drafts
stay undecided, as before; a post-park `refuse` gate line or a refused run lock writes nothing. The park
instruction gains an additive `auto_followed_up` array (the draft paths recorded automatically), and its message
names their count and the hand-drop command `automate-helpers.sh dismissed-decide <runfile> <draft> drop`; the
owner's later drop wins. Every ledger row `--auto` writes now ends with a 4th column `auto`, so an automatic
follow-up is told apart from an owner's answer. This includes the existing summary auto-keep rows, a deliberate
small extension: every ledger reader still takes column 2 as the decision.
