# Evidence — dismissed follow-ups 06a, `docs` group (Subtask 2)

Requirement: `.supervisor/requirements/dismissed-followups/06a-docs-and-evidence-drift.md` (gitignored; carried on
`loomwright-meta`). Sibling file for the `scripts` group: `docs/evidence/dismissed-followups-06a-scripts.md`.

Base: `8100319b23d9371f620233e51f86feac286b15a7` (`git rev-parse HEAD` in this subtask's worktree, before any edit).
Re-verified 2026-11-10 on macOS (Darwin 25.6.0), from the worktree root. Commands run with `bash` unless noted.

**Every finding below is `doc-only`.** Each edit is prose, a tree label, a frozen figure in a budget entry and
its mirror row, or a note added to a frozen evidence file. None of them changes executed behaviour, so no
`test-*.sh` leg is added (AC2). The one figure a gate reads, `.commands.janitor.measured`, is pinned by
`scripts/check-token-budget.sh`'s mirror-row sync; the mutation run is recorded under F356.

| Finding | Disposition | File changed |
|---|---|---|
| F343 | fixed | `.claude-plugin/README.md`, `loomwright/docs/command-parts/agent-help/guide.md` |
| F347 | fixed (same edit as F343) | `loomwright/docs/command-parts/agent-help/guide.md` |
| F348 | fixed (same edit as F343) | `loomwright/docs/command-parts/agent-help/guide.md` |
| F356 | fixed | `loomwright/docs/prompt-token-budgets.json`, `loomwright/docs/ARCHITECTURE_CONTRACTS.md` |
| F368 | fixed | `loomwright/skills/quality-checklist/SKILL.md` |
| F050 | fixed | `README.md` |
| F118 | fixed (the figure 70 reproduces; command added, cell unchanged) | `loomwright/docs/RULES_BASELINE.md` |
| F144 | fixed | `docs/evidence/af39b-run-lock-holder.md` |
| F146 | fixed (same edit as F144) | `docs/evidence/af39b-run-lock-holder.md` |
| F310 | fixed | `docs/evidence/as19-split-lanes-and-trail-scripts.md` |
| F231 | fixed (footnote) | `docs/evidence/review-gate-rounds.md` |

No finding in this group was already fixed on the base, so none is `recorded` under AC21.

## F343, F347, F348 — `commands/` trees omit five commands

```
$ ls loomwright/commands | wc -l
      25
$ grep -nE 'commands/ +# ' .claude-plugin/README.md loomwright/docs/command-parts/agent-help/guide.md
.claude-plugin/README.md:443:    ├── commands/                            # Slash commands
loomwright/docs/command-parts/agent-help/guide.md:257:├── commands/                         # Slash commands
```

Both trees still omitted `backlog.md`, `handoff.md`, `janitor.md`, `propose.md` and `rules.md`, and neither said
it was partial. **Fixed:** each tree's `commands/` label now reads
`# Slash commands — excerpt; full list: loomwright/commands/`. No count is restated, so a new command needs no edit
to either tree. `git grep -nE '[├└]── commands/' -- '*.md'` finds no third tree. F347 and F348 are duplicates of
F343 on `guide.md` and are closed by the same edit.

## F356 — `.commands.janitor.measured` and its mirror row are stale

```
$ jq -c '.commands.janitor' loomwright/docs/prompt-token-budgets.json
{"budget":1470,"measured":1336,"note":"new command (af/39f): measured + ~10%"}
$ grep -nF '| `janitor` |' loomwright/docs/ARCHITECTURE_CONTRACTS.md
768:| `janitor` | 1470 | 1336 |
$ bash scripts/check-token-budget.sh | grep '^janitor '
janitor                    1427     1470  OK      43 headroom (loomwright/commands/janitor.md)
```

The measured value on this base is **1427**, the figure the brief's `## Pin mutations` row assumes, so that row
needs no change. **Fixed:** `.commands.janitor.measured` and the mirror row's Measured cell are now 1427; `budget`
stays 1470 and the entry's `note` is unchanged. `check-token-budget.sh` exits 0 after the edit.

Pin mutation (from the brief): with `"measured": 1427` flipped back to `1336` in the JSON only, the gate exits 1:

```
janitor                       -     1470  ERROR   mirror drift: table MEASURED cell '1427' != JSON measured '1336' in loomwright/docs/ARCHITECTURE_CONTRACTS.md — …
check-token-budget: FAILED — prompt inventory ratchet tripped (see BREACH/ERROR rows above).
```

The JSON was restored from a copy and the gate re-run green.

Limit: the entry's `note` ("measured + ~10%") describes how the 1470 ceiling was set from the original 1336
measure; 1427 + 10% is not 1470. The brief keeps the note, and `ARCHITECTURE_CONTRACTS.md`'s re-measure log has
precedent for a live re-measure that leaves every `budget` unchanged, so only the measured figure moved.

## F368 — module-shape heading scope disagrees with code-reviewer step 5d

```
$ grep -nF '**Module shape (`module_shape`' loomwright/skills/quality-checklist/SKILL.md
163:- [ ] **Module shape (`module_shape` — Supervisor Phase 4.5 only).** When the spawn prompt carries …
$ grep -nF '5d. **Module shape' loomwright/agents/code-reviewer.md
305:5d. **Module shape (structure — every caller, every mode; the MODULE-SHAPE ADVISORY facts line is Supervisor Phase 4.5 only)**
```

**Fixed:** the heading now reads
``**Module shape (`module_shape` — every caller; the MODULE-SHAPE ADVISORY facts line is Supervisor Phase 4.5 only).**``.
The body is unchanged, the line keeps `never read absence as clean`, and it does not gain `does not apply`
(`test-module-shape-facts.sh` G9). `git grep -nF 'module_shape` — Supervisor Phase 4.5 only'` prints nothing after
the edit.

## F050 — README's unattended section omits the newer can't-ask outcomes

```
$ for p in launch_pad_cant_ask_non_interactive saved_on_pass_non_interactive pr_base_verify_skipped_non_interactive "Question-gate inventory"; do printf '%s: ' "$p"; grep -cF "$p" README.md; done
launch_pad_cant_ask_non_interactive: 0
saved_on_pass_non_interactive: 0
pr_base_verify_skipped_non_interactive: 0
Question-gate inventory: 0
```

The other half of the finding (the `commands/autonomous.md` ESCALATED row) has been gone since the prompt diet, so
only the README half was left. **Fixed:** one bullet added under `--non-interactive-fallback` in
§"Running /autonomous in CI / unattended". It names the Launch Pad forward, `saved_on_pass_non_interactive`, the
`launch_pad_cant_ask_non_interactive` run outcome (with Launch Pad's own status kept in the summary), the
`pr_base_verify_skipped_non_interactive` skip, and points at `loomwright/docs/ARCHITECTURE_CONTRACTS.md`
§"Question-gate inventory" as the full list. Each named status was checked against its authority:
`skills/autonomous-loop/SKILL.md` PLAN steps 1 and 3, `skills/autonomous-loop/multi-iteration.md`
§"EVALUATE PR-base verification", and the inventory's Launch Pad and `/autonomous` rows.

## F118 — no command derives the `distinct PRs` baseline 70

```
$ grep -nF 'baseline 70' loomwright/docs/RULES_BASELINE.md
181:- **Records:** 73 (baseline 84) · **distinct PRs:** 73 (baseline 70) · **Findings:** 87 (baseline
$ git rev-parse --short 5293d06:.supervisor/postmortem/results.jsonl
952ff91
$ git show 5293d06:.supervisor/postmortem/results.jsonl | jq -r '.number' | sort -u | wc -l
      71
$ git show 5293d06:.supervisor/postmortem/results.jsonl | jq -r '[.repo, (if (.number//0)==0 then (.pr_url|capture("/pull/(?<n>[0-9]+)").n) else (.number|tostring) end)]|@tsv' | sort -u | wc -l
      70
$ git show 5293d06:.supervisor/postmortem/results.jsonl | jq -c 'select((.number//0)==0)|{number,pr_url}'
{"number":0,"pr_url":"https://github.com/vikashruhilgit/loomwright/pull/126"}
```

**70 reproduces**, so the cell is not changed. The 71 from Launch Pad's probe counts the one `number: 0` record
as its own PR. Under the row's own rule (a `number: 0` record takes its number from `pr_url`) that record is #126,
which another record already carries. The same `.repo`-plus-number pairing the window's `pairs.tsv` uses gives 70.
Dropping `.repo` also gives 70, so no PR is counted twice across the ledger's two slugs. **Fixed:** the
distinct-PR command block now carries this command, with `# 70 (baseline)` as its trailing comment, and its lead-in
sentence says why a plain distinct-`.number` count prints 71. The command prints 70 in both bash and zsh.

## F144, F146 — af39b provenance line predates the UTC pin

```
$ git log --format='%h %ad' --date=iso -- docs/evidence/af39b-run-lock-holder.md
463dc37 2026-10-14 15:30:46 +0530
$ git show -s --format='%h %ad %s' --date=iso 4cf6a58
4cf6a58 2026-10-14 15:59:27 +0530 fix: address review feedback (iteration 1)
$ git show 463dc37:loomwright/scripts/run-lock.sh | grep -c 'TZ=UTC0'
0
$ grep -nF 'TZ=UTC0' loomwright/scripts/run-lock.sh
78:# `pid_start` fingerprints the holder: `env TZ=UTC0 LC_ALL=C ps -o lstart=
294:  env TZ=UTC0 LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | …
$ git merge-base --is-ancestor 463dc37 4cf6a58 && echo before
before
```

The file still said the capture ran "against this branch's `loomwright/scripts/run-lock.sh`". It was captured at
`463dc37`, before `4cf6a58` added the UTC pin, so its `pid_start` values (e.g. `Wed Oct 14 15:27:47 2026`) are
local IST. **Fixed:** the provenance paragraph now names `463dc37`, says the values are local time captured before
`4cf6a58`'s `env TZ=UTC0 LC_ALL=C ps -o lstart=` pin, says the shipped script records UTC, and says no captured
value was altered. No transcript line was edited. F146 is the same root and is closed by the same edit.

## F310 — as19 §3 and the line-7 note do not reach §10

```
$ grep -nE '051553e:<path>|Pre-merge vs' docs/evidence/as19-split-lanes-and-trail-scripts.md
7:**Pre-merge vs. merged tree.** … its merged value is given beside it or in §9.
79:… equals `git show 051553e:<path>`) is asserted by the AC3 legs of the two `*-modules.sh` tests (56/56 and 24/24 above).
$ grep -n '^BASE_SHA' loomwright/scripts/test-automate-lanes-modules.sh
47:BASE_SHA=087b9e417e521217e3998381f3d8c2f79695e109
$ grep -n '^BASE=' loomwright/scripts/test-automate-trail-modules.sh
37:BASE=087b9e417e521217e3998381f3d8c2f79695e109
```

**Fixed:** §3's AC3 sentence now says `051553e` was the pin when §3 was measured and that the current pin is
`087b9e4` (`BASE_SHA` and `BASE` in the two module tests), moved by §9 and §10. The line-7 note now adds that a
second merge re-based onto `087b9e4`, recorded in §10, which supersedes §9's base pin. No measured figure changed.

## F231 — `not recorded (… no Plan Review N/M)` cells hide cap-less attempt text

```
$ git show 8100319:docs/evidence/review-gate-rounds.md | grep -cF 'not recorded (run file, brief: no Plan Review N/M)'
62
$ grep -nF 'no Plan Review N/M' docs/evidence/review-gate-rounds.md | grep -E '^[0-9]+:\| #(222|455) ' | cut -c1-40
122:| #222 | verify-walkthrough/02-verif
173:| #455 | automate-followups/38-close
```

62 table cells on the base carry it, `#222` and `#455` among them (after the edit the count is 63: the footnote
quotes the phrase once). The extractor still reads only `N/M` forms. **Fixed:** a footnote under the pre table, below its `<!-- /pre -->` marker and `</details>`, says these
cells mean "no `N/M` form found", that cap-less `Plan Review attempt N` text was not read, and that the run files
are not in this checkout. It sits outside every `<!-- name -->` block, so `## Commands` block 3's re-run comparison
is unaffected. No cell and no count changed.

Live read, not re-run by block 3 and not written into the frozen file: the primary checkout holds meta-synced run
files. `automate-2026-10-10-094837.md` (the #455 item) records `Plan Review attempt 1 PASS … attempt 2 PASS`, a
cap-less form the extractor skips, so #455 used 2 attempts with an unrecorded cap. The #222 segment of
`automate-2026-09-14-072219.md` (`picked …/02-verify-evidence-store.md` up to its next `picked` line) has no
Plan Review text at all, so its `not recorded` is accurate. The other rows with this cell were not read.

## Validation

See the PR body and the subtask's result for the final `bash scripts/ci-local.sh --affected` and
`bash scripts/check-version-bump.sh` lines. The release fragment is `changelog.d/dismissed-followups-06a-docs-drift.md`;
no version file was edited by hand.
