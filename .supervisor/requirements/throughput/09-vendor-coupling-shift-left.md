# 09 — Vendor-coupling ratchet, shifted left: a breach says exactly what was added and how to fix it

## Status: parked — superseded by `.supervisor/requirements/implementation-quality/02-iq01-and-throughput-merged.md` (owner decision 2026-10-09: implementation-quality/01 + throughput/01–09 merged into ONE item / ONE PR; this file is kept as that file's Part source)

## Depends on
05

## Touches
scripts/check-vendor-coupling.sh
scripts/test-check-vendor-coupling.sh
loomwright/docs/vendor-coupling-manifest.json
loomwright/docs/ARCHITECTURE_CONTRACTS.md
AGENT_GUIDELINES.md
changelog.d/throughput-09-vendor-coupling-shift-left.md

## Owner / red-team constraint (binding)
The ratchet must never auto-raise, never exempt silently, and never loosen fail-closed. `scripts/check-vendor-coupling.sh` is a **deliberate**, fail-CLOSED portability gate. Its header says counts "may FALL or stay FLAT, but … may not RISE without a reviewed, REASONED edit to the manifest", and it has "no third state and no `|| true`". It came from `.supervisor/requirements/2026-08-22-092036-vendor-coupling-ratchet.md` (status done) and the owner's core-vs-adapter direction (`loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Core/adapter architecture rule"). This item changes **when** a breach is seen and **how clearly** it says what to do. It does not change **what** counts as a breach.

## Problem
The gate is right, but its failure is found late and is hard to act on.

1. **It is a genuine catch.** On PR #435 the ratchet caught real new coupling. The first red run (`b8f9698…`, 12:54Z) printed BREACH rows for five paths:
   - `emit-token-ledger.sh` +3 (`core`, `hook_protocol`)
   - `test-token-ledger.sh` +3
   - `test-automate-lanes.sh` +1
   - `TELEMETRY.md` +2
   - `ARCHITECTURE_CONTRACTS.md` +1

   The fix commit `87f2205` removed the emitter's references instead of raising them ("New prose names no host hook token; the emitter reuses its existing `_apath`"). It raised only two test allowances by one each, with reasons. So the gate is worth keeping exactly as strict as it is.
