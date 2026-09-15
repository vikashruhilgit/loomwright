#!/usr/bin/env bash
# verify-helpers.sh — the `/verify` evidence store's ONLY writer and ONLY deriver. Schema authority:
# `docs/RESULT_SCHEMAS.md §VERIFY_EVIDENCE` (layout of `.supervisor/verify/<run_id>/`, the line
# shape, the latest-per-ac_id rule, the `rejected.jsonl` wrapper). Modelled on `automate-helpers.sh`
# (subcommand dispatch, diag to stderr, jq-only JSON construction, atomic temp+mv for derived files).
#
# WHY THIS EXISTS. The QA lane's accounting layer failed because an agent WROTE the roll-up: a
# `failed` scope was reported `completed`, and the summary was overwritten per scope. Here a fact is
# appended exactly once, only after `validate-verify-evidence.py` (sibling path, never a plugin-root
# variable — this file is vendor-neutral core) exits 0; every human-readable summary is DERIVED from
# the lines by `summary-build` on every append; a total can only be computed, never written.
#
# Subcommands:
#   run-id             <slug>              # prints `verify-<YYYYMMDDTHHMMSSZ>-<slug>`; slug lower-cased, [^a-z0-9] runs collapsed to one `-`, edge dashes trimmed
#   evidence-append    <run_dir> <json|->  # compact-to-one-line, validate, then ONE `>>` write; refused input is wrapped RAW into <run_dir>/rejected.jsonl (exit 1); regenerates summary.md (a derivation failure is named on stderr, exit stays 0 — the fact IS stored)
#   summary-build      <run_dir>           # the ONLY reader of evidence.jsonl: derives <run_dir>/summary.md (atomic temp+mv) with a `derived_from:` trailer
#   first-unverdicted  <run_dir>           # prints the first `ac_id` (acs.json order) with NO `ac` line yet, else nothing; exit 0 either way ("fully verdicted" is not an error)
#
# Exit codes: 0 success; 1 refused / generic failure; 2 usage.
# Dependencies: bash 3.2+, jq, python3 (the validator; absent ⇒ every append is REFUSED as
# `validator_unavailable`, never let through), `shasum -a 256` or `sha256sum` (trailer hash).

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
VALIDATOR="$HERE/validate-verify-evidence.py"

diag()  { echo "verify-helpers: $*" >&2; }
die()   { diag "$*"; exit 1; }
usage() { diag "usage: $*"; exit 2; }

# sha256_of <file> — `shasum -a 256` first (macOS ships no sha256sum), `sha256sum` fallback.
sha256_of() {
  local f="$1" h=""
  if command -v shasum >/dev/null 2>&1; then
    h="$(shasum -a 256 "$f" | cut -d' ' -f1)"
  elif command -v sha256sum >/dev/null 2>&1; then
    h="$(sha256sum "$f" | cut -d' ' -f1)"
  fi
  [ -n "$h" ] || die "neither shasum nor sha256sum is available — cannot derive the trailer hash"
  printf '%s\n' "$h"
}

# --------------------------------------------------------------------------- #
# run-id <slug>
# --------------------------------------------------------------------------- #
run_id() {
  local raw="${1:-}" slug
  [ -n "$raw" ] || usage "run-id <slug>"
  slug="$(printf '%s' "$raw" | tr 'A-Z' 'a-z' | sed 's/[^a-z0-9]\{1,\}/-/g; s/^-\{1,\}//; s/-\{1,\}$//')"
  [ -n "$slug" ] || die "run-id: slug '$raw' normalises to nothing"
  printf 'verify-%s-%s\n' "$(date -u +%Y%m%dT%H%M%SZ)" "$slug"
}

