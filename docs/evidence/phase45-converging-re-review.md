# Phase 4.5 converging re-review (`heal_review_scope`): evidence

Brief: `.supervisor/jobs/in-progress/2026-11-01-phase45-re-review-converges-on-last-fix.md`, acceptance criterion AC17 (requirement Validation 2a). Base commit: `26eda742b616a339f971b34b5b7d8740c9654851`.

## Status: pending — the pre-release shadow run has not been executed yet

AC17 asks for one real `/automate` item, run headless against this branch's plugin in `shadow` mode (the shipped default), with that item's heal-round record lines and the `heal-review-scope.sh --shadow-report` output committed here. **That run has not happened.** It takes hours, and the worker that wrote this file was told not to start it from inside its own session. This file therefore holds **no** real record lines and **no** real report output. The section below shows what the helper does on synthetic data, and it is not the AC17 run.

AC17 is open until the owner (or a later lane) runs the procedure below and replaces this section with the real output.

## What this file will hold once the run is done

1. The `/automate` item that ran (run id, item, PR number) and the plugin version reported by the stream's `init` event, which proves the `--plugin-dir` copy was loaded.
2. Every line of that item's record file, `.supervisor/heal-rounds/<brief basename>.jsonl`, verbatim. Each record holds a `{file, issue_category, rule}` fingerprint and no finding prose, so the lines can be committed as they are.
3. The verbatim output of `heal-review-scope.sh --shadow-report` over that directory.
4. If the item never reached a heal round ≥ 2 (Phase 4.5 passed in round 1, so no round record has `iteration ≥ 2`), a statement saying so, plus a second item's record lines and report.

## Procedure (the AC17 run)

Run from a scratch `git init` repo, or a disposable clone, **outside** this worktree so the run's `.supervisor/` never mixes with this checkout's. Leave `.supervisor/config.json` without a `heal_review_scope` key so the default (`shadow`) is what gets measured. `--non-interactive-fallback` makes every question gate take its fail-closed branch instead of waiting for an answer that cannot come in a headless run. Bound the run: start it in the background and wait on the `rc=` line it appends, never on `pgrep -f`.

```
cd <scratch-repo>
claude -p "/loomwright:automate \"<one small, real item>\" --limit 1 --non-interactive-fallback" \
  --plugin-dir <this branch's checkout>/loomwright \
  --output-format stream-json --verbose > <scratch>/automate-stream.jsonl 2>&1; echo rc=$? >> <scratch>/automate-stream.jsonl

# the item's records (one round record per round, one finding record per actionable or dismissed finding)
cat .supervisor/heal-rounds/*.jsonl

# the promotion evidence (read-only)
bash <this branch's checkout>/loomwright/scripts/heal-review-scope.sh --shadow-report --dir .supervisor/heal-rounds
```

Paste items 1–4 above into this file, delete the `Status: pending` section, and link this file from the PR body.

## Synthetic local demonstration (NOT the AC17 run)

To show the record and report shapes before the real run, `loomwright/scripts/heal-review-scope.sh` was driven by hand on 2026-11-01 in a `mktemp -d` scratch repo with `HOME` relocated into it. Every record below was written by the helper's own `record` subcommand, and every fingerprint came from its `fingerprint` subcommand. The scenario is invented: two files changed by a "fix" commit, one MEDIUM `nit` dismissed in round 1, and one HIGH `new` finding fixed in round 1. Both findings are re-reported in round 2. The review timestamps and `pr: 1` are made-up inputs, and the commit shas are those of the scratch repo, which was deleted afterwards. It shows the shapes and nothing about how real heal rounds behave.

