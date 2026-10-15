<!-- bump: patch -->
/automate Step 0 loads the automate-loop split files conditionally, by run mode
`commands/automate.md` Step 0 no longer reads every automate-loop split file on every run. It keeps the documented
order but labels each file **Always** (`per-item-loop.md`, `modes-and-merge-gate.md`, `invariants.md`) or **Only when**
with a trigger the run can observe: a flag (`--resume`, `--parallel`), a helper's printed line (`resume-glob --finalize`
listing an incomplete run, `meta-entry` printing anything but `meta-entry: off`, `pick-guard` printing
`refuse: live_lane …`), `automate-helpers.sh lane-info` exiting 0, or a PICK's RECONCILE finding an in-flight item. So a
one-item sequential fresh run no longer loads `resume.md`, `branch-mode.md`, `lanes.md` or `command-lanes.md` (about 78K
chars it never used). Step 0 also says to read plugin files with the Read tool, one per call, never several via `cat` in
one Bash call (an oversized result is saved and read back, loading the text twice), and to run `lane-info` once at start
so a lane loads the lanes files before its first PICK. The `SKILL.md` split-layout note now points at Step 0 as the one
authority for which file is read when, instead of restating it. Only the timing of the reads changed; no split file's text
changed, and `test-automate-loop-split.sh` is untouched and green.
