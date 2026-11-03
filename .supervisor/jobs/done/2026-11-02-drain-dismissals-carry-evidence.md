# Supervisor Job: Drain dismissals carry checkable evidence

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes/automate-2026-11-02-173506/L1
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/2026-11-02-120032-drain-dismissals-carry-checkable-evidence.md
- **Base commit:** 38eb8e4627947356b62a7980de90fda6f790beb8

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash + jq driver, python draft writer, markdown docs — all present |
| 2 | Dependency Availability | GO | no new dependency |
| 3 | Architecture Fit | GO | extends the existing `--result` fail-CLOSED validation (`rh_check_findings`) and the existing optional-additive `dismissed` item shape |
| 4 | Scope vs Supervisor Capability | CAUTION | ~24 files incl. ~14 small golden-fixture edits; est. ~300 changed lines; kept single-agent (see Risk Assessment) |
| 5 | Hard Blockers | GO | none |

**Overall Verdict:** CAUTION

## Task
**Goal:** Make every finding the `/review-pr --until-mergeable` drain dismisses carry checkable evidence (a repo `path:line`, a commit sha, or a quoted span), refuse a dismissal without it, and show it in the round's marker comment, the `REVIEW_HEAL_RESULT` block and `/automate`'s dismissed-findings draft.

**Problem Statement:**
The plugin owner, deciding fix-now / follow-up / drop on dismissed findings when an `/automate` item parks, needs to confirm or overturn each dismissal in seconds because otherwise every check is a re-investigation.
Currently, the drain's validate-then-fix step requires a `file:line` only for a CONFIRMED finding; a DISMISSED one needs only a free-text one-line `reason` ("stale", "invalid"), and the draft shows that reason alone. 280 dismissals across 43 of the last 60 merged PRs were recorded this way.
Success looks like: over the next 10 drains that dismiss anything, every dismissal carries evidence, and the owner's park decisions need no re-investigation to confirm one.

**Owner decisions carried from the requirement (do not reopen):** no new verdict or outcome; PR drain only — Phase 4.5 `heal_dismissed` is out of scope; no memory of dismissals across rounds.

## Acceptance Criteria

**Happy Path:**
- [ ] AC1 — Given the drain's `validate findings` or `fallback review` report dismisses a finding, when `review-heal-next-step.sh --result` folds the round, then the stored dismissal carries a one-line `evidence` field that contains at least one of three checkable forms, as the driver's one jq `def evidence_ok:` checks them:
      - **path:line** — a token `<path>:<digits>` (optional `-<digits>` range) whose `<path>` contains a `/` or ends in `.<1–8 alphanumerics>`, and is preceded by start-of-string, whitespace, `(` or a backtick. Accepts `src/widget.sh:42`, `README.md:7`, `see loomwright/x.sh:10-12`; rejects `host:8080`, `12:15`.
      - **commit sha** — a word-bounded run of 7–40 lowercase hex characters that holds at least one digit AND at least one letter `a-f`. Accepts `fixed in 3f9a2b1`; rejects `1234567` (all digits) and `deadbee` read as a word with no digit.
      - **quoted span** — a span between two straight double quotes (`"…"`) holding at least 12 characters, at least one of which is a space (two or more words), naming text from the PR diff, PR body or brief. Accepts `"load_config checks jq's exit status"`; rejects `"ok"` and `"intentional"`.
      The driver checks form only; it does not look up the path, sha or quote. The test pins each accept and reject example above.
- [ ] AC2 — Given a dismissal with evidence, when the drain posts its `<!-- loomwright:dismissed round=<n> -->` comment and writes its `REVIEW_HEAL_RESULT`, then the comment shows the evidence on an indented line directly under that finding's unchanged `- **<finding>** — <reason> (<source>)` bullet, and the result block's `dismissed` item carries `evidence: <json-quoted string>`.
- [ ] AC3 — Given a drafted dismissed finding with evidence, when `automate-dismissed.sh dismissed-drafts` writes the owner's draft, then the draft shows `- **Evidence:** <evidence>` on the line under `- **Reason dismissed:** <reason>`.

