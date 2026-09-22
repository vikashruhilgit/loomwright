# 07 — `/verify` spec replay: derive a ticket AC's Playwright spec once, replay it deterministically, re-derive only on drift

## Status: pending

> **Origin (2026-09-22).** From the AI Radar review of Simular Sai's *learn-once → compile-to-code → replay*
> pattern (LLM for discovery, deterministic code for repeats, fall back to the model only when the recipe
> breaks). Loomwright already has HALF of this: `verify-run.sh impact prior-acs` replays PASS specs from OTHER
> runs as bounded `scope: impact` regression rows. The ticket's OWN acceptance criteria are re-derived by the
> QA Executor on every `/verify <ticket>` run. This item makes ticket-scope derivation replay-first. Every
> premise below was read from the file on 2026-09-22 at `main @ 8e54942` — re-check before starting; `main` moves.

## Problem
Re-running `/verify` on the same ticket (after a fix, after a heal round, before a merge) pays the full
AC → Playwright derivation cost again. `skills/verify-walkthrough/SKILL.md` §6 budgets "about 2–3 calls per AC"
of the 80-tool-call budget for spec authoring; nothing reuses a spec that a prior run already authored for the
identical AC text. `impact prior-acs` matches on `surfaces` intersection across ANY ticket and returns
`{run_id, ac_id, text, surfaces}` — it never matches on ticket or AC text and never copies a spec file, so it
cannot serve the ticket's own ACs. Consequence: the marginal cost of a re-verify equals the first verify, the
exact cost curve Sai's pattern flattens.

## Goal
On a re-run of `/verify <ticket>`, every AC whose text is unchanged since a prior run of the SAME ticket reuses
that run's spec verbatim (zero authoring calls); a replayed spec that fails for a NON-AC reason is re-derived
at most once; every replayed / authored / re-derived spec is labelled in the evidence file; verdict semantics,
the four-verdict taxonomy and `counts` are byte-unchanged.

## Verified premises (read 2026-09-22 at `8e54942`)
- `verify-run.sh preflight <ticket>` creates `.supervisor/verify/<run_id>/` (`run_dir=` at ~237/241), writes
  `acs.json` (SKILL §1: "the executor reads THAT file, never the ticket") and a `run_start` evidence line
  carrying `ticket_path` (~269) and the contract hash from `sha256_of` (`shasum -a 256` first, `sha256sum`
  fallback, empty ⇒ null — never a made-up value).
- SKILL §2: ONE spec per verifiable AC at `<run_dir>/specs/<ac_id>.spec.ts`, title `[<ac_id>] <AC text>` — the
  `[ACn]` prefix is the ingest key; an id outside `acs.json` is skipped `ac_id_unknown`.
- `walk <run_dir> [--specs-dir <dir>]` (default `specs`) reads `<run_dir>/<specs_dir>/*.spec.*`; no spec files
  at all ⇒ every remaining id `BLOCKED [no_spec]` (~705–800).
- `impact prior-acs` (617–680): scans SIBLING run dirs' `evidence.jsonl` (never self), latest-per-`ac_id` PASS
  lines whose `surfaces` intersect this run's `impact_surfaces`, most-recent-first by run_id (timestamp-prefixed
  ⇒ lexical = chronological), bounded by `--impact-limit` (default 10); zero siblings prints `[]`, exit 0.
- SKILL §Reconcile: "The stale run dir is NEVER reused and NEVER deleted". Replay COPIES a file OUT of a prior
  run dir; it never resumes, writes into, or deletes one.
- `validate-verify-evidence.py:78`: `EVENTS = ("run_start", "env", "auth", "ac", "issue", "pause", "resume",
  "run_end", "impact_surfaces")` — a CLOSED enum; a new event kind is rejected until the validator names it.
  The validator's exit status IS the gate consumed by `verify-helpers.sh evidence-append`.
- `docs/RESULT_SCHEMAS.md` §VERIFY_RESULT `schema_version: 1`, validated by `validate-qa-result.py` rules
  V1–V7 (V7 = `paused` ⇔ `pause_reason` pairing, added additively without a bump); `counts` is COPIED verbatim
  from the row `verify-run.sh finish` prints, never tallied by the agent.
- SKILL §6 budget: 80 tool calls; `--verify` runs no discovery; RED zone at 92% ⇒ stop authoring, `walk` what
  exists, `finish --status aborted`.
