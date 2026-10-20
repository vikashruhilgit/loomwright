## Module: rules

Gives a **cold-start** repo a non-empty `.agent/rules/` house-rules store by seeding a small set of **portable** conventions — ones true of any repository, in any language, with any layout. `/dreaming` is the other half of this substrate and the opposite direction: it DISTILS rules from what a repo has actually accumulated (ledger findings, the agent-memory corpus). A fresh repo has accumulated nothing, so that path yields an empty batch and the store stays cold forever; this module closes that gap without pretending anything was measured.

The deterministic engine is `${CLAUDE_PLUGIN_ROOT}/scripts/seed-rules.sh` (subcommands `check` / `seed`, plus `--confirm` to apply and `--root <dir>` to point at another repo). It authors every rule through the sole writer `add-rule.sh`, never by hand. This command owns the INTERACTIVE half — the offer and the one confirm.

> **SEEDED IS NOT LEARNED, and the distinction is DATA.** Every seeded rule is stamped `provenance.source=setup:rules-seed`. That value IS the mechanism: a reader separates a shipped default from a rule `/dreaming` earned off this repo's own findings (which carries `dreaming:<session_id>`) by reading `provenance.source` and nothing else. **No new member is added to the rule object and no sidecar file is written** — the schema is frozen at 7 always-present members (`id`, `category`, `statement`, `enforcement`, `check`, `provenance`, `applies_to`) plus the optional `supersedes`, and `add-rule.sh` rejects any unknown argument outright. When you report the result, say plainly that these rules are **seeded defaults, not something the tool learned here** — the helper's own output says so on every path; relay it, do not paraphrase it into "rules configured for your repo".
>
> **Honest limits — relay these, do not soften them.** (a) Every seed is **repo-wide** (`applies_to: null`) and that is a stated justification, not a silent default: a path glob is a claim about a directory layout, and no layout is universal, so scoping a portable rule to a path would contradict the portability that qualifies it. A rule that genuinely needs a path scope is evidence-derived — that is `/dreaming`'s job, not this module's. (b) `check` is `null` on every seed and the helper never passes `--check`: **rules are DATA, never executed**, the `rules-check.sh --no-cmd` trust boundary is unchanged, and **this module adds NO gate** — seeds are advisory and subordinate to the project's own `CLAUDE.md`. (c) The store is committed and human-curated, so a seed you disagree with is meant to be edited or retracted (`/rules`), not tolerated. (d) **Those two curation actions are NOT equally durable, and the user must be told which is which.** An EDIT is durable: presence is keyed on the seeded stamp for the seed's category, not on the statement text, so a rewritten seed is reported `ALREADY SEEDED (curated)` and a later run never touches it. A RETRACT is **not** a permanent opt-out: it deletes the object, so nothing is left carrying the stamp and a later `/setup rules` re-offers and rewrites that seed at exit 0 with no record of the refusal. Recording a refusal would need a store the frozen schema has no room for (a sidecar would be the same freeze violation one layer out), so the honest advice is: to keep a seed out, edit it down to what you do want, or do not re-run the module.

### Check

Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/seed-rules.sh" check` and report its cells: the per-seed `seed: ABSENT` / `seed: ALREADY SEEDED` lines (each with its category and statement) and the `seeds: N total · N already seeded · N absent` summary. **Read-only — `check` invokes no writer and creates nothing, not even the store directory.** It exits 0; a non-zero exit means it could not run (exit 2 = missing `jq`, or a usage error), and that is `unknown`, never a not-seeded claim.

### Report

Print what check found, including the helper's seeded-not-learned disclosure block. For the `status` subcommand, STOP after the report — read-only, no writes, no offer.

### Offer

Branch on what Check found (never re-seed silently):

**If any seed is ABSENT** — use `AskUserQuestion` (cap 4 options):
- `question`: "Seed this repo's rules store with portable conventions?"
- `header`: "Rules"
- `multiSelect`: false
- `options`:
  1. `Seed them` — "Write the absent portable rules to .agent/rules/ via add-rule.sh, each stamped provenance.source=setup:rules-seed so they read as SEEDED, not learned from this repo. Advisory only — nothing is gated, nothing is executed, nothing is committed."
  2. `Plan only (show me what would be written)` — "Print the exact rule object for each absent seed and write nothing."
  3. `Cancel` — "Do nothing."

