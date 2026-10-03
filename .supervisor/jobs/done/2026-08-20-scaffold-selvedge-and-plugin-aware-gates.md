# Supervisor Job: Scaffold `selvedge` and make the loomwright-pinned CI gates plugin-aware

**Source requirement:** `.supervisor/requirements/selvedge-extraction/02-scaffold-selvedge-and-plugin-aware-gates.md`
**Base commit:** `97ff83d` (`origin/main` tip at brief authoring)
**Base branch:** `main`
**Prepared by:** Launch Pad, inline under `/automate --resume automate-2026-08-18-124023 --limit 1`
**Revision:** 2 — rewritten after Plan Review attempt 1 returned FAIL with 5 HIGH. Every finding was
independently re-verified against the files before being accepted. See §"What revision 2 changed".

## Environment
- **Project:** `~/Documents/work/AI/ai-agent-manager`
- **CLAUDE.md:** ✓ found
- **Git:** branch `main`, `HEAD == origin/main == 97ff83d` (0 ahead / 0 behind)
- **GitHub CLI:** ✓ authenticated · **jq:** ✓ present (already a hard CI dependency)
- **Open PRs:** 0 · **Blockers:** 0 · **Warnings:** 2

### Warning 1 — two unrelated uncommitted artifacts are in this checkout
`.supervisor/postmortem/results.jsonl` (modified) and `loomwright/docs/SPIKES/IMPECCABLE_TEARDOWN.md`
(untracked). **Neither belongs to this slice.** This slice runs on the Single-Agent Path in the main
checkout, so `git add -A` / `git add .` would sweep both in. **Commit only slice-owned paths, by
name**, and assert at FINALIZE via `git show --stat HEAD`.

### Warning 2 — 10 git worktrees are registered
Pre-existing, out of scope, harmless on the Single-Agent Path. Do not clean them up here.

## Task

**Goal:** Create an empty-but-registered `selvedge` plugin, and teach the three loomwright-pinned CI
gates plus the CI hard-gate self-test loop about multi-plugin layouts — **while every count stays
exactly where it is** (14 agents / 21 commands / 41 skills / 24 hooks).

Pure-infrastructure slice. No QA asset moves. No selvedge agents, skills, commands, hooks, or scripts.

### Dependency on slice 01 — resolved, not dangling
The requirement says "Depends on: 01 (its verdicts shape the scaffold's `hooks.json` and skill
layout)". **This slice ships neither a `hooks.json` nor skills** (Scope step 4 forbids both), so 01's
resolution verdicts do not constrain any file here. 01's contribution to *this* slice is purely
methodological: its `## Method note` prior art for driving plugin install/uninstall non-interactively.
01's verdicts become load-bearing at slice 03/04, not here. Do not go looking for a `hooks.json`
decision to apply.

## Subtask Structure

| # | Title | Est. Files | Status |
|---|-------|-----------|--------|
| 1 | Scaffold `selvedge`, register it, make 3 gates + the CI loop plugin-aware, bump + sweep the version | ~7 create, ~16 modify | LAUNCHABLE |

**Subtask 1 contract:**

```yaml
requires: []          # single-subtask brief — no sibling to depend on
provides:
  - {kind: file, path: "selvedge/.claude-plugin/plugin.json"}
  - {kind: file, path: "selvedge/README.md"}
  - {kind: file, path: ".claude-plugin/marketplace.json"}
  - {kind: file, path: "scripts/check-token-budget.sh"}
  - {kind: file, path: "scripts/check-shared-prefix.sh"}
  - {kind: file, path: "scripts/check-contract-parity.sh"}
  - {kind: file, path: "scripts/test-check-token-budget.sh"}
  - {kind: file, path: "scripts/test-check-shared-prefix.sh"}
  - {kind: file, path: "loomwright/scripts/test-check-contract-parity.sh"}
  - {kind: file, path: ".github/workflows/ci.yml"}
  - {kind: file, path: "CHANGELOG.md"}
lanes:
  - "selvedge/**"
  - "scripts/check-*.sh"
  - "scripts/test-check-*.sh"
  - "loomwright/scripts/test-check-contract-parity.sh"
  - ".github/workflows/ci.yml"
  - ".claude-plugin/marketplace.json"
  - ".claude-plugin/README.md"
  - "loomwright/.claude-plugin/plugin.json"
  - "CLAUDE.md"
  - "README.md"
  - "AGENT_GUIDELINES.md"
  - "CHANGELOG.md"
  - "loomwright/commands/agent-help.md"
  - "loomwright/docs/ARCHITECTURE.md"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
```

Every `provides` entry is `{kind, path}` addressable on disk, and every `lanes` entry is a
repo-relative glob resolving to an existing file or an existing parent — both required by
``loomwright/skills/supervisor-readiness/SKILL.md:279 [pins: `addressable on disk`]`` and
``:305 [pins: `Every lane path SHOULD resolve`]``. This matters concretely: the Supervisor's
per-subtask `outputs_verified` gate keys on `provides`, so free-text tokens would make the **only**
per-subtask gate on a ~23-file slice a silent no-op.

## Configuration

- **Mode:** single-agent (no fan-out), Single-Agent Path
- **Recommended workers:** 1
- **Base branch:** `main`
- **Base commit:** `97ff83d`
- **Cost profile:** default (`inherit`) — `--cheap` was not passed to this run

## Parallelism Analysis

**single-agent (no fan-out) — Decomposition Threshold = 1.**

A split was considered and rejected on measured overlap. Any plausible cut
(scaffold │ gates │ version-bump) collides: `.claude-plugin/marketplace.json` is touched by both the
scaffold and the version sweep; the sweep touches all 9 doc-currency surfaces including
`plugin.json`; and — decisively, see Measured fact 9 — the contract-parity widening and its fixture
update **must land in the same commit** or 14 hard-gate cases go red. Sequential, one worker, one branch.

