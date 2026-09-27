# 10 — Rules reach EVERY review: the Code Reviewer reads the store itself, so `/code-reviewer` and `/review-pr` stop being rule-blind

## Status: pending

> **Origin (2026-09-27).** Owner question after walking items 05–09: *"does code review also audit the rules?
> like /code-review?"* Answer, verified by grep: only the Phase 4.5 review sees the store, and only because
> Supervisor pastes it into the reviewer's spawn prompt. Every review that runs OUTSIDE the Supervisor loop is
> blind to it — standalone `/code-reviewer`, `/review-pr` (including the `/automate` owned
> `--until-mergeable` drain), and the `claude-review` CI bot. Items 05–09 add rules to planning, the worker,
> Phase 4.5 health, merge and CI; none of them touches the standalone reviewer.

## Problem
The house-rules seam is wired at the **caller**, not at the **reviewer**:

1. **Phase 4.5 works only because it injects.** `skills/self-heal-advisory/SKILL.md` §"House-rules advisory
   (committed convention enrichment)" runs `read-rules.sh <touched files…>` and threads the output into the
   `code-reviewer` Task prompt as the **HOUSE-RULES ADVISORY** line (Part 2 §"Review-and-fix loop").
2. **No other caller injects, and the agent never reads.** `agents/code-reviewer.md` has 0 references to the
   store. Its Context Setup already reads two advisory sources on its own — `REVIEW.md` (step 2) and
   `read-project-memory.sh` (step 3) — but not `read-rules.sh`.
3. **So the same agent reviews with different knowledge depending on who spawned it.**
   - `/code-reviewer` is a thin wrapper around the agent; nothing injects.
   - `skills/review-heal/SKILL.md` Step 2's reviewer `Task(...)` prompt carries no rules line. That loop is
     `/review-pr`'s AND the `/automate` owned drain's — so on an `/automate` item the rules are seen once at
     Phase 4.5 and then dropped for every drain round that follows.

## Goal
Every `loomwright:code-reviewer` run sees the house rules that apply to the files it is reviewing, whoever
spawned it — with no double injection on the Phase 4.5 path, and with the rules staying advisory exactly as
they are at Phase 4.5 today.

## Scope (recommendation, not pre-decided)

