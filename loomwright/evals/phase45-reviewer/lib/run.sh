#!/usr/bin/env bash
# run.sh — THE documented command of the phase45-reviewer suite: replay every corpus case against the current
# loomwright:code-reviewer and print `caught: X/Y`, one row per case and the controls' noise.
#
#   bash loomwright/evals/phase45-reviewer/lib/run.sh [extra `claude plugin eval` args, e.g. --model <m>]
#
# MODEL-BACKED and on-demand only: it spends the operator's Claude credential (one reviewer per case). Never
# run it from CI or from a test, except under a PATH stub that shadows `claude` (the selftest's missing-tool
# assertion).
#
# 1. `claude plugin eval --help` must exit 0, with `claude` resolved through PATH. Otherwise:
#    `phase45-reviewer: missing tool: claude plugin eval` on stderr, exit 1, no `caught:` line.
# 2. From the repo root (the eval target must be the PATH ./loomwright — the bare name resolves to the
#    installed plugin), every output in a `mktemp -d` dir, never in the repo:
#      claude plugin eval ./loomwright --eval-dir evals/phase45-reviewer --scaffold --allow-tools Bash
#        --ablation none --no-publish --trust-plugin --keep-temp --output-dir … --report … --json … [args]
#    The CLI exits 1 when any case scores below its threshold (an UNSTAGEABLE case has no reply, so it
#    always does); that is not a failure here — the report is lib/summarize.sh's, not the eval's pass/fail,
#    which only means "a reply was captured".
# 3. lib/summarize.sh over the eval JSON, with PHASE45_WALL_S = the eval's wall clock in seconds.
# Exit codes: 0 the report printed; 1 the tool is missing, or the eval wrote no JSON; otherwise summarize's.
# bash 3.2 + BSD userland.
set -uo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE="$(cd "$LIB/.." && pwd)"
REPO="$(cd "$SUITE/../../.." && pwd)"

if ! claude plugin eval --help >/dev/null 2>&1; then
  echo "phase45-reviewer: missing tool: claude plugin eval" >&2
  exit 1
fi

S="$(mktemp -d "${TMPDIR:-/tmp}/phase45-reviewer.XXXXXX")" || { echo "phase45-reviewer: mktemp -d failed" >&2; exit 1; }
echo "phase45-reviewer: eval output in $S (kept sandboxes: chmod -R u+rwx each one before deleting it)" >&2
start="$(date +%s)"
( cd "$REPO" && claude plugin eval ./loomwright --eval-dir evals/phase45-reviewer --scaffold --allow-tools Bash \
    --ablation none --no-publish --trust-plugin --keep-temp \
    --output-dir "$S/out" --report "$S/report.html" --json "$S/eval.json" "$@" )
erc=$?
end="$(date +%s)"
echo "phase45-reviewer: claude plugin eval exited $erc" >&2
if [ ! -s "$S/eval.json" ]; then
  echo "phase45-reviewer: the eval wrote no JSON ($S/eval.json) — no report" >&2
  exit 1
fi
PHASE45_WALL_S="$((end - start))" bash "$LIB/summarize.sh" "$S/eval.json" "$SUITE"
