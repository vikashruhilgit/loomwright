<!-- bump: patch -->
Inline phases: a checkpointed item resumes with --continue too
The `--continue` resume for a checkpointed item now also covers `--inline-phases`. Before, under that flag
`automate-next-step.sh` re-ran `/autonomous --single-iteration --requirement <item>` (a fresh Launch Pad) on such an
item. The inline line could not be detected either: an inline RUN reports /autonomous's `supervisor_checkpoint`
token, not `checkpoint`, and no `launch-pad saved` line names the task. Now three things change. The checkpoint read
accepts `supervisor_checkpoint`. The no-PR line gains `; resume with /supervisor --continue task: <task_id>`, taken
from the reported SUPERVISOR_RESULT, when the one-line why does not already name the task; the inline RUN `then`
asks for that block after a checkpoint. `run` prints an inline `/loomwright:supervisor --continue task: <id>` spawn
with /autonomous's /supervisor forward set: `--non-interactive` where /autonomous would get
`--non-interactive-fallback`, plus `--cheap` and `--max-tokens N`. `--notify` is dropped: Supervisor has no such
flag, /autonomous never forwards it, and its gate webhooks fire only at /autonomous-layer gates, which a resume does
not reach. Driver leg F4i covers the path from the RUN report to the re-pick; mutants M9g, M9h and M9i each turn it
red.
