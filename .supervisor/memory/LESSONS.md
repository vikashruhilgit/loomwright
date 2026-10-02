# Project Lessons (advisory — bounded <=3 active per category; written only via write-lessons.sh)

## self-heal
- [7c40ad9b] Read heal_decision together with heal_iterations and ground_truth_status — post-hardening the heal lens discriminates (1/2/3 iterations, one ESCALATED in the last 3 sessions with heal data), but PASS is still not drain-clean (1c7be561 PASSed, then needed 3 drain fix cycles), and a max-iteration ESCALATED's final fix commit is unreviewed code. contract_conformance_status: skipped remains UNVERIFIED, not clean.  <!-- last_verified=2026-10-02T07:10:12Z confidence=medium supersedes=d8f68195 -->

## review-process
- [0d7865dc] A green check-doc-currency.sh is necessary but NOT sufficient for a consistency PASS. On any count/version/budget/phase/section change, grep the OLD value repo-wide before passing — the gate never scans Supervisor phase enumerations, per-row skill version cells in SKILLS_INDEX.md, per-run YAML frontmatter field lists in build-insights.sh, budget/zone numbers, or /insights dashboard section enumerations.

## security
- [a7e4fb1c] Any user/PR-text -> JSON in a firing path (webhook, telemetry, gh/curl) MUST be built with jq --arg, never echo or shell-templated JSON, and MUST be gated by a single-quote/backslash/newline round-trip test. This is payload-CONSTRUCTION injection safety, distinct from jq parse-time type-traps (see jq-optional-chain-type-trap memory).

## ops
- [4a97f733] Failure philosophy is bimodal: correctness gates fail CLOSED under --non-interactive/CI/stdin-not-tty (preflight_overlap_detected, non_interactive_without_fallback, rubric_gate_closed_non_interactive), while runtime side-effect emitters (telemetry wrapper, send-webhook.sh, session-resume observability probe) fail SAFE and ALWAYS exit 0. Inverting either flips the security posture silently.
- [898f4858] contract_conformance_status: skipped means UNVERIFIED, not clean — it ran in only 3/7 recent twin sessions and found a violation in 2 of those 3. Never credit a session as conformant on a skipped check; conformance only runs when the brief authored an ## Executable Acceptance ground-truth surface.
- [55534238] A failing test is 'pre-existing env' only if the same leg passes on a clean base worktree. Recurring case: test-orca-mirror.sh leg L fails in the primary checkout because gitignored loomwright/sdk-spike/node_modules trips the core-cleanliness scan; record it as an environment issue, never a regression.  <!-- last_verified=2026-10-02T07:12:48Z confidence=medium -->

## testing
- [34e7c865] Every shell-script deliverable in this plugin ships a co-located static-only test-*.sh; CI runs all of them with no Docker daemon, no network, and no gh, so tests must stub external deps (PATH stubs for curl/docker/gh), parse YAML/JSON, and assert state machines rather than hit live dependencies.
- [ef916b74] A self-test asserting the "feature OFF" path of an env-gated script must scrub the gating flag with `env -u <FLAG>` (or a clean env); the dev/CI shell may set it globally, and an inherited =1 silently turns OFF-path fixtures into false passes.  <!-- last_verified=2026-09-27T18:23:21Z confidence=medium -->
- [fa32a308] A mutation control is evidence only if the mutant is VALID. Two mechanisms have produced silently-invalid mutants here: perl -0pi -e interpolates $VAR inside the pattern even under \Q...\E (the mutation no-ops), and a sed delimiter colliding with the target line (| vs ||) yields an EMPTY mutant. Both pass every fail-open assertion. Gate every mutant on non-empty + differs-from-original + bash -n before trusting the run.  <!-- last_verified=2026-09-01T05:59:31Z confidence=high supersedes=4abc6112 -->

## verification
- [be1ecb0a] A `heal_decision: PASS` with no `ground_truth_status` and no `contract_conformance_status: pass` is UNVERIFIED on two axes; do not credit it as reviewer-clean.  <!-- last_verified=2026-09-16T04:27:03Z confidence=medium -->
- [1b4bf009] The System Twin read path is provenance-gated and fails DARK: a contract whose content_hash has no chain-valid 'add' entry in .supervisor/twin/.provenance.jsonl is dropped to .supervisor/logs/twin.log while the store on disk still looks populated. Verify read-system-contract.sh reports twin_store_status: healthy with dropped 0 (2026-10-02: emitted 38, dropped 0) before crediting any twin signal; 'dark' means the signal is missing, not empty.  <!-- last_verified=2026-10-02T07:10:14Z confidence=medium supersedes=2d56232f -->
- [dba90cf3] A fail-SAFE reader's exit-0 empty output is not evidence of absence: name the reader behind every correctness gate and test its empty case (stripped clone, missing ledger, absent remote branch); and scope any fail-CLOSED enumeration to the roots it manages, or unrelated churn refuses legitimate runs.  <!-- last_verified=2026-10-02T07:10:15Z confidence=medium -->

## jq-safety
- [f0d8d600] When `false` is a meaningful, distinct config intent from `absent` (opt-out flags), never read it with `jq '.field // empty'`; use `if has("field") then .field else empty end`.  <!-- last_verified=2026-09-16T04:27:03Z confidence=medium -->

## planning
- [6e0baac1] Bump the version only with `bash scripts/bump-version.sh`, as the LAST commit of a PR: it reads the live `plugin.json` version when it runs, so a brief never hard-codes a target version (one authored against a stale snapshot silently regresses the bump). Companion PRs each carry only a `changelog.d/` fragment, so they no longer conflict; if `main` moves before the merge, drop the bump commit, rebase, and re-run the script.  <!-- last_verified=2026-10-01T15:01:13Z confidence=medium supersedes=16ffd26d -->

## release-mechanics
- [71cbd7e2] A version bump is `bash scripts/bump-version.sh`, never a hand edit: it bumps `plugin.json` and the loomwright entry of `marketplace.json` (one line each), folds every `changelog.d/` fragment into ONE new CHANGELOG entry, deletes the fragments and runs `validate-version.sh` + `check-doc-currency.sh`, restoring every file on failure. The old ~8-surface lockstep is retired; only count claims in the description cards are still edited in place when a count changes.  <!-- last_verified=2026-10-01T15:01:21Z confidence=medium supersedes=a642885b -->
