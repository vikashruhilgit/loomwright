# Skills-spec lint covers description, name shape, required keys and size

## Status: pending

Source: `loomwright-archive/requirements/batchD/2026-10-30-085420-skills-spec-lint-checks-description-name-shape-required-keys-and-size-for-every-skill.md` (Batch D item K1).

**As the** owner (Vikash), who ships skills in two plugins (`loomwright/skills/`, `stackpack/skills/`) that Claude Code lists and loads by their frontmatter,
**I want** the existing skill frontmatter suite to also check that every `SKILL.md` has a valid single-line `description` within the spec's length, a spec-shaped `name`, and the `version` and `lastUpdated` keys the repo's template requires, and to print an advisory line-size report, with every limit read from one committed spec file that cites its source,
**so that** a skill whose description is missing, too long or unparseable, or whose name or version is malformed, fails CI on the PR that introduces it instead of being silently truncated, mis-listed, or skipped by the index gate.

### Problem (verified on main `8ec200e`, v17.35.1)

`loomwright/scripts/test-skill-frontmatter.sh` is the one skill-frontmatter checker. It scans every `*/skills/*/SKILL.md` (60 files: 42 in `loomwright/`, 18 in `stackpack/`), refuses a 0-file run, and checks only that the frontmatter leads the file and that `name` appears once and equals the directory. Its section (2) checks that the template carries `name` and `description`. Nothing checks a real skill's `description`, `name` shape, `version` or `lastUpdated`.

Measured on `8ec200e`:
- **One live defect:** `loomwright/skills/rules/SKILL.md`'s `description` is 1,129 characters (1,131 bytes, because of two multi-byte dashes). The limit is 1,024 characters.
- Every other skill has a non-empty single-line `description`, and every skill has exactly one `name`, `description`, `version` and `lastUpdated`. No skill uses a block-scalar description or a `when_to_use:` key.
- Six SKILL.md files are over 500 lines: `playwright-e2e` (923), `frontend-ui` (913), `qa-test-patterns` (884), `review-heal` (583), `supervisor-readiness` (556), `qa-gates` (526). All six are in `loomwright/`.
- `scripts/check-skills-index-sync.sh` skips a skill with no `version:` (its self-test pins the skip), so a versionless skill passes every current gate.
- No `skills-spec.json` or any other skill-limit file exists.

### External limits (read 2026-11-09)

- Agent Skills specification, https://agentskills.io/specification: `name` 1 to 64 characters, lowercase `a-z`, `0-9` and hyphens, no leading, trailing or consecutive hyphen, equal to the directory. `description` 1 to 1,024 characters. "Keep your main `SKILL.md` under 500 lines."
- Claude Code skills docs, https://code.claude.com/docs/en/skills: `name` and `description` are optional to Claude Code (only `description` is recommended). `description` plus `when_to_use` is truncated at 1,536 characters in the skill listing. "Keep `SKILL.md` under 500 lines." If the frontmatter YAML does not parse, the skill loads with no fields set.

The Agent Skills limits are the stricter of the two and are the ones this lint applies.

### Scope

**Part A — one spec authority.** A committed `loomwright/docs/skills-spec.json` is the only home of the limits: `name_pattern` (`^[a-z0-9]+(-[a-z0-9]+)*$`), `name_max` (64), `description_max` (1024), `required_keys` (`name`, `description`, `version`, `lastUpdated`), `version_pattern` (`^[0-9]+\.[0-9]+\.[0-9]+$`, after unquoting), `advisory_max_lines` (500), and `sources` (one `{url, read_date, what}` per external limit and one repo pointer per repo-defined rule). No prose restates the numbers. `loomwright/skills/SKILL_TEMPLATE.md` gains one comment line pointing at the file, and the suite's header points at it instead of listing limits.

**Part B — extend `test-skill-frontmatter.sh` in place.** Same scan, same `frontmatter` / `fm_values` helpers, no second parser. New `VIOLATION <path>: <rule>` lines for:
- `description` missing, empty, or present more than once;
- `description` a block scalar (`>`, `|` and their variants) or otherwise not a single-line scalar;
- `description` longer than `description_max` characters after unquoting (characters, not bytes);
- `name` failing `name_pattern` or longer than `name_max` (in addition to the existing directory check);
- a `required_keys` entry missing or empty;
- `version` failing `version_pattern`.

New advisory output, which never fails the suite: `ADVISORY <path>: <n> lines > <advisory_max_lines>` for every SKILL.md over the line budget in any plugin, naming the hard size gate that does apply (`check-token-budget.sh` for `loomwright/`, `none` for `stackpack/`).

The spec file fails CLOSED: missing, malformed JSON or a missing key ⇒ the suite fails with `skills-spec unreadable`. It never falls back to numbers built into the script. The existing section (3) fixtures gain `version` and `lastUpdated` so they stay conforming.

