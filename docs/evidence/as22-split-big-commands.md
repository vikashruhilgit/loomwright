# Evidence — automate-speed/22: split `/setup`, `/dreaming` and `/agent-help` into routers + parts (move-only)

Base `626f35fab85796da1c0a4da0b2e80480a8249a02`. Every "base" number below was measured in a clean `git worktree add --detach` of that commit in a scratch directory (removed afterwards); every "branch" number on the integrated branch (`feature/split-big-commands-4-dep`, subtasks 1–3 merged, plus this subtask), in the same session.

## Owner decision OD1 — router + parts vs the original bytes

The requirement asked for "router + parts no larger than the original". Under the move-only index convention every moved heading stays in the router as an index entry. That keeps every citation of a heading resolving without an edit, and it adds the entries, markers and read rules on top of the original bytes. The brief reads the AC as "the content is exactly the original": the assembled text is byte-identical (check E below). The routing overhead is measured per command in the part map. The alternative, no index entries with every citation re-pointed to its part, would meet the literal byte bound but drop the citation-safety net. **Default taken: index entries.**

## Owner decision OD2 — `/dreaming`'s `## Purpose` / `## Usage` / `## Parameters` live in a part (AC2 keep list vs the size bound)

AC2's `/dreaming` keep list names `## Purpose`, `## Usage` and `## Parameters` as router sections, and AC2/AC6 F also require the router to be < 20480 bytes. Both cannot hold. Measured on this branch: the router is 18916 B; putting `overview.md` (5450 B, exactly those three sections) back in place of its 447 B split block gives **23919 B** (18916 − 447 + 5450) — 3439 B over the bound, before any other keep-list section returns. So the three sections moved to `docs/command-parts/dreaming/overview.md`, and the router keeps their headings as index entries (citations still resolve). **Why a readiness decline still reads no part:** the decline path is `### Step 0 — readiness` and `### Run report (four mandatory lines)`, both still in the router; the read rule loads `overview.md` only once readiness passes (or `--force`), before Phase 1 GATHER. **Decision for the owner:** accept the deviation on record (the size bound wins; AC2's keep list is read as "every section a declined run needs"), or amend AC2's keep list to drop the three sections. No code change either way.

## Owner decision OD3 — vendor-coupling flat total 2654 → 2664 (AC10 "unchanged" vs AC3's read rules)

AC10 asks for the flat total unchanged; AC3 requires each read rule to name the parts by their `${CLAUDE_PLUGIN_ROOT}/docs/command-parts/<command>/` runtime paths, and each such path is a counted install-root reference. Both cannot hold: the read rules add 9 references (setup 7, dreaming 1, agent-help 1) and the new test's needle adds 1, so the total is 2664 (table under AC10 below). The manifest records the real counts; a flat total would need either a read rule without runtime paths (breaks AC3) or an allowance that lies about what the file carries. **Decision for the owner:** accept the +10 on record, or amend AC10 to "unchanged except for the read rules' runtime paths". No manifest change.

## Part map per command (part → headings it holds → bytes), router bytes vs base

### /setup

Router `loomwright/commands/setup.md`: **20405** bytes (base 93858). Parts total 80410 bytes; router + parts = 100815 bytes = base + 6957 bytes of routing overhead (index entries, markers, read rule).

| Part | Headings it holds (top level first, then the count of sub-headings) | Bytes |
|---|---|---|
| `dashboard.md` | No-arg flow — status dashboard (+ 0 sub-heading(s)) | 12822 |
| `obs.md` | Module: observability (+ 9 sub-heading(s)) | 13222 |
| `memory.md` | Module: memory (+ 10 sub-heading(s)) | 30579 |
| `rules.md` | Module: rules (+ 6 sub-heading(s)) | 9527 |
| `statusline.md` | Module: statusline (+ 7 sub-heading(s)) | 7467 |
| `other.md` | Module: telemetry; Module: notifications; Module: webhook; Module: beads; Module: mysql-mcp (+ 4 sub-heading(s)) | 6059 |
| `ex.md` | Examples (+ 0 sub-heading(s)) | 734 |

