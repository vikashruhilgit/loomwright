# 04 — Branch mode: briefs that pass the scrub, and an M1 step 1 that matches the shipped `meta-sync.sh`

## Depends on
none

## Touches
loomwright/skills/supervisor-readiness/SKILL.md
loomwright/agents/launch-pad.md
loomwright/commands/launch-pad.md
loomwright/skills/agent-output/SKILL.md
loomwright/agents/orchestrator.md
loomwright/agents/supervisor.md
loomwright/commands/orchestrator.md
loomwright/commands/supervisor.md
loomwright/commands/code-reviewer.md
loomwright/commands/product-owner.md
loomwright/docs/SPIKES/LOOP_EVIDENCE_2026-07.md
changelog.d/meta-sync-followups-04-scrub-safe-briefs-and-push-rehearsal.md

## Notes on the touched files (conditions moved out of the machine-read section)
- `supervisor-readiness/SKILL.md`: the brief template's `- **Project:**` line.
- agents/commands/skills: their `/Users/<name>/...` examples (the acceptance grep also hits orchestrator, supervisor, code-reviewer and product-owner, so they are listed).
- `meta-sync.sh` + `test-meta-sync.sh` were listed for option B only; the owner chose A (2026-10-05), so they are no longer touched.
- Metadata-branch edits, not part of the code PR: `parallel-automate/operator-run/M1-migrate-this-repo.md` step 1 (and the runbook convention).
- PRs #334 and #347 dropped from Depends (both merged).
- `docs/SPIKES/LOOP_EVIDENCE_2026-07.md` added 2026-10-05 (owner, at #391's park): its one real absolute home path
  rewritten to `~/` on #391 (`1f0571b`). The other two "Not verified" leftovers went to `09` (schema/fixture
  placeholders, overlaps af/32) and `10` (anchor the `home_path` regex, overlaps ms/08).

## Problem
Found 2026-10-02 while preparing operator M1, by rehearsing `meta-sync.sh init` + `push` from a scratch clone against a local bare remote (nothing reached GitHub).

1. **New briefs will trip the scrub.** The brief template asks for `- **Project:** {absolute path}` (`skills/supervisor-readiness/SKILL.md`), and the Launch Pad / agent-output examples show `/Users/<name>/...`. `meta-sync.sh push` fails closed on `home_path` (`/(Users|home)/<name>/`). Most of the 150 done briefs on `main` wrote `~/...` anyway, but 3 recent ones wrote the absolute path. With branch mode on, every such brief makes the trail push exit 2, so the done brief, stamp and run file of that item never reach `loomwright-meta` — and M1's own Verify step (one real `/automate` cycle landing on the branch) passes or fails depending on how the brief happened to be written.
2. **M1 step 1 names a flag that does not exist.** The runbook says `meta-sync.sh push --dry-run` "(or the scrub alone)". The shipped script has neither: requirement 02 defined `init|pull|push|status` with no dry-run, and the script matches 02. The runbook was written in the same pass as 02 (`acfd7c5`) and, living in `operator-run/`, was never plan-reviewed, so nothing compared its commands to 02's interface. The scrub itself is safe without a dry-run — `push` scrubs before publishing and exits 2 with nothing pushed — but the runbook tells the operator to run a command that errors.

## Goal
A brief written from the template passes the `meta-sync.sh` scrub, and M1 step 1 is a command sequence that runs on the shipped script.

## Scope
1. **Template:** change the brief template's `- **Project:**` value to the home-relative form (`~/...`, or the repo name when not under `$HOME`), and the `/Users/<name>/...` examples in the three other files to match. Before changing, confirm nothing consumes the value as an absolute path: no script under `loomwright/scripts`/`hooks` parses it today (checked 2026-10-02 — only test fixtures carry it), but re-check the agent prompts (`context-setup` "Project path identified").
2. **M1 step 1 — OWNER CHOSE A (2026-10-05): the rehearsal recipe, no code.** (Option B is kept below for the record only.)
   - **A. Rehearsal recipe (no code).** Replace step 1 with: clone the repo into a scratch dir, `git init --bare` a scratch remote, point the clone's `origin` at it, **copy `.supervisor/config.json` into the clone** (the scrub's repo allowlist is `setup_memory.repo_allowlist` in that gitignored file — without it every forge slug is a hit, which is how the first rehearsal reported 218 false hits), then `meta-sync.sh init` + `push --root <clone>`. Iterate until `push` exits 0. Nothing is published.
   - **B. Real `--dry-run` on `push`.** Run the plan + scrub, print the candidate list and any hits, publish nothing, exit 0/2 like `push`. Needs a test leg proving nothing is pushed and the meta-base is untouched, a version bump, and a plugin reinstall before M1 can use it.
3. **Prevention (the class, not just this instance):** add one line to the runbook convention (and to M1/S1 themselves) that every command in an `operator-run/` file is checked against the shipped script's usage text before the runbook is used. Do not build a checker for two files.

## Non-goals
Cleaning the existing tracked hits on `main` — done separately (chore/meta-scrub-cleanup, 2026-10-02). Changing the scrub rules or the allowlist source.

## Acceptance criteria
- Given a brief generated from the updated template in this repo, when `meta-sync.sh push` scrubs it, then it reports no `home_path` hit.
- `grep -rn '/Users/name' loomwright/agents loomwright/commands loomwright/skills` returns nothing.
- M1 step 1 names only commands and flags that exist in `meta-sync.sh --help`; following it on a scratch clone reaches `push` exit 0 on a clean `main`.
- Option B only: a test leg shows `push --dry-run` leaves origin's branch tip and `<gitdir>/meta-base` unchanged and prints the same scrub hits as `push`.
- `bash scripts/ci-local.sh` green; plugin-file changes carry a `changelog.d/` fragment (bump via `scripts/bump-version.sh`, not by hand).

## Provenance
Owner request 2026-10-02 (session c72c09d3, resume of run automate-2026-10-01-142337): "queue step 2" after the M1 rehearsal. Rehearsal evidence: first push exit 2 with 218 hits (missing allowlist, a rehearsal artifact), second push exit 2 with 7 real hits (5 `home_path`, 2 `forge_slug` on the `acme/widgets` placeholder) — the same set the 02 brief's Feasibility #5 predicted.

## Status: pending

## Priority raised (2026-10-04, from S1 v2 — evidence on a real lane)
Lane v2-b's closeout metadata push FAILED on the scrub: `meta-push FAILED: scrub
.supervisor/jobs/done/2026-10-04-fail-to-unstamped-escalates.md: home_path`. The brief carried one absolute
`/Users/<name>/` path, and **the scrub refusing one file blocked the lane's WHOLE push**: run file, sidecars, done
stamp, check-off and postmortem line all stayed in the clone (carried by hand, with the path rewritten to `~/`). Lane
v2-a's brief had no such path and pushed fine. This is the brief-template half of this item (the `- **Project:**`
line and the `/Users/<name>/...` examples), and it is now a **prerequisite for `parallel-automate/05`/`06`**: at
5–10 lanes, any lane whose brief names a home path loses its closeout records. Still open: the owner's choice of
option A or B for the rehearsal half.
