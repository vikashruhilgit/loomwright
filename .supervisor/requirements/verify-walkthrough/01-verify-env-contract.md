# 01 — Verification environment contract (`.agent/verify.json`)

## Problem
Nothing in the plugin can start the app under test, seed it, reset it, sign in to it, or prove it is not
production. `agents/qa-executor.md` Phase 3 requires the app to already be running (it `curl`s a URL it read
from `playwright.config.ts` / `.env` or asked the user for); Phase 5 only *inventories* seed data; auth is a
single `--auth-state` flag. Every `/verify` run would otherwise re-guess all five per app. The repo already has
the right shape for a committed, per-project, propose-only store: `.agent/product.json`
(`propose-product.sh` sole writer, `read-product.sh` fail-safe reader, `RESULT_SCHEMAS.md` §PRODUCT_CONTEXT,
`test-product-seam.sh`). This item is that pattern applied to the verification environment.

## Goal
A project declares once, in a committed file, how its app is started / health-checked / authenticated /
seeded / reset and how the plugin can prove the target is non-production. A reader hands that to `/verify`;
absence is announced by name and stops the run before the app is touched.

## Scope
1. **Schema — `RESULT_SCHEMAS.md` §`VERIFY_ENV`** (`.agent/verify.json`; same documented `schema_version`
   exception as PRODUCT_CONTEXT, same rationale). Required keys: `start` (shell string or `null` = already
   running), `base_url`, `health` (path or full URL that must return 2xx), `auth` (object:
   `method: none|storage_state`, `storage_state_path`, `probe_path` = a route that 401/302s when logged out),
   `non_prod_assert` (object: at least one of `base_url_matches` regex / `env_var_equals` `{name,value}`
   / `cmd` — the run refuses when NONE passes), `seed` (shell string or `null`), `reset` (shell string or
   `null`), `stop` (shell string or `null`). Optional: `ready_timeout_s` (default 60), `notes`.
   Nullable-but-required keys need a **presence** check (memory `nullable-required-field-needs-presence-check`):
   `has("seed")` with `null` is valid; a missing `seed` key is malformed.
2. **`scripts/read-verify.sh`** — advisory, fail-safe: exits 0 always; **empty stdout** when the store is
   absent / malformed / `jq` missing (reason on stderr); prints the validated object on stdout otherwise.
   Malformed = root not an object, any required key missing, `non_prod_assert` with no usable member.
   Never executes any of the shell strings — it is a reader.
3. **`scripts/propose-verify.sh`** — propose-only, `--confirm`-gated bootstrap, sole writer of
   `.agent/verify.json`, writes nothing else (creates `.agent/` if absent; same-dir temp + atomic mv). Scans
   for candidates: `package.json` scripts (`dev|start|serve`), `playwright.config.*` `baseURL`/`webServer`,
   `.env*` `APP_URL|BASE_URL|PORT`, `docker-compose*.yml`, `prisma/seed*`, `db:seed|db:reset` scripts,
   `Makefile` targets. Prints the proposal; the one field it never guesses is `non_prod_assert` — like
   `--stance` in `propose-product.sh`, it **refuses to write without an explicit `--non-prod <regex|env=NAME=VAL>`**,
   because a scanner cannot know what production looks like for this project.
4. **`scripts/verify-env.sh`** — the executor of the contract (the only thing that runs the shell strings):
   subcommands `assert-non-prod` (fail CLOSED: exit 1 + reason unless ≥1 member passes), `start` (runs
   `start` if non-null, polls `health` until 2xx or `ready_timeout_s`, prints the pid/marker), `stop`,
   `seed`, `reset`, `auth-probe` (GET `probe_path` with the storage state; prints `authenticated|anonymous`).
   Every subcommand refuses to run anything before `assert-non-prod` has passed in the same invocation.
5. **`scripts/test-verify-seam.sh`** — absent store → empty stdout + exit 0; malformed roots and each
   missing required key → empty stdout; `seed: null` valid vs `seed` missing invalid (both directions);
   `assert-non-prod` fails closed on an empty object and on a regex that does not match; `propose-verify.sh`
   without `--non-prod` writes nothing and exits non-zero; with `--non-prod` and no `--confirm` writes nothing;
   `--confirm` writes exactly one file. Mutation control: delete the presence check and the missing-`seed`
   case must fail the suite.

## Non-goals
No Playwright here. No auth handling beyond the probe (item 04). No CLAUDE.md section fallback — the store is
the contract. Does not touch qa-executor.

## Acceptance criteria
- `read-verify.sh` with no `.agent/verify.json` prints nothing on stdout, exits 0, and stderr names the path.
- A store missing any required key reads as malformed (empty stdout); a store with every key present and
  `seed: null`, `reset: null`, `start: null` reads as valid.
- `verify-env.sh assert-non-prod` against `{"non_prod_assert":{}}` exits non-zero with reason
  `non_prod_assert_empty`; against `base_url_matches: "^http://localhost"` and `base_url: "https://app.example.com"`
  exits non-zero with `non_prod_assert_failed`; a matching regex exits 0.
- `verify-env.sh start` on a fixture whose `health` never returns 2xx exits non-zero after `ready_timeout_s`
  with `health_timeout` and has run `stop`; on a fixture `python3 -m http.server` it exits 0 within the timeout.
- `propose-verify.sh` is the sole writer: a grep for `verify.json` write paths across `scripts/` finds exactly
  one `mv` target.
- Schema section exists in `RESULT_SCHEMAS.md`; `check-doc-currency.sh` green.

## Outcomes Rubric
- Store absent ⇒ announced, never guessed
- Every required key presence-checked, null-legal keys tested both ways
- `non_prod_assert` fails CLOSED and is never inferred by the scanner
- Exactly one writer, propose-only, `--confirm`-gated
- Reader never executes a contract string

## Status: done (PR #220, merge be8329b)
- **Completed:** 2026-09-14T08:05:20Z (PR merge time; stamp backfilled 2026-09-26 — it had been left `pending`)
- **Brief:** .supervisor/jobs/done/2026-09-14-verify-env-contract.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/220

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-09-14T05:24:19Z
- **Brief:** .supervisor/jobs/done/2026-09-14-verify-env-contract.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/220
