# Evidence — dismissed follow-ups 06c (doc, header and evidence-file drift)

Requirement: `.supervisor/requirements/dismissed-followups/06c-docs-and-evidence-drift.md` (gitignored; carried on
`loomwright-meta`). Brief: `2026-11-10-dismissed-followups-06c-docs-drift` (single subtask).

Base: `e1e0750f9f9636020f99cca29404506e85ff029a`. Re-verified 2026-11-10 on macOS (Darwin 25.6.0), from the repo
root, with `bash`. Every anchor check reads the base blob with `git show e1e0750:<path>`, so it re-runs the same
way after the fix lands. All 16 findings reproduced on the base, so none is `recorded`.

**One finding changes emitted output: F122** (`capabilities.json`'s `host_switch.effect`). It carries a regression
leg that fails on the base generator (section "F122 pin mutation" below). Every other finding is a doc, comment,
header or published-description wording change with no executed behaviour, so it gets no leg. The four AC5 files
change comment lines only (`git diff -U0` on them shows no non-`#` line). `capabilities.json` was regenerated with
`bash loomwright/scripts/build-capabilities.sh` once, after both source edits it reflects (F122 and F125), and
`bash loomwright/scripts/build-capabilities.sh --check` exits 0.

| Finding | Disposition | File (change) :: test leg |
|---|---|---|
| F108 | fixed | `loomwright/docs/result-schemas/automate-run/parallel-lanes.md` (§"Lane inbox answer file": `answers` row reads `{"<question text>": "<label[,label…]>", …}`, keyed by question text, the index-keyed `lane-answer` input re-keyed by `_lanes_validate_answers`; policy `note` cell reads `` `null` ``, as `relay.sh`'s policy writer stores) — doc-only, no leg |
| F112 | fixed | `loomwright/scripts/test-read-rules.sh` ((j2) comment: "the store's repo-wide rule (applies_to: null in .agent/rules/process.json)") — comment-only, no leg |
| F123 | fixed | `loomwright/docs/CAPABILITIES_CONTRACT.md` (Row key bullet: a glob of `*` and `?` only, any other character including `[…]` literal, an unmatched basename fails safe to `unknown`) and `loomwright/scripts/build-capabilities.sh` (the row-key comment says the same) — doc/comment-only, no leg. `HOOKS.md` does not restate the glob rule (no `shell glob` at base), so it is unchanged |
| F296 | fixed | `scripts/check-doc-currency.sh` (header: all three mirror tables, per-agent, "Skill size ceilings" and "Command size ceilings", are synced by `scripts/check-token-budget.sh`) — comment-only, no leg |
| F309 | fixed | `loomwright/scripts/guard-lane-wait-armed.sh` (header item 5 and the lane-states comment place `_LANES_WAIT_LIVE` / `_lanes_quick_state` in `automate-lanes.d/status.sh`, sourced through `automate-lanes.sh`; `LANES_SH` and the sourcing unchanged) — comment-only, no leg. The restated copy in `loomwright/docs/HOOKS.md`'s lane-wait `Stop` row (found by the post-fix sweep `git grep -nF "automate-lanes.sh's \`_LANES_WAIT_LIVE\`"`) is corrected in the same change |
| F321 | fixed | `loomwright/skills/automate-loop/lanes.md` (the `wave-build` paragraph runs the local CI and the release step "when the project has `scripts/ci-local.sh` / `scripts/bump-version.sh` (otherwise that step is skipped and its line says so)"; step 9's parenthesis reads "it runs the local CI, when `scripts/ci-local.sh` is present") — doc-only, no leg |
| F324 | fixed | `loomwright/docs/PITFALLS.md` (lane-park entry: `lane-answer <lane_dir> --deliver-pending --owner-command '<cmd>'`) — doc-only, no leg |
| F337 | fixed | `loomwright/docs/TELEMETRY.md` (Issue body template `## Raw Data` example: `"score": 9`, `"score_float": 9.0`, `"score_bucket": "high"`; the `status` placeholder kept) — doc-only, no leg |
| F117 | fixed | `loomwright/docs/RULES_BASELINE.md` (post-rules row, ledger-pin bullet: ledger line 85, `pr_url` #160 as read from the pinned ledger, is counted by neither row) — doc-only, no leg |
| F122 | fixed | `loomwright/scripts/build-capabilities.sh` (`HOST_EFFECT` names the gate/redirects-class destination and says a skips-class hook never writes) and `loomwright/capabilities.json` (regenerated) :: `loomwright/scripts/test-build-capabilities.sh` leg `(HM) host_switch.effect names both HOOKS.md host-mode class words: redirects and skips` |
| F130 | fixed | `loomwright/docs/CORE_CONTRACT.md` (§4: the resolver is the "one place the core reads the harness's install-root variable"; the adapter-classed exceptions in "Honest state" unchanged) — doc-only, no leg |
| F276 | fixed | `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (§"Prompt Token Budgets": bold paragraph drops the `EXCEPT the ¹-marked rows above (…)` clause and its row list, now "never enforced values (¹ only marks a row whose `measured` was re-measured live)"; footnote ¹'s pointer to the bold paragraph replaced by "every row is marked"; its three "The `measured` cell/field above reflects/now reflects" sentences for retired figures put in the past tense). No budget or measured cell touched — doc-only, no leg |
| F361 | fixed | `loomwright/scripts/automate-lanes.d/status-read.sh` (`_lanes_render_terse` comment: "the renderer body of lane-status's default view (status.sh appends the backlog pointer line)") — comment-only, no leg |
| F041 | fixed | `loomwright/docs/result-schemas/schema-versioning.md` (2026-10-05 entry: `current-rebuild` repairs an unset or stale-`done` `## Current` at RESUME; the entry stays a dated log) — doc-only, no leg |
| F073 | fixed | `loomwright/docs/HOOKS.md` (§"Hook Table": new paragraph after the preamble — a new or changed leaf's script writes need a row in `build-capabilities.sh`'s writes audit table, then `capabilities.json` regenerated; no row publishes `writes: ["unknown"]`) — doc-only, no leg |
| F125 | fixed | "each evidenced review round" in `loomwright/commands/pr-postmortem.md` (frontmatter `description` and the intro's "buckets each …"), `loomwright/skills/pr-postmortem/SKILL.md` (frontmatter `description`), `loomwright/docs/command-parts/agent-help/ops.md` (`/pr-postmortem` Purpose), `loomwright/docs/result-schemas/postmortem-result.md` (opening sentence), and `loomwright/capabilities.json` (regenerated `/pr-postmortem` description, equal to the command frontmatter's). The `### Step 3 — Categorize each review round` heading is kept on purpose; its body already says "that has concrete evidence". Description only, no leg |

## Re-verify on the base

### F108

```
$ git show e1e0750:loomwright/docs/result-schemas/automate-run/parallel-lanes.md | grep -nF -- '| `answers` | `{"0": "<label>"' | cut -c1-140
21:| `answers` | `{"0": "<label>", …}` — the question's own option labels | same |
```

### F108

```
$ git show e1e0750:loomwright/docs/result-schemas/automate-run/parallel-lanes.md | grep -nF -- 'none — a policy carries no note' | cut -c1-140
22:| `note` | the owner's optional note, or `null` | none — a policy carries no note |
```

### F112

```
$ git show e1e0750:loomwright/scripts/test-read-rules.sh | grep -nF -- 'no-regression guard for the one rule the plugin' | cut -c1-140
622:# no-regression guard for the one rule the plugin's own store ships (.agent/rules/process.json).
```

### F123

```
$ git show e1e0750:loomwright/docs/CAPABILITIES_CONTRACT.md | grep -nF -- 'matched as a shell glob' | cut -c1-140
103:- **Row key:** a row whose first cell starts with `StopFailure inline leaf` is the inline-leaf row; the row whose first cell is `` `Task
```

### F123

```
$ git show e1e0750:loomwright/scripts/build-capabilities.sh | grep -nF -- 'a script file name or a shell glob' | cut -c1-140
423:# row is keyed by the FIRST backticked token of its first cell — a script file name or a shell glob
```

### F296

```
$ git show e1e0750:scripts/check-doc-currency.sh | grep -nF -- 'per-agent mirror table' | cut -c1-140
25:# ARCHITECTURE_CONTRACTS.md §"Prompt Token Budgets" per-agent mirror table's budget
```

### F309

```
$ git show e1e0750:loomwright/scripts/guard-lane-wait-armed.sh | grep -nF -- 'quick state is in automate-lanes.sh' | cut -c1-140
26:#   5. some lane is LIVE (its quick state is in automate-lanes.sh's `_LANES_WAIT_LIVE` — the very set
```

### F309

```
$ git show e1e0750:loomwright/scripts/guard-lane-wait-armed.sh | grep -nF -- 'The lane states come from `_lanes_quick_state` (automate-lanes.sh, sourced)' | cut -c1-140
41:# The lane states come from `_lanes_quick_state` (automate-lanes.sh, sourced): the lane table, lane
```

### F321

```
$ git show e1e0750:loomwright/skills/automate-loop/lanes.md | grep -nF -- 'runs the local CI' | cut -c1-140
24:9. **Build the wave** — once every wave lane is converted (`awaiting_merge`, after `lane-convert-ready`, "Terminal park" below), run `w
74:**`wave-build <parent_runfile> [--wave-branch <name>]` — the one writer of a wave branch.** In a temporary worktree off a fresh `origin
```

### F324

```
$ git show e1e0750:loomwright/docs/PITFALLS.md | grep -nF -- 'lane-answer <lane_dir> --deliver-pending`.' | cut -c1-140
75:A lane answers its own question only when a policy answer (a human-stamped project policy or the owner-set wave policy, `docs/LANE_GATES.
```

### F337

```
$ git show e1e0750:loomwright/docs/TELEMETRY.md | grep -nF -- '"score": 7,' | cut -c1-140
1440:  "score": 7,
```

### F337

```
$ git show e1e0750:loomwright/docs/TELEMETRY.md | grep -nF -- '"score_bucket": "medium",' | cut -c1-140
1442:  "score_bucket": "medium",
```

### F117

```
$ git show e1e0750:loomwright/docs/RULES_BASELINE.md | grep -nF -- 'Line 85 is the last line of the ledger' | cut -c1-140
173:  lines **86–158**. Line 85 is the last line of the ledger at `3f4bb2e`, the commit that landed
```

### F122

```
$ git show e1e0750:loomwright/scripts/build-capabilities.sh | grep -nF -- 'hook state goes to the state_dir_env directory when it is valid' | cut -c1-140
417:HOST_EFFECT="Host mode is on only when env is exactly 1; then no hook writes the session's working tree: hook state goes to the state_di
```

### F130

```
$ git show e1e0750:loomwright/docs/CORE_CONTRACT.md | grep -nF -- 'install-root variable is read' | cut -c1-140
216:`loomwright/scripts/resolve-loomwright-root.sh` is the **one place the harness's install-root variable is read**. It
```

### F276

```
$ git show e1e0750:loomwright/docs/ARCHITECTURE_CONTRACTS.md | grep -nF -- 'EXCEPT the ¹-marked rows above' | cut -c1-140
702:**`measured` and the "Preloaded skills" column are snapshot metadata, not enforced values, EXCEPT the ¹-marked rows above** (`code-revi
```

### F276

```
$ git show e1e0750:loomwright/docs/ARCHITECTURE_CONTRACTS.md | grep -nF -- 'authoritative enumeration of the marked set' | cut -c1-140
620:¹ **Marks a LIVE re-measure, not the frozen v15.10.0 baseline.** Every ¹-marked cell in the table above carries a figure re-measured a
```

### F361

```
$ git show e1e0750:loomwright/scripts/automate-lanes.d/status-read.sh | grep -nF -- 'default view: the header line' | cut -c1-140
686:# _lanes_render_terse <status JSON> — lane-status's default view: the header line, then each lane's first
```

### F041

```
$ git show e1e0750:loomwright/docs/result-schemas/schema-versioning.md | grep -nF -- '`current-rebuild` repairs one at RESUME' | cut -c1-140
20:- **AUTOMATE_RUN additive `closeout_leftover` value; `## Current` written only by `current-set`** (2026-10-05, `.supervisor/requirements/
```

### F073

```
$ git show e1e0750:loomwright/docs/HOOKS.md | grep -nF -- 'build-capabilities' | cut -c1-140
114:- **The capabilities contract reads the off-mode branch of the StopFailure leaf.** `build-capabilities.sh` parses that inline leaf as if
```

### F125

```
$ git show e1e0750:loomwright/commands/pr-postmortem.md | grep -nF -- 'categorize each review round' | cut -c1-140
2:description: Read-only post-hoc analysis of an existing PR — categorize each review round into one of 6 root-cause classes, attribute it
```

### F125

```
$ git show e1e0750:loomwright/commands/pr-postmortem.md | grep -nF -- 'buckets each review round' | cut -c1-140
11:After an agent-generated PR has absorbed several rounds of post-PR review-and-fix, `/pr-postmortem` asks **"why did this PR need back-and
```

### F125

```
$ git show e1e0750:loomwright/skills/pr-postmortem/SKILL.md | grep -nF -- 'categorizes each review round' | cut -c1-140
3:description: Inline, READ-ONLY post-hoc analysis protocol for `/pr-postmortem <pr-url>` — gathers an existing PR's review/churn signals 
```

### F125

```
$ git show e1e0750:loomwright/docs/command-parts/agent-help/ops.md | grep -nF -- 'buckets each review round' | cut -c1-140
23:**Purpose:** On-demand, read-only diagnostic that analyzes a merged or open PR's review-and-fix churn to find the **root cause** of repea
```

### F125

```
$ git show e1e0750:loomwright/docs/result-schemas/postmortem-result.md | grep -nF -- 'buckets each review round' | cut -c1-140
6:`scripts/pr-postmortem-gather.sh`), buckets each review round into a reproducible root-cause class, and
```

### F117 — the PR on ledger line 85

```
$ git show 1df5d34:.supervisor/postmortem/results.jsonl | sed -n 85p | jq -c '{pr_url, ts}'
{"pr_url":"https://github.com/vikashruhilgit/loomwright/pull/160","ts":"2026-08-31T03:44:07Z"}
$ git show 1df5d34:.supervisor/postmortem/results.jsonl | wc -l
     158
```

Line 85 is #160, as the finding said. The row's sentence names it from `pr_url` (the record's `number` field is
not set).

### F125 — after the fix

```
$ git grep -niE "(categorizes?|buckets) each review round" -- loomwright/ ':!loomwright/CHANGELOG.md'
loomwright/skills/pr-postmortem/SKILL.md:93:### Step 3 — Categorize each review round
```

The one hit is the heading the brief keeps. `capabilities.json`'s `/pr-postmortem` description was diffed against
the command frontmatter's `description:` value: equal.

## F122 pin mutation

The base string names neither class word (`skipped` is not `skips`). The mutation restores the base generator in a
scratch plugin root and builds from it. The scratch root is a copy of the fixed tree's `.claude-plugin`, `agents`,
`commands`, `skills`, `hooks`, `docs`, `scripts` and `capabilities.json`, with
`git show e1e0750:loomwright/scripts/build-capabilities.sh` written over `scripts/build-capabilities.sh`.

```
$ M=<scratch>/pin-mut
$ bash $M/plugin/scripts/build-capabilities.sh --out $M/base.json          # rc 0
$ bash loomwright/scripts/build-capabilities.sh --out $M/fixed.json        # rc 0
# the leg's jq test, on each output:
#   jq -r '.host_switch.effect | test("\\bredirects\\b") and test("\\bskips\\b")' <file>
--- base:
FAIL (HM) host_switch.effect does not name both class words redirects and skips: Host mode is on only when env is exactly 1; then no hook writes the session's working tree: hook state goes to the state_dir_env directory when it is valid, otherwise gate state goes to a per-user temp root and every other hook write is skipped.
--- fixed:
ok   (HM) host_switch.effect names both HOOKS.md host-mode class words: redirects and skips
```

The real suite file, copied into the same scratch root (so it runs the base generator), goes red on the leg:

```
$ bash $M/plugin/scripts/test-build-capabilities.sh            # rc 1
FAIL (C) committed capabilities.json is stale: capabilities.json is stale — run: bash loomwright/scripts/build-capabilities.sh and commit
FAIL (HM) host_switch.effect does not name both class words redirects and skips: Host mode is on only when env is exactly 1; …
FAIL (M) baseline fixture already fails --check — the control would prove nothing
test-build-capabilities: 108 passed, 3 failed
```

`(C)` and `(M)` fail there only because the scratch root's committed `capabilities.json` already carries the fixed
string. The `(HM)` effect leg is the one this finding adds. On the fixed tree:

```
$ bash loomwright/scripts/test-build-capabilities.sh            # rc 0
ok   (HM) host_switch.effect names both HOOKS.md host-mode class words: redirects and skips
test-build-capabilities: 111 passed, 0 failed
$ bash loomwright/scripts/build-capabilities.sh --check; echo rc=$?
rc=0
```

## Validation on the fixed tree

- `bash scripts/ci-local.sh --affected`: 18 early-set entries (every static CI gate, including
  `check-doc-currency.sh`, `check-token-budget.sh`, `check-prompt-history-refs.sh`, `build-capabilities.sh` and
  `check-version-bump.sh`) plus the 4 mapped suites (`test-build-capabilities.sh`, `test-guard-lane-wait-armed.sh`,
  `test-read-rules.sh`, `test-citation-drift.sh`); all 22 passed.
- `--affected` maps most of the changed docs to no suite, so every suite that reads one of those files was run
  directly, and all exited 0: `test-automate-golden`, `test-automate-lanes` (which runs the `01-create-to-wait.sh`
  part), `test-automate-lanes-modules`, `test-automate-next-step`, `test-brief-conformance-seam`,
  `test-close-stranded-run`, `test-command-parts`, `test-curation-status`, `test-gen-color-legend`,
  `test-guard-test-integrity`, `test-hook-payload-contract`, `test-host-mode`,
  `test-measure-heal-signal-distribution`, `test-non-interactive-gates-seam`, `test-pr-postmortem-gather`,
  `test-progress-state`, `test-result-schemas-split`, `test-retention-sweep`, `test-review-heal-next-step`,
  `test-rule-conformance-seam`, `test-script-event-telemetry`, `test-send-telemetry-core`,
  `test-suite-helpers-defined`, `test-telemetry`, `test-validate-entry`, `test-worktree-audit` and
  `scripts/test-check-vendor-coupling.sh`.
- `bash scripts/check-version-bump.sh`: not bumped, 1 fragment pending (legal).
