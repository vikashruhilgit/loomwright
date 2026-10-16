# as25 — `/automate` Step 0 loads the split files by mode: evidence

Requirement: `.supervisor/requirements/automate-speed/25-automate-load-by-mode.md`. Contract: `loomwright/commands/automate.md` Step 0 (its index-only block). Base commit: `f5c2d0e23fb717d385047340d7ddb5862153b6e0`.

## Validation 1

The four repo checks, run from the branch's worktree root after the change (worker run, 2026-10-15).

`bash loomwright/scripts/test-automate-loop-split.sh` (the script itself is unchanged from the base commit):

```
  ok: F: Step 0 names all 8 skill split files, in documented order
  ok: F: Step 0 resolves them under the plugin install root's skills/automate-loop/
  ok: MUTATION CONTROL: Step 0 missing resume.md is REJECTED (F)
RESULT: 39 passed, 0 failed
```

`bash scripts/check-doc-currency.sh`:

```
Authoritative → version=17.3.0  agents=14  commands=23  skills=42  hooks=48
✓ doc-currency: all checked version/count claims match the authoritative source.
```

`bash loomwright/scripts/test-citation-drift.sh`:

```
citation-drift: 26 passed, 0 failed
```

`bash scripts/check-vendor-coupling.sh` (`commands/automate.md` stays at its allowance of 8, unchanged):

```
loomwright/commands/automate.md                                adapter_frontmatter       8       8  OK      at allowance [install_root=6 ask_user=1 hook_protocol=1]
check-vendor-coupling: OK — no path exceeds its declared vendor-coupling allowance, and every raise or exemption carries a reason.
```

Confinement check (AC5): with every `<!-- index-only:begin -->` … `<!-- index-only:end -->` block removed, both edited doc files are byte-identical to the base commit:

```
outside-index-only identical: loomwright/commands/automate.md
outside-index-only identical: loomwright/skills/automate-loop/SKILL.md
test-automate-loop-split.sh unchanged
version files unchanged
```

## Validation 2

Running system, main thread, 2026-10-15, at branch head `d70321c`. A fresh scratch repo (`git init`, one requirement, a one-line backlog; no remote, no `--parallel`, no incomplete run, branch mode off) ran one headless sequential `/automate` with THIS branch's plugin and the installed copy disabled:

```
claude -p "/loomwright:automate --backlog .supervisor/backlog.md" \
  --plugin-dir <lane checkout>/loomwright \
  --settings '{"enabledPlugins":{"loomwright@atelier":false}}' \
  --max-turns 14 --output-format stream-json --verbose
```

The session's init event names the plugin it loaded: `loomwright plugin: <lane checkout>/loomwright` (this branch, not the marketplace cache). Every Read tool `file_path` the session used, in order (paths relative to the lane checkout):

```
loomwright/skills/automate-loop/SKILL.md
loomwright/skills/automate-loop/per-item-loop.md
loomwright/skills/automate-loop/modes-and-merge-gate.md
loomwright/skills/automate-loop/invariants.md
loomwright/skills/automate-loop/SKILL.md
loomwright/skills/automate-loop/per-item-loop.md
loomwright/commands/autonomous.md
loomwright/commands/review-pr.md
loomwright/skills/automate-loop/intake.md
```

No `lanes.md`, `command-lanes.md`, `resume.md` or `branch-mode.md`. A scan of every tool input in the transcript (Read, Bash, Grep) for those four names returned no match, so no `cat`/`grep`/`wc` touched them either. The run reached the first PICK and parked there for an environmental reason (the scratch repo has no remote, so `trail-gate` fails closed):

```
- skipped AUT-QUEUE: backlog queue 1 ≤ limit 5
- trail-gate: PARK — trail PR state unreadable (gh pr list failed)
- parked trail_pr_open — repo has no git remote; gh cannot read trail PR state (fail closed)
```

**What the first attempt found (at `ea7a88d`, fixed by `6d4479c` and `d70321c`).** The same run at the first commit did not Read the four files, but `pick-guard` refused `refuse: automate_dir_missing .supervisor/automate`. The only instruction to `mkdir -p .supervisor/automate` before `pick-guard` on a new run lived in the resume split file's §4, which a fresh run no longer reads. The session then ran `grep -n "pick-guard"` over `resume.md` and `lanes.md` (about 7.5K chars) to recover. `6d4479c` puts that one start-order step in the `intake.md` row. `d70321c` closes a second rule of the same kind: the `progress-append` of a start-time `closeout-others: record — …` line also lives only in §4, so that line is now a `resume.md` trigger. The re-run above shows neither the refusal nor any touch of the four files.

**Honest limits.** One run covers the fresh, sequential, branch-mode-off, no-remote shape only. The `closeout-others: record — …` trigger was not exercised (it needs another run with a merged in-flight PR). A run that reads the trigger lines still depends on the model following Step 0's "read when the trigger is observed" instruction; nothing mechanical enforces the late reads.

**Re-run at `df24b18`** (after Phase 4.5 fix 1 added the always-run `meta-entry` step and the `- parallel:` lanes trigger; the plugin was loaded from a detached worktree of that commit, same flags, a new scratch repo). Every Read tool `file_path`:

```
loomwright/skills/automate-loop/SKILL.md
loomwright/skills/automate-loop/per-item-loop.md
loomwright/skills/automate-loop/SKILL.md
loomwright/skills/automate-loop/intake.md
loomwright/commands/autonomous.md
loomwright/skills/automate-loop/modes-and-merge-gate.md
loomwright/skills/automate-loop/invariants.md
loomwright/commands/review-pr.md
```

No tool input names `lanes.md`, `command-lanes.md`, `resume.md` or `branch-mode.md`. The new start step ran and printed `meta-entry: off` (twice), which fires no read. The session created its run file, recorded `skipped AUT-QUEUE: backlog queue 1 ≤ limit 5`, and then stopped before PICK on its own because the scratch repo has no remote. That is earlier than the first run, which reached `trail-gate`. It is the model's own call about the environment, not a protocol step this change touches. Commits after `df24b18` change only the changelog fragment and this file.
