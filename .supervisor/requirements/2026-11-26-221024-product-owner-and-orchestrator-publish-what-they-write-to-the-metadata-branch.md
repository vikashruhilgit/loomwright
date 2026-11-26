# Product Owner and Orchestrator publish the requirement files they write to the metadata branch, and stop calling them local-only

## Status: open

## Why

In branch mode (`setup-memory.sh mode` prints `on <branch>`), `.supervisor/requirements/**/*.md` is in
`meta-sync.sh`'s managed set and is meant to live on the metadata branch. But the only thing that ever
pushes is `/automate`'s trail (`trail-pr`), for the item it ran. Files written by `/product-owner`,
`/orchestrator` or by hand stay on one machine until someone remembers `meta-sync.sh push`.

The prompts make it worse. `loomwright/agents/product-owner.md`, `loomwright/commands/product-owner.md`,
`loomwright/agents/orchestrator.md` and `loomwright/commands/orchestrator.md` each carry a "Collaboration
note" saying file-fallback stories and plans are "local-only — a teammate cloning the repo won't see them".
That predates branch mode and is false wherever branch mode is on.

## Story

**As the** owner running Loomwright in a branch-mode repo,
**I want** every requirement file Product Owner or Orchestrator writes to be on the metadata branch as soon as
it is written, with a named line when that fails,
**so that** what is planned is never split between "on this machine" and "on the branch", and no agent tells
me a synced file is local-only.

## Scope

- One shared helper that publishes an exact list of paths: branch-mode check, then `meta-sync.sh scrub
  --paths-from`, then `meta-sync.sh push --paths-from` on a clean scrub. It never pushes a whole root.
- Product Owner calls it at the end of its Persist step (file-fallback mode) with exactly the files that run
  wrote: stories and the `_BACKLOG-*` plan doc.
- Orchestrator calls it after it writes `{slug}-plan.md` or appends `## Task Plan` to a handed-off
  requirement file, with that one path.
- The four "Collaboration note" paragraphs say what is true in each mode.

## Acceptance criteria

**Happy path**
- [ ] Given branch mode `on loomwright-meta`, when `/product-owner` persists two stories and a plan doc, then
  those three paths, and no others, are pushed. `git show origin/loomwright-meta:<path>` matches each local
  file, and the report names the push (the commit sha and path count `meta-sync.sh` printed).
- [ ] Given branch mode on, when `/orchestrator` writes `{slug}-plan.md` or appends `## Task Plan` to a
  requirement file, then that one path is pushed the same way.
- [ ] Given the helper, when it runs, then it pushes only the paths it was given (`--paths-from`), never a
  whole root, so another unpushed or locally deleted managed file is left alone. A test pins this with a
  local-ahead file and a locally deleted file that are not in the list.

**Edge cases**
- [ ] Given branch mode `off`, when either agent writes, then nothing is pushed, and the report says so in one
  line ("branch mode off: requirement files stay in this checkout").
- [ ] Given branch mode `unknown <reason>`, when either agent writes, then nothing is pushed, and the report
  names the reason.
- [ ] Given this checkout is an `/automate` lane (`automate-helpers.sh lane-info` exits 0), when either agent
  writes, then the helper does not push, because a lane publishes its files only at wave end through
  `lane-convert-ready` (or `lane-remove --abandon`), and the report says so.
- [ ] Given Product Owner's can't-ask branch (`po_gate: needs_owner`), when the run ends, then nothing was
  persisted and nothing is pushed.
- [ ] Given a path outside the managed set, when passed to the helper, then it is refused by name and
  nothing is pushed.

**Error scenarios**
- [ ] Given a scrub hit in one of the files, when the helper runs, then nothing is pushed, each hit is named
  (`scrub-hit` lines), the files stay written locally, and the agent's report says the push did not happen
  and why.
- [ ] Given `meta-sync.sh push` fails (no network, a merge conflict on the branch, the lock held), when the
  helper runs, then the failure is named in the report with the exact command to retry, the files stay
  written locally, and the agent's run still completes (fail-safe: publishing never undoes a write).

