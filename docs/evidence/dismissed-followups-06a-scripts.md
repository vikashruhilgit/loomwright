# Dismissed follow-ups 06a: script headers, engine docs and contracts (`scripts` group)

Source requirement: `.supervisor/requirements/dismissed-followups/06a-docs-and-evidence-drift.md`, Subtask 1
(findings F106 F319 F010 F053 F093 F104 F126 F127 F128 F129 F085 F096 F143). The sibling `docs` group
lives in `docs/evidence/dismissed-followups-06a-docs.md`.

**Base:** `8100319b23d9371f620233e51f86feac286b15a7` (`main`). Every re-verify command below was run from the
worktree root on that base, before any edit. A match line is given as "line N" of the file the command names.

**Regression legs (AC2):** every finding below is `doc-only`. Each edit is prose, a comment, a usage string or
a golden fixture, and none changes executed behaviour, so no `test-*.sh` leg is added. The one executable
text change (F010, the `meta-entry` usage row printed by `automate-helpers.sh --help`) is pinned by the
existing golden comparison in `loomwright/scripts/test-automate-helpers-dispatch.sh` (step 5), which reads
`fixtures/automate-helpers-help/meta.golden`.

**AC21:** none of the 13 findings was already fixed on the base. Every anchor still matched, so nothing is
`recorded` as already fixed.

## Findings

