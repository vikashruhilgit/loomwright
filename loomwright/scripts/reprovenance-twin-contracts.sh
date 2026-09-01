#!/usr/bin/env bash
# reprovenance-twin-contracts.sh — the SANCTIONED recovery path for System Twin contracts whose
# bodies were changed outside write-system-contract.sh and therefore no longer verify.
#
# THE INCIDENT THIS EXISTS FOR (diagnosed 2026-09-01, root cause dated 2026-08-12). A tree-wide
# rebrand `sed` (`ai-agent-manager-plugin` -> `loomwright`) rewrote every file under
# `.supervisor/twin/contracts/` in place. `.supervisor/twin/` is gitignored, so nothing in CI or in
# review saw it; the edit never went through the sole writer, so no provenance was appended. All 21
# contract hashes then had no chain-valid `add` entry and `read-system-contract.sh` dropped 100% of
# the store on every read for two weeks. PROOF of the mechanism, not a hypothesis: reversing the
# substitution and re-hashing reproduced a ledger `content_hash` for all 21 of 21 files.
#
# WHAT THIS SCRIPT IS NOT. It is NOT a way around the read gate. The gate is deliberately strict
# (red-team W1: "provenance alone is theater") and nothing here relaxes it — an unverified contract
# stays unverified until a human blesses the bytes now on disk. That blessing is the whole point of
# `--confirm`, and it is why this is report-only by default: re-provenancing says "I have looked at
# these bodies and I accept them", which is a claim only a person can make. Running it blind on a
# store that was poisoned rather than merely rewritten would launder the poison.
#
# HOW IT WORKS. It never writes the store itself. For each contract the read gate drops, it pipes
# the CURRENT on-disk body back through `write-system-contract.sh` — the sole sanctioned writer —
# which validates the entry, appends a real hash-chained `add` over those exact bytes, and rewrites
# the file atomically. The sole-writer and pinned-CWD invariants are therefore untouched, including
# the writer's own worktree refusal.
#
# WHY --subsystem IS THE FILENAME STEM, NOT THE BODY'S LOGICAL id. The writer derives the on-disk
# filename from --subsystem. Passing the body's logical `subsystem:` would, for a store whose
# bodies were rebranded but whose filenames were not, write a SECOND file under a new name and
# leave the stale one behind — 19 of the 21 live contracts are in exactly that state
# (`ai-agent-manager-plugin-scripts-twin-graph.sh` on disk vs `loomwright/scripts/twin-graph.sh` in
# the body). Passing the stem round-trips to the identical path and can never duplicate. The cost,
# stated rather than hidden: the ledger's `subsystem` label for a repaired entry is the sanitized
# filename, not the logical id. That label is metadata — the read gate keys on `content_hash` alone
# and every consumer reads the logical id out of the BODY — so nothing downstream changes. The
# report names each divergence so renaming stays an explicit, separate owner decision.
#
# Usage:  reprovenance-twin-contracts.sh                     report only (default; writes nothing)
#         reprovenance-twin-contracts.sh --confirm           re-provenance every dropped contract
#         reprovenance-twin-contracts.sh --subsystem <stem>  restrict to one contract
#         reprovenance-twin-contracts.sh --source <id>       provenance label (default reprovenance:<date>)
# Exit:   0 clean (report printed, or every repair verified) · 1 a repair failed or did not verify
#         · 2 bad usage / wrong checkout / tooling unavailable.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd || printf '%s' ".")"
READER="${REPROVENANCE_READER:-$HERE/read-system-contract.sh}"
WRITER="${REPROVENANCE_WRITER:-$HERE/write-system-contract.sh}"

