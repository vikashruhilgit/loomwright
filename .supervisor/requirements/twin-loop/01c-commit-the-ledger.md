# 01c — Make the findings ledger committable, safely (opt-in or fail-closed)

> Split out of **01b** on 2026-08-07 by owner decision, after two Plan Review rounds proved the
> ledger cannot be committed as data work. 01b ships the two memory stores and leaves the ledger
> gitignored; this item is the capability that makes committing it safe **for every repo**, not
> just this one.

## Problem

Item 01 made `.claude/agent-memory/` and `.supervisor/memory/` committable via a sentinel-delimited
managed block in `.gitignore`. The findings ledger — `.supervisor/postmortem/results.jsonl` — was
not included, and three findings block a naive addition:

1. **A hand-added negation cannot survive.** `proposed_applied_content()`
   (`setup-memory.sh:369-372`) is `strip_managed_block | comment_bare_excludes` followed by
   `managed_block`, so the block is re-emitted at **end-of-file** on every `apply`. Any negation
   placed after it is relocated **above** the block's `.supervisor/*` line (`setup-memory.sh:362`).
   Gitignore is last-match-wins and a file under an excluded parent cannot be re-included, so the
   ledger silently reverts to ignored. It is **silent**: `render_report` probes only
   `INTENDED_PATHS` (`setup-memory.sh:145-148`), which omits the ledger, so the verdict still
   prints `configured` and `warn_if_not_configured()` stays quiet.

2. **The ledger is structurally CROSS-REPO by contract.** `skills/pr-postmortem/SKILL.md:21` — the
   append goes to the ledger under the *current working* `.supervisor/`, **never** the analyzed
   repo's. That is exactly how this repo accumulated 7 `otherhub` records. So promoting the
   ledger to a **default** managed path un-ignores an **unfiltered** cross-repo file in every repo
   a user runs `/setup memory apply` in — `apply` does not filter (`filter-ledger` only PRINTS,
   `setup-memory.sh:52-53`, impl `:593-634`). That generalizes the exact contamination this queue
   exists to remediate. **This is the finding that makes the feature non-trivial.**