**(a) Put the read in the agent, not in each caller.** Add one Context Setup step to `agents/code-reviewer.md`,
immediately after "Determine Review Scope" (the reader needs the scope's path set):
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-rules.sh" <review-scope paths…>` — paths as **command-line
ARGUMENTS, never stdin** (the no-hang shape every other seam uses). Fail-safe: the reader always exits 0 and
self-gates on `.agent/rules/*.json`; empty output ⇒ no enrichment, no placeholder line.
Why the agent and not the callers: one change covers `/code-reviewer`, `/review-pr`, the `/automate` drain,
and any future caller; fixing callers one by one is the drift pattern the store's own
`process-when-one-surface-restates…` rule names.

**(b) Deduplicate against Phase 4.5.** When the spawn prompt already carries a **HOUSE-RULES ADVISORY** line,
the agent uses it and skips its own read. The injected line wins because Phase 4.5 computed it on the
integrated diff scope, which may be wider than the agent would infer.

**(c) Same advisory contract as Phase 4.5, restated by pointer, not copied.** The rules bias the review lens;
a clear violation of an applicable rule may become an ordinary finding under the existing severity rules. They
never add a new decision state, never change the `CODE_REVIEW_RESULT` schema, and are subordinate to CLAUDE.md
and `REVIEW.md`. Cite `skills/self-heal-advisory/SKILL.md` §"House-rules advisory" for the contract instead of
restating it (token budget, see Risks).

**(d) The reader only.** The agent must never invoke `rules-check.sh` or `audit-rules.sh`, and never execute a
rule's `check` (the reader emits it as DATA). Executing checks stays with Phase 4.5's `--if-stamped` replay
(and items 06/07). The reviewer is read-only by frontmatter (`disallowedTools: Write, Edit, …`), and this item
must not change that.

**(e) Extend the seam guard deliberately.** `loomwright/scripts/test-rules-seams.sh` pins exactly FOUR seams.
Add `agents/code-reviewer.md` as a fifth ARGS-BEARING seam so assertions (A)–(D) cover it — including (B)'s
zero-tolerance rule on `rules-check.sh` (no `--if-stamped` exception for this surface) and (D)'s path-argument
placeholder. Update the header comment's count and list in the same change.

## Acceptance criteria
- [ ] `agents/code-reviewer.md` Context Setup invokes `read-rules.sh` with a path-argument placeholder, after
      the scope is determined; `test-rules-seams.sh` (D) passes on it and FAILS when the placeholder is removed
      (mutation control).
- [ ] The agent prompt states the dedupe rule: an injected **HOUSE-RULES ADVISORY** line is used as-is and the
      agent does not read again.
- [ ] `agents/code-reviewer.md` never names `rules-check.sh` or `audit-rules.sh` in an invocation shape —
      `test-rules-seams.sh` (B) with no exception for this surface.
- [ ] No output change on an empty store: the reader emits nothing, and the prompt forbids a "no house rules"
      placeholder (same wording rule as Phase 4.5).
- [ ] `CODE_REVIEW_RESULT` schema unchanged; `check-contract-parity.sh` green.
- [ ] `commands/code-reviewer.md` "What This Does" list mentions the house-rules read, and
      `check-command-sync.sh` stays green (thin-wrapper contract: no policy restated there).
- [ ] `commands/rules.md` / `skills/rules/SKILL.md` wherever they enumerate the advisory seams (worker /
      Phase 4.5 / SessionStart nudge) now name the reviewer too — grep the OLD enumeration repo-wide, per
      CLAUDE.md.
- [ ] `check-token-budget.sh` green for `code-reviewer`; if a raise is needed, re-measure and update BOTH
      `docs/prompt-token-budgets.json` and the mirror row in `ARCHITECTURE_CONTRACTS.md` §"Prompt Token
      Budgets".
- [ ] The full test loop is green — BOTH `loomwright/scripts/test-*.sh` AND root `scripts/test-*.sh` plus
      `scripts/check-vendor-coupling.sh`.

## Out of scope
- The `claude-review` CI bot (`.github/workflows/claude-code-review.yml`). Its `--allowed-tools` allowlist is
  deliberately narrow and widening it is item 02's question; running rules in CI is item 08's.
- Claude Code's built-in `/code-review`. It is not a Loomwright surface.
- Making a rule violation block (item 07) or running any check from the reviewer (items 06/07).
- Changing `read-rules.sh`'s routing semantics or the rule schema.

## Risks
- **Token budget is the tight constraint.** `code-reviewer` measures **24491 against a 25131 budget — 640
  tokens of headroom** (`scripts/check-token-budget.sh`, 2026-09-27). Keep the new step to a few lines and
  point at `self-heal-advisory/SKILL.md` for the contract. Expect to need a small, re-measured raise; do not
  pad the prose to explain the design.
- **Scope inference differs by caller.** Standalone `/code-reviewer` scopes from its file arguments or the
  recent git diff; the review-heal loop scopes from `git diff <base>...HEAD`. Both are valid inputs to the
  reader. An empty path set fails OPEN (repo-wide), which is the safe direction.
- **Double read on Phase 4.5 if (b) is skipped.** Harmless (same data), but it spends a tool call and can make
  the reviewer see two slightly different rule sets. (b) exists to prevent that.

## Verified premises (read at `main @ ebd4de7`, 2026-09-27)
- `grep -ciE 'read-rules|rules-check|audit-rules|\.agent/rules|house.rules'` ⇒ **0** on
  `agents/code-reviewer.md`, `commands/code-reviewer.md`, `agents/review-pr.md`, `skills/review-heal/SKILL.md`,
  and `.github/workflows/claude-code-review.yml`.
- `skills/review-heal/SKILL.md` Step 2: the reviewer spawn is
  `Task(subagent_type: "loomwright:code-reviewer", prompt: "Review the PR-branch diff (git diff <base>...HEAD) …")`
  with no house-rules line.
- `skills/self-heal-advisory/SKILL.md` §"House-rules advisory (committed convention enrichment)": reader called
  with touched paths as args, output threaded into the reviewer prompt only when non-empty, "NEVER changes
  `heal_decision`", subordinate to CLAUDE.md; Part 2 carries the **HOUSE-RULES ADVISORY** prompt line.
- `agents/code-reviewer.md` §"Context Setup (REQUIRED)": step 2 loads optional `REVIEW.md`, step 3 runs
  `read-project-memory.sh` (advisory, fail-safe, subordinate to CLAUDE.md), step 4 "Determine Review Scope".
- `agents/code-reviewer.md` frontmatter: `disallowedTools: Write, Edit, NotebookEdit, Task, TaskOutput,
  WebSearch, WebFetch` (Bash stays allowed, so the reader call needs no tool change).
- `commands/code-reviewer.md`: thin wrapper — "The canonical prompt lives in `loomwright/agents/code-reviewer.md`".
- `loomwright/scripts/test-rules-seams.sh`: `SEAMS=(agents/supervisor.md agents/execute-manager.md
  skills/self-heal-advisory/SKILL.md scripts/session-resume.sh)`; assertions (A)–(D) as described in its header.
