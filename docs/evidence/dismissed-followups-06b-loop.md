# Evidence — dismissed follow-ups 06b, `loop` group (Subtask 1)

Requirement: `.supervisor/requirements/dismissed-followups/06b-docs-and-evidence-drift.md` (gitignored; carried on
`loomwright-meta`). Sibling files: `docs/evidence/dismissed-followups-06b-docs.md` (`docs` group) and
`docs/evidence/dismissed-followups-06b-scripts.md` (`scripts` group).

Base: `edcdc2f3d20a23517f77bf0f3c5268cb4236fc67`. Re-verified 2026-11-10 on macOS (Darwin 25.6.0) from the
worktree root with `git grep … edcdc2f -- <path>`, so every check below reads the base tree, not the edit.

**Every finding in this group is a doc, header-comment or golden-fixture fix.** None changes executed behaviour
or emitted output, so no new `test-*.sh` leg is added (AC2). The heading rename is held by the suites that
already pin the heading; their mutation runs are recorded under F151.

| Finding | Disposition | File changed |
|---|---|---|
| F151 | fixed (doc/comment/golden only, no new leg) | the heading in `loomwright/skills/automate-loop/per-item-loop.md` and `loomwright/skills/automate-loop/SKILL.md`, plus every citation (list below) |
| F153 | fixed (same edit as F151) | as F151 |
| F154 | fixed (same edit as F151) | as F151 |
| F349 | fixed (doc only, no leg) | `loomwright/docs/result-schemas/automate-run.md` (`done` row), `loomwright/docs/loop-inventory/automate-loop.md` (AL-295, AL-556 expected-behavior cells) |
| F064 | fixed (doc only, no leg) | `loomwright/skills/automate-loop/per-item-loop.md` (§8 `escalated` bullet) |
| F140 | fixed (doc only, no leg) | `loomwright/skills/automate-loop/helpers.md` (`sweep` row) |
| F258 | fixed (doc/comment only, no leg) | `loomwright/skills/automate-loop/SKILL.md` (step 4), `loomwright/docs/result-schemas/supervisor-result.md` (nested-object key sets), `loomwright/skills/self-heal-advisory/completion-tail.md` (ground_truth comment) |
| F174 | fixed (doc only, no leg) | `loomwright/commands/automate.md` (branch-mode row) |

No finding in this group was already fixed on the base, so none is `recorded`.

## F151, F153, F154 — the heading says "before the park", but a sequential interactive READY park asks after it

Re-verify on the base:

```
$ git grep -cE 'decision step \(before the park\)' edcdc2f -- loomwright docs CLAUDE.md AGENT_GUIDELINES.md | wc -l
      21
$ git grep -nE '^### Dismissed-findings decision step \(before the park\)' edcdc2f -- loomwright/skills/automate-loop | cut -d: -f1-3
edcdc2f:loomwright/skills/automate-loop/SKILL.md:163
edcdc2f:loomwright/skills/automate-loop/per-item-loop.md:90
$ git grep -nE 'decision step \(before( the)?$' edcdc2f -- loomwright | cut -d: -f1-3
edcdc2f:loomwright/scripts/fixtures/automate-golden/MAP.tsv:64
```

Fix: the suffix ` (before the park)` was dropped after `decision step` in the 19 citing files
(this also covers the copies wrapped after `Dismissed-findings` / `Dismissed-` in the headers of
`automate-dismissed.sh`, `automate-next-step.sh` and `automate-helpers.d/resume.sh`), and the `MAP.tsv` comment
split after `(before the` was re-wrapped. Files: `per-item-loop.md`, `automate-loop/SKILL.md`, `helpers.md`,
`modes-and-merge-gate.md`, `run-file.md`, `commands/automate.md`, `self-heal-advisory/SKILL.md`,
`result-schemas/automate-run.md`, `result-schemas/supervisor-result.md`, `loop-inventory/automate-loop.md`
(AL-312 / AL-567 `h:` anchors), `automate-helpers.sh` (the `dismissed-drafts` `#:` row), `automate-helpers.d/resume.sh`,
`automate-next-step.sh`, `automate-dismissed.sh`, `fixtures/automate-helpers-help/{hdr-trail,resume}.golden`,
`fixtures/automate-golden/MAP.tsv` (key column; slug `dismissed-findings-decision-step` unchanged),
`test-automate-dismissed.sh` (the `SUBH` extractor and the case patterns quoting the heading — renamed, none removed),
`test-automate-next-step.d/12-dismissed-batch.sh` (header comment).

