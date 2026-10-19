## Reflection Report Sections

Every `/dreaming` report **must** include all six of the following sections, in this order:

### 1. Recurring Patterns

Concrete patterns observed across the analyzed sessions: repeated failure modes, repeated review findings, repeated decisions, repeated blockers. Each entry cites the originating session IDs so the user can cross-check.

### 2. Distilled Insights

The interpretation layer: what the recurring patterns *mean*. Each insight is a short, falsifiable claim — e.g., "Workers consistently miss boundary tests when subtasks lack explicit `provides:` entries" — paired with the evidence count. When the **System Twin contract-drift** input is present (the `contract_conformance_status`/`contract_violations` trend from `session_end`, and/or per-subsystem drift read read-only from `.supervisor/twin/`), it is folded in here as an additional evidence stream — e.g. "contract conformance in subsystem X has regressed across the last 3 sessions." This input is read-only and **advisory**, optional, and silently omitted when no twin data exists (backward-compatible with repos that have never run the System Twin).

### 3. Proposed Memory Updates

Per-agent proposed additions, edits, or deletions for `.claude/agent-memory/{agent-id}/`. Each proposal lists:
- Target agent (must be one with `memory: project`)
- Proposed change type (add / edit / delete)
- Target file or tag within the memory directory
- Proposed text (verbatim)
- Justification linked to a Distilled Insight
- **Evidence: N distinct sessions (ids)** — carried down verbatim from that Insight's own evidence count. It is not decoration: it is the field the §3 recommendation rule is computed from (see "Approval Option Contract" below), and a proposal that omits it can never be recommended
- Approval status: **PENDING USER APPROVAL** (always — `/dreaming` does not auto-apply)

### 4. Proposed CLAUDE.md Updates

Proposed additions or revisions to project `CLAUDE.md` (or a sub-file it references). Each proposal lists:
- Target section (existing heading or proposed new heading)
- Proposed text (verbatim, in the same prose style as the surrounding doc)
- Justification linked to a Distilled Insight
- **Evidence: N distinct sessions (ids)** — carried down from that Insight, same role as in §3: it is what the §4-additive recommendation rule reads, and its absence means no recommendation. A **curation** candidate (below) carries it too, but is never recommended regardless
- Approval status: **PENDING USER APPROVAL** (always — `/dreaming` does not auto-apply)

**Curation candidates (prune / merge / supersede) — same section, same gate, no new writer.** Alongside additive proposals, `/dreaming` may also surface a **curation** candidate when reflection determines that CLAUDE.md (or a sub-file it references, e.g. a relocated section in `loomwright/docs/`) has drifted from what a fresh session actually needs. A curation candidate is still just a §4 proposal — labeled **PENDING USER APPROVAL**, applied by the user (or a follow-up turn) via the existing paste-to-apply mechanism, never written by `/dreaming` itself. Three shapes:
- **Prune** — an existing section (or sub-file section) no longer earns its context cost (e.g. it describes a retired behavior, or duplicates something now authoritative elsewhere). The proposal names the section to remove and the justification (linked Insight).
- **Merge** — two sections restate the same fact and should collapse into one. The proposal names both sections, which one survives, and the merged text (verbatim, ready to paste).
- **Supersede** — a claim's authoritative home has moved (e.g. a count or version claim that should now read "see `plugin.json`" instead of restating a number — see `AGENT_GUIDELINES.md` §"Claim Duplication Rule"). The proposal names the stale claim, its new authoritative source, and the replacement text.

Each curation proposal carries the same **Accept / Reject / Edit** gate as every other §4 item (there is no CLAUDE.md writer, so `Supersede`/`Retract` as *actions* — the composed store-verb calls used elsewhere in this command for LESSONS/orientation memos — do not apply here; a curation candidate that *recommends* a prune/merge/supersede is still just accepted, rejected, or edited as **prose to paste**). This is UX parity with the v15.14.0 store-curation shape (per-item gating, never bulk) — not a claim that CLAUDE.md gained a mechanized sole writer; it explicitly did not (see the Read-Only Contract below).

### 5. Collected Memory Candidates

