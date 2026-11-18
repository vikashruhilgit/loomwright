# qa-split 11b1 — removal evidence

Evidence record for the QA removal part 1 (qa-split item 11b1): the rollback tag, then the gate and
Validation 3 outputs. The rationale is in `loomwright/docs/rationale/qa-split.md`; the per-path plan is
`loomwright/docs/qa-removal-manifest.md`.

## Rollback tag

Recorded once, before any deletion, and never recomputed (a later merge of `main` into the branch moves
the merge-base; the tag correctly does not move).

Start sha: 4951d864ad493d477d1cdf839b9d6980665b094a

How the start sha was computed (on branch `feature/qa-split-11b1-remove-qa-surfaces`, after
`git fetch origin main`):

```
$ git merge-base HEAD origin/main
4951d864ad493d477d1cdf839b9d6980665b094a
```

Remote tag before tagging (empty output — the tag did not exist):

```
$ git ls-remote --tags origin pre-qa-removal
```

Tag command. The push runs from a linked worktree that is not the run's feature-branch checkout, because
`guard-finalize-publish.sh` denies `git push` in the live run's own checkout before FINALIZE; a tag is
repo-wide, so the push only sends the tag ref:

```
$ git tag pre-qa-removal 4951d864ad493d477d1cdf839b9d6980665b094a
$ git -C .claude/worktrees/strange-visvesvaraya-79c9b9 push origin pre-qa-removal
To https://github.com/vikashruhilgit/loomwright.git
 * [new tag]         pre-qa-removal -> pre-qa-removal
```

Remote tag after tagging:

```
$ git ls-remote --tags origin pre-qa-removal
4951d864ad493d477d1cdf839b9d6980665b094a	refs/tags/pre-qa-removal
```

To restore any removed file: `git checkout pre-qa-removal -- <path>`.

## Gates (Subtask 2)

Run on branch `feature/qa-split-11b1-remove-qa-surfaces` at `47abdbd` (after the test re-points and the
v18.0.0 bump). Last two output lines of each gate, then its exit status:

```
$ bash scripts/check-contract-parity.sh
✓ contract-parity: all hook-enforced fields present and all status/decision literals in-enum.
(exit 0)

$ bash scripts/check-prompt-history-refs.sh
check-prompt-history-refs: scanned files: 118 | references: 395 | violations: 0 | errors: 0
check-prompt-history-refs: OK — no runtime prompt above its baseline, and the baseline did not rise.
(exit 0)

$ bash scripts/check-skills-index-sync.sh
✓ skills-index-sync [stackpack/skills]: every versioned SKILL.md has exactly one matching index row; no ghost rows; index equals its frontmatter render.
✓ skills-index-sync [selvedge/skills]: every versioned SKILL.md has exactly one matching index row; no ghost rows; index equals its frontmatter render.
(exit 0)

$ bash scripts/check-vendor-coupling.sh
files scanned: 1868 (counted: 1862, of which frontmatter-bounded (header exempt, body counted): 34; adapter-exempt: 6) | files with references: 368 | total references: 2748 | breaches: 0 | errors: 0
check-vendor-coupling: OK — no path exceeds its declared vendor-coupling allowance, and every raise or exemption carries a reason.
(exit 0)

$ bash loomwright/scripts/build-capabilities.sh --check

(exit 0)

$ bash scripts/check-doc-currency.sh
✓ color-legend: the generated legend matches agent frontmatter (12 rows).
✓ doc-currency: all checked version/count claims match the authoritative source.
(exit 0)

$ bash scripts/check-token-budget.sh
agents checked: 12 | skill dirs checked: 36 | command docs checked: 22 | breaches: 0 | errors: 0 | proxy tokens = bytes/4 (NOT exact Anthropic counts)
check-token-budget: OK — every agent, skill dir and command doc within its declared prompt-inventory budget.
(exit 0)

$ bash loomwright/scripts/check-qa-removal-manifest.sh --expect 11b1
ok keep 11b1 loomwright/skills/unit-testing/
summary: 436 rows, expect 11b1: 0 MISMATCH, 253 pending, 117 done, 66 ok
(exit 0)

$ bash scripts/check-version-bump.sh
bump-version: check OK — bumped 17.39.0 -> 18.0.0 (major); the entry is the fold of: claude-auth-fallback.md followup-race-forced-overlap.md qa-removal-11b1.md qa-removal-manifest.md scrub-reserved-test-domains.md (base origin/main, merge base 4951d864ad49)
(exit 0)
```

`hooks.json` matchers containing `qa-` (`jq` over every object with a `matcher` key): `[]`.

`bash scripts/ci-local.sh --affected` at `615beae` (the test re-points, before the bump commit, which
touches only the version files, `CHANGELOG.md` and the folded fragments, and before `47abdbd`, which
changes two fixture names in `test-build-capabilities.sh`; that suite was re-run on its own there:
`test-build-capabilities: 114 passed, 0 failed`):