- **Recommended workers:** 1

---

## Measured facts (read off disk at `97ff83d`; re-verify before editing)

Citations are pinned per CLAUDE.md's convention (`file:N [pins: <token>]`) so they can be re-derived
after an insertion above them.

1. **The gate scripts live in the repo-root `scripts/` dir, not `loomwright/scripts/`.**
   `ls scripts/` → `check-command-sync.sh`, `check-contract-parity.sh`, `check-doc-currency.sh`,
   `check-shared-prefix.sh`, `check-skills-index-sync.sh`, `check-token-budget.sh`,
   `test-check-shared-prefix.sh`, `test-check-token-budget.sh`, `validate-version.sh`.
   `ci.yml` invokes them as `bash scripts/<name>.sh`.

2. **The three pins, verbatim:**
   - ``scripts/check-token-budget.sh:50 [pins: `TOKEN_BUDGET_AGENTS_DIR:-loomwright/agents`]`` (with
     `SKILLS_DIR` and ``TOKEN_BUDGET_JSON:-loomwright/docs/prompt-token-budgets.json`` on the two
     following lines)
   - ``scripts/check-shared-prefix.sh:33 [pins: `SHARED_PREFIX_CANONICAL:-loomwright/docs/shared-agent-prefix.md`]``
     and ``:34 [pins: `SHARED_PREFIX_AGENTS_DIR:-loomwright/agents`]``
   - ``scripts/check-contract-parity.sh:46 [pins: `PLUGIN="$ROOT/loomwright"`]``

3. **`check-shared-prefix.sh` fails LOUDLY on a 0-agent run** —
   ``scripts/check-shared-prefix.sh:129 [pins: `refusing to pass a 0-agent gate`]``, guarded by an
   `agent_count` counter. This is why Scope step 4 forbids an empty `selvedge/agents/`.

4. **`check-skills-index-sync.sh`'s `run_gate()` is THE discovery idiom to copy** —
   ``scripts/check-skills-index-sync.sh:158 [pins: `run_gate() {`]`` through its `return $rc`, with
   ``:50 [pins: `MARKETPLACE_JSON=".claude-plugin/marketplace.json"`]``. Its shape:
   ```sh
   run_gate() {
     if [ -n "${CHECK_SKILLS_DIR:-}" ] || [ -n "${CHECK_SKILLS_INDEX:-}" ]; then   # env escape hatch
       ... single check ...; return $?
     fi
     command -v jq >/dev/null 2>&1 || { echo "...: jq required for marketplace plugin discovery" >&2; return 1; }
     [ -f "$MARKETPLACE_JSON" ] || { echo "...: marketplace manifest not found: $MARKETPLACE_JSON" >&2; return 1; }
     local rc=0 checked=0 src sdir
     while IFS= read -r src; do
       [ -n "$src" ] && [ "$src" != "null" ] || continue
       sdir="${src#./}"; sdir="${sdir%/}/skills"
       [ -d "$sdir" ] || continue          # <-- SKIP SILENTLY: plugin ships no such tree
       checked=$((checked + 1))
       run_check "$sdir" "$sdir/SKILLS_INDEX.md" || rc=1
     done < <(jq -r '.plugins[].source' "$MARKETPLACE_JSON")
     if [ "$checked" -eq 0 ]; then         # <-- ANTI-DRIFT TRIPWIRE
       echo "...: no ...-bearing plugin sources found via $MARKETPLACE_JSON — gate matched nothing (anti-drift tripwire)" >&2
       return 1
     fi
     return $rc
   }
   ```
   Both required behaviours are already here: `[ -d … ] || continue` = **skip silently**; the
   `checked -eq 0` tripwire plus each `run_check`'s internal guards = **fail loudly**.

5. **`ci.yml`'s hard-gate loop globs `loomwright/scripts/test-*.sh`** —
   ``.github/workflows/ci.yml:62 [pins: `tests=(loomwright/scripts/test-*.sh)`]``, with
   `shopt -s nullglob` plus an explicit `[ "${#tests[@]}" -gt 0 ]` count check.
   **The root `scripts/test-*.sh` files are NOT in that loop** — `test-check-token-budget.sh` and
   `test-check-shared-prefix.sh` are invoked by name in their own steps
   (``ci.yml:38 [pins: `bash scripts/test-check-token-budget.sh`]``,
   ``ci.yml:43 [pins: `bash scripts/test-check-shared-prefix.sh`]``). Preserve that split; do not
   silently fold them into the loop.

6. **`.claude-plugin/marketplace.json` entries are FULL manifests** — each carries `description`,
   `version`, `author`, `license`, `keywords`. **What the gate actually enforces is narrower:**
   ``scripts/validate-version.sh:83 [pins: `jq -c '.plugins[]'`]`` loops the entries and checks only
   that `.source` is present and resolvable and that `.version` matches the plugin's own
   `plugin.json`. `description` / `author` / `license` / `keywords` are a **sibling-consistency
   convention**, not gate-enforced — follow it because the requirement asks for it, not because CI
   would catch you.

7. **The local manifest is `"name": "atelier"` — the SAME name as the marketplace already registered
   on this machine from the REMOTE git URL** (`claude plugin marketplace list` →
   `atelier / Source: Git (https://github.com/vikashruhilgit/loomwright.git)`). Per the requirement's
   `## Method note` §1–2: do **not** `claude plugin marketplace add <repo-root>`, and do **not** run
   `claude plugin install selvedge@atelier` — it resolves against the remote, where an unmerged local
   plugin does not exist, and returns a **false** "not found".

