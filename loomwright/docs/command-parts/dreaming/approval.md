## Approval Option Contract

Every per-item gate in this command is asked with `AskUserQuestion`, and this section is the authoritative shape of that call. Before it existed the command named only the *verbs* a user picks (`Accept` / `Reject` / `Edit` / `Supersede` / `Retract`) and never the payload, so labels, descriptions, order, and whether anything was recommended were improvised per run — two runs over the same proposal could present it differently, and **nothing was ever recommended even for the classes whose report entries already carry the evidence to justify one**. Every other `AskUserQuestion` caller in this plugin specifies its payload (see `commands/setup.md`, the observability / memory / rules module questions); this brings `/dreaming` in line.

### Payload shape (all gates)

- `multiSelect: false` — every gate is single-choice, and every content gate is per-item (the one per-run gate is the memory PR's Pre-push confirmation, which approves a push of writes already Accepted item by item — see "Memory PR (delivery queue)"). There is no bulk-accept anywhere in this command, and a multi-select gate would be one.
- `header` — ≤12 chars naming the item class: `Memory` (§3 / §5 / agent-memory queue — same underlying store), `CLAUDE.md` (§4), `Lesson` (§6), `Orientation` (orientation queue), `Rule`, `Push` (both Pre-push confirmations — the rules gate 2 and the memory PR's). Every row of the table below maps to one of these; a row with no header is the gap this list has already had twice.
- `question` — names the **target store** and the action, so the user can tell a paste-to-apply proposal from a sole-writer write without scrolling back to the report.
- `options` — from the fixed per-class sets below. **`AskUserQuestion` accepts at most 4 options**; the harness appends its own `Other` beyond them, so a fifth explicit option is an invalid call. The five verbs are consequently **never offered together**: `Supersede` and `Retract` act on an *existing* corpus entry and are mutually exclusive with the new-proposal set. That has always been true in practice — this states it as a constraint instead of leaving it to luck.
- Every option carries a one-line `description` saying what the choice does **mechanically** (which writer runs with which flags, or that nothing is written) — never a restatement of its label.

### Per-class option sets (fixed; in this order unless a recommendation reorders them)

| Item class | Options |
|---|---|
| §3 agent-memory proposal · §5 collected candidate · §4 additive CLAUDE.md proposal · orientation queue · agent-memory queue | `Accept` · `Reject` · `Edit` |
| §4 curation candidate (prune / merge / supersede as prose) | `Accept` · `Reject` · `Edit` |
| §6 new lesson (category not full) | `Accept` · `Reject` · `Edit` |
| §6 new lesson, category **full** — capacity eviction (plain `Accept`; `write-lessons.sh` enforces the ≤3 bound at write time and evicts the oldest). Distinct from the row below, per "Curating existing LESSONS" above | `Accept` · `Reject` · `Edit` |
| §6 proposal replacing a *specific* named lesson (explicit `Supersede`) | `Supersede` · `Reject` · `Edit` |
| existing corpus entry offered for curation (a live LESSON or committed memo) | `Retract` · `Keep as-is` · `Supersede instead` |
| harvested rule — gate 1 (content), no `check_candidate` shown | `Accept` · `Reject` · `Edit` |
| harvested rule — gate 1 (content), a `check_candidate` WAS shown (executable-rule-candidates/01) | `Accept` · `Accept rule WITH check` · `Reject` · `Edit` (4 options — at, never over, the cap) |
| harvested rule — gate 2 (Pre-push confirmation) | `Do not push` · `Push and open a PR` |
| memory PR — Pre-push confirmation (ONE per run, header `Push`; see "Memory PR (delivery queue)") | `Do not push` · `Push and open a PR` |

Do not grow a set. A new destination folds into an existing row or gets its own row here.

**Having a row is not the same as being offered.** Two harvested-rule cases are never asked at all, and this table does not override either: a batch the harvester marked **DISTILLATION FAILURE** is not offered item-by-item (see that subsection above), and a proposal printed as a **`DEFERRED — ALREADY COVERED`** block is context for the reader, not a queue item — it carries no `invocation:` line and Accepting one would duplicate a convention the live `.agent/rules/` store already states. Gate 1's row applies to the **numbered** proposals only.

### Recommendation

When — and **only** when — one of the rules below fires, the recommended option is moved to **first position** and ` (Recommended)` is appended to its label (the harness convention). Its `description` MUST additionally state the **basis** in one clause — e.g. "3 sessions corroborate" — so the nudge is falsifiable against the report printed above it. **A recommendation with no citable basis in that report is a defect**, not a style lapse: an unfalsifiable nudge on a write gate is how a per-item gate degrades into a rubber stamp.

| Item class | Recommend the named option iff | Otherwise |
|---|---|---|
| §3 agent-memory proposal | the linked Distilled Insight's evidence spans **≥2 distinct sessions**. (No dedupe clause: §3 targets `.claude/agent-memory/`, which is never deduped against project memory — that step is §5's alone) | abstain |
| §5 collected candidate | evidence spans **≥2 distinct sessions**. (No dedupe clause: §5's own spec drops any candidate already present in project memory *before* listing it, so surviving the dedupe is a precondition of appearing at all — asserting it here would be a condition that can never be false) | abstain |
| §4 additive proposal | the linked Distilled Insight's evidence spans **≥2 distinct sessions**, read from §4's own `Evidence:` field | abstain |
| §4 curation candidate (prune / merge / supersede) | **never** — a curation candidate rewrites or removes prose the user wrote; the judgment is theirs | abstain |
| §6 new lesson, category **not** full | evidence spans ≥2 distinct sessions/subtasks **and** it is the highest-scoring §6 proposal for its category in this batch | abstain |
| §6 lesson displacing an existing entry (category full, or an explicit `Supersede`) | **never** — the displacement is a judgment about the *existing* corpus, which reflection saw less of than the user did | abstain |
| existing entry offered for `Retract` | reflection found an observation that **contradicts** the entry (cite it). **Staleness or mere disuse is never a basis** | abstain |
| orientation / agent-memory promotion queue | **never** — a queued proposal is a single-run artifact written by one session's completion tail, so no cross-session corroboration exists for it to cite, and this contract does not compute one. Abstaining is the honest reading, not a gap to be filled later | abstain |
| harvested rule — **all three** gate-1/gate-2 choices (`Accept`; `Accept rule WITH check`; gate 2 `Do not push`) | **never** — including `Do not push`. There is no evidence axis to cite for any of the three: choosing to run a `check_candidate` at all is a judgment about *executable* trust distinct from content approval, not-pushing is a *default*, and this contract requires a **basis**, not a preference. The default is already expressed by `Do not push` holding first position in the option set (see the exclusion below); `Accept rule WITH check` never holds first position either — it is always ADDED after the plain `Accept`, never in front of it | abstain |
| memory PR — Pre-push confirmation (`Do not push`; `Push and open a PR`) | **never**, either option — the same reasoning as the harvested-rule gate 2: not-pushing is a default with no evidence axis to cite, and the default is already expressed by `Do not push` holding first position | abstain |

**Abstain is the default and it is not a failure.** When no rule fires, emit the class's option set in its neutral order above with **no** `(Recommended)` marker anywhere. A run in which nothing is recommended is the expected shape for a thin window; manufacturing a recommendation to fill the slot is the failure mode this table exists to prevent.

### The one exclusion that is load-bearing

**Neither harvested-rule gate may ever carry a recommendation *toward* the remote-affecting action.** Gate 2's stated contract is *default to NOT pushing; an ambiguous answer is a no* (see "Two distinct gates, and the ordering is the safety property" above) — a `(Recommended)` on `Push and open a PR` would resolve a safety gate toward the action it exists to slow down. Gate 1 is excluded too, for a different reason: the whole point of the batch's two scope-fidelity figures is that the user reads **both**, and a recommendation substitutes for that reading. **The memory PR's Pre-push confirmation is under the same exclusion:** its contract is the same *default to NOT pushing; an ambiguous answer is a no* (see "Memory PR (delivery queue)"), so it never carries a `(Recommended)` marker toward `Push and open a PR`.

**`Do not push` gets no marker either**, and the reason is worth stating because the opposite reading is tempting: it is the *safe* direction, so a marker on it would do no harm. But this contract's own rule is that a marker must cite a **basis**, and not-pushing has none to cite — it is a default, not an observation. The safe direction is already carried by **option order**: `Do not push` holds first position in gate 2's set and in the memory Pre-push set, which is how a default is expressed here without borrowing the vocabulary of evidence. A marker that means "this is the default" and a marker that means "the evidence supports this" must not look identical, or the second one stops meaning anything.

