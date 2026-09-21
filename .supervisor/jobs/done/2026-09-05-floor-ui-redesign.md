# Supervisor Job: The Floor people can actually read, and a `serve` the agent can actually run

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: `main` @ `b3ef8f3`
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 2 (R5 context-bound, R7 taste-is-not-testable)
- **Source requirement:** `.supervisor/requirements/floor-ui-redesign/01-floor-ui-redesign-and-agent-callable-serve.md`

> **Read the source requirement in full before starting.** It carries a frozen
> §"Decisions taken by the owner before planning" (typography and dual-theme) and a
> §"Non-negotiables" list. Every item on that list **except the accessibility bullet** is
> asserted by a test with a mutation control — those are not preferences. **The accessibility
> bullet is asserted by NOTHING**, which AC19 exists to fix; do not assume a guard catches you
> there. An earlier draft of this brief claimed the whole list was guarded, and that was false.

## Feasibility

| # | Check | Verdict | Detail |
|---|---|---|---|
| 1 | Tech Stack Compatibility | GO | Both sides are the same shape — plain `index.html` + one CSS + one JS, no framework, no bundler, no `package.json`. Verified: the site's `site.css` (453 lines) has **0** `http(s)` refs, **0** `@font-face`, **0** `@import`. The design language is directly portable. |
| 2 | Dependency Availability | GO | Zero new dependencies, and none possible — the bundle forbids them. |
| 3 | Architecture Fit | GO | Restyle of 3 files the module already owns, plus prose in 3 docs. No IA change, no new data, no new surface on `floor.json`. |
| 4 | Scope vs Supervisor Capability | CAUTION | Two scopes (A: command bodies, B: restyle) that **overlap on `docs/FLOOR_UI.md` and `test-setup-ui.sh`**, so a split trips `file-conflict` rather than earning `genuine-parallelism`. Kept as ONE subtask; context-bound risk is R5. |
| 5 | Hard Blockers | GO | The one real blocker was found and resolved before planning: the site's three typefaces are **remote-loaded from Google Fonts** and ship no local files, so they cannot cross into the bundle. The owner chose the site's own declared fallback stacks. See the requirement's frozen decisions. |

**Overall Verdict:** CAUTION — matching the worst row rather than rounding up. Both CAUTION findings are carried into Risk Assessment (R5 from check 4, R6 from check 5); neither blocks, but the roll-up should not read cleaner than its inputs.

## Task

**Goal:** Restyle The Floor into the loomwright-site design language — warm cream palette, the
site's component vocabulary, both themes — and make it legible to a first-time reader, while
preserving every asserted trust property; and fix the four command-body surfaces so `/ui serve`
invoked as a slash command actually leaves a server running.

**Problem Statement:**
Someone watching a run needs to glance at The Floor and immediately know what is happening.
Currently the page renders the truth but is visually poor and hard to read — the owner's verdict
is that it *"is not at all looking good"* — so the one thing it exists for is the thing it does
badly. Separately, `/ui serve` **cannot work through the slash command at all**: `do_serve`
without `--detach` ends in `wait "$srv"` under an `EXIT` trap, so an agent-invoked run blocks
until the tool timeout and then the trap **kills the server it just started**. Success is a page
that a stranger can read, that looks like the same product as the site, that breaks none of the
properties that make it trustworthy — and a `serve` command that starts a server.

## Acceptance Criteria

Derived from the requirement's acceptance criteria — its 15, plus five lifted from the frozen decisions, the Non-negotiables, and this review. The requirement is the authority if they ever disagree.

- [ ] **AC1 — `/ui serve` as a slash command leaves a server running.** Asserted end-to-end: run it
      the way the command body now instructs, then confirm the socket answers, the pidfile names a
      live process, **and the invocation returned rather than blocking.**
