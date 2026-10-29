# Supervisor Job: Config writers refuse a write that a symlinked parent folder sends outside the repo

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (11 linked worktrees from other sessions; none on this item's branch)
- **Source requirement:** .supervisor/requirements/2026-10-28-config-writer-symlink-containment.md
- **Base commit:** ef981491bdb6314e88ab35759b7cd8ef87684bba

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2-safe shell + jq, the stack every touched writer already uses |
| 2 | Dependency Availability | GO | no new dependency; plain `readlink`, `cd -P`/`pwd -P`, `-ef` (the `_ge_phys`/`_ge_inside` idiom already in `automate-helpers.sh`) |
| 3 | Architecture Fit | GO | one sourceable `scripts/*-lib.sh` library (precedent: `exec-acceptance-lib.sh`), called from each writer before its first write |
| 4 | Scope vs Supervisor Capability | CAUTION | 21 files (17 modify, 4 create) — over the `context-bound` bound, so split into 4 subtasks |
| 5 | Hard Blockers | CAUTION | `test-setup-memory-modules.sh` check 5 pins the setup-memory bundle byte-for-byte to the pre-split base, so any edit to `setup-memory.d/allowlist.sh` turns it red unless the check is re-scoped (Subtask 3); copy/bundle/mutant test layouts lack the new library unless each harness places it (Design §"Library loading") |

**Overall Verdict:** CAUTION

## Task
**Goal:** Every plugin script that writes a repo-relative config file refuses, with a named status and nothing written, when the physical location of that file is outside the repo.

**Problem Statement:**
A maintainer who runs `/setup` and `/automate` in repos they cloned needs every repo-relative config writer to refuse a target whose real location is outside the repo, because a repo that commits a symlinked `.supervisor/` (or `.claude/`) can otherwise make the plugin rewrite — and leave backups beside — a file elsewhere on the machine.
Currently, the writers check only a symlinked *leaf* (`[ -L "$CFG" ]`) or nothing at all; reproduced on main @ ef98149: with `.supervisor -> <outside>`, `setup-base-branch.sh set main` rewrote `<outside>/config.json` and left `config.json.backup.<ts>` beside it. The unattended `config-suppress` around every `/automate` RUN phase is the widest exposure.
Success looks like: all six in-scope writers refuse the symlinked-parent case with `path_outside_repo` (outside folder byte-identical, no backup, no temp), while inside-pointing symlinks and repos reached through a symlinked ancestor (macOS `/tmp`) still write.

## Acceptance Criteria
- [ ] AC1 — Given a scratch repo with `.supervisor -> <outside>` (absolute symlink) and `<outside>/config.json` = `{"keep":1}`, when `setup-base-branch.sh set main --repo <repo>` runs, then its headline is `set: ABORTED (path_outside_repo) — …`, `<outside>/config.json` is byte-identical, and `<outside>` holds no `config.json.backup.*` and no temp file (pinned as case (a) in `test-setup-base-branch.sh`).
- [ ] AC2 — Given the same symlinked-parent fixture (`.claude -> <outside>` for otel), when each of `setup-routing.sh apply --seat …` (and `setup-routing.sh remove`, the other `CFG` write), the `setup-memory` allowlist seed, `automate-helpers.sh config-suppress`, `automate-helpers.sh config-restore` and `set-otel-resource-attrs.sh` runs, then each refuses with `path_outside_repo` in its own convention, the outside folder is byte-identical with no backup/temp file, and each writer's case (a) goes red when its `cpl_check_write` call is neutralized (an in-test gated mutation control — non-empty, differs, `bash -n` — at least in `test-setup-base-branch.sh`; the Pin mutations table covers the rest).
- [ ] AC3 — Given a relative `--root`/config path that names a location inside the repo, (b) `.supervisor -> ./real-supervisor` inside the repo, and (c) a repo whose path runs through a symlink *above* its root (e.g. a checkout under macOS `/tmp`, or `ln -s <real-parent> <link>` then `--repo <link>/repo`), when each in-scope writer runs, then the write succeeds (no false refusal) — cases (b) and (c) green for every writer.
- [ ] AC4 — Given an `/automate` item whose repo has `.supervisor -> <outside>`, when `config-suppress` runs before RUN, then it exits 2 (the code `automate-next-step.sh` already maps to `config_malformed` before the `/autonomous` spawn — anchor `if [ "$rc" = 2 ]; then ns_err "config_malformed`) with stderr naming `path_outside_repo`; no `.auto_review` toggle happens and no backup is written outside. `config-restore` likewise exits 2 naming `path_outside_repo` and neither writes nor deletes the outside config.
- [ ] AC5 — Given the user-scope writers (`setup-statusline.sh`, `egress.json` via `setup-routing.sh`'s grant path, `meta-sync-consent.json`, `rules-check-stamp.json`), when this change lands, then they are unchanged: `setup-statusline.sh` still follows a symlinked `settings.json` (its `(l1)`/`(l2)`/`(l5)` legs green) and `setup-routing.sh` keeps its leaf-only `refuse_symlink` for `EGRESS`.
- [ ] AC6 — Given the merge executor, when `git diff origin/main -- loomwright/scripts/automate-helpers.sh` runs, then it shows no change inside `gate_eval()` (`_ge_phys`/`_ge_inside` copied, never moved).
- [ ] AC7 — Given the finished branch, when the targeted tests run under bash (`test-contained-path-lib.sh`, `test-setup-base-branch.sh`, `test-setup-routing.sh`, `test-setup-memory.sh`, `test-setup-memory-modules.sh`, `test-automate-helpers.sh`, `test-automate-helpers-dispatch.sh`, `test-automate-golden.sh`, `test-verify-queue.sh`, `test-automate-next-step.sh` leg `config_malformed`, `test-set-otel-resource-attrs.sh`, `test-setup-statusline.sh`) plus `check-test-hermetic.sh`, `check-doc-currency.sh`, `test-citation-drift.sh`, `check-vendor-coupling.sh`, `check-token-budget.sh` and `bash scripts/check-version-bump.sh`, then all pass.
- [ ] AC8 — Given `docs/PITFALLS.md`, then it carries one entry saying repo-relative config writers refuse a target whose real location is outside the repo and that user-scope files are exempt on purpose; and `changelog.d/config-writer-symlink-containment.md` exists with first line `<!-- bump: patch -->`, folded by `bash scripts/bump-version.sh`.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| library + docs + release (S1) | `loomwright/docs/PITFALLS.md` (89); release fold: `loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `CHANGELOG.md`, `loomwright/capabilities.json` (written only by `bump-version.sh`) | `loomwright/scripts/contained-path-lib.sh`, `loomwright/scripts/test-contained-path-lib.sh`, `changelog.d/config-writer-symlink-containment.md` | HIGH |
| setup-base-branch + setup-routing (S2) | `loomwright/scripts/setup-base-branch.sh` (276), `loomwright/scripts/test-setup-base-branch.sh` (235), `loomwright/scripts/setup-routing.sh` (577 — replaces its two `refuse_symlink "$label" "$CFG"` call sites in place; no new function body beyond a one-line wrapper), `loomwright/scripts/test-setup-routing.sh` (462), `loomwright/docs/command-parts/setup/base-branch.md` (34), `loomwright/docs/command-parts/setup/providers.md` (31) | — | HIGH |
| setup-memory allowlist (S3) | `loomwright/scripts/setup-memory.d/allowlist.sh` (511 — a single `# cpl-guard` guard in `seed_allowlist`, the one writer of `$CFG` in that module), `loomwright/scripts/test-setup-memory.sh` (362 — one `tsm_part` line + the library placed beside the `MEMB` bundle), `loomwright/scripts/test-setup-memory-modules.sh` (293 — re-scope check 5), `loomwright/scripts/test-setup-memory.d/02-meta-allowlist.sh` (535), `loomwright/scripts/test-setup-memory.d/04-verdicts-trail.sh` (399), `loomwright/scripts/test-setup-memory.d/05-branch-mode-consent.sh` (555) (each: only a library `cp`/`ln -s` into a mutant dir that runs `apply`, if any — MEDIUM, the worker confirms per dir) | `loomwright/scripts/test-setup-memory.d/06-config-containment.sh` (new part: `02-meta-allowlist.sh` is 535 lines, past the module-layout threshold) | MEDIUM |
| automate config toggle + otel (S4) | `loomwright/scripts/automate-helpers.d/config.sh` (129), `loomwright/scripts/test-automate-helpers.d/01-config.sh` (272), `loomwright/scripts/set-otel-resource-attrs.sh` (180), `loomwright/scripts/test-set-otel-resource-attrs.sh` (276) | — | HIGH |

**Module layout (`skills/supervisor-readiness/SKILL.md` §"Module layout"):** the one new responsibility — physical-path containment — gets one home, the CREATE `contained-path-lib.sh`; every writer only calls it. The `_ge_phys`/`_ge_inside` helpers in `automate-helpers.sh` `gate_eval()` are deliberately **copied, not extracted** (owner decision D2 — the merge executor stays byte-identical; a later reviewed change moves it onto the library). The three files at/past 500 lines get only in-place call-site lines (reasons in the map); the new setup-memory test cases go to a new part, not the 535-line `02-meta-allowlist.sh`.

> **Validator-owned surfaces:** `check-doc-currency.sh` scans `docs/` (PITFALLS, command-parts); `check-token-budget.sh` counts `docs/command-parts/setup/*.md` toward the `setup` command budget; `test-automate-helpers-dispatch.sh` pins `config.sh`'s `#:` help lines byte-for-byte via `fixtures/automate-helpers-help/config.golden` (leave those lines unchanged); `check-vendor-coupling.sh` ratchets vendor-path mentions per file (the new library and its test must not name `.claude/`).

**Total estimated files:** 17 modify + 4 create (+ the 4 release files `bump-version.sh` writes)

### Blast-Radius / Impact Prediction
Omitted — no touched subsystem has a verified Twin contract or graph edge (`twin-graph.sh` returned empty groups for all five).

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

## Design (binding for every subtask)

**Library API — `loomwright/scripts/contained-path-lib.sh`** (sourceable, no top-level side effects, bash 3.2, no `realpath`, no `readlink -f`):
- `cpl_phys <path>` — prints the physical path. Copy `_ge_phys` (absolute only; follow a symlinked final component with plain `readlink`, `[ "$n" -le 40 ]` hop cap; `CDPATH='' cd -P -- … && pwd -P` on the directory). **Extension for a missing target:** when the directory does not exist, walk up to the nearest existing ancestor, resolve it with `cd -P`, and re-append the missing tail components; a tail component of `.` or `..` fails. **A symlink anywhere on that walk that does not resolve (dangling) fails** — it must never fall through to "the repo root exists, so inside".
- `cpl_inside <physical-path> <root>` — copy `_ge_inside` (`-ef` ancestor walk) **with one deliberate inversion: when the 256-step cap is exhausted it returns 1 (outside ⇒ refuse)**, not `_ge_inside`'s `return 0`. In `gate_eval` "inside" means "not honoured"; here "inside" means "allowed", so a capped walk must fail closed.
- `cpl_check_write <label> <target> <repo-root> [<symlink-reason>]` — returns 0 silently when the write is allowed. Otherwise sets the global `CPL_REASON`, prints ONE headline `<label>: ABORTED (<reason>) — <why>. Nothing was written.` to stdout, and returns 1. **Relative paths:** before anything else, a relative `<target>` or `<repo-root>` is made absolute by prefixing `$PWD/` (callers pass relative paths today — `setup-memory.sh --root .` sets `repo="$ROOT_OVERRIDE"` verbatim, and `config-suppress <config_path>` is a public helper CLI); only a path that is still unresolvable after that is refused. Order: (1) `[ -L "<target>" ]` ⇒ reason = `<symlink-reason>` (default `symlink`); (2) `cpl_phys <repo-root>` or `cpl_phys <target>` fails ⇒ `path_outside_repo` (unresolvable is refused); (3) `cpl_inside "$(cpl_phys <target>)" "$(cpl_phys <repo-root>)"` fails ⇒ `path_outside_repo`. The root is always resolved physically by the library, so callers need not change how they resolve `REPO`.

**Library loading (one rule for every writer — Plan Review attempt 1 fix):** the library is located from the **executed entry script's directory, `$(dirname "$0")/contained-path-lib.sh`**, never from `BASH_SOURCE` of a sourced module (an `_ah_bundle`/`_sm_bundle` single-file expansion inlines the module text, so a module-relative `../` path points outside the bundle's temp dir), and it is loaded **lazily, inside the guarded writer function, immediately before the `cpl_check_write` call** — never at module top level or in a loader block, so module loaders, `--help`, and every copy/bundle that never reaches a write behave byte-for-byte as before. A library that cannot be loaded is a **refusal in that writer's own convention with reason `containment_unavailable`** (fail CLOSED: nothing written), except the fail-SAFE otel emitter, which exits 0 silently. **Every test harness that runs a copy, bundle or mutant of a writer that reaches a write places `contained-path-lib.sh` beside it** (`test-automate-helpers.sh` `ah_build_bundle` already symlinks every sibling, so it needs nothing; `test-setup-base-branch.sh` `mutant()`, `test-setup-routing.sh`'s mutant helper, the `MEMB` bundle dir in `test-setup-memory.sh` and each mutant dir in `test-setup-memory.d/02`/`04`/`05` that runs `apply` need a `cp`/`ln -s` line). The worker runs each touched suite before and after its change and confirms every pre-existing leg (including every MUTATION CONTROL leg) still reports the same verdict — a mutant that now dies at the library load is a vacuous control, not a pass.

