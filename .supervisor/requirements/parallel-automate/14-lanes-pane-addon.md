# 14 — The lanes pane as an optional, installable add-on (Claude adapter; nothing depends on it)

## Status: in review — PR #472 (https://github.com/vikashruhilgit/loomwright/pull/472), review drain READY 2026-10-11; awaiting owner approval + merge, then the two owner-run checks below

## Where it stands (2026-10-11)
- **Inbox added (owner, 2026-10-11, after the first READY):** every lane's pending question in one list, oldest
  first, answered in place, with an optional note (delivered by lane-answer as an annotation) and a replace path
  for a held (`answer_pending`) answer; lane cards point to it and show the stamped policy's automatic answers.
  Drain rounds 3–4: the bot found the mobile note-field branch untested; the fix worker's real mobile mount showed
  it could never run (`$.ui.resolve()` returns every element on every surface, so `'Input' in ui` is always true)
  — now decided by surface (6fb8ef7), test comment corrected (0baff6f). Drain READY `sub_floor_converged`, 4 of 5
  rounds.
- **Built and reviewed (PR #472, head 0baff6f; first READY was at 965bd29):** the `loomwright-lanes` plugin (Scopes 2, 3, 5's static + fixture
  tests), the core `lane-status --json` additions (`questions[].items[]`, per-lane `branch`), docs, CI step,
  changelog fragment (`bump: minor`, left unfolded for the release PR). CI green on every check.
- **Review drain (`/review-pr --until-mergeable`):** READY, converged, 2 fix cycles —
  (1) LOW: the vendor-coupling manifest comment's sibling list omitted the add-on; the first fix named it under
  `loomwright/`, which tripped this item's own P9 gate (red `ci`, drain escalated); resolved by describing the
  unscanned set structurally instead of listing names (0300d92) — the drift cannot recur;
  (2) the static guard's `lane()` command check was single-line and missed the multi-line `lane-answer` call;
  now flattened, with a 3-call-site assertion and a `lane-answer` mutation control (965bd29).
  A `/pr-postmortem` was dispatched (repeat required-check failure after a fix).
- **Still open — owner-run, after merge (cannot be done from a session):**
  1. Acceptance 1 / Validation 3: `/plugin install loomwright-lanes@atelier` in a fresh session, `/lanes` over a
     real two-lane wave, answer a waiting lane through the pane, check the lane's answer file shows
     `via: lanes-addon`, then uninstall and confirm the run is unaffected. Paste the result here.
  2. Validation 1's base-vs-branch `<passed>/<total>` baseline: the PR records the branch counts; a base run
     was not taken.
- **Release:** the fragment folds in the next `bump-version.sh` release PR.

## Decisions and findings (2026-10-11, owner session)
- **Answer authority (owner, option a):** a button press in the pane counts as the owner answering. The pane calls
  `lane-answer <lane_dir> <id> --owner-command '/lanes answer <lane> <id>' --via lanes-addon`. (`_lanes_gate` only
  requires a non-empty owner command — an empty one BLOCKS and marks the lane `blocked_launch` — and records
  `via`, never the command.) Rejected: (b) hold the answer for `/automate --resume` to deliver; (c) show the
  command only.
