# as13 — Launch Pad and /autonomous carry rules, not stories: evidence

Requirement: `.supervisor/requirements/automate-speed/13-diet-launch-pad-autonomous.md`. Base commit: `142540b8210a4b206e87e2b4349999c9978f8e29`. Every number below was measured on the branch's worktree after the change (worker run, 2026-10-16), from the repo root unless a `cd` is shown.

## AC2 — runtime read set (`wc -c`)

The four runtime files `/automate` reads inline on every item. Before, at the base commit (`git show 142540b:<path>` into a scratch dir, then `wc -c`):

```
   94385 agents/launch-pad.md
   30217 commands/launch-pad.md
  102429 skills/autonomous-loop/SKILL.md
   43079 commands/autonomous.md
  270110 total
```

After (`cd loomwright && wc -c agents/launch-pad.md commands/launch-pad.md skills/autonomous-loop/SKILL.md commands/autonomous.md`):

```
   78706 agents/launch-pad.md
   19802 commands/launch-pad.md
   44435 skills/autonomous-loop/SKILL.md
   15614 commands/autonomous.md
  158557 total
```

158,557 ≤ 189,077: the single-iteration read set is 41.3% smaller.

All-modes total — the four files plus `skills/autonomous-loop/multi-iteration.md`, which Step 0 reads only when the run is not `--single-iteration`:

```
   78706 agents/launch-pad.md
   19802 commands/launch-pad.md
   44435 skills/autonomous-loop/SKILL.md
   29153 skills/autonomous-loop/multi-iteration.md
   15614 commands/autonomous.md
  187710 total
```

187,710 bytes: a multi-iteration run reads 30.5% less than before. The `.skills["autonomous-loop"]` ceiling counts both skill files (18,396 of 28,168 proxy tokens); ceilings were not lowered here (item 18 does that).

## AC3 — history references