# --------------------------------------------------------------------------- #
# evidence-append <run_dir> <json|->
# --------------------------------------------------------------------------- #
# The ONLY writer of the store, and it NEVER READS the store file — derivation belongs to
# summary_build (a separate function, the only reader). The function body names the store file on
# exactly ONE line: the single `printf … >>` write (the shell's `>>` is O_APPEND, so two concurrent
# appenders never interleave bytes and there is no read-modify-write window). Validator status is
# captured as `$?` in the statement AFTER the substitution — `local x="$(…)"` or `if ! x=$(…)` would
# lose it, and a lost status is exactly how an invalid fact would reach the store. The record is
# canonicalised to one compact line BEFORE validation, so the validated bytes ARE the stored bytes.
evidence_append() {
  local run_dir="${1:-}" input="${2:-}" json line out rc reason ts
  { [ -n "$run_dir" ] && [ -n "$input" ]; } || usage "evidence-append <run_dir> <json|->"
  if [ "$input" = "-" ]; then json="$(cat)"; else json="$input"; fi
  [ -n "$json" ] || die "evidence-append: empty record"
  mkdir -p "$run_dir/artifacts" || die "evidence-append: cannot create $run_dir/artifacts"
  # Canonicalise to ONE compact line BEFORE validating, so the bytes validated are the bytes stored.
  # `json.loads` accepts a pretty-printed (multi-line) record, and writing that verbatim would put N
  # physical lines in the store for one fact — breaking one-object-per-line, the `derived_from:` count
  # and the store's own file-mode re-validation. `jq -cs` reduces exactly ONE JSON value to its
  # compact form; anything else (not JSON, two concatenated values) is left RAW so the validator
  # refuses it with its own reason and `rejected.jsonl` still carries the input verbatim.
  line="$(printf '%s' "$json" | jq -cs 'if length == 1 then .[0] else error("not exactly one JSON value") end' 2>/dev/null)" || line="$json"
  out="$(python3 "$VALIDATOR" --line "$line" 2>/dev/null)"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '%s\n' "$line" >> "$run_dir/evidence.jsonl" || die "evidence-append: append failed"
    # Derivation runs in a SUBSHELL: every failure inside summary_build is a `die` (exit 1), and in
    # THIS process that would turn a successful append into exit 1 — indistinguishable from a refusal,
    # so a caller retrying on rc 1 would replay the append and duplicate the fact. The fact is stored;
    # the derivation failure is named on stderr and the exit status stays 0.
    ( summary_build "$run_dir" ) || diag "evidence-append: summary-build failed after a successful append (the record IS stored; run summary-build on $run_dir to see why)"
    return 0
  fi
  case "$rc" in
    1)   reason="$(printf '%s' "$out" | jq -r '.reason // empty' 2>/dev/null)"
         [ -n "$reason" ] || reason="validator_rejected" ;;
    127) reason="validator_unavailable" ;;
    *)   reason="validator_error:$rc" ;;
  esac
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  jq -cn --arg ts "$ts" --arg reason "$reason" --arg line "$json" \
    '{rejected_at:$ts,reason:$reason,line:$line}' >> "$run_dir/rejected.jsonl" \
    || die "evidence-append: could not record the refusal in $run_dir/rejected.jsonl"
  diag "evidence-append: REFUSED ($reason) — recorded in $run_dir/rejected.jsonl"
  return 1
}