- **Core gap found and closed in the same PR:** `lane-status --json` carried only the FIRST question's text per
  pending call (no options, header, multiSelect, or later questions) and no branch — the pane could not draw
  option buttons without reading lane files. Added, additively: `questions[].items[]`
  (`{question, header, multiSelect, options[{label, description}]}`, in answer-key order) and per-lane `branch`
  (from the run file's `## Current` `branch:` field, via a separate `_lanes_runfile_branch` — adding a sixth
  field to `_lanes_runfile_fields` would join its callers' fifth). Tests R13–R16, U9b.
- **multiSelect:** the design's "exactly one option picked" holds for single-select only; a multiSelect question
  needs at least one pick, sent comma-joined (lane-answer's own format).
- **Scope 1 (packaging), from the build's own reference (`plugin-authoring` skill, Claude Code 2.1.295):** a
  marketplace plugin whose content is a hooks module alone installs with `/plugin install <mod>@<marketplace>`
  and is active at once ("Installed <mod>. Plugin is now active."), no hot-reload step; the official
  `code-modernization` plugin ships `"modules"` in its `hooks.json` the same way. `claude plugin validate`
  reads manifest + module source (hooks, `$` calls, `$.state` keys vs the `types` contract); `claude plugin
  test` runs `*.test.tsx` against the engine. Still to confirm on a real install: Acceptance criterion 1.
- **Finding the core scripts (step 2's open choice):** the `loomwrightRoot` option when set, else the
  `installPath` of the enabled `loomwright@*` entry in `claude plugin list --json` — never a glob of
  `~/.claude/plugins/cache/` (the CLI store keeps stale versions). This is the module's one process call that
  is not a lane command; `scripts/test-lanes-addon.sh` pins both argv shapes.
- **Scope 4 (vendor coupling) — deviation:** `vendor-coupling-manifest.json`'s own header leaves the sibling
  plugins (`stackpack/`, `mysql-mcp/`) deliberately UNSCANNED; `loomwright-lanes/` is treated the same and is
  NOT added, rather than breaking that design. Recorded in the changelog fragment.
- **`lane-feed`** has no `--recent N`; the pane keeps the last 20 lines of its output.
- **Pane design (owner review of a live fixture preview, 2026-10-11, five rounds):** desktop sections are soft
  see-through tints of their tone (no borders — nested borders drew double lines); a question's options sit on
  one rounded tray in the page color (`inverseText`; a desktop rounds a Box only through its border, so square
  per-button backings showed their corners); a picked option is a filled button with its mark — ● ○ for pick
  one, ☑ ☐ for pick any; Send stays light until every question is answered, then is the one filled button;
  options without descriptions sit side by side as chips; aligned label/value rows (Item without the
  `.supervisor/requirements/` prefix, Branch, Ready, CI slot, Progress without its timestamp); a "↻ Refresh
  now" button beside the refresh interval. The terminal keeps one rounded border per section. Platform limits
  found: a desktop draws native buttons a plugin cannot color, and a Button's label must be plain text (the
  engine refuses a styled `Text` child on this build).
- **Idle cost:** installed, the module runs in every session; with no lanes and no pane opened it polls once a
  minute instead of every 15 s (test-pinned).

## Problem
Owner (2026-10-04, after using it): "the /lanes command you build here — should that be a part of harness/plugin? …
do we have requirement for this? … is this temporary?" It is temporary today:
- In S1 v1 the pane was written as a session dev mod (`s1-lanes`) and not loaded; in S1 v2 it was repointed and
  hot-reloaded, used as a status view; in wave w1 it was rebuilt as `lanes` with a per-lane **Details** toggle (last
  20 steps) and question buttons. It lives only in that session's private mods folder
  (`~/.claude/dev-mods/<session>/lanes/`), loads only through that session's hot reloading, and talks to the spike
  harness (`s1h.sh status --json`, `s1h.sh recent`, `s1h.sh answer`), which item 05 replaces.
- The requirement set mentions a pane only as one optional client (05 Scope 13) and describes what it shows (05
  Scope 15). Nothing says how it ships, installs, or is tested.

## Goal
Anyone running parallel lanes in Claude Code can install a lanes pane that shows every lane live and answers lane
questions — while the lanes, the core scripts and every other harness behave identically with it uninstalled
(decision P9).

## Design (decided here; P9 rules apply verbatim)
- **A separate, opt-in sibling plugin in this marketplace** (working name `loomwright-lanes`), like `stackpack` and
  `mysql-mcp` — NOT inside `loomwright/`, so installing Loomwright never loads it and its Claude-only code stays out of
  the core.
- **It reads and writes only through item 05's core commands:** `lane-status --json` for state (including Scope 14's
  last actions / stalled state / CI-slot position and Scope 15's merge-readiness score), `lane-feed <lane>` (or a
  `--recent N` form) for the Details view, `lane-answer <lane> <id>` for every answer. It never reads lane files
  directly, never launches or resumes a lane itself (P9 rule 5), never holds state that matters (P9 rule 3).
- **What it shows** (the w1 prototype, kept): a `/lanes` command opening a pane; a status-line summary; a toast when
  a lane starts waiting; per lane: state glyph (running / waiting for you / stalled / parked + reason), item, PR,
  branch, last progress, last 3 actions, a Details toggle with the last ~20 steps, merge-readiness (`ready 5/5` or the
  failing checks), and the question with one button per option plus a send button that refuses until every question
  has exactly one option picked. Refresh every 15 s; an action refreshes at once.
- **Added 2026-10-06 (owner, from the S3 wave-2 operator rebuild of the prototype):** three more things in the pane,
  each read from `lane-status --json` only (item 05 Scope 17b supplies the fields; the pane computes nothing from lane
  files):
  - **a machine-health line** at the top: load state (`ok` / `busy` / `overloaded` from item 16's `machine-load.sh`,
    with load1 and memory pressure), keep-awake (`held` / `not held`), and a visible HIGH-LOAD alert when the state is
    `overloaded` (wave 1 froze the machine at load1 119 with nothing on screen saying so);
  - **a wait time on every pending question** ("waiting 12 m"), from the question's `asked_at`, oldest first — the
    longest wait in S3 wave 1 was ~8.5 h overnight and nothing showed it;
  - **each lane's latest message**: the lane's own most recent assistant text, one or two lines, beside the last
    actions (which are tool steps, not what the lane said).
- **Failure is fail-safe:** a failing `lane-status` call shows "status unavailable" and changes nothing; a refused
  answer shows `lane-answer`'s refusal text verbatim.

## Scope
1. **Packaging spike first (read before building):** verify on the current Claude Code build how a marketplace
   plugin ships a function-hooks module (`hooks/hooks.json` with `"modules"`), that a normal install loads it with no
   hot-reload step, and what `claude plugin validate` and `claude plugin test` check for it. Record the findings in
   this file. If a normal install cannot load a module, stop and report instead of working around it.
2. **The plugin:** `loomwright-lanes/` with `.claude-plugin/plugin.json`, `hooks/hooks.json`, `hooks/register.tsx`,
   `types/index.d.ts` (the `$.state` contract), `README.md` (what it is, that it is optional, the plain fallback:
   `lane-status --watch` + answering in the main session). Ported from the w1 prototype with the harness calls
   replaced by item 05's commands. No absolute paths: the core scripts are found through the installed Loomwright
   plugin's root or `PATH` (decide in step 1; never this repo's `scripts/`).
