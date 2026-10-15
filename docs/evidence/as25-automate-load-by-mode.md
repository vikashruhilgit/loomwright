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

Pending: the main thread appends the scratch-repo headless `/automate` run (the `--plugin-dir` it used, plus the fenced list of plugin `file_path`s the session read) before the PR is opened.