2. **It is found late.** It failed 3 of the 9 full `ci-local` runs attributed to PR #435 by tree key: `b8f9698…` 12:54Z, `3e7bc89…` 14:29Z and `96b9fcf…` 15:31Z, in `~/.local/state/loomwright/ci-slots/dd8a9612cd818d9a/runs/`. Each time the verdict came at the end of a 646 s, 836 s and 639 s run (10.7–13.9 min). The live gate itself takes about 8 s (`PASS 8s … 12-check-vendor-coupling.sh` in run `e615441…`). Its self-test fails alongside it every time (`FAIL - case15 live repo passes its own ratchet` in `scripts/test-check-vendor-coupling.sh`), so one cause shows up as two red entries. Item 05 moves the 8 s gate into an early phase, which fixes the timing.
3. **The remediation is unclear.** The BREACH row (the `printf "$ROWFMT" … "BREACH  +$((n - allow)) over the declared allowance — remove the reference, or raise the allowance …"` site) prints only the count, the overage and the per-class totals. It does not say **which lines** added the references, gives no ready-to-paste manifest edit, and does not say how to route the reference through an adapter. The author has to diff by hand to find the new tokens.
4. **Much of the friction is test files.** `loomwright/scripts/*` is classed `core` (manifest `classes.core.globs`), and that glob includes hermetic `test-*.sh` files, which legitimately spell hook-protocol tokens to build payloads. Re-measured 2026-10-09 (this corrects the evidence brief's wording, see below):
   - **Allowance lines added.** Across the manifest's history (`git log -p`) there are 384 added path-allowance lines, and 76 of them are `test-*.sh` paths. This counts the initial seeding commit `7fa14d8`. Without it, the numbers are 316 and 60. These are *added* lines (new or changed values), not all raises.
   - **Current allowances.** 50 of the 262 allowance entries are `loomwright/scripts/test-*.sh`. Those hold 666 of the 1330 allowance units in `core` paths, about **50%**, and 666 of 2581 overall.
   - **Manifest edit rate.** Since the manifest was created (2026-08-30, `7fa14d8`), 38 of 587 non-merge commits touching `loomwright/scripts/` or `scripts/` also edited the manifest (**6.5%**). Counting merge commits, the figure is 59 of 646 (9.1%).
5. **The manifest is a merge-conflict hotspot.** PRs #410, #412 and #417 all edited `loomwright/docs/vendor-coupling-manifest.json` (verified via `gh pr view --json files`). Every unnecessary per-path raise adds to that.
6. **A dismissed follow-up is still open.** `.supervisor/requirements/proposed/automate-2026-10-05-002720--01-ratchet-hardening-5ac6cf--dismissed-summary.md` (PR #385, decision follow-up) holds three LOW items, re-checked on `main` 2026-10-09. All three still apply:
   - Entry 1, key `6751fe48`: the summary line still reads `of which frontmatter-exempt: N`, although those files' bodies are counted (the `files scanned:` echo).
   - Entry 2, key `7a5865e3`: the seven token-class names are restated in the script header ("named classes — install root, subagent orchestration, …") and in `ARCHITECTURE_CONTRACTS.md` §"Core/adapter architecture rule", besides the manifest's `token_classes`.
   - Entry 3, key `93982b64`: the raise_check BREACH row prints the raw JSON literal (`$bv -> $cur`, e.g. `2 -> 3.0`), and the jq predicate accepts `-0`, which the shell check then rejects.

## Goal
When the ratchet trips, the author learns in seconds (via item 05) exactly which added lines tripped it and the two legitimate ways out:
- route the reference through an existing adapter or indirection, or
- raise the allowance with a reason the author must write.

The gate stays exactly as strict as today. A pasted suggestion with an unfilled reason is still a BREACH.

## Scope (shift-left only)
1. **Per-breach detail, printed by the gate (`scripts/check-vendor-coupling.sh`).** For every BREACH path, print a block under its row:
   - **Added lines.** List the lines that carry tokens and were added versus the base: `git diff <base> -- <path>` `+` lines, counted with the **same** awk leftmost-longest counter, never a second matcher. Give each line's number, its token(s) and class(es). When the base does not resolve, list the path's token-bearing lines, capped and labelled `base unavailable — showing all, not only added`.
   - **Ways out, in this order.** (a) Reword prose so it names the concept, not the token (docs). (b) Reuse the file's existing reference; PR #435's emitter reused its existing `_apath`. (c) Move the harness-specific code into an `adapter`-classed file; list the manifest's `classes.adapter.globs` as data, never hard-coded. (d) Raise the allowance. The block must **never** suggest assembling a token at runtime (concatenation or indirection to dodge the literal count). That is the gate's documented blind spot (header: "It therefore CANNOT see a reference ASSEMBLED AT RUNTIME"), and recommending it would loosen the gate in practice.
   - **Ready-to-paste raise row.** Print both manifest entries, `"<path>": <actual>,` for `allowances` and `"<path>": "<placeholder>"` for `allowance_reasons`. The placeholder is a fixed sentinel string. **raise_check treats a reason equal to, or containing, the sentinel as missing (BREACH)**, so pasting without writing the reason still fails closed. Integer formatting follows Entry 3 (below).
2. **Owner decision option, NOT decided here: a separate test-fixture path group.** Present it in the PR body for the owner, and implement it only if the owner picks it. Option A is the default.
   - **A (status quo):** `test-*.sh` stays `core`. Pro: one ratchet, nothing new to reason about. Con: about half of the `core` allowance units are tests, test-only raises churn the hotspot manifest, and the `core` number overstates runtime coupling.
   - **B:** a new class, e.g. `test_fixture`, for `loomwright/scripts/test-*.sh`, `scripts/test-*.sh` and `loomwright/scripts/fixtures/*`. It keeps per-path allowances and keeps reasons on raises, so it is still fail-closed. Moving the paths is a `policy_reasons` `exempt:`-namespaced change, reviewed once. Pro: `core` then measures what a non-Claude harness would run. Con: a new class in the gate's fixed four-class precedence, and a runtime helper named `test-*.sh` would be misclassed. Mitigation: the gate ERRORs if a `test_fixture` path is referenced from `loomwright/hooks/hooks.json` or sourced by a non-test script.
   - **C:** B with one class-level budget instead of per-path allowances. This removes most test raises from the hotspot, at the cost of per-path visibility. A raise still needs a reason.

   Whichever is chosen: no class may be uncounted (that would be `adapter`), and a moved path keeps being counted.
3. **Visible early.** Two parts:
   - **Mechanical: the early phase (Depends on 05).** `check-vendor-coupling.sh` is a `scripts/check-*.sh` ci.yml gate. Item 05 makes it run in the early phase of every full `ci-local` run, and it already runs under `--affected` (the cheap-gate filter). This item's job is that the early-phase output carries the Scope-1 block in full.
   - **Advisory: one line in `AGENT_GUIDELINES.md` §"Pre-push: one command".** After adding any install-root, hook-protocol or ask-user token (see the manifest's `token_classes`, not a restated list), run `bash scripts/check-vendor-coupling.sh` (about 8 s) before the full run.

   **`loomwright/agents/worker.md` is deliberately not touched.** `implementation-quality/01` is editing it. More importantly, the worker prompt ships to every user project, and this gate is a Loomwright-repo-only root `scripts/` gate, so naming it there would be wrong for every other project. This also removes the need to depend on iq/01.
4. **case15 reads as the same cause.** When `test-check-vendor-coupling.sh` case15 ("live repo passes its own ratchet") fails, its FAIL line says it is the live gate's verdict, and it points at, or reprints, the live BREACH rows. One cause then reads as one cause. Its assertion is unchanged: it still fails whenever the live repo breaches.
5. **Fold in the three dismissed LOW items (the `proposed/…ratchet-hardening…dismissed-summary.md` file, Problem 6).**
   - Entry 1: relabel the `frontmatter-exempt` count in the summary line so it does not read as uncounted, for example `frontmatter-bounded (header exempt, body counted)`.
   - Entry 2: the script header and `ARCHITECTURE_CONTRACTS.md` point at `token_classes` instead of naming the seven classes. The #385 changelog fragment was already folded into `CHANGELOG.md` and is history, so leave it.
   - Entry 3: the raise row prints integers. The jq predicate rejects `-0` in the same place the shell check does, so the two layers agree.

## Acceptance criteria
- **The detail block.** A fixture that adds two hook-protocol tokens to a `core` script prints a BREACH block. The block lists exactly those two added lines (line numbers, tokens, class) and not the file's pre-existing references. It lists the adapter globs read from the fixture manifest, and the ready-to-paste raise row with the sentinel reason. The exit code is 1, as today.
- **The sentinel still fails.** Pasting the suggested row unchanged and re-running gives exit 1, with a raise_check BREACH naming the unfilled reason. Replacing the sentinel with a real reason gives exit 0. Mutation control: drop the sentinel check and the "pasted unchanged" leg must fail.
- **No suggestion of runtime assembly.** The test greps the block for the advice it must never give, and the block also states that rule positively.
- **No base.** With no base (the `skipped (no base)` path), the block says `base unavailable` and lists the token-bearing lines. The exit code is unchanged.
- **case15.** On a breaching live-repo fixture, case15 still FAILs, and its line names the live gate's verdict as the cause.
- **Entries 1–3.** Each has a leg: the summary label, no restated class list in either surface (grep), integer raise-row output, and `-0` rejected consistently.
- **Strictness unchanged.** The whole existing `test-check-vendor-coupling.sh` passes unchanged except the asserted new output. No existing BREACH/ERROR case flips to exit 0.
- **If the owner picks B or C,** the moved paths are still counted (the per-class report shows the new class), and the move is certified by `policy_reasons` entries. Otherwise the manifest is untouched by this item.

## Validation (must pass before merge)
1. `bash scripts/ci-local.sh` green (the full run).
2. New `test-check-vendor-coupling.sh` legs fail on the base commit and pass on the branch.
3. **Running system.** Replay PR #435's first red tree: check out `fe64cff` (tree `b8f9698…`) in a scratch worktree, run the gate against base `9a65ecb`, and paste the five BREACH blocks in the PR body. The `emit-token-ledger.sh` block must list the 3 added `hook_protocol` lines that `87f2205` later removed.
4. The owner's A/B/C answer is recorded in the PR body, and in this file's Scope 2 once decided.

## Non-goals
- Any loosening: no auto-raise, no silent exemption, no `|| true`, no warning-only mode, no skip on a missing base where CI sets `VENDOR_COUPLING_REQUIRE_BASE=1`.
- Moving the gate earlier in `ci-local`. That is item 05; this item only makes the early output actionable.
- Seeing runtime-assembled references (the gate's stated literal-match limit). Out of scope, and never to be "solved" by advising authors to use it.
- Editing `loomwright/agents/worker.md` (see Scope 3).
- Resolving manifest merge conflicts mechanically (#410/#412/#417). Option B or C would reduce how often they happen. Neither removes them.
