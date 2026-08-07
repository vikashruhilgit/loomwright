# Red Team Reviewer Memory — ai-agent-manager-plugin

- [Fail-closed vs fail-safe split](attack_failclosed_vs_failsafe_split.md) — correctness gates fail CLOSED under CI; runtime emitters fail SAFE (exit 0); inverting either is a regression
- [jq-only JSON injection](attack_jq_only_json_injection.md) — user/PR-text → JSON must be jq --arg built, gated by a quote/backslash/newline round-trip test
- [Sole-writer worktree ban](attack_sole_writer_worktree_ban.md) — .supervisor/{state.md,twin,memory,lessons} each have one repo-root writer that refuses a worktree CWD (red-team F1)
- [User-global config writes](attack_user_global_config_writes.md) — ~/.claude/settings.json writes must deep-merge + backup-first + abort-on-parse-failure
- [Self-heal PASS ≠ review-clean](attack_self_heal_pass_not_review_clean.md) — PASS is a weak signal; probe whether ground_truth/conformance actually ran
