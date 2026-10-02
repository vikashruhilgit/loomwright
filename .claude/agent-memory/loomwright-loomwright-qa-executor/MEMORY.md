# QA Executor Memory — loomwright

- [ci_wiring_and_userland_gap](ci_wiring_and_userland_gap.md) — For a new script's test check CI wiring (glob or ci.yml), macOS-only userland, and git-add before any git-ls-files ratchet
- [count-version-gate-blindspots](count_version_gate_blindspots.md) — Count/version drift is the top late-stage failure; gate regexes miss phrasing variants — sweep all surfaces + all phrasings
- [env_failure_attribution](env_failure_attribution.md) — Classify a failing self-test as ENVIRONMENT_ISSUE only after reproducing the pass on a clean base worktree (known case: orca-mirror leg L vs gitignored sdk-spike/node_modules)
- [fail-safe-exit-0](fail_safe_exit_0.md) — Read-only/probe/advisory scripts must always exit 0; the self-test must assert exit 0 on the missing-dependency path
- [golden-fixture-regen](golden_fixture_regen.md) — Golden fixtures need a WRITE_GOLDENS=1 regen path + a normalise rule for every release-varying value
- [infra-self-test-contract](infra_self_test_contract.md) — This repo's "QA surface" is shell self-tests + gate scripts, not Playwright; every script needs a co-located static-only test-*.sh
- [no_pipe_grep_q_in_tests](no_pipe_grep_q_in_tests.md) — In new self-tests assert with grep -q < <(producer), never producer | grep -q (pipefail 141 on match; the test-no-pipefail-grep-q lint fails the PR)
- [session-end-qa-signal](session_end_qa_signal.md) — The durable per-session QA record is the session_end JSON line in .supervisor/logs/{id}.jsonl
