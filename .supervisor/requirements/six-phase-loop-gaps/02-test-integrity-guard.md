# 02 — Test-integrity guard (blocking `PreToolUse` hook + worker rule of explanation)


> **Cross-queue amendment (2026-09-22).** Sequenced by `.supervisor/requirements/_BACKLOG-hardening-sequence-2026-09-22.md` AFTER `red-team-hardening/01` (which rewrites the `dispatch-pr-review.sh` launch line this item pre-arms — re-read that line, do not apply the §"Dispatcher pre-arm" edit from memory) and AFTER `six-phase-loop-gaps/01`; `harness-port/01` follows and adds its own worker prose. §7 budget: `5876/5905 — 29 headroom` is the `05823bf` figure; re-measure and raise from the LIVE number with one raise-log row naming this item.

> **Rev 4 (2026-09-21, after third red-team).** Rev 3's lifecycle had two disarm paths left, both verified:
> (a) `arm` overwrote a marker carrying a different `session_id`, and the one Bash shape the guard allowed
> (`guard-arm.sh arm <word>`) reads that id from the Bash env — `CLAUDE_CODE_SESSION_ID=dead bash …/guard-arm.sh
> arm x` was a one-command disarm; (b) one marker file per checkout meant a second session on the same
> checkout (recurring here — memory `concurrent-heal-loop-sweeps-uncommitted-edits`) silently disarmed the
> first via the very backstop that armed it. Rev 4 replaces the single slot with **one marker file per
> session** — no overwrite rule exists, so neither path exists. Also from that audit: the detached runner had
> no hook backstop (it is `claude --agent`, never a `Task`) — the dispatcher now pre-arms with
> `claude --session-id <uuid>` (flag verified in `claude --help`); the guard's own source and `hooks.json` were
> unprotected while the "mentions `guard-arm.sh`" rule denied *reading* them; `settings.json` in any
> directory caught `.vscode/settings.json`; the backstop's suffix match armed on any `*worker` agent.
> **Rev 3:** fail-loud arm, hook backstop, no tool-call disarm, presence-scoped reviewer clause,
> `settings.json` + `git clean -x` patterns, same-simple-command rule, probes P1–P3.
> **Rev 2:** marker replaces the `in-progress/` gate. **Rev 1 (retracted):** `in-progress/` gate +
> config.json opt-out named in the deny line.

## Problem
Nothing in the plugin stops an agent from editing the gate it is being measured by. `hooks.json`
`PreToolUse` has exactly one matcher — `AskUserQuestion`, a notifier. The only guard against a worker
gaming its own verification is the destructive-command tripwire in `scripts/result_block_parser.py`
(`_DESTRUCTIVE_PATTERNS`: `rm -rf`, `git push`, `git reset --hard`, `DROP`, `TRUNCATE`) — post-hoc at
`SubagentStop`, and it says nothing about `git commit --no-verify`, `HUSKY=0`, `git clean -x`, or a one-line
edit to `jest.config.ts` that excludes the failing spec. Agents optimise the evidence they can see; a "fix"
that lands without a diagnosis most often edited the assertion, not the code. Our own cases are the same
shape: memory `shared-fixture-default-disarms-its-own-assertion` and PR #101's non-integer-budget fail-open
both passed green because the check itself was changed.

## Goal
While a Loomwright-spawned agent is working in a session — Supervisor run, detached or inline review drain,
`/automate` item — it cannot (a) bypass commit/push hooks, (b) edit the test-runner, lint, git-hook, or Claude
settings configuration, (c) remove or neuter the guard (its marker, its two scripts, `hooks.json`), or (d) fix
a failing test without recording a diagnosis. A session that never ran a Loomwright entry point is inert by
construction; a session that did stays armed until it ends (an inline run is the human's own session — see
§Non-goals for the honest statement). Arming is **fail-loud** (an unarmed run says so), one marker per
session, and the off-switch is not reachable from a tool call and not named to the model. This is the
plugin's first fail-CLOSED `type: command` hook and is documented as such everywhere the `|| true` convention
is stated. It is a tripwire, not a sandbox (S5) — the honest-limits list is part of the deliverable.

