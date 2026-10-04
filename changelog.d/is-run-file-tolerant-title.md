<!-- bump: patch -->
is_run_file tolerates a BOM, ATX-legal indentation, whitespace and case in the run-file title
`automate-helpers.sh`'s `is_run_file` matched only the exact, case-sensitive `# Automate Run:` line, so a run file
saved with a UTF-8 BOM or hand-edited to `#  Automate Run:` / `# automate run:` was hidden from `/automate` RESUME
and refused by `runfile-write` / `progress-append` / `queue-checkoff`, while `build-handoff.sh` read the title with a
different leniency. Both readers now share one title rule (`RUN_TITLE_ERE`, mirrored byte-for-byte into
`build-handoff.sh` and pinned by a test): an optional BOM, 0-3 leading spaces, any letter case and flexible whitespace,
exactly one `#`. H2 lines, 4+-space- and tab-indented lines (indented code blocks) and the result sidecars are still
not run files. New legs cover each tolerated form, the negatives, the write validators and `plan-waves`, with gated
mutation controls proving each tolerance and the indentation cap are load-bearing. Rule:
`skills/automate-loop/SKILL.md` §4 step 1.
