# Supervisor Job: Drain bounding — mechanize the shared ceiling + termination-only severity floor

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (15618 bytes, fresh — rewritten in the v15.21.0 diet)
- **Git:** clean, branch `main` @ `b16414c`
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (two stale `claude/*` agent worktrees pinned at the old tip `9a791e1` — Claude Code's own isolation worktrees, not Supervisor's; outside this lane, do not touch)

## Configuration
- **Base Branch:** main
- **Subtasks:** 1 (Decomposition Threshold default — no split reason fires)
- **Path:** Single-Agent Path (no worktree, no execute-manager)
- **Source requirement:** `.supervisor/requirements/final-state/13-drain-bounding-earned-checks.md`
- **Cost profile:** cheap (Sonnet) — forwarded `/automate → /autonomous → /supervisor`

## Task

**Goal:** Make the declared `--until-mergeable` drain bound actually bind, and stop the drain when nothing *material* remains rather than when nothing at all remains.

### Provenance and the two corrected premises (READ THIS FIRST)

This is a **defect follow-up to shipped step 4 (D4)**, not a new step in `FINAL_STATE_GOAL.md`'s execution order. **Both premises in the source requirement were falsified at Launch Pad Phase 2.5 and the owner picked a corrected direction for each. The brief below supersedes the requirement's own scope wording; where they disagree, this brief wins.**

**F1 — the defect is real, the stated mechanism is not.** The requirement claims `max_rounds` "is enforced inside the `review-pr-runner` agent path" while `/automate`'s inline drain "degrades to honour-system", i.e. two enforcement regimes. **Verified false.** The bound is declared exactly once, in the *shared* loop body: `loomwright/skills/review-heal/SKILL.md:365` (`max_rounds = 5`), the `while rounds < max_rounds` at `:378`, and the exhaustion→`ESCALATED` exit at `:480` — all inside §"Step U4 — The bounded drain loop", which **both** entry paths read. `loomwright/agents/review-pr.md:115` and `loomwright/commands/review-pr.md:31,59` merely **restate** it; neither implements it. The runner's only structural bound is frontmatter `maxTurns: 60` — a *turn* bound, not a *round* bound. So item 04 stopping at 5 and PR #122 running to 7 is **the same prose-only bound obeyed once and not the other time**, not an asymmetry.

> **Consequence — the source AC2 is unsatisfiable as written** ("the asymmetry that produced 5-vs-7 is closed"): there is no asymmetry to close. **Owner decision D2 = mechanize the shared bound** and rewrite AC2 to assert the bound binds on the single path both entries share. Do NOT add a second, inline-only counter — that would *encode* the asymmetry we just established does not exist.

**F2 — the severity floor collides with a deliberate, named anti-pattern.** The floor was not overlooked; it was removed on purpose. `SKILL.md:350`: Validate-Then-Fix *"replaces the old `fixable = actionable BLOCKING/HIGH items` severity floor… A real MEDIUM like #64 must be fixed; the old floor would have silently dropped it."* "There is no severity floor" recurs at `:355`, `:390`, `:412`, and `:661` is a named Anti-Pattern forbidding reinstatement. (The requirement also cites the *wrong* prior artifact to reconcile against — the review-rigor category-based cosmetic-defer rule — rather than the Validate-Then-Fix replacement that actually blocks it.)

> **Owner decision D1 = TERMINATION-ONLY floor.** Validate-Then-Fix stays **byte-for-byte as-is**: every finding, at any stated severity, is still validated and still fixed *within* a round. Nothing is dropped, so #64's lesson holds. The floor governs **only whether to start another round**: a completed round whose findings were all sub-floor terminates `READY` instead of re-scanning. This is genuinely compatible with `:661`, which forbids **dropping** a finding below HIGH — not bounding the number of rounds. It still collapses PR #122's rounds 5–7.

### PINNED SEMANTICS — read this before writing any code (resolves a Plan-Review-1 HIGH)

Plan Review attempt 1 correctly found that the first draft of this brief contained **two mutually exclusive readings** of the floor and pushed the worker toward the wrong one. Exactly one is authorized:

