# Supervisor Job: Test-integrity guard (blocking PreToolUse hook + worker rule of explanation)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: feature/loop-gaps-02-test-integrity-guard (== origin/main @ c4fbe33)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (see Feasibility check 4 — this is the plugin's FIRST fail-CLOSED blocking hook; elevated care required)
- **Source requirement:** .supervisor/requirements/six-phase-loop-gaps/02-test-integrity-guard.md

## Feasibility (optional — Launch Pad v10.3+)

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Bash + jq (matches every existing guard-shaped script in this repo, e.g. `dispatch-pr-review.sh`'s `acquire_lock`, which this item's marker-file pattern explicitly reuses the shape of). |
| 2 | Dependency Availability | GO | No new dependency; `jq`/`bash` already required repo-wide. |
| 3 | Architecture Fit | GO | Extends the existing `hooks.json` PreToolUse surface and mirrors the `out_of_lane`/`deviations` "additive, never weakening" pattern this exact run has used twice already (items 01/06/08). |
| 4 | Scope vs Supervisor Capability | CAUTION (elevated) | This is the plugin's **first fail-CLOSED `type: command` hook** — every other command hook in `hooks.json` today is `\|\| true` (verified: 0/39 leaves currently omit it). A bug in the new guard's Bash-matcher pattern set could over-deny (blocking legitimate commands in every future armed session across every project using this plugin) or under-deny (silently providing no protection at all) — this is qualitatively different risk from a doc-drift or test-suite item. The requirement itself is already the product of 4 rounds of red-team revision (2 disarm bypasses found and closed in rev 4 alone) — the worker's job is to implement the ALREADY-HARDENED spec precisely, not redesign it. ~20 files, 2 new scripts (one of them a large test-case matrix per the requirement's own §10), 3 live runtime probes required as the FIRST implementation tasks (P1–P3, see Scope below) before any guard code is written. Kept single-subtask (the probes' answers determine exact wording in later steps — this is a sequential dependency chain, not independent parallel groups; also converges on shared `hooks.json`/CHANGELOG.md/plugin.json, same file-conflict reasoning as items 06/08/six-phase-loop-gaps/01 in this run). Expect substantially more worker turns/resumes than any prior item in this run — this is the largest and highest-stakes item in the queue. |
| 5 | Hard Blockers | GO | No migration framework, no new credentials. Independently re-verified during planning: Claude Code's ACTUAL current `PreToolUse` hook semantics (exit 2 blocks unconditionally; stderr shown to model; `hookSpecificOutput.permissionDecision: "deny"` JSON is the documented structured form, exit 2 remains fully supported — do BOTH, matching the requirement's own instruction) — confirmed via live fetch of the official Claude Code hooks docs, resolving the requirement's own open "re-verify against the current hooks reference" premise. Two stale figures in the requirement corrected below (worker token budget, `dispatch-pr-review.sh`'s exact launch line) — both because items already merged earlier in THIS SAME automate run moved the ground truth after the requirement was authored on 2026-09-21. |

**Overall Verdict:** CAUTION (elevated — proceeds per Phase 2.5 flow with an explicit Warning recorded, not a NO-GO; the requirement's own extensive probe-and-mutation-control discipline is the mitigation)

## Task
**Goal:** Give the plugin a fail-CLOSED `PreToolUse` guard that, while a Loomwright-spawned agent is working in a session, prevents it from bypassing commit/push hooks, editing test-runner/lint/git-hook/Claude-settings configuration, removing or neutering the guard itself, or fixing a failing test without recording a diagnosis — armed automatically per-session, disarmed only at `SessionEnd`, with no tool-call-reachable disarm.

**Problem Statement:**
Nothing in the plugin today stops an agent from editing the gate it is being measured by. `hooks.json`'s `PreToolUse` matcher list has exactly one entry (`AskUserQuestion`, a notifier) — verified live, unchanged from the requirement's own claim. The only existing guard against a worker gaming its own verification is `result_block_parser.py`'s post-hoc `_DESTRUCTIVE_PATTERNS` tripwire at `SubagentStop` (`rm -rf`, `git push`, `git reset --hard`, `DROP`, `TRUNCATE` — verified, `git clean` genuinely absent) — it says nothing about `git commit --no-verify`, `HUSKY=0`, `git clean -x`, or a one-line edit to `jest.config.ts` that excludes the failing spec. This repo has already been bitten by exactly this failure shape twice (memory `shared-fixture-default-disarms-its-own-assertion`; PR #101's non-integer-budget fail-open — both passed green because the check itself was changed, not the code). Success looks like: an armed session cannot bypass or neuter its own verification surface, a diagnosed-vs-undiagnosed test-assertion edit is distinguishable and reviewable, and the honest limits (script-file indirection, non-Bash command channels, no sandbox) are documented, not hidden.

