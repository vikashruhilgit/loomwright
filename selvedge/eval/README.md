# Selvedge known-answer set

A fixed set of acceptance criteria with known right answers, used to measure how often Selvedge
says PASS when the right answer is FAIL. The set is split by underlying defect into a **tuning**
side (about 40% of the defects) and a **held-out** side (about 60%). The held-out answers file is
kept outside this repository, but in this release every held-out answer can still be worked out
from committed data (see "What the outside folder does not hide" below); only the planted variants,
once they land, will be withheld.

This folder is an owner-only measurement tool. It is not part of the `selvedge` CLI, and nothing
in `selvedge/bin` or `selvedge/lib` reads it.

The set's sizes are never written here: run `node selvedge/eval/eval-set.mjs count`, which prints
each count beside its floor and marks it `met` or `open`. The floors live in `eval-set.mjs`
(`FLOORS`).

Floors still open: known-FAIL and held-out known-FAIL. Both need the planted-defect set (below),
which the owner writes in a separate session; `count` shows the measured values.

## Layout

| Path | What it holds |
|---|---|
| `split.json` | the split rule's name and seed: `{"schema_version": 1, "rule": "<SPLIT_RULE>", "seed": "<seed>"}` |
| `tuning/cases.json` | `{"schema_version": 1, "cases": [...]}`, every case with its `answer` |
| `held-out/cases.json` | the same shape, **no** `answer` key on any case |
| `held-out/manifest.sha256` | `<sha256>  <relative path>`, one line per file in the outside folder, sorted |
| `real-bugs.json` | `{"schema_version": 1, "entries": [...]}`, one entry per real bug tried |
| `eval-set.mjs` | the tooling (below) |
| `harness.mjs` | the eval harness: runs Selvedge on one side of the set and scores it ([The eval harness](#the-eval-harness)) |
| `stats.mjs` | the harness's arithmetic: rates, Clopper-Pearson intervals, the gate, the two-revision rule (no I/O) |
| `target-driver.sh` | brings one target (a commit, or a planted variant) up on localhost for the harness |
| `results.json` | every report the harness wrote, one per run; the only place its rates live |
| `plugin-eval-limits.md` | what `claude plugin eval` can and cannot do for this set |

Outside the repository, in the **outside folder** `$SELVEDGE_EVAL_HELD_OUT` (default
`~/.claude/selvedge-eval/held-out/`):

- `answers.json` — `{"<case_id>": "PASS" | "FAIL"}` for every held-out case, and nothing else
- `variants/<group_id>/…` — held-out planted app variants, when the planted set lands

## Data model

- **Group** (`group_id`) — the unit of the split: one real bug (`sm-pr-<N>`) or one planted defect
  (`pd-<slug>`). Every case from that bug, including the non-defect criteria taken on its
  commits, carries its `group_id`, so they all land on the same side.
- **Case** — one criterion checked on one target, with one known answer:
  `{case_id, group_id, source, criterion: {id, text}, target, answer?}`
  - `case_id`: unique across the set, letters, digits, `.`, `_` and `-` (starting with a letter or digit)
  - `source`: `real-bug`, `non-defect` or `planted`
  - `criterion.text` is `normalizeCriterionText(raw)` and `criterion.id` is
    `criterionId(criterion.text)`, both from `selvedge/lib/criteria.mjs`
  - `target`: `{"kind": "commit", "repo": "<owner/name>", "sha": "<40 hex>"}` or
    `{"kind": "variant", "path": "<relative path>"}`
  - a real-bug criterion gives two cases: FAIL on the bug's `parent_sha`, PASS on its `fix_sha`;
    a `non-defect` case's answer is PASS
- **Real-bug entry** (`real-bugs.json`) — `repo`, `pr`, `parent_sha`, `fix_sha` (40 hex each),
  `setup` (the steps used to revive the commits: a list of strings, or `{"parent": [...], "fix":
  [...]}`), `status` (`used` or `skipped`), and a non-empty `skip_reason` on every `skipped` entry.
  A real-bug case must target the `parent_sha` or `fix_sha` of a complete `used` entry. An entry
  may carry `group_id` (default `sm-pr-<pr>`): when one commit is one entry's `fix_sha` and another
  entry's `parent_sha` (two fixes merged back to back), a case on it takes its role from the entry
  whose group is the case's `group_id`, and with no such entry it is `case_invalid`.

## The split rule

A group goes to tuning when the first 8 hex characters of `sha256(seed + ":" + group_id)`, read as
an integer, mod 100 are below 40; otherwise it goes to held-out. The rule is per group, so adding a
group later never moves an existing one. `split.json` records the rule's name and the seed;
`node selvedge/eval/eval-set.mjs side <group_id>…` prints the side a group gets.

## The outside folder

`$SELVEDGE_EVAL_HELD_OUT` is read by `eval-set.mjs` only (not by the `selvedge` CLI). It lives on
one machine. To back it up, copy the whole folder; to check a restored copy, run
`node selvedge/eval/eval-set.mjs manifest check`. Losing it loses `answers.json` (which, in this
release, can be rebuilt from committed data) and, once they land, the held-out planted variants,
which cannot; the held-out set then has to be rebuilt.

Finder and other tools can drop files such as `.DS_Store` into the folder; `manifest check` names
any file it does not list (`manifest_extra_file`), so remove such files rather than re-writing the
manifest around them.

**What the outside folder does not hide.** In this release, every held-out answer can be worked
out from committed data alone. A `non-defect` case's answer is PASS by the rule above, and its
`source` is committed in `held-out/cases.json`. A real-bug case is FAIL on its entry's `parent_sha`
and PASS on its `fix_sha`, and both commits, with what the probe saw (`observed`), are committed in
`real-bugs.json`. So `answers.json` keeps no held-out answer secret yet; it is what `count` reads.
Only the planted variants, once they land, will be withheld: their files and answers go to the
outside folder only.

## Commands

All commands take `--repo <dir>` (the repository top level; default: this checkout) and exit 0 ok,
1 a named failure (`eval-set: FAIL <token>: <detail>` on stderr), 2 a usage error or cannot run.

| Command | What it does |
|---|---|
| `node selvedge/eval/eval-set.mjs count` | `validate`, then `manifest check`, then the answers check, then each count beside its floor |
| `node selvedge/eval/eval-set.mjs validate` | `split.json`, both `cases.json` files and `real-bugs.json` against the rules above |
| `node selvedge/eval/eval-set.mjs check-leak` | the tracked files under `selvedge/eval/` (from `git ls-files`) hold no held-out answer or variant; also runs `validate` |
| `node selvedge/eval/eval-set.mjs split <cases.json>` | adds cases (each with an `answer`) by the rule: tuning cases with answers, held-out cases without, held-out answers into the outside `answers.json`; writes nothing when a check fails |
| `node selvedge/eval/eval-set.mjs side <group_id>…` | the side the recorded rule gives each group |
| `node selvedge/eval/eval-set.mjs manifest write` | lists every file in the outside folder in `held-out/manifest.sha256` (refuses an empty or missing folder) |
| `node selvedge/eval/eval-set.mjs manifest check` | the outside folder against the committed manifest |
| `node selvedge/eval/eval-set.mjs check-start-folder <dir>` | the planted-defect author's start folder holds only the two allowed copies (below) |
| `node selvedge/eval/eval-set.mjs import-planted <out-dir>` | adds the planted-defect session's output (below) to the set, through the same rules as `split` |

Adding cases: write them, with answers, to a file outside the repo (a held-out answer must never
be committed, even briefly), then run `split <file>`, `manifest write`, `check-leak` and `count`.

### Reason tokens

| Token | Meaning |
|---|---|
| `split_unreadable` | `split.json` is missing, unreadable, or names no known rule and non-empty seed |
| `defect_on_both_sides` | one `group_id` has cases in both `tuning/cases.json` and `held-out/cases.json` |
| `case_on_wrong_side` | a case sits on the side the rule does not give its `group_id` |
| `case_invalid` | a case is malformed (fields, criterion id, duplicate `case_id`, answer direction, real-bug link) |
| `held_out_answer_committed` | a tracked file, read by content whatever its name (JSON, or JSON Lines line by line, at any depth), holds an object for a held-out group or case that carries an answer, or maps held-out case ids to PASS or FAIL; or a tracked file sits under a held-out variant path, is named `answers.json`, or has the bytes of an outside file (an outside `variants/` file left unchanged from `tests/fixtures/app-server.mjs` or `servers.mjs` is exempt) |
| `real_bug_entry_incomplete` | a `real-bugs.json` entry lacks a field, or a `skipped` entry lacks its `skip_reason` |
| `no_tracked_files` | `git ls-files` returned nothing (fails closed rather than passing an empty tree) |
| `manifest_empty` | `held-out/manifest.sha256` is missing or lists no file |
| `manifest_invalid` | a manifest line is not `<sha256>  <relative path>`, or repeats a path |
| `manifest_mismatch` | a listed outside file's bytes changed |
| `manifest_missing_file` | a listed outside file is gone (a missing outside folder names every file) |
| `manifest_extra_file` | the outside folder holds a file the manifest does not list |
| `held_out_answers_incomplete` | the outside `answers.json` is missing, or its keys are not exactly the held-out `case_id`s, or an answer is not PASS or FAIL |
| `start_folder_not_clean` | the start folder holds a file that is not one of the two allowed copies, or lacks one of them |
| `planted_import_invalid` | the planted-defect session's `out/` folder is not as the brief asks: a `cases.jsonl` line with other fields, a bad slug or answer, an empty or repeated criterion, a group with no FAIL criterion, a variant folder with no cases (or cases with none), a variant folder holding anything but exactly `app-server.mjs` and `servers.mjs`, or a non-regular file, or a variant already imported with other bytes |

These are the eval tool's own reasons; the CLI's verdict and config reasons are listed in
`selvedge/README.md`.

## The eval harness

`harness.mjs` runs the normal Selvedge path on every case of one side of the set: plan (the
default `claude -p` planner, or `SELVEDGE_PLANNER`), freeze, the model-free `selvedge run`, and the
verdict. It then scores each criterion's verdict against its known answer, appends one report to
`results.json`, and prints the rates and the gate line. The harness writes no rate anywhere else:
`selvedge/README.md` shows the latest reports in a block that `harness.mjs readme` generates from
`results.json`, and `selvedge/tests/test-eval-harness.sh` fails when the two differ.

| Command | What it does |
|---|---|
| `node selvedge/eval/harness.mjs run --set held-out\|tuning [--planner-repeats N] [--runner-repeats N] [--work-dir <dir> [--resume]]` | checks the set (held-out: `eval-set.mjs count`, so validate, `manifest check` and the answers check; tuning: `validate`), stopping on any problem before a target is brought up or a file is written; then brings each target up once, plans and runs its cases, takes it down, and appends the report |
| `node selvedge/eval/harness.mjs score --work-dir <dir>` | scores a finished work dir again and appends that report |
| `node selvedge/eval/harness.mjs readme` | rewrites the results block in `selvedge/README.md` from `results.json` (never edit the block by hand) |
| `node selvedge/eval/harness.mjs check-readme` | exits 1 when that block is not what `readme` would write |

All take `--repo <dir>`, `--results <file>` and (readme, check-readme) `--readme <file>`.

**Repeats.** `--planner-repeats N` makes N fresh plans per target: plan 1 gives the main verdicts,
plans 2 to N only feed the planner-flip number. `--runner-repeats N` runs plan 1 N times in all (the
first run, then `selvedge run --replay` of it): runs 2 to N only feed the runner-flip number. A case
flips when its verdicts across those repeats are not all equal. A target whose plan 1 does not
freeze is never replayed: its cases keep their BLOCKED main verdicts but are left out of the runner
series, so the runner `cases` count can be lower than the case count. The main rates' denominators
are the case counts, whatever the repeats.

**Work dir and targets.** Every run folder, workspace, clone and log lives in the work dir, outside
this repository (default under `${TMPDIR}`; a work dir inside the repository is refused). A run
that stops part-way keeps each finished target; `--work-dir <dir> --resume` finishes it with the same
set, engine, repeats and cases. Each target is brought up by `target-driver.sh` (or the command in
`SELVEDGE_EVAL_TARGET_DRIVER`): `up <target.json> <dir>` prints `origin=<url>` and `root=<dir>`,
`down <dir>` takes it down, and `stop <dir>` runs once at the end. For a commit it carries out the
`setup` lines `real-bugs.json` recorded for that commit, each as a known step: a scratch clone
(`SELVEDGE_EVAL_CLONE_DIR`), `supabase/config.toml` copied read-only from the owner's checkout
(`SELVEDGE_EVAL_SM_CHECKOUT`) and patched to project id `selvedge-eval-sm` and ports 553xx, `npm ci`,
`supabase db reset --local`, any fixture SQL, `.env.local`, the Google Fonts stylesheets (fetched
again, up to five tries in all, when Google serves one as `fonts.gstatic.com/l/` files, which Turbopack
refuses; `fonts <clone> <out.js>` runs this step alone), and a fresh
`next dev -p 3471`. A setup line it does not know, or a step that fails, stops the run with
`target_unavailable` and the step named; a target is never scored part-way. A planted variant is
served with `node app-server.mjs serve`. Each target's workspace is a git repo in the work dir
holding `criteria.json` and a `selvedge.json` that allows only the driver's origin, and
`selvedge/bin/selvedge` runs there (`SELVEDGE_EVAL_SELVEDGE_BIN` replaces it; Playwright comes from
`SELVEDGE_PLAYWRIGHT_MODULE`). `SELVEDGE_PLANNER_TOKEN_BUDGET` is removed from every selvedge child's
environment: a plan over budget would be BLOCKED after its tokens were spent.

**Scoring.** Abstention = (BLOCKED + NOT_VERIFIABLE) ÷ every criterion scored. False-PASS = PASS on
a known-FAIL case ÷ every known-FAIL case. False-FAIL = FAIL on a known-PASS case ÷ every
known-PASS case. Each comes with its numerator, denominator and exact Clopper-Pearson 95% interval
(two-sided). A plan that does not freeze makes each of that target's criteria BLOCKED with the
planner's reason (`planner_failed`, `plan_invalid`), and a run that leaves no `verdict.json` makes
them BLOCKED with its reason: Selvedge gave no verdict, so they count as abstention. A criterion
whose `evidence_class` in `verdict.json` is `model-judged` is counted in the report's own
`model_judged` section and never in those rates. A `budget_exceeded` BLOCKED is shown on its own line
as well as in abstention.

**The Phase 3 gate** (`stats.mjs`, `GATE`): `met` only on a held-out report whose known-FAIL
denominator is at least `FLOORS.held_out_fail` (from `eval-set.mjs`), with a false-PASS point
estimate at most `GATE.false_pass_max` and abstention at most `GATE.abstention_max`; otherwise `not
met`, naming every condition that failed. A tuning report has no gate verdict. **Two-revision rule:**
when the latest held-out reports (each at or above the floor) of `GATE.revisions_before_review`
distinct engine versions all miss the gate, the harness prints that the owner should stop and run
the section 8 review early. Nothing in the harness raises the abstention cap or loosens the gate.

**`results.json`** is `{"schema_version": 1, "reports": [...]}`. Each report holds `set`, `engine`
(`selvedge_version` from `plugin.json`, `planner_model` from `SELVEDGE_PLANNER_MODEL` or the
planner's default, or `SELVEDGE_PLANNER` for a custom planner), `ts`, `cases`, `rates`
(`false_pass`, `false_fail`, `abstention`, each `{numerator, denominator, rate, ci95: {lower,
upper}}`), `verdict_counts`, `abstention_reasons`, `budget_exceeded`, `model_judged`, `per_group`
and `per_app` (counts per `group_id` and per app: the target repo, or `sample-app` for a variant),
`repeatability` (`runner` and `planner`, each with `repeats`, `cases`, `flipped` and `flips`, an
array of `{case_id, verdicts}`), `runs` (planner tokens and duration per run), `totals` and `gate`
(`{verdict: "met" | "not met", failed}`, or null for tuning). It carries no `answer` key and no map
of case ids to PASS or FAIL, so `check-leak` passes on it. When the planted held-out set lands, check
the per-group counts and flip lists of planted groups for answer exposure before committing a report.

### Harness reason tokens

Printed `harness: FAIL <token>: <detail>` on stderr (exit 1). A failing set check prints
`eval-set.mjs`'s own lines and tokens (above) instead.

| Token | Meaning |
|---|---|
| `target_unavailable` | the target driver could not bring a target up (the step it stopped at is named); the run stops, nothing is scored |
| `results_invalid` | `results.json` is missing (for `readme`) or not `{"schema_version": 1, "reports": [...]}` with a set, engine and rates on every report |
| `readme_results_out_of_sync` | the results block in `selvedge/README.md` is not what `readme` would write from `results.json` (or a block exists with no results file) |
| `readme_markers_missing` | `selvedge/README.md` has one block marker without the other, or no markers and no "Measuring Selvedge" section to put them in |
| `work_dir_invalid` | the work dir is inside the repository, already holds a run (without `--resume`), or holds a run of another set, engine, repeat count or case list |
| `run_incomplete` | `score` (or the end of `run`) found a target with no finished result in the work dir |

## The planted-defect author session (open)

Planted defects (`source: "planted"`, `target.kind: "variant"`, `group_id` `pd-<slug>`) are written
by a separate session the owner starts by hand, so the session that builds Selvedge never sees the
held-out variants. The tooling accepts them with no code change: tuning variants are committed
under `selvedge/eval/tuning/variants/<group_id>/`, held-out variants go to the outside folder under
`variants/<group_id>/`.

- Session id: TBD
- Start date: TBD
- Committed brief: [`planted-session-brief.md`](planted-session-brief.md), given as the session's first
  message (the start folder may hold only the two app files, so the brief cannot sit in it)

**Building its start folder.** Make an empty folder outside this repository and copy exactly two
files into it, unchanged:

```bash
mkdir <dir>
cp selvedge/tests/fixtures/app-server.mjs selvedge/tests/fixtures/servers.mjs <dir>/
node selvedge/eval/eval-set.mjs check-start-folder <dir>
```

`check-start-folder` fails (`start_folder_not_clean`) naming each file in `<dir>` that is not one
of those two copies (saying which tracked file under `selvedge/` it copies, when it does), and each
of the two that is missing. Start the session in that folder only after the check passes:

```bash
cd <dir> && claude "$(cat <repo>/selvedge/eval/planted-session-brief.md)"
```

**Importing its output.** The session writes `out/cases.jsonl` and one `out/pd-<slug>/` folder per
variant. The owner runs the import, never the session that builds Selvedge, since it reads the held-out
variants:

```bash
node selvedge/eval/eval-set.mjs import-planted <dir>/out
node selvedge/eval/eval-set.mjs manifest write
node selvedge/eval/eval-set.mjs check-leak
node selvedge/eval/eval-set.mjs count
```

A slug names its bug, so next to the held-out criteria it would give the answers away. The import
gives each group an opaque id instead, `pd-` and the first 10 hex of `sha256("planted:" + slug)`. The
slug-to-id list goes to `<dir>/out/imported-ids.tsv` and never into the set. `out/BUGS.md` is never
read. Each case is `<id>.<criterion id without c->`, with source `planted` and target
`{"kind": "variant", "path": "variants/<id>"}`. The cases go in through `split`, so the split rules
apply and a refusal writes nothing. The variants are copied only after that: a tuning variant to
`tuning/variants/<id>/` (committed), a held-out variant to the outside folder's `variants/<id>/`.
Running the import again with the same output changes nothing. A variant that differs from the one
already imported under its id is refused. The command prints only counts. Its refusals name slugs,
so run it in your own terminal.
