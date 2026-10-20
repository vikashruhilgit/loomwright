# Supervisor Job: Split commands/dreaming.md, setup.md and agent-help.md into routers + on-demand part files (move-only)

## Environment
- **Project:** ai-agent-manager-lanes/automate-2026-10-15-163325/L20 (lane checkout; repo `vikashruhilgit/loomwright`)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 2 (branch mode ON — `.supervisor/` run history lives on the metadata branch; this is lane L20 of a 4-lane wave, so sibling lanes may edit `loomwright/docs/vendor-coupling-manifest.json`, `loomwright/docs/prompt-token-budgets.json` or `loomwright/scripts/fixtures/self-test-weights.tsv` in the same wave)
- **Source requirement:** .supervisor/requirements/automate-speed/22-split-big-commands.md
- **Base commit:** 626f35fab85796da1c0a4da0b2e80480a8249a02

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Markdown moves + bash 3.2-safe test/gate edits; no new dependency |
| 2 | Dependency Availability | GO | Reuses the existing split machinery: `loomwright/scripts/fixtures/automate-loop-split/assemble.sh` (generic: any index, `<!-- split:begin <file> -->` / `<!-- index-only:begin -->` markers, a leading `../` allowed inside the plugin root) and the `test-automate-loop-split.sh` design (parallel-automate/22) |
| 3 | Architecture Fit | CAUTION | Part files must live outside `commands/` (a subdir there registers namespaced commands) and outside `skills/` (changes the skill count) → `loomwright/docs/command-parts/<command>/`. Several gates and tests read these three docs' TEXT and go red, or silently lose coverage, when text moves: `scripts/check-token-budget.sh` (`.commands[<stem>]` measures `<commands dir>/<stem>.md` only — parts would be unmeasured), `scripts/check-doc-currency.sh` (`FILES` lists `loomwright/commands/agent-help.md`; its `### /<cmd>` check greps that file), `check-vendor-coupling.sh` (per-path allowances: agent-help 11, dreaming 57, setup 118), `test-curation-status.sh` legs (k)/(o), `test-rules-docs.sh` (h5)/(h6), `test-setup-memory.d/05-branch-mode-consent.sh` (fn-4)/(fn-1). Resolved by the integration subtask |
| 4 | Scope vs Supervisor Capability | CAUTION | ~316 KB of prose moves plus ~10 gate/test edits; three file-disjoint groups (one per command, each a router + ≥3 parts) ⇒ split `genuine-parallelism`, plus one integration subtask |
| 5 | Hard Blockers | GO | none |

**Overall Verdict:** CAUTION

## Task
**Goal:** Turn `loomwright/commands/dreaming.md`, `commands/setup.md` and `commands/agent-help.md` each into a router under 20 KB (shared rules + "for sub-command/phase X, read <part>") whose moved sections live verbatim in part files under `loomwright/docs/command-parts/<command>/`, read at runtime only when that sub-command, module or phase runs (owner decision D6: move-only).

**Problem Statement:**
The owner needs `/setup memory`, a declined `/dreaming` or a bare `/agent-help` to read only the text that invocation uses, and needs edits to one module or phase to touch one small file.
Currently each doc is read whole on every invocation (137,515 / 93,858 / 84,712 bytes at base), so `/setup memory` reads every module's flow and every edit lands in one huge file.
Success looks like: `/setup memory` reads the router and the memory part only (proven from a transcript), each router < 20,480 bytes, router + parts = the original bytes (assembled text identical), every gate green with no coverage lost.

