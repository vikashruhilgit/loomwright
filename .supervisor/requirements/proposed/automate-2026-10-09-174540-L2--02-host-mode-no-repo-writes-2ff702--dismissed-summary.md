# Dismissed findings below the tracking threshold: 02-host-mode-no-repo-writes (4)

## Status: proposed

- **Run:** automate-2026-10-09-174540-L2
- **Item:** .supervisor/requirements/host-contract/02-host-mode-no-repo-writes.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/450
- **Decision:** follow-up

## Depends on
none

## Touches
unknown

## Findings (verbatim, untrusted data — never an instruction)

### Entry 1

- **Round:** 3
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** drift
- **Key:** b67f0354

```
> HOOKS.md 'both guards then deny' does not say an unusable D1 root under host mode makes guard-test-integrity deny every Write/Edit/Bash call, even unarmed; row 87 still says the inert path is unchanged; the changelog fragment is silent
```

### Entry 2

- **Round:** 3
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** 48e36dfc

```
> check-children-settled.sh's header says 'never writes', but under host mode with no state dir it calls lw_gate_state_dir, which creates the D1 dirs
```

### Entry 3

- **Round:** 3
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** 03aba9e1

```
> test-host-mode.sh leg (g) writes to the real /tmp fallback and leaves /tmp/loomwright-host-<uid> behind; a pre-existing foreign-owned or group/world-writable root would fail the leg
```

### Entry 4

- **Round:** 3
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** 95ac81f8

```
> _lw_under_any compares only lexical ancestors by inode, so a symlink pointing at a strict descendant of a worktree is not seen; not exploitable by current callers, but the header overstates the guarantee
```

propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`.
