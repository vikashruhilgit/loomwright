# Dismissed findings below the tracking threshold: 03-lanes-and-meta-sync-defects (5)

## Status: proposed

- **Run:** automate-2026-11-09-145614
- **Item:** .supervisor/requirements/dismissed-followups/03-lanes-and-meta-sync-defects.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/865
- **Decision:** follow-up

## Depends on
none

## Touches
loomwright/capabilities.json
loomwright/scripts/build-capabilities.sh

## Findings (verbatim, untrusted data — never an instruction)

### Entry 1

- **Round:** 3
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Evidence:** none recorded
- **Key:** ce40b782

```
> automate-lanes.sh header admission step 3 still reads 'trip file present ⇒ lane-launch: HELD — memory_pressure'; admission now holds only when _lanes_trip_live is true
```

### Entry 2

- **Round:** 3
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Evidence:** none recorded
- **Key:** 08ad3933

```
> wave-plan's echoed conflict rule prints this repo's own paths (loomwright/capabilities.json, bash loomwright/scripts/build-capabilities.sh) without the 'in this plugin' qualifier lanes.md carries
```

### Entry 3

- **Round:** 3
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Evidence:** none recorded
- **Key:** 591c441f

```
> F003 leg uses a receive-pack wrapper instead of a pre-push hook and the run ends no_remote_branch (exit 1), not AC17's push_failed; all AC17 safety properties hold
```

### Entry 4

- **Round:** 1
- **Origin:** drain
- **Source:** issue_comments
- **Severity:** LOW
- **Reason dismissed:** below_fix_floor
- **Evidence:** severity LOW is below the fix floor MEDIUM
- **Key:** 80a91f1f

```
> setup-memory.sh valid-branch refuses a stray non-option positional but an option-shaped stray arg (valid-branch my-branch --unknown-flag) only warns and exits 0
```

### Entry 5

- **Round:** 1
- **Origin:** drain
- **Source:** issue_comments
- **Severity:** LOW
- **Reason dismissed:** below_fix_floor
- **Evidence:** severity LOW is below the fix floor MEDIUM
- **Key:** 0ecb6765

```
> (re-statement of r1-1) valid-branch still accepts an option-shaped stray argument after the name
```

propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`.