CONFIRM=0; ONLY=""; SOURCE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --confirm)     CONFIRM=1; shift ;;
    --subsystem)   ONLY="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --subsystem=*) ONLY="${1#--subsystem=}"; shift ;;
    --source)      SOURCE="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --source=*)    SOURCE="${1#--source=}"; shift ;;
    -h|--help)     sed -n '2,45p' "$0"; exit 0 ;;
    # Unknown flags are REFUSED, not ignored — same reasoning as the writer's own arg parser: a
    # caller reaching for a store-redirecting flag this script does not implement must not get a
    # successful-looking run against a store they did not mean to touch.
    *) echo "reprovenance-twin-contracts: unrecognised argument '$1' (accepted: --confirm, --subsystem, --source, --help). Nothing was done." >&2; exit 2 ;;
  esac
done

GITROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$GITROOT" ] || { echo "reprovenance-twin-contracts: not inside a git repo — refusing." >&2; exit 2; }
# Fail EARLY and by name rather than letting 21 writer invocations each exit 3. A linked worktree's
# top-level `.git` is a FILE; the twin store lives only in the primary checkout.
if [ -f "$GITROOT/.git" ]; then
  echo "reprovenance-twin-contracts: refusing to run from a non-primary checkout ($GITROOT) — its top-level '.git' is a FILE (a linked git worktree or a submodule). The twin store is written only from the primary repo root; re-run there." >&2
  exit 2
fi
cd "$GITROOT" || { echo "reprovenance-twin-contracts: cannot cd to repo root" >&2; exit 2; }

CONTRACT_DIR=".supervisor/twin/contracts"
PROV=".supervisor/twin/.provenance.jsonl"

[ -r "$READER" ] || { echo "reprovenance-twin-contracts: read gate '$READER' is missing or unreadable — trust cannot be determined; refusing rather than guessing." >&2; exit 2; }
if [ ! -d "$CONTRACT_DIR" ]; then
  echo "reprovenance-twin-contracts: no contract store at $CONTRACT_DIR — nothing to do."
  exit 0
fi

# is_trusted <stem> — asks the READ GATE, which is the authority on what "verified" means. Not a
# reimplementation of the chain walk: a second copy would be a drift surface between the two halves
# of one gate, and "present in the ledger" is NOT the same predicate as "chain-valid `add`".
is_trusted() {
  _rp_out="$(bash "$READER" --subsystem "$1" 2>/dev/null || true)"
  grep -qxF "### contract: $1" <<< "$_rp_out"   # herestring, not a pipe: no SIGPIPE status to lose
}

# body_subsystem <file> — the logical id the body declares, or "" when it declares none (2 of the
# 21 live contracts declare none, which is why the stem, not this, drives the write).
body_subsystem() {
  grep -m1 -E '^[[:space:]]*subsystem[[:space:]]*:' "$1" 2>/dev/null \
    | sed -E 's/^[[:space:]]*subsystem[[:space:]]*:[[:space:]]*//; s/^"//; s/"$//; s/^'"'"'//; s/'"'"'$//' \
    || true
}

safe_id() { printf '%s' "$1" | tr '/' '-' | sed -E 's/[^A-Za-z0-9._-]/-/g; s/-+/-/g; s/^-+//; s/-+$//'; }

