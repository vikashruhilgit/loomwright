# Supervisor Job: pa/18b — `right-size` verdict (small / ok / large) with merge candidates, a mechanical `merge-items` helper, and the size line where items are written and queued

## Environment
- **Project:** L1 (lane clone of the loomwright marketplace repo)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/parallel-automate/18b-right-size-check.md
- **Base commit:** 7b7cb08392ce372c66c0694db7ced666fd0cbba9

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2-portable shell + jq + awk, the same stack as every `automate-helpers.d/` family |
| 2 | Dependency Availability | GO | No new dependency; reuses `plan_waves --touches` (`_pw_touches` + `_pw_expand`), `is_done`, `is_not_ready`, `_rs_skip_path` |
| 3 | Architecture Fit | GO | A new helper family file `automate-helpers.d/right-size.sh`, registered the way `plan-waves.sh` is (marker pair + `_ah_source`, `_AH_HELP_SEGMENTS`, case arm, per-segment golden) |
| 4 | Scope vs Supervisor Capability | CAUTION | ~30 files across scripts, tests, fixtures, skills and prompts. This exceeds one worker's context (`context-bound`), so the work is split into 4 dependency-ordered subtasks |
| 5 | Hard Blockers | GO | None. The af/33 merge originals and the ms/09, ms/10 items exist locally (gitignored, metadata branch), so committed fixture copies can be built from them |

**Overall Verdict:** CAUTION

## Task
**Goal:** Ship `automate-helpers.sh right-size <item|dir|item-list> [--root <checkout>] [--json]`. It gives a `small` / `ok` / `large` / `unknown` verdict per item, computed from the item's companion-expanded Touches, with merge candidates for `small` and a split remedy for `large`. Also ship a mechanical, lossless `automate-helpers.sh merge-items`, and print the size line at the requirement writers, at folder/backlog intake, and in `plan-waves --explain`.

**Problem Statement:**
The owner and the requirement writers (Product Owner, `/propose`, dismissed-finding drafts) need to know, when an item is written or queued, whether it is too small to pay a full `/automate` run (~$17–20 and four or more owner questions) or too big for one PR.
Currently `skills/user-story-writing/SKILL.md` §"Shape decision" says "No mechanical size check ships yet: count by hand". Items written one finding at a time come out too small. Merged items come out too big (pa/18 itself reached ~50 files and had to be split). Each hand merge (af/33 = 17 + 25, ms/08, af/32) repeated the same copy / park / re-point / no-line-lost steps.
Success looks like: one advisory verdict line per item, computed from the same companion-expanded Touches set the planner reserves; merge candidates that never name a parked, done, operator-run item or a cycle; a `merge-items` that refuses to write unless every original line survives; and the skill text pointing at the command instead of "count by hand". Nothing is blocked and nothing is merged without the owner.

## Acceptance Criteria

Thresholds (owner decision 2026-10-22, from the requirement): `small` = companion-expanded Touches count ≤ `right_size_small` (default 3). `large` = count > `right_size_large_files` (default 30) OR `## Part` count > `right_size_max_parts` (default 7). A Touches-unknown item reads `unknown`, never `small`. Keys are read from `<root>/.supervisor/config.json`. An absent, malformed, non-integer or negative value falls back to the default.

**right-size (Subtask 1)**
- [ ] AC1 — Given a hermetic temp requirements tree (`mktemp -d`, its own `.agent/companions.json`) and an item whose companion-expanded Touches has 3 files, when `right-size <item> --root <tmp>` runs, then it prints `<item>: small (3 files, <S> scope items, <A> criteria) — merge candidates: <cand> (<k> shared files[, same chain][, same folder])`. At least one named candidate shares a Touches path with the item, and the line names the shared files' count.
- [ ] AC2 — Given the same tree with a `parked`, a `proposed`, a `done`, an `operator-run/` and a cycle-forming sibling that each share files with the small item, when `right-size` runs, then none of them is ever named as a candidate. A cycle-forming sibling is one where merging would make the merged item depend on itself through a third item. When no eligible sibling remains, the line reads `merge candidates: none`.
- [ ] AC3 — Given an item with 31 expanded Touches files, and separately an item with 8 `## Part` headings, when `right-size` runs, then each reads `large (…) — will not fit one PR: split by Part`. An item with both causes names both (e.g. `large (35 files, 8 parts) — will not fit one PR: split by Part`).
- [ ] AC4 — Given `{"right_size_small": 5}` in `<tmp>/.supervisor/config.json`, when `right-size` runs on a 4-file item, then the verdict is `small`. With the key absent, the same item reads `ok`. A malformed config, or a non-integer or negative value, reads the default (3) and never aborts.
- [ ] AC5 — Given an item whose `## Touches` is missing, unparsable or the sole `unknown`, when `right-size` runs, then the verdict is `unknown (Touches <why>)` (the `plan-waves --touches` reason text), never `small`.
- [ ] AC6 — Given a plan doc built from the skill's plan-doc template (extracted between the `plan-doc-template:begin/end` markers, never copied), when `right-size <plan doc>` runs, then it prints `<doc>: plan doc: sections ok` followed by the normal verdict line for each checklist item. With one required section deleted it prints `plan doc: missing: <names>`. Given an item with a `## Measurements` section that names no frozen commit (no 7–40 hex sha), it prints one extra `<item>: measurements: no frozen commit named` line (C5/C6 leftovers). Advisory only: none of these changes the exit code.
- [ ] AC7 — Given `--json`, when `right-size` runs, then stdout is ONE JSON array with one object per item. Each object carries `item`, `verdict`, `files`, `scope_items`, `criteria`, `parts`, `causes` (array), `candidates` (array of `{item, shared_files, same_chain, same_folder}`), `plan_doc` (null | `"ok"` | array of missing names) and `measurements` (null | `"no_frozen_commit"`), built with `jq` (never shell-templated). This is the column 18a's board reads. The shape is documented in `right-size.sh`'s header (Subtask 1) and, by Subtask 4, in `skills/automate-loop/helpers.md`.
- [ ] AC8 — Given usage errors, an item that does not exist, or `companions_malformed`, when `right-size` runs, then it exits 1 with empty stdout (the `plan-waves` convention). Every verdict path, including `unknown`, `large` and missing plan-doc sections, exits 0.
- [ ] AC9 — Hermetic fixtures (committed under `loomwright/scripts/fixtures/right-size/` and copied into a temp tree; no test reads the live `.supervisor/requirements/`) reproduce the Source text's three acceptance checks:
  - (a) copies of `meta-sync-followups/09` and `/10` read `small` and name each other as the TOP candidate (`same folder`). The copies are restamped `## Status: pending`, since both are parked in the live tree. They sit alone in one folder of a fixture tree whose `.supervisor/config.json` sets `right_size_small` to 7 and whose `.agent/companions.json` carries the repo's `loomwright/agents/*.md` companion rule (copied from `.agent/companions.json`), because their expanded counts are 4 and 7 (agent companion). The 2026-10-06 check predates the 3-file default, so at the default they read `ok`. The fixture/test comment records this; a second leg asserts that at the default both read `ok`.
  - (b) an iq/02-shaped fixture (over 30 files, 10 parts) reads `large` with both causes and `split by Part`;
  - (c) the `merge-items` round trip in AC12.

