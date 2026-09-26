# 08 — Executable rule candidates: `/dreaming` proposes the `check`, a human accepts it, Phase 4.5 replays accepted checks behind a content-keyed user-scope stamp


> **Origin (2026-09-22).** From the AI Radar review of Simular Sai (*LLM for discovery, deterministic code for
> repeats*), applied to REVIEW FINDINGS rather than tasks: a convention discovered by a reviewer once should run
> as a check for ~0 tokens ever after. Loomwright already records findings → harvests conventions → commits rules,
> and the chain ends in PROSE: `.agent/rules/` holds 3 rules, 0 with a `check`; `harvest-conventions.sh` never
> synthesises one by design; `rules-check.sh` is human-invoked only and reached by no runtime seam. This is
> `NORTH_STAR_DIRECTION.md` Bet 6 Tier 1 ("a failing lint rule is the strongest enforcement"), never reached.
> Every premise below was read on 2026-09-22 at `main @ 8e54942` — re-check before starting; `main` moves.

## Problem
A convention that could be a grep is enforced by an LLM review every time — and only when the reviewer happens
to look. The worker receives house rules as an ADVISORY prose paste (`agents/supervisor.md` ~741 via
`async-orchestration/SKILL.md` spawn contract, "NEVER-gating"); Phase 4.5 runs `run-ground-truth.sh` for a brief's
`cmd:` bullets (`self-heal-advisory/SKILL.md` ~390–403) but never `rules-check.sh`; `/rules check --confirm`
(a human typing `y` at `[y/N]`) is the only executor in the plugin. Result after months of ledger: three rules,
no checks, and every recurrence of a mechanizable finding costs a review turn it may not get.

## Goal
(a) The harvester emits a `check_candidate` STRING as proposal DATA for findings whose evidence is grep-shaped —
never written into `check`, never executed; (b) acceptance is the existing `add-rule.sh --check … --confirm`
path, unchanged; (c) Phase 4.5 replays `must` rules' checks ONLY when they match a content-keyed stamp a human
wrote by running `/rules check --confirm` once, recorded in USER scope — and reports the outcome as an ADVISORY
line that never changes `heal_decision`; (d) without a matching stamp it records `rules_check: unstamped` (n
must-rules with checks not executed) and nothing else happens.

