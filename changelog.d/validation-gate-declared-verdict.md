<!-- bump: minor -->
The validation gate accepts committed evidence with a declared verdict
`validation-gate` and `lane-readiness` read the PR body first, exactly as before, and a body PASS or FAIL stays final. A
"Running system" step the body leaves not run is now looked up in the `docs/evidence/*.md` files the PR adds or changes,
read at the PR head through the same `gh` seam. A file counts only through a declared line at column 0, outside any
fence: `Verdict: <PASS|FAIL|NOT-RUN> for Validation <n>`. A declared PASS also needs fenced output. The gate never infers
the step or the result from headings or from words in the output, so expected `FAIL` output in a fixture no longer
fails the step. When several changed files declare the same step, the worst declared result wins. A file the PR does not
change is never used. An unreadable changed-file list, directory listing or file fails closed with its reason, and the
gate still prints one line and exits 0. The `ok` line names each file-evidenced step and its file. An `unrun` step's
text now ends in the remedy: add the verdict line and the fenced output to the step's `docs/evidence/` file, never paste
into the PR body. The lookup lives in a new module, `automate-lanes.d/evidence.sh`, called only from the one shared
Validation reader, `_lanes_validation_rows`. It makes no `gh` call when the body evidences every step, and none from the
waiver or the no-PR pre-check.