- `impact diff <run_dir>` already computes `git diff --name-only base_sha...head_sha` from `run_start`.
- `preflight-sync/SKILL.md` §2: never conclude "no churn" from an EMPTY pathspec-filtered `git log` alone — an
  empty result also means a broken pathspec. The same trap applies to any churn count this item records.
- D8 (`docs/SPIKES/FINAL_STATE_GOAL.md`): staleness is measured by churn over the anticipated file set, never
  elapsed time.
- `.supervisor/verify/` is fully gitignored (`.gitignore` `.supervisor/*` with no `verify/` negation) ⇒ a fresh
  clone / linked worktree / CI has zero prior runs. Same honest limit `prior-acs` already documents.
- Tests: `loomwright/scripts/test-verify-walkthrough.sh` and `test-verify-evidence.sh` exist and drive the REAL
  scripts over fabricated run dirs in a throwaway repo — extend those, do not add a parallel harness.
- `harness-port/04-not-verified-transport.md` adds `scope: impact, source: "not_verified"` rows to the same
  `/verify` evidence + summary surfaces — this item is sequenced AFTER it and must re-read `summary-build`.

## Design
1. **New mechanical subcommand `verify-run.sh spec-replay <run_dir> [--repo <dir>] [--no-replay]`** — runs
   after `preflight`, before any authoring. For each entry in `<run_dir>/acs.json`: find the MOST RECENT sibling
   run dir (same lexical-sort rule as `prior-acs`) whose `run_start.ticket_path` equals this run's, whose
   `acs.json` has an entry with the SAME `ac_id` AND the same `text_sha` (sha256 of the AC text, whitespace
   normalised, via the existing `sha256_of` helper on a temp file — never a new hashing routine), and which has
   an existing `specs/<ac_id>.spec.ts`. Copy that file byte-for-byte into `<run_dir>/specs/`. Append ONE
   evidence event per copy: `{event: "spec_replay", ac_id, source_run_id, text_sha, churn_files}` where
   `churn_files` = count of `git diff --name-only <source.head_sha>...<this.head_sha>` ∩ the source run's `ac`
   line `surfaces` for that id; empty or absent `surfaces` ⇒ `null` (NEVER `0` — the pathspec trap above).
   Prints `replayed=<n> total=<m>` LAST (the `preflight` "prints … LAST" convention). Zero siblings, no same-ticket
   sibling, `--no-replay` ⇒ `replayed=0 total=<m>`, nothing copied, exit 0. Match is **id AND text** — a renumbered
   but unchanged AC is re-derived (stated limit; rewriting `[ACn]` titles is out of scope).
2. **QA Executor `--verify` (SKILL §2 + `agents/qa-executor.md` mirror):** author specs ONLY for ids with no file
   under `specs/` after `spec-replay`. Replayed ACs cost 0 authoring calls; the §6 budget sentence gains the
   arithmetic ("about 2–3 calls per AUTHORED AC").
3. **Drift fallback (Sai's shape, bounded):** after `walk --scope ticket`, for each REPLAYED AC whose verdict is
   `BLOCKED` with a harness reason (`no_spec` cannot occur for a copied file; the relevant reasons are the walk's
   own non-assertion outcomes — read `walk_cmd`'s reason vocabulary at implementation and enumerate them in the
   SKILL, do not guess) the executor re-derives that ONE spec, re-runs `walk` for it, and appends
   `{event: "spec_rederived", ac_id, reason}`. **A replayed spec that FAILS on the AC assertion is a real FAIL and
   is NEVER re-derived** — re-deriving on a genuine failure is how a verifier learns to pass. At most one
   re-derivation per AC per run; `spec_rederived` count ≤ `spec_replay` count by construction.
4. **Summary + result block:** `finish`/`summary-build` gains one line `spec sources: replayed n · authored n ·
   re-derived n` derived from the evidence events (never tallied by the agent). `VERIFY_RESULT` gains OPTIONAL
   `spec_sources: {replayed, authored, rederived}` — additive, **no `schema_version` bump** (the V7 precedent);
   `validate-qa-result.py` rule V8: absent ⇒ accepted; present ⇒ object with exactly those three keys, each a
   non-negative integer, else reject. Copied from the printed line, same rule as `counts`.
5. **Freshness (D8):** `churn_files` is RECORDED, never a decision input — a replay with `churn_files > 0` still
   runs; the human sees the number in `summary.md`. `--no-replay` is the human's override (exposed as
   `/verify --no-replay`, forwarded to `spec-replay`).
