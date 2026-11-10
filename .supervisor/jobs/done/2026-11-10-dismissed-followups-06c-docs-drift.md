# Supervisor Job: Dismissed follow-ups 06c — doc, header and evidence-file drift (16 findings)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (two unrelated worktrees — `wt-842` on `fix-842` in another session's scratchpad and `.claude/worktrees/confident-gagarin-ad5777` on `fix/phase-wait-late-init-session-id` — not touched by this job)
- **Source requirement:** .supervisor/requirements/dismissed-followups/06c-docs-and-evidence-drift.md
- **Base commit:** e1e0750f9f9636020f99cca29404506e85ff029a

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Markdown docs, bash 3.2 comments/headers, one generator string and its generated `capabilities.json`; no new stack |
| 2 | Dependency Availability | GO | Every fix edits an existing file; F117 reads the pinned ledger `git show 1df5d34:.supervisor/postmortem/results.jsonl` (read-only, the commit `RULES_BASELINE.md` already pins) |
| 3 | Architecture Fit | GO | Wording, one published contract string (F122, regenerated through `build-capabilities.sh`) and one test leg; no gate, merge executor or fail-mode change |
| 4 | Scope vs Supervisor Capability | GO | 16 findings, 21 modified + 2 created files. `context-bound`'s file predicate fires (23 > 12), but the brief stays single-agent on purpose: the threshold allows a split and never requires one, nearly every edit is one clause, and the whole change is far under 800 lines, so one worker's context holds it |
| 5 | Hard Blockers | CAUTION | `docs/result-schemas/automate-run/parallel-lanes.md` (where F108's table really lives — the requirement names its parent `automate-run.md`), `test-build-capabilities.sh` (F122's leg), `commands/pr-postmortem.md`, `skills/pr-postmortem/SKILL.md`, `docs/command-parts/agent-help/ops.md`, `docs/result-schemas/postmortem-result.md` (F125's blurbs), the evidence file and the changelog fragment sit outside the requirement's `## Touches` — asked once at Phase 6 (`LP-SCOPE`) |

**Overall Verdict:** CAUTION

## Task
**Goal:** Close the 16 owner-deferred review findings of `dismissed-followups/06c`: re-verify each on the base commit, fix it (with a regression leg where it changes emitted output), or record a one-line reason it is not reproducible / not worth fixing.

**Problem Statement:**
The owner needs the 16 `follow-up` findings bundled from the `/automate` dismissed drafts acted on, because "follow-up" decisions were never turned into work.
Re-verified by Launch Pad at e1e0750: all 16 are still present (each anchor in `## Touched-file invariants` and the Design bullets greps in its file). They are stale restated wording (an answer-file table, a deliver-pending invocation, a wave-build paragraph, a telemetry example, a postmortem blurb), comments that point at the wrong file or under-describe their own scope, a self-contradicting contract paragraph and footnote, a dated schema-log entry, a missing hook-editor pointer, and one published contract string (`capabilities.json`'s `host_switch.effect`) that is broader than the classification it summarises.
Success looks like: every finding has one disposition (fixed, or recorded with a reason) in a committed evidence file, the one emitted-string fix has a leg that fails on the base, `capabilities.json` is regenerated (not hand-edited), and CI is green.

**Design (chosen at planning; the evidence file records any deviation with its reason):**
- **Dispositions live in a committed evidence file, not in the requirement file** (`.supervisor/requirements/` is gitignored). The worker writes `docs/evidence/dismissed-followups-06c.md` with one row per finding: `F<id> | fixed | <file> (<what changed>)[ :: <test file> <leg>]` or `F<id> | recorded | <one-line reason>`, plus the re-verify command it ran on the base commit.
- **F108** — `docs/result-schemas/automate-run/parallel-lanes.md` §"Lane inbox answer file": the `answers` row reads `{"<question text>": "<label[,label…]>", …}` — keyed by the question's text (the `lane-answer` input is index-keyed; `_lanes_validate_answers` re-keys it), both writers alike; the `note` row's policy cell reads `` `null` — a policy carries no note `` (`_lanes_policy_apply` writes `note: null`).
- **F112** — `test-read-rules.sh` (j2) comment: `the no-regression guard for the store's repo-wide rule (applies_to: null in .agent/rules/process.json)`. Comment-only.
- **F123** — `docs/CAPABILITIES_CONTRACT.md`'s Row key bullet: `a glob of \`*\` and \`?\` only (\`validate-*-result.py\`) matched against a script's basename — any other character, \`[…]\` included, is literal (an unmatched basename fails safe to \`unknown\`)`; `build-capabilities.sh`'s own row-key comment (`a script file name or a shell glob`) gets the same `*`/`?`-only wording. `HOOKS.md` does not restate it (grep at base: no `shell glob`), so it is not changed for F123.
- **F296** — `scripts/check-doc-currency.sh` header: the per-agent, skill and command mirror tables (`Skill size ceilings`, `Command size ceilings`) are all synced by `scripts/check-token-budget.sh`.
- **F309** — `guard-lane-wait-armed.sh` header item 5 and the `The lane states come from` comment point at `automate-lanes.d/status.sh` (sourced through `automate-lanes.sh`). Comment-only; `LANES_SH` and the sourcing are unchanged.
- **F321** — `skills/automate-loop/lanes.md`: the `wave-build` paragraph ("Wave close") says it runs the local CI and makes the release step the last commit **when the project has `scripts/ci-local.sh` / `scripts/bump-version.sh` (otherwise that step is skipped and its line says so)**; step 9's `(it runs the local CI)` gets the same `when present` qualifier.
- **F324** — `docs/PITFALLS.md` lane-park entry: `lane-answer <lane_dir> --deliver-pending --owner-command '<cmd>'` (every other copy — `automate-lanes.sh` usage, `relay.sh`, `lanes.md` step 8 — already carries the flag).
- **F337** — `docs/TELEMETRY.md` Issue body template `## Raw Data` example: `"score": 9`, `"score_float": 9.0`, `"score_bucket": "high"` (a PASS with no findings scores 9; `score_f >= 8` buckets `high`), and the `status` placeholder kept as is.
- **F117** — `docs/RULES_BASELINE.md`'s post-rules row gains one sentence naming ledger line 85: it is counted by neither row (it postdates the baseline's 84 records and is the last line before the window). The PR number on line 85 is read from the pinned ledger (`git show 1df5d34:.supervisor/postmortem/results.jsonl | sed -n 85p`) and written as read; if it is not #160 the evidence row says what it is.
- **F122 — the emitted contract string is corrected:** `build-capabilities.sh`'s `HOST_EFFECT` reads `Host mode is on only when env is exactly 1; then no hook writes the session's working tree: gate and redirects-class hook state goes to the state_dir_env directory when it is valid, otherwise gate state goes to a per-user temp root; a skips-class hook never writes, whatever the state dir.` `capabilities.json` is regenerated with `bash loomwright/scripts/build-capabilities.sh` (never hand-edited) and `--check` passes. New leg in `test-build-capabilities.sh` beside the `(HM)` legs: `.host_switch.effect` names both class words of `docs/HOOKS.md` §"Host mode" — `redirects` and `skips` (the base string names neither; its `skipped` is not `skips`).
- **F130** — `docs/CORE_CONTRACT.md` §4: `resolve-loomwright-root.sh is the **one place the core reads the harness's install-root variable**` (the adapter-classed exceptions in "Honest state" stay as they are).
- **F276** — `docs/ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" bold paragraph: drop the `EXCEPT the ¹-marked rows above (…)` clause and its row list — `measured` is never enforced; ¹ only marks a row re-measured live. Footnote ¹'s pointer `the authoritative enumeration of the marked set is the bold paragraph at the end of this section` would then point at nothing, so it is replaced by `every row is marked`; the footnote sentences that still say `The \`measured\` cell/field above reflects this … re-measure` for retired figures are put in the past tense (`reflected`). Budget and measured cells are not touched (`check-token-budget.sh` mirror sync).
- **F361** — `automate-lanes.d/status-read.sh` comment: `_lanes_render_terse <status JSON> — the renderer body of lane-status's default view (status.sh appends the backlog pointer line): …`.
- **F041** — `docs/result-schemas/schema-versioning.md` 2026-10-05 entry: `current-rebuild` repairs an unset **or stale-`done`** `## Current` at RESUME (one clause; the entry stays a dated log).
- **F073** — `docs/HOOKS.md` §"Hook Table" preamble gains one line: a new or changed leaf's script writes need a row in `build-capabilities.sh`'s writes audit table, then `capabilities.json` regenerated — without it the leaf publishes `writes: ["unknown"]` (fail-closed).
- **F125** — "categorize each evidenced review round" (rounds with no concrete evidence are omitted, Step 3) in: `commands/pr-postmortem.md` frontmatter `description` and its line-11 `buckets each review round`, `skills/pr-postmortem/SKILL.md` frontmatter `description`, `docs/command-parts/agent-help/ops.md`'s `/pr-postmortem` Purpose and `docs/result-schemas/postmortem-result.md`'s opening sentence. `capabilities.json` (it carries the command description) is regenerated in the same commit as F122. `commands/agent-help.md` only points at `ops.md` and is not changed; the SKILL.md `### Step 3 — Categorize each review round` heading is not renamed (its body already says "that has concrete evidence").
- **Not modified although listed in Touches:** `CLAUDE.md`, `automate-run.md` (the table lives in its split file), `runfile.sh` / `relay.sh` / `status.sh` / `automate-lanes.sh` / `automate-wave.sh` / `resolve-loomwright-root.sh` / `send-telemetry-core.sh` / `set-otel-resource-attrs.sh` / `stamp-requirement-status.sh` / `bump-version.sh` / `check-token-budget.sh` / `ci-local.sh` (each is the correct side a doc is corrected against), `skills/autonomous-loop/SKILL.md` (no finding lands there at base).

## Acceptance Criteria

- [ ] AC1. Given each of the 16 findings, when the worker starts, then it re-runs the finding's anchor check on its own base (the `grep -nF` of the quoted anchor in `## Touched-file invariants` or in the Design bullet) and the committed evidence file `docs/evidence/dismissed-followups-06c.md` contains, per finding, the check run and exactly one disposition: `fixed` naming the file and the change (and the test leg, where one exists), or `recorded` with a one-line reason; the PR body links to the file.
- [ ] AC2 (F122). Given `build-capabilities.sh` and the regenerated `capabilities.json`, when `bash loomwright/scripts/test-build-capabilities.sh` runs, then a new `(HM)` leg asserts `.host_switch.effect` contains both `redirects` and `skips`; run against the base-commit generator (`git show e1e0750:loomwright/scripts/build-capabilities.sh` copied into a scratch plugin root, `--out` a scratch file), the leg fails, and it passes on the fixed tree — the leg name and the red line are in the evidence file; `bash loomwright/scripts/build-capabilities.sh --check` exits 0.
- [ ] AC3 (F108, F324, F321). Given the fixed tree, when read: `parallel-lanes.md`'s `answers` row says the keys are the question text and the policy `note` cell says `null`; `PITFALLS.md`'s deliver-pending invocation carries `--owner-command '<cmd>'`; `lanes.md`'s `wave-build` paragraph and step 9 make the CI and release steps conditional on `scripts/ci-local.sh` / `scripts/bump-version.sh` being present.
- [ ] AC4 (F337, F117, F130, F276, F041, F073, F123). Given the fixed tree, when read: the TELEMETRY Raw Data example reads `"score": 9` / `9.0` / `"high"`; `RULES_BASELINE.md` names ledger line 85 as counted by neither row; `CORE_CONTRACT.md` §4 no longer says the resolver is the one place the variable is read; `ARCHITECTURE_CONTRACTS.md`'s bold paragraph has no `EXCEPT the ¹-marked rows` clause; the schema-versioning entry names the stale-`done` repair; `HOOKS.md` points hook editors at the writes audit; `CAPABILITIES_CONTRACT.md` and the `build-capabilities.sh` row-key comment say `*` and `?` only.
- [ ] AC5 (F112, F296, F309, F361). Given the fixed tree, when the comments are read: `test-read-rules.sh` (j2) names the store's repo-wide rule, not "the one rule"; `check-doc-currency.sh`'s header names all three mirror tables; `guard-lane-wait-armed.sh` places `_LANES_WAIT_LIVE` and `_lanes_quick_state` in `automate-lanes.d/status.sh`; `status-read.sh`'s `_lanes_render_terse` comment names status.sh's appended backlog pointer. No code line changes in those four files (`git diff -U0` shows comment lines only).
- [ ] AC6 (F125). Given the fixed tree, when `git grep -niE "(categorizes?|buckets) each review round" -- loomwright/` runs (excluding `CHANGELOG.md`, `docs/evidence/` and the deliberately kept `### Step 3 — Categorize each review round` heading in `skills/pr-postmortem/SKILL.md`), then it prints nothing — this covers SKILL.md's `categorizes each review round` description too, and `capabilities.json`'s `/pr-postmortem` description equals the command frontmatter's.

**Validation**
- [ ] V1. `bash scripts/ci-local.sh --affected` passes, including `check-prompt-history-refs.sh` (no finding id, PR number or incident story added to a prompt file — `lanes.md`, `pr-postmortem` command/skill, `ops.md`; the F-ids live only in the evidence file), `check-token-budget.sh` (`pr-postmortem` command has ~200 tokens of headroom — the edit adds one word per blurb), `test-citation-drift.sh` (no bare `file:N` in new prose) and `check-doc-currency.sh`.
- [ ] V2. `bash scripts/check-version-bump.sh` passes; the PR carries `changelog.d/dismissed-followups-06c-docs-and-evidence-drift.md` and no hand-edited version file.

## Scope widening
- docs/evidence/dismissed-followups-06c.md
- loomwright/commands/pr-postmortem.md
- loomwright/docs/command-parts/agent-help/ops.md
- loomwright/docs/result-schemas/automate-run/parallel-lanes.md
- loomwright/docs/result-schemas/postmortem-result.md
- loomwright/scripts/test-build-capabilities.sh
- loomwright/skills/pr-postmortem/SKILL.md
- accepted: LP-SCOPE 2026-11-10

## File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| docs | `loomwright/docs/result-schemas/automate-run/parallel-lanes.md` (29), `loomwright/docs/CAPABILITIES_CONTRACT.md` (116), `loomwright/skills/automate-loop/lanes.md` (110), `loomwright/docs/PITFALLS.md` (92), `loomwright/docs/TELEMETRY.md` (2609 — the one example block), `loomwright/docs/RULES_BASELINE.md` (303), `loomwright/docs/CORE_CONTRACT.md` (353), `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (1066 — one paragraph + footnote), `loomwright/docs/result-schemas/schema-versioning.md` (71), `loomwright/docs/HOOKS.md` (127), `loomwright/commands/pr-postmortem.md` (79), `loomwright/skills/pr-postmortem/SKILL.md` (216), `loomwright/docs/command-parts/agent-help/ops.md` (109), `loomwright/docs/result-schemas/postmortem-result.md` (259) | `docs/evidence/dismissed-followups-06c.md` | HIGH |
| scripts | `loomwright/scripts/build-capabilities.sh` (588 — one string + one comment), `loomwright/capabilities.json` (1381 — regenerated), `loomwright/scripts/test-build-capabilities.sh` (447 — one leg), `loomwright/scripts/test-read-rules.sh` (939 — one comment), `scripts/check-doc-currency.sh` (359 — header), `loomwright/scripts/guard-lane-wait-armed.sh` (177 — comments), `loomwright/scripts/automate-lanes.d/status-read.sh` (799 — one comment) | `changelog.d/dismissed-followups-06c-docs-and-evidence-drift.md` | HIGH |

New responsibilities get no new module: every fix is a wording change inside the surface that owns it, one generator string, or one assertion appended to the suite that already pins that generator's `host_switch` (`test-build-capabilities.sh`'s `(HM)` block, reusing its `ok`/`no`/`q` helpers), so appending to the large files (`TELEMETRY.md`, `ARCHITECTURE_CONTRACTS.md`, `build-capabilities.sh`, `capabilities.json`, `test-read-rules.sh`, `status-read.sh`) is the single-authority form — each is the one home of the sentence it corrects. No helper is copied.

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
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.
  - id: process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