**Edge Cases:**
- [ ] AC4 — Given a confirmed finding dismissed because its stated severity is below the fix floor, when it is recorded, then the driver itself writes its evidence as `severity <SEV> is below the fix floor <FLOOR>` (reason stays `below_fix_floor`), and it is never refused for missing evidence.
- [ ] AC5 — Given a drain result written before this change (a `dismissed` item with no `evidence`), when `/automate` drafts it, then the draft line reads `- **Evidence:** none recorded` and nothing fails (`sidecar-check` still passes such a sidecar).
- [ ] AC6 — Given a dismissal whose proof is outside the repo (an owner decision, a convention), when the validator has no checkable form to cite, then the validator's instructions (the `validate findings` / `fallback review` spawn `then:` text and `skills/review-heal/SKILL.md` §"Step U3.5 — Validate-Then-Fix") tell it to report the finding `confirmed` with `auto_fixable: false`, so it lands in `needs_human`, still blocks READY and reaches the owner.

**Error Scenarios:**
- [ ] AC7 — Given a `dismissed` item with no `evidence` (absent, empty, or multi-line), when the validator answers `--result`, then the driver exits 2 with a stderr message naming the missing evidence (`--result: a dismissed finding needs evidence …`), writes nothing (state, ledger, comments unchanged), and re-prints the same pending spawn on the next no-`--result` call so the validator answers again. The evidence check runs in `rh_check_findings` AFTER the existing `malformed` check and AFTER the validate-mode id check, as its own `rh_die2`, so every existing `r_refuse` keeps the message it pins.
- [ ] AC8 — Given evidence that matches none of the three forms (e.g. the single word `intentional`, or `"ok"`), when the validator answers `--result`, then the driver refuses it the same way as AC7.

**Validation (from the requirement — must pass before merge):**
- [ ] AC9 — `bash loomwright/scripts/test-review-heal-next-step.sh` covers AC1, AC2, AC4, AC6 (the spawn text), AC7, AC8, each with a mutation control listed in `## Pin mutations` (removing the evidence check from the driver turns the AC7/AC8 pins red).
- [ ] AC10 — `bash loomwright/scripts/test-automate-dismissed.sh` covers a draft with an evidence line (AC3) and a draft from an older result with no evidence (AC5).
- [ ] AC11 — `bash scripts/check-version-bump.sh` passes and `bash scripts/ci-local.sh --affected` is green.

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

