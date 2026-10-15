<!-- bump: patch -->
/automate Step 0 loads the automate-loop split files conditionally, by run mode
`commands/automate.md` Step 0 no longer reads every automate-loop split file on every run. It keeps the documented
order but labels each file **Always** (`per-item-loop.md`, `modes-and-merge-gate.md`, `invariants.md`) or **Only when**
with a trigger the run can observe (each one named in `commands/automate.md` Step 0, the one authority for which file is
read when). So a one-item sequential fresh run no longer loads `resume.md`, `branch-mode.md`, `lanes.md` or
`command-lanes.md` (about 85K chars it never used). Step 0 also says to read plugin files with the Read tool, one per
call, never several via `cat` in one Bash call (an oversized result is saved and read back, loading the text twice); to
run the two always-run start steps it names, `meta-entry` and `lane-info`; and, on a NEW run, to create
`.supervisor/automate` before `pick-guard`, a start-order step that used to live only in the resume split file. The
`SKILL.md` split-layout note now points at Step 0 instead of restating it. Only the timing of the reads changed; no split
file's text changed, and `test-automate-loop-split.sh` is untouched and green.
