# 07 — Migration announcement and release: this is a user-facing breaking change

**Depends on:** 04, 05, 06. Runs last.

## Problem — after slice 04 a working command silently stops existing

Anyone who has `loomwright@atelier` installed and types `/qa-executor` or `/qa-strategist` gets
nothing. There is no deprecation shim, no redirect, and no error explaining why: the command file is
simply gone from the plugin they installed. Two agents, two commands, and five skills leave a plugin
users already have.

This is a **breaking change**, and the plugin's own conventions make it easy to under-announce:

- `plugin.json` / `marketplace.json` `description` is an **anti-rebloat summary** — counts and the
  version string are edited **in place**, never appended to. So the description cannot carry the
  migration story.
- `CLAUDE.md` keeps only a **one-paragraph** latest-change summary and is explicitly forbidden from
  restating version numbers or counts.
- Therefore `CHANGELOG.md` and the READMEs are the **only** surfaces that can carry the real notice,
  and a user who reads neither will simply find a broken command.

## Goal

Ship the release: version bumps, changelog entries for both plugins, README migration notes, and a
recovery path a user can actually follow when `/qa-executor` stops responding.

## Scope

### 1. Version bumps

- **loomwright** — a **minor** bump at minimum. Removing 2 agents, 2 commands, and 5 skills is a
  capability removal; the version must move enough that a user comparing versions sees it. Recommend
  a minor bump with the breaking change stated at the very top of the entry. If the project's
  convention would ordinarily treat this as major, follow the convention rather than this brief.
- **selvedge** — `1.0.0` (first real release; 02 created the manifest at 1.0.0 with no content).
- `validate-version.sh` keeps `plugin.json` ↔ `marketplace.json` aligned for both.

### 2. `CHANGELOG.md`

The full narrative lives here — it is the only place that can hold it:

- What moved, and the exact new install command.
- **What a user must do:** `/plugin install selvedge@atelier` to keep `/qa-executor` and
  `/qa-strategist`.
