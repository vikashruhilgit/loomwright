# Selvedge known-answer set

A fixed set of acceptance criteria with known right answers, used to measure how often Selvedge
says PASS when the right answer is FAIL. The set is split by underlying defect into a **tuning**
side (about 40% of the defects) and a **held-out** side (about 60%). The held-out answers are kept
outside this repository, so the people and agents who build Selvedge never tune toward them.

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
`node selvedge/eval/eval-set.mjs manifest check`. Losing it loses the held-out answers that are not
derivable (non-defect cases, planted variants), and the held-out set then has to be rebuilt.

Finder and other tools can drop files such as `.DS_Store` into the folder; `manifest check` names
any file it does not list (`manifest_extra_file`), so remove such files rather than re-writing the
manifest around them.

**What the outside folder does not hide.** A real bug's answers can be worked out from the
committed `parent_sha` / `fix_sha` and from sports-management's public history (the fix commit is
where the criterion starts to pass). The outside folder still keeps the answers that cannot be
worked out that way: the non-defect cases and, later, the planted variants.

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

Adding cases: write them, with answers, to a file outside the repo (a held-out answer must never
be committed, even briefly), then run `split <file>`, `manifest write`, `check-leak` and `count`.

### Reason tokens

| Token | Meaning |
|---|---|
| `split_unreadable` | `split.json` is missing, unreadable, or names no known rule and non-empty seed |
| `defect_on_both_sides` | one `group_id` has cases in both `tuning/cases.json` and `held-out/cases.json` |
| `case_on_wrong_side` | a case sits on the side the rule does not give its `group_id` |
| `case_invalid` | a case is malformed (fields, criterion id, duplicate `case_id`, answer direction, real-bug link) |
| `held_out_answer_committed` | a tracked case or answer for a held-out group carries an answer, a tracked file sits under a held-out variant path, is named `answers.json`, or has the bytes of an outside file |
| `real_bug_entry_incomplete` | a `real-bugs.json` entry lacks a field, or a `skipped` entry lacks its `skip_reason` |
| `no_tracked_files` | `git ls-files` returned nothing (fails closed rather than passing an empty tree) |
| `manifest_empty` | `held-out/manifest.sha256` is missing or lists no file |
| `manifest_invalid` | a manifest line is not `<sha256>  <relative path>`, or repeats a path |
| `manifest_mismatch` | a listed outside file's bytes changed |
| `manifest_missing_file` | a listed outside file is gone (a missing outside folder names every file) |
| `manifest_extra_file` | the outside folder holds a file the manifest does not list |
| `held_out_answers_incomplete` | the outside `answers.json` is missing, or its keys are not exactly the held-out `case_id`s, or an answer is not PASS or FAIL |
| `start_folder_not_clean` | the start folder holds a file that is not one of the two allowed copies, or lacks one of them |

These are the eval tool's own reasons; the CLI's verdict and config reasons are listed in
`selvedge/README.md`.

## The planted-defect author session (open)

Planted defects (`source: "planted"`, `target.kind: "variant"`, `group_id` `pd-<slug>`) are written
by a separate session the owner starts by hand, so the session that builds Selvedge never sees the
held-out variants. The tooling accepts them with no code change: tuning variants are committed
under `selvedge/eval/tuning/variants/<group_id>/`, held-out variants go to the outside folder under
`variants/<group_id>/`.

- Session id: TBD
- Start date: TBD
- Committed brief: TBD

**Building its start folder.** Make an empty folder outside this repository and copy exactly two
files into it, unchanged:

```bash
mkdir <dir>
cp selvedge/tests/fixtures/app-server.mjs selvedge/tests/fixtures/servers.mjs <dir>/
node selvedge/eval/eval-set.mjs check-start-folder <dir>
```

`check-start-folder` fails (`start_folder_not_clean`) naming each file in `<dir>` that is not one
of those two copies (saying which tracked file under `selvedge/` it copies, when it does), and each
of the two that is missing. Start the session in that folder only after the check passes.
