# 02 — Direct unit tests for send-telemetry-core.sh (P0, tests-only)

## Goal
The privacy/consent/dedup logic in `loomwright/scripts/send-telemetry-core.sh` (~1,079 lines,
the only component whose regression could leak user data to a public GitHub issue) gets a
direct deterministic self-test, not just the existing wrapper-level fixture test.

## Evidence
- `loomwright/scripts/test-telemetry.sh` exercises the wrapper + consent states via fixtures,
  but does NOT unit-test core's stage-1 Python privacy scan, redaction, interest filter,
  or dedup hash directly.
- Privacy patterns (core ~lines 115–125): openai-key, github-token, api-key, bearer,
  password, macos/linux home path, email, env-assignment.
- Exit-code contract: 0 sent / 2 privacy_blocked / 3 no_consent / 4 no_repo_configured /
  5 filter_skipped. The v11.2.0 order-of-operations fix (raw-privacy scan BEFORE consent)
  is currently protected by nothing.

## Scope
Create `loomwright/scripts/test-send-telemetry-core.sh` (bash, mirrors existing test-*.sh
conventions — deterministic, no network, exit non-zero on any failed assertion, runs under
`bash` not zsh, bash-3.2-safe: no mapfile/assoc arrays/`;&` fallthrough). Use `--dry-run`
and/or environment isolation so `gh` is NEVER invoked (assert `WOULD_EXIT` where the
dry-run path supports it; otherwise stub `gh` via a PATH shim that fails loudly if called).

Test matrix (fixtures under `loomwright/scripts/fixtures/telemetry-core/` or reuse the
existing fixtures dir convention — check what test-telemetry.sh uses and match it):

1. **Privacy true-positives** — one fixture payload per pattern label (9 patterns): each
   must produce exit 2 and a `PRIVACY_BLOCKED` stderr line naming the label.
2. **Privacy true-negatives** — a benign payload containing near-misses (e.g. `sk-short`,
   `ghp_short`, "keyword: apikey mentioned in prose without =", a path like `/Users/` with
   no username segment) must NOT exit 2.
3. **Ordering guarantee** — a payload that BOTH contains a secret AND would be
   filter-skipped (healthy score) must exit 2, not 5 (regression test for the v11.2.0 fix).
4. **Consent matrix** — consent file absent → exit 3; `{"telemetry":"no"}` → exit 3 skip path;
   malformed JSON → treated per current behavior (read the code first, then assert THAT
   behavior — fail closed expected); `always_allow` without repo → exit 4;
   `always_allow` + `telemetry_repo` + dry-run → would-send path.
5. **Nullable/missing-key discipline** — per memory "nullable-required-field-needs-presence-check":
   test both missing-key and explicit-null for consent fields.
6. **Dedup determinism** — same task_id::bucket::primary_error twice within window → second
   run exits 5; different primary_error → not deduped. Seed `.supervisor/logs/telemetry-sent.log`
   in a temp sandbox dir.
7. **Redaction visibility** — a redacted body contains `[REDACTED:<label>]` markers.

Also: extend `test-telemetry.sh` ONLY if trivial; otherwise leave it untouched.

## Constraints / invariants
- Zero behavior change to send-telemetry-core.sh unless a test exposes a real bug — if it
  does, fix it in the same PR with its own regression assertion, and call it out in the
  PR description (do not silently fold fixes in).
- Test must pass on macOS bash 3.2 AND Linux CI (memory: stat-flavor/set-u trap —
  validate any numeric probe before arithmetic; try `stat -c %Y` then `-f %m`).
- All temp state under a mktemp sandbox; never touch the real `.supervisor/`.
- Emitter fail-safe invariant untouched: the wrapper still always exits 0.

## Acceptance criteria
- [ ] New test-send-telemetry-core.sh runs green locally via `bash` and in CI (it is picked
      up automatically by the ci.yml nullglob test loop — verify it appears in the CI log).
- [ ] All 7 matrix groups implemented; ≥1 assertion per privacy pattern label.
- [ ] `gh` proven never-invoked (PATH shim assertion or dry-run only).
- [ ] Counts unchanged; minor version bump (15.1.x → 15.2.0) + CHANGELOG entry, OR patch
      bump if the repo convention treats tests-only as patch — follow validate-version.sh.

## Out of scope
Rewriting the privacy regexes (the email over-match is a known accepted trade-off —
document it in a test comment, don't change it), webhook tests (item 06).

## Status: done
- Completed 2026-07-06 via /automate → PR #92 (v15.2.2), Phase 4.5 PASS, heal_iterations 0.
