# 04 — Validate before you write: sole-writer checks, an agent-memory writer, and a proposal queue

> Depends on **03** (routing). Depends on **01** (stores committed) so validation runs against the
> source of truth rather than a local-only copy.

## Problem
Curation happens only when a human types a command. Nothing checks, at the moment a fact is written,
whether it contradicts or supersedes something already stored. The result is a store that only ever
grows and quietly accumulates entries that are no longer true.

There is a natural chokepoint: **five sole writers** already funnel every write to a curated store —
`write-lessons.sh`, `write-project-memory.sh`, `add-rule.sh`, `add-orientation.sh`,
`write-system-contract.sh`. Today they append; they do not look around first. `add-rule.sh` has
`--supersedes`, but a human must know to pass it.

Agent memory has the opposite problem: **there is no write path at all.**
- No agent prompt instructs an agent to write memory. The only mention across all 14 is a
  *prohibition* (`agents/rubric-grader.md:49`).
- `code-reviewer` has `Write` **blocked** outright; its prompt calls the store read-only
  (`agents/code-reviewer.md:293`).
- Writes are rare and hand-made: measured mtimes are **2026-08-04, 2026-07-06, 2026-06-26** — three
  in ~six weeks, all to one store. (An earlier draft said the last write was 2026-06-26; that was an
  alphabetical-month sort error, corrected 2026-08-06.) The 32 files came from `/dreaming` proposals
  pasted in by hand, which is also why one index rotted to 1-of-18 (item 01b repairs that instance).
  **Note precisely what this does and does not falsify:** the recent write is fully consistent with
  the documented paste-to-apply path, so it does **not** show that an agent write path exists. The
  "no agent write path is specified" finding below rests on a grep across all 14 agent prompts and
  stands unchanged — do not descope this item on the strength of the corrected date.
- Meanwhile five of the six `memory: project` agents (`launch-pad`, `product-owner`, `qa-executor`,
  `qa-strategist`, `red-team-reviewer`) **do** have `Write` unblocked and nothing states whether they
  may write to their own store. That is an unspecified capability, and unspecified capabilities drift.

## Goal
Every write to a curated store passes five checks first; agent memory gains a real,
validated write path modelled on the pattern the plugin already uses for orientation memos; and
autonomous agent memory writes remain **out of scope by design**.

## Scope

1. **Five validations, shared by all sole writers** (one helper, not five copies — but see the
   independence caveat below before mandating that shape):
   - **Contradiction** → detect a supersede candidate and propose `--supersedes` rather than silently
     appending a contradicting entry.
   - **Duplicate** → refuse a near-identical entry.
   - **Provenance** → an entry must cite what motivated it (a finding, a PR, a session).
   - **Dead-reference** → **does every file/path the entry cites still resolve?** Deterministic, no
     model judgment, and the same check that curates every store. This is the general form of the
     index-integrity check item 01b applies to memory.
   - **Cross-repo reference** → **does the entry cite a repo outside the allowlist?** Shares item
     01's allowlist — one list, two consumers (ledger filter + this check). See the coverage caveat
     immediately below; it is NOT deterministic in the same sense as the other four.

   **Cross-repo check — bounded by construction, and it must say so.** The other four key on
   structured fields. This one scans free prose, where a foreign reference is just a word and a
   number (`otherhub #146`). Implementation: derive org and short names from the allowlist's known
   foreign slugs and scan case-insensitively as **whole words**. That is deterministic and cheap,
   and it *would* have caught the known instance — but it finds only repos already in the list. An
   unknown repo's references are invisible to it. **Do not describe this check as complete
   coverage**; overstating it would be the same class of error as the false clean that motivated it
   (see item 01b scope 3: two audits grepped `/hub` while the string was `otherhub #146`).

   **Why this check exists at all — the ledger filter cannot substitute for it.** The ledger's
   `otherhub` records are PRs `133 139 146 154`; the contaminated memory entry cites **`#129`,
   which is not in the ledger**. Memory is distilled from session logs and those sessions span
   repos, so a reference can enter a curated store without ever passing the ledger's `repo` field.
   A one-time scrub is necessary but not sufficient; this is the recurring guard.

   **Independence caveat — verify before mandating a shared helper.** The five existing sole writers
   share **zero** code today: `write-lessons.sh` (460 lines), `add-orientation.sh` (476),
   `add-rule.sh` (435), `write-system-contract.sh` (169), `write-project-memory.sh` (123) — none
   sources anything. A shared helper makes them the first writers with a dependency, and these are
   fail-safe writers where self-containment may be deliberate: one broken shared lib would break
   every curated store at once instead of one. Confirm whether the standalone shape is intentional
   before collapsing it, and state the trade-off either way. Five copies of a validator is
   duplication; one shared point of failure across every store is a different and possibly worse risk.

2. **Flag, do not delete.** Validation marks a superseded/stale entry and surfaces it. It never
   removes anything — see item 06 for why distilled stores are not auto-deletable. A validation
   failure is a **refusal to write plus an explanation**, never a silent mutation of the store.