- ✅ **AUTHORIZED — "fix-then-stop" (reading B).** Round N runs Validate-Then-Fix **completely**: every validated finding, at every severity including sub-floor, **is fixed and pushed**. The floor then decides only that round N+1's **re-scan does not start**. No finding is ever declined a fix on severity grounds, so `:350`/`:355`/`:390`/`:412`/`:661` all remain true statements.
- ❌ **FORBIDDEN — "find-then-defer" (reading A).** Round N's scan finds a sub-floor finding, **declines to fix it**, reports it, terminates. This IS the `:661` anti-pattern — #64 was precisely a MEDIUM that had to be *fixed*, and "reported instead of fixed" is the prohibited move wearing a nicer name. Do not implement this.

### WHERE the floor check sits, and what a `sub_floor_converged` termination must STILL do (resolves a Plan-Review-2 HIGH)

Plan Review 2 attacked reading B on request and found a real fail-**open**, which the first draft mis-scoped as merely epistemic. The mechanism, verified against §U4:

READY is tested at **`:430`, at the TOP of a round**, and is only meaningful because `:379-381` ran first for the **current** head SHA (`discover_required_checks` → `wait_for_scoped_checks_to_settle` → `read_all_channels`); `required_failing` is computed at `:388` from that. The fix is pushed at **`:465`** and `rounds += 1` at **`:477`** — the *next* iteration is what re-evaluates against the new commit. A naive reading-B termination stops after `:465` and never re-enters, so:

- **Hole 1 (fail-OPEN on required checks).** `required_failing` was computed against the **pre-fix** SHA. A sub-floor fix that turns `ci` red yields `decision: READY` on a **red PR**. This inverts the bimodal fail-closed invariant CLAUDE.md pins by name. Not hypothetical: PR #122 round 6's finding was a *hardcoded `3` in a header note* — in this repo, editing a hardcoded number is precisely the edit class that trips `check-doc-currency.sh`.
- **Hole 2 (regression detection structurally disabled).** `:469` `repeat_after_fix` and `:493` `repeat_check_failure` can **only** fire on round N+1. Terminating at the end of round N disables both for the final round by construction, and `:476` stores `fingerprints_prev` for a comparison that never happens — so a sub-floor fix that silently regresses something is undetectable *by design*.
- **Hole 3 (earned fallback bypassed).** `:396-399` gates the earned fallback on "a round that would otherwise declare READY", evaluated at the **top**. A floor check wired at the **bottom** never runs `compute_no_review_lens_posted` (`:401`), silently disabling the PR-#117 counter-pressure fallback.

**MANDATORY IMPLEMENTATION SHAPE — split the skipped work; do not skip the whole round.** A `sub_floor_converged` termination MUST still run the **confirming required-check pass** against the **pushed** SHA, and may skip **only** the expensive all-channel bot-finding re-scan + validate pass (`:381-394`). **If the required set is not green (or unreadable) ⇒ `ESCALATED`, never `READY`.**

> **R1 — SHA-BINDING IS LOAD-BEARING; a bare re-run of `:380` does NOT do what that sentence says.** The settle predicate at `:328-331` defines settled as **`in_flight == []`** — the *absence* of pending entries. A check run GitHub **has not yet created** for the just-pushed SHA is not in `rollup`, so not in `scoped`, so not in `in_flight` ⇒ the wait **breaks immediately** and the rollup it read still carries the **prior commit's** `SUCCESS` entries. Verified: **`headRefOid` appears ZERO times in `review-heal/SKILL.md`** — there is no SHA binding anywhere in the drain today. This race exists in the loop now and is *benign* only because a stale-green settle falls through to a re-scan and another round catches it; **AC11 makes that read terminal**, which would import a latent race into a terminal decision. The confirming pass MUST therefore: capture the SHA at `push_fix_to_pr()` time, re-read `gh pr view --json headRefOid,statusCheckRollup`, assert the rollup describes **that** SHA, and treat *"no check runs yet exist for the pushed SHA"* as **NOT-settled — keep polling** — never as green. **Precedent, do not re-coin:** `automate-helpers.sh:371-376` already does exactly this (`ready_sha` vs `head_sha`, `PARK: head_sha_moved`), documented at `automate-loop/SKILL.md:291`. The drain simply never adopted it — so this is **new machinery in the skill, not a doc sync.**