6. **Validator:** `validate-verify-evidence.py` `EVENTS` gains `"spec_replay"` and `"spec_rederived"` with their
   required keys (`spec_replay`: `ac_id`, `source_run_id`, `text_sha` non-empty strings, `churn_files` int-or-null
   with an explicit presence check — memory `nullable-required-field-needs-presence-check`; `spec_rederived`:
   `ac_id`, `reason` non-empty strings).
7. **Docs:** `skills/verify-walkthrough/SKILL.md` §2 (replay-first + fallback), §6 (budget arithmetic),
   §Checklist (one new box: every replayed id has a `spec_replay` line); `commands/verify.md` (`--no-replay`);
   `docs/RESULT_SCHEMAS.md` §VERIFY_EVIDENCE + §VERIFY_RESULT; one CHANGELOG paragraph; version bump
   (`plugin.json` + `marketplace.json` + CHANGELOG only). Counts unchanged (agents/commands/skills/hooks).

## Acceptance criteria
- **AC1** — throwaway repo, one prior `completed` run of ticket T with 3 ACs: `spec-replay` on a new run of T
  copies all 3 specs, prints `replayed=3 total=3`, evidence has exactly 3 `spec_replay` lines, each with a
  `source_run_id` equal to the prior run id.
- **AC2** — AC #2's text changed by one character in the ticket: `replayed=2 total=3`; no `specs/AC2.spec.ts`.
- **AC3** — no sibling run at all: `replayed=0 total=3`, exit 0, no evidence line, `specs/` absent or empty.
- **AC4** — sibling run of a DIFFERENT `ticket_path` with byte-identical AC text: `replayed=0` (ticket-scoped).
- **AC5** — `--no-replay`: `replayed=0`, nothing copied, exit 0.
- **AC6** — the source run dir is byte-identical before and after (`diff -r`), i.e. replay never writes into a
  prior run.
- **AC7** — `churn_files` equals the intersection count when the source `ac` line has `surfaces`; is `null` when
  it has none; a validator-rejected `spec_replay` line (missing `source_run_id`, or `churn_files` KEY absent)
  is refused by `evidence-append` (non-zero, nothing appended).
- **AC8** — `VERIFY_RESULT` with `spec_sources` absent validates; with `{replayed: "3", …}` (string) is rejected
  by V8; with the three ints validates.
- **AC9 (mutation control)** — delete the `text_sha` comparison in `spec-replay` ⇒ AC2 fails (AC2 would be
  replayed); delete the `ticket_path` comparison ⇒ AC4 fails.
- **AC10** — `summary.md` carries the `spec sources:` line whose three numbers equal the evidence counts
  (asserted by the test over a fabricated evidence file with 2 replay + 1 rederived + 1 plain `ac` line).
- **AC11 (prose, gate-checked)** — SKILL §2 states replay-first, the never-re-derive-on-assertion-FAIL rule and
  the ≤1 re-derivation bound; `check-command-sync.sh` / doc-currency stay green; every new `path:line` citation
  in prose is pinned per CLAUDE.md §"Adding or Modifying Agents" step 5.

## Tests
Extend `test-verify-walkthrough.sh` (AC1–AC6, AC9, AC10) and `test-verify-evidence.sh` (AC7) and the
`validate-qa-result.py` test file (AC8). Fabricated prior run dirs need only `evidence.jsonl` (`run_start` +
`ac` lines), `acs.json` and `specs/*.spec.ts` — `walk`/Playwright are NOT required for these cases. Run the full
`loomwright/scripts/test-*.sh` loop AND root `scripts/test-*.sh` + `scripts/check-vendor-coupling.sh` before
pushing (memory `run-full-ci-suite-loop-before-push`).

## Honest limits (state these in the SKILL, do not soften)
- A replayed spec that still PASSES may no longer exercise the AC if the UI moved in a way the spec never
  touches — `churn_files` surfaces this for a human; it does not decide.
- Zero benefit on a fresh clone / worktree / CI (gitignored store) — identical to `prior-acs`.
- Renumbered-but-unchanged ACs are re-derived.
- The saving is MEASURED, not asserted: before stamping this item done, record the first 5 real re-runs'
  `spec sources:` lines in a `## Result` section here (D11 — no metric claimed without a row).

## Dependencies / order
After `harness-port/04` (shared `/verify` evidence + summary surfaces). Independent of everything else in the
sequence backlog; placed LAST there. No new agent / command / skill / hook; no merge path; `heal_decision`
untouched; nothing gating.