## Probes — MUST run FIRST, before any guard code is written (per requirement's own explicit sequencing)
- **P1 — session-id equality under `claude -p`.** Confirm `CLAUDE_CODE_SESSION_ID` (Bash env), the hook payload's `session_id`, and (under `--session-id <uuid>`) the passed uuid all agree. If they do NOT agree under `-p`, the prompt-step `arm` source must change before §1 is built.
- **P2 — `agent_type` on a subagent's `PreToolUse`.** Confirm a `Task`-spawned subagent's own `PreToolUse[Bash]` payload carries `agent_type`/`agent_id` while the outer main-thread call does not (memory `subagentstop-payload-shape` confirms this for `PostToolUse`; `PreToolUse` is unverified — the existing `spawn-probe-2026-09-02/pretooluse-task-*.json` fixtures are main-thread `Agent`-tool calls and prove nothing about subagent payloads, independently re-confirmed during planning). Fallback if NO: the two deny-message variants in Scope item 2 collapse to one (the subagent wording).
- **P3 — does `settings.json` `env` reach hook processes?** Determines whether `/.claude/settings*.json` protection in Scope item 2 is load-bearing or merely belt-and-braces.

Each probe gets a fixture + README under `loomwright/scripts/progress-event-fixtures/guard-probe-<date>/` stating the launch mode and the answer — this is itself an acceptance criterion, not optional groundwork.

