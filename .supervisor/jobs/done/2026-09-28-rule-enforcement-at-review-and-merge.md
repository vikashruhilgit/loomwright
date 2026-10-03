# Supervisor Job: Rules that gate — a failing human-stamped `must` check blocks Phase 4.5 and the drain, and parks the merge gate (automate-followups 07)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager/.claude/worktrees/loomwright-automate-resume-ca9197
- **CLAUDE.md:** ✓ Found (fresh — §"Failure-Mode Invariants" is the paragraph D4 amends)
- **Git:** dirty (1 file: the tracked `/automate` run file, expected), branch: claude/loomwright-automate-resume-ca9197 (== origin/main)
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 2 (worktree checkout — feature branch is created off `origin/main` here, not in the main checkout; the installed runtime plugin is 15.108.4 while `main` is 15.110.0 — agents spawned this run carry the older prompts, the CODE under test is `main`)
- **Source requirement:** .supervisor/requirements/automate-followups/07-rule-enforcement-at-review-and-merge.md
- **Base commit:** 5f00e72ec51482cff9fdfc03f5e030b340d4e098

## Feasibility
**Verdict: CAUTION.**
1. Tech stack — bash 3.2 + jq + markdown prose, same as every sibling script (`rules-check.sh`, `worker-rule-selfcheck.sh`, `automate-helpers.sh`). ✓
2. Dependencies — every seam this item gates already exists on `main`: `rules-check.sh --if-stamped`/`--list-selected` (twin-loop/08, PR #267), the self-resolving `gate-eval` (red-team-hardening/03, PR #250), the fail-closed replay parser in `worker-rule-selfcheck.sh` (automate-followups/06, PR #294), the `rule:` Executable-Acceptance kind (automate-followups/05, PR #292). ✓
3. Architecture fit — this is the first time a `.agent/rules/` signal gates anything; CLAUDE.md §"Failure-Mode Invariants" and `skills/rules/SKILL.md` §8/§9 say "never gates" in several places. The owner's D1–D4 (2026-09-28) authorize the change and require the CLAUDE.md amendment in the same PR. CAUTION → Risk row R1.
4. Scope — three sequential subtasks (`context-bound`), one PR. ✓
5. Hard blockers — none. **CAUTION (owner-stated):** on this repo the store holds 3 rules, 0 `must`, 0 with a `check` (`rules-check.sh --list-selected` prints nothing), so every gate built here is DORMANT on `main` and every acceptance criterion is proven against FIXTURE stores in temp git repos with a sandboxed `$HOME` stamp — never the live store, never the real stamp. → Risk row R2.

## Task
**Goal:** Make a failing, human-stamped, gate-countable `must`-rule check a correctness gate at three seams — a BLOCKING Phase 4.5 finding that enters the review-and-fix loop, a `--until-mergeable` READY blocker, and a self-resolved `gate-eval` condition 7 — while `unstamped`, `cmd_disabled`, advisory rules and non-countable checks stay exactly as advisory as today, and CLAUDE.md records the new invariant in the same change.

**Problem Statement:**
The plugin owner needs "the rule was followed" and "the rule failed and we printed it" to be distinguishable in a terminal state because today a mechanized, human-confirmed `must` check can be executed at Phase 4.5, observed to FAIL, and the PR still reaches `heal_decision: PASS`, the drain still reaches `READY`, and `--auto-merge` still merges (`skills/self-heal-advisory/SKILL.md` §"Rules-check replay": "a failing stamped check still replays and still never gates"; `gate-eval` has six conditions and none reads the rules store).
Currently the replay is report prose only. This causes the house-rules substrate to have no teeth at exactly the one point where its signal is deterministic, reproducible and human-authorized (a stamped check), which the owner chose to change (D1–D4).
Success looks like: a fixture store with a stamped, countable, FAILING `must` check makes Phase 4.5 spawn a fix task naming the rule id and its check, makes the drain's READY test fail, and makes `gate-eval` print `PARK: rules_check_failed (<id>)`; an all-passing stamped store, an `unstamped` store, `--no-cmd`, an advisory-only rule and a check that invokes an undeclared repo script all leave today's behavior byte-identical (or, at the merge gate, park by D3's middle form); and a PR that edits a file a counted check invokes is caught by the stamp, not trusted.

## Design (decided at Launch Pad — implement as written; Plan Review adjudicates the two marked choices)

### D-a — Caveat (d): BIND, with the "executes no repo file" test used only to REFUSE countability *(choice 1 for Plan Review)*
The stamp today hashes `id\tcheck` (`rules-check.sh` LIVE_HASH; `skills/rules/SKILL.md` §8.1 honest limit 3 says so explicitly). Shell cannot be statically parsed for "executes", so the plan does NOT try to prove (i) positively. Instead:
- **New OPTIONAL rule field `binds`** (`null`/absent, or an array of repo-relative path strings — same path space as `applies_to`, same write-time rejections for `..`/absolute/`~` paths). Semantics: "the repo-tracked files this check EXECUTES; their CONTENT is part of what the confirming human approved".
- **Hash binding (rules-check.sh):** when a selected rule carries a non-empty `binds` array, its hash-input line becomes `id\tcheck\t<path>=<sha256 of file content | MISSING>` for each bound path in `LC_ALL=C` sorted order (paths resolved from the repo root; a path outside the repo root or non-tracked is hashed as `INVALID`). A rule WITHOUT `binds` (or `binds: null`/`[]`) hashes exactly as today — **every existing stamp stays valid** (AC: byte-identical `Checks passed:` output on a binds-free store before/after). Because the stamp WRITE and the `--if-stamped` COMPARE already read the same in-memory `$selected`, both pick the new input up from one place — extend the `[.id, .check] | @tsv` line, nothing else.
- **Countability (the gate's universe), decided by `rules-check.sh --list-gateable` (NEW read-only flag, same precedence tier as `--list-selected`: executes nothing, never prompts, exits 0):** prints one `id\tcountable|advisory\t<reason>` line per SELECTED id, sorted. For each selected check it derives the **detected invoked files** = every whitespace-split token of the check (leading/trailing quotes stripped, `./` prefix stripped) that (1) resolves, relative to the repo root, to a git-TRACKED file (`git ls-files --error-unmatch -- <tok>`), AND (2) is executable (`test -x`) OR begins with `#!` OR is immediately preceded by an interpreter word from the fixed set `bash sh zsh source . python python3 node perl ruby`. Then: `countable` ⇔ every detected file ∈ `binds`; else `advisory` with reason `unbound:<path>[,<path>]` (files detected but not declared) — or `binds_invalid` when `binds` is present but not an array of strings, or names a path that is absolute/`..`-bearing/untracked. **The (i) leg is an EXPLICIT human declaration, never an inference:** a rule with NO `binds` key (or `binds: null`) is `advisory\tbinds_undeclared` — nothing is counted that a human did not explicitly assert; an explicit `binds: []` asserts "this check executes no repo file" and is `countable\tno_invocations` iff ZERO invoked files are detected (else `advisory\tunbound:<paths>` — the declaration was dishonest and the heuristic demotes it); a non-empty `binds` whose detected set is a subset is `countable\tbound:<n>`. The heuristic therefore only ever DEMOTES a rule to advisory; it never promotes one. Hashing is unchanged for absent/`null`/`[]` (all hash exactly as today). Documented honest limits (in §8.1 and the `--list-gateable` header): transitive invocations (a bound script calling another script), `$(…)`/`eval`/globs, interpreter aliases, AND task-runner indirection — `make lint`, `npm run lint`, `pytest`, `cargo test`, `go test ./...` execute tracked files (Makefile, package.json scripts, conftest/test modules) that a whitespace-token scan cannot see — are not followed; a human who declares `binds: []` on such a check has asserted something false, and the remedy is to declare the executed files in `binds` (the CHANGELOG follow-up for `audit-rules.sh unbound_invocation`, item 09's seam, should flag task-runner words).
- **Why bind rather than a positive (i):** the trust anchor stays the confirming human on their own machine (§8.1), no second stamp mechanism is introduced, and the property the AC demands falls out of the existing stamp: a PR that edits a bound file changes the live hash → `--if-stamped` prints `[SKIP] all (unstamped)` → the merge gate PARKs by D3 (`rules_unstamped`) and Phase 4.5/the drain report `unstamped` (advisory, as today). The PR cannot turn a failing bound check into a pass without a human re-running `/rules check --confirm`.

### D-b — ONE fail-CLOSED verdict helper, delegating to `rules-check.sh` *(choice 2 for Plan Review: extract a shared parse lib vs a documented mirror)*
New `loomwright/scripts/rules-gate-verdict.sh [--root <tree>]` — the inverse posture of `worker-rule-selfcheck.sh` (that one is fail-SAFE/silent; this one is fail-CLOSED/loud). It never reads the store, never extracts or runs a `check`, resolves `rules-check.sh` as a SIBLING (never PATH), runs every delegated call with `</dev/null`, and unsets `RULES_CHECK_CONFIRM` first. Calls, in order: (1) `--list-selected` (ids); empty ⇒ verdict `none`; (2) `--list-gateable` (countable/advisory per id); malformed or an id set that differs from (1) ⇒ `unreadable`; (3) if `RULES_CHECK_NO_CMD=1` in the environment ⇒ `cmd_disabled` (never invokes `--if-stamped`); else `--if-stamped` once, parsed with EXACTLY the fail-closed rules item 06 adopted (empty stdout ⇒ `unreadable`; the exact whole line `  [SKIP] all (unstamped)` with no `  [RUN ] ` line ⇒ `unstamped`; trailer rule `Checks passed: N/M` with `M == |selected|` and rc ∈ {0,1}, else every id `unresolved`; per-id exact `  [PASS] <id>` / `  [FAIL] <id>` with near-miss detection ⇒ pass/fail/unresolved). **Decided at Plan Review (choice 2 — EXTRACT):** extract that parse from `worker-rule-selfcheck.sh` into a sourced `loomwright/scripts/rules-replay-lib.sh` (functions `rules_replay_trailer_ok`, `rules_replay_map_id`; the lib defines FUNCTIONS ONLY — no top-level side effects, no `set -e`, no argv parsing) so both helpers run the SAME tested code — a second copy of a fail-closed security parser kept honest only by a byte-equality pin is exactly the "second copy that drifts silently" defect house rule 3 names. Sourcing posture differs by consumer: `worker-rule-selfcheck.sh` sources it FAIL-SAFE (`. "$HERE/rules-replay-lib.sh" 2>/dev/null || exit 0` — stdout stays empty, exit 0, its contract unchanged); `rules-gate-verdict.sh` sources it FAIL-CLOSED (absent/unsourceable lib ⇒ verdict `unreadable`). **The extraction is NOT free for item 06's test:** `test-worker-rule-selfcheck.sh`'s (ii-b) and (M-mismatch) mutants `sed` the helper's trailer-rule lines (`  0|1)`, `&& [ "$_m" -eq "$LISTED_N" ]`) behind `cmp -s` gates, and its spy/spym blocks copy ONLY the helper beside a stub checker — so that test's fixtures, expected-output strings and every `ok`/`no` assertion stay UNCHANGED, and ONLY its three mutant-construction blocks (ac7, ii-b, M-mismatch) and two spy-dir setups (spy, spym) are updated to copy `rules-replay-lib.sh` beside the helper copy and to apply the ii-b / M-mismatch `sed` mutants to the lib copy — same gated-mutant discipline (non-empty, differs, `bash -n`, positive control).
**Output — ONE JSON object on stdout, always exit 0** (a verdict is a normal outcome; consumers decide):
```
{"verdict":"ok|none|fail|unresolved|unstamped|cmd_disabled|unreadable",
 "selected":[ids],"countable":[ids],"advisory":[{"id":..,"reason":..}],
 "passed":[ids],"failing":[ids],"unresolved":[ids],"checks_passed":"n/m"|null}
```
Verdict derivation (state trace, in this order): no `jq` / checker absent / not a git tree / bad `--root` / malformed list output ⇒ `unreadable`. `selected == []` ⇒ `none`. `countable == []` (every selected id advisory) ⇒ `none` (the advisory ids are still listed so consumers can REPORT them). `RULES_CHECK_NO_CMD=1` ⇒ `cmd_disabled`. `[SKIP] all (unstamped)` ⇒ `unstamped`. Trailer rule fails ⇒ `unresolved` (every countable id listed in `unresolved`). Any COUNTABLE id maps `fail` ⇒ `fail`; else any COUNTABLE id maps `unresolved` ⇒ `unresolved`; else `ok`. An ADVISORY id's pass/fail is reported in `passed`/`failing` for the report line but NEVER changes the verdict (AC: "a check outside the chosen set is reported advisory, never counted"). All ids are emitted as `--arg` data through jq, never as program text. Bound: none needed (JSON, not deviations lines).

### D-c — gate-eval condition 7 (self-resolved, cond-6 posture, no override)
- **New gate-owned keys refused in `ctx.json`:** `rules_gate`, `rules_ok`, `rules_check` — added to the existing refusal loop; any of them present ⇒ `PARK: ctx_carries_gate_owned_key` before anything else (AC5).
- **Evaluated AFTER cond 6** (so every existing PARK reason keeps its precedence and the existing test order is untouched): the gate runs `"$(dirname "$0")/rules-gate-verdict.sh" --root "$root"` ITSELF (sibling lookup, exactly the cond-6 `classify-risk.sh` shape) on the checkout the drain declared READY in, parses `.verdict` with an explicit `has()`/`type=="string"` read, and computes `rules_ok` in the affirmative form: `ok` ⇒ `"true"`; `none` ⇒ `"true"` (D3: nothing countable to verify — the cond-5 `na` precedent); everything else ⇒ not `"true"`. Then the single test `[ "$rules_ok" != "true" ] ⇒ PARK` with a NAMED reason: `fail` ⇒ `PARK: rules_check_failed (<up to 3 ids; "; ">)`; `unresolved` ⇒ `PARK: rules_check_unresolved (<ids>)`; `unstamped` ⇒ `PARK: rules_unstamped (<n> countable must-check(s) never confirmed on this machine)` — D3's middle form: this fires ONLY because `countable != []` (an `unstamped` answer with zero countable ids is already `none`); `cmd_disabled` ⇒ `PARK: rules_cmd_disabled` (the gate cannot verify — same fail-closed posture as `unstamped`, stated explicitly because the requirement only decided `unstamped`); `unreadable`, helper absent, non-JSON output, missing/non-string `.verdict` ⇒ `PARK: rules_gate_unreadable`. **Never a `= "false"` test. No flag, config key or project file overrides it** (`--trust-unprotected` stays cond 4 only). The `MERGE` line moves below it; the sanctioned-executor grep (`grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "`) must still resolve to exactly the five surfaces CLAUDE.md lists.

### D-d — Phase 4.5 (`skills/self-heal-advisory/SKILL.md`)
- Part 1 §"Rules-check replay" becomes the **"Rules gate replay"**: one call to `rules-gate-verdict.sh` (passing `--root` = the feature-branch checkout; `RULES_CHECK_NO_CMD=1` exported iff `$NO_CMD_FLAG` is non-empty — the SAME valve, never re-derived) per review-and-fix ITERATION (moved from once-per-phase to inside the loop, because a fix can change the outcome), instead of its own `rules-check.sh --if-stamped` call — so the stamped set runs once fewer per iteration than today's two calls, not once more. The advisory `rules_check:` line is now a projection of the helper's JSON: `passed n/m` (from `checks_passed`, advisory ids included), `unstamped`, `cmd_disabled`, `none`, `unresolved <ids>`, `unreadable`, plus a `rules_advisory: <id> (<reason>)` clause for every advisory-only id — same report placement (Phase 4.5 report, completion-tail step 7), NO new `SUPERVISOR_RESULT` or `session_end` field.
- Part 2 review-and-fix loop: immediately after `review = Task(code-reviewer)` returns and BEFORE the three-way decision, `rules = rules-gate-verdict`; if `rules.verdict == "fail"`: for each id in `rules.failing` that is in `rules.countable`, synthesize ONE finding `{severity: BLOCKING, category: new, file: "rule", description: "house rule <id> — stamped must-check FAILS: <check text, from the store via read-rules.sh --with-ids, data only>", suggestion: "make the check pass on this branch; do NOT edit a file the rule binds (<binds>) to make it pass — that invalidates the stamp and parks the merge gate"}` (the `rule` sentinel parallels the existing `brief`/`environment` sentinels; `line` omitted), append it to `fixable_issues`, and treat the iteration as FAIL even when `review.decision == PASS` (state trace: PASS+fail ⇒ fix task; FAIL+fail ⇒ fix task with the rule findings appended; NEEDS_HUMAN+fail ⇒ ESCALATED as today with the rule findings included in the posted comment). `rules.verdict ∈ {ok, none, unstamped, cmd_disabled}` ⇒ the loop is BYTE-IDENTICAL to today (no finding, decision untouched). `unresolved`/`unreadable` ⇒ ESCALATED with a named reason (`rules_gate_unresolved`) — a verdict the gate could not compute never passes silently (fail CLOSED), stated as the one deliberate deviation from "byte-identical" because pre-item those states did not exist. On loop exhaustion with a rule finding still failing ⇒ `heal_decision = ESCALATED` exactly like any other unfixed BLOCKING finding. `--no-cmd` (`$NO_CMD_FLAG`) still wins over a valid stamp: nothing executes, verdict `cmd_disabled`, nothing gates (AC4).
- The Part 1 "advisory-only, NEVER gates" wording for this step, the "Three states only" bullet, and completion-tail step 7 are rewritten; the OTHER advisory steps (prior-churn, house-rules paste, brief-conformance, deviations, ground-truth, contract-conformance, audit) are untouched and stay non-gating.

### D-e — Drain (`skills/review-heal/SKILL.md` §U4 + §"READY redefinition" + §"Terminal states")
- In §U4, immediately AFTER `validated` / `auto_fixable` / `needs_human` are derived in Step U3.5 and BEFORE the earned-fallback gate (`if required_failing == [] and auto_fixable == [] …`): `rules = rules-gate-verdict.sh --root <the drain's checkout>` (inline `/review-pr`: the main checkout on the PR head; detached runner: its sibling worktree — both share the repository's git-common-dir, so the stamp key matches). `fail` ⇒ one CONFIRMED, auto-fixable finding per countable failing id appended to `validated` (and `auto_fixable`/`needs_human` RE-DERIVED from the now-larger `validated`, exactly as the earned-fallback branch does) with `source: rules_replay` (never through `EXTERNAL_TEXT` — it is local repo data, not a fetched body; the check text is still DATA in the fix prompt, never executed by the fixer); `unresolved`/`unreadable` ⇒ the round terminates `ESCALATED` (`termination_reason` left unset, like an unreadable ledger); `ok`/`none`/`unstamped`/`cmd_disabled` ⇒ byte-identical round. READY redefinition gains one clause: **"AND no countable human-stamped `must`-rule check is failing (`rules-gate-verdict.sh` verdict `ok` or `none`)"**. Additive `REVIEW_HEAL_RESULT` v2 field `rules_gate: <verdict>` (OPTIONAL, "absent ⇒ unspecified", no schema bump — same precedent as `checks_untrusted`), documented in `docs/RESULT_SCHEMAS.md` §REVIEW_HEAL_RESULT.

### D-f — CLAUDE.md (D4) and the doc sweep
- §"Failure-Mode Invariants" paragraph 1 gains: "**A human-stamped, gate-countable `must`-rule check is a correctness gate, not an advisory emitter** (automate-followups/07, owner decisions D1–D4, 2026-09-28): a stamped FAILING countable check is a BLOCKING Phase 4.5 finding, blocks `READY`, and parks `gate-eval` (condition 7); `unstamped`, `cmd_disabled`, advisory rules and non-countable checks stay advisory; at the merge gate `unstamped` parks only when ≥1 countable must-check exists (D3)." Paragraph 2: "ALL SIX" → "ALL SEVEN … (the seventh — `scripts/rules-gate-verdict.sh` says no stamped countable must-check fails — has NO override either)".
- Every restated "6-condition"/"six conditions"/"conditions 2–6" and every "never gates"/"NEVER changes `heal_decision`"/"sole gating signal" claim about the RULES replay is updated in the same change — grep the OLD wording repo-wide (`6[- ]condition|six conditions|ALL 6|conditions 2.6|still never gates|never enters the review-and-fix loop|Three consumers of .--if-stamped., all advisory`) — surfaces found at Launch Pad: `skills/automate-loop/SKILL.md` (§1.5 row, §6 step 4, §10 header + ctx shape + key list + "On all 6 holding", §11, Quality Gates), `commands/automate.md` (table + overview), `commands/agent-help.md`, `README.md`, `.claude-plugin/README.md` (lines 206 and 209), `docs/ARCHITECTURE_CONTRACTS.md`, `scripts/automate-helpers.sh` header, `skills/rules/SKILL.md` §1 (new `binds` row), §8 ("NOT an unattended gate" → now one gating consumer, named), §8.1 (hash input; honest limit 3 rewritten to describe `binds`; "Three consumers, all advisory" → four, one gating), §8.2 (`--list-gateable` sibling), §9; `.agent/rules/README.md` schema table (+`binds`); `commands/rules.md` §check (`--list-gateable`, `binds`); `commands/supervisor.md` + `agents/supervisor.md` Phase 4.5 stanza ("`CODE_REVIEW_RESULT` stays the sole gating signal" → "… the sole LLM gating signal; a stamped countable `must`-rule failure is the one deterministic co-gate"); `skills/self-heal-advisory/SKILL.md`; `skills/review-heal/SKILL.md`; `docs/RESULT_SCHEMAS.md` (REVIEW_HEAL_RESULT `rules_gate`); `CHANGELOG.md` + version bump `15.110.0 → 15.111.0` in `loomwright/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` (description counts unchanged — do not append a version clause). **Literal-count discipline (house rule 2):** keep the literal "seven" ONLY in the authority (`skills/automate-loop/SKILL.md` §10) and in CLAUDE.md's invariant paragraph; on every secondary surface (README, `.claude-plugin/README.md`, `agent-help.md`, `automate.md`, `ARCHITECTURE_CONTRACTS.md`, the helper header) replace the count with a pointer — "the fail-closed trusted-merge gate (conditions enumerated in `skills/automate-loop/SKILL.md` §10)" — so the next condition needs no N-surface sweep.

### Out of scope (from the requirement, restated so the worker does not drift)
No gating on advisory rules, on `unstamped`/`cmd_disabled` at Phase 4.5/drain, or on `audit-rules.sh` findings (item 09). No new executor of a `check` (`rules-check.sh` stays the only one; the new helper and the gate DELEGATE). No shared/committed stamp (item 08). No `add-rule.sh --binds` flag (a `binds` array is hand-authored JSON; `audit-rules.sh` lints are item 09's seam — record `unbound_invocation` as a follow-up idea in the CHANGELOG entry, do not build it).

## Acceptance Criteria
- [ ] AC1 Given a fixture store (temp git repo, sandboxed `$HOME`) with a countable `must` rule whose check FAILS and a valid stamp written by `--confirm`, when `rules-gate-verdict.sh` runs, then it prints `verdict: fail` with the id in `failing` and exits 0; and when `gate-eval` runs against an otherwise all-green stubbed PR, then it prints `PARK: rules_check_failed (<id>)` and the merge stub log shows 0 merges.
- [ ] AC2 Given the same fixture with the check PASSING, when `rules-gate-verdict.sh` and `gate-eval` run, then the verdict is `ok`, `gate-eval` prints `MERGE` (1 merge), and the Phase 4.5 report line is `rules_check: passed 1/1` — byte-identical to the pre-item line for that state.
- [ ] AC3 Given an `unstamped` store (stamp absent, or one byte of a check edited after stamping), when the helper runs, then verdict `unstamped`, `[RUN ]` never appears and a canary file the check would `touch` is absent; Phase 4.5/drain prose keeps today's `rules_check: unstamped` line and adds no finding; `gate-eval` prints `PARK: rules_unstamped (…)` when `countable != []` and `MERGE` when the store's only must-checks are advisory-only/none (D3 middle form — both legs tested).
- [ ] AC4 Given a valid stamp and `RULES_CHECK_NO_CMD=1` (Phase 4.5 `--no-cmd`), when the helper runs, then verdict `cmd_disabled`, `--if-stamped` is NEVER invoked (argv spy), the canary stays absent, and Phase 4.5 keeps `rules_check: cmd_disabled` with no finding; `gate-eval` prints `PARK: rules_cmd_disabled` when `countable != []`.
- [ ] AC5 Given a `ctx.json` carrying any of `rules_gate`/`rules_ok`/`rules_check` (any value), when `gate-eval` runs, then `PARK: ctx_carries_gate_owned_key`, 0 merges, and the helper stub was never called (call-log assertion — proves cond 7 is gate-owned and self-resolved).
- [ ] AC6 Given the `--list-gateable` fixtures — (a1) a grep-only check with an explicit `binds: []` ⇒ `countable\tno_invocations`; (a2) the same check with NO `binds` key (or `binds: null`) ⇒ `advisory\tbinds_undeclared`; (b) `bash scripts/lint.sh` (tracked, +x) with `binds: []` ⇒ `advisory\tunbound:scripts/lint.sh`; (c) the same with `binds: ["scripts/lint.sh"]` ⇒ `countable\tbound:1`; (d) a tracked `#!` script named without an interpreter ⇒ detected; (e) an untracked path named ⇒ not detected; (f) `binds` naming an absolute/`..`/untracked path or a non-array ⇒ `advisory\tbinds_invalid` — when `rules-check.sh --list-gateable` runs, then each prints exactly that, executes nothing (canary), and exits 0.
- [ ] AC7 (caveat d) Given fixture (c) stamped and FAILING, when a "PR" commit edits `scripts/lint.sh` so the check would now pass, then `--if-stamped` prints `[SKIP] all (unstamped)` (the hash moved), the helper says `unstamped`, and `gate-eval` PARKs (`rules_unstamped`) — the edit could not turn the failure into a counted pass; and given fixture (b) (unbound) stamped and FAILING, then the helper's verdict is `none` with the id in `advisory`, the Phase 4.5 line reports `rules_advisory: <id> (unbound:scripts/lint.sh)`, and `gate-eval` does not park on it.
- [ ] AC8 Given a binds-free store (no `binds` key, `binds: null`, or `binds: []`), when the pre-item and post-item `rules-check.sh --confirm` then `--if-stamped` run, then the written stamp hash and every stdout line are byte-identical (existing stamps stay valid); `test-rules-check.sh` and `test-run-ground-truth.sh` stay green; `test-worker-rule-selfcheck.sh` stays green with its fixtures, expected-output strings and every `ok`/`no` assertion UNCHANGED — ONLY its three mutant-construction blocks (ac7, ii-b, M-mismatch) and two spy-dir setups (spy, spym) are updated to copy `rules-replay-lib.sh` beside the helper copy and to apply the ii-b / M-mismatch `sed` mutants to the lib copy (each mutant still gated: non-empty, differs, `bash -n`, positive control).
- [ ] AC9 Mutation controls (gated: mutant non-empty, differs, `bash -n` passes, else the control FAILS loudly): (a) deleting the helper invocation + the READY clause from `skills/review-heal/SKILL.md` and the finding-synthesis block from `skills/self-heal-advisory/SKILL.md` makes the static prompt-seam pin test fail (the prose-side control for "reverting (a) makes AC1 reach READY"); (b) commenting out the cond-7 `rules-gate-verdict.sh` invocation in `automate-helpers.sh` makes the AC1 failing-check case print `MERGE` (the code-side control), and the instrumented stub proves the helper is otherwise called on the all-green path (load-bearing, like the cond-6 control).
- [ ] AC10 Given the forgery legs from item 06 (a check that pre-prints `  [PASS] <id>`, a forged `[SKIP] all (unstamped)` beside a `[RUN ]` line, a pre-print-then-kill with a forged complete trailer, an `M ≠ |selected|` trailer), when the helper runs, then every countable id is `unresolved` (never `ok`), `gate-eval` PARKs `rules_check_unresolved`, and Phase 4.5/drain escalate — a forged output can only ADD a blocker, never remove one.
- [ ] AC11 CLAUDE.md §"Failure-Mode Invariants" amended per D-f; `grep -rniE '6[- ]condition|six conditions|ALL 6 (trusted|cond)|conditions 2.6' loomwright CLAUDE.md README.md .claude-plugin/README.md` and the "never gates" greps in D-f return no stale hit (`agents/red-team-reviewer.md`'s "ALL 6 MANDATORY" attack-vector lines are a different count and are excluded by the narrowed pattern); `scripts/check-doc-currency.sh` and `scripts/check-token-budget.sh` green; `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` resolves to exactly the five sanctioned surfaces.
- [ ] AC12 The full test loop is green: every `loomwright/scripts/test-*.sh` AND every root `scripts/test-*.sh`, plus `scripts/check-vendor-coupling.sh`, `scripts/check-test-hermetic.sh` (the new tests source `hermetic-test-env.sh`), run with `bash` (never pasted inline).

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Mechanism: `binds` hash-binding + `--list-gateable` in `rules-check.sh`; shared replay parse lib (item 06's test scaffolding follows it); `rules-gate-verdict.sh` + its test | AC1 (helper half), AC2 (helper half), AC3 (helper), AC4 (helper), AC6, AC7 (helper half), AC8, AC10 (helper half) | 4 modify, 3 create | `skills/rules/SKILL.md` §8–§9, `skills/unit-testing/SKILL.md` | LAUNCHABLE |
| 2 | `gate-eval` condition 7 (self-resolved, refused ctx keys, named PARK reasons) + test section F + gated mutant | AC1 (gate half), AC2 (gate half), AC3 (gate legs), AC4 (gate leg), AC5, AC7 (gate half), AC9(b), AC10 (gate half) | 2 modify, 0 create | `skills/automate-loop/SKILL.md` §10, `skills/unit-testing/SKILL.md` | BLOCKED (by #1) |
| 3 | Prose + docs: Phase 4.5 gate replay + finding synthesis, drain READY clause + `rules_gate` field, CLAUDE.md D4, rules skill/README/command, automate surfaces (pointer, not a count), CHANGELOG + version 15.111.0, static prompt-seam pin test | AC2 (report line), AC3/AC4 (prose legs), AC7 (report line), AC9(a), AC11, AC12 | 19 modify, 1 create | `skills/self-heal-advisory/SKILL.md`, `skills/review-heal/SKILL.md`, `skills/quality-checklist/SKILL.md` | BLOCKED (by #1, #2) |

### Subtask Contracts (provides / requires / external_requires / lanes)

```yaml
subtask_1:
  provides:
    - {kind: "file", path: "loomwright/scripts/rules-gate-verdict.sh"}
    - {kind: "file", path: "loomwright/scripts/rules-replay-lib.sh"}
    - {kind: "file", path: "loomwright/scripts/test-rules-gate-verdict.sh"}
    - {kind: "symbol", path: "loomwright/scripts/rules-check.sh", name: "--list-gateable"}
    - {kind: "symbol", path: "loomwright/scripts/rules-check.sh", name: "binds"}
    - {kind: "symbol", path: "loomwright/scripts/rules-gate-verdict.sh", name: "verdict"}
  requires: []
  external_requires:
    - {kind: "file", path: "loomwright/scripts/rules-check.sh"}
    - {kind: "file", path: "loomwright/scripts/worker-rule-selfcheck.sh"}
    - {kind: "file", path: "loomwright/scripts/test-worker-rule-selfcheck.sh"}
    - {kind: "file", path: "loomwright/scripts/hermetic-test-env.sh"}
  lanes:
    - "loomwright/scripts/rules-check.sh"
    - "loomwright/scripts/rules-replay-lib.sh"
    - "loomwright/scripts/worker-rule-selfcheck.sh"
    - "loomwright/scripts/rules-gate-verdict.sh"
    - "loomwright/scripts/test-rules-check.sh"
    - "loomwright/scripts/test-rules-gate-verdict.sh"
    - "loomwright/scripts/test-worker-rule-selfcheck.sh"

subtask_2:
  provides:
    - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "rules_check_failed"}
    - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "rules_gate_unreadable"}
    - {kind: "symbol", path: "loomwright/scripts/test-automate-helpers.sh", name: "rules_check_failed"}
  requires:
    - {kind: "file", path: "loomwright/scripts/rules-gate-verdict.sh", from: 1}
    - {kind: "symbol", path: "loomwright/scripts/rules-gate-verdict.sh", name: "verdict", from: 1}
  external_requires:
    - {kind: "file", path: "loomwright/scripts/automate-helpers.sh"}
    - {kind: "file", path: "loomwright/scripts/test-automate-helpers.sh"}
  lanes:
    - "loomwright/scripts/automate-helpers.sh"
    - "loomwright/scripts/test-automate-helpers.sh"

subtask_3:
  provides:
    - {kind: "symbol", path: "CLAUDE.md", name: "gate-countable"}
    - {kind: "symbol", path: "CHANGELOG.md", name: "v15.111.0"}
    - {kind: "symbol", path: "loomwright/skills/automate-loop/SKILL.md", name: "rules_check_failed"}
    - {kind: "symbol", path: "loomwright/skills/self-heal-advisory/SKILL.md", name: "rules-gate-verdict.sh"}
    - {kind: "symbol", path: "loomwright/skills/review-heal/SKILL.md", name: "rules-gate-verdict.sh"}
    - {kind: "symbol", path: "loomwright/skills/rules/SKILL.md", name: "binds"}
    - {kind: "file", path: "loomwright/scripts/test-rules-gate-seams.sh"}
  requires:
    - {kind: "file", path: "loomwright/scripts/rules-gate-verdict.sh", from: 1}
    - {kind: "symbol", path: "loomwright/scripts/rules-check.sh", name: "--list-gateable", from: 1}
    - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "rules_check_failed", from: 2}
  external_requires:
    - {kind: "file", path: "CLAUDE.md"}
    - {kind: "file", path: "loomwright/skills/self-heal-advisory/SKILL.md"}
    - {kind: "file", path: "loomwright/skills/review-heal/SKILL.md"}
    - {kind: "file", path: "loomwright/skills/automate-loop/SKILL.md"}
    - {kind: "file", path: "loomwright/skills/rules/SKILL.md"}
    - {kind: "file", path: "loomwright/docs/RESULT_SCHEMAS.md"}
    - {kind: "file", path: "loomwright/.claude-plugin/plugin.json"}
    - {kind: "file", path: "scripts/check-doc-currency.sh"}
  lanes:
    - "CLAUDE.md"
    - "README.md"
    - "CHANGELOG.md"
    - ".agent/rules/README.md"
    - ".claude-plugin/marketplace.json"
    - ".claude-plugin/README.md"
    - "loomwright/.claude-plugin/plugin.json"
    - "loomwright/skills/self-heal-advisory/SKILL.md"
    - "loomwright/skills/review-heal/SKILL.md"
    - "loomwright/skills/automate-loop/SKILL.md"
    - "loomwright/skills/rules/SKILL.md"
    - "loomwright/commands/automate.md"
    - "loomwright/commands/agent-help.md"
    - "loomwright/commands/rules.md"
    - "loomwright/commands/supervisor.md"
    - "loomwright/agents/supervisor.md"
    - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
    - "loomwright/docs/RESULT_SCHEMAS.md"
    - "loomwright/docs/prompt-token-budgets.json"
    - "loomwright/scripts/test-rules-gate-seams.sh"
```

### Per-subtask notes for the worker
- **S1:** `--list-gateable` sits in the SAME early-exit tier as `--list-selected` (before the hash, the `--if-stamped` compare, the execute loop, the stamp write) and is the ONLY place the `binds`/invoked-file classification is computed (`rules-check.sh` stays the one parser of a check). Detected-invoked-file resolution runs from the repo root with `git ls-files --error-unmatch -- <tok>` (tracked) — never `[ -e ]` alone. Hash input: keep `[.id, .check] | @tsv` for a binds-free rule; for a bound rule append `\t<path>=<sha256|MISSING|INVALID>` per sorted path (compute with the script's existing `_rc_sha256_file`). `worker-rule-selfcheck.sh` after sourcing the lib (fail-SAFE: `. "$HERE/rules-replay-lib.sh" 2>/dev/null || exit 0`) must produce byte-identical stdout on every existing case — `test-worker-rule-selfcheck.sh`'s assertions and expected strings are the proof and stay untouched; only its mutant-construction and spy-dir scaffolding learns about the lib (AC8). `rules-gate-verdict.sh` sources the same lib FAIL-CLOSED (absent ⇒ `unreadable`). The new test mirrors `test-worker-rule-selfcheck.sh`'s structure (temp git repos, per-case `HOME`, canary files, argv/PATH spy, gated mutants) and adds the `binds` fixtures of AC6/AC7 (a tracked `scripts/lint.sh` committed in the temp repo, then edited in a second commit). Portability: bash 3.2, no `mapfile`, no `timeout`, `LC_ALL=C sort`.
- **S2:** copy the cond-6 shape exactly (sibling lookup via `$(dirname "$0")`, `-r` check, explicit `has()`/type read, affirmative test, named PARK with up to 3 ids joined by `"; "`). In the test, add a stub `rules-gate-verdict.sh` next to the stub `classify-risk.sh` in `$GWD` that echoes `$GH_STUB_DIR/rules.json` (default `{"verdict":"none",...}` so every EXISTING gate case still MERGEs/PARKs exactly as before — re-baseline it in `reset_live`), then section F: fail / unresolved / unstamped-with-countable / unstamped-with-none / cmd_disabled / unreadable (non-JSON, missing verdict, helper absent) / the three refused ctx keys / the gated mutant (comment out the invocation ⇒ `MERGE` on the failing case; instrumented stub log proves the call on the green path). Update the header comment's condition list and PARK-reason enumeration.
- **S3:** state-trace every prose branch (the skill/agent `.md` files are the program). In `self-heal-advisory` Part 2, the synthesis block goes right after `phase45_review_invoked = true` / the CODE_REVIEW_RESULT parse and BEFORE `heal_dismissed`; keep the `heal_decision` derivation sentences in the completion tail consistent. Keep the `agents/supervisor.md` edit to one sentence (token budget). CHANGELOG entry: lead with the owner decision, name the three seams, the `binds` design and its honest limits, and the D3 middle form; record `unbound_invocation` as a follow-up for `audit-rules.sh`. `test-rules-gate-seams.sh` pins: (1) `rules-gate-verdict.sh` invoked in both skills; (2) the READY clause in `review-heal` mentions the rules verdict; (3) the BLOCKING synthesis in `self-heal-advisory`; (4) CLAUDE.md carries the D4 sentence — each with a gated mutant that deletes the line.

## Parallelism Analysis

### Dependency Graph
```
1 ──▶ 2 ──▶ 3
```
### File Overlap Matrix
| | 1 | 2 | 3 |
|---|---|---|---|
| 1 | — | none | none |
| 2 | none | — | none |
| 3 | none | none | — |
Lanes are disjoint; ordering is by `requires` (2 needs 1's helper contract; 3 documents 1 and 2). All three are mutually reachable in the DAG, so no lane collision is possible.

### Batch Plan
- Batch 1: [1] · Batch 2: [2] · Batch 3: [3] — `sequential`, 1 worker, on the feature branch (no worktree fan-out).

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/rules/SKILL.md` (§1 schema, §8.1 stamp, §8.2 list, §9 trust boundary), `skills/unit-testing/SKILL.md`, `skills/quality-checklist/SKILL.md` |
| 2 | `skills/automate-loop/SKILL.md` §10–§11, `skills/unit-testing/SKILL.md` |
| 3 | `skills/self-heal-advisory/SKILL.md`, `skills/review-heal/SKILL.md`, `skills/automate-loop/SKILL.md`, `skills/quality-checklist/SKILL.md` (count/version/restated-list drift) |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| R1 — A documented invariant flips ("never gates" → a gate): a reviewer or a future worker treats the amended CLAUDE.md as an error and "fixes" it back — source: Feasibility (Phase 2.5) | HIGH | D4 sentence names the owner decision and date; the static pin test (AC9a) fails if the sentence is removed; CHANGELOG leads with the decision. |
| R2 — Dormant on this repo: nothing exercises the gate on `main`, so a defect only shows up on the first checkable `must` rule — source: Feasibility (Phase 2.5) | MEDIUM | Every AC is fixture-proven (temp repos, sandboxed HOME, canaries, forgery legs, gated mutants); item 09's audit nudge watches the store; record the dormancy honestly in CHANGELOG. |
| R3 — `binds` is a human declaration; an explicit `binds: []` rule whose check invokes repo files through a shape the heuristic cannot see (task-runner indirection such as `make`/`npm run`/`pytest`, transitive calls, `$(…)`, globs) is counted while a PR edits those files | MEDIUM | Heuristic only DEMOTES; honest limits documented in §8.1 and `--list-gateable` header; follow-up `audit-rules.sh unbound_invocation` lint recorded (not built here). |
| R4 — A Phase 4.5 fix worker "fixes" a failing check by editing its bound file: the set becomes `unstamped` (advisory) and Phase 4.5 PASSes | MEDIUM | By design: the merge gate then PARKs `rules_unstamped` (D3) and a human re-confirms; the synthesized finding's `suggestion` tells the fixer not to; documented as the D3 consequence. |
| R5 — Changing `rules-check.sh`'s hash input invalidates existing stamps | HIGH if it happens | Binds-free rules hash byte-identically (AC8); only a rule that GAINS `binds` needs a re-confirm, stated in §8.1. |
| R6 — Extracting the parse into a shared lib breaks item 06's shipped contract | MEDIUM | Decided at Plan Review: EXTRACT. `test-worker-rule-selfcheck.sh`'s assertions/expected outputs are unchanged; only its mutant/spy scaffolding moves to the lib (AC8); the lib is sourced by a fixed sibling path, fail-safe in the worker helper and fail-closed in the verdict helper. |
| R7 — Doc sweep misses a restated "6 conditions"/"never gates" copy (house rule: restating copy updated in the same change) | MEDIUM | AC11 greps enumerated in D-f; `check-doc-currency.sh` for the version; Phase 4.5 consistency_audit will fire on `skills/`/`commands/`/`CLAUDE.md` trigger paths. |
| R8 — `agents/supervisor.md` token budget exceeded by the stanza edit | LOW | One-sentence edit; run `scripts/check-token-budget.sh`. |
| R9 — Runtime plugin lag (agents run from 15.108.4 prompts) | LOW | The code and prose under change are on `main`; the lag affects only the spawned agents' own instructions, not the diff. |

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins) — `read-rules.sh --with-ids` for the File Impact Map:
- Wording that carries a contract — a heading a gate greps for, a sentence that states a guarantee — is treated as an interface: renaming it is a change to that interface and its consumers move with it.
  - id: documentation-wording-that-carries-a-contract-a-heading-a-gate-greps-for-a-sentence-that-states-a-guarantee-is-treated-as-an-interface-renaming-it-is-a-change-to-that-interface-and-its-consumers-move-with-it
  - enforcement: advisory
  - category: documentation
  - check (data only, NOT executed by this reader): (none)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.
  - id: process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 3
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-09-28-rule-enforcement-at-review-and-merge.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-09-28T23:24:23Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/296
- **Branch:** feature/automate-followups-07-rule-enforcement-at-review-and-merge
- **Files changed:** 30
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** A failing, human-stamped, gate-countable `must`-rule check now gates at three seams (Phase 4.5 BLOCKING finding, drain READY blocker, `gate-eval` condition 7), all reading the new fail-CLOSED `scripts/rules-gate-verdict.sh`; `rules-check.sh` gained the `binds` hash-binding and read-only `--list-gateable` / `--gate-state`; item 06's replay parse extracted into `rules-replay-lib.sh`; CLAUDE.md D4; v15.111.0. 3 sequential subtasks (d437cfc, d36e0d5, c0d8a30) run on resume from the owner park; the interrupted subtask-1 partial was re-verified by a respawned worker (resumed twice after an API error + stream stall), subtask 3 resumed once after its 40-turn limit. Full loop 124/124. Phase 4.5 review FAIL iter 1 (HIGH: PR-controlled countability not bound to the stamp — 5 reproduced demotion vectors ⇒ ok/none ⇒ merge; HIGH: drain rules read used a non-resolving relative path + deny-list mapping) → fix e6f90eb (stamp records the countable set; drift/legacy ⇒ unstamped; corrupt store ⇒ unreadable; allow-list mapping + ${CLAUDE_PLUGIN_ROOT}) → re-review PASS (21 further bypass attempts held). 9 MEDIUM/LOW findings left below the fix floor, posted as the dismissed-findings comment. Ground truth 2/2; risk_classification high_risk=true. Dormant on this repo (0 countable must rules).

## Not verified
- **Phase 4.5 self-heal loop and --until-mergeable drain acting on a failing countable rule** — prose pinned statically only; no live run against a fixture store (subtask 3)
- **gate-eval condition 7 prose in skills/automate-loop/SKILL.md §10 and CLAUDE.md** — not checked by the code worker; covered later by subtask 3 and both Phase 4.5 reviews (subtask 2)