| Finding | Re-verify command | Result on base | Disposition | Kind |
|---|---|---|---|---|
| F106 | `grep -nF 'The release lane runs the bump once for the whole wave.' changelog.d/README.md` | 1 match (line 39) | `fixed`: `changelog.d/README.md`, the `Parallel wave` bullet now says `automate-wave.sh wave-build`'s release step runs `scripts/bump-version.sh` once for the whole wave and commits the fold as the wave branch's last commit; lanes still write fragments only | doc-only |
| F319 | same command as F106 (same bullet) | 1 match (line 39) | `fixed`: `changelog.d/README.md`, by the F106 edit | doc-only |
| F010 | `grep -nF 'writes nothing under .supervisor/automate/' loomwright/scripts/automate-helpers.d/meta.sh loomwright/scripts/fixtures/automate-helpers-help/meta.golden` | 2 matches (line 3 of `meta.sh`, line 1 of `meta.golden`) | `fixed`: `loomwright/scripts/automate-helpers.d/meta.sh` and `loomwright/scripts/fixtures/automate-helpers-help/meta.golden`, both now `writes nothing itself; the meta-sync pull it runs may update managed .supervisor/automate/ files; always exits 0` (`meta-sync.sh`'s header lists `.supervisor/automate/*.md` among the managed paths) | doc-only (usage string + golden) |
| F053 | `grep -nF 'automate-helpers.sh (_pw_touches)' loomwright/scripts/automate-dismissed.sh loomwright/scripts/propose-from-verify.sh` | 2 matches (line 457 of `automate-dismissed.sh`, line 125 of `propose-from-verify.sh`) | `fixed`: `loomwright/scripts/automate-dismissed.sh` and `loomwright/scripts/propose-from-verify.sh`, comments now locate the authority as the `PW_TOUCHES_GRAMMAR` line in `automate-helpers.d/plan-waves.sh` (`_pw_touches`); no code line changed | doc-only (comment) |
| F093 | `grep -nF 'the completion tail STAMPS' loomwright/scripts/test-reconcile-jobs.sh` | 1 match (line 5) | `fixed`: `loomwright/scripts/test-reconcile-jobs.sh`, the header bullet now says leg 11 checks `is_done()` against the format the live writers stamp (closeout, `automate-trail.d/closeout.sh`; the owner-abandon heading, `automate-helpers.d/reconcile-status.sh`) and names cases `11a-11f`; no leg changed | doc-only (comment) |
| F104 | `grep -nF 'At both seams it calls' loomwright/docs/PITFALLS.md` | 1 match (line 38) | `fixed`: `loomwright/docs/PITFALLS.md`, now "At both seams the engine runs `closeout`, whose step 2 is `automate-helpers.sh brief-repair <item> <pr_url>`" (`automate-trail.d/closeout.sh` calls `brief-repair`; `per-item-loop.md` steps 1 and 5 say the same) | doc-only |
| F126 | `grep -nF 'release --owner <label> \| --session-id <id> [--root <dir>]' loomwright/docs/CORE_CONTRACT.md` | 1 match (line 111), with no `[--force-unlock]` on `release` | `fixed`: `loomwright/docs/CORE_CONTRACT.md`, the `run-lock.sh` row's release argv now reads `release --owner <label> \| --session-id <id> [--root <dir>] [--force-unlock]`, matching `run-lock.sh`'s usage echo | doc-only |
| F127 | `grep -nF 'consumers fail CLOSED on `missing` / `unverifiable`' loomwright/docs/CORE_CONTRACT.md` | 1 match (line 123) | `fixed`: `loomwright/docs/CORE_CONTRACT.md`, the `verify-provides.sh` row now says consumers fail CLOSED on `missing`, while `unverifiable` routes per `agents/supervisor.md` Single-Agent step 3 (some reasons fall back to the worker's self-report) | doc-only |
| F128 | `grep -nF 'the validators fall through to the transcript path' loomwright/docs/CORE_CONTRACT.md` | 1 match (line 308) | `fixed`: `loomwright/docs/CORE_CONTRACT.md` §5.3 Cursor bullet, now says the common input's `transcript_path` matches a ladder key in `PAYLOAD_TRANSCRIPT_KEYS` (`agent_transcript_path`, `transcript_path` in `result_block_parser.py`) while the cited docs do not name the subagent transcript field, so whether it matches is UNVERIFIED | doc-only |
| F129 | `grep -nF 'Codex run-in-background' loomwright/docs/CORE_CONTRACT.md` | 0 matches (§5.2 did not classify it) | `fixed`: `loomwright/docs/CORE_CONTRACT.md` §5.2, Codex run-in-background is listed under `Could not be re-verified` (the 2026-08-22 row's wording is not available to compare), naming the detach primitive the §5.1 matrix marks UNVERIFIED | doc-only |
| F085 | `grep -nF 'emit-token-ledger.sh header' loomwright/scripts/read-token-ledger.sh` | 1 match (line 65) | `fixed`: `loomwright/scripts/read-token-ledger.sh`, the pointer now names `read_transcript`'s docstring in `emit-token-ledger.sh`; the docstring, which still carries the original finding tag, is not edited | doc-only (comment) |
| F096 | `grep -nF 'deny mechanics and the jq-free inert path unchanged' loomwright/docs/HOOKS.md` | 1 match (line 89) | `fixed`: `loomwright/docs/HOOKS.md`, the D1 bullet and the `guard-test-integrity.sh` host-mode row both say an unresolvable D1 gate root makes the guard deny every Write/Edit/Bash call (`guard_unavailable`), even in an unarmed session. Both name the one exception the code has: the `LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS=1` opt-out (step ii) runs before that deny (step iii). Only the row's third cell changed; key and Class cell are untouched | doc-only |
| F143 | `grep -nF 'run_lock_degraded' loomwright/skills/automate-loop/lanes.md loomwright/skills/automate-loop/per-item-loop.md` | 1 match (the PICK-time acquire in `per-item-loop.md`, line 15); none at the wave-lock acquire or the closeout **Concurrency** bullet | `fixed`: `loomwright/skills/automate-loop/lanes.md` (the PICK wording, verbatim) and `loomwright/skills/automate-loop/per-item-loop.md` (wording adapted, see below) | doc-only |

### F143: why the closeout clause is not the PICK wording verbatim

The coordinator runs the wave-lock acquire in `lanes.md` itself and reads its stderr, so the PICK wording,
"noted once and is not a park", is accurate there. `closeout` is a script: `automate-trail.d/closeout.sh` runs
its `run-lock.sh acquire` with `2>/dev/null`, so a `run_lock_degraded` line from that acquire is never seen by
anyone and cannot be "noted". The **Concurrency** bullet therefore says: "A `run_lock_degraded` stderr line is
not a park: `closeout` discards run-lock's stderr and proceeds". The not-a-park half matches the PICK wording,
and the noted half is not claimed where no code backs it. A degraded acquire exits 0 (`run-lock.sh` header,
"Degraded"), which is why `closeout` proceeds.

## Validation

- `bash scripts/ci-local.sh --affected` after the edits: PASS, all 22 entries (the early set, which includes
  `check-doc-currency.sh`, `check-token-budget.sh`, `check-prompt-history-refs.sh`, `build-capabilities.sh` and
  `check-version-bump.sh`, plus `test-automate-dismissed.sh`, `test-automate-helpers-dispatch.sh`,
  `test-citation-drift.sh`, `test-propose-from-verify.sh`, `test-read-token-ledger.sh` and
  `test-reconcile-jobs.sh`).
- `--affected` listed nine changed files as not covered, so every suite that reads one of them was run
  directly: `test-loop-inventory.sh`, `test-automate-next-step.sh`, `test-automate-golden.sh`,
  `test-automate-loop-split.sh`, `test-wave-build.sh`, `test-build-capabilities.sh`,
  `test-guard-test-integrity.sh`, `test-host-mode.sh`, `test-progress-state.sh`, `test-worktree-audit.sh`,
  `test-validate-entry.sh`, `test-automate-helpers.sh` (its X7 grammar-drift leg covers F053's comments),
  `test-module-shape-facts.sh`, `test-release-refold.sh` and `scripts/test-bump-version.sh`. All pass.
  `test-automate-golden.sh`'s M3 check failed once before the commit, because it requires
  `git diff --quiet -- automate-dismissed.sh` and the F053 comment edit was still uncommitted. It passed on
  the committed tree.
- The HOOKS.md claim (F096) was reproduced in a scratch repo with the real `guard-test-integrity.sh`, host
  mode on and a world-writable per-user root planted under a scratch `TMPDIR`. A Write to a plain
  `notes.txt` in an unarmed session was denied (`guard_unavailable: gate state dir unresolvable`, exit 2).
  The same call with `LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS=1` was allowed (exit 0), and so was the call with the
  root absent (exit 0, inert).