The worker-proposed durable facts harvested from the gathered sources. `/dreaming` collects candidates from two concrete, unambiguous shapes: (a) the `memory_candidates:` array inside a `WORKER_RESULT` block in the session logs, and (b) a `## memory_candidates` section in a `.worker-summary.md` file — one `- ` bullet per candidate string (the format workers write into the summary). Workers have emitted the optional `WORKER_RESULT.memory_candidates[]` field since v14.4.0 and echo the same strings under the `## memory_candidates` summary heading, which is why both shapes are scanned. The collected strings are **deduped** against the existing project memory — `/dreaming` reads the verified facts via `bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-project-memory.sh"` first and drops any candidate already present (and dedups duplicates among the candidates themselves). Each surviving unique candidate is listed:
- Candidate text (verbatim, one line)
- Source session ID / subtask it came from
- **Evidence: N distinct sessions (ids)** — how many of the analyzed sessions independently produced this candidate (1 for a single-session candidate, which is the common case). Same role as in §3: it is what the recommendation rule reads, and its absence means no recommendation
- Approval status: **PENDING USER APPROVAL** (always)

On Accept, a candidate is written as a PROJECT_MEMORY fact via `write-project-memory.sh` (see Phase 4 / APPROVE).

### 6. Proposed LESSONS

Distilled, **category-tagged** lessons, **bounded ≤3 active per category**. Before proposing, `/dreaming` reads the existing `.supervisor/memory/LESSONS.md` to respect the bound; if a category already holds 3 active lessons, the proposal is framed as **replacing the oldest** lesson in that category (the bound is also enforced independently by `write-lessons.sh` at write time). Each lesson is scored by a simple heuristic — **recall-frequency × outcome × diversity** — where *recall-frequency* is how often the underlying pattern recurred across the analyzed sources, *outcome* weights lessons tied to failures/regressions higher than cosmetic ones, and *diversity* rewards patterns seen across multiple distinct subtasks/sessions rather than one noisy run; the product orders which lessons are worth the scarce ≤3 slots. Each proposal lists:
- Category tag and lesson text (verbatim)
- Heuristic score (and, when a category is full, which existing lesson it would replace)
- Justification linked to a Distilled Insight
- Approval status: **PENDING USER APPROVAL** (always)

On Accept, a lesson is written via `write-lessons.sh` (see Phase 4 / APPROVE).

#### Curating existing LESSONS (Supersede / Retract)

Reflection may also surface that an **existing** `LESSONS.md` entry (not just a newly-distilled §6 candidate) is now wrong, contradicted by a more recent pattern, or simply stale. When it does, `/dreaming` offers that existing entry for **`Supersede`** or **`Retract`** alongside the normal §6 proposals — same per-item `AskUserQuestion` gate, no bulk action:

- **`Supersede`** — offered when a §6 proposal is framed as replacing a *specific* existing lesson (not merely "the oldest in a full category" — see the ≤3-bound note above, which is a capacity eviction, distinct from this explicit curation action). On the user picking `Supersede` (instead of a plain `Accept`), `/dreaming` invokes the target's own `supersede` verb, composing PRE-CHECK → RETRACT → ADD in one call (this ordering is enforced inside `write-lessons.sh`, never by `/dreaming` sequencing two separate calls):

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-lessons.sh" supersede "<category>" "<old lesson text>" \
    --replacement "<new lesson text>" --source "dreaming:<session_id>" --confirm
  ```

  `--replacement` is **required** (a supersede without one is indistinguishable from a `Retract`). On success the new lesson carries `supersedes=<hash-of-old>` in its trailer and the old entry is gone; on a pre-check failure (target absent or not chain-trusted) the verb fails loud (exit 4) and `LESSONS.md` is left byte-identical — `/dreaming` surfaces that failure to the user rather than silently dropping the item.

- **`Retract`** — offered on an existing lesson reflection determined is simply wrong or no longer applicable, **with no replacement**. On the user picking `Retract`, `/dreaming` invokes the already-shipped retract verb:

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-lessons.sh" retract "<category>" "<lesson text>" --source "dreaming:<session_id>" --confirm
  ```

  This is the same `retract` flow `write-lessons.sh` has shipped since the curation/anti-rot work landed (tombstoned via provenance, entry line removed, `read-lessons.sh` labels it `RETRACTED` if it's ever inspected historically) — `/dreaming` is simply a new per-item-gated CALLER of it, not a reimplementation.

Both actions pass `<category>` / `<lesson text>` / `<new lesson text>` as **literal argv values**, never interpolated into a shell string — matching the argv discipline already required for §6 Accept (see Phase 4 / APPROVE).

### Pending orientation proposals (promotion queue)

When the gitignored `.supervisor/orientation-proposals/` directory holds proposal `.md` files (written by the Supervisor Phase 4.5 completion tail — see `skills/self-heal-advisory/completion-tail.md` step 2.6), `/dreaming` appends a promotion queue after the six report sections, listing each proposal's area slug, one-line summary, and file path, labeled **PENDING USER APPROVAL**. This is a promotion queue, not a seventh mandatory report section — it appears only when proposals exist. Per-item **Accept** promotes the proposal into the committed `.agent/orientation/` store via `add-orientation.sh … --confirm` and deletes the promoted proposal file; **Reject** deletes the proposal file without writing; **Edit** revises the proposal text before a re-offered Accept (see Phase 4 / APPROVE for the exact invocation and argv discipline).

**Supersede / Retract for existing committed memos.** When a pending proposal's area-slug logically replaces a *different*, already-committed memo (e.g. an area was renamed or split), or when reflection independently determines an existing committed memo is stale with no proposal replacing it, `/dreaming` offers the same two curation actions on the existing `.agent/orientation/<slug>.md` entry, per-item-gated exactly like the proposal actions above:

- **`Supersede`** — promotes the pending proposal as the declared replacement of an existing memo (rather than a plain new/updated memo at its own slug):

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/add-orientation.sh" --supersedes \
    --target "<old-area-slug>" --replacement "<new-area-slug>" --reason "<text>" --confirm
  ```

  Both `<old-area-slug>` and `<new-area-slug>` must already exist as parseable memos (the replacement is normally the just-promoted proposal, so promote it first via the plain create path, then supersede). `--replacement` is required; the target memo file itself is left in place — `read-orientation.sh` is what hides a superseded memo from output (single-hop, non-transitive), not deletion.

- **`Retract`** — removes an existing committed memo outright, with no replacement:

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/add-orientation.sh" --retract \
    --target "<area-slug>" --reason "<text>" --confirm
  ```

  There is no in-store home for the reason (no provenance sidecar for this store — adding one would violate the curation freeze), so the writer **prints** a one-line provenance record to stdout; the commit that lands the removal is the durable record. `/dreaming` surfaces that printed line to the user as confirmation.

### Pending agent-memory proposals (promotion queue)

When the gitignored `.supervisor/agent-memory-proposals/` directory holds proposal `.md` files (the surprise-only proposals agents are instructed to write rather than editing `.claude/agent-memory/` by hand), `/dreaming` appends a second promotion queue after the six report sections, listing each proposal's `agent:` slug, `name:` entry slug, one-line `description:`, and file path, labeled **PROMOTE PENDING PROPOSAL**. Like the orientation queue, this is a promotion queue and **not** a seventh mandatory report section — it appears only when proposals exist, and an **absent directory is the normal empty case** (it has never been populated in this repo), never an error.

Per item, human-gated, no bulk action:

- **Accept** — promotes the proposal into the store through its sole writer:

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-agent-memory.sh" --proposal <proposal-file> --confirm
  ```

  The proposal file carries its own routing in frontmatter (`agent:` / `name:` / `description:`, optionally `title:` / `source:` / `type:`), so **pass the path and nothing else** — the writer refuses positional arguments alongside `--proposal`. It exits `0` on a verified write, `1` on a REFUSAL it examined (validation, hostile marker, cap, bad slug), `2` on could-not-examine, and `3` from a git worktree. **On success `/dreaming` deletes the promoted proposal file** — the writer does not delete it, so this deletion is `/dreaming`'s own step, exactly as for the orientation queue. **On any non-zero exit the proposal file is left in place** and the refusal is surfaced to the user for editing; a refused promotion is never silently dropped.
- **Reject** — deletes the proposal file **without writing**. The committed store is untouched.
- **Edit** — revises the proposal text, writes nothing, and re-offers it for Accept.

This closes the gap `write-agent-memory.sh` names in its own header. Nothing here creates a branch at Accept time: agent-memory is an in-place store with a sole writer, so an accepted promotion is written in place. It reaches a branch only through the optional memory PR offered after every Accept, behind its own Pre-push confirmation (see "Memory PR (delivery queue)" below); the `.agent/rules/` queue below has the other PR path.

