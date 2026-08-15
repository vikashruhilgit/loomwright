# Harvest dry-run sample — the real `.agent/rules/` proposal batch

This file is the **verbatim output of a real `harvest-conventions.sh` dry run over this repository's
own corpus**, committed so the batch can be judged by READING it rather than by trusting a metric.
It exists because every other deliverable of this change is a file or a symbol inside a file the same
change creates, i.e. entirely self-satisfiable: without a durable artifact, a fixture-tested script
that has never produced a reviewable batch would pass every gate.

## How to falsify this file

It is a transcript, not prose, and it is cheap to re-derive. Run **exactly** this from the repo root:

```
bash loomwright/scripts/harvest-conventions.sh --session-id 2026-08-15-3afc27a
```

The run is **read-only** — `harvest-conventions.sh` has no write mode at all, so re-running it cannot
create a branch, a commit, a PR, or a rule. If the output below is not what you get, this file is
stale or hand-written and should be rejected on that basis.

Two things will legitimately differ on a later re-run, and neither invalidates the rest:

- **`--session-id`.** Omitted, it defaults to `dreaming:<UTC date>-<short HEAD sha>`, so it moves with
  HEAD. It is pinned above to the sha this sample was taken at (`3afc27a`).
- **The ledger.** `.supervisor/postmortem/results.jsonl` grows as PRs land, so the counts below are a
  snapshot. **Input read for this sample: 85 ledger records.** The convention_mismatch class was
  107/226 (47%) of all findings at that point.

## What to look at first

- **Every proposed rule names the finding ids that motivated it** (`motivating findings (N): …`).
  An id is `<repo>#<pr>:L<ledger line>.<index into that record's categories array>` and resolves with
  e.g. `sed -n '3p' .supervisor/postmortem/results.jsonl | jq '.categories[0]'`. Spot-check two or
  three: if a rule's cited findings do not support its statement, the number below is worthless.
- **`scope fidelity`** is a check OF THE DERIVATION, not an independent oracle — the derivation and
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
invocation: 'loomwright/scripts/harvest-conventions.sh' '--session-id' '2026-08-15-3afc27a'
session source (--source passed to add-rule.sh): dreaming:2026-08-15-3afc27a
thresholds: cap=5  min-support=8  project-wide=85%  distillation-floor=2.00  applies-to-cover=95%  max-globs=4

--- inputs read ---
  (i)  ledger:    /Users/vikashruhil/Documents/work/AI/ai-agent-manager/.supervisor/postmortem/results.jsonl
       85 records read WHOLE (no repo filter — decision (a); nothing dropped), 226 findings, 95 self-heal misses
  (ii) corpus:    /Users/vikashruhil/Documents/work/AI/ai-agent-manager/.claude/agent-memory
       28 entries (MEMORY.md indexes excluded)
       proposals queue: /Users/vikashruhil/Documents/work/AI/ai-agent-manager/.supervisor/agent-memory-proposals — absent (normal empty case — the queue has never been populated in this repo)
  convention surfaces for the project-wide signal: 2 of 2 readable
  rules store (read for context, NEVER written): /Users/vikashruhil/Documents/work/AI/ai-agent-manager/.agent/rules

--- repo distribution (advisory cross-check, decision (a)) ---
      79  vikashruhilgit/ai-agent-manager
      28  vikashruhilgit/loomwright
  (no --expect-repo supplied, so nothing is flagged. This script never resolves a repo
   allowlist itself: the available resolver reads gitignored machine-local config, which
   would make this check behave differently here and in CI. Pass --expect-repo to arm it.)