Default to NOT seeding. If the answer is ambiguous, treat it as Cancel.

**If 0 are absent** — do NOT re-run apply. Report "already seeded" and offer `Status` / `Cancel` only. There is no reconfigure (a second seed on a still-seeded repo is a no-op by design, edits included) and no `remove` (retracting a rule is `/rules` territory — `add-rule.sh --retract`, which is a per-rule human decision, not a module teardown).

(A bare `/setup rules` with NO subcommand lands here and branches exactly as above. A `status` subcommand never reaches this phase — Report already stopped it.)

### Apply

1. On `Plan only`, run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/seed-rules.sh" seed` — it prints the full rule object each absent seed WOULD produce and writes nothing. Then return to the Offer.
2. On `Seed them`, and ONLY after that explicit confirm, run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/seed-rules.sh" seed --confirm`.
3. **Which invocation writes, stated so nothing is assumed.** `add-rule.sh` writes on `--confirm`, and otherwise **prompts `Confirm write? [y/N]` and writes on `y` whenever stdin and stdout are both a TTY** — which is exactly how `/setup` runs. A missing `--confirm` is therefore not by itself a dry run. The helper closes that by redirecting **every** writer invocation's stdin from `/dev/null` on **both** paths, which makes the prompting branch unreachable: so `seed-rules.sh` itself NEVER prompts, N seeds can never fire N prompts at the user's terminal, and the consent lives here, once, in the Offer above. Do not add a second prompt, and do not pass `--confirm` on the plan path.
4. Read the helper's summary line and report it verbatim — `written: N · failed: M` (apply) or `planned: N · failed: M · NOTHING WAS WRITTEN` (plan). Its exit contract: **0** = every seed handled (reported / planned / written / already present); **1** = at least one seed the writer REFUSED (the per-seed `seed: FAILED` line names it) — surface those and do NOT report success; **2** = usage error or missing dependency (`jq`, or the writer itself) — nothing was attempted.
5. **Seeding is not committing.** The store is a committed, version-controlled surface, but this command never stages anything. Tell the user to review `git status --short .agent/rules` and commit deliberately.

### Verify

Re-run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/seed-rules.sh" check` and show the before/after: each previously-absent seed now `ALREADY SEEDED`, and `0 absent` in the summary. Success is claimed ONLY after that re-check — and it is claimed as *"N portable rules seeded"*, never as *"N rules learned from your repo"*.

### Idempotency note

A second `/setup rules` on a **seeded and unretracted** repo reports "already seeded" and writes nothing: the helper skips a seed that is already PRESENT in a well-formed `.agent/rules/*.json` array, checked BEFORE the writer is invoked, so no duplicate is created and the run still exits 0. That skip is deliberate rather than left to the writer's own duplicate check — that check REFUSES with a non-zero status, which would turn a correct, already-configured second run into a reported failure.

**PRESENT is keyed on the seeded stamp, not on the statement text**, and the difference is what makes editing safe. A rule counts as present when its statement matches the seed EXACTLY (any provenance) **or** when it carries `provenance.source=setup:rules-seed` for that seed's category — matched on `.category` or on the frozen `<category>-` id prefix. So **an edited seed is recognised as curated, not missing**: `check` reports it `ALREADY SEEDED` and marks the match `curated`, a re-run writes nothing, and your wording survives byte-for-byte. (Keying on the exact statement instead made the skip strictly narrower than the near-identical refusal it exists to avoid: one edited word made the seed look absent, the writer then refused it as a near-duplicate, and the module reported a hard failure on every subsequent run of a correctly-configured repo.)

**RETRACT IS NOT A PERMANENT OPT-OUT — say so rather than implying idempotence covers it.** `add-rule.sh --retract` removes the rule object outright, so nothing is left carrying the stamp: a later `/setup rules` re-offers that seed and writes it back at exit 0, with no record that you rejected it. That asymmetry is real and worth stating to the user plainly — **editing a seed is durable curation; retracting one is not.** It is a known limit rather than an oversight: recording a refusal needs somewhere to store it, and the rule schema is frozen at 7 members while a sidecar would be the same freeze violation one layer out. To keep a seed out today, **edit it down to what you do want** (durable), or simply do not re-run the module.

---

