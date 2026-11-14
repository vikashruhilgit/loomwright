# Sign-in is scripted by the CLI, stored outside the repo, and never loops

## Status: pending

> Phase 1, item 05 of `qa-split/00-plan.md` (rev 2, approved 2026-11-12).
> Decision: D11 (with its honest limit). Loomwright invariant carried over: every question gate has a
> named can't-ask branch. Red-team: C5.

## Why

Agents loop at login walls and leak what they type into traces. Devin found a scripted login fixture
"decreased flakiness dramatically". The plan never contains a credential; the runner resolves `{{NAME}}`
from env at run time. Honest limit, to be written into the README: an agent with shell access can read any
file the user can. We keep secrets out of plans, evidence, PR comments and model prompts; we do not claim
they are out of reach.

## Design

- `selvedge auth setup`: runs the approved `hooks.auth_setup` (item 02 approval rules apply) with
  credentials only from env vars the user names in config (`auth.env: ["APP_USER", "APP_PASS"]`). The hook
  must write a Playwright `storageState` to the path in `$SELVEDGE_STORAGE_STATE`.
- Storage path: `~/.local/state/selvedge/<repo-id>/auth/storageState.json`, directory 0700, file 0600.
  Never inside the repo. `run` loads it when present.
- Detecting a login wall during `run`: config `auth.signed_in_check` (a URL + a locator that must exist when
  signed in). If it fails before the first criterion:
  - interactive (stdin is a TTY and not `--non-interactive`): print what is needed and wait for the human
    to sign in via `selvedge auth setup --headed`, then continue once;
  - non-interactive: every criterion BLOCKED `needs_auth`, exit 2, immediately. Never retry in a loop.
- Expired state is not refreshed silently; it's the same `needs_auth` path.

## Acceptance criteria (each a test)

- Fixture app with a login wall, non-interactive, no storage state → all BLOCKED `needs_auth`, exit 2,
  within one check (no retry loop; test asserts a single attempt).
- `auth setup` with an approved hook writes storage state at the path above with mode 0600; nothing new
  appears under the repo (`git status --porcelain` unchanged).
- With valid storage state, the walled criterion runs and PASSes.
- `evidence.jsonl`, `verdict.json` and the planner prompt contain no credential value (grep for the
  fixture password returns nothing).
- An unapproved `auth_setup` hook → BLOCKED `env_hooks_unapproved` (reuses item 02).

## Depends on

04

## Touches

- `selvedge/lib/auth*`, `selvedge/lib/runner/**` (login-wall check), `selvedge/tests/**`
- `selvedge/README.md` (the honest-limit paragraph)