## Probes — FIRST tasks of this item, each recorded as a fixture beside `scripts/progress-event-fixtures/`
- **P1 — session-id equality under `claude -p`.** Run `claude -p` with a throwaway `PreToolUse[Bash]` hook
  that appends the payload's `session_id` to a log, and a prompt that runs `printf '%s' "$CLAUDE_CODE_SESSION_ID"`.
  Assert equal. Run it a second time with `--session-id <uuid>` and assert both equal the uuid. (Verified for
  this desktop session only: env var = transcript basename = payload `session_id`; `notify-desktop.sh`
  already uses the env var as a fallback.) If the env var differs under `-p`, the prompt-step `arm` source
  must change before anything else is built; the dispatcher path (§1, `--session-id`) does not depend on it.
- **P2 — `agent_type` on a subagent's `PreToolUse`.** Same throwaway hook, prompt spawns one `Task`
  (`subagent_type: general-purpose`) that runs a Bash call. Assert the inner call's payload carries
  `agent_type` + `agent_id` and the outer does not. Memory records this for `PostToolUse` (2026-09-05);
  `PreToolUse` is the same family but unverified. The repo's `spawn-probe-2026-09-02/pretooluse-task-*.json`
  are main-thread `Agent` calls and prove nothing about subagents — say so in the fixture README.
  **Fallback if NO:** the two deny variants in §2 collapse to the subagent wording; nothing else changes.
- **P3 — does `settings.json` `env` reach hook processes?** Set a canary key in `~/.claude/settings.json`
  `env`, restart, log `env` from a throwaway hook. If NO: the opt-out is a shell-launch env var only, and
  §3 + HOOKS.md say so; if YES: `/.claude/settings*.json` protection in §2 is load-bearing, not belt-and-braces.

