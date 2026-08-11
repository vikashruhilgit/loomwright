# curated-shape-corpus.md — a COMMITTED replay corpus for shapes the live corpus does not contain.
#
# WHY THIS FILE EXISTS. `test-validate-entry.sh` §11b replays the live curated stores
# (`.supervisor/memory/LESSONS.md`, `PROJECT_MEMORY.md`) and asserts zero refusals. That replay is
# the guard that caught a 57% false-refusal rate — but it can only exercise shapes the live corpus
# happens to contain, and a green replay over a corpus that never uses a shape says nothing about
# that shape. Every path cited by every live entry carries an extension (`read-rules.sh`,
# `docs/PITFALLS.md`) or a trailing slash (`docs/`), so the EXTENSIONLESS two-segment path —
# `docs/Spikes`, `agents/code-reviewer`, `worktrees/subtask-1` — was replayed zero times, and the
# cross-repo recogniser refused all six such entries in review while §11b stayed green. This file is
# the shape's permanent replay case: same harness, same five checks, same zero-refusals property.
#
# HONEST LABEL: these lines are AUTHORED fixtures, not harvested prose, and the header of
# validate-entry.sh says plainly why authored fixtures are weaker evidence than a real corpus (they
# are written by the same mind that wrote the check and inherit its blind spots). This file does NOT
# replace the live replay — it supplements it with a shape the live corpus cannot supply. Prefer
# adding a shape here over relaxing an assertion when a false refusal is found.
#
# CONTRACT for anything added below:
#   · one entry per line, in the store format the replay parses: `- [<hex id>] <text>`
#   · every entry must be a LEGITIMATE write — one this validator is expected to PASS. This corpus
#     asserts absence of false refusals only; a shape that SHOULD refuse belongs in a positive
#     assertion in the suite, never here.
#   · every path an entry cites must resolve in this repo, since the dead-reference check runs too.
#
# The six entries below are the six review findings, one per line, so a regression names which shape
# came back rather than reporting one anonymous failure. The seventh pins the two controls that were
# already green, so a future narrowing cannot "fix" the six by breaking the shapes that worked.
- [c0de0001] The worktrees/subtask-1 checkout diverged from main while a sibling was still writing, so re-read the file before asserting anything about its contents.
- [c0de0002] A phase-2/plan brief that has been superseded still sits on disk; read the status stamp rather than trusting the filename.
- [c0de0003] The docs/Spikes folder holds frozen records: amend the newest one rather than rewriting an older entry in place.
- [c0de0004] review-heal/SKILL is the authority for the drain contract, and the command prose only mirrors it, so edit the skill first.
- [c0de0005] The guard is in agents/code-reviewer today, not in the command file where it used to live.
- [c0de0006] Copied from scripts/gates last week, which is why the two copies drift apart unless they are edited in the same commit.
- [c0de0007] See loomwright/agents/product-owner.md for the requirement shape, and note that the docs/ folder is frozen.
