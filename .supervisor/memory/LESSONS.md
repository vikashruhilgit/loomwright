# Project Lessons (advisory — bounded <=3 active per category; written only via write-lessons.sh)

## self-heal
- [51795404] A green heal_decision: PASS (especially with heal_iterations: 0) is NOT evidence the diff is review-clean — 5/8 such records preceded 3-6 post-PR review-fix rounds. During Phase 4.5 / /review-pr heal, apply the miss-class checklist as a DIFFERENT lens than the per-subtask reviewer, and verify ground_truth status != skipped on plugin-self doc-surface briefs.

## review-process
- [0d7865dc] A green check-doc-currency.sh is necessary but NOT sufficient for a consistency PASS. On any count/version/budget/phase/section change, grep the OLD value repo-wide before passing — the gate never scans Supervisor phase enumerations, per-row skill version cells in SKILLS_INDEX.md, per-run YAML frontmatter field lists in build-insights.sh, budget/zone numbers, or /insights dashboard section enumerations.

## security
- [a7e4fb1c] Any user/PR-text -> JSON in a firing path (webhook, telemetry, gh/curl) MUST be built with jq --arg, never echo or shell-templated JSON, and MUST be gated by a single-quote/backslash/newline round-trip test. This is payload-CONSTRUCTION injection safety, distinct from jq parse-time type-traps (see jq-optional-chain-type-trap memory).

## ops
- [4a97f733] Failure philosophy is bimodal: correctness gates fail CLOSED under --non-interactive/CI/stdin-not-tty (preflight_overlap_detected, non_interactive_without_fallback, rubric_gate_closed_non_interactive), while runtime side-effect emitters (telemetry wrapper, send-webhook.sh, session-resume observability probe) fail SAFE and ALWAYS exit 0. Inverting either flips the security posture silently.
- [898f4858] contract_conformance_status: skipped means UNVERIFIED, not clean — it ran in only 3/7 recent twin sessions and found a violation in 2 of those 3. Never credit a session as conformant on a skipped check; conformance only runs when the brief authored an ## Executable Acceptance ground-truth surface.

## testing
- [34e7c865] Every shell-script deliverable in this plugin ships a co-located static-only test-*.sh; CI runs all of them with no Docker daemon, no network, and no gh, so tests must stub external deps (PATH stubs for curl/docker/gh), parse YAML/JSON, and assert state machines rather than hit live dependencies.
- [ef916b74] A self-test asserting the "feature OFF" path of an env-gated script must scrub the gating flag with `env -u <FLAG>` (or a clean env); the dev/CI shell may set it globally, and an inherited =1 silently turns OFF-path fixtures into false passes.  <!-- last_verified=2026-06-29T13:00:14Z confidence=medium -->

## verification
- [be1ecb0a] A `heal_decision: PASS` with no `ground_truth_status` and no `contract_conformance_status: pass` is UNVERIFIED on two axes; do not credit it as reviewer-clean.  <!-- last_verified=2026-06-17T20:13:20Z confidence=medium -->

## jq-safety
- [f0d8d600] When `false` is a meaningful, distinct config intent from `absent` (opt-out flags), never read it with `jq '.field // empty'`; use `if has("field") then .field else empty end`.  <!-- last_verified=2026-06-17T20:13:20Z confidence=medium -->

## planning
- [16ffd26d] Run companion version-bumping briefs strictly sequentially and read the live `plugin.json` version at execution; a hard-coded target in a brief authored against a stale snapshot silently regresses the bump.  <!-- last_verified=2026-06-17T20:13:20Z confidence=medium -->

## release-mechanics
- [a642885b] A version bump touches ~8 doc surfaces in lockstep (both manifests, CHANGELOG paragraph, CLAUDE.md banner rotation keeping only the 2 most recent, README dated banner ADD, plugin.json annotations, agent-help, marketplace description in-place). Missing any one is the single most common self-heal-miss churn class on plugin-self PRs — enumerate and diff all 8 before Phase 4.5 PASS.  <!-- last_verified=2026-07-20T08:22:01Z confidence=high -->
