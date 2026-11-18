# Quick start timing

How long [the README's Quick start](../README.md#quick-start) takes, from nothing to a first verdict
on the bundled sample app. The target is **15 minutes or less** from a fresh account, with no vendor
sign-up beyond the user's existing Claude login.

Two runs are recorded. The first is a **rehearsal** by the implementing agent on the maintainer's
Mac, with a fresh `HOME`: it times the commands and found what the README got wrong. It is not a
fresh account and does not count as the 15-minute result. The second is the **owner's run** on a
fresh macOS user account; only that run decides whether the target is met.

Neither run used any vendor account or key other than the existing Claude login: no Playwright, npm
or browser sign-up, no API key.

## Rehearsal (worker, fresh HOME)

- **Date:** 2026-11-18 (started 05:38:07 UTC)
- **Machine:** `uname -sm`: `Darwin arm64`; macOS 26.6.2; Node.js 24.11.1; git 2.54.0 (Apple
  Git-157, `/usr/bin/git`); Claude Code 2.1.325
- **Selvedge:** `selvedge --version` printed `selvedge 0.7.0` (observed on that date)
- **Fresh:** a new empty `HOME` (a temp folder), so an empty npm cache (`npm_config_cache` inside it),
  an empty Playwright browser cache (Playwright's default, `$HOME/Library/Caches/ms-playwright`,
  inside it), no `~/.local/bin/selvedge`, no `~/.claude/selvedge/approvals.json`, no installed
  plugin and no `atelier` marketplace. Every command ran under `env -i` with only that `HOME`, `PATH`,
  `USER`, `TERM`, `LANG` and `TMPDIR`.
- **How it was timed:** `date +%s` before and after each command, by a script that ran the README's
  commands in order. The seconds are the commands' own run time. **They do not include a person
  reading the README, typing, or switching terminals**, which a script does not do; the owner's run
  measures that.

| # | README step | Command | Seconds | Result |
|---|---|---|---|---|
| 1 | Install the plugin | `claude plugin marketplace add <this checkout>` (see "Not fresh") | 1 | ok |
| 1 | Install the plugin | `claude plugin install selvedge@atelier` | 0 | ok |
| 2 | CLI on `PATH` | `~/.claude/plugins/cache/atelier/selvedge/*/bin/selvedge install-cli` | 1 | ok |
| 2 | CLI on `PATH` | `selvedge --version` | 0 | `selvedge 0.7.0` |
| 3 | Demo folder | `mkdir selvedge-demo && cd selvedge-demo` | 0 | ok |
| 3 | Demo folder | `git init` | 0 | ok |
| 3 | Demo folder | `npm init -y` | 0 | ok |
| 3 | Demo folder | `npm i -D playwright` | 2 | `added 2 packages` (playwright 1.65.1) |
| 4 | Chromium | `npx playwright install chromium` | 26 | ok: 191.9 + 100.8 + 1.4 MiB downloaded |
| 5 | `selvedge.json` | `selvedge env init --port 4173` | 0 | ok |
| 6 | Doctor | `selvedge doctor` | 1 | six `ok` lines, exit 0 |
| 7 | Sample app | `selvedge sample-app --port 4173` (background) | 0 to the `serving on` line | ok |
| 8 | Verify | `… \| selvedge criteria from-text > criteria.json` | 0 | 3 criteria |
| 8 | Verify | `run_dir="$(selvedge plan criteria.json)" && selvedge run "$run_dir"`, first try | 1 | exit 2 `planner_failed` (see below) |
| 8 | Verify | the same, after the fix below | 31 | exit 0; planner 144162 tokens in / 2247 out |
| 9 | Verdict | read from `run`'s output and `verdict.json` | 0 | `PASS` ×3, `verdict PASS` |

**Total, as measured:** 63 seconds of command time (the sum of the rows above, the failed first
try included). The download in step 4 dominated (26 s for about 294 MiB), then the planner in
step 8 (most of the 31 s). This is well under 15 minutes, but it is command time on a fast network
with no human in the loop, so it is **not** evidence for the 15-minute target; the owner's run is.

**Where the README was wrong or unclear, and the fix made:**

1. **A fresh account has no `atelier` marketplace,** so `/plugin install selvedge@atelier` alone
   fails there. Fix: step 1 now starts with `/plugin marketplace add vikashruhilgit/loomwright`.
   (Found while writing the quick start, before the timed run.)
2. **The Chromium download size was wrong.** The draft said about 150 MB; `npx playwright install
   chromium` downloaded three things, 191.9 + 100.8 + 1.4 MiB (Chrome for Testing, its headless
   shell, FFmpeg). Fix: step 4 says about 300 MB and shows the `… downloaded to …` lines.
3. **`selvedge env init` prints two lines, not one.** The first is `selvedge env: added .selvedge/
   to …/.gitignore`. Fix: step 5 shows both.
4. **`install-cli` also prints the re-run-after-update note.** Fix: step 2's expected output says so.
5. **The terminal chain prints progress on stderr before the verdict lines.** Fix: the "Without
   Claude Code's slash command" block's expected output says so.
6. **The draft said "in about 15 minutes"** as if measured. Fix: the intro calls 15 minutes the
   target and points here.
7. **`/selvedge:verify` asks to approve the verifier's commands** in an interactive session. Fix:
   step 8 says to approve its `selvedge` commands. (Not observed in this rehearsal: see below.)

**Not fresh in this rehearsal:**

- **The Claude login and Claude Code itself** were already installed on this Mac. The fresh `HOME`
  has no login, so the default planner's `claude -p` stopped with `Not logged in · Please run
  /login` and `selvedge plan` exited 2 `planner_failed` (the first step-8 row). For the retry, a
  wrapper ran only the `claude` process with the real `HOME` (where the login lives), with
  `PLAYWRIGHT_BROWSERS_PATH` pointed at the fresh `HOME`'s browser cache so the planner's
  `selvedge snapshot` calls used the browser downloaded in step 4. That `claude` process therefore
  also saw the maintainer's own Claude Code settings. Everything else ran in the fresh `HOME`.
- **Node.js, npm and git** were already installed (Node through nvm, git the system's
  `/usr/bin/git`). Homebrew is installed on this Mac but was not on the rehearsal's `PATH`.
- **The marketplace was this checkout,** added by path (`claude plugin marketplace add <checkout>`),
  not `vikashruhilgit/loomwright` from GitHub: the version under test (with `doctor` and
  `sample-app`) is not on GitHub's `main` until this change merges. A GitHub add also downloads the
  repository, so it takes longer than the 1 s measured here.
- **Step 1 ran as the `claude plugin …` shell commands,** not the `/plugin …` session commands the
  README shows (they do the same thing; the session form needs an interactive session).
- **`$HOME/.local/bin` was already on `PATH`** for every command, so `install-cli`'s "is not on your
  PATH" note and the `export PATH=…` line in step 2 were not exercised.
- **Steps 8 and 9 used the equivalent CLI commands, not `/selvedge:verify`:**
  `selvedge criteria from-text` → `selvedge plan` (which runs the planner and freezes the plan) →
  `selvedge run` (which writes `verdict.json`; `selvedge verdict` re-derives the same file). The
  slash command was not attempted headless: under `claude -p` nobody can answer the verifier's
  permission prompts, and the fresh `HOME` has no Claude login or plugin settings for it. The
  owner's run covers `/selvedge:verify` itself, including its verdict table.
- **The network** was this office connection (about 11 MiB/s for the browser download).

## Owner run (fresh macOS account)

Status: pending owner run — the owner fills this section in on a fresh macOS account before merging

- **Date:**
- **Machine:** `uname -sm`; macOS version; Node.js version
- **Fresh:** a new macOS user account; what was installed before step 1 (Node.js, git, Claude Code
  and its login)

| # | README step | Command | Seconds | Result |
|---|---|---|---|---|
| 1 | Install the plugin | `/plugin marketplace add vikashruhilgit/loomwright` | | |
| 1 | Install the plugin | `/plugin install selvedge@atelier` | | |
| 2 | CLI on `PATH` | `~/.claude/plugins/cache/atelier/selvedge/*/bin/selvedge install-cli` | | |
| 2 | CLI on `PATH` | `export PATH="$HOME/.local/bin:$PATH"` (if asked), `selvedge --version` | | |
| 3 | Demo folder | `mkdir selvedge-demo && cd selvedge-demo`, `git init`, `npm init -y` | | |
| 3 | Demo folder | `npm i -D playwright` | | |
| 4 | Chromium | `npx playwright install chromium` | | |
| 5 | `selvedge.json` | `selvedge env init --port 4173` | | |
| 6 | Doctor | `selvedge doctor` | | |
| 7 | Sample app | `selvedge sample-app --port 4173` (second terminal) | | |
| 8 | Verify | `/selvedge:verify` with the three criteria | | |
| 9 | Verdict | read the verdict table | | |

**Total (wall clock, reading and typing included):**

**Where the README was wrong or unclear, and the fix made:**

**Not fresh:**
