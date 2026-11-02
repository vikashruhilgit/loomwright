# Phase 4.5 converging re-review (`heal_review_scope`): evidence

Brief: `.supervisor/jobs/in-progress/2026-11-01-phase45-re-review-converges-on-last-fix.md`, acceptance criterion AC17 (requirement Validation 2a). Base commit: `26eda742b616a339f971b34b5b7d8740c9654851`.

## The AC17 run

- **Item:** `.supervisor/requirements/dismissed-followups/05-test-coverage-gaps.md`, built as PR #788 (https://github.com/vikashruhilgit/loomwright/pull/788).
- **Run:** `automate-2026-11-02-071559-L1`, a single-lane `/loomwright:automate --parallel 1` run on 2026-11-02 in a fresh clone of `main` (`26eda742`), so its `.supervisor/` never mixed with this branch's checkout. The lane is a headless `claude -p` session whose `--plugin-dir` is the plugin root of the script that launched it; the launching scripts were this branch's copy at `1ee2e80`, run with `CLAUDE_PLUGIN_ROOT` unset (it takes precedence over the script's own location). Its questions were relayed to the owner instead of failing closed under `--non-interactive-fallback`, so Launch Pad, Supervisor and the drain ran exactly as in a normal run.
- **Config:** `.supervisor/config.json` carried `fix_floor: HIGH` and no `heal_review_scope` key, so the shipped default `shadow` is what ran.
- **Plugin loaded** (the lane stream's first `init` event): `{"session_id":"1d45e9f2-fa80-4e40-8314-f0a42c22278f","loomwright":[{"name":"loomwright","path":"<work>/ai-agent-manager-ac17-plugin/loomwright","source":"loomwright@inline","version":"17.24.0"}]}`. The Phase 4.5 records below are a second proof: the installed 17.23.1 has no `heal-review-scope.sh`, so only this branch's code could have written them.
- **Round ≥ 2:** yes. Phase 4.5 ran two rounds: round 1 fixed one BLOCKING finding (`8564841`) and dismissed three; round 2 found nothing and passed. No second item was needed.

Record file `.supervisor/heal-rounds/2026-11-02-dismissed-05-test-coverage-gaps.jsonl`, verbatim (here and below, the only edit is the local path prefix shown as `<work>/`):

```
{"kind":"round","run_id":"543cb78b-c11f-4f7b-bfa8-5b3a79616a39","iteration":1,"reviewed_sha":"a86ec11e30c4c32f8662181c437158fb1ceb1e32","pr":"https://github.com/vikashruhilgit/loomwright/pull/788","mode":"shadow","scope":"full","scope_files":27,"full_files":27,"scope_fallback":null,"would_suppress":[],"suppressed_repeat":0,"repeat_of_fixed":[]}
{"kind":"finding","run_id":"543cb78b-c11f-4f7b-bfa8-5b3a79616a39","iteration":1,"reviewed_sha":"a86ec11e30c4c32f8662181c437158fb1ceb1e32","pr":"https://github.com/vikashruhilgit/loomwright/pull/788","severity":"BLOCKING","outcome":"fixed","file":"loomwright/scripts/test-automate-helpers.d/07-rules-gate.sh","issue_category":"new","rule":"ad2912f07bd1","fix_commit":"8564841290be161bfdaf25858f6155f7be6b5c0e"}
{"kind":"finding","run_id":"543cb78b-c11f-4f7b-bfa8-5b3a79616a39","iteration":1,"reviewed_sha":"a86ec11e30c4c32f8662181c437158fb1ceb1e32","pr":"https://github.com/vikashruhilgit/loomwright/pull/788","severity":"MEDIUM","outcome":"dismissed","file":"loomwright/scripts/test-automate-helpers.sh","issue_category":"new","rule":"e2d9bffc71c8"}
{"kind":"finding","run_id":"543cb78b-c11f-4f7b-bfa8-5b3a79616a39","iteration":1,"reviewed_sha":"a86ec11e30c4c32f8662181c437158fb1ceb1e32","pr":"https://github.com/vikashruhilgit/loomwright/pull/788","severity":"MEDIUM","outcome":"dismissed","file":"loomwright/scripts/run-pin-mutations.sh","issue_category":"pre_existing","rule":"f48e53977267"}
{"kind":"finding","run_id":"543cb78b-c11f-4f7b-bfa8-5b3a79616a39","iteration":1,"reviewed_sha":"a86ec11e30c4c32f8662181c437158fb1ceb1e32","pr":"https://github.com/vikashruhilgit/loomwright/pull/788","severity":"LOW","outcome":"dismissed","file":"loomwright/scripts/test-host-mode.sh","issue_category":"new","rule":"f2711e64e580"}
{"kind":"round","run_id":"543cb78b-c11f-4f7b-bfa8-5b3a79616a39","iteration":2,"reviewed_sha":"8564841290be161bfdaf25858f6155f7be6b5c0e","pr":"https://github.com/vikashruhilgit/loomwright/pull/788","mode":"shadow","scope":"full","scope_files":2,"full_files":27,"scope_fallback":null,"would_scope":["docs/evidence/dismissed-05-helpers.md","docs/evidence/dismissed-05-trail-meta.md"],"would_suppress":[],"suppressed_repeat":0,"repeat_of_fixed":[]}
```

`heal-review-scope.sh --shadow-report` over that directory, verbatim:

```
heal-review-scope shadow report (read-only)
dir: .supervisor/heal-rounds
rounds: 1
findings_total: 0
outside_scope: 0
would_suppress: 0
repeat_of_fixed: 0
skipped_review_minutes_est: 0 (estimate: sum of review minutes x (1 - scope_files / full_files) over non-fallback rounds)
fallbacks: none
```

What it shows:

- Round 2's `would_scope` is exactly the two files the round-1 fix commit `8564841` changed (`git diff --name-only a86ec11 8564841` lists the same two evidence docs): 2 of the PR's 27 files. A `files` round 2 would have reviewed 2 files instead of 27 and, here, missed nothing, since the full round 2 found nothing anywhere.
- Shadow changed nothing: round 2's `scope` is `full`, `suppressed_repeat` is 0, and no fallback fired.
- One round, one item: this is a shape check on real data, not a promotion decision. `outside_scope` measures catch-rate risk only when a round ≥ 2 actually finds something.

**Defect found by this run, fixed on this branch:** both round records lack `review_started_at` / `review_ended_at`, so `skipped_review_minutes_est` read 0. The helper accepts both keys and its own tests feed them by hand, but step R of `skills/self-heal-advisory/SKILL.md` only said "the review's start and end times", never the key names, and no step took the start time. Step S now sets both around the reviewer spawn and step R names the keys; `test-heal-review-scope-seam.sh` (g) pins both, with mutation controls, and fails on the pre-fix file. The record lines above predate that fix and are kept verbatim.

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
{"kept":[<both round-2 issues>],"suppressed":[{"file":"c.txt","issue_category":"nit","rule":"aa22f8a70b80"}],"count":1,"repeat_of_fixed":[{"file":"a.sh","issue_category":"new","rule":"3f89b2557002"}]}
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