# ---- Survey ---------------------------------------------------------------
total=0; trusted_n=0
DROPPED_STEMS=""
for f in "$CONTRACT_DIR"/*.md; do
  [ -e "$f" ] || continue          # nullglob-safe: the literal pattern when the dir is empty
  stem="$(basename "$f" .md)"
  [ -n "$ONLY" ] && [ "$stem" != "$ONLY" ] && [ "$stem" != "$(safe_id "$ONLY")" ] && continue
  total=$((total+1))
  if is_trusted "$stem"; then trusted_n=$((trusted_n+1)); else DROPPED_STEMS="${DROPPED_STEMS}${stem}"$'\n'; fi
done

if [ "$total" -eq 0 ]; then
  if [ -n "$ONLY" ]; then echo "reprovenance-twin-contracts: no stored contract matches --subsystem '$ONLY'."; exit 0; fi
  echo "reprovenance-twin-contracts: the contract store is empty — nothing to do."
  exit 0
fi

dropped_n=0
[ -n "$DROPPED_STEMS" ] && dropped_n="$(printf '%s' "$DROPPED_STEMS" | grep -c '^' )"

echo "System Twin contract store: $CONTRACT_DIR"
echo "  stored:      $total"
echo "  verified:    $trusted_n"
echo "  UNVERIFIED:  $dropped_n   (dropped by the read gate — invisible to every consumer)"
echo

if [ "$dropped_n" -eq 0 ]; then
  echo "Every stored contract verifies. Nothing to re-provenance."
  exit 0
fi
if [ "$dropped_n" -eq "$total" ]; then
  echo "!! The read path is 100% DARK: no consumer is receiving ANY contract content."
  echo
fi

echo "Unverified contracts (bodies present on disk, hashes absent from $PROV):"
while IFS= read -r stem; do
  [ -n "$stem" ] || continue
  f="$CONTRACT_DIR/$stem.md"
  logical="$(body_subsystem "$f")"
  printf '  - %s\n' "$f"
  printf '      bytes: %s   modified: %s\n' \
    "$(wc -c < "$f" 2>/dev/null | tr -d ' ')" \
    "$(ls -l "$f" 2>/dev/null | awk '{print $6, $7, $8}')"
  if [ -n "$logical" ]; then
    printf '      body declares subsystem: %s\n' "$logical"
    if [ "$(safe_id "$logical")" != "$stem" ]; then
      printf '      NOTE: that logical id sanitizes to "%s", not the filename stem — the body was renamed but the file was not. Repair writes IN PLACE under the stem; renaming the file is a separate, explicit decision.\n' "$(safe_id "$logical")"
    fi
  else
    printf '      body declares no subsystem: line\n'
  fi
done <<< "$DROPPED_STEMS"
echo

if [ "$CONFIRM" -ne 1 ]; then
  cat <<EOM
REPORT ONLY — nothing was written.

Re-provenancing BLESSES THE BYTES CURRENTLY ON DISK. Read the bodies above (or diff them against
what you expect) before you do it: this is the step that decides an out-of-band edit was legitimate,
and it is exactly the judgement the read gate refuses to make on its own.

  bash $0 --confirm
EOM
  exit 0
fi

# ---- Repair ---------------------------------------------------------------
[ -r "$WRITER" ] || { echo "reprovenance-twin-contracts: sole writer '$WRITER' is missing or unreadable — refusing." >&2; exit 2; }
[ -n "$SOURCE" ] || SOURCE="reprovenance:$(date -u +%Y-%m-%d 2>/dev/null || echo undated)"

echo "Re-provenancing $dropped_n contract(s) through $WRITER (source=$SOURCE)..."
repaired=0; failed=0
while IFS= read -r stem; do
  [ -n "$stem" ] || continue
  f="$CONTRACT_DIR/$stem.md"
  [ -f "$f" ] || continue
  if out="$(bash "$WRITER" --subsystem "$stem" --contract-file "$f" --source "$SOURCE" 2>&1)"; then
    # VERIFY, do not assume. The writer reporting success is not evidence the read gate now accepts
    # the file — that is precisely the assumption the dedup short-circuit made for two weeks while
    # exiting 0 and appending nothing.
    if is_trusted "$stem"; then
      echo "  repaired: $f"
      repaired=$((repaired+1))
    else
      echo "  FAILED (writer exited 0 but the read gate still drops it): $f" >&2
      printf '    writer said: %s\n' "$(printf '%s' "$out" | tr '\n' ' ')" >&2
      failed=$((failed+1))
    fi
  else
    echo "  FAILED (writer refused): $f" >&2
    printf '    writer said: %s\n' "$(printf '%s' "$out" | tr '\n' ' ')" >&2
    failed=$((failed+1))
  fi
done <<< "$DROPPED_STEMS"

echo
echo "repaired: $repaired   failed: $failed"
if [ "$failed" -gt 0 ]; then
  echo "reprovenance-twin-contracts: $failed contract(s) were NOT repaired and remain invisible to consumers." >&2
  exit 1
fi
exit 0