**Part C — bring main to green in the same change.** Shorten `loomwright/skills/rules/SKILL.md`'s `description` to at most `description_max` characters, keeping its "Use when …" clause. Any detail the trimmed text carried that the body does not already state moves into the body; none is deleted. Patch-bump that skill's `version` (1.4.1 → 1.4.2) and its `lastUpdated`, then regenerate the index with `bash scripts/check-skills-index-sync.sh --write`. No baseline or exemption file.

## Acceptance Criteria

All cases run inside `loomwright/scripts/test-skill-frontmatter.sh` under `hermetic-test-env.sh`. Fixture cases build trees under the suite's scratch dir, as section (3) does today. No network.

**Happy path**
- [ ] Given main with Part C applied, when `bash loomwright/scripts/test-skill-frontmatter.sh` runs, then it exits 0, reports the scanned count (> 0) across both plugins, and prints an `ADVISORY` line for each SKILL.md over `advisory_max_lines`. The suite asserts that advisories never fail it; it does not assert a count.
- [ ] Given a conforming fixture skill (`name: alpha` in `alpha/`, a quoted single-line description, `version: "1.0.0"`, `lastUpdated: "2026-10"`), then no `VIOLATION` line is printed for it.
- [ ] Given the suite's source, then every limit is read from `loomwright/docs/skills-spec.json` with `jq`, and no limit number appears as a literal in the suite (a grep case over the suite file).

**Edge cases**
- [ ] Given a description of exactly `description_max` characters, then it passes; given `description_max + 1`, then `VIOLATION … description is <n> chars > <max>`. Quotes are not counted. A description of `description_max` characters that contains multi-byte characters passes (characters, not bytes).
- [ ] Given `description: >` followed by indented lines, or `description: |`, then `VIOLATION … description is not a single-line scalar`.
- [ ] Given a skill with no `description:`, an empty one, or two `description:` lines, then a `VIOLATION` naming the case.
- [ ] Given a name `Alpha_1` in a directory `Alpha_1`, then the directory check passes but `VIOLATION … name fails name_pattern`. Given `a--b` in `a--b/`, then the same violation. Given a 65-character lowercase name equal to its directory, then `VIOLATION … name longer than name_max`.
- [ ] Given a skill with no `version:` (the case `check-skills-index-sync.sh` skips), then `VIOLATION … missing required key version`. Given `version: v1.2`, then `VIOLATION … version fails version_pattern`. Given no `lastUpdated:`, then `VIOLATION … missing required key lastUpdated`.
- [ ] Given a `stackpack`-shaped fixture skill (a second plugin dir) over `advisory_max_lines`, then its `ADVISORY` line names `none` as the hard size gate, and the suite still exits 0.

**Error scenarios**
- [ ] Given `skills-spec.json` missing, given it malformed, and given it without `description_max`, then in each case the suite exits non-zero with `skills-spec unreadable`.
- [ ] Given fixture mutants for the length rule, the block-scalar rule, the `version` presence rule and the `name_pattern` rule, then each is reported by its own `VIOLATION` line, so no new rule can turn vacuous without a red case. Given an over-length fixture with no other defect, then the suite's verdict for that tree has no `VIOLATION` (an advisory never becomes a failure). The existing (3) mutants A and B stay and stay green.
- [ ] Given Part C applied, then `bash scripts/check-skills-index-sync.sh`, `bash scripts/check-token-budget.sh`, `bash scripts/check-doc-currency.sh` and `bash scripts/check-vendor-coupling.sh` each exit 0.