```
$ heal-review-scope.sh mode --root .            # no .supervisor/config.json
shadow
$ heal-review-scope.sh scope --round 1 --head <R1> --root .
scope: full
$ heal-review-scope.sh scope --round 2 --prev <R1> --head <R2> --root .
scope: files
a.sh
b.md
$ heal-review-scope.sh prev-sha --file <records> --run-id sess-demo
b23622cfc20b
$ printf <round-2 issues: both round-1 findings re-reported> | heal-review-scope.sh suppress --file <records> --run-id sess-demo --count-only
{"kept":2,"suppressed":[{"file":"c.txt","issue_category":"nit","rule":"aa22f8a70b80"}],"count":1,"repeat_of_fixed":[{"file":"a.sh","issue_category":"new","rule":"3f89b2557002"}]}
$ echo <a finding record carrying "description"> | heal-review-scope.sh record --file <records>
heal_round_record_failed: 1 record(s) refused (first: finding: unknown key(s): description)
$ cat .supervisor/heal-rounds/demo-brief.jsonl
{"kind":"round","run_id":"sess-demo","iteration":1,"reviewed_sha":"b23622cfc20b","pr":1,"mode":"shadow","scope":"full","full_files":3,"scope_fallback":null,"would_suppress":[],"suppressed_repeat":0,"repeat_of_fixed":[],"review_started_at":"2026-11-01T10:00:00Z","review_ended_at":"2026-11-01T10:20:00Z"}
{"file":"c.txt","issue_category":"nit","rule":"aa22f8a70b80","kind":"finding","run_id":"sess-demo","iteration":1,"reviewed_sha":"b23622cfc20b","pr":1,"severity":"MEDIUM","outcome":"dismissed"}
{"file":"a.sh","issue_category":"new","rule":"3f89b2557002","kind":"finding","run_id":"sess-demo","iteration":1,"reviewed_sha":"b23622cfc20b","pr":1,"severity":"HIGH","outcome":"fixed","fix_commit":"6a9b442fca55"}
{"kind":"round","run_id":"sess-demo","iteration":2,"reviewed_sha":"6a9b442fca55","pr":1,"mode":"shadow","scope":"full","scope_files":2,"full_files":3,"would_scope":["a.sh","b.md"],"scope_fallback":null,"would_suppress":[{"file":"c.txt","issue_category":"nit","rule":"aa22f8a70b80"}],"suppressed_repeat":0,"repeat_of_fixed":[{"file":"a.sh","issue_category":"new","rule":"3f89b2557002"}],"review_started_at":"2026-11-01T10:30:00Z","review_ended_at":"2026-11-01T10:48:00Z"}
{"file":"c.txt","issue_category":"nit","rule":"aa22f8a70b80","kind":"finding","run_id":"sess-demo","iteration":2,"reviewed_sha":"6a9b442fca55","pr":1,"severity":"MEDIUM","outcome":"dismissed","in_would_scope":false}
{"file":"a.sh","issue_category":"new","rule":"3f89b2557002","kind":"finding","run_id":"sess-demo","iteration":2,"reviewed_sha":"6a9b442fca55","pr":1,"severity":"HIGH","outcome":"remaining","in_would_scope":true}
$ heal-review-scope.sh --shadow-report --dir .supervisor/heal-rounds
heal-review-scope shadow report (read-only)
dir: .supervisor/heal-rounds
rounds: 1
findings_total: 2
outside_scope: 1
  - c.txt|nit|aa22f8a70b80 pr=1
would_suppress: 1
  - c.txt|nit|aa22f8a70b80 pr=1
repeat_of_fixed: 1
  - a.sh|new|3f89b2557002 pr=1
skipped_review_minutes_est: 6 (estimate: sum of review minutes x (1 - scope_files / full_files) over non-fallback rounds)
fallbacks: none
(records dir byte-identical before and after the report)
```

What it shows, within the synthetic scenario:

- Round 1 is always `scope: full`. Round 2's would-be scope is exactly the two files the fix commit changed (`a.sh`, `b.md`), not the untouched `c.txt`.
- Under `shadow` (`--count-only`) nothing is dropped (`kept: 2`). The dismissed `nit` is the only would-suppress fingerprint. The re-reported **fixed** finding is never suppressed: it is listed under `repeat_of_fixed` (owner decision D2).
- `record` refuses a record carrying finding prose and says so on one stderr line.
- The report counts only round ≥ 2 shadow records, flags the dismissed `nit` as outside the would-be scope, and leaves the records directory unchanged.

What it does **not** show: whether real heal rounds ≥ 2 find bugs outside the fix's files (the `outside_scope` count on real items is the number AC17 is for), how often the description-hash fingerprint matches a real repeat, or how much review time `files` mode would save. Only the AC17 run above can answer those.