3. **`write-agent-memory.sh` — a sixth sole writer.** Owns: the five validations, the store layout,
   **and the `MEMORY.md` index**. Making the index the writer's responsibility is what turns item    01's one-time repair into a structural guarantee — `18 files / 1 pointer` becomes impossible.

   **This is the highest-value part of this item, because the index is the injection mechanism.**
   Item 01's probe (2026-08-06) measured it: an entry file sitting in the correct harness directory
   but missing from `MEMORY.md` was **not injected into the spawned agent's context at all**. So an
   unindexed entry is not merely deprioritised — it does not exist as far as the agent is concerned.
   The `code-reviewer` store's 17 unindexed files are dead weight on disk today. Item 01b repairs
   that instance; **this writer is what makes the repair permanent**, and the root cause it removes
   is proven, not inferred: `MEMORY--premigration.md` holds 16 pointers against the current 1, so a
   migration replaced the index instead of merging it.

4. **A proposal queue, mirroring the orientation precedent.** The pattern already exists and is
   proven: agents drop proposals into the gitignored `.supervisor/orientation-proposals/`, and
   `/dreaming` promotes them into the committed store via the confirm-gated sole writer
   `add-orientation.sh` (`commands/dreaming.md:5`). Mirror it exactly:

   ```
   agent notices something in-run
        ↓ writes a PROPOSAL (no judgment about the existing store)
   .supervisor/agent-memory-proposals/       (gitignored)
        ↓ /dreaming triages  → item 05
   write-agent-memory.sh                     (validates + indexes)
        ↓
   .agent/ agent-memory                      (committed)
        ↓ PR → AI review → human merge       → item 05
   ```

   Agents propose (low stakes, no store-wide reasoning); the writer validates (deterministic); the
   human merges (final gate). No new trust model is introduced.

5. **Proposal trigger: surprise-only to start.** Agents propose when they hit something surprising,
   not at every run's end. Every-run gives better coverage but floods the queue. Record queue volume
   so the decision to widen is made on data. Whatever is chosen, state it explicitly in the agent
   prompts — the current silence is the actual defect.

6. **Resolve the unspecified capability.** State, in the shared agent contract, whether a
   `memory: project` agent may write its own store directly. Recommended: **no** — proposals only,
   writes go through the sole writer. Then make the prompts say so for all six, instead of one
   prohibition on an agent that does not even have the feature.

## Non-goals
No autonomous deletion. No LLM-judged validation — the four structured-field checks are fully
deterministic, and the fifth (cross-repo) is deterministic **but bounded by the allowlist**: it
matches known foreign org/repo names as whole words and cannot see a repo nobody has listed. That
limit is stated, never papered over. No change to
`rules-check.sh`'s execution trust boundary. No harvesting (item 05). No new gates: a validation
refusal blocks *that write*, never a PR, a run, or a `heal_decision`.

## Acceptance criteria
- All six sole writers run the five validations; each check demonstrably refuses a seeded violation
  (five fixtures, one per check). Whether they share a helper or carry independent copies is decided
  by the independence caveat in scope 1 and **justified in the PR**, not assumed.
- **The cross-repo check catches the known instance** — an entry citing `otherhub #146` is refused when
  `otherhub` is in the allowlist as a foreign slug — **and a test asserts its documented blind
  spot**: an entry citing a repo absent from the allowlist passes, proving the coverage limit is
  real and stated rather than discovered later.
- The cross-repo check and item 01's repo allowlist read **the same allowlist** — one source, two
  consumers; a test changes the list once and asserts both behaviours move together.
- Dead-reference detection is proven on a real stale entry, and on a **nullable-but-required** field
  it asserts key **presence** (`jq has()`), not merely type — a missing key must not pass as valid.
- `write-agent-memory.sh` rebuilds the index on every write; a seeded unindexed file is corrected,
  and the item-01 integrity check stays green after a write.
- The proposal queue round-trips: an agent writes a proposal, `/dreaming` sees it, the writer stores
  it, the index updates.
- The write-permission question is answered explicitly for all six `memory: project` agents, and the
  prompts match the answer.
- Every writer still refuses a worktree CWD (existing sole-writer invariant) — re-verified, not assumed.
- All new scripts always exit 0 where the convention requires it; `test-*.sh` Ubuntu-clean.

## Outcomes Rubric
- Five checks, each red on a seeded violation; shared-vs-independent shape justified, not assumed
- Cross-repo check catches the known instance AND its blind spot is asserted by test, not just prose
- One allowlist shared with item 01's repo allowlist
- Flag-not-delete honoured; refusals never mutate the store
- `write-agent-memory.sh` owns the index; rot structurally prevented
- Proposal queue round-trips end-to-end
- Agent write permission specified for all six agents, prompts consistent

## Status: brief-shipped

Job `.supervisor/jobs/done/2026-08-10-write-time-validation.md` completed (reconciled from the job lifecycle, not self-reported).
Acceptance criteria are NOT machine-verified here — review them before promoting this to `## Status: done`.
