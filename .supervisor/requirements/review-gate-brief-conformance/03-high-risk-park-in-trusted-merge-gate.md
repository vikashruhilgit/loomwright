# 03 — High-risk diffs park in the trusted auto-merge gate (6th condition, no override)

## Problem
`automate-helpers.sh gate-eval` (§10 of `skills/automate-loop/SKILL.md`) is the plugin's ONLY executor of
`gh pr merge --squash`. It is a pure function over 5 per-PR booleans — drain READY (+ not
`sub_floor_converged`), head SHA unmoved + base main, no blocking `reviewDecision` / unresolved human thread,
enforceable branch protection (or `--trust-unprotected`), required checks green + rubric satisfied. **It is
path-blind:** a diff touching auth, secrets, payments or a migration merges under exactly the same conditions
as a lint fix. A high-risk classifier already exists — the `high_risk` heuristic in
`skills/self-heal-advisory/SKILL.md` §"Advisory red-team lens" (`*auth*`, `*authz*`, `*security*`, `*crypto*`,
`*secret*`, `*token*`, `*payment*`, `migrations/`, `*migration*`; `.github/workflows/`, `hooks/`, `agents/`,
`commands/`, `skills/`; `workflow|automation|orchestration` in path/content; `changed_lines > 400`;
`changed_files > 15`) — but it is prompt-only, lives in one skill, and is used solely to decide whether to spawn
the advisory red-team pass. It never reaches the merge decision. Raised by an external reviewer on 2026-09-13
("a high pass rate on the easy stuff quietly buys trust for exactly the changes where a mistake is expensive").
Premise correction recorded for honesty: the gate has NO accumulating trust score, so the "streak buys trust"
mechanism cannot occur here — the conclusion (high-risk categories stay behind a human) still holds.

## Goal
A high-risk integrated diff can never be auto-merged. `high_risk` becomes a sixth fail-CLOSED condition of the
trusted gate, computed by one shared script, extensible per project, and **without an override flag** — this
category stays behind manual review indefinitely, independent of how the other five conditions read.

