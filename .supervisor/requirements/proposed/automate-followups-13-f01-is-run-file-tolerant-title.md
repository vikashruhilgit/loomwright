# `is_run_file` exact-match hides a run file whose title differs in whitespace / case / BOM

## Status: proposed

> **Origin.** Dismissed finding 1 from PR #288 (item 03, resume-glob / `is_run_file`), recovered by the item-13 triage
> sweep (run automate-2026-09-30-054439, classified 2026-10-01 against main@0dc0a5b, owner-approved as *draft*).

## Finding (verbatim summary)
> `is_run_file` matches only the exact `^# Automate Run:` form; a run file whose title differs in whitespace/case/BOM is
> hidden from RESUME (and `build-handoff.sh` reads the same predicate).

## Evidence on main
- `loomwright/scripts/automate-helpers.sh` `is_run_file()`: `grep -qE '^# Automate Run:' "$1"` — case-sensitive, no
  BOM / whitespace tolerance; last touched by ae8fe1a (the #288 commit itself).
- `loomwright/scripts/build-handoff.sh` reads the title leniently (`sed -nE 's/^#[[:space:]]*Automate Run:…'`), so the
  two readers disagree on what a run file is.

## Scope (recommendation)
- Make `is_run_file` tolerate a leading UTF-8 BOM and `#[[:space:]]*Automate Run:` (decide on case-insensitivity),
  keep the result sidecars excluded (they carry no title line).
- Fixture legs in `loomwright/scripts/test-automate-helpers.sh` (section D0b): BOM, extra space, lower-case, plus a
  sidecar control that must stay unlisted.
- Behavioural, low risk; one function + one test file.