**merge-items (Subtask 1)**
- [ ] AC10 — Given two originals A and B in a temp tree, when `merge-items <out.md> --title <t> --goal <text> --date <YYYY-MM-DD> A:<a.md> B:<b.md>` runs, then `<out.md>` holds:
  - the title and goal;
  - each original's body copied VERBATIM as `## Part <X> — <original title>` with its headings demoted one level. The original's `## Status`, `## Depends on` and `## Touches` sections are REMOVED from its Part body, because they are folded below;
  - each original's Status / Depends on / Touches folded into the merged item's own `## Depends on` (union, minus the originals themselves) and `## Touches` (union, sorted unique, `changelog.d/<original>.md` fragments replaced by one `changelog.d/<out-slug>.md`).

  Each original's `## Status:` becomes `parked (merged <date> into <out> as Part <X> — do not run this file)`. Every pool item whose `## Depends on` names an original is re-pointed to `<out>` (deduplicated, relative path from the dependent's directory).
- [ ] AC11 — The post-check's scope, exactly:
  - (a) every non-heading, non-blank line of each original OUTSIDE its Status / Depends on / Touches sections appears verbatim in that original's Part;
  - (b) every Touches line of each original appears in the merged `## Touches`, except a `changelog.d/<original-slug>.md` line, which must map to the one `changelog.d/<out-slug>.md` line;
  - (c) every Depends on line of each original appears in the merged `## Depends on`, except `none` and references to the originals themselves;
  - (d) the original's Status line is not carried (it is replaced by the parked stamp).

  Given a merge where any line covered by (a)–(c) is missing from the output, when the post-check runs, then `merge-items` exits 1 and writes NOTHING: no `<out.md>`, no original restamped, no dependent edited. All writes are staged in temp files and renamed only after the post-check passes. It also refuses (exit 1, nothing written) a `done` original, an `operator-run/` original, an already-merged original (`## Status: parked (merged …`), and a merge that would create a dependency cycle. Legs prove each of (a), (b) and (c) separately: a dropped body line, a dropped non-changelog Touches line, and a dropped Depends on line each trip the post-check, while the `changelog.d` remap alone does not.
- [ ] AC12 — Given committed fixture copies of `automate-followups/17` and `/25` as they were before the 2026-10-05 merge (the `## Status: parked (merged …)` line removed), when `merge-items` runs, then the post-check reports zero lost lines and the output equals a committed golden `fixtures/right-size/merge-af33.expected.md` byte-for-byte (the real pin). Against the hand-merged `automate-followups/33` (fixture copy as merged: its `## Touches re-pointed 2026-10-07…` and `## Amended 2026-10-07…` sections and `## Status: done` dropped):
  - the produced Part B equals 33's Part B modulo heading depth and blank lines;
  - the produced Part A equals 33's Part A plus the 4-line `> **Promoted from \`proposed/\` …` / `> **Origin (2026-10-01).** …` blockquote of af/17, which the hand merge dropped.

  The test asserts exactly that difference and the fixture README records it as the hand-merge line loss that the post-check exists to catch.

