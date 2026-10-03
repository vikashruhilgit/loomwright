# 02 — Scaffold `selvedge` and make the loomwright-pinned CI gates plugin-aware

**Depends on:** 01 (its verdicts shape the scaffold's `hooks.json` and skill layout).

## Problem — three gates are hard-pinned to `loomwright/` and would fail closed on a second agent-bearing plugin

`check-skills-index-sync.sh` was already made multi-plugin in v15.6.0 (the stackpack spin-off), and
`validate-version.sh` already loops `.plugins[]`. Those two are fine. **Three others are not** — and
each fails CLOSED, which is correct behaviour but means they must be taught about selvedge *before*
anything moves, or slice 04 becomes un-landable:

| Gate | Pin | What happens when QA agents live in `selvedge/agents/` |
|---|---|---|
| `check-token-budget.sh` | `AGENTS_DIR="${TOKEN_BUDGET_AGENTS_DIR:-loomwright/agents}"` | selvedge's agents are **never budgeted** — the ratchet silently stops covering them (the gate can only fail closed on agents it can see; agents it cannot see are simply unmeasured) |
| `check-shared-prefix.sh` | `CANONICAL="${SHARED_PREFIX_CANONICAL:-loomwright/docs/shared-agent-prefix.md}"`, `AGENTS_DIR="${SHARED_PREFIX_AGENTS_DIR:-loomwright/agents}"` | the byte-identity invariant stops covering the 2 moved copies; and the **canonical prefix file stays in loomwright**, so selvedge's copies are checked against another plugin's canonical — a cross-plugin dependency that must be named, not stumbled into |
| `check-contract-parity.sh` | `PLUGIN="$ROOT/loomwright"` (hooks + agents resolved beneath it) | its `MANIFEST` row for `qa-executor` resolves `agent_path="$AGENTS/qa-executor.md"`, the file is gone, and the gate errors `field-presence`. **This is the gate that makes slice 04 atomic** |

Plus the CI runner itself:

- `.github/workflows/ci.yml`'s hard-gate loop globs **`loomwright/scripts/test-*.sh`** only. A
  `selvedge/scripts/test-*.sh` would never run. The loop is deliberately written to fail loudly on an
  empty glob (anti-drift) — extending it must preserve that property for **each** plugin, so a moved
  or renamed selvedge scripts dir fails loudly rather than passing vacuously.

Both `check-token-budget.sh` and `check-shared-prefix.sh` are **already env-parameterized**, which is
the cheap path — but an env override in `ci.yml` invoking each gate twice is a second call site that
can silently drift out of sync with `marketplace.json`. Prefer plugin **discovery** (the pattern
`check-skills-index-sync.sh` already established: read `.claude-plugin/marketplace.json` with `jq`,
resolve `.source`, skip plugins lacking the relevant tree) over a hand-maintained list. Read that
script's `run_check` loop and follow it — do not invent a second discovery idiom.

## Goal

Create an empty-but-registered `selvedge` plugin and teach the three pinned gates + the CI loop about
multi-plugin layouts, **while every count stays exactly where it is**. Land the runway before the
plane.

## Scope

1. **`selvedge/.claude-plugin/plugin.json`** — `name: selvedge`, `version: 1.0.0`, a **short**
   description (anti-rebloat: summary, not changelog — mirror stackpack's one-sentence shape), author
   + license matching the siblings, a focused `keywords` list. Do **not** copy loomwright's 90-entry
   keyword list.
2. **`selvedge/README.md`** — brief, and explicit that selvedge is a **companion** requiring
   `loomwright@atelier`, not a standalone install.
3. **Register in `.claude-plugin/marketplace.json`** as a fourth plugin. `validate-version.sh` will
   then check it automatically.
4. **Do NOT create `selvedge/agents/`, `selvedge/skills/`, or `selvedge/hooks/` yet.** They must
   arrive populated, in 04. Creating them empty is actively harmful:
   - `check-shared-prefix.sh` treats an **empty agents dir as a failure** ("a 0-agent run of a
     fail-closed gate is a false pass" — its own header says so).
   - `check-skills-index-sync.sh` **fails loudly** on a `skills/` dir with no `SKILLS_INDEX.md`.

   The gate work in step 5 must therefore be written to **skip a plugin that ships no such tree**,
   exactly as `check-skills-index-sync.sh` already skips `mysql-mcp`, and to fail loudly on a tree
   that exists but is malformed. Those two behaviours are different and both are required.
5. **Make the three gates plugin-aware**, each with a negative-path self-test proving the new loop
   has teeth:
   - `check-token-budget.sh` — discover agent dirs across plugins; each plugin's budgets read from
     that plugin's own `prompt-token-budgets.json` (selvedge gets its own in 04). Keep fail-closed on
     an undeclared budget **per plugin**.
   - `check-shared-prefix.sh` — check every plugin's agents against the **single** canonical at
     `loomwright/docs/shared-agent-prefix.md`. Decide and **record in the script header** whether the
     canonical staying in loomwright is intended (it is: owner decision 2 forbids a second copy) and
     what happens if loomwright is absent.
   - `check-contract-parity.sh` — parameterize `PLUGIN`; the `MANIFEST` and `ENUMS` tables gain a
     plugin dimension so a row can name which plugin owns its hooks.json and agent. Rows all still
     point at loomwright after this slice; 04 flips the two QA rows.
6. **Extend `ci.yml`'s hard-gate self-test loop** to every plugin that ships a `scripts/` dir, keeping
   the loud-on-empty-glob property per plugin.
7. **Bump loomwright's patch/minor version** per the normal release rules, sweeping the version string
   on every doc-currency surface **in place**.

## Constraints / invariants

- **Counts do not change in this slice.** agents 14, commands 21, skills 41, hooks 24 — unchanged.
  `check-doc-currency.sh` reads loomwright only, so it should not even notice selvedge; verify that
  it does not, rather than assuming.
- **A gate that stops covering something is a regression, not a refactor.** Every parameterization
  here must be proven to still fail on the case it previously caught. The repo's own recorded lesson
  applies directly: injecting a default into a shared test helper can make the one assertion whose
  subject is that input **vacuous** — it then passes with the mechanism deleted. Mutation-control
  every loop touched here.
- No QA asset moves. No `selvedge` agents, skills, commands, hooks, or scripts yet.
- Follow the existing discovery idiom (`jq` over `marketplace.json`, resolve `.source`) rather than a
  hand-maintained plugin list — a second list is a second thing to drift.
- bash-3.2-safe and Ubuntu-clean: macOS-green ≠ CI-green for `stat` / `date` / `sed -i`.

## Acceptance criteria

- [ ] `selvedge/` exists with `plugin.json` (v1.0.0) + `README.md`; **no** `agents/`, `skills/`, or
      `hooks/` dir.
- [ ] `.claude-plugin/marketplace.json` lists 4 plugins; `validate-version.sh` and its `--self-test`
      both pass.
- [ ] `selvedge` installs cleanly locally alongside loomwright
      (`/plugin install selvedge@atelier`), verified with `/agent-help`.
- [ ] All three gates are plugin-aware, each with a **negative-path self-test** that fails when the
      new per-plugin branch is removed — i.e. the loop is mutation-controlled, not merely exercised.
- [ ] Each gate **skips silently** a plugin with no relevant tree, and **fails loudly** on a tree that
      exists but is malformed (empty agents dir, `skills/` with no index). Both branches tested.
- [ ] `ci.yml`'s test loop covers every plugin's `scripts/test-*.sh` and still fails loudly on an
      empty glob **per plugin** — proven, not asserted.
- [ ] `check-doc-currency.sh` output is byte-identical to before for all four counts (it must not
      start counting selvedge).
- [ ] Full CI green: `validate-version.sh`, `check-command-sync.sh`, `check-doc-currency.sh`,
      `check-skills-index-sync.sh`, `check-contract-parity.sh`, `check-token-budget.sh`,
      `check-shared-prefix.sh`, and the whole `test-*.sh` hard-gate loop.
- [ ] Version bumped and swept in place across all 9 doc-currency surfaces; plugin/marketplace
      `description` fields edited in place, **no appended version clause**.

## Out of scope

Any QA asset relocation. Selvedge's own doc-currency gate (04/06). Selvedge scripts or tests (04/06).
Any change to `check-command-sync.sh` (it targets only `loomwright/commands/code-reviewer.md` and is
genuinely unaffected — confirm, do not touch).

## Outcomes Rubric

- `selvedge` registered and installable, deliberately empty, with no gate false-passing on emptiness
- Three pinned gates now discover plugins the same way `check-skills-index-sync.sh` already does — one
  idiom, not two
- Every widened loop is mutation-controlled: removing the new branch fails a self-test
- Skip-silently vs fail-loudly are distinguished and both tested
- CI's hard-gate loop keeps its loud-on-empty property per plugin
- Counts and doc-currency output provably unchanged


## Method note (added 2026-08-20 by the /automate engine at RUN — measured, not assumed)

This note is **additive**. Nothing above it was edited: the Problem, Goal, Scope, Constraints,
Acceptance criteria, Out of scope, and Outcomes Rubric are untouched. It resolves *how* to satisfy one
acceptance criterion whose stated method is unavailable in this session type, and it flags one AC
whose literal wording cannot be honestly satisfied by this slice's own deliverables.

### 1. AC3's stated method (`/plugin install selvedge@atelier`) is unavailable here — and the obvious CLI substitute would produce a FALSE negative

`/plugin install` and `/plugin uninstall` are **interactive terminal-dialog slash commands**, not
available in the desktop / SDK-hosted session this slice is dispatched from. This is the same blocker
slice 01 hit and recorded; 01's `## Method note` is the reusable prior art.

The non-obvious half — **measured on 2026-08-20, not recalled**:

```
$ claude plugin marketplace list
  ❯ atelier
    Source: Git (https://github.com/vikashruhilgit/loomwright.git)
```

The registered `atelier` marketplace resolves from the **remote git URL**, not this working copy. So
the straightforward non-interactive substitute — `claude plugin install selvedge@atelier` — would
resolve `selvedge` against the remote, where an unmerged local scaffold **does not exist**, and report
"not found". That is a **false negative about our own new plugin**, and it is the exact shape of the
snapshot trap slice 01 measured for skill bodies ("installed plugin bodies are SEPARATE SNAPSHOTS").
Do not run it and record the failure as evidence.

A second measured constraint compounds it: this repo's own `.claude-plugin/marketplace.json` is
**`"name": "atelier"`** — the *same name* as the already-registered remote-sourced marketplace. So
`claude plugin marketplace add <repo-root> --scope local` risks colliding with, shadowing, or
clobbering the owner's live `atelier` registration. **Do not add the live repo root as a marketplace.**

### 2. The verified path

Follow slice 01's probe pattern (`loomwright/docs/SPIKES/cross-plugin-probe/run-probe.sh`, which is
committed and readable): build a **throwaway scratch marketplace under a temp dir with a DISTINCT
name**, containing a copy of the manifest and the `selvedge/` tree, then:

- `claude plugin validate <path>` (and `--strict`) — the cheapest first check; run it on
  `selvedge/.claude-plugin/plugin.json` **and** on the amended `.claude-plugin/marketplace.json`
  before any install is attempted.
- `claude plugin marketplace add <scratch-marketplace-dir> --scope local` — `<source>` accepts a local
  path (verified in 01). `--scope local` keeps the probe out of user- and project-scoped config.
- `claude plugin install selvedge@<scratch-marketplace-name> --scope local`
- `claude plugin list` / `claude plugin details selvedge` — the inventory read.
- **Teardown, and assert it:** `claude plugin uninstall selvedge` + `claude plugin marketplace remove
  <scratch-name>`, then re-read `claude plugin marketplace list` and confirm the **owner's `atelier`
  entry is still present and still sourced from the git URL**. Slice 01 shipped a teardown whose four
  assertions all failed OPEN and had to be healed — do not repeat that: every teardown assertion must
  be able to fail, and should be mutation-controlled.
- Every nested `claude` invocation is headless: use **`claude -p`** with a **bounded** poll
  (`IFS= read -r -d '' -t N` — stock macOS has no `timeout`), and record a deadline expiry as
  **UNMEASURED**, never as a negative result.

### 3. AC3's `/agent-help` verification cannot be satisfied literally — and should not be faked

AC3 says "verified with `/agent-help`". By this slice's own Scope step 4, `selvedge` ships **no**
`agents/`, `skills/`, `commands/`, or `hooks/` — deliberately. So `/agent-help` has nothing new to
list, and a worker that reports "verified with /agent-help" has either fabricated it or verified
nothing.

**The honest substitute:** `claude plugin details selvedge` returning a **zero-component inventory**
for a successfully *installed* plugin — which is precisely the property this slice wants (registered
and installable while deliberately empty). Record the verbatim `details` output as the evidence, and
state plainly in the PR that AC3's `/agent-help` clause was satisfied by this substitute and why.
Do not silently drop the AC, and do not edit the AC to match what was done.

### 4. Working-tree note for FINALIZE

At dispatch time this checkout carries two unrelated uncommitted artifacts: a modified
`.supervisor/postmortem/results.jsonl` (gitignored-adjacent engine ledger) and an untracked
`loomwright/docs/SPIKES/IMPECCABLE_TEARDOWN.md`. **Neither belongs to this slice.** Commit only paths
this slice actually creates or edits — never `git add -A`/`git add .` — and verify at FINALIZE that
neither file entered the commit.

## Status: done (PR #155, merge e44cfa8)
- **Completed:** 2026-08-20T09:22:47Z
- **Brief:** (engine-driven; see automate-2026-08-18-124023.md)
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/155
- **Reconciled:** 2026-09-21 by hand from the merged PR — the PR was merged outside the /automate loop, so nothing wrote this stamp at merge time.