## Non-goals
- Body section structure (the template's `## When to Use` … sections); 19 protocol-authority skills do not use them.
- A hard size ceiling for `stackpack/skills/`; it is reported as advisory here.
- Promoting the line advisory to a failure.
- Reserved words in `name` (`anthropic`, `claude`, `synced`).
- Checking `when_to_use` or the combined 1,536-character Claude Code listing cap. No skill uses `when_to_use` today.
- A format check on `lastUpdated` (presence only; main mixes `2026-03` and `2026-09-06`).
- Running `claude plugin validate` in CI.
- Agent and command frontmatter.

## Owner decisions
- 2026-11-09 (Vikash, in chat): APPROVED from the archive review; refreshed against main 8ec200e / v17.35.1.
- 2026-11-09 (Vikash, in chat): extend the existing `test-skill-frontmatter.sh`; no second frontmatter parser (source OQ-K2).
- PO default, pending owner review: limits as read on 2026-11-09 from the Agent Skills specification (stricter than Claude Code's docs): `name` ≤ 64 and `^[a-z0-9]+(-[a-z0-9]+)*$`, `description` ≤ 1,024 characters, advisory 500 lines (source OQ-K1, now verified, not from memory).
- PO default, pending owner review: description length counts characters, not bytes, as the spec does. The `rules` description is 1,129 characters and 1,131 bytes; it fails either way.
- PO default, pending owner review: fix the `rules` description in this change, with no baseline file (OQ-K3); require `lastUpdated` as well as `version` (OQ-K7); no body-section rule (OQ-K4); advisory-only size report, with stackpack getting no hard ceiling (OQ-K5); no reserved-word rule (OQ-K6).
- PO default, pending owner review: keep the approved separate `loomwright/docs/skills-spec.json` (cited sources live next to the numbers) rather than constants at the top of the suite.

## Priority: Phase 2
**Rationale:** Cheap, self-contained and runnable now. It closes a real silent gap: a versionless skill passes every current gate, and a 1,129-character description is live on main. Nothing user-visible is broken today. The Claude Code listing truncates at 1,536 characters, so the `rules` skill still lists in full.

## Assumptions
- The repo's one-line awk parsers (`fm_values`, `check-skills-index-sync.sh`, `build-capabilities.sh` `fmval`) are the binding constraint, so single-line `description` is the safe rule even though YAML allows block scalars.
- `jq` is available wherever the suite runs (CI and `ci-local.sh`), as it is for the other suites that read `loomwright/docs/*.json`.
- `loomwright/skills/rules/SKILL.md` has 1,721 proxy tokens of headroom (`check-token-budget.sh`). Moving detail from the description into the body is close to size-neutral, so no budget change is expected. `prompt-token-budgets.json` and its mirror row in `ARCHITECTURE_CONTRACTS.md` are listed in Touches only in case the gate asks.
- Shortening the description cannot raise a vendor-coupling count; that ratchet never requires exact equality, so `vendor-coupling-manifest.json` needs no edit.

## Dependencies
- Depends on: none.
- Blocks: none.

## Risks
- **Routing signal:** a shorter `rules` description could change when the model loads that skill. Mitigation: keep the "Use when running /rules or modifying any part of the rules substrate" clause and the key nouns.
- **Spec drift:** the external documents can change. Mitigation: the limits live only in `skills-spec.json` with URL and read date, so a change is one value.
- **A new docs file under a gated root:** `loomwright/docs/` is a `check-vendor-coupling.sh` scan root. The spec file's URLs must not contain a counted token (for example `.claude/`); `code.claude.com/docs` does not.
- **An unread advisory:** it prints in CI output next to the hard gate it names. Making it a failure is a later owner choice.

## Validation (must pass before merge)
1. **Static — the lint:** `bash loomwright/scripts/test-skill-frontmatter.sh` passes on main with Part C applied, including every new fixture, mutant, spec-unreadable and no-literal case.
2. **Static — neighbouring gates:** `bash scripts/check-skills-index-sync.sh`, `bash scripts/check-token-budget.sh`, `bash scripts/check-doc-currency.sh` and `bash scripts/check-vendor-coupling.sh` pass.
3. **Static — repo gates:** `bash scripts/ci-local.sh --affected` passes; run directly any suite it lists as not covered.
4. **Static — release:** the PR adds `changelog.d/skills-spec-lint.md` and never hand-edits `plugin.json`, `marketplace.json` or `CHANGELOG.md`; `bash scripts/check-version-bump.sh` passes.

## Depends on
none

## Touches
loomwright/docs/skills-spec.json
loomwright/scripts/test-skill-frontmatter.sh
loomwright/skills/SKILL_TEMPLATE.md
loomwright/skills/rules/SKILL.md
loomwright/skills/SKILLS_INDEX.md
loomwright/docs/prompt-token-budgets.json
loomwright/docs/ARCHITECTURE_CONTRACTS.md
changelog.d/skills-spec-lint.md

## Changes since the source was written
- **External limits verified.** The source took them "from memory, UNVERIFIED". They were read on 2026-11-09 from agentskills.io and Claude Code's skills docs, and they match the source's defaults. New facts: Claude Code treats `name` and `description` as optional and truncates `description` plus `when_to_use` at 1,536 characters; both documents recommend under 500 lines.
- **Baseline re-measured on `8ec200e`.** Still 60 SKILL.md files and one over-long description (`rules`, 1,129 characters / 1,131 bytes). Still six files over 500 lines, with new counts for two of them: `review-heal` 574 → 583, `supervisor-readiness` 555 → 556.
- **Character vs byte unit made explicit.** The source's "about 1,129" and the owner's 1,131 are the same description measured in characters and in bytes.
- **Touches trimmed.** `loomwright/docs/vendor-coupling-manifest.json` was dropped: its ratchet never requires equality, and a shorter description cannot raise a count. `ARCHITECTURE_CONTRACTS.md` was added as the mirror of `prompt-token-budgets.json`, and the changelog entry is named as one fragment file.
- **Mutation cases restated** as fixture mutants, matching the suite's existing section (3) pattern, instead of edits to the checker's own code.
- **Two cases added:** a `--` name, and a multi-byte description at the limit. `when_to_use` and a `lastUpdated` format check are named as non-goals.