## Verified premises (read 2026-09-22 at `8e54942`)
- `.agent/rules/documentation.json`: 1 rule; `process.json`: 2 rules; all `check: null` (jq count).
- `loomwright/scripts/harvest-conventions.sh:36–49`: "RULES ARE DATA, NEVER EXECUTED. `check` is left `null` on
  every proposal: this script does not pass `--check` at all and NEVER synthesises a shell command into a
  rule"; the printed proposal line (~1129) reads `check: null (AC9b — no obviously mechanical check; this
  harvester never synthesises shell into check)`. It dedupes proposals against the live store (`feb1429`).
- `loomwright/scripts/add-rule.sh`: accepts `--check <string>` (~410: "check is either a string (when --check
  supplied) or null"), `--confirm`, `--supersedes`, `--applies-to`, `--retract`; the stored object is
  `{id, category, statement, enforcement, check, supersedes, applies_to, provenance: {source, added}}` (~568–584).
  **No hash of the check is recorded anywhere.**
- `loomwright/scripts/rules-check.sh` header: "the SOLE EXECUTION path … ONLY rules where enforcement == must AND
  check is a non-null STRING … each selected check runs from the REPO ROOT via `bash -c`"; `--no-cmd` records
  `[SKIP] … (cmd execution disabled)` and **WINS OVER `--confirm`**; the confirmation prompt is
  `Run the must-rule check commands from <root> ? [y/N]` (~122); prints `Checks passed: n/m`; `jq` missing or no
  rule files ⇒ `Checks passed: 0/0`, fail-safe.
- No agent, skill or command invokes `rules-check.sh` at runtime — `grep -rn rules-check.sh` over
  `agents/ skills/ commands/` hits only `skills/rules/SKILL.md`, `commands/rules.md`, `commands/agent-help.md`
  (§Purpose prose) and `commands/setup.md` (honest-limits prose).
- `self-heal-advisory/SKILL.md:398` `NO_CMD_FLAG = (NON_INTERACTIVE == true) ? "--no-cmd" : ""` →
  `run-ground-truth.sh --brief <brief> $NO_CMD_FLAG` (~403). `red-team-hardening/05` replaces that condition with
  a content-keyed brief stamp (`exec-acceptance-hash.sh <brief>`), `--no-cmd` wins over a valid stamp, a
  machine-authored brief never carries the stamp.
- `red-team-hardening/00` decision **R2**: opt-ins are process-env or user-scope only — never a key in a file the
  repo or the model can write. `.agent/rules/*.json` IS repo-committed and model-writable (a worker can edit it
  inside a PR), so a `check` string is untrusted shell BY CONSTRUCTION. That is why execution at a seam is keyed
  to a human act recorded OUTSIDE the repo, never to the rule's own `provenance` field.
- `commands/dreaming.md`: read-only-until-Accept; the PR path carries ONLY `.agent/rules/*.json` objects authored
  by the store's confirm-gated sole writer (`add-rule.sh`).
- `twin-loop/05` (dreaming triage → rules PR) is `brief-shipped`; the harvester itself is on `main`
  (last `a5ebb8a`). This item edits the SHIPPED harvester; if 05's PR lands first, rebase onto it.
- The harvester's proposal quality is bounded by the ledger's evidence field (memory
  `invention-queue-proposal-triage`) — a candidate is only as good as the literal tokens the findings carry.
- CLAUDE.md §"Failure-Mode Invariants": two review lenses, no new pass; `heal_decision` never changed by an
  advisory; every `type: command` hook is fail-safe — **this item adds NO hook**.

## Design
1. **Harvester (`harvest-conventions.sh`) — candidate as data.** When ≥ 3 supporting findings of one proposal
   carry the same literal token or path in their evidence, emit `check_candidate: <string>` in the human-facing
   proposal block AND as a `check_candidate` key in the proposal JSON. `check` stays `null` (the AC9b line is
   kept, reworded to say a candidate MAY be shown beside it). The candidate is built from a FIXED template
   allowlist — `! grep -rnE '<pattern>' <paths>` (absence) and `test "$(grep -rlE '<pattern>' <paths> | wc -l)"
   -le <N>` (bound) — where finding text appears ONLY inside the single-quoted pattern; any finding text
   containing `'`, `$(`, backtick, `;`, `|`, `&` or a newline yields NO candidate (omitted, not escaped — the
   harvester must not become a shell-quoting engine). Paths come from the finding's `changed_paths` / file
   fields, never from free text.
2. **`/dreaming` Accept — two buttons, not one.** The Accept step shows the candidate VERBATIM and offers
   "Accept rule" (today's call, `check` null) and "Accept rule WITH check" (calls the unchanged
   `add-rule.sh … --check "<candidate>" --confirm`). Accepting a rule never implies accepting its check.
   `add-rule.sh` is byte-unchanged.
3. **`rules-check.sh` — the stamp.** The existing human path (`--confirm`, answered `y`) additionally writes a
   stamp `{repo_root, hash, ts}` in USER scope, where `hash` = sha256 over the sorted `id\tcheck\n` lines of the
   must-rules it selected (the same selection jq, so stamp and execution can never disagree on the set). New
   flag `--if-stamped` (non-interactive): compute the live hash the same way, compare to the stamp for this
   `repo_root`; equal ⇒ run the checks with no prompt; unequal or absent ⇒ print `[SKIP] all (unstamped)` and
   `Checks passed: 0/0`, exit 0. `--no-cmd` still wins over everything. **User-scope location = whichever path
   `red-team-hardening/02` establishes for user-scope opt-ins** — read that item's shipped result at
   implementation time; do not invent a second location.
4. **Phase 4.5 seam (`self-heal-advisory/SKILL.md`, beside the ground-truth step, Part 1 advisory machinery):**
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/rules-check.sh --if-stamped $NO_CMD_FLAG`, capture the summary line, emit
   ONE advisory line `rules_check: passed n/m | unstamped | cmd_disabled` into the Phase 4.5 report and the PR
   body's advisory section. A failed check is SURFACED there; it is not a new review pass, does not enter the
   review-and-fix loop, and never changes `heal_decision` (D4, CLAUDE.md invariants).
5. **Worker seam: NONE.** Linked worktrees cannot see `.supervisor/`; running model-writable shell inside a
   worker is exactly the trap R2 names. The advisory paste is unchanged.
6. **Docs:** `commands/dreaming.md` + `commands/rules.md` + `skills/rules/SKILL.md` §8 (stamp semantics, the
   R2 reasoning, "a rule edit invalidates the stamp — re-run `/rules check --confirm`"); `self-heal-advisory`
   advisory-line row; `docs/RESULT_SCHEMAS.md` only if a result block gains a field (none planned); CHANGELOG
   paragraph; version bump (`plugin.json` + `marketplace.json` + CHANGELOG only). Counts unchanged.

## Acceptance criteria
- **AC1** — fixture ledger with 3 findings sharing a literal path under one proposal: the proposal prints
  `check_candidate:` and the JSON carries it; `check` is `null` in both.
- **AC2** — fixture whose shared token contains `'` (and a second containing `$(`): NO candidate, proposal
  otherwise identical.
- **AC3 (mutation control, non-execution)** — a fixture token `; touch <tmpdir>/pwned`: the candidate is shown
  as text (or omitted under AC2's rule) and `<tmpdir>/pwned` does NOT exist after the harvest run.
- **AC4** — `add-rule.sh` diff against `main` is empty; accept-with-check produces a rule whose `check` is the
  candidate string; accept-without-check produces `check: null`.
- **AC5** — `rules-check.sh --confirm` with `y` piped writes the stamp (user scope) and the stamp's hash equals
  an independently computed sha256 of the sorted `id\tcheck` lines; `--if-stamped` then runs without prompting
  and prints `Checks passed: n/m` with n/m > 0/0.
- **AC6** — edit one accepted `check` by one byte: `--if-stamped` ⇒ `[SKIP] all (unstamped)`, `Checks passed:
  0/0`, exit 0; `--no-cmd --if-stamped` ⇒ `[SKIP] … (cmd execution disabled)` regardless of stamp.
- **AC7** — after AC5, `git status --porcelain` in the repo shows NO new or modified file (the stamp never lands
  under the repo root).
- **AC8 (mutation control)** — delete the hash comparison in `--if-stamped` ⇒ AC6's first case fails.
- **AC9 (prose, state-traced)** — `self-heal-advisory` shows the advisory line in all three states and the
  `heal_decision` text is byte-identical on a failing check (memory `feedback_prompt_is_program_state_trace`:
  trace a run with `passed 1/2`, one with `unstamped`, one with `cmd_disabled`).
- **AC10** — `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` still resolves to
  exactly the five surfaces CLAUDE.md enumerates; `hooks.json` byte-unchanged; agent/command/skill counts
  unchanged.

## Tests
Extend `test-harvest-conventions.sh` (AC1–AC3), `test-rules-check.sh` (AC5–AC8, with `HOME`/the user-scope
path pointed at a temp dir), `test-add-rule.sh` (AC4 — assert no diff plus the two accept shapes). Full
`loomwright/scripts/test-*.sh` loop AND root `scripts/test-*.sh` + `scripts/check-vendor-coupling.sh` before
pushing (a literal `${CLAUDE_PLUGIN_ROOT}` in a core COMMENT trips the ratchet — reword neutrally).

## Honest limits (state these in the SKILL, do not soften)
- Only grep-shaped conventions become checks; anything needing semantics stays an LLM review.
- The stamp is per-user per-machine (R2): CI and every teammate run `unstamped` until each human confirms once.
  That is the design, not a gap — a repo-carried stamp is a model-writable stamp.
- "The check caught it" vs "the reviewer caught it" is attributable only when the advisory line fires on a diff
  the reviewer ALSO flagged; record both, infer nothing. Before stamping this item done, record 10 Phase 4.5 runs'
  `rules_check:` lines in a `## Result` section here (D11).

## Dependencies / order
After `red-team-hardening/05` (stamp semantics + the `NO_CMD_FLAG` condition fix this seam reuses) and
`red-team-hardening/02` (the user-scope location). Sequenced in
`.supervisor/requirements/_BACKLOG-hardening-sequence-2026-09-22.md` after `harness-port/07`. No new agent /
command / skill / hook; no merge path; `heal_decision` untouched; nothing gating.

## Status: done (PR #267, merge 91c117e)
- **Completed:** 2026-09-26T02:15:12Z
- **Brief:** .supervisor/jobs/done/2026-09-25-executable-rule-candidates.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/267
- **Follow-up (open, not blocking):** D11 observation — record the `rules_check:` line from 10 real Phase 4.5 runs in a `