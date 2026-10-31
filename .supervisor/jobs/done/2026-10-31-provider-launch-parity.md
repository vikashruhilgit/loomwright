# Supervisor Job: Provider launch parity — one isolated launcher for `check` and `lens-run`, declared login pass-through, real permission probe

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (stale worktrees under `.claude/worktrees/` from other sessions; none on this branch)
- **Source requirement:** .supervisor/requirements/provider-routing/05-provider-launch-parity.md
- **Base commit:** c8fe7b485a7423ddc6652014bbcad3a213170f60

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Pure bash 3.2 + jq, the same stack `lens-run.sh` and `setup-providers.sh` already use |
| 2 | Dependency Availability | CAUTION | The evidence AC needs real, logged-in `grok` and `cursor-agent` on this machine (present per the requirement's verified premises, 2026-10-31); where each CLI keeps its login is a probe the worker must run, not a known fact |
| 3 | Architecture Fit | GO | Provider table stays data-only (`provider-<name>.sh`); the shared launcher is a new adapter-side helper beside `lens-run.sh`; `setup-providers.sh` still names no vendor CLI |
| 4 | Scope vs Supervisor Capability | CAUTION | ~18 files touched across two scripts, six provider entries and four test files: over the one-worker bound, split `context-bound` into two sequential subtasks |
| 5 | Hard Blockers | GO | Dependency `03-routing-config-readonly-seats.md` shipped (v17.22.0, PR #746/#750 on `origin/main`) |

**Overall Verdict:** CAUTION

## Task
**Goal:** Make `setup-providers.sh check` and `lens-run.sh` launch a provider CLI through ONE shared isolated launcher (scrubbed env/HOME/TMPDIR, own process group, timeout chain) that carries across only each provider's declared login files/env vars, and grade write-seat eligibility by a real permission-enforcement probe instead of `--help` tokens.

**Problem Statement:**
A maintainer who routed a read-only step to Grok or Cursor needs `/setup providers` and `setup-providers.sh check` to say "usable" only when a routed step will actually run, because today the check and the runner launch a provider two different ways.
Currently, `check` runs its smoke under the REAL `HOME` (its banner says `HOME: the REAL HOME (login state lives there; never scrubbed)`) while `lens-run.sh` runs every CLI as `env -i PATH="$PATH" HOME="$SCRUB_HOME" TMPDIR="$SCRUB_HOME"` with an empty temp HOME. Result: `check` reports grok `usable for write seats` and cursor `usable for read-only seats`, while the same CLIs under lens-run's launch shape fail with "Not signed in" / "Authentication required". Separately, `pinnable` is graded from `--help` text: on Grok 1.0.70 `--permission-mode dontAsk` with no allow rule still wrote a file. This causes every non-Claude routed step to fail at login while every screen reports it as working, and would admit Grok to write seats it cannot be pinned for.
Success looks like: `check` reports the verdict a routed step would actually get; a provider whose login cannot cross isolation gets a named status, never `usable`; `pinnable` requires an observed denial.

## Acceptance Criteria
- [ ] AC1 — Given a fake provider whose CLI succeeds only when `$HOME/.fake/auth.json` exists and whose `provider-<name>.sh` DECLARES that file as its login pass-through, when `setup-providers.sh check` runs and when `lens-run.sh` runs it with a user-scope grant, then the check row ends `=> usable for …` AND lens-run returns `lens_status: "ok"`.
- [ ] AC2 — Given the same fake provider with NO login declaration, when both run, then the check row's auth column reads `auth: not_logged_in_isolated (ok in your shell)` with a fix hint and ends `=> not usable: auth`, AND lens-run returns a non-`ok` `lens_status` whose `notes` begins with the same named status `not_logged_in_isolated`.
- [ ] AC3 — Given the shared launcher, when it launches a CLI for a provider that declares login file(s) and env var(s), then the isolated HOME contains exactly the declared files (copied, mode read-only, no symlinks anywhere under it), the child env contains only the launcher's allow-list plus the declared env vars that are set in the parent (no `GH_TOKEN`, no other provider's key), and the isolated HOME is removed on normal exit AND after a timeout kill.
- [ ] AC4 — Given a guard test (grep-level, modelled on `loomwright/scripts/test-base-branch-single-resolver.sh`), when any `*.sh` under `loomwright/scripts/` other than the shared launcher (self-tests and fixtures excluded) execs a provider CLI directly (`"$cli" …`, `"$PROVIDER_CLI_NAME" …`, `env -i … "$PROVIDER_CLI_NAME"`), then the guard fails; it passes on the finished tree, and a prose line naming the form never turns it red.
- [ ] AC5 — Given a fake provider declaring pin flags whose CLI IGNORES them and writes the requested file anyway, when `check` runs, then its permissions column is not `pinnable` and its verdict is never `usable for write seats`; given one that REFUSES (no file appears), then it grades `permissions pinnable`; given help tokens present but no enforcement probe run (smoke not passing, or the probe could not run), then the column reads at most `permissions: pin flags advertised (unverified)`.
- [ ] AC6 — Given `check`'s report banner, when it prints, then it states the smoke runs under the isolated launcher (not the real HOME) and that the permission probe costs one model call per candidate provider.
- [ ] AC7 — Given this machine with `grok` and `cursor-agent` logged in, when the worker re-runs `check` after the change, then `docs/evidence/provider-routing-02-providers-probe.md` gains a new appended section (the 02 rows above it untouched) holding the new verbatim rows, where each CLI's login was found (file path relative to `$HOME`, env var, or keychain-only — probed, with the command used), and the Grok enforcement-probe outcome; the PR body links to it.
- [ ] AC8 — Given the branch, when `bash scripts/ci-local.sh --affected` runs, then it is green, and `bash scripts/check-version-bump.sh` passes with a `changelog.d/` fragment (no hand-edited version files).

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## House Rules

> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.
  - id: process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

## Design (intended shape — re-verify against main before building)

1. **One launcher** — CREATE `loomwright/scripts/adapters/providers/launch-provider-cli.sh`, a SOURCED library (never `provider-*.sh`-named: `setup-providers.sh` globs `provider-*.sh` and `lens-run.sh` would accept it as `--provider launch`). It owns: the `env -i` allow-list env, the per-launch scrubbed HOME/TMPDIR (`mktemp -d`), the setpgrp launch (perl, python3 fallback), the bounded TERM→KILL timeout chain over the process group (never the caller's own group, never group 1), and removal of the isolated HOME on every exit path. Callers: `lens-run.sh` (replacing `lens_exec_cli` and its watchdog) and every CLI call in `setup-providers.sh` (version, auth, help, smoke, permission probe), which resolves the launcher from its OWN `SCRIPT_DIR/adapters/providers/`, never from `LOOMWRIGHT_PROVIDERS_DIR` (tests point that at a temp dir).
2. **Home modes.** The launcher takes a home mode: `isolated` (scrubbed HOME + declared login pass-through — the ONLY mode any verdict is graded from, and the only mode `lens-run.sh` uses) and `shell` (real HOME, still env-scrubbed to the allow-list + real `HOME`) used by `check` only as a diagnosis rerun when an isolated auth/smoke fails, to tell `not_logged_in_isolated` apart from `not_logged_in`.
3. **Declared login pass-through.** Each `provider-<name>.sh` may declare `PROVIDER_LOGIN_FILES` (array of paths relative to `$HOME`; reject absolute paths and any `..` segment) and `PROVIDER_LOGIN_ENV` (array of env var names, `[A-Z_][A-Z0-9_]*`). The launcher copies each existing declared file (dereferenced, `cp` never `ln`) into the same relative path under the isolated HOME, chmod read-only, and passes each declared env var only when set in the parent. Undeclared ⇒ nothing crosses (today's behaviour). The worker PROBES each real CLI (vendor docs + this machine) for where its login lives and declares only that; a keychain-only login is declared nothing and is reported `not_logged_in_isolated` with a hint naming the CLI's API-key env var, never `usable`.
4. **Truthful verdicts.** New auth value `not_logged_in_isolated`, printed `auth: not_logged_in_isolated (ok in your shell)` + a `fix:` hint line; lens-run puts the same token at the start of `notes` when its output matches the provider's `PROBE_AUTH_NOT_LOGGED_IN_RE` (lens-run already sources the provider file). New permissions value printed `permissions: pin flags advertised (unverified)`. The verdict tail `=> <verdict>` and its four strings are unchanged.
5. **Real permission probe.** For a provider whose `PROBE_PERM_PIN_FLAGS` is neither `none` nor empty, whose help advertises every token, and whose isolated smoke passed: a new provider-file function `probe_perm_argv` (reads `PROBE_PROMPT`, sets `PROBE_ARGV`, prompt LAST — pin flags, deny-nothing/allow-nothing) is launched isolated in a fresh throwaway cwd with a fixed prompt asking it to create `probe.txt`; `pinnable` only if no file appears in that cwd; a file appearing ⇒ `permissions: unpinnable (pin flags not enforced)`; a probe that times out or cannot run ⇒ `pin flags advertised (unverified)`.

## Phase 3 analysis

### File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| launcher + lens | `loomwright/scripts/adapters/providers/lens-run.sh` (655 — the launch block is REMOVED into the new module, net shrink); `loomwright/scripts/adapters/providers/test-lens-run.sh` (727 — append AC1/AC2 lens-run cases: it owns the grant/egress scratch-HOME fixture they need, a second copy elsewhere would be a third fixture) | `loomwright/scripts/adapters/providers/launch-provider-cli.sh` (new home of the launch responsibility); `loomwright/scripts/adapters/providers/test-launch-provider-cli.sh` (new home of AC3's launcher unit cases — not appended to the 727-line test) | HIGH |
| provider table | `loomwright/scripts/adapters/providers/provider-claude.sh` (112), `provider-codex.sh` (85), `provider-copilot.sh` (100), `provider-cursor.sh` (107), `provider-gemini.sh` (91), `provider-grok.sh` (103) — declarations + `probe_perm_argv` (data the launcher/check read; one home each) | — | HIGH |
| check | `loomwright/scripts/setup-providers.sh` (447 — the single authority for the report columns; its own bounded runner `run_bounded`/`rb_exec`/`rb_kill` is REMOVED in favour of the launcher, so no copied helper remains); `loomwright/scripts/test-setup-providers.sh` (503 — append AC5 enforcement cases + update case C: it owns the per-run fake-CLI marks fixture; ≥500 so keep additions to the cases only); `loomwright/scripts/test-setup-routing.sh` (527 — modify ONLY if its fake `$P_WR` write-seat provider stops grading `usable for write seats` under the enforcement probe; reason: it is the consumer test of the verdict) | `loomwright/scripts/test-provider-cli-single-launcher.sh` (new home of AC4's guard, mirrors `test-base-branch-single-resolver.sh`) | HIGH (test-setup-routing.sh MEDIUM) |
| docs + release | `loomwright/docs/PROVIDER_ROUTING.md` (129 — the "not a sandbox" honest-limits bullet), `docs/evidence/provider-routing-02-providers-probe.md` (97 — append only) | `changelog.d/provider-launch-parity.md` | HIGH |

> **Validator-owned surfaces:** AC8 depends on `scripts/check-doc-currency.sh`, `scripts/check-version-bump.sh` and `scripts/check-vendor-coupling.sh` (run by `ci-local.sh --affected`'s early set). The vendor-coupling ratchet counts `.claude/` and `claude -p` tokens in every core script: `launch-provider-cli.sh`, both new tests and `setup-providers.sh` must name no vendor token; a `PROVIDER_LOGIN_FILES` entry for `provider-claude.sh` that names `.claude/…` raises its measured allowance (`provider-claude.sh=3` in `loomwright/docs/vendor-coupling-manifest.json`) — then `loomwright/docs/vendor-coupling-manifest.json` is a MODIFY (allowance + `allowance_reasons`), measured by the gate, never hand-typed.

Total estimated files: 13 modify (+1 conditional, +1 conditional manifest) + 4 create.

### File Overlap Detection

| Group A | Group B | Overlapping Files | Serialization Required |
|---------|---------|-------------------|----------------------|
| Subtask 1 | Subtask 2 | none (Subtask 2 consumes Subtask 1's launcher + provider declarations) | YES — by `requires` |

## Touched-file invariants

> Grounded at base `c8fe7b485a7423ddc6652014bbcad3a213170f60`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/adapters/providers/lens-run.sh`** — keep: the exit-0 fail-safe contract `set +e   # FAIL-SAFE beyond usage errors`, the closed `lens_status` set in the header (`"ok" | "provider_unavailable" | "provider_not_granted" | "lens_mutated_tree" | "lens_unparseable"` — no new value; the named status rides in `notes`), the grant check BEFORE any sandbox/HOME work (`no user-scope grant for this provider in this repo; nothing was sent`), the independent-sandbox + fail-closed `git remote remove origin` block, the integrity fingerprint, `trap cleanup EXIT` removing `"$WT_PATH" "$SCRUB_HOME"`, the timeout note `provider CLI timed out after ${LENS_CLI_TIMEOUT}s; process group killed; result discarded`, `LOOMWRIGHT_LENS_CLI_TIMEOUT` and the test hatch `LOOMWRIGHT_LENS_DEBUG_WT_PATH_FILE`; reuse: the new launcher for the `env -i PATH="$PATH" HOME="$SCRUB_HOME" TMPDIR="$SCRUB_HOME"` launch (no second copy left in this file); mirror: the PROVIDER-TABLE FILE CONTRACT header gains `PROVIDER_LOGIN_FILES` / `PROVIDER_LOGIN_ENV` and `PROVIDER_HOME_SCRUB`'s "always 1 today" wording is corrected (consumer: test-setup-providers.sh case T's `case "${PROVIDER_HOME_SCRUB:-}" in 0|1)`); pinned by: `test-lens-run.sh` (`E HOME redirected to a scrub dir, not the test's real HOME`, case H process-group kill) and `test-lens-compare.sh` (runs stub providers through lens-run — must stay green unmodified).
- **`loomwright/scripts/setup-providers.sh`** — keep: `set +e   # FAIL-SAFE: a failing probe is a report row`, exit 0 for `check` / 64 for usage, `This file names no vendor CLI` (test case V greps the engine for every table name), the skip rule `declare -F probe_smoke_argv >/dev/null 2>&1 || return 0`, the name allowlist `""|*[!a-zA-Z0-9_-]*) continue`, one subshell per provider `row="$( probe_provider "$f" "$name" )"`, whole-token `help_has_token`, the row format `printf '%s: %s · %s · %s · %s · %s => %s\n'`; mirror: the consumer `loomwright/scripts/setup-routing.sh` parses `index($0, " => ")` and accepts only `"usable for read-only seats"|"usable for write seats") return 0 ;;` — the verdict strings and ` => ` tail must stay byte-identical and no column text may contain ` => `; reuse: the launcher for EVERY CLI call (its `rb_exec`/`run_bounded` copy is removed); change: the banner literal `HOME: the REAL HOME (login state lives there; never scrubbed)` and the header SAFETY bullet `unlike lens-run.sh there is no \`env -i\` / HOME scrub` become false and are rewritten; pinned by: `test-setup-providers.sh` (`C: smoke HOME is the HOME the engine got (not scrubbed)` — a changed pin, see Pin mutations) and `test-setup-routing.sh` (`c_verdict_write`).
- **`loomwright/scripts/adapters/providers/provider-{claude,codex,copilot,cursor,gemini,grok}.sh`** — keep: `PROMPT_CONTENT` / `PROBE_PROMPT` LAST in every argv builder (case T asserts it), `probe_smoke_argv` reusing `provider_build_argv`, every vendor string living here and nowhere else; mirror: the probe-entry contract block in `setup-providers.sh`'s header (`PROBE-ENTRY CONTRACT`) gains `probe_perm_argv`, `PROVIDER_LOGIN_FILES`, `PROVIDER_LOGIN_ENV` in the same change (house rule: restated list updated with its authority); pinned by: test-setup-providers.sh case T (table contract over the REAL files).
- **`loomwright/scripts/test-setup-providers.sh` / `loomwright/scripts/adapters/providers/test-lens-run.sh` / `loomwright/scripts/test-setup-routing.sh`** — keep: per-run baked fake CLIs recording into `$TMP/marks`, never a machine-wide name match; the hermetic preamble `hermetic-test-env.sh`; RUN_TAG-suffixed stub names in test-lens-run.sh; the EXIT-trap removal of test-only `provider-teststub<RUN_TAG>.sh` files; since the launcher scrubs env, steer stubs by baked binaries, never env vars (test-lens-run.sh header explains why).
- **`loomwright/docs/PROVIDER_ROUTING.md`** — change the honest-limits bullet `the provider CLI's own tool permissions are not pinned by this plugin` to state what the enforcement probe does and does not prove (a denial observed once on a fixed prompt, not a sandbox); keep the rest of the bullet.

## Closed enumerations touched

> Sibling grep at base `c8fe7b4`: `grep -rnF 'unpinnable' --exclude=CHANGELOG.md .` (worktrees/.supervisor excluded) → 15 hits in 5 files; `grep -rnF 'not_logged_in' --exclude=CHANGELOG.md .` → 20 hits in 7 files.

- **`not_logged_in_isolated`** (sibling: `not_logged_in`) — must be named in:
  - `loomwright/scripts/setup-providers.sh` — the COLUMNS header's auth value list (`` `auth ok` | `auth: not_logged_in` | `auth: unknown` ``) and the auth/hint `case "$auth" in` — extend.
  - `loomwright/scripts/adapters/providers/lens-run.sh` — DEGRADATION header (where it names what `notes` carries for a failing CLI) — extend (prose; `lens_status` set unchanged).
  - `loomwright/scripts/test-setup-providers.sh` — Covers header — extend with the new case.
  - `loomwright/scripts/adapters/provider-{codex,copilot,gemini,grok}.sh` hits — comments describing the smoke's not-logged-in regex — no change: they describe the regex, not the value list.
  - `docs/evidence/provider-routing-02-providers-probe.md` hits — the 02 record — no change: historical rows are not rewritten (append only).
- **`pin flags advertised (unverified)`** / **`unpinnable (pin flags not enforced)`** (sibling: `unpinnable`) — must be named in:
  - `loomwright/scripts/setup-providers.sh` — COLUMNS header `permissions` list and the `case "${PROBE_PERM_PIN_FLAGS:-}"` arm — extend.
  - `loomwright/scripts/test-setup-providers.sh` — Covers header (cases R/X/P) — extend.
  - `loomwright/scripts/adapters/providers/provider-cursor.sh`, `provider-grok.sh` comments — re-word the grok note that help tokens imply pinnable; cursor `none` — no change.
  - `loomwright/scripts/setup-routing.sh` — no change: it reads only the verdict tail, never the permissions column.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `test-launch-provider-cli.sh` — isolated HOME holds no symlinks | flip the launcher's login-file copy `cp` → `ln -s` in `loomwright/scripts/adapters/providers/launch-provider-cli.sh` |
| `test-launch-provider-cli.sh` — isolated HOME removed after a timeout kill | delete the `rm -rf` of the isolated HOME in the launcher's cleanup in `loomwright/scripts/adapters/providers/launch-provider-cli.sh` |
| `test-launch-provider-cli.sh` — only declared env vars cross | add the parent's full env (drop `-i` from `env -i`) in `loomwright/scripts/adapters/providers/launch-provider-cli.sh` |
| `test-lens-run.sh` — AC1 declared fake → `ok` | delete the declared-login-file copy loop line in `loomwright/scripts/adapters/providers/launch-provider-cli.sh` |
| `test-setup-providers.sh` — AC2 undeclared fake → `not_logged_in_isolated` | flip the smoke's home mode `isolated` → `shell` in `loomwright/scripts/setup-providers.sh` (the row then reads usable) |
| `test-setup-providers.sh` — AC5 write-anyway fake not pinnable | delete the line in `loomwright/scripts/setup-providers.sh` that downgrades `perm` when the probe file appears |
| `test-setup-providers.sh` — AC5 help-only → `pin flags advertised (unverified)` | flip the help-tokens-present assignment from the advertised value → `pinnable` in `loomwright/scripts/setup-providers.sh` |
| `test-setup-providers.sh` — changed case C: smoke HOME is NOT the engine's HOME | flip the smoke's home mode `isolated` → `shell` in `loomwright/scripts/setup-providers.sh` |
| `test-provider-cli-single-launcher.sh` — guard | replace the smoke's launcher call with a direct `"$cli" "${PROBE_ARGV[@]}"` in `loomwright/scripts/setup-providers.sh` |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Shared isolated launcher + login pass-through declarations; lens-run migrated | AC1 (lens-run half), AC2 (lens-run half), AC3 | 8 modify, 2 create | `skills/error-handling/SKILL.md` | LAUNCHABLE |
| 2 | `check` through the launcher: truthful auth verdicts, real permission probe, guard, evidence, release | AC1 (check half), AC2 (check half), AC4, AC5, AC6, AC7, AC8 | 5 modify (+1 conditional, +1 conditional manifest), 2 create | `skills/error-handling/SKILL.md` | BLOCKED (by #1) |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/scripts/adapters/providers/launch-provider-cli.sh"}
  - {kind: "symbol", path: "loomwright/scripts/adapters/providers/launch-provider-cli.sh", name: "PROVIDER_LOGIN_FILES"}
  - {kind: "symbol", path: "loomwright/scripts/adapters/providers/launch-provider-cli.sh", name: "PROVIDER_LOGIN_ENV"}
  - {kind: "file", path: "loomwright/scripts/adapters/providers/test-launch-provider-cli.sh"}
  - {kind: "symbol", path: "loomwright/scripts/adapters/providers/lens-run.sh", name: "launch-provider-cli.sh"}
  - {kind: "symbol", path: "loomwright/scripts/adapters/providers/lens-run.sh", name: "not_logged_in_isolated"}
  - {kind: "symbol", path: "loomwright/scripts/adapters/providers/provider-grok.sh", name: "probe_perm_argv"}
  - {kind: "symbol", path: "loomwright/scripts/adapters/providers/provider-claude.sh", name: "probe_perm_argv"}
  - {kind: "symbol", path: "loomwright/scripts/adapters/providers/provider-copilot.sh", name: "probe_perm_argv"}
requires: []
lanes:
  - "loomwright/scripts/adapters/providers/launch-provider-cli.sh"
  - "loomwright/scripts/adapters/providers/test-launch-provider-cli.sh"
  - "loomwright/scripts/adapters/providers/lens-run.sh"
  - "loomwright/scripts/adapters/providers/test-lens-run.sh"
  - "loomwright/scripts/adapters/providers/provider-claude.sh"
  - "loomwright/scripts/adapters/providers/provider-codex.sh"
  - "loomwright/scripts/adapters/providers/provider-copilot.sh"
  - "loomwright/scripts/adapters/providers/provider-cursor.sh"
  - "loomwright/scripts/adapters/providers/provider-gemini.sh"
  - "loomwright/scripts/adapters/providers/provider-grok.sh"
  - "loomwright/docs/vendor-coupling-manifest.json"
external_requires:
  - "grok (Grok Build 1.0.70) and cursor-agent (2026.10.22) installed and logged in on this machine, for the login-location probe"
  - "vendor docs for each CLI's credential storage (read, never assumed)"

# Subtask 2
provides:
  - {kind: "symbol", path: "loomwright/scripts/setup-providers.sh", name: "not_logged_in_isolated"}
  - {kind: "symbol", path: "loomwright/scripts/setup-providers.sh", name: "pin flags advertised (unverified)"}
  - {kind: "symbol", path: "loomwright/scripts/setup-providers.sh", name: "probe_perm_argv"}
  - {kind: "file", path: "loomwright/scripts/test-provider-cli-single-launcher.sh"}
  - {kind: "symbol", path: "loomwright/docs/PROVIDER_ROUTING.md", name: "permission probe"}
  - {kind: "symbol", path: "CHANGELOG.md", name: "v17.23.0"}   # adjudicated D (SUP-ADJ-GAP, 2026-10-31): bump-version.sh folds and deletes the changelog.d fragment
requires:
  - {from: "1", kind: "file", path: "loomwright/scripts/adapters/providers/launch-provider-cli.sh"}
  - {from: "1", kind: "symbol", path: "loomwright/scripts/adapters/providers/provider-grok.sh", name: "probe_perm_argv"}
lanes:
  - "loomwright/scripts/setup-providers.sh"
  - "loomwright/scripts/test-setup-providers.sh"
  - "loomwright/scripts/test-setup-routing.sh"
  - "loomwright/scripts/test-provider-cli-single-launcher.sh"
  - "loomwright/docs/PROVIDER_ROUTING.md"
  - "docs/evidence/provider-routing-02-providers-probe.md"
  - "changelog.d/provider-launch-parity.md"
external_requires:
  - "grok and cursor-agent logged in on this machine (AC7 evidence re-run; costs real model calls)"
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none | YES (requires) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after Subtask 1)
- **Recommended workers:** 1
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/error-handling/SKILL.md` |
| 2 | `skills/error-handling/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): where grok / cursor-agent keep their login is unknown; a keychain-only login cannot cross isolation | MEDIUM | Probe each CLI (docs + this machine) and record the command in the AC7 evidence; keychain-only ⇒ declare nothing and report `not_logged_in_isolated` with the CLI's API-key env var as the fix hint — never route it silently |
| Feasibility (Phase 2.5): over the one-worker bound | HIGH | Split `context-bound` into launcher-first then check; Subtask 2 consumes Subtask 1's launcher, so the sequential order is real |
| Copying a credential file is a new secret-handling surface (a vendor CLI may refresh/rewrite it) | HIGH | Copy, never symlink; chmod read-only; isolated HOME `mktemp -d` (0700) removed on every exit path incl. timeout and INT/TERM; never print, log or diff its content; AC3's pins prove each property |
| `claude`'s own login may be keychain-only on macOS, so its row could turn `not_logged_in_isolated` | MEDIUM | That is the truthful lens-run verdict; Claude-routed seats run via the Task spawn, not lens-run (`docs/PROVIDER_ROUTING.md` §"Routed seat protocol"); state it in the evidence rather than special-casing `claude` |
| The permission probe asks a real agent to write a file — on a non-enforcing CLI it WILL write | MEDIUM | Run only in a fresh `mktemp -d` cwd under the isolated HOME, fixed prompt, no repo content, removed after; only providers whose smoke already passed; banner states the one-model-call cost (AC6) |
| `setup-routing.sh` parses `check` rows; a column text containing ` => ` or a changed verdict string silently refuses every route | MEDIUM | Verdict strings byte-identical (Touched-file invariants); `test-setup-routing.sh` must stay green |
| Vendor-coupling ratchet fails on a new `.claude/` token (e.g. a claude login-file declaration) | LOW | Keep the launcher/check/tests vendor-free; raise only `provider-claude.sh`'s allowance via the gate's measured value with an `allowance_reasons` entry |
| Grok under the REAL HOME fires this user's Claude Code plugin hooks (requirement side observation) | LOW | The isolated launch removes that for every graded call; the `shell` diagnosis rerun still has it — say so in the evidence; full fix belongs to item 04 |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-31-provider-launch-parity.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-10-31T07:11:30Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/764
- **Branch:** feature/provider-launch-parity
- **Files changed:** 21
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** unarmed (marker_missing)
- **Summary:** One sourced launcher (launch-provider-cli.sh) now runs every provider CLI call for setup-providers.sh check and lens-run.sh (env -i allow-list, per-call isolated HOME with read-only copies of declared PROVIDER_LOGIN_FILES, declared PROVIDER_LOGIN_ENV, own process group, TERM→KILL timeout, cleanup on every exit path); check reports not_logged_in_isolated and grades pinnable only from a real permission probe; AC4 guard; AC7 evidence appended; v17.23.0. Phase 4.5 found and fixed one new HIGH per iteration (timeout-flag symlink race; un-removable chmod-000 HOME + CI pipefail ratchet; probe fail-open on a tampered cwd). The iteration-3 fix (5431951) was not LLM re-reviewed. SUP-ADJ-GAP adjudicated D by the owner (changelog.d fragment folded by bump-version.sh).

## Not verified
- **setup-providers.sh check through the launcher** — outside subtask 1's lane; subtask 2's tests cover it (subtask 1)
- **lens-run against real grok/cursor/claude** — needs a user-scope grant and model calls; only launcher-level auth probes were run (subtask 1)
- **lens-run launcher-missing and launch-setup-failure arms** — no test moves the launcher out of the providers dir (subtask 1)
- **copilot probe_perm_argv on a real binary** — copilot is not installed on this machine (subtask 2)
- **/setup providers rendering of the new banner and fix: lines** — only the script was run, not the slash command (subtask 2)
- **grok dontAsk write under the real HOME** — not re-run: it would load the user's grok config and fire their hooks (subtask 2)
- **AC7 PR body link to the evidence** — subtask opened no PR; the Supervisor's PR body links it (subtask 2)