- [ ] **AC2 — The foreground description survives, scoped by caller.** All **five** surfaces state
      which caller they describe. **Cited by phrase, not line, because this subtask edits all
      four files and line numbers will have drifted by grading time:** the `Ctrl-C stops it`
      usage comment and `Foreground is the default and Ctrl-C is enough.` in `commands/ui.md`;
      `Foreground is the default (Ctrl-C stops it).` in `commands/setup.md`; and the same
      `Foreground is the default and Ctrl-C is enough.` sentence in `docs/FLOOR_UI.md`; and
      `(Ctrl-C stops it; --detach backgrounds it)` in **`commands/agent-help.md`** — the fifth
      surface, a mirror of the `ui.md` usage line that an earlier draft of this brief missed.
      **Two shapes, and both must be handled — the enumeration above is only the first.**
      *Prose* surfaces get caller-scoping (the five above). *Invocation* surfaces get
      `--detach`: the fenced `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-ui.sh" serve` in
      `commands/ui.md` and the `Run \`bash … serve\` from the project root` step in
      `commands/setup.md`. Those two bare invocations are the lines an agent actually executes
      — they are what causes the defect, and a worker scoping only the five prose sentences
      would leave them standing. A grep proves `--detach` is present on the agent path.
      Deleting the foreground prose fails this criterion — it is true for a human at a terminal.
- [ ] **AC3 — A guard fails when a command body tells the agent to run a blocking foreground
      server**, with a mutation control proving the guard fires. **It must scan ALL of
      `loomwright/commands/*.md` with no per-file exclusions.** `agent-help.md` is in scope
      precisely because it is the surface that was missed; narrowing the guard's file set to
      make it pass is the gate-relaxation R1 forbids, and is the cheapest wrong answer here.
      **The runtime carve-out must be load-bearing, not free.** Scoping the guard to
      `commands/*.md` alone would make "don't flag `setup-ui.sh`" true for nothing — a shell
      script is structurally outside that glob, so the clause would assert nothing and be the
      self-satisfiable class this repo has already recorded twice. So **widen the scan to
      include `loomwright/scripts/*.sh`** and require a control asserting `setup-ui.sh`'s
      `foreground: Ctrl-C to stop` **is seen and is NOT flagged** — that is engine runtime
      output to a human at a terminal, the one place the message is unconditionally true.
      Then the command-body-vs-runtime-string discrimination is a real thing the guard must
      implement. **Key the guard on serve/foreground semantics, not on the bare word
      "blocking"**: 19 command files use "blocking" in the unrelated subagent sense and are
      outside this subtask's lanes, so a naive keyword guard would demand edits to files this
      contract cannot legally touch.
- [ ] **AC4 — The design language is demonstrably the site's, not invented.** Name each adopted
      token and cite where it came from in `~/Documents/work/personal/loomwright-site/site.css`.
      The palette, the `.4rem`/`99px`/`50%` radius vocabulary, the `1px solid var(--hair)`
      hairline, the soft warm shadows, and the uppercase letter-spaced mono label treatment are
      the identifiable signature — carry them, do not approximate them.
- [ ] **AC5 — Typography uses the site's own fallback stacks** (`Impact` display / `Georgia` body /
      `ui-monospace, Menlo` mono) and **no font is fetched or vendored**. See the frozen decision.
- [ ] **AC6 — Both themes are in the warm hue family.** Light adopts the site's cream palette;
      dark is derived into the same family, not left cold grey. Neither theme may look like a
      different product from the other.
- [ ] **AC7 — Zero egress, re-asserted after the restyle.** No `http(s)` URL, no protocol-relative
      ref in any `src`/`href`/`url(`, no `@import`, no `preconnect`, no `@font-face`, in any of the
      three bundle files. Existing scanner + mutation controls still pass.
- [ ] **AC8 — The CSP meta line is byte-identical** to before.
- [ ] **AC9 — The motion budget is unchanged at BOTH counting sites**: `setInterval == 1`,
      `requestAnimationFrame == 0`, `setTimeout == 0`. One site is **comment-inclusive**, so the
      token may not appear even in prose. **No CSS animation or transition that represents state**
      — motion is evidence, never decoration. A transition responding to hover/focus is input, not
      state, and is allowed.
- [ ] **AC10 — `fetch(` and `fetchText(` call-site counts unchanged** (2 and 3), or re-baselined to
      new **exact** numbers with their anti-vacuity and mutation controls still meaningful.
- [ ] **AC11 — The four guarded writes still work** — token in custom header, `Origin`, `Host` —
      and the page still refuses in words when it holds no token.
- [ ] **AC12 — `read-only` renders as hollow dot AND text in BOTH roster and lanes**, absent as
      `read-only unknown`. Colour alone is never a signal — this is load-bearing under a palette
      that introduces hue.