**Wording**
- [ ] Given the four "Collaboration note" paragraphs, when this lands, then each says: branch mode off ⇒
  local to this checkout; branch mode on ⇒ published to the metadata branch, which is public when the repo
  is. The agent and command copies of each note say the same thing (house rule: a restated text changes
  in the same change as its source).

## Non-goals

- Pushing files `/product-owner` or `/orchestrator` did not write in this run (the backlog of already
  unpushed files is a one-off push for the owner).
- Launch Pad briefs and Supervisor jobs: `/automate`'s trail already publishes them.
- Pushing inside an `/automate` lane (lanes publish at wave end).
- Changing `meta-sync.sh`'s merge, scrub or managed-set rules.
- Making the metadata branch private.

## Owner decisions

- 2026-11-27 (Vikash): "PO should push the requirement to meta as it's created, so there will be no gaps or
  confusion." This replaces automate-speed decision **D7** (2026-10-15: "Product Owner does not push to
  `loomwright-meta`; the owner pushes before a `--parallel` run"), which was recorded without a reason.
- 2026-11-27 (Vikash): asked that Orchestrator be covered by the same change (it writes to the same folder).
- 2026-11-27: the metadata branch is on the public repo `vikashruhilgit/loomwright`, so publishing on write
  makes a draft story public the moment it is written; the scrub runs first.

## Priority: MVP

**Rationale:** unpushed planning files already caused a wrong "local-only" claim to the owner and a 12-file
gap on 2026-11-27. Every new `/product-owner` run widens the gap until this ships.

## Assumptions

- Defect evidence: observed — on 2026-11-27, `meta-sync.sh status --paths` listed 12 local-ahead managed
  files, including requirement files written by `/product-owner` on 2026-11-21 and 2026-11-23 and qa-split
  files written by hand. In the same session an agent told the owner requirement files were local-only,
  quoting the prompts' "Collaboration note".
- Product Owner and Orchestrator both have Bash, so they can call a script; neither needs a new tool.
- When `/automate` takes a prompt source, Product Owner's push and the later trail push can both send the
  same file. `meta-sync.sh` merges per file, so the second push of unchanged content is a no-op; a test
  confirms this.
- The helper belongs next to the existing branch-mode helpers (`automate-helpers.d/meta.sh`, dispatched by
  `automate-helpers.sh`), following the `<script>.d/` module layout. The worker may choose another home if
  the module layout says otherwise.

## Risks

- **Public by default.** A story with a private detail goes public on write. The scrub catches home paths and
  known secret shapes, not every private fact. The Collaboration note states this.
- **Slower runs.** A push adds a fetch and a push per run (seconds). On failure the run still completes.
- **Two writers.** A concurrent `/automate` trail push and a PO push can contend for meta-sync's lock; the
  loser reports a named failure and a retry command.

## Validation (must pass before merge)

1. **Static — affected suites:** `bash scripts/ci-local.sh --affected` passes, with new legs in the helper's
   test (branch mode on/off/unknown, a lane checkout, a scrub hit, a path outside the managed set, a failed
   push, a local-ahead and a locally deleted file left alone, a repeated push as a no-op), against a local
   bare repo as `origin`.
2. **Static — prompt gates:** `check-token-budget.sh` and `check-doc-currency.sh` pass with updated budget
   rows for the agent and command files that grew.
3. **Running system — a real PO run:** in a branch-mode scratch clone whose `origin` is a local bare repo,
   `/loomwright:product-owner` writes one story, and `git show origin/loomwright-meta:<path>` prints it right
   after the run. The output is pasted in the PR.

## Depends on
none

## Touches
loomwright/scripts/automate-helpers.d/meta.sh
loomwright/scripts/automate-helpers.sh
loomwright/scripts/test-automate-helpers.sh
loomwright/scripts/test-automate-helpers-dispatch.sh
loomwright/agents/product-owner.md
loomwright/commands/product-owner.md
loomwright/agents/orchestrator.md
loomwright/commands/orchestrator.md
loomwright/skills/automate-loop/branch-mode.md
loomwright/docs/prompt-token-budgets.json
loomwright/docs/ARCHITECTURE_CONTRACTS.md
changelog.d