## Acceptance Criteria
(Condensed from the source requirement's own precise Acceptance Criteria list — read that section directly for the exhaustive case-by-case detail; do not re-derive from this summary alone.)
- [ ] P1/P2/P3 each produce a fixture + README; §1/§2/§3 wording in the shipped code matches the probes' actual answers (not assumed answers).
- [ ] With a marker file named by the payload's `session_id` present: every Bash-matcher deny pattern (no-verify variants, `git commit -n`, `git -c core.hooksPath=`, `HUSKY=0`/`SKIP=`/`PRE_COMMIT_ALLOW_NO_CONFIG=` anchored at simple-command start, `pre-commit uninstall`, `lefthook uninstall`, `.git/hooks` write, `git clean` with x/X in its cluster, any `guard-arm.sh` invocation other than plain `arm`) and every Write|Edit-matcher deny basename/directory-suffix (test-runner/lint/git-hook configs, the guard's own two scripts + `hooks.json`, `.claude/`+`settings*.json`) → `exit 2`; the same commands' negation twins (reads, `git push -n`, `CI_SKIP=1`, a mention of `guard-arm.sh` as a `grep`/`cat`/`shellcheck` argument, `.vscode/settings.json`, `config/settings.json`, a fresh `new/dir/*` path) → `exit 0`.
- [ ] `guard/` absent, or holding only foreign-session-id files, or `LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS=1` in the hook's process env → every payload `exit 0`.
- [ ] `guard-arm.sh arm` NEVER writes a file whose name is not its own `CLAUDE_CODE_SESSION_ID` (or, dispatcher-shape only, the explicit `--session-id`); a forged-env `arm` leaves every other marker file byte-identical; the two-marker concurrency case (item A stays denied after item B's `arm` runs) passes; empty/unset session id → `exit 3`, no file written.
- [ ] `dispatch-pr-review.sh` writes `<worktree>/.supervisor/guard/<uuid>.json` BEFORE launch and passes `--session-id <uuid>` — inserted into the ACTUAL current launch line (see File Impact Map correction below, not the requirement's own paraphrase).
- [ ] Supervisor Phase 0 INIT and `review-heal` loop entry each record `guard_armed: {ok|failed: <reason>}`; on `failed` the run proceeds visibly unguarded (`## Decisions Log` + completion-tail `guard: unarmed`).
- [ ] Neither deny stderr line names the opt-out env var, a marker path, `settings`, `config.json`, or `guard-arm`.
- [ ] `hooks.json`: the two guard leaves (`PreToolUse[Bash]`, `PreToolUse[Write|Edit]`) carry NO `\|\| true`; the arm-backstop (`PreToolUse[Agent|Task]`) and `SessionEnd` disarm leaves DO carry it; leaf count 39→43, pinned in `loomwright/scripts/test-worktree-audit.sh` at the line-159 AC-2 assertion (see File Impact Map — exact line verified).
- [ ] `CLAUDE.md` (line 95) and `docs/HOOKS.md` (line 10) — both already end their `\|\| true` convention sentence anticipating a future blocking exception; rewrite each to NAME the two guard leaves as that exception (verified exact current sentence text below — do not invent new phrasing, extend what's there).
- [ ] `agents/worker.md` step 2 "Run tests" sub-bullet (verified at line 113) gains the diagnose-before-fix rule; the Phase 4.5 fix-task spawn prompt gains the conditional-mandatory `test:` wording.
- [ ] `agents/code-reviewer.md` gains a NEW, separate, presence-scoped paragraph (distinct from the Self-heal-lens paragraph item 01 already extended at line 182 — do not re-edit that one) with the assertion-diagnosis HIGH finding, the truncation/absent exemptions, the settings/hooks/guard-source HIGH, and the same-test-twice→NEEDS_HUMAN cap.
- [ ] `result_block_parser.py`'s `_DESTRUCTIVE_PATTERNS` gains `git clean` with x/X in its flag cluster, using the SAME `_CMD_START` prefix discipline and negation-context test the existing 6 entries use.
- [ ] `worktree-salvage.sh` excludes `.supervisor/guard/` from its `untracked/` copy — verify first whether this is ALREADY true structurally (see File Impact Map note) before writing a code change; the AC is satisfied by a regression test either way.
- [ ] All eight mutation controls named in the requirement's Scope item 10 fail when applied and pass when reverted.
- [ ] `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` still resolves to exactly the same 5 surfaces CLAUDE.md enumerates — this item DOES touch one of the 5 (`scripts/result_block_parser.py`, via the `_DESTRUCTIVE_PATTERNS` addition below); that edit is unrelated to, and must not disturb, the line-1379 comment the invariant grep matches on.
- [ ] Full `loomwright/scripts/test-*.sh` loop + root `scripts/check-*.sh` green locally before push, including a NEW `loomwright/scripts/test-guard-test-integrity.sh` covering every case the requirement's Scope item 10 lists.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Test-integrity guard: probes, marker-file arming, PreToolUse deny matchers, worker/reviewer rules, docs | all | 18 modify, 3 create | none needed (plain bash/JSON/markdown edits) | LAUNCHABLE |

```yaml
# Subtask 1 — Test-integrity guard (LAUNCHABLE, sole subtask — probes-then-code sequential dependency)
provides:
  - {kind: "file", path: "loomwright/scripts/guard-arm.sh"}
  - {kind: "file", path: "loomwright/scripts/guard-test-integrity.sh"}
  - {kind: "file", path: "loomwright/scripts/test-guard-test-integrity.sh"}
  - {kind: "symbol", path: "loomwright/scripts/guard-arm.sh", name: "arm"}
  - {kind: "symbol", path: "loomwright/scripts/guard-arm.sh", name: "arm-from-payload"}
  - {kind: "symbol", path: "loomwright/scripts/guard-arm.sh", name: "disarm-session"}
requires: []
lanes:
  - "loomwright/scripts/guard-arm.sh"
  - "loomwright/scripts/guard-test-integrity.sh"
  - "loomwright/scripts/test-guard-test-integrity.sh"
  - "loomwright/scripts/progress-event-fixtures"
  - "loomwright/hooks/hooks.json"
  - "loomwright/scripts/result_block_parser.py"
  - "loomwright/scripts/dispatch-pr-review.sh"
  - "loomwright/scripts/worktree-salvage.sh"
  - "loomwright/scripts/test-worktree-audit.sh"
  - "loomwright/skills/supervisor-config/SKILL.md"
  - "loomwright/skills/review-heal/SKILL.md"
  - "loomwright/agents/worker.md"
  - "loomwright/agents/code-reviewer.md"
  - "loomwright/docs/HOOKS.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "CLAUDE.md"
  - "AGENT_GUIDELINES.md"
  - "loomwright/docs/PITFALLS.md"
  - "CHANGELOG.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
external_requires: []
```

### File Impact Map

**Read the source requirement's own Scope items 1–11 directly for the exhaustive pattern list, deny-message wording, and full test-case matrix — this section gives anchor points, corrections to stale/imprecise premises, and sequencing, not a re-transcription of ~270 lines of already-precise spec.**

**Do FIRST — Probes (before any guard code):**
- Run P1/P2/P3 exactly as the requirement's "Probes" section describes. Save each as a fixture + README under `loomwright/scripts/progress-event-fixtures/guard-probe-<today's-date>/`. If P1 disagrees under `-p`, STOP and re-derive the `arm` source's session-id-reading approach before writing `guard-arm.sh` — do not proceed on an assumed answer.

**Create:**
- `loomwright/scripts/guard-arm.sh` — subcommands `arm <by>`, `arm-from-payload`, `arm dispatcher --session-id <uuid>`, `disarm-session`, plus the 7-day prune-on-arm behavior. Mirror `dispatch-pr-review.sh`'s `acquire_lock` (lines 560-602, quoted in full during planning research) for the atomic-write/stale-reclaim SHAPE — but this is a one-marker-PER-SESSION design (no shared lock slot), per the requirement's Rev 4 correction of Rev 3's exact bug. Exact I/O rules, the `CLAUDE_CODE_SESSION_ID`-only naming rule, and the empty-id `exit 3` behavior are specified in Scope item 1 — implement precisely, this is the section that closes the two Rev-4 disarm bypasses.
- `loomwright/scripts/guard-test-integrity.sh` — Bash + Write|Edit matchers, stdin payload read, the 5-step evaluation order in Scope item 2 (cheap-first, no `jq` on the inert path). The exact pattern list (no-verify variants, `HUSKY=0` etc., `git clean` x/X, protected basenames, directory suffixes) is fully specified in Scope item 2 — transcribe it precisely, do not paraphrase or "improve" it (this spec is already the product of 4 red-team rounds). Deny mechanics: `exit 2` + ONE stderr line, the exact two-variant wording (subagent vs main-thread) is given verbatim in Scope item 2 — copy it verbatim, and confirm the deny line never names the opt-out/marker/settings/guard-arm (an explicit acceptance criterion). Emit BOTH `hookSpecificOutput.permissionDecision: "deny"` JSON AND `exit 2` (independently confirmed via live Claude Code docs fetch during planning: exit 2 blocks unconditionally regardless of JSON; the JSON form is the current documented structured mechanism — do both, per the requirement's own fallback instruction).
- `loomwright/scripts/test-guard-test-integrity.sh` — the full case matrix in Scope item 10 (every Bash pattern + its negation twin, every Write|Edit basename + allow-cases, the 6 gate cases, the `guard-arm.sh` subcommand cases, the concurrency case, P1 as a live test not just a fixture, the sentinel checks, and all 8 named mutation controls). This is the largest new test file in this item — budget significant worker effort here.

**Modify:**
- `loomwright/hooks/hooks.json` — add 4 leaves per Scope item 4: `PreToolUse[Bash]` + `PreToolUse[Write|Edit]` → `guard-test-integrity.sh`, **NO `\|\| true`** (verified: this repo's `hooks.json` currently has ZERO command leaves without `\|\| true` — these will be the first, exactly as intended); `PreToolUse[Agent|Task]` → `guard-arm.sh arm-from-payload \|\| true`; `SessionEnd` → `guard-arm.sh disarm-session \|\| true`. Match the exact existing JSON shape (quoted during planning: the `AskUserQuestion` matcher object at lines 247-259 is the style template). Leaf count 39→43.
- `loomwright/scripts/test-worktree-audit.sh` — line 159's AC-2 leaf-count assertion (`= "39"` → `= "43"`); note lines 160-161 pin unrelated `PostToolUse[Bash]` counts — do not touch those.
- `loomwright/scripts/result_block_parser.py` — add a `git clean` (x/X in cluster) entry to `_DESTRUCTIVE_PATTERNS` (currently 6 entries, lines 1383-1389, quoted in full during planning) using the exact same `_CMD_START` prefix (line 1381) and the existing negation-context test (`_NEGATION_RE`, ~lines 1403-1406) other entries already use — additive only, never weaken an existing pattern.
- `loomwright/scripts/dispatch-pr-review.sh` — **CORRECTED anchor (the source requirement's own premise text is a paraphrase, not the literal line — re-read before editing):** the actual current launch is at **line 891**: `"$_bin" -p --permission-mode "$_pmode" --allowedTools "$_atools" --disallowedTools "$_dtools" --agent "$_runner" "$_pr" >>"$_log" 2>&1 </dev/null` (inside a heredoc `$WRAPPER`, itself invoked via `nohup bash -c` at line 895). Insert `--session-id <uuid>` into this exact flag sequence. Before this launch, write `<worktree>/.supervisor/guard/<uuid>.json` via `guard-arm.sh arm dispatcher --session-id <uuid>` (the ONE caller allowed to pass the id explicitly). The `acquire_lock`/`write_lock_meta` functions (lines 560-602) are a SHAPE reference only — do not call them; the guard marker is a separate, one-file-per-session mechanism.
- `loomwright/scripts/worktree-salvage.sh` — **verify before changing anything:** the script's own header documents that gitignored `.supervisor/` content is excluded STRUCTURALLY (its `git status --porcelain=v1 -z --untracked-files=all` call at line 170 has no `--ignored` flag, so gitignored paths never appear in the `untracked/` copy at all — not via a path denylist). `.gitignore:86` (`.supervisor/*`) covers `.supervisor/guard/` with no negating `!.supervisor/guard/` line anywhere — so this exclusion likely ALREADY HOLDS with zero code change. Write the regression test first (an untracked `.supervisor/guard/<id>.json` present at salvage time must not appear in `untracked/`); if it already passes, the AC is satisfied by the test alone — do NOT add a redundant path-denylist, and do NOT add `--ignored` to "fix" something that isn't broken (that would change what else gets swept into salvage).
- `loomwright/skills/supervisor-config/SKILL.md` — no single named "after config resolution" anchor exists (verified — the closest structural point is the end of `## Protocol`'s step 6, around line 107-109, immediately before the `**Output:**` block at line 109). Insert the arm call + `record_decision("guard_armed: ...")` there.
- `loomwright/skills/review-heal/SKILL.md` — no literal "loop entry" anchor exists; the natural insertion point is the top of `## Step 2 — The bounded review→fix→re-review loop` (heading line 116, loop code starting line 120/125) — arm before the loop begins. **Confirmed live: 0 occurrences of "ADVISORY" in this file** — the requirement's premise that this drain's reviewer receives no advisory line is accurate; no advisory-carriage change needed here (that's an explicit non-goal, tracked as a follow-up item elsewhere).
- `loomwright/agents/worker.md` — the "Run tests" sub-bullet is item **2** under **`### Step 5: Verify`**, confirmed at **line 113**. Add the diagnose-before-fix rule exactly as worded in Scope item 8. **Token budget correction:** the requirement's cited `5876/5905/29 headroom` is STALE — item 01 in this same automate run already raised the worker budget to **7314** (live-measured 6649, 665 headroom, confirmed during planning). This item must raise FURTHER from 7314/6649 after adding its own prose, not repeat item 01's already-landed raise — write the prose first, re-measure, then raise `docs/prompt-token-budgets.json`'s `.agents.worker` + add a NEW raise-log row in `docs/ARCHITECTURE_CONTRACTS.md` naming THIS item, distinct from item 01's existing row (verified present at ARCHITECTURE_CONTRACTS.md line 547 — do not edit that row, add a new one after it).
- `loomwright/agents/code-reviewer.md` — **do NOT re-edit** the Self-heal-lens paragraph at line 182 (item 01 already extended it with the `deviations` clause, confirmed current text during planning — it already covers `brief_conformance`/`deviations` and is complete for its own purpose). This item adds a NEW, separate, presence-scoped paragraph elsewhere in the file per Scope item 9's exact wording (assertion-diagnosis HIGH finding, truncation/absent exemptions, settings/hooks/guard-source HIGH, same-test-twice cap).
- `CLAUDE.md` — line 95, current exact sentence (verified): `"**\|\| true convention:** every type: command hook string carries \|\| true as belt-and-suspenders — valid ONLY because all of them are always-exit-0 fail-safe emitters/validators. A future blocking gate (non-zero-exit) added as a type: command hook must NOT carry \|\| true — that would silently neuter it (see §"Failure-Mode Invariants" below)."` — this ALREADY anticipates the exception; extend it to NAME the two guard leaves as that exception, don't rewrite the whole sentence.
- `loomwright/docs/HOOKS.md` — line 10, current exact sentence (verified, near-identical to CLAUDE.md's): also already anticipates the exception — extend to name the two guard leaves, add the full row-level documentation Scope item 5 specifies (arm points, marker files, disarm, opt-out + P3's answer, both deny variants, all honest limits including the non-Bash-channel and inline-session-arming ones).
- `AGENT_GUIDELINES.md`, `loomwright/docs/PITFALLS.md` — one-line pointers each, per Scope item 5's instruction (grep for the `\|\| true` sentence first in each, per that same instruction).
- `CHANGELOG.md` + `loomwright/.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` — one paragraph, one version bump, done LAST after everything else lands (same shared-file convergence point as every other item in this run).

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | none needed — plain bash/JSON/markdown edits, no framework-specific skill applies |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| **First fail-CLOSED blocking hook in the plugin — over-deny or under-deny both have real consequences** | HIGH (inherent to the item, not introducible by planning) | The requirement is the product of 4 red-team rounds with 8 explicit mutation controls and a huge fixture-based test matrix specified in Scope item 10 — the worker's job is precise implementation of an already-hardened spec, not design. Full test suite (including the new `test-guard-test-integrity.sh`) must be green, all 8 mutation controls must demonstrably fail-then-pass, before this is considered done. Recommend the Phase 4.5 reviewer pay special attention to the exact pattern regexes vs. the requirement's literal text (character-for-character, not paraphrased). |
| Probes (P1-P3) determine wording used later in the SAME implementation | MEDIUM | Explicitly sequenced FIRST in this brief and the requirement; a worker that writes guard code before running the probes and it turns out P1 disagrees under `-p` would need to redo the `arm` source's core approach. Flagged prominently. |
| Scope vs Supervisor Capability CAUTION — 21 files (18 modify, 3 create), by far the largest item in this run | MEDIUM | Kept single-subtask (probes-then-code sequential dependency + shared hooks.json/CHANGELOG.md/plugin.json convergence, same reasoning as items 06/08/loop-gaps-01); worker should expect substantially more turn-limit resumes than any prior item. |
| Two stale figures in the source requirement (worker token budget 5905 vs live 7314; `dispatch-pr-review.sh`'s launch-line paraphrase vs its actual current flag sequence) | LOW | Both independently re-verified and corrected in this File Impact Map — caused by items 01/red-team-hardening-01 already merging earlier in this same automate run, after the requirement was authored on 2026-09-21. Worker must use the CORRECTED anchors above, not the requirement's own stale citations for these two specific facts (the rest of the requirement was independently re-verified as accurate). |
| `code-reviewer.md`'s Self-heal-lens paragraph already modified by item 01 — risk of accidentally re-editing/duplicating | LOW | Explicitly flagged in the File Impact Map: this item's reviewer-side change is a SEPARATE new paragraph, not a further edit to the line-182 paragraph item 01 already completed. |
| `ARCHITECTURE_CONTRACTS.md`'s worker raise-log already has one row from item 01 | LOW | This item adds a NEW row (naming itself) after the existing one — do not edit or duplicate item 01's row. |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-09-23-test-integrity-guard.md
```
