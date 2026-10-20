<!-- bump: patch -->
Fresh-phase sessions: no false phase-died, and a checkpointed item resumes with --continue
Two engine fixes from wave 7, the first live run of the fresh-session-per-phase path. First, the `_lane-run` wrapper
(`automate-lanes.d/launch.sh`, shared by phase sessions and lanes) decided "no result line, write `.died`" from the
exit status of `tail | grep -q` under the script's `pipefail`. When a result line came early in a stream larger than
a pipe holds, grep's first-match exit made tail die of SIGPIPE (141), the pipeline read as failed, and a session that
had finished got a `.died` marker, so `phase-wait` exited 6. That happened to lane L22's Supervisor phase after it
had opened its PR. The wrapper now reads a `grep -c` count, which consumes the stream to EOF, instead of a pipeline's
exit status. Test AN21 reproduces the 141 path (a 1.6 MB stream with the result line second); its mutant puts the
old line back and must write the false `.died`. Second, `automate-next-step.sh` re-picked an item whose last RUN had
checkpointed (`ran /autonomous — no PR: checkpoint (… --continue task: <id>)`) and printed a fresh Launch Pad
spawn, although the brief was in `.supervisor/jobs/in-progress/` and the feature branches held the finished
subtasks (lane L23). Under fresh phases, PICK and `--start run` now resume such an item with the Supervisor phase
spawn `/loomwright:supervisor --continue task: <id>`. The id comes from the line's `--continue task:`, else from the
name of the brief saved before it. The rule needs both the checkpoint line and the in-progress brief. A newer
`launch-pad saved` line supersedes the checkpoint. With no in-progress brief the item is planned afresh, as before.
Driver leg F4 and mutants M9e/M9f cover it. `--inline-phases` is unchanged.