## Touched-file invariants

> Grounded at base `e1e0750f9f9636020f99cca29404506e85ff029a`. The worker re-checks every entry before hand-back.

- **`loomwright/scripts/build-capabilities.sh`** — keep: `capabilities.json` is its output, never hand-edited; `--check` (`--check     regenerate to a temp file and compare byte-for-byte with <plugin-root>/capabilities.json`) stays the CI staleness gate; exit codes (`# exit: 0 ok · 1 stale (--check) or a fail-CLOSED source inconsistency · 2 usage`); the host-row glob conversion (`within a basename; every other non-alphanumeric character literal).`) is NOT changed — F123 corrects the docs to it. Fix sites: `HOST_EFFECT="Host mode is on only when env is exactly 1; then no hook writes the session's working tree: hook state goes to the state_dir_env directory when it is valid` and the comment `row is keyed by the FIRST backticked token of its first cell — a script file name or a shell glob`. Pinned by: `loomwright/scripts/test-build-capabilities.sh`, `scripts/test-ci-local.sh`, `scripts/test-bump-version.sh` (both run the generator), `loomwright/scripts/test-automate-lanes.d/04-fleet-closeout-to-optout.sh`.
- **`loomwright/capabilities.json`** — keep: generated only (`bash loomwright/scripts/build-capabilities.sh`), regenerated AFTER both the `HOST_EFFECT` edit and the `commands/pr-postmortem.md` description edit, in one commit with them. Fix sites (generated): `"effect": "Host mode is on only when env is exactly 1;` and `"description": "Read-only post-hoc analysis of an existing PR — categorize each review round`.
- **`loomwright/scripts/test-build-capabilities.sh`** — keep: every leg; the new leg reuses `ok() { pass=$((pass + 1)); echo "ok   $1"; }`, `no()` and `q() { local e="$1"; shift; jq -r "$@" "$e" "$tmp/a.json"; }`, and sits beside `ok "(HM) host_switch = {env: LOOMWRIGHT_HOST_MODE, state_dir_env: LOOMWRIGHT_HOST_STATE_DIR, effect: <non-empty>}"`.
- **`loomwright/scripts/guard-lane-wait-armed.sh`** — a `Stop` hook (`hooks.json`: `"command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/guard-lane-wait-armed.sh\" || true"`); keep: code untouched, its allow shape (`allow() { printf '{}\n'; exit 0; }`) and `LANES_SH="${HOOK_DIR:+$HOOK_DIR/}automate-lanes.sh"` (it still sources `automate-lanes.sh`, which sources `automate-lanes.d/status.sh`). Fix sites: `#   5. some lane is LIVE (its quick state is in automate-lanes.sh's \`_LANES_WAIT_LIVE\`` and `# The lane states come from \`_lanes_quick_state\` (automate-lanes.sh, sourced)`. Pinned by: `loomwright/scripts/test-guard-lane-wait-armed.sh`, `test-automate-lanes-modules.sh`, `test-automate-lanes.d/08-scope-regate.sh`, `test-worktree-audit.sh`.
- **`loomwright/scripts/automate-lanes.d/status-read.sh`** — keep: code untouched (`_lanes_render_terse() { jq -r "$_LANES_RENDER_HEAD"' hdr, (.lanes[] | lane1)' <<<"$1"; }`); the backlog pointer stays printed in `status.sh` only (`# The backlog pointer: printed HERE, after the renderer (never inside _lanes_render / _lanes_render_terse,`). Fix site: `# _lanes_render_terse <status JSON> — lane-status's default view: the header line, then each lane's first`. Pinned by: `loomwright/scripts/test-automate-lanes.d/01-create-to-wait.sh`, `test-automate-next-step.sh`.
- **`loomwright/scripts/test-read-rules.sh`** — keep: every leg; fix site the comment `# no-regression guard for the one rule the plugin's own store ships (.agent/rules/process.json).` Pinned by: `loomwright/scripts/test-citation-drift.sh` (pinned citations into this file — the comment edit must not shift a pinned line; re-run it).
- **`scripts/check-doc-currency.sh`** — keep: code and the scan set untouched; fix site the header lines `# ARCHITECTURE_CONTRACTS.md §"Prompt Token Budgets" per-agent mirror table's budget` / `# cells are mechanically synced to prompt-token-budgets.json by`. Mirror: `scripts/check-token-budget.sh` (`SKILLS_MIRROR_HEADING="Skill size ceilings"`, `COMMANDS_MIRROR_HEADING="Command size ceilings"`). Pinned by: `scripts/test-check-doc-currency.sh`.
- **Doc mirrors the fixes are corrected against (read, not modified):** `relay.sh` — `'{answers: $a, note: null, source: "policy", policy_sha: $sha, gate: $gate, via: "policy", at: $at}'` and `# _lanes_validate_answers <question_file> <input JSON> — prints {<question>: "<label[,label…]>"} or`; `automate-lanes.sh` — `#   lane-answer <lane_dir> --deliver-pending --owner-command '<cmd>' [--without-gate-optout]`; `automate-wave.sh` — `_wb "ci — skipped (no scripts/ci-local.sh; the wave PR's CI is the gate)"`; `send-telemetry-core.sh` — `if decision == "PASS" and new_blocking == 0 and new_high == 0:` / `base = 9.0` and `elif score_f < 8:`; `runfile.sh` — `` `done` and not the LAST picked item ``; `status.sh` — `[ "$json" = 1 ] || printf '%s\n' "backlog: every requirement item's state — run /backlog"`.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-build-capabilities.sh` — F122 `(HM)` `host_switch.effect` names `redirects` and `skips` | restore the base `HOST_EFFECT=` line (`hook state goes to the state_dir_env directory when it is valid, otherwise gate state goes to a per-user temp root and every other hook write is skipped.`) in a scratch copy of `loomwright/scripts/build-capabilities.sh`, build with `--out` a scratch file, and run the leg's jq test on it |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Dismissed follow-ups 06c — 16 doc/header/contract-string fixes, the F122 leg, evidence file and fragment | AC1–AC6, V1, V2 | 21 modify, 2 create | `skills/unit-testing/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "docs/evidence/dismissed-followups-06c.md"}
  - {kind: "file", path: "changelog.d/dismissed-followups-06c-docs-and-evidence-drift.md"}
  - {kind: "symbol", path: "loomwright/scripts/build-capabilities.sh", name: "skips-class"}
  - {kind: "symbol", path: "loomwright/docs/PITFALLS.md", name: "--deliver-pending --owner-command"}
  - {kind: "symbol", path: "loomwright/commands/pr-postmortem.md", name: "each evidenced review round"}