3. **It breaks a load-bearing consent contract.** `print_consent_disclosure()`
   (`setup-memory.sh:638-658`) enumerates exactly two stores, and `:656-657` asserts *"What stays
   IGNORED (unchanged): … and everything else under those two directories"* — materially false with
   a third managed store. `commands/setup.md:319` requires that copy shown **verbatim** ("do not
   paraphrase, summarise or shorten it"). The two-store list is mirrored at `commands/setup.md:119`,
   `:299`, `:326`, `:344`, `:361`. `check-command-sync.sh` does **not** cover prose, so nothing
   mechanical catches this drift — it is the repo's recorded `agent↔command mirror drift` class.

## Scope

1. **Make the default SAFE.** Pick one, and justify it against the bimodal invariant
   (CLAUDE.md §"Failure-Mode Invariants": correctness gates fail **CLOSED**):
   - **Opt-in flag** — `.setup_memory.commit_ledger`, default `false`; the ledger joins the managed
     block only when explicitly enabled; or
   - **Fail-closed apply** — `apply` REFUSES to un-ignore the ledger while it contains any record
     whose `.repo` is outside the resolved allowlist, printing the offending slugs.

   The fail-closed form turns the allowlist from advisory into load-bearing and is the better fit
   for the invariant. Whichever is chosen, **`apply` must never un-ignore an unfiltered ledger.**

2. **Managed-block membership, not a hand-added line.** When enabled, the ledger negation is
   emitted **inside** `managed_block()` so intra-block order is byte-stable across re-applies
   (`strip_managed_block` at `setup-memory.sh:260-266` removes BEGIN..END inclusive and the block is
   re-emitted verbatim). It needs the full three-line nested form, **emitted AFTER `.supervisor/*`**:
   ```gitignore
   !.supervisor/postmortem/
   .supervisor/postmortem/*
   !.supervisor/postmortem/results.jsonl
   ```
   Order is the whole defect class — emitted *before* `.supervisor/*` the re-include is dead again,
   silently. Pin BOTH negative controls: the naive one-line form, and the three lines in the wrong
   position.

3. **Add it to `INTENDED_PATHS`** (`setup-memory.sh:145-148`) so `check` probes it and the verdict
   can no longer read `configured` while the ledger is ignored.

4. **Update the consent surface in the same change.** `print_consent_disclosure()` (:638-658,
   including the now-false :656-657 line), the script header WHAT block (:6-11), the managed block's
   inline comment (:354-356), `do_remove()`'s tracked-count / `git rm -r --cached` copy (:916-931),
   and all five `commands/setup.md` mirror sites. The disclosure must state that the ledger can
   contain records from **other repos** and what the gate does about it.

5. **Then apply it to this repo** — the allowlist must hold BOTH historical slugs
   (`vikashruhilgit/ai-agent-manager`, 42 records; `vikashruhilgit/loomwright`, 37), then filter the
   7 `otherhub` records out and commit the filtered ledger.

   **The pre-rename slug is a HAND-EDIT, not a seed — this WILL silently no-op if treated as one.**
   Item 01b's `apply` already ran, and `load_allowlist`'s layer-4 default is the CURRENT git remote
   alone (`setup-memory.sh:513-520`), so `.setup_memory.repo_allowlist` already holds the ONE-entry
   array `["vikashruhilgit/loomwright"]`. `seed_allowlist` **never overwrites a non-empty array**
   (`setup-memory.sh:550-553` — *"already configured … left untouched"*), so re-seeding does
   nothing. Filtering against that one-entry list retains only the 37 `loomwright` records and drops
   all 42 `ai-agent-manager` ones — **exactly the pre-rename data loss the list-shaped allowlist
   exists to prevent** (`setup-memory.sh:22-28`) — and it fails quietly, because the filter prints a
   plausible-looking 37 lines. Set it explicitly and verify before filtering:
   ```bash
   jq '.setup_memory.repo_allowlist = ["vikashruhilgit/loomwright","vikashruhilgit/ai-agent-manager"]' \
     .supervisor/config.json > tmp && mv tmp .supervisor/config.json
   bash loomwright/scripts/setup-memory.sh allowlist   # MUST print two entries
   ```
   (The tool warns about exactly this at `setup-memory.sh:583`.)

## Non-goals

No changes to the two memory stores (item 01b). No new agent / command / skill / hook — counts stay
unchanged; the plugin **version does bump** because capability code changes.

## Acceptance criteria

- `apply` on a repo whose ledger holds a non-allowlisted record does NOT un-ignore the ledger, and
  says why, naming the offending slugs.
- With the gate satisfied, `apply` run TWICE leaves the ledger committable after both runs
  (the relocation defect is pinned as a regression test that fails against the pre-fix block).
- The three lines emitted BEFORE `.supervisor/*` leave the ledger ignored — pinned as a negative
  control, alongside the naive one-line form.
- `setup-memory.sh check` lists the ledger under `intended (must be committable)` and probes it.
- Every ledger assertion uses **jq**, never grep: `results.jsonl:83` is spaced JSON
  (`"repo": "…"`) while every other line is compact, so `grep -c '"repo":"…loomwright"'` returns
  36 not 37, and a foreign record appended in spaced form evades a compact-form grep entirely.
  That line is a named fixture case.
- A simulated foreign-repo append **in the spaced form** fails the guard; removing it passes.
- The consent disclosure and all five `commands/setup.md` mirror sites state the third store and
  the cross-repo caveat; no surface still claims only two stores are affected.
- Version bump applied in lockstep across `plugin.json`, `marketplace.json`, the CLAUDE.md banner
  and `CHANGELOG.md` (grep for the OLD version repo-wide — a green doc-currency run is necessary,
  not sufficient).
- Tests make ZERO writes under the real repo root: `mktemp -d` + `git init` + `--root`
  (`setup-memory.sh:70,131-136`) with `trap … EXIT`, per `test-no-junk-tracked-files.sh:62-71`.
- `setup-memory.sh allowlist` prints **two** entries BEFORE any filtering runs — asserted, not
  assumed, because a re-seed is a silent no-op against 01b's one-entry array (Scope §5).
- This repo's committed ledger contains ZERO records outside the allowlist, re-asserted after a
  simulated foreign-repo append. Retained counts verified (42 + 37 = 79), not assumed.

## Outcomes Rubric
- `apply` fails closed (or stays opt-in) on a ledger holding a non-allowlisted record, with a test proving it
- The ledger negation lives inside `managed_block()` after `.supervisor/*`, with both wrong-form negative controls pinned
- `INTENDED_PATHS` includes the ledger, so `check` probes it and cannot report a false `configured`
- Consent disclosure + all five `commands/setup.md` mirror sites name the third store and the cross-repo caveat
- Every ledger assertion is jq-based and `results.jsonl:83`'s spaced form is a named fixture case
- Version bump present in all four lockstep surfaces

## Status: brief-shipped

Job `.supervisor/jobs/done/2026-08-08-commit-the-ledger-safely.md` completed (reconciled from the job lifecycle, not self-reported).
Acceptance criteria are NOT machine-verified here — review them before promoting this to `## Status: done`.
