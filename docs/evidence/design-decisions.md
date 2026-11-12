# Evidence — briefs record the chosen approach and the alternatives it beat

Requirement: `.supervisor/requirements/approach-decisions/02-briefs-record-the-chosen-approach-and-the-alternatives-it-beat.md`
(AC10, Validations 4–6). Captured 2026-11-12 on macOS (Darwin 25.6.0) with Claude Code 2.1.319 and
`claude-opus-5-5`, from the subtask-3 worktree of branch `feature/approach-02-design-decisions` (subtasks 1
and 2 merged into it, base `0c83614`). Home paths are written as `/Users/<name>/`; `<scratch>` is a
`mktemp -d` directory outside the repo.

**Status in one line:** AC10's proposed rule is below, unwritten. Validation 6 is PASS: every condition was
seen in its run. Validations 4 and 5 have no `Verdict:` line, and the owner decides them (`AUT-WAIVE`). V4 needs
an interactive `LP-APPROACH` answer that a headless run cannot give. V5 ran headless and showed two of its three
conditions; the printed no-trigger line was not seen.

## AC10 — the proposed house rule (not written)

No file under `.agent/rules/` changes in this change; `loomwright/scripts/test-design-decisions.sh` guards
that against `origin/main` on this change's branch. The rule is proposed for the owner to add with:

```text
/rules add --category process --statement 'A brief that adds a new dependency carries a `## Design decisions` entry naming the chosen library, at least one rejected alternative and the evidence' --enforcement advisory --applies-to package.json --applies-to package-lock.json --applies-to requirements.txt --applies-to pyproject.toml --applies-to go.mod --applies-to Cargo.toml --applies-to pubspec.yaml
```

The statement is single-quoted so the backticks around `## Design decisions` stay literal in a shell.

**Why advisory and why no `--check`.** A `must` rule with a check has to be proven first
(`commands/rules.md` §"Proof step", `loomwright/scripts/prove-rule-check.sh`). Leg 1 runs the check on the
current tree and needs it to pass. Leg 2 applies a counterexample patch to a scratch copy of HEAD and needs it
to fail. The violation this rule names is a fact about a brief, and a brief lives under the gitignored
`.supervisor/jobs/`, so it never reaches a commit. A change that adds a dependency with a
proper `## Design decisions` entry and one that adds it with none therefore commit the same tree: the same
manifest edit and no brief. A counterexample patch for leg 2 is that manifest edit. Any check that fails on it
also fails on the conforming change, so it cannot pass leg 1 on a tree that already has correct dependency
additions. A check that passes leg 1 passes leg 2 as well, and the proof comes back `VACUOUS`. So the rule
stays advisory, with no check. Plan Reviewer Criterion 23 (23a, 23b) is where a brief's `## Design decisions`
entry for a new dependency is actually read.

## How the runs were made

Each run used a fresh scratch Node project: `package.json` (Express 4 and multer; no rate-limit
dependency), a CLAUDE.md naming the stack, `src/server.js`, `src/routes/upload.js`, and a `README.md` whose
`## Install` line reads ``Run `npm instal` to install the dependancies, then `npm start`.``. Each project has
one commit on `main` and a local bare remote, populated by a fetch from the bare side, so `origin/main` and
`origin/HEAD` resolve for Launch Pad's base-branch check. Nothing was pushed.

```bash
cd <scratch>/<project>
env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT CLAUDE_PLUGIN_ROOT=<checkout>/loomwright \
  claude -p --plugin-dir <checkout>/loomwright --permission-mode acceptEdits \
  --allowedTools "Bash Read Write Edit Glob Grep Task Agent" --output-format stream-json --verbose "$PROMPT"
```

`$PROMPT` was: ``Run the Loomwright /launch-pad slash command with these arguments: <args>``, followed by
``The plugin root for this run is <checkout>/loomwright. Read commands/launch-pad.md, agents/launch-pad.md and
every skill, script or doc they name from that root only; never read or run anything under ~/.claude/plugins.
Spawn the Plan Reviewer as the loomwright plan-reviewer agent.``