# --------------------------------------------------------------------------- #
# summary-build <run_dir>
# --------------------------------------------------------------------------- #
# The ONLY reader of evidence.jsonl and the ONLY writer of summary.md. `jq -s` over the file (absent
# or empty ⇒ a "0 lines" summary — the hash is of /dev/null, never skipped). Latest-per-ac_id and
# latest-per-env-step are computed by input order (`_i` index, `max_by`), never by timestamp. The
# counts row is COMPUTED over the latest-per-ac_id set. Written to `summary.md.tmp.$$` then `mv -f`,
# so a crash never leaves a half summary. No agent ever writes this file.
summary_build() {
  local run_dir="${1:-}" src body tmp n hash rc
  [ -n "$run_dir" ] || usage "summary-build <run_dir>"
  mkdir -p "$run_dir" || die "summary-build: cannot create $run_dir"
  src="$run_dir/evidence.jsonl"
  [ -f "$src" ] || src=/dev/null
  tmp="$run_dir/summary.md.tmp.$$"
  body="$(jq -rs '
    def esc: tostring | gsub("\\|"; "\\|") | gsub("\n"; " ");
    def show: if . == null then "—" else esc end;
    def listish: if (. == null) or (. == []) then "—" else (map(tostring) | join(", ") | esc) end;
    def latest_by(f): group_by(f) | map(max_by(._i)) | sort_by(._i);
    (to_entries | map(.value + {_i: .key})) as $L
    | ([$L[] | select(.event == "run_start")] | last) as $rs
    | (if $rs != null then $rs.run_id elif ($L | length) > 0 then $L[-1].run_id else "(none)" end) as $run_id
    | ([$L[] | select(.event == "env")] | latest_by(.step)) as $env
    | ([$L[] | select(.event == "auth")] | last) as $auth
    | ([$L[] | select(.event == "ac")] | latest_by(.ac_id)) as $acs
    | [$L[] | select(.event == "issue")] as $issues
    | [$L[] | select(.event == "pause" or .event == "resume")] as $pr
    | ([$L[] | select(.event == "run_end")] | last) as $re
    | ([$L[] | select(.event == "ac" or .event == "issue") | (.artifacts // [])[] | tostring] | unique) as $arts
    | def cnt(v): [$acs[] | select(.verdict == v)] | length;
    [
      "# Verify run \($run_id) — summary",
      "> DERIVED by `verify-helpers.sh summary-build` from evidence.jsonl on every append — do not edit; edits are overwritten.",
      "",
      "## Run",
      (if $rs == null then "_no run_start line_" else
        "- ticket: \($rs.ticket_path | show) (\($rs.ticket_kind | show))",
        "- branch: \($rs.branch | show)",
        "- head_sha: \($rs.head_sha | show) · base_sha: \($rs.base_sha | show)",
        "- env_contract_hash: \(if $rs.env_contract_hash == null then "(none)" else ($rs.env_contract_hash | esc) end)"
      end),
      "",
      "## Environment (latest line per step)",
      (if ($env | length) == 0 then "_no env lines_" else
        "| step | outcome | reason |",
        "|---|---|---|",
        ($env[] | "| \(.step | show) | \(.outcome | show) | \(.reason | show) |")
      end),
      "",
      "## Auth",
      (if $auth == null then "_no auth line_" else "- state: \($auth.state | show)" end),
      "",
      "## Acceptance criteria (latest line per ac_id)",
      (if ($acs | length) == 0 then "_no ac lines_" else
        "| ac_id | scope | verdict | classification | reason | artifacts |",
        "|---|---|---|---|---|---|",
        ($acs[] | "| \(.ac_id | show) | \(.scope | show) | \(.verdict | show) | \(.classification | show) | \(.reason | show) | \(.artifacts | listish) |")
      end),
      "",
      "PASS: \(cnt("PASS")) · FAIL: \(cnt("FAIL")) · BLOCKED: \(cnt("BLOCKED")) · NOT_VERIFIABLE: \(cnt("NOT_VERIFIABLE")) · total: \($acs | length)",
      "",
      "## Issues",
      (if ($issues | length) == 0 then "_none_" else
        ($issues[] | "- [\(.severity | show)] \(.text | show)\(if .route == null then "" else " (route: \(.route | esc))" end)")
      end),
      "",
      "## Pauses / resumes",
      (if ($pr | length) == 0 then "_none_" else ($pr[] | "- \(.ts | show) \(.event): \(.reason | show)") end),
      "",
      "## Artifacts",
      (if ($arts | length) == 0 then "_none_" else ($arts[] | "- \(esc)") end),
      "",
      "## Run end",
      (if $re == null then "_no run_end line_" else "- status: \($re.status | show) at \($re.ts | show)" end),
      ""
    ] | .[]
  ' "$src")"
  rc=$?
  [ "$rc" -eq 0 ] || die "summary-build: jq could not derive the summary from $src (rc=$rc)"
  n=$(( $(wc -l < "$src") ))
  hash="$(sha256_of "$src")" || exit 1
  {
    printf '%s\n' "$body"
    printf 'derived_from: %s lines, sha256 %s\n' "$n" "$hash"
  } > "$tmp" || die "summary-build: cannot write $tmp"
  mv -f "$tmp" "$run_dir/summary.md" || die "summary-build: cannot move $tmp into place"
}

# --------------------------------------------------------------------------- #
# first-unverdicted <run_dir>
# --------------------------------------------------------------------------- #
# AC6 (`/verify --resume`'s resume-position derivation). Reads `<run_dir>/acs.json` for the ORDERED
# `ac_id` list, and `evidence.jsonl` for the SET of `ac_id`s carrying at least one `{event:ac}` line
# (EXISTENCE, not "latest" — any prior line, of any verdict, means that AC already ran). Prints the
# first `ac_id` from the ordered list NOT in that set; prints NOTHING when every `ac_id` is covered —
# a distinct, documented "nothing left" signal, never a nonzero exit, since full coverage is a normal
# state, not an error. Mirrors the `latest_by` / done-set idiom already used by `summary_build` /
# `walk_block_remaining` (this file / verify-run.sh).
first_unverdicted() {
  local run_dir="${1:-}" done_ids
  [ -n "$run_dir" ] || usage "first-unverdicted <run_dir>"
  [ -f "$run_dir/acs.json" ] || die "first-unverdicted: no acs.json in $run_dir — run preflight first [acs_missing]"
  done_ids="[]"
  [ -f "$run_dir/evidence.jsonl" ] && done_ids="$(jq -cs '[.[] | select(.event == "ac") | .ac_id]' "$run_dir/evidence.jsonl" 2>/dev/null)"
  [ -n "$done_ids" ] || done_ids="[]"
  jq -r --argjson done "$done_ids" \
    '[.acs[].ac_id | select(. as $i | ($done | index($i)) == null)] | first // empty' \
    "$run_dir/acs.json"
}

main() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    run-id)             run_id "$@" ;;
    evidence-append)    evidence_append "$@" ;;
    summary-build)      summary_build "$@" ;;
    first-unverdicted)  first_unverdicted "$@" ;;
    ""|-h|--help)
      grep -E '^#   [a-z]' "$0" | sed 's/^#   /  /'
      ;;
    *) die "unknown subcommand: $cmd (try --help)" ;;
  esac
}

main "$@"
