# Supervisor Job: Dismissed-findings triage sweep — fix the 7 still-open cheap findings (doc/prose + one test file) from run automate-2026-09-26-115755, ship the 4 behavioural ones as `proposed/` drafts (v15.115.1)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** `main` == origin/main @ 0dc0a5b. Uncommitted, NOT this job's to commit: the tracked run file `.supervisor/automate/automate-2026-09-30-054439.md` (live Progress lines), `.supervisor/requirements/agnostic-phase1/` (owner WIP), `.supervisor/requirements/automate-followups/14-closeout-fail-safe.md` (owner-added Queue item). Commit EXPLICIT paths only — never `git add -A`/`.`/`-u`.
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/automate-followups/13-dismissed-findings-triage-sweep.md

## Task
**Goal:** Close out the item-13 triage sweep. Scope (a) — classify findings 1–17 against `main` with evidence and get the owner's sign-off — is DONE (Launch Pad discovery, 2026-10-01, three read-only agents, scratch repros for 13/15/16/17; owner approved "as proposed"). This job implements scope (b) (fix the approved still-open cheap findings in ONE PR with a patch release) and commits the scope (c) drafts that are already written.

### Owner-approved classification (evidence, main@0dc0a5b)
| # | Verdict | Evidence | Disposition |
|---|---|---|---|
| 1 | still-open | `scripts/automate-helpers.sh` `is_run_file()` — `grep -qE '^# Automate Run:'` exact; `build-handoff.sh` lenient | DRAFT (written) |
| 2 | still-open (nit) | `skills/automate-loop/SKILL.md` §1.5 `resume-glob` row: "…the … result sidecars … never are, so they are never listed" — unconditional, though the title is matched ANYWHERE in the file; §3 + RESULT_SCHEMAS §AUTOMATE_RUN already use the conditional form; `automate-helpers.sh` usage comment for `resume-glob` says "§6 result sidecars never listed" | FIX |
| 3 | still-open | `gate_eval` cond 7 runs `rules-gate-verdict.sh --root "$root"` with no `HEAD == live_head` / clean-tree pin | DRAFT (written) |
| 4 | already-fixed c4b8cb9 | supervisor.md / FAILURE_ESCALATION / self-heal-advisory carry the co-gate wording | — |
| 5 | already-fixed a01f1b0 | root CLAUDE.md D3 is now a pointer to §10 cond 7 | — |
| 6 | still-open | `RULES_PASSABLE` includes `unstamped`; review-heal drain treats unstamped advisory | DRAFT (written) |
| 7 | already-fixed a01f1b0 | `countable_set_drift` PARK text | — |
| 8 | still-open | `skills/self-heal-advisory/SKILL.md` §"Rules-check replay": `rules_check_line` reaches `cmd_disabled` only via `if $NO_CMD_FLAG is non-empty`; an AMBIENT `RULES_CHECK_NO_CMD=1` makes `rules-gate-verdict.sh` return verdict `cmd_disabled` with `checks_passed` null, so the line falls through to `rules_check: none` (report line only — gating unaffected) | FIX |
| 9 | still-open | `skills/automate-loop/SKILL.md` §10 cond 7 "**Honest limit (dormancy):** on a store with no countable `must` rule … the verdict is `none` and the condition always holds" — unqualified; neighbouring bullets already say a non-parseable store is `unreadable` (never `none`) and drift can empty the live countable set (⇒ `unstamped` park) | FIX |
| 10 | not-a-defect | CLAUDE.md "ALL SEVEN" matches §10, updated in the same change | — (owner skipped optional pointer) |
| 11 | not-a-defect | AC9(b) mutant (i) meets the literal wording | — |
| 12 | still-open | `CHANGELOG.md` v15.113.0 entry: "…every round of the owned `--until-mergeable` drain) reviewed with no knowledge of the rules" — the drain is heal-only; only the Earned Fallback Review spawns a reviewer, at most once per run | FIX |
| 13 | still-open (reproduced) | `scripts/test-rules-seams.sh` (B) only `grep -qF 'rules-check.sh'`; appending a `bash …/audit-rules.sh` line to `agents/code-reviewer.md` still passes | FIX (test-only) |
| 14 | not-a-defect | code-reviewer step 4 already ranks REVIEW.md; effective order identical | — (owner skipped optional tweak) |
| 15 | still-open (reproduced) | `scripts/session-resume.sh` `rules_nudge()`: `rules_out="$(bash "$reader" 2>/dev/null \|\| true)"` with `reader=…/read-rules.sh` on an earlier line; seam (C)'s scan skips lines lacking the literal `read-rules.sh`, so a `\| bash` added to that call passes | FIX (test-only) |
| 16 | still-open (reproduced) | `test-rules-seams.sh` `seam_c_is_sink` matches only `'| bash'`/`'| sh'` (space) + eval/source/`$(bash`; in-span `\|bash`, `\| zsh`, `\|& bash`, `. <(bash …/read-rules.sh)` all pass | FIX (test-only) |
| 16b | already-fixed 69698db | the extra #301 finding (sink after the closing backtick) — `SEAM_C_AFTER_SPAN_RE` | — |
| 17 | still-open (reproduced) | telemetry `issues_by_severity` derived from the BLOCKING/HIGH-only body list (5d9f7a2); `Failed: true` by spec | DRAFT (written); issues #282/#287/#297/#302 closed by owner decision |

