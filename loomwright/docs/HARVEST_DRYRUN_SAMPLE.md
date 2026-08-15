# Harvest dry-run sample — the real `.agent/rules/` proposal batch

This file is the **verbatim output of a real `harvest-conventions.sh` dry run over this repository's
own corpus**, committed so the batch can be judged by READING it rather than by trusting a metric.
It exists because every other deliverable of this change is a file or a symbol inside a file the same
change creates, i.e. entirely self-satisfiable: without a durable artifact, a fixture-tested script
that has never produced a reviewable batch would pass every gate.

## How to falsify this file

It is a transcript, not prose, and it is cheap to re-derive. **Generate it from a CLEAN CLONE at the
pinned sha, not from your working tree** — the ledger it reads is git-tracked and grows with every
PR, so a dirty tree produces numbers no other reader can obtain (that mistake is recorded, and
corrected, in `RULES_BASELINE.md`):

```
git clone <this repo> /tmp/harvest-sample && cd /tmp/harvest-sample
git checkout --detach 25e84f2
bash loomwright/scripts/harvest-conventions.sh --session-id 2026-08-15-25e84f2
```

**Pinned input:** commit **`25e84f2`**, at which `.supervisor/postmortem/results.jsonl` is blob
**`952ff91`** and holds **84 records / 225 findings / 95 self-heal misses**. If `wc -l` on that file
is not 84, you are not running what produced the transcript below and the counts will differ.

**A CLONE, not a `git worktree`.** This is a real constraint, not a preference: `add-rule.sh` refuses
to write from a linked worktree (its top-level `.git` is a file — the red-team F1 guard), so a
worktree run reports `writer REFUSED this proposal (exit 3)` on every line instead of exercising the
`PLANNED WRITE` branch this sample is partly here to show. A clone has a real `.git` directory and
reproduces the transcript.

The run is **read-only** — `harvest-conventions.sh` has no write mode at all, so re-running it cannot
create a branch, a commit, a PR, or a rule. If the output below is not what you get, this file is
stale or hand-written and should be rejected on that basis.

Two things will legitimately differ on a re-run, and neither invalidates the rest:

- **`--session-id`.** Omitted, it defaults to `dreaming:<UTC date>-<short HEAD sha>`, so it moves with
  HEAD. It is pinned above to the sha this sample was taken at.
- **Absolute paths.** The `--- inputs read ---` block prints the clone's own absolute paths, so yours
  will name your clone directory rather than the one below. Nothing downstream depends on them.

## What to look at first

- **Every proposed rule names the finding ids that motivated it** (`motivating findings (N): …`).
  An id is `<repo>#<pr>:L<ledger line>.<index into that record's categories array>` and resolves with
  e.g. `sed -n '3p' .supervisor/postmortem/results.jsonl | jq '.categories[0]'`. Spot-check two or
  three: if a rule's cited findings do not support its statement, the number below is worthless.
- **`scope fidelity` prints TWO figures, and the second one is the honest one.** The first is over
  the CHECKABLE findings — those with at least one changed_path still tracked by git, the only ones a
  glob can be matched against. The second is over ALL motivating findings, and it is lower: on this
  corpus 98% (54 of 55) checkable against 72% (54 of 74) overall. The 19-finding difference is
  disclosed by count on every rule, and 18 of the 19 are not deleted paths at all — they are ledger
  records that carry no `changed_paths` whatsoever, so nothing about them can confirm or refute a
  scope. Printing only the first figure would let the metric flatter itself by dropping its own
  unfalsifiable evidence, which is the failure AC4 exists to prevent.
- **`scope fidelity` is a check OF THE DERIVATION**, not an independent oracle — the derivation and
  the verification read the same evidence. It catches a derived glob that does not match what it was
  derived from; it cannot tell you the scope is the *right* one. That judgement is the reviewer's.
- **The scope is an upper bound.** The ledger records `changed_paths` per PR record, not per finding,
  so a theme's paths are the union of the file lists of the PRs its findings came from.
- **`writer result: PLANNED WRITE (not written)`** on every proposal — each one was composed and run
  through the sole writer `add-rule.sh` with stdin detached, so the writer's own validation applied
  and nothing was written.