- **Capability changes recorded honestly**, per 03's decisions: whether `/dreaming --agent
  qa-executor` still works, and whether QA telemetry is still collected. If either was retired,
  **say so plainly** — a removal discovered later by a confused user is worse than one announced.
- **The agent-memory migration step from 06**, for users with a populated
  `.claude/agent-memory/loomwright-loomwright-qa-executor/` store. It is local-only and gitignored, so
  it will never migrate itself and no clone carries it.
- Any `${CLAUDE_PLUGIN_ROOT}` / cross-plugin behaviour from 01 that changes what users can do.

Decide whether selvedge gets its **own** `CHANGELOG.md` or is covered in loomwright's. `stackpack`'s
precedent is worth checking before choosing — follow it if it exists, and record the choice if it
does not.

### 3. READMEs

- **`README.md`** (root, user-facing) — §"The 14 Agents" retitles and loses 2 rows; the QA workflow
  sections either move or become "provided by selvedge"; add a short **Migration** section near the
  top of the current release notes.
- **`.claude-plugin/README.md`** — same treatment (20 QA refs).
- **`selvedge/README.md`** — the QA docs' new home: what the two agents do, the debate loop, the
  companion requirement, and the back-pointers 05 established.

Both root READMEs are `check-doc-currency.sh` surfaces — their counts were fixed in 04; this slice
fixes their *story*.

### 4. Marketplace + plugin descriptions

Update **in place**: loomwright's description loses the QA clause and carries the new counts;
selvedge's gains a real one-sentence description with its counts. **Never append another version
clause** — that is the documented anti-rebloat rule, and both files carry the same string so they must
be edited together.

### 5. Install-both smoke test

Fresh `/plugin uninstall` + `/plugin install` of **both** plugins, then verify:
`/agent-help` lists 12 loomwright agents; `/qa-executor` and `/qa-strategist` resolve via selvedge; a
real QA run completes and its `QA_RESULT` is validated by selvedge's hook. Record the output in the PR.

Watch the desktop-vs-CLI install-location trap: do **not** diagnose the active plugin version from
`~/.claude/plugins/cache/` — that is the CLI store and holds stale leftovers; the desktop app tracks
its own version in its plugin panel.

## Constraints / invariants

- **`description` is a summary, not a changelog.** Edit in place; no appended version clause.
- **`CLAUDE.md`'s latest-change banner carries no version string and no counts** — both already live
  in `plugin.json` and `CHANGELOG.md`, and a hand-maintained copy there goes stale silently.
- **State removals plainly.** If `/dreaming --agent qa-executor` or QA telemetry was retired, the
  changelog says so in the user's language. Under-announcing a removal to keep the entry tidy is the
  failure mode this slice exists to prevent.
- **Verify install state; never assert it.** The smoke test is run, and its output attached. "It
  should work" is not evidence.
- Counts are already correct from 04 — if any count changes in this slice, something upstream was
  wrong; stop and fix it there rather than patching the number here.

## Acceptance criteria

- [ ] loomwright version bumped (minor at minimum) and swept in place across all 9 doc-currency
      surfaces; selvedge at `1.0.0`; `validate-version.sh` + `--self-test` green.
- [ ] `CHANGELOG.md` entry states the breaking change **first**, gives the exact
      `/plugin install selvedge@atelier` recovery step, and records every capability change from 03
      (dreaming, telemetry) explicitly rather than by omission.
- [ ] The 06 agent-memory migration step is in the changelog, flagged as **local-only and gitignored**
      so users understand it will not happen automatically.
- [ ] Selvedge changelog question decided (own file vs covered in loomwright's), with the choice
      recorded and the stackpack precedent checked first.
- [ ] `README.md` and `.claude-plugin/README.md` reflect the post-split agent inventory and carry a
      short, findable Migration section; `selvedge/README.md` is the QA docs' real home.
- [ ] Descriptions in `loomwright/.claude-plugin/plugin.json`,
      `selvedge/.claude-plugin/plugin.json`, and both `marketplace.json` entries updated **in place**,
      counts correct, **no** appended version clause (diff-verified).
- [ ] `CLAUDE.md` latest-change banner updated with **no** version string and **no** counts.
- [ ] Install-both smoke test executed with output attached: 12 loomwright agents in `/agent-help`,
      both QA commands resolving via selvedge, and a real QA run whose `QA_RESULT` the selvedge hook
      validates.
- [ ] Repo-wide grep confirms no user-facing surface still tells a user to reach QA through
      loomwright.
- [ ] Full CI green for both plugins.

## Out of scope

Any code or file relocation. Any count change. A deprecation shim in loomwright — explicitly **not**
built: a stub command whose only job is to print "install selvedge" is a permanent surface with no
retirement plan, and it would reintroduce a QA reference into the plugin this queue just cleaned. The
changelog and README are the announcement. **Record this rejection with its reason**, so it is not
re-proposed as an oversight.

## Outcomes Rubric

- The breaking change is announced where users will actually find it, with an exact recovery command
- Capability removals from 03 stated plainly, never softened by omission
- The local-only memory-migration step reaches users — the only channel it has
- Descriptions edited in place; anti-rebloat and the no-counts CLAUDE.md banner rule both honoured
- Both plugins installed fresh and exercised end-to-end, with output attached as evidence
- The no-shim decision recorded with its reasoning rather than left as an apparent oversight


## Status: done_with_escalation — ABANDONED (owner dropped the selvedge extraction track 2026-08-22)
- **Evidence:** `.supervisor/automate/automate-2026-08-18-124023.md` (queue rows 04–07 "abandoned: owner dropped the selvedge extraction track on 2026-08-22; not pursued"); PR #157 CLOSED unmerged; branch `feature/relocate-qa-to-selvedge` retained on origin.
- **Why this stamp:** `is_done()` in automate-helpers.sh honours only `done` / `done_with_escalation`, so this is the only marker that keeps `/automate` from re-enqueuing a dropped item. Slices 01–03 DID merge (#153/#155/#156) and are stamped done separately.
- **Reconciled:** 2026-09-21 by hand.
