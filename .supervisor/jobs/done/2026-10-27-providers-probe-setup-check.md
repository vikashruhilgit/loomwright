# Supervisor Job: Provider probe — `setup-providers.sh check` (read-only, fail-safe) + probe entries in every provider-table file + new Grok and Copilot entries

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-27-125907/L2
- **CLAUDE.md:** ✓ Found (fresh — layout, Portability and doc-currency claims spot-checked against the tree)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/provider-routing/02-providers-probe.md
- **Base commit:** 84d9023b2d7561c3c34929df3e64696bad7b2339

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Portable bash 3.2 + `jq`, the same stack as the existing provider-table adapter (`loomwright/scripts/adapters/providers/`) |
| 2 | Dependency Availability | CAUTION | `claude` and `cursor-agent` are on PATH here; `grok`, `copilot`, `codex`, `gemini` are absent (re-checked 2026-10-27). The evidence step needs the owner to install and log in to `grok` first (the requirement's own Assumption) |
| 3 | Architecture Fit | GO | Adding a provider = one new `provider-<name>.sh` (lens-run.sh header contract). Probe data goes into those files; the engine reads them and names no vendor CLI itself (Portability rule) |
| 4 | Scope vs Supervisor Capability | GO | 12 files, estimated ~700 changed lines. Below the `context-bound` bound and there is no second ≥3-file group, so it stays one subtask |
| 5 | Hard Blockers | CAUTION | Vendor invocation shapes for `grok`/`copilot` must be read from the vendors' current docs at build time; nothing on this machine can verify them until installed |

**Overall Verdict:** CAUTION

## Task
**Goal:** Add a read-only, always-exit-0 `loomwright/scripts/setup-providers.sh check` that reports, from commands it actually ran, whether each provider-table CLI is installed, logged in, headless-usable with parseable output, permission-pinnable and browser-capable, plus a one-line verdict per provider. The probe data lives in each `provider-<name>.sh`, including new `provider-grok.sh` and `provider-copilot.sh` entries.

**Problem Statement:**
The maintainer needs to know which AI CLIs on a real machine can run which pipeline step, because routing items 03–04 must be designed against what works, not against vendor docs.
Currently, the provider table (`provider-{claude,codex,cursor,gemini}.sh`) has only lens invocation templates. Two of them were written from docs and have never run, there is no Grok or Copilot entry, and nothing reports install/auth/headless/permission state. Routing designed now would rest on guesses (owner decision D2′: no provider-table runner before a real second-harness probe).
Success looks like this: one command prints a per-provider row, with its verdict and the exact install/login hint, from real invocations, and the committed evidence note records that report from a real machine.

## Acceptance Criteria

**Happy path**
- [ ] AC1: Given `claude` installed and logged in, when `bash loomwright/scripts/setup-providers.sh check` runs, then the `claude` row shows `installed <ver>`, `auth ok`, `headless pass`, `permissions pinnable` and the verdict `usable for write seats`. The permission column for `claude` is derived from its `--help` advertising `--permission-mode` with `dontAsk` plus `--allowedTools`/`--disallowedTools`, the same probe `dispatch-pr-review.sh` uses for `PERMISSION_REGIME_UNPINNABLE`.
- [ ] AC2: Given `grok` installed and logged in, when `check` runs, then the `grok` row has a real value (not `unknown`) in installed, auth and headless.
- [ ] AC3: Given any machine, when `check` runs, then the script writes nothing outside its own `mktemp -d` scratch dir, which it removes on exit. `test-setup-providers.sh` asserts this with a temp HOME and stubs: the repo tree (`git status --porcelain` before = after) and the temp HOME's `.claude` tree are unchanged.
- [ ] AC4: Given each verdict rule, when a row is printed, then it ends with exactly one of: `usable for read-only seats` (installed + auth ok + headless pass), `usable for write seats` (all of that + permissions pinnable), or `not usable: <first failing column>`, with columns checked in the order installed → auth → headless.

**Edge cases / errors**
- [ ] AC5: Given a provider binary absent from PATH, when `check` runs, then the row shows `installed: no`, the provider's install hint and `not usable: installed`. The script exits 0 and runs no other column for that provider.
- [ ] AC6: Given a binary that is installed but not logged in (e.g. `cursor-agent` today), when `check` runs, then the row shows `auth: not_logged_in`, the provider's login hint and `not usable: auth`, and the headless smoke is NOT run.
- [ ] AC7: Given a smoke call that hangs past the timeout (env-overridable, positive integer, default bounded), when `check` runs, then the row shows `headless: fail:timeout`, the smoke's whole process group is TERM-then-KILL'd (the test checks only the pids/pgid its own stub recorded, never a machine-wide name match), and the script exits 0.
- [ ] AC8: Given a smoke call whose output does not parse to the fixed JSON reply, when `check` runs, then the row shows `headless: fail:unparseable`.
- [ ] AC9: Given a provider whose only non-interactive mode auto-approves every tool (a lone `--always-approve`-style flag, declared in its probe entry), when `check` runs, then `permissions: unpinnable` is shown and the verdict can never be `usable for write seats`.
- [ ] AC10: Given the smoke runs, then it runs from a throwaway `mktemp -d` cwd (never the repo), with a fixed prompt string (no repo content), under the REAL HOME (auth needs it — `PROVIDER_HOME_SCRUB=1` breaks `cursor-agent` login), and the report header says so. The script never reads, prints or stores an API key or token, and never installs anything.
- [ ] AC11: Given `bash loomwright/scripts/test-setup-providers.sh`, when it runs, then it covers every column state (installed yes/no; auth ok/not_logged_in/unknown; headless pass/fail:timeout/fail:unparseable/not run; permissions pinnable/unpinnable/unknown; browser yes/no/unknown) and all three verdict forms. Fake binaries on PATH and a temp providers dir drive the cases, like `test-lens-run.sh`, and the suite exits 0 only when all pass.
- [ ] AC12: Given a provider-table file that declares no probe entries (e.g. `test-lens-run.sh`'s transient `provider-teststub<pid>.sh`, or `test-lens-compare.sh`'s `provider-teststubx<pid>.sh` / `provider-teststuby<pid>.sh`), when `check` enumerates the table, then that file is skipped, never reported or run.

**Table contract**
- [ ] AC13: Given each of `provider-{claude,codex,cursor,gemini,grok,copilot}.sh`, then it declares probe entries as data: version command, auth-check command (with its ok / not-logged-in mapping), a headless smoke invocation expecting the fixed JSON reply, the permission-pinning flag set (or `none`), browser capability (`unknown` until shown), and install/login hints. Each also still satisfies lens-run.sh's PROVIDER-TABLE FILE CONTRACT unchanged. `provider-grok.sh` and `provider-copilot.sh` cite the vendor doc each invocation shape came from, with its date, in their header (never from memory). `test-lens-run.sh` still passes.

**Evidence (Part 4)**
- [ ] AC14: Given the change is ready for PR, then a committed evidence file `docs/evidence/provider-routing-02-providers-probe.md` contains the real `check` output from this machine for `claude` and for every other provider installed when the item runs (at least `grok` once the owner has installed it), the date and CLI versions, and the honest limits (vendor CLIs may write their own session/state files during the smoke). The PR body links to that file.

**Gates**
- [ ] AC15: Given the diff, then nothing under `loomwright/agents/`, `loomwright/skills/`, `loomwright/commands/` or `loomwright/docs/command-parts/` changes. `setup-providers.sh` itself names no vendor CLI literally: every vendor string lives in a `provider-<name>.sh` file.
- [ ] AC16: Given the diff, then `bash scripts/check-vendor-coupling.sh` passes, including its `raise_check`. Any raised or new allowance in `loomwright/docs/vendor-coupling-manifest.json` is measured by `--print-allowances` and carries an added/changed `allowance_reasons` entry.
- [ ] AC17: Given the diff, then `bash scripts/check-doc-currency.sh` and `bash scripts/check-version-bump.sh` pass (one `changelog.d/` fragment, version files never hand-edited), and `bash scripts/ci-local.sh` is green.

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

## Rule conflicts (open decisions)
- Conflict: `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Portability" keeps its restated four-name provider list after this item adds two provider-table entries. Owner's choice: override
- Rule override: process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift — kept file-disjoint from parallel wave-1 item 01, which owns ARCHITECTURE_CONTRACTS.md; the dated 'as of this writing' list is turned into a pointer by item 03 (acknowledged by the owner: Launch Pad Phase 6, 2026-10-27)
- Hand-off recorded in `.supervisor/requirements/provider-routing/03-routing-config-readonly-seats.md` (§"Intended shape" bullet "Handed over from item 02" + `## Touches`).

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| provider table | `loomwright/scripts/adapters/providers/provider-claude.sh` (68), `provider-codex.sh` (48), `provider-cursor.sh` (60), `provider-gemini.sh` (49) — each is the existing per-provider home for its own probe data | `loomwright/scripts/adapters/providers/provider-grok.sh`, `loomwright/scripts/adapters/providers/provider-copilot.sh` | HIGH |
| lens-run pointer | `loomwright/scripts/adapters/providers/lens-run.sh` (573 — header comment only: replace the restated provider list with a pointer to the `provider-*.sh` files in its dir; no logic change, no new responsibility) | — | HIGH |
| probe engine | — | `loomwright/scripts/setup-providers.sh` (the one new responsibility: enumerate, probe, report, verdict) | HIGH |
| tests | — | `loomwright/scripts/test-setup-providers.sh` (auto-discovered by `scripts/ci-local.sh`'s `loomwright/scripts/test-*.sh` glob) | HIGH |
| ratchet | `loomwright/docs/vendor-coupling-manifest.json` (784 — the single authority for allowances; only touched if `--print-allowances` measures a raise) | — | MEDIUM |
| evidence + release | — | `docs/evidence/provider-routing-02-providers-probe.md` (repo-root `docs/evidence/` is the existing convention; `loomwright/docs/evidence/` does not exist), `changelog.d/provider-probe-check.md` | HIGH |

**Module layout:** the new process-group timeout runner for the smoke has one home in `setup-providers.sh`. Today only `lens-run.sh` has the same `setpgrp` launcher, inlined and bound to that script's own globals, so this is the second copy, not a third: no extract row. If a third consumer appears, extract both into a shared helper then.

> **Validator-owned surfaces:** `scripts/check-vendor-coupling.sh` counts every tracked file under `loomwright/` and `scripts/` against `loomwright/docs/vendor-coupling-manifest.json` (hence its row above). `scripts/check-doc-currency.sh` scans the doc surface; this change touches no file in its `FILES` list.

**Total estimated files:** 6 modify + 6 create

## Touched-file invariants

> Grounded at base `84d9023b2d7561c3c34929df3e64696bad7b2339`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/adapters/providers/provider-{claude,codex,cursor,gemini}.sh`** — keep: the lens contract globals and functions exactly as they are (`PROVIDER_CLI_NAME="claude"`, `PROVIDER_HOME_SCRUB=1`, `provider_build_argv()`, `provider_extract_text()`); probe entries are ADDED beside them, never replacing them. keep: `PROMPT_CONTENT MUST be the LAST element` in `provider_build_argv`. keep: `provider-cursor.sh` deliberately does not pass `-f`/`--force` (`DELIBERATELY NOT PASSING -f/--force`). Its probe's permission entry must reflect that reasoning, not silently adopt `-f`. reuse: the existing header style (dated "verified against a real `--help`" vs "DOCUMENTED ASSUMPTION" wording) for every new probe field. A field not verified on a real binary says so. mirror: `lens-run.sh`'s `PROVIDER-TABLE FILE CONTRACT`. pinned by: `loomwright/docs/vendor-coupling-manifest.json` allowances `"loomwright/scripts/adapters/providers/provider-claude.sh": 3` and `"loomwright/scripts/adapters/providers/provider-cursor.sh": 1` (a new literal vendor token raises them).
- **`loomwright/scripts/adapters/providers/lens-run.sh`** — keep: every line of logic. The only edit is the header list `` (`claude`, `cursor`, `codex`, `gemini` as of this writing — `` turned into a pointer to the `provider-*.sh` files in this dir. keep: `set +e   # FAIL-SAFE beyond usage errors`, the NAME allowlist `""|*[!a-zA-Z0-9_-]*)`, the source line `. "$PROVIDER_FILE"`. mirror (for `setup-providers.sh`): source provider files the same way, with the same `[!a-zA-Z0-9_-]` name allowlist, and launch the smoke the way `lens_exec_cli` does (`perl -e 'setpgrp; exec @ARGV'`, python3 `os.setpgrp()` fallback), with TERM then KILL of the group on expiry. Unlike lens-run, no `env -i`/HOME scrub for the auth and smoke columns (AC10). fired by: `skills/self-heal-advisory/multi-voter.md` via `--voter-provider` (any `provider-<name>.sh` present becomes selectable, so the two new files make `grok`/`copilot` voter-selectable). pinned by: `loomwright/scripts/adapters/providers/test-lens-run.sh` (`provider-teststub<RUN_TAG>.sh`. It writes transient provider files into this same dir, which is why AC12 exists).
- **`loomwright/docs/vendor-coupling-manifest.json`** — keep: `"allowance_reasons"` gets an added or changed one-line entry for every raised/new allowance (the gate's `raise_check`); values come from `--print-allowances`, never hand-typed. reuse: the allowances_note's "DESCRIBES the token rather than quoting it" self-raise-avoidance convention for any prose added there. pinned by: `scripts/test-check-vendor-coupling.sh`.
- **Precedent, not modified — `loomwright/scripts/dispatch-pr-review.sh`**: mirror the `claude` permission probe it already runs (`grep -q 'dontAsk'`, `--allowedTools`, `--disallowedTools`, `PERMISSION_REGIME_UNPINNABLE`) as `provider-claude.sh`'s pinnability data, so the two cannot disagree on what "pinnable" means for `claude`. Mirror WHAT it tests, never HOW: its `printf '%s' "$HELP_OUT" | grep -q` form is banned in any new file. pinned by: `loomwright/scripts/test-no-pipefail-grep-q.sh` (RULE 2, `WRITER_BASELINE` — a file not listed is red). In `setup-providers.sh` and every `provider-*.sh`, use `grep -q PAT <<<"$var"` or `grep -q PAT < <(producer)`.

## Closed enumerations touched

> Sibling grep at base `84d9023b2d7561c3c34929df3e64696bad7b2339`: `git grep -nF 'gemini' -- ':!CHANGELOG.md' ':!.supervisor'` → 9 hits in 4 files.

- **`grok`, `copilot`** (sibling: `gemini`) — must be named in:
  - `loomwright/scripts/adapters/providers/lens-run.sh` — the restated provider list in the `--provider` usage header, quoting `` `claude`, `cursor`, `codex`, `gemini` as of this writing `` — extend by replacing it with a pointer to the `provider-*.sh` files (house rule: a pointer cannot drift).
  - `loomwright/scripts/adapters/providers/provider-gemini.sh` — its own header and `PROVIDER_CLI_NAME="gemini"` — no change: it is the sibling entry itself, not a list.
  - `loomwright/docs/vendor-coupling-manifest.json` — `allowances_note` prose recording the 2026-09-18 entries (`The other two provider files`) — no change: a dated historical record, not a live list.
  - `loomwright/docs/ARCHITECTURE_CONTRACTS.md` — §"Portability" "Second example" (`` `claude`, `cursor`, `codex`, `gemini` as of this writing ``) — no change in this item: the file is in parallel wave-1 item 01's Touches, and the source requirement keeps 02 file-disjoint from 01. The sentence is dated ("as of this writing"). It is handed to item 03 under the owner's `Rule override:` (see `## Rule conflicts (open decisions)`), and the hand-off is recorded in item 03's requirement.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `test-setup-providers.sh` — absent binary → `installed: no` + `not usable: installed` | delete the `command -v` presence check line in `loomwright/scripts/setup-providers.sh` (the row must then mis-report) |
| `test-setup-providers.sh` — not logged in → headless not run | delete the line in `loomwright/scripts/setup-providers.sh` that skips the smoke when auth is not `ok` (the stub's smoke-ran marker must then appear and the pin go red) |
| `test-setup-providers.sh` — hung smoke → `fail:timeout` + group killed | delete the KILL-the-process-group line of the timeout watcher in `loomwright/scripts/setup-providers.sh` |
| `test-setup-providers.sh` — garbage output → `fail:unparseable` | flip the fixed-reply comparison in `loomwright/scripts/setup-providers.sh` to always succeed |
| `test-setup-providers.sh` — `--always-approve`-only stub → `unpinnable`, never `usable for write seats` | flip the verdict's permissions condition in `loomwright/scripts/setup-providers.sh` so `unpinnable` counts as pinnable |
| `test-setup-providers.sh` — writes nothing (repo + temp HOME unchanged) | add a `touch` of a file under `$HOME/.claude/` in `loomwright/scripts/setup-providers.sh` |
| `test-setup-providers.sh` — teststub file with no probe entries skipped | delete the "no probe entries ⇒ skip" guard line in `loomwright/scripts/setup-providers.sh` |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Provider probe: table probe entries + Grok/Copilot entries + `setup-providers.sh check` + stub-backed test + evidence | all | 6 modify, 6 create | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/scripts/setup-providers.sh"}
  - {kind: "symbol", path: "loomwright/scripts/setup-providers.sh", name: "usable for write seats"}
  - {kind: "symbol", path: "loomwright/scripts/setup-providers.sh", name: "fail:timeout"}
  - {kind: "symbol", path: "loomwright/scripts/setup-providers.sh", name: "not_logged_in"}
  - {kind: "file", path: "loomwright/scripts/test-setup-providers.sh"}
  - {kind: "file", path: "loomwright/scripts/adapters/providers/provider-grok.sh"}
  - {kind: "symbol", path: "loomwright/scripts/adapters/providers/provider-grok.sh", name: "PROVIDER_CLI_NAME"}
  - {kind: "symbol", path: "loomwright/scripts/adapters/providers/provider-grok.sh", name: "provider_build_argv"}
  - {kind: "file", path: "loomwright/scripts/adapters/providers/provider-copilot.sh"}
  - {kind: "symbol", path: "loomwright/scripts/adapters/providers/provider-copilot.sh", name: "PROVIDER_CLI_NAME"}
  - {kind: "symbol", path: "loomwright/scripts/adapters/providers/provider-copilot.sh", name: "provider_build_argv"}
  - {kind: "file", path: "docs/evidence/provider-routing-02-providers-probe.md"}
  - {kind: "file", path: "changelog.d/provider-probe-check.md"}
requires: []
lanes:
  - "loomwright/scripts/adapters/providers/provider-*.sh"
  - "loomwright/scripts/adapters/providers/lens-run.sh"
  - "loomwright/scripts/setup-providers.sh"
  - "loomwright/scripts/test-setup-providers.sh"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "docs/evidence/provider-routing-02-providers-probe.md"
  - "changelog.d/provider-probe-check.md"
external_requires:
  - "grok (Grok Build CLI) installed and logged in by the owner before the evidence step (AC2, AC14)"
  - "Vendor docs for Grok Build headless mode and GitHub Copilot CLI, read at build time and cited with dates"
  - "jq on PATH (already a dependency of lens-run.sh)"
```

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| `grok` not installed on this machine (re-checked 2026-10-27), so AC2/AC14 evidence cannot be produced unattended — Feasibility (Phase 2.5) | HIGH | The owner installs and logs in to `grok` before the evidence step (requirement Assumption). If it is still absent, the evidence file records the real `installed: no` row and says plainly that the grok report is outstanding. It never fabricates one, and the run parks rather than claiming AC2 |
| Vendor invocation shapes for `grok`/`copilot` change fast and cannot be verified here — Feasibility (Phase 2.5) | MEDIUM | Read the vendors' current docs at build time and cite URL + date in each file header. Mark every unverified field a DOCUMENTED ASSUMPTION (the existing codex/gemini header convention). The probe reports run-time truth |
| A real smoke writes vendor-side state (e.g. `claude` session transcripts under the real HOME), which contradicts a naive "writes nothing" reading | MEDIUM | AC3 scopes the claim to the script's own writes (asserted with stubs + temp HOME). The `claude` smoke passes `--no-session-persistence` (present in this build's `--help`). The evidence file states the residual vendor-side writes |
| `PROVIDER_HOME_SCRUB=1` breaks `cursor-agent` login, so auth/smoke under a scrubbed HOME would misreport | MEDIUM | AC10: auth and smoke run under the real HOME, and the report header says so. The lens path (`lens-run.sh`) is unchanged |
| Two new provider files make `grok`/`copilot` selectable as `--voter-provider` via `lens-run.sh` with unverified envelopes | MEDIUM | AC13 keeps the full lens contract. An envelope mismatch degrades to `lens_unparseable` (existing fail-safe), and the headers carry the DOCUMENTED ASSUMPTION wording |
| `test-lens-run.sh` (`provider-teststub<pid>.sh`) and `test-lens-compare.sh` (`provider-teststubx/y<pid>.sh`) drop transient provider files into the same dir, so a concurrent `check` could enumerate them | MEDIUM | AC12: files without probe entries are skipped. The test drives `setup-providers.sh` against its own temp providers dir (env override), never the real dir |
| The restated provider list in `ARCHITECTURE_CONTRACTS.md` §"Portability" stays at four names (house rule on restated lists) | LOW | Not editable here without colliding with parallel item 01's lane. The sentence is dated "as of this writing". The owner's `Rule override:` records this, and item 03's requirement now carries the pointer edit as an acceptance criterion. Noted in the PR body |
| Vendor-coupling ratchet trips on new literal tokens (e.g. a `.claude/` path in the test's write-containment assertion, or a `claude -p` shape in a header) | LOW | Prefer describing over quoting where legible. Otherwise raise via `--print-allowances` with an `allowance_reasons` entry (AC16) |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-27-providers-probe-setup-check.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-10-27T13:18:26Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/723
- **Branch:** feature/providers-probe-setup-check
- **Files changed:** 11
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** Read-only always-exit-0 setup-providers.sh check with probe data in every provider-*.sh (new grok, copilot entries cited from vendor docs), 108-case stub test, evidence note with real report (claude usable for write seats; cursor-agent read-only seats; grok/copilot/codex/gemini not installed), changelog fragment. Phase 4.5 iteration 1 fixed a HIGH whole-token pin-match bug plus 3 MEDIUMs (bash 3.2 test parse, AC6 trade-off documented, qualified login hints / gemini smoke JSON); iteration 2 PASS. Real grok report (AC2) outstanding; AC6 scope for no-auth-command providers is an owner decision; ci-local had 3 lane-env/load test failures unrelated to the diff.

## Not verified
- **grok real-binary row (AC2)** — grok not installed on this machine; covered only by stub CLIs in test-setup-providers.sh (subtask 1)
- **copilot/codex/gemini invocation, envelope, auth and pin shapes** — binaries not installed; fields are DOCUMENTED ASSUMPTIONs from vendor docs read 2026-10-27 (subtask 1)
- **full bash scripts/ci-local.sh (AC17)** — worker ran only the --affected plan; Supervisor's full run: 179/182 self-tests, 3 failures (test-automate-lanes/next-step/trail) from lane-session env leakage + machine load, unrelated to the diff; next-step and trail pass with lane env unset, lanes leaves 4 liveness-fixture failures (subtask 1)
- **PR body link to the evidence file (AC14)** — linked by the Supervisor in PR #723's body (subtask 1)
- **--voter-provider grok/copilot via lens-run.sh** — needs a real installed and logged-in binary (subtask 1)
