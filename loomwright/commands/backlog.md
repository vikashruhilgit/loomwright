---
description: One read-only board of every requirement item's real state — done, in flight, parked, open, unknown — derived each run from run files, live lanes, merged PRs and the item's own stamp, never from a hand-kept label; --verify stamps only what the owner approves per item
---

> **Read-only, except `--verify`'s owner-approved stamps.** `/backlog` derives every value from sources on each run and writes nothing. Only `--verify` writes, and only one item at a time, after the owner answers that item's question. It writes through `backlog-stamp --confirm` and publishes through `meta-sync.sh`. It never runs git, never merges, and never stamps on its own judgement.

# Command: /backlog

## Purpose

A requirement's first `## Status:` line is not updated when its work merges: close-out appends a done stamp lower in the file, and `_BACKLOG.md` checkboxes are hand-kept. So counting `pending` first lines over-counts open work and re-offers shipped work. `/backlog` answers "what is pending, done, in flight" from evidence. Each item gets exactly one state, the totals add up to the item count, and each row names the evidence line its state rests on.

## Usage

```bash
/backlog                       # the board: every item, grouped by folder, with totals
/backlog --json                # the same board as ONE JSON object
/backlog --state <s>           # only rows in state <s>; totals stay whole-tree
/backlog --unknown             # unknown + brief_shipped items with a suggested fix (writes nothing)
/backlog --verify [<item>...]  # owner-gated verify-and-stamp of items with no merge evidence
```

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--json` | off | Print the board document: `schema_version`, `github`, `right_size`, `item_count`, `totals`, `state_filter`, `items[]` (`item`, `path`, `folder`, `state`, `evidence`, `run`, `lane`, `pr`, `pr_state`, `right_size`, `via`, `conflict`, `candidates`), `stale_runs[]`. |
| `--state <s>` | all | Filter rows to one state from the closed set. An unknown state is a usage error that lists the valid ones. |
| `--unknown` | off | List every `unknown` and `brief_shipped` item with its reason and a suggested fix: add `## Status: pending`, stamp done with the PR that shipped it, or mark it abandoned. It only suggests. |
| `--verify [<item>...]` | off | The owner flow below. With no items it covers every `brief_shipped`, `unknown` and `conflict` item. Named items are added to that set. |

## What it does

Every script named on this page lives in the plugin's `scripts/` directory and runs as `bash "${CLAUDE_PLUGIN_ROOT}/scripts/<script>" …`. Run the engine and print its output as is:

```bash
automate-helpers.sh backlog [--json] [--state <s>] [--unknown]
```