## Scope
1. **Arm markers — `.supervisor/guard/<session_id>.json`, ONE FILE PER SESSION** `{ "session_id",
   "armed_at", "by" }`. `scripts/guard-arm.sh arm <by>` writes ONLY its own file, named from
   `CLAUDE_CODE_SESSION_ID`; **empty/unset ⇒ exit 3, write nothing, one stderr line `guard_arm_failed: no
   session id`** — never a placeholder. Idempotent: own file already present ⇒ exit 0 no-op. **There is no
   overwrite rule and no cross-session write of any kind:** an `arm` run with a forged env id
   (`CLAUDE_CODE_SESSION_ID=dead bash …/guard-arm.sh arm x`) creates `dead.json`, which no payload ever
   matches — harmless — and cannot touch the live session's file. Two sessions on one checkout each hold
   their own file and never see each other's. Atomic same-dir temp + `mv`; creates `.supervisor/guard/` if
   absent. `arm` also prunes marker files whose `armed_at` is older than 7 days (dead sessions; the only
   deletion `arm` performs, never the caller's own or any newer file).
   **Arm points (two prompt steps + one hook backstop + one dispatcher pre-arm):**
   - Supervisor Phase 0 INIT (`skills/supervisor-config/SKILL.md`, after config resolution) and
     `review-heal/SKILL.md` **loop entry** (covers the inline `/review-pr` and the `/automate` owned drain —
     the latter is also already covered by the Supervisor's marker from the same session, since nothing
     disarms between RUN and DRAIN). Each records `record_decision(… "guard_armed: {ok | failed: <reason>}")`;
     on `failed` the run **proceeds, visibly unguarded** — logged into `## Decisions Log` and surfaced in the
     completion tail's outcome line as `guard: unarmed`. Creating `.supervisor/guard/` in a worktree is the
     runner's own action — distinct from the observer rule "gate on existing `.supervisor/`, never create it";
     state that in the script header.
   - **Hook backstop — `PreToolUse` matcher `Agent|Task`** (the payload's `tool_name` is `Agent` in current
     Claude Code — `spawn-probe-2026-09-02/pretooluse-task-1.json`; `Task` kept for older builds):
     `guard-arm.sh arm-from-payload` reads stdin and arms with the payload's `session_id` when
     `tool_input.subagent_type` matches `:(worker|execute-manager|supervisor-runner|review-pr-runner)$` —
     **namespace colon required** (the plugin prefix varies by install, memory `agent-type-doubled-prefix`,
     but it is always present; a bare suffix match would arm a human's session on any `*worker` agent from
     another plugin or `~/.claude/agents/`). Check `subagent_type` BEFORE any file I/O — this leaf forks on
     every spawn in every project. It is an emitter (`|| true`); a prompt step skipped is the plugin's own
     documented failure mode (`self-heal-advisory/SKILL.md` "Hook backstop (v14.34.0 — defense-in-depth)").
   - **Dispatcher pre-arm — `scripts/dispatch-pr-review.sh`:** the detached runner is launched with
     `claude --agent`, never spawned by `Task`, and its fixers are `general-purpose` — so the backstop cannot
     fire in the detached drain. The dispatcher therefore generates a uuid, writes
     `<worktree>/.supervisor/guard/<uuid>.json` (`guard-arm.sh arm dispatcher --session-id <uuid>` — the ONE
     caller allowed to pass the id explicitly, because it is a plugin script that owns the launch, not a
     prompt step) **before** the launch, and passes `--session-id <uuid>` to `claude -p`. Deterministic,
     script-owned, no LLM step. The runner's review-heal entry `arm` then finds its own file present ⇒ no-op.
   - **No `/automate` arm or disarm.** The inner `/autonomous` → Supervisor arms; the owned drain arms at
     review-heal entry; nothing disarms between them.
   **Disarm — exactly ONE point, never a tool call:** `SessionEnd` leaf `guard-arm.sh disarm-session`
   (`|| true`), removing only the file named by the payload's `session_id`. No `disarm` reachable from
   Bash. Crash/kill: the file outlives the session with a dead id ⇒ matches no payload ⇒ pruned by a later
   `arm`. `worktree-salvage.sh` must exclude `.supervisor/guard/` from the `untracked/` copy (a salvaged
   marker in the primary checkout is harmless but confusing).
2. **`scripts/guard-test-integrity.sh`** — one script, two matchers, reads the hook payload from stdin.
   **Evaluation order (cheap first, no `jq` on the inert path):** (i) `.supervisor/guard/` absent or empty →
   `exit 0`; (ii) `LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS=1` in the hook's process env → `exit 0`; (iii) `jq`
   missing / payload unparseable / `tool_input` absent / `session_id` absent → **deny**
   `guard_unavailable: <reason>` (reachable only with at least one marker present); (iv)
   `.supervisor/guard/<payload session_id>.json` absent → `exit 0` (a foreign or dead marker is inert for
   this session); (v) evaluate patterns.
   - **Bash matcher** (`tool_input.command`). Split the string into simple commands on `;`, `&&`, `||`, `|`,
     newline; evaluate each simple command independently — a write verb and a protected basename must be in
     the SAME simple command (`git diff jest.config.ts > /tmp/d.patch` is a read; `cat > jest.config.js` is a
     write). One bash array, one comment per line, the single source of truth (HOOKS.md points at it):
     `--no-ver[a-z]*` on any `git` simple command (git accepts unambiguous long-option prefixes — probed);
     `git commit` with a short-flag cluster containing `n` (NOT `git push -n`); `git -c core.hooksPath=`,
     `git config` with `core.hooksPath` and a value and WITHOUT `--get`/`--get-all`/`--list`/`-l` (reads are
     exempt); `GIT_CONFIG_PARAMETERS=`; env names ANCHORED at simple-command start or after `export`/`env` —
     `HUSKY=0`, `HUSKY_SKIP_HOOKS=`, `SKIP=`, `PRE_COMMIT_ALLOW_NO_CONFIG=` (`CI_SKIP=1` must not match);
     `pre-commit uninstall`; `lefthook uninstall`; `rm`/`chmod`/`mv` with an argument containing `.git/hooks`;
     **`git clean` with `x` or `X` in its flag cluster** (deletes ignored files: the markers AND `state.md`);
     **invocations** of `guard-arm.sh` with any subcommand other than `arm` — i.e. a simple command whose
     first word (or the word after `bash`/`sh`/`source`/`.`/`exec`) is a path ending `guard-arm.sh` and whose
     next word is not `arm` (`arm` from a tool call is harmless by construction: it can only create the
     caller's own or a junk file; `arm-from-payload`, `disarm-session`, `prune`, or any future subcommand
     are denied). A *mention* of `guard-arm.sh` as an argument to anything else (`cat`, `sed -n`, `shellcheck`,
     `grep`, `bash -n`) is NOT an invocation and is allowed — an armed run must be able to read the guard;
     write verbs `>`, `>>`, `tee`, `sed -i`, `mv`, `cp`, `rm`, `truncate`, `install` whose simple command
     names a protected basename (below) or contains `.supervisor/guard`.
   - **`Write|Edit` matcher** (`tool_input.file_path`): match on **basename** (`${f##*/}`) and **directory
     suffix** — never `realpath`. Basenames: test runners (`jest.config.*`, `vitest.config.*`,
     `vitest.workspace.*`, `playwright.config.*`, `cypress.config.*`, `.mocharc*`, `karma.conf.*`,
     `pytest.ini`, `tox.ini`), linters/formatters (`eslint.config.*`, `.eslintrc*`, `.eslintignore`,
     `.prettierrc*`, `.prettierignore`, `biome.json*`, `ruff.toml`, `.ruff.toml`, `.flake8`, `mypy.ini`,
     `.pylintrc`), git-hook managers (`.pre-commit-config.yaml`, `lefthook.yml`), **the guard itself
     (`guard-test-integrity.sh`, `guard-arm.sh`, `hooks.json`)** — the live hook is the installed copy under
     `~/.claude/plugins/cache/<marketplace>/loomwright/<ver>/scripts/` (a real directory copy, verified — not
     a symlink to any checkout), and one `exit 0` at its top kills the gate for every session; a maintainer
     of the guard sets the env opt-out for that session (§3, the self-hosting note). Directory-suffix
     matches: `/.husky/`, `/.git/hooks/`, `/.supervisor/guard/`, and **`/.claude/` + basename
     `settings.json` | `settings.local.json`** (covers `~/.claude/` and `<repo>/.claude/`; `.vscode/settings.json`
     and an app's `config/settings.json` are ordinary edit targets and must NOT match): an armed agent has
     no legitimate reason to edit Claude settings (`/setup` writes them and is never armed), and the detached
     drain's fresh `claude -p` would otherwise honour an opt-out written mid-run. `conftest.py` only when
     `git -C "$(dirname "$f")" rev-parse --show-toplevel` succeeds AND equals its parent — a failed lookup
     (new directory) means "not toplevel ⇒ allow", never `guard_unavailable`. **Not in the default list:**
     `package.json`, `pyproject.toml`, `setup.cfg`, `tsconfig*.json`, `.github/workflows/**`;
     `LOOMWRIGHT_GUARD_EXTRA_GLOBS` (colon-separated) extends it — process-env, next-launch semantics, same as
     the opt-out; document both together.
   - **Deny mechanics:** `exit 2` with ONE stderr line, two variants keyed on `agent_type` presence (P2; if
     P2 is NO, the subagent wording is the only variant): subagent — `test_integrity_guard: denied
     <bash|edit> — <pattern label> — this session is a Loomwright run; record the need in outputs_gap /
     escalate NEEDS_HUMAN instead`; main thread — `… — a Loomwright run is armed in this session; finish or
     end the session before editing gate configuration`. **Never names the opt-out, the marker path,
     `settings.json`, `guard-arm`, or any file the agent could edit to proceed.** The `hooks.json` entries
     MUST NOT carry `|| true` (S3) — sentinel test below.
   - **Never denies its own plumbing:** a match that sits only inside a quoted argument to `grep`, `printf`,
     `echo`, `rg`, `jq` (e.g. `grep -n -- '--no-verify' docs/HOOKS.md`) MUST NOT be denied — mirror
     `result_block_parser.py`'s "ACTUAL NEGATIONS ONLY" discipline. **Self-hosting:** a Supervisor run on THIS
     repo maintaining the guard has its worker's `printf … > "$T/jest.config.js"` fixtures denied AND its
     `Edit` on `guard-*.sh` / `hooks.json` denied; list both in HOOKS.md as the known self-hosting cost — the
     maintainer launches that session with the env opt-out, or the worker writes fixtures via heredoc into a
     file whose basename is not protected (e.g. `fixture-jest-config.txt`) and the test copies it. Reading
     the guard's own source is never denied (see the invocation rule above).
3. **Opt-out — process env only.** `LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS=1` in the shell that launched Claude
   Code (and, iff P3 says YES, `settings.json` `env`). A tool call cannot change the running process's env;
   `/.claude/settings*.json` is protected while armed so the "next launch" route (the detached drain) is
   closed too. **No `.supervisor/config.json` key.** Documented in HOOKS.md and the CHANGELOG only — pin
   `grep -rln ALLOW_GATE_CONFIG_EDITS loomwright/agents loomwright/skills` = 0.
4. **`hooks.json`:** `PreToolUse[Bash]` + `PreToolUse[Write|Edit]` → `guard-test-integrity.sh`, NO `|| true`;
   `PreToolUse[Agent|Task]` → `guard-arm.sh arm-from-payload || true`; `SessionEnd` → `guard-arm.sh
   disarm-session || true`. Leaf count 39 → 43 in `loomwright/scripts/test-worktree-audit.sh` AC-2
   (`check-doc-currency.sh` derives its own).
5. **Convention docs (same PR, or the guard is a claim no check backs):** `CLAUDE.md` §"Plugin Hooks" and
   `docs/HOOKS.md` §intro: rewrite "every `type: command` hook string carries `|| true`…" to name the two guard
   leaves as the fail-CLOSED exception. HOOKS.md rows carry: arm points + hook backstop + dispatcher pre-arm,
   the per-session marker files and fail-loud arm, the single SessionEnd disarm, the env opt-out (with P3's
   answer), the two deny variants, and the **honest limits**: script-file indirection (`printf … > x.sh;
   bash x.sh`); configs inside `package.json`/`pyproject.toml`; unlisted paths; a marker deleted by an
   unlisted command shape; flag abbreviations other than `--no-ver*`; **command channels that are not the
   `Bash` tool — `mcp__terminal__run_in_terminal`, a git MCP server, `Workflow` scripts — are outside both
   matchers**; **an inline run arms the human's own session until it ends** (no tool-call disarm exists, by
   design); the self-hosting cost. `AGENT_GUIDELINES.md` / `docs/PITFALLS.md` one-line pointers (grep for the
   `|| true` sentence first).
6. **Destructive tripwire (additive, never weakening):** add `git clean` with `x`/`X` in its cluster to
   `result_block_parser.py` `_DESTRUCTIVE_PATTERNS` with the same `_CMD_START` discipline and a negation-context
   test — the post-hoc net should catch what the pre-action net is for.
7. **Token budget (CI fails CLOSED):** `worker 5876/5905 — 29 headroom`. §8's sub-bullet does not fit. Raise
   `.agents.worker` in `docs/prompt-token-budgets.json` + the ARCHITECTURE_CONTRACTS raise-log row, coordinated
   with item 01. Never trim unrelated `worker.md` prose.
8. **Rule of explanation — `agents/worker.md` step 2 "Run tests"**, one sub-bullet: *"If a test fails,
   diagnose before you fix: add one `test: <test name> — <code wrong | assertion wrong | env>: <why>` entry to
   `deviations` (and its `## deviations` echo). An assertion edit with no `test:` entry for that test, or one
   whose diagnosis says `code wrong`, is a review finding."* Honest framing in the prose: the record is emitted
   at the end, so this captures the diagnosis, not the order of operations. Mirror in the Sequential /
   Single-Agent spawn template only if it restates the run-tests step. **Fix-task prompt (Phase 4.5,
   `general-purpose` agent — no validator, no loomwright prompt discipline):** conditional-MANDATORY wording —
   *"a `FIX_RESULT` whose diff edits a test assertion and carries no `test:` entry is incomplete; add it
   before emitting"*. **Depends on item 01** — run 01 first.
9. **Reviewer side (`agents/code-reviewer.md` Self-heal lens):** *"**When a DEVIATIONS ADVISORY line is
   present** and a hunk changes a test assertion and the advisory carries no `test:` entry naming that test
   (worker or fixer), or carries one that says `code wrong`, raise a HIGH `category: new` finding 'assertion
   changed without diagnosis'. When the advisory is ABSENT (the standalone `/review-pr` drain has no
   advisory carriage today) or reports truncation (`omitted N`), raise nothing. Also HIGH: any hunk touching
   `.claude/settings*.json`, `hooks.json`, or `scripts/guard-*.sh`."* **Same-test-twice cap:** the same test
   flagged on two consecutive Phase 4.5 iterations ⇒ `NEEDS_HUMAN`, not a third round (a bound the loop
   already knows how to honour). The `review-heal` carriage of `fixer_deviations` is a **follow-up item, not
   this one** — record it in 00.