8. **Version is `15.36.0`** (``loomwright/.claude-plugin/plugin.json:3``).
   ``scripts/check-doc-currency.sh:61 [pins: `FILES=(`]`` opens the authoritative 9-surface list:
   `CLAUDE.md`, `README.md`, `AGENT_GUIDELINES.md`, `.claude-plugin/README.md`,
   `.claude-plugin/marketplace.json`, `loomwright/.claude-plugin/plugin.json`,
   `loomwright/commands/agent-help.md`, `loomwright/docs/ARCHITECTURE.md`,
   `loomwright/docs/ARCHITECTURE_CONTRACTS.md`. `.github/workflows/*.yml` is deliberately unscanned
   (reason in-script) — **do not put a version or count claim in `ci.yml`.**

9. **`check-contract-parity.sh`'s self-test lives at `loomwright/scripts/test-check-contract-parity.sh`
   — inside `ci.yml`'s hard-gate loop — and its fixtures contain NO marketplace manifest.**
   `grep -c 'marketplace\|claude-plugin' loomwright/scripts/test-check-contract-parity.sh` → **0**.
   Its `make_fixture()` creates only `$d/loomwright/{hooks,agents,scripts,skills/…}`. **13 of its 14
   cases** invoke `bash "$GUARD" --root "$TMP/<fixture>"`; the exception is case 5
   (``loomwright/scripts/test-check-contract-parity.sh:386 [pins: `--root "$REPO_ROOT"`]``), which runs
   against the live repo. **Consequence:** naively copying fact 4's idiom into this gate makes it
   hard-fail `[ -f "$MARKETPLACE_JSON" ]` on all 13 fixture cases, red-lining them *and* the CI
   hard-gate loop. This is the single most important fact in this brief. (The `$ROOT`-relative path
   base in §"The discovery path base" is what keeps case 5 working too.)

10. **No sibling plugin ships a `scripts/` dir.** `stackpack/` contains only `.claude-plugin/`,
    `README.md`, `skills/`; `mysql-mcp/` only `.claude-plugin/`, `.mcp.json`, `README.md`. Selvedge
    ships none by design. **After this slice, exactly one plugin has a `scripts/` dir**, so the
    per-plugin loud-on-empty branch has **no live subject** and there is no `ci.yml` test harness
    anywhere in the repo. See AC6 for how this is handled honestly.

11. **`.claude-plugin/marketplace.json` IS a scanned doc-currency surface (fact 8), and its
    descriptions are live text for the count patterns:**
    ``scripts/check-doc-currency.sh:138 [pins: `[0-9]+ quality gate hooks`]``,
    ``:144 [pins: `[0-9]+ agent roles,`]``, ``:151 [pins: `[0-9]+ slash commands`]``, and a
    skills pattern. The counts are derived from **loomwright only**
    (``check-doc-currency.sh:55 [pins: `find loomwright/skills`]``). Stackpack's neighbouring
    description survives only by punctuation accident — it reads `…; 18 skills, no agents/commands/hooks`,
    and `; ` does not match `and `. **So a selvedge description phrased "…N agents and N skills…"
    would red the gate.**

12. **Registering a 4th plugin staleifies FIVE current-tense claims that NO gate covers**
    (`check-doc-currency.sh` has no plugin-count pattern — this drift is silent and CI-green).
    Revision 2 named only the first two; the enumeration was completed after Plan Review pointed out
    that a count-only sweep leaves the *lists* stale:
    - ``CLAUDE.md:25 [pins: `three sibling plugins`]`` — **both** the word "three" **and** its
      parenthetical `(loomwright, stackpack, mysql-mcp)`. Changing only the number leaves a list that
      contradicts it.
    - ``CLAUDE.md:34 [pins: `Sibling plugins:`]`` — enumerates `stackpack/` and `mysql-mcp/` only.
    - ``.claude-plugin/README.md:424 [pins: `lists 3 plugins`]``
    - ``.claude-plugin/README.md:426 [pins: `Sibling plugin: 18 tech-stack`]`` and the `mysql-mcp/`
      row beneath it — the file-tree listing has no `selvedge/` row.
    ``README.md:27 [pins: `NEW in v15.6.0`]`` also matches but is a **dated historical banner** — a
    fixed point. **Leave it alone.**

13. **The three gates have NO manifest-path override; only `validate-version.sh` does** —
    ``scripts/validate-version.sh:5 [pins: `CHECK_MARKETPLACE_JSON`]``. `check-skills-index-sync.sh`
    hardcodes its path (fact 4). **And every existing self-test case drives its gate exclusively
    through the per-gate env overrides** —
    ``scripts/test-check-shared-prefix.sh:33 [pins: `SHARED_PREFIX_CANONICAL="$CANON"`]`` is the only
    invocation in that file; ``scripts/test-check-token-budget.sh:72 [pins: `TOKEN_BUDGET_AGENTS_DIR="$1"`]``
    is the same shape (its one non-env run at ``:261 [pins: `OUT="$(bash "$GATE" 2>&1)"`]`` hits the
    live repo, whose discovery result is identical to the pinned default). **Consequence: with
    discovery layered under an escape hatch that returns first, a negative test that deletes the
    discovery branch would still PASS — the branch was never on the path.** See AC4 for the fix.

---

## Acceptance Criteria

- [ ] **AC1 — scaffold, with the content the requirement specifies.** `selvedge/` exists with
      `plugin.json` (`name: selvedge`, `version: 1.0.0`) + `README.md`; **no** `agents/`, `skills/`, or
      `hooks/` dir. The `plugin.json` carries a **short one-sentence** description mirroring
      stackpack's shape (**not** a changelog, **not** loomwright's ~50-entry keyword list — a focused
      keyword list), and `author` + `license` matching the siblings. `README.md` states explicitly
      that selvedge is a **companion requiring `loomwright@atelier`, not a standalone install**.
      The description carries **no** `N agents` / `N skills` / `N commands` / `N hooks` phrasing
      (fact 11).
