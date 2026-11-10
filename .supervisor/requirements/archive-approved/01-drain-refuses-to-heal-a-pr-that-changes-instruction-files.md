# The review-and-heal drain refuses to heal a PR that changes instruction or config files

## Status: pending

Source: `loomwright-archive/requirements/2026-10-27-062803-review-heal-drain-does-not-heal-a-pr-that-changes-instruction-files.md` (item 2 of the rules-trusted-root plan doc). Refreshed against main 8ec200e / v17.35.1.

**As the** owner running `/review-pr --until-mergeable` (inline, or detached from the `gh pr create` hook or Supervisor step 5.5) and `/automate` (one owned drain per item),
**I want** the drain to stop before it starts any agent session, fix worker or checkout when the PR changes a trusted-root file, and to hand the PR to me with a named reason,
**so that** no review or heal step runs with instructions, hooks, permissions or MCP servers that the PR under review supplied.

### Problem (verified against main 8ec200e)

1. **The trusted-root list exists, but nothing in the drain reads it.** `loomwright/scripts/classify-risk.sh` carries the one list (`TRUSTED_ROOT_ANYDEPTH`: `CLAUDE.md`, `AGENTS.md`, `REVIEW.md`, `CLAUDE.local.md`; `TRUSTED_ROOT_ROOTONLY`: `.claude/`, `.mcp.json`, `.agent/rules/`, `.agent/risk.json`, `.agent/verify.json`) and the matcher `trusted_root_hit` (shipped in PR #721 / v17.19.0). Only `gate-eval` (the merge gate) and the Phase 4.5 lens call the classifier. `review-heal-next-step.sh` and `dispatch-pr-review.sh` never do.
2. **Its `reasons` array cannot be the drain's input.** Reasons are capped at 20 plus `+N more`, and trusted-root reasons are appended after the `path:` / `content:` / `size:` ones. In this repo nearly every PR has many `path:` reasons (agents/, skills/), so a trusted-root hit can fall behind the cap. The drain needs an uncapped, trusted-root-only answer from the same list.
3. **Detached drain.** `dispatch-pr-review.sh` adds a worktree at the PR head SHA and launches `claude -p --permission-mode dontAsk --allowedTools … --disallowedTools … --agent loomwright:review-pr-runner` in it. `DISALLOWED_TOOLS` blocks writing `./.claude/**` and `./.mcp.json`, but the session still loads the head's `CLAUDE.md`, `.claude/settings*.json` and `.mcp.json` at start. Neither `--setting-sources` nor `--strict-mcp-config` appears anywhere in the plugin. The `DRY_RUN_DISPATCH` branch exits before the head is resolved (`gh pr view` comes later, at step ④).
4. **Inline drain.** `commands/review-pr.md` step 1 and the skill's §"Step 1 — PR-URL → head resolution" run `git checkout "$HEAD_REF"` on the main checkout *before* the driver starts. Claude Code picks up a changed `.claude/settings*.json` mid-session, so a PR that adds a hook takes effect at that checkout, before any refusal in the driver could run. Every later spawn (validate findings, the earned fallback review, each fix worker) also starts in that tree.
5. **`/automate` drain phase.** `automate-lanes.d/phase.sh` `_lanes_phase_spawn` starts the fresh `drain` session with `_lanes_claude_flags` (shared with lanes) plus `--settings <relay hook>`, cwd = the run's checkout. It gets no isolation flags.
6. **House-rule text in review comes from the checkout.** `agents/code-reviewer.md` step 4a (the earned fallback review in the drain, and the default `/review-pr` reviewer) and `skills/self-heal-advisory/on-entry.md` §"House-rules advisory" run `read-rules.sh` against the working tree. `read-rules.sh` has no way to read a git ref. The drain driver itself does not call `read-rules.sh`: its `rules` step uses `rules-gate-verdict.sh`, which is already stamp-bound.

## Acceptance Criteria

**One list**
- [ ] Given `classify-risk.sh`, when the drain needs to know which trusted-root files a diff changes, then it gets them from a read-only mode of `classify-risk.sh` (working name `--trusted-root <base> <head>`), which emits only the trusted-root paths, uncapped and computed by the same `trusted_root_hit` over the same `--no-renames -z` diff. The driver, the dispatcher and the docs hold no second copy of the list. Test: `test-classify-risk.sh` cases for the new mode (a diff with more than 20 `path:` reasons plus a `CLAUDE.md` change still lists `claude.md`; a clean diff lists nothing; `--kind-table` and the refs/`--paths` output are byte-identical to today).
- [ ] Given the new mode cannot read the diff (bad ref, `git diff` error, missing jq), when it runs, then it reports `unclassifiable` with a reason and exits 0. It never reports an empty list on failure. Test: `test-classify-risk.sh`.

**Inline drain (`review-heal-next-step.sh`)**
- [ ] Given a same-repo PR whose diff against its base changes root `CLAUDE.md`, when the drain runs, then it ends `ESCALATED` with `termination_reason: trusted_root_changed` and `escalation_cause: other`. The transcript shows no `validate findings`, `fallback review` or `fix worker` spawn, no push happens, and exactly one PR comment names `claude.md` (a capped path list) and says a human must review. The `notify` step fires as for any ESCALATED run, and a normal `REVIEW_HEAL_RESULT` is written. Test: a new golden case under `scripts/fixtures/review-heal-golden/` (row in `MAP.tsv`) run by `test-review-heal-next-step.sh`.
- [ ] Given a PR that changes only one of `AGENTS.md`, `REVIEW.md`, `CLAUDE.local.md`, a file under `.claude/`, `.mcp.json`, `.agent/rules/<x>.json`, `.agent/risk.json` or `.agent/verify.json`, when the drain runs, then it refuses the same way. Test: one table-driven case in `test-review-heal-next-step.sh` that iterates the classifier's own list, so the list is never typed into the test either.
- [ ] Given a PR that deletes `.agent/rules/process.json` or renames `CLAUDE.md`, when the drain runs, then it refuses. Test: `test-review-heal-next-step.sh`.
- [ ] Given a PR whose head moves during the drain to a commit that newly changes `CLAUDE.md`, when the next `round` reads the new head, then the drain refuses at that round before any spawn. The check runs on every head the drain is about to act on, not only at `start`. Test: `test-review-heal-next-step.sh` (head-move case).
- [ ] Given a fork PR that also changes `CLAUDE.md`, when the drain runs, then `trusted_root_changed` wins over `fork_no_push`, and no review session is spawned at all. Test: `test-review-heal-next-step.sh`.
- [ ] Given the trusted-root read fails (base ref unreadable, `git diff` error, or the classifier answers `unclassifiable`), when the drain runs, then it refuses with `termination_reason: trusted_root_unreadable` and the cause in the comment. It never proceeds as if nothing changed (fail CLOSED). Test: `test-review-heal-next-step.sh` (stubbed failing classifier, and an empty-output classifier).
- [ ] Given a PR that changes no trusted-root file, when the drain runs, then every existing golden case passes unchanged. Test: `test-review-heal-next-step.sh` goldens.

**Inline checkout order (`/review-pr --until-mergeable`)**
- [ ] Given a PR that changes `.claude/settings.json`, when the inline `/review-pr --until-mergeable` runs, then the trusted-root check runs on the fetched refs before `git checkout` of the PR head, and on a refusal the checkout never happens. `commands/review-pr.md` and the skill's Step 1 state this order. Test: a doc-order pin in `test-review-heal-next-step.sh` (the check precedes the checkout line in both files), plus the Running system check in Validation.

**Detached drain (`dispatch-pr-review.sh`)**
- [ ] Given a PR that changes `CLAUDE.md`, when the dispatcher runs on its real path (stubbed `gh` and `claude` on PATH), then no `claude` process is launched and no worktree is left behind. The durable marker records `regime=trusted_root_refused` (next to `pinned` / `permissive_refused`), the existing desktop/webhook notification fires, no PR comment is posted, no `.died` marker is written, and the dispatcher exits 0. Test: `test-dispatch-pr-review.sh`.
- [ ] Given the trusted-root read fails in the dispatcher, when it runs, then it does not launch either (marker `regime=trusted_root_unreadable`, exit 0). The decision fails CLOSED and the process fails SAFE. Test: `test-dispatch-pr-review.sh`.
- [ ] Given any PR, when the dispatcher launches the runner (the real launch with a stubbed `claude`, and the `DRY_RUN_DISPATCH` line), then the argv contains `--setting-sources user` and `--strict-mcp-config` and no `--mcp-config`. Both sites read one shared flag constant. Test: `test-dispatch-pr-review.sh`.
- [ ] Given the header contract "marker present ⇔ a dispatch genuinely started", when this lands, then the header and `docs/HOOKS.md` say what a refusal marker means. `session-resume.sh` and `status-line.sh` show no "drain died" for a refused PR. Test: `test-dispatch-pr-review.sh` asserts that no `.died` file is written.

**`/automate` drain phase session**
- [ ] Given an `/automate` item whose `drain` phase runs as a fresh session, when `phase-launch … drain` spawns it (stubbed `claude`), then its argv contains `--setting-sources user` and `--strict-mcp-config`, and still carries `--plugin-dir` and the relay `--settings`. The `launch-pad` and `supervisor` phases and lane spawns are unchanged. Test: `test-automate-lanes.d/06-phase-sessions.sh`.
- [ ] Given an owned drain that ends `ESCALATED` / `trusted_root_changed`, when `/automate` reads the drain report, then the item parks through the existing escalated path and the run file shows the reason. No new `/automate` code: `automate-next-step.sh` already accepts any `termination_reason` matching `^[A-Za-z0-9_-]{1,64}$`. Test: an existing `test-automate-next-step.sh` escalated case fed this reason.

**House-rule text from the base**
- [ ] Given `read-rules.sh --ref <git-ref>`, when it runs, then it reads `.agent/rules/*.json` from that ref through git objects only, with the same validation, routing and fail-safe exit 0 as today. An absent `.agent/rules/` at the ref means no rules. A ref that cannot be read emits nothing and prints the reason on stderr, and never falls back to the working tree. Test: `test-read-rules.sh` (base rule A vs working-tree rule B ⇒ only A; unreadable ref ⇒ empty, not B).
- [ ] Given the code reviewer's step 4a when it reviews a PR with a known base, and Phase 4.5's §"House-rules advisory", when they build the house-rules input, then they call `read-rules.sh --ref origin/<base>`. Test: a pin in `test-read-rules.sh` that both prompt lines carry `--ref`.

**Mutation controls**
- [ ] Given a mutation that removes the refusal from the driver, or from the dispatcher, or that drops either flag from either launch site, or that switches `read-rules.sh --ref` back to the working tree, when the suites run, then at least one case fails for each. Test: the mutation controls in the three suites named above.

## Non-goals
- Supervisor Phase 4.5 refusing on a trusted-root change. Its branch's edits come from a human-approved brief (OQ-5). Only its house-rules read moves to the base (see Owner decisions).
- Any override flag or config key. A human who wants a heal anyway runs the default (non-`--until-mergeable`) `/review-pr` by hand after reading the change.
- Changing the default diff-only `/review-pr` loop, the merge gate, or `rules-gate-verdict.sh` (already stamp-bound; the merge gate already parks these PRs at condition 6).
- Isolation flags for the `launch-pad` / `supervisor` phase sessions or for lanes.
- Reading `CLAUDE.md` / `REVIEW.md` from the base tip for reviewers. The runtime loads `CLAUDE.md` itself, and a plugin cannot redirect that.
- Changing the dispatcher's REGIME PROBE (it still reads project settings tiers and fails toward review-only).
- A second `.agent/risk.json` reader: `classify-risk.sh` already reads it only from `<base_ref>` (shipped in #721), and the drain adds no read of it.

## Owner decisions
- 2026-11-09 (Vikash, in chat): APPROVED from the archive review; refreshed against main 8ec200e / v17.35.1.
- 2026-11-09 (Vikash, in chat): the sibling item (trusted-root branch in `classify-risk.sh`) shipped in PR #721 / v17.19.0. Build on that list, never a second copy of it.
- 2026-10-27 (Vikash GO): OQ-5 Phase 4.5 refusal out of scope; OQ-6 the detached refusal records the marker and notifies, but posts no PR comment; OQ-7 refuse outright, never review-only; OQ-8 merge-base copies are accepted.
- 2026-10-27 (spike-backed owner addition): review/heal sessions the plugin launches as new `claude` processes pass `--setting-sources user` and `--strict-mcp-config`.
- 2026-10-28 (owner AC): house-rule text in review and heal paths is read from the PR's base branch, never the checkout.
- PO default, pending owner review: the trusted-root answer comes from a new uncapped `classify-risk.sh` mode, not from its capped `reasons` (problem 2).
- PO default, pending owner review: the inline check runs before the PR checkout, not only at driver `start`, because a checked-out `.claude/settings.json` hook takes effect mid-session (problem 4).
- PO default, pending owner review: OQ-5 and the 10-28 AC overlap on Phase 4.5. Phase 4.5 does not refuse, but its house-rules read takes `--ref origin/<base>` (the later, explicit owner AC wins).
- PO default, pending owner review: a refusal writes the durable marker (OQ-6), so it also blocks re-dispatch for that PR. The marker contract is reworded rather than adding a second file.
- PO default, pending owner review: a failed trusted-root read gets its own reason, `trusted_root_unreadable`, separate from `trusted_root_changed`.

## Priority: MVP
**Rationale:** The merge gate already parks these PRs, but only under `--auto-merge`. Every default drain, including the detached one fired by the `gh pr create` hook, still runs agent sessions and a pushing fix worker under the PR's own `CLAUDE.md`, `.claude/settings.json` and `.mcp.json`.

## Assumptions
- Claude Code loads project `CLAUDE.md`, `.claude/settings*.json` and `.mcp.json` from the session's cwd, and reloads settings files when they change mid-session. The 2026-10-27 spike covered the load. The implementer confirms the reload on the current CLI. The refusal is correct either way, because it is the owner's policy.
- Under `--setting-sources user`, `--agent loomwright:review-pr-runner` still resolves when the plugin is enabled at user scope, and `--settings` / `--plugin-dir` flag settings still load. If the runner cannot be resolved (for example, a plugin enabled only at project scope), the dispatcher does not launch: it logs, exits 0 and writes no marker. It never drops the flags.
- The dispatcher can fetch the base (`gh pr view` gains `baseRefName`; `git fetch origin <base>`). The head is already fetched via `refs/pull/<n>/head`.
- How the inline command runs the check before checkout (a driver pre-step or a direct classifier call) is a planning choice, as long as the order AC holds.

## Dependencies
- Depends on: none (the trusted-root list shipped in #721).
- Blocks: none.

## Risks
- **List drift.** A hand-typed list in the driver, dispatcher, tests or docs drifts from the classifier. The "one list" AC and the table-driven test guard this.
- **Fail-safe reader feeding a gate.** The classifier and `read-rules.sh --ref` exit 0 with empty output on some failures. Both drain paths must treat empty or `unclassifiable` output as a refusal. The empty case is tested (CLAUDE.md §"Failure-Mode Invariants").
- **Self-hosting friction.** Release PRs here touch `CLAUDE.md` or `.claude/`, so their drains always escalate to the owner. This is intended.
- **Fix-worker quality.** Drain sessions launched with `--setting-sources user` no longer see the project `CLAUDE.md`, so fix workers lose project conventions. Owner-accepted trade-off; watch heal outcomes.
- **Known limits (documented, not fixed).** Tools inside a session can still read and execute PR files. User-level config, user MCP servers and auto memory still load.
- **Prompt and coupling gates.** Edits to `code-reviewer.md`, `on-entry.md`, `review-pr.md` and the skill need `check-token-budget.sh` headroom. New `.claude/` or `claude -p` text in core scripts needs a `vendor-coupling-manifest.json` allowance raise. No history references go in prompts (`check-prompt-history-refs.sh`).
- **PR size.** About 25 files across two drain paths, the phase launcher, two readers and their docs. Large but cohesive. If it must split, the seam is house-rules `--ref` (one PR) vs the refusal plus flags (the other).

## Validation (must pass before merge)
1. **Static — suites:** `bash loomwright/scripts/test-classify-risk.sh`, `test-review-heal-next-step.sh`, `test-dispatch-pr-review.sh`, `test-automate-lanes.sh` (incl. `06-phase-sessions.sh`), `test-read-rules.sh` and `test-automate-next-step.sh` pass, including every mutation control named above.
2. **Static — repo gates:** `bash scripts/ci-local.sh --affected` passes (incl. `check-token-budget.sh`, `check-vendor-coupling.sh`, `check-doc-currency.sh`, `check-prompt-history-refs.sh`, `test-citation-drift.sh`). A `changelog.d/` fragment is added, `bash scripts/check-version-bump.sh` passes, and no version file is hand-edited.
3. **Running system — detached refusal:** in a sandbox repo, open a PR that edits `CLAUDE.md` with auto-review on. The dispatcher log shows `trusted_root_refused`, no `claude` process starts for it (`proc-registry.sh` / `ps`), and a notification arrives.
4. **Running system — inline refusal:** `/review-pr <that PR> --until-mergeable` ends `ESCALATED trusted_root_changed` with one PR comment, and the working tree is still on its prior branch (no checkout).
5. **Running system — isolation flags:** a detached drain on a clean PR whose head adds a `.claude/settings.json` hook and an `.mcp.json` server (on a branch that was already merged into the base) neither fires the hook nor starts the server, and still reaches a `REVIEW_HEAL_RESULT`.

## Depends on
none

## Touches
loomwright/scripts/classify-risk.sh
loomwright/scripts/test-classify-risk.sh
loomwright/scripts/review-heal-next-step.sh
loomwright/scripts/test-review-heal-next-step.sh
loomwright/scripts/fixtures/review-heal-golden
loomwright/scripts/dispatch-pr-review.sh
loomwright/scripts/test-dispatch-pr-review.sh
loomwright/scripts/automate-lanes.d/phase.sh
loomwright/scripts/test-automate-lanes.d/06-phase-sessions.sh
loomwright/scripts/read-rules.sh
loomwright/scripts/test-read-rules.sh
loomwright/scripts/test-automate-next-step.sh
loomwright/agents/code-reviewer.md
loomwright/agents/review-pr.md
loomwright/commands/review-pr.md
loomwright/skills/self-heal-advisory/on-entry.md
loomwright/skills/review-heal/SKILL.md
loomwright/skills/review-heal/escalation.md
loomwright/docs/result-schemas/review-heal-next-step.md
loomwright/docs/result-schemas/review-heal-result.md
loomwright/docs/loop-inventory/review-heal.md
loomwright/docs/HOOKS.md
loomwright/docs/ARCHITECTURE_CONTRACTS.md
loomwright/docs/prompt-token-budgets.json
loomwright/docs/vendor-coupling-manifest.json
changelog.d/drain-refuses-trusted-root-change.md

## Changes since the source was written
- The sibling item shipped (#721, v17.19.0): the trusted-root list, `.agent/verify.json`, and the base-ref read of `.agent/risk.json` are done. Dropped: the dependency, and the risk.json half of the base-ref AC.
- New: `classify-risk.sh` caps `reasons` at 20, so the drain needs an uncapped trusted-root mode rather than grepping reasons.
- New: the inline checkout happens before the driver runs, so the check must come before the checkout.
- Corrected: the drain driver has no `read-rules.sh` seam. The house-rule text reads are the code reviewer's step 4a and Phase 4.5's on-entry, and `read-rules.sh` has no `--ref` yet.
- Corrected: the `drain` phase spawn is in `automate-lanes.d/phase.sh` (`_lanes_phase_spawn`), not `launch.sh`. Adding the flags there leaves lanes and the other phases unchanged.
- `DRY_RUN_DISPATCH` exits before head resolution, so the refusal is tested on the real path with stubs.