3. **Marketplace + docs:** add the plugin to `.claude-plugin/marketplace.json`; update the surfaces that enumerate
   the sibling plugins (`CLAUDE.md` §"Plugin Layout", `README.md`, `.claude-plugin/README.md`) and anything
   `scripts/check-doc-currency.sh` counts.
4. **Vendor coupling:** the plugin is Claude adapter code; record it in `loomwright/docs/vendor-coupling-manifest.json`
   the way the ratchet requires, so it is counted, not hidden.
5. **Tests:**
   - a static test (`scripts/test-lanes-addon.sh`): the module's every `$.process.run` argv starts with
     `lane-status`, `lane-feed` or `lane-answer` (no other command, no lane file paths); `claude plugin validate` passes
     where `claude` is available (skip with a stated reason in CI if not, never a silent pass);
   - **the P9 test, required:** item 05's lane round trip (launch → question → answer by file / main session →
     resume → park) passes with the add-on NOT installed, and the core suites run with no add-on loaded (P9 rule 7);
   - a fixture `lane-status --json` with a waiting lane renders the question with its exact option labels.

## Non-goals
- No new lane behaviour, no state, no merge actions (P1, P5). No pane for other harnesses (P9: they use the plain view).
- Not the Floor (`/ui`): the Floor is a browser run view; this is an in-session pane. They may later share
  `lane-status --json`.

