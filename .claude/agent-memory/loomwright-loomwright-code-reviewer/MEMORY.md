# Code Reviewer Memory — loomwright

- [agent-help phase-list drift](project_agent_help_phase_drift.md) — agent-help.md Supervisor phase enumerations are NOT covered by the doc-currency CI gate; check them in any phase-adding consistency audit
- [entry-points gate RESOLVED](project_entry_points_gate_blindspot.md) — doc-currency now scans "(N entry points)"/"N slash commands" incl. historical README banners (gate-forced updates)
- [Supervisor budget surfaces](project_supervisor_budget_surfaces.md) — budget/zone numbers in 9+ surfaces incl. 2 PRELOADED skills + IMPROVEMENTS_ROADMAP; grep old value everywhere
- [Half-fixed example classes](project_half_fixed_example_classes.md) — job-paths, NEEDS_HUMAN semantics, PO steps, agent-help phases, insights section enum, SKILLS_INDEX version column
- [Substring heuristic traps](project_substring_heuristic_traps.md) — "review" matches "preview" (deploy-preview bots), unanchored "round N" matches "background 4"; verify regex alternations empirically
- [jq optional-chain type trap](project_jq_optional_chain_type_trap.md) — non-string values abort jq at test()/gsub(); BUT capture() non-match emits empty (safe after tostring)
- [test-telemetry cwd trap](project_test_telemetry_cwd_sensitivity.md) — run test-*.sh from REPO ROOT; from scripts/ telemetry phantom-fails ~30 cases (would_exit=3)
- [insights per-run frontmatter gap](project_insights_per_run_frontmatter_gap.md) — build-insights.sh per-run YAML loop is a separate hand-list from the aggregate record; insights.md can overclaim per-run fields (CI only checks aggregates)
- [Self-heal rubber-stamp pattern](project_self_heal_rubber_stamp.md) — heal PASS + 0 iterations did NOT predict 0 post-PR rounds (5/8 records); v14.x hardening (consistency_audit lens + miss-class checklist + ground_truth) shipped to break it
- [Two six-class taxonomies](project_two_six_class_taxonomies.md) — pr-postmortem buckets (plan_gap…) vs Self-Heal Miss-Class Checklist; CHANGELOG/banner prose conflates them
- [Roadmap next-order drift](project_roadmap_next_order_drift.md) — LEARNING_LOOP_ROADMAP "Recommended next order" list restates phase status; goes stale when a phase is flipped to shipped in the table/section but not the list (not CI-scanned)
- [PR-create hook false-positive](project_pr_create_hook_false_positive.md) — hook-dispatch-on-pr-create.sh triggers on ANY Bash stdout with a /pull/N URL (not just gh pr create); AC3 session gate is sole defense; tool_input.command check = LOW hardening, not FAIL
- [Self-heal three fixer sites](project_self_heal_three_fixer_sites.md) — fixer-prompt edits must sync 3 sites (supervisor 4.5 + review-heal default + drain); drain is the weak spot for gate-as-back-reference instead of co-located comment
- [Invisible control-char delimiter](project_invisible_control_char_delimiter.md) — jq join("\x1F") renders as join("") in diff/sed/cat; od -c the bytes before flagging an idempotency-key collision (automate-helpers.sh learning-emit)
- [hook-count jq two-level descent](project_hook_count_jq_two_levels.md) — counting hooks.json LEAF entries (claimed 20) needs `.hooks[][] | .hooks[]`, not `.hooks[][]` (=15 matcher-objects); the one-level form silently undercounts
- [OTel labeler session-lag](project_otel_labeler_session_lag.md) — set-otel SessionStart hook writes settings.local.json but it's READ before the hook fires; one-session-lag is by design (init-tail + $CLAUDE_ENV_FILE mitigate), NOT a bug
- [Hook-gate summary drift](project_hook_gate_summary_drift.md) — when hook-dispatch-on-pr-create.sh's session-scope gate logic changes, TWO prose summaries under-describe it and are NOT doc-currency-scanned
- [Unscanned drift surfaces on version bump](unscanned-drift-surfaces-on-version-bump.md) — README banner stack + skill frontmatter/SKILLS_INDEX rows drift despite green doc-currency gate
