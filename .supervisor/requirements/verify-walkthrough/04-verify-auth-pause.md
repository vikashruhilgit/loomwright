# 04 — Auth: pause for a human sign-in, save the session, resume

## Problem
The owner's ask includes "ask and save if any login is required". Two hard constraints shape this: the plugin
never handles credentials (V8 — the harness forbids typing passwords, and the design must not want to), and
qa-executor is a subagent with no `AskUserQuestion` — it can only warn (today it logs "OAuth/SSO detected.
Crawl will be unauthenticated only" and continues). An unauthenticated walkthrough of an authenticated AC is a
`BLOCKED`, not a verdict — so without this item most real tickets block.

## Goal
When a run needs a session it does not have, it parks with a named reason; the human signs in themselves in a
headed browser; Playwright saves the storage state; the run resumes and reuses it until it expires.

## Scope
1. **Detection** (in the `--verify` mode, before the first AC): `verify-env.sh auth-probe` — if the 01
   contract says `auth.method: none`, skip. Else GET `probe_path` with the storage state file if present:
   `authenticated` ⇒ continue; file absent or `anonymous` ⇒ append an `auth: needs_auth` line, emit
   `VERIFY_RESULT` with `status: paused`, `pause_reason: needs_auth`, and return. Mid-run: a 401/302-to-login
   on any AC step ⇒ `auth: expired`, the AC is `BLOCKED (ENVIRONMENT_ISSUE, session_expired)`, run pauses the
   same way — never continues anonymously and never reports the remaining ACs.
2. **The human step** (command layer, `commands/verify.md`): on `pause_reason: needs_auth` the command prints
   ONE exact instruction — `npx playwright codegen --save-storage=<auth.storage_state_path> <base_url>` (the
   path and URL from the contract), "sign in, close the window", then `/verify --resume <run_id>`. The
   plugin never opens a browser for the human, never reads the fields they type, never stores anything but
   the file Playwright wrote. `.gitignore` guidance: the command checks whether `storage_state_path` is
   ignored and warns by name if not (it contains session cookies).
3. **`/verify --resume <run_id>`**: re-runs `auth-probe`; `authenticated` ⇒ appends `resume` and continues
   with the first AC that has no verdict line (derive from `evidence.jsonl`, never from a counter);
   still `anonymous` ⇒ prints the same instruction again, no new run dir.
4. **Fixture app** for tests: a tiny server with `/login` (sets a cookie on any POST), `/probe` (200 with
   the cookie, 302 without), `/protected` page. Tests: absent state file ⇒ `needs_auth` and ZERO `ac` lines;
   a state file with the cookie ⇒ probe `authenticated` and the AC runs; a state file whose cookie the server
   rejects ⇒ `expired`, `BLOCKED` with `session_expired`, paused — mutation control: remove the mid-run 302
   check and the expired case must fail; `--resume` continues at the first unverdicted AC (fixture with AC-1
   already PASS in the log).

## Non-goals
No OAuth automation, no credential storage, no headless login, no "test account" provisioning — a project that
needs a seeded test user declares it in the 01 `seed` command and signs in as that user by hand. No change to
qa-executor's non-verify auth warning.

## Acceptance criteria
- With `auth.method: storage_state` and no state file, `/verify` writes `auth: needs_auth`, no `ac` line, and
  prints the codegen instruction with the contract's real path and URL.
- `grep -rn 'password\|credential' skills/verify-walkthrough commands/verify.md agents/qa-executor.md` finds
  only negative assertions ("never …") — the same negation-filter convention CLAUDE.md uses for the merge grep.
- An expired session mid-run produces `BLOCKED` for that AC and a paused run; no later AC has a verdict line.
- `/verify --resume` after the human signs in resumes at the first AC without a verdict and finishes; the
  summary shows every AC exactly once.
- The storage-state file is never copied, logged, or appended into `evidence.jsonl` (assert: no line contains
  the file's contents; fixture cookie value is a unique token grepped for).

## Outcomes Rubric
- Needs-auth is a named pause, never an anonymous continue
- Human signs in; the plugin only reads the file Playwright wrote
- Expiry mid-run detected and recorded as BLOCKED, not FAIL
- Resume position derived from evidence lines
- No credential ever touches the plugin's files or logs

## Status: pending

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-09-15T14:20:00Z
- **Brief:** .supervisor/jobs/done/2026-09-15-verify-auth-pause.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/226