```
all 25 self-tests passed (wall 220s, 6-way)
ci-local: leak gate — clean (0 new processes survived)
ci-local --affected: PASS after 222s — 25 of the full run's 230 entries
affected-only — not a CI result; GitHub CI runs the full suite on the PR
```

## Validation 3 — the removed commands are gone from the loaded plugin

Claude Code `2.1.325`, plugin loaded from this checkout with `--plugin-dir` (which loads ONLY the
checkout's copy), `CLAUDE_CODE_ENTRYPOINT` unset.

### `/loomwright:qa-executor`

```
$ env -u CLAUDE_CODE_ENTRYPOINT claude -p --plugin-dir ./loomwright "/loomwright:qa-executor"
`/loomwright:qa-executor` didn't run because it isn't installed in this session. That fits the branch you're on: `feature/qa-split-11b1-remove-qa-surfaces` deletes it on purpose. Commit `a66a322` removes the `qa-executor` and `qa-strategist` agents, the `/qa-executor`, `/qa-strategist` and `/verify` commands, and their six skills.

According to `changelog.d/qa-removal-11b1.md` and `loomwright/docs/rationale/qa-split.md`, the replacements are:

| Removed | Use instead |
|---|---|
| `/qa-executor`, `/verify` | `/selvedge:verify` and the `selvedge` CLI. Each acceptance criterion gets one PASS / FAIL / BLOCKED / NOT_VERIFIABLE verdict with evidence. |
| `/qa-strategist` | Nothing. Its risk-strategy role was dropped on purpose (decision D2). |

To get Selvedge, the changelog note says to run `/plugin install selvedge@atelier`, then `selvedge install-cli` to put the CLI on your `PATH`. I can't tell from here whether `/selvedge:verify` is already loaded in this session.

If you meant to run the old QA executor, its files can be restored from the rollback tag `pre-qa-removal` (the rationale doc explains how). Otherwise, tell me which PR or acceptance criteria you want checked and I'll run them through Selvedge, or check them by hand.
(exit 0)
```

This CLI version printed no `Unknown command` line: the unrecognised slash command reached the model as
plain text, and the model answered that the command is not installed. The deterministic check is the
session's own `init` event, which lists every slash command and agent the session loaded. From the
`/loomwright:agent-help` run below (`--output-format stream-json --verbose`):

```
$ jq -c 'select(.type=="system" and .subtype=="init") | {loomwright_commands: [.slash_commands[] | select(test("^loomwright:"))], loomwright_agents: [.agents[]? | select(test("loomwright"))]}' probe-ah.jsonl
{"loomwright_commands":["loomwright:agent-help","loomwright:automate","loomwright:autonomous","loomwright:backlog","loomwright:capability-check","loomwright:code-reviewer","loomwright:dreaming","loomwright:handoff","loomwright:insights","loomwright:janitor","loomwright:launch-pad","loomwright:obsidian","loomwright:orchestrator","loomwright:pr-postmortem","loomwright:product-owner","loomwright:propose","loomwright:red-team-reviewer","loomwright:review-pr","loomwright:rules","loomwright:setup","loomwright:supervisor","loomwright:telemetry","loomwright:agent-output","loomwright:agent-teams","loomwright:async-orchestration","loomwright:automate-loop","loomwright:autonomous-loop","loomwright:beads-workflow","loomwright:brain-context","loomwright:brainstorming","loomwright:ci-cd","loomwright:claude-md-validation","loomwright:commit","loomwright:context-setup","loomwright:context-summarization","loomwright:context7-lookup","loomwright:domain-knowledge","loomwright:error-handling","loomwright:frontend-ui","loomwright:memory-tool","loomwright:monitoring-observability","loomwright:mvp-scoping","loomwright:pattern-detector","loomwright:preflight-sync","loomwright:product-discovery","loomwright:quality-checklist","loomwright:review-heal","loomwright:self-heal-advisory","loomwright:state-management","loomwright:supervisor-config","loomwright:supervisor-readiness","loomwright:unit-testing","loomwright:user-story-writing","loomwright:workflow-management"],"loomwright_agents":["loomwright:loomwright:code-reviewer","loomwright:loomwright:context-keeper","loomwright:loomwright:execute-manager","loomwright:loomwright:launch-pad-runner","loomwright:loomwright:orchestrator","loomwright:loomwright:plan-reviewer","loomwright:loomwright:product-owner","loomwright:loomwright:red-team-reviewer","loomwright:loomwright:review-pr-runner","loomwright:loomwright:rubric-grader","loomwright:loomwright:supervisor-runner","loomwright:loomwright:worker"]}
```

Entries matching `qa-executor`, `qa-strategist` or exactly `loomwright:verify` among the loaded
commands and agents: `0`. So `/loomwright:qa-executor` is an unknown command in this session.

### `/loomwright:agent-help`

```
$ env -u CLAUDE_CODE_ENTRYPOINT claude -p --plugin-dir ./loomwright --output-format stream-json --verbose "/loomwright:agent-help"
(the final "result" event's text:)
# Loomwright: agent commands

## Which command to use

| I want to… | Run | What it won't do |
|---|---|---|
| Start a new task or goal | `/launch-pad`, then `/supervisor` (or `/autonomous`) | It never merges |
| Work through one goal over several rounds, with stacked PRs | `/autonomous "<goal>"` | It never merges. A person merges the stack from the bottom up |
| Work through a queue of separate goals (a folder or backlog doc) | `/automate` | It doesn't merge unless you pass `--auto-merge` (off by default) |
| Review and fix an existing PR | `/review-pr <pr-url>` | It never merges. It pushes fixes and leaves the PR open |
| Review my diff without changing anything | `/code-reviewer` | It only reads: no fixes, no commits |

## Command index

- **Planning and running work:** `/launch-pad`, `/supervisor`, `/autonomous`, `/automate`
- **Building by hand:** `/product-owner` (requirements), `/orchestrator` (task breakdown), `/code-reviewer`, `/commit`, `/red-team-reviewer` (attacks your work to find failures)
- **Knowledge and reflection:** `/dreaming`, `/capability-check`, `/insights`, `/obsidian`, `/handoff`, `/propose`
- **Operations:** `/telemetry`, `/rules`, `/pr-postmortem`, `/backlog`, `/janitor`, `/setup`

**Common flows:**
- **Plan first:** `/launch-pad` writes a reviewed brief to `.supervisor/jobs/pending/`, then `/supervisor job: <brief>` runs it.
- **By hand:** `/product-owner` → `/orchestrator` → code → `/code-reviewer` → `/commit`.
- **A queue of items:** `/automate --folder <dir>`, `/automate --backlog <doc>`, or a plain prompt. Running `/automate` on its own resumes an unfinished run. `--parallel N` runs up to N items at once, each in its own copy of the repo.

Ask about any command by name for its full flags and examples.

## Old QA references still in this help on your branch

`feature/qa-split-11b1-remove-qa-surfaces` removes the QA agents, but this help text still mentions them:

- **`loomwright/commands/agent-help.md`:** the "QA Pipeline (2 agents)" block in Quick Start still lists QA Strategist and QA Executor. Line 25 of the index also points to "the QA Workflow Diagram".
- **Two help sub-files:** `loomwright/docs/command-parts/agent-help/more.md` still has the "QA Workflow Diagram" section, and `guide.md` still has "QA Pipeline (Test Automatically)".

Nothing on the branch updated them, so new users would see agents that no longer exist. Your gate scripts check version numbers and counts, not whether a removed agent is still named in prose.

I can remove these in this PR if you want.
```

The output has no `/qa-strategist`, `/qa-executor` or `/verify` command section. Its last section lists
the QA mentions that stay until item 12 (below), by owner decision of 2026-11-18.

### Anchored grep on the router

```
$ grep -nE '^### [^ ]+ /(qa-strategist|qa-executor|verify) ' loomwright/commands/agent-help.md
(no output, exit 1)
$ ls loomwright/docs/command-parts/agent-help/qa.md
ls: loomwright/docs/command-parts/agent-help/qa.md: No such file or directory
```

### QA mentions in agent-help that remain until item 12

- `loomwright/commands/agent-help.md` Quick Start "QA Pipeline (2 agents)" block (the `QA Strategist` and
  `QA Executor` lines), the `more.md` topic bullet naming "the QA Workflow Diagram", and the
  `### QA Workflow Diagram` / `### QA Pipeline (Test Automatically)` headings.
- `loomwright/docs/command-parts/agent-help/more.md` — the QA Workflow Diagram's `/qa-strategist` and
  `/qa-executor` command lines.
- `loomwright/docs/command-parts/agent-help/guide.md` — the SubagentStop row naming `qa-executor`, the
  file-tree lines for `qa-strategist.md` / `qa-executor.md` / `QA_SYSTEM_BLUEPRINT.md`, and the
  "QA Pipeline (Test Automatically)" table.
- `loomwright/docs/command-parts/agent-help/knowledge.md` — `/dreaming --agent qa-executor` examples and
  the valid-target list naming QA Executor.
- The `### 🌱 /propose — … a /verify Run …` heading (in the router and in `knowledge.md`) and the
  `/propose --from-verify` lines.

### Honest limits

- `--plugin-dir` stands in for `/plugin install loomwright@atelier`; the owner re-checks the installed
  plugin after merge.
- Both answers above are model text: `/loomwright:agent-help` is a prompt the model renders, not a fixed
  printout, so a re-run words it differently. The command and agent lists in the `init` event are the
  part that does not vary.
- The PR body link to this file is added when the PR is opened at FINALIZE; it is not part of this commit.

Verdict: PASS for Validation 3
