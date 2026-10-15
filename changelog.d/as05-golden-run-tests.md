<!-- bump: patch -->
Golden run-file tests pin today's /automate per-item loop (automate-speed/05)
New `loomwright/scripts/test-automate-golden.sh` replays each step of `skills/automate-loop/per-item-loop.md`,
`modes-and-merge-gate.md` and `resume.md` by calling the `automate-helpers.sh` subcommands that step names, in the
prose's order, over run files built from real `.supervisor/automate/` runs (scrubbed, under
`loomwright/scripts/fixtures/automate-golden/`). Each case runs in its own scratch checkout with `gh` stubbed and
compares the resulting run file and every step's stdout, stderr and exit code byte for byte, with timestamps and
scratch paths normalised. Every heading and numbered branch of those three files is extracted live and must map to
a case in `MAP.tsv` (or to a `judgment — covered at the step boundary` case); an unmapped unit or a stale map row
fails the suite. Built-in gated mutation legs prove that a one-character change to a pinned run-file prefix, an
extra or missing prose heading, or a home path in a fixture turns it red, naming the case. Items 06–09 can now show
that a `next-step` script writes the same run file. No behaviour changes; the prose/output gaps found are listed in
`docs/evidence/as05-golden-run-tests.md`.