## The run

```text
=== harvest-conventions.sh — DRY RUN (read-only: this tool has no write mode at all) ===
invocation: 'loomwright/scripts/harvest-conventions.sh' '--session-id' '2026-08-15-25e84f2'
session source (--source passed to add-rule.sh): dreaming:2026-08-15-25e84f2
thresholds: cap=5  min-support=8  project-wide=85%  distillation-floor=2.00  applies-to-cover=95%  max-globs=4

--- inputs read ---
  (i)  ledger:    /private/tmp/claude-501/-Users-vikashruhil-Documents-work-AI-ai-agent-manager/54b0ce93-5b49-4498-a1b4-ed52065bb450/scratchpad/clone2/.supervisor/postmortem/results.jsonl
       84 records read WHOLE (no repo filter — decision (a); nothing dropped), 225 findings, 95 self-heal misses
  (ii) corpus:    /private/tmp/claude-501/-Users-vikashruhil-Documents-work-AI-ai-agent-manager/54b0ce93-5b49-4498-a1b4-ed52065bb450/scratchpad/clone2/.claude/agent-memory
       28 entries (MEMORY.md indexes excluded)
       proposals queue: /private/tmp/claude-501/-Users-vikashruhil-Documents-work-AI-ai-agent-manager/54b0ce93-5b49-4498-a1b4-ed52065bb450/scratchpad/clone2/.supervisor/agent-memory-proposals — absent (normal empty case — the queue has never been populated in this repo)
  convention surfaces for the project-wide signal: 2 of 2 readable
  rules store (read for context, NEVER written): /private/tmp/claude-501/-Users-vikashruhil-Documents-work-AI-ai-agent-manager/54b0ce93-5b49-4498-a1b4-ed52065bb450/scratchpad/clone2/.agent/rules

--- repo distribution (advisory cross-check, decision (a)) ---
      79  vikashruhilgit/ai-agent-manager
      28  vikashruhilgit/loomwright
  (no --expect-repo supplied, so nothing is flagged. This script never resolves a repo
   allowlist itself: the available resolver reads gitignored machine-local config, which
   would make this check behave differently here and in CI. Pass --expect-repo to arm it.)

--- target class (AC14) ---
  this batch targets: convention_mismatch
  share of all findings:      107/225 (47%)
  share of self-heal MISSES:  60/95 (63%) — the class this batch is aimed at
  by flow stage:
      60 self_heal
      18 unknowable
      29 worker

--- triage (AC1): every candidate in exactly ONE bucket, with the assigning reason ---
  [rules] 10 candidate(s)
    - theme:restated-count-version (ledger: 36)
      reason: 36 convention_mismatch findings (>= the 8 support floor) recur across the ledger and reach the DO side, so the convention has to be readable before the code is written, not only after
    - theme:cross-surface-sync (ledger: 20)
      reason: 20 convention_mismatch findings (>= the 8 support floor) recur across the ledger and reach the DO side, so the convention has to be readable before the code is written, not only after
    - theme:doc-currency-drift (ledger: 8)
      reason: 8 convention_mismatch findings (>= the 8 support floor) recur across the ledger and reach the DO side, so the convention has to be readable before the code is written, not only after
    - theme:naming-framing (ledger: 10)
      reason: 10 convention_mismatch findings (>= the 8 support floor) recur across the ledger and reach the DO side, so the convention has to be readable before the code is written, not only after
    - project_agent_help_phase_drift (corpus: pw=91%,normative=1)
      reason: normative, and 91% of its distinctive terms already appear in this repo's committed convention surfaces (>= 85%), so the project already asserts it repo-wide; still corroborated by the 'cross-surface-sync' theme's 20 findings, so it is a convention being broken rather than one merely written down. It CORROBORATES that theme's rule and does not become a rule of its own — the batch counts it as a deferral, since the theme's rule already covers the same evidence
    - project_test_telemetry_cwd_sensitivity (corpus: pw=88%,normative=1)
      reason: normative, and 88% of its distinctive terms already appear in this repo's committed convention surfaces (>= 85%), so the project already asserts it repo-wide; still corroborated by the 'restated-count-version' theme's 36 findings, so it is a convention being broken rather than one merely written down. It CORROBORATES that theme's rule and does not become a rule of its own — the batch counts it as a deferral, since the theme's rule already covers the same evidence
    - fail_safe_exit_0 (corpus: pw=100%,normative=1)
      reason: normative, and 100% of its distinctive terms already appear in this repo's committed convention surfaces (>= 85%), so the project already asserts it repo-wide; still corroborated by the 'restated-count-version' theme's 36 findings, so it is a convention being broken rather than one merely written down. It CORROBORATES that theme's rule and does not become a rule of its own — the batch counts it as a deferral, since the theme's rule already covers the same evidence
    - infra_self_test_contract (corpus: pw=88%,normative=1)
      reason: normative, and 88% of its distinctive terms already appear in this repo's committed convention surfaces (>= 85%), so the project already asserts it repo-wide; still corroborated by the 'restated-count-version' theme's 36 findings, so it is a convention being broken rather than one merely written down. It CORROBORATES that theme's rule and does not become a rule of its own — the batch counts it as a deferral, since the theme's rule already covers the same evidence
    - session_end_qa_signal (corpus: pw=100%,normative=1)
      reason: normative, and 100% of its distinctive terms already appear in this repo's committed convention surfaces (>= 85%), so the project already asserts it repo-wide; still corroborated by the 'restated-count-version' theme's 36 findings, so it is a convention being broken rather than one merely written down. It CORROBORATES that theme's rule and does not become a rule of its own — the batch counts it as a deferral, since the theme's rule already covers the same evidence
    - attack_failclosed_vs_failsafe_split (corpus: pw=92%,normative=1)
      reason: normative, and 92% of its distinctive terms already appear in this repo's committed convention surfaces (>= 85%), so the project already asserts it repo-wide; still corroborated by the 'restated-count-version' theme's 36 findings, so it is a convention being broken rather than one merely written down. It CORROBORATES that theme's rule and does not become a rule of its own — the batch counts it as a deferral, since the theme's rule already covers the same evidence
  [agent-memory] 22 candidate(s)
    - project_entry_points_gate_blindspot (corpus: pw=84%,normative=1)
      reason: role-lens knowledge: normative=1 and only 84% of its distinctive terms appear in the committed convention surfaces (< 85%), so it binds one agent's review lens rather than the repository
    - project_half_fixed_example_classes (corpus: pw=66%,normative=0)
      reason: role-lens knowledge: normative=0 and only 66% of its distinctive terms appear in the committed convention surfaces (< 85%), so it binds one agent's review lens rather than the repository
    - project_hook_count_jq_two_levels (corpus: pw=62%,normative=0)
      reason: role-lens knowledge: normative=0 and only 62% of its distinctive terms appear in the committed convention surfaces (< 85%), so it binds one agent's review lens rather than the repository
    - project_hook_gate_summary_drift (corpus: pw=91%,normative=0)
      reason: role-lens knowledge: normative=0 and only 91% of its distinctive terms appear in the committed convention surfaces (< 85%), so it binds one agent's review lens rather than the repository
    - project_insights_per_run_frontmatter_gap (corpus: pw=50%,normative=1)
      reason: role-lens knowledge: normative=1 and only 50% of its distinctive terms appear in the committed convention surfaces (< 85%), so it binds one agent's review lens rather than the repository
    - project_invisible_control_char_delimiter (corpus: pw=14%,normative=0)
      reason: role-lens knowledge: normative=0 and only 14% of its distinctive terms appear in the committed convention surfaces (< 85%), so it binds one agent's review lens rather than the repository
    - project_jq_optional_chain_type_trap (corpus: pw=63%,normative=1)
      reason: role-lens knowledge: normative=1 and only 63% of its distinctive terms appear in the committed convention surfaces (< 85%), so it binds one agent's review lens rather than the repository
    - project_otel_labeler_session_lag (corpus: pw=69%,normative=0)
      reason: role-lens knowledge: normative=0 and only 69% of its distinctive terms appear in the committed convention surfaces (< 85%), so it binds one agent's review lens rather than the repository
    - project_pr_create_hook_false_positive (corpus: pw=100%,normative=0)
      reason: role-lens knowledge: normative=0 and only 100% of its distinctive terms appear in the committed convention surfaces (< 85%), so it binds one agent's review lens rather than the repository
    - project_roadmap_next_order_drift (corpus: pw=72%,normative=0)
      reason: role-lens knowledge: normative=0 and only 72% of its distinctive terms appear in the committed convention surfaces (< 85%), so it binds one agent's review lens rather than the repository
    - project_self_heal_rubber_stamp (corpus: pw=58%,normative=0)
      reason: role-lens knowledge: normative=0 and only 58% of its distinctive terms appear in the committed convention surfaces (< 85%), so it binds one agent's review lens rather than the repository
    - project_self_heal_three_fixer_sites (corpus: pw=77%,normative=1)
      reason: role-lens knowledge: normative=1 and only 77% of its distinctive terms appear in the committed convention surfaces (< 85%), so it binds one agent's review lens rather than the repository
    - project_substring_heuristic_traps (corpus: pw=66%,normative=0)
      reason: role-lens knowledge: normative=0 and only 66% of its distinctive terms appear in the committed convention surfaces (< 85%), so it binds one agent's review lens rather than the repository
    - project_supervisor_budget_surfaces (corpus: pw=80%,normative=0)
      reason: role-lens knowledge: normative=0 and only 80% of its distinctive terms appear in the committed convention surfaces (< 85%), so it binds one agent's review lens rather than the repository
    - project_two_six_class_taxonomies (corpus: pw=62%,normative=1)
      reason: role-lens knowledge: normative=1 and only 62% of its distinctive terms appear in the committed convention surfaces (< 85%), so it binds one agent's review lens rather than the repository
    - unscanned-drift-surfaces-on-version-bump (corpus: pw=80%,normative=1)
      reason: role-lens knowledge: normative=1 and only 80% of its distinctive terms appear in the committed convention surfaces (< 85%), so it binds one agent's review lens rather than the repository
    - count_version_gate_blindspots (corpus: pw=45%,normative=1)
      reason: role-lens knowledge: normative=1 and only 45% of its distinctive terms appear in the committed convention surfaces (< 85%), so it binds one agent's review lens rather than the repository
    - golden_fixture_regen (corpus: pw=50%,normative=1)
      reason: role-lens knowledge: normative=1 and only 50% of its distinctive terms appear in the committed convention surfaces (< 85%), so it binds one agent's review lens rather than the repository
    - attack_jq_only_json_injection (corpus: pw=25%,normative=1)
      reason: role-lens knowledge: normative=1 and only 25% of its distinctive terms appear in the committed convention surfaces (< 85%), so it binds one agent's review lens rather than the repository
    - attack_self_heal_pass_not_review_clean (corpus: pw=81%,normative=0)
      reason: role-lens knowledge: normative=0 and only 81% of its distinctive terms appear in the committed convention surfaces (< 85%), so it binds one agent's review lens rather than the repository
    - attack_sole_writer_worktree_ban (corpus: pw=100%,normative=0)
      reason: role-lens knowledge: normative=0 and only 100% of its distinctive terms appear in the committed convention surfaces (< 85%), so it binds one agent's review lens rather than the repository
    - attack_user_global_config_writes (corpus: pw=69%,normative=1)
      reason: role-lens knowledge: normative=1 and only 69% of its distinctive terms appear in the committed convention surfaces (< 85%), so it binds one agent's review lens rather than the repository
  [project-memory] 3 candidate(s)
    - theme:citation-anchor (ledger: 2)
      reason: only 2 corroborating findings (< the 8 support floor) — too thin to generalise into a committed convention; recorded as durable project context instead
    - theme:test-vacuity (ledger: 1)
      reason: only 1 corroborating findings (< the 8 support floor) — too thin to generalise into a committed convention; recorded as durable project context instead
    - theme:gate-exit-contract (ledger: 4)
      reason: only 4 corroborating findings (< the 8 support floor) — too thin to generalise into a committed convention; recorded as durable project context instead

--- proposed rule batch (cap 5; 4 emitted, 6 deferred by cap or already-covered evidence) ---
  1) [process] theme=restated-count-version  origin=ledger theme
     statement: A count or version number is claimed in exactly one authoritative machine-readable place; every other surface derives it at read time or names the authority instead of restating the literal, because a restated number is a live claim that nothing keeps current.
     enforcement: advisory
     check: null  (AC9b — no obviously mechanical check; this harvester never synthesises shell into `check`)
     applies_to: [CLAUDE.md]
     scope fidelity: 96% (26 of the 27 CHECKABLE motivating findings have a live changed_path matched by the derived globs, via the same bash `case` matcher read-rules.sh uses)
                     over ALL 36 motivating findings: 72% (26 of 36). The denominator above is SMALLER on purpose and the filter is not silent: 9 finding(s) come from a ledger record with no changed_paths at all, and 0 have changed_paths of which none is still tracked by git. Neither can be matched against a glob, so neither is evidence for OR against the scope — but they are motivating findings all the same, and the honest figure is the second one.
     motivating findings (36): ai-agent-manager#43:L3.1 ai-agent-manager#43:L3.5 ai-agent-manager#60:L5.4 ai-agent-manager#62:L7.3 ai-agent-manager#67:L8.3 ai-agent-manager#67:L8.4 ai-agent-manager#67:L9.3 ai-agent-manager#67:L9.4 ai-agent-manager#67:L9.7 ai-agent-manager#70:L12.2 ai-agent-manager#37:L13.2 ai-agent-manager#45:L14.1 … (+24 more)
     invocation: add-rule.sh --category 'process' --statement 'A count or version number is claimed in exactly one authoritative machine-readable place; every other surface derives it at read time or names the authority instead of restating the literal, because a restated number is a live claim that nothing keeps current.' --enforcement advisory --applies-to 'CLAUDE.md' --source 'dreaming:2026-08-15-25e84f2' < /dev/null
     writer result: PLANNED WRITE (not written)
       | PLANNED WRITE (not written — pass --confirm to apply):
       |   target: /private/tmp/claude-501/-Users-vikashruhil-Documents-work-AI-ai-agent-manager/54b0ce93-5b49-4498-a1b4-ed52065bb450/scratchpad/clone2/.agent/rules/process.json
       |   object: {
       |   "id": "process-a-count-or-version-number-is-claimed-in-exactly-one-authoritative-machine-readable-place-every-other-surface-derives-it-at-read-time-or-names-the-authority-instead-of-restating-the-literal-because-a-restated-number-is-a-live-claim-that-nothing-keeps-current",

  2) [process] theme=cross-surface-sync  origin=ledger theme
     statement: When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.
     enforcement: advisory
     check: null  (AC9b — no obviously mechanical check; this harvester never synthesises shell into `check`)
     applies_to: [CLAUDE.md, loomwright/scripts/*]
     scope fidelity: 100% (15 of the 15 CHECKABLE motivating findings have a live changed_path matched by the derived globs, via the same bash `case` matcher read-rules.sh uses)
                     over ALL 20 motivating findings: 75% (15 of 20). The denominator above is SMALLER on purpose and the filter is not silent: 5 finding(s) come from a ledger record with no changed_paths at all, and 0 have changed_paths of which none is still tracked by git. Neither can be matched against a glob, so neither is evidence for OR against the scope — but they are motivating findings all the same, and the honest figure is the second one.
     motivating findings (20): ai-agent-manager#43:L3.2 ai-agent-manager#43:L3.7 ai-agent-manager#47:L4.4 ai-agent-manager#47:L4.6 ai-agent-manager#62:L7.5 ai-agent-manager#70:L12.1 ai-agent-manager#70:L12.3 ai-agent-manager#63:L18.3 ai-agent-manager#64:L19.2 ai-agent-manager#56:L27.2 ai-agent-manager#57:L28.2 ai-agent-manager#75:L33.4 … (+8 more)
     invocation: add-rule.sh --category 'process' --statement 'When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.' --enforcement advisory --applies-to 'CLAUDE.md' --applies-to 'loomwright/scripts/*' --source 'dreaming:2026-08-15-25e84f2' < /dev/null
     writer result: PLANNED WRITE (not written)
       | PLANNED WRITE (not written — pass --confirm to apply):
       |   target: /private/tmp/claude-501/-Users-vikashruhil-Documents-work-AI-ai-agent-manager/54b0ce93-5b49-4498-a1b4-ed52065bb450/scratchpad/clone2/.agent/rules/process.json
       |   object: {
       |   "id": "process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift",

  3) [documentation] theme=doc-currency-drift  origin=ledger theme
     statement: Prose that describes current behaviour is corrected in the same change that alters the behaviour; a sweep for the OLD wording across every doc surface is part of the change, not a follow-up.
     enforcement: advisory
     check: null  (AC9b — no obviously mechanical check; this harvester never synthesises shell into `check`)
     applies_to: [CLAUDE.md, loomwright/scripts/*]
     scope fidelity: 100% (5 of the 5 CHECKABLE motivating findings have a live changed_path matched by the derived globs, via the same bash `case` matcher read-rules.sh uses)
                     over ALL 8 motivating findings: 62% (5 of 8). The denominator above is SMALLER on purpose and the filter is not silent: 2 finding(s) come from a ledger record with no changed_paths at all, and 1 have changed_paths of which none is still tracked by git. Neither can be matched against a glob, so neither is evidence for OR against the scope — but they are motivating findings all the same, and the honest figure is the second one.
     motivating findings (8): ai-agent-manager#61:L6.2 ai-agent-manager#68:L10.1 ai-agent-manager#59:L17.1 ai-agent-manager#78:L36.1 ai-agent-manager#83:L41.1 loomwright#97:L58.5 loomwright#95:L60.5 loomwright#129:L80.2 
     invocation: add-rule.sh --category 'documentation' --statement 'Prose that describes current behaviour is corrected in the same change that alters the behaviour; a sweep for the OLD wording across every doc surface is part of the change, not a follow-up.' --enforcement advisory --applies-to 'CLAUDE.md' --applies-to 'loomwright/scripts/*' --source 'dreaming:2026-08-15-25e84f2' < /dev/null
     writer result: PLANNED WRITE (not written)
       | PLANNED WRITE (not written — pass --confirm to apply):
       |   target: /private/tmp/claude-501/-Users-vikashruhil-Documents-work-AI-ai-agent-manager/54b0ce93-5b49-4498-a1b4-ed52065bb450/scratchpad/clone2/.agent/rules/documentation.json
       |   object: {
       |   "id": "documentation-prose-that-describes-current-behaviour-is-corrected-in-the-same-change-that-alters-the-behaviour-a-sweep-for-the-old-wording-across-every-doc-surface-is-part-of-the-change-not-a-follow-up",

  4) [documentation] theme=naming-framing  origin=ledger theme
     statement: Wording that carries a contract — a heading a gate greps for, a sentence that states a guarantee — is treated as an interface: renaming it is a change to that interface and its consumers move with it.
     enforcement: advisory
     check: null  (AC9b — no obviously mechanical check; this harvester never synthesises shell into `check`)
     applies_to: [CLAUDE.md, AGENT_GUIDELINES.md]
     scope fidelity: 100% (8 of the 8 CHECKABLE motivating findings have a live changed_path matched by the derived globs, via the same bash `case` matcher read-rules.sh uses)
                     over ALL 10 motivating findings: 80% (8 of 10). The denominator above is SMALLER on purpose and the filter is not silent: 2 finding(s) come from a ledger record with no changed_paths at all, and 0 have changed_paths of which none is still tracked by git. Neither can be matched against a glob, so neither is evidence for OR against the scope — but they are motivating findings all the same, and the honest figure is the second one.
     motivating findings (10): ai-agent-manager#48:L2.2 ai-agent-manager#43:L3.4 ai-agent-manager#70:L12.4 ai-agent-manager#37:L13.1 ai-agent-manager#37:L13.3 ai-agent-manager#45:L14.2 ai-agent-manager#55:L16.3 ai-agent-manager#57:L28.3 loomwright#99:L56.1 loomwright#99:L56.4 
     invocation: add-rule.sh --category 'documentation' --statement 'Wording that carries a contract — a heading a gate greps for, a sentence that states a guarantee — is treated as an interface: renaming it is a change to that interface and its consumers move with it.' --enforcement advisory --applies-to 'CLAUDE.md' --applies-to 'AGENT_GUIDELINES.md' --source 'dreaming:2026-08-15-25e84f2' < /dev/null
     writer result: PLANNED WRITE (not written)
       | PLANNED WRITE (not written — pass --confirm to apply):
       |   target: /private/tmp/claude-501/-Users-vikashruhil-Documents-work-AI-ai-agent-manager/54b0ce93-5b49-4498-a1b4-ed52065bb450/scratchpad/clone2/.agent/rules/documentation.json
       |   object: {
       |   "id": "documentation-wording-that-carries-a-contract-a-heading-a-gate-greps-for-a-sentence-that-states-a-guarantee-is-treated-as-an-interface-renaming-it-is-a-change-to-that-interface-and-its-consumers-move-with-it",

--- metrics (AC4) — computed from the run above, not asserted ---
  coverage:        74/107 convention_mismatch findings (69%) map to >= 1 proposed rule
                   UNMAPPED REMAINDER: 33 findings, of which 26 matched no theme in the lexicon
                   and the rest belong to the themes itemised below, EACH WITH THE REASON it
                   emitted no rule. The reason is printed rather than assumed: a theme can be
                   unmapped for three different causes, and only one of them is the support
                   floor. Every unmapped theme appears here, so this list sums to
                   33 minus the 26 unthemed findings — it cannot under-state its own total:
                     citation-anchor          2    (below the 8-finding support floor)
                     test-vacuity             1    (below the 8-finding support floor)
                     gate-exit-contract       4    (below the 8-finding support floor)
  dedupe rate:     18.50 findings distilled per rule emitted (74 in / 4 out)
  scope fidelity:  aggregate 98% (54 of 55 CHECKABLE motivating findings routed by their own rule's derived globs)
                   over ALL motivating findings: 72% (54 of 74) — the 19 difference is findings whose ledger record carries no changed_paths, or none still tracked by git; they cannot be matched against a glob either way. This denominator spans EVERY emitted rule, including the 0 repo-wide one(s) whose findings are unmatchable by construction — excluding those would drop the batch's least flattering evidence from the very figure meant to expose it. Both figures are printed because the first one alone would flatter the derivation by dropping its own unfalsifiable evidence; per-rule breakdowns are with each rule above
                   0 proposal(s) fell back to a repo-wide (null) scope, each with the stated justification shown above
  distillation:    OK — above the 2.00 findings-per-rule floor.

=== END DRY RUN — no branch, no commit, no PR, nothing written to /private/tmp/claude-501/-Users-vikashruhil-Documents-work-AI-ai-agent-manager/54b0ce93-5b49-4498-a1b4-ed52065bb450/scratchpad/clone2/.agent/rules ===
```

## Reviewer's note on the numbers

The three numbers supplement the batch above; they do not replace reading it.

- **coverage** — the share of convention_mismatch findings that map to at least one proposed rule.
  The unmapped remainder is printed, not hidden: findings that matched no theme in the lexicon, plus
  themes that fell below the support floor. A high coverage number over a batch of bad rules is
  worse than a low one over good rules.
- **dedupe rate** — findings distilled per rule emitted. Its job is to make over-fitting
  self-reporting: a batch approaching one rule per finding has restated the ledger rather than
  distilled it, and the run says `DISTILLATION FAILURE` in its own output instead of offering it.
- **scope fidelity** — see the two-figure caveat above, and the per-rule breakdowns in the run.

Known limits of this sample, stated so it is not read as more than it is: the ledger's records are
overwhelmingly `agent_generated_guess: true`, the theme lexicon is a committed human-edited table
rather than a learned model, and no rule here has been accepted — the batch is a proposal awaiting
per-item human review.