10. **`scripts/test-guard-test-integrity.sh`** (under `bash`, never inline; no `timeout`; `stat -c` first if
    mtime is ever needed): with a marker file named by the payload's `session_id` — every Bash pattern denies
    and its negation twin allows: `git commit -m x` allow · `git commit -n -m x` deny · `git commit -qm x
    --no-veri` deny · `git push -n` allow · `git push --no-verify` deny · `HUSKY=0 git commit -m x` deny ·
    `export HUSKY=0; git commit -m x` deny · `CI_SKIP=1 npm test` allow · `git -c core.hooksPath=/dev/null
    commit` deny · `git config --get core.hooksPath` allow · `git config core.hooksPath /dev/null` deny ·
    `GIT_CONFIG_PARAMETERS="'core.hooksPath=/dev/null'" git commit` deny · `git clean -fdx` deny ·
    `git clean -fd` allow · `grep -- '--no-verify' docs/HOOKS.md` allow · `cat > jest.config.js <<EOF` deny ·
    `git diff jest.config.ts > /tmp/d.patch` allow · `sed -i '' s/a/b/ vitest.config.ts` deny ·
    `rm .supervisor/guard/<sid>.json` deny · `bash …/guard-arm.sh disarm-session` deny ·
    `bash …/guard-arm.sh arm-from-payload` deny · `bash …/guard-arm.sh arm supervisor` allow ·
    `cat …/guard-arm.sh` allow · `sed -n 1,40p …/guard-arm.sh` allow · `shellcheck …/guard-arm.sh` allow ·
    `printf 'x' > notes.md` allow · `sed -i s/a/b/ …/guard-test-integrity.sh` deny. Write|Edit: every
    basename denies incl. `.claude/settings.json`, `~/.claude/settings.local.json`, `hooks.json`,
    `guard-arm.sh`, `guard-test-integrity.sh` (both at a checkout path and at a
    `~/.claude/plugins/cache/…/scripts/` path); `src/foo.test.ts`, `package.json`, `docs/jest.config.md`,
    `new/dir/file.ts`, `new/dir/conftest.py`, **`.vscode/settings.json`**, `config/settings.json` allow;
    `../repo-sub/jest.config.ts` denies; `.github/workflows/ci.yml` allows by default, denies under
    `LOOMWRIGHT_GUARD_EXTRA_GLOBS`. **Gate cases:** `guard/` absent → all allow; `guard/` holds only a
    foreign-id file → all allow; own-id file present → deny cases deny; env opt-out → all allow; no `jq` +
    own-id file → `guard_unavailable` deny; no `jq` + empty `guard/` → allow. **`guard-arm.sh`:** `arm` with
    `CLAUDE_CODE_SESSION_ID` unset → exit 3, no file; set → `<id>.json`; same id again → exit 0 unchanged;
    **a second `arm` under a different env id creates a second file and leaves the first byte-identical**;
    `arm dispatcher --session-id X` writes `X.json`; `arm-from-payload` with `subagent_type`
    `loomwright:loomwright:worker` arms, with `general-purpose` and with unnamespaced `my-worker` does not;
    `disarm-session` removes only the file named by the payload id; `arm` prunes a file with `armed_at`
    8 days old and keeps one 6 days old. **Concurrency case:** two marker files (A, B); a payload with id A
    is denied on `git commit -n`; after `arm` runs with env id B (simulating the second session's backstop),
    the same payload A is STILL denied. **Live probe (P1 recorded as a test, not a fixture):** under
    `claude -p --session-id <uuid>`, the payload `session_id` a throwaway hook logged equals `<uuid>`, and
    the dispatcher's pre-written marker is the file the guard consulted. **Sentinels:** the two guard commands
    contain `guard-test-integrity.sh` and NOT `|| true`; `grep -rln ALLOW_GATE_CONFIG_EDITS loomwright/agents
    loomwright/skills` empty; neither deny line contains `ALLOW_GATE`, `.json`, `settings`, `config.json`,
    `guard-arm`. **Mutation controls:** (a) delete `exit 2` → `git commit -n` case fails; (b) append `|| true`
    to a guard hook string in a temp copy → sentinel fails; (c) make the guard read a fixed `armed.json`
    instead of `<sid>.json` → the foreign-id-only case fails; (d) `--no-ver[a-z]*` → `--no-verify` →
    `--no-veri` case fails; (e) delete the empty-id check in `arm` → the unset-env case fails; (f) drop the
    same-simple-command rule → `git diff jest.config.ts > /tmp/d.patch` case fails; (g) let `arm` write a
    file named from a caller-supplied id outside the `dispatcher --session-id` shape → the concurrency case
    fails; (h) drop the namespace-colon requirement from `arm-from-payload` → the `my-worker` case fails.
11. **Docs/release:** `CHANGELOG.md` one paragraph; version bump per
    `release-surfaces-readme-claude-md-no-longer-bump`.

## Non-goals
No sandbox, no network sealing, no held-out test set. No default block on `.github/workflows`. No
per-agent-frontmatter hook. No tool-call disarm of any kind. No `/automate`-specific arm/disarm. No
`review-heal` advisory carriage (follow-up). No gating on `in-progress/` anywhere. No coverage of command
channels other than the `Bash` tool (MCP terminal/git tools, `Workflow`) — honest limit, listed. **Human
sessions:** a session that never ran a Loomwright entry point is inert by construction (no file named by its
id). A session that ran one inline (`/supervisor`, `/review-pr`, `/automate`) is the human's own session and
stays armed until it ends — the main-thread deny variant then applies to the human's own `git commit -n`.
That is the intended trade for having no tool-call disarm; it is stated, not hidden.

## Acceptance criteria
- P1, P2, P3 each have a fixture + README under `scripts/progress-event-fixtures/guard-probe-<date>/` stating
  the launch mode and the answer; §1/§2/§3 wording matches the answers.
- With a marker file named by the payload's `session_id`: `git commit -n -m x`, `git commit -qm x --no-veri`,
  `git clean -fdx`, `bash …/guard-arm.sh disarm-session`, `Edit jest.config.ts`, `Edit ../repo-sub/jest.config.ts`,
  `Edit .claude/settings.json`, `Edit ~/.claude/plugins/cache/x/loomwright/1/scripts/guard-test-integrity.sh`,
  `Edit hooks.json` → exit 2; `git diff jest.config.ts > /tmp/d.patch`, `git config --get core.hooksPath`,
  `CI_SKIP=1 npm test`, `Write new/dir/file.ts`, `Edit .vscode/settings.json`, `bash …/guard-arm.sh arm
  supervisor`, `cat …/guard-arm.sh` → exit 0.
- `guard/` absent, or holding only files named by other ids, or env opt-out → every payload exit 0.
- `guard-arm.sh arm` never writes a file whose name is not its own `CLAUDE_CODE_SESSION_ID` (or, for the
  dispatcher shape only, the explicit `--session-id`); a forged-env `arm` leaves every other file
  byte-identical; the concurrency case in §10 passes.
- `dispatch-pr-review.sh` writes `<worktree>/.supervisor/guard/<uuid>.json` before launch and passes
  `--session-id <uuid>`; its test asserts both (DRY_RUN output names the uuid twice).
- `guard-arm.sh arm` with empty `CLAUDE_CODE_SESSION_ID` → exit 3 and no file; Supervisor INIT and
  review-heal entry record `guard_armed: failed` and the completion tail shows `guard: unarmed`.
- Neither deny line names the opt-out, a marker, `settings`, `config.json`, or `guard-arm`.
- `hooks.json`: two guard leaves without `|| true`, arm-backstop + SessionEnd leaves with it; leaf count 43
  pinned; `check-doc-currency.sh`, `check-token-budget.sh` pass.
- `CLAUDE.md` §"Plugin Hooks" and `docs/HOOKS.md` name the guard leaves as the fail-CLOSED exception; zero
  unqualified "every `type: command` hook string carries" hits; HOOKS.md carries every honest limit in §5
  including the non-Bash-channel and inline-session-arming entries.
- `agents/worker.md` step 2 sub-bullet with honest framing; fix-task prompt conditional-mandatory `test:`;
  `agents/code-reviewer.md` clause is presence-scoped, has the truncation + absent exemptions, the
  settings/hooks/guard-source HIGH, and the same-test-twice → NEEDS_HUMAN cap.
- `_DESTRUCTIVE_PATTERNS` gains `git clean -x/-X` with a negation-context test.
- `worktree-salvage.sh` excludes `.supervisor/guard/`.
- All eight mutation controls in §10 fail when applied and pass when reverted.
- `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` still resolves to exactly the
  five surfaces CLAUDE.md enumerates.
- Full `loomwright/scripts/test-*.sh` loop + root `scripts/check-*.sh` green locally before push.

## Verified premises (re-check before starting; each was read or probed on 2026-09-21)
- `hooks.json` `PreToolUse` matchers: `AskUserQuestion` only; leaf count 39 pinned in `test-worktree-audit.sh`
  AC-2, derived in `scripts/check-doc-currency.sh`.
- `CLAUDE_CODE_SESSION_ID` is set in the Bash tool env of this desktop session and equals the transcript
  basename; `scripts/notify-desktop.sh` reads it as a fallback session id. Unverified under `claude -p` (P1).
  A Bash tool call can set it per-command (`VAR=x cmd`) — which is why `arm` may never use it to name any
  file but its own.
- `claude --help` lists `--session-id <uuid>` ("Use a specific session ID for the conversation") — the
  dispatcher can fix the detached runner's id before launch.
- The live plugin is `~/.claude/plugins/cache/atelier/loomwright/<ver>/` — a real directory copy (`ls -la`
  shows a directory, `readlink` empty), so `${CLAUDE_PLUGIN_ROOT}/scripts/guard-*.sh` is an editable file
  that is NOT this checkout; editing the checkout does not change the live hook, editing the cache does.
- Memory `subagentstop-payload-shape` §"PostToolUse fires for a SUBAGENT's tool calls": payload carried
  `agent_type: "general-purpose"` + `agent_id`, with the MAIN session's `session_id`. `PreToolUse` unverified (P2).
  `spawn-probe-2026-09-02/pretooluse-task-*.json` are main-thread `tool_name: "Agent"` calls — they show the
  `Agent` tool name for the backstop matcher, nothing about subagent payloads.
- `subagent_type` shapes the plugin spawns: `general-purpose` (8), `loomwright:code-reviewer` (6),
  `loomwright:worker` (2), `loomwright:execute-manager` (2), …; the runner is never a `Task` target.
- `skills/self-heal-advisory/SKILL.md` fix tasks: `subagent_type: "general-purpose"` (two sites).
- `skills/review-heal/SKILL.md`: 0 occurrences of `ADVISORY` — the drain's reviewer receives no advisory line.
- CLAUDE.md §"`/automate` single-drain ownership": the `.auto_review` cleanup wraps RUN, not DRAIN; the owned
  drain is inline. `self-heal-advisory/SKILL.md` "Hook backstop (v14.34.0 — defense-in-depth)": prompt steps
  get skipped; hooks are the backstop.
- `scripts/dispatch-pr-review.sh`: `cd "$_wt"` then `nohup bash -c … "$_bin" -p --agent "$_runner"` — a fresh
  `claude` process (fresh settings read) launched mid-run by the `gh pr create` hook.
- `scripts/worktree-salvage.sh` copies `untracked/` into `<primary>/.supervisor/salvage/`.
- This repo carries `.claude/settings.local.json` (Claude Code writes it internally on permission grants —
  not a tool call, so the guard never sees it); `.vscode/settings.json` is the common false-positive shape.
- The plugin's own scripts/skills/agents never run `git clean`, `git -c`, or a `SKIP=` prefix (grep: 0
  outside tests) — no self-deny on the FINALIZE / cleanup paths.
- `git commit -qm x --no-veri` committed past a failing pre-commit hook (live probe). `realpath` rc 1 on a
  missing path; no `-m`. `bash scripts/check-token-budget.sh` → `worker 5876 5905 OK 29 headroom`.
- `.supervisor/config.json` writers: `setup-memory.sh`, `automate-helpers.sh`, `curation-status.sh`,
  `measure-heal-signal.sh`.
- `mcp__terminal__run_in_terminal` exists in the desktop app's tool list — a command channel the `Bash`
  matcher never sees.
- Claude Code `PreToolUse`: exit 2 blocks and stderr is shown to the model — re-verify against the current
  hooks reference; if `permissionDecision: deny` JSON is preferred, emit it AND still exit 2.

## Status: done (PR #258, merge 0b1975e)
- **Completed:** 2026-09-26T02:14:50Z
- **Brief:** .supervisor/jobs/done/2026-09-23-test-integrity-guard.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/258