## File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| driver | `loomwright/scripts/review-heal-next-step.sh` (1110 — `rh_check_findings` is the single authority for `--result` validation and `rh_fold`/`rh_marker`/`rh_result` the single writers of the dismissal record; the form check is one small jq `def` inside it) | — | HIGH |
| driver tests | `loomwright/scripts/test-review-heal-next-step.sh` (1084 — new `r_refuse` cases sit beside the existing `r_refuse` block, the one place report refusals are pinned; the inline `B_DISMISS` report and the `--result` drive with `"reason":"already-addressed"` gain `evidence`); golden fixtures under `loomwright/scripts/fixtures/review-heal-golden/` (~14 files): `converged-ready/{report-1.json,expected.comments,expected.result.md,expected.out}`, `fix-round-pushed/{report-3.json,expected.comments,expected.result.md,expected.out}`, `fallback-no-review-lens/{expected.comments,expected.result.md,expected.out}` (below-floor evidence + fallback spawn text), `bound-hit-escalated/expected.out`, `clean-review-not-dismissed/expected.out`, `sub-floor-converged-ready/expected.out` (validate spawn text), `fallback-red-review-check/expected.out`, `fallback-ambiguous-output/expected.out`, `fallback-once-per-run/expected.out` (fallback spawn text) | — | HIGH (MEDIUM on the exact golden set — the G leg names any missed one) |
| draft goldens | `loomwright/scripts/fixtures/automate-golden/` cases whose `tree/dot-supervisor/requirements/proposed/` holds dismissed drafts (`dismissed-no-finding-verdict-skipped`, `fix-now-became-follow-up`, `pick-pending-decisions-ask`, `dismissed-fix-now-re-drain`, `park-first-decisions-recorded`, `reconcile-closeout-merged`) — `tree/` is case INPUT copied in before the steps (`test-automate-golden.sh` header), so keep `tree/` as the pre-change state and update only the `expected.*` files `test-automate-golden.sh` / `test-automate-next-step.sh` report as changed by the rewritten draft body | — | MEDIUM (may need no change — the harnesses decide) |
| shape | `loomwright/scripts/result_nested_keys.py` (106) | — | HIGH |
| draft | `loomwright/scripts/automate-dismissed.sh` (992 — two edit sites: the `entries.append(dict(origin=origin, source=source, reason=reason, sev=sev,` call gains `evidence=` read with `one_line(...)`, and `meta(e)`, the one place a draft's per-finding metadata lines are built, gains one line) | — | HIGH |
| draft tests | `loomwright/scripts/test-automate-dismissed.sh` (1233 — new cases beside the existing `Reason dismissed` pins; the B-leg pin on the schema row text is updated in place) | — | HIGH |
| docs | `loomwright/docs/result-schemas/review-heal-next-step.md` (109); `loomwright/docs/result-schemas/review-heal-result.md` (128); `loomwright/skills/review-heal/SKILL.md` (576 — §U3.5 case 4 and §"Dismissed-findings marker comment" are the single authorities being amended; appending elsewhere would split them); `loomwright/docs/loop-inventory/review-heal.md` (421 — RH-120/RH-148 restate the item shape) | — | HIGH (loop-inventory MEDIUM) |
| release | — | `changelog.d/drain-dismissals-carry-evidence.md` | HIGH |

**New responsibilities and their one home:** evidence-form check → a jq `def evidence_ok:` inside `rh_check_findings` in the driver (the one `--result` validator; no second copy in automate-dismissed.sh, which only displays); below-floor evidence text → `rh_fold` (where `below_fix_floor` is already assigned); evidence display in drafts → `meta(e)` in `automate-dismissed.sh`; item key set → `result_nested_keys.py` (the one shared table both `sidecar-check` paths read).

> **Validator-owned surfaces:** `check-doc-currency.sh` scans `skills/` and `docs/` (no count/version claim is added, so no change expected); `check-token-budget.sh` caps `skills/review-heal` at its `.skills["review-heal"]` entry (1316 tokens of headroom at base — keep SKILL.md additions well under that, or raise the budget entry + its `ARCHITECTURE_CONTRACTS.md` mirror row in the same change); `check-prompt-history-refs.sh` baselines `skills/review-heal/SKILL.md` at 18 history refs (add none — no item ids or PR numbers in the new prose); `test-loop-inventory.sh` requires every new `###`/`####` heading in the SKILL to have an `h:` row and every `prose`-home row's `q:` anchor to stay a substring of a SKILL line.

### File Overlap Detection

Single subtask — no overlap analysis needed.

### Prior churn / blast radius
`read-postmortem.sh` returned nothing for the touched paths; `twin-graph.sh` returned empty `DEPENDS_ON`/`DEPENDED_ON_BY` for both scripts — no Blast-Radius section.

## Touched-file invariants

> Grounded at base `38eb8e4627947356b62a7980de90fda6f790beb8`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/review-heal-next-step.sh`** — keep: `--result` validation fails CLOSED with exit 2 and writes nothing — `rh_die2() { rh_err "$*"; exit 2; }` and the existing message `--result: a finding is malformed (verdict, a one-line finding, auto_fixable on confirmed, reason on dismissed, severity) — nothing written`; the new refusal is a separate `rh_die2` call whose message names evidence, so the AC7/AC8 pins can tell the two apart. Keep: the dismissed bullet line byte-identical — `"- **" + .finding + "** — " + .reason + " (" + .source + ")"` — the evidence goes on its OWN following line indented two spaces (`"  - evidence: " + .evidence`), never inside the bullet. Keep: `reason: "below_fix_floor"` for below-floor items. Keep: the result emitter's tojson quoting for untrusted text — `"    - {finding: " + (.finding | tojson)` — render `evidence` with `tojson` too, never `bare`. Reuse: the existing one-line test `(test("[\n\r]") | not)` for evidence. Mirror: the report contract the spawn `then:` text states (`"evidence": "<confirmed: file:line on the current branch>"`) — extend it to name dismissed evidence and the out-of-repo ⇒ `confirmed` + `auto_fixable: false` rule; the spawn `then:` strings appear verbatim in the golden `expected.out` files. Pinned by: `loomwright/scripts/test-review-heal-next-step.sh` (`r_refuse "a multi-line finding"` and the G leg's byte-for-byte golden compare, which also runs `automate-helpers.sh sidecar-check` on every emitted block).
- **`loomwright/scripts/result_nested_keys.py`** — keep: `DISMISSED_ITEM = (["finding", "reason", "source"], ["severity"])` is shared by `"heal_dismissed": ("list",) + DISMISSED_ITEM + ({},),` (Phase 4.5, OUT of scope) — add `evidence` to the drain's `"dismissed"` entry only (a separate item table, e.g. `DRAIN_DISMISSED_ITEM = (["finding", "reason", "source"], ["severity", "evidence"])`), never to `heal_dismissed`. `evidence` stays OPTIONAL in the table (AC5: older sidecars must still pass); the driver, not the shape check, enforces it on new reports. Fired by: `automate-trail.sh` `sidecar-check` and `validate-supervisor-result.py` (rule 15). Pinned by: `loomwright/scripts/test-result-validators.sh` (`dismissed: flow-map with a quoted ': ' inside a value parses without error`).
- **`loomwright/scripts/automate-dismissed.sh`** — keep: draft identity is content-addressed from origin/source/finding only — `h8 = hashlib.sha1("\t".join(k).encode("utf-8")).hexdigest()[:8]` — evidence must NOT feed `k`/h8 or any ledger decision (a re-drain that changes evidence rewrites an undecided draft under the same name). Reuse: `one_line(...)` for the evidence value exactly as `reason = one_line(i.get("reason")).strip() or "unspecified"`. Keep: the line `"- **Reason dismissed:** " + e["reason"]` unchanged, the new `- **Evidence:** …` line directly after it. Keep the script's write scope (header `SCOPE OF ITS WRITES (the whole list — anything else is a bug)`) unchanged. Phase 4.5 `heal_dismissed` items carry no evidence and render `none recorded` too — truthful, no Phase 4.5 change. Pinned by: `loomwright/scripts/test-automate-dismissed.sh` (`- **Reason dismissed:** stale: fixed in abc123`, and the B-leg pin `` `[{finding, reason, source, severity?}]` `` on `review-heal-result.md`, which this change updates in the same edit as the schema row).
- **`loomwright/scripts/test-review-heal-next-step.sh`** — keep: one tally (`PASS: <n> FAIL: <m>`, exit 1 on any failure) and hermetic sandboxes (`mktemp -d`, stub `gh` first on PATH — no network). Keep every existing `r_refuse` pin's expected message: `r_refuse "an unknown id" '{"findings":[{"id":"r9-9","verdict":"dismissed","finding":"x","reason":"stale"}]}' 'every candidate id'` and `r_refuse "a multi-line finding"` send dismissals WITHOUT evidence and must still get `every candidate id` / `malformed` — which is why the evidence check runs after both (AC7). Reuse: the `r_refuse` helper for AC7/AC8 and the accept/reject examples of AC1. Keep the G leg's byte-for-byte golden compare and its `sidecar-check` of every emitted block; never loosen a normalisation to make a fixture pass. Keep the S leg: no instruction contains `gh pr merge` or `--force`.
- **`loomwright/scripts/test-automate-dismissed.sh`** — keep its existing pins green: `- **Reason dismissed:** stale: fixed in abc123` (`free-text drain reason carried verbatim`) and `- **Reason dismissed:** nit` in the summary draft. Update in the same edit as the schema row: the B-leg pin `` grep -qF '`[{finding, reason, source, severity?}]`' "$RSD/review-heal-result.md" `` follows the new row text. Reuse: its existing sidecar-writing helpers to add one drain sidecar item with `evidence` (AC3) and one without (AC5).
- **`loomwright/scripts/pr-postmortem-gather.sh`** (NOT modified — consumer to keep working) — its bullet parser `capture("^- \\*\\*(?<finding>.+?)\\*\\* — (?<reason>.+?) \\((?<source>[^()]+)\\)\\s*$")` reads only lines starting `- **`; the indented evidence line is skipped by construction. Pinned by `loomwright/scripts/test-pr-postmortem-gather.sh`.
- **`loomwright/skills/review-heal/SKILL.md`** — keep: §"Dismissed-findings marker comment" states Phase 4.5 posts the SAME shape (`skills/self-heal-advisory/SKILL.md` cross-references it) — document the evidence line as drain-only and optional so Phase 4.5's comment stays valid unchanged. Keep the `q:` anchors of prose-home loop-inventory rows as substrings (RH-116 `**Validate (evidence-citing — mitigates R4, no rubber-stamping).**`, RH-120 `**Validated as stale / invalid / already-addressed → DISMISSED.**`). Pinned by: `loomwright/scripts/test-loop-inventory.sh`, `scripts/check-token-budget.sh`, `scripts/check-prompt-history-refs.sh`.

## Closed enumerations touched

> Sibling grep at base `38eb8e4`: `grep -rnF '"finding", "reason", "source"' --exclude=CHANGELOG.md .` → 1 hit; `grep -rnF 'finding, reason, source' --exclude=CHANGELOG.md loomwright` → 7 hits in 6 files.

- **`evidence`** (new optional key of a drain `dismissed` item; sibling: `severity`) — must be named in:
  - `loomwright/scripts/result_nested_keys.py` — the closed item key set, `DISMISSED_ITEM = (["finding", "reason", "source"], ["severity"])` — extend (drain entry only, see invariants).
  - `loomwright/docs/result-schemas/review-heal-result.md` — the schema line `dismissed: [{finding: string, reason: string, source: string, severity?: string}]` and the table row `` `[{finding, reason, source, severity?}]` `` and the §"Nested-object key sets" sentence `each `dismissed` item — required `finding`, `reason`, `source`, optional `severity`` — extend all three.
  - `loomwright/docs/result-schemas/review-heal-next-step.md` — the report shape `{"id", "verdict", "finding", "auto_fixable"?, "severity"?, "reason"?, "evidence"?, "fingerprint"?}` already names `evidence`; extend the prose (`dismissed` needs a one-line `reason` …) to require evidence on dismissed — extend.
  - `loomwright/skills/review-heal/SKILL.md` — §U3.5 case 4 `the itemised `{finding, reason, source}` list` — extend.
  - `loomwright/docs/loop-inventory/review-heal.md` — RH-148 outcome cell `` `{finding, reason, source}` plus `severity` `` — extend.
  - `loomwright/scripts/test-automate-dismissed.sh` — pin on the schema row text — extend with the row.
  - `loomwright/scripts/pr-postmortem-gather.sh` — `{round: $round, finding, reason, source}` — no change: it parses the marker comment, not the result block, and evidence is deliberately not carried into the postmortem record (requirement scope).
  - `loomwright/skills/self-heal-advisory/SKILL.md` — `heal_dismissed = []  # ITEMISED {finding, reason, source, severity}` — no change: Phase 4.5 is out of scope (owner decision).

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-review-heal-next-step.sh` — `r_refuse` "a dismissal with no evidence" (AC7) | delete `(.evidence | evidence_ok)` in `loomwright/scripts/review-heal-next-step.sh` |
| `loomwright/scripts/test-review-heal-next-step.sh` — `r_refuse` "evidence in none of the three forms" (`intentional`, AC8) | delete `(.evidence | evidence_ok)` in `loomwright/scripts/review-heal-next-step.sh` |
| `loomwright/scripts/test-review-heal-next-step.sh` — below-floor evidence `severity LOW is below the fix floor MEDIUM` in the fallback-no-review-lens golden (AC4) | delete `is below the fix floor` in `loomwright/scripts/review-heal-next-step.sh` |
| `loomwright/scripts/test-review-heal-next-step.sh` — marker evidence line `  - evidence: ` in golden `expected.comments` (AC2) | delete `"  - evidence: "` in `loomwright/scripts/review-heal-next-step.sh` |
| `loomwright/scripts/test-review-heal-next-step.sh` — result block `evidence:` in golden `expected.result.md` (AC2) | delete `", evidence: "` in `loomwright/scripts/review-heal-next-step.sh` |
| `loomwright/scripts/test-review-heal-next-step.sh` — G leg `sidecar-check` on a block carrying `evidence` (AC2) | flip `["severity", "evidence"]` → `["severity"]` in `loomwright/scripts/result_nested_keys.py` |
| `loomwright/scripts/test-review-heal-next-step.sh` — AC6 validate spawn text names `auto_fixable: false` for proof outside the repo | delete `proof lives outside the repo` in `loomwright/scripts/review-heal-next-step.sh` (literal only in `rh_validate`'s spawn `then:` text) |
| `loomwright/scripts/test-review-heal-next-step.sh` — AC6 fallback spawn text carries the same rule | delete `proof is outside the repo` in `loomwright/scripts/review-heal-next-step.sh` (literal only in `rh_fallback`'s spawn `then:` text — distinct from the validate literal so each row removes exactly its own copy) |
| `loomwright/scripts/test-automate-dismissed.sh` — `- **Evidence:** src/widget.sh:42` draft line (AC3) | delete `"- **Evidence:** "` in `loomwright/scripts/automate-dismissed.sh` |
| `loomwright/scripts/test-automate-dismissed.sh` — `- **Evidence:** none recorded` on an older sidecar (AC5) | flip `none recorded` → `unspecified` in `loomwright/scripts/automate-dismissed.sh` |

(The literals in the Mutation column are the ones the worker writes; if the implementation names them differently, update this table's literals to the shipped text so each row stays machine-applicable.)

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Drain dismissals carry checkable evidence (driver, shape, draft, docs, tests, fragment) | all | ~24 modify (incl. ~14 small golden-fixture edits; automate-golden expected files only if its harness reports them), 1 create | `skills/review-heal/SKILL.md`, `skills/unit-testing/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/scripts/review-heal-next-step.sh", name: "evidence_ok"}
  - {kind: "symbol", path: "loomwright/scripts/result_nested_keys.py", name: "DRAIN_DISMISSED_ITEM"}
  - {kind: "symbol", path: "loomwright/scripts/automate-dismissed.sh", name: "- **Evidence:** "}
  - {kind: "file", path: "changelog.d/drain-dismissals-carry-evidence.md"}
requires: []
lanes:
  - "loomwright/scripts/review-heal-next-step.sh"
  - "loomwright/scripts/test-review-heal-next-step.sh"
  - "loomwright/scripts/fixtures/review-heal-golden/**"
  - "loomwright/scripts/fixtures/automate-golden/**"
  - "loomwright/scripts/result_nested_keys.py"
  - "loomwright/scripts/automate-dismissed.sh"
  - "loomwright/scripts/test-automate-dismissed.sh"
  - "loomwright/docs/result-schemas/review-heal-next-step.md"
  - "loomwright/docs/result-schemas/review-heal-result.md"
  - "loomwright/skills/review-heal/SKILL.md"
  - "loomwright/docs/loop-inventory/review-heal.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "changelog.d/drain-dismissals-carry-evidence.md"
external_requires: []
```

(The fragment is listed as a provides because this is a lane PR that never bumps — the wave/release step folds it. If the Supervisor run itself runs `scripts/bump-version.sh`, replace that entry with the folded `CHANGELOG.md` headline.)

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/review-heal/SKILL.md`, `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): file count (~24) technically meets the `context-bound` predicate, but ~14 are small golden-fixture edits and the change is est. ~300 lines; splitting driver vs. draft would put the shared `evidence` key shape across two workers | MEDIUM | Kept single-agent so one worker owns the key name end to end; the G leg's byte-for-byte golden compare names any fixture missed |
| Golden fixtures pin the spawn `then:` text verbatim in five+ `expected.out` files; changing the validator instructions (AC6) churns them all | MEDIUM | Edit the `then:` strings once, then update every golden `expected.out` the G leg reports; never weaken the G leg's compare |
| Form-only check: a validator can cite a plausible but wrong `path:line` or sha — evidence is checkable by the owner, not verified by the driver | MEDIUM | Matches the requirement (checkable forms, owner confirms at the park); note in the changelog fragment. Widen, never remove, the forms if early refusals are frequent (requirement Assumption) |
| Overlap with pending items `dismissed-followups/12-bundle-04ab-drivers-and-gate-tooling.md` (drain driver) and `dismissed-followups/01-follow-up-decision-becomes-tracked-work.md` (draft writer) | MEDIUM | Not in the same `--parallel` wave; whichever lands second rebases onto the other |
| Token budget: `skills/review-heal` has 1316 tokens of headroom; history-refs baseline for its SKILL.md may only go down | LOW | Keep new SKILL prose short and free of item ids/PR numbers; if over, raise `.skills["review-heal"]` (measured + ~10%) and its `ARCHITECTURE_CONTRACTS.md` mirror row |
| Each refused report costs one extra validator answer in that round (requirement Risk) | LOW | Refusal message names exactly what is missing so one retry suffices |
| Marker-comment shape is shared with Phase 4.5 and parsed by `pr-postmortem-gather.sh` | LOW | Bullet line byte-identical; evidence on its own indented line the parser skips; document it as drain-only and optional |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-02-drain-dismissals-carry-evidence.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-11-02T14:50:00Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/801
- **Branch:** feature/drain-dismissals-carry-evidence
- **Files changed:** 27
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** armed
- **Summary:** Drain dismissals now must carry checkable evidence (path:line, commit sha or quoted span; jq `def evidence_ok:` in rh_check_findings, exit-2 refusal otherwise), shown in the dismissed marker comment, the REVIEW_HEAL_RESULT `dismissed` item and the /automate draft (`none recorded` for older results). Phase 4.5 round 1: review PASS but required CI red on test-no-pipefail-grep-q (3 branch-introduced `producer | grep -q` pipes under pipefail — ci-local --affected does not run that repo-wide scanner); fixed in 219e1ad; round 2 review PASS and CI green. Two LOW/nit findings dismissed (PR comment).

## Not verified
- **live /review-pr --until-mergeable drain on a real PR** — no live PR run; only the hermetic goldens with a stubbed gh (subtask 1)
