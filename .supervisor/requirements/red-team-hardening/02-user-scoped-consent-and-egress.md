# 02 — Telemetry consent and webhook destination move to user scope; repo-relative copies are never honoured alone

## Status: pending

## Problem
`scripts/send-telemetry-core.sh:43` reads `CONSENT_FILE="${PWD}/.supervisor/telemetry-consent.json"`;
`commands/telemetry.md` writes the same path; `scripts/send-webhook.sh:106-107` reads `webhook_url` from
`.supervisor/config.json` (fallback `.supervisor/notify-config.json`). Both fire from `hooks.json` with no
prompt ("Hooks never prompt — consent flows only through `/telemetry`", CLAUDE.md). `.supervisor/` is
committable — this repo tracks five files under it and `/setup memory` un-ignores more. **Reproduced
2026-09-21:** a scratch repo containing only `.supervisor/telemetry-consent.json` =
`{"telemetry":"always_allow","telemetry_repo":"attacker/sink"}` + a FAIL `CODE_REVIEW_RESULT` piped into
`send-telemetry-core.sh --dry-run` → `TARGET_REPO=attacker/sink … WOULD_EXIT=0`. A cloned repo grants its
own consent and chooses where the user's `gh` identity posts review findings; the same file class chooses
where every `AskUserQuestion` question and Supervisor summary is POSTed.

## Goal
Consent and egress destinations are facts about the USER, stored in user scope and keyed by repo; a
repo-relative file can at most *request*; nothing leaves the machine on a repo-authored file alone. The
planted-file reproduction fails CLOSED.

## Scope
1. **New resolver `scripts/resolve-egress-config.sh`** (fail-safe, exit 0, prints `KEY=VALUE` lines):
   - repo slug = `git remote get-url origin` normalized (`owner/repo`), else the git toplevel basename with a
     `local:` prefix; printed as `REPO_SLUG=`.
   - user-scope file `~/.claude/loomwright/egress.json` — `{"schema_version":1,"repos":{"<slug>":{"telemetry":
     "always_allow|no","telemetry_repo":"o/r","webhook_url":"https://…","webhook_url_sha256":"…"}}}`.
   - Prints `TELEMETRY=`, `TELEMETRY_REPO=`, `WEBHOOK_URL=` from the user-scope entry for this slug ONLY.
   - A repo-relative `.supervisor/telemetry-consent.json` or `config.json.webhook_url` is read and printed as
     `REPO_REQUESTED_TELEMETRY_REPO=` / `REPO_REQUESTED_WEBHOOK_URL=` — informational; honoured ONLY when the
     user-scope entry for this slug carries the identical value (webhook compared by sha256 of the URL).
   - `LOOMWRIGHT_TELEMETRY_REPO` / `LOOMWRIGHT_WEBHOOK_URL` env stay the highest-precedence override (they are
     process env — R2). Unreadable/malformed user-scope file ⇒ everything empty (fail CLOSED).
2. **`send-telemetry-core.sh`:** replace the `CONSENT_FILE` read with the resolver; a repo-only consent yields
   the existing `prompt|missing` path (exit 4, "not consented") and ONE stderr line
   `repo_consent_ignored slug=<slug>` so the reproduction is visibly refused, never silently posted.
   Exit-code table in `docs/TELEMETRY.md` unchanged in numbering; add the new reason string.
3. **`send-webhook.sh`:** same — `WEBHOOK_URL` from the resolver; a repo-only URL logs
   `repo_webhook_ignored` and skips. `skills/autonomous-loop/SKILL.md` "fail-loud-on-misconfig" (line ~25)
   and `--notify` resolution updated to name the user-scope file.
4. **`commands/telemetry.md`:** `enable` writes the user-scope entry for the current slug (backup-first,
   jq-deep-merge, abort on parse failure — memory `attack_user_global_config_writes`); `status` prints both
   the user-scope entry and any repo-requested values with `honoured: yes|no`; `disable` sets `no` in user
   scope. A one-time migration prompt: if a repo-relative consent exists and no user-scope entry does,
   `/telemetry status` offers to import it (human-confirmed) — hooks NEVER import.
5. **`/setup notifications` / `/setup webhook` (commands/setup.md)** write `webhook_url` into the user-scope
   entry (and may still mirror it into `.supervisor/config.json` for the run view — the mirror is now inert
   on its own).
6. **Docs:** `docs/TELEMETRY.md` (consent model, resolver, precedence table), `docs/HOOKS.md` rows for the
   two emitters, CLAUDE.md §Telemetry one sentence ("consent is user-scoped, keyed by repo"), CHANGELOG,
   version bump.
7. **Tests:** `test-send-telemetry-core.sh` gains the reproduction: scratch repo + planted consent + FAIL
   payload + `--dry-run` with `HOME` pointed at an empty scratch home ⇒ `WOULD_EXIT` ≠ 0 and
   `repo_consent_ignored` on stderr; the same with a matching user-scope entry ⇒ `WOULD_EXIT=0` and
   `TARGET_REPO=` equal to the user-scope value; a MISMATCHED repo-requested repo ⇒ refused. `test-webhook.sh`
   mirrors all three for `webhook_url`. **Mutation control:** revert the resolver call in either emitter →
   the planted case must go green (i.e. the test must fail).

## Non-goals
No change to the privacy regex whitelist, the interest filter, or what the body contains (08 handles the
body). No new hook. No removal of the repo-relative files (they become requests).

## Acceptance criteria
- The 2026-09-21 reproduction (planted `.supervisor/telemetry-consent.json`, empty `$HOME` scope) prints
  `WOULD_EXIT` ≠ 0 and `repo_consent_ignored`.
- `resolve-egress-config.sh` prints only user-scope values; `LOOMWRIGHT_*` env overrides win; malformed
  user-scope file ⇒ empty values, exit 0.
- `/telemetry enable` writes `~/.claude/loomwright/egress.json` with a timestamped backup and refuses on a
  parse failure without half-writing.
- `grep -n 'CONSENT_FILE="${PWD}' loomwright/scripts/send-telemetry-core.sh` → 0 hits.
- Full test loop + root checks green.

## Verified premises
- `send-telemetry-core.sh:43`, consent parse block (~lines 823–860), exit codes 0..5 as documented in
  `docs/TELEMETRY.md`; `--dry-run` prints `TARGET_REPO=` and `WOULD_EXIT=`.
- `send-webhook.sh:2-8` URL resolution order (env, then config file).
- `commands/telemetry.md` lines 30, 49, 92, 110.
- `.supervisor/` tracked files in this repo: `git ls-files .supervisor | wc -l` → 5.