Deliberately not rewritten: `CHANGELOG.md` (release history), `docs/evidence/as22-split-big-commands.md` (dated
record) and the frozen requirement fixture under `fixtures/automate-golden/gate-validation-waive/`.

AC3 check on the fixed tree:

```
$ grep -rnE 'decision step \(before the park\)' loomwright/ docs/ CLAUDE.md AGENT_GUIDELINES.md | cut -d: -f1
loomwright/scripts/fixtures/automate-golden/gate-validation-waive/tree/dot-supervisor/requirements/automate-speed/01-question-gates-dont-stall.md
docs/evidence/as22-split-big-commands.md
$ grep -rnE 'decision step \(before( the)?$' loomwright/
(no output)
```

(This file quotes the old heading only inside its re-verify commands, never as a match line, so it is not a hit.)

Mutation runs, in a `mktemp -d` copy of the worktree with `HOME` relocated (never the worktree):

| Mutation | Suite | Result |
|---|---|---|
| revert `### Dismissed-findings decision step` to the old heading in `per-item-loop.md` only | `test-loop-inventory.sh` | rc=1 — `FAIL AL-567: anchor not found …` and the per-item-loop.md heading has no `h:` row |
| same | `test-automate-dismissed.sh` | rc=1 — 294 passed, 4 failed (`B: SKILL lacks '### Dismissed-findings decision step'`, …) |
| revert the `dismissed-drafts` `#:` row's comment in `automate-helpers.sh` only | `test-automate-helpers-dispatch.sh` | rc=1 — 52 passed, 3 failed (`'--help' output differs from the ordered segment fixtures`) |

## F349 — two restated done-exit sequences omit the `process registry:` line

The authority, `per-item-loop.md` §"Termination", runs `trail-pr --reason done`, then the `process registry:` line,
then the dry sweep line. Re-verify on the base:

```
$ git grep -noF 'then appends ONE `<ts> process registry: <summary line>` line' edcdc2f -- loomwright/skills/automate-loop/per-item-loop.md
edcdc2f:loomwright/skills/automate-loop/per-item-loop.md:38:then appends ONE `<ts> process registry: <summary line>` line
$ git grep -noF 'and the dry sweep line are written' edcdc2f -- loomwright/docs/result-schemas/automate-run.md
edcdc2f:loomwright/docs/result-schemas/automate-run.md:122:and the dry sweep line are written
$ git grep -noF 'then one dry-run `sweep` summary line, then release' edcdc2f -- loomwright/docs/loop-inventory/automate-loop.md
edcdc2f:loomwright/docs/loop-inventory/automate-loop.md:319:then one dry-run `sweep` summary line, then release
$ git grep -noF '(trail-pr --reason done + the dry sweep line)' edcdc2f -- loomwright/docs/loop-inventory/automate-loop.md
edcdc2f:loomwright/docs/loop-inventory/automate-loop.md:583:(trail-pr --reason done + the dry sweep line)
```

Fix: the `done` row now reads `(trail-pr --reason done, then the process registry: line, then the dry sweep line are
written)`; AL-295's and AL-556's expected-behavior cells name the same three lines in that order. The `q:` / `h:`
anchors and the nine-cell shape are unchanged. `automate-next-step.sh`'s own `terminate` header row already names
the `process registry:` line, so it was left alone.

## F064 — §8's `escalated` bullet reads as if only a human ends the park

Re-verify on the base:

```
$ git grep -noF 'until a human resolves it (§9); stacking' edcdc2f -- loomwright/skills/automate-loop/per-item-loop.md
edcdc2f:loomwright/skills/automate-loop/per-item-loop.md:121:until a human resolves it (§9); stacking
$ git grep -noF "Armed by the driver's \`park\` step at §9's \`awaiting_merge\` and \`escalated\` parks" edcdc2f -- loomwright/skills/automate-loop/per-item-loop.md
edcdc2f:loomwright/skills/automate-loop/per-item-loop.md:72:Armed by the driver's `park` step at §9's `awaiting_merge` and `escalated` parks
```

