# 08 — Rules in EVERY project: `/setup rules` offers a deterministic CI job (the plugin cannot edit a user's CI)

## Status: pending

## Depends on
Item 07 (decides whether a failing check gates at all). Related: item 02 in this folder — the `claude-review`
bot's read-only sandbox. **Complementary, not overlapping:** 02 asks whether the *reviewer agent* may execute;
this item adds a *deterministic job* that executes without widening the reviewer's allowlist at all.

> **Origin (2026-09-26).** Items 05–07 all fire on plugin-driven work only. A human PR, or a plain session that
> never runs Supervisor, is unenforced everywhere. And the owner's framing was explicit: *"not only for this
> repo, wherever we use this plugin"* — so the answer cannot be "edit `ci.yml`", because the plugin runs in
> arbitrary user projects whose CI it does not own. It can only **offer**.

## Problem
Two facts that together define the shape of the fix:

1. **The stamp deliberately grants nothing in CI.** It is "per-user-per-machine (per repository on that
   machine), never shared, never committed … grants NOTHING on any other machine or in CI — every other
   human confirms once on THEIR OWN machine, or that machine's `--if-stamped` stays `unstamped` forever."
   So a CI job **cannot** authorize itself with `--if-stamped`. It will always report `unstamped`.
2. **Static review provably misses this class.** Item 02 records it: on PR #267 the `claude-review` bot
   reported **no findings** on a commit that the executing Phase 4.5 review failed with 4 HIGH findings,
   each reproduced only by running code — including *"an accepted check stored advisory and never run"* and
   *"an invalid-ERE token producing an always-pass check"*. A rule-shaped defect is exactly what reading cannot
   catch and running can.

## Goal
A user of the plugin, in their own project, can accept a one-time offer that puts the deterministic half of the
rules substrate into their own CI — with the authorization living in the workflow file they reviewed, not in a
stamp that cannot travel.

## Scope (recommendation, not pre-decided)

**(a) A new `/setup rules` CI cell**, in the module's existing check → report → offer → confirm → apply → verify
discipline. Default to NOT applying; ambiguous answer ⇒ Cancel. It writes
`.github/workflows/loomwright-rules.yml` into the **user's** project.

**(b) What the job runs.**
- `audit-rules.sh` — **unconditionally, and it needs no decision at all**: it executes nothing, so there is no
  trust question. Exit `1` findings / `2` could-not-examine, and `2` must fail the job, never pass as clean.
- `rules-check.sh` — the trust-sensitive half. **Authorization is `RULES_CHECK_CONFIRM=1` *without*
  `--if-stamped`**, which is a genuine confirm under the documented precedence chain
  (`--no-cmd` > argv `--confirm` / `RULES_CHECK_CONFIRM=1` when `--if-stamped` is absent > `--if-stamped` >
  TTY-yes > default-skip). The env var is ignored only *under* `--if-stamped` — the anti-laundering rule — so
  this is the sanctioned unattended path, not a bypass of it.

**(c) State the trust envelope in the offer, honestly, and let the user decide.** A rule's `check` is arbitrary
shell that can land via an unreviewed PR. Running it in CI is safe **only** to the extent the user's CI already
runs PR-authored code — which for most projects it does (their own test suite). The offer must say this in one
sentence rather than implying the plugin has verified anything. Recommend the workflow gate the job to
non-fork PRs, since a fork PR is the case where that assumption breaks.

**(d) Pin what the workflow checks out.** The workflow references plugin scripts, so it must pin a plugin
tag/sha rather than tracking a moving branch — otherwise a plugin release silently changes a user's CI.

**(e) This repo becomes the dogfood instance, not a special case.** Whatever the module writes for a user is
what lands in this repo's own `.github/workflows/` — so the mechanism is exercised by its author.
> **Expect a green-but-empty first run here.** A PR that modifies a workflow file makes
> `anthropics/claude-code-action` skip itself and exit 0 with no comments. Verify this item on a **follow-up
> non-workflow PR**; never assert on run conclusion alone.

## Acceptance criteria
- [ ] `/setup rules` status reports the CI cell as configured / not configured, read-only, creating nothing.
- [ ] Decline / ambiguous ⇒ nothing written; `git status --porcelain` empty.
- [ ] Accept ⇒ exactly one workflow file written, pinned per (d), and re-running the module is a no-op
      (idempotent, no second copy, no silent overwrite of a user-edited file).
- [ ] The generated workflow, run against a store with a failing `must` check, **fails the job**; against a
      clean store, passes; against a store with a `no_mechanism` finding, fails on `audit-rules.sh`.
- [ ] `audit-rules.sh` exit 2 in the job ⇒ job fails (never reported as clean).
- [ ] Mutation control: removing `RULES_CHECK_CONFIRM=1` makes the failing-check case pass vacuously
      (`skipped — needs confirmation`) — the assertion proves the confirm is load-bearing.
- [ ] `check-vendor-coupling.sh` green — the workflow template is a user-project surface; keep
      `${CLAUDE_PLUGIN_ROOT}`/cache literals out of core comments (reword neutrally, never raise the allowance).
- [ ] `check-doc-currency.sh` / `check-command-sync.sh` green — a new `/setup` module cell is a claimed surface;
      sync `commands/setup.md` prose and the module table in the same change.
- [ ] The full test loop is green — BOTH `loomwright/scripts/test-*.sh` AND root `scripts/test-*.sh`.

## Out of scope
- Sharing, syncing, or committing the user-scope stamp to make CI "stamped" — the stamp's whole design is that it
  cannot travel; reproducing it in the repo re-creates the vulnerability 08/§8.1 prevents.
- Widening the `claude-review` reviewer's `--allowed-tools` (that is item 02's question, deliberately separate).
- Any non-GitHub CI provider in this item.

## Verified premises (read at `main @ 4f681d0`, 2026-09-26)
- `skills/rules/SKILL.md` §8.1: "Deliberately per-user-per-machine (per repository on that machine), never
  shared, never committed … grants NOTHING on any other machine or in CI"; precedence chain as quoted in (b);
  "under `--if-stamped` the `RULES_CHECK_CONFIRM` env var is IGNORED — only an explicit argv `--confirm`
  confirms".
- `scripts/rules-check.sh`: exits 0 on no failures, 1 on ≥1 selected-check failure; fail-safe `Checks passed:
  0/0` + exit 0 when `jq` is absent or no rule files exist.
- `commands/rules.md` §`audit`: `audit-rules.sh` never executes a `check`, has no write mode, and exits
  `0`/`1`/`2` with 2 = could-not-examine, which "is NEVER reported as clean".
- `commands/setup.md`: `rules` is an existing module (`## Module: rules`) built on
  check → report → offer → confirm → apply → verify, defaults to NOT seeding, treats an ambiguous answer as
  Cancel, and redirects every writer invocation's stdin from `/dev/null` so no second prompt can fire.
- `.github/workflows/claude-code-review.yml` (line ~248): the reviewer's `claude_args` carries a deliberately
  read-only `--allowed-tools` allowlist; the file's own comments record that broader `Bash(...)` wildcards were
  removed on purpose.
- This folder's item 02 documents the PR #267 static-vs-executing review divergence quoted above.