### /dreaming

Router `loomwright/commands/dreaming.md`: **18916** bytes (base 137515). Parts total 126350 bytes; router + parts = 145266 bytes = base + 7751 bytes of routing overhead (index entries, markers, read rule).

| Part | Headings it holds (top level first, then the count of sub-headings) | Bytes |
|---|---|---|
| `overview.md` | Purpose; Usage; Parameters (+ 0 sub-heading(s)) | 5450 |
| `record.md` | Final step — record this run (mandatory, even when nothing was accepted) (+ 0 sub-heading(s)) | 1994 |
| `workflow.md` | What This Does / Workflow (+ 1 sub-heading(s)) | 22037 |
| `reflection-prompt.md` | Reflection-Mode Task Prompt (+ 0 sub-heading(s)) | 5761 |
| `report.md` | Reflection Report Sections (+ 9 sub-heading(s)) | 14713 |
| `rules-pr.md` | Harvested `.agent/rules/` proposals (PR delivery queue) (+ 0 sub-heading(s)) | 24635 |
| `memory-pr.md` | Memory PR (delivery queue) (+ 0 sub-heading(s)) | 17489 |
| `report-notes.md` | Harness-memory pointer (on LESSONS Accept); Empty-state suppression; APPLY deferral (v14.5.0 scope) (+ 0 sub-heading(s)) | 3645 |
| `approval.md` | Approval Option Contract (+ 4 sub-heading(s)) | 9853 |
| `read-only.md` | Read-Only Contract (+ 1 sub-heading(s)) | 10364 |
| `reference.md` | Example Output; Workflow Positioning; When to Use; When NOT to Use; See Also (+ 0 sub-heading(s)) | 10409 |

### /agent-help

Router `loomwright/commands/agent-help.md`: **18626** bytes (base 84712). Parts total 76862 bytes; router + parts = 95488 bytes = base + 10776 bytes of routing overhead (index entries, markers, read rule).

| Part | Headings it holds (top level first, then the count of sub-headings) | Bytes |
|---|---|---|
| `readiness.md` | 🚀 /launch-pad — Supervisor Readiness; 🤖 /supervisor — Parallel Orchestrator (v4) (+ 0 sub-heading(s)) | 8347 |
| `build.md` | 0️⃣ /product-owner — Define Requirements; 1️⃣ /orchestrator — Plan Your Work; 2️⃣ /code-reviewer — Review Code Changes; 3️⃣ /commit — Create Commits; 4️⃣ /red-team-reviewer — Attack Your Work (Adversarial) (+ 0 sub-heading(s)) | 7468 |
| `qa.md` | 5️⃣ /qa-strategist — Risk-Based QA Strategy; 6️⃣ /qa-executor — Automated QA Testing; 🔎 /verify — Walk a ticket through the running app (+ 0 sub-heading(s)) | 9818 |
| `knowledge.md` | 💤 /dreaming — Reflect on Past Sessions (Read-Only Until You Accept); 🔭 /capability-check — Scan for New Platform Capabilities (Read-Only); 📊 /insights — Local Insights Dashboard (Read-Only, Obsidian-friendly); 🔮 /obsidian — Local Obsidian Vault Projection (Read-Only, Linked); 🤝 /handoff — Catch-Up / Hand-Off Digest (Read-Only); 🌱 /propose — Candidate Work Items from the Churn Ledger, a /verify Run, and the Domain (Read-Only, Propose-Only) (+ 0 sub-heading(s)) | 17847 |
| `ops.md` | 📡 /telemetry — Opt-In GitHub Issues Telemetry; 📜 /rules — House Rules Substrate (Committed `.agent/rules/`); 🩺 /pr-postmortem — PR Review-Churn Root-Cause Analysis (Read-Only); 🔁 /autonomous — Continuous Autonomous Loop (v14, stacked PRs) (+ 0 sub-heading(s)) | 9015 |
| `more.md` | 🧩 /setup — Optional-Capability Dashboard & Guided Configuration; 🩺 /review-pr — Standalone PR Review-and-Heal; QA Workflow Diagram (+ 0 sub-heading(s)) | 5203 |
| `guide.md` | Daily Workflow Example; Common Scenarios; Key Concepts; Tips & Tricks; Files & Directories; Getting Help; Keyboard Shortcuts; Summary (+ 33 sub-heading(s)) | 19164 |