requires: []
lanes:
  - "loomwright/docs/result-schemas/automate-run/parallel-lanes.md"
  - "loomwright/docs/CAPABILITIES_CONTRACT.md"
  - "loomwright/skills/automate-loop/lanes.md"
  - "loomwright/docs/PITFALLS.md"
  - "loomwright/docs/TELEMETRY.md"
  - "loomwright/docs/RULES_BASELINE.md"
  - "loomwright/docs/CORE_CONTRACT.md"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/docs/result-schemas/schema-versioning.md"
  - "loomwright/docs/HOOKS.md"
  - "loomwright/commands/pr-postmortem.md"
  - "loomwright/skills/pr-postmortem/SKILL.md"
  - "loomwright/docs/command-parts/agent-help/ops.md"
  - "loomwright/docs/result-schemas/postmortem-result.md"
  - "loomwright/scripts/build-capabilities.sh"
  - "loomwright/capabilities.json"
  - "loomwright/scripts/test-build-capabilities.sh"
  - "loomwright/scripts/test-read-rules.sh"
  - "scripts/check-doc-currency.sh"
  - "loomwright/scripts/guard-lane-wait-armed.sh"
  - "loomwright/scripts/automate-lanes.d/status-read.sh"
  - "docs/evidence/dismissed-followups-06c.md"
  - "changelog.d/dismissed-followups-06c-docs-and-evidence-drift.md"