> **R2 — the honest cost, stated rather than hidden.** An earlier draft claimed this "preserves the entire PR-#122 saving … cheap and passes". **That was wrong**, and it conflated *"`ci` was green"* with *"`ci` did not need to re-run"*: each of rounds 5/6/7 **pushed a fix**, which re-triggers `ci` — and in this repo `ci` runs the whole `loomwright/scripts/test-*.sh` suite plus `npm ci` + build + the sdk-spike suites, i.e. minutes. The all-channel re-scan AC11 lets us skip is a handful of `gh` calls — **the cheap half**; the settle wait is where the wall-clock lives. **So AC11 gives back most of the wall-clock saving.** What genuinely survives is **one fewer full round of scan + validate + fix-worker dispatch** — real, but smaller than the requirement assumed. **New park path:** per `:337`, if the bounded wait elapses with a required check still in flight ⇒ `ESCALATED`, and in `/automate` `ESCALATED` always parks the run (§9). A purely **cosmetic** sub-floor fix can therefore park an autonomous run when CI is queued or slow — not theoretical given this account's documented Actions billing/queueing history. Accepted knowingly: the alternative is a terminal fail-open.

The floor check must be positioned so the `:399` earned-fallback gate still evaluates **for the skipped round** (AC12).

**The residual that genuinely remains after that fix:** a finding that would only have been *discovered* by round N+1's all-channel re-scan is never found. That is the real cost traded for the saving, it is bounded by the floor (only rounds whose entire yield was sub-floor are skipped), and it is why `sub_floor_converged` is **not** auto-merge-eligible (AC9).

Consequently the result field is named **`sub_floor_fixed[]`**, not `sub_floor_deferred[]` — under reading B nothing is deferred; the array records what was fixed in the final, un-re-scanned round.

### Evidence

PR #122 ran **7 drain rounds** against a declared hard ceiling of **5** and a corpus recent-half mean of **3.03**. Rounds 5/6/7 returned, in order: a stale PR *title*, a hardcoded `3` in a header note, and a pre-existing "four vs six" miscount — none merge-blocking; the required check (`ci`) had been green since round 1. Round 7 found nothing at all. Ledger: `.supervisor/postmortem/results.jsonl`, `number: 122`, `review_rounds: 7`, `source: automate_drain`.

## Acceptance Criteria