## Scope
1. **`loomwright/scripts/classify-risk.sh <base_ref> <head_ref> [--root <dir>]`** — deterministic, read-only,
   fail-SAFE emitter (always exit 0). Computes `git diff --name-only` + `git diff` between the refs and applies
   the heuristic above **verbatim** (path OR content, case-insensitive, same three branches a/b/c). Prints one
   JSON object on stdout: `{"high_risk": true|false, "reasons": ["path:src/auth/jwt.ts matched *auth*",
   "size:changed_lines=612>400", ...], "changed_files": N, "changed_lines": N, "source": "classify-risk.sh"}`.
   On an unreadable ref / not a git repo / `git` failure it prints `{"high_risk": null, "reasons":
   ["unclassifiable: <reason>"]}` and the reason on stderr — **`null` is the fail-closed value** for every
   consumer (a gate that cannot classify does not merge).
   - **Per-project extension — committed `.agent/risk.json`** (the `.agent/product.json` / `.agent/rules/`
     pattern: fail-safe reader, propose-only writer): `{"schema_version": 1, "paths": ["billing/**",
     "infra/terraform/**"], "content": ["stripe"]}`. Globs are matched against changed paths; `content` terms
     against diff content. Absent / malformed file ⇒ silently the generic heuristic only (reason on stderr).
     Malformed = root not an object, `paths` present but not an array of strings. A project can ADD risk
     surfaces; **it cannot remove the generic ones** — no `exclude` key, by design.
   - `--kind-table` (mirrors item 02's convention): prints the heuristic as a markdown table so the skill
     prose can point at the script instead of restating the regex list.
2. **Phase 4.5 red-team lens** (`skills/self-heal-advisory/SKILL.md` §"Advisory red-team lens"): replace the
   inline pseudo-code heuristic with a call to `classify-risk.sh "$BASE_BRANCH" HEAD` and read `high_risk`;
   `null` ⇒ treat as high-risk (spawn the advisory pass — the safe direction for an advisory lens is to
   run it). Record `red_team_advisory` reasons from the script's `reasons[]`. Semantics otherwise UNCHANGED
   (still opt-in, still advisory, still one pass outside the heal loop). Record `high_risk` +
   `risk_reasons` on `SUPERVISOR_RESULT` as a NEW optional nested object `risk_classification`
   (`{high_risk, reasons[]}`) — `docs/RESULT_SCHEMAS.md` §SUPERVISOR_RESULT, additive, optional, so old
   consumers ignore it. This is the value the `/automate` loop reads in step 3.
3. **`/automate` loop — condition 6** (`skills/automate-loop/SKILL.md` §10, new numbered condition after 5):
   the loop obtains `high_risk` by **re-running `classify-risk.sh main <ready_sha>` at GATE time** on the
   fetched PR head (NOT by trusting `SUPERVISOR_RESULT.risk_classification` — the drain may have pushed fix
   commits after Phase 4.5, and cond 2 already establishes the SHA being judged; the Supervisor's value is
   recorded in `## Progress` for comparison only). Passes `"high_risk": true|false|null` and
   `"risk_reasons": [...]` into `ctx.json`.
   - **`gate-eval`** (`loomwright/scripts/automate-helpers.sh`): add cond 6 in the file's mandated affirmative
     form — `high_risk == "false"` ⇒ pass; anything else (`true`, `null`, missing, unreadable) ⇒
     `PARK: high_risk_diff (<first 3 reasons>)`. Follow the header comment's FAIL-CLOSED CONVENTION exactly
     (never a `= "false"` test on a coerced value — read with `has()` + explicit string compare).
   - **NO override.** No `--trust-high-risk`, no `.supervisor/config.json` key, no `.agent/risk.json`
     `exclude`. `--trust-unprotected` continues to override cond 4 ONLY (state this in the §10 text and in
     `commands/automate.md`'s Parameters table — memory `agent-command-mirror-drift-on-fixes`).
   - PARK reason surfaces through the existing park + notify path (`pause_reason: awaiting_merge`, the
     `--notify` webhook line) with the matched reasons, so the human sees WHY it waits.
4. **Tests — extend `loomwright/scripts/test-automate-helpers.sh` group E** (the per-condition fail-closed
   group): cond 6 parks on `true`, on `null`, on missing key, on a non-boolean string; MERGE only when every
   other condition holds AND `high_risk` is the string/JSON `false`; `--trust-unprotected` present + `high_risk:
   true` still PARKS (the override does not leak). **New `loomwright/scripts/test-classify-risk.sh`:** fixture
   repo in a temp dir — each generic branch (a) path match, (a) content-only match (a `secret` string added in
   an innocuously named file), (b) workflow path, (c) size by lines, (c) size by files, a clean small diff ⇒
   `false`; `.agent/risk.json` adds `billing/**` and a `billing/x.ts` diff flips to `true`; malformed
   `risk.json` ⇒ generic-only + stderr reason; bad ref ⇒ `high_risk: null`. Mutation control: delete cond 6
   from `gate_eval` ⇒ the new group-E cases must fail; delete the content-match branch from the script ⇒ the
   content-only case must fail. Register both in the CI `test-*.sh` loop.
5. **Invariant surfaces:** the CLAUDE.md §"Failure-Mode Invariants" `gh pr merge --squash` grep still resolves
   to the same five surfaces (no new executor; cond 6 lives inside the existing one) — run the grep and paste
   the result in the PR. `docs/ARCHITECTURE_CONTRACTS.md` gate row: "5 conditions" → "6 conditions";
   `check-doc-currency.sh` — grep the repo for the OLD phrasing (`5-condition`, `ALL 5`, `five conditions`,
   `ALL FIVE`) and update every hit in the same change (memory `sweep-grep-gate-variants`); `commands/automate.md`
   + `commands/agent-help.md` prose; CHANGELOG bullet.

## Non-goals
- No change to the advisory status of the red-team lens, rubric, ground truth or contract conformance (R1).
- No accumulating trust score / hit-rate / history — deliberately: the gate stays a pure per-PR function; the
  commenter's failure mode is impossible by construction and this item keeps it that way.
- No loosening: `.agent/risk.json` only adds surfaces. Removing a generic surface is a plugin change, not a
  project config.
- Not applied to `/review-pr` `READY` or Supervisor Phase 4.5 `PASS` — those never merge (CLAUDE.md invariant),
  so there is nothing to park.

## Acceptance criteria
- `gate-eval` with all five prior conditions satisfied and `"high_risk": true` prints
  `PARK: high_risk_diff ...` and does NOT invoke `gh pr merge` (stub asserts zero calls); with `"high_risk": false`
  it prints `MERGE`; with the key absent or `null` it PARKS.
- `--trust-unprotected` + `high_risk: true` ⇒ PARK (override scoped to cond 4 only).
- `classify-risk.sh` on a diff adding `const token = ...` to `src/utils/format.ts` (innocuous path, matching
  content) returns `high_risk: true` with a `content:` reason; on a 3-line change to `README.md` returns `false`.
- `.agent/risk.json` `{"schema_version":1,"paths":["billing/**"]}` + a `billing/x.ts` diff ⇒ `true`; the same
  file with `"paths": "billing/**"` (string, not array) ⇒ generic-only result + `risk_json_malformed` on stderr.
- Phase 4.5 red-team gating reads the script; `SUPERVISOR_RESULT` carries `risk_classification` on a run.
- `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` output is unchanged from
  CLAUDE.md's enumerated five surfaces.
- Full `test-*.sh` loop, `check-doc-currency.sh`, `check-token-budget.sh` green; repo-wide grep for the old
  "5 condition" phrasings returns only CHANGELOG history.

## Evidence to record on close-out
The group-E mutation run (cond 6 deleted ⇒ red), and the grep output for the merge-executor invariant.

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-09-13T13:50:29Z
- **Brief:** .supervisor/jobs/done/2026-09-13-high-risk-park-in-trusted-merge-gate.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/219
