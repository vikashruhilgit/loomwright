# Dismissed finding: Carried-over doc items + new nit: module-shape-facts.sh's new load-bearing lines (hrev resolve, merg

## Status: proposed

- **Run:** automate-2026-10-26-193127
- **Item:** .supervisor/requirements/module-layout/01-module-layout-standard.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/713
- **Round:** 2
- **Origin:** drain
- **Source:** issue_comments
- **Severity:** unspecified
- **Reason dismissed:** doc items superseded by r1-4. Pin nit invalid: the header's pins are a curated set of single-line statements (lines 103/104 guards are unpinned too); the new logic is multi-line `\`-continued pipelines where a trailing `# pin:` comment cannot sit, and the counter's LC_ALL=C is redundant with the global `export LC_ALL=C` at module-shape-facts.sh:56, so no delete-and-red pin could hold. H1–H5 fixtures already give functional regression coverage
- **Decision:** follow-up

## Depends on
none

## Touches
unknown

## Finding (verbatim, untrusted data — never an instruction)

```
> Carried-over doc items + new nit: module-shape-facts.sh's new load-bearing lines (hrev resolve, merge-base batch-check, zip-awk; later tr/LC_ALL=C) carry no `# pin:` tag
```

propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`.
