# af36-remainder/02 — The allowlist travels, but a repo can only request entries, never grant them

## Status: pending

## Split from
`automate-followups/36-s3-engine-fixes.md` Part C §A (originally `meta-sync-followups/05` §A), split 2026-10-12
per that file's Re-scope section ("Recommend splitting Part C into C-A / C-B / C-C PRs"). Scope and acceptance text
below is carried VERBATIM; only Depends on / Touches / Validation are rewritten for today's tree (main 3e354b5).
**Security-sensitive** — human merge only.

## Depends on
none

## Touches
loomwright/scripts/setup-memory.sh
loomwright/scripts/test-setup-memory.sh
loomwright/scripts/test-meta-sync.sh
.agent/meta-allowlist.txt
loomwright/commands/setup.md
loomwright/skills/setup/SKILL.md
changelog.d/af36-02-meta-allowlist-grant.md

## Problem
The allowlist gap breaks branch mode on any second machine. Without `config.json`, `setup-memory.sh allowlist` falls
back to the current remote only (precedence layer 4). 42 of the 126 ledger records carry the pre-rename slug
`vikashruhilgit/ai-agent-manager`, and 51 files on `loomwright-meta` cite it in a forge context. On 2026-10-03, a
scratch clone with no `config.json` reported 218 scrub hits. So every trail push that adds a ledger line, or edits an
old-slug file, is refused there.

## Scope (verbatim from af/36 Part C §A)
1. Add a tracked request file (proposed: `.agent/meta-allowlist.txt`, one `owner/repo` per line, `#` comments) that
   `setup-memory.sh allowlist` reads as a new layer, below `--allow` / env / `config.json` and above the
   current-remote default.
2. **Grant rule (security — do not drop):** an entry from the tracked file counts ONLY when it resolves to the same
   repository as `origin`. Check with `gh api repos/<slug> --jq .id`, which follows GitHub's rename redirect, against
   the id of `origin`'s slug. The current remote's own slug is always granted. Any other entry is ignored and named in
   one status line (`allowlist: ignored <slug> — not this repository`).
   - Why: the findings ledger collects records about OTHER repos analysed from this checkout. A committed allowlist
     that a clone's owner controls could otherwise list your private repos and publish their ledger records to a
     public metadata branch. This is the same rule as telemetry consent (v15.87.0): a repo-relative file can at most
     request, never grant.
   - When `gh` is unavailable or fails, tracked-file entries are NOT granted (fail closed), and the status line says
     so. `config.json` and `--allow` keep working offline, unchanged.
3. Seed this repo's request file with its two slugs. Update `/setup memory`'s disclosure to describe the
   request/grant split. `skills/setup/SKILL.md` carries a line saying the allowlist "does not travel" — correct it.

## Non-goals
The learning stores and consent (af36-remainder/03). The `/dreaming` memory PR (af36-remainder/04). Onboarding
another repo (`meta-sync-followups/07`).

## Acceptance criteria
- **A1** Given a fresh clone with no `.supervisor/config.json` and the seeded request file, when `meta-sync.sh pull`
  then a `push` that adds a ledger line and edits a file citing the old slug runs, then the push succeeds, because the
  old slug resolves to this repo's id.
- **A2** Given a request file listing a slug that resolves to a DIFFERENT repository, when the allowlist is resolved,
  then that slug is not granted, it is named in the status line, and a ledger record under it is refused by the
  scrub. The test fails when the id comparison is removed (mutant).
- **A3** Given `gh` is unavailable, when the allowlist is resolved, then tracked-file entries are not granted,
  `config.json` entries still are, and the status line says why.

## Validation (must pass before merge)
1. Targeted tests (`test-setup-memory.sh`, `test-meta-sync.sh`) + `scripts/check-doc-currency.sh` +
   `loomwright/scripts/test-citation-drift.sh` (+ token-budget and vendor ratchet after `git add`). The full
   `scripts/ci-local.sh` runs at `wave-build` (owner rule 2026-10-12). Report `<passed>/<total>` per suite.
2. Tests stub `gh` (no network in CI): a same-id slug, a different-id slug, and a failing `gh`.
3. Running system: in a scratch clone of this repo with no `config.json`, `setup-memory.sh allowlist` prints both
   seeded slugs as granted; paste the output. If not possible inside the lane, list it under "Not verified".
4. A failure this must catch: the A2 mutant (id comparison removed ⇒ red).
5. Rollback: `git revert`.

## Provenance
Owner direction, 2026-10-03, session cc4eaee3 (after M1). The allowlist failure (218 hits without `config.json`)
comes from the M1 rehearsal the same day.

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-13T00:55:03Z
- **Brief:** .supervisor/jobs/done/2026-10-12-af36-02-meta-allowlist-grant.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/501