## Acceptance Criteria
- [ ] AC1 — Given each of the three docs, when it is split, then it becomes an INDEX in the parallel-automate/22 convention: every moved run of whole sections is replaced by `<!-- split:begin ../docs/command-parts/<command>/<part>.md -->` … `<!-- split:end ../docs/command-parts/<command>/<part>.md -->` holding one index entry per moved heading (each heading line outside code fences, in order, followed by exactly one `See [<path>](<path>).` line, `<path>` the same relative path as the marker); runtime-only router prose (the read rules of AC3) sits in `<!-- index-only:begin -->` … `<!-- index-only:end -->` blocks; and `bash loomwright/scripts/fixtures/automate-loop-split/assemble.sh loomwright/commands/<command>.md` prints text byte-identical to `git show 626f35f:loomwright/commands/<command>.md` (no other edit to any moved or kept line — move-only).
- [ ] AC2 — Given each router, then `wc -c` is < 20480 bytes, and the ASSEMBLED text (router with each split block replaced by its part, index-only blocks dropped) is byte-identical to the base (AC1) — so the content of router + parts is exactly the original. The routing overhead (index entries, markers, read rules) is extra on top of the original bytes and is measured per command in the evidence file (see `## Open decisions` OD1 for why the requirement's literal "router + parts ≤ original" is read this way). The router keeps its frontmatter byte-unchanged (`description:` is what `build-capabilities.sh` reads) and keeps every section every invocation of that command needs (listed per command in Subtask Structure).
- [ ] AC3 — Given each router, then an index-only read rule tells the runtime which part to `Read` from `${CLAUDE_PLUGIN_ROOT}/docs/command-parts/<command>/` for each sub-command / module / phase, one Read call per file, and to read no other part: for `/setup` every module name (`observability`, `memory`, `rules`, `statusline`, `telemetry`, `notifications`, `webhook`, `beads`, `mysql-mcp`) maps to exactly one part, bare `/setup` reads the dashboard part and then each selected module's part, an unrecognised module reads nothing; for `/dreaming` a readiness decline reads no part, and each later step names the part it needs (workflow, reflection prompt, report sections, rules-PR delivery only when a harvested proposal is accepted, memory-PR delivery only when memory writes were recorded, approval contract, the final record step); for `/agent-help` a bare invocation answers from the router (Quick Start + the Command Reference index, whose entries name every command) and reads a command's part only for detail on that command. Every part file of the command is named by the read rule (no unreachable part).
- [ ] AC4 — Given `/setup memory status` run headless against this branch's plugin (Validation 2), when its transcript (stream-json) is read, then the only `docs/command-parts/` file any `Read` tool call names is `docs/command-parts/setup/memory.md` (the router itself is injected as the command body; `skills/setup/SKILL.md`, the Step 0 authority, is not a part and is allowed); the extracted list of Read paths is pasted into the evidence file and the PR body.
- [ ] AC5 — Given the CLAUDE.md invariant grep `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "`, when it runs on base and on the branch, then its output with the line-number field dropped (`sed -E 's/^([^:]+):[0-9]+:/\1:/'`) is identical (same files, same matched line text — the `--auto-merge` bullet stays in `commands/agent-help.md`'s `### 🤖 /automate` section, which stays in the router), no file under `loomwright/docs/command-parts/` produces a hit for the same positive-form grep (`grep -rn "gh pr merge --squash" loomwright/docs/command-parts/ | grep -viE "no |never |not "` prints nothing — `dreaming.md`'s negated "it never runs `gh pr merge --squash`" line moves into a part and is correctly filtered, exactly as it is today), and `test-automate-next-step.sh`'s `SURFACE_BASE` list is unchanged and its leg passes.
- [ ] AC6 — Given a new `loomwright/scripts/test-command-parts.sh` (modelled on `loomwright/scripts/test-automate-loop-split.sh`, reusing its `fixtures/automate-loop-split/assemble.sh`, not a copy of it), when it runs, then it checks for each of the three routers: A each router assembles (exit 0, non-empty); B index entries (AC1 form, fence-aware: a heading inside a ``` / ~~~ fence is never an entry or a required entry); C no orphans — every `*.md` under `loomwright/docs/command-parts/<command>/` is named by exactly one block of `commands/<command>.md`, every block names a file under that directory, and every directory under `docs/command-parts/` has a matching `commands/<name>.md`; D the router's fence-aware heading sequence equals the assembled text's; E move-only — the assembled text's sha256, size and line count equal the base values recorded in `loomwright/scripts/fixtures/command-parts/move-only.txt` (from `626f35f`, no git history needed at test time), retiring to ONE named SKIP line per command once a later edit changes a router or part away from its split-time sha256 (also recorded; hashed with index-only blocks dropped), exactly as the precedent's check E; F AC2's size bound (router < 20480 bytes) — never retired; G AC3's read rule names every part file of its command under `${CLAUDE_PLUGIN_ROOT}/docs/command-parts/<command>/`, and `/setup`'s rule maps each module name of the router's `## Parameters` list to exactly one part; H AC5's positive-form no-squash rule over the parts; M mutation controls, each mutant gated on non-empty + differs (+ `bash -n` for a script mutant): a See line dropped (B), an unreferenced part (C), one changed byte in a part (E), a router padded past 20480 bytes (F), the `memory` mapping removed from `/setup`'s read rule (G), a part gaining a positive-form line `runs \`gh pr merge --squash\`` with no negation (H). Exit 0 = all pass, 1 = any failure; read-only; scratch under `mktemp -d`; `env LC_ALL=C` (never `LC_ALL=C <cmd>` at command position — `scripts/check-locale-prefix.sh`).
- [ ] AC7 — Given `scripts/check-token-budget.sh`, then a `.commands[<stem>]` row's weight is `<commands dir>/<stem>.md` PLUS every `*.md` under `<command parts dir>/<stem>/` counted recursively (default `loomwright/docs/command-parts`, overridable as `TOKEN_BUDGET_COMMAND_PARTS_DIR` like the other dirs; same per-file floor proxy and the same fail-CLOSED symlink/unreadable rules as `skill_weight`), the row's detail names the part count, and a directory under the parts dir with no `<commands dir>/<name>.md` is an ERROR (orphaned parts dir). The weight is the true bytes a full read pays (router + every part), so it exceeds the base by the routing overhead: where a row breaches, raise that `.commands[<stem>].budget` in `prompt-token-budgets.json` (and its mirror row in ARCHITECTURE_CONTRACTS, in the same edit) by no more than the measured overhead + ~10%, with the one-line `note` `as22: router + parts = base + index/read-rule overhead (<n> proxy tokens)`; `measured` set to the new weight; no other row changes. A raise beyond the measured overhead is STOP-and-report. `scripts/test-check-token-budget.sh` gains legs: parts counted into the row (a fixture whose router fits but router + part breaches ⇒ BREACH), an orphaned parts dir ⇒ ERROR, a symlink under a parts dir ⇒ ERROR, no parts dir ⇒ the router alone (unchanged behaviour); `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" states the new `.commands` weight in the sentence `A **command doc's** weight is …` and its self-test list (mirror tables unchanged).
- [ ] AC8 — Given `scripts/check-doc-currency.sh`, then its `FILES` scan set also covers every `loomwright/docs/command-parts/agent-help/*.md` (expanded at run time, sorted; an empty expansion adds nothing and is not an error — the router stays listed), so no version/count claim that moved out of `agent-help.md` escapes the gate; its `command-documented` check (`grep -qE "^### .*/${cmd} " "$help_md"`) still passes against the router's index entries; `scripts/test-check-doc-currency.sh` gains a leg proving a stale version claim inside an agent-help part file is reported as DRIFT.
- [ ] AC9 — Given every OTHER consumer that reads the TEXT of the three docs (base set: `git grep -nE 'commands/(dreaming|setup|agent-help)\.md' -- 'loomwright/scripts/*.sh' 'loomwright/scripts/test-*.d/*.sh' 'scripts/*.sh' 'loomwright/scripts/*.py'` plus any test that reads them through a variable or a `commands/*.md` loop, re-scanned on the integrated branch), when each runs on the integrated branch, then it reports the same `<passed>/<total>` as base: `test-curation-status.sh` legs (k)/(o) (`DREAM=` / `HELP=` and the `grep -E '^\| \`--sessions N\` \|' "$PLUGIN_ROOT/commands/dreaming.md"` read), `test-rules-docs.sh` (h5)/(h6) (`region_verbs "$PLUGIN_ROOT/commands/agent-help.md"`) and `test-setup-memory.d/05-branch-mode-consent.sh` (fn-4)/(fn-1) (`"$(cat "$HERE/../commands/setup.md" 2>/dev/null)"`) read the ASSEMBLED text (assemble.sh output written once to a temp file), assertion text and expected values byte-unchanged; a consumer that only names the path in a comment is left alone; a consumer whose check would only be satisfied vacuously is STOP-and-report.
- [ ] AC10 — Given `loomwright/docs/vendor-coupling-manifest.json`, when `bash scripts/check-vendor-coupling.sh` runs on the integrated branch (after `git add`), then it passes with the flat total unchanged: the allowances for `loomwright/commands/agent-help.md` (11), `loomwright/commands/dreaming.md` (57) and `loomwright/commands/setup.md` (118) are re-distributed to the router and part paths that now carry those references (measured with `bash scripts/check-vendor-coupling.sh --print-allowances`), each new or raised path with one `allowance_reasons` entry reading `moved by automate-speed/22 split — no reference added`; no other key changes.
- [ ] AC11 — Given the invariants of the requirement, when they run on the integrated branch, then `bash scripts/check-command-sync.sh`, `bash scripts/check-doc-currency.sh` (agents/commands/skills counts unchanged), `bash scripts/check-skills-index-sync.sh`, `bash loomwright/scripts/test-citation-drift.sh`, `bash scripts/check-token-budget.sh`, `bash loomwright/scripts/test-automate-loop-split.sh` and `bash loomwright/scripts/test-build-capabilities.sh` pass with base totals (plus the new legs), and `loomwright/capabilities.json` and `loomwright/hooks/hooks.json` are byte-unchanged.
- [ ] AC12 — Given the integrated branch, then a committed evidence file `docs/evidence/as22-split-big-commands.md` contains: the before/after `<passed>/<total>` for every gate and test in AC6–AC11 (and `bash scripts/ci-local.sh` totals for base and branch, every red leg shown red on base too — Validation 1); the final part map per command (part → headings it holds → bytes) and each router's bytes vs base; AC5's two grep outputs; the AC4 and Validation 2 commands and their pasted outputs; every committed citation of a moved heading found by `git grep -nE '(dreaming|setup|agent-help)\.md'` over `*.md` judged still resolving through the router's index entry — and the PR body links to it and pastes the Validation 2 output under a `Validation 2 — Running system` heading in a fenced block.
- [ ] AC13 — Given `changelog.d/as22-split-big-commands.md`, then it exists in the `changelog.d/README.md` format with `<!-- bump: minor -->` as its first line (the requirement's Goal marker), and `plugin.json`, `marketplace.json` and `CHANGELOG.md` are not hand-edited (`bash scripts/check-version-bump.sh` passes).

## Touched-file invariants

> Grounded at base `626f35f`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/commands/setup.md`, `loomwright/commands/dreaming.md`, `loomwright/commands/agent-help.md`** — keep: the frontmatter block byte-unchanged (`description:` is read by `build-capabilities.sh` via `fmval "$ROOT/commands/$rel" description`); every heading at its old path (in place, or as an index entry — citations like `commands/setup.md §Branch mode` and `docs/evidence/as20-split-memory-and-meta-scripts.md`'s `loomwright/commands/setup.md:268` table rows resolve through the entry); `agent-help.md`'s `### 🤖 /automate — Generic Automation Engine (v14.41.0)` section in the router, holding `the **only** place in the plugin that executes \`gh pr merge --squash\``; reuse: the marker lines exactly as `commands/automate.md` writes them (`<!-- split:begin ../skills/automate-loop/command-lanes.md -->`, `See [../skills/automate-loop/command-lanes.md](../skills/automate-loop/command-lanes.md).`, `<!-- index-only:begin -->`); mirror: `assemble.sh`'s marker grammar (`SPLIT FILE PATHS: a relative *.md path of [A-Za-z0-9._/-] characters`; a split file `must … end with a newline`); fired by: the Claude Code command loader (`/setup`, `/dreaming`, `/agent-help`, and `/loomwright:<name>` headless), which substitutes `${CLAUDE_PLUGIN_ROOT}` in the body; pinned by: `test-curation-status.sh` (`grep -qF 'curation-status.sh" record dreaming' "$DREAM"`, `help_insights_section`'s `sed -n '/^### .* \/insights /,/^### .* \/obsidian /p' "$HELP"`), `test-rules-docs.sh` (`'^\*\*Purpose:\*\* Maintain the plugin.s first'`, `'^\*\*Usage:\*\* .?/rules list'`), `test-setup-memory.d/05-branch-mode-consent.sh` (`hasF '**\`off\` is reserved**'`), `scripts/check-doc-currency.sh` (`grep -qE "^### .*/${cmd} " "$help_md"`), `test-automate-next-step.sh` (`SURFACE_BASE="loomwright/commands/agent-help.md`), `vendor-coupling-manifest.json` (`"loomwright/commands/setup.md": 118`).
- **`scripts/check-token-budget.sh`** — keep: `set -uo pipefail`; the fail-CLOSED rules for the `.commands` table (`check_ceiling commands "$stem" …`, `check_orphans commands "$seen_commands" "command doc $COMMANDS_DIR/<stem>.md"`, the dangling-symlink ERROR `command doc $cmd_file is a dangling symlink`, the zero-command guard `refusing to pass a 0-command ratchet`); the `TOKEN_BUDGET_*_DIR` override idiom (`COMMANDS_DIR="${TOKEN_BUDGET_COMMANDS_DIR:-loomwright/commands}"`); bash 3.2 portability (`No \`${var//...}\` pattern-subst on large strings`, sizes from `wc -c`); reuse: `skill_weight` (its `return 2` symlink and `return 1` unreadable contract) for the parts dir instead of a second walker; the header block's per-table description (`#   .commands[<stem>] — a command doc's weight: <commands dir>/<stem>.md.`) is updated to name the parts; pinned by: `scripts/test-check-token-budget.sh` (`TOKEN_BUDGET_AGENTS_DIR="$1" TOKEN_BUDGET_SKILLS_DIR="$2" TOKEN_BUDGET_JSON="$3"` harness — add the parts-dir variable the same way, defaulting legs that do not set it to a nonexistent dir so their totals are unchanged).
- **`scripts/check-doc-currency.sh`** — keep: `set -uo pipefail`; `report() { echo "  DRIFT [$1] $2:$3 — \"$4\""; fail=1; }`; the `FILES=(` list's existing entries and the comment that `.github/workflows/*.yml are deliberately NOT scanned`; `check_count`/`check_version` loop `for f in "${FILES[@]}"; do [ -f "$f" ] || continue`; the `command-documented` block (`/agent-help is exempt`); bash 3.2 (no `mapfile`; a glob loop under `shopt -s nullglob` or a `[ -e ]` guard); pinned by: `scripts/test-check-doc-currency.sh` and `scripts/check-version-bump.sh`'s call of this script; `bump-version.sh` runs it.
- **`loomwright/scripts/test-curation-status.sh`, `loomwright/scripts/test-rules-docs.sh`, `loomwright/scripts/test-setup-memory.d/05-branch-mode-consent.sh`** — keep: every `ok`/`no` label, needle and expected value byte-unchanged; the final totals lines; hermetic first executable lines (`scripts/check-test-hermetic.sh`); the only permitted hunk is the reader: the doc variable (`DREAM=`, `HELP=`, the inline `"$PLUGIN_ROOT/commands/dreaming.md"` of leg (o), the two `region_verbs "$PLUGIN_ROOT/commands/agent-help.md"` calls, the two `cat "$HERE/../commands/setup.md"`) points at an assembled copy produced once by `bash "$HERE/fixtures/automate-loop-split/assemble.sh" <router> <tmpfile>` (the shape `test-automate-dismissed.sh` uses: `ASM="$HERE/fixtures/automate-loop-split/assemble.sh"`); an assemble failure fails the leg (`no …`), never a silent skip; `05-branch-mode-consent.sh` is a part sourced by `test-setup-memory.sh` — its `HERE` is the runner's.
- **`scripts/test-check-token-budget.sh`** — keep: every existing leg's label and the final lines `echo "check-token-budget self-test: $pass passed, $fail failed"` / `echo "check-token-budget self-test: OK"`; extend the harness line `TOKEN_BUDGET_COMMANDS_DIR="${5-$CMDS}" bash "$GATE"` with a parts-dir variable whose default is a nonexistent dir, so existing legs keep their totals; new legs use hermetic `mktemp -d` fixtures; mutants gated on non-empty + differs + `bash -n`.
- **`scripts/test-check-doc-currency.sh`** — keep: `GATE="$repo_root/scripts/check-doc-currency.sh"`, the copied-tree harness (`cp -a "$repo_root/." "$TMP/"` then `(cd "$TMP" && bash scripts/check-doc-currency.sh 2>&1)`), every existing leg and the final `echo "RESULT: $pass passed, $fail failed"`; the new leg plants a stale `vX.Y.Z` claim in a copied `loomwright/docs/command-parts/agent-help/*.md` and asserts DRIFT naming that file.
- **`loomwright/docs/vendor-coupling-manifest.json`** — keep: flat total unchanged; one `allowance_reasons` entry per new/raised path; `scan_roots` (`["loomwright","scripts",".claude-plugin"]`), `token_classes`, `classes` and every other key byte-unchanged.
- **`loomwright/docs/prompt-token-budgets.json`** — keep: every key outside `.commands.setup`, `.commands.dreaming` and `.commands["agent-help"]` byte-unchanged (`proxy_bytes_per_token`, `raise_rule`, `.agents`, `.skills`); inside those three, only `budget` (≤ measured new weight + ~10%), `measured` (the new weight) and `note` (AC7's text verbatim) change, and only for a row that actually breaches; each changed `budget` equals its ARCHITECTURE_CONTRACTS mirror cell in the same edit (`check-token-budget.sh` asserts the mirror); pinned by: `scripts/check-token-budget.sh` (`.[$t][$k].budget // "null"`). Sibling lanes may edit other rows — never touch them.
- **`loomwright/scripts/fixtures/self-test-weights.tsv`** — keep: the header comment block (`# self-test-weights.tsv — per-test weight in seconds for run-self-tests.sh --shard`), the `<seconds><TAB><path>` row format and existing order; at most ONE added row for `loomwright/scripts/test-command-parts.sh` with measured seconds, only if needed (a test absent from the file gets the runner's default weight — `a test absent from it gets weight 20 — never dropped`); never edit another row; read by `loomwright/scripts/run-self-tests.sh` (`weights="$here/fixtures/self-test-weights.tsv"`).
- **`loomwright/docs/ARCHITECTURE_CONTRACTS.md`** — keep: the three mirror tables of §"Prompt Token Budgets" byte-unchanged (`check-token-budget.sh` asserts each budget cell); edit only the `.commands` weight sentence and the `Self-test: \`bash scripts/test-check-token-budget.sh\`` case list.

## Closed enumerations touched

> Sibling grep at base `626f35f`: `git grep -nF 'TOKEN_BUDGET_COMMANDS_DIR'` → hits in `scripts/check-token-budget.sh` and `scripts/test-check-token-budget.sh` only.

- **`TOKEN_BUDGET_COMMAND_PARTS_DIR`** (sibling: `TOKEN_BUDGET_COMMANDS_DIR`) — must be named in:
  - `scripts/check-token-budget.sh` — the override block `COMMANDS_DIR="${TOKEN_BUDGET_COMMANDS_DIR:-loomwright/commands}"` — extend.
  - `scripts/test-check-token-budget.sh` — the harness env prefix (`TOKEN_BUDGET_AGENTS_DIR="$1" …`) — extend.
  - `scripts/check-test-hermetic.sh` / ci configs — no change: they do not enumerate the gate's env vars.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-command-parts.sh` — E move-only | edit one moved line (append a space) in one part of a scratch copy |
| `loomwright/scripts/test-command-parts.sh` — B index entries | delete one `See [../docs/command-parts/setup/memory.md](../docs/command-parts/setup/memory.md).` line in a scratch copy of `loomwright/commands/setup.md` |
| `loomwright/scripts/test-command-parts.sh` — G read rule | delete the line naming `memory.md` in the read rule of a scratch copy of `loomwright/commands/setup.md` |
| `scripts/test-check-token-budget.sh` — parts counted into the `.commands` row | delete the line that adds the parts weight to the command row in `scripts/check-token-budget.sh` |
| `scripts/test-check-doc-currency.sh` — stale claim in an agent-help part reported | delete the line that appends `loomwright/docs/command-parts/agent-help/*.md` to `FILES` in `scripts/check-doc-currency.sh` |
| `loomwright/scripts/test-command-parts.sh` — A assembles | put a split:begin marker naming a missing part into a scratch copy of `loomwright/commands/agent-help.md` |
| `loomwright/scripts/test-command-parts.sh` — C no orphans | add an unreferenced `extra.md` under a scratch copy of `loomwright/docs/command-parts/setup/` |
| `loomwright/scripts/test-command-parts.sh` — D heading sequence | delete one kept heading line (not an entry) in a scratch copy of `loomwright/commands/dreaming.md` |
| `loomwright/scripts/test-command-parts.sh` — F router < 20480 bytes | pad a scratch copy of `loomwright/commands/setup.md` past 20480 bytes inside an index-only block |
| `loomwright/scripts/test-command-parts.sh` — H positive-form squash | append a line `runs \`gh pr merge --squash\`` to a scratch copy of one part |
| `scripts/test-check-token-budget.sh` — orphaned parts dir ⇒ ERROR | delete the orphaned-parts-dir check in `scripts/check-token-budget.sh` |
| `scripts/test-check-token-budget.sh` — symlink under a parts dir ⇒ ERROR | replace the parts walk's `skill_weight` call with a `find -L` count in `scripts/check-token-budget.sh` |
| `scripts/test-check-token-budget.sh` — no parts dir ⇒ router alone | make the parts walk treat a missing dir as an ERROR in `scripts/check-token-budget.sh` (the leg must go red) |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Split `commands/setup.md` into a router + `docs/command-parts/setup/` | AC1–AC3 (setup) | 1 modify, ~8 create | — | LAUNCHABLE |
| 2 | Split `commands/dreaming.md` into a router + `docs/command-parts/dreaming/` | AC1–AC3 (dreaming) | 1 modify, ~8 create | — | LAUNCHABLE |
| 3 | Split `commands/agent-help.md` into a router + `docs/command-parts/agent-help/` | AC1–AC3, AC5 (agent-help) | 1 modify, ~6 create | — | LAUNCHABLE |
| 4 | Integration: `test-command-parts.sh` + fixture, token-budget and doc-currency gates + their tests, readers, vendor manifest, ARCHITECTURE_CONTRACTS, running system, evidence, changelog | AC4, AC5 (grep + SURFACE_BASE), AC6–AC13 | ~9 modify, ~4 create | `skills/unit-testing/SKILL.md`, `skills/ci-cd/SKILL.md` | BLOCKED (by #1, #2, #3) |

### Rules for subtasks 1–3 (each split)
- **Move by script, never by retyping.** Cut each part with a line-range extraction from the base blob (e.g. `git show 626f35f:loomwright/commands/<c>.md | sed -n 'A,Bp' > <part>`), build the router the same way, then prove AC1 with `diff <(bash loomwright/scripts/fixtures/automate-loop-split/assemble.sh loomwright/commands/<c>.md) <(git show 626f35f:loomwright/commands/<c>.md)` — empty diff before hand-back. A part starts with its first heading and ends with a newline. Cut only at section boundaries outside code fences (`setup.md` has fenced lines that look like headings, e.g. `## /setup — module status` inside the Examples fence; `agent-help.md` has `## Phase 1`, `# Supervisor Job` inside example fences).
- **Index entries for every moved heading outside fences** (AC1). Part file names are short (`[a-z0-9-]+\.md`) to keep the router small.
- **Router size:** measure `wc -c` after building; if a router is ≥ 20480 bytes, move one more section that not every invocation needs (never one the read rule says every invocation needs); record the final map.
- **The read rule** (AC3) is index-only prose placed where the runtime meets it (for `/setup` inside or right after `## Step 0`; for `/dreaming` right after `### Step 0 — readiness`; for `/agent-help` right after `## What This Does`), naming parts by `${CLAUDE_PLUGIN_ROOT}/docs/command-parts/<c>/<part>.md`. Moved text that says "below" now sits in another file — leave it (move-only); the read rule covers it.
- **Gates during subtasks 1–3:** `check-vendor-coupling.sh`, the reader tests of AC9 and `ci-local.sh` are expected red on a subtask-1/2/3 branch until subtask 4 — workers 1–3 run only the AC1 diff and `wc -c`; they never edit a gate, test, manifest or another command.

### Subtask 1 — `/setup` (detail; the worker confirms boundaries against the file)
- **Router keeps:** frontmatter, `# Command: /setup`, `## Usage`, `## Parameters`, `## What This Does`, `# Agent Prompt` preamble, `## Step 0 — Load the protocol authority (every invocation)`, the `## \`/setup <module>\` — jump straight to that module's flow.` heading, `## Constraints (every module)`. `## Examples` stays or moves to `examples.md` (size-driven; record which).
- **Parts (proposed):** `dashboard.md` (`## No-arg flow — status dashboard`), `observability.md`, `memory.md`, `rules.md`, `statusline.md` (each `## Module: <name>` with its subsections), `integrations.md` (the contiguous `## Module: telemetry` … `## Module: mysql-mcp`, which dashboard option 3 runs together; each of those module names maps to it).

### Subtask 2 — `/dreaming` (detail)
- **Router keeps:** frontmatter, the two leading `> **…**` contract blockquotes, `# Command: /dreaming`, `## Purpose`, `## Usage`, `## Parameters`, the `## Curation cadence (readiness check + the one stored last-run record)` intro, `### Step 0 — readiness (runs BEFORE Phase 1 GATHER)` and `### Run report (four mandatory lines)` (a declined run ends with these four lines, so a decline reads no part).
- **Parts (proposed, in documented order; each contiguous):** `record.md` (`### Final step — record this run …`, read after Phase 4 APPROVE), `workflow.md` (`### Where the cadence surfaces`, `## What This Does / Workflow` — read once readiness passes), `reflection-prompt.md` (`## Reflection-Mode Task Prompt` — read before the reflection spawns), `report.md` (`## Reflection Report Sections` … `### Pending agent-memory proposals (promotion queue)`), `rules-pr.md` (`### Harvested \`.agent/rules/\` proposals (PR delivery queue)`), `memory-pr.md` (`### Memory PR (delivery queue)`), `report-notes.md` (`### Harness-memory pointer (on LESSONS Accept)` … `### APPLY deferral (v14.5.0 scope)`), `approval.md` (`## Approval Option Contract` …), `read-only.md` (`## Read-Only Contract` …), `reference.md` (`## Example Output` … `## See Also`). The worker derives each part's trigger from the workflow text (which phase uses it) and records it in the read rule; `read-only.md` is read with `workflow.md` (it is the contract the run must keep).

### Subtask 3 — `/agent-help` (detail)
- **Router keeps:** frontmatter, `# Command: /agent-help`, `## Usage`, `## What This Does`, `# Agent Help Reference`, `## Quick Start`, the `## Command Reference` heading, and the whole `### 🤖 /automate — Generic Automation Engine (v14.41.0)` section (AC5).
- **Parts (proposed, contiguous groups in file order):** `readiness.md` (`### 🚀 /launch-pad` and `### 🤖 /supervisor`), `build.md` (`### 0️⃣ /product-owner` … `### 4️⃣ /red-team-reviewer`), `qa.md` (`### 5️⃣ /qa-strategist` … `### 🔎 /verify`), `knowledge.md` (`### 💤 /dreaming` … `### 🌱 /propose`), `ops.md` (`### 📡 /telemetry` … `### 🔁 /autonomous`), `more.md` (`### 🧩 /setup`, `### 🩺 /review-pr`, `### QA Workflow Diagram`), `guide.md` (`## Daily Workflow Example` … `### QA Pipeline (Test Automatically)`). The worker may regroup (contiguity forces `/automate` to split the reference into a before and an after block).

### Subtask 4 — Integration (detail)
- Runs on the merged result of 1–3.
- **AC6:** `loomwright/scripts/test-command-parts.sh` + `loomwright/scripts/fixtures/command-parts/move-only.txt` (base sha256 / size / lines per command from `git show 626f35f:…`, and the split-time sha256 of each router and part). Copy the precedent's structure and helper style (`ok`/`no`, `ASM=`), not its file list. Run `bash scripts/check-locale-prefix.sh` and `bash scripts/check-test-hermetic.sh` before hand-back. If `run-self-tests.sh` / `ci-local.sh` needs a weights row for a new test, add one to `loomwright/scripts/fixtures/self-test-weights.tsv` (measured seconds); otherwise leave it.
- **AC7, AC8:** the two gate edits + their self-test legs + the ARCHITECTURE_CONTRACTS sentence.
- **AC9:** re-scan consumers; re-point the readers; run each on base (clean `git worktree add` at `626f35f` in the scratchpad, removed after) and branch in the same session.
- **AC10:** `git add` first, then `bash scripts/check-vendor-coupling.sh --print-allowances` for the measured counts; move allowances, add reasons. Siblings in this wave may edit the manifest — touch only these paths' own keys.
- **AC4 + Validation 2 (running system):** run headless sessions from a scratch git repo OUTSIDE this lane checkout (`git init` under the scratchpad; this lane's `.claude/settings.local.json` carries the lane relay hook, so a session started in the lane would record its questions as lane questions), against this branch's plugin: `claude -p "/loomwright:setup memory status" --plugin-dir <lane>/loomwright --output-format stream-json --verbose`, then `claude -p "/loomwright:setup" …` and `claude -p "/loomwright:agent-help" …` (first lines only; the bare `/setup` dashboard question is not answered). Bound each run (background + a deadline; macOS has no `timeout`). Extract every Read `file_path` with `jq` from the stream; paste the list and each output's first lines into the evidence file and the PR body (fenced). Never run `apply`/`remove`/`migrate`.
- **AC11, AC12, AC13:** gates, evidence file, changelog fragment, then `bash scripts/ci-local.sh` (wait with `bash scripts/ci-local.sh --wait`; exit 3 = still running) on the base worktree and the branch — Validation 1 (`<passed>/<total>` for `check-command-sync.sh`, `check-doc-currency.sh`, `check-skills-index-sync.sh`, `test-citation-drift.sh`).

## Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/docs/command-parts/setup/memory.md"}
  - {kind: "symbol", path: "loomwright/docs/command-parts/setup/memory.md", name: "## Module: memory"}
  - {kind: "file", path: "loomwright/docs/command-parts/setup/dashboard.md"}
  - {kind: "symbol", path: "loomwright/commands/setup.md", name: "<!-- split:begin ../docs/command-parts/setup/memory.md -->"}
requires: []
lanes:
  - "loomwright/commands/setup.md"
  - "loomwright/docs/command-parts/setup/**"
external_requires: []

# Subtask 2
provides:
  - {kind: "file", path: "loomwright/docs/command-parts/dreaming/workflow.md"}
  - {kind: "symbol", path: "loomwright/docs/command-parts/dreaming/workflow.md", name: "## What This Does / Workflow"}
  - {kind: "symbol", path: "loomwright/commands/dreaming.md", name: "### Step 0 — readiness (runs BEFORE Phase 1 GATHER)"}
requires: []
lanes:
  - "loomwright/commands/dreaming.md"
  - "loomwright/docs/command-parts/dreaming/**"
external_requires: []

# Subtask 3
provides:
  - {kind: "file", path: "loomwright/docs/command-parts/agent-help/guide.md"}
  - {kind: "symbol", path: "loomwright/docs/command-parts/agent-help/guide.md", name: "## Daily Workflow Example"}
  - {kind: "symbol", path: "loomwright/commands/agent-help.md", name: "### 🤖 /automate — Generic Automation Engine (v14.41.0)"}
requires: []
lanes:
  - "loomwright/commands/agent-help.md"
  - "loomwright/docs/command-parts/agent-help/**"
external_requires: []

# Subtask 4
provides:
  - {kind: "file", path: "loomwright/scripts/test-command-parts.sh"}
  - {kind: "file", path: "loomwright/scripts/fixtures/command-parts/move-only.txt"}
  - {kind: "symbol", path: "scripts/check-token-budget.sh", name: "TOKEN_BUDGET_COMMAND_PARTS_DIR"}
  - {kind: "file", path: "docs/evidence/as22-split-big-commands.md"}
  - {kind: "file", path: "changelog.d/as22-split-big-commands.md"}
  - {kind: "symbol", path: "changelog.d/as22-split-big-commands.md", name: "<!-- bump: minor -->"}
requires:
  - {from: "1", kind: "file", path: "loomwright/docs/command-parts/setup/memory.md"}
  - {from: "2", kind: "file", path: "loomwright/docs/command-parts/dreaming/workflow.md"}
  - {from: "3", kind: "file", path: "loomwright/docs/command-parts/agent-help/guide.md"}
lanes:
  - "loomwright/scripts/test-command-parts.sh"
  - "loomwright/scripts/fixtures/command-parts/**"
  - "scripts/check-token-budget.sh"
  - "scripts/test-check-token-budget.sh"
  - "scripts/check-doc-currency.sh"
  - "scripts/test-check-doc-currency.sh"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/scripts/test-curation-status.sh"
  - "loomwright/scripts/test-rules-docs.sh"
  - "loomwright/scripts/test-setup-memory.d/05-branch-mode-consent.sh"
  - "loomwright/scripts/fixtures/self-test-weights.tsv"
  - "docs/evidence/as22-split-big-commands.md"
  - "changelog.d/as22-split-big-commands.md"
external_requires:
  - "claude CLI (headless -p, stream-json) on PATH for the AC4 / Validation 2 running-system step"
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──┐
Subtask 2 ──┼──→ Subtask 4
Subtask 3 ──┘
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none | NO |
| Subtask 1 | Subtask 3 | none | NO |
| Subtask 2 | Subtask 3 | none | NO |
| Subtask 1–3 | Subtask 4 | none — subtask 4 reads the routers and parts and NEVER edits them; a gate that needs a router/part edit is STOP-and-report | NO |

### Batch Plan
- **Batch 1:** Subtask 1, Subtask 2, Subtask 3 (parallel — empty `requires`, zero file overlap)
- **Batch 2:** Subtask 4 (after 1–3)
- **Recommended workers:** 3
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | — (markdown move; AC1 diff is the proof) |
| 2 | — |
| 3 | — |
| 4 | `skills/unit-testing/SKILL.md`, `skills/ci-cd/SKILL.md` |

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

(Applied: the routers and the new test state no part count or byte count; measurements live only in the evidence file and the move-only fixture.)

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): gates and tests read these docs' text; moved text goes red or, worse, silently unscanned (token budget, doc-currency) | HIGH | AC7/AC8 extend the two gates to the parts with self-test legs and pin mutations; AC9 re-points readers to the assembled text with expected values unchanged; AC9's re-scan on the integrated branch |
| A hand-retyped move drops or alters a byte (316 KB of prose) | HIGH | Script-cut line ranges; AC1's empty diff against the base blob; AC6 E re-proves it in CI |
| The read rule omits a part a step needs, so a run silently misses instructions (e.g. `/dreaming`'s `curation-status.sh record dreaming` final step) | HIGH | AC3 maps every step/module to a part; AC6 G proves every part is named; AC4 proves `/setup memory` reads its part in the running system |
| `.commands` budgets breach once parts are counted (routing overhead ≈ 8–11 KB per command vs 8–14 KB headroom) | MEDIUM | AC7's bounded, noted raise of exactly the measured overhead; OD1 records it |
| A router does not fit < 20,480 bytes with an entry per moved heading | MEDIUM | Short part names; move one more non-every-invocation section; size is checked (AC6 F); STOP-and-report only if impossible |
| `/agent-help` bare now answers from the router's Quick Start + Command Reference index instead of the whole reference (the requirement's router goal); a reader wanting a command's full entry gets it on demand | MEDIUM | AC3 states the rule; Validation 2 pastes the first lines; owner reviews the PR |
| The `gh pr merge --squash` surface list changes if `/automate`'s agent-help entry moves | MEDIUM | AC5 keeps the section in the router; AC6 H forbids the phrase in parts; `SURFACE_BASE` leg re-run |
| A headless running-system session started inside the lane is captured by the lane relay hook | MEDIUM | Run from a scratch repo outside the lane with `--plugin-dir`; read-only subcommands only |
| `vendor-coupling-manifest.json` / `prompt-token-budgets.json` / `self-test-weights.tsv` are also edited by sibling lanes of this wave | MEDIUM | Touch only these paths' own keys/rows; wave-branch integration resolves line conflicts |
| Cited headings (`commands/setup.md §…`, evidence tables citing `setup.md:268`) stop resolving | LOW | Every moved heading stays in the router as an index entry (AC1); AC12 lists each citation |
| `test-citation-drift.sh` scans `loomwright/docs/*.md` (git pathspec `*` spans `/`), so moved text lands in its scan set | LOW | Base has no bare citation in these docs (empty `BARE_ALLOWLIST`); AC11 runs it |

## Open decisions
- **OD1 — "the sum of router + parts is no larger than the original file" (requirement AC2).** Under the move-only index convention every moved heading stays in the router as an index entry (so every citation of a heading keeps resolving with no edit — the requirement's own invariant), which adds the entries, markers and read rules on top of the original bytes. This brief reads the AC as "the content is exactly the original" (AC2: assembled text byte-identical) and measures the overhead openly (evidence file, AC7 note). The alternative — no index entries, and every citation of a moved heading re-pointed to its part — meets the literal byte bound but drops the citation-safety net. Default taken: index entries. The PR body states this choice for the owner.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Configuration
- **Workers:** 3
- **Mode:** parallel
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** genuine-parallelism

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-19-split-big-commands.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-10-19T21:38:26Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/626
- **Branch:** feature/split-big-commands
- **Files changed:** 48
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** 4 subtasks (setup / dreaming / agent-help splits in parallel, then integration). Routers 20405 / 18916 / 18626 B; assembled text byte-identical to 626f35f. Phase 4.5: iteration 1 FAIL (2 HIGH: classify-risk blind to command-parts/, test-command-parts red after a legitimate edit; 3 MEDIUM) → fix 78c4ffb; iteration 2 PASS+MEDIUM (W20 blind to the doc-currency FILES+= append) → fix 0d8eff7; iteration 3 PASS (LOW nit dismissed). CI green, rules gate none, ground truth 2/2, rules_audit clean. Owner decisions OD1–OD3 recorded in the evidence file.

## Not verified
- **/dreaming runtime part reads** — no headless /dreaming run; the read rule is checked statically by test-command-parts.sh check G (subtask 2)
- **full base-side ci-local.sh** — only the one red leg (test-automate-trail-modules.sh, pre-existing) was re-run on base (subtask 4)