- **The item set** is every `*.md` under `.supervisor/requirements/`, minus the files `reconcile-status` skips (its `_rs_skip_path`). `proposed/` files are items.
- **The states** are one closed set, defined once in the header of `scripts/automate-helpers.d/backlog.sh` together with their precedence. `automate-helpers.sh item-state <item>` prints one item's state and the evidence behind it. Four states need the owner's attention: `merged_unstamped` (merge evidence exists but there is no done stamp), `conflict` (an `# abandoned:` / `# skipped:` Queue row disagrees with the item's own explicit `pending`/`ready`), `brief_shipped` (a brief landed, but nobody verified its acceptance criteria) and `unknown` (no status line, or an off-enum one). `stale_run` is a run state, listed under "runs needing attention" and never counted as an item: an unfinished run whose `## Current` names an item that its own stamp says is finished.
- **GitHub** is read twice per pass, as one cached `gh pr list` for merged PRs and one for open PRs. If either read fails, the header says `github: unverified` and every PR field reads `unverified`. A claimed item stays `in_flight`, never `pr_open`, and an item that would read `open` reads `unknown` (`merged-PR lookup unverified`), because `open` means no merge evidence and that needs the merged list. A merged PR counts as evidence only when its branch or title names a distinctive key as a whole token: the `NN-` id-prefixed basename or the folder-qualified one. A bare basename such as `spec` is only a `--verify-list` candidate.
- **The right-size column** comes from ONE `right-size --json` call over the whole item list. If that call fails, the column reads `unknown` and nothing else changes. That call is the slow part of a pass.

## `--verify` — owner-gated verify and stamp

1. **Can't-ask check first.** The flow cannot ask when this prose runs inside a subagent (the host strips the ask tool there) or the session is non-interactive (a headless print-mode session, CI, stdin not a TTY). In that case, run step 2, print every proposal from step 3, and write nothing. The first output line is `verify_requires_owner: <n> item(s) need the owner's answer — nothing stamped`. Never pick an answer for the owner.
2. **List.** Run `automate-helpers.sh backlog --verify-list [<item>...] --json`. It is read-only and prints the items with no merge evidence, with candidate merged PRs from the cached list.
3. **Propose, read-only.** For each item, read its acceptance criteria and check each one against the default branch: the named files, functions, flags and docs exist and say what the criterion says. Read each candidate PR's files and body with `gh pr view <n> --json files,body,mergedAt` (read-only). Then propose one outcome with its evidence: done (name the PR), done with escalation (say what is still owed), still pending (say what is missing; nothing to stamp), or abandoned (say what superseded it).
4. **Ask per item**, one question per call, each with its proposal and evidence in the question text:
   - An evidence-less item (`brief_shipped`, `unknown`, or named): ask with `header: "BL-VERIFY"` and the options `Stamp done` · `Stamp done with escalation` · `Abandon` · `Skip`. Offer the two stamp options only when step 3 names a merged PR. Otherwise offer only `Abandon` · `Skip`.
   - A `conflict` item: ask with `header: "BL-CONFLICT"` and the options `Abandon` · `Keep open` · `Skip`. Show both sources with their dates: the Queue row's run file and run date, and the item's last dated stamp (or `undated`).

5. **Stamp only the approved items**, one `backlog-stamp` call each, `<item>` repo-relative and never an absolute home path:

   | Answer (`BL-VERIFY` / `BL-CONFLICT`) | Call |
   |---|---|
   | `Stamp done` | `backlog-stamp <item> done --pr <url> [--pr <url>]... --confirm` |
   | `Stamp done with escalation` | `backlog-stamp <item> done_with_escalation --pr <url> --owed "<what is owed>" --confirm` |
   | `Abandon` | `backlog-stamp <item> abandoned --reason "<reason>" --confirm` |
   | `Keep open` | `backlog-stamp <item> kept-open --supersedes <the conflict row's run_id> --confirm` |
   | `Skip` | nothing |

   Each call is `automate-helpers.sh backlog-stamp …`. The PR URLs, owed text and reason come from the proposal the owner saw. The owner's answer note overrides them, word for word. A refusal (exit 1: already done, outside the requirements tree, a home path, a missing `--pr`/`--owed`/`--reason`, a `--pr` that is not one `https://…/pull/<n>` URL, a `--date` later than today) writes nothing. Report it and go on to the next item.
6. **Publish** once, after the last answer, and only if something was stamped. Read the mode with `setup-memory.sh --root <root> mode`. On `on <branch>` (branch mode), write the stamped repo-relative paths to a temp list and run `meta-sync.sh push --branch <branch> --paths-from <list> --message "backlog --verify: owner-approved stamps"`. If the push fails, say so loudly: the stamps stay on disk and a later push carries them. On `off`, the requirement files belong to the code branch: push nothing and list them for the owner to commit. On `unknown`, push nothing and print the reader's reason.
7. **Report** one line per item, `<item>: <answer> — stamped | skipped | refused (<reason>)`, then the publish result.

## See Also

- `scripts/automate-helpers.d/backlog.sh` is the engine (`item-state`, `backlog`, `backlog-stamp`), and its header is the authority for the states and precedence. `scripts/test-automate-helpers.sh`'s `18-backlog` part tests it on the hermetic fixtures under `scripts/fixtures/backlog-state/`.
- `reconcile-status` is the other stamper, driven by evidence. It never stamps ABANDONED over an explicit `pending`/`ready` item, and it prints `info\t<item>\tconflict\t<run file>` for a `conflict` item instead (`skills/automate-loop/helpers.md`).
- `docs/LANE_GATES.md` lists the `BL-VERIFY` / `BL-CONFLICT` gates (human-only). `docs/ARCHITECTURE_CONTRACTS.md` §"Question-gate inventory" holds their can't-ask row.