- [ ] **AC2 — registered.** `.claude-plugin/marketplace.json` lists 4 plugins with a full sibling-shaped
      entry for selvedge (`version: 1.0.0`, matching its `plugin.json`);
      `validate-version.sh --self-test` and `validate-version.sh` both pass.
- [ ] **AC3 — installs cleanly locally, verified by substitute** (requirement `## Method note` §2–3;
      the literal `/plugin install selvedge@atelier` is unavailable here *and* would return a false
      negative — fact 7). Required sequence, all recorded:
      1. `claude plugin validate selvedge/.claude-plugin/plugin.json` and
         `claude plugin validate .claude-plugin/marketplace.json`, each also with `--strict`.
      2. Build a throwaway scratch marketplace under a temp dir with a **DISTINCT** name (follow
         `loomwright/docs/SPIKES/cross-plugin-probe/run-probe.sh`), then
         `claude plugin marketplace add <scratch-dir> --scope local` and
         `claude plugin install selvedge@<scratch-name> --scope local`.
      3. **Primary assertion:** `claude plugin list` shows **selvedge present and enabled**. This —
         not the `details` output — is the load-bearing evidence, because a zero-component inventory
         is trivially true of a plugin that ships zero components and cannot distinguish "installed
         and correctly empty" from "install silently no-oped".
      4. **Secondary:** `claude plugin details selvedge` shows a zero-component inventory (the honest
         stand-in for the AC's `/agent-help` clause, which has nothing to list because this slice
         ships no components). Report AC3 as **satisfied-by-substitute with the reason** in the PR —
         do not silently drop it, and do not edit the AC to match what was done.
      5. **Teardown, asserted:** `claude plugin uninstall selvedge`,
         `claude plugin marketplace remove <scratch-name>`, then re-read
         `claude plugin marketplace list` and confirm the owner's **`atelier` entry is still present
         and still sourced from the git URL**. Every teardown assertion must be able to fail —
         slice 01 shipped four that all failed OPEN and had to be healed.
      6. Every nested `claude` call is headless `claude -p` with a **bounded** poll
         (`IFS= read -r -d '' -t N` — stock macOS has no `timeout`); a deadline expiry is recorded as
         **UNMEASURED**, never as a negative result.
- [ ] **AC4 — all three gates plugin-aware, each with a negative-path self-test that genuinely fails
      when the new per-plugin branch is removed.** Because of fact 13 this requires two things, not one:
      1. **Each widened gate accepts a manifest-path override.** Reuse the existing name
         **`CHECK_MARKETPLACE_JSON`** (`validate-version.sh:5`) rather than minting a fourth
         convention. Without it discovery cannot be pointed at a fixture, so it cannot be negatively
         tested at all.
      2. **The new negative cases must actually REACH discovery.** For `check-token-budget.sh` and
         `check-shared-prefix.sh` that means running with `TOKEN_BUDGET_*` / `SHARED_PREFIX_*`
         **unset** and `CHECK_MARKETPLACE_JSON` pointed at a **fixture manifest listing two plugin
         sources** — a case that sets a per-gate override returns before discovery and proves nothing.
         For `check-contract-parity.sh` the shape is **different and must not be copy-pasted**:
         `--root` is not a discovery escape hatch, it is the base path for `HOOKS`/`AGENTS`, so
         "unset `--root`" would just point the gate at the live repo. Its negative case is
         **`--root <two-plugin-fixture>`**, where the fixture tree contains a
         `.claude-plugin/marketplace.json` listing two plugin sources (per §"The discovery path base").
      3. **Mutation control is performed, not asserted:** for each gate, delete the new per-plugin
         branch, re-run its self-test, record that it **FAILS**; restore, re-run, record that it
         **PASSES**. Paste both outputs. A widened loop whose self-test still passes with the branch
         deleted is vacuous — this repo has a recorded incident of exactly that
         (`shared-fixture-default-disarms-its-own-assertion`).
- [ ] **AC5 — skip-silently vs fail-loudly are distinguished and both tested, per gate.**
      *Skip silently:* plugin source with no relevant tree (`[ -d … ] || continue`).
      *Fail loudly:* tree exists but is malformed — an **empty agents dir** (fact 3), a `skills/` with
      no `SKILLS_INDEX.md`, and — for token-budget — **an agents dir present with its
      `prompt-token-budgets.json` missing** (that is malformed, not absent, and must fail closed
      per plugin, not skip).