external_requires: []
```

The fragment is the PR's only `changelog.d/` entry (one group-level summary, no per-finding counts). The version bump is folded by `bash scripts/bump-version.sh` at release, never hand-edited.

## Parallelism Analysis

### Dependency Graph
```
single-agent (no fan-out)
```

### Batch Plan
- **Batch 1:** Subtask 1
- **Recommended workers:** 1
- **Estimated batches:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): `parallel-lanes.md`, `test-build-capabilities.sh`, the four F125 blurb files, the evidence file and the fragment sit outside the requirement's `## Touches` | MEDIUM | Asked once at Launch Pad Phase 6 (`LP-SCOPE`) before save |
| Prior churn (postmortem ledger): `ARCHITECTURE_CONTRACTS.md` (78), `capabilities.json` (19), `TELEMETRY.md` (17), `PITFALLS.md` (15), `HOOKS.md` (13) carry prior churn (`drain_churn`, `self_heal_churn`, `convention_mismatch`), with a `self_heal_miss` in prior rounds | HIGH | Each edit is one clause in place, matched to its authority (the two advisory house rules); `capabilities.json` only through the generator plus `--check`; `ARCHITECTURE_CONTRACTS.md` edit leaves every budget cell alone so `check-token-budget.sh` mirror sync stays green; `ci-local.sh --affected` before hand-back |
| `capabilities.json` regenerated before the second source edit (F122 vs F125) and left stale | MEDIUM | Regenerate once after both edits; `build-capabilities.sh --check` is in AC2 and in CI |
| F122's new effect string is read by a consumer that matches its old text | LOW | `git grep -nF "hook state goes to the state_dir_env"` before editing; the only base hits are the generator and `capabilities.json` |
| F117's line-85 PR number differs from the finding's "#160" | LOW | Read it from the pinned ledger and write what is there; the evidence row names the read |
| F125's `/pr-postmortem` command description sits ~200 tokens under its budget | LOW | One word per blurb; `check-token-budget.sh` in V1 |
| A concurrent session in this checkout can sweep uncommitted edits (project memory) | LOW | The worker runs in its own worktree and commits once |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-10-dismissed-followups-06c-docs-drift.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-11-10T16:13:23Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/876
- **Branch:** feature/dismissed-followups-06c-docs-drift
- **Files changed:** 23
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 0
- **Heal reason:** needs_human
- **Heal remaining issues:** 3
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** armed
- **Summary:** All 16 dismissed-followups-06c findings fixed in 3 commits (evidence: docs/evidence/dismissed-followups-06c.md; F122 (HM) leg red on base, green on fix). Phase 4.5 round-1 review returned NEEDS_HUMAN: a HIGH gate-configuration lens on the brief-mandated, comment-only guard-lane-wait-armed.sh edit (needs an owner waiver), plus 2 MEDIUM at the fix floor — HOST_EFFECT dropped the "redirected writes skipped without a state dir" clause, and skills/pr-postmortem/SKILL.md line 13 still says "bucket each round". Findings posted to the PR; nothing merged.

## Not verified
- **capabilities.json host_switch.effect external consumer** — no external consumer runs in this repo (subtask 1)
- **GitHub CI on the PR (incl. sdk-spike node step)** — the worker did not push, so CI had not run (subtask 1)
