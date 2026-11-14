# In Claude Code: one command, a separate verifier, and one text-only PR comment

## Status: pending

> Phase 1, item 06 of `qa-split/00-plan.md` (rev 2, approved 2026-11-12).
> Decisions: D8 (separate verifier context), D13 (one comment, text evidence only; rev 3: no raw page
> values by default), D6 rev 3 (revisions shown), P4/P5, N8.
> No hooks in the MVP (red-team W6): plan integrity lives in the CLI (item 04).

## Why

The verifier must not be the agent that wrote the code. And the PR comment must show the work without
leaking it: traces and screenshots carry cookies and PII, and the atelier repo is public.

## Design

- **`/selvedge:verify [criteria source]`** (command): resolves criteria (PR number, file, or pasted text),
  then spawns the verifier subagent and reports the verdict table.
- **Verifier subagent** (`selvedge/agents/verifier.md`): tools limited to Bash and Read. It runs
  `selvedge criteria …`, `selvedge snapshot …`, writes `plan.json`, runs `plan --validate` and
  `plan --freeze`, then `run` and `verdict`. Its prompt forbids editing `plan.json` after freezing (the CLI
  enforces it anyway) and forbids reading `~/.local/state/selvedge/`. Agent frontmatter declares its token
  budget.
- **SKILL.md** (`selvedge/skills/verify/SKILL.md`): the same workflow for any agent host, CLI-only.
- **`selvedge comment <run-dir> --pr <n>`:** posts or updates ONE comment, found by a hidden marker
  `<!-- selvedge:verdict -->`. Body: a one-line summary (`3 PASS · 1 FAIL · 1 NOT_VERIFIABLE`), then a
  folded `<details>` table per criterion: criterion, interpretation, unverified assumptions (material ones
  marked), steps taken (types + locators), expected value (written by the plan, not read from the page),
  matched yes/no, verdict, `evidence_class`, reason/unblock hint for BLOCKED/NOT_VERIFIABLE, plan sha256
  (short) and revision. **No links to traces or screenshots, no request bodies, no headers.** Evidence
  stays in `.selvedge/` locally.
- **Raw page values are not published by default.** Names, addresses and arbitrary text can't be reliably
  masked, so `read_value` stays in local `verdict.json`. Opt-in per repo (`"comment": {"read_values":
  true}` in `selvedge.json`, read from the base branch) applies configurable redaction patterns (defaults:
  emails, digit runs of 6+, URL query strings, long base64/hex tokens) before posting. `selvedge comment`
  refuses the opt-in on a public repo (`gh repo view --json visibility`) unless `--allow-public-values`.
- **Revisions are visible:** when `prior_revisions` is non-empty the criterion's verdict cell reads e.g.
  `FAIL on plan 1 → PASS on plan 2`, never a bare `PASS`, and the summary line counts it under its own
  label (`1 PASS after revision`).
- Comment posting is explicit (the command asks before posting in an interactive session; `--yes` for
  scripted use). Never on by default (N2).

## Acceptance criteria

- Two runs on the same PR leave exactly one selvedge comment, updated (test with a `gh` shim).
- The comment body contains no `http(s)://` link to evidence files, no `Cookie`/`Authorization` text, no
  `{{NAME}}`-resolved value (test).
- With the default config, a page value read by a criterion (a fixture email and name) appears nowhere in
  the comment body (test).
- With `read_values: true` on a repo the `gh` shim reports as public → refused without
  `--allow-public-values`.
- A criterion with `prior_revisions: [FAIL]` and a current PASS renders `FAIL on plan 1 → PASS on plan 2`.
- The verifier subagent's frontmatter tools are exactly Bash and Read.
- `/selvedge:verify` on the item 04 fixture app produces the same `verdict.json` as running the CLI by hand
  with the same frozen plan.

## Depends on

05

## Touches

- `selvedge/commands/verify.md`, `selvedge/agents/verifier.md`, `selvedge/skills/verify/SKILL.md`
- `selvedge/lib/comment*`, `selvedge/schemas/selvedge-config.schema.json` (adds `comment.read_values`), `selvedge/tests/**`