## Acceptance Criteria
- [ ] **AC1 (finding 2):** the §1.5 `resume-glob` row in `loomwright/skills/automate-loop/SKILL.md` states the exclusion conditionally (a sidecar is never listed BECAUSE it carries no `# Automate Run:` line, and the title is matched anywhere in the file) — same form as §3's sidecars paragraph and RESULT_SCHEMAS §AUTOMATE_RUN (§4 step 1 and the Quality Gates bullet are out of scope — not in the owner-approved verdict); the `resume-glob` usage comment in `loomwright/scripts/automate-helpers.sh` gets the same conditional wording (comment only — no code change).
- [ ] **AC2 (finding 8):** `rules_check_line` in `loomwright/skills/self-heal-advisory/SKILL.md` §"Rules-check replay" emits `rules_check: cmd_disabled` when `$NO_CMD_FLAG` is non-empty OR `rules.verdict == "cmd_disabled"` (ambient `RULES_CHECK_NO_CMD=1`); the "Line states" bullet below it, if it names when `cmd_disabled` appears, says the same.
- [ ] **AC3 (finding 9):** the §10 condition-7 dormancy honest limit in `loomwright/skills/automate-loop/SKILL.md` is qualified: `none` holds only for a READABLE store with no countable `must` rule; a corrupt / non-parseable store is `unreadable` (parks) and a drifted / legacy stamp with zero countable rules is `unstamped` (parks) — by pointer to the neighbouring bullets, not a restated list.
- [ ] **AC4 (finding 12):** the v15.113.0 CHANGELOG entry no longer claims "every round of the owned `--until-mergeable` drain" spawned a reviewer — it says the drain's Earned Fallback Review (at most once per run). Historical entry edited in place, nothing else in it changed.
- [ ] **AC5 (finding 13):** `loomwright/scripts/test-rules-seams.sh` assertion (B) also fails when `agents/code-reviewer.md` invokes `audit-rules.sh` (AC3's second half of item 10), with a mutant leg labelled exactly `B-mut-audit` that appends such a line to a scratch copy and must turn (B) red, plus the existing control staying green.
- [ ] **AC6 (finding 15):** seam (C) inspects `scripts/session-resume.sh`'s real reader call — either by resolving the `reader=` variable or by pinning the exact `rules_out="$(bash "$reader" …)"` shape — with a mutant (`… | bash`) that must turn (C) red.
- [ ] **AC7 (finding 16):** `seam_c_is_sink` catches `|bash`, `| zsh`, `| dash`, `|& bash`, `. <(…read-rules.sh…)` and `source <(…)` in-span (reuse the `\|&?[[:space:]]*(ba|z|da)?sh` form of `SEAM_C_AFTER_SPAN_RE`), with one mutant leg per new shape, run through the existing `c_mut_run <label> <file> <sed>` helper with the short labels `nospace`, `zsh`, `pipe-amp`, `dot-source`, `source-procsub` (so the file prints `(C-mut:nospace)` … `(C-mut:dot-source)` per its convention, and `c_mut_run dot-source` contains no literal `C-mut:dot-source` — so ALSO name the leg in its comment as `# C-mut:dot-source — …`, which is what the provides token greps) and the current repo surfaces still green (no false positive on the legitimate `bash …/read-rules.sh <paths>` invocations or prose containing "never").
- [ ] **AC8 (drafts):** the four drafts already in `.supervisor/requirements/proposed/` (`automate-followups-13-f01-is-run-file-tolerant-title.md`, `…-f03-gate-eval-cond7-pin-head.md`, `…-f06-fail-to-unstamped-silently-cleared.md`, `…-f17-telemetry-severity-counts-and-failed-semantics.md`) are committed in this PR UNCHANGED (each carries `## Status: proposed`; nothing is enqueued). `test-propose-work.sh` stays green.
- [ ] **AC9 (release):** 15.115.1 in `loomwright/.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json`; new top CHANGELOG entry naming the fixed findings and the drafted ones; skill frontmatter versions bumped for the two edited skills (`automate-loop` 1.8.0→1.8.1, `self-heal-advisory` 1.9.0→1.9.1) with matching `loomwright/skills/SKILLS_INDEX.md` rows (version AND last-updated date → 2026-10-01); `scripts/check-doc-currency.sh`, `scripts/validate-version.sh`, `scripts/check-skills-index-sync.sh` green.
- [ ] **AC10 (full loop green, hermetic):** every `loomwright/scripts/test-*.sh`, `loomwright/scripts/adapters/*/test-*.sh`, root `scripts/test-*.sh`; plus `scripts/check-vendor-coupling.sh` (after `git add`), `scripts/check-doc-currency.sh`, `scripts/check-command-sync.sh`, `scripts/check-skills-index-sync.sh`, `scripts/check-token-budget.sh`, `scripts/check-test-hermetic.sh`, `scripts/check-contract-parity.sh`, `loomwright/scripts/test-citation-drift.sh`. `test-rules-seams.sh` passes under macOS `/bin/bash` 3.2 too. Known pre-existing failures (orca-mirror leg L — gitignored sdk-spike/node_modules; test-hermetic-egress (R) under /bin/bash 3.2) are named, not fixed.
- [ ] **AC11 (scope fence):** no behavioural change to any script other than `test-rules-seams.sh` (findings 1/3/6/17 stay drafts — the owner did not promote them); `git grep -n "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` still resolves to the same five surfaces.

## Non-goals
- Fixing findings 1, 3, 6, 17 (drafts only — owner decision); the optional wording tweaks for 10 and 14 (owner skipped).
- Other runs' dismissed findings; the engine mechanism (item 12) and trail step (item 11).
- Editing the drafts' content.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Doc fixes 2/8/9/12 + seam test hardening 13/15/16 + commit drafts + 15.115.1 release | AC1–AC11 | 9 modify, 4 add (pre-written drafts) | unit-testing, quality-checklist | LAUNCHABLE |

## Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/scripts/test-rules-seams.sh", name: "B-mut-audit"}
  - {kind: "symbol", path: "loomwright/scripts/test-rules-seams.sh", name: "C-mut:dot-source"}
  - {kind: "symbol", path: "loomwright/skills/self-heal-advisory/SKILL.md", name: 'rules.verdict == "cmd_disabled"'}
  - {kind: "symbol", path: "loomwright/.claude-plugin/plugin.json", name: "15.115.1"}
  - {kind: "symbol", path: "CHANGELOG.md", name: "v15.115.1"}
  - {kind: "file", path: ".supervisor/requirements/proposed/automate-followups-13-f03-gate-eval-cond7-pin-head.md"}
requires: []
lanes:
  - "loomwright/skills/automate-loop/SKILL.md"
  - "loomwright/skills/self-heal-advisory/SKILL.md"
  - "loomwright/skills/SKILLS_INDEX.md"
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/test-rules-seams.sh"
  - "CHANGELOG.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
  - ".supervisor/requirements/proposed/automate-followups-13-f01-is-run-file-tolerant-title.md"
  - ".supervisor/requirements/proposed/automate-followups-13-f03-gate-eval-cond7-pin-head.md"
  - ".supervisor/requirements/proposed/automate-followups-13-f06-fail-to-unstamped-silently-cleared.md"
  - ".supervisor/requirements/proposed/automate-followups-13-f17-telemetry-severity-counts-and-failed-semantics.md"
external_requires: []
```

## Parallelism Analysis
- **Batch 1:** Subtask 1
- **Recommended workers:** 1 (Single-Agent Path)
- **Estimated batches:** 1

## File Impact Map

| Group | Files to Modify | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| skill prose | `loomwright/skills/automate-loop/SKILL.md` (§1.5 resume-glob row, §10 cond-7 dormancy, frontmatter), `loomwright/skills/self-heal-advisory/SKILL.md` (§"Rules-check replay" `rules_check_line` + Line states, frontmatter), `loomwright/skills/SKILLS_INDEX.md` (2 version cells) | — | HIGH |
| comment | `loomwright/scripts/automate-helpers.sh` (`resume-glob` usage comment only) | — | HIGH |
| seam test | `loomwright/scripts/test-rules-seams.sh` ((B), (C) scan + `seam_c_is_sink`, mutant legs) | — | HIGH |
| release | `CHANGELOG.md` (v15.113.0 in-place fix + new top entry), `loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` | — | HIGH |
| drafts | — | the four `.supervisor/requirements/proposed/automate-followups-13-f*.md` (pre-written, commit as-is) | HIGH |

> **Validator-owned surfaces:** `scripts/check-token-budget.sh` (skill prose growth — keep edits minimal), `scripts/check-skills-index-sync.sh` (frontmatter ↔ SKILLS_INDEX), `scripts/check-doc-currency.sh` (version claims), `loomwright/scripts/test-citation-drift.sh` (no new bare `file:N` citations in committed prose), `scripts/check-test-hermetic.sh` (test-rules-seams must keep sourcing the hermetic env if it already does).

## Skill References
- `skills/automate-loop/SKILL.md` §1.5, §3, §4 step 1, §10 condition 7 — the conditional-exclusion wording and the neighbouring cond-7 bullets to point at
- `skills/self-heal-advisory/SKILL.md` Part 1 §"Rules-check replay"; `scripts/rules-gate-verdict.sh` section (4) "the unattended no-cmd valve"
- `scripts/test-rules-seams.sh` header (SEAMS array, `SEAM_C_AFTER_SPAN_RE`, pass 1b) — mutant technique: scratch copy, never mutate the repo
- `skills/unit-testing/SKILL.md`, `skills/quality-checklist/SKILL.md`

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely.
  - enforcement: advisory · category: process
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority.
  - enforcement: advisory · category: process

> Applied here: AC3 qualifies the dormancy sentence by POINTER to the neighbouring bullets (no restated verdict list); the new CHANGELOG entry carries no restated counts.

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Widened `seam_c_is_sink` false-positives on a legitimate repo surface | MEDIUM | AC7: full current surface set must stay green; anchor sink shapes to the reader span / same line. |
| Mutant legs mutate the repo | HIGH | Scratch copies under `mktemp -d` only (existing technique); trap cleanup. |
| bash 3.2 / pipefail-grep traps in the test | MEDIUM | `[[ =~ ]]` with the regex in a variable (existing style); no `\| grep -q` under pipefail (`test-no-pipefail-grep-q.sh` lint); run under `/bin/bash`. |
| Editing a historical CHANGELOG entry trips doc-currency | LOW | Change only the overclaim clause; run `check-doc-currency.sh`. |
| Uncommitted owner files ride the commit | HIGH | Explicit-path `git add` only (Environment). |
| Token budget for self-heal-advisory / automate-loop | LOW | One-clause edits; `check-token-budget.sh`. |

## Configuration
- **Mode:** single-agent (1 subtask)
- **Recommended workers:** 1
- **Estimated batches:** 1
- **Target version:** 15.115.1 (patch — doc/test-only)

## Carried Plan Review advisories (Plan Review FAIL 1/3 → PASS 2/3 → owner chose fix + re-review → PASS 3/3; owner chose save + carry)
1. **LOW (optional) — `c_mut_run` message wording:** its CONFIRMED/REFUTED strings are hard-coded to the pipe-into-bash shape; for the new zsh / dot-source / source-procsub legs make them shape-neutral (e.g. "the exec-sink mutant of the real reader invocation"). Pass/fail logic keys only on `SEAM_C_LEAK` and is unaffected.

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-10-01-dismissed-findings-triage-sweep.md

## Outcome
- **Status:** completed
- **Completed:** 2026-10-01T02:21:42Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/319
- **Branch:** feature/automate-followups-13-dismissed-findings-triage-sweep
- **Files changed:** 12
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** Findings 2/8/9/12 fixed in prose, 13/15/16 in test-rules-seams.sh (B/C hardened; every new mutant except source-procsub was confirmed load-bearing), 4 proposed drafts committed (1/3/6/17), v15.115.1. Phase 4.5 iter 1 HIGH (legacy-stamp dormancy over-claim) fixed in e9dc41e with a class sweep; iter 2 PASS (11 scratch store states).

## Not verified
- **test-hermetic-egress (R) under /bin/bash 3.2** — known pre-existing failure per brief; loop ran tests with bash (subtask 1)
- **full test loop run serially** — ran with xargs -P 8; a serial-only failure would not show (subtask 1)