--- target class (AC14) ---
  this batch targets: convention_mismatch
  share of all findings:      107/226 (47%)
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
     scope fidelity: 96% (26 of 27 motivating findings have a live changed_path matched by the derived globs, via the same bash `case` matcher read-rules.sh uses)
     motivating findings (36): ai-agent-manager#43:L3.1 ai-agent-manager#43:L3.5 ai-agent-manager#60:L5.4 ai-agent-manager#62:L7.3 ai-agent-manager#67:L8.3 ai-agent-manager#67:L8.4 ai-agent-manager#67:L9.3 ai-agent-manager#67:L9.4 ai-agent-manager#67:L9.7 ai-agent-manager#70:L12.2 ai-agent-manager#37:L13.2 ai-agent-manager#45:L14.1 … (+24 more)
     invocation: add-rule.sh --category 'process' --statement 'A count or version number is claimed in exactly one authoritative machine-readable place; every other surface derives it at read time or names the authority instead of restating the literal, because a restated number is a live claim that nothing keeps current.' --enforcement advisory --applies-to 'CLAUDE.md' --source 'dreaming:2026-08-15-3afc27a' < /dev/null
     writer result: PLANNED WRITE (not written)
       | PLANNED WRITE (not written — pass --confirm to apply):
       |   target: /Users/vikashruhil/Documents/work/AI/ai-agent-manager/.agent/rules/process.json
       |   object: {
       |   "id": "process-a-count-or-version-number-is-claimed-in-exactly-one-authoritative-machine-readable-place-every-other-surface-derives-it-at-read-time-or-names-the-authority-instead-of-restating-the-literal-because-a-restated-number-is-a-live-claim-that-nothing-keeps-current",

  2) [process] theme=cross-surface-sync  origin=ledger theme
     statement: When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.
     enforcement: advisory
     check: null  (AC9b — no obviously mechanical check; this harvester never synthesises shell into `check`)
     applies_to: [CLAUDE.md, loomwright/scripts/*]
     scope fidelity: 100% (15 of 15 motivating findings have a live changed_path matched by the derived globs, via the same bash `case` matcher read-rules.sh uses)
     motivating findings (20): ai-agent-manager#43:L3.2 ai-agent-manager#43:L3.7 ai-agent-manager#47:L4.4 ai-agent-manager#47:L4.6 ai-agent-manager#62:L7.5 ai-agent-manager#70:L12.1 ai-agent-manager#70:L12.3 ai-agent-manager#63:L18.3 ai-agent-manager#64:L19.2 ai-agent-manager#56:L27.2 ai-agent-manager#57:L28.2 ai-agent-manager#75:L33.4 … (+8 more)
     invocation: add-rule.sh --category 'process' --statement 'When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.' --enforcement advisory --applies-to 'CLAUDE.md' --applies-to 'loomwright/scripts/*' --source 'dreaming:2026-08-15-3afc27a' < /dev/null
     writer result: PLANNED WRITE (not written)
       | PLANNED WRITE (not written — pass --confirm to apply):
       |   target: /Users/vikashruhil/Documents/work/AI/ai-agent-manager/.agent/rules/process.json
       |   object: {
       |   "id": "process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift",

  3) [documentation] theme=doc-currency-drift  origin=ledger theme
     statement: Prose that describes current behaviour is corrected in the same change that alters the behaviour; a sweep for the OLD wording across every doc surface is part of the change, not a follow-up.
     enforcement: advisory
     check: null  (AC9b — no obviously mechanical check; this harvester never synthesises shell into `check`)
     applies_to: [CLAUDE.md, loomwright/scripts/*]
     scope fidelity: 100% (5 of 5 motivating findings have a live changed_path matched by the derived globs, via the same bash `case` matcher read-rules.sh uses)
     motivating findings (8): ai-agent-manager#61:L6.2 ai-agent-manager#68:L10.1 ai-agent-manager#59:L17.1 ai-agent-manager#78:L36.1 ai-agent-manager#83:L41.1 loomwright#97:L58.5 loomwright#95:L60.5 loomwright#129:L80.2 
     invocation: add-rule.sh --category 'documentation' --statement 'Prose that describes current behaviour is corrected in the same change that alters the behaviour; a sweep for the OLD wording across every doc surface is part of the change, not a follow-up.' --enforcement advisory --applies-to 'CLAUDE.md' --applies-to 'loomwright/scripts/*' --source 'dreaming:2026-08-15-3afc27a' < /dev/null
     writer result: PLANNED WRITE (not written)
       | PLANNED WRITE (not written — pass --confirm to apply):
       |   target: /Users/vikashruhil/Documents/work/AI/ai-agent-manager/.agent/rules/documentation.json
       |   object: {
       |   "id": "documentation-prose-that-describes-current-behaviour-is-corrected-in-the-same-change-that-alters-the-behaviour-a-sweep-for-the-old-wording-across-every-doc-surface-is-part-of-the-change-not-a-follow-up",

  4) [documentation] theme=naming-framing  origin=ledger theme
     statement: Wording that carries a contract — a heading a gate greps for, a sentence that states a guarantee — is treated as an interface: renaming it is a change to that interface and its consumers move with it.
     enforcement: advisory
     check: null  (AC9b — no obviously mechanical check; this harvester never synthesises shell into `check`)
     applies_to: [CLAUDE.md, AGENT_GUIDELINES.md]
     scope fidelity: 100% (8 of 8 motivating findings have a live changed_path matched by the derived globs, via the same bash `case` matcher read-rules.sh uses)
     motivating findings (10): ai-agent-manager#48:L2.2 ai-agent-manager#43:L3.4 ai-agent-manager#70:L12.4 ai-agent-manager#37:L13.1 ai-agent-manager#37:L13.3 ai-agent-manager#45:L14.2 ai-agent-manager#55:L16.3 ai-agent-manager#57:L28.3 loomwright#99:L56.1 loomwright#99:L56.4 
     invocation: add-rule.sh --category 'documentation' --statement 'Wording that carries a contract — a heading a gate greps for, a sentence that states a guarantee — is treated as an interface: renaming it is a change to that interface and its consumers move with it.' --enforcement advisory --applies-to 'CLAUDE.md' --applies-to 'AGENT_GUIDELINES.md' --source 'dreaming:2026-08-15-3afc27a' < /dev/null
     writer result: PLANNED WRITE (not written)
       | PLANNED WRITE (not written — pass --confirm to apply):
       |   target: /Users/vikashruhil/Documents/work/AI/ai-agent-manager/.agent/rules/documentation.json
       |   object: {
       |   "id": "documentation-wording-that-carries-a-contract-a-heading-a-gate-greps-for-a-sentence-that-states-a-guarantee-is-treated-as-an-interface-renaming-it-is-a-change-to-that-interface-and-its-consumers-move-with-it",

--- metrics (AC4) — computed from the run above, not asserted ---
  coverage:        74/107 convention_mismatch findings (69%) map to >= 1 proposed rule
                   UNMAPPED REMAINDER: 33 findings, of which 26 matched no theme in the lexicon
                   and the rest belong to themes below the 8-finding support floor:
                     citation-anchor          2
                     test-vacuity             1
                     gate-exit-contract       4
  dedupe rate:     18.50 findings distilled per rule emitted (74 in / 4 out)
  scope fidelity:  aggregate 98% (54 of 55 motivating findings routed by their own rule's derived globs); per-rule figures are printed with each rule above
                   0 proposal(s) fell back to a repo-wide (null) scope, each with the stated justification shown above
  distillation:    OK — above the 2.00 findings-per-rule floor.

=== END DRY RUN — no branch, no commit, no PR, nothing written to /Users/vikashruhil/Documents/work/AI/ai-agent-manager/.agent/rules ===
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
- **scope fidelity** — see the caveat above.

Known limits of this sample, stated so it is not read as more than it is: the ledger's records are
overwhelmingly `agent_generated_guess: true`, the theme lexicon is a committed human-edited table
rather than a learned model, and no rule here has been accepted — the batch is a proposal awaiting
per-item human review.