- [ ] **AC13 — Every honest state still renders and is distinguishable**, browser-verified against
      the committed fixtures with the console read: absent, empty, stale, no-run-in-flight,
      registry-absent, registry-unparseable, project-unavailable.
- [ ] **AC14 — The stopped state is browser-verified**: distinct render, buttons disabled, no
      uncaught error, poll stopped.
- [ ] **AC15 — Contrast meets WCAG 2.1 AA in both themes**, reported as **measured ratios** per
      text/background pair, not asserted. The warm cream palette is lower-contrast than the current
      cold one — this is the criterion most likely to fail, so measure early, not at the end.
- [ ] **AC16 — Every section states its own subject and freshness basis.** Enumerable form,
      because "a first-time reader can explain the page" is comprehension and no two reviewers
      grade it alike: **each `aria-labelledby` section in `index.html` carries a caption naming
      (a) what that section shows and (b) what its freshness is measured against.** The section
      list is already derived mechanically by `(j36)`, so this is countable rather than
      judged. The spirit — a stranger can read the page — is the rubric's job, not an AC's.
- [ ] **AC17 — Suite green, coverage not reduced.** `bash loomwright/scripts/test-setup-ui.sh`
      ends 0 failed / 0 skipped and the assertion count does not go **down**.
- [ ] **AC18 — Ratchet measured** with `bash scripts/check-vendor-coupling.sh --print-allowances`
      after staging; report before/after. The bundle files should still hold **no** allowance entry.
