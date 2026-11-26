# Selvedge setup scout learns the app and asks only what it can't find

## Status: pending

**As a** developer adding Selvedge to any web app, and coming back to it months later,
**I want** one command that looks through my repo and my running app, works out the settings Selvedge needs, and asks me only what it could not find out, in plain words with a suggested answer,
**so that** I don't have to learn `selvedge.json` to start, and the settings keep up as the app changes.

## Why now
Selvedge's settings are written by hand or by `env init`, which asks only for a port. The new `read_only` and `ready` keys, the sign-in check and the planner's knowledge of the app's pages all need someone who knows the app. Nothing notices when the app changes underneath them: a moved health route, a new sign-in page, a renamed page. The owner asked (2026-11-23) for one agent that checks the app thoroughly, gathers what is needed, and asks in a way users can easily understand.

## Acceptance Criteria

**First run (`/selvedge:setup`)**
- [ ] Given a repo with no `selvedge.json`, when the user runs `/selvedge:setup`, then a scout agent reads the repo (framework, dev port, routes, sign-in page) and, when the app is running, the app through `selvedge snapshot`, so every page it opens goes through the browser guard.
- [ ] The scout finds, with the evidence for each: the origin and port, a ready URL (the health paths `env init` tries), the pages that exist, the sign-in page and a signed-in marker, and the API calls the main actions send (the snapshot's request list).
- [ ] The scout reads env and config files for key names and host values only (for example `DB_HOST=zqa-rds…`). It never reads or copies a password, token or key value. When a database host is not local, it says so as the reason for its `read_only` suggestion.
- [ ] Only what it could not decide becomes a question. Each question is one plain sentence, names what was found and why it matters, offers a suggested answer first, and is asked by the command on the main thread, never by the scout. A subagent cannot ask the user, so the scout returns its questions.
- [ ] The user sees one summary before anything is written: what was found, the proposed `selvedge.json`, and the answers given. Nothing is written without a yes.
- [ ] On yes, the settings that affect safety (`origins`, `read_only`, `ready`, the sign-in check) are written to `selvedge.json` for the user to commit. The planner hints (pages, which page shows a list or a count, API calls seen) go to an uncommitted `.selvedge/profile.json`.
- [ ] Hooks (`seed`, `reset`, `auth_setup`) are only proposed as text. Approving them stays with `selvedge env approve`, which needs a terminal.

**Later runs (the checkup)**
- [ ] Given an existing `selvedge.json`, when the user runs `/selvedge:setup` again, then the scout compares what it finds now with the file and shows only the differences as proposed edits (for example "the health URL moved from `/health` to `/api/health`"). Settings that still match are not asked about again.
- [ ] The checkup reads `.selvedge/runs.jsonl` and turns repeated patterns into suggestions, each with the runs it saw:
  - a plan that used to pass now failing a step: the app probably changed, so make a fresh plan;
  - repeated `needs_auth`: the sign-in check is probably stale;
  - repeated `side_effect_not_observable` notes naming status codes: use a response read.
- [ ] `.selvedge/profile.json` is rebuilt on every run. The planner reads it when present and works as today when it is absent.

**Edge and error cases**
- [ ] Given the app is not running, then the scout says so, does the repo-only part, and lists what it could not check.
- [ ] Given a running app whose origin is remote, then the scout explores only with GET, and only after the user confirms the origin.
- [ ] Given a non-interactive run, or the command's question tool missing, then nothing is written and the output ends with the open questions and `setup: needs_owner (<n> questions)`.
- [ ] The scout never changes a frozen plan or a run folder, and never applies a fix on its own.

## Non-goals
- Self-healing plans or locators (ruled out in the qa-split plan, §7).
- Native, mobile or desktop apps.
- Approving hooks, or writing `selvedge.json` without the user's yes.
- A model in `selvedge run` (the scout runs only at setup time).

## Owner decisions
- 2026-11-23 (/product-owner session): split storage. Safety settings go in the committed `selvedge.json` as proposed edits the user approves. Planner hints go in a rebuilt, uncommitted `.selvedge/profile.json`.
- 2026-11-23 (/product-owner session): the scout may read env and config files for key names and hostnames only, never secret values, and never copies values into a file.
- 2026-11-23 (/product-owner session): new configs get `read_only: true` unless the user says the data is disposable (enforced by the read-only story).

## Priority: Phase 2
**Rationale:** It depends on the response read (for API calls) and on the `read_only` / `ready` keys. It is a larger design. The accuracy gate should be in reach before setup gets polish, but the scout is what makes Selvedge usable on an app without reading the README.

## Assumptions
- The scout runs as a Selvedge plugin agent with Bash and Read only, like `agents/verifier.md`, and is spawned by a new `commands/setup.md` that owns the questions.
- `.selvedge/` is already gitignored by `env init`, so `profile.json` is never committed.
- The honest limit carries over: an agent with shell access can read any file the user can. The hostnames-only rule is an instruction and a test of what the scout writes, not a sandbox.

## Dependencies
- Depends on: the response-read story (snapshot request list), the read-only and ready story (the keys it proposes)
- Blocks: none

## Risks
- Questions creep back in. Mitigated by the AC that a found setting is never asked about, and by a test that counts questions on the sample app.
- A PR-controlled repo can steer the scout's suggestions. Mitigated by nothing being written without the user's yes, by `selvedge.json` being read from the base branch at run time, and by planner hints never widening `origins`.
- The scout reads an env value by mistake. Mitigated by a test that scans its output and the files it writes for the sample app's fixture secret.

## Validation (must pass before merge)
1. **Static — selvedge's own gate:** `bash selvedge/tests/run.sh` passes, with a new `tests/test-setup.sh`:
   - the scout, driven by a stub planner on the sample app, proposes `origins`, `ready` and `read_only`;
   - the fixture `.env` secret value never appears in its output, `selvedge.json` or `profile.json`;
   - a second run after changing the sample app's health path proposes exactly that one edit;
   - non-interactive ends with `setup: needs_owner`.
2. **Running system — a real app:** `/selvedge:setup` in a fresh checkout of sports-management, run locally, reaches a proposed `selvedge.json` with at most three questions. The questions, and the time taken, go in the story's PR description.

## Depends on
2026-11-23-100810-selvedge-reads-the-response-an-action-caused.md
2026-11-23-100810-selvedge-read-only-mode-and-ready-check.md

## Touches
selvedge/commands/setup.md
selvedge/agents/scout.md
selvedge/skills/SKILLS_INDEX.md
selvedge/lib/env.mjs
selvedge/lib/plan-planner.mjs
selvedge/prompts/planner.md
selvedge/bin/selvedge
selvedge/README.md
selvedge/tests/test-setup.sh
selvedge/tests/run.sh
selvedge/tests/fixtures/app-server.mjs
selvedge/CHANGELOG.md
selvedge/.claude-plugin/plugin.json
.claude-plugin/marketplace.json
