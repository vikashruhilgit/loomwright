# Supervisor Job: iq01 + throughput/01–09 merged — prevent findings at write time and make each review cycle cheaper (ONE PR)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main (== origin/main)
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 2 (two orphaned worktrees: `ai-agent-manager-pa05-engine`, `.claude/worktrees/nice-turing-03abd6` — unrelated, left alone; the `PostToolUse[AskUserQuestion]` live payload probe Part T04 3a asks for could not be run — see Risk Assessment)
- **Source requirement:** .supervisor/requirements/implementation-quality/02-iq01-and-throughput-merged.md
- **Base commit:** 45f6d7b021b3f7884e4b2ffda60f28eb2c224aa2

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2 / BSD userland scripts, python3 validators, jq, markdown prompts — all existing stack |
| 2 | Dependency Availability | GO | jq, python3, gh, git present; no new dependency |
| 3 | Architecture Fit | GO | every part extends an existing mechanism (validator rules, drain helpers, lifecycle emitter, ci-local plan, run-self-tests markers, vendor ratchet) |
| 4 | Scope vs Supervisor Capability | CAUTION | ~95 files across 10 parts in ONE PR — far past one worker's context; split `context-bound` into 7 subtasks (the cap) with a requires-DAG, each run by ONE continuous worker with per-Part evidence files; per-subtask worker turn budget is the binding constraint (worker `maxTurns: 40` in the INSTALLED plugin — this PR's raise does not apply to its own run) |
| 5 | Hard Blockers | GO | preconditions met: PR #438 and #439 MERGED; T09 option decided (A); T03 bound decided (keep 1200 s) |

**Overall Verdict:** CAUTION

## Task
**Goal:** Land implementation-quality/01 (Part IQ01) and throughput/01–09 (Parts T01–T09) as ONE PR that makes the worker apply the reviewer's lens before hand-back, measures findings and phase wall-clock, mechanizes the drain's sub-floor stop and resumable check-wait, shows fix-now cost, makes ci-local fail early, removes the serial tail and fixed-sleep races, shards GitHub CI, and makes vendor-coupling breaches actionable.

**Problem Statement:**
The owner needs an `/automate` item to reach a mergeable PR in far fewer, cheaper review cycles because PR #435 took 5 h 13 m for ~700 lines.
Currently, 11 of its 14 review findings were classes the reviewer checks but the worker is never asked to; each fix cycle cost ~45 min (11-min ci-local, 12-min GitHub CI, re-review); the drain's sub-floor stop is model-evaluated prose (one extra 33-min round); the check-wait contract exceeds the host's 600 s foreground cap; fix-now is chosen without its cost; ci-local reports a 7-second gate failure only after ~11 min; a ~181 s serial tail and a 0.3 s sleep race inflate every run; and nobody can say where an item's time went.
Success looks like: every Part's acceptance criteria met and evidenced in the PR body under that Part's heading, `bash scripts/ci-local.sh` green, and the next real item measurable (first-pass PASS rate, phase timing).

**Owner decisions recorded for this run (binding):** T09 Scope 2 = **A (status quo — manifest class layout untouched)**; T03 total check-wait bound = **keep 1200 s** (refresh the sizing note only); **owner run rule** (source requirement §"Owner run rule"): no new follow-up items — every finding is fixed in THIS PR unless the owner says a finding would divert too much; Merged-item rules 1–7 (source requirement §"Merged-item rules") override the Parts where they conflict.

## Acceptance Criteria

This checklist is a NON-EXHAUSTIVE condensation — the Part acceptance criteria bind. The authoritative per-Part text is the source requirement's `## Part …` sections (Problem / Goal / Scope / Acceptance criteria / Validation / Non-goals, kept verbatim there). Each subtask's worker MUST read its Part(s) from the source requirement in the MAIN checkout (path in the spawn prompt) before starting. Condensed checklist:

- [ ] **AC-IQ01a** Given a worker about to emit WORKER_RESULT, when its status is `completed`/`partial` (not `failed`, not `no_changes: true`), then `agents/worker.md` requires the four-part self-review (checklist, scratch-dir adversarial repro per `agents/code-reviewer.md` §5 — referenced not copied, old-wording sweep, re-check of `## Touched-file invariants`), WORKER_RESULT carries `self_review`, and `validate-worker-result.py` blocks a result without it using the documented `{"decision":"block","reason":…}` shape — with a test that fails on the base commit.
- [ ] **AC-IQ01b** The Self-Heal Miss-Class Checklist gains a "reuse the file's own conventions and guards" class.
- [ ] **AC-IQ01c** A brief that modifies existing scripts carries `## Touched-file invariants` with grounded (file:anchor) entries; Plan Reviewer gains a conditional criterion flagging its absence; template, Launch Pad agent and command mirror agree.
- [ ] **AC-IQ01d** Worker `maxTurns` raised with the measured justification (pa/24 worker: 79 assistant messages / 82 tool calls vs 40); token budgets declared; `check-token-budget.sh` green.
- [ ] **AC-IQ01e** SUPERVISOR_RESULT and the flat `session_end` line carry the first Phase 4.5 iteration decision and total `new` findings (additive, `schema_version` unchanged, `heal_decision` enum not extended); `/insights` shows first-pass PASS rate and findings per item; fixture test covers both.
- [ ] **AC-IQ01f** Replay: the self-review procedure run against PR #435's pre-review commit `87f2205` (scratch clone, base `9a65ecb`) catches ≥ 9 of the 11 worker-preventable findings; per-row result recorded for the PR body, misses listed honestly.
- [ ] **AC-T01** `drain-subfloor-decision.sh eligible|decide` exists with its decision table in the header; §U4 no longer contains a model-evaluated `sub_floor_eligible` expression or READY/ESCALATED branch; the 2026-10-08 round-1 replay fixture prints `confirm` then `READY sub_floor_converged` with exactly the one LOW finding; table-driven tests cover every row; two mutation controls run against COPIES; `sub_floor_fixed` = final round only (fixture + schema row sentence); `gate-eval` condition 1b byte-unchanged.
- [ ] **AC-T02** `automate-helpers.sh dismissed-cost <runfile>` prints exactly one `fix_now_cost:` line, exit 0 on all inputs; fixtures: six-span median ≈ 66 min range 14 m–2 h 53 m, 09-30 out-of-order row dropped, > 12 h span dropped, pinned and legacy terminal wordings, zero samples ⇒ default line naming its basis; §6 step 2 shows the cost in every fix-now option and follow-up as "0 min now"; §6 step 3 pins the re-drain start/terminal line formats (mirrored in `automate-run.md`); decision enum, ledger row shape, `dismissed-pending` and the non-interactive branch unchanged; help golden regenerated.
- [ ] **AC-T03** `wait-for-checks.sh --bound N --call-max M` prints `CONTINUE … remaining=…` at the per-call ceiling and the continuation call ELAPSES within the remaining budget (persisted deadline keyed PR+SHA+scope); new SHA ⇒ fresh deadline; unreadable state on continuation ⇒ `ELAPSED … pending=unreadable_deadline`; without `--call-max` output byte-identical (incl. `escalation.sh`'s `--bound 0 --names`); deadline-reset mutant fails; both skill call sites loop on `CONTINUE` with `--call-max ≤ 570`; no prose still requires one call to cover the bound; `retention-sweep.sh` lists the new scratch dir (mirrored in ARCHITECTURE_CONTRACTS.md's retention table).
- [ ] **AC-T04** `phase-timing.sh --run .supervisor/automate/automate-2026-10-08-121222.md` reproduces every known span of the Part T04 table within 60 s (committed trimmed fixtures in `loomwright/scripts/fixtures/phase-timing/`, replayed by `test-phase-timing.sh`); owner-wait exact/fallback/`null` fixtures; three mutation controls (drop the cc_session_id join, missing endpoint ⇒ 0, attribute ci-local by time window); emitters 3a (`PostToolUse[AskUserQuestion]` → `emit-lifecycle.sh answered`; the hooks.json leaf ends exactly `emit-lifecycle.sh\" answered || true` — NO extra argument after `answered` (unlike the `waiting ask_user` leaf), because Subtask 5's `provides` checks that literal; HOOKS.md row), 3b (timestamped `dismissed:` line), 3c (`pr_created` event), 3d (ci-local HEAD/branch log header line) each tested and exit 0 on empty/malformed input; `/insights` `## Wall-clock (phases · machine vs owner)` renders `null` as "not recorded"; no prose instructs a model to compute a duration.
- [ ] **AC-T05** A full ci-local run on a tree with a red early entry exits 1 with a `ci-local: FAIL …` verdict last, names every red early entry, starts no pool entry, leaves no PASS stamp; a green tree runs every entry exactly once across the two phases; the early set is DERIVED (non-`test-*` ci.yml gates + `# run-self-tests: early` tests) with a marker-removal mutation control; `run-self-tests.sh` streams `run-self-tests: FAIL (exit <rc>, <secs>s): <test>` before the end report; `early`+`serial` on one test ⇒ exit 1 named; `--affected` uses the early set (closes `ae6f354e`); `--list` shows the phases; forced early-red wall time measured (target ≤ 120 s).
- [ ] **AC-T06** Each remaining `serial` marker carries a written reason + measured loaded-pool failure rate; each removed marker has 10/10 green loaded-pool runs; serial tail ≤ 30 s; full `ci-local --force` ≤ 540 s wall (before/after on this machine); every mutation control in the touched tests still red on its mutant; if `test-automate-trail.sh` is split, assertion union equals the original and only if it lowers the pool's critical path by ≥ 60 s.
- [ ] **AC-T07** S6, N8, dead-pid reclaim, (E7) `dbl_arm`, (p6) reap helper and AA-F12e rewritten to bounded condition waits that fail naming the condition; `wait-lib.sh` + `test-wait-lib.sh` (clock-bounded, slow-`sleep` mutation control); `test-no-fixed-sleep-race.sh` ratchet with `# fixed-sleep-ok: <reason>` escape hatch and fire/no-fire controls; (c) lines annotated; S6 delayed-stub repro red on base, green on branch; S6 passes 50/50 under a loaded pool.
- [ ] **AC-T08** `run-self-tests.sh --shard K/N` / `--list` with the union-equals-full-list invariant tested; ci.yml split into `static`, `suite` (matrix, `fail-fast: false`) and an aggregating job named exactly `ci` (`if: always()`, fails unless both needs succeed, fails closed on a missing manifest / missing or duplicated test / non-zero rc, inline `run:` — no new `bash scripts/<x>.sh` line); every job carries job-level `timeout-minutes`; `ci-local --list` gate lines identical before/after; `test-ci-local.sh`, `test-run-self-tests.sh`, `test-check-vendor-coupling.sh` green with new arms red on base. (Red-shard / dropped-manifest probes on real CI are post-push operator evidence — see Risk Assessment.)
- [ ] **AC-T09** A BREACH prints a detail block (added lines with line numbers, tokens, classes via the SAME awk counter; ways out in order reword → reuse → adapter globs read from the manifest → raise; never runtime assembly, stated positively; ready-to-paste raise row with a sentinel reason that raise_check treats as missing); `base unavailable` path; case15 names the live gate's verdict; dismissed LOW entries 1–3 folded in (label, no restated class list in script header or ARCHITECTURE_CONTRACTS.md, integer raise row, `-0` rejected consistently); strictness unchanged; manifest class layout untouched (owner chose A); AGENT_GUIDELINES.md gains the advisory pre-full-run line.
- [ ] **AC-MERGED** One changelog fragment `changelog.d/iq01-throughput-merged.md` (`<!-- bump: minor -->`, one paragraph per Part); NO `scripts/bump-version.sh`; token budgets, skill `version:`/`lastUpdated:` + `SKILLS_INDEX.md` (`check-skills-index-sync.sh --write`), and vendor-coupling manifest allowances each reconciled ONCE in the last subtask; `plan-waves … --lint` on the source requirement prints `Touches ok; Depends on ok`; `bash scripts/ci-local.sh` green before the push; the PR body carries one labelled section per Part with its evidence.

## Touched-file invariants

> Grounded at base `45f6d7b` (file + quoted anchor). Every worker re-checks the entries for the files in its lanes before hand-back. Full per-file notes: this section is the contract; anything not listed is still governed by the file's own header.

- **`loomwright/agents/worker.md`** — `test-no-self-matching-wait.sh` requires the phrase "the waiter matches itself and never exits" within 3 lines after the `pre-push command` line in `### Step 5: Verify`: insert the self-review AFTER item 4's sub-bullets, never between them. Keep the `Step 5.65` heading, "worktree…ABSOLUTE path on the Parallel path" and `brief_unreadable`/`jq_missing` text (`test-verify-provides.sh`). `status: X` literals limited to the ENUMS set. All three `## WORKER_RESULT` templates (Success/Partial) must show `self_review`. "Turn budget — 40 turns (advisory)" prose moves with `maxTurns`. The FIX_RESULT `self_review:` clause in `self-heal-advisory`/`review-heal` (prompt-contract only) is a distinct convention — name it, rename neither.
- **`loomwright/scripts/validate-worker-result.py`** — output only through `result_block_parser.emit(ok, reason)`; always exit 0; import guard fails safe to `{}`; header counts rules ("EIGHT numbered rules" + "ADDITIONAL RULE (9)…(12)") and discloses "R4: transcribe, do not silently strengthen" — the new rule is appended LAST (13) with its own disclosure and a `REASON_*` constant; rule 12 (`no_changes`) is evaluated before rule 2. Re-validators: `test-progress-state.sh` case42b and `test-worker-rule-selfcheck.sh` ac4 run the real validator on completed fixtures, `emit-progress-event.sh` re-runs it for `rejected` — their fixtures gain `self_review`.
- **`loomwright/docs/result-schemas/worker-result.md`** — fenced field list `name: type   # optional|required — …`; states "`schema_version` bumps only for breaking or required-field changes" → the worker records the version decision and its rationale (bump with every consumer updated, OR keep 2 with an explicit, consistent justification in the doc) — never silent.
- **`scripts/check-contract-parity.sh`** — MANIFEST `matcher|agent file|block|fields`, 4th column only (never a 5th — out-of-tree consumer `loomwright/scripts/eval-corpus/parity-emit-block/check.sh`); a field must appear in the validator's non-prose code and as a real `- field:` key line in the agent's `## BLOCK` template; update `loomwright/scripts/test-check-contract-parity.sh`'s fixture list; templates stay in the strict YAML subset (no wrapped flow lists, no `|`/`>`).
- **`loomwright/agents/code-reviewer.md`** — reference-only for Subtask 1 (the worker self-review cites its §5 adversarial-repro procedure by name, never copies or edits it); only Subtask 7's token-budget reconciliation may touch it.
- **`loomwright/skills/quality-checklist/SKILL.md`** — class bullet form `- [ ] **Name (\`token\` — scope).** … Class signal: …` under `## Self-Heal Miss-Class Checklist`; `test-deviations-advisory-seam.sh` and `test-brief-conformance-seam.sh` count tokens in that section.
- **`loomwright/agents/plan-reviewer.md` + `loomwright/agents/launch-pad.md` + `loomwright/commands/launch-pad.md` + `loomwright/docs/POINTER_AUDIT.md`** — `test-rule-conformance-seam.sh` pins `## 17 Review Criteria`, `All 17 review criteria must be checked`, `(17 total, Criteria 11, 12, 13, 14, 15, 16, and 17 conditional)`, `All 17 criteria checked`, `| lane_overlap | rule_conformance |`, launch-pad `Check all 17 review criteria.`, command `checks all 17 criteria`; its C17 block spans `### 17. Rule Conformance` → `## Decision Matrix` (a new `### 18` there falls inside it — move the pins in the same commit, keep the 17b mutant killed); Criterion 3's list is already stale. `test-non-interactive-gates-seam.sh` pins phase headings and the `- **Can't-ask rule:**` byte mirror agent↔command. `test-verify-provides.sh` pins `1b. **Gate-parse check` … `2. Spawn Plan Reviewer`, `--- GATE PARSE ---`, and every fenced yaml block with `provides:` needs a `Subtask N` anchor.
- **`loomwright/skills/self-heal-advisory/SKILL.md`** — §"Hard-signal dual emission" flat↔nested table is a "hard contract with ST4 — do NOT rename"; `heal_decision` enum (PASS/ESCALATED/null) not extended; loop keeps `iter_decision` semantics (forced FAIL on rule findings; PASS/NEEDS_HUMAN break before `heal_iterations += 1`).
- **`loomwright/scripts/automate-trail.sh`** — `SUP_ALLOWED` is a CLOSED key set (sidecar-check "carries non-schema key"): new SUPERVISOR_RESULT keys are added there; closeout prints only `closeout:` lines in `CLOSEOUT_TABLE` (an unknown line is classified a leftover; test CL1) → the `item_timing` append is SILENT (`>/dev/null 2>&1 || true`), placed before trail-pr; always exit 0.
- **`loomwright/scripts/build-insights.sh` / `test-insights.sh` / `commands/insights.md`** — always exit 0; fields read `(.x//null)` (keep a `0`: `has()` where `false`/`0` must survive); do NOT insert a section between `## Eval fitness function`…`## System Twin growth` or `## Token economics`…`## Recent sessions` (pinned sed ranges); `insights.md` restates the Summary contents — update in the same change.
- **`loomwright/skills/review-heal/SKILL.md`** — `test-rules-gate-seams.sh` pins (grep -F, gated mutants) `and rules_after.verdict in RULES_PASSABLE:` and the full branch-1 `if outcome.result == "GREEN" and not (rules_after.verdict == "unstamped" and rules_failed_seen) and rules_after.verdict in RULES_PASSABLE:` line plus `rules_escalates = rules_escalates or (rules.verdict == "unstamped" and rules_failed_seen)` — keep verbatim or move the pins in the same commit (mutants must still die); PINNED SEMANTICS blockquote, "split the skipped work, never skip the whole round", and the R2 residual paragraph stay verbatim; the "Never run this wait in the background…" sentence stays at every call site (PITFALLS "Fixed two ways." claims it); Anti-Pattern bullet form `- **\`name\` — title (origin).** prose`.
- **`loomwright/scripts/wait-for-checks.sh`** — ALWAYS exit 0, EXACTLY ONE final line, `set -u` (no `-e`), `GH`/`JQ` stub seams, unknown `--flags` ignored; without `--call-max` byte-identical output and NO state write (consumer `automate-helpers.d/escalation.sh` parses `required=`, `pending=`, `pending_names=`, `red_names=`); validate `--call-max` numerically (today `BOUND` is never validated). Reuse `drain-rounds.sh`'s `pr_hash` derivation; state must not leak into the test's cwd (the drain-rounds LEAK PIN lesson).
- **`loomwright/scripts/retention-sweep.sh`** — rows `row <dir> exhaust '*.json' '<consumers>' '<why>'`; mirrored in `ARCHITECTURE_CONTRACTS.md`'s retention table and the mirror test checks both directions.
- **`loomwright/scripts/automate-dismissed.sh`** — header "SCOPE OF ITS WRITES (the whole list — anything else is a bug)": `dismissed-cost` is read-only; always exit 0; `set -uo pipefail`, no `-e`; bash 3.2/BSD safe; existing-but-unreadable ledger fails closed; unknown-subcommand echo lists every subcommand. `test-automate-dismissed.sh` `progress_n` (`'^- dismissed: '`) and the `- dismissed: drop …` grep change with 3b's leading ts — update the patterns, keep every count assertion.
- **`loomwright/scripts/automate-helpers.sh`** — `--help` is generated from `#   <subcommand> …` header comment lines; golden regenerated with `bash loomwright/scripts/automate-helpers.sh --help > loomwright/scripts/fixtures/automate-helpers-help.golden` (byte compare `--help`/`-h`/no-arg); `progress-append` adds no ts; the `current_not_set` guard regex `'^([^ ]+ )?(picked |ran /autonomous|owned drain started)'` is unchanged.
- **`loomwright/scripts/emit-lifecycle.sh`** — `trap 'exit 0' EXIT`; `plugin_present` gate (never creates `.supervisor/`); payload-only fields, never invented; `.lifecycle-asked-ids` is ask-only and never shared — `answered` needs its own ledger; debounce applies to `heartbeat` only; every new `payload.get("x")` must exist in a `progress-event-fixtures/spawn-probe-2026-09-02/` fixture (`test-hook-payload-contract.sh`) or be `KNOWN_EXEMPT`.
- **`loomwright/hooks/hooks.json`** — a new `type: command` leaf carries `|| true` (fail-safe emitter); the hook leaf count is a claim checked by `scripts/check-doc-currency.sh` (root `.claude-plugin/README.md`) and `test-build-capabilities.sh` (`loomwright/capabilities.json`, regenerate with `build-capabilities.sh`, CI gate `--check`); `docs/HOOKS.md` row `| Hook | Trigger | Location | Validation |`.
- **`loomwright/scripts/hook-dispatch-on-pr-create.sh`** — ALWAYS exit 0, `set -u`, log to stderr; gate order unchanged; it resolves NO session log today (cwd-relative paths) — the `pr_created` append must resolve the log the way `emit-lifecycle.sh` does and never alter dispatch; existing `pr_created` consumers read `{event, url}` (`orca-mirror.sh` `.url // .pr_url`; `build-floor.sh` needs `has("ts")`).
- **`scripts/ci-local.sh`** — stdout line 1 and the last line are `ci-local: log <path>` (`test-ci-local.sh` pins): the 3d header line goes into the LOG FILE only, right after `open_log`'s line 1; log name glob `<key>-<ts>-<pid>.log`; `--last` reads the last non-empty line (`PASS`…`result NOT cached` / `PASS` / `FAIL` / INCOMPLETE); `--wait` never uses pgrep, exit 3 while running; stamp `$state/pass/$key` written only when the key is unchanged, removed on FAIL; gate regex derives ANY `bash scripts/<x>.sh` ci.yml line as a gate.
- **`loomwright/scripts/run-self-tests.sh`** — markers parsed with `grep -qx`; no-arg globs `(loomwright/scripts/test-*.sh loomwright/scripts/adapters/*/test-*.sh)` appear verbatim in both it and `ci-local.sh` (`test-ci-local.sh` (W)); a missing rc file is a failure (`no-result`); end report order unchanged; pinned strings `FAIL (exit 3): …`, `1 concurrently (4 at a time), then 1 serially`, TIMEOUT lines, `all 2 self-tests passed`, `(6 at a time)`.
- **`.github/workflows/ci.yml`** — `test-run-self-tests.sh` (W) needs `bash loomwright/scripts/run-self-tests.sh` and a 4-space-indented job-level `timeout-minutes:`; `test-ci-local.sh` (W) needs `bash scripts/test-ci-local.sh` + `bash loomwright/scripts/build-capabilities.sh --check`; `test-check-vendor-coupling.sh` case14a–f pin the vendor step's fetch refspec, env and no `|| true`; `test-read-playwright-pin.sh` (W) reads from `id: pw-pin` to `read-playwright-pin.sh` under `set -euo pipefail`; meta-sync pull stays AFTER any test step in its job; inserted lines shift pinned `ci.yml:NN` citations (`test-citation-drift.sh`).
- **`loomwright/scripts/test-*.sh` generally** — first executable line sources `hermetic-test-env.sh` (`scripts/check-test-hermetic.sh`); `test-suite-helpers-defined.sh` flags calls named `assert*|ok|no|pass|fail|check*|expect*|require*` not defined in the same file (wait-lib names avoid those prefixes); mutation controls run against COPIES gated non-empty + differs + `bash -n`; `test-automate-trail.sh` ends with a `_tally_ok/_tally_no` cross-check a split file must copy.
- **`scripts/check-vendor-coupling.sh`** — fail-CLOSED, no third state, no `|| true`; one awk leftmost-longest counter (`scan()`) — the detail block reuses it; `BASE_REF=${VENDOR_COUPLING_BASE:-origin/main}`; under `VENDOR_COUPLING_REQUIRE_BASE=1` a missing base is an ERROR; `test-check-vendor-coupling.sh` case15 asserts the live run exits 0 and prints `files scanned:`, `per token class`, `TOTAL (flat)`, `sdk_binding=`.
- **`loomwright/docs/vendor-coupling-manifest.json`** — every touched core file is AT its allowance (`emit-lifecycle.sh` 13, `hook-dispatch-on-pr-create.sh` 2, `build-insights.sh` 5, `automate-helpers.sh` 5, `wait-for-checks.sh` 2, `HOOKS.md` 50, `agent-lifecycle-jsonl.md` 22, `automate-loop/SKILL.md` 18, `insights.md` 7, `test-emit-lifecycle.sh` 8): write vendor-neutral prose; a raise needs an `allowance_reasons` entry and lands only in Subtask 7.
- **`loomwright/docs/prompt-token-budgets.json`** — live `check-token-budget.sh` measurements at base (the JSON `measured` fields are frozen raise-time values): worker 8436/9062 (626 headroom), launch-pad 43259/45940, plan-reviewer 10371/11300, review-pr 39304/43235; a breach is raised per `raise_rule` with the `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" mirror row and a raise-log paragraph — Subtask 7 only.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Part IQ01 (worker) — self-review stage, `self_review` validator rule, checklist class, maxTurns raise | AC-IQ01a, AC-IQ01b, AC-IQ01d (maxTurns + ARCH timeout row), AC-IQ01f | 15 modify, 0 create | quality-checklist, unit-testing | LAUNCHABLE |
| 2 | Part IQ01 (plan) — `## Touched-file invariants` brief section + Plan Reviewer criterion 18 | AC-IQ01c | 7 modify, 0 create | supervisor-readiness | LAUNCHABLE |
| 3 | Parts T01 → T03 — `drain-subfloor-decision.sh`, then resumable `wait-for-checks.sh` + skill loop on `CONTINUE` + retention row | AC-T01, AC-T03 | 11 modify, 2 create | review-heal, unit-testing | BLOCKED (by #1) |
| 4 | Part T02 — `dismissed-cost` estimator, pinned re-drain lines, fix-now cost in the prompt | AC-T02 | 7 modify, 0 create | automate-loop, unit-testing | LAUNCHABLE |
| 5 | Parts IQ01 (metric) → T04 — findings-per-item fields, then emitters 3a–3d, `phase-timing.sh` reader, replay fixtures, `item_timing`, `/insights` wall-clock | AC-IQ01e, AC-T04 | 27 modify, 3 create | self-heal-advisory, state-management, unit-testing | BLOCKED (by #1, #2, #4) |
| 6 | Parts T05 → T06 → T07 → T08 — ci-local early phase, serial tail removed, fixed-sleep races + ratchet, sharded CI | AC-T05, AC-T06, AC-T07, AC-T08 | 16 modify, 4–6 create | ci-cd, unit-testing | BLOCKED (by #5) |
| 7 | Part T09 + reconciliation — vendor-coupling detail block, then budgets, skill versions + SKILLS_INDEX, manifest, capabilities.json, changelog fragment, full ci-local | AC-T09, AC-MERGED, AC-IQ01d (budgets) | 10–14 modify, 1 create | quality-checklist, unit-testing | BLOCKED (by #2, #3, #6) |

**Execution note (each subtask spans several Parts) — ONE continuous worker run per subtask:** the Supervisor runs Phase 3 inline on the main thread (an Execute Manager subagent cannot spawn workers) and spawns exactly ONE worker per subtask. The spawn prompt tells the worker to do its Parts in the order the title lists (e.g. Subtask 6: T05, then T06, then T07, then T08) in ONE continuous run: before starting each Part it re-reads that Part from the source requirement; after finishing it writes `.supervisor/evidence/iq02/<part>.md` in the MAIN checkout (an on-disk progress marker carrying that Part's evidence) and moves straight on — no intermediate stop (the installed `validate-worker-result.py` SubagentStop hook blocks any worker stop that lacks a WORKER_RESULT). It emits exactly ONE `WORKER_RESULT` after its LAST Part (`completed`, or `partial` with a real `outputs_gap`), so the `outputs_verified` gate and Code Review run once per subtask. SendMessage is used ONLY for the approved turn-limit resume (`agents/execute-manager.md` `ended_without_result` / `rejected_stops` path): the resume message names the first Part that has no evidence file, so a resume is correct however the turn-limit stop was handled. Single-Part subtasks (2, 4) are ordinary one-shot workers.

## Subtask Contracts

```yaml
# Subtask 1 — Part IQ01 (worker)
provides:
  - {kind: "symbol", path: "loomwright/agents/worker.md", name: "self_review"}
  - {kind: "symbol", path: "loomwright/scripts/validate-worker-result.py", name: "self_review"}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/worker-result.md", name: "self_review"}
  - {kind: "symbol", path: "scripts/check-contract-parity.sh", name: "self_review"}
  - {kind: "symbol", path: "loomwright/skills/quality-checklist/SKILL.md", name: "own conventions"}
requires: []
lanes:
  - "loomwright/agents/worker.md"
  - "loomwright/scripts/validate-worker-result.py"
  - "loomwright/docs/result-schemas/worker-result.md"
  - "loomwright/docs/RESULT_SCHEMAS.md"
  - "scripts/check-contract-parity.sh"
  - "loomwright/scripts/test-check-contract-parity.sh"
  - "loomwright/scripts/test-result-validators.sh"
  - "loomwright/scripts/result-validator-fixtures/*"
  - "loomwright/scripts/test-progress-state.sh"
  - "loomwright/scripts/test-worker-rule-selfcheck.sh"
  - "loomwright/scripts/progress-event-fixtures/**"
  - "loomwright/skills/quality-checklist/SKILL.md"
  - "loomwright/agents/execute-manager.md"
  - "loomwright/skills/async-orchestration/SKILL.md"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
external_requires:
  - "a scratch clone of the repo at 87f2205 (PR #435 pre-review commit, base 9a65ecb) for the AC-IQ01f replay"

# Subtask 2 — Part IQ01 (plan)
provides:
  - {kind: "symbol", path: "loomwright/skills/supervisor-readiness/SKILL.md", name: "## Touched-file invariants"}
  - {kind: "symbol", path: "loomwright/agents/plan-reviewer.md", name: "## 18 Review Criteria"}
  - {kind: "symbol", path: "loomwright/agents/launch-pad.md", name: "Touched-file invariants"}
  - {kind: "symbol", path: "loomwright/commands/launch-pad.md", name: "Touched-file invariants"}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/plan-review-result.md", name: "touched_file_invariants"}
requires: []
lanes:
  - "loomwright/agents/launch-pad.md"
  - "loomwright/commands/launch-pad.md"
  - "loomwright/agents/plan-reviewer.md"
  - "loomwright/skills/supervisor-readiness/SKILL.md"
  - "loomwright/docs/result-schemas/plan-review-result.md"
  - "loomwright/docs/POINTER_AUDIT.md"
  - "loomwright/scripts/test-rule-conformance-seam.sh"
external_requires: []

# Subtask 3 — Parts T01 then T03
provides:
  - {kind: "file", path: "loomwright/scripts/drain-subfloor-decision.sh"}
  - {kind: "file", path: "loomwright/scripts/test-drain-subfloor-decision.sh"}
  - {kind: "symbol", path: "loomwright/skills/review-heal/SKILL.md", name: "drain-subfloor-decision.sh"}
  - {kind: "symbol", path: "loomwright/commands/review-pr.md", name: "drain-subfloor-decision.sh"}
  - {kind: "symbol", path: "loomwright/scripts/wait-for-checks.sh", name: "CONTINUE sha="}
  - {kind: "symbol", path: "loomwright/skills/review-heal/SKILL.md", name: "--call-max"}
  - {kind: "symbol", path: "loomwright/scripts/retention-sweep.sh", name: "check-wait"}
# serialization edge for the shared loomwright/docs/ARCHITECTURE_CONTRACTS.md (no data consumed)
requires:
  - {from: "1", kind: "symbol", path: "loomwright/docs/result-schemas/worker-result.md", name: "self_review"}
lanes:
  - "loomwright/scripts/drain-subfloor-decision.sh"
  - "loomwright/scripts/test-drain-subfloor-decision.sh"
  - "loomwright/skills/review-heal/SKILL.md"
  - "loomwright/agents/review-pr.md"
  - "loomwright/commands/review-pr.md"
  - "loomwright/docs/result-schemas/review-heal-result.md"
  - "loomwright/scripts/test-rules-gate-seams.sh"
  - "loomwright/scripts/wait-for-checks.sh"
  - "loomwright/scripts/test-wait-for-checks.sh"
  - "loomwright/docs/PITFALLS.md"
  - "loomwright/scripts/retention-sweep.sh"
  - "loomwright/scripts/test-retention-sweep.sh"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
external_requires: []

# Subtask 4 — Part T02
provides:
  - {kind: "symbol", path: "loomwright/scripts/automate-dismissed.sh", name: "dismissed-cost"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "dismissed-cost"}
  - {kind: "symbol", path: "loomwright/scripts/fixtures/automate-helpers-help.golden", name: "dismissed-cost"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/SKILL.md", name: "fix_now_cost"}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/automate-run.md", name: "owned drain started (fix-now re-drain)"}
requires: []
lanes:
  - "loomwright/scripts/automate-dismissed.sh"
  - "loomwright/scripts/test-automate-dismissed.sh"
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/fixtures/automate-helpers-help.golden"
  - "loomwright/skills/automate-loop/SKILL.md"
  - "loomwright/commands/automate.md"
  - "loomwright/docs/result-schemas/automate-run.md"
external_requires: []

# Subtask 5 — Parts IQ01 (metric) then T04
provides:
  - {kind: "symbol", path: "loomwright/skills/self-heal-advisory/SKILL.md", name: "heal_first_decision"}
  - {kind: "symbol", path: "loomwright/scripts/validate-supervisor-result.py", name: "heal_new_findings"}
  - {kind: "symbol", path: "loomwright/scripts/emit-lifecycle.sh", name: "answered"}
  - {kind: "symbol", path: "loomwright/hooks/hooks.json", name: "answered || true"}
  - {kind: "symbol", path: "loomwright/scripts/hook-dispatch-on-pr-create.sh", name: "pr_created"}
  - {kind: "symbol", path: "scripts/ci-local.sh", name: "ci-local: head "}
  - {kind: "file", path: "loomwright/scripts/phase-timing.sh"}
  - {kind: "file", path: "loomwright/scripts/test-phase-timing.sh"}
  - {kind: "symbol", path: "loomwright/scripts/automate-trail.sh", name: "item_timing"}
  - {kind: "symbol", path: "loomwright/scripts/build-insights.sh", name: "## Wall-clock"}
requires:
  - {from: "1", kind: "symbol", path: "scripts/check-contract-parity.sh", name: "self_review"}
  - {from: "4", kind: "symbol", path: "loomwright/scripts/automate-dismissed.sh", name: "dismissed-cost"}
# ordering edge — owner §"Internal ordering": T04 after the Part IQ01 subtasks (plural); no data consumed
  - {from: "2", kind: "symbol", path: "loomwright/agents/plan-reviewer.md", name: "## 18 Review Criteria"}
lanes:
  - "loomwright/skills/self-heal-advisory/SKILL.md"
  - "loomwright/agents/supervisor.md"
  - "loomwright/docs/result-schemas/supervisor-result.md"
  - "loomwright/scripts/validate-supervisor-result.py"
  - "scripts/check-contract-parity.sh"
  - "loomwright/scripts/test-check-contract-parity.sh"
  - "loomwright/scripts/test-result-validators.sh"
  - "loomwright/scripts/result-validator-fixtures/*"
  - "loomwright/skills/state-management/SKILL.md"
  - "loomwright/scripts/emit-lifecycle.sh"
  - "loomwright/scripts/test-emit-lifecycle.sh"
  - "loomwright/hooks/hooks.json"
  - "loomwright/docs/HOOKS.md"
  - "loomwright/docs/result-schemas/agent-lifecycle-jsonl.md"
  - "loomwright/docs/result-schemas/session-end-jsonl.md"
  - "loomwright/scripts/progress-event-fixtures/**"
  - "loomwright/scripts/hook-dispatch-on-pr-create.sh"
  - "loomwright/scripts/test-hook-dispatch-on-pr-create.sh"
  - "loomwright/scripts/automate-dismissed.sh"
  - "loomwright/scripts/test-automate-dismissed.sh"
  - "scripts/ci-local.sh"
  - "scripts/test-ci-local.sh"
  - ".claude-plugin/README.md"
  - "loomwright/capabilities.json"
  - "loomwright/scripts/phase-timing.sh"
  - "loomwright/scripts/test-phase-timing.sh"
  - "loomwright/scripts/fixtures/phase-timing/**"
  - "loomwright/scripts/automate-trail.sh"
  - "loomwright/scripts/test-automate-trail.sh"
  - "loomwright/scripts/build-insights.sh"
  - "loomwright/scripts/test-insights.sh"
  - "loomwright/commands/insights.md"
  - "loomwright/docs/result-schemas/automate-run.md"
  - "loomwright/skills/automate-loop/SKILL.md"
external_requires:
  - "PostToolUse[AskUserQuestion] payload shape — live probe not run (denied); pair by tool_use_id when present, else by order, and say so"
  - "the gitignored replay inputs in the MAIN checkout: .supervisor/automate/automate-2026-10-08-121222.md, .supervisor/logs/auto-2026-10-08-123152.jsonl, .supervisor/logs/33e9ed8c-64ae-4ee8-8563-8468e749516f.jsonl (copied, trimmed, into the committed fixture dir)"

# Subtask 6 — Parts T05 then T06 then T07 then T08
provides:
  - {kind: "symbol", path: "loomwright/scripts/run-self-tests.sh", name: "run-self-tests: early"}
  - {kind: "symbol", path: "loomwright/scripts/run-self-tests.sh", name: "--select-marked"}
  - {kind: "symbol", path: "loomwright/scripts/test-citation-drift.sh", name: "# run-self-tests: early"}
  - {kind: "file", path: "loomwright/scripts/wait-lib.sh"}
  - {kind: "file", path: "loomwright/scripts/test-wait-lib.sh"}
  - {kind: "file", path: "loomwright/scripts/test-no-fixed-sleep-race.sh"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-lanes.sh", name: "wait_for_file_content"}
  - {kind: "symbol", path: "loomwright/scripts/run-self-tests.sh", name: "--shard"}
  - {kind: "symbol", path: ".github/workflows/ci.yml", name: "fail-fast: false"}
requires:
  - {from: "5", kind: "symbol", path: "scripts/ci-local.sh", name: "ci-local: head "}
  - {from: "5", kind: "symbol", path: "loomwright/scripts/automate-trail.sh", name: "item_timing"}
lanes:
  - "scripts/ci-local.sh"
  - "scripts/test-ci-local.sh"
  - "loomwright/scripts/run-self-tests.sh"
  - "loomwright/scripts/test-run-self-tests.sh"
  - "loomwright/scripts/test-automate-helpers-dispatch.sh"
  - "loomwright/scripts/test-citation-drift.sh"
  - "AGENT_GUIDELINES.md"
  - "loomwright/scripts/test-ci-slot.sh"
  - "loomwright/scripts/test-build-floor.sh"
  - "loomwright/scripts/test-harvest-conventions.sh"
  - "loomwright/scripts/test-automate-trail.sh"
  - "loomwright/scripts/test-automate-trail-closeout.sh"
  - "loomwright/scripts/test-automate-trail-merge-watch.sh"
  - ".github/workflows/ci.yml"
  - "loomwright/scripts/wait-lib.sh"
  - "loomwright/scripts/test-wait-lib.sh"
  - "loomwright/scripts/test-no-fixed-sleep-race.sh"
  - "loomwright/scripts/test-automate-lanes.sh"
  - "loomwright/scripts/test-setup-ui.sh"
  - "loomwright/scripts/test-token-ledger.sh"
  - "loomwright/scripts/test-setup-memory.sh"
  - "loomwright/scripts/fixtures/self-test-weights.tsv"
external_requires:
  - "GitHub Actions matrix + needs/if: always() semantics; branch protection required context `ci` (read-only — never changed)"
# Lanes note: T07's guard records every other test file's current count in its baseline WITHOUT editing it; only the (b)/(c)/(d) sites the Part names are edited or annotated.

# Subtask 7 — Part T09, then reconciliation (Merged-item rules 1–5)
provides:
  - {kind: "symbol", path: "scripts/check-vendor-coupling.sh", name: "base unavailable"}
  - {kind: "symbol", path: "AGENT_GUIDELINES.md", name: "check-vendor-coupling.sh"}
  - {kind: "file", path: "changelog.d/iq01-throughput-merged.md"}
  - {kind: "symbol", path: "changelog.d/iq01-throughput-merged.md", name: "bump: minor"}
  - {kind: "symbol", path: "loomwright/docs/prompt-token-budgets.json", name: "implementation-quality/02"}
requires:
  - {from: "2", kind: "symbol", path: "loomwright/agents/plan-reviewer.md", name: "## 18 Review Criteria"}
  - {from: "3", kind: "symbol", path: "loomwright/scripts/retention-sweep.sh", name: "check-wait"}
  - {from: "6", kind: "symbol", path: "loomwright/scripts/run-self-tests.sh", name: "--shard"}
lanes:
  - "scripts/check-vendor-coupling.sh"
  - "scripts/test-check-vendor-coupling.sh"
  - "AGENT_GUIDELINES.md"
  - "changelog.d/iq01-throughput-merged.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "loomwright/skills/SKILLS_INDEX.md"
  - "loomwright/skills/*/SKILL.md"
  - "loomwright/capabilities.json"
  - "loomwright/agents/*.md"
  # post-merge re-check of Subtask 3 tests vs Subtask 6 baselines (Risk Assessment); both are ancestors of 7
  - "loomwright/scripts/test-drain-subfloor-decision.sh"
  - "loomwright/scripts/test-wait-for-checks.sh"
  - "loomwright/scripts/test-retention-sweep.sh"
  - "loomwright/scripts/test-no-fixed-sleep-race.sh"
  - "loomwright/scripts/fixtures/self-test-weights.tsv"
external_requires:
  - "a scratch worktree at fe64cff (tree b8f9698, PR #435's first red tree) with base 9a65ecb for the T09 Validation-3 replay"
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 3, Subtask 5
Subtask 2, Subtask 4 ──→ Subtask 5
Subtask 5 ──→ Subtask 6
Subtask 2, Subtask 3, Subtask 6 ──→ Subtask 7
```
(Edges from `requires.from`: 3←1; 5←1,2,4; 6←5; 7←2,3,6. The 5←2 edge carries no data — it honours the owner's §"Internal ordering" rule "Part T04 after the Part IQ01 subtasks". Subtask 7 is reachable from every subtask.)

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| 1 | 3 | `loomwright/docs/ARCHITECTURE_CONTRACTS.md` | YES (3 requires 1) |
| 1 | 5 | `scripts/check-contract-parity.sh`, `loomwright/scripts/test-check-contract-parity.sh`, `test-result-validators.sh`, `result-validator-fixtures/*`, `progress-event-fixtures/**` | YES (5 requires 1) |
| 1, 3 | 7 | `loomwright/docs/ARCHITECTURE_CONTRACTS.md`; 1/7 `loomwright/skills/*/SKILL.md`, `loomwright/agents/*.md` | YES (7 requires 3 ← 1) |
| 2 | 7 | `loomwright/agents/*.md`, `loomwright/skills/*/SKILL.md` (glob) | YES (7 requires 2) |
| 3 | 7 | `loomwright/skills/review-heal/SKILL.md`, `loomwright/agents/review-pr.md` (via globs); `test-drain-subfloor-decision.sh`, `test-wait-for-checks.sh`, `test-retention-sweep.sh` (re-check) | YES (7 requires 3) |
| 6 | 7 (re-check) | `test-no-fixed-sleep-race.sh`, `fixtures/self-test-weights.tsv` | YES (7 requires 6) |
| 4 | 5 | `automate-dismissed.sh`, `test-automate-dismissed.sh`, `automate-loop/SKILL.md`, `automate-run.md` | YES (5 requires 4) |
| 5 | 6 | `scripts/ci-local.sh`, `scripts/test-ci-local.sh`, `loomwright/scripts/test-automate-trail.sh` | YES (6 requires 5) |
| 5 | 7 | `loomwright/capabilities.json`, `loomwright/skills/*/SKILL.md` (glob) | YES (7 requires 6 ← 5) |
| 6 | 7 | `AGENT_GUIDELINES.md` | YES (7 requires 6) |
| 1, 2, 4 | each other | none | NO |
| 2, 3, 4 | each other | none | NO |

### Batch Plan
- **Batch 1:** Subtasks 1, 2, 4 (parallel — empty `requires`, zero overlap)
- **Batch 2:** Subtask 3 (after 1), Subtask 5 (after 1, 2, 4) — parallel, zero overlap
- **Batch 3:** Subtask 6 (after 5)
- **Batch 4:** Subtask 7 (after 2, 3, 6)
- **Recommended workers:** 3
- **Estimated batches:** 4

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md` |
| 2 | `skills/supervisor-readiness/SKILL.md` |
| 3 | `skills/review-heal/SKILL.md`, `skills/unit-testing/SKILL.md` |
| 4 | `skills/automate-loop/SKILL.md`, `skills/unit-testing/SKILL.md` |
| 5 | `skills/self-heal-advisory/SKILL.md`, `skills/state-management/SKILL.md`, `skills/unit-testing/SKILL.md` |
| 6 | `skills/ci-cd/SKILL.md`, `skills/unit-testing/SKILL.md` |
| 7 | `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Scope: ~95 files / 10 Parts in one PR (Feasibility check 4) | HIGH | `context-bound` split into 7 subtasks (Criterion 4 cap), each run by ONE continuous worker with per-Part evidence files and one final WORKER_RESULT (see Subtask Structure execution note); each worker reads ONLY its Part(s) from the source requirement; evidence per Part written to `.supervisor/evidence/iq02/<part>.md` in the MAIN checkout for the PR body |
| Worker turn exhaustion (installed worker `maxTurns: 40`; pa/24 needed 82 tool calls) | HIGH | One continuous worker per subtask (execution note) writing a per-Part evidence file as it goes; an out-of-turns worker is resumed by SendMessage naming the first Part with no evidence file (hard stop-and-report), never respawned; ONE final WORKER_RESULT per subtask |
| Per-subtask verification vs once-only reconciliation (Merged rules 3–5) | MEDIUM | Each subtask verifies with its own tests + `bash scripts/ci-local.sh --affected`; `check-token-budget.sh`, `check-vendor-coupling.sh` and `check-skills-index-sync.sh` breaches caused only by deferred reconciliation are listed in `not_verified`, not fixed per subtask; prose stays vendor-neutral (prefer removing a token over a raise); Subtask 7 runs the ONE full `bash scripts/ci-local.sh` (backgrounded, `--wait` until exit ≠ 3) |
| T04 3a live payload probe could not run (temporary `.claude/settings.local.json` hook denied by the auto-mode classifier) | MEDIUM | Evidence on disk: `PreToolUse[AskUserQuestion]` payloads carry `tool_use_id` (`emit-lifecycle.sh` already consumes it); `fixtures/posttooluse-gh-pr-create.json` shows `PostToolUse` carrying `tool_use_id`. Emitter pairs by `tool_use_id` when present, else by order, and the PR body says the live probe is an operator follow-up |
| T08 real-CI probes (red shard ⇒ `ci` fails; dropped manifest ⇒ fails) need throwaway pushed commits | MEDIUM | Done AFTER the PR exists, by the drain/operator on the PR branch with revert before merge; locally covered by `test-run-self-tests.sh` / fixture ci.yml arms; flagged in PR body until run |
| T06 measurements (10× loaded pool, ≤ 540 s full run) and T05 forced early-red timing need an idle machine | MEDIUM | Measure, record numbers + log paths; a marker whose repair is not proven stays with a written reason + rate (AC allows it) — never unmarked on hope |
| `test-rules-gate-seams.sh` pins inside the §U4 branch Subtask 3 replaces | MEDIUM | Keep the pinned lines verbatim (as the documented mirror of the script's `decide` table) or move pins + mutants in the same commit |
| WORKER_RESULT `schema_version` rule vs a new required field | MEDIUM | Subtask 1 decides explicitly (bump with consumers, or keep 2 with consistent justification) and records why — reviewer checks it |
| Hook leaf count claims (README, capabilities.json) drift when 3a adds a leaf | MEDIUM | Subtask 5 updates the README count lines and regenerates `capabilities.json` in the same change; Subtask 7 re-runs `build-capabilities.sh --check` after all prompt edits |
| Prior churn (postmortem ledger): ARCHITECTURE_CONTRACTS.md (42), RESULT_SCHEMAS.md (41), `.claude-plugin/README.md` (39), SKILLS_INDEX.md (38), agents/supervisor.md (21); classes drain_churn, convention_mismatch, self_heal_churn; `self_heal_miss` seen | HIGH | Workers grep the OLD value repo-wide on every count/version/budget/section change (green doc-currency is necessary, not sufficient); SKILLS_INDEX is generated only by `check-skills-index-sync.sh --write` in Subtask 7 |
| `test-automate-trail.sh` touched by Subtasks 5 and 6 (6 may split it in its T06 pass) | MEDIUM | Strict DAG order 5 → 6; T07 pass edits the post-split files; assertion union preserved |
| Subtask 3 and Subtask 6 are unordered: 3's new/edited tests (`test-drain-subfloor-decision.sh`, `test-wait-for-checks.sh`, `test-retention-sweep.sh`) are invisible to 6's T07 `test-no-fixed-sleep-race.sh` baseline, T05 early set and T08 shard list/weights | MEDIUM | Subtask 7 (after both) re-runs `test-no-fixed-sleep-race.sh`, `run-self-tests.sh --list`/shard-union check and the T08 weights/manifest check on the merged tree, and fixes or `# fixed-sleep-ok:`-annotates any Subtask 3 test site there (Subtask 7's lanes add exactly those three test files plus `test-no-fixed-sleep-race.sh` and `fixtures/self-test-weights.tsv` for this re-check — no other test file) |
| `ci.yml` line insertions shift pinned `ci.yml:NN` citations | LOW | `test-citation-drift.sh` is early-marked in Subtask 6's T05 pass and re-run in its T06/T08 passes after every ci.yml edit; anchors re-derived |

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

## Configuration
- **Workers:** 3
- **Mode:** parallel
- **Estimated batches:** 4
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-09-iq01-throughput-merged.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-10-09T14:11:40Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/440
- **Branch:** feature/iq02-iq01-throughput-merged
- **Files changed:** 97
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** 7 subtasks (IQ01, T01–T09) merged into one PR; full ci-local PASS 531 s (145/145) pre-heal; 3 heal rounds each fixed every HIGH (phase-timing hang, sleep-ratchet leak, closeout idempotence, wait-line split); final fix 7a89c8f not LLM-re-reviewed. Ground truth 2/2 pass; benchmark pass; risk high (advisory).

## Not verified
- **AC-IQ01f catch rate** — executed replay 8/11 (8/8 judgeable at 87f2205); owner-scored as met; not blind (subtask 1)
- **Plan Reviewer Criterion 18 live behaviour** — prompt text pinned only, no live probe (subtask 2)
- **Live until-mergeable drain with ≥2 foreground waits on one SHA** — needs a real PR drain (subtask 3)
- **Live interactive park showing fix-now cost** — post-merge operator validation (subtask 4)
- **Question tool post-call hook live payload** — tool_use_id pairing unverified live (subtask 5)
- **Real /automate item_timing with exact owner intervals** — needs a live run after merge (subtask 5)
- **Real-CI red-shard and dropped-manifest probes** — post-push operator evidence; local (AG) arms cover it (subtask 6)
- **GitHub sdk-spike step on this tree** — runs only in CI (subtask 7)
