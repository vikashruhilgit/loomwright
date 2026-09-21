# 07 — Provider-pluggable review lens (owner ask: use Claude + Codex/GPT/Grok/Gemini across steps)

## Problem
D4 fixes two review lenses and says every additional pass must state what the earlier one could not see.
Today both lenses are Claude (Phase 4.5 + `claude-review` CI). A second MODEL FAMILY is the cleanest
"different information" there is — different training, different blind spots (Orca's own rationale:
"different agents make different mistakes… where they split, you've found the hard part"). The
multi-voter verification voter (`--multi-voter-heal`, opt-in, never ran) already has the right shape —
an independent vote on the same diff, refuted findings logged not fixed, gate shape unchanged — but it
can only spawn a Claude subagent.

## Mechanism (verified 2026-09-11)
Claude Code subagents cannot run a non-Anthropic model (`model:` frontmatter = Claude tiers). The ONLY
route is shelling out to the vendor's CLI in print mode, exactly as `dispatch-pr-review.sh` shells out to
`claude -p`. On this machine: `cursor-agent -p --output-format json --model gpt-5|sonnet-4|…` is installed
and routes to non-Anthropic models; `codex exec`, `gemini -p`, `grok` are NOT installed (flags must be
verified from `--help` when they are — memory `verify-invocation-shapes-from-the-file`).
**Safety fact:** cursor-agent print mode "has access to all tools, including write and bash" and offers
no read-only or sandbox switch. It DOES offer `-f, --force  "Force allow commands unless explicitly denied"`
(verified from `--help` 2026-09-12), which implies print mode may DENY shell commands unless forced —
**probe this first** (prompt it to `touch` a file in a throwaway worktree without `-f`; record the result
here). If commands are denied by default, that is the read-only lever and §2 is the backstop; if not, §2
is the only lever and its limit below applies.

## Probe result — `-f`/deny-by-default (2026-09-18, DEFERRED; RESOLVED 2026-09-20)
Attempted per Mechanism's "probe this first": `cursor-agent status` → `Not logged in` (also checked
`env | grep -i cursor` and `~/.cursor/{cli-config,agent-cli-state}.json` — no stored CLI auth token; the
`CURSOR_AGENT=1` env var and conversation/request IDs present are unrelated artifacts, not credentials).
The probe requires an authenticated session to observe real command-allow/deny behavior; a login prompt was
surfaced to the operator (Vikash), who declined to authenticate during this automated run. Standing decision
(Vikash, 2026-09-18): **skip the live probe, document as follow-up** — do not fabricate or force it. This
item proceeds on the conservative assumption from Mechanism §Safety fact (no confirmed read-only lever) —
§2's throwaway-worktree-plus-mutation-check is therefore load-bearing, not a backstop, until the probe runs.

**Follow-up run — 2026-09-20, RESOLVED (operator-run/08).** Vikash authenticated `cursor-agent` mid-run
(`cursor-agent status` → `Logged in as <redacted e-mail>`, verified independently, not taken on the
relayed claim alone). Probe executed exactly as specified above, in a throwaway scratch dir outside any
repo (`mktemp -d`), never a real worktree:
- **`cursor-agent -p --output-format json --workspace <dir> "touch probe.txt"` (no `-f`, real `$HOME`):**
  exit 1, `probe.txt` NOT created, stderr `⚠ Workspace Trust Required … Pass --trust, --yolo, or -f if you
  trust this directory`. **Deny-by-default is REAL and confirmed** — the CLI refuses ANY action, including
  a trivial file write, without an explicit trust override.
