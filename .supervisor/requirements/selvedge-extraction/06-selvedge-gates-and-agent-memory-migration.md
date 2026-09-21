# 06 — Selvedge's own gates, and the orphaned QA agent-memory store

**Depends on:** 04 (agents relocated and renamed), 05 (docs settled).

## Problem A — renaming the agent orphans a live, populated memory store

Both QA agents declare `memory: project`. The harness derives the store path from the agent id, and
the loomwright QA store is **real and populated** today:

```
.claude/agent-memory/loomwright-loomwright-qa-executor/
  MEMORY.md
  count_version_gate_blindspots.md
  fail_safe_exit_0.md
  golden_fixture_regen.md
  infra_self_test_contract.md
  session_end_qa_signal.md
```

Five indexed entries — and per the twin-loop baseline, `qa-executor` is one of only two stores with a
**correctly shaped 5/5 index** (`code-reviewer`, by contrast, has 18 entry files with 1 indexed). This
is the healthy store, and it is the one about to be orphaned: after the rename to
`selvedge:qa-executor`, the harness will resolve a *different* sanitized directory
(`selvedge-selvedge-qa-executor` on the observed doubled-prefix pattern — **confirm the exact form
empirically per 01's unknown C; do not derive it from the old path**) and start from empty.

There is no `qa-strategist` store on disk today, so only one store is affected.

Nothing fails when this happens. The agent simply loses five accumulated lessons silently — which is
the precise failure the twin-loop queue exists to prevent, and it would be self-inflicted here.

**Two hard constraints on the fix:**

- **`write-agent-memory.sh` is the sole writer**, it rebuilds `MEMORY.md` on every write, and a
  hand-edited entry is both unvalidated and liable to be overwritten. A bare `git mv` of the directory
  is therefore **not** obviously correct — decide and record whether re-homing must go through the
  writer, and whether the writer's slug containment (which permits the on-disk plugin form
  `loomwright-loomwright-<agent>`) accepts a `selvedge-…` slug at all. **Read the writer's containment
  rule before choosing.**
- `loomwright/scripts/test-committed-twin-scrub.sh` hard-codes
  `.claude/agent-memory/loomwright-loomwright-qa-executor/MEMORY.md`. That pin must move with the
  store, and the test must still fail when its mechanism is removed.

Also note: `.claude/` is gitignored, so the store is **local-only**. The migration is a local-state
operation, not a committed change — which makes it easy to skip and easy to get wrong unattended.
Record explicitly what a *user* with their own populated store should do; a note in the migration
announcement (07) is the only way they will ever learn of it.

## Problem B — selvedge ships agents and a hook, but has no currency gate of its own

After 04, selvedge has 2 agents, 2 commands, 5 skills, 1 hook, and its own scripts — and its
`plugin.json` / `marketplace.json` descriptions state those counts. **Nothing checks them.**
`check-doc-currency.sh` reads `PLUGIN_JSON="loomwright/.claude-plugin/plugin.json"` and the three
`loomwright/` dirs, hard-coded. So selvedge starts life in exactly the drift-prone state that gate was
written to eliminate — the state loomwright was in before v14.3.0.

Slice 02 made three *other* gates plugin-aware. This one was deliberately left out of 02 because
selvedge had no counts to check yet; now it does.

**Two options:**

1. **Generalize `check-doc-currency.sh`** to loop marketplace plugins, each with its own authoritative
   sources and its own surface list. Correct, and consistent with the discovery idiom
   `check-skills-index-sync.sh` established.
2. **Give selvedge a minimal count check** covering only its `plugin.json` + `marketplace.json` entry.
   Cheaper; a second idiom to maintain.

**Recommendation:** 1 — one gate, one idiom. The surface list becomes per-plugin data rather than a
hard-coded array, and loomwright's 9 surfaces are unchanged.

Whichever is chosen, preserve the gate's deliberate narrowness (only high-confidence "current claim"
phrasings; never bare numbers) and its documented frozen-example-value convention. Widening it into
bare-number scanning would generate false positives on every dated changelog line.

## Scope

1. **Decide and execute the agent-memory re-homing** — through the sole writer, or as a documented
   local `mv` if the writer cannot re-home. Record the choice and the reason, including what the
   writer's slug containment actually permits.
2. **Move the `test-committed-twin-scrub.sh` pin** to the new store path; verify the test still fails
   when its mechanism is removed.
3. **Document the user-facing migration step** for anyone with a populated
   `loomwright-loomwright-qa-executor` store — feeds 07's announcement.