**Call sites (exact literals — the Pin mutations rows below flip them; change a literal only together with its row):**
- `setup-base-branch.sh`: `refuse_symlink()`'s body becomes the single line `cpl_check_write "$1" "$CFG" "$REPO" config_symlink` (the leaf reason stays `config_symlink`, so `c_symlink` stays green); its two callers (`do_set`, `do_remove`) are unchanged and already run before any `mkdir -p`/backup. The helper first loads `$script_dir/contained-path-lib.sh` (`script_dir` is already `$(dirname "$0")`-derived); a failed load prints `<label>: ABORTED (containment_unavailable) — … Nothing was written.` and returns 1 (exit 0, the script's refusal convention).
- `setup-routing.sh`: add a one-line wrapper whose body is `cpl_check_write "$1" "$CFG" "$REPO" symlink` and replace the two `refuse_symlink "$label" "$CFG"` call sites (`apply_routing` and the routing-remove path) with it. `refuse_symlink "$label" "$EGRESS"` (two sites) stays exactly as is — user scope. The wrapper loads `$script_dir/contained-path-lib.sh` lazily as above (`ABORTED (containment_unavailable)` on failure).
- `setup-memory.d/allowlist.sh` `seed_allowlist`: immediately after the jq check, one guard line ending `# cpl-guard`: `{ . "$(dirname "$0")/contained-path-lib.sh" 2>/dev/null || { CPL_REASON=containment_unavailable; false; }; } && cpl_check_write allowlist "$CFG" "$repo" >/dev/null || { echo "  allowlist: SKIPPED — ${CPL_REASON:-containment_unavailable}: $CFG resolves outside $repo or cannot be checked; nothing was written (unchanged)."; return 0; }  # cpl-guard` (the worker may split it across lines, provided every line of the guard ends `# cpl-guard` and the literal `cpl_check_write allowlist` stays on one line). The `allowlist: SKIPPED —` … `(unchanged).` literal convention is kept. `setup-memory.sh` itself is **not** modified — no loader-block change.
- `automate-helpers.d/config.sh`: load the library lazily inside `config_suppress` and `config_restore` from the dispatcher's directory, the way `_ah_source` finds families (`. "$(dirname "$0")/contained-path-lib.sh" 2>/dev/null || abort "containment_unavailable: cannot load contained-path-lib.sh; nothing was written"`); never at module top level, never edit `automate-helpers.sh`. The repo root is derived lexically as the parent of the config file's directory (`<root>/.supervisor/config.json` ⇒ `<root>`). `config_suppress` first line: `cpl_check_write config-suppress "$cfg" "$root" >/dev/null || abort "$CPL_REASON: refusing to write $cfg — it resolves outside $root; nothing was written"` — before the validity checks, the backup `cp` and the `mktemp`. `config_restore`: the same with label `config-restore`, after the missing-backup `die` and before the delete/`mktemp`. Exit code 2 (`abort`) is what `automate-next-step.sh` maps to `config_malformed`; do not edit `automate-next-step.sh`. Leave the `#:` help lines untouched.
- `set-otel-resource-attrs.sh` (a fail-SAFE SessionStart emitter — always exit 0, silent): immediately before `mkdir -p "$ROOT/.claude" 2>/dev/null || exit 0`, the lines `. "$(dirname "$0")/contained-path-lib.sh" 2>/dev/null || exit 0` and `cpl_check_write otel "$SL" "$ROOT" >/dev/null 2>&1 || exit 0`. A missing library exits 0 silently (fail-SAFE), never non-zero.