Fix: the bullet gains `— the merge watcher armed at the park (§6 "Post-merge close-out") re-checks the PR and runs
\`closeout\` on a merge`. The bullet's prefix (`- **\`escalated\`:** the run stays **paused**`, AL-398's `q:` anchor)
is unchanged.

## F140 — the `sweep` row gives one line form for three callers

Re-verify on the base:

```
$ git grep -noF '(`<ts> sweep (dry run): <summary>`: §6 "Termination", `finalize-empty`, `fleet-closeout`)' edcdc2f -- loomwright/skills/automate-loop/helpers.md
edcdc2f:loomwright/skills/automate-loop/helpers.md:38:(`<ts> sweep (dry run): <summary>`: §6 "Termination", `finalize-empty`, `fleet-closeout`)
$ git grep -noF 'progress-append "$rf" "fleet closeout sweep (dry run): $sw"' edcdc2f -- loomwright/scripts/automate-lanes.d/wave.sh
edcdc2f:loomwright/scripts/automate-lanes.d/wave.sh:109:progress-append "$rf" "fleet closeout sweep (dry run): $sw"
```

`test-automate-lanes.d/04-fleet-closeout-to-optout.sh` greps `^- fleet closeout sweep (dry run): `, so
fleet-closeout's line carries no `<ts>`. Fix: the row reads `<ts> sweep (dry run): <summary>` for §6 "Termination"
and `finalize-empty`; `fleet closeout sweep (dry run): <summary>` for `fleet-closeout`.

## F258 — three copies of the refusal rule say "nothing written" without the ledger exception's scope

The authority, `automate-run.md` §"Writers and failures", says nothing is written with ONE exception (a refused
`--result` appends its `ok: false` line to the coordinator-model ledger). Re-verify on the base:

```
$ git grep -noF 'nothing written, with ONE exception' edcdc2f -- loomwright/docs/result-schemas/automate-run.md
edcdc2f:loomwright/docs/result-schemas/automate-run.md:144:nothing written, with ONE exception
$ git grep -noF 'exit 2 is a refusal with nothing written.' edcdc2f -- loomwright/skills/automate-loop/SKILL.md
edcdc2f:loomwright/skills/automate-loop/SKILL.md:43:exit 2 is a refusal with nothing written.
$ git grep -noF 'exit 2, nothing written)' edcdc2f -- loomwright/docs/result-schemas/supervisor-result.md loomwright/skills/self-heal-advisory/completion-tail.md
edcdc2f:loomwright/docs/result-schemas/supervisor-result.md:108:exit 2, nothing written)
edcdc2f:loomwright/skills/self-heal-advisory/completion-tail.md:172:exit 2, nothing written)
```

Fix: all three now say `nothing written to the run file`; the authority keeps its ONE-exception sentence.
`supervisor-result.md`'s other `nothing written` (the `--result` shapes paragraph) describes the supervisor runner, not
`/automate`, and is left alone.

## F174 — the branch-mode row's "equivalently" is not equivalent

`meta-entry` prints `failed — mode unknown (…)` when `setup-memory.sh mode` prints `unknown <reason>`, so "anything
but `meta-entry: off`" also covers `unknown`. Re-verify on the base:

```
$ git grep -noF '(equivalently `setup-memory.sh mode` prints `on <branch>`)' edcdc2f -- loomwright/commands/automate.md
edcdc2f:loomwright/commands/automate.md:87:(equivalently `setup-memory.sh mode` prints `on <branch>`)
$ git grep -noF 'print ONE line: off | on <branch> | unknown <reason>' edcdc2f -- loomwright/scripts/setup-memory.sh
edcdc2f:loomwright/scripts/setup-memory.sh:114:print ONE line: off | on <branch> | unknown <reason>
```

Fix: the row reads `(or \`setup-memory.sh mode\` prints \`on <branch>\` or \`unknown\`)`; the trigger is unchanged.

## Suites run on the fixed tree

`test-loop-inventory.sh` 53/53, `test-automate-dismissed.sh` 298 passed / 0 failed,
`test-automate-helpers-dispatch.sh` 55 passed, `test-automate-loop-split.sh` 46 passed, `test-automate-golden.sh`
73 passed / 0 failed (its M3 leg checks `git diff --quiet -- automate-dismissed.sh`, so it reads green only once the
header edit is committed).
