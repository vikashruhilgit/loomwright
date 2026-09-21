# The Floor people can actually read, and a `serve` the agent can actually run

## Problem

Two separate defects, both of the same shape: **the thing works, and is unusable as delivered.**

### A. `/ui serve` cannot work through the slash command

`do_serve` without `--detach` ends in `wait "$srv"` and installs
`trap "kill $srv $loop …" EXIT INT TERM`. That is correct for a human running
`bash setup-ui.sh serve` in their own terminal.

But `/ui` is a **slash command — its only caller is an agent**, in the app and in the CLI
alike. On that path the documented default:

1. blocks the agent's Bash call until the tool timeout (up to 10 minutes);
2. the tool then kills the process, the `EXIT` trap fires, and **it kills the server it just
   started**;
3. the user gets a hung turn and no running server;
4. and *"Ctrl-C to stop"* is advice the user has no way to follow — it is not their shell.

So the documented default path **cannot work through the command at all**. Verified against
`setup-ui.sh` `do_serve`, not reasoned about.

**Root cause, and it is not in the engine.** The engine is correct. The command bodies restate
the engine's CLI semantics without distinguishing *which caller they are describing*, and `/ui`
inherited prose written for a human at a terminal. Same class as the falsified-docs finding on
PR #182: committed prose describing a behaviour that does not hold on the path it is on.

The claim appears on **five** surfaces — an earlier draft of this requirement said four and
missed the mirror in `agent-help.md`, which is exactly this repo's recorded agent↔command
mirror-drift class:

- `loomwright/commands/ui.md` — the `Ctrl-C stops it` usage comment
- `loomwright/commands/ui.md` — "Foreground is the default and Ctrl-C is enough."
- `loomwright/commands/setup.md` — "Foreground is the default (Ctrl-C stops it)."
- `loomwright/docs/FLOOR_UI.md` — the same sentence, ending a `--detach`/`stop` bullet
- `loomwright/commands/agent-help.md` — `(Ctrl-C stops it; --detach backgrounds it)`, a
  mirror of the `ui.md` usage line, in a command body, unscoped by caller

(`setup-ui.sh`'s own `foreground: Ctrl-C to stop` is engine **runtime output** to a human at a
terminal and is correctly out of scope — it is the one place the message is true unconditionally.)

### B. The page is not good enough to look at

The Floor renders the truth and renders it plainly, but it is visually poor and hard to read,
and the owner's verdict is that it *"is not at all looking good"* and that **everything on it
must be understandable**. A view whose entire purpose is that a human glances at it mid-run and
immediately knows what is happening does not get to be hard to read — legibility is the feature,
not decoration on top of it.

There is an existing design language to adopt rather than invent: the marketing/product site at
`~/Documents/work/personal/loomwright-site/`. Using it makes the tool and the site look like one
product instead of two.

## Goal

The Floor restyled in the site's design language and made genuinely legible to someone who has
never seen it before — **without breaking a single one of the properties that make it
trustworthy** — and `/ui serve` fixed so the command that starts it actually starts it.

## Scope

### A. Agent-callable `serve` (command bodies only — the engine does not change)

1. `/ui serve` and `/setup ui`'s serve step must instruct the agent to pass **`--detach`**, and to
   relay the pids line and how to stop it (`/ui stop`).
2. **Do not delete the foreground/Ctrl-C description — scope it.** It is true and useful for a
   human running the engine directly; it is wrong only as guidance to the agent. Say which caller
   each applies to.
3. Add a guard so the class cannot recur: something that fails if a command body instructs the
   agent to run a blocking foreground server. A comment alone is not a guard.

### B. The redesign

4. **Adopt the design language of `~/Documents/work/personal/loomwright-site/`** — read that repo
   for its palette, type scale, spacing rhythm, and component shapes. Take the *language*, not the
   implementation: the site may use a framework, a bundler and web fonts, none of which may cross
   into this bundle (see Non-negotiables). If the repo cannot be read, **stop and say so** — do
   not invent a design and claim it matches.
5. **Legibility is the acceptance bar, not taste.** Every state a first-time reader can land on
   must be self-explaining: what the page is showing, which project, how fresh it is, and what
   the four buttons will do. Prefer plain words over icons and jargon.
6. The existing information architecture is *sound* and is not up for redesign: pipeline stages
   above lanes, a roster, a projects picker, honest-state banners. This is a **restyling and a
   clarity pass**, not an IA rewrite.

## Decisions taken by the owner before planning (frozen — do not re-litigate)

Two questions were resolved with the owner up front, because both materially change the
deliverable and both were discovered by reading the site rather than assumed:

**1. Typography — use the site's OWN declared fallback stacks; do not vendor the fonts.**
The site names three typefaces in `site.css` (`--display:"Big Shoulders Display"`,
`--body:"Literata"`, `--mono:"Azeret Mono"`) but ships **no local font files** — it loads them
from `fonts.googleapis.com` / `fonts.gstatic.com` via `<link>` + `preconnect` in its
`index.html`. The Floor cannot do that: zero-egress, the verbatim CSP and "no web font" are all
asserted with mutation controls. So the Floor uses the fallbacks the site itself declares:

