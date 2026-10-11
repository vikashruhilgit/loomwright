<!-- bump: minor -->
Split the /automate engine's shared doc surfaces by concern, move-only, with an anchor index at every old path (parallel-automate/22)
`skills/automate-loop/SKILL.md` is now the skill's index: §2 lives in `intake.md`, §4–§5 in `resume.md`, §6–§8 in
`per-item-loop.md`, §9–§10 in `modes-and-merge-gate.md`, §11 in `invariants.md`, §13 in `branch-mode.md` and §14 in
`lanes.md`, each moved verbatim; §1, §1.5, §3, §12, Anti-Patterns, Related Skills and Quality Gates stay in the index,
and every moved heading keeps an index entry (the heading plus one `See [<file>](<file>).` line), so every existing
`§N` / quoted-anchor citation still resolves at the old path. `commands/automate.md`'s lanes section moved to
`skills/automate-loop/command-lanes.md`, and its Step 0 now names every split file to read. The AUTOMATE_RUN doc keeps
its run-file layout and `## Current` fields in `docs/result-schemas/automate-run.md` and moves the other sections into
`docs/result-schemas/automate-run/`. The skill's version moves 1.16.0 -> 1.17.0. A new `test-automate-loop-split.sh`
checks the index entries, orphan files, the heading sequence, Step 0, that every citation of the three surfaces in the
tracked tree resolves, that the tests reading moved text read the documented-order assembly, and (on the split commit)
that the assembled text equals the pre-split originals byte for byte; seven existing tests are re-pointed to that
assembly with no assertion edited. No engine behaviour, gate, schema field or step order changes.