- **`cursor-agent -p --output-format json -f --workspace <dir> "touch probe.txt"` (real `$HOME`):** exit 0,
  `probe.txt` created, well-formed envelope `{"type":"result","subtype":"success","is_error":false,
  "result":"Created \`probe.txt\` in the workspace.","session_id":"…","usage":{"inputTokens":…,
  "outputTokens":…,"cacheReadTokens":…,"cacheWriteTokens":…}}`. **Confirms `provider-cursor.sh`'s
  `.result`-field guess was correct**, and reveals the real `usage` object shape (token counts, not $ —
  D11 cost-honesty's `cost: "unknown"` stays correct; nothing here reports a dollar figure).
- **New finding, NOT anticipated by this item: HOME-scrub breaks auth.** With `env -i … HOME=<scrubbed>`
  (`lens-run.sh`'s own `PROVIDER_HOME_SCRUB=1` mitigation), BOTH calls above instead fail with `Error:
  Authentication required. Please run 'agent login' first…` — `cursor-agent`'s credential is a file under
  the real `$HOME`, not an env var, so the scrub that protects other secrets also strips its own auth.
  **Net effect: as shipped, the cursor provider degrades to `lens_unparseable` on EVERY real invocation
  today, for either of two independent reasons (scrubbed HOME → no auth; real HOME but no `-f` → trust
  prompt refusal) — it has never produced a real `ok` result in production, only against the AC's stub.**
  This is a genuine gap in the merged adapter, not a hypothetical; see "Post-merge findings" below for the
  fix options. Not resolved in-place here — 07 is `done`/merged; recorded as a citable fact for any future
  item that touches `provider-cursor.sh` or the HOME-scrub design.

## Post-merge findings (operator-run/08, 2026-09-20) — cross-family eval on THIS PR's own diff
As part of 08's D11 eval design, a real `cursor:gpt-5` review lens was run (once auth existed) against
this item's own diff (`git diff 2c63cad^1..2c63cad^2`, the PR #239 merge), composed with the same
`Role: review … --- DIFF --- … --- OUTPUT CONTRACT ---` template `lens-run.sh` uses, in an independent
throwaway sandbox clone (temp branch ref workaround for `file://` shallow-fetch-by-SHA, deleted after) —
manually, with `-f` AND real `$HOME` together (both barriers dropped at once, a materially different
exposure than the shipped adapter's design; done only after explicit operator sign-off on that specific
tradeoff). It raised 5 findings; two are independently verified as REAL, confirmed defects in this item's
own merged code (grep-verified against the actual files, not taken on the CLI's word):
- **HIGH, confirmed:** `skills/self-heal-advisory/SKILL.md:790`, `skills/supervisor-config/SKILL.md:73`,
  and `commands/supervisor.md:72` all invoked `loomwright/scripts/adapters/providers/lens-run.sh` — the
  dev-checkout-relative path — instead of `${CLAUDE_PLUGIN_ROOT}/scripts/adapters/providers/lens-run.sh`,
  the canonical runtime path this repo's own CLAUDE.md already mandates ("Repo path vs. runtime path").
  **The entire `--voter-provider` wiring was silently non-functional on any marketplace install.** Neither
  the primary code-reviewer nor the Claude red-team-reviewer voter caught this in the original PR #239
  review — a genuine "different agents, different blind spots" data point for D11. **Fixed** in
  operator-run/08's own PR (mechanical 3-line path correction, no behavior change to `lens-run.sh` itself).
- **HIGH, confirmed:** `lens-run.sh:365`'s `git fetch --depth 1 --no-tags --quiet origin "$COMMIT"` passes
  a caller-supplied `--commit` value with no SHA-format validation and no `--` separator before it — a
  value starting with `-` (e.g. `--upload-pack=…`) is interpreted as a fetch option, not a revision. Today
  the only caller (`self-heal-advisory`) passes a trusted internal SHA, so this is a defense-in-depth gap,
  not an active exploit path — but `lens-run.sh` is a general-purpose adapter and documents `--commit` as
  caller-supplied. **NOT fixed here** — recorded as a follow-up; a real fix (resolve+validate `^[0-9a-f]
  {40}$`/`{64}$` before fetching, add `--` before the revision) touches the safety-critical sandbox-setup
  path and deserves its own reviewed change, not a bundle-in.
- **BLOCKING claim, NOT corroborated:** the lens also claimed `.git/FETCH_HEAD` in the sandbox retains the
  parent `file://<SRC_ROOT>` URL after `git remote remove origin`, and that `git push file://<parent>
  HEAD:refs/heads/<attacker>` "empirically succeeds" from inside the sandbox. **The FETCH_HEAD leak itself
  is real** — independently confirmed by reading the sandbox's `.git/FETCH_HEAD` after the run, it does
  contain the real parent path. **The "empirically succeeds" push claim is NOT corroborated** — a full
  audit of the real repo immediately after the run (`git remote -v`, `git show-ref`, `git branch -a`,
  `git reflog show HEAD`, `git fsck`, `git status`) found no new remote, no attacker ref, no working-tree
  change. Either the CLI reasoned about the exploit without executing it, or attempted it and it silently
  failed; either way, **an agentic CLI's own claim of having "empirically confirmed" something must still
  be independently checked, not trusted at face value** — itself a load-bearing lesson for anyone using a
  provider lens's findings. NOT fixed here (same reasoning as the `--commit` gap: a real isolation-hardening
  change to `lens-run.sh` needs its own reviewed cycle, not a bundle-in); recorded as a follow-up
  (candidate fix: `rm -f .git/FETCH_HEAD .git/ORIG_HEAD` in the sandbox before starting the provider CLI).
- **MEDIUM claims, plausible from re-reading the cited lines, not independently re-verified line-by-line
  here:** `.line` normalization doesn't enforce a JSON-number type before pass-through; the refute-step
  prose in `self-heal-advisory/SKILL.md` doesn't explicitly spell a `lens-run.sh --role refute` path for a
  provider-lens voter's own findings. Recorded for a future pass, not acted on in this item.

**Why these three (`--commit` injection, FETCH_HEAD leak, refute-path gap) are NOT fixed inside
operator-run/08:** that item is scoped to planning + eval, not to re-opening and re-reviewing a merged,
safety-critical adapter's isolation guarantees. Bundling an unreviewed security fix into an eval PR is the
wrong place for it to get the scrutiny it needs. They are follow-up candidates for a dedicated item.

## Goal
One adapter turns any installed agent CLI into a review lens that returns the same findings shape the
multi-voter merge rule already consumes; the voter becomes provider-selectable; nothing gates on it.

## Scope
1. **`scripts/adapters/providers/lens-run.sh --provider <p>[:<model>] --role review --diff <file>
   --prompt <file> --out <json>`.** Provider table (`claude`, `cursor`, `codex`, `gemini`) = command
   template + output parser, one file per provider, absent CLI → `provider_unavailable` (exit 0, named).
2. **Read-only by verification — honest scope.** Run the CLI in a throwaway detached `git worktree` at
   the PR head; after the run, `git status --porcelain` non-empty → result DISCARDED with
   `lens_mutated_tree` and the worktree removed. Never run a print-mode CLI in the live tree. **This
   DETECTS mutation of the worktree only** — a CLI with bash can write outside it (main checkout, `~/.claude`,
   a `git push`). Mitigations in scope: run with `--workspace <worktree>`, a scrubbed env (no `GH_TOKEN`,
   `HOME` pointed at a temp dir if the CLI's auth survives that — verify), and `git remote remove origin` in
   the throwaway worktree so a push has nowhere to go. What remains un-mitigated is stated in the adapter's
   header and in ARCHITECTURE_CONTRACTS §"Portability" — never described as "enforced".
3. **Normalize** to the CODE_REVIEW_RESULT findings fields (severity, file, line, summary, evidence);
   unparseable → `lens_unparseable`; both degrade to the existing single-voter fail-safe line.
4. **Wire:** `--multi-voter-heal --voter-provider cursor:gpt-5` (config `.voter_provider` — a NEW key,
   does not exist today); default stays `loomwright:red-team-reviewer` (Claude). `--multi-voter-heal` has
   NEVER executed (0 `multi_voter` lines in any live JSONL, 2026-09-12); the first run of this item would
   otherwise exercise two never-run paths at once — see AC-0. The merge rule, refute spawn, and "changes WHICH findings get
   fixed, not the gate shape" invariant are untouched.
5. **Cost honesty (D11):** provider usage is not in `token_ledger`; record wall-clock + whatever usage the
   CLI's JSON reports, else `cost: unknown` — never `0`. Auth is the user's CLI login; no keys in argv or files.

## Non-goals
No non-Claude WORKER or any write step (that is `operator-run/08`, and it is blind to our hooks). No new default —
graduates only if the FABLE_PARITY arm shows fewer post-merge defects/review rounds at ≤1.5× cost (same
bar the existing multi-voter cost note sets). No vendor SDKs — CLIs only, adapter dir only.

## Acceptance criteria
- **AC-0 (baseline row first):** one real `--multi-voter-heal` run with the default Claude voter, recorded
  as the FABLE_PARITY baseline row, BEFORE any provider code lands — so a failure in this item is
  attributable to the adapter, not to the never-run voter path.
- The `-f`/deny-by-default probe result is recorded in this file (date, command, observed behaviour).
- With `cursor-agent` on PATH: a fixture diff produces a normalized findings JSON; with it absent →
  `provider_unavailable` and the heal iteration runs single-voter, logged.
- Mutation test: a stub provider that writes a file → `lens_mutated_tree`, result discarded, worktree gone.
- A stub returning garbage → `lens_unparseable`, single-voter path, exit 0.
- `--voter-provider` absent → behavior byte-identical to today's multi-voter (existing tests green).
- `grep -rl "cursor-agent\|codex exec\|gemini -p" loomwright/ --exclude-dir=adapters` → docs only.

## Outcomes Rubric
- Provider table + parser per provider, absent = named no-op
- Read-only: deny-by-default probed; in-tree mutation detected and discarded; out-of-tree limit stated, never called "enforced"
- Voter selectable; merge rule and gate shape unchanged
- Cost recorded honestly, unknown never zero

## Status: done (PR #239 MERGED → 2c63cad8)
