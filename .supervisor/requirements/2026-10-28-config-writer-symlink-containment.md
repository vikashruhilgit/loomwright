# Config writers refuse a write that a symlinked parent folder sends outside the repo

## Status: pending

**As a** maintainer who runs `/setup` and `/automate` in repos I cloned,
**I want** every plugin script that writes a repo-relative config file to refuse when the real
location of that file is outside the repo,
**so that** a repo that commits a symlinked `.supervisor/` (or `.claude/`) cannot make the plugin
rewrite, or leave backups beside, a file somewhere else on my machine.

Source: the follow-up draft
`proposed/automate-2026-10-28-145528--03-routing-config-readonly-seats-476094--dismissed-07f85eaa.md`
(the claude-review finding on PR #746, MEDIUM, dismissed below the HIGH fix floor and kept as a follow-up).
That finding names `setup-routing.sh` and says the pattern is family-wide. This item covers the family.

## Verified premises (main @ ef98149, 2026-10-28)

- **Reproduced.** In a scratch repo with `.supervisor -> <outside dir>` (an absolute symlink) and an existing
  `<outside dir>/config.json` of `{"keep":1}`, `setup-base-branch.sh set main --repo <repo>`:
  - printed `base-branch: main (source: config)`;
  - rewrote `<outside dir>/config.json` to `{"keep":1,"base_branch":"main"}`;
  - left `config.json.backup.<ts>` beside it.

  `setup-routing.sh` shares the same leaf-only check, so it behaves the same way (see its row below).
  `.supervisor/` is gitignored, but a repo can still commit the symlink with `git add -f`.
- **Repo-relative writers (in scope).** None of them resolves the real path before writing, and none
  checks a symlinked parent folder:

  | Writer | Target | Current symlink defence | Test today |
  |---|---|---|---|
  | `scripts/setup-base-branch.sh` (`refuse_symlink`) | `$REPO/.supervisor/config.json` | `[ -L "$CFG" ]`: refuses a symlinked file only | `test-setup-base-branch.sh` `c_symlink` (file only) |
  | `scripts/setup-routing.sh` (`refuse_symlink`, the `CFG` writes) | `$REPO/.supervisor/config.json` | `[ -L "$2" ]`: file only | `test-setup-routing.sh` `c_symlink` (file only) |
  | `scripts/setup-memory.d/allowlist.sh` (the allowlist write) | `$repo/.supervisor/config.json` | none (`[ -f ]` follows links) | `test-setup-memory.d/02-meta-allowlist.sh`: no symlink case |
  | `scripts/setup-memory.d/gitignore.sh` (gated in `probes.sh`) | `$repo/.gitignore` | `[ -L "$GI" ]`: file only (its parent is the repo root itself) | `03-apply-safety-ledger-gate.sh` case `(f5)` (file only) |
  | `scripts/automate-helpers.d/config.sh` (`config-suppress` / `config-restore`) | `$ROOT/.supervisor/config.json`, run **unattended** around every `/automate` item's RUN phase | none | `test-automate-helpers.d/01-config.sh`: no symlink case |
  | `scripts/set-otel-resource-attrs.sh` | `$ROOT/.claude/settings.local.json` | none | `test-set-otel-resource-attrs.sh`: no symlink case |

  `REPO` in both `setup-*.sh` scripts is resolved with plain `cd "$REPO" && pwd`, which gives the logical
  path, not the physical one.
- **Precedent for the stance.** `scripts/meta-sync.d/managed.sh` (`list_local`) already refuses a
  symlinked `.supervisor` with the message "run history must live inside the checkout". Nothing in the
  plugin creates a `.supervisor` symlink. `commands/insights.md` suggests symlinking
  `.supervisor/insights` into an Obsidian vault, a different path that no config writer touches.
- **Portable idiom already in the repo (bash 3.2, BSD and GNU).** In `scripts/automate-helpers.sh`,
  `gate_eval()` contains `_ge_phys` and `_ge_inside`:
  - `_ge_phys` follows a symlinked final component with plain `readlink`, capped at 40 hops;
  - it then resolves the directory with `CDPATH='' cd -P -- … && pwd -P`;
  - `_ge_inside` walks the ancestors and compares each with `-ef`, so `/tmp` vs `/private/tmp` style
    aliases are treated as the same place.

  `scripts/brief-pointer.sh` (`brief_requirement_path`) uses a simpler `cd … && pwd -P` plus a prefix
  check. There is no shared config-writer library today. Each `setup-*.sh` finds its siblings with
  `script_dir="$(cd "$(dirname "$0")" && pwd)"`, and `setup-memory.sh` / `automate-helpers.sh` source
  their own `*.d/` modules.
- **User-scope writers (out of scope, on purpose).** These targets sit under the user's own `$HOME`,
  not inside a repo a stranger controls:
  - `egress.json` (`setup-routing.sh` grant, `/telemetry`, `/setup webhook`);
  - `meta-sync-consent.json` (`setup-memory.d/commands.sh`);
  - `~/.claude/settings.json` (`setup-statusline.sh`);
  - `rules-check-stamp.json` (`rules-check.sh`).

  A symlink there is the user's own doing. `setup-statusline.sh` deliberately *follows* a symlinked
  `settings.json`, because dotfile managers symlink it (its tests `(l1)`/`(l2)`/`(l5)` pin that), and
  refusing it would be a regression.

## Invariant check (CLAUDE.md §"Failure-Mode Invariants" and related)

- **Bimodal failure.** This is a correctness refusal, so it fails **closed**: nothing written, no
  backup made, a named status printed. It never adds a non-zero exit to a fail-safe emitter. Each
  writer keeps its existing refusal convention (the `setup-*.sh` "ABORTED (<reason>) … nothing was
  written" headline and that script's exit code). The new check adds one reason to that convention;
  it does not change how refusals are signalled.
- **User scope vs repo scope.** CLAUDE.md's telemetry rule says a repo-relative file can at most
  request, never grant. This item applies the same principle to writes: repo content must not be able
  to steer a plugin write outside the repo.
- **Single-drain / config-toggle contract (`skills/automate-loop` §7).**
  - A refused `config-suppress` must stop the item **before RUN**, with a named status, the same way
    "malformed pre-existing config ⇒ abort" does today. Nothing is toggled, so there is no double-drain
    window.
  - `config-restore` must also refuse to write outside the repo. A crash-stranded backup must never be
    restored through a symlink.
- **Merge-gate executor (`gh pr merge --squash` has one executor).** `gate_eval()` and its
  `_ge_phys` / `_ge_inside` are **not edited** by this item (see D2). Touching the sole merge executor
  makes the diff high-risk for no gain here.
- **Committed prose.** Cite code by descriptive anchor, not bare `file:line` (`test-citation-drift.sh`).
- **Tests.** Every new or changed `test-*.sh` sources `hermetic-test-env.sh` first
  (`check-test-hermetic.sh`). Run them under bash, not zsh.

## Scope

### Part 1 — one containment helper

Add `loomwright/scripts/contained-path-lib.sh`, a sourceable library, bash 3.2 safe, with no `realpath`
and no `readlink -f`. It provides:

- `cpl_phys <path>`: the physical path of `<path>`. Follow a symlinked final component (bounded), then
  resolve its directory with `cd -P`/`pwd -P`. Fail on a non-absolute or unresolvable path.
- `cpl_inside <physical-path> <root>`: 0 iff the path's directory is `<root>` or under it, compared by
  `-ef` along the ancestors.
- `cpl_check_write <label> <target> <repo-root>`: prints one refusal headline and returns 1 when either
  of these holds, else returns 0 silently:
  - `<target>` is itself a symlink, giving `symlink`;
  - `cpl_phys <target>`'s directory is not inside `cpl_phys <repo-root>`, giving `path_outside_repo`.

  The target need not exist yet. For a missing file, resolve its nearest existing ancestor folder.

Reuse the `_ge_phys` / `_ge_inside` logic, but copy it rather than move it (D2).

### Part 2 — apply it to every in-scope writer

Call `cpl_check_write` before any backup, temp file or `mkdir -p` in each writer in the table. The
check runs **before** the backup because the backup is itself a write through the symlink.

- In `setup-base-branch.sh` and `setup-routing.sh` the new check replaces `refuse_symlink` for `CFG`.
  `setup-routing.sh` keeps its leaf-only `refuse_symlink` for `EGRESS` (user scope).
- `setup-memory.d/gitignore.sh` is unchanged. Its target is `.gitignore` at the repo root, so there is no
  parent folder below the root to redirect, and its existing symlinked-file refusal stays.
- `config-suppress` refuses with a named status the engine treats like a malformed config (abort before
  RUN). `config-restore` refuses to write or delete outside the repo.
- Resolve the repo root physically (`pwd -P`), so a repo reached through a symlinked path above it (for
  example a checkout under macOS `/tmp`) is **not** refused.

### Part 3 — tests

For every in-scope writer, add cases in its existing test file:

- **(a) Symlinked parent pointing outside the repo.** `.supervisor -> <outside>` (or `.claude -> …` for
  otel) with a pre-existing outside file. Expect a refusal (`path_outside_repo`); the outside folder
  must be byte-identical, with no backup and no temp file.
- **(b) Symlinked parent pointing inside the repo.** `.supervisor -> ./real-supervisor`. Expect the write
  to succeed: the file is inside.
- **(c) Repo reached through a symlinked ancestor.** The repo path goes through a symlink *above* the repo
  root. Expect the write to succeed (no false positive).
- **(d) Symlinked leaf.** Keep the existing case.

Add a self-test for `contained-path-lib.sh` covering relative symlinks, a missing target, a 41-hop link
chain (refused) and `/tmp` vs `/private/tmp` on macOS.

Add at least one mutation control: with `cpl_check_write` neutralized, case (a) of `test-setup-base-branch.sh`
must go red.

### Part 4 — docs

Add one line to `docs/PITFALLS.md`. It says repo-relative config writers refuse a target whose
real location is outside the repo, and that user-scope files are exempt on purpose.

Add a changelog fragment (`changelog.d/`, `bump: patch`).

## Acceptance criteria

1. The repro in Verified premises now refuses. After `setup-base-branch.sh set main` with
   `.supervisor -> <outside>`, the headline names `path_outside_repo`, `<outside>/config.json` is
   byte-identical, and no `config.json.backup.*` and no temp file exist in `<outside>`.
2. The same holds for `setup-routing.sh apply --seat …`, the `setup-memory` allowlist write,
   `config-suppress`, `config-restore` and `set-otel-resource-attrs.sh`. Each has its case (a) green and
   its case (a) red with the check neutralized.
3. Cases (b) and (c) pass for every writer: no false refusal for an inside-pointing symlink or a repo
   under a symlinked path such as macOS `/tmp`.
4. In an `/automate` item whose repo has a symlinked `.supervisor` pointing outside, the item stops before
   RUN with the named status. No `.auto_review` toggle happens, and no backup is written outside.
5. `setup-statusline.sh` still follows a symlinked `settings.json` (`(l1)`/`(l2)`/`(l5)` green), and the
   user-scope writers are unchanged.
6. `gate_eval()` is byte-identical to main (`git diff origin/main -- loomwright/scripts/automate-helpers.sh`
   shows no change inside `gate_eval`).
7. Targeted tests for the touched scripts pass, as do `check-test-hermetic.sh`, `check-doc-currency.sh`,
   `test-citation-drift.sh`, `check-vendor-coupling.sh` and `check-version-bump.sh`.

## Owner decisions (2026-10-28, answered before promoting)

- **D1 — the rest of `.supervisor`:** a separate follow-up item, not this one. This item stays scoped to
  config writers. The engine entry check (refuse to start `/automate`, `/supervisor` and `/autonomous` when
  `.supervisor` resolves outside the repo) is drafted as
  `proposed/2026-10-28-supervisor-dir-containment-at-entry.md`.
- **D2 — copy vs share:** copy `_ge_phys` / `_ge_inside` into `contained-path-lib.sh` and leave `gate_eval()`
  byte-identical (acceptance criterion 6). Moving the merge gate onto the library is a later, separately
  reviewed change.
- **D3 — host mode:** leave `_lw_under_any` to `dismissed-followups/02`, which already records it. Do not
  fold it in here.

## Priority: MVP (security hardening; unattended `config-suppress` is the widest exposure)

## Assumptions

- A repo's own `.supervisor` / `.claude` folders are meant to be real folders inside the checkout.
  `meta-sync` already assumes this.
- No legitimate setup routes `.supervisor/config.json` outside the repo. If an owner does, they can move
  the real folder inside the repo and symlink it the other way.

## Risks

- **False positives.** A path-resolution bug could refuse legitimate writes, for example on macOS `/tmp`,
  case-variant paths or firmlinks. Cases (b)/(c) and the `-ef` ancestor compare are the mitigation.
- **Missing-target resolution.** Resolving a not-yet-existing file's nearest ancestor is the subtle part;
  the library's self-test must pin it.

## Depends on
none

## Touches
loomwright/scripts/contained-path-lib.sh
loomwright/scripts/test-contained-path-lib.sh
loomwright/scripts/setup-base-branch.sh
loomwright/scripts/test-setup-base-branch.sh
loomwright/scripts/setup-routing.sh
loomwright/scripts/test-setup-routing.sh
loomwright/scripts/setup-memory.d/allowlist.sh
loomwright/scripts/test-setup-memory.d/02-meta-allowlist.sh
loomwright/scripts/automate-helpers.d/config.sh
loomwright/scripts/test-automate-helpers.d/01-config.sh
loomwright/scripts/set-otel-resource-attrs.sh
loomwright/scripts/test-set-otel-resource-attrs.sh
loomwright/docs/PITFALLS.md
changelog.d/config-writer-symlink-containment.md
