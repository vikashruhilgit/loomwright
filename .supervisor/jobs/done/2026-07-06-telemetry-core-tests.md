# Supervisor Job: Direct unit tests for send-telemetry-core.sh (tests-only)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh, v15.2.1)
- **Git:** clean, branch: main @ b5c0561 (up to date with origin)
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **legacy_brief:** true (single-subtask — inter-subtask contracts vacuous)
- **Source requirement:** .supervisor/requirements/review-remediation/02-telemetry-core-tests.md

## Task
**Goal:** Give the privacy/consent/dedup logic in loomwright/scripts/send-telemetry-core.sh (1078 lines; the one component whose regression could leak user data to a public GitHub issue) a direct deterministic self-test: new `loomwright/scripts/test-send-telemetry-core.sh`. Zero behavior change to the core unless a test exposes a real bug (then fix + regression assertion + explicit PR callout).

## Acceptance Criteria
- [ ] Given the new test-send-telemetry-core.sh, when run via `bash` (NOT zsh) on macOS bash 3.2, then it passes deterministically with no network and exits non-zero on any failed assertion; it is bash-3.2-safe (no mapfile / assoc arrays / `;&`), and numeric probes are validated before arithmetic (stat `-c %Y` then `-f %m` fallback if mtime is needed).
- [ ] Given the CI nullglob loop (ci.yml lines 40–50 auto-includes `loomwright/scripts/test-*.sh`), when CI runs on the PR, then the new test appears in the log and passes.
- [ ] All 7 matrix groups implemented: (1) privacy true-positives — one fixture per pattern label ×9 (openai-key, github-token, api-key, bearer, password, macos-home-path, linux-home-path, email, env-assignment; core:117-125), each asserting exit 2 + a stderr line naming the label; (2) privacy true-negatives (near-misses: `sk-short`, `ghp_short`, "apikey in prose without =", `/Users/` without a username segment) NOT exit 2; (3) ordering guarantee — secret + healthy-score payload exits 2 not 5 (v11.2.0 raw-scan-before-consent regression); (4) consent matrix — absent file → 3; `{"telemetry":"no"}` → 3; malformed JSON → read the code FIRST, then assert the actual (fail-closed expected) behavior; `always_allow` without repo → 4; `always_allow` + `telemetry_repo` + `--dry-run` → would-send (`WOULD_EXIT=0`); (5) nullable/missing-key discipline — BOTH missing-key AND explicit-null for consent fields (jq `has()` lesson from PR #84); (6) dedup determinism — same task_id::bucket::primary_error twice within window → second exits 5; different primary_error → not deduped (seed telemetry-sent.log in a mktemp sandbox); (7) redaction — redacted body contains `[REDACTED:<label>]` markers.
- [ ] `gh` proven never invoked: PATH shim that fails loudly if called, and/or `--dry-run`-only paths with `WOULD_EXIT` assertions.
- [ ] All temp state under a mktemp sandbox; the real `.supervisor/` is never touched; the wrapper's always-exit-0 fail-safe invariant is untouched.
- [ ] Version bump from 15.2.1 per repo convention (patch 15.2.2 expected for tests-only — confirm against validate-version.sh/CHANGELOG precedent) + CHANGELOG entry; counts unchanged 14/21/57/21 (a scripts/ test is uncounted); check-doc-currency.sh + check-command-sync.sh + validate-version.sh pass; CLAUDE.md/README banner rotation per two-most-recent convention.

## Verified Evidence (Phase 3)
- Core: 1078 lines; anchor on the `PRIVACY_PATTERNS` identifier (9 labeled tuples at ~core:116-124, stage-1 Python; `PRIVACY_BLOCKED pattern=<label>` stderr emit at ~core:724); exit-contract in header (0/2/3/4/5); `--dry-run` prints `WOULD_EXIT=` markers at multiple decision points; consent/log paths are `$PWD`-based (core:42-44) so sandbox-CWD isolation works; telemetry-sent.log appended only on the live path, so group-6 dedup must seed the log in the sandbox.
- Test conventions: 36 sibling `test-*.sh` under loomwright/scripts/; test-telemetry.sh's actual fixture convention is `loomwright/scripts/telemetry-fixtures/` (test-telemetry.sh:57) — follow that convention (or a telemetry-core/ subdir of it), NOT the generic `fixtures/` dir.
- CI: nullglob hard-gate loop runs every `test-*.sh` automatically — no ci.yml edit needed.
- Known accepted trade-off: email regex over-match — document in a test comment, do NOT change the regex.

## Subtask Structure

| # | Title | Est. Files | Status |
|---|-------|-----------|--------|
| 1 | test-send-telemetry-core.sh + fixtures + version bump/CHANGELOG/banners | 1–2 create (test + fixtures dir), ~5 modify (plugin.json, marketplace.json, CHANGELOG, CLAUDE.md, README) | LAUNCHABLE |

## Parallelism Analysis
- Single subtask, fast-path, 1 worker. Test + fixtures are one coherent unit; version/doc bump must be consistent with the same change.

## Skills
- unit-testing, quality-checklist. Reference: docs/TELEMETRY.md (scoring rubric, exit-code table).

## Configuration
- base branch: main; heal iterations: default 3.

## Risk Assessment
| Risk | Severity | Mitigation |
|------|----------|------------|
| bash-3.2 vs Linux CI divergence (stat/date/sed -i flavors) | HIGH | Memory "stat-flavor-setu-arithmetic-trap": try `-c %Y` first, validate numeric before arithmetic; run test via `bash` locally; keep pure-bash where possible |
| Test wedges on large payloads (bash-3.2 pattern-sub O(n²) trap) | MEDIUM | Keep fixtures small; avoid `${var//…}` on large strings (memory "bash32-pattern-sub-wedge") |
| Malformed-consent behavior assumption wrong | MEDIUM | AC mandates read-code-first, assert actual behavior; if a real fail-open bug is found, fix + call out per requirement |
| Sandbox leakage into real .supervisor/ | MEDIUM | mktemp sandbox + explicit assertion that HOME/config paths are overridden; core reads consent path — verify it's overridable or run from sandbox CWD |

## Test Plan
- `bash loomwright/scripts/test-send-telemetry-core.sh` green locally; `bash loomwright/scripts/test-telemetry.sh` still green (untouched unless trivial).
- All three CI validator scripts pass.
- PR description: note any real bug found+fixed (none expected), and the `gh`-never-invoked proof.

## Out of Scope
Rewriting privacy regexes (email over-match accepted), webhook tests (item 06), any wrapper change.

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-07-06-telemetry-core-tests.md

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/92
- **heal_loop_ran:** true
- **heal_decision:** PASS
- **heal_iterations:** 0
- **heal_remaining_issues:** 0
- **rubric_score:** null (no Outcomes Rubric)
- **Until-mergeable dispatched:** false (default dispatch suppressed by /automate engine; owned inline drain follows)