- [ ] **AC6 — the `ci.yml` loop is plugin-aware and keeps loud-on-empty per plugin, proven against a
      fixture** (fact 10: there is no live second subject, so "proven" cannot mean "observed in this
      repo"). Extract the loop body into a small harness driven by a plugin-source list, and record
      **two** runs against a temp fixture tree: (a) a plugin with `scripts/test-*.sh` present → exit 0;
      (b) a plugin with a `scripts/` dir but **no** `test-*.sh` → exit **1**, and the message names
      the plugin. Also preserve the fact-5 split: the two root self-tests stay invoked by name.
      If the harness proves impractical, **say so plainly in the PR and downgrade the claim to
      "unproven against live state"** — do not report "proven" for an unexercised branch.
- [ ] **AC7 — `check-doc-currency.sh` output unchanged for all four counts.** Capture the full output
      (not just the first line — `DRIFT` lines print *after* the `Authoritative →` line) before any
      edit and diff it after. It must not start counting selvedge, and selvedge's new description text
      in the scanned `marketplace.json` must not trip a count pattern (fact 11).
- [ ] **AC8 — full CI green:** `validate-version.sh`, `check-command-sync.sh`, `check-doc-currency.sh`,
      `check-skills-index-sync.sh`, `check-contract-parity.sh`, `check-token-budget.sh`,
      `check-shared-prefix.sh`, the two named root self-tests, and the whole
      `loomwright/scripts/test-*.sh` hard-gate loop (including
      `test-check-contract-parity.sh` — fact 9).
- [ ] **AC9 — version bumped and swept in place across all 9 doc-currency surfaces**, `description`
      fields edited **in place** with no appended version clause, **plus all five silent-drift
      surfaces from fact 12** — updating the **counts AND the enumerations** (a `three`→`four` edit
      that leaves `(loomwright, stackpack, mysql-mcp)` beside it is a half-fix that no gate catches),
      and leaving `README.md:27`'s dated v15.6.0 banner untouched.

## Executable Acceptance

Machine-run by `run-ground-truth.sh`, which parses **leading-`-` bullets from this section only**
(``loomwright/scripts/run-ground-truth.sh:188 [pins: `## Executable Acceptance`]``); the next `## `
heading closes the section, so §"Verification commands (worker-facing)" below is not parsed.

**`corpus-task:` bullets only — deliberately, not by omission.**
``loomwright/skills/supervisor-readiness/SKILL.md:198 [pins: `MUST NOT emit `cmd:``]`` forbids a
machine-authored brief from emitting `cmd:` / bare-shell bullets, and this brief is Launch-Pad-authored
under `/automate`. Revision 2 shipped 23 `cmd:` bullets, which was wrong twice over: it breached that
convention, **and** it verified nothing on this brief's own dispatch path, because Supervisor passes
`run-ground-truth.sh --no-cmd` on the unattended route
(``loomwright/skills/self-heal-advisory/SKILL.md:264 [pins: `NO_CMD_FLAG`]``) and every bullet would
record `unverified` / `cmd_disabled`. The three bullets below are real bundled corpus tasks under
`loomwright/scripts/eval-corpus/`, each deterministic and read-only, and each `--no-cmd`-unaffected.

- corpus-task: version-consistent
- corpus-task: doc-currency-green
- corpus-task: eval-selftest-green

`version-consistent` wraps `validate-version.sh` (AC2 — the gate that will first see the 4th plugin
entry). `doc-currency-green` wraps `check-doc-currency.sh` (AC7/AC9 — the gate that will first see
selvedge's description text in the scanned `marketplace.json`, and the stale plugin-count prose lives
in two of its scanned files). `eval-selftest-green` is the "self-test must stay passing" oracle, which
is the property AC4's mutation control turns on.

**All three were RUN against pristine `97ff83d` before being written here, and all three PASS** —
`bash loomwright/scripts/run-ground-truth.sh --brief <this file>` → `3/3`. That check is not
ceremony: `parity-emit-block` was the natural third pick (a stronger oracle than
`check-contract-parity.sh`'s own Check 1, covering the gate this slice widens most invasively) and it
**already FAILS on pristine main** — `execute-manager.md`'s `EXECUTE_CHECKPOINT` emit-block template
is missing five declared fields (`adjudication_required`, `missing_outputs`, `adjudication_options`,
`adjudication_kind`, `colliding_lanes`). That is a **real pre-existing repo defect, wholly unrelated
to this slice and out of its scope** — but shipping it as an EA bullet would have pinned this job's
ground-truth signal to `advisory_failures` forever for a reason no worker here could fix, which is the
identical defect class to the un-passable counts grep that failed Plan Review revision 2. **Do not add
it back.** The defect itself is tracked separately.

## Verification commands (worker-facing)

**Not machine-parsed.** These are the ones that actually carry AC4 / AC6 / AC7 / commit hygiene — run
each and paste the output into the PR. A pasted result is the evidence; a claim is not.

```sh
# --- AC7: counts unchanged. Capture BEFORE any edit, diff AFTER. ---
# Do NOT pipe to `head -1`: DRIFT lines print AFTER the "Authoritative →" line
# (check-doc-currency.sh:58 vs :79), so a head-1 pipeline reports an identical first
# line on a FAILING run and its exit status is head's, not the gate's.
# Note the field separator is TWO spaces, not one.
bash scripts/check-doc-currency.sh 2>&1 | tee /tmp/doccur-after.txt
grep -qE 'agents=14[[:space:]]+commands=21[[:space:]]+skills=41[[:space:]]+hooks=24' /tmp/doccur-after.txt
diff /tmp/doccur-before.txt /tmp/doccur-after.txt

# --- AC8: every gate, incl. the two root self-tests named by hand in ci.yml ---
for g in check-command-sync check-doc-currency check-contract-parity check-token-budget check-shared-prefix; do
  echo "== $g =="; bash "scripts/$g.sh" || echo "FAILED: $g"
done
bash scripts/validate-version.sh --self-test && bash scripts/validate-version.sh
bash scripts/check-skills-index-sync.sh --self-test && bash scripts/check-skills-index-sync.sh
bash scripts/test-check-token-budget.sh
bash scripts/test-check-shared-prefix.sh

# --- AC8: the ci.yml hard-gate loop, exactly as ci.yml runs it.
# bash, NOT the agent's zsh Bash tool. Includes test-check-contract-parity.sh (fact 9).
bash -c 'set -euo pipefail; shopt -s nullglob; tests=(loomwright/scripts/test-*.sh);
  [ "${#tests[@]}" -gt 0 ] || { echo "no self-tests found" >&2; exit 1; };
  for t in "${tests[@]}"; do echo "== $t =="; bash "$t"; done'

# --- AC9: the ungated plugin-enumeration surfaces (fact 12).
# Grep the ENUMERATION, not just the word "three" — changing "three"→"four" while
# leaving "(loomwright, stackpack, mysql-mcp)" stale would pass a word-only check.
grep -rn 'three sibling plugins\|lists 3 plugins\|stackpack, mysql-mcp\|mysql-mcp)' \
  CLAUDE.md .claude-plugin/README.md
grep -q 'NEW in v15.6.0' README.md   # the dated historical banner MUST survive untouched

# --- AC1: selvedge deliberately empty ---
test ! -d selvedge/agents && test ! -d selvedge/skills && test ! -d selvedge/hooks && echo "OK: empty"

# --- Commit hygiene (Warning 1). Assert over the WHOLE BRANCH, not HEAD~1..HEAD:
# the ordering below prescribes several commits, so a HEAD~1 window is blind to
# anything swept in an earlier one — and with no HEAD~1 at all, git writes `fatal:`
# to stderr with EMPTY stdout, so a `test -z "$(git diff ... HEAD~1 HEAD)"` check
# fails OPEN (passes). Three-dot range against the merge base is the correct window.
test -z "$(git diff --name-only origin/main...HEAD -- \
  .supervisor/postmortem/results.jsonl loomwright/docs/SPIKES/IMPECCABLE_TEARDOWN.md)"

# --- AC4 mutation control: a real edit-run-revert per gate, BOTH outputs pasted.
# --- AC6 fixture harness: two recorded runs (tests present => 0; scripts/ dir but no test-*.sh => 1).
```

## Implementation Guidance

### Ordering — corrected; the naive order is NOT safe
Revision 1 claimed "widen the gates first, it's a no-op while only 3 plugins exist". That is true for
`check-token-budget.sh` and `check-shared-prefix.sh`. It is **false for `check-contract-parity.sh`**
(fact 9): its 14 fixtures have no marketplace manifest, so a widened gate hard-fails
`[ -f "$MARKETPLACE_JSON" ]` on every one of them, and that self-test is inside CI's hard-gate loop.

Safe order:
1. Widen `check-token-budget.sh` and `check-shared-prefix.sh` (no-ops while only 3 plugins exist),
   **together with** their new `CHECK_MARKETPLACE_JSON` override and new fixture-driven negative cases.
2. Widen `check-contract-parity.sh` **and** update `loomwright/scripts/test-check-contract-parity.sh`'s
   `make_fixture()` to write a `.claude-plugin/marketplace.json` into each fixture tree — **in the same
   commit**. There is **no alternative** to this; see §"The discovery path base" for why the tempting
   escape hatch is forbidden.
3. Scaffold `selvedge/`; register it in `marketplace.json`.
4. Bump + sweep the version, plus the fact-12 surfaces.

Run the full gate set after **each** step, not only at the end.

### Follow ONE discovery idiom — with ONE deliberate, documented refinement
Copy `run_gate()`'s shape (fact 4) — the env escape hatch (the existing per-gate overrides must keep
working; the current self-tests depend on them for hermetic fixtures) and the `checked -eq 0`
anti-drift tripwire. Layer discovery *under* the overrides, and add `CHECK_MARKETPLACE_JSON` so
discovery itself is reachable from a test (fact 13 / AC4).

**The discovery path base — the one refinement, applied identically to all three gates.**
`check-skills-index-sync.sh` does `cd "$repo_root"` and then resolves both the manifest
(``:50 [pins: `MARKETPLACE_JSON=".claude-plugin/marketplace.json"`]``) and each `.source`
(``:169 [pins: `sdir="${src#./}"`]``) **relative to CWD**. That is incompatible with
`check-contract-parity.sh`, which bases every path on `$ROOT` from `--root`
(``scripts/check-contract-parity.sh:46 [pins: `PLUGIN="$ROOT/loomwright"`]``). Copied verbatim, its
discovery would ignore `--root` and silently check the **real** `loomwright/` tree from inside every
fixture — flipping the ~10 fixture cases that expect exit 1 into exit 0.

So all three widened gates use:

```sh
MARKETPLACE_JSON="${CHECK_MARKETPLACE_JSON:-$ROOT/.claude-plugin/marketplace.json}"
# ...and resolve each .source relative to `dirname "$MARKETPLACE_JSON"`, NOT to CWD.
```

(For token-budget / shared-prefix, `$ROOT` is their existing `repo_root`.) This is **one idiom with a
documented path-base rule**, not a second idiom — say so in each script's header comment.

**Do NOT gate discovery on "`--root` is the real repo".** It is the obvious way to dodge the fixture
update, and it is forbidden: it makes the new per-plugin branch **unreachable from any fixture**, so
AC4.3's mutation control for that gate could never fail. That is exactly the vacuous-assertion defect
this whole slice exists to prevent, and it is the finding that failed Plan Review revision 1.

### `check-shared-prefix.sh` — record the cross-plugin decision in the header, and make the code match
The canonical prefix stays at `loomwright/docs/shared-agent-prefix.md` (owner decision 2 forbids a
second copy), so selvedge's agents will be checked against **another plugin's file** — a real
cross-plugin dependency. Write into the script's header comment: that this is intended, why, and what
happens if `loomwright` is absent from the manifest. Then **decide that behaviour in code and cover it
with a test.** A header comment describing behaviour the code lacks is precisely the defect class this
repo's `rules-violated-by-their-own-surrounding-text` lesson names.

### `check-token-budget.sh` — budgets are PER PLUGIN
Each plugin's agents are budgeted against **that plugin's own** `prompt-token-budgets.json` (selvedge
gets one in slice 04). Agents-dir-present-but-budget-file-missing is the **malformed** case: fail
loudly, per plugin. Do not let it fall into the skip-silently branch (AC5).

### `check-contract-parity.sh` — add a plugin dimension, flip nothing
`MANIFEST` and `ENUMS` rows gain a plugin column so a row can name which plugin owns its `hooks.json`
and agent. **Every row still points at loomwright after this slice.** Slice 04 flips the two QA rows —
resist flipping them early; the agent files have not moved.

### `check-command-sync.sh` — confirm, do NOT touch
The requirement's Out-of-scope is explicit: it targets only `loomwright/commands/code-reviewer.md` and
is genuinely unaffected. **Confirm that by reading it; make no edit.** With three sibling gates being
widened, "make check-command-sync plugin-aware too" is the obvious scope drift. Don't.

### Version bump
`15.36.0 → 15.37.0` (minor: a new plugin is registered and three gates gain a capability; no breaking
change, no count change). Sweep **in place** across the 9 surfaces (fact 8) plus a new top
`CHANGELOG.md` entry. Per CLAUDE.md: edit `description` fields in place, **never append another
version clause**; write the CLAUDE.md latest-change banner **without version numbers or counts**. Do
not add a version/count claim to `ci.yml` (fact 8).

### Portability
bash 3.2 (macOS) + Ubuntu-clean. No GNU-only `stat -c` / `sed -i` / `date` flags; no
`${var//[[:space:]]/}` on large strings. **Validate scripts with `bash file.sh`** — the agent's Bash
tool runs zsh, and a zsh artifact reads as a false failure. Wrap glob loops in `bash -c` with
`shopt -s nullglob`.

### Commit hygiene
Commit only slice-owned paths, by name. Verify at FINALIZE that neither
`.supervisor/postmortem/results.jsonl` nor `loomwright/docs/SPIKES/IMPECCABLE_TEARDOWN.md` entered the
commit.

## Risks

| Risk | Mitigation |
|---|---|
| **A negative test that cannot fail** — discovery sits behind an escape hatch every existing test case sets (fact 13). | AC4: add `CHECK_MARKETPLACE_JSON`; new cases run with per-gate overrides **unset**; mutation control is an edit-run-revert with both outputs pasted. |
| **Widening contract-parity red-lines 14 hard-gate cases** (fact 9). | Ordering step 2: gate widening and fixture update land in the same commit. |
| **AC6 claims "proven" for a branch with no live subject** (fact 10). | Fixture harness with two recorded runs, or an honest downgrade stated in the PR. |
| **Selvedge's description trips a doc-currency count pattern** (fact 11). | `marketplace.json` **is** scanned; keep the description free of `N agents`/`N skills`/`N commands`/`N hooks` phrasing. AC7 diffs full output. |
| **Silent, CI-green plugin-count drift** (fact 12). | AC9 names all five file:line targets; the worker-facing greps cover the enumerations as well as the numbers, and assert the dated banner survives. |
| **This PR's own review lens silently does not run.** Scope step 6 forces a `ci.yml` edit, and `anthropics/claude-code-action` **self-skips any PR that modifies a workflow file while exiting 0** — a green `claude-review` check with **zero comments**. For a slice whose entire thesis is "a gate that cannot fail is worse than no gate", this is the failure mode arriving through the front door. | **Never assert on check conclusion.** Assert on **posted content**: `gh pr view <n> --json comments,reviews` must show a review actually posted, and unresolved review threads must be read via GraphQL (there is no `--json reviewThreads` flag). If the self-skip fires, say so plainly in the PR — a green check with no comments is UNREVIEWED, not clean. |
| **False "not found" from `claude plugin install selvedge@atelier`** (fact 7). | Scratch marketplace with a distinct name; never add the repo root. |
| **Teardown clobbers the owner's live `atelier` registration.** | Distinct scratch name + `--scope local`; assert afterwards that `atelier` is still present and git-sourced. |
| **AC3 reported satisfied when nothing was verified.** | Primary assertion is `claude plugin list` showing selvedge **present and enabled**, not the trivially-true empty `details`. |
| **A widened gate silently stops covering loomwright.** | Mutation control (AC4) plus before/after gate-output diffs against the live repo. |
| **An unrelated uncommitted file swept into the commit.** | Named-path commits; `git show --stat HEAD` assertion. |
| **Scope drift into `check-command-sync.sh`.** | Explicit do-not-touch guidance above, carried from the requirement's Out-of-scope. |

## Outcomes Rubric

7 bullets, each **diff-checkable from the PR diff alone** (the bound is 3–7 per
``loomwright/skills/supervisor-readiness/SKILL.md:182 [pins: `3-7 bullets`]``). Revision 2 had 8, two
of which depended on pasted runtime evidence rather than the diff; those are rephrased here as
assertions about what the diff must *contain*, and the runtime evidence itself remains required by
AC3 / AC4 / AC6.

- [ ] `selvedge/` contains exactly `.claude-plugin/plugin.json` (v1.0.0) + `README.md` — no `agents/`, `skills/`, or `hooks/` dir — and is registered as the 4th entry in `.claude-plugin/marketplace.json`
- [ ] All three widened gates resolve the manifest via `CHECK_MARKETPLACE_JSON` defaulting to `$ROOT/.claude-plugin/marketplace.json`, with `.source` resolved relative to the manifest's dir — one idiom, one path-base rule, documented in each script header
- [ ] Each widened gate's self-test file gains at least one case that **reaches discovery** (per-gate override unset, or `--root <two-plugin-fixture>` for contract-parity) — the diff shows a test that the pre-change code could not have passed
- [ ] `loomwright/scripts/test-check-contract-parity.sh`'s `make_fixture()` writes a `.claude-plugin/marketplace.json` into each fixture tree, in the same commit as the contract-parity widening
- [ ] Skip-silently (`[ -d … ] || continue`) and fail-loudly (empty agents dir; `skills/` with no index; agents dir with no `prompt-token-budgets.json`) are separate, named branches with a test case each
- [ ] `.github/workflows/ci.yml`'s hard-gate loop iterates plugin sources and retains a per-plugin loud-on-empty guard, while the two root self-tests stay invoked by name
- [ ] The version is swept in place across the 9 doc-currency surfaces and all five fact-12 enumeration surfaces (counts **and** plugin lists), with `README.md`'s dated v15.6.0 banner unchanged and no appended version clause in any `description`

## What revision 2 changed

All five Plan Review HIGH findings were re-verified against the files, all five confirmed, all five fixed:

- **H1 → facts 13 + AC4.** Discovery was untestable: no gate has a manifest-path override, and every
  existing self-test case drives its gate through the per-gate env override, which returns *before*
  discovery. Fix: reuse `CHECK_MARKETPLACE_JSON`; negative cases run with per-gate overrides unset.
- **H2 → fact 9 + corrected ordering.** `loomwright/scripts/test-check-contract-parity.sh` (never
  mentioned in rev 1) has 14 cases whose fixtures contain no manifest; the "widen first, it's a no-op"
  ordering was wrong for that gate. Fix: named as a modify target; widening + fixture update in one commit.
- **H3 → fact 10 + rewritten AC6.** No sibling ships a `scripts/` dir, so AC6's per-plugin branch has no
  live subject, and rev 1's EA §4 reproduced the *pre-change* loop — green either way. Fix: fixture
  harness with two recorded runs, or an honest downgrade.
- **H4 → fact 11.** Rev 1's Risks table said doc-currency "reads loomwright only" — true of the count
  *derivation*, false of the *scanned surfaces*, and `marketplace.json` is where selvedge's description
  lands. Fix: stated as a mechanism, with the phrasing constraint in AC1.
- **H5 → fact 12 + AC9.** `CLAUDE.md:25` and `.claude-plugin/README.md:424` go stale on registration and
  no gate covers it. Fix: both named, both grepped in EA, dated banner explicitly preserved.

MEDIUM findings M1–M6 and LOW L1–L3 were also addressed: EA converted to parser-visible bullets
(M1); the requirement's scaffold content requirements carried into AC1 (M2); the
`check-command-sync.sh` do-not-touch guard carried over (M3); AC3's primary assertion moved to
`claude plugin list` (M4); the un-failable `| head -1` proof replaced (M5); subtask contract blocks
added (M6); citations pinned and the two off-by-one ranges corrected (L1); fact 6 narrowed to what the
gate actually enforces (L2); the slice-01 dependency resolved explicitly (L3).

## What revision 3 changed

Plan Review attempt 2 confirmed revision 2 closed H2 and H4 outright, closed H1 for two of three gates
and H3 at the AC level, and partially closed H5 — but found **3 new HIGH in the material revision 2
added**. Each was independently re-verified against the files before being accepted. Every one was a
real defect, and two of them were the *same* defect class the brief was written to prevent, reproduced
inside the fix:

- **N1 → EA rewritten.** Revision 2's counts bullet grepped
  `'agents=14 commands=21 skills=41 hooks=24'` with single spaces, but
  ``scripts/check-doc-currency.sh:58 [pins: `Authoritative → version=`]`` emits **two** spaces between
  every field. Verified by running it: `agents=14··commands=21··skills=41··hooks=24`. The bullet could
  **never** match — it would have failed permanently for a reason unrelated to what it checked, and
  driven `status: advisory_failures` red on every ground-truth run regardless of the work. An
  un-passable check written to mechanize an AC about un-failable checks. Now a whitespace-agnostic
  `grep -qE` in the worker-facing section.
- **N2 → §"The discovery path base" + corrected AC4.2.** Revision 2 said "copy `run_gate()`, don't
  invent a second idiom" while also requiring per-fixture manifests — but that idiom resolves the
  manifest and `.source` **relative to CWD**, which is incompatible with contract-parity's `--root`
  base, so the fixtures would have been ignored and ~10 expect-failure cases would have flipped to
  exit 0. Worse, revision 2 **blessed an "Alternative"** (activate discovery only when `--root` is the
  real repo) that would have made the new branch unreachable from every fixture — reopening H1 for the
  third gate, explicitly sanctioned. The Alternative is **struck**; one `$ROOT`-relative path-base rule
  now applies to all three gates, and contract-parity's negative case is `--root <two-plugin-fixture>`
  (revision 2's "run with `--root` unset" was incoherent — `--root` is the base for `HOOKS`/`AGENTS`,
  not a discovery escape hatch).
- **N3 → addressable `provides` + real `lanes` globs.** Revision 2's
  `provides: [selvedge-plugin-registered, gates-plugin-aware, ci-loop-plugin-aware]` are free-text
  tokens, explicitly rejected by
  ``loomwright/skills/supervisor-readiness/SKILL.md:279 [pins: `addressable on disk`]``, and
  `lanes: [infra]` resolves to no path. Since the Supervisor's `outputs_verified` gate keys on
  `provides`, the **only** per-subtask gate on a ~23-file slice would have been a silent no-op — the
  recorded `outputs-verified-silent-noop-on-dead-worker` lesson, in a brief that cites that lesson
  family three times.

MEDIUM/LOW also addressed: fact 12 extended from 2 to **5** stale surfaces, with the greps covering the
*enumerations* not just the numbers (M1); commit hygiene asserted over `origin/main...HEAD` instead of
a `HEAD~1` window that both fails OPEN when `HEAD~1` is absent and is blind across the ordering's
multiple commits (M2); **EA reduced to three real `corpus-task:` bullets** because a machine-authored
brief MUST NOT emit `cmd:` bullets and Supervisor's `--no-cmd` on this very dispatch path would have
recorded all 23 as `unverified` (M3); the pre-change `nullglob` residue bullet deleted (M4); real lane
globs (M5); the `ci.yml`-edit → `claude-review` self-skip risk added with an assert-on-posted-comments
mitigation (M6); rubric trimmed 8→7 and both non-diff-checkable bullets rephrased as diff-observable
(M7); fact 9 corrected to 13-of-14 cases (L2); `## Configuration` added (L3).

## Handoff

/supervisor job: .supervisor/jobs/pending/2026-08-20-scaffold-selvedge-and-plugin-aware-gates.md
