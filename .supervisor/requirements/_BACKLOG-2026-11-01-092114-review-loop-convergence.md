# Review-loop convergence and reviewer regression guard — plan doc (index document, not an implementable item)

## Status: done (index document — nothing to implement)

## Why now
From the 2026-11-01 comparison of Anthropic's "How the Claude Code team does code review" with Loomwright. Loomwright
already has the article's layers: a fresh separate reviewer, executable acceptance, house rules, fix-the-class, a
round cap and multi-voter verification. Two gaps were measured as worth closing:
- **Cost and convergence:** on plugin ≥ 17.2.0, heal fix rounds 0/1/2/3 = 1/3/7/5 of 16 items
  (`docs/evidence/review-gate-rounds.md`). Recorded Phase 4.5 durations run 32m to 2h 27m, and every round reviews
  the whole PR. 65% of the lines late rounds modify were written by an earlier fix. Item 01 targets this. It carries
  the owner's D1 answer from this session: rounds ≥ 2 review the whole files the last fix touched.
- **Reliability:** the reviewer prompt, protocol and routing changed several times this month (PRs #634, `cb9e69c`,
  `4aefe4d`), and nothing checks catch rate. The CI lens found something after Phase 4.5 on 19 of 43 recent items,
  so real misses exist to replay. Item 02 targets this.
- **Knowing what earns its cost:** the run log carries no per-feature fields, so no data says which optional gate,
  lens or advisory catches anything. Most of the signals already sit scattered in sidecars, pin-mutation caches and
  the postmortem ledger, and the heal-signal catch-rate ledger has been stale since 2026-08-14. Item 03 targets this.
Post-heal misses are rare (3 of 43), so item 01 must keep catch rate flat while cutting cost. Item 02 is how a drop
would be seen, and item 03 is how every feature's keep or retire call gets evidence.

**Testing without a release.** Every item carries a pre-release validation run through
`claude -p --plugin-dir <branch>/loomwright`, which loads only the branch's copy. Item 01 also ships in **shadow
mode**: the narrowed scope is computed and recorded but never applied, until the owner flips `heal_review_scope` to
`files` from the `--shadow-report` evidence.

## Owner decisions
none recorded

## Order
| Item | Delivers | Depends on | Can run in parallel with |
|---|---|---|---|
| 01 | Per-round finding records; rounds ≥ 2 scoped to the files the last fix touched, repeats suppressed; ships in shadow mode | none | 02, 03 |
| 02 | On-demand replay of past reviewer misses, with a model-free grader selftest in CI | none | 01, 03 |
| 03 | Feature registry + read-only scorecard in `/insights`, stale heal-signal fixed, `/propose --from-scorecard` | none | 01, 02 |

## Run
/automate --backlog .supervisor/requirements/_BACKLOG-2026-11-01-092114-review-loop-convergence.md --parallel 3
- N = 3: the three items' Touches are disjoint and each is one-PR sized. `plan-waves --max 3 --explain`:
  `wave 1: 01 02 03`. No serialisation. Use `--parallel 2` instead if you'd rather review a smaller wave PR; 03
  then runs in wave 2.
- Hotspots: `docs/prompt-token-budgets.json` and `ARCHITECTURE_CONTRACTS.md` belong to 01 only; 03's Scope keeps
  its command-doc additions within current headroom or moves them to `docs/command-parts/`. `AGENT_GUIDELINES.md`
  and `.github/pull_request_template.md` belong to 02 only. `commands/insights.md`, `commands/propose.md` and the
  insights/heal-signal scripts belong to 03 only. Each item writes its own `changelog.d/` fragment.
- Safe mode (no `--auto-merge`, which `--parallel` refuses anyway). The owner merges the wave PR.
- Item 01 is high-risk by `classify-risk.sh` (it edits `agents/` and `skills/`): read its Phase 4.5 result before
  merging, and run 02's replay on 01's branch if 02 lands first.

## Considered and not queued
- **Low / medium / high risk tiers that set review depth.** `classify-risk.sh` marked 31 of the 40 most recent merged
  PRs high-risk (its rule (b) flags any path under `agents/`, `skills/`, `commands/`, `hooks/`). The 9 that weren't
  were mostly releases and small fixes. A lighter path would barely fire in this repo, and lowering review depth is
  a reliability risk with no measured payoff.
- **Code-blind "first-time user" tester.** A `/verify` mode for the user's app, not plugin performance or reliability.
  No miss in the postmortem ledger points at it.
- **Hunk-only re-review** (Anthropic's exact design): rejected by the owner (D1 in item 01), because 35% of late-round
  fix lines repair original-build code.
- **A new `/scorecard` command:** `/insights` already owns dashboards and `/propose` already owns turning evidence
  into drafts; a third surface would split them. Item 03 extends both instead.
- **Emitters for features with no record yet:** they would edit the same prompt files as item 01. Item 03 names
  them under "needs an emitter", and that list becomes a follow-up item.
- **Mockup-first and owner-approved evals before build; a 5-round loop** (from the video): `/automate` deliberately runs
  without a mid-run owner stop, Launch Pad already gates the brief interactively, and the article's own lesson is a
  3-round cap.

## Revisit when
- Item 01's Measurements show `self_heal_misses` or CI-lens rounds per item rising (revisit D1).
- Loomwright's postmortem ledger holds external-project items in which `classify-risk.sh` marks most diffs not
  high-risk (reopens risk tiers).
- A shipped `/verify` miss traces to the agent having read the app's source (reopens the code-blind tester).
- Item 03's scorecard lists features under "needs an emitter" (opens the emitter follow-up), or marks one
  `review:` (opens a `/propose --from-scorecard` draft for the owner).

## Checklist
- [ ] .supervisor/requirements/2026-11-01-092114-phase-4-5-re-reviews-converge-on-what-the-last-fix-changed.md
- [ ] .supervisor/requirements/2026-11-01-092115-phase-4-5-reviewer-replays-its-own-past-misses.md
- [ ] .supervisor/requirements/2026-11-01-092116-feature-scorecard-shows-which-features-earn-their-cost.md
