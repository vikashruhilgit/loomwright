# Supervisor Job: Relocate the QA subsystem into `selvedge` — agents, commands, skills, hook, validator, pins, counts

Source requirement: `.supervisor/requirements/selvedge-extraction/04-relocate-qa-agents-commands-skills.md`
Automate run: `automate-2026-08-18-124023` (item 04 of 7; items 01–03 merged)

## Environment

- Base branch: `main` @ `742a6df` (the PR #156 merge — slice 03). Verified fresh: `git rev-list --left-right --count origin/main...HEAD` = `0 0`.
- Feature branch: `feature/relocate-qa-to-selvedge`
- Two pre-existing uncommitted artifacts on this checkout are **NOT yours** and must stay untouched and uncommitted: modified `.supervisor/postmortem/results.jsonl` (the engine's learning ledger) and untracked `loomwright/docs/SPIKES/IMPECCABLE_TEARDOWN.md`. Assert commit hygiene over the **whole branch** with the three-dot form `git diff --name-only origin/main...HEAD`, never `HEAD~1 HEAD`.
- The Bash tool is **zsh**; the repo's scripts and CI run **bash**. Run every gate as `bash scripts/...`, and wrap any glob loop in `bash -c` with quoted globs — an unquoted `--include=*.md` dies in zsh with "no matches found" **before grep runs**, which reads as a green zero. That exact artifact produced a false "0 hits" during the previous slice.

## Subtask Contract

```yaml
subtask: relocate-qa-to-selvedge
requires: []
lanes: [selvedge/, loomwright/agents/, loomwright/commands/, loomwright/skills/, loomwright/scripts/, loomwright/hooks/, loomwright/docs/, scripts/, .claude-plugin/, CLAUDE.md, README.md, AGENT_GUIDELINES.md]
provides:
  - {kind: file, path: selvedge/hooks/hooks.json,                     name: selvedge-qa-hook}
  - {kind: file, path: selvedge/docs/prompt-token-budgets.json,       name: selvedge-budgets}
  - {kind: file, path: selvedge/docs/ARCHITECTURE_CONTRACTS.md,       name: selvedge-budget-mirror}
  - {kind: file, path: selvedge/skills/SKILLS_INDEX.md,               name: selvedge-skills-index}
  - {kind: file, path: selvedge/scripts/test-result-validators.sh,    name: selvedge-validator-test}
  - {kind: file, path: selvedge/agents/qa-executor.md,                name: selvedge-qa-executor}
  - {kind: file, path: selvedge/agents/qa-strategist.md,              name: selvedge-qa-strategist}
  - {kind: file, path: selvedge/scripts/validate-qa-result.py,        name: selvedge-qa-validator}
```

## Parallelism Analysis

Mode: **single-agent (no fan-out)**. Recommended workers: **1**. Est. files: ~45.
Every change is entangled through the CI gates — that entanglement IS the slice's premise (the source requirement justifies each forbidden smaller cut against a named gate, and those justifications were re-checked against the scripts on disk and hold). Parallel worktrees would each observe a red gate the other fixes, and per-worktree reviewers cannot see sibling worktrees.

## Skill References

None preloaded. This is a mechanical relocation whose difficulty is entirely in the CI gates; the relevant contracts are the gate scripts themselves, cited by path in the Measured facts below. Read on demand if needed: `quality-checklist`.

## Task

Relocate the QA subsystem from `loomwright/` to `selvedge/` in one green commit-set, with every mechanically-forced pin, budget, gate row, test literal and doc count updated alongside it. `selvedge` today ships only `.claude-plugin/plugin.json` + `README.md`; slice 02 already made the three loomwright-pinned gates plugin-aware and taught CI's hard-gate loop to run `selvedge/scripts/test-*.sh`.

**The atomicity is real, not laziness.** The source requirement justifies each forbidden smaller cut against a named gate; those justifications were re-checked against the scripts on disk and hold.

## Measured facts (read off disk at `742a6df` — re-verify before editing; do not re-derive from the brief)

1. **Counts today:** agents **14**, commands **21**, skills **41**, hooks **24** leaf entries. Commands:
   `find loomwright/agents -maxdepth 1 -name '*.md' | wc -l`, `find loomwright/commands -maxdepth 1 -name '*.md' | wc -l`, `find loomwright/skills -mindepth 1 -maxdepth 1 -type d | wc -l`, `jq '[.hooks[][].hooks[]] | length' loomwright/hooks/hooks.json`. These are the **same four expressions `scripts/check-doc-currency.sh:53-56` uses**, so a count you derive any other way is not the one the gate checks.

2. **There is exactly ONE QA matcher in `loomwright/hooks/hooks.json`** — `SubagentStop` / `loomwright:qa-executor` — and it carries **two** leaf hooks: `validate-qa-result.py`, and the shared `send-telemetry.sh` + `emit-token-ledger.sh` fan-out (both in ONE leaf entry's command string).

3. **The hook figure after this slice is 24 → 23, NOT 24 → 22.** The source requirement's own §7 table says 22 and its note says "re-derive from `hooks.json`; never restate a number from this brief" — do exactly that. Slice 03's recorded decision (`loomwright/docs/TELEMETRY.md` §"QA telemetry after the selvedge split — decision, 2026-08-20", lines ~699-766) **keeps the fan-out leaf in loomwright** under a re-pointed matcher; only the `validate-qa-result.py` leaf moves. So loomwright loses exactly one leaf.

4. **Both namespace forms are already decided and recorded — do NOT infer either from the loomwright pattern.** From spike `loomwright/docs/SPIKES/CROSS_PLUGIN_RESOLUTION.md` (Unknown D), mirrored in `TELEMETRY.md`'s decision table:
   | Slot | Form | Value |
   |---|---|---|
   | `hooks.json` **matcher** (both plugins' hooks.json) | **single**-prefix, matches the agent's frontmatter `name:` | `selvedge:qa-executor` |
   | `Task(subagent_type:)` **spawn** | **doubled** | `selvedge:selvedge:qa-executor` / `selvedge:selvedge:qa-strategist` |
   The spike measured that the doubled form *also* fires as a matcher today, so the distinction is convention rather than load-bearing **on this version** — but a matcher that stops firing loses the QA telemetry fan-out **silently**, under `|| true`. Use the table.

5. **`quality-checklist` STAYS in loomwright and the selvedge agents keep preloading it cross-plugin.** The spike's Unknown A declined all three fallbacks explicitly (dropping the preload is "strictly worse than doing nothing"); the chosen outcome is one copy, no anti-drift machinery. **Consequence the source requirement got backwards:** it says "if the preload was dropped… budgets **drop**". The preload is NOT dropped, so the selvedge budgets are re-measured with `quality-checklist` still counted.

6. **BLOCKING, MEASURED, AND THE HARDEST PART OF THIS SLICE — fact 5's decision does not currently pass the gate that slice 02 shipped.** `scripts/check-token-budget.sh` resolves every preloaded skill **plugin-locally**: `skill_file="$SKILLS_DIR/$skill/SKILL.md"` inside `run_check`, with `run_gate` calling `run_check "$pdir/agents" "$pdir/skills" …`. A selvedge agent declaring `skills: - quality-checklist` therefore resolves to `selvedge/skills/quality-checklist/SKILL.md`, which will not exist. **Proven by running it, not by reading it** — a scratch fixture with `qa-strategist.md`, its two QA skills present and `quality-checklist` absent produced:
   ```
   qa-strategist             18143        -  ERROR   missing preloaded SKILL.md for: quality-checklist
   check-token-budget: FAILED — prompt inventory ratchet tripped
   ```
   So this slice must extend the gate's skill resolution, not just move files. See "Implementation Guidance §A" for the required shape and its teeth.
   *(Trap recorded from that same run: the visible `rc=0` was the `tail` pipeline's status, not the gate's. Read the gate's own FAILED line, or run it unpiped.)*

7. **`check-shared-prefix.sh` needs no change.** It is already plugin-aware with a single loomwright-owned canonical and an explicit cross-plugin dependency; it fails loudly if `loomwright` is absent from the manifest and skips silently for a plugin with no `agents/`. Today `grep -rlF "SHARED-AGENT-PREFIX v1" loomwright/agents/` = **14**. After the move: 12 loomwright + 2 selvedge, all byte-identical against the one canonical.

8. **`check-contract-parity.sh` carries the plugin dimension INSIDE column 1** — the row format is a four-column public contract and **must gain no column** (a second out-of-tree consumer re-parses the same heredoc with a four-column read). Two rows flip:
   - `MANIFEST`: `loomwright:qa-executor|qa-executor.md|QA_RESULT|…` → `selvedge:qa-executor|…`
   - `ENUMS`: `loomwright:agents/qa-executor.md|status|…` → `selvedge:agents/qa-executor.md|status|…`
   The gate resolves `HOOKS`/`AGENTS`/the validator path from the row's plugin, and expands `${CLAUDE_PLUGIN_ROOT}` to that plugin root — so after the flip it reads selvedge's `hooks.json`, selvedge's `agents/qa-executor.md`, and `selvedge/scripts/validate-qa-result.py`. The pin-drift guard greps the validator's **comment- and docstring-stripped** source, so moving the file must not disturb the field names in its executable body.

9. **The source requirement names a test file that does not exist, and undercounts another — the same fail-open path class that bit the previous slice.** It says "`scripts/test-check-contract-parity.sh` (repo root) — 25 QA refs". Measured: `ls scripts/test-check-contract-parity.sh` ⇒ **No such file or directory**. The real file is **`loomwright/scripts/test-check-contract-parity.sh`** with **27** lines matching a **case-sensitive** `grep -c "qa"`. State the grep with any such count — a differently-scoped grep on the same file legitimately returns a different number (case-insensitive, or matching only the two agent names, both give other totals), and an unstated count invites a worker to treat it as a completeness checklist. Repo-root `scripts/` holds only `check-*.sh` plus `test-check-{plugin-selftests,shared-prefix,token-budget}.sh` and `validate-version.sh`. **Run the real path; a wrong path exits 127 and "No such file" reads as noise.**

10. **`loomwright/scripts/test-agent-memory-permission.sh` pins a seven-surface list** at `:69-75` — `AGENT_GUIDELINES.md` plus six `$PLUGIN_ROOT/agents/*.md`, two of which are the QA agents — and its mutation control uses `qa-strategist.md` as the VICTIM (`:195-196`, `:240`). Both the surface list and the mutation control break the moment the files move.

11. **QA-referencing surfaces outside the moving files** (repo-wide `grep -rl 'qa-executor\|qa-strategist'`, excluding `.git/`, `.supervisor/` and the 11 moving paths). **The per-file numbers below are `grep -c "qa"` line counts, case-sensitive — they are ORIENTATION, not a checklist; re-derive with a grep scoped to what you are actually changing.** 5 test scripts (`test-result-validators.sh` 33, `test-run-ground-truth.sh` 10, `test-agent-memory-permission.sh` 4, `test-token-ledger.sh` 3, `test-insights.sh` 2, plus `test-check-contract-parity.sh` 27 and `test-committed-twin-scrub.sh`), the 9 doc-currency surfaces, `agent-help.md` (27 QA refs), `SKILLS_INDEX.md`, `plan-reviewer.md`, `dreaming.md`, `run-ground-truth.sh`, `result_block_parser.py`, `send-telemetry-core.sh`, `send-webhook.sh`, `notify-desktop.sh`, `telemetry-fixtures/qa-failed.json`, three loomwright skills (`self-heal-advisory`, `supervisor-readiness`, `workflow-management`), and the docs deferred to slice 05. **Slice 03 already re-pointed the behavioural spawn/kind sites** — do not re-edit those; verify each is already correct before touching it.

12. **`selvedge/docs/ARCHITECTURE_CONTRACTS.md` is MANDATORY, and the source requirement's stated escape hatch is impossible.** Slice 02's discovery loop always passes a non-empty fourth argument — `run_check "$pdir/agents" "$pdir/skills" "$pdir/docs/prompt-token-budgets.json" "$pdir/docs/ARCHITECTURE_CONTRACTS.md"` — and `run_check`'s mirror block fires whenever that argument is non-empty (`check-token-budget.sh:312-313`), emitting `ERROR contracts mirror file not found` and setting `exit_code=1`. The empty-string skip exists **only** for the hermetic self-test fixtures, reachable via `TOKEN_BUDGET_CONTRACTS_MD=""`, which is not the discovery path. It then requires, per JSON agent, a `## Prompt Token Budgets` row whose **budget** cell equals `.agents[k].budget` **and** whose **MEASURED** cell equals `.agents[k].measured`, with no ghost rows. So the source requirement's §5 alternative — "record explicitly that selvedge has no mirror table yet and why" — **cannot be taken**: the gate fails closed on the missing file. Create the file with a well-formed mirror table.

13. **Both moving agent prompts carry a cross-plugin `${CLAUDE_PLUGIN_ROOT}` path that breaks on the move — the same Unknown-B class slice 03 handled for the telemetry fan-out, missed for the memory writer.** `loomwright/agents/qa-executor.md:766` and `loomwright/agents/qa-strategist.md:507` both read: *"That writer is `${CLAUDE_PLUGIN_ROOT}/scripts/write-agent-memory.sh`"*. `${CLAUDE_PLUGIN_ROOT}` is per-plugin — the measured fact the whole telemetry decision rests on — so after the move it resolves to `selvedge/scripts/write-agent-memory.sh`, which does not and must not exist (`write-agent-memory.sh` is a loomwright-owned single-copy asset).
    Two consequences that decide the fix, **both verified on disk**:
    - **The line is OUTSIDE the byte-identical shared-prefix block**, which spans only `qa-strategist.md:17-26` and `qa-executor.md:19-28`, and the canonical `loomwright/docs/shared-agent-prefix.md` does not contain the writer sentence at all. So editing it does **NOT** break `check-shared-prefix.sh` byte-identity. (Verify this yourself before editing — if it were inside the markers, the correct answer would be the opposite one.)
    - **The sentence is nonetheless replicated verbatim across all six `memory: project` agents** (`code-reviewer`, `launch-pad`, `product-owner`, `red-team-reviewer`, and the two QA agents). Editing only the two moved copies is a deliberate divergence and must be recorded as one.
    **Required fix:** in the two moved prompts only, re-word so the writer is named as a **loomwright-owned** script without a plugin-rooted path that selvedge cannot resolve. **Keep the bare literal `write-agent-memory.sh` in the sentence** — `loomwright/scripts/test-agent-memory-permission.sh:61-64` asserts name-presence of **four** literals, and **all four must survive the re-wording verbatim** — `LIT_REFUSAL='may NOT write its own \`.claude/agent-memory/\` store directly'`, `LIT_WRITER='write-agent-memory.sh'`, `LIT_SURPRISE='The proposal trigger is SURPRISE-ONLY'`, `LIT_BASH='Bash is not restricted by the harness'`. The refusal sentence sits in the **same paragraph** as the path being re-worded and is the one most likely to be disturbed. **Re-run `bash loomwright/scripts/test-agent-memory-permission.sh` immediately after this edit**, not only at the end of the set. Say in the PR why the two copies now differ from the other four.
    **This also exposes a vacuous acceptance the brief would otherwise have shipped:** that test checks *name-presence in prose*, so re-pointing its surface list cross-plugin (§B) leaves it GREEN on a prompt whose writer path is broken, and its existing mutation control (deleting the refusal sentence) does not test path resolution. AC12's grep is therefore widened to cover `selvedge/agents/`.

14. **A THIRD mechanically-forced pin, and a literal grep provably cannot find it — `loomwright/scripts/eval-corpus/parity-emit-block/check.sh` is NOT plugin-aware.** Verified on disk at `:22-23`: it hard-codes `parity="$repo_root/scripts/check-contract-parity.sh"` and `agents="$repo_root/loomwright/agents"`, re-parses the MANIFEST heredoc at `:29`, then at `:33-36` does `agent_path="$agents/$agent"` and fails with `FAIL: $agent missing at $agent_path`. Slice 02 taught `check-contract-parity.sh` itself to resolve AGENTS from the row's plugin — **this second consumer was not widened**. So the moment AC6 flips the row to `selvedge:qa-executor|qa-executor.md|…` while AC1 has `git mv`-ed the file away, it resolves `loomwright/agents/qa-executor.md`, finds nothing, and exits 1.
    - **Fact 8 already knows this file** as "a second out-of-tree consumer [that] re-parses that same heredoc with a four-column read" and correctly protects its **column count** — but not its **path resolution**. Fact 8 guarded one half of that contract and missed the other.
    - **Fix it in commit 3, alongside the row flip**, by mirroring slice 02's `plugin_dirs` / `resolve_row_plugin` idiom so the agents dir comes from the row's plugin. It is in scope here for exactly the reason the slice is atomic at all; it is NOT slice-05 deferral.
    - **It fails LOUDLY, not silently, and does not break a hard gate** — `loomwright/scripts/test-run-eval.sh` asserts against hermetic fixtures (`:58`, `:105`), not the real corpus, so `check-plugin-selftests.sh` stays green. What degrades is the advisory `run-eval.sh` fitness rate and **this brief's own declared ground-truth surface**.
    - **THE GENERALISABLE LESSON, worth more than the fix: fact 11's inventory method structurally CANNOT discover this file.** It contains **zero** occurrences of `qa-executor` / `qa-strategist` (measured) because it derives the agent name from the MANIFEST at runtime. **A DERIVED pin is invisible to a literal grep.** So run a **second, non-literal sweep** before believing the inventory is complete: every consumer of the MANIFEST heredoc, and every hard-coded `loomwright/agents` / `loomwright/skills` / `loomwright/commands` path outside the plugin-aware gates. `bash -c 'grep -rn "loomwright/agents\|loomwright/skills\|loomwright/commands" scripts/ loomwright/scripts/ .github/workflows/ loomwright/hooks/'` is the starting point; judge each hit for whether it should have been plugin-aware. Measured on the two script dirs at base: ~15 hits, every one judgeable — the `check-*.sh` env-override DEFAULTS layered under discovery (legitimate, not the defect), `check-doc-currency.sh`'s deliberately loomwright-scoped counts (selvedge doc-currency is slice 06 per §C), `check-command-sync.sh`'s code-reviewer-only scope, and two header comments. A bounded set, not a haystack — and it recursively covers `parity-emit-block/check.sh`, so the sweep rediscovers its own founding instance, which is the test a generalised sweep has to pass.

## Subtask Structure

Single-Agent Path, ONE worker, no worktree — every change is mutually entangled through the gates (that is the whole premise of the slice) and parallel worktrees would each see a red gate the other fixes.

Ordered commits (each buildable; the gates need only be green at the END of the set, since the moves and the pins are one atomic change by construction):

1. `git mv` all 11 paths + create `selvedge/hooks/hooks.json`, `selvedge/skills/SKILLS_INDEX.md`, `selvedge/scripts/test-result-validators.sh`.
2. Namespace rename in the moved files (frontmatter `name:`, the two internal debate-loop spawns, the command's `subagent_type`, the validator's own docstring/comments) **and** fact 13's writer-path re-wording.
3. Gate data — **budgets are written HERE, not in commit 1**, because commits 1–2 change the very bytes being measured and a weight taken before the rename is stale by construction: `check-token-budget.sh` cross-plugin skill resolution (§A); create `selvedge/docs/prompt-token-budgets.json` **and** `selvedge/docs/ARCHITECTURE_CONTRACTS.md` (fact 12) with matching budget/MEASURED cells; parity `MANIFEST`/`ENUMS` row flips **and** the stale header comment at `scripts/check-contract-parity.sh:207-211`, which justifies the single-validator selection rule with "loomwright:qa-executor also has the telemetry fan-out" — post-split that describes a matcher that no longer exists in that form; **`eval-corpus/parity-emit-block/check.sh` made plugin-aware (fact 14)**; loomwright's `prompt-token-budgets.json` entries removed (its own mirror rows too — the orphaned-budget check and the ghost-row check both fail closed).
4. Tests de-vacuum-ed with mutation controls (§B).
5. Counts + `agent-help.md` + `SKILLS_INDEX.md` + the two `playwright-e2e` pointers + both plugin manifests.

## Configuration

- Cost profile: inherit (`--cheap` was NOT passed on this tick).
- No Beads.

## Acceptance Criteria

- [ ] **AC1** All 11 paths relocated with `git mv` (history preserved — verify with `git log --follow` on one 700+ line agent prompt). `unit-testing` and `quality-checklist` remain in loomwright.
- [ ] **AC2** Namespace renamed using fact 4's table: single-prefix `selvedge:qa-executor` in BOTH plugins' hooks.json matchers; doubled `selvedge:selvedge:qa-*` in every `Task(subagent_type:)` spawn. **Both internal debate-loop call sites in `qa-executor.md` traced by reading them, not by counting search-replace hits** — state-trace the loop and say in the PR where each call site is and what it now resolves to.
- [ ] **AC3** `selvedge/hooks/hooks.json` ships ONE `SubagentStop` matcher `selvedge:qa-executor` carrying `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/validate-qa-result.py" || true`. `loomwright/hooks/hooks.json`'s QA matcher is re-pointed to `selvedge:qa-executor` and retains **only** the fan-out leaf. Hook count **re-derived from the file** with the `jq` output pasted into the PR; expected 23, and if the file says otherwise the file wins.
- [ ] **AC4** `check-token-budget.sh` passes for **both** plugins with `quality-checklist` still preloaded by both selvedge agents, **and still fails closed** on (a) an agent with no declared budget, (b) a genuinely nonexistent skill name in either plugin. Both (a) and (b) demonstrated by a real edit-run-revert with both outputs pasted.
- [ ] **AC4c** The tooth §A genuinely LOSES is named and mitigated: a skill that exists in the **wrong** plugin now resolves silently, so a typo colliding with any sibling plugin's skill name stops being caught. Mitigation must be an assertion, not prose — a cross-resolved skill is **visibly attributed** in the gate output, and a test asserts on that attribution string (not merely on rc=0).
- [ ] **AC4d** The §A change is **bash-3.2-safe / Ubuntu-clean** (no GNU-only `stat`/`sed`/`date` flags, no nested arrays, no `${var//…}` over large strings) — the script's own header commits to this, and this repo has a recorded macOS-green / Linux-red incident for exactly this class. `bash scripts/test-check-token-budget.sh` passes.
- [ ] **AC5** `selvedge/docs/prompt-token-budgets.json` has entries for both agents with proxy weights **re-measured from the post-move files** (+~10% headroom). **Make the measurement observable rather than assertable** — a budget that is too LARGE passes silently (the only breach branch is `if [ "$total" -gt "$budget" ]`), so a worker could satisfy a prose-only version of this AC by copying loomwright's existing numbers and writing the note, and nothing would catch it. Required instead: paste the gate's own post-move **PROXY column** output into the PR; `.agents[<stem>].measured` must equal that number; and the `selvedge/docs/ARCHITECTURE_CONTRACTS.md` mirror row's MEASURED cell must equal it too — at which point the gate enforces it mechanically. Loomwright's two entries **and their mirror rows** removed (orphaned-budget and ghost-row checks both fail closed).
- [ ] **AC5b** `selvedge/docs/ARCHITECTURE_CONTRACTS.md` exists with a `## Prompt Token Budgets` section carrying exactly one row per selvedge agent (fact 12). State in the PR that the source requirement's "or record that selvedge has no mirror table yet" alternative was **not available**, citing the `CONTRACTS_MD` fail-closed branch as the reason — this is a correction to the source requirement, not an unrequested addition.
- [ ] **AC6** Parity `MANIFEST` + `ENUMS` rows flipped to `selvedge:`, **row format still four columns**; the pin-drift guard still resolves `selvedge/scripts/validate-qa-result.py` and finds every pinned field in its stripped source; gate green.
- [ ] **AC7** `check-shared-prefix.sh` green with 12 loomwright + 2 selvedge byte-identical copies against the single loomwright canonical (no second canonical created).
- [ ] **AC8** `check-skills-index-sync.sh` green for both plugins; `selvedge/skills/SKILLS_INDEX.md` has 5 well-formed rows whose Version cells match each `SKILL.md`'s frontmatter; loomwright's 5 rows removed.
- [ ] **AC9** Counts updated on all 9 doc-currency surfaces (`CLAUDE.md`, `README.md`, `AGENT_GUIDELINES.md`, `.claude-plugin/README.md`, `.claude-plugin/marketplace.json`, `loomwright/.claude-plugin/plugin.json`, `loomwright/commands/agent-help.md`, `loomwright/docs/ARCHITECTURE.md`, `loomwright/docs/ARCHITECTURE_CONTRACTS.md`) to 12 / 19 / 36 / 23; `check-doc-currency.sh` rc=0.
- [ ] **AC10** Every relocated or edited test still has teeth. For **each** assertion whose literal subject changed, a mutation control shows it fails when the mechanism is removed — at minimum: the moved `test-result-validators.sh` QA arm, `test-agent-memory-permission.sh`'s surface list (its existing deleted-rule mutation must still fail), and the `agent_type: "loomwright:qa-executor"` literals in `test-insights.sh` / `test-token-ledger.sh`.
- [ ] **AC11** `agent-help.md` no longer advertises `/qa-strategist` or `/qa-executor` as loomwright commands and points users at selvedge.
- [ ] **AC12** No cross-plugin `${CLAUDE_PLUGIN_ROOT}` path survives anywhere, checked in **both** directions: (a) `unit-testing/SKILL.md` and `ci-cd/SKILL.md` `playwright-e2e` pointers rewritten as install-guidance ("install `selvedge@atelier`"); (b) **zero** occurrences under `selvedge/agents/` of a `${CLAUDE_PLUGIN_ROOT}`-rooted path naming a script selvedge does not ship — this is fact 13's `write-agent-memory.sh` case, and the grep must cover the moved prompts, not just the two loomwright skills.
- [ ] **AC13** `selvedge/.claude-plugin/plugin.json` description + counts updated **in place** (2 agents / 2 commands / 5 skills / 1 hook), mirrored in `.claude-plugin/marketplace.json`. Summary, not changelog — no appended version clause.
- [ ] **AC14** Repo-wide sweep of the OLD counts (14 / 21 / 41 / 24) with **flexible separators** returns only legitimate historical mentions (CHANGELOG entries, dated narrative), each named in the PR as intentional. A green `check-doc-currency.sh` is necessary, not sufficient — it verifies claims that ARE made and cannot tell you a claim should not have been made, and agent/command **enumeration prose** is entirely outside its scope.
- [ ] **AC15** **Runtime resolution — the honest limit, recorded rather than silently dropped.** The source requirement asks for "a real QA run emits a `QA_RESULT` that the selvedge hook validates… verified by running it". A live end-to-end QA run cannot be executed from inside this PR: the moved files only become resolvable after `/plugin install selvedge@atelier`, which is a user-side action against a *published* marketplace version, and this branch is not installed. **Do the largest verifiable subset and state the gap plainly in the PR body** rather than claiming an unrun check: (a) both `plugin.json` manifests parse and declare the new counts; (b) `validate-qa-result.py` runs standalone against the moved `qa-result-valid.md` fixture and exits 0, and against a mutated fixture and exits non-zero; (c) the selvedge matcher string is byte-compared against the moved agent's frontmatter `name:`; (d) the marketplace manifest resolves selvedge's `.source` to a dir that now contains `agents/`, `commands/`, `skills/`, `hooks/`, `scripts/`. The live-install check is handed to slice 07 (migration/release) — name it there in the PR body.
- [ ] **AC15b** `loomwright/scripts/eval-corpus/parity-emit-block/check.sh` resolves its agents dir from the MANIFEST row's **plugin**, not a hard-coded `loomwright/agents` (fact 14). Verified by `bash loomwright/scripts/run-eval.sh` reporting the **same task count and pass rate at base `742a6df` and on the final branch** (that pairing specifically — a "before" taken mid-branch, after the `git mv` but before the fix, legitimately reports 5/6 and would let a 5/6→6/6 delta stand in for a no-regression proof against base) — a DROP means a corpus task stopped resolving. Paste both runs. Also complete fact 14's **derived-pin sweep** and name in the PR every hit judged intentional.
- [ ] **AC16** Full hard-gate loop green, run at the **repo-root** paths (fact 9): `bash scripts/check-plugin-selftests.sh` exit 0, plus every `check-*.sh` and the four self-tests listed in §"Verification commands". Paste the `check-plugin-selftests.sh` suite/assertion totals into the PR — a suite count that DROPS without explanation means a test stopped being discovered by the move.

## Executable Acceptance

Machine-run by `run-ground-truth.sh`, which parses **leading-`-` bullets from this section only**
(``loomwright/scripts/run-ground-truth.sh:213 [pins: `"## Executable Acceptance") in_section=1`]``); the next `## `
heading closes the section, so §"Verification commands (worker-facing)" below is deliberately NOT parsed.

**`corpus-task:` bullets only — deliberately, not by omission.**
``loomwright/skills/supervisor-readiness/SKILL.md:198 [pins: `MUST NOT emit `cmd:``]`` forbids a
machine-authored brief from emitting `cmd:` / bare-shell bullets, and this brief is Launch-Pad-authored
under `/automate`. An earlier revision of THIS brief carried 11 bare-shell bullets, which was wrong
twice over — it breached that convention, **and** it would have verified nothing on this brief's own
dispatch path, because Supervisor passes `run-ground-truth.sh --no-cmd` on the unattended route
(``loomwright/skills/self-heal-advisory/SKILL.md:264 [pins: `NO_CMD_FLAG`]``) and every bullet would
have recorded `unverified` / `cmd_disabled`. The same trap the immediately-preceding slice was
corrected for; recorded here rather than quietly fixed. The four below are bundled corpus tasks under
`loomwright/scripts/eval-corpus/`, each deterministic, read-only, and `--no-cmd`-unaffected.

**They are NOT equally load-bearing, and saying so is the point** — four green bullets otherwise read
as four slice-relevant signals when there are really two:

| Bullet | What it actually bears on this slice |
|---|---|
| `doc-currency-green` | **Load-bearing.** Runs the count gate; the 12 / 19 / 36 / 23 changes are exactly what it checks. |
| `parity-emit-block` | **Load-bearing — and it FAILS by construction until fact 14 is fixed.** Left in deliberately: it is the surface that proves fact 14's fix landed. |
| `version-consistent` | Manifest-wellformedness tripwire only. This slice edits both manifests' descriptions and counts but not versions, so it catches malformed JSON, nothing more. |
| `eval-selftest-green` | Unrelated regression tripwire; passes identically before and after regardless of what the worker does. Included for corpus completeness, not as evidence. |

- corpus-task: doc-currency-green
- corpus-task: parity-emit-block
- corpus-task: version-consistent
- corpus-task: eval-selftest-green

**The full gate set is NOT expressible here** (there is no corpus task for `check-token-budget.sh`,
`check-shared-prefix.sh` or `check-skills-index-sync.sh`). Those are worker-run and PR-evidenced via
§"Verification commands" below and AC16 — stated plainly so a green ground-truth surface is not
mistaken for full gate coverage. `contract_conformance_status` on this brief means "these four tasks
passed", not "the slice is verified".

## Verification commands (worker-facing)

Run every one of these; they are the real gate set, and they are here rather than in
§"Executable Acceptance" because a machine-authored brief may not emit bare-shell bullets there:

```bash
bash scripts/check-doc-currency.sh          # rc 0
bash scripts/check-token-budget.sh          # rc 0, BOTH plugins listed
bash scripts/check-shared-prefix.sh         # rc 0
bash scripts/check-contract-parity.sh       # rc 0
bash scripts/check-skills-index-sync.sh     # rc 0
bash scripts/check-plugin-selftests.sh      # rc 0 — runs every plugin's test-*.sh
bash scripts/test-check-token-budget.sh     # rc 0 — the §A change must not break the gate's own self-test
bash loomwright/scripts/test-check-contract-parity.sh
bash loomwright/scripts/test-agent-memory-permission.sh
bash loomwright/scripts/test-citation-drift.sh
```

Do NOT pipe these to `head`/`tail` and read the pipeline's status — that is the exact trap this brief
records in §D; `check-command-sync.sh` is deliberately absent because it only inspects
`loomwright/commands/code-reviewer.md` and is green regardless of this slice.

**PATH NOTE (fact 9):** the seven `check-*.sh` gates and `test-check-{plugin-selftests,shared-prefix,token-budget}.sh` live at **repo-root `scripts/`**. Everything else — including `test-check-contract-parity.sh` — lives at **`loomwright/scripts/`**. A wrong path exits **127** and reads as noise. Verify with `ls` before trusting a green.

```bash
# Counts — the four expressions the gate itself uses (check-doc-currency.sh:53-56).
find loomwright/agents   -maxdepth 1 -name '*.md' | wc -l      # expect 12
find loomwright/commands -maxdepth 1 -name '*.md' | wc -l      # expect 19
find loomwright/skills   -mindepth 1 -maxdepth 1 -type d | wc -l  # expect 36
jq '[.hooks[][].hooks[]] | length' loomwright/hooks/hooks.json # RE-DERIVE (expect 23)
jq '[.hooks[][].hooks[]] | length' selvedge/hooks/hooks.json   # expect 1

# Shared prefix copies: 12 + 2, against ONE canonical.
grep -rlF "SHARED-AGENT-PREFIX v1" loomwright/agents/ | wc -l   # expect 12
grep -rlF "SHARED-AGENT-PREFIX v1" selvedge/agents/   | wc -l   # expect 2

# Namespace forms (fact 4). Matchers single-prefix; spawns doubled.
jq -r '.hooks|to_entries[]|.key as $k|.value[]|"\($k) :: \(.matcher)"' loomwright/hooks/hooks.json selvedge/hooks/hooks.json | grep -i qa
grep -rn 'subagent_type' selvedge/agents/qa-executor.md selvedge/commands/qa-executor.md

# Old-count sweep with FLEXIBLE separators (AC14) — run under bash, quoted globs.
bash -c 'grep -rnE "\b(14|21|41|24)\b" --include="*.md" --include="*.json" . | grep -iE "agent|command|skill|hook" | grep -v CHANGELOG'

# No cross-plugin ${CLAUDE_PLUGIN_ROOT} path (AC12) — must return ZERO.
bash -c 'grep -rn "CLAUDE_PLUGIN_ROOT" loomwright/skills/unit-testing/SKILL.md loomwright/skills/ci-cd/SKILL.md'

# Commit hygiene over the WHOLE branch. The two pre-existing artifacts must NOT appear.
git diff --name-only origin/main...HEAD | grep -E 'results\.jsonl|IMPECCABLE_TEARDOWN' && echo "HYGIENE FAIL" || echo "hygiene ok"
```

## Implementation Guidance

### §A — the `check-token-budget.sh` cross-plugin skill resolution (fact 6)

The gate encodes an assumption the spike **falsified**: that a preloaded skill lives in the declaring agent's own plugin. Cross-plugin preload was measured working at runtime, and slice 01 chose it. So the gate must learn the same resolution order the runtime has — and must lose no teeth doing it.

Required shape:
- In `run_check`, when `$SKILLS_DIR/$skill/SKILL.md` is absent, fall back to a **list of sibling skills dirs** before declaring the reference missing. Only a skill found in **no** dir is an ERROR.
- Populate that list in a **PRE-PASS over `plugin_dirs` BEFORE the budgeting loop is entered** — not incrementally inside it. `run_gate` calls `run_check` *inside* its own `while … read -r name pdir` loop, so a list built during iteration is only complete for the LAST plugin. `.claude-plugin/marketplace.json` happens to list loomwright first and selvedge fourth, so an incremental implementation would pass **today purely by manifest ordering** and break silently the moment a plugin is reordered or added. Mutation-control it: reorder the manifest so selvedge precedes loomwright and show the gate still passes. Layer it **under** the existing env overrides exactly as slice 02 layered its discovery, so **every prior caller stays byte-identical**: under a pure `TOKEN_BUDGET_*` override run with no fallback list set, behaviour must be unchanged from today.
- Report the resolution honestly — a skill counted from another plugin should be visibly attributed (the DETAIL column, or the `N preloaded skills` note), because a silently cross-resolved skill is how a genuine typo would start passing.
- **Mutation control (AC4b):** point a selvedge agent at a skill name that exists nowhere and show the gate still ERRORs. Do not accept "it passes now" as evidence the guard survived — this repo has a recorded case of a shared-fixture default silently disarming the one assertion it was meant to protect.

### §B — de-vacuum-ing the tests (AC10)

- `test-result-validators.sh`: **move the QA arm** into a new `selvedge/scripts/test-result-validators.sh` (a plugin's tests belong with the plugin; slice 02 already taught CI to run them). Do not point the loomwright test cross-plugin.
- `test-agent-memory-permission.sh`: the contract (`AGENT_GUIDELINES.md`'s agent-memory write rule) **stays single-copy in loomwright**, so make the surface list cross-plugin rather than duplicating the check. Its existing mutation control uses `qa-strategist.md` as VICTIM — re-point it and **prove it still fails** when the rule is deleted.
- `test-insights.sh` / `test-token-ledger.sh`: these assert on `agent_type: "loomwright:qa-executor"` ledger lines. Since loomwright keeps the fan-out matched on `selvedge:qa-executor`, the honest update is the new literal — not deletion. An assertion whose subject no longer exists is vacuous; say in the PR which literal each now asserts and why.
- `test-run-ground-truth.sh`: slice 03 already made a decision on the reserved kind — **read what it recorded and conform**, do not re-decide.

### §C — things that are NOT yours

Deferred to slice 05, and say so explicitly in the PR body so a reviewer sees it is intentional: `QA_SYSTEM_BLUEPRINT.md` relocation, `RESULT_SCHEMAS.md` `QA_RESULT` ownership, the `ARCHITECTURE*.md` **narrative** (their counts ARE yours), `HOOKS.md`, `TELEMETRY.md`, `POINTER_AUDIT.md`, `FAILURE_ESCALATION.md`, `AGENT_GUIDELINES.md` narrative rows, `IMPROVEMENTS_ROADMAP.md`, `docs/SPIKES/*` mentions. Agent-memory store migration and selvedge's own doc-currency gate are slice 06; CHANGELOG/README migration notes are slice 07.

### §D — standing traps this repo has actually hit

- **Verify the verification.** Three times in the previous slice a green/zero result was the shell lying: an unquoted glob under zsh, `tr | wc -l` undercounting an alternation's last field, and a `tail`-swallowed exit status. Do not count alternation branches with `wc -l` — use `awk` `split()`.
- **A 0-hit grep is not evidence of absence** until you have confirmed the grep itself ran.
- **Prompts are programs.** A wrong `subagent_type` fails at runtime, not in CI.
- **Do not restate a number from this brief** where the brief tells you to re-derive it.

## Risks

| Risk | Handling |
|---|---|
| §A widens a fail-closed gate and could fail OPEN | Mutation-control both directions (AC4); keep the env-override path byte-identical; run the gate's own self-test `scripts/test-check-token-budget.sh` |
| Matcher form wrong ⇒ telemetry fan-out silently stops under `\|\| true` | Fact 4's table is measured, not inferred; AC3 asserts both plugins' matchers by reading the files |
| A moved test goes vacuous | AC10 requires a per-assertion mutation control, not a green run |
| Enumeration prose goes stale (no gate covers it) | AC14's flexible-separator sweep + naming each surviving hit as intentional |
| **A DERIVED pin is invisible to a literal grep** — an agent path computed from the MANIFEST at runtime carries no `qa-executor` string, so fact 11's inventory structurally cannot find it (this is how `parity-emit-block/check.sh` was missed through two brief revisions) | Fact 14's second, non-literal sweep over MANIFEST consumers and hard-coded `loomwright/{agents,skills,commands}` paths; every hit named intentional in the PR (AC15b) |
| A cross-plugin `${CLAUDE_PLUGIN_ROOT}` path survives in a moved prompt | Fact 13 + AC12(b) grep `selvedge/agents/` specifically; the `write-agent-memory.sh` case is the known instance |
| Duplicating a loomwright-owned shared asset | Explicit AC7/§B: one canonical prefix, one `quality-checklist`, one memory-permission contract |

## Outcomes Rubric

- QA subsystem lives in selvedge and is proven resolvable by the strongest check a PR can actually run — validator standalone-green on the moved fixture and non-zero on a mutated one, matcher byte-matching the moved agent's frontmatter `name:` — with the live-install proof explicitly handed to slice 07. *(This bullet deliberately departs from the source requirement's "proven by an executed QA run": AC15 establishes that a live run is impossible from inside this PR, and a rubric demanding it would force a grader to fail a brief for correctly saying so.)*
- Atomicity is justified per-cut against a named gate, and nothing separable was swept in
- Every mechanically-forced pin moved in the same commit: budgets **and their contracts mirror**, parity rows, shared prefix, index, **and the DERIVED pins a literal grep cannot see** (the corpus-task MANIFEST consumer)
- Hook count re-derived from `hooks.json` with output attached; 22 vs 23 settled by measurement
- No moved or edited test went vacuous — each changed assertion is mutation-controlled
- No loomwright-owned shared asset duplicated; no cross-plugin `${CLAUDE_PLUGIN_ROOT}` path
- Old counts swept repo-wide with flexible separators; remaining hits verified intentional

## Handoff

```
/loomwright:supervisor .supervisor/jobs/pending/2026-08-20-relocate-qa-agents-commands-skills.md
```

---

> **ABANDONED 2026-08-22 by owner decision** — the selvedge QA-extraction track is not being pursued. Retired here from the active queue so no `/automate` or `/supervisor` tick re-picks it. `main` was force-pushed back past this track on 2026-08-20T15:31:01Z; the work survives only on `origin/feature/relocate-qa-to-selvedge`. Requirements remain at `.supervisor/requirements/selvedge-extraction/` if the decision is ever reversed.
