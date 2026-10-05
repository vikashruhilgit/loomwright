# Dismissed findings below the tracking threshold: 01-ratchet-hardening (3)

## Status: proposed

- **Run:** automate-2026-10-05-002720
- **Item:** .supervisor/requirements/agnostic-phase1/01-ratchet-hardening.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/385
- **Decision:** follow-up

## Findings (verbatim, untrusted data — never an instruction)

### Entry 1

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** nit
- **Key:** 6751fe48

```
> Summary label frontmatter-exempt: 38 reads as exempt although those bodies are counted
```

### Entry 2

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** drift
- **Key:** 7a5865e3

```
> The seven token-class names are restated in the script header, ARCHITECTURE_CONTRACTS.md and the changelog fragment besides the manifest
```

### Entry 3

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** nit
- **Key:** 93982b64

```
> raise row prints the raw JSON literal (2 -> 3.0) without floor; the jq predicate accepts -0 which the shell check then rejects
```

propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`.
