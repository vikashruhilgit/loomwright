# 05 — Provider launch parity: one launcher for `check` and `lens-run`, declared login pass-through, real permission probe

## Status: pending

**As a** maintainer who routed a read-only step to Grok or Cursor, **I want** `/setup providers` and
`setup-providers.sh check` to say "usable" only when a routed step will actually run, **so that** routing a step to a
non-Claude CLI does not fail at login on every run while every screen reports it as working.

## Verified premises (2026-10-31, owner's Mac, main @ c8fe7b4, Grok Build 1.0.70 and cursor-agent 2026.10.22 both logged in)

- **The check and the runner launch a provider two different ways.**
  - `loomwright/scripts/setup-providers.sh` runs its smoke under the REAL `HOME`; its header comment says why: "a
    scrubbed HOME breaks at least one provider's login", and its printed banner says
    `HOME: the REAL HOME (login state lives there; never scrubbed)`.
  - `loomwright/scripts/adapters/providers/lens-run.sh` runs the CLI through `lens_exec_cli`, every branch of which is
    `env -i PATH="$PATH" HOME="$SCRUB_HOME" TMPDIR="$SCRUB_HOME"` with `SCRUB_HOME` a fresh `mktemp -d`. Nothing re-adds a
    login file or key variable.
- **Result: every non-Claude routed step fails at login.**
  - `check` reports `grok … auth ok (via smoke) · headless pass · permissions pinnable => usable for write seats` and
    `cursor (cursor-agent) … auth ok · headless pass · permissions: unpinnable => usable for read-only seats`.
  - The same CLIs run with lens-run's exact `env -i` shape (empty temp HOME, cwd = that dir):
    - grok → `{"type":"error","message":"Not signed in. … set the XAI_API_KEY environment variable …"}`;
    - cursor-agent → `Error: Authentication required. Please run 'agent login' first, or set CURSOR_API_KEY …`.
  - Full lens-run path not exercised end to end: this repo has no user-scope grant, so lens-run returned
    `provider_not_granted` ("nothing was sent"), which is correct. The grant is the owner's call; the reproduction above
    uses lens-run's own launch shape.
- **`pinnable` is a help-text check, not an enforcement check.**
  - `provider-grok.sh` sets `PROBE_PERM_PIN_FLAGS="--permission-mode dontAsk --allow --deny"`; `check` grades
    `pinnable` when `grok --help` lists those tokens.
  - Hand probe in throwaway dirs, prompt "create probe.txt":
    - `grok --permission-mode dontAsk` (no allow rule) → **file written**;
    - `grok --permission-mode dontAsk --deny Write --deny Edit --deny Bash` → refused, no file.
  - So on this build `dontAsk` is not default-deny; only an explicit deny list holds.
- **Side observation (input to 04, not this item):** a Grok run under the real HOME fires this user's Claude Code plugin
  hooks. Each run left `.claude/settings.local.json` (Loomwright's SessionStart `set-otel-resource-attrs.sh`) in its cwd.

## Intended shape (re-verify against main before building)

1. **One launcher.** Move the isolated-launch logic (`env -i` allow-list env, scrubbed HOME/TMPDIR, process group,
   timeout chain) out of `lens-run.sh` into one shared helper that `lens-run.sh` AND `setup-providers.sh check`'s smoke
   both call. The smoke then answers "will a routed step run", not "does the CLI work in my shell". A guard test fails if
   either script launches a provider CLI any other way.
2. **Declared login pass-through, per provider, minimal.**
   - Each `provider-<name>.sh` may declare exactly what its login needs inside the isolated HOME: named credential
     file(s) relative to `$HOME`, and/or named env var(s).
   - The launcher copies only those, read-only, into the scrubbed HOME and removes them on exit. Copy, never symlink,
     so the CLI cannot write back through it.
   - Nothing else crosses: no `GH_TOKEN`, no other provider's key, no ambient env. Undeclared ⇒ nothing crosses (today's
     behaviour).
   - **Where each CLI keeps its login is a probe, not an assumption.** The worker reads each CLI's docs and verifies on
     this machine: Grok's `~/.grok/auth.json` is a candidate; Cursor may use the macOS keychain. A provider whose login
     cannot cross the isolation (e.g. keychain-only) gets a named verdict instead of `usable`. It is never silently
     routed.
3. **Truthful verdicts.**
   - `check` reports auth from the isolated launch. When the real-HOME login works but the isolated one does not, it says
     so with a named status (e.g. `auth: ok in your shell, fails isolated`) and a fix hint.
   - `usable for …` is never printed for a provider whose isolated smoke fails.
4. **Real permission probe for write-seat eligibility.**
   - `pinnable` requires an enforcement test: in a throwaway dir, launch with the provider's pin flags and NO allow rule,
     ask for a file write, and pass only if no file appears.
   - Help-text tokens alone grade at most `pin flags advertised (unverified)`.
   - Expected on Grok 1.0.70: fails ⇒ not `usable for write seats`.
   - The probe costs one model call per candidate provider; say so in the banner.
5. **Evidence.** Re-run `check` on this machine with grok + cursor logged in and append the new rows, plus the
   enforcement-probe outcome, to `docs/evidence/provider-routing-02-providers-probe.md`. Do not rewrite the 02 rows.

## Acceptance Criteria

- A fake provider whose CLI succeeds only when `$HOME/.fake/auth.json` exists:
  - declared → `check` says usable AND a `lens-run.sh` call with a grant succeeds;
  - undeclared → both fail, with the same named status.
- Guard test: no provider CLI launch outside the shared launcher (grep-level, like the base-branch single-resolver
  guard).
- The isolated HOME holds only the declared files; no symlinks; it is removed on exit, including on timeout.
- A fake provider that ignores its pin flags and writes anyway grades not-pinnable; one that refuses grades pinnable.
- `bash scripts/ci-local.sh --affected` green; `bash scripts/check-version-bump.sh` passes (changelog fragment).

## Owner decisions

- 2026-10-31: fix launch parity before any write-seat work; 04 parked until this ships and Grok passes the real
  permission probe.

## Depends on
03-routing-config-readonly-seats.md

## Touches
loomwright/scripts/setup-providers.sh
loomwright/scripts/test-setup-providers.sh
loomwright/scripts/adapters/providers/lens-run.sh
loomwright/scripts/adapters/providers/test-lens-run.sh
loomwright/scripts/adapters/providers/provider-claude.sh
loomwright/scripts/adapters/providers/provider-codex.sh
loomwright/scripts/adapters/providers/provider-copilot.sh
loomwright/scripts/adapters/providers/provider-cursor.sh
loomwright/scripts/adapters/providers/provider-gemini.sh
loomwright/scripts/adapters/providers/provider-grok.sh
docs/evidence/provider-routing-02-providers-probe.md

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-31T07:31:55Z
- **Brief:** .supervisor/jobs/done/2026-10-31-provider-launch-parity.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/764
