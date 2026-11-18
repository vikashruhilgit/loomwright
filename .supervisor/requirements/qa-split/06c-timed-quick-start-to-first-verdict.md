# A fresh machine reaches its first verdict in 15 minutes or less, with no sign-up beyond the Claude login

## Status: done
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/939

> Phase 1, item 06c of `qa-split/00-plan.md` (rev 2, approved 2026-11-12). Product rule P1; §8 measure
> "fresh-machine time to first verdict". Last item of Phase 1 (Phase 2 measurement starts after it).

## Why

Onboarding friction is the top reason teams drop an AI QA tool after a trial (round-2 research): DevAssure
needs an OAuth login, Bug0's library needs two vendor keys plus Redis. P1 is only true if it is timed.

## Scope

- `selvedge/README.md` quick start: install the plugin → `selvedge install-cli` (if item 01's spike says
  it's needed) → `npx playwright install chromium` → `selvedge env init` on the bundled sample app (the
  item 04 fixture app, startable with one command) → `/selvedge:verify` with three example criteria → read
  the verdict. Every command copy-pasteable; expected output shown.
- A `selvedge doctor` command that checks Node, Playwright + browser, `selvedge.json`, approvals, and the
  planner (`claude` on PATH, or `SELVEDGE_PLANNER` set) and prints the one fix for each failure.
- **The timed run:** follow the README exactly on a clean macOS user account (or a fresh container for the
  CLI path), with a stopwatch, and record the result in `selvedge/docs/quick-start-timing.md`: date, machine,
  each step's time, total, every place the README was wrong or unclear, and the fix made.

## Acceptance criteria

- `quick-start-timing.md` records a total ≤ 15 minutes, from a fresh account, with no vendor sign-up other
  than the user's existing Claude login.
- `selvedge doctor` reports each missing prerequisite with a one-line fix (tested by removing each one).
- The README states the honest limits: web only, what NOT_VERIFIABLE and BLOCKED mean, D11's secret limit,
  and that accuracy numbers come only after Phase 2.

**Owner decision (2026-11-18):** the first acceptance line is met by an agent-run timed quick start on a real project (Sportify) with a fresh `HOME`, in place of a fresh macOS account; `quick-start-timing.md` says plainly that both recorded runs are command time, not a new person reading and typing.

## Depends on

06

## Touches

- `selvedge/README.md`, `selvedge/docs/quick-start-timing.md`, `selvedge/lib/doctor*`, `selvedge/tests/**`

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-11-18T08:35:10Z
- **Brief:** .supervisor/jobs/done/2026-11-18-qa-split-06c-timed-quick-start.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/939