## Touched-file invariants

> Grounded at base `ef981491bdb6314e88ab35759b7cd8ef87684bba`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/setup-base-branch.sh`** — keep: the fail-safe contract `FAIL-SAFE CONTRACT (mirrors setup-statusline.sh / setup-memory.sh): every REFUSED / ABORTED` (every refusal writes nothing, makes no backup, exits 0); the leaf reason literal `ABORTED (config_symlink)`; reuse: `script_dir="$(cd "$(dirname "$0")" && pwd)"` to locate the library; mirror: the header reasons list (`config_symlink | no_backup_name | backup_failed |`) and `docs/command-parts/setup/base-branch.md`'s list (`` `config_symlink`, `jq_unavailable` ``) both gain `path_outside_repo`; pinned by: `test-setup-base-branch.sh` `c_symlink` (`has "$out" "ABORTED (config_symlink)"`).
- **`loomwright/scripts/setup-routing.sh`** — keep: `FAIL-SAFE CONTRACT (mirrors setup-base-branch.sh): every REFUSED / ABORTED branch writes`; the user-scope leaf check `refuse_symlink "$label" "$EGRESS" || return 0` at both EGRESS sites; the leaf reason `ABORTED (symlink)`; reuse: `script_dir`; mirror: the header `ABORTED reasons: jq_unavailable | config_unparseable | routing_unexpected_shape |` and `docs/command-parts/setup/providers.md` (`` `symlink`, `no_home` ``) gain `path_outside_repo`; pinned by: `test-setup-routing.sh` `c_symlink` (`has "$out" "ABORTED (symlink)"`).
- **`loomwright/scripts/setup-memory.d/allowlist.sh`** (and the unmodified entry `setup-memory.sh`) — keep: the loader's fail-CLOSED rule `A missing, unreadable or empty module fails CLOSED (exit 1, the file named on stderr)`; modules `Listed by name, never globbed`; allowlist's convention `allowlist: SKIPPED —` … `(unchanged).` with `return 0`, and `Backup-first, parse-gated` ordering (the guard precedes `mkdir -p "$(dirname "$CFG")"` and `unique_backup_path`); `usage` and `apply_readiness_event` stay entry-only (check 6 of the modules test); pinned by: `test-setup-memory-modules.sh` check 5 (`bundle minus the Modules map, loader block and markers == $BASE:$BASE_PATH byte-for-byte`) — re-scope it to also strip lines carrying `# cpl-guard` before the comparison, keep its gated mutant, and say so in its header; check 2 (behaviour equals the base on fresh fixtures) must stay green unchanged, which holds because the guard never fires on its fixtures and `$E` runs from `loomwright/scripts/` where the library sits; checks 3 and 4 (`mk_copy` copies only `setup-memory.sh` + `setup-memory.d/`) stay green because the library is loaded lazily inside `seed_allowlist`, never by the loader, and neither check runs `apply`; mutants written from `MEMB` (`ma_mutant` in 02, `$Tm/setup-memory.sh` (t-mut) in 04, `$BMR_MUT`/`$BMF_D`/`$BML_D` and siblings in 05) run from their own temp dirs — any that reach `seed_allowlist` need the library beside them or they print `SKIPPED — containment_unavailable` and their control may go vacuous.
- **`loomwright/scripts/automate-helpers.d/config.sh`** — keep: `A MALFORMED pre-existing config ⇒ ABORT (exit 2)` and the `abort`/`die` split (`abort() { echo "automate-helpers: ABORT: $*" >&2; exit 2; }`), byte-for-byte backup `cp "$cfg" "$bak"`, the `__ABSENT__` marker semantics, atomic `mktemp "${cfg}.XXXXXX"` + `mv -f`; the `#:  config-suppress` help lines (pinned by `fixtures/automate-helpers-help/config.golden` in `test-automate-helpers-dispatch.sh`); mirror: `automate-next-step.sh`'s consumer `if [ "$rc" = 2 ]; then ns_err "config_malformed` (unchanged — the refusal must use exit 2, not `die`'s exit 1); callers: `automate-next-step.sh` (`bash "$H" config-suppress "$CFG_PATH" "$BAK_PATH"`, `ns_config_restore`) and `janitor-report.sh` (`config-restore`); copy layouts that carry only `automate-helpers.sh` + `automate-helpers.d/` (`test-automate-helpers-dispatch.sh` `mk_copy`, `test-verify-queue.sh` `stage()`) must stay green — they never call config-suppress/restore, so the lazy load never runs there; `test-automate-helpers.sh` `ah_build_bundle` symlinks every sibling (`ln -s "$e" "$d/$(basename "$e")"`), so `$(dirname "$0")/contained-path-lib.sh` resolves in the bundle; pinned by: `test-automate-helpers.d/01-config.sh` A1–A3 (their `$WD/config.json` fixtures sit outside a `.supervisor/` dir — the lexical root is then `$WD`'s parent, so they stay inside and green) and `test-automate-next-step.sh` `leg_config_malformed`.
- **`loomwright/scripts/set-otel-resource-attrs.sh`** — keep: `` `set -u` (intentionally NO `set -e` / pipefail), jq-gated, and ALWAYS exits 0 `` (CLAUDE.md bimodal invariant: a fail-SAFE emitter never gains a non-zero exit); `[ "$SO_HOST" = 1 ] && exit 0   # host mode: never reaches settings.local.json`; the parse-gate `jq empty "$SL" 2>/dev/null || exit 0`; fired by: `hooks.json` SessionStart `bash \"${CLAUDE_PLUGIN_ROOT}/scripts/set-otel-resource-attrs.sh\" || true`; pinned by: `test-set-otel-resource-attrs.sh` `== 12. Always exit 0`.
- **`loomwright/scripts/automate-helpers.sh`** — NOT modified (AC6). Source of the copied idiom: `_ge_phys <abs-path> — the PHYSICAL path git would open` and `_ge_inside <physical-path> <top>`.
- **`loomwright/scripts/setup-statusline.sh`** — NOT modified (AC5); it deliberately follows a symlinked `settings.json`.

## Closed enumerations touched

> Sibling grep at base `ef981491bdb6314e88ab35759b7cd8ef87684bba`: `grep -rnF 'config_symlink' --exclude=CHANGELOG.md .` → 6 hits in 3 files; `grep -rnF 'routing_unexpected_shape' --exclude=CHANGELOG.md .` → 4 hits in 3 files.

- **`path_outside_repo`** and **`containment_unavailable`** (sibling: `config_symlink`) — both must be named in:
  - `loomwright/scripts/setup-base-branch.sh` — header ABORTED reasons list, anchor `config_symlink | no_backup_name | backup_failed |` — extend.
  - `loomwright/docs/command-parts/setup/base-branch.md` — the `<set|remove>: ABORTED (<reason>)` list, anchor `` `config_symlink`, `jq_unavailable` `` — extend.
  - `loomwright/scripts/setup-base-branch.sh` — `refuse_symlink()`'s echo of `ABORTED (config_symlink)` — no change: replaced by the library headline, which keeps `config_symlink` as the leaf reason.
  - `loomwright/scripts/test-setup-base-branch.sh` — `c_symlink` header + assertion — no change: the leaf case keeps its reason; new cases (a)–(c) are added beside it.
- **`path_outside_repo`** and **`containment_unavailable`** (sibling: `routing_unexpected_shape`) — both must be named in:
  - `loomwright/scripts/setup-routing.sh` — header `ABORTED reasons: jq_unavailable | config_unparseable | routing_unexpected_shape |` — extend.
  - `loomwright/docs/command-parts/setup/providers.md` — the `ABORTED (<reason>)` list — extend.
  - `loomwright/scripts/setup-routing.sh` / `test-setup-routing.sh` — the shape-abort echo and its assertion — no change: a different reason.
- `automate-helpers.d/config.sh` and `set-otel-resource-attrs.sh` carry no closed reason list (free-text `abort` / silent exit) — no extension needed; `allowlist.sh`'s SKIPPED lines are free text.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-setup-base-branch.sh` — case (a) symlinked parent ⇒ `ABORTED (path_outside_repo)`, outside untouched | flip `cpl_check_write "$1" "$CFG" "$REPO" config_symlink` → `true "$1" "$CFG" "$REPO" config_symlink` in `loomwright/scripts/setup-base-branch.sh` |
| `loomwright/scripts/test-setup-routing.sh` — case (a) apply/remove ⇒ `ABORTED (path_outside_repo)` | flip `cpl_check_write "$1" "$CFG" "$REPO" symlink` → `true "$1" "$CFG" "$REPO" symlink` in `loomwright/scripts/setup-routing.sh` |
| `loomwright/scripts/test-setup-memory.d/06-config-containment.sh` — case (a) allowlist ⇒ `allowlist: SKIPPED — path_outside_repo:` | flip `cpl_check_write allowlist` → `true allowlist` in `loomwright/scripts/setup-memory.d/allowlist.sh` |
| `loomwright/scripts/test-automate-helpers.d/01-config.sh` — case (a) config-suppress ⇒ exit 2, no backup outside | flip `cpl_check_write config-suppress` → `true config-suppress` in `loomwright/scripts/automate-helpers.d/config.sh` |
| `loomwright/scripts/test-automate-helpers.d/01-config.sh` — case (a) config-restore ⇒ exit 2, outside config kept | flip `cpl_check_write config-restore` → `true config-restore` in `loomwright/scripts/automate-helpers.d/config.sh` |
| `loomwright/scripts/test-set-otel-resource-attrs.sh` — case (a) `.claude -> <outside>` ⇒ outside `settings.local.json` byte-identical, exit 0 | flip `cpl_check_write otel` → `true otel` in `loomwright/scripts/set-otel-resource-attrs.sh` |
| `loomwright/scripts/test-contained-path-lib.sh` — 41-hop link chain refused | flip `[ "$n" -le 40 ]` → `[ "$n" -le 99 ]` in `loomwright/scripts/contained-path-lib.sh` |
| `loomwright/scripts/test-contained-path-lib.sh` — leaf symlink ⇒ reason `symlink` | flip `[ -L "$2" ]` → `[ -L "/nonexistent-cpl" ]` in `loomwright/scripts/contained-path-lib.sh` (the worker keeps the leaf test literally `[ -L "$2" ]` inside `cpl_check_write`, or updates this row) |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Containment library + self-test, PITFALLS entry, changelog fragment, version bump | AC6, AC7 (lib test, citation-drift, doc-currency, vendor ratchet, version-bump), AC8 | 1 modify (+4 release files via `bump-version.sh`), 3 create | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` | LAUNCHABLE |
| 2 | setup-base-branch + setup-routing writers, tests (library beside each `mutant` copy), setup docs | AC1, AC2 (routing), AC3, AC5 (EGRESS unchanged), AC7 (their tests, token budget) | 6 modify, 0 create | `skills/unit-testing/SKILL.md` | BLOCKED (by #1) |
| 3 | setup-memory allowlist writer, new test part, modules-test re-scope, library beside test mutants | AC2 (allowlist), AC3, AC7 (`test-setup-memory.sh`, `test-setup-memory-modules.sh`) | 6 modify, 1 create | `skills/unit-testing/SKILL.md` | BLOCKED (by #1) |
| 4 | automate config-suppress/restore + otel writer, tests | AC2 (config-suppress/restore, otel), AC3, AC4, AC7 (`test-automate-helpers.sh`, `test-automate-helpers-dispatch.sh`, `test-automate-golden.sh`, `test-verify-queue.sh`, `leg_config_malformed`, otel test) | 4 modify, 0 create | `skills/unit-testing/SKILL.md` | BLOCKED (by #1) |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/scripts/contained-path-lib.sh"}
  - {kind: "symbol", path: "loomwright/scripts/contained-path-lib.sh", name: "cpl_phys"}
  - {kind: "symbol", path: "loomwright/scripts/contained-path-lib.sh", name: "cpl_inside"}
  - {kind: "symbol", path: "loomwright/scripts/contained-path-lib.sh", name: "cpl_check_write"}
  - {kind: "symbol", path: "loomwright/scripts/contained-path-lib.sh", name: "path_outside_repo"}
  - {kind: "file", path: "loomwright/scripts/test-contained-path-lib.sh"}
  - {kind: "symbol", path: "loomwright/scripts/test-contained-path-lib.sh", name: "hermetic-test-env.sh"}
  - {kind: "symbol", path: "loomwright/docs/PITFALLS.md", name: "path_outside_repo"}
requires: []
lanes:
  - "loomwright/scripts/contained-path-lib.sh"
  - "loomwright/scripts/test-contained-path-lib.sh"
  - "loomwright/docs/PITFALLS.md"
  - "changelog.d/config-writer-symlink-containment.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
  - "CHANGELOG.md"
  - "loomwright/capabilities.json"
external_requires:
  - "bash 3.2 (macOS) and GNU bash; BSD and GNU readlink/dirname/pwd -P"

# Subtask 2
provides:
  - {kind: "symbol", path: "loomwright/scripts/setup-base-branch.sh", name: "cpl_check_write \"$1\" \"$CFG\" \"$REPO\" config_symlink"}
  - {kind: "symbol", path: "loomwright/scripts/setup-base-branch.sh", name: "path_outside_repo"}
  - {kind: "symbol", path: "loomwright/scripts/setup-routing.sh", name: "cpl_check_write \"$1\" \"$CFG\" \"$REPO\" symlink"}
  - {kind: "symbol", path: "loomwright/scripts/setup-routing.sh", name: "path_outside_repo"}
  - {kind: "symbol", path: "loomwright/scripts/test-setup-base-branch.sh", name: "path_outside_repo"}
  - {kind: "symbol", path: "loomwright/scripts/test-setup-routing.sh", name: "path_outside_repo"}
  - {kind: "symbol", path: "loomwright/docs/command-parts/setup/base-branch.md", name: "path_outside_repo"}
  - {kind: "symbol", path: "loomwright/docs/command-parts/setup/providers.md", name: "path_outside_repo"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/contained-path-lib.sh", name: "cpl_check_write"}
lanes:
  - "loomwright/scripts/setup-base-branch.sh"
  - "loomwright/scripts/test-setup-base-branch.sh"
  - "loomwright/scripts/setup-routing.sh"
  - "loomwright/scripts/test-setup-routing.sh"
  - "loomwright/docs/command-parts/setup/base-branch.md"
  - "loomwright/docs/command-parts/setup/providers.md"
external_requires: []

# Subtask 3
provides:
  - {kind: "symbol", path: "loomwright/scripts/setup-memory.d/allowlist.sh", name: "# cpl-guard"}
  - {kind: "file", path: "loomwright/scripts/test-setup-memory.d/06-config-containment.sh"}
  - {kind: "symbol", path: "loomwright/scripts/test-setup-memory.d/06-config-containment.sh", name: "path_outside_repo"}
  - {kind: "symbol", path: "loomwright/scripts/test-setup-memory.sh", name: "06-config-containment"}
  - {kind: "symbol", path: "loomwright/scripts/test-setup-memory-modules.sh", name: "cpl-guard"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/contained-path-lib.sh", name: "cpl_check_write"}
lanes:
  - "loomwright/scripts/setup-memory.d/allowlist.sh"
  - "loomwright/scripts/test-setup-memory.sh"
  - "loomwright/scripts/test-setup-memory-modules.sh"
  - "loomwright/scripts/test-setup-memory.d/06-config-containment.sh"
  - "loomwright/scripts/test-setup-memory.d/02-meta-allowlist.sh"
  - "loomwright/scripts/test-setup-memory.d/04-verdicts-trail.sh"
  - "loomwright/scripts/test-setup-memory.d/05-branch-mode-consent.sh"
external_requires: []

# Subtask 4
provides:
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.d/config.sh", name: "cpl_check_write config-suppress"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.d/config.sh", name: "cpl_check_write config-restore"}
  - {kind: "symbol", path: "loomwright/scripts/set-otel-resource-attrs.sh", name: "cpl_check_write otel"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-helpers.d/01-config.sh", name: "path_outside_repo"}
  - {kind: "symbol", path: "loomwright/scripts/test-set-otel-resource-attrs.sh", name: "path_outside_repo"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/contained-path-lib.sh", name: "cpl_check_write"}
lanes:
  - "loomwright/scripts/automate-helpers.d/config.sh"
  - "loomwright/scripts/test-automate-helpers.d/01-config.sh"
  - "loomwright/scripts/set-otel-resource-attrs.sh"
  - "loomwright/scripts/test-set-otel-resource-attrs.sh"
external_requires: []
```

**Per-subtask test cases (each writer's test file):** (a) symlinked parent → outside, pre-existing outside file, expect refusal naming `path_outside_repo`, outside dir byte-identical (compare a listing + `cksum` before/after), no `*.backup.*`, no temp file; (b) `.supervisor -> ./real-supervisor` (or `.claude -> ./real-claude`) ⇒ write succeeds; (c) repo reached through a symlinked ancestor ⇒ write succeeds; (d) leaf symlink: setup-base-branch/setup-routing keep their existing case; the allowlist, config-suppress/restore and otel writers — which today `mv` over a leaf link and so replace it — gain a NEW leaf case (`config.json`/`settings.local.json` symlinked, even to an inside target) expecting a refusal with reason `symlink` and the link plus its target unchanged (a deliberate tightening, see Risk Assessment). Every new test file sources `hermetic-test-env.sh` first. Subtask 1's self-test covers: relative symlinks (leaf and parent), a missing target (missing file; missing parent dir ⇒ nearest existing ancestor), a dangling parent symlink ⇒ refused, a 41-hop chain ⇒ refused, `/tmp` vs `/private/tmp` (macOS only; a named skip elsewhere), the leaf ⇒ `symlink` / custom reason, relative `<target>`/`<repo-root>` resolved against `$PWD` (allowed when inside), and `CPL_REASON` set on refusal. `06-config-containment.sh` adds a `--root <relative>` case (b).

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2
Subtask 1 ──→ Subtask 3
Subtask 1 ──→ Subtask 4
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 2 | Subtask 3 | none | NO |
| Subtask 2 | Subtask 4 | none | NO |
| Subtask 3 | Subtask 4 | none | NO |
| Subtask 1 | Subtasks 2–4 | none (2–4 only source the library) | YES (requires) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2, Subtask 3, Subtask 4 (parallel — mutually unreachable, zero file overlap)
- **Recommended workers:** 3
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` |
| 2 | `skills/unit-testing/SKILL.md` |
| 3 | `skills/unit-testing/SKILL.md` |
| 4 | `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Scope spans 21 files — Feasibility (Phase 2.5) | MEDIUM | Split `context-bound` into a library subtask and three independent writer subtasks with disjoint lanes |
| `test-setup-memory-modules.sh` check 5 pins the setup-memory bundle byte-for-byte to the pre-split base `a8819a38`; editing `allowlist.sh` turns it red — Feasibility (Phase 2.5) | HIGH | Subtask 3 tags its guard line(s) `# cpl-guard` and re-scopes check 5 to strip those lines before comparing; keeps the gated mutant; documents why in the test header |
| Copy/bundle/mutant test layouts lacking the library turn existing MUTATION CONTROL legs vacuous (they die at the load, not at the mutated code) — Plan Review attempt 1 | HIGH | Lazy load inside the writer from `$(dirname "$0")`; every harness that runs a writer copy places the library beside it; worker diffs each suite's per-leg verdicts before/after |
| False positive on macOS `/tmp` → `/private/tmp`, case-variant paths or firmlinks refuses a legitimate write | HIGH | Root and target both resolved with `cd -P`/`pwd -P`; ancestor compare by `-ef`; cases (b)/(c) per writer and the `/tmp` leg in the library self-test |
| Missing-target resolution: a dangling `.supervisor` symlink could resolve to "nearest existing ancestor = repo root" and pass | HIGH | Library refuses any dangling symlink on the walk; pinned in the self-test |
| Copying `_ge_inside` verbatim keeps its cap-exhausted `return 0`, which here would mean "allowed" (fail-open) | HIGH | Design section mandates `return 1` on cap; reviewer checks the inversion |
| A refusal in `config-suppress` using `die` (exit 1) instead of `abort` (exit 2) would surface as a generic helper error, not `config_malformed`, and may still be handled after state changes | MEDIUM | Call-site literal uses `abort`; AC4 + `leg_config_malformed` verify the mapping |
| The otel emitter gaining a non-zero exit would break the bimodal invariant | MEDIUM | Guard ends `|| exit 0`; a missing library exits 0; test §12 "Always exit 0" stays green |
| Leaf-symlink refusal is NEW for the allowlist, config-suppress/restore and otel writers: an inside-pointing `.supervisor/config.json -> ../shared/config.json` that they used to replace with a regular file is now refused (config-suppress ⇒ exit 2 ⇒ `config_malformed`, `/automate` stops before RUN) | MEDIUM | Deliberate, matching setup-base-branch/setup-routing (replacing a link silently breaks the owner's setup); the refusal names reason `symlink`, the owner moves the real file in place; pinned by each writer's new case (d) |
| Relative `--root`/config path wrongly refused as `path_outside_repo` | MEDIUM | `cpl_check_write` absolutizes relative inputs against `$PWD` first; pinned by a relative-path leg in `test-contained-path-lib.sh` and a `--root <relative>` case (b) in `06-config-containment.sh` |
| Token budget for the `setup` command parts grows by two reason tokens | LOW | Run `check-token-budget.sh`; the ~10% headroom covers two words |
| Vendor-coupling ratchet: the new library/test naming `.claude/` would add mentions | LOW | Keep vendor paths out of the library and its self-test; otel test already carries its allowance |

## Configuration
- **Workers:** 3
- **Mode:** parallel
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-28-config-writer-symlink-containment.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-10-29T07:31:30Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/752
- **Branch:** feature/config-writer-symlink-containment
- **Files changed:** 23
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** armed
- **Summary:** New contained-path-lib.sh (cpl_phys/cpl_inside/cpl_check_write) + self-test; six repo-relative config writers (setup-base-branch, setup-routing repo write, setup-memory allowlist seed, config-suppress/config-restore, otel emitter) refuse a physically-outside target with path_outside_repo (containment_unavailable when the library cannot load); PITFALLS entry; v17.22.1. Phase 4.5: iteration 1 review PASS but required ci red on check-locale-prefix (fixed 08b797a); iteration 2 PASS, CI green. 2 drift findings dismissed as follow-ups.

## Not verified
- **automate-next-step.sh end to end with `.supervisor -> <outside>`** — only the exit-2 → config_malformed mapping was exercised (subtask 4)
- **Backup path containment** — the backup is written only after the config check passes; its own path is not separately checked (subtask 4)
