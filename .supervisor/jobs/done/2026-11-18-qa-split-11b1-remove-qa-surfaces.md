# Supervisor Job: QA removal part 1 — delete the QA agents, commands, skills, hooks and agent memory (manifest rows 11b1), with a migration note

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** dirty (2 untracked dirs: `reports/`, `research_notes/` — not touched by this job), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 2 (untracked dirs; 6 linked worktrees from other sessions, none on this job's branch)
- **Source requirement:** .supervisor/requirements/qa-split/11b1-remove-qa-agents-commands-skills.md
- **Base commit:** 4951d864ad493d477d1cdf839b9d6980665b094a

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Deletions plus Markdown/JSON/bash edits in the plugin's own stack |
| 2 | Dependency Availability | GO | No new dependency; Selvedge already ships in this marketplace (`selvedge/`) |
| 3 | Architecture Fit | GO | Follows the reviewed manifest `loomwright/docs/qa-removal-manifest.md` and its checker |
| 4 | Scope vs Supervisor Capability | CAUTION | ~27 edited files + ~40 deleted; a `context-bound` split into 2 sequential subtasks |
| 5 | Hard Blockers | CAUTION | The plan deletes `loomwright/docs/command-parts/agent-help/qa.md` and edits `loomwright/scripts/fixtures/command-parts/move-only.txt`, both outside the requirement's `## Touches` (owner chose this at Launch Pad `LP-CLARIFY`, 2026-11-18: `test-command-parts.sh` check C fails otherwise — probed); asked once at `LP-SCOPE` |

**Overall Verdict:** CAUTION

## Task
**Goal:** Remove every user-facing QA surface the manifest marks `delete … 11b1` (agents `qa-executor`/`qa-strategist`, commands `qa-executor`/`qa-strategist`/`verify`, six QA skill dirs, the two QA SubagentStop matchers, the tracked `qa-executor` agent-memory dir) in one green release, with only the edits other files need for this PR's own gates, a `changelog.d/` migration note, and `loomwright/docs/rationale/qa-split.md`.

**Problem Statement:**
The plugin maintainer needs the unused QA system gone because every release still pays for it in counts, token budgets and doc gates (owner decision D1; Selvedge replaces it).
Currently, 2 agents, 3 commands and 6 skills of the old QA system ship in Loomwright and nobody runs them. This costs prompt budget, doc-gate drift and review rounds on every change near them.
Success looks like: `check-qa-removal-manifest.sh --expect 11b1` exits 0, every repo gate is green with the new counts, and a `/qa-executor` user reading the changelog knows to install Selvedge.

**Grounding — what breaks when only the deletions land (probed by Launch Pad on a scratch worktree at the base commit, 2026-11-18):** deleting the 11b1 paths alone keeps the manifest gate green (`0 MISMATCH`) but turns these red, each of which this job must fix:
- `scripts/check-doc-currency.sh` — authoritative becomes `agents=12 commands=22 skills=36`, and `hooks=45` once the two matchers go (48 − 3 hook leaves); drift sites: `CLAUDE.md` (lines with "14 agent roles (", "14 markdown prompts", heading "The 14 Agent Roles"), `.claude-plugin/README.md` (agent, skill and hook counts), `loomwright/commands/agent-help.md` ("14 agent roles ("), `.claude-plugin/marketplace.json` and `loomwright/.claude-plugin/plugin.json` descriptions, `loomwright/docs/ARCHITECTURE.md` ("14-agent system"), `README.md` ("14 specialized agents"); plus the generated Color Legend block in `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (regenerate with `bash loomwright/scripts/gen-color-legend.sh --write`). The gate checks only numbers that are claimed, so a drift site is fixed either by the new number or by dropping the number — see "Counts" below for which.
- **Counts (owner decision at `LP-RULE-OVR`, 2026-11-18: honor the house rule):** the two manifest `description` fields (`loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`) keep their counts, updated in place to 12 agent roles, 22 slash commands, 36 skills, 45 quality gate hooks (CLAUDE.md: "update the four counts in place"). Every prose drift site above — `CLAUDE.md`, `README.md`, `.claude-plugin/README.md`, `loomwright/commands/agent-help.md`, `loomwright/docs/ARCHITECTURE.md` — DROPS the number instead of restating a new one (e.g. heading "The Agent Roles", "agent roles (user-facing + internal)", "a multi-agent system", "focused skills", "quality gate hooks (see `hooks.json`)"), including the same-value claims the gate does not scan (e.g. `CLAUDE.md`'s "(42 skills, see `SKILLS_INDEX.md`)"). `scripts/test-check-doc-currency.sh` must stay green (its live-repo legs read the descriptions). The CLAUDE.md heading is an interface (house rule "wording that carries a contract"): its two citers in `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (the "Relocated from `CLAUDE.md` §\"The 14 Agent Roles\"" note and the display-name note) move to `§"The Agent Roles"` in the same change; `git grep -n 'The 14 Agent Roles'` outside `CHANGELOG.md` and `docs/evidence/` prints nothing afterwards.
- `scripts/check-token-budget.sh` — orphaned `.agents`/`.commands`/`.skills` entries in `loomwright/docs/prompt-token-budgets.json`, then ghost mirror rows in `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets".
- `scripts/check-prompt-history-refs.sh` — 11 orphan entries in `loomwright/docs/prompt-history-refs-baseline.json`.
- `scripts/check-skills-index-sync.sh` — ghost rows in `loomwright/skills/SKILLS_INDEX.md` (fix: `bash scripts/check-skills-index-sync.sh --write`).
- `scripts/check-vendor-coupling.sh` — stale `allowances` AND `allowance_reasons` entries in `loomwright/docs/vendor-coupling-manifest.json` for the 5 deleted paths that carry one.
- `scripts/check-contract-parity.sh` — its `MANIFEST` rows for `qa-executor` (QA_RESULT, VERIFY_RESULT) and its `ENUMS` row `agents/qa-executor.md|status|…`.
- `loomwright/capabilities.json` is stale (regenerate with `bash loomwright/scripts/build-capabilities.sh`).
- Test suites: `test-agent-memory-permission.sh`, `test-check-contract-parity.sh`, `test-non-interactive-gates-seam.sh`, `test-build-capabilities.sh`, `test-verify-walkthrough.sh` (74 prompt-surface assertions on the deleted `agents/qa-executor.md`, `commands/verify.md`, `commands/qa-executor.md`, `skills/verify-walkthrough/SKILL.md`), `test-resolve-routing.sh` (the `qa_strategist` read seat's home `commands/qa-strategist.md` is gone) and, once that seat is removed, `adapters/providers/test-lens-roles.sh` (uses `qa_strategist` as its text-role fixture). Probed green with the deletions: `test-check-qa-removal-manifest.sh`, `test-verify-queue.sh`, `test-verify-seam.sh`, `test-verify-evidence.sh`, `test-committed-twin-scrub.sh`, `test-automate-helpers.sh`, `test-context-digest.sh`, `test-insights.sh`, `test-result-validators.sh`, `test-send-telemetry-core.sh`, `test-skills-index-companion.sh`, `test-token-ledger.sh`, `test-check-prompt-history-refs.sh`. The root `scripts/test-check-{token-budget,doc-currency,vendor-coupling}.sh` "live repo passes" legs follow their gates.

**Order of work (Subtask 1 step 1 is first, before any deletion):** create and push the rollback tag; delete; fix the gates above; write the migration note; Subtask 2 re-points the tests, runs `bash scripts/ci-local.sh --affected`, writes the evidence file, runs the version bump.

**How each surface changes (decided here, not by the worker):**
- **Tag:** `BASE=$(git merge-base HEAD origin/main)`, computed once; Subtask 1 then CREATES `docs/evidence/qa-split-11b1-removal.md` (its own lane) with a `Start sha: <BASE>` line, the tag command and the `git ls-remote --tags origin pre-qa-removal` output — before any deletion, so the sha is on disk for Subtask 2 and never recomputed; if `git ls-remote --tags origin pre-qa-removal` prints nothing, `git tag pre-qa-removal "$BASE"` and `git push origin pre-qa-removal`; if it prints a sha, it must equal `$BASE` — otherwise stop and escalate (never move or overwrite the tag). Push the tag from a checkout that is NOT the run's feature-branch checkout (e.g. `git -C <primary checkout on main> push origin pre-qa-removal`): `guard-finalize-publish.sh` denies any `git push` in the live run's own checkout before FINALIZE, by design. A denial is the guard working — never bypass it; escalate instead.
- **JSON edits** (`hooks.json`, `prompt-token-budgets.json`, `prompt-history-refs-baseline.json`, `vendor-coupling-manifest.json`): delete the stale entries/lines in place, preserving the file's existing formatting — never re-serialize the whole file with `jq` (a probe `jq` rewrite of the baseline produced a 400-line reformat diff). `git diff --stat` on these four files shows deletions only (hooks.json may also lose a trailing comma on the preceding entry).
- **`loomwright/scripts/resolve-routing.sh`:** delete the `qa_strategist commands/qa-strategist.md Classification -` seat line; **`loomwright/scripts/adapters/providers/lens-roles.sh`:** delete its `qa_strategist)` arm (2 lines) in `lens_role_shape`. Nothing else in either file changes.
- **`test-lens-roles.sh`:** re-point the text-role fixture from `qa_strategist` to the existing text seat `product_owner` (marker `HANDOFF`, shape sentence "requirements and stories"); the `gen_text` byte-bound helper subtracts the marker's length (hard-coded `14` = `length("Classification")`) — use the new marker's length (`7`), or better `${#marker}` from a variable. Probe result after these edits: `RESULT: 134 passed, 0 failed`.
- **`test-verify-walkthrough.sh`:** keep the file (it is an 11b2 `delete` row) and every leg that exercises a still-present script (`verify-run.sh`, `verify-env.sh`, `verify-helpers.sh`, `RESULT_SCHEMAS.md`); remove only the legs whose subject is one of the four deleted prompt files (groups such as `(cmd)`, `(skill)`, `(NV-docs)`, `(I06-docs)`, `(I4-FIX1)`, `(AC7)`, `(AC7a)`, `(AC7b)`, `(AC7c)`, `(AC8)` prompt-text checks). Do NOT delete the test, its CI cache step, `self-test-weights.tsv` row or `test-no-fixed-sleep-race.sh` baseline — that is 11b2.
- **`test-check-contract-parity.sh`:** re-point every leg that uses the removed `qa-executor` matcher to agents still in `check-contract-parity.sh`'s `MANIFEST`, and drop `qa-executor` from the fixture's `mk(...)` hooks list and its `agents/qa-executor.md` heredoc:
  - leg 2 "missing hook-required field fails" → `code-reviewer` (drop `files_checked` from the fixture's `code-reviewer.md`);
  - leg 4 "hooks.json pin-drift fails" (its heredoc loop `if "qa-executor" in e["matcher"]:` strips `, coverage_estimate`) → match `code-reviewer` and strip `, files_checked` from that matcher's prompt, so the leg still creates real drift;
  - the command-fallback legs (cases 6–9 and the `cmd-fallback-prose-*` / bare / hash-in-string legs: `set_command_hooks … qa-executor …`, `write_validator … scripts/validate-qa-result.py "$QA_FIELDS"`) → matcher `supervisor-runner`, validator path `scripts/validate-supervisor-result.py` (the real one in `hooks.json`), field set `SUP_FIELDS` = the `supervisor-runner|supervisor.md|SUPERVISOR_RESULT|` MANIFEST row's fields, and the drift leg drops `heal_dismissed` where it dropped `coverage_estimate`; the two-validator leg's second file becomes `scripts/validate-supervisor2-result.py`. Rename `QA_FIELDS` to `SUP_FIELDS`. Every leg keeps its expected exit code. Update `check-contract-parity.sh`'s header comment that lists "loomwright:qa-executor also has the telemetry fan-out" so it no longer names the removed matcher.
- **`test-build-capabilities.sh`:** remove the `(A)` assertions about `loomwright:qa-executor` / `loomwright:qa-strategist`, and re-point the rules they covered — never drop the coverage (`build-capabilities.sh` survives): keep the `execute-manager` multi-block assertion (EXECUTE_RESULT + EXECUTE_CHECKPOINT) as its own leg, and re-point the emission-verb leg (was qa-strategist's "Step 4: EMIT GATE_VERDICT", which had no template line) to a synthetic fixture in the style of the file's existing `(F)` `$tmp/ff/agents/worker.md` legs: a copy of a real agent with one appended line `Step 4: EMIT RED_TEAM_RESULT` (an indexed block with no `RED_TEAM_RESULT:` template line in that fixture), asserting `RED_TEAM_RESULT` is in its `result_blocks`. Do not use `launch-pad.md` — its `LAUNCH_PAD_RESULT:` template lines satisfy the template rule, so the leg would survive its mutation.
- **`test-agent-memory-permission.sh`:** drop the two QA agents from its surface list (7 → 5 `memory: project` surfaces) and move its mutation victim from `agents/qa-strategist.md` to `agents/product-owner.md`.
- **`test-non-interactive-gates-seam.sh` (Subtask 2):** remove the `agents/qa-executor.md` URL-fallback leg `(g)` and its `QA_AGENT` variable. **Subtask 1** (it owns `ARCHITECTURE_CONTRACTS.md`), with its other edits there: in `ARCHITECTURE_CONTRACTS.md` §"Question-gate inventory" remove the rows whose surface is a deleted file (`qa-executor VERIFY sign-in`, `qa-executor URL fallback`, `` `/verify` queue ambiguous resume ``).
- **Docs this PR edits anyway** (counts per "Counts" above): remove the rows/lines that list a deleted surface — CLAUDE.md agent-roles table rows `QA Strategist` and `QA Executor` (and "dual-agent QA" in its overview line), README agent/command tables and the `/verify`, `/qa-executor`, `/qa-strategist` command rows (pointing the reader to Selvedge in one line), `.claude-plugin/README.md` count lines, `loomwright/docs/HOOKS.md` §"Hook Table" row `SubagentStop (qa-executor)` and the `qa-executor` name inside the "SubagentStop telemetry × 3" row (now × 2) and the emitter list naming `qa-strategist`, `ARCHITECTURE_CONTRACTS.md` budget mirror rows, color legend (regenerated), cost-profile row `qa-executor | inherit`, effort-table names `qa-executor, qa-strategist`. Plugin and marketplace `description`: update the four counts in place (the only surfaces that keep a count) and drop "QA," from the list of what dedicated agents cover; `keywords`: drop `"playwright"`, `"qa-executor"`, `"qa-strategist"` (manifest re-point rows, item 11b1). Every other mention (`/dreaming`, `agent-help` pages, name maps, `RESULT_SCHEMAS.md`, telemetry) is item 11b2/12 and stays.
- **`/agent-help` (Validation 3 needs it to list no QA command; owner decision `LP-CLARIFY` 2026-11-18 — delete the page now):** in `loomwright/commands/agent-help.md` delete the whole split block from `<!-- split:begin ../docs/command-parts/agent-help/qa.md -->` to `<!-- split:end ../docs/command-parts/agent-help/qa.md -->` (the `### 5️⃣ /qa-strategist`, `### 6️⃣ /qa-executor` and `### 🔎 /verify` index entries), drop the topic bullet `` `qa.md` — `/qa-strategist`, `/qa-executor`, `/verify`. `` (it would point at the deleted page), and drop the number from the Quick Start count line (`**14 agent roles** (9 user-facing + 5 internal)`). Delete the split page `loomwright/docs/command-parts/agent-help/qa.md` with it — removing the index entries while the page stays fails `test-command-parts.sh` check C (probed at the base commit: 34 pass, 2 fail; with the page and its fixture row also gone, 36 pass, 0 fail) — plus its three ties: the `"loomwright/docs/command-parts/agent-help/qa.md"` entry in `prompt-history-refs-baseline.json`, its `allowances` + `allowance_reasons` entries in `vendor-coupling-manifest.json`, and its `split-time` row in `loomwright/scripts/fixtures/command-parts/move-only.txt`. Everything else in agent-help stays for item 12 (owner decision 2026-11-18): the Quick Start "QA Pipeline" block (its `QA Strategist`/`QA Executor` lines and "(2 agents)" group label), `docs/command-parts/agent-help/more.md`'s QA Workflow Diagram command lines, the `guide.md`/`knowledge.md` mentions and the `### 🌱 /propose …a /verify Run…` heading. `loomwright/scripts/test-command-parts.sh` and `test-automate-loop-split.sh` must stay green.
- **Manifest upkeep (no row moves — owner decision 2026-11-18):** leave every existing row's action and item as it is. The `delete | 12` row for `agent-help/qa.md` then reads `done` early, and the re-point rows this PR finishes early (`resolve-routing.sh`, `lens-roles.sh`, `test-lens-roles.sh` `qa_strategist`; the baseline, vendor-manifest and `move-only.txt` `agent-help/qa.md` keys; agent-help's `agent-help/qa.md`) read `done` in report mode. `--expect 11b1` fails on none of them (re-point rows are checked at `--expect 12` only). Only add the rows the manifest's own rule asks for ("a row a removal PR finds missing … is changed here in that PR"): one `keep | 11b1` row each for `loomwright/docs/rationale/qa-split.md` and `docs/evidence/qa-split-11b1-removal.md` (reference `—`, reasons "rationale doc (history by design)" and "evidence record (history by design)"), updating `Row count:` 434 → 436. The checker refuses a wrong row count (exit 2), so run it after the edit.

## Acceptance Criteria
- [ ] Given this branch, when `bash loomwright/scripts/check-qa-removal-manifest.sh --expect 11b1` runs, then it exits 0 with `0 MISMATCH` (every `delete … 11b1` path absent, every `keep` row present with its reference).
- [ ] Given a brief whose Executable Acceptance has a `qa-executor: x` bullet, when ground truth runs, then it still records the bullet as deferred and spawns nothing: `bash loomwright/scripts/test-run-ground-truth.sh` passes, and the diff does not touch `loomwright/scripts/run-ground-truth.sh` or `loomwright/scripts/exec-acceptance-lib.sh`.
- [ ] Given this branch, when `bash scripts/check-doc-currency.sh` runs, then it passes with agents=12, commands=22, skills=36, hooks=45; the plugin and marketplace `description` fields carry those four counts, and `CLAUDE.md`, `README.md`, `.claude-plugin/README.md`, `loomwright/commands/agent-help.md` and `loomwright/docs/ARCHITECTURE.md` carry no agent, command, skill or hook count (none of `14 agent`, `12 agent`, `42 skill`, `36 skill`, `42 focused`, `48 quality`, `48 hooks`, `9 user-facing`, `7 user-facing` matches in them); and when `bash scripts/check-token-budget.sh` runs, then it passes and `loomwright/docs/prompt-token-budgets.json` has no `.agents`/`.commands`/`.skills` key for a deleted agent, command or skill (and `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" no mirror row for one).
- [ ] Given this branch, when `bash scripts/check-contract-parity.sh`, `bash scripts/check-prompt-history-refs.sh`, `bash scripts/check-skills-index-sync.sh`, `bash scripts/check-vendor-coupling.sh`, `bash loomwright/scripts/build-capabilities.sh --check` and `bash scripts/ci-local.sh --affected` run, then each exits 0; `loomwright/hooks/hooks.json` has no `loomwright:qa-executor` or `loomwright:qa-strategist` matcher.
- [ ] Given the remote, when `git ls-remote --tags origin pre-qa-removal` runs, then it prints the sha recorded ONCE at tag time — the branch's start commit, `git merge-base HEAD origin/main` computed when the tag was created, never recomputed later (a later merge of `main` into the branch moves the merge-base; the tag correctly does not move) — and a committed evidence file `docs/evidence/qa-split-11b1-removal.md` contains the recorded start sha, the tag command and the `ls-remote` output, and the PR body links to it.
- [ ] Given the `changelog.d/` fragment this PR adds, when read, then it names `/qa-executor`, `/qa-strategist` and `/verify` (and the `qa-executor`/`qa-strategist` agents) as removed, says what replaces each (`/selvedge:verify` and the `selvedge` CLI for `/qa-executor` and `/verify`; no direct replacement for `/qa-strategist`, whose risk-strategy role Selvedge deliberately does not carry over — plan D2), and says how to install Selvedge (`/plugin install selvedge@atelier`, then `selvedge install-cli`).
- [ ] Given `loomwright/docs/rationale/qa-split.md`, when read, then it states the why (the old QA had zero runs, the drift cost every release paid, decision D1), points to the plan `.supervisor/requirements/qa-split/00-plan.md` and the manifest, names the rollback tag `pre-qa-removal`, and restates no plugin count.
- [ ] Given `loomwright/commands/agent-help.md`, when `grep -nE '^### [^ ]+ /(qa-strategist|qa-executor|verify) ' loomwright/commands/agent-help.md` runs, then it prints nothing (anchored after the heading's emoji, so the kept `### 🌱 /propose … a /verify Run …` heading does not match; never the unanchored `^### .*/(…) `), `loomwright/docs/command-parts/agent-help/qa.md` is absent, and `bash loomwright/scripts/test-command-parts.sh` passes.
- [ ] Given the plugin loaded from this branch (`claude -p --plugin-dir ./loomwright "/loomwright:qa-executor"` with `CLAUDE_CODE_ENTRYPOINT` unset, and `/loomwright:agent-help`), when run, then `/loomwright:qa-executor` is an unknown command and the agent-help output has no `/qa-strategist`, `/qa-executor` or `/verify` command section; the committed evidence file `docs/evidence/qa-split-11b1-removal.md` contains both outputs, the anchored grep's (empty) output, the line `Verdict: PASS for Validation 3` (column 0), the list of agent-help QA mentions that remain until item 12 (the Quick Start "QA Pipeline" block, `more.md`'s QA diagram lines, the `guide.md`/`knowledge.md` mentions, the `/propose` heading), and the honest limit that `--plugin-dir` stands in for `/plugin install loomwright@atelier`, which the owner re-checks after merge.

## Scope widening
- loomwright/docs/command-parts/agent-help/qa.md
- loomwright/scripts/fixtures/command-parts/move-only.txt
- accepted: LP-SCOPE 2026-11-18

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
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

> Applied here: the count rule is honored (requirement Scope "Counts", owner `LP-RULE-OVR` 2026-11-18) — only the two manifest `description` fields keep a count; every prose surface drops its number, and the fragment, rationale doc and evidence file name no agent/command/skill/hook count. The contract-wording rule: the renamed CLAUDE.md heading's citers move with it (Task, "Counts"). The restated-list rule: every list of agents, commands, skills or hooks this PR edits (CLAUDE.md roles table, README tables, HOOKS.md hook table, SKILLS_INDEX.md, budget mirror rows) changes in the same commit as the deletion it mirrors.

## Touched-file invariants

> Grounded at base `4951d864ad493d477d1cdf839b9d6980665b094a`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/hooks/hooks.json`** — keep: every remaining `type: command` leaf byte-identical, including each `|| true` and the fail-CLOSED leaves that carry none (`guard-test-integrity.sh`, `guard-finalize-publish.sh`, with `"onFailure": "block"`); remove exactly the two objects whose `"matcher"` is `"loomwright:qa-executor"` and `"loomwright:qa-strategist"` (3 hook leaves) and nothing else; mirror: `loomwright/docs/HOOKS.md` §"Hook Table" rows `SubagentStop (qa-executor)` and `SubagentStop telemetry × 3`; fired by: SubagentStop; pinned by: `scripts/check-doc-currency.sh` hook count (`hooks=`) and `scripts/check-contract-parity.sh` (reads matchers).
- **`scripts/check-contract-parity.sh`** — keep: the fail-CLOSED selection rule ("exactly ONE command entry may reference a validate-*-result.py script") and every other `MANIFEST`/`ENUMS` row unchanged; remove only the lines starting `qa-executor|qa-executor.md|` and `agents/qa-executor.md|status|`; pinned by: `loomwright/scripts/test-check-contract-parity.sh` (`set_command_hooks`).
- **`loomwright/scripts/resolve-routing.sh`** — keep: the `seats` heredoc format `<id> <home-file> <role-marker> <validator|->` and every other seat line (e.g. `product_owner commands/product-owner.md HANDOFF -`); pinned by: `loomwright/scripts/test-resolve-routing.sh` ("seats every home file exists").
- **`loomwright/scripts/adapters/providers/lens-roles.sh`** — keep: `lens_role_shape`'s `*) return 1 ;;` default and the `product_owner)` arm; remove only the `qa_strategist)` arm; pinned by: `adapters/providers/test-lens-roles.sh` (`lens_role_contract`).
- **`loomwright/scripts/test-verify-walkthrough.sh`, `test-check-contract-parity.sh`, `test-build-capabilities.sh`, `test-agent-memory-permission.sh`, `test-non-interactive-gates-seam.sh`, `adapters/providers/test-lens-roles.sh`** — keep: each file's own assertion helpers (`ok`/`no`/`assert_eq`/`assert_true`) and its final `RESULT:` summary and exit-status convention; never weaken a leg whose subject still exists — only legs about a deleted file are removed or re-pointed; `test-check-contract-parity.sh` keeps its negative legs (a missing field and an out-of-enum literal must still fail the gate). **`test-verify-walkthrough.sh` additionally keeps its `PW_TEST_VERSION=1.63.0` assignment line byte-identical on its own line** (the file's own comment: "Keep the assignment on its own line, exactly `PW_TEST_VERSION=<x.y.z>`") — it is read by `loomwright/scripts/read-playwright-pin.sh` (default subject), pinned by `loomwright/scripts/test-read-playwright-pin.sh` (`SUBJECT="$HERE/test-verify-walkthrough.sh"`) and feeds `.github/workflows/ci.yml`'s Playwright cache key; a leg trim never touches it.
- **`loomwright/docs/ARCHITECTURE_CONTRACTS.md`** — three gate-pinned regions this PR edits, each only by removing rows for deleted surfaces: (1) the generated block between `<!-- loomwright:color-legend BEGIN (generated by gen-color-legend.sh) -->` and `<!-- loomwright:color-legend END -->` — regenerate with `bash loomwright/scripts/gen-color-legend.sh --write`, never hand-edit (checked by `scripts/check-doc-currency.sh`); (2) `## Prompt Token Budgets` mirror rows — remove exactly the rows of the deleted agents/commands/skills, in the same commit as their `prompt-token-budgets.json` entries (checked by `scripts/check-token-budget.sh`); (3) `## Question-gate inventory` — remove only the three rows named in Task (read by `test-non-interactive-gates-seam.sh`). Every other row and the two `§"The 14 Agent Roles"` citers (re-pointed per Task "Counts") stay otherwise byte-identical.
- **`loomwright/docs/prompt-token-budgets.json`, `loomwright/docs/prompt-history-refs-baseline.json`, `loomwright/docs/vendor-coupling-manifest.json`** (fail-CLOSED gate inputs) — keep: the files' formatting and every non-deleted entry byte-identical; edits are line deletions only, never a `jq` re-serialisation; in the vendor manifest remove a path's `allowances` entry AND its `"allowance_reasons"` entry together (the gate errors on either alone); the history baseline "may only go down" — remove entries, never raise one; anchors: `"raise_rule"` (budgets), `"_comment"` (baseline), `"allowance_reasons"` (vendor); pinned by: `scripts/check-token-budget.sh`, `scripts/check-prompt-history-refs.sh`, `scripts/check-vendor-coupling.sh` (and their `scripts/test-check-*.sh` live-repo legs).
- **`loomwright/capabilities.json`** — generated: change it only by running `bash loomwright/scripts/build-capabilities.sh` (and later `bump-version.sh`, which rewrites its `"plugin_version"`), never by hand; pinned by: `build-capabilities.sh --check` and `loomwright/scripts/test-build-capabilities.sh` "(C) committed capabilities.json is stale".
- **`loomwright/commands/agent-help.md`** (router) — keep: every other `<!-- split:begin <part> -->` … `<!-- split:end <part> -->` block byte-identical, each index entry a heading followed by exactly one `See [<path>](<path>).` line, and the `<!-- index-only:begin -->` read rule naming every remaining part file; size < 20480 bytes; pinned by: `loomwright/scripts/test-command-parts.sh` (checks B, C, D, F, G).
- **`loomwright/scripts/fixtures/command-parts/move-only.txt`** — keep: its tab-separated row format and every other row byte-identical; remove only the `split-time` row for `loomwright/docs/command-parts/agent-help/qa.md` (sha `13272703980f79e741736930d0109ff3aba05e39aab366ac3f3f9e35a63b3550`); pinned by: `test-command-parts.sh` check E and its mutation controls.
- **`loomwright/docs/qa-removal-manifest.md`** — keep: the format contract in `check-qa-removal-manifest.sh`'s header (`Row count: <N>` equals the data rows; header `| path | reference | action | item | reason |`); pinned by: `loomwright/scripts/test-check-qa-removal-manifest.sh` (`need_row`).

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/adapters/providers/test-lens-roles.sh` — "C a text contract carries the MUST-contain marker sentence" (re-pointed to `product_owner`) | delete `    product_owner)` in `loomwright/scripts/adapters/providers/lens-roles.sh` |
| `loomwright/scripts/test-check-contract-parity.sh` — "missing hook-required field fails" (re-pointed to `code-reviewer`) | delete `code-reviewer|code-reviewer.md|CODE_REVIEW_RESULT|` in `scripts/check-contract-parity.sh` |
| `loomwright/scripts/test-check-contract-parity.sh` — leg 4 "hooks.json pin-drift fails" (re-pointed to `code-reviewer`) | delete `code-reviewer|code-reviewer.md|CODE_REVIEW_RESULT|` in `scripts/check-contract-parity.sh` |
| `loomwright/scripts/test-check-contract-parity.sh` — command-fallback legs 6–9 and the `cmd-fallback-prose-*` legs (re-pointed to `supervisor-runner`) | delete `supervisor-runner|supervisor.md|SUPERVISOR_RESULT|` in `scripts/check-contract-parity.sh` |
| `loomwright/scripts/test-agent-memory-permission.sh` — surface/mutation leg (victim moved to `product-owner.md`) | delete `### Agent memory write permission` in `loomwright/agents/product-owner.md` |
| `loomwright/scripts/test-build-capabilities.sh` — `execute-manager` multi-block leg (split into its own leg) | flip `result_blocks: $blocks,` → `result_blocks: [],` in `loomwright/scripts/build-capabilities.sh` |
| `loomwright/scripts/test-build-capabilities.sh` — emission-verb leg (synthetic fixture `Step 4: EMIT RED_TEAM_RESULT`) | flip `(EMIT|[Ee]mit|` → `([Ee]mit|` in `loomwright/scripts/build-capabilities.sh` |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Tag, delete the 11b1 paths, fix the config/doc/gate surfaces, write the migration note | AC1, AC2, AC3, AC6, AC7, AC8 (and the non-test half of AC4, the tag half of AC5) | 20 modify, 3 create (+ ~40 deletions incl. `agent-help/qa.md`) | `skills/quality-checklist/SKILL.md`, `skills/commit/SKILL.md` | LAUNCHABLE |
| 2 | Re-point the broken tests, run the gates, write the evidence file, bump the version | AC4, AC5 (evidence + PR link), AC9 | 7 modify incl. the evidence file (+ bump: `CHANGELOG.md`, versions), 0 create | `skills/unit-testing/SKILL.md`, `skills/quality-checklist/SKILL.md` | BLOCKED (by #1) |

### File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| delete (Subtask 1) | `git rm -r`: `loomwright/agents/qa-executor.md`, `loomwright/agents/qa-strategist.md`, `loomwright/commands/qa-executor.md`, `loomwright/commands/qa-strategist.md`, `loomwright/commands/verify.md`, `loomwright/skills/playwright-e2e/`, `loomwright/skills/qa-gates/`, `loomwright/skills/qa-orchestration/`, `loomwright/skills/qa-strategy/`, `loomwright/skills/qa-test-patterns/`, `loomwright/skills/verify-walkthrough/`, `.claude/agent-memory/loomwright-loomwright-qa-executor/` | — | HIGH |
| config (Subtask 1) | `loomwright/hooks/hooks.json` (367), `loomwright/docs/prompt-token-budgets.json` (93), `loomwright/docs/prompt-history-refs-baseline.json` (135), `loomwright/docs/vendor-coupling-manifest.json` (819 — deletions only, no new responsibility), `loomwright/capabilities.json` (1381 — generated), `loomwright/.claude-plugin/plugin.json` (98), `.claude-plugin/marketplace.json` (140) | — | HIGH |
| docs (Subtask 1) | `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (1071 — row deletions + regenerated legend, no new responsibility), `loomwright/skills/SKILLS_INDEX.md` (82 — generated), `loomwright/docs/HOOKS.md` (129), `CLAUDE.md` (167), `README.md` (772 — row/count edits only), `.claude-plugin/README.md` (613 — count edits only), `loomwright/commands/agent-help.md` (426 — one count, the QA split block and topic bullet removed), `loomwright/docs/ARCHITECTURE.md` (178 — one count), `loomwright/docs/qa-removal-manifest.md` (587 — 2 keep rows added per Task §"Manifest upkeep", no row moved; `Row count` 434 → 436; the single authority for these rows), `loomwright/scripts/fixtures/command-parts/move-only.txt` (34 — one row deleted); `git rm`: `loomwright/docs/command-parts/agent-help/qa.md` (127) | `loomwright/docs/rationale/qa-split.md`, `changelog.d/qa-removal-11b1.md`, `docs/evidence/qa-split-11b1-removal.md` (Subtask 1, at tag time: start sha, tag command, `ls-remote` output) | HIGH |
| scripts (Subtask 1) | `scripts/check-contract-parity.sh` (443 — row deletions), `loomwright/scripts/resolve-routing.sh` (410 — one line), `loomwright/scripts/adapters/providers/lens-roles.sh` (124 — 2 lines) | — | HIGH |
| tests (Subtask 2) | `loomwright/scripts/test-verify-walkthrough.sh` (1891 — leg removals only, no new responsibility; the file goes whole in 11b2), `loomwright/scripts/test-check-contract-parity.sh` (510 — fixture re-point, no new responsibility), `loomwright/scripts/test-build-capabilities.sh` (473), `loomwright/scripts/test-agent-memory-permission.sh` (295), `loomwright/scripts/test-non-interactive-gates-seam.sh` (441), `loomwright/scripts/adapters/providers/test-lens-roles.sh` (311), `docs/evidence/qa-split-11b1-removal.md` (created by Subtask 1; Subtask 2 appends) | — | MEDIUM |
| release (Subtask 2) | `CHANGELOG.md` (890), versions in `loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `loomwright/capabilities.json` — all via `bash scripts/bump-version.sh` | — | HIGH |

> **Validator-owned surfaces:** `scripts/check-doc-currency.sh` (its 16 scanned surfaces — the count drift sites above are the ones the probe surfaced), `scripts/check-token-budget.sh`, `scripts/check-prompt-history-refs.sh`, `scripts/check-skills-index-sync.sh`, `scripts/check-vendor-coupling.sh`, `scripts/check-contract-parity.sh`, `loomwright/scripts/build-capabilities.sh --check`, `loomwright/scripts/check-qa-removal-manifest.sh`. Per the lessons store: a green doc-currency run is necessary but not sufficient — grep the OLD values repo-wide (`14 agent`, `25 slash`, `42 skill`, `42 focused`, `48 quality`, `48 hooks`, `9 user-facing`) outside `CHANGELOG.md`, `docs/evidence/` and the manifest's history keep rows, and fix each live claim.

### Blast-Radius / Impact Prediction

| Touched Subsystem | Depends On (`DEPENDS_ON`) | Depended-on-by — derived dependents (`DEPENDED_ON_BY`) | Source Contract | Incident History |
|-------------------|---------------------------|-------------------------------------------------------|-----------------|------------------|
| `loomwright/hooks/hooks.json` | — | `loomwright/scripts/emit-token-ledger.sh`, `loomwright/scripts/session-resume.sh` | — | — |

**Predicted ripple beyond directly-touched files:** `emit-token-ledger.sh`, `session-resume.sh` — read matchers generically; no QA-specific code expected to change (its `qa-executor` name map is item 12).

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/docs/rationale/qa-split.md"}
  - {kind: "file", path: "changelog.d/qa-removal-11b1.md"}
  - {kind: "symbol", path: "docs/evidence/qa-split-11b1-removal.md", name: "Start sha:"}
  - {kind: "symbol", path: "loomwright/docs/qa-removal-manifest.md", name: "loomwright/docs/rationale/qa-split.md"}
  - {kind: "symbol", path: "loomwright/docs/qa-removal-manifest.md", name: "Row count: 436"}
  - {kind: "symbol", path: "loomwright/hooks/hooks.json", name: "loomwright:code-reviewer"}
  - {kind: "symbol", path: "CLAUDE.md", name: "The Agent Roles"}
requires: []
lanes:
  - "loomwright/agents/qa-executor.md"
  - "loomwright/agents/qa-strategist.md"
  - "loomwright/commands/qa-executor.md"
  - "loomwright/commands/qa-strategist.md"
  - "loomwright/commands/verify.md"
  - "loomwright/skills/playwright-e2e/**"
  - "loomwright/skills/qa-gates/**"
  - "loomwright/skills/qa-orchestration/**"
  - "loomwright/skills/qa-strategy/**"
  - "loomwright/skills/qa-test-patterns/**"
  - "loomwright/skills/verify-walkthrough/**"
  - ".claude/agent-memory/loomwright-loomwright-qa-executor/**"
  - "loomwright/hooks/hooks.json"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/prompt-history-refs-baseline.json"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "loomwright/capabilities.json"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/skills/SKILLS_INDEX.md"
  - "loomwright/docs/HOOKS.md"
  - "CLAUDE.md"
  - "README.md"
  - ".claude-plugin/README.md"
  - "loomwright/commands/agent-help.md"
  - "loomwright/docs/command-parts/agent-help/qa.md"
  - "loomwright/scripts/fixtures/command-parts/move-only.txt"
  - "loomwright/docs/ARCHITECTURE.md"
  - "loomwright/docs/qa-removal-manifest.md"
  - "loomwright/docs/rationale/qa-split.md"
  - "changelog.d/qa-removal-11b1.md"
  - "docs/evidence/qa-split-11b1-removal.md"
  - "scripts/check-contract-parity.sh"
  - "loomwright/scripts/resolve-routing.sh"
  - "loomwright/scripts/adapters/providers/lens-roles.sh"
external_requires:
  - "push access to origin for the rollback tag pre-qa-removal (owner-approved in plan §6)"

# Subtask 2
# provides: the fragment from Subtask 1 is folded into CHANGELOG.md by the bump and deleted, so the folded entry is named instead
provides:
  - {kind: "file", path: "docs/evidence/qa-split-11b1-removal.md"}
  - {kind: "symbol", path: "docs/evidence/qa-split-11b1-removal.md", name: "Verdict: PASS for Validation 3"}
  - {kind: "symbol", path: "loomwright/scripts/adapters/providers/test-lens-roles.sh", name: "product_owner"}
  - {kind: "symbol", path: "CHANGELOG.md", name: "QA agents, commands and skills removed"}
requires:
  - {from: "1", kind: "file", path: "changelog.d/qa-removal-11b1.md"}
  - {from: "1", kind: "file", path: "loomwright/docs/rationale/qa-split.md"}
  - {from: "1", kind: "symbol", path: "docs/evidence/qa-split-11b1-removal.md", name: "Start sha:"}
lanes:
  - "loomwright/scripts/test-verify-walkthrough.sh"
  - "loomwright/scripts/test-check-contract-parity.sh"
  - "loomwright/scripts/test-build-capabilities.sh"
  - "loomwright/scripts/test-agent-memory-permission.sh"
  - "loomwright/scripts/test-non-interactive-gates-seam.sh"
  - "loomwright/scripts/adapters/providers/test-lens-roles.sh"
  - "docs/evidence/qa-split-11b1-removal.md"
  - "CHANGELOG.md"
  - "changelog.d/**"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
  - "loomwright/capabilities.json"
external_requires:
  - "claude CLI on PATH for the --plugin-dir unknown-command probe (Validation 3)"
```

**Fragment headline (fixed, so Subtask 2's provides resolves):** `changelog.d/qa-removal-11b1.md` starts `<!-- bump: major -->` (removing user-facing commands is a breaking change), then the headline `QA agents, commands and skills removed — Selvedge replaces them (qa-split 11b1)`.

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | `docs/evidence/qa-split-11b1-removal.md` (Subtask 1 creates it at tag time; Subtask 2 appends the gate and Validation 3 outputs and the verdict line), `loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `loomwright/capabilities.json` (the bump re-writes the version fields after Subtask 1's description/keyword/regenerate edits) | YES (ordered by `requires`) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after Subtask 1)
- **Recommended workers:** 1 at a time
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/quality-checklist/SKILL.md`, `skills/commit/SKILL.md` |
| 2 | `skills/unit-testing/SKILL.md`, `skills/quality-checklist/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): two paths outside the requirement's `## Touches` — `loomwright/docs/command-parts/agent-help/qa.md` (deleted) and `loomwright/scripts/fixtures/command-parts/move-only.txt` (one row) — needed for `test-command-parts.sh`, as probed | MEDIUM | Owner chose this at `LP-CLARIFY`; recorded under `## Scope widening` once accepted at `LP-SCOPE`; no other out-of-Touches edit |
| Feasibility (Phase 2.5): `context-bound` scope (~27 edited + ~40 deleted files) | MEDIUM | Two sequential subtasks; Subtask 2 runs `ci-local.sh --affected` over the integrated tree |
| A deleted prompt is still read by a test or hook not on the probe list | MEDIUM | `ci-local.sh --affected` before push; GitHub `ci` runs the full suite on the PR; fix each red there |
| `/dreaming --agent qa-executor` (and `all`) still names the deleted agent until item 12 re-points `dreaming` | MEDIUM | Owner-planned sequencing (plan item 12, requirement non-goal); the changelog fragment says `/dreaming`'s QA reflection is gone |
| The tag push is denied by `guard-finalize-publish.sh` when run from the run's own checkout | LOW | Push from the primary checkout on `main`; never bypass the guard; escalate if denied |
| `pre-qa-removal` already exists on the remote at a different commit | LOW | Never move it; stop and escalate (Task §"How each surface changes") |
| Trimming `test-verify-walkthrough.sh` drops coverage of a still-present script by mistake | MEDIUM | Remove only legs naming one of the four deleted prompt files; the test must still pass and still exercise `verify-run.sh`/`verify-env.sh` |
| Validation 3 says "after `/plugin install loomwright@atelier`" before merge; AC9 uses `claude -p --plugin-dir` as the pre-merge stand-in | LOW | The evidence file states the limit; the owner re-checks the real install after merge (noted for the owner at Launch Pad Phase 6) |
| Prior churn (postmortem ledger): `CLAUDE.md` (94), `loomwright/commands/agent-help.md` (56), `hooks.json`, `check-contract-parity.sh`, `test-check-contract-parity.sh` (9 each) — recurring `convention_mismatch`, `drain_churn`, `quality_gap`; `self_heal_miss` recurred | HIGH | Grep the OLD count values and the old heading repo-wide after the edit (not only the doc-currency gate); run `test-command-parts.sh` and `test-check-contract-parity.sh` directly; keep every re-pointed test's negative legs |
| Deleting `agent-help/qa.md` (an item-12 `delete` row) in 11b1 leaves agent-help's Quick Start "QA Pipeline" block and `more.md`'s QA diagram naming QA agents with no help page | LOW | Owner-chosen (`LP-CLARIFY` 2026-11-18); the evidence file lists the remaining mentions for item 12 |
| Users with `/qa-executor` muscle memory | LOW | Changelog fragment + rationale doc name the replacement and the install steps |
| A JSON edit re-serializes the whole file (noisy diff, hidden changes) | LOW | Line deletions only; `git diff --stat` shows deletions for the four JSON files |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-18-qa-split-11b1-remove-qa-surfaces.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-11-19T01:45:17Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/946
- **Branch:** feature/qa-split-11b1-remove-qa-surfaces
- **Files changed:** 62
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 3
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** armed
- **Summary:** QA removal 11b1 shipped as v18.0.0 in PR #946. Two sequential subtasks: deletions and gate fixes, then test re-points, evidence and the bump. The owner applied the hooks.json patch because the test-integrity guard blocks that edit. Three heal rounds: (1) /dreaming no longer spawns qa-executor, by owner ruling, plus SKILLS_INDEX and Cost Profiles leftovers and a changelog re-fold; (2) evidence-file correction and the ARCHITECTURE_CONTRACTS 11b1 sweep; (3) three red CI self-tests that pinned 14 agents, 48 hook leaves and a deleted memory entry. The round-3 fix was not re-reviewed, so the run escalated. Ground truth 2/2 pass.

## Not verified
- **PR body link to docs/evidence/qa-split-11b1-removal.md (AC5)** — the PR body lists it under ## Evidence; not judged by the review (subtask 2)
- **/plugin install loomwright@atelier installed-plugin path (AC9)** — --plugin-dir stood in; the owner re-checks after merge (subtask 2)
- **full CI suite** — GitHub CI runs it; the fixer's local full run shows 2 of 212 red, both also red on origin/main (subtask 2)