## Read rule — what each invocation reads

- **/setup** (index-only block in `## Step 0`): every `## Parameters` module maps to exactly one part (`observability` → `obs.md`; `memory`, `rules`, `statusline` → their own part; `telemetry`, `notifications`, `webhook`, `beads`, `mysql-mcp` → `other.md`). Bare `/setup` reads `dashboard.md` and then each selected module's part. An unrecognised module reads nothing. `ex.md` is read only when examples are asked for. Check G of `test-command-parts.sh` asserts the module → one-part map.
- **/dreaming** (index-only block after `### Step 0 — readiness`): a readiness decline reads **no** part. Passing readiness reads `overview.md` + `workflow.md` + `read-only.md`. Then `reflection-prompt.md` (Phase 2), `report.md` + `report-notes.md` + `reference.md` (Phase 3), `approval.md` (Phase 4), and `record.md` (the mandatory `curation-status.sh record dreaming` final step).
  - **Recorded deviation from AC3's wording:** `rules-pr.md` is read once GATHER's harvest prints a rule batch, before that queue is shown. AC3 said "only when a harvested proposal is accepted". `memory-pr.md` is read before Phase 4's first write, because its Step 0 dirt snapshot must precede that write. AC3 said "only when memory writes were recorded". Both triggers are **earlier** than AC3's wording. The reason is that each part also holds text needed before the accept/record moment (the queue's offer text, the pre-write snapshot), so reading at AC3's moment would be too late. `report-notes.md` and `reference.md` are read at Phase 3 with `report.md`. This subtask does not edit the routers, so this is recorded rather than changed.
- **/agent-help** (index-only block after `## What This Does`): a bare invocation answers from the router (`## Quick Start` + the `## Command Reference` index, whose entries name every command). A command's part is read only for detail on that command. `/automate` stays whole in the router (AC5). The rule names the parts directory once and then bare file names, the form `commands/automate.md` uses. Check G accepts that form.

## Validation 2 — Running system

Run from a scratch `git init` repo **outside** this worktree and the lane checkout (the lane's `.claude/settings.local.json` carries the lane relay hook), against this branch's plugin. Each run was bounded: started in the background, polled, and killed at a 420 s deadline (macOS has no `timeout`). None hit the deadline. `apply` / `remove` / `migrate` were never run. Claude Code 2.1.300; the stream's `init` event lists the plugin as `loomwright loomwright@inline 17.10.0`, i.e. the `--plugin-dir` copy.

```
cd <scratch>/rs && git init -q .
claude -p "/loomwright:setup memory status" --plugin-dir <worktree>/loomwright --output-format stream-json --verbose \
  --allowedTools Read "Bash(bash:*)" "Bash(jq:*)" "Bash(git:*)" --disallowedTools Write Edit NotebookEdit --add-dir <worktree>/loomwright
claude -p "/loomwright:setup"      --plugin-dir <worktree>/loomwright --output-format stream-json --verbose \
  --allowedTools Read --disallowedTools Write Edit NotebookEdit Bash --add-dir <worktree>/loomwright
claude -p "/loomwright:agent-help" --plugin-dir <worktree>/loomwright --output-format stream-json --verbose \
  --allowedTools Read --disallowedTools Write Edit NotebookEdit Bash --add-dir <worktree>/loomwright
# Read paths, per stream:
jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="Read") | .input.file_path' <stream>.jsonl
```

### AC4 — `/setup memory status` (rc=0, 36 s, 4 turns)

Every `Read` `file_path` in the stream (`<plugin>` = `<worktree>/loomwright`):

```
<plugin>/skills/setup/SKILL.md
<plugin>/docs/command-parts/setup/memory.md
```

The only `docs/command-parts/` file any Read names is `docs/command-parts/setup/memory.md`. The router itself is injected as the command body. `skills/setup/SKILL.md` is the Step 0 authority, not a part. The one Bash call was the read-only `setup-memory.sh check`. Output:

```
I ran the read-only `check` against `…/scratchpad/s4/rs` and changed nothing. As the `status` subcommand requires, there is no offer step.

**Memory readiness: `partial`**: some paths that should stay ignored are committable right now.

| Item | State |
|---|---|
| `.gitignore` | **absent** |
| Managed block | absent |
| Intended stores (agent-memory, `.supervisor/memory`, requirements, `jobs/done` and `jobs/failed`, automate `*.md`, the findings ledger `results.jsonl`) | all committable |
| Paths that should stay ignored | **7 of 8 are committable**: `.claude/worktrees/`, `.supervisor/logs/`, `jobs/pending/`, `jobs/in-progress/`, `*.config-backup.json`, the nested `.supervisor/` tree under requirements, and `.rules-nudge-shown` |
| `.claude/settings.local.json` | ignored. No repo `.gitignore` exists, so a global or other exclude rule must be catching it. I didn't trace which one. |
| Tracked today | 0 files in each of the three stores |
| Allowlist | **empty**. It's unset because the repo has no git remote to default from. |

**What this means:**
- **Nothing is ignored here.** Everything shows as committable because the repo has no `.gitignore`, not because of a broken rule. A `git add -A` would sweep in worktrees, logs and in-flight briefs.
- **Apply wouldn't work yet.** `apply` aborts on an absent `.gitignore`. You'd need to create one first.
- **The findings ledger would stay ignored.** An empty allowlist means the gate lets nothing through. It stays that way until you add a remote or set `.setup_memory.repo_allowlist` in `.supervisor/config.json` by hand.

The full "what becomes version-controlled" disclosure is printed at the end of the check output. It's shown in full when you run `/setup memory apply`.

Setup: memory status: readiness `partial` (no `.gitignore`, empty allowlist with no remote); read-only, nothing written.
```

### Bare `/setup` (rc=0, 73 s, 9 turns; Bash withheld, so the dashboard probes could not run)

```
<plugin>/skills/setup/SKILL.md
<plugin>/docs/command-parts/setup/dashboard.md
~/.claude/settings.json
<scratch-repo>/.git/config
```

The only part read is `dashboard.md`; no module was selected, so no module part was read. The two other Reads are the dashboard's own file probes. First line of the output (the rest reports this machine's user-scope configuration and is omitted from a committed file on purpose):

```
I couldn't produce the real `/setup` dashboard. Neither this session nor the helper agent I started has a shell. The setup protocol requires every cell to come from running its check command, and none of those commands ran. Below is what I could read directly from files instead; nothing was written or changed.
```

### Bare `/agent-help` (rc=0, 13 s, 1 turn)

**Zero tool calls**: no Read at all, so no part. It answered from the router. First lines:

```
# Loomwright: available agent commands

Loomwright has **14 agent roles**: 9 you can run directly and 5 used internally. Most people start with one of these:

| I want to… | Run | Does NOT do |
|---|---|---|
| Start a new task or goal | `/launch-pad` then `/supervisor` (or `/autonomous`) | Never merges |
| Work on one goal over several rounds, as stacked PRs | `/autonomous "<req>"` | Never merges (a human merges the stack from the bottom up) |
| Work through a list of separate goals (a folder or backlog) | `/automate` | Never merges unless you pass `--auto-merge` (off by default) |
| Review an existing PR and push fixes to it | `/review-pr <pr-url>` | Never merges (pushes fixes, the PR stays open) |
| Review my changes without fixing anything | `/code-reviewer` | Read-only: no fixes, no commits, never merges |

```

## AC5 — the `gh pr merge --squash` invariant grep

`grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not " | sed -E 's/^([^:]+):[0-9]+:/\1:/' | sort` produces **byte-identical output on base and branch** (`cmp` clean, 15 lines). The `--auto-merge` bullet stays in `commands/agent-help.md`'s `### 🤖 /automate` section in the router. Branch output:

```
loomwright/commands/agent-help.md:- `--auto-merge` — opt-in (default OFF) trusted auto-merge behind the fail-closed trusted-merge gate (conditions enumerated in `skills/automate-loop/SKILL.md` §10); the **only** place in the plugin that executes `gh pr merge --squash`. Condition 6 re-classifies the PR head with `scripts/classify-risk.sh` and parks any high-risk or unclassifiable diff — nothing overrides it
loomwright/docs/loop-inventory/automate-loop.md:| AL-026 | skills/automate-loop/helpers.md | q: The fail-CLOSED trusted auto-merge gate (conditions enumerated in §10) | `--auto-merge` at GATE | re-derive conditions from live reads; refuse a ctx carrying a gate-owned key (`PARK: ctx_carries_gate_owned_key`); the only `gh pr merge --squash` | deterministic | script:automate-helpers.sh gate-eval | script:automate-helpers.sh gate-eval | test-automate-helpers.sh |
loomwright/docs/loop-inventory/automate-loop.md:| AL-124 | skills/automate-loop/SKILL.md | q: **Letting the engine merge anywhere but the §10 gate.** | any merge | `gh pr merge --squash` only in the `--auto-merge` gate | rule | global | script:automate-helpers.sh gate-eval | test-automate-helpers.sh |
loomwright/docs/loop-inventory/automate-loop.md:| AL-133 | skills/automate-loop/SKILL.md | q: `--auto-merge` executes `gh pr merge --squash` ONLY when EVERY trusted-gate condition | any blocker at the gate | park + notify (fail CLOSED) | rule | global | script:automate-helpers.sh gate-eval | test-automate-helpers.sh |
loomwright/docs/loop-inventory/automate-loop.md:| AL-533 | commands/automate.md | q: **Opt-in, default OFF.** At the GATE, executes `gh pr merge --squash` ONLY when the trusted-merge gate holds | `--auto-merge` | merge only when the self-resolving gate holds; gate-owned ctx key refused; condition 6 merges only on JSON `false` | deterministic | global | script:automate-helpers.sh gate-eval | test-automate-helpers.sh |
loomwright/scripts/automate-helpers.sh:  # ALL conditions hold — the ONLY sanctioned `gh pr merge --squash` in the plugin (§11).
loomwright/scripts/automate-helpers.sh:# `gh pr merge --squash --match-head-commit <live head> <url>` ONLY when EVERY
loomwright/scripts/fixtures/automate-golden/drain-superseded-by-merge/tree/dot-supervisor/requirements/automate-followups/11-post-park-lifecycle.md:      `gh pr merge --squash` positive grep (CLAUDE.md §Failure-Mode Invariants) still resolves to exactly the same
loomwright/scripts/result_block_parser.py:# convention CLAUDE.md already uses for the `gh pr merge --squash` invariant
loomwright/scripts/test-automate-helpers.sh:  ok "gate all-pass: MERGE fires 'gh pr merge --squash --match-head-commit <checked head> <url>' exactly once"
loomwright/scripts/test-automate-helpers.sh:#      `gh pr merge --squash --match-head-commit <checked head>` exactly once; AND a head
loomwright/scripts/test-automate-helpers.sh:# --- All-pass MERGE fires `gh pr merge --squash` EXACTLY once, and the stub
loomwright/skills/automate-loop/modes-and-merge-gate.md:- **`--auto-merge` mode (opt-in, default OFF, gated):** at the GATE, `gh pr merge --squash` fires **only** when the trusted gate (§10) holds; otherwise fail **CLOSED** → park + notify — that `PARK: <reason>` park is `awaiting_merge` with the PR open, so it takes safe mode's park-first order: `dismissed-drafts`, the park state, the merge watcher, the notify and `run-lock.sh release` first, then `park-ask-gate` and the §6 "Dismissed-findings decision step (before the park)" decisions (after a `MERGE`, only its `dismissed-drafts` runs and the drafts wait for the next interactive PICK).
loomwright/skills/automate-loop/modes-and-merge-gate.md:On all seven holding: `gh pr merge --squash --match-head-commit <live head> <url>` — the SHA pin binds the merge to the exact head conditions 2, 6 and 7 were evaluated against, so a push landing between those reads and the merge is refused by GitHub and parks `merge_command_failed` instead of merging unchecked code. Then SYNC (`closeout … --no-trail`, whose sync fast-forwards `main`) so the next item branches fresh (§6 step 5).
loomwright/skills/automate-loop/per-item-loop.md:  - **Honest limits.** The gate covers this run's trail PR only: another merge to the base while an item's PR is open (a hand-merged PR, another run's trail PR) still leaves it `BEHIND` under `strict` — the owner updates the branch (GitHub's "Update branch" button, or a hand merge of the base), and under `--auto-merge` the gate's `gh pr merge --squash` fails and parks `merge_command_failed`. Under `--auto-merge` a skip/abandon check-off opens a trail PR mid-run, so an unattended run parks `trail_pr_open` at the next PICK until the owner merges it.
```

`grep -rn "gh pr merge --squash" loomwright/docs/command-parts/ | grep -viE "no |never |not "` prints **nothing**. The one raw hit, `docs/command-parts/dreaming/rules-pr.md`, is the negated "it never runs `gh pr merge --squash`" line, correctly filtered, as on base. `test-command-parts.sh` builds its own needle from two pieces, so the new test is not itself a new hit. `test-automate-next-step.sh`'s `SURFACE_BASE` list is unchanged (diffed against base); that test reports PASS 143 / FAIL 0 on both base and branch.

## Gates and tests — before / after (`<passed>/<total>` where the tool prints it)

| Gate / test | Base | Branch | Note |
|---|---|---|---|
| `loomwright/scripts/test-command-parts.sh` (AC6, new) | absent | 38/38 | A–H + 13 mutation controls (review iteration 1 added M-I: one part edited after the split ⇒ exit 0, one SKIP for that command) |
| `scripts/check-token-budget.sh` (AC7) | OK, exit 0 | OK, exit 0 | `.commands` rows now router + parts |
| `scripts/test-check-token-budget.sh` (AC7) | 98/98 | 111/111 | +13: parts counted / nested part / router alone / empty parts dir / orphaned parts dir / symlink under parts dir / 2 mutation controls |
| `scripts/check-doc-currency.sh` (AC8, AC11) | OK, 9 surfaces | OK, 16 surfaces | + the 7 agent-help parts; agents/commands/skills = 14/23/42 on both |
| `scripts/test-check-doc-currency.sh` (AC8) | 6/6 | 8/8 | +2: stale `Loomwright vX.Y.Z` in an agent-help part ⇒ DRIFT naming it; removed ⇒ pass |
| `loomwright/scripts/test-curation-status.sh` (AC9, legs (k)/(o)) | 333/333 | 333/333 | reads the assembled text; labels identical but for the run's own timestamps |
| `loomwright/scripts/test-rules-docs.sh` (AC9, (h5)/(h6)) | 46/46 | 46/46 | labels identical |
| `loomwright/scripts/test-setup-memory.sh` (AC9, part 05 (fn-4)/(fn-1)) | 574/574 | 574/574 | labels identical but for the run's own random sleep values |
| `scripts/check-vendor-coupling.sh` (AC10) | OK, 2654 refs | OK, 2664 refs | see AC10 below — the read rules ADD references |
| `scripts/test-check-vendor-coupling.sh` | 338/338 | 338/338 | |
| `scripts/check-command-sync.sh` (AC11) | OK | OK | |
| `scripts/check-skills-index-sync.sh` (AC11) | OK | OK | |
| `loomwright/scripts/test-citation-drift.sh` (AC11) | 26/26 | 26/26 | |
| `loomwright/scripts/test-automate-loop-split.sh` (AC11) | 40/40 | 40/40 | |
| `loomwright/scripts/test-build-capabilities.sh` (AC11) | 110/110 | 110/110 | |
| `loomwright/scripts/test-automate-next-step.sh` (AC5) | 143/143 | 143/143 | `SURFACE_BASE` unchanged |
| `scripts/check-locale-prefix.sh`, `scripts/check-test-hermetic.sh` | OK | OK | run with the new test staged |
| `bash scripts/check-version-bump.sh` (AC13) | — | OK: not bumped, 1 fragment pending | lane writes a fragment only; the wave's release lane bumps |

`loomwright/capabilities.json` and `loomwright/hooks/hooks.json` are byte-unchanged (`git diff --quiet 626f35f --` on both).

### Validation 1 — `bash scripts/ci-local.sh`

Integrated branch (subtasks 1–4 merged), run by the Execute Manager in this session: **175/176 self-tests pass**. The one red leg is `loomwright/scripts/test-automate-trail-modules.sh` (23/24); the same test run alone on the base worktree at `626f35f` fails identically (23/24), so it is pre-existing and not caused by this change. A full base-side `ci-local.sh` run was not made — only that leg was re-run on base.

## AC7 — token budget

The `.commands[<stem>]` weight is now `<commands dir>/<stem>.md` + every `*.md` under `loomwright/docs/command-parts/<stem>/`, recursive. Override: `TOKEN_BUDGET_COMMAND_PARTS_DIR`. The walker is the same `skill_weight`, which fails CLOSED on a symlink or an unreadable subtree. An orphaned parts dir is an ERROR.

| Row | Base weight | Branch weight (router + parts) | Budget | Raised? |
|---|---|---|---|---|
| `setup` | 23464 | 25199 | 25811 | no (612 headroom) |
| `dreaming` | 34378 | 36313 | 37813 | no (1500 headroom) |
| `agent-help` | 21178 | 23868 | 23236 → **25926** | yes — breached by 632; raised by exactly the measured overhead 23868 − 21178 = **2690** proxy tokens (≤ overhead + ~10%), restoring the base headroom of 2058; `measured` 21123 → 23868; note `as22: router + parts = base + index/read-rule overhead (2690 proxy tokens)`; the ARCHITECTURE_CONTRACTS mirror row moved in the same edit |

## AC10 — vendor coupling (a recorded departure from the AC's "flat total unchanged" — owner decision OD3 above)

Measured with `bash scripts/check-vendor-coupling.sh --print-allowances` after `git add`. The allowances moved to the router and part paths that now carry the references, and each part has the reason `moved by automate-speed/22 split — no reference added`. **The flat total is not unchanged. It cannot be, because the read rules genuinely add install-root references.** Writing "no reference added" for the routers, or fudging a count, would have been false.

| Path | Base allowance (base measured) | Branch allowance (measured) | Why |
|---|---|---|---|
| `commands/setup.md` | 118 (105) | 31 | 81 moved to the parts, 24 stay; the read rule **adds 7** (one runtime path per part); the unused slack of 13 is dropped |
| `commands/dreaming.md` | 57 (57) | 4 | 54 moved, 3 stay; the read rule **adds 1** (the parts dir, named once) |
| `commands/agent-help.md` | 11 (11) | 1 | all 11 moved; the read rule **adds 1** |
| `docs/command-parts/<command>/*.md` (23 of the 25 parts; `agent-help/readiness.md` and `agent-help/build.md` carry none) | — | 146 (setup 81, dreaming 54, agent-help 11) | moved verbatim, no reference added |
| `scripts/test-command-parts.sh` (new) | — | 1 | check G's runtime-dir needle (one literal) |

Flat reference total **2654 → 2664** (+9 from the three read rules, +1 from the new test). Allowance sum 2702 → 2699. `raise_check`: 24 new or raised paths, all with an added reason. No other manifest key changed.

## AC12 — committed citations of a moved heading

`git grep -nE '(dreaming|setup|agent-help)\.md' -- '*.md'` (CHANGELOG.md excluded) gives 87 lines. Most name the file as a whole, such as directory trees, "see `commands/setup.md`", or path lists in golden fixtures, and resolve to the router as before. The ones that name a section or a line:

| Citation | Target | Judgement |
|---|---|---|
| `AGENT_GUIDELINES.md` — `commands/dreaming.md` §"Pending agent-memory proposals (promotion queue)" | heading in `report.md` | resolves: the router keeps `### Pending agent-memory proposals (promotion queue)` as an index entry |
| `ARCHITECTURE_CONTRACTS.md` — `commands/setup.md` notifications section | `## Module: notifications` | resolves through the router's entry (part `other.md`) |
| `docs/command-parts/dreaming/approval.md` — `commands/setup.md`, the observability / memory / rules module questions | `## Module: …` / `### Offer` | resolves through the router's entries |
| `docs/command-parts/dreaming/rules-pr.md` — `commands/setup.md`, the rules-module Offer | `## Module: rules` → `### Offer` | resolves through the entries |
| `docs/command-parts/agent-help/knowledge.md` — `dreaming.md` §4 | `### 4. Proposed CLAUDE.md Updates` | resolves: the router holds that entry (`report.md`) |
| `commands/capability-check.md`, `commands/insights.md`, `commands/rules.md` — `commands/setup.md`'s own note | `## Parameters` notes | in the router itself (kept section) |
| `docs/command-parts/agent-help/{knowledge,more}.md` — "Learn More: see `loomwright/commands/<cmd>.md`" | whole doc | resolves to the router, whose entries lead to every part |
| `docs/POINTER_AUDIT.md` — `commands/dreaming.md` INPUTS block, ~L102–110 | the INPUTS block of `## Reflection-Mode Task Prompt` | resolves through that entry (part `reflection-prompt.md`). The `~L102–110` hint was already stale at base, where INPUTS sat at line 202 |
| `docs/evidence/as20-split-memory-and-meta-scripts.md` — `loomwright/commands/setup.md:268` / `:270` | the `setup-memory.sh` engine paragraph and the migrate exception | historical evidence frozen at as20's commit. The two lines are now verbatim in `docs/command-parts/setup/memory.md` (lines 9 and 11) under `## Module: memory`, reached through the router's entry. Not edited: an evidence file records its own commit |
| `loomwright/scripts/fixtures/corpus-briefs/done/2026-07-23-curation-anti-rot.md` — `commands/dreaming.md:86` | a done-brief fixture | frozen corpus input, not a live citation |
| `.claude/agent-memory/…code-reviewer/*.md` — `agent-help.md ~228`, `~1045` | approximate line hints | the text sits in parts now (`readiness.md`, `guide.md`). The hints were approximate before the split; agent memory is not edited by this subtask |

## Honest limits and follow-ups

- Fixed in review iteration 1: `loomwright/scripts/test-meta-sync.d/03-mutants-scrub-allowlist.sh` case 54's home-path guard now scans `docs/command-parts/` alongside `agents/`, `commands/` and `skills/`, with a fixture case proving it fires on a part. The same iteration added `command-parts/` to `classify-risk.sh`'s `GENERIC_DIRS`, so a parts-only edit to a split command classifies `high_risk: true` like the same edit to its router (test case B5b).
- Check D (router heading sequence == assembled) cannot see a deleted **kept** heading, because both sides lose it. The move-only proof E sees it, and mutation M-D2 shows E catching it. The brief's pin for D ("delete one kept heading") is therefore proved by E, and D's own mutant deletes a moved heading from a part.
- The running-system runs withheld Bash from bare `/setup` and `/agent-help` on purpose (read-only proof). The bare dashboard therefore could not run its probes, and its output says so.