**Why the plugin root is named in the prompt.** The first two attempts used the plain
`/loomwright:launch-pad <args>` slash command. The session's `init` record showed the checkout loaded as
`loomwright@inline`, and the command body was the checkout's (it names Phase 2.7). But that body names
`agents/launch-pad.md` relative to the plugin root, and the model never read `$CLAUDE_PLUGIN_ROOT`. It ran
`ls -d ~/.claude/plugins/cache/*/loomwright/*` and read the installed 17.36.2 agent, which has no Phase 2.7.
Those attempts tested the installed plugin, not this change, so they are not counted. The pinned runs read
`<checkout>/loomwright/agents/launch-pad.md`, `commands/launch-pad.md` and `skills/supervisor-readiness/`
(checked from the `Read` tool calls in each transcript).

## Validation 4 — a triggering goal, interactive

Not run. V4 needs `LP-APPROACH` to be asked and answered by a person, and this capture ran headless, where
no question can be shown. V6 below runs the same goal under `--non-interactive`. No verdict.

## Validation 5 — a non-triggering goal

Arguments: `goal: "fix the typo in README.md §Install" --non-interactive`. `--non-interactive` is added
because a headless run cannot answer the save question; with the flag, Phase 6 saves a PASSed brief
unmutated. Session `31f2cd20-…`, 13 turns, 124 s, exit 0.

Observed:

- The run read `<checkout>/loomwright/agents/launch-pad.md` and spawned one Plan Reviewer
  (`loomwright:loomwright:plan-reviewer`).
- The saved brief `.supervisor/jobs/pending/2026-11-12-fix-readme-install-typo.md` has these sections, and no
  `## Design decisions`: Environment, Feasibility, Task, Acceptance Criteria, File Impact Map, Subtask
  Structure, Parallelism Analysis, Skill References, Risk Assessment, Configuration, Handoff.
- The Plan Review result carries no `approach_` category. The string `approach_` does not occur anywhere in
  the transcript. Its result:

```text
PLAN_REVIEW_RESULT:
  schema_version: 1
  decision: PASS
  requirement_fit: fulfils
  issues:
    - severity: LOW
      section: "Subtask Structure"
      category: "dep_graph"
      description: "Subtask 1 provides {kind: symbol, path: README.md, name: \"## Install\"}. … The check would pass even if the worker made no edit, so it does not show the fix landed."
  summary: "Brief is sound. … Criteria 14, 15, 17, 18, 19, 20, 21 and 23 were skipped because their triggers are absent. …"
```

- `LAUNCH_PAD_RESULT`: `status: saved`, summary `saved_on_pass_non_interactive: Plan Review PASS on attempt 1/3 (1 LOW deferred) …`.

Not observed: the line `## Phase 2.7: APPROACH — no trigger`. In this headless run the model printed only a
final summary, with no per-phase output. That line occurs in the transcript only inside the prompt files it
read. The other two conditions hold. Because this one was not seen, there is no verdict.

## Validation 6 — the can't-ask branch

Arguments: `goal: "add rate limiting to the /api/upload route with a library" --non-interactive` (the V4
goal under the flag). Session `1bd61425-…`, 15 turns, 259 s, exit 0.

Observed:

- **No question was asked.** The transcript has 0 calls to the ask tool.
- **The entry carries `status: unconfirmed`.** The run read `<checkout>/loomwright/skills/supervisor-readiness/design-decisions.md`
  (Phase 2.7's `Read(`) and wrote two entries. The T1 one is unconfirmed; the second, for the T4
  cross-cutting mechanism, has no tie and no new dependency, so it was decided with no question and is
  `confirmed`. From the draft brief `.supervisor/jobs/scratch/2026-11-12-add-rate-limiting-api-upload.md`:

```text
## Design decisions
- decision: which mechanism enforces the per-client request limit on POST /api/upload
  chosen: `express-rate-limit` (new npm dependency, Express middleware, in-memory store)
  rejected: multer `limits` option (already in the manifest via `multer`) — fits the CLAUDE.md stack: no; it caps per-request size and file count, not request rate, so it cannot meet the goal
  rejected: `rate-limiter-flexible` (new npm dependency) — fits the CLAUDE.md stack: partial (not Express middleware out of the box, needs a hand-written wrapper); reversibility: partial (wrapper code to unpick)
  rejected: hand-written in-memory middleware — excluded by the goal itself ("with a library"); also a new module to own and test
  evidence: repo — `package.json` dependencies are only `"express": "^4.19.2"` and `"multer": "^1.4.5-lts.1"`; no lockfile; `grep -ri "rate" package.json src/` → no hits. Express 4 / Node 20 have no built-in rate limiter. Context7 was not available in this session, so library docs were not consulted (repo evidence only)
  revisit when: the API runs as more than one process/instance (an in-memory store no longer gives a global limit — then a shared store such as Redis is needed), or a second route needs limiting with different policy
  status: unconfirmed
- decision: where the limiter is mounted (rate limiting is a cross-cutting mechanism)
  chosen: route-level, inside `src/routes/upload.js`, ahead of `store.single('file')`
  rejected: app-wide `app.use(limiter)` in `src/server.js` — blast radius: no (would also govern any future route, outside the goal); reversibility: partial
  rejected: mounted in `src/server.js` on `app.use('/api/upload', limiter, upload)` — blast radius: partial (touches a second file for no gain); CLAUDE.md keeps route concerns in `src/routes/` one file per route
  evidence: `src/server.js` only mounts routers (`app.use('/api/upload', upload);`); `src/routes/upload.js` owns the route's middleware chain (`router.post('/', store.single('file'), (req, res) => {`)
  revisit when: several routes need the same limiter policy (then extract a shared middleware module)
  status: confirmed
```

- **Plan Review is NEEDS_HUMAN with a MEDIUM `approach_unjustified` naming 23d**, and no BLOCKING or HIGH
  issue (no `approach_reinvents` anywhere in the transcript). The other issues are three MEDIUM
  (no `.gitignore` risk row, `pin_mutations`, `lane_overlap`) and one LOW. Its Criterion 23 issue and summary:

```text
decision: NEEDS_HUMAN
  - severity: MEDIUM
    category: "approach_unjustified"
    description: "23d: The T1 trigger is present: Feasibility rows 1, 2 and 5 are CAUTION and name the new npm dependency `express-rate-limit`. Its Design decisions entry ('which mechanism enforces the per-client request limit on POST /api/upload') carries `status: unconfirmed`. The run was non-interactive, so nobody answered LP-APPROACH. The entry itself is sound: … An owner still has to confirm the new runtime dependency."
    suggestion: "The owner confirms express-rate-limit (then set `status: confirmed`), switches to another library, or drops the dependency. …"
summary: "There are no BLOCKING or HIGH issues. NEEDS_HUMAN comes from one source only: Criterion 23d, an unconfirmed new runtime dependency (T1). … The decision would otherwise be PASS. …"
```

- `LAUNCH_PAD_RESULT`: `status: aborted`, summary
  `needs_human_non_interactive: Plan Review 1/3 NEEDS_HUMAN on Criterion 23d (unconfirmed new dependency express-rate-limit); no BLOCKING/HIGH; nothing saved.`
  This is the existing Phase 6 can't-ask branch for NEEDS_HUMAN; no new park state.

One limit, recorded rather than hidden: the Plan Reviewer subagent has no Bash and was given no plugin root, so
when Criterion 23 told it to read `skills/supervisor-readiness/design-decisions.md` it searched for it and
read the installed plugin's `SKILL.md` under `/Users/<name>/.claude/plugins/marketplaces/`, where that file
does not exist yet. Its 23d finding comes from the criterion text in its own prompt, which was this change's.
Once the plugin is released, the installed copy carries the file.

Verdict: PASS for Validation 6