**Where the line prints (Subtasks 2–4)**
- [ ] AC13 — Given `plan-waves <set> --max N --explain`, when a placed item is `small` (counted from the planner's OWN already-expanded Touches set, never a second `## Touches` parse, through the SAME count function right-size uses, `_rsz_count`, so the directory-entry rule is identical and the two verdicts cannot disagree), then its explain block carries one `  small (<N> files): run right-size <item> for merge candidates` line. This applies to every placed item, wave 1 included: a small wave-1 item gets an `explain <item> (wave 1):` block holding just that line. The default `--max`, `--lint` and `--touches` outputs stay byte-identical (pins X2, X2b and lane-readiness's `--touches` read).
- [ ] AC14 — Given a successful `pc_guarded_write` of a `*.md` requirement draft (not `README.md`, not a name starting with `_`), when the write returns 0, then one `right-size` line for the written file is printed on STDERR. The `--root` is derived by walking up from `<out_dir_abs>` to the nearest directory holding `.supervisor/`; when none is found, the line is skipped silently. The return code, stdout and the written bytes are unchanged. When `right-size` fails or is absent, nothing is printed and the write still returns 0. This holds for the `/propose` bases (`propose-work.sh`, `propose-domain.sh`, `propose-from-verify.sh`) and both `automate-dismissed.sh` call sites. The dismissed-drafts TSV `draft` rows on stdout and each propose basis's stdout stay byte-identical (`test-propose-from-verify.sh` re-run to prove it).
- [ ] AC15 — Given folder or backlog intake (`skills/automate-loop/intake.md`), when the Queue is resolved, then the prose runs `automate-helpers.sh right-size <resolved Queue>` before the Queue is confirmed and prints its lines beside the Queue. This happens in every mode: sequential runs gain the advisory line but no prompt and no gate. It sits beside the `--parallel N>1` `plan-waves --lint` line. It is never a gate, `automate-next-step.sh` gains no call site, and a non-zero exit blocks nothing.
- [ ] AC15b — Given the docs that restate plan-waves' callers and `--explain` scope, when Subtask 4 lands, then each one matches the new behaviour:
  - `skills/automate-loop/helpers.md`'s `plan-waves` row says `--explain` covers every placed item (wave-1 small notes), and its "never called when N = 1 / the sequential loop never calls it" claim carves out the read-only `--touches` read that `right-size` makes;
  - the new `right-size` / `merge-items` rows document the `--json` shape, the count rule, the candidate rule, the thresholds (pointing at config.sh's reader) and `merge-items`' requirements-tree-only write carve-out;
  - loop-inventory row AL-053 is reworded or annotated to match;
  - intake.md §14's "Sequential runs … unchanged — no lint, no new prompt, no new gate" stays true for lint and states that the advisory `right-size` line is printed in every mode.

  Subtask 2 rewords `plan-waves.golden` and its `#:  ` line to match.
- [ ] AC16 — Given `skills/user-story-writing/SKILL.md` §"Shape decision", when it is read, then it no longer says "count by hand". It names `automate-helpers.sh right-size <item>` (`small` ⇒ merge into a named candidate, or `merge-items`; `large` ⇒ split by Part) and carries the Scope 5 wording "small enough to review in one PR, large enough to pay the run's fixed cost; when two stories touch the same files, prefer one story with parts". The Product Owner agent's Persist step and its `commands/product-owner.md` mirror both run `right-size` on each persisted file after the `plan-waves --lint` call, with identical text (same commit).
- [ ] AC17 — Mutation controls, each turning its leg red in a scratch copy (gate every mutant on non-empty + differs-from-original + `bash -n`):
  - (i) dropping the companion expansion from the size count fails a `17-right-size` leg;
  - (ii) dropping the parked/done exclusion from merge candidates fails a `17-right-size` leg;
  - (iii) dropping `merge-items`' lost-line post-check fails a `17-right-size` leg.
- [ ] AC18 — Given the finished branch, when the Validation's running-system step is performed, then a committed evidence file `docs/evidence/pa18b-right-size-check.md` contains:
  - the three `right-size` verdict lines for hand-built items with 2, 12 and 35 Touches files in a temp tree (the exact commands included);
  - the targeted-test `<passed>/<total>` lines.

  The PR body links to it.
- [ ] AC19 — Given the branch, when `bash scripts/check-version-bump.sh` runs, then it passes with the `changelog.d/pa18b-right-size-check.md` fragment folded by `bash scripts/bump-version.sh`.

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

Applying them here:
- The three threshold defaults live ONCE, in `automate-helpers.d/config.sh`'s reader. The skill and helpers.md name the keys and point at that reader (or quote the owner decision); they do not add a second numeric copy that must be kept in sync.
- The helpers.md subcommand table, the `--help` goldens and the `#:` usage lines are restatements of the case arms. All of them are updated in the same change.
- The `--explain` "not in wave 1" wording and the "never called when N = 1" claim are restated in `plan-waves.sh`'s `#:  ` line and header, `plan-waves.golden`, helpers.md's `plan-waves` row, loop-inventory AL-053 and intake.md §14. All of them are updated in this change (AC15b; Subtask 2 owns the script, header and golden, Subtask 4 owns the rest).

## File Impact Map

| Group | Files to Modify | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| right-size core (S1) | `loomwright/scripts/automate-helpers.sh`, `loomwright/scripts/automate-helpers.d/config.sh`, `loomwright/scripts/test-automate-helpers.d/01-config.sh`, `loomwright/scripts/test-automate-helpers.sh` (TAH_PARTS + `tah_run 17-right-size` line), `loomwright/scripts/test-automate-helpers-dispatch.sh` (SEGMENTS), `loomwright/scripts/automate-helpers.d/intake.sh` (MEDIUM — only if intake needs a helper; otherwise unchanged) | `loomwright/scripts/automate-helpers.d/right-size.sh`, `loomwright/scripts/fixtures/automate-helpers-help/right-size.golden`, `loomwright/scripts/fixtures/right-size/` (ms-09, ms-10, af-17-pre, af-25-pre, af-33-merged, merge-af33.expected.md, iq-02-shaped), `loomwright/scripts/test-automate-helpers.d/17-right-size.sh` | HIGH |
| planner note (S2) | `loomwright/scripts/automate-helpers.d/plan-waves.sh`, `loomwright/scripts/test-automate-helpers.d/13-plan-waves.sh`, `loomwright/scripts/fixtures/automate-helpers-help/plan-waves.golden` | — | HIGH |
| writer seams (S3) | `loomwright/scripts/propose-common.sh`, `loomwright/scripts/test-propose-common.sh`, `loomwright/scripts/automate-dismissed.sh` (MEDIUM — only comment/doc lines if the seam lives wholly in `pc_guarded_write`), `loomwright/scripts/test-automate-dismissed.sh`, `loomwright/scripts/test-propose-from-verify.sh` (MEDIUM — a stderr/stdout-unchanged leg) | — | HIGH |
| docs + prompts (S4) | `loomwright/skills/user-story-writing/SKILL.md`, `loomwright/skills/automate-loop/intake.md`, `loomwright/skills/automate-loop/helpers.md`, `loomwright/skills/SKILLS_INDEX.md`, `loomwright/agents/product-owner.md`, `loomwright/commands/product-owner.md`, `loomwright/scripts/test-requirement-shape.sh`, `loomwright/docs/prompt-token-budgets.json`, `loomwright/docs/ARCHITECTURE_CONTRACTS.md`, `loomwright/docs/loop-inventory/automate-loop.md` (MEDIUM — only if an intake.md/helpers.md heading or `q:` anchor changes) | `changelog.d/pa18b-right-size-check.md`, `docs/evidence/pa18b-right-size-check.md` | HIGH |

> **Validator-owned surfaces:** `scripts/check-doc-currency.sh` (doc surface); `scripts/check-token-budget.sh` (`.agents["product-owner"]`, `.commands["product-owner"]`, `.skills["user-story-writing"]` — 431 tokens headroom at base, `.skills["automate-loop"]` — every `*.md` under the dir is counted); `scripts/check-skills-index-sync.sh` (SKILLS_INDEX Version cell = SKILL.md `version:` — bump `user-story-writing` 1.3.0 → 1.4.0, and `automate-loop` if its files change by convention); `loomwright/scripts/test-loop-inventory.sh` (heading coverage + live `q:` anchors for `skills/automate-loop/*.md`; AL-051..053 and AL-182 anchor helpers.md / intake.md); `scripts/check-prompt-history-refs.sh` (ratchet — runtime prompts may not gain history refs); `loomwright/scripts/test-citation-drift.sh`; `loomwright/scripts/test-automate-helpers-dispatch.sh` (per-segment goldens).

The requirement's own Touches list omits `test-automate-helpers.sh`, `test-automate-helpers-dispatch.sh`, the evidence file and the loop inventory. They are added here because the new family and test part are registered in closed lists those files own (see `## Closed enumerations touched`).

**Total estimated files:** 24 modify + 6 create = 30 entries with the fixture dir counted once. Counting the fixture dir's ~7 files under its own directory rule gives ~36, so this item would itself read `large`. The owner already split pa/18 to this size, and the excess is test fixtures (see Risk Assessment).

## Touched-file invariants

> Grounded at base `7b7cb08392ce372c66c0694db7ced666fd0cbba9`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/automate-helpers.sh`**
  - keep: families sourced BY NAME between marker pairs, never globbed (`# >>> automate-helpers.d/plan-waves.sh` / `_ah_source plan-waves` / `# <<< automate-helpers.d/plan-waves.sh`); `_ah_usage` fails CLOSED on a listed segment with no line, so the new segment must have ≥1 `#:  ` line; exit codes `0 success; 1 generic failure; 2 abort`.
  - reuse: add `right-size` to `_AH_HELP_SEGMENTS="config runfile intake resume hdr-gate learning escalation reconcile-status hdr-trail meta plan-waves hdr-lanes"` (after `plan-waves`), and add `right-size)` / `merge-items)` arms beside `plan-waves)      plan_waves "$@" ;;`.
  - mirror: the header's READ-ONLY claim (`it never edits source repos, never runs git mutations of its own`) — `merge-items` writes only requirement files under the requirements tree, on the owner's explicit invocation. Subtask 1 states that carve-out in the header; Subtask 4 states it in helpers.md's closing note.
  - pinned by: `test-automate-helpers-dispatch.sh` (`SEGMENTS="config runfile intake resume hdr-gate learning escalation reconcile-status hdr-trail meta plan-waves hdr-lanes incidental"`, mutants (a)/(b) loop every family automatically).
- **`loomwright/scripts/automate-helpers.d/plan-waves.sh`**
  - keep: every mode's error contract `exit 1 + empty stdout`; the `--touches` output exactly `known` then sorted unique entries (lane-readiness reads it: `plan-waves "$d/$item" --touches --root "$d"` in `automate-lanes.d/readiness.sh`); `_PW_EXPLAIN=0   # reset per call` (pin X2b); X2's rule that `--explain`'s stdout up to the first `explain ` line equals the default run.
  - reuse: the note is built inside the existing `# 8. --explain:` block from the planner's own `_pw_expand` output (the `.why` sidecar / `$_PW_TMP/t.$i` set), never a second `## Touches` parse; the threshold comes from config.sh's reader.
  - pinned by: `13-plan-waves.sh` X1 byte-for-byte pins (`x_rc "X1 explain: …"`). Their fixture items have 1–2 files, so they turn `small` and those pins must be updated deliberately; X2/X2b stay as they are.
- **`loomwright/scripts/automate-helpers.d/config.sh`**
  - keep: the existing three subcommands' semantics and `config.golden` (a reader function only — no new `#:  ` line unless a subcommand is added).
  - reuse: the falsy-safe read idiom used by `config_orig` (`if has("auto_review") and (.auto_review != null) then … else … end`) — never `.key // default`; integer type check before use.
  - pinned by: `01-config.sh` §A legs (add A-legs for the three keys: absent, valid, malformed file, non-integer, negative).
- **`loomwright/scripts/propose-common.sh`**
  - keep: `pc_guarded_write` returns 0 on a successful write and 1 on a refusal (`Returns 0 on a successful write`); the marked guard block `# >>> WRITE-PATH GUARD (a mutation control deletes this marked block)` / `# <<< END WRITE-PATH GUARD` unchanged, and no redundant second check (the comment `a second, redundant check at the call site would make THIS guard's own mutation control … vacuous`); `set -uo pipefail`, no `set -e`; sourced only, no main.
  - reuse: the size line is printed AFTER the successful `mv -f` and before `return 0`, on stderr, swallowing every failure of the `right-size` call (fail-SAFE emitter). It resolves the dispatcher as a sibling of this file (`${BASH_SOURCE[0]}`), because callers source it from `$SCRIPT_DIR`. Skip `README.md` (propose-work writes one through `guarded_write "README.md"`) and `_*` names.
  - mirror: `automate-dismissed.sh` captures `err="$(pc_guarded_write "$out_abs" "$SELF" "$name" < "$src" 2>&1)"`, and on success that capture is discarded, so stdout `draft` rows stay byte-identical. `dismissed-decide` pipes with `2>/dev/null`, so its line is silently dropped (acceptable, document it).
  - pinned by: `test-propose-common.sh`, `test-propose-work.sh` AC8, `test-propose-domain.sh` AC10, `test-automate-dismissed.sh` A11 (`plan-waves --lint reports every draft … ok`).
- **`loomwright/scripts/automate-dismissed.sh`**
  - keep: `always exits 0`; the TSV `printf 'draft\t%s\t%s\t%s\n'` rows and the `dismissed-drafts: <n> per-finding + <s> summary` summary line byte-identical on stdout.
  - reuse: the seam lives in `pc_guarded_write`; add no second right-size call here.
  - pinned by: `test-automate-dismissed.sh`.
- **`loomwright/scripts/test-automate-helpers.d/13-plan-waves.sh`** — keep: X2's `x_same` prefix check and X2b's same-shell `plan_waves … --explain` then default call, both unchanged. X1 pins (`x_rc "X1 explain: …"`) change only by adding the new small-note lines. Add one leg proving a non-small item gets no note and one proving `--touches` output is unchanged.
- **`loomwright/scripts/test-automate-helpers.d/01-config.sh`** — keep: the §A suppress/restore legs (`echo "== A. config suppress / restore =="`) untouched. New legs go in their own lettered group and use `mktemp -d` dirs, as A1 does.
- **`loomwright/scripts/test-automate-helpers-dispatch.sh`** — keep: mutants (a)/(b) iterate every `_ah_source` family automatically (`only $NFAM _ah_source lines found`); add only `right-size` to `SEGMENTS` (before `hdr-lanes`, matching `_AH_HELP_SEGMENTS`).
- **`loomwright/scripts/test-propose-common.sh`, `loomwright/scripts/test-automate-dismissed.sh`, `loomwright/scripts/test-propose-from-verify.sh`** — keep: every existing mutation control still points `PROPOSE_COMMON_SH` at a mutated COPY of propose-common.sh (`"${PROPOSE_COMMON_SH:-$SCRIPT_DIR/propose-common.sh}"`). New legs assert rc, stdout and file bytes are unchanged, and the stderr line appears exactly once (absent when `right-size` is unavailable). Keep `A11 plan-waves --lint reports every draft` green.
- **`loomwright/scripts/test-requirement-shape.sh`** — keep: S1's template extraction between the `plan-doc-template:begin/end` markers and M1/M2 mutation controls. Add legs: "count by hand" is absent from the skill, and `right-size` is named identically in the skill, the PO agent and the command mirror.
- **`loomwright/scripts/automate-helpers.d/intake.sh`** — keep: `resolve_folder` / `resolve_backlog` / `queue_confirm` output byte-identical (`03-intake.sh`). Expected change: none. Intake's size line is prose in intake.md calling `right-size`. Touch this file only if a helper turns out to be needed, and then add a `03-intake.sh` leg.
- **`loomwright/scripts/test-automate-helpers.sh`**
  - keep: `TAH_PARTS` is the ONE part list and the runner self-checks that its source lines equal one `tah_run <p> && . "$TAH_D/<p>.sh"` per part, in order. Append `17-right-size` to `TAH_PARTS` and add `tah_run 17-right-size && . "$TAH_D/17-right-size.sh"` after the `16-queue-gates` line.
- **`loomwright/skills/user-story-writing/SKILL.md`, `loomwright/agents/product-owner.md`, `loomwright/commands/product-owner.md`**
  - keep: the plan-doc template between the `plan-doc-template:begin/end` markers (extracted by `test-requirement-shape.sh` S1); the PO agent and command Persist-step paragraphs stay identical text (`Before reporting, run \`bash "${CLAUDE_PLUGIN_ROOT}/scripts/automate-helpers.sh" plan-waves <each persisted file> --lint\``); runtime prompts gain no history references (`check-prompt-history-refs.sh` baseline only goes down). So the S2 lane-cost evidence behind the defaults goes in `right-size.sh`'s header comment and the changelog fragment, never in the skill or the prompt.
  - pinned by: `test-requirement-shape.sh` S1–S4 (`(S4) agent and command mirror both name the plan doc`); `test-wave-scope.sh` S1 (``run `automate-helpers.sh plan-waves <file> --max <item count> --explain` ``) and S1b (`**Choose N from the plan, never a fixed default**`). Keep both strings in the skill verbatim.

## Closed enumerations touched

> Sibling grep at base `7b7cb08`: `git grep -nF 'plan-waves' -- ':!CHANGELOG.md' ':!.supervisor'` → ~40 hits (prose, evidence docs, the case arm, the segment lists); `git grep -nF '16-queue-gates' -- ':!CHANGELOG.md' ':!docs/evidence'` → 2 hits in `test-automate-helpers.sh`.

- **`right-size` / `merge-items`** (sibling: `plan-waves`) — must be named in:
  - `loomwright/scripts/automate-helpers.sh` — `main()` case arms (`plan-waves)      plan_waves "$@" ;;`) — extend.
  - `loomwright/scripts/automate-helpers.sh` — `_AH_HELP_SEGMENTS="… meta plan-waves hdr-lanes"` — extend with segment `right-size`.
  - `loomwright/scripts/test-automate-helpers-dispatch.sh` — `SEGMENTS="… plan-waves hdr-lanes incidental"` — extend with `right-size` in the same position.
  - `loomwright/scripts/fixtures/automate-helpers-help/` — one golden per segment — create `right-size.golden`.
  - `loomwright/skills/automate-loop/helpers.md` — the §1.5 subcommand table (`| \`plan-waves\` | \`--parallel N>1\` only (item 05) |`) — extend with two rows.
  - `loomwright/docs/loop-inventory/automate-loop.md` — rows for helpers.md / intake.md headings — no change unless a new `###`/`####` heading is added or an existing `q:` anchor's text is edited (then add/adjust rows and the `## Counts` lines).
  - `loomwright/scripts/automate-lanes.d/readiness.sh`, `automate-wave.sh`, `propose-*.sh`, `docs/evidence/*` — prose/consumer mentions of `plan-waves --touches` / `--lint` — no change: not closed lists of subcommands.
- **`17-right-size`** (sibling: `16-queue-gates`) — must be named in:
  - `loomwright/scripts/test-automate-helpers.sh` — `TAH_PARTS="… 15-lane-seams 16-queue-gates"` and the `tah_run 16-queue-gates && . "$TAH_D/16-queue-gates.sh"` source-line set — extend.
- **Verdict values `small|ok|large|unknown`** — new vocabulary with no existing closed list. They are defined once in `right-size.sh`'s header and documented in helpers.md; 18a's board consumes them via `--json`.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-automate-helpers.d/17-right-size.sh` — companion-expansion leg (a companion rule lifts a 2-file item past the threshold, or adds the shared file that makes the candidate) | delete the `_pw_expand` call in right-size's count function in `loomwright/scripts/automate-helpers.d/right-size.sh` |
| `loomwright/scripts/test-automate-helpers.d/17-right-size.sh` — parked/done candidate-exclusion leg | delete the `is_not_ready` / `is_done` exclusion line in right-size's candidate filter in `loomwright/scripts/automate-helpers.d/right-size.sh` |
| `loomwright/scripts/test-automate-helpers.d/17-right-size.sh` — lost-line post-check leg (a fixture original with a line the merge drops ⇒ exit 1, nothing written) | delete the post-check call in `merge_items` in `loomwright/scripts/automate-helpers.d/right-size.sh` |
| `loomwright/scripts/test-automate-helpers.d/17-right-size.sh` — cycle refusal leg | delete the cycle check line in right-size's candidate filter / `merge_items` in `loomwright/scripts/automate-helpers.d/right-size.sh` |
| `loomwright/scripts/test-automate-helpers.d/01-config.sh` — `right_size_small=5` ⇒ 4-file item `small` | flip the config read of `right_size_small` to always return the default in `loomwright/scripts/automate-helpers.d/config.sh` |
| `loomwright/scripts/test-automate-helpers.d/13-plan-waves.sh` — `--explain` small-note leg | delete the small-note `printf` in the `# 8. --explain:` block of `loomwright/scripts/automate-helpers.d/plan-waves.sh` |
| `loomwright/scripts/test-propose-common.sh` — size-line-on-stderr leg (and rc 0, stdout empty) | delete the right-size call line after the `mv -f` in `loomwright/scripts/propose-common.sh` |
| `loomwright/scripts/test-automate-helpers.d/17-right-size.sh` — Touches-unknown reads `unknown`, never `small` (AC5) | delete the `unknown` short-circuit before the threshold comparison in the verdict function in `loomwright/scripts/automate-helpers.d/right-size.sh` |
| `loomwright/scripts/test-automate-helpers.d/17-right-size.sh` — `companions_malformed` ⇒ exit 1, empty stdout (AC8) | delete the propagation of `plan_waves --touches`' non-zero exit in `_rsz_count`'s caller in `loomwright/scripts/automate-helpers.d/right-size.sh` |
| `loomwright/scripts/test-automate-helpers.d/17-right-size.sh` — refuses an already-merged / done / operator-run original, nothing written (AC11) | delete the already-merged (`parked (merged`) refusal line in `merge_items` in `loomwright/scripts/automate-helpers.d/right-size.sh` |
| `loomwright/scripts/test-automate-helpers.d/17-right-size.sh` — all-or-nothing staging (AC11) | replace the staged-temp rename of the originals with an in-place write before the post-check in `merge_items` (reviewer-applied) |
| `loomwright/scripts/test-automate-dismissed.sh` — dismissed-drafts stdout byte-identical with the size line present (AC14) | redirect the right-size call's output in `loomwright/scripts/propose-common.sh` from stderr to stdout |
| `loomwright/scripts/test-requirement-shape.sh` — "count by hand" absent + `right-size` named in skill, PO agent and command | restore the sentence `No mechanical size check ships yet: count by hand.` in `loomwright/skills/user-story-writing/SKILL.md` |

(Mutation wording is descriptive because the protected lines do not exist at base; the reviewer applies each row per the D1 fallback. Workers SHOULD make each mutation a single deletable line.)

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | `right-size` + `merge-items` family, config reader, registration, fixtures, test part 17 | AC1–AC12, AC17 | 6 modify, 4 create | `skills/unit-testing/SKILL.md`, `skills/automate-loop/SKILL.md` (helpers.md §1.5) | LAUNCHABLE |
| 2 | `plan-waves --explain` small note (every placed item) | AC13 | 3 modify, 0 create | `skills/automate-loop/SKILL.md` | BLOCKED (by #1) |
| 3 | Size line in `pc_guarded_write` (propose + dismissed writers) | AC14 | 5 modify, 0 create | `skills/unit-testing/SKILL.md` | BLOCKED (by #1) |
| 4 | Skill / PO prompt / intake / helpers docs, budgets, inventory, changelog, evidence | AC7 (helpers.md documentation half), AC15, AC15b, AC16, AC18, AC19 | 10 modify, 2 create | `skills/user-story-writing/SKILL.md`, `skills/automate-loop/SKILL.md` | BLOCKED (by #1, #2, #3) |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/scripts/automate-helpers.d/right-size.sh"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.d/right-size.sh", name: "_rsz_count"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.d/right-size.sh", name: "right_size"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.d/right-size.sh", name: "merge_items"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.d/config.sh", name: "right_size_small"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "_ah_source right-size"}
  - {kind: "file", path: "loomwright/scripts/fixtures/automate-helpers-help/right-size.golden"}
  - {kind: "file", path: "loomwright/scripts/test-automate-helpers.d/17-right-size.sh"}
  - {kind: "file", path: "loomwright/scripts/fixtures/right-size/merge-af33.expected.md"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-helpers.sh", name: "17-right-size"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-helpers-dispatch.sh", name: "right-size"}
requires: []
lanes:
  - "loomwright/scripts/automate-helpers.d/right-size.sh"
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/automate-helpers.d/config.sh"
  - "loomwright/scripts/automate-helpers.d/intake.sh"
  - "loomwright/scripts/test-automate-helpers.d/01-config.sh"
  - "loomwright/scripts/test-automate-helpers.d/17-right-size.sh"
  - "loomwright/scripts/test-automate-helpers.sh"
  - "loomwright/scripts/test-automate-helpers-dispatch.sh"
  - "loomwright/scripts/fixtures/automate-helpers-help/right-size.golden"
  - "loomwright/scripts/fixtures/right-size/**"
external_requires:
  - "jq (already required by automate-helpers.sh)"
  - "local gitignored originals .supervisor/requirements/automate-followups/{17,25,33}-*.md and meta-sync-followups/{09,10}-*.md, copied once into the committed fixtures"

# Subtask 2
provides:
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.d/plan-waves.sh", name: "small ("}
  - {kind: "file", path: "loomwright/scripts/fixtures/automate-helpers-help/plan-waves.golden"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/automate-helpers.d/config.sh", name: "right_size_small"}
  - {from: "1", kind: "symbol", path: "loomwright/scripts/automate-helpers.d/right-size.sh", name: "_rsz_count"}
lanes:
  - "loomwright/scripts/automate-helpers.d/plan-waves.sh"
  - "loomwright/scripts/test-automate-helpers.d/13-plan-waves.sh"
  - "loomwright/scripts/fixtures/automate-helpers-help/plan-waves.golden"
external_requires: []

# Subtask 3
provides:
  - {kind: "symbol", path: "loomwright/scripts/propose-common.sh", name: "right-size"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/automate-helpers.d/right-size.sh", name: "right_size"}
lanes:
  - "loomwright/scripts/propose-common.sh"
  - "loomwright/scripts/test-propose-common.sh"
  - "loomwright/scripts/automate-dismissed.sh"
  - "loomwright/scripts/test-automate-dismissed.sh"
  - "loomwright/scripts/test-propose-from-verify.sh"
external_requires: []

# Subtask 4
provides:
  - {kind: "symbol", path: "loomwright/skills/user-story-writing/SKILL.md", name: "right-size"}
  - {kind: "symbol", path: "loomwright/agents/product-owner.md", name: "right-size"}
  - {kind: "symbol", path: "loomwright/commands/product-owner.md", name: "right-size"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/helpers.md", name: "merge-items"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/intake.md", name: "right-size"}
  # changelog.d/pa18b-right-size-check.md dropped (adjudication D, 2026-10-22): bump-version.sh folds and deletes it per AC19
  - {kind: "file", path: "docs/evidence/pa18b-right-size-check.md"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/automate-helpers.d/right-size.sh", name: "merge_items"}
  - {from: "2", kind: "file", path: "loomwright/scripts/fixtures/automate-helpers-help/plan-waves.golden"}
  - {from: "3", kind: "symbol", path: "loomwright/scripts/propose-common.sh", name: "right-size"}
lanes:
  - "loomwright/skills/user-story-writing/SKILL.md"
  - "loomwright/skills/automate-loop/intake.md"
  - "loomwright/skills/automate-loop/helpers.md"
  - "loomwright/skills/SKILLS_INDEX.md"
  - "loomwright/agents/product-owner.md"
  - "loomwright/commands/product-owner.md"
  - "loomwright/scripts/test-requirement-shape.sh"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/docs/loop-inventory/automate-loop.md"
  - "changelog.d/pa18b-right-size-check.md"
  - "docs/evidence/pa18b-right-size-check.md"
external_requires: []
```

### Subtask 1 implementation notes
- **Count:** take the `plan_waves <item> --touches --root <root>` set (the planner's own parser + one companion pass). Never re-parse `## Touches`. A directory entry counts the regular files under `<root>/<dir>` (at least 1); an entry that does not exist yet counts 1. Document this in the header and the skill.
- **Scope items:** the top-level numbered/bulleted lines under `## Scope`. **Criteria:** the bullets under `## Acceptance criteria` / `### Acceptance Criteria`, case-insensitive. **Parts:** `^## Part ` headings outside fences. Count headings at H2 only, so an H3 `### Part` inside a quoted source text (as in 18b itself) is not counted.
- **Candidate pool:** every `*.md` under `<root>/.supervisor/requirements/` (recursive). Excluded: `proposed/`; `_rs_skip_path` (`00-*`, `_*`, `README*`, `operator-run/`, top-level `*-plan.md`) — reuse that function rather than a copy; `is_done`; `is_not_ready`; run files; the item itself.
- **Eligibility and ranking (the Source text's three bases):** a candidate qualifies by ≥1 shared expanded Touches path, a place in the same `## Depends on` chain, OR the same requirement folder. Rank by shared count, then same chain, then same folder, then path. Show at most 3.
- **Count function:** one `_rsz_count <expanded-set-file> <root>` in `right-size.sh` is the single count rule, called by `right_size` and by `plan-waves --explain` (Subtask 2).
- **Cost bound:** the pool scan runs only for a `small` verdict, so `ok`, `large` and `unknown` items do no pool work.
- **Fixture sources:** they are gitignored and absent from a worker worktree. Read them from the primary checkout, `"$(git rev-parse --git-common-dir)/.."/.supervisor/requirements/…`, copy them once into `fixtures/right-size/`, and never write an absolute home path into a committed file or a test. If they are unreachable, report it in WORKER_RESULT; never invent their text.
- **Cycle rule:** refuse a candidate when a dependency path between the two items passes through a third item. A direct edge between the two collapses and is allowed.
- **Display name:** the path relative to `.supervisor/requirements/`, without `.md`.
- **`merge-items` determinism:** take `--date` (default today, UTC) so goldens stay deterministic.

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2
Subtask 1 ──→ Subtask 3
Subtask 2 ──→ Subtask 4
Subtask 3 ──→ Subtask 4
Subtask 1 ──→ Subtask 4
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none (S2 reads S1's config reader; no shared file) | YES (requires) |
| Subtask 1 | Subtask 3 | none | YES (requires) |
| Subtask 2 | Subtask 3 | none | NO |
| Subtask 4 | Subtasks 1–3 | none (S4 documents their outputs) | YES (requires) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2, Subtask 3 (parallel — zero file overlap, both only require #1)
- **Batch 3:** Subtask 4
- **Recommended workers:** 2
- **Estimated batches:** 3

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md`, `skills/automate-loop/SKILL.md` |
| 2 | `skills/automate-loop/SKILL.md` |
| 3 | `skills/unit-testing/SKILL.md` |
| 4 | `skills/user-story-writing/SKILL.md`, `skills/automate-loop/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Scope is 30 entries (~36 counting the fixture dir's files), at or past the 30-file `large` bound (Feasibility (Phase 2.5), check 4) | MEDIUM | Split into 4 subtasks (`context-bound`); the excess is hermetic fixtures, not logic. Nothing beyond the requirement's scope; any new need goes to a follow-up item, never into this PR |
| Fixture sources (af/17, /25, /33, ms/09, /10) are gitignored and absent from a worker worktree | MEDIUM | Subtask 1 reads them from the primary checkout through `git rev-parse --git-common-dir` (a repo-relative resolution, no absolute home path) and commits copies under `fixtures/right-size/`. It reconstructs af/33 as merged (amendment sections + done stamp dropped) and restamps ms/09 and ms/10 `pending`. The iq/02-shaped fixture is synthesized. Unreachable sources are reported, never invented |
| Candidate eligibility includes "same folder" (Source text's third ranking basis), so a small item in a large folder always gets candidates | LOW | Ranked last and capped at 3, shown only for a `small` verdict. This is the reading that makes the Source text's ms/09 ↔ ms/10 example reproducible; the owner can narrow it later |
| Per-write latency: every successful `pc_guarded_write` runs `right-size`, and dismissed-drafts writes one draft per finding | MEDIUM | The pool scan runs only on a `small` verdict, and one `plan_waves --touches` runs per candidate. Tests bound the case with a fixture pool. If it proves slow, the follow-up is a `--no-candidates` writer mode, not in this PR |
| Help/registration closed lists (`_AH_HELP_SEGMENTS`, dispatch-test `SEGMENTS`, `TAH_PARTS` + source lines, per-segment goldens) are missed, and `_ah_usage` / the runner self-check fail CLOSED | HIGH | Subtask 1 owns all four. Run `test-automate-helpers-dispatch.sh` and `test-automate-helpers.sh 17-right-size` before hand-back |
| The `--explain` small note changes existing X1 byte pins (their fixture items have 1–2 files) | MEDIUM | Update X1 expectations deliberately in Subtask 2, keep X2 / X2b and the `--touches` output untouched, and add a leg showing a non-small item gets no note |
| A size line on stdout would corrupt the dismissed-drafts TSV / propose counts; a failing `right-size` could flip `pc_guarded_write`'s return code | HIGH | stderr only, after the successful `mv -f`, every failure swallowed (fail-SAFE emitter, bimodal invariant). Tests assert rc, stdout and bytes are unchanged with `right-size` present, absent and failing |
| `merge-items` is the first writer in `automate-helpers.sh`'s own process, which claims READ-ONLY | MEDIUM | Writes only requirement files under the requirements tree, all-or-nothing (staged temps + post-check before any rename). The header and helpers.md state the carve-out |
| Skill / prompt token budgets (user-story-writing has 431 tokens headroom) and the history-refs ratchet | MEDIUM | Replace text rather than add. Put the S2 cost evidence in `right-size.sh`'s header + changelog fragment, not the skill. Re-measure and raise the budget rows (+ ARCHITECTURE_CONTRACTS mirror) only as needed (this item owns both files in wave 1) |
| Intake reading of the header: does the size line print on sequential runs? | LOW | Interpreted as yes (advisory line at intake in every mode, no prompt, no gate, no driver call site), per "print the size line where intake actually runs". The §14 sentence on lint stays as is |
| loop-inventory rows anchored on intake.md / helpers.md (AL-051..053, AL-182) break if their quoted text or headings are edited | MEDIUM | Add text without rewording anchored lines. If a heading is added, add its row and fix `## Counts`. Run `test-loop-inventory.sh` |
| Fixture copies of real requirement files could carry a home path (meta-sync scrub) | LOW | Checked at base: af/17, /25, /33 carry 0 home-path (`/Users/<name>/`) hits. Re-check the ms/09, ms/10 copies the same way before committing |

## Configuration
- **Workers:** 2
- **Mode:** parallel
- **Estimated batches:** 3
- **Base Branch:** main
- **Split reason:** context-bound

## Validation (from the source requirement — must pass before merge)
1. Targeted tests: `bash loomwright/scripts/test-automate-helpers.sh 17-right-size 13-plan-waves 01-config`, `test-propose-common.sh`, `test-automate-dismissed.sh`, `test-propose-from-verify.sh`, `test-requirement-shape.sh`, `test-wave-scope.sh`, `test-automate-helpers-dispatch.sh` (help goldens), `test-loop-inventory.sh`, plus `bash scripts/check-doc-currency.sh`, `bash loomwright/scripts/test-citation-drift.sh`, `bash scripts/check-token-budget.sh`, `bash scripts/check-skills-index-sync.sh`, `bash scripts/check-prompt-history-refs.sh`, `bash scripts/check-version-bump.sh`. The full `ci-local` runs on GitHub CI (owner rule 2026-10-12).
2. Running system: `right-size` on three hand-built items (2, 12, 35 Touches files) in a temp tree. The three verdict lines go in `docs/evidence/pa18b-right-size-check.md` (AC18), linked from the PR body.
3. Rollback: `git revert`.

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-22-pa18b-right-size-check.md
```

---

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/675
- **Reconciled:** lifecycle move completed by reconcile-jobs.sh, not by the completion tail
- **Evidence:** automate engine supplied merge evidence for .supervisor/requirements/parallel-automate/18b-right-size-check.md (https://github.com/vikashruhilgit/loomwright/pull/675) — the engine verified the PR merged against the forge; this reconciler stayed offline
- **Caveat:** fields the completion tail would have recorded (files changed, heal decision and iterations, red-team advisory) are NOT recoverable after the fact and are deliberately omitted rather than invented.
