<!-- bump: minor -->
Split /setup, /dreaming and /agent-help into routers with on-demand part files (automate-speed/22)
`commands/setup.md`, `commands/dreaming.md` and `commands/agent-help.md` each become a router under 20 KB in the
parallel-automate/22 index convention, with the moved sections verbatim in `loomwright/docs/command-parts/<command>/`
(move-only: the assembled router + parts are byte-identical to the pre-split doc, and every moved heading stays at its
old path as an index entry). An index-only read rule tells the runtime which part to Read for each module, phase or
command, so `/setup memory` reads only the memory part and a declined `/dreaming` or a bare `/agent-help` reads none.
New `loomwright/scripts/test-command-parts.sh` (with `fixtures/command-parts/move-only.txt`) checks assembly, index
entries, orphans, heading sequence, the move-only proof, the router size bound, the read rule and the no-squash rule,
each with a mutation control. `scripts/check-token-budget.sh` now counts a command's parts into its `.commands` row
(override `TOKEN_BUDGET_COMMAND_PARTS_DIR`; an orphaned parts dir or a symlink under one fails closed), and the
`agent-help` ceiling is raised by exactly the routing overhead. `scripts/check-doc-currency.sh` also scans the
agent-help parts. The readers in `test-curation-status.sh`, `test-rules-docs.sh` and the setup-memory branch-mode
part read the assembled text. Vendor-coupling allowances move to the paths that now carry the references; the read
rules add install-root references, each counted with its reason. `classify-risk.sh` adds `command-parts/` to its
workflow-surface directories, so a parts-only edit to a split command classifies high-risk like the same edit to its
router (the `--auto-merge` gate's condition 6), and the meta-sync home-path guard scans the parts too. Measurements and the running-system transcript:
`docs/evidence/as22-split-big-commands.md`.
