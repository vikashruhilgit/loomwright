# Telemetry privacy list catches every GitHub token prefix

## Status: pending

Source: `loomwright-archive/requirements/batchB/2026-10-30-073112-per-run-credentials-and-connectors-ledger.md`, Part C (privacy patterns) only. The credentials ledger (Parts A and B) is deferred and is not part of this story.

**As the** owner (Vikash), who has opted in to telemetry and whose agents handle GitHub OAuth, user-to-server, App installation and fine-grained tokens, not only classic PATs,
**I want** the telemetry privacy deny-list to block every GitHub token prefix (`ghp_`, `gho_`, `ghu_`, `ghs_`, `ghr_`, `github_pat_`) with the same fail-CLOSED exit 2 it already applies to `ghp_`, and the wrapper's stderr redactor to redact the same prefixes,
**so that** a GitHub token of any kind that appears in an agent result or in the core's stderr never reaches a telemetry issue or `telemetry.log`.

### Problem (verified on main `8ec200e`, v17.35.1)

The privacy list exists in two inline copies and both match only `ghp_`:

1. `loomwright/scripts/send-telemetry-core.sh`, `PRIVACY_PATTERNS` inside the `STAGE1_PY` heredoc: the row `ghp_[A-Za-z0-9]{20,}` labelled `github-token`. A match blocks the post with exit 2 (`PRIVACY_BLOCKED pattern=<label>`). `gho_`, `ghu_`, `ghs_`, `ghr_` and `github_pat_` tokens pass the scan.
2. `loomwright/scripts/send-telemetry.sh`, the stderr redactor's `patterns` list (comment: "keep aligned with send-telemetry-core.sh and TELEMETRY.md"): the same single `ghp_` row, so those tokens reach `telemetry.log` unredacted.

`loomwright/scripts/meta-sync.d/scrub.sh` already covers the family (`token_github` = `gh[pousr]_[A-Za-z0-9]{36,}`, `token_github_pat` = `github_pat_[A-Za-z0-9_]{22,}`). It guards a different egress (the meta branch) and is not changed here.

The list is restated in prose in three places, all naming only `ghp_`: `loomwright/docs/TELEMETRY.md` (the pattern table, plus the stderr-redaction section), `loomwright/skills/telemetry/SKILL.md` ("What does NOT get sent") and `.claude-plugin/README.md` ("Privacy guarantees").

### Scope

- **Core:** widen the `github-token` row to `gh[pousr]_[A-Za-z0-9]{20,}` (one regex; `ghp_` behaviour unchanged). Add a row `github_pat_[A-Za-z0-9_]{20,}` labelled `github-pat`, directly after `github-token` and before the body-only `env-assignment` row (which stays last). Update the comment above the list that counts the wrapper's tuples.
- **Wrapper:** the same two rows in the stderr redactor, replacing with `[REDACTED:github-token]` and `[REDACTED:github-pat]`.
- **Drift guard:** a test asserts that the wrapper's regex set equals the core's regex set minus `env-assignment`, so the two copies cannot drift again silently.
- **Docs:** update the three prose surfaces above in the same change. Each names the GitHub token family, not `ghp_` alone.

## Acceptance Criteria

All cases run in the existing suites under `hermetic-test-env.sh`, with no network.

**Happy path**
- [ ] Given a schema-valid result block carrying a bait token for each of `gho_`, `ghu_`, `ghs_` and `ghr_` (prefix + 20 to 35 alphanumerics), when the core runs, then each run exits 2 and stderr carries `PRIVACY_BLOCKED pattern=github-token`, never the token. Test: `test-send-telemetry-core.sh` Group 1, extended with one case per prefix.
- [ ] Given a bait `github_pat_` token (prefix + 20 or more of `[A-Za-z0-9_]`), then the core exits 2 with `PRIVACY_BLOCKED pattern=github-pat`. Test: `test-send-telemetry-core.sh` Group 1 (the `privacy_label_count` assertion moves from 9 to 10).
- [ ] Given the existing `ghp_` fixtures (`priv-github-token`, `secrets-bait-ghp.json`, `secrets-bait-lastmsg-ghp.json`), then they still exit 2 with `pattern=github-token`. Tests: `test-send-telemetry-core.sh`, `test-telemetry.sh`.
- [ ] Given five new fixtures `telemetry-fixtures/secrets-bait-{gho,ghu,ghs,ghr,github-pat}.json`, when `test-telemetry.sh` runs its matrix, then each reads `WOULD_EXIT=2` in all three consent states (`none`, `allow_no_repo`, `allow_with_repo`): privacy fails closed before consent. The existing `secrets-bait-*` glob discovers them, and no count is hard-coded.
- [ ] Given a stub core beside a copy of `send-telemetry.sh` that writes each new bait token to stderr, when the wrapper runs, then the `telemetry.log` line carries `[REDACTED:github-token]` or `[REDACTED:github-pat]` and none of the token values, and the wrapper exits 0. Test: a new case in `test-telemetry.sh`. No current test covers the wrapper's redactor.