Command (the requirement's regex, over the four runtime files):

```bash
cd loomwright
cat agents/launch-pad.md commands/launch-pad.md skills/autonomous-loop/SKILL.md commands/autonomous.md \
  | grep -oE '#[0-9]{2,4}\b|queue/[0-9]+|20[0-9]{2}-[0-9]{2}-[0-9]{2}|item [0-9]+' | wc -l
```

- Before (base commit): **34**
- After: **5** — `agents/launch-pad.md` 4 (example dates in Phase 3/7 templates, untouched by this subtask), `skills/autonomous-loop/SKILL.md` 1 (its `lastUpdated:` frontmatter date). `multi-iteration.md` adds 0.

Information only (not in AC3's regex): `v<major>.<minor>[.<patch>]` version tags in the four files went from 59 to 6. The 6 left are emitted text or a field value — the INIT migration hint and the deprecation / conflicting-flag messages (which print `v14.0.0` / `v13`), the `_v1_note` string written into every `state.json`, and the `SUPERVISOR_RESULT schema (v12.2)` contract line — and were kept verbatim on purpose: changing them changes what the loop prints or writes.

## AC1 — story and rule rows by home

Command (counts every `story` and `rule` row of the group by home, the rationale anchor stripped):

```bash
AWKC='/^\| LP-[0-9]+ \|/ { n = split($0, c, " \\| "); k = c[6]; h = c[7]; sub(/#.*/, "", h); if (k == "story" || k == "rule") print k "\t" h }'
git show 142540b:loomwright/docs/loop-inventory/launch-pad-autonomous.md | awk "$AWKC" | sort | uniq -c   # before
awk "$AWKC" loomwright/docs/loop-inventory/launch-pad-autonomous.md | sort | uniq -c                     # after
```

Before:

```
 119 rule	prose
  25 story	prose
```

After:

```
  56 rule	global
   1 rule	rationale:docs/rationale/launch-pad-autonomous.md
   1 rule	script:validate-launch-pad-result.py
  64 rule	step-scoped
  25 story	rationale:docs/rationale/launch-pad-autonomous.md
```

No `story` and no `rule` row has home `prose`. The one `rule` row with a `rationale:` home is LP-507 (the command doc's restated brief-save-detection rule), split per Part B: its rule part is LP-332 / LP-346 in `SKILL.md` PLAN step 4. The rule-row total grew from 119 to 122: LP-531 (split from story LP-406 — keep branch names in memory, the `jq` reads are illustrative) and the two load-by-mode rows LP-532 / LP-533.

**Step-scoped rows, verified by hand** (the checker does not anchor-check `step-scoped`). Every one of the 64 `step-scoped` rows' anchors resolves in its file — `h:` equals a line, `q:` is a substring of a line — by a one-off reader over the inventory (`awk` the `step-scoped` rows, then `grep -F` / exact-line match each anchor in its file): 64 `ok`, 0 missing.

- `agents/launch-pad.md`: LP-034 LP-057 LP-061 LP-065 LP-068 LP-070 LP-072 LP-083 LP-085 LP-089 LP-091 LP-092 LP-093 LP-095 LP-101 LP-108 LP-118 LP-119 LP-124 LP-137 LP-151 LP-166 LP-173 LP-174 LP-194 LP-195 LP-196 LP-197 LP-198 LP-199
- `commands/launch-pad.md`: LP-246 LP-260 LP-265 LP-284 LP-285
- `skills/autonomous-loop/SKILL.md`: LP-311 LP-314 LP-317 LP-346 LP-364 LP-365 LP-366 LP-367 LP-442 LP-445 LP-446 LP-447
- `skills/autonomous-loop/multi-iteration.md`: LP-350 LP-357 LP-385 LP-387 LP-390 LP-395 LP-396 LP-403 LP-404 LP-408 LP-413 LP-414 LP-419 LP-438 LP-439 LP-498 LP-531

## AC6 / AC8 — load by mode

- Step 0 of `skills/autonomous-loop/SKILL.md` and of `commands/autonomous.md` reads `commands/launch-pad.md`, `commands/supervisor.md` and `skills/autonomous-loop/SKILL.md`, and reads `skills/autonomous-loop/multi-iteration.md` only when the arguments do not include `--single-iteration`.
- Moved to `multi-iteration.md`: PLAN step 2's conditional auto-authoring directive, "Never under `--non-interactive-fallback`", the degenerate-rubric fallback and PLAN step 7 (persist + freeze); EXECUTE's `--base-branch` passthrough and the `review_heal` field; stacked-branch mechanics; and the whole EVALUATE body (PR-base verification, the chained review-heal step, Signal 1, Signal 2, the no-rubric gate, default termination, the Phase 1.5 pre-flight termination, the max-iterations cap). The single-iteration short-circuit stays in `SKILL.md`.
- Every moved `###` section keeps its heading in `SKILL.md` with a one-line pointer (PLAN step 2 / step 7 and EXECUTE step 1 keep their step numbers with pointers), so `§"EVALUATE PR-base verification (AC-3 + AC-15)"`, `§"EVALUATE review-heal step"`, `§"Signal 1"`, `§"No-rubric gate"`, "EVALUATE termination table" and "PLAN steps 2 and 7" citations in `docs/ARCHITECTURE_CONTRACTS.md`, `docs/result-schemas/autonomous-run.md` and `docs/TELEMETRY.md` still resolve. Two heading texts lost a version tag (`No-rubric gate (…)`, `Phase 1.5 pre-flight gate — …`); every citation of them uses the unversioned prefix.
- `test-loop-inventory.sh`'s `launch-pad-autonomous)` arm and the inventory's `## Sources` both list `skills/autonomous-loop/multi-iteration.md`; its ten `###` headings are the `h:` anchors of LP-521 … LP-530.

## AC9 — pinned can't-ask statuses

`test-non-interactive-gates-seam.sh` now also reads `multi-iteration.md` (`AL_MULTI`): `pr_base_verify_skipped_non_interactive` moved there with its gate (the `SKILL.md` read of it moved, not deleted), the three other moved gates' statuses are asserted there as new checks, the five statuses `SKILL.md` still names are still asserted on `SKILL.md`, and the (r) rubric leg reads `## PLAN — multi-iteration additions` in `multi-iteration.md`. Both repoints are load-bearing — run on a scratch copy of the plugin:

```
# "**Never under `--non-interactive-fallback`:**" line deleted from multi-iteration.md
  FAIL: (r) autonomous-loop PLAN step 2/7 do not gate rubric auto-authoring off under --non-interactive-fallback
RESULT: 63 passed, 1 failed
# every pr_base_verify_skipped_non_interactive line deleted from multi-iteration.md
  FAIL: (g) skills/autonomous-loop/multi-iteration.md does not name its can't-ask status `pr_base_verify_skipped_non_interactive` (…)
RESULT: 63 passed, 1 failed
```

The bimodal fail-closed/fail-safe rule, the named can't-ask branches and the `--non-interactive-fallback` forwards stay in the runtime prompts (INIT step 0, PLAN step 1, EXECUTE step 1, and each gate's section).

## Validation 1 — AC12 gates

Each run individually from the worktree root:

| Gate | Result |
|---|---|
| `bash loomwright/scripts/test-loop-inventory.sh` | `RESULT: 43/43 passed` (`loop-inventory: OK — 2195 rows across 4 groups`) |
| `bash scripts/check-doc-currency.sh` | exit 0 — `✓ doc-currency: all checked version/count claims match the authoritative source.` |
| `bash loomwright/scripts/test-citation-drift.sh` | `citation-drift: 26 passed, 0 failed` |
| `bash scripts/check-token-budget.sh` | exit 0 — `check-token-budget: OK — every agent, skill dir and command doc within its declared prompt-inventory budget.` |
| `bash loomwright/scripts/test-non-interactive-gates-seam.sh` | `RESULT: 64 passed, 0 failed` |
| `bash loomwright/scripts/test-rule-conformance-seam.sh` | `146 passed, 0 failed` |
| `bash loomwright/scripts/test-pr-body-evidence-seam.sh` | `77 passed, 0 failed` |
| `bash loomwright/scripts/test-closed-enum-pins-seam.sh` | `79 passed, 0 failed` |
| `bash loomwright/scripts/test-run-lock.sh` | `RESULT: 82 passed, 0 failed` (`autonomous-loop SKILL INIT: all 1 acquire line(s) … carry --session-id`) |
| `bash loomwright/scripts/test-agent-memory-permission.sh` | `agent-memory-permission: 12 passed, 0 failed` |
| `bash loomwright/scripts/test-build-capabilities.sh` | `test-build-capabilities: 110 passed, 0 failed` |
| `bash loomwright/scripts/test-verify-provides.sh` | `RESULT: 163 passed, 0 failed` |

Also run: `bash scripts/check-version-bump.sh` (exit 0 — not bumped, fragments pending, legal), `bash scripts/check-skills-index-sync.sh` (green), `bash scripts/check-vendor-coupling.sh` (exit 0 — see below).

Vendor-coupling: the subtask-2 rationale doc carried one install-root token over its zero allowance (a BREACH on the inherited tree); it is reworded away. `skills/autonomous-loop/multi-iteration.md` is a new path carrying 13 references moved out of `SKILL.md` (which went from 51 to 29 measured), so `loomwright/docs/vendor-coupling-manifest.json` gains its allowance (13) with a reason; the skill's total fell from 51 to 42.

## Validation 2 — mutation control on a real `global` row

Row LP-362 (`skills/autonomous-loop/SKILL.md`, `q: **Auto-forwarded flags (the complete `/supervisor` forward set):**`, home `global`). On a `mktemp -d` scratch copy of the repo (`loomwright/` + `scripts/`, `HOME` relocated), the anchored line was deleted from the copy of `SKILL.md` (mutant 434 lines vs 435, differs), then `bash loomwright/scripts/test-loop-inventory.sh --root <scratch>/loomwright`:

```
rc=1
FAIL LP-362: anchor not found in skills/autonomous-loop/SKILL.md
loop-inventory: FAIL — 1 problem(s)
```

Control — the same scratch copy with the original `SKILL.md` restored: `loop-inventory: OK — 2195 rows across 4 groups`.

## Behaviour questions

Recorded, not fixed (AC10 — move-only change).

1. *(from subtask 2)* `commands/launch-pad.md`'s inline workflow omits MATERIALIZE, Phase 5.5 actions 1b/1c and the Phase 7 emission, relying on pointers to `agents/launch-pad.md`. Is a pointer enough for the inline path, or should the command carry those steps?
2. *(from subtask 2)* `agents/launch-pad.md`'s Flags table has no `--fix-floor` row, though Phase 5.5 action 1c reads it.
3. Single-iteration short-circuit: EVALUATE's first step emits `status: done, status_reason: null` for every single-iteration run, while the default-termination table (`failed` → `failed`, `checkpoint` → `aborted`, `preflight_overlap_detected` → `failed`) sits in the multi-iteration body. Read literally, a single-iteration run whose Supervisor returned `failed` or `checkpoint` reports `done` (only EXECUTE step 5's no-result fallback reports `failed`). Should the single-iteration path map `SUPERVISOR_RESULT.status` through the same table?
4. Signal 1's webhook POST is conditioned "when `--notify` AND `$LOOMWRIGHT_WEBHOOK_URL` are set", while Quick Rules say `send-webhook.sh` resolves the URL itself (env var or the user-scope egress entry) and the call site does not check, and the no-rubric gate's POST says only "when `--notify` set". A run configured only through the egress file would, read literally, skip the rubric-gate POST. Kept verbatim.
5. The Failure Modes row for `rubric_dropped_from_brief` recommends "re-run without `--allow-multi-iteration` (single-iteration ignores the rubric-preservation gate entirely)", but `--allow-multi-iteration` is a no-op now (multi-iteration is the default) and PLAN step 6 is not mode-gated: it fires in single-iteration mode whenever the requirement carried a rubric. Kept verbatim.
6. The `ls`-diff fallback's pre-snapshot stale-session-id check asks the user (abort / move / force) and names no can't-ask branch, so under `--non-interactive-fallback` it would ask. Already gap-listed (LP-342).

## Pointers repointed in Phase 4.5 (fix iteration 1)

Two pointers outside the four runtime files went stale when this branch moved content; both were repointed in the Phase 4.5 fix commit `6863a0f` ("fix: address review feedback (iteration 1)"). Neither file is in the AC2 read set, so no measured number above changes.

- `skills/supervisor-readiness/SKILL.md` §"Decomposition Threshold" said the `genuine-parallelism` bounds are restated in "`agents/launch-pad.md`'s worked example"; subtask 2 moved that worked example, so the pointer now names `docs/rationale/launch-pad-autonomous.md` §"Complete worked example brief".
- `commands/agent-help.md`'s `/autonomous` "Learn More" line sent readers to `commands/autonomous.md` for the signal-extraction algorithm, refined-requirement templates and troubleshooting, which this branch moved out of it; it now names `commands/autonomous.md` §"Flow Diagram", `skills/autonomous-loop/multi-iteration.md` §"Signal 1" / §"Signal 2", and `docs/rationale/launch-pad-autonomous.md` §"/autonomous — usage notes".

## Proposed hooks

None filed under `.supervisor/requirements/proposed/`: every rule row got an existing home (`global`, `step-scoped`, `script:`), so no rule was left in prose waiting on a new hook. Candidates a later item could consider, all currently `global` / `step-scoped` prose:

- LP-101 — the Launch Pad home-path rule (an absolute home path in a brief); a hook could reject it at brief save.
- LP-202 — Launch Pad's agent-memory no-write contract ("Bash is not restricted by the harness"); a `PreToolUse` guard could enforce it.
- LP-368 — "the autonomous loop never touches the job lifecycle"; a guard could refuse `mv` into `.supervisor/jobs/*/` outside Supervisor.
- LP-293 — "never construct gate-event JSON inline"; only `send-webhook.sh`'s own jq-only construction enforces the inside of that boundary.

## Not run — Validation 3

Validation 3 (one real item that exercises this group after the change, with the phase's result block pasted) is a running-system step, and it is a **pre-merge owner step outside this job**. This job does not run it and does not fabricate its result block. Before merge, the owner either:

- runs one live item on the changed prompts (for example `/automate` on a one-item queue, which drives `/autonomous --single-iteration` through Launch Pad and Supervisor) and pastes that phase's fenced result block (`LAUNCH_PAD_RESULT` / `AUTONOMOUS_RUN`) into the PR body; or
- waives Validation 3 through the human-only `AUT-WAIVE` ask that `/automate`'s `validation-gate` raises.

Until one of the two happens the gap stays visible and the gate fails closed.
