# 04b — Close the writer-side validation gaps 04 found but deliberately did not patch

> ## Status: brief-shipped
>
> **HALF OF THIS ITEM WAS ALREADY CLOSED BEFORE IT RAN — measured at execution, not assumed.**
> Three commits landed against `add-orientation.sh` after this brief was written, and they moved
> the ground under it. Recorded here because the next reader would otherwise re-derive it:
>
> - **Scope 1's duplicate half and AC2: ALREADY FIXED**, by a different mechanism than this brief
>   proposed. `5e60498` replaced `--store` (which had pointed at the memo's own target file) with a
>   derived whole-store corpus, `build_compare_corpus`. Probed on the live writer at execution time:
>   an identical body reposted under a second slug at a **12-token** body is `REFUSE_DUPLICATE`.
>   The "~90 body token" threshold this brief is built on **never existed** — the check was not
>   biting late, it was not biting at all, and the corpus fix closed it.
> - **AC2's stated premise is therefore void.** It asks for the `VE_N=120` inflation to be removed
>   because "its removal is what makes the assertion meaningful". `VE_N=120` remains, but with a
>   different and now-correct rationale already stated in the suite ("a long body is still the
>   realistic shape for a memo — not because 90 is a threshold anything needs to clear"), and the
>   short-body case is asserted directly. Removing it would prove nothing.
> - **"Why this is not deferrable past 05" no longer holds.** That argument rests entirely on the
>   duplicate check being inert during 05's ~104-rule harvest. It is not inert. **05 was never
>   blocked by this item.**
> - **Scope 3's duplicate half: already done.** The suite had already replaced that limitation test
>   with controls (a) and (b) and narrates the correction in place.
>
> **What was genuinely live, and what shipped:** scope 2 (provenance) and scope 4 (confirm gates).
> Scope 3's *provenance* limitation test also worked exactly as designed — it went RED naming the
> limitation as closed, and was replaced with three positive assertions covering both directions.
>
> **AC1 knowingly reverses `3ce5d9e`.** That commit — the most recent to touch this file before this
> work — deliberately made a *labelled* `head_sha:` count as a citation, after an earlier attempt
> refused real memos whenever an abbreviated sha happened to contain no `a-f` (2.6% of this repo's
> commits). Closing AC1 means `/dreaming`'s promotion path must now supply `--source`. The owner was
> shown the conflict and chose to close AC1. Worth recording: `3ce5d9e` rejected
> `--source "head_sha:$sha"` precisely because it would let "the writer vouch for itself outside the
> artifact a reader can see" — while the fix it accepted kept the writer vouching for itself one
> layer in. The fix here is writer-side only: the validated entry became body+summary.
> `validate-entry.sh`'s five checks are untouched, and the labelled-sha acceptance still serves
> every other writer.

> Depends on **04** (the shared validator and its wiring must exist first).
> **MUST precede 05.** See "Why this is not deferrable past 05" below — 05 harvests ~104 rules
> through the very writer whose duplicate check is effectively off for ordinary-sized memos.

## Problem

Item 04 wired five validations into six sole writers. For **one** of those writers,
`add-orientation.sh`, two of the five are effectively inert — and 04's own PR states this rather
than fixing it. Both stem from a single root cause, which is why they belong in one item.

**Root cause: `add-orientation.sh` validates the COMPOSED memo, not the memo body.** The entry it
hands to `validate_entry_all` is header + summary + body. The header is one the writer stamps
itself:

```
<!-- written_at: <ISO-8601 UTC> | head_sha: 1f49b70 | areas: demo-area -->
```

Two consequences, both **verified by execution** during 04's Phase 4.5 review, not inferred:

1. **Provenance is unfalsifiable through this writer.** That `head_sha` is a 7-hex token, which
   `_VE_PROVENANCE_RE` accepts as a commit reference — so **every memo vouches for itself**. A memo
   whose summary and body cite nothing at all is written (rc 0). The header alone scores rc 0; the
   body alone scores rc 1. The writer also has no `--source` flag, so there is no caller-side route
   to the refusal either. Provenance is, in practice, **off** for this writer.

2. **Duplicate only bites above ~90 body tokens.** The composed entry carries ~10 header/summary
   tokens the *stored* side never carries (`_ve_store_lines` skips `<!--` lines when reading a memo
   back). Overlap is scored over the larger set, so a duplicate registers only when
   `N/(N+10) >= 90%`. Measured transition: 20/40/60/80/**90** body tokens → not detected;
   **100**/120/200 → `REFUSE_DUPLICATE`. **Memos are capped at 1000 chars**, so the common case sits
   *below* the threshold: duplicate is effectively off for ordinary memos.

**Separately — a pre-existing confirm-gate asymmetry, surfaced the hard way.** `add-rule.sh`,
`add-orientation.sh` and `write-agent-memory.sh` require `--confirm`; `write-lessons.sh`,
`write-project-memory.sh` and `write-system-contract.sh` do **not**. 04's reviewer demonstrated this
by accident: **one non-interactive invocation from the repo root appended a validated entry to the
committed store.** It was caught and restored, and the working tree was verified clean — but the
lesson stands and is now load-bearing: **validation is not a substitute for a confirm gate.** Once
all six writers share a validator it is easy to read "validated" as "gated", and for three of them
that is false.

## Why this is not deferrable past 05

Item 05 harvests roughly 104 rules through these writers. Running that harvest while
`add-orientation.sh`'s duplicate check is inert for ordinary-sized memos means the harvest is
exactly the workload most likely to produce near-identical memos, and the one check that would catch
them cannot fire at that size. Fixing it afterwards means curating a store that has already
accumulated the duplicates this queue exists to prevent.

## Goal

Make all five validations genuinely load-bearing on `add-orientation.sh` by validating the memo
**body** rather than the composed file, and resolve the confirm-gate asymmetry explicitly — either
by gating the remaining three writers or by documenting the split as deliberate.

## Scope

1. **Validate the body, not the composed memo.** `add-orientation.sh` passes the memo body (and,
   where meaningful, the summary) to `validate_entry_all` — never the self-stamped header. Do not
   special-case the header inside `validate-entry.sh`: the validator is shared by six writers and
   must not learn one writer's file format. The fix belongs in the writer.

2. **Provenance must become reachable for this writer.** Once the header is out of the entry, a memo
   citing nothing will refuse. Decide and state how a legitimate memo supplies provenance — most
   likely a `--source` flag mirroring the other writers, with `/dreaming`'s promotion call passing
   the proposal's originating session id (it already passes `dreaming:<session_id>` to
   `write-lessons.sh` after 04). Whatever is chosen, `/dreaming`'s promotion path must keep working
   end to end.

3. **Retire the two pinned-limitation tests as the limitations close.** 04 pinned both bounds as
   *facts*, worded so the tests go **red naming the limitation as closed** when the writer is fixed —
   that is the intended signal, not a regression. Replace them with ordinary positive assertions
   (an un-provenanced memo REFUSES; a short near-identical memo REFUSES) and delete the
   `VE_N=120` inflation the duplicate fixture currently needs.

4. **Resolve the confirm-gate asymmetry.** Either add `--confirm` to `write-lessons.sh`,
   `write-project-memory.sh` and `write-system-contract.sh`, or document the split as deliberate with
   the reason. **State which, and why** — the one thing that must not survive is six writers whose
   gating differs with no stated rationale, since that is what let a review probe write to the
   committed store.

## Non-goals

- **No change to `validate-entry.sh`'s five checks.** They were proven correct in 04 against the
  live corpus (21 live entries + 21 adversarial prose entries, zero false refusals). This item
  changes *what a writer hands them*, not what they do.
- No autonomous deletion, no new gate, no LLM-judged validation — 04's non-goals carry forward.
- **Not in scope: making the AC9 agent-memory write rule enforceable.** It is structurally
  unenforceable in this plugin — `code-reviewer`'s own prompt records that Bash is unrestricted by
  the harness, so no `disallowedTools` setting can prevent a store write. It is a permanent caveat,
  correctly stated in prose, and this item must not pretend to close it.
- Not in scope: the seven-file coupling of the four required AC9 literals. That is an accepted
  maintenance cost chosen over a vacuous heading grep, not a defect.

## Acceptance criteria

- [ ] An `add-orientation.sh` memo whose body and summary cite no PR / issue / session / commit is
      **REFUSED** for provenance — proving the writer no longer vouches for itself via its own
      `head_sha` header.
- [ ] A second near-identical memo at an **ordinary** body size (≤ 40 tokens, well inside the
      1000-char cap) is **REFUSED** as a duplicate. The `VE_N=120` inflation is gone from the
      fixture, and its removal is what makes the assertion meaningful.
- [ ] `/dreaming`'s orientation-promotion path still round-trips end to end with a legitimate,
      provenanced memo — the human-gated Accept flow is not broken by the new refusal.
- [ ] The two limitation-pinning tests from 04 are **replaced**, not deleted silently: the PR states
      that each went red because the limitation closed, which is the signal they were written to give.
- [ ] The confirm-gate question is answered for all six writers, with the decision and its reason
      recorded in `AGENT_GUIDELINES.md` or the writers' headers — no writer's gating is left
      unexplained.
- [ ] Every existing check still holds: the live-corpus replay stays at **zero** false refusals, and
      all suites plus root gates stay green.

## Outcomes Rubric

- `add-orientation.sh` passes the memo body to the validator; the self-stamped header is no longer
  part of the validated entry
- An un-provenanced memo is refused, and a legitimate provenanced memo still writes
- A near-identical memo at ordinary size (≤ 40 body tokens) is refused as a duplicate
- `validate-entry.sh`'s five checks are unchanged — the fix is writer-side only
- 04's two limitation-pinning tests are replaced by positive assertions, with the transition stated
- The confirm-gate asymmetry is resolved or documented, with the reason recorded
- Live-corpus replay still yields zero false refusals
