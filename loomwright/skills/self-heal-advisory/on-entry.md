# Self-Heal Protocol — Phase 4.5 entry (on-entry actions, first-iteration enrichments)

Read by the Supervisor at Phase 4.5 entry, before the first Code Reviewer spawn; not needed again on later iterations. Part of `skills/self-heal-advisory/` (index and the HARD ADVISORY CONTRACT that governs every enrichment here: `SKILL.md`). Steps 1g (deviations) and 1h (module shape), both every iteration, live in `SKILL.md` Part 1.

## On-entry actions (steps 1–5)

**On-entry actions:**
1. Progress state (session phase) is not written here — it is derived by the hook-triggered `scripts/emit-progress-event.sh` + `scripts/build-state.sh` projector. See `docs/TELEMETRY.md`.
1a. Confirm the protocol read: `skills/self-heal-advisory/SKILL.md` and this file were Read at phase entry (the Phase 4.5 stanza in `agents/supervisor.md` mandates it). The other split files are Read only at the step that names them (`SKILL.md`'s index).
1b/1d. *(Retired with the graphify tier; the letters stay so references to steps 1c / 1e remain valid.)*
1c. **Prior-churn advisory (pre-review enrichment — ADVISORY ONLY, fail-safe):** run §"Prior-churn advisory (pre-review enrichment)" below to compute the `prior_churn` summary BEFORE the review-and-fix loop, passing the touched paths as **command-line ARGUMENTS** (never stdin); **skip silently on empty output** (the reviewer prompt then omits the enrichment line). `prior_churn` NEVER changes `heal_decision`, NEVER drives the fix task (the corpus is fed to the REVIEW lens ONLY, never to workers/fixers), and NEVER gates or blocks the PR. It is threaded into the `code-reviewer` Task prompt in the review-and-fix loop (`SKILL.md` Part 2) as advisory context.
1e. **House-rules advisory (committed convention enrichment — pre-review enrichment, ADVISORY ONLY, fail-safe):** run §"House-rules advisory (committed convention enrichment)" below — a sibling to step 1c on the SAME touched-file scope — to compute `house_rules` BEFORE the review-and-fix loop: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-rules.sh" <touched files...> --with-ids`, the paths as **command-line ARGUMENTS** (never stdin), the output kept VERBATIM (ids included), never summarized; **skip silently on empty output**. **Run it UNCONDITIONALLY like step 1c** — `read-rules.sh` self-gates on `.agent/rules/*.json`. Advisory and non-gating, fed to the REVIEW lens only; each rule's `check` is DATA, NEVER executed. Threaded as the **HOUSE-RULES ADVISORY** line, only when `house_rules` is non-empty.
1f. **Brief-conformance advisory (acceptance-criteria enrichment — pre-review enrichment, ADVISORY ONLY, fail-safe):** run §"Brief-conformance advisory (acceptance-criteria enrichment)" below — a sibling to steps 1c and 1e — to compute `brief_conformance` BEFORE the review-and-fix loop from the in-progress brief at `brief_path`: its `## Acceptance Criteria` bullets (checkbox prefix stripped) plus its `## Outcomes Rubric` bullets when present, bounded by **the cap in Part 1** (do NOT restate the number here). **Skip silently on the three skip conditions: (1) no `brief_path` (a direct `/supervisor task:` run — this step must not error), (2) no `## Acceptance Criteria` section, (3) zero bullets parse.** `record_decision(phase: SELF_HEAL, decision: "brief_conformance: {non-empty | empty}", …)` on every path. No new gate and no new schema field (R1); fed to the REVIEW lens only; **unlike 1c/1e the reviewer's response IS ordinary `category: new` / HIGH findings (R2)** through the existing gate and fix selection. Threaded as the **BRIEF-CONFORMANCE ADVISORY** line, directly after the HOUSE-RULES ADVISORY line, only when non-empty.
1g. **Deviations advisory** — runs here AND on every later iteration: `SKILL.md` Part 1 §"Deviations advisory (worker- and fixer-recorded plan drift)", step 1g.
1h. **Module-shape advisory** — runs here AND on every later iteration: `SKILL.md` Part 1, step 1h.
2. **Initialize invariant tracking:**
   - `skip_self_heal_requested` — set from INIT-parsed flags (true iff `--skip-self-heal` was passed on the command line). Set once here, never mutated.
   - `STACKED` — `true` iff `BASE_BRANCH` differs from the repo's own base, the stdout of the plugin's `scripts/resolve-base-branch.sh --repo .` run with no `--flag` and no `--brief` (a `/autonomous` iteration N+1 based on iteration N's branch reads `true`; a run on a repo whose base is `development` reads `false`). A non-zero exit there ⇒ `false` (the holistic review). Set once here and threaded beside `BASE_BRANCH` into the review and grading prompts; base names are never compared against a literal `main`.
   - `phase45_review_invoked` — initialize to `false`. Flip to `true` only when the `code-reviewer` Task call below actually executes (first iteration of the review-and-fix loop).
   - `red_team_advisory` — initialize to `"disabled"` HERE, BEFORE the resume-thrash / `--skip-self-heal` early-jump checks below, so the completion-tail Outcome line always has a value even when this phase is bypassed and the Advisory red-team lens (further down) never runs. The lens overrides this to `ran` / `skipped_low_risk` / `error` (or re-affirms `disabled`) when it executes; on a bypass path it remains `"disabled"` (lens never ran).
3. **Resume-thrash guard (if this is a `--continue` run landing in SELF_HEAL):**
   - `Context-Keeper(operation: record_self_heal_resume, increment: true)` → reads the returned count
   - This is the ONLY place the resume counter is incremented: exactly once, at Phase 4.5 entry of a `--continue` run. A pause/crash earlier in the same run does NOT increment — the increment belongs to the next run's entry.
   - If count ≥ 3: abort the loop, mark task `completed_with_escalation` with reason `"self_heal_resume_thrash"`, skip to completion tail with `heal_loop_ran=true, heal_decision=ESCALATED, error: "self_heal_resume_thrash"`. Set `heal_remaining_issues` to the last known open-issue count from state (it may legitimately be 0 — the escalation result is valid because `error` is non-empty, per the SUPERVISOR_RESULT ESCALATED invariant). Do NOT set `phase45_review_invoked=true` based on a prior run's review — that flag tracks only the current run and is not persisted. `red_team_advisory` stays `"disabled"` (initialized in step 2 — the advisory lens lives later in this phase and is bypassed on this early jump).
4. Check `--skip-self-heal` flag: if set, record `record_decision(phase: SELF_HEAL, decision: "loop_skipped", rationale: "--skip-self-heal flag")` and jump to completion tail with `heal_loop_ran=false`. `red_team_advisory` stays `"disabled"` (initialized in step 2; the advisory red-team lens is part of this phase and is bypassed when self-heal is skipped).
5. **Phase 4.5 base-mismatch check (v14.0.0, AC-7 — short-circuits the review-and-fix loop):** before running the heal loop, check whether Phase 4 detected a base-branch mismatch:

   ```
   mismatch = Context-Keeper(operation: get_flag, key: "base_mismatch_detected")
   ```

   If `mismatch` is non-null (Phase 4 set the flag — either real mismatch or `gh pr view` failure under `--non-interactive`): Read `escalation.md` (this skill's directory) and run its §"Phase 4.5 base-mismatch cleanup (step 5)" — it returns from Phase 4.5 without the review-and-fix loop and without the standard completion tail. Null ⇒ continue to the review-and-fix loop in `SKILL.md` Part 2.

---

## Prior-churn advisory (pre-review enrichment)

Runs **at Phase 4.5 entry, BEFORE the first Code Reviewer spawn**, to bias the reviewer toward root-cause classes that **churned before on the touched files** (recurring `self_heal_miss` / root-cause classes / flow stages from the postmortem corpus).

> **HARD ADVISORY CONTRACT — `prior_churn` is advisory input to the REVIEW lens ONLY:** it NEVER changes `heal_decision`, NEVER drives the fix task (the corpus never reaches workers/fixers), never triggers a fix iteration, never blocks the PR. Fail-safe: `read-postmortem.sh` ALWAYS exits 0 and emits EMPTY output on a NO-HIT (no sentinel line), so empty `prior_churn` means "no prior churn" and the line is omitted.
```
# touched files = the same integrated-diff scope the Code Reviewer reviews: the remote-tracking
# ref of the resolved BASE_BRANCH for EVERY base (a stacked iteration's parent branch included) —
# the SAME DIFF-SCOPE OVERRIDE. Never the local BASE_BRANCH ref, which can lag its remote.
touched = paths from the integrated diff (read-only):
          git diff --name-only "origin/$BASE_BRANCH...HEAD"

prior_churn = ""   # advisory summary; empty string when no prior churn (proceed with no enrichment)

# Pass the touched paths as COMMAND-LINE ARGUMENTS (args take precedence — STDIN is NEVER
# read, so an args-bearing call can never block on an open-but-idle pipe in a non-TTY agent
# context). NEVER pipe the paths on stdin. See ${CLAUDE_PLUGIN_ROOT}/scripts/read-postmortem.sh.
if touched is non-empty:
  prior_churn = bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-postmortem.sh" <touched files...>
  # Emits a bounded markdown summary ONLY on a REAL hit; on a NO-HIT, an absent/empty corpus or missing
  # jq it emits NOTHING (no sentinel line) and exits 0. Guard the reviewer-prompt enrichment on
  # `prior_churn` being NON-EMPTY. Do NOT restate the reader's internals here.

record_decision(phase: SELF_HEAL, decision: "prior_churn: {non-empty | empty}", rationale: "advisory pre-review enrichment — heal_decision unchanged, fixers never see the corpus")
```
Threaded into the reviewer prompt as the PRIOR-CHURN ADVISORY line (`SKILL.md` Part 2); not a SUPERVISOR_RESULT field.

---

## House-rules advisory (committed convention enrichment)

A **sibling** of the prior-churn advisory — same point, same touched-file scope, same reviewer prompt — reading the committed **house-rules substrate** (`.agent/rules/*.json`, contract: `skills/rules/SKILL.md`) via `read-rules.sh`.

> **HARD ADVISORY CONTRACT — `house_rules` is advisory input to the REVIEW lens ONLY:** it NEVER changes `heal_decision`, NEVER drives the fix task, never triggers a fix iteration, never blocks the PR; **subordinate to CLAUDE.md — on any conflict, CLAUDE.md wins.** Fail-safe: the reader ALWAYS exits 0 and emits EMPTY output on no valid rule (no sentinel), so empty `house_rules` means "no house rules". The reader emits each rule's `check` as **DATA (text) only — it NEVER executes, evals, sources, or `bash -c`s a `check`**; this seam calls the READER ONLY and NEVER pipes/evals/sources the reader output.

```
# touched files = the same integrated-diff scope as the prior-churn advisory above (the SAME DIFF-SCOPE OVERRIDE).
touched = paths from the integrated diff (read-only):
          git diff --name-only "origin/$BASE_BRANCH...HEAD"

house_rules = ""   # advisory summary; empty string when no valid house rules (proceed with no enrichment)

# Pass the touched paths as COMMAND-LINE ARGUMENTS (args take precedence — STDIN is NEVER read,
# so an args-bearing call can never block on an open-but-idle pipe in a non-TTY agent context).
# NEVER pipe the paths on stdin. read-rules.sh self-gates on .agent/rules/*.json — call it
# UNCONDITIONALLY (NOT wrapped in any "if a rules store is detected" conditional), exactly like
# read-postmortem.sh self-gates on its corpus. See ${CLAUDE_PLUGIN_ROOT}/scripts/read-rules.sh.
#
# PATH ROUTING (the args are a REAL filter): read-rules.sh routes on each rule's `applies_to`, so
# the diff scope passed here DETERMINES which rules come back. A rule with `applies_to: null` (or no
# such key) is repo-wide and always emitted; a rule with a non-empty glob array is emitted only when
# one of these touched paths matches it. Everything ambiguous fails OPEN (malformed `applies_to`, and
# an EMPTY path set, both emit repo-wide) — so a degraded/empty diff can never silently suppress the
# house rules. Pass the paths as ARGS, never stdin. The reader NEVER executes a `check` — checks are
# surfaced as DATA only.
house_rules = bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-rules.sh" <touched files...> --with-ids
  # --with-ids adds each rule's `id:`/`enforcement:` lines: the reviewer answers every rule BY ID
  # (`house_rule_verdicts`, agents/code-reviewer.md step 5c). The flag changes nothing else.
  # On no valid rule (absent substrate / no *.json / all skipped) or missing jq it emits NOTHING and exits 0:
  # guard the reviewer-prompt enrichment on `house_rules` being NON-EMPTY. Do NOT restate the reader's internals here.

record_decision(phase: SELF_HEAL, decision: "house_rules: {non-empty | empty}", rationale: "advisory pre-review enrichment (committed house rules) — heal_decision unchanged, subordinate to CLAUDE.md, fixers never act on it as a gate")
```
Threaded into the reviewer prompt as the **HOUSE-RULES ADVISORY** line — **pasted VERBATIM, every rule the reader emitted** (a paraphrase or subset drops rules the reviewer is never asked about); answered in `house_rule_verdicts` (`SKILL.md` §"House-rule verdicts line"). Not a SUPERVISOR_RESULT field.

---

## Brief-conformance advisory (acceptance-criteria enrichment)

The THIRD pre-review enrichment, same point and prompt: it tells the reviewer **what was asked for** — the in-progress brief's acceptance criteria (plus rubric bullets, orientation only). Owner decisions R1/R2/R4 carried in.

> **HARD ADVISORY CONTRACT — `brief_conformance` is advisory input to the REVIEW lens ONLY:** it NEVER changes `heal_decision` and adds no gate or schema field (R1: `heal_decision` derives ONLY from `CODE_REVIEW_RESULT` plus the deterministic co-gates, `multi-voter.md` §"Delay-vs-decide"), never reaches workers/fixers via this seam, and never blocks the PR on its own. **The one deliberate difference (R2):** the reviewer's response IS ordinary `category: new` / HIGH findings through the existing gate. Subordinate to CLAUDE.md. Fail-safe: every skip condition yields EMPTY output and the prompt omits the line (no sentinel).
```
# Source = the in-progress brief at `brief_path` — the SAME path `run-ground-truth.sh --brief`
# and `parse_rubric(brief_path)` (Part 2 §"Outcomes Rubric grading") already read. There is no
# other source: no brief ⇒ no criteria ⇒ no enrichment.

brief_conformance = ""   # advisory summary; empty string on every skip condition (proceed with no enrichment)

# SKIP CONDITIONS — an explicit ORDERED list, each yielding EMPTY `brief_conformance` SILENTLY
# (record_decision below still runs; nothing errors, nothing is logged as a failure):
#   1. no `brief_path` (or the file at brief_path is unreadable) — a direct `/supervisor task:"..."`
#      invocation without Launch Pad (the same back-compat case the completion tail's "job file is
#      not in `in-progress/`" rule handles);
#   2. the brief has no `## Acceptance Criteria` section;
#   3. the section exists but ZERO bullets parse from it.
if brief_path is set AND the file at brief_path is readable:
  # PARSE RULE (the rubric parser's rule, applied twice):
  #   criteria = every leading-`-` bullet under `## Acceptance Criteria`, read up to the next
  #              `## ` heading; strip a leading `[ ]` / `[x]` checkbox prefix from each bullet.
  #   rubric   = every leading-`-` bullet under `## Outcomes Rubric` when that section is present
  #              (same up-to-the-next-`## `-heading rule); [] when absent.
  if criteria is non-empty:                      # conditions 2 and 3 both land here as empty
    # CAP (stated here ONCE — every other surface says "the cap in Part 1"):
    #   brief_conformance carries at most 25 bullets total — criteria FIRST, then rubric bullets
    #   — and when anything is truncated it ends with the marker `(+N bullets omitted — see brief)`
    #   where N counts ALL omitted bullets (criteria + rubric; rubric bullets are dropped first).
    brief_conformance = "criteria:" + the kept criteria bullets
                      + ("rubric (orientation only):" + the kept rubric bullets, when any survive the cap)
                      + (the omitted-marker, when anything was truncated)

record_decision(phase: SELF_HEAL, decision: "brief_conformance: {non-empty | empty}", rationale: "advisory pre-review enrichment (brief acceptance criteria) — heal_decision unchanged; findings it yields are ordinary category:new findings through the existing gate; fixers never see the brief via this seam")
```
Threaded into the reviewer prompt as the **BRIEF-CONFORMANCE ADVISORY** line, whose wording (`SKILL.md` Part 2) is the authority for the verdicts; not a SUPERVISOR_RESULT field. The standalone `/review-pr` drain has no brief (R4).