| Role | Site's stack | What the Floor uses |
|---|---|---|
| display | `"Big Shoulders Display", Impact, sans-serif` | `Impact, sans-serif` |
| body | `"Literata", Georgia, serif` | `Georgia, serif` |
| mono | `"Azeret Mono", ui-monospace, Menlo, monospace` | `ui-monospace, Menlo, monospace` |

This is not a compromise — it is **exactly what the site renders as when the network is
unavailable**, which is the Floor's permanent condition by design. Self-hosting was considered
and **rejected**: it would take the bundle past three files, change `BUNDLE_FILES` and the
module's own `present (3 files)` report, and require relaxing the `@font-face` prohibition — i.e.
weakening an asserted gate so a style change fits, which this requirement forbids elsewhere.

**2. Both light and dark themes, in the site's warm hue family.**
The site is **light-only** (zero `prefers-color-scheme` rules). The Floor has a working dark mode
today. **Both themes are kept.** The light theme adopts the site's cream palette directly; the
dark theme is **derived** into the same warm hue family rather than left as the current cold grey
— two themes that look like different products is the failure mode to avoid. Dropping dark mode
is not an option: it is existing behaviour on a page that stays open for long runs.

**The palette to adopt** (from `site.css` `:root`, cited so it is traceable rather than invented):

- surfaces `--ink:#F4EBDC` · `--ink-2:#FFF8EE` · `--ink-3:#EFE4D2` · `--linen:#FFF8EE`
- text `--text:#2C2418` · `--dim:#6B6154` · hairline `--hair:rgba(44,36,24,.14)`
- accents `--copper:#E8893A` · `--copper-deep:#8A4E12` · `--brass:#C47A2C` · `--indigo:#4F6FE8`
  · `--madder:#D63D5C` · `--teal:#1A9A8E` · `--violet:#7A5AE0` · `--gold:#C9A227`
  · `--chartreuse:#C8E05C`

Note the Floor currently uses a **cold neutral** palette (`--bg:#f7f7f5`, `--ink:#14171a`,
one blue accent `--accent:#1a4f8a`). The shift to warm cream is the substance of the restyle, and
the accent family is what lets lanes, stages and states be distinguished by hue **in addition to**
the shape/text cues they already carry — never instead of them.

## Non-negotiables

**Every item below is asserted by a test with a mutation control — EXCEPT the accessibility
bullet, which is asserted nowhere at all.** That exception is the point: it is an unguarded
property sitting inside the two files this change rewrites, and it needs a guard, not an
assumption.

**These are the properties that took an entire release series to earn. A redesign that breaks one
of them is a regression, not a trade-off. Do not relax a gate to make a style change fit — change
the style.**

- **Three files. No framework, no bundler, no Node, no npm, no package manager, no CDN, no web
  font.** The bundle is `index.html`, `floor.css`, `floor.js` and nothing else.
- **Zero egress.** No `http(s)` URL, no protocol-relative reference in any `src`/`href`/`url(`, no
  `@import`, no `preconnect`, no `@font-face`. Asserted by a scanner with mutation controls, and
  re-asserted over the changed bundle. **Type must come from a system font stack.**
- **The CSP meta line is asserted VERBATIM.** `default-src 'self'` and friends. If a style change
  needs a CSP change, that is a signal the change is wrong.
- **The motion budget:** exactly **one** `setInterval`, **zero** `requestAnimationFrame`, **zero**
  `setTimeout` in `floor.js` — counted at two sites, one of them **comment-inclusive**, so the
  token may not appear even in prose. No CSS animation may smuggle in motion that is not backed by
  a recorded event. **Motion is evidence, never decoration** is a standing invariant of this page.
- **Exactly two `fetch(` call sites and exactly three `fetchText(` call sites**, both asserted as
  exact counts with anti-vacuity and mutation controls. A restyle should not move either; if it
  does, re-baseline to the new **exact** number, never to an inequality.
- **The four guarded write buttons keep working** — token in a custom header, `Origin`, `Host` —
  and the page still refuses, with words, when it holds no token.
- **The stopped state stays distinct**: not a spinner, not a stale floor shown as current, no
  uncaught console error, controls disabled.
- **`read-only` renders as a hollow dot AND the text**, in *both* the roster and the lanes view.
  Colour or shape alone is not a signal. Absent renders as `read-only unknown`, never as silence.
- **Absent / empty / stale remain three distinct renders**, never a blank page and never a spinner.
- **Accessibility does not regress — and this is the ONE item on this list that no test backs.**
  Measured, not assumed: `skip-link` has **0** occurrences in `test-setup-ui.sh`; `aria-live`
  has exactly **1**, and it is a comment excluding the attribute from an unrelated count;
  there is **no** WCAG/luminance/contrast assertion anywhere in the suite; and `(j36)`'s
  label-association loop reads its section list *from* `aria-labelledby`, so a section that
  loses the attribute drops out of the input and the check **passes vacuously**. The skip
  link, the banner's `role=status` + `aria-live=polite`, and the section label associations
  must survive — and must gain a guard, because they are unguarded properties sitting inside
  the two files this change rewrites. Contrast must meet **WCAG 2.1 AA**.