- [ ] **AC19 — The accessibility properties gain the guard they never had.** A new static
      assertion over `index.html` requiring: the skip-link anchor present; the banner retaining
      **both** `role="status"` and `aria-live="polite"`; and every section still carrying
      `aria-labelledby`. It needs a **mutation control** (remove one, watch it redden) **and** an
      anti-vacuity guard on `(j36)`. **A `>=` count is not sufficient and was the first draft's
      mistake** — `(j36)` enumerates with `grep -oE 'aria-labelledby="[a-z]+-h"'` over the whole
      file, so a count-based guard has three escapes: it is **comment-inclusive** (and
      `index.html` already comments on these attributes, so one comment restores a count a
      removal dropped — R2's hazard, in a new place), it is **not tied to how many sections
      exist**, and `[a-z]+-h` **excludes hyphenated or digit-bearing ids**, so renaming
      `stages-h` → `run-summary-h` keeps the attribute but leaves the loop's input. The closing
      form is **per-section, not per-document**: assert
      `count(<section[^>]*aria-labelledby="[^"]+") == count(<section) == 7`.
      **Two document-wide counts are NOT sufficient** — that was the second draft's mistake and
      it is escape #2 one level up. `aria-labelledby` is legal on *any* element, and AC16 makes
      adding a captioned landmark (`<nav>`, `<aside>`, `<div role="region">`) a natural move; a
      section could then **lose** the attribute while a non-section **gains** one, both totals
      still read 7, and the guard passes while AC19's own stated property is false. Measured
      today: 7 `aria-labelledby` and 7 on `<section` lines — they coincide **by luck, not by
      construction**, which is exactly why the equality must be anchored to `<section`.
      **Two mutation controls, because one cannot see both failures:** (i) remove the attribute
      from a section without removing the section; (ii) **move** it from a section to a sibling
      non-section element — control (i) reddens on the count drop, which is the case that
      already worked, so only (ii) exercises the displacement hole.
      **The comment-stripper needs its own control, and a multi-line-capable implementation.**
      All four comment blocks in `index.html` are multi-line (spans 8-14, 26-30, 34-40, 50-57),
      so the reflexive `sed 's/<!--.*-->//g'` strips **nothing** — measured: 7 before, 7 after —
      silently re-opening the comment-inclusive escape in full, and neither control above
      detects that. Use a multi-line-capable strip (`perl -0777 -pe 's/<!--.*?-->//gs'` or an
      awk state machine) and add a control that injects `aria-labelledby="x"` **inside a comment
      block** and asserts the count does **not** move.
- [ ] **AC20 — The browser verification leaves an artefact in the diff, at a named path.**
      AC13/AC14 and two rubric bullets rest on browser evidence a diff cannot contain. Create
      **`loomwright/docs/FLOOR_UI_VERIFICATION.md`** listing, per state exercised: the fixture
      used, what rendered, and the console result. The path is named deliberately — it must sit
      **outside** `loomwright/scripts/floor-ui/`, because that directory is capped at three
      files by a Non-negotiable (`BUNDLE_FILES`), so an unnamed artefact's only lane-legal home
      would have broken the very constraint it documents. Honest limit: this makes the claim
      **auditable for completeness** against AC13's seven states and AC14 — it does not make it
      independently true, since it is still self-reported.

## Outcomes Rubric

- The Floor and the loomwright site look like one product, using tokens traceable to the site repo.
- A first-time reader can say what the page shows, which project, and how fresh it is, unaided.
- Every trust property survives the restyle: zero egress, verbatim CSP, one timer, exact fetch
  counts, and the four guarded writes.
- `/ui serve` run as a slash command leaves a server actually running, and the agent's call returns.
- Every honest state and the stopped state are browser-verified, not asserted from the code.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Restyle the bundle in the site's language + scope the serve prose by caller | AC1–AC20 | 8 modify, 1 create | `frontend-ui`, `quality-checklist`, `unit-testing` | LAUNCHABLE |

**Single subtask by the Decomposition Threshold default — no split, so no split reason.** A split
into "command bodies" and "restyle" was considered and rejected: both scopes edit
`docs/FLOOR_UI.md` and `test-setup-ui.sh`, so the division trips `file-conflict` rather than
earning `genuine-parallelism`.

```yaml
# Subtask 1 — restyle + caller-scoped serve prose + guards (LAUNCHABLE)
provides:
  - {kind: "file",   path: "loomwright/scripts/floor-ui/floor.css"}
  - {kind: "symbol", path: "loomwright/scripts/floor-ui/floor.css", name: "--copper"}
  - {kind: "symbol", path: "loomwright/scripts/floor-ui/floor.css", name: "--hair"}
  - {kind: "file",   path: "loomwright/scripts/floor-ui/index.html"}
  - {kind: "file",   path: "loomwright/scripts/floor-ui/floor.js"}
  - {kind: "file",   path: "loomwright/commands/ui.md"}
  - {kind: "file",   path: "loomwright/commands/setup.md"}
  - {kind: "file",   path: "loomwright/docs/FLOOR_UI.md"}
  - {kind: "file",   path: "loomwright/scripts/test-setup-ui.sh"}
  - {kind: "symbol", path: "loomwright/scripts/test-setup-ui.sh", name: "no_blocking_foreground_serve"}
  - {kind: "file",   path: "loomwright/commands/agent-help.md"}
  - {kind: "file",   path: "loomwright/docs/FLOOR_UI_VERIFICATION.md"}
requires: []
lanes:
  - "loomwright/scripts/floor-ui/*"
  - "loomwright/commands/ui.md"
  - "loomwright/commands/setup.md"
  - "loomwright/commands/agent-help.md"
  - "loomwright/docs/FLOOR_UI.md"
  - "loomwright/docs/FLOOR_UI_VERIFICATION.md"
  - "loomwright/scripts/test-setup-ui.sh"
external_requires:
  - "~/Documents/work/personal/loomwright-site/ — read-only design source, OUTSIDE the project root"
```

> **`provides` verification (done at plan time, not assumed):** `--copper`, `--hair` and
> `no_blocking_foreground_serve` each return **0** repo-wide hits, so none can be satisfied by
> pre-existing text. Each also matches its file's conventions — `floor.css` already declares 36
> tokens in `--name:` form, and `test-setup-ui.sh` already declares 55 functions in `name() {`
> form. `--copper` and `--hair` are the two tokens that prove the *site's* palette landed rather
> than a hand-picked warm palette: `--hair` is its hairline border and `--copper` its primary
> accent.

## Parallelism Analysis

single-agent (no fan-out)

- Recommended workers: 1
- Rationale: one subtask, one lane group, nothing to overlap.

## Skill References

- `skills/frontend-ui/SKILL.md` — design-system, WCAG 2.1 AA, responsive (AC4–AC6, AC15)
- `skills/unit-testing/SKILL.md` — mutation-control discipline (AC3, AC7, AC9, AC10)
- `skills/quality-checklist/SKILL.md` — pre/post gates

## Risk Assessment

| # | Risk | Severity | Source | Mitigation |
|---|------|----------|--------|------------|
| R1 | **A restyle silently disarms a gate.** Nine asserted invariants live in the files being restyled; the tempting fix for a red gate is to relax it so the new style fits. | HIGH | Requirement | AC7–AC12 name each one. The requirement is explicit: *change the style, not the gate.* Suite coverage may not go **down** (AC17). |
| R2 | **The comment-inclusive motion budget.** `(b11)` counts `setTimeout(` including inside comments, so even *writing about* a timeout in a CSS or JS comment reddens it. A restyle is exactly when someone writes "no setTimeout here". | HIGH | Phase 3 analysis | AC9 states it. Do not name the token in prose. |
| R3 | **Warm cream is lower-contrast than cold grey.** `--text:#2C2418` on `--ink:#F4EBDC` is fine, but `--dim:#6B6154` on cream, and any accent-on-cream, are the pairs that will fail AA. | HIGH | Phase 3 analysis | AC15 — measure ratios early and report them, do not assert compliance at the end. |
| R4 | **Hue becomes a signal.** The accent family invites encoding lane/stage/state in colour, which breaks the page's standing rule that no state is colour-only. | MEDIUM | Requirement | AC12. Hue may only ever be **additional** to an existing shape or text cue. |
| R5 | **Context-bound single subtask.** `floor.js` is 1627 lines, `floor.css` 357, `test-setup-ui.sh` ~4500, plus 3 docs and an external repo to read. | MEDIUM | Feasibility | Splitting is worse (file-conflict on two files). Read only the regions being edited; append test groups rather than re-reading the suite. |
| R6 | **The design source is outside the project root.** `~/Documents/work/personal/loomwright-site/` is not under the repo, so a worker may not be able to read it. | MEDIUM | Feasibility | Declared in `external_requires`. **If it cannot be read, STOP and say so** — do not invent a design and claim it matches (AC4). |
| R7 | **"Looks good" is not testable.** AC4/AC16 are the two criteria a green suite cannot evidence. | MEDIUM | Plan analysis | AC4 is made checkable by requiring each token to be *cited* to the site; AC16 by requiring every section to carry its own explanatory words. The rest is a human judgement at review — say so rather than implying the suite covers it. |
| R8 | **`floor.js` edits risk the render contracts.** The restyle mostly belongs in CSS; JS edits should be confined to label/class text needed for clarity. | MEDIUM | Phase 3 analysis | Keep `floor.js` changes minimal and justify each one; AC10/AC13/AC14 re-assert its behaviour. |

## Configuration

- **Base Branch:** main
- **Worktrees:** not required (single subtask)
- **Cost profile:** inherit
- **Review lane:** deterministic `outputs_verified` + suite; Phase 4.5 integrated review is the sole LLM gate
- **Test command:** `bash loomwright/scripts/test-setup-ui.sh`
- **Ratchet command:** `bash scripts/check-vendor-coupling.sh --print-allowances` (after staging)
- **Design source (read-only):** `~/Documents/work/personal/loomwright-site/`
- **Release-surface bump is OUT of this subtask's scope — stated rather than left to be
  discovered.** `plugin.json`, `marketplace.json`, `CHANGELOG.md` and the CLAUDE.md banner
  are deliberately absent from `provides` and `lanes`. The version bump is handled at
  **FINALIZE**, by the same hand that opens the PR — which is how the previous item in this
  series shipped. Note `version-consistent` checks version *consistency* across manifests,
  not that a bump happened, so not bumping stays green: this is a decision, not a gap the
  gate would have caught.

## Handoff

/supervisor job: .supervisor/jobs/pending/2026-09-05-floor-ui-redesign.md

---

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/185
- **Reconciled:** lifecycle move completed by reconcile-jobs.sh, not by the completion tail
- **Evidence:** vcs merge commit 7031fe2 on origin/main — subject [Merge pull request #185 from vikashruhilgit/feature/floor-ui-redesign] — attributed by branch-slug match, committed on/after the brief date; git refs on disk only, no fetch, no forge call (https://github.com/vikashruhilgit/loomwright/pull/185)
- **Caveat:** fields the completion tail would have recorded (files changed, heal decision and iterations, red-team advisory) are NOT recoverable after the fact and are deliberately omitted rather than invented.
