# 01 — Command clarity: decision table + flag-table completeness audit (P0, docs-only)

> REBASELINED 2026-07-06 against v15.2.0. Original 2026-07-05 scope assumed no flag
> tables existed — v15.2.0-era command docs now HAVE Parameters tables (supervisor.md
> ~line 46+, autonomous.md 8 rows incl. `--cheap` forwarding). The auto-merge 5-condition
> inline requirement is DROPPED: automate.md deliberately does NOT restate the deep
> contract (automate.md ~line 60 "deliberately not restated — reference the skill") and
> its `--auto-merge` row already summarizes the gate shape; inlining would fight a
> standing anti-drift design decision. Surviving core: the decision table (still absent
> — verified by grep 2026-07-06) + completeness/precondition audit of the existing tables.

## Goal
A user who is not the maintainer can answer "which command do I run?" in one screen, and
every flag in the command docs appears in its Parameters table with default + precondition.

## Evidence (re-verified 2026-07-06)
- NO "Which command?" decision table exists in README.md, .claude-plugin/README.md, or
  commands/agent-help.md (grep confirms).
- Parameters tables EXIST in commands/supervisor.md and commands/autonomous.md, but their
  COMPLETENESS was never audited: flags may appear in Phase-0/body prose without a table
  row, and rows may lack the "only meaningful when" precondition (e.g.
  --check-wait-timeout requires the until-mergeable drain).
- Terminology diverges: "iteration" (/autonomous) vs "item" (/automate) for cognate
  concepts — no note connects them.

## Scope — files to touch
1. **`README.md` + `.claude-plugin/README.md`**: add a "Which command?" decision table
   near the top of the Commands section. Rows: "I have a task/goal for new work" →
   /launch-pad then /supervisor (or /autonomous for the chained loop); "I want
   multi-iteration on one goal with stacked PRs" → /autonomous; "I have a queue of
   independent goals (folder/backlog)" → /automate; "I have an existing PR to
   review-and-heal" → /review-pr; "I just want a review of my diff, no fixes" →
   /code-reviewer. One line each on what it does NOT do (none merge except
   /automate --auto-merge, opt-in).
2. **`loomwright/commands/supervisor.md`**: COMPLETENESS AUDIT of the existing Parameters
   table — enumerate every `--flag` mentioned anywhere in the file body (grep the file,
   not memory), assert each has a table row; add missing rows; add/verify a
   precondition ("only meaningful when") note per row where one applies. Do NOT change
   any flag semantics.
3. **`loomwright/commands/autonomous.md`**: same completeness audit. Verify the forwarded
   set is documented accurately post-v15.2.0 (read the autonomous-loop skill's
   "Auto-forwarded flags" subsection — created in v15.2.0 — and assert command-doc
   parity). Add the terminology note: "iteration (this command) ≈ one
   /launch-pad→/supervisor pass on the SAME goal; /automate's 'item' = one independent
   goal from a queue."
4. **`loomwright/commands/automate.md`**: completeness audit only. Do NOT inline the
   5 trusted-merge conditions (standing anti-drift decision); verify the `--auto-merge`
   row still summarizes: opt-in, default OFF, fail-CLOSED, authority = skill §10.
   Any new wording must keep the merge-executor invariant grep
   (`grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "`)
   resolving to exactly the four sanctioned surfaces.
5. **`loomwright/commands/agent-help.md`**: add the same decision table (condensed).

## Constraints / invariants
- Docs-only: no behavior change, no script change, no schema change.
- Command↔agent mirror discipline: if any enumeration in commands/*.md is touched, verify
  the corresponding agent .md prose still matches (check-command-sync.sh does NOT cover
  Parameters-table prose — do the sweep manually, per memory "agent-command-mirror-drift").
- Counts unchanged (14/21/57/21). Patch version bump from the CURRENT version at
  execution time (15.2.0 → 15.2.1 if unchanged) + CHANGELOG entry.
- Keep plugin.json/marketplace.json description: update version string in place only.

## Acceptance criteria
- [ ] A decision table appears in README.md, .claude-plugin/README.md, and agent-help.md,
      consistent across all three.
- [ ] For each of supervisor.md / autonomous.md / automate.md: zero flags exist in body
      prose that are absent from the Parameters table (attach the per-file grep proof to
      the PR).
- [ ] autonomous.md's forwarded-flag documentation matches the autonomous-loop skill's
      "Auto-forwarded flags" subsection exactly.
- [ ] The merge-executor grep still returns exactly 4 surfaces; the 5 conditions remain
      un-restated in automate.md.
- [ ] check-doc-currency.sh, check-command-sync.sh, validate-version.sh all pass.

## Test plan
CI validators only (docs-only change). Manually run the merge-executor grep and the
per-file flag-completeness greps; paste outputs into the PR description.

## Out of scope
Removing/renaming flags, demoting flags to config keys (candidate follow-up), inlining
the trusted-merge deep contract, any behavior change to the drain or gates.

## Status: done
- Completed 2026-07-06 via /automate → PR #91 (v15.2.1), Phase 4.5 PASS, heal_iterations 0.