**Edge cases**
- [ ] Given near-misses `ghs_short`, `ghx_` + 24 alphanumerics (a letter outside `[pousr]`) and `github_pat_short`, then the core does not privacy-block (exit 3 at missing consent, no `PRIVACY_BLOCKED`). Test: `test-send-telemetry-core.sh` Group 2, extended.
- [ ] Given the extracted `STAGE1_PY` (Group 7), then `PRIVACY_PATTERNS` contains both GitHub rows and `scan_for_secret()` returns `github-token` for a `ghs_` bait and `github-pat` for a `github_pat_` bait. Test: `test-send-telemetry-core.sh` Group 7.
- [ ] Given the core's `PRIVACY_PATTERNS` and the wrapper's `patterns`, then the wrapper's set of regex sources equals the core's set minus `env-assignment`. Test: a new parity case in `test-send-telemetry-core.sh`.
- [ ] Given the real-payload and plugin-facts groups (Groups 11 and 12), then they stay green unchanged: the widened row adds no false block on them.

**Error scenarios (mutation)**
- [ ] Given the core row reverted to `ghp_` only, then the `gho_`/`ghu_`/`ghs_`/`ghr_` Group 1 cases and their bait fixtures fail. Given the `github-pat` row removed from the core, then the `github-pat` case fails. Given either row removed from the wrapper only, then the parity case and the wrapper redaction case fail.

## Non-goals
- The credentials ledger: the `credential_use` schema, `record-credential-use.sh`, `read-credential-ledger.sh` and their hook leaves (source Parts A and B). Deferred by the owner.
- One shared pattern file for the core and wrapper, or for telemetry and `meta-sync.d/scrub.sh` (see Owner decisions).
- Changing `meta-sync.d/scrub.sh`, its lengths or its rule names.
- Other secret families not in the list today (Slack `xox`, AWS `AKIA`, …): telemetry has never covered them. That is a separate decision.
- Changing how the home-path rows redact, or any consent, interest or dedup behaviour.