## Non-goals

- **No information-architecture rewrite.** No new sections, no new data, no new surfaces on
  `floor.json`.
- **No new capability on the page.** The four write endpoints stay four.
- **No engine change for scope A.** It is a command-body defect; the engine is correct.
- **No dark-mode framework or theme system.** The page already handles light/dark; match the
  site's treatment within what exists.
- No new dependency of any kind, for any reason.

## Depends on

Nothing. `main` carries PR #182 (guarded writes) and #184 (registry lock).

## Release-surface obligations

- Command count unchanged; `/ui` gains no verb, and scope A adds none.
- No new agent, no new hook.
- `setup-ui.sh` is **CORE** in `docs/vendor-coupling-manifest.json` (allowance 3): if it is touched
  at all, measure with `bash scripts/check-vendor-coupling.sh --print-allowances` after staging and
  report the before/after. The bundle files hold no allowance entry and should keep holding none.
- If the redesign changes what the page renders in any state, `FLOOR_UI.md` §"Honest states" must
  match. A doc describing a render that no longer exists is the exact defect class this repo keeps
  finding.

## Acceptance criteria

- [ ] **`/ui serve` invoked as a slash command actually leaves a server running.** Asserted end to
      end: run it the way the command body now instructs, then confirm the socket answers and the
      pidfile names a live process — and that the agent's invocation **returned** rather than
      blocking.
- [ ] **The foreground description survives, scoped.** Each of the four surfaces states which
      caller it describes. A grep proves the `--detach` instruction is present on the agent path.
- [ ] **A guard fails when a command body tells the agent to run a blocking foreground server**,
      with a mutation control proving the guard fires.
- [ ] **The design language is demonstrably the site's, not invented.** Name the specific tokens
      adopted — palette, type scale, spacing, component shapes — and cite where each came from in
      `~/Documents/work/personal/loomwright-site/`. If that repo was unreadable, the item **stops**
      and says so rather than shipping a guess.
- [ ] **No remote reference of any kind** in the three bundle files, re-asserted after the
      restyle, with the existing mutation controls still passing.
- [ ] **The CSP meta line is byte-identical** to before.
- [ ] **The motion budget is unchanged**: `setInterval == 1`, `requestAnimationFrame == 0`,
      `setTimeout == 0` at both counting sites, and no CSS animation/transition that represents
      state rather than responding to input.
- [ ] **`fetch(` and `fetchText(` call-site counts are unchanged**, or re-baselined to new exact
      numbers with their controls still meaningful.
- [ ] **Every honest state still renders and is still distinguishable**: absent, empty, stale, no
      run in flight, registry absent, registry unparseable, project unavailable — browser-verified
      against the committed fixtures with the console read.
- [ ] **The stopped state is browser-verified**: distinct render, buttons disabled, no uncaught
      error, poll stopped. (This is the criterion the previous item could not close for lack of a
      browser — close it this time.)
- [ ] **`read-only` shows dot AND text in both roster and lanes**, and absent shows
      `read-only unknown`.
- [ ] **Contrast meets WCAG 2.1 AA** for every text/background pair in both light and dark, stated
      as measured ratios rather than asserted.
- [ ] **A first-time reader can explain the page.** Every section carries enough words to say what
      it is showing and how fresh it is, without the reader knowing the codebase.
- [ ] **`bash loomwright/scripts/test-setup-ui.sh` is green with 0 failed and 0 skipped**, and the
      assertion count does not go **down** — a restyle that deletes coverage is a restyle that
      broke something.
- [ ] The vendor-coupling ratchet is measured and the delta reported.

## Outcomes Rubric

- The Floor and the loomwright site look like one product, using tokens traceable to the site repo.
- A first-time reader can say what the page shows, which project, and how fresh it is, unaided.
- Every trust property survives the restyle: zero egress, verbatim CSP, one timer, exact fetch
  counts, and the four guarded writes.
- `/ui serve` run as a slash command leaves a server actually running, and the agent's call returns.
- Every honest state and the stopped state are browser-verified, not asserted from the code.

## Status: brief-shipped

Job `.supervisor/jobs/done/2026-09-05-floor-ui-redesign.md` completed (reconciled from the job lifecycle, not self-reported).
Acceptance criteria are NOT machine-verified here — review them before promoting this to `## Status: done`.

## Status: done (PR #185, merge 7031fe2)
- **Completed:** 2026-09-05T11:46:02Z
- **Brief:** .supervisor/jobs/done/2026-09-05-floor-ui-redesign.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/185
- **Reconciled:** 2026-09-21 by hand from the merged PR — the PR was merged outside the /automate loop, so nothing wrote this stamp at merge time.
