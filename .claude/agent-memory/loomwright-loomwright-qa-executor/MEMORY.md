# QA Executor Memory — loomwright

- [Infra self-test contract](infra_self_test_contract.md) — QA surface = shell self-tests + gates, not Playwright; static-only tests required
- [Golden fixture regen](golden_fixture_regen.md) — WRITE_GOLDENS=1 + normalise rule per release-varying value
- [Count/version gate blind spots](count_version_gate_blindspots.md) — sweep all surfaces + all phrasing variants
- [Fail-safe exit 0](fail_safe_exit_0.md) — advisory/probe scripts always exit 0; assert it on missing-dep path
- [session_end QA signal](session_end_qa_signal.md) — durable per-session quality record + advisory-tier semantics