- [ ] **AC1** — Given a drain running on either entry path, when the round counter reaches the declared ceiling, then the loop terminates with a bound-hit terminal state and does NOT start another round — verified by a test that drives the counter past the ceiling.
- [ ] **AC2 (REWRITTEN per D2 — supersedes the source requirement's AC2)** — Given that `/automate`'s inline drain and the `review-pr-runner` path execute the *same* §U4 loop body, when either runs, then the declared bound is enforced by the **same mechanized counter** on that shared path, and neither path carries a private bound of its own. The brief must NOT assert or implement an inline-vs-runner symmetry between two independent counters.
- [ ] **AC3** — Given a completed drain round whose validated findings were **all below the severity floor**, when the round completes, then those findings **have already been fixed and pushed** (reading B — never declined a fix), the drain terminates `READY` with `termination_reason: sub_floor_converged` **without starting another round**, and the fixed sub-floor findings are listed in the terminal summary via `sub_floor_fixed[]`.
- [ ] **AC4** — Given a validated finding **at or above** the floor, when the round completes, then the drain continues exactly as today: no regression in healing real issues, and **Validate-Then-Fix still fixes every finding at any severity within the round** — verified by asserting `SKILL.md:350/:355/:390/:412/:661` are still true statements after the change (read them; do not assume).
- [ ] **AC5** — Given an unreadable/absent round count or an unreadable severity classification, when the gate evaluates, then it fails **CLOSED** (park / `ESCALATED`) rather than looping or silently passing.
- [ ] **AC6** — Given a completed drain, when the run record is read, then a **bound-hit** termination is mechanically distinguishable from a **converged** one and from a **sub-floor-converged** one (`review_rounds` alone cannot currently tell "converged at 3" from "guillotined at 5").
- [ ] **AC7** — Given the source requirement file, when this work lands, then its AC2 and the matching rubric bullet are corrected in place to the D2 framing (so the file does not keep asserting a falsified asymmetry), and the file is stamped `## Status: done`.
- [ ] **AC8** — Given **every gate in `.github/workflows/ci.yml`** (seven `check-*`/`validate-*` gates — note `check-shared-prefix.sh` is the one an earlier draft omitted — plus the `loomwright/scripts/test-*.sh` whole-suite loop at `ci.yml:62` and the sdk-spike suites at `:82-110`), when CI runs post-change, then all exit 0. The new `test-drain-rounds.sh` is auto-included by that glob, so it **must be clean on ubuntu**, not merely on macOS.
- [ ] **AC9 (NEW — auto-merge safety, resolves a Plan-Review-1 HIGH)** — Given a drain that terminated `sub_floor_converged`, when the `--auto-merge` trusted gate evaluates condition 1, then it **PARKs** rather than merging: a final round that was never re-scanned must not be auto-merge-eligible. Today `automate-helpers.sh:367` tests only `.drain_result != "READY"`, so a `sub_floor_converged` READY would flow straight through — this is the "Merging on bare `READY`" anti-pattern named at `automate-loop/SKILL.md:377`. Condition 1 must additionally read `termination_reason` and fail **CLOSED** on a missing/unreadable value (the explicit `has()`/`!= null` form used elsewhere in that script — **not** the falsy-coercing `//`). Cover it in `test-automate-helpers.sh`.
- [ ] **AC10** — Given the two skills whose `version:` frontmatter this change bumps (`review-heal` 1.5.0, `automate-loop` 1.2.0), when `check-skills-index-sync.sh` runs, then `SKILLS_INDEX.md:24-25` carries the matching bumped Version cells (the gate requires exact equality; index follows skill).
- [ ] **AC11 (resolves the Plan-Review-2 HIGH; the most important AC in this brief)** — Given a `sub_floor_converged` termination, when the drain decides its terminal state, then it has re-settled and re-evaluated the required-check set **bound to the PUSHED SHA** — capture the SHA at `push_fix_to_pr()` (`:465`), re-read `gh pr view --json headRefOid,statusCheckRollup`, and **assert the rollup describes that SHA**. **"No check runs yet exist for the pushed SHA" counts as NOT-settled (keep polling), never as green** — the `:328-331` predicate defines settled as `in_flight == []`, an absence, so an un-materialised check set would otherwise read as a stale green from the prior commit (`headRefOid` appears **zero** times in the skill today, so this is new machinery, modelled on `automate-helpers.sh:371-376`). `READY` only if that set is green for that SHA; red **or** unreadable **or** wrong-SHA ⇒ `ESCALATED`. Only the all-channel re-scan + validate pass (`:381-394`) may be skipped. **Verified by two tests:** (i) a sub-floor fix turns a required check red ⇒ `ESCALATED`, not `READY`; (ii) the rollup still describes the pre-push SHA ⇒ treated as not-settled, not as green.
- [ ] **AC12** — Given a round that would terminate `sub_floor_converged`, when the earned-fallback gate is evaluated, then it is evaluated **FOR THE SKIPPED ROUND** — i.e. **after** the sub-floor fixes are pushed, with `auto_fixable`/`needs_human` re-derived as empty — so `compute_no_review_lens_posted` (`:401`) runs exactly where round N+1 would have run it. Merely leaving the `:396-399` gate in place is **NOT** sufficient: on a sub-floor round `auto_fixable != []` at the top, so that gate was never going to fire on that round; it fires on the next round, which is precisely the one being skipped. State the chosen position explicitly in the SKILL prose.
- [ ] **AC13** — Given a `sub_floor_converged` termination, when the confirming pass observes a required check that had been fixed re-failing, then `repeat_check_failure` is set (its `:493` definition says "re-fails in a later round", and under AC11 there is no later round). It is an OR-trigger for the Postmortem Dispatch Tail (`RESULT_SCHEMAS.md:2139`), so leaving it unstated would silence the tail on exactly the path that most needs it.

## File Impact Map

**MODIFY**

| Path | What | Confidence |
|---|---|---|
| `loomwright/skills/review-heal/SKILL.md` | **The hub.** §U4 loop body: call the round ledger; add the termination-only floor **positioned per §"WHERE the floor check sits"** (confirming required-check pass still runs; `:399` earned-fallback gate still evaluates). §"READY redefinition" + §"Terminal states": add the sub-floor-converged terminal and the bound-hit distinction. Flag table (~`:24-40`): add `--severity-floor`. §Anti-Patterns near `:661`: add the reconciliation note that a **termination-only** floor is NOT the forbidden reinstatement — **and fix `:681`** (*"PASS and ESCALATED are the only terminal `decision` values"*), which the new terminal falsifies. Bump `version:` frontmatter. | HIGH |
| `loomwright/docs/RESULT_SCHEMAS.md` | `REVIEW_HEAL_RESULT` v2 **additive** fields: `termination_reason` (`converged` \| `bound_hit` \| `sub_floor_converged`), `severity_floor`, `sub_floor_fixed[]`. Additive only — v1 and existing v2 consumers must keep parsing. **Also update the outcome-model prose at `:2150`/`:2151`** (it defines READY/ESCALATED and is made incomplete by the new terminal) **and the `max_rounds` restatements at `:2110`/`:2136`** if the mechanization changes how the bound is described. Do not scope this to the additive fields alone. | HIGH |
| `loomwright/commands/review-pr.md` | `--severity-floor` Parameters row; sync the bound restatements at `:31`/`:59` **AND the terminal/outcome-model prose at `:46`, `:48`, `:52`, `:58`** — do not scope this to the bound alone. | HIGH |
| `loomwright/agents/review-pr.md` | Sync the bound restatement at `:115` **AND three further outcome-model restatements made stale by the new terminal: `:116` ("READY is terminal-stop-and-notify, merge-identical to PASS/ESCALATED"), `:130` (`decision: PASS \| ESCALATED` comment), `:138`.** | HIGH |
| `loomwright/docs/ARCHITECTURE_CONTRACTS.md` | **Unconditional** (separate from the conditional budget-mirror row below): `:214` asserts *"its only terminal `decision` values are `PASS` … and `ESCALATED`"* — already stale re `READY` today, and the new terminal worsens it. | HIGH |
| `loomwright/skills/automate-loop/SKILL.md` | §6 step 3 / §7 (`:196`, `:246`): note the owned inline drain is bound by the same mechanized ceiling — **reference, do not re-coin** (Claim Duplication Rule). **§10 condition 1 (`:289`) and the `owned_drain_result` line (`:249`)** must state that `sub_floor_converged` is NOT merge-eligible (AC9). Bump `version:` frontmatter. | HIGH |
| `loomwright/scripts/automate-helpers.sh` | **`gate-eval` condition 1 (`:366-369`)** — the plugin's only sanctioned `gh pr merge --squash` executor. Add the `termination_reason` check per AC9, fail-CLOSED on missing/unreadable (explicit `has()`/`!= null`, never the falsy-coercing `//`). | HIGH |
| `loomwright/scripts/test-automate-helpers.sh` | Cover the AC9 arms: `sub_floor_converged` ⇒ PARK; missing/unreadable `termination_reason` ⇒ PARK; plain `converged` READY ⇒ still merge-eligible (no regression). | HIGH |
| `loomwright/skills/SKILLS_INDEX.md` | Rows `:24` (`automate-loop`, 1.2.0) and `:25` (`review-heal`, 1.5.0) — Version cells must exactly equal the bumped frontmatter or `check-skills-index-sync.sh` fails (AC10). | HIGH |
| `CLAUDE.md` | The `:15` "**Latest change**" one-paragraph current-version summary — a version bump leaves it describing the previous release. Convention (per `:17`), not CI-gated; keep it to one paragraph and put the narrative in CHANGELOG.md. | MEDIUM |
| `loomwright/.claude-plugin/plugin.json` | Version bump + `description` version string updated **in place** (never append a clause). | HIGH |
| `.claude-plugin/marketplace.json` | Same bump, kept byte-consistent (`validate-version.sh` diffs the two). | HIGH |
| `CHANGELOG.md` | Release entry — the per-release narrative lives here, not in CLAUDE.md. | HIGH |
| `.supervisor/requirements/final-state/13-drain-bounding-earned-checks.md` | AC2 + rubric bullet 2 corrected to D2 framing (AC7); stamp `## Status: done`. | HIGH |

**CREATE (2)**

| Path | What | Confidence |
|---|---|---|
| `loomwright/scripts/drain-rounds.sh` | The mechanized bound — an **uncounted plain script** (not an agent/command/skill/hook), consumed by the §U4 loop body on **both** entry paths. Subcommands roughly: `init <pr> <max>`, `bump <pr>`, `check <pr>` (fail-CLOSED on unreadable/absent count), `read <pr>`. Fail-closed on a missing/garbage ledger; must be safe under `set -u` and macOS bash 3.2 + BSD userland. | MEDIUM |
| `loomwright/scripts/test-drain-rounds.sh` | Self-test incl. **driving the counter past the ceiling** (AC1) and the fail-closed arms (AC5). Follow the existing `scripts/test-*.sh` house style. **Auto-included by `ci.yml:62`'s whole-suite glob — must be ubuntu-clean.** | MEDIUM |

**MODIFY — conditional, only if the ratchet breaches (2)**

| Path | What | Confidence |
|---|---|---|
| `loomwright/docs/prompt-token-budgets.json` | `agents["review-pr"]` currently has **budget 27955 / measured 25413 = 2542 tokens headroom** (verified by running `check-token-budget.sh`). The gate sums the agent `.md` **plus every frontmatter-preloaded SKILL.md**, and `agents/review-pr.md:10-12` preloads `review-heal` — so **every byte added to the hub file counts against this ratchet**. Re-run the gate after editing; only if it breaches, raise `budget` per the script's `raise_rule` and update `measured`. | MEDIUM |
| `loomwright/docs/ARCHITECTURE_CONTRACTS.md` | The mirrored §"Prompt Token Budgets" row for `review-pr`. Must move **in the same commit** as the JSON or CI fails closed. Touch only if the JSON was touched. | MEDIUM |

## Subtask Structure

| # | Title | Est. Files | Status |
|---|-------|-----------|--------|
| 1 | Mechanize the shared drain bound + add the termination-only severity floor, with the auto-merge fail-closed guard and schema/doc/index sync | 14 modify (+2 conditional), 2 create | LAUNCHABLE |

### Subtask 1 — contract

```yaml
subtask: 1
requires: []          # no sibling subtasks — single-lane brief
provides:
  - drain-rounds.sh                     # the mechanized shared bound
  - REVIEW_HEAL_RESULT.termination_reason
  - REVIEW_HEAL_RESULT.severity_floor
  - REVIEW_HEAL_RESULT.sub_floor_fixed
lanes:
  - loomwright/skills/review-heal/SKILL.md
  - loomwright/skills/automate-loop/SKILL.md
  - loomwright/skills/SKILLS_INDEX.md
  - loomwright/docs/RESULT_SCHEMAS.md
  - loomwright/docs/ARCHITECTURE_CONTRACTS.md
  - loomwright/commands/review-pr.md
  - loomwright/agents/review-pr.md
  - loomwright/scripts/drain-rounds.sh
  - loomwright/scripts/test-drain-rounds.sh
  - loomwright/scripts/automate-helpers.sh
  - loomwright/scripts/test-automate-helpers.sh
  - loomwright/.claude-plugin/plugin.json
  - .claude-plugin/marketplace.json
  - CLAUDE.md
  - CHANGELOG.md
  - .supervisor/requirements/final-state/13-drain-bounding-earned-checks.md
```

## Parallelism Analysis
single-agent (no fan-out) — `review-heal/SKILL.md` is the hub every other file references; any split would place it in every lane (a same-wave overlap). Recommended workers: 1.

## Risk Assessment

| Risk | Severity | Source | Mitigation |
|---|---|---|---|
| The floor is implemented as a **fix-time** filter instead of a **termination-time** one, silently reinstating the `:661` anti-pattern and re-breaking #64 | **HIGH** | Feasibility (Phase 2.5) | AC4 pins it: Validate-Then-Fix must still fix every severity *within* a round. `:350/:355/:390/:412/:661` must all remain true after the change — assert this explicitly, don't assume. |
| A second, inline-only round counter is added, encoding the asymmetry F1 disproved | **HIGH** | Feasibility (Phase 2.5) | AC2 forbids it. One counter, on the shared §U4 path. |
| Sub-floor findings get **declined a fix** rather than fixed-then-not-re-scanned | **HIGH** | Feasibility 2.5 + Plan Review 1 | §"PINNED SEMANTICS" authorizes reading B only and forbids reading A by name; `sub_floor_fixed[]` is named to make the wrong reading obviously misnamed. |
| **Reading B declares `READY` on a RED PR** — `required_failing` was computed against the pre-fix SHA, so a sub-floor fix that breaks `ci` still reports ready. Inverts the bimodal fail-closed invariant. | **HIGH** | Plan Review 2 | AC11 — the confirming required-check pass against the **pushed** SHA is mandatory; only the all-channel re-scan may be skipped. Red or unreadable ⇒ `ESCALATED`. |
| **Regression detectors structurally disabled on the final round** — `:469` `repeat_after_fix` and `:493` `repeat_check_failure` can only fire on round N+1 | **HIGH** | Plan Review 2 | AC11's confirming pass restores required-check regression detection. The bot-finding-regression gap is the stated, bounded residual. |
| Floor check wired at the bottom of §U4 bypasses the `:396-399` earned-fallback gate, silently disabling the PR-#117 counter-pressure fallback | **HIGH** | Plan Review 2 | AC12 — position must be stated explicitly in the SKILL prose. |
| A `sub_floor_converged` READY silently becomes auto-merge-eligible, weakening the plugin's only sanctioned merge gate | **HIGH** | Plan Review 1 | AC9 — `automate-helpers.sh:367` tests only `.drain_result != "READY"` today, so the new terminal would flow straight through ("Merging on bare `READY`", `automate-loop/SKILL.md:377`). Fail CLOSED on missing/unreadable `termination_reason`. |
| New `REVIEW_HEAL_RESULT` fields break existing consumers | MEDIUM | Phase 3 + Plan Review 1 | Additive-only. **`/autonomous` EVALUATE confirmed safe by reading the file:** `autonomous-loop/SKILL.md:467` states it keys solely off `decision`, and `:466` already treats an unrecognized decision as terminal-non-re-iterate. `automate-helpers.sh learning-emit` is the direct ledger writer. **`read-postmortem.sh` is an INDIRECT consumer** — it reads the `results.jsonl` ledger and contains zero `REVIEW_HEAL`/`decision`/`READY` matches, so do not go hunting for a parser there (an earlier draft of this brief pointed the worker at the wrong file). |
| Skill `version:` bumped without the matching `SKILLS_INDEX.md` row ⇒ `check-skills-index-sync.sh` fails | MEDIUM | Plan Review 1 | AC10 — the gate requires exact equality on the Version cell; index follows skill. |
| Hub-file growth silently breaches the `review-pr` token ratchet (**2542 headroom**, verified by running the gate) | MEDIUM | Plan Review 1 | `agents/review-pr.md:10-12` preloads `review-heal`, so every byte added to the hub counts. Re-run `check-token-budget.sh`; if it breaches, the JSON + ARCHITECTURE_CONTRACTS mirror row must move in the SAME commit. |
| `drain-rounds.sh` written with GNU-isms (`stat -c`, `timeout`) | MEDIUM | Machine lesson | macOS bash 3.2 + BSD userland; macOS-green ≠ CI-green for `stat`/`date`/`sed -i`. Validate with `bash file.sh`, never inline. |
| Restating the ceiling `5` in the new script/docs, violating the Claim Duplication Rule this repo just shipped | MEDIUM | Phase 3 | One authoritative home (`SKILL.md:365`); derive or reference elsewhere. A gate is the LAST resort — and a new CI gate is an explicit non-goal. |

## Non-goals (carry forward verbatim)
- No change to *what* the drain reviews, to the Earned Fallback Review's evidence gate, or to the two-lens contract (D4 as amended stands).
- **No new CI gate surface.** The derivation-lint idea is recorded as considered-and-declined.
- Nothing merges automatically; the never-merge invariant is untouched. `--auto-merge` was NOT passed.

## Outcomes Rubric

> Bullet 2 is **rewritten** from the source requirement per owner decision D2 (the original asserted a falsified inline-vs-runner symmetry). AC7 syncs the requirement file to match. Every other bullet is verbatim.

- `max_rounds` enforced by a mechanized counter on the shared §U4 drain path, with a test that drives it past the ceiling
- The bound binds on the single loop body both entry paths share — no private per-path counter is introduced
- Severity floor implemented at **termination time only** — sub-floor findings are **fixed, then not re-scanned** (never declined a fix), and Validate-Then-Fix is unchanged within a round
- A `sub_floor_converged` termination still re-evaluates required checks against the pushed SHA and degrades to `ESCALATED` when they are red or unreadable — `READY` never means "red or unknown CI"
- Fail-closed on unreadable round count or severity
- Bound-hit vs converged vs sub-floor-converged termination distinguishable in the run record
- A `sub_floor_converged` drain is NOT auto-merge-eligible; the trusted gate fails closed on a missing or unreadable `termination_reason`
- No new CI gate surface added

## Executable Acceptance

> Both tasks exist and **will actually run** — verified at `loomwright/scripts/eval-corpus/doc-currency-green/` and `.../version-consistent/`, each with a `check.sh` + `spec.md`. (An earlier draft of this brief claimed `eval-corpus/` was absent; that claim came from a single repo-root Glob, was wrong, and is retracted. Note also `eval-corpus/review-churn-canary/` exists and is topically relevant to this change.)

- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-08-04-drain-bounding-earned-checks.md

---

## Outcome

- **Status:** COMPLETE, UNMERGED (parked `escalated` at the drain bound)
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/123 — v15.22.0, 6 commits, head `c817bf5`, branched off `b16414c`
- **Plan Review:** 3/3 exhausted — FAIL → FAIL → NEEDS_HUMAN; owner cleared the Phase 6 gate by inserting R1/R2/R3
- **Phase 4.5 SELF_HEAL:** PASS at heal iteration 1, 0 BLOCKING/HIGH (auto-expanded to `consistency_audit`)
- **Owned drain:** 5 rounds, terminal **ESCALATED (bound_hit)** — hit the declared `max_rounds` ceiling of 5 without a round verifying zero new findings. Not rounded up to READY.
- **Verification:** all 7 CI gates green; plugin self-test suite 0 failures; `test-drain-rounds` 34/34; `test-automate-helpers` 65/65; AC11 confirming pass GREEN and SHA-bound on `c817bf5`; `ci` (only required check) SUCCESS; 0 unresolved threads.
- **Nothing merged.** `--auto-merge` not passed; the 5-condition trusted gate never ran.

### What this job actually taught, beyond the diff

Both premises of the source requirement were false, and finding that out was worth more than the feature. There was never an inline-vs-runner enforcement asymmetry — one prose-only bound, obeyed once and not the other time. And the severity floor had been removed *deliberately*; reinstating it as written would have re-broken the #64 case.

The drain then found a defect in the fix for the defect: the AC12 earned-fallback guard was **unreachable dead code**, because `sub_floor_eligible` requires `bot_findings != []` while `no_review_lens_posted` requires it empty. Tracing that changed the conclusion rather than the code — a non-empty findings union *is* evidence a lens posted, so Plan Review's Hole 3 is vacuous on that path, not unhandled. Shipping the proof beats shipping a guard that can never fire.

Owed forward: this drain **hit its own ceiling**. Five rounds, each producing real fixes, on a change whose entire purpose is to stop drains from running long. That is evidence the bound is set at a plausible place, not evidence the feature failed — but it also means the honest `review_rounds` for this PR is 5-at-bound, which is exactly the `converged`-vs-`bound_hit` distinction AC6 exists to make legible.