## Acceptance criteria
- Installing `loomwright-lanes` from the marketplace in a fresh session gives a working `/lanes` pane over a real
  two-lane run; uninstalling it changes nothing about that run.
- `grep` over the plugin shows no read of lane files and no command other than the three core lane commands.
- (2026-10-06) A fixture `lane-status --json` renders the machine-health line (incl. the HIGH-LOAD alert on
  `overloaded`), a wait time on each pending question, and each lane's latest message.

## Validation (must pass before merge)
1. Baseline full loop on base and branch, `<passed>/<total>` and `SKIP` counts.
2. Unchanged path: Loomwright's own suites and `check-vendor-coupling.sh` pass with the add-on absent.
3. Running system: a real two-lane wave; paste the pane (screenshot or text render) with one lane waiting, the answer
   sent through it, and the lane's answer file showing `via: lanes-addon`.
4. A failure this must catch: a module change that reads a lane's run file directly ⇒ the static test fails.
5. Rollback: remove the plugin from the marketplace (`git revert`); nothing else depends on it.

## Verified premises (re-check before starting)
- Marketplace today lists three plugins (`loomwright`, `stackpack`, `mysql-mcp`) in `.claude-plugin/marketplace.json`.
- The w1 prototype: `~/.claude/dev-mods/07b3f63c-0dc0-4bf9-82c3-1b14ef791064/lanes/` (validated with
  `claude plugin validate`, 2026-10-04); the S1 v1 original: `~/.claude/dev-mods/0d556d54-…/s1-lanes/`.
- Later prototypes (2026-10-11 inventory, all session-private dev mods): `lanes` v0.4.0 (`2216aefd…`, the most
  complete UI — machine line, wait times, latest message — still on `s1h.sh` by absolute path), `automate-lanes`
  (`3066b7d2…`), `lanes-panel` (`a5b28c91…`, `f090e7f3…` — read-only, parses `lane-status` TEXT output, finds
  helpers by globbing the plugin cache). The add-on ports v0.4.0's UI onto item 05's commands.

## Evidence
S1 run record (v1 mod written, v2 repointed and loaded, visibility test) and wave w1 (owner used `/lanes`, asked for
details, live tracking, and this item).

## Depends on
05

## Touches
loomwright-lanes/.claude-plugin/plugin.json
loomwright-lanes/hooks/hooks.json
loomwright-lanes/hooks/register.tsx
loomwright-lanes/types/index.d.ts
loomwright-lanes/README.md
.claude-plugin/marketplace.json
.claude-plugin/README.md
README.md
CLAUDE.md
scripts/check-doc-currency.sh
scripts/test-lanes-addon.sh
loomwright/docs/vendor-coupling-manifest.json
changelog.d/parallel-automate-14-lanes-pane-addon.md

## Owner-run checks resolved (owner decision 2026-10-12)
- **Check 1 (Acceptance 1 / Validation 3): verified in a real run, uninstall step waived by the owner.** During wave W4 (run automate-2026-10-11-182243, 2026-10-11) the owner opened `/lanes` over a real two-lane wave and answered lane L2's Launch Pad save question through the pane; the lane's answer file `.supervisor/inbox/answers/toolu_01GFZ9J9QfkhXBtFYSWNPnNt.json` read `"source":"human","via":"lanes-addon","at":"2026-10-11T13:05:07Z"` (read by the coordinator at the time) and the lane resumed and shipped (#479). The uninstall-and-confirm step was not run; the no-dependency property stays enforced by `scripts/test-lanes-addon.sh` in CI.
- **Check 2 (Validation 1 base-vs-branch baseline): superseded** — #472 merged 2026-10-11 (a8b5654) and every later `main` CI run is green.

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-12T05:21:05Z
- **Brief:** none (direct implementation outside /automate)
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/472