## Owner decisions
- 2026-11-09 (Vikash, in chat): APPROVED from the archive review; refreshed against main 8ec200e / v17.35.1.
- 2026-11-09 (Vikash, in chat): standalone fix of the privacy slice only; the credential ledger is deferred.
- PO default, pending owner review: **no single shared pattern source.** The two telemetry copies stay inline, and a parity test pins them. Reason: `test-send-telemetry-core.sh` Group 7 extracts the `STAGE1_PY` heredoc and `exec()`s it with no `LOOMWRIGHT_TELEMETRY_CORE_DIR`, and `PRIVACY_PATTERNS` is defined before any exit point for that reason. Moving the list into an imported module would change that harness and the core's fail-closed import path, which is more than this fix needs. `meta-sync.d/scrub.sh` cannot be the source either: its table is an inline bash ERE heredoc with a leading non-word anchor and 36+ / 22+ lengths, serving a different gate. Alternative if the owner prefers it: a `privacy_patterns.py` beside `result_block_parser.py`, imported by both (a missing module = the core fails closed, the wrapper drops stderr).
- PO default, pending owner review: keep the existing `{20,}` minimum length for the new prefixes (looser than scrub's `{36,}`). A fail-CLOSED deny-list should over-match, not under-match.
- PO default, pending owner review: `github_pat_` gets its own label `github-pat`; the other four prefixes share `github-token` with `ghp_`, so existing log lines keep their label.
- PO default, pending owner review: bait fixture tokens are shorter than a real token (under 36 characters after a `gh?_` prefix, under 82 after `github_pat_`), as the existing `ghp_` bait is, so a committed fixture never looks like a live credential to GitHub push protection.

## Priority: MVP
**Rationale:** Telemetry is an egress path and its privacy gate is meant to fail CLOSED. `ghs_` is what a GitHub App installation mints and `github_pat_` is the default PAT format today. Both pass the gate. The fix is small and self-contained.

## Assumptions
- The six prefixes are GitHub's current token family (`ghp_` classic PAT, `gho_` OAuth, `ghu_` user-to-server, `ghs_` server-to-server / installation, `ghr_` refresh, `github_pat_` fine-grained PAT). This matches the list `meta-sync.d/scrub.sh` already encodes.
- The wrapper can be tested by copying `send-telemetry.sh` into a scratch dir beside a stub `send-telemetry-core.sh`, because it resolves `CORE` from its own directory. If that proves impractical, the case may drive the redactor some other way, as long as it runs the wrapper's real list.
- `loomwright/skills/telemetry/SKILL.md` grows by a few proxy tokens (293 of headroom today). No budget change is expected. `prompt-token-budgets.json` and its mirror row are listed in Touches only in case `check-token-budget.sh` asks.

## Dependencies
- Depends on: none.
- Blocks: none. When the deferred credentials ledger is picked up, its emitter's self-check should reuse this list rather than copy it.

## Risks
- **False blocks:** the widened regex has no leading anchor, as the `ghp_` row has none today. A snake_case identifier ending in `gh[pousr]` followed by `_` and 20 or more alphanumerics would block a post. This is unlikely, and over-blocking is the safe direction for this gate. The Group 2, 11 and 12 cases watch for it.
- **Restated-list drift:** five surfaces name the list (two code copies, three prose). The parity test covers the code copies only. The three prose surfaces must change in the same PR (house rule on restated lists).
- **Push protection:** a bait fixture shaped like a real token could be flagged on push. The fixture length rule above avoids it.

## Validation (must pass before merge)
1. **Static — core gate:** `bash loomwright/scripts/test-send-telemetry-core.sh` passes, including the new per-prefix, near-miss, Group 7 and parity cases.
2. **Static — fixture matrix and wrapper:** `bash loomwright/scripts/test-telemetry.sh` passes, including the five new `secrets-bait-*` fixtures and the wrapper redaction case.
3. **Static — repo gates:** `bash scripts/ci-local.sh --affected` passes (it includes `check-token-budget.sh`, `check-doc-currency.sh` and `check-prompt-history-refs.sh`); run directly any suite it lists as not covered.
4. **Static — release:** the PR adds `changelog.d/telemetry-privacy-github-token-prefixes.md` and never hand-edits `plugin.json`, `marketplace.json` or `CHANGELOG.md`; `bash scripts/check-version-bump.sh` passes.

## Depends on
none

## Touches
loomwright/scripts/send-telemetry-core.sh
loomwright/scripts/send-telemetry.sh
loomwright/scripts/test-send-telemetry-core.sh
loomwright/scripts/test-telemetry.sh
loomwright/scripts/telemetry-fixtures/secrets-bait-gho.json
loomwright/scripts/telemetry-fixtures/secrets-bait-ghu.json
loomwright/scripts/telemetry-fixtures/secrets-bait-ghs.json
loomwright/scripts/telemetry-fixtures/secrets-bait-ghr.json
loomwright/scripts/telemetry-fixtures/secrets-bait-github-pat.json
loomwright/docs/TELEMETRY.md
loomwright/skills/telemetry/SKILL.md
.claude-plugin/README.md
loomwright/docs/prompt-token-budgets.json
loomwright/docs/ARCHITECTURE_CONTRACTS.md
changelog.d/telemetry-privacy-github-token-prefixes.md

## Changes since the source was written
- **Narrowed to Part C.** The source was the whole credentials ledger (C1: schema, emitter, hook leaves, reader). Only the privacy-pattern slice is kept; the rest is deferred by the owner.
- **A second copy found.** The source named only the core's `PRIVACY_PATTERNS`. On `8ec200e` the wrapper `send-telemetry.sh` keeps its own copy for stderr redaction, which also matches only `ghp_`. Both copies change here, and a parity test is added.
- **"One pattern source" re-scoped.** The source wanted the ledger emitter and telemetry to share one list. With the emitter deferred, the remaining copies are the core and wrapper. They stay inline with a parity test (Owner decisions).
- **More restating surfaces.** `skills/telemetry/SKILL.md`, `.claude-plugin/README.md` and the stderr-redaction section of `TELEMETRY.md` also name only `ghp_`; the source listed `TELEMETRY.md` only.
- **Bait fixtures added.** The source extended only `test-send-telemetry-core.sh`. This story also adds one `secrets-bait-*` fixture per new prefix to the `test-telemetry.sh` matrix, and a first test of the wrapper's redactor.
- **`meta-sync.d/scrub.sh` checked:** it already covers `gh[pousr]_` and `github_pat_`. It is unchanged and named as a non-goal.