4. **Make `check-doc-currency.sh` cover selvedge** (option 1 recommended), with a negative-path
   self-test proving a drifted selvedge count fails.
5. **Verify selvedge's `scripts/test-*.sh` actually run in CI** — 02 extended the loop; now that
   selvedge has real tests, prove they execute rather than being globbed-but-empty. Assert on test
   *output* appearing in the CI log, not on the job's exit code. (Precedent: the sdk-spike suite sat
   in CI for multiple releases self-SKIPping to green because `dist/` was gitignored.)
6. **Confirm selvedge's agent-memory permission contract.** Both selvedge agents carry the
   `memory: project` write-permission prose; `AGENT_GUIDELINES.md` remains the single contract in
   loomwright. Verify 04's resolution of `test-agent-memory-permission.sh` genuinely covers the two
   selvedge agents and has teeth.

## Constraints / invariants

- **Distilled stores never auto-delete.** The regenerability split recorded in
  `docs/SPIKES/FINAL_STATE_GOAL.md` (D9, as amended) puts agent-memory firmly in the *Distilled* class:
  human-gated judgment, not rebuildable from the repo. This migration **must not** delete the old
  store as a side effect — re-home it, verify, and only then remove, under an explicit confirmation.
- `write-agent-memory.sh` stays the sole writer; `MEMORY.md` is writer-owned and regenerated on every
  write. A hand-written index is silently replaced.
- **A gate that cannot fail is not a gate.** Every check added here needs a negative-path self-test.
  The existing precedent is `check-skills-index-sync.sh --self-test`.
- **`.claude/` is gitignored** — state clearly which steps are committed and which are local-only, per
  slice. An unstated local step will be skipped by every future clone.
- Counts unchanged in this slice; CI green throughout.
- bash-3.2-safe / Ubuntu-clean.

## Acceptance criteria

- [ ] The new store path is **confirmed empirically** (spawn the selvedge agent, observe the directory
      the harness resolves), not derived from the old path's shape.
- [ ] All five entries plus a correct `MEMORY.md` index are present at the new path, and the index is
      writer-generated rather than hand-copied — or the deviation is recorded with its reason.
- [ ] The old store is removed **only after** the new one is verified, under explicit confirmation;
      the D9 Distilled-store rule is cited in the PR.
- [ ] `test-committed-twin-scrub.sh`'s pin updated and mutation-controlled.
- [ ] `check-doc-currency.sh` covers selvedge's counts and version, with a negative-path self-test
      proving a drifted selvedge count **fails**; loomwright's 9 surfaces and its output are unchanged.
- [ ] The gate keeps its deliberate narrowness — no bare-number scanning, frozen-example convention
      intact. Verified by running it against a dated changelog line containing an old count.
- [ ] Selvedge's tests are proven to **execute** in CI by asserting on their output in the log, not on
      the job's exit code.
- [ ] `test-agent-memory-permission.sh` (or its selvedge counterpart) covers both selvedge agents and
      still fails when a rule sentence is deleted.
- [ ] The user-facing memory-migration step is written up and handed to 07.
- [ ] Full CI green for both plugins.

## Out of scope

Any QA file relocation (done in 04). Doc narrative (05). CHANGELOG / READMEs / version bumps (07).
Migrating any store other than `qa-executor`'s — `code-reviewer`'s known 18-entry/1-indexed rot is the
twin-loop queue's item 01, not this one, and must not be opportunistically "fixed" here.

## Outcomes Rubric

- The healthy 5/5 QA memory store survives the rename — verified at the empirically-confirmed path
- Re-homing respects the sole-writer contract and the D9 Distilled no-auto-delete rule
- Selvedge gains real count-currency coverage rather than starting in the pre-v14.3.0 drift state
- One gate, one discovery idiom — no second count-check implementation
- Selvedge's tests are proven to run by their output, not by a green job
- Local-only vs committed steps are stated per step, so nothing depends on undocumented local state


## Status: done_with_escalation — ABANDONED (owner dropped the selvedge extraction track 2026-08-22)
- **Evidence:** `.supervisor/automate/automate-2026-08-18-124023.md` (queue rows 04–07 "abandoned: owner dropped the selvedge extraction track on 2026-08-22; not pursued"); PR #157 CLOSED unmerged; branch `feature/relocate-qa-to-selvedge` retained on origin.
- **Why this stamp:** `is_done()` in automate-helpers.sh honours only `done` / `done_with_escalation`, so this is the only marker that keeps `/automate` from re-enqueuing a dropped item. Slices 01–03 DID merge (#153/#155/#156) and are stamped done separately.
- **Reconciled:** 2026-09-21 by hand.
