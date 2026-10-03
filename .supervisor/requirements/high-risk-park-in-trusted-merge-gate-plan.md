# Task Plan — high-risk-park-in-trusted-merge-gate

Source brief: `.supervisor/jobs/in-progress/2026-09-13-high-risk-park-in-trusted-merge-gate.md` (AC1–AC11, D1/D2, R1/R5 — authoritative; this plan orders the work and records deviations, it does not restate the criteria).
Persistence: file fallback (no `.beads`). Base: `main` @ 25b5cfa (v15.71.0 live). Planned 2026-09-13.

## EPIC: high-risk-park-in-trusted-merge-gate
Ship `classify-risk.sh` as the one high-risk heuristic, make it fail-CLOSED condition 6 of `gate-eval` with NO override, point the Phase 4.5 lens at it, surface `risk_classification` on SUPERVISOR_RESULT, sweep "5 conditions" → 6, release v15.72.0.

### Decomposition decision
ONE task (deviation from the letter of `context-bound`, recorded). Named reason NOT to split: a script+suite / gate+docs split is a strict `requires` chain (docs' risk-table block is generated FROM `--kind-table`; group E's ctx shape follows the script's output keys) — no genuine parallelism, plus an avoidable worktree merge on `RESULT_SCHEMAS.md`. Same call as item 02. Work is ordered below so the chain is respected inside one worker.

## TASK 1 — classify-risk.sh + condition 6 + wiring + sweep + release  (single-agent, no worktree)
Skills: `skills/unit-testing/SKILL.md` (mutation controls), `skills/quality-checklist/SKILL.md`, `AGENT_GUIDELINES.md` (read-before-write).
Gate: deterministic `outputs_verified` (the brief's `provides` list) + `bash loomwright/scripts/test-classify-risk.sh` + `bash loomwright/scripts/test-automate-helpers.sh` + AC10 gate set. No per-subtask reviewer; Phase 4.5 integrated review runs once after FINALIZE.

### Phase A — the script (AC3, AC4, AC5)  [blocked by: nothing]
- [ ] `[TO BE CREATED]` `loomwright/scripts/classify-risk.sh` — data lists at top (path/content globs, path-prefix dirs, content words) shared by classifier and `--kind-table`; `git -C "$root"` only; every early exit emits JSON; jq-less path is the ONE shell-templated object.
- [ ] `.agent/risk.json` reader: strict shape (`object` root, `paths`/`content` arrays of strings); malformed ⇒ generic-only + `risk_json_malformed`; `exclude` ⇒ `risk_json_exclude_ignored`, never honoured; `case`/`grep -iF` only, never `eval`.
- [ ] `[TO BE CREATED]` `loomwright/scripts/test-classify-risk.sh` — fixture repo in `mktemp -d`, cwd elsewhere; every AC8 branch; mutation control: delete content-match branch from a COPY ⇒ content-only case red (gate mutant on non-empty + differs + `bash -n`).

### Phase B — the gate (AC1, AC2, AC8 group E)  [blocked by: Phase A key names `high_risk` / `reasons`]
- [ ] `loomwright/scripts/automate-helpers.sh` `gate_eval`: cond 6 after cond 5, before `MERGE`, EXACTLY the `unresolved_human_thread` shape (`has()` + `!= null` + `tostring`, `!= "false"` ⇒ `PARK: high_risk_diff (<first 3 risk_reasons; "; ">)`). No read of any config/flag for cond 6. Header ctx example, `# ALL 5 hold` comment, the `gate-eval` line in the subcommand table (`automate-helpers.sh:36`) → 6.
- [ ] `loomwright/scripts/test-automate-helpers.sh`: header comment (line 24) → 6; existing all-pass ctx gains `"high_risk": false` so MERGE cases keep firing exactly once; new PARK cases: `true`, `null`, missing, `"yes"` string, `trust_unprotected:true`+`high_risk:true`; mutation control: delete cond 6 from a COPY of `gate_eval` ⇒ PARK cases red.

### Phase C — loop + lens + result block (AC6, AC7)  [blocked by: Phase A/B]
- [ ] `loomwright/skills/automate-loop/SKILL.md`: §1.5 row (line 65), §6 step 4 (line 198), §9 bullet (line 283), §10 title/intro/"ALL 5"/"On all 5 holding" (294–329) + cond 6 text (re-run `classify-risk.sh main <ready_sha> --root <checkout>` at GATE; Supervisor's value recorded in `## Progress` for comparison only; `null` ⇒ PARK), §11 (six conditions, still five surfaces), §12 D2 sentence, Anti-Patterns (390), Quality Gates (418), cond 4 D2 sentence.
- [ ] `loomwright/skills/self-heal-advisory/SKILL.md` lens (lines 863–931): classification moved ABOVE the `RED_TEAM_ENABLED` guard; `high_risk = (...)` expression replaced by the script call + `--kind-table` pointer; spawn gated on `RED_TEAM_ENABLED AND high_risk != false`; `record_decision` on every path. **Coupling budget: file is at 17/18 — the one new `${CLAUDE_PLUGIN_ROOT}` ref lands exactly at the allowance; do not add a second, do not raise the allowance.**
- [ ] `loomwright/agents/supervisor.md` §"Result Block": optional additive `risk_classification: {high_risk, reasons}`; budget headroom 1596 — measure with `check-token-budget.sh`, raise only on breach.
- [ ] `loomwright/docs/RESULT_SCHEMAS.md` §SUPERVISOR_RESULT: nested object + `<!-- risk-table:begin/end -->` block generated from `--kind-table` (never hand-typed; suite byte-compares) + schema-history bullet.

### Phase D — consistency surfaces (AC9, D2)  [blocked by: Phase C]
Brief-listed sweep (all verified 2026-09-13 as live hits): `README.md:248,253` · `.claude-plugin/README.md:206` · `REQUIREMENTS-SITE-V2.md:87` · `commands/automate.md:60,78` · `commands/agent-help.md:805,812` (+ ADD `--trust-unprotected` line with the cond-4-only sentence) · `CLAUDE.md:131` ("ALL FIVE" → "ALL SIX"; leave "exactly five surfaces") · `docs/ARCHITECTURE_CONTRACTS.md:319` (optional: extend "§10 condition 1" pointer to name condition 6; add NO gate-count row).
Surfaces the brief does NOT list (found by this plan):
- [ ] **`docs/RESULT_SCHEMAS.md` §AUTOMATE_RUN Run-Config row (line ~1797)** defines `trust_unprotected` as "allows auto-merge onto a branch without enforceable protection" — a D2 surface: append "(condition 4 only — nothing overrides condition 6)". The section does NOT enumerate the conditions, so no count sweep there.
- [ ] `docs/PITFALLS.md`, `docs/HOOKS.md`: verified NO gate-count or auto-merge condition prose — nothing to edit (do not add).
- [ ] Re-run after editing and paste: `grep -rniE "(five|5)[ -]+(trusted[- ]merge[- ]|per-PR[- ]|gate[- ])?(conditions|booleans)|ALL[ -]+(5|five)\b|(5|five)[ -]condition" . --include='*.md' --include='*.sh' --include='*.json' | grep -vE "^\./(\.supervisor|\.claude|CHANGELOG)"` — remaining hits must be only the unrelated "five validators / five lenses / 5 subtasks" phrases.

### Phase E — DEVIATION to resolve before Phase C's RESULT_SCHEMAS edit (AC6 flat fields)
AC6 asks for FLAT `risk_high` + `risk_reasons_count` on the `session_end` JSONL line "following the hard-signal table". Verified: `scripts/build-insights.sh` projects a FIXED field list (lines 56–66: contract_conformance_*, benchmark_*, …) and the table's opening sentence claims "This is what `build-insights.sh` aggregates". Adding two flat fields nothing projects makes that sentence a claim no consumer backs (memory: `verify-consumer-contract-before-for-free`, `rules-violated-by-their-own-surrounding-text`). Precedent: `red_team_advisory` is nested/summary-only, never flat.
**Plan decision (smallest correct): keep AC6's NESTED object; DROP the flat `risk_high`/`risk_reasons_count` fields and the session_end table rows.** Record the deviation in the PR body and CHANGELOG ("flat session_end projection deferred until build-insights consumes it"). If the Supervisor prefers to honour AC6 literally, the alternative is a 3-line scope add: project both keys in `build-insights.sh` (jq select lines 56–66 + one frontmatter line ~96) and one `test-insights.sh` case (present ⇒ rendered; absent ⇒ not invented) — pick ONE; never document a flat field with no reader.

### Phase F — release + gates (AC10, AC11)  [blocked by: A–E]
- [ ] `loomwright/.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` → 15.72.0 (read live at execution; 15.71.0 today); `vX.Y.Z` in both descriptions in place; ONE CHANGELOG top entry (bold-paragraph shape) naming cond 6 + NO override (R5), D1, add-only `.agent/risk.json`, honest limits, "Counts unchanged" (read live: 14 agents / 23 commands / 41 skills / hooks per `check-doc-currency.sh`'s convention — copy the previous entry's phrasing).
- [ ] `grep -rn "15\.71\.0" --include=*.json --include=*.md . | grep -v CHANGELOG | grep -v "^./.supervisor\|^./.claude/worktrees"` ⇒ empty.
- [ ] `bash scripts/check-token-budget.sh && bash scripts/check-doc-currency.sh && bash scripts/check-contract-parity.sh && bash scripts/check-vendor-coupling.sh` green.
- [ ] `for t in scripts/test-*.sh loomwright/scripts/test-*.sh; do bash "$t" || echo "RED: $t"; done` — every suite, no early exit (memory: CI's `set -e` loop hides later reds).
- [ ] AC9 invariant grep output pasted in PR body (must still be the same five surfaces). Do NOT stage `.supervisor/postmortem/results.jsonl`.

## Risks (delta over the brief's table)
| Risk | Mitigation |
|---|---|
| Flat session_end fields documented with no consumer (AC6) | Phase E decision — nested only, or wire build-insights + test in the same PR |
| `trust_unprotected` scope drift on the unlisted AUTOMATE_RUN row | Phase D bullet; grep `trust_unprotected` repo-wide after editing |
| self-heal-advisory coupling at exactly 18/18 after the edit | one ref only; verify `check-vendor-coupling.sh` before push |
| Hook count restated in CHANGELOG from the wrong counting convention | copy the previous entry's "Counts unchanged" phrasing; `check-doc-currency.sh` is the arbiter |
