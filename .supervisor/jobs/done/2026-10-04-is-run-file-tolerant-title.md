# Supervisor Job: is_run_file tolerates a BOM, ATX-legal indentation, whitespace and case in the run-file title

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes-v2/v2-a (S1 v2 lane v2-a clone of loomwright)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main (== origin/main)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1
- **Source requirement:** .supervisor/requirements/automate-followups/19-is-run-file-tolerant-title.md
- **Base commit:** 6a048be267c5526c23f2fdc5ee00841f85157f89

> **Warning (1):** this clone is one lane of the S1 two-lane spike (v2). A sibling lane (v2-b, item 18) runs
> concurrently in a SEPARATE clone; both touch `loomwright/scripts/automate-helpers.sh` and
> `loomwright/scripts/test-automate-helpers.sh`, so the two PRs may conflict textually at merge time. The v1 attempt
> at this item (closed PR #370, branch `s1v1/item-19`) is kept for comparison and MUST NOT be read or reused —
> this run is an independent rerun. The branch name `feature/is-run-file-tolerant-title` is free (v1 moved to
> `s1v1/item-19`); never push to `s1v1/*`.

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Pure bash 3.2 + BSD grep/sed/awk, the repo's existing surface. No new dependency. |
| 2 | Dependency Availability | GO | `grep -E`, `printf` octal escapes, `awk` all present on macOS and CI Linux. |
| 3 | Architecture Fit | GO | Widens one shape predicate; keeps the §4 "hiding a run is the worse failure" direction. No schema change, no gate change. |
| 4 | Scope vs Supervisor Capability | GO | One function + its test section, one title reader + its test, two doc rows, one changelog fragment. Single subtask. |
| 5 | Hard Blockers | GO | All paths exist; the changelog fragment is the only create. |

**Overall Verdict:** GO

## Task
**Goal:** Make `is_run_file` (and the `/handoff` run-file title reader) recognise a `/automate` run file whose title
line differs from the exact `# Automate Run:` form only in a leading UTF-8 BOM, CommonMark-legal indentation,
whitespace, or letter case — while result sidecars, H2 lines and indented code blocks are still NOT run files.

**Problem Statement:**
The `/automate` RESUME path needs to see every incomplete run, because a hidden run is silently forgotten and a
second run starts beside it.
Currently `is_run_file()` in `loomwright/scripts/automate-helpers.sh` is `grep -qE '^# Automate Run:'` — exact, case-
sensitive, BOM-intolerant. A run file saved by an editor that adds a BOM, or hand-edited to `#  Automate Run:` /
`# automate run:`, is dropped by `resume-glob`, and `runfile-write` / `progress-append` / `queue-checkoff` refuse to
write it. `build-handoff.sh` reads the title with a different leniency (`^#[[:space:]]*Automate Run:`), so the two
readers disagree on what a run file is.
Success looks like: both readers accept the same set of title forms, the sidecar/H2/code-block negatives stay
unlisted, and a mutation control proves each new tolerance is load-bearing.

## Decisions (owner-reviewable at Phase 6)
- **D1 — case-insensitive: YES.** The predicate's failure direction is "hide a run"; matching `# automate run:` costs
  nothing (no sidecar carries that phrase) and removes a hiding path.
- **D2 — BOM:** an optional UTF-8 BOM (bytes EF BB BF) immediately before the line content is accepted. BSD grep ERE
  has no `\x` escape — build the byte string with `printf` octal (`\357\273\277`) and run the match under
  `env LC_ALL=C` (the repo's `check-locale-prefix.sh` gate forbids the bare `LC_ALL=C grep` prefix form).
- **D3 — indentation capped at 0–3 spaces** (the CommonMark ATX-heading limit). A line indented 4+ spaces, or
  starting with a tab, is an indented code block, not a heading — e.g. a sidecar or requirement quoting
  `    # Automate Run: x` in a code example must NOT be listed as a run (that would re-create the
  `resume_ambiguous` failure automate-followups/03 fixed).
- **D4 — whitespace:** zero-or-more spaces/tabs between `#` and `Automate`, one-or-more between `Automate` and `Run`,
  zero-or-more before `:`. Exactly ONE `#` — `## Automate Run:` (H2) is not a run file.
- **D5 — same forms in `build-handoff.sh`:** its title reader must accept exactly the same title-line forms (strip the
  BOM and indentation, case-insensitive), and still fall back to the basename when no title line exists. The two
  regexes are mirrored copies (handoff does not source the helper) — each carries a comment naming the other.

## Acceptance Criteria
- [ ] AC1 — Given a run file (`## Status: paused`) whose title line is each of: BOM + `# Automate Run: x`;
  `#  Automate Run: x` (extra space); `#Automate Run: x` (no space); `# Automate   Run : x` (inner spaces);
  `# automate run: x` (lower case); `   # Automate Run: x` (3-space indent), when `resume-glob` runs, then each is
  listed — one fixture per form, asserted separately in `test-automate-helpers.sh` §D0b.
- [ ] AC2 — Given a directory holding a done run plus files whose only title-like line is `## Automate Run: x` (H2),
  `    # Automate Run: x` (4-space indent), a tab-indented `# Automate Run: x`, and the two existing result sidecars,
  when `resume-glob` runs, then nothing is listed and it exits 0.
- [ ] AC3 — Given a complete run file (title + `## Status:` + `## Queue` + `## Progress`) whose title is a tolerated
  non-exact form (at least the BOM form and the lower-case form), when `progress-append`, `queue-checkoff` and
  `runfile-write` (with that same content on stdin) run, then each succeeds (exit 0) instead of refusing.
- [ ] AC4 — Given the existing always-true `is_run_file` mutation control, when the test suite runs, then the mutant is
  still actually injected (its `sed` is re-targeted at the new function body, gated on non-empty + differs +
  `bash -n` + the override string present) and still leaks exactly the two sidecars.
- [ ] AC5 — Given a NEW gated mutant that restores the old exact `^# Automate Run:` match, when it runs against the AC1
  fixtures, then the tolerant fixtures (at least BOM, lower-case and extra-space) are NOT listed — proving the new
  tolerance is what lists them; and a second NEW gated mutant that lifts the 0–3 indentation cap (e.g. allows any
  leading whitespace) DOES list the 4-space-indented negative from AC2 — proving the cap is load-bearing.
- [ ] AC6 — Given a seeded run file whose title is BOM + lower-case + extra-space, when `build-handoff.sh` renders the
  digest, then the item's title is the text after the colon (not the basename); and given a file whose only title-like
  line is an H2 `## Automate Run:` line, and separately one whose only title-like line is indented 4 spaces, then the
  basename fallback is used in both (the indentation cap is tested in both readers).
- [ ] AC7 — Given the `is_run_file` header comment, when read, then it names ALL its real callers — `resume_glob`, the
  `runfile-write` validator (staged-content and existing-file checks), `progress_append`, `queue_checkoff`, and
  `plan_waves` (its run-file-vs-item-list input branch) — instead of "Called ONLY from resume_glob", and states D1–D4.
- [ ] AC9 — Given a run file whose title is BOM + lower-case (`# automate run: x` after the BOM) with unchecked
  `- [ ]` Queue rows, when `plan-waves` runs on it (§W fixture conventions: `mktemp -d`, `--root` = fixture root),
  then it is parsed as a run file — the plan set is its unchecked Queue rows — not as an item list.
- [ ] AC10 — Given `skills/automate-loop/SKILL.md`, when its §1.5 helper-table `resume-glob` row is read, then it
  carries a pointer to the tolerated forms (e.g. "tolerant title forms: §4 step 1") rather than restating them; the
  `runfile-write` / `progress-append` / `queue-checkoff` rows and `commands/automate.md` stay as they are (the exact
  form is still accepted, so they remain true) — the PR body says so explicitly.
- [ ] AC8 — Given the whole change, when `bash scripts/ci-local.sh` runs, then it is green (doc-currency, citation-drift,
  locale-prefix, and every `loomwright/scripts/test-*.sh`), and the PR carries a `changelog.d/<slug>.md` fragment and
  NO hand-edited version file.

## Outcomes Rubric
- `is_run_file` accepts BOM / 0–3-space indent / whitespace / case variants of the H1 title, and nothing else new.
- Sidecars, H2 lines, and 4+-space or tab-indented lines are still not run files (negative legs present).
- Every new tolerance and the indentation cap are each pinned by a gated mutation control that turns a leg red.
- `build-handoff.sh` and `is_run_file` accept the same title forms, including the indentation cap.
- The `is_run_file` comment names every caller, `plan-waves` included, and `plan-waves` still parses a tolerated run file.
- The write validators accept a tolerated title (they share the predicate).
- No version file hand-edited; a changelog fragment is present; CI-local green.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Tolerant `is_run_file` + mirrored handoff title reader, tests, docs | ALL (AC1 … AC10) | 6 modify, 1 create | `unit-testing`, `quality-checklist` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "RUN_TITLE_ERE"}
  - {kind: "symbol", path: "loomwright/scripts/build-handoff.sh", name: "mirrors is_run_file"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-helpers.sh", name: "is_run_file exact-match mutant"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-helpers.sh", name: "is_run_file indent-cap mutant"}
  - {kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "tolerated title forms"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/SKILL.md", name: "tolerant title forms"}
  - {kind: "file", path: "changelog.d/is-run-file-tolerant-title.md"}
requires: []
lanes:
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/test-automate-helpers.sh"
  - "loomwright/scripts/build-handoff.sh"
  - "loomwright/scripts/test-build-handoff.sh"
  - "loomwright/docs/RESULT_SCHEMAS.md"
  - "loomwright/skills/automate-loop/SKILL.md"
  - "changelog.d/is-run-file-tolerant-title.md"
external_requires: []
```

**Exact-name mandate:** every `provides` name above is a literal string that does NOT exist on base 6a048be and MUST
appear after the change — `RUN_TITLE_ERE` (the shared title ERE variable `is_run_file` matches against, defined in
`automate-helpers.sh`); the literal comment phrase `mirrors is_run_file` on `build-handoff.sh`'s title reader (D5);
the two mutation-control leg labels `is_run_file exact-match mutant` and `is_run_file indent-cap mutant` (AC5) in the
`ok`/`no` messages of `test-automate-helpers.sh`; the phrase `tolerated title forms` in `RESULT_SCHEMAS.md`'s
§AUTOMATE_RUN title row; and the phrase `tolerant title forms` in `SKILL.md` (the §1.5 resume-glob pointer, AC10).
Renaming any of these voids the `outputs_verified` gate.

## File Impact Map

| Group | Files to Modify | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| predicate | `loomwright/scripts/automate-helpers.sh` (`is_run_file` + its header comment) | — | HIGH |
| predicate tests | `loomwright/scripts/test-automate-helpers.sh` (§D0b legs, re-targeted always-true mutant, two new mutants, one §W plan-waves leg) | — | HIGH |
| handoff | `loomwright/scripts/build-handoff.sh` (AUTOMATE title reader), `loomwright/scripts/test-build-handoff.sh` | — | HIGH |
| docs | `loomwright/docs/RESULT_SCHEMAS.md` (§AUTOMATE_RUN title row), `loomwright/skills/automate-loop/SKILL.md` (§4 step 1 — one clause naming the tolerated forms; §1.5 resume-glob row — pointer clause) | `changelog.d/is-run-file-tolerant-title.md` | MEDIUM |

## Parallelism Analysis
Single subtask, one batch, one worker. No overlap analysis needed.

## Skill References

| Skill | Why |
|---|---|
| `skills/unit-testing/SKILL.md` | Leg structure for the new fixtures |
| `skills/quality-checklist/SKILL.md` | Pre/post-implementation gates |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Over-widening: any leading whitespace accepted, so an indented code example in a sidecar is listed as a run (re-creates `resume_ambiguous`) | HIGH | D3 caps indentation at 0–3 spaces; AC2 negative legs; AC5 mutant lifting the cap must turn a leg red |
| A mutation control silently invalid (empty mutant from a sed delimiter collision; the old always-true `sed` no longer matching the new function line) | HIGH | Verified lesson fa32a308: gate every mutant on non-empty + differs-from-original + `bash -n` + override-string-present (AC4/AC5) |
| BOM handling differs between BSD and GNU grep (`\x` unsupported in BSD ERE; multibyte locale may not match raw bytes) | MEDIUM | D2: `printf` octal byte string, `env LC_ALL=C` grep; the test builds the BOM fixture with `printf '\357\273\277'` |
| Bare `LC_ALL=C grep` prefix trips `check-locale-prefix.sh` | MEDIUM | Use `env LC_ALL=C grep` |
| The two title regexes drift again | MEDIUM | D5: mirrored comments naming each other + AC6 legs exercising the same forms |
| Widening changes `plan-waves` input classification: an item-list file that happens to contain a tolerated title-like line (e.g. `# automate run: …`) is now read as a run file | LOW | AC7 names the caller; AC9 pins the positive case; item lists are bare path lines in practice, so a title-like H1 there is unlikely |
| Sibling lane v2-b edits the same two helper files → merge conflict | LOW | Keep the diff local to `is_run_file`, its comment and §D0b; resolve at merge time (owner-ordered) |
| `build-handoff.sh` indexes every `.supervisor/automate/*.md` (sidecars included) as an AUTOMATE item | LOW | Out of scope here (not a title-reader defect); note it in the PR body as a follow-up candidate, do not fix |
| New bare `file:N` citation in committed prose | LOW | Use descriptive anchors or `[pins: …]` (test-citation-drift.sh) |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-04-is-run-file-tolerant-title.md
```

## Plan Review: PASS (attempt 2/3)

## Outcome
- **Status:** completed
- **Completed:** 2026-10-04T08:18:54Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/374
- **Branch:** feature/is-run-file-tolerant-title
- **Files changed:** 7
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0
- **Rubric score:** 7/7
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** is_run_file + build-handoff title reader share RUN_TITLE_ERE (optional BOM, 0-3 space indent, any case, flexible whitespace, one #); negatives/sidecars unlisted; gated mutants; Phase 4.5 PASS on iteration 1 (consistency_audit, all scratch repros held) with 2 LOW nits + 1 pre-existing LOW dismissed; risk_classification high_risk=true (skills/ path, advisory); ground truth 2/2; detached drain suppressed by /automate (owned drain follows).

## Not verified
- **/automate RESUME end-to-end on a real BOM/lower-case run file** — needs a live /automate run; helper exercised in mktemp fixtures only (subtask 1)
- **GNU grep/sed behaviour of RUN_TITLE_ERE with raw BOM bytes** — macOS BSD only locally; CI runs Linux (subtask 1)
