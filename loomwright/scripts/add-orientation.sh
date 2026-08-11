#!/usr/bin/env bash
# add-orientation.sh — the SOLE WRITER for the committed .agent/orientation/ memo store.
# (New file — orientation-memo substrate writer side, cloned from the add-rule.sh sole-writer
#  discipline: path-containment slug rules, hard REJECT of hostile input, temp-file + atomic-mv
#  writes, read-back verification.)
#
# The committed store is written ONLY via this helper, with per-item HUMAN approval — never by
# automated runs (those write proposals to the gitignored .supervisor/orientation-proposals/
# instead; a human promotes an approved proposal through this writer). Human approval is
# MECHANIZED, not prose: a confirm-only gate (cloned from add-rule.sh) writes ONLY when
# --confirm is passed OR an interactive TTY user answers y. Any other invocation (e.g. an
# automated non-TTY run without --confirm) is a DRY-RUN: it prints the planned memo + target
# path and exits 0 WITHOUT writing.
#
# WRITE DISCIPLINE (all enforced here in code, never as prose):
#   1. Slug containment. <area-slug> must be a single [a-z0-9-]+ segment. REJECT — abort,
#      non-zero, never silently sanitize/rewrite — any slug with '/', '..', a leading dot,
#      a leading or trailing '-', spaces/metacharacters, or that is empty. The write can
#      NEVER escape the store dir.
#   2. Cap. REJECT when summary+body exceed 1000 chars, and when the COMPOSED memo file
#      (header + summary + body) exceeds the 1000-char hard cap — so this writer can never
#      author a memo read-orientation.sh would later skip as over-cap.
#   3. Hostile markers. REJECT a summary/body containing any of the same instruction-injection
#      markers the reader scans for (case-insensitive, fixed-string): "ignore previous",
#      "ignore all previous", "system prompt", "you must now", "disregard", "<system>",
#      "[INST]". The scan runs against a WHITESPACE-NORMALIZED copy of the content (newlines/
#      tabs → single spaces) so a marker split across lines cannot evade it. Keep the list AND
#      the normalization in sync with read-orientation.sh.
#   4. Header stamp: current UTC ISO-8601 time + `git rev-parse --short HEAD` + `areas:` from
#      --areas (default: the slug itself as a path prefix). Areas are validated to a benign
#      character set (no '..', no '|'/metachars — '|' would break header parsing).
#   5. Confirm-only gate (per-item human approval). Write only when --confirm OR an
#      interactive TTY confirms y. Otherwise print the planned memo + target and exit 0
#      WITHOUT writing.
#   6. Write via temp file + atomic `mv` INSIDE the store dir. One memo per area: an existing
#      <area-slug>.md is atomically REPLACED (memo update), never partially written.
#   7. Read-back verify: header line parses + file under cap; on verify failure of a NEW memo
#      remove the written file; on verify failure of a memo UPDATE restore the prior memo
#      (stashed before the mv) — then exit non-zero either way.
#
# CURATION ACTIONS — `--supersedes` and `--retract` (mirrors curate-postmortem.sh's
# --target/--reason/--replacement/--confirm shape + validate-before-write + fail-loud
# discipline; rules + orientation have no existing curation verb, per the brief's Prior art).
# Both actions take NO positional area-slug/summary/body — only --target/--reason(/--replacement)
# + --confirm. Both validate everything BEFORE any write, and leave the store byte-identical on
# any rejection.
#
#   add-orientation.sh --supersedes --target <old-slug> --replacement <new-slug> \
#                       --reason <text> [--confirm] [--store <dir>] [--repo <dir>]
#     Stamps `supersedes: <old-slug>` into the REPLACEMENT memo's line-1 header (pinned BETWEEN
#     head_sha and areas — see read-orientation.sh's encoding contract), overwriting the field if
#     already present. --replacement is REQUIRED (a supersede without one is indistinguishable
#     from a retract). --target and --replacement must both already exist as parseable memos and
#     must differ. Does NOT touch/remove the target file — read-orientation.sh is what hides a
#     superseded memo from output, not deletion. The composed (updated) replacement file must
#     still satisfy the 1000-char cap.
#
#   add-orientation.sh --retract --target <area-slug> --reason <text> \
#                       [--confirm] [--store <dir>] [--repo <dir>]
#     REMOVES the memo file at <area-slug>.md. There is no in-store home for a post-deletion
#     reason (no provenance file for this store — see the brief's Retraction table), so this
#     writer PRINTS a one-line provenance reason to stdout; the commit is the durable record. NO
#     sidecar, no tombstone object is written. --replacement is REJECTED (retract has no
#     replacement — supersede is the verb for that).
#
#   Exit codes for BOTH curation actions (distinct from the create/update path below):
#     0 = applied + verified, OR dry-run (no --confirm — nothing written, plan printed) ;
#     2 = validation / write error (fail loud, no partial write).
#
# Usage:
#   add-orientation.sh <area-slug> <summary-line> <body-file-or-'-'>
#                      [--confirm] [--store <dir>] [--repo <dir>] [--areas "<paths>"]
#   defaults: repo = cwd git root; store = <repo>/.agent/orientation
#   env overrides (for tests): ORIENTATION_STORE_DIR / ORIENTATION_REPO_DIR
#   precedence: flags > env > defaults. Body '-' reads stdin.
# Exit:  0 = wrote + verified, OR dry-run (no --confirm, non-interactive: printed plan, wrote
#        nothing); non-zero = rejected / error (no partial write).

set -euo pipefail

PROG="add-orientation.sh"

die() { printf '%s: %s\n' "$PROG" "$1" >&2; exit "${2:-1}"; }

# ---------------------------------------------------------------------------
# WRITE-TIME VALIDATION — LOAD GUARD (decision (a) of the write-time-validation brief).
# See validate-entry.sh's LOAD GUARD CONTRACT. Three clauses, ALL required:
#   (i)   `. validate-entry.sh` must exit 0. `|| true` is FORBIDDEN on that line — discarding the
#         status IS the silent unvalidated append this design does not sanction. The status is
#         CAPTURED instead, and the caller's own errexit state is saved and restored around the
#         source so this block cannot change the shell options the rest of the script runs under.
#   (ii)  all five validator functions must be present. Bash defines every function ABOVE a syntax
#         error before aborting the parse, so a truncated helper leaves SOME validators defined —
#         a one-function probe would report "examined and clean" over half a validator.
#   (iii) $VALIDATE_ENTRY_CONTRACT must equal the HARDCODED literal below. Comparing against a
#         variable the helper exports (VALIDATE_ENTRY_CONTRACT_EXPECTED), or iterating the list it
#         exports ($VALIDATE_ENTRY_FUNCTIONS), would be CIRCULAR: both are assigned ABOVE the
#         sentinel, so a truncated copy could define them and pass its own test.
# Any shortfall is REFUSE_VALIDATOR_UNAVAILABLE, exit 2 (could-not-examine), nothing written.
# ---------------------------------------------------------------------------
REFUSE_VALIDATOR_UNAVAILABLE="REFUSE_VALIDATOR_UNAVAILABLE"
VALIDATE_ENTRY_CONTRACT_REQUIRED="validate-entry/1"
VALIDATOR_REQUIRED_FUNCS="validate_duplicate validate_contradiction validate_provenance validate_dead_reference validate_cross_repo_reference"

# Resolved BEFORE any `cd`: $0 may be relative, and three of these writers cd to the repo root.
VE_HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd || printf '%s' ".")"

# _ve_load_validator — runs the three-clause guard. Called on the write path, never at parse time.
_ve_load_validator() {
  VALIDATOR="${ADD_ORIENTATION_VALIDATOR:-}"
  if [ -z "$VALIDATOR" ]; then
    if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/validate-entry.sh" ]; then
      VALIDATOR="${CLAUDE_PLUGIN_ROOT}/scripts/validate-entry.sh"
    else
      VALIDATOR="$VE_HERE/validate-entry.sh"
    fi
  fi

  # ---- LOAD GUARD BEGIN -----------------------------------------------------
  # BEGIN/END delimit the guard as ONE replaceable unit so this suite's mandated mutation control
  # can replace it with `|| true` in a single edit and prove AC2 goes RED. Structural, not decor.
  if [ ! -f "$VALIDATOR" ] || [ ! -r "$VALIDATOR" ]; then
    printf '%s: %s — the shared write-time validator is missing or unreadable at "%s", so this entry could not be examined; refusing rather than appending it unvalidated. Nothing was written.
'       "add-orientation.sh" "$REFUSE_VALIDATOR_UNAVAILABLE" "$VALIDATOR" >&2
    exit 2
  fi

  # Clause (i). errexit is saved/restored rather than assumed: these five writers do not all run
  # under `set -e` (write-system-contract.sh is `set -uo pipefail`), so an unconditional `set -e`
  # here would silently change the failure semantics of everything downstream.
  case "$-" in *e*) _ve_had_e=1 ;; *) _ve_had_e=0 ;; esac
  set +e
  # shellcheck source=/dev/null
  . "$VALIDATOR"
  _ve_src_rc=$?
  if [ "$_ve_had_e" -eq 1 ]; then set -e; fi
  if [ "$_ve_src_rc" -ne 0 ]; then
    printf '%s: %s — sourcing the shared write-time validator "%s" failed (status %s: unparseable or truncated), so this entry could not be examined. Nothing was written.
'       "add-orientation.sh" "$REFUSE_VALIDATOR_UNAVAILABLE" "$VALIDATOR" "$_ve_src_rc" >&2
    exit 2
  fi

  # Clause (ii). All five are probed, plus the aggregate the call site actually uses — never one
  # name as a proxy for the rest.
  for _vef in $VALIDATOR_REQUIRED_FUNCS validate_entry_all; do
    if ! command -v "$_vef" >/dev/null 2>&1; then
      printf '%s: %s — the shared write-time validator loaded but "%s" is not defined (a partially-loaded validator would report "examined and clean" over half a check), so this entry could not be examined. Nothing was written.
'         "add-orientation.sh" "$REFUSE_VALIDATOR_UNAVAILABLE" "$_vef" >&2
      exit 2
    fi
  done

  # Clause (iii). Compared against the HARDCODED literal — see the circularity note above.
  if [ "${VALIDATE_ENTRY_CONTRACT:-}" != "$VALIDATE_ENTRY_CONTRACT_REQUIRED" ]; then
    printf '%s: %s — the shared write-time validator contract sentinel is "%s", not the expected "%s" (the file is truncated, or its contract changed), so this entry could not be examined. Nothing was written.
'       "add-orientation.sh" "$REFUSE_VALIDATOR_UNAVAILABLE" "${VALIDATE_ENTRY_CONTRACT:-<unset>}" "$VALIDATE_ENTRY_CONTRACT_REQUIRED" >&2
    exit 2
  fi
  # ---- LOAD GUARD END -------------------------------------------------------
}


# ---------------------------------------------------------------------------
# Parse args (three positionals + optional flags for the create/update path; --target/
# --reason/--replacement/--confirm for the --retract / --supersedes curation actions).
# ---------------------------------------------------------------------------
slug=""
summary=""
body_src=""
store_arg=""
repo_arg=""
areas_arg=""
confirm=0
pos=0
curate_target=""
curate_reason=""
replacement_set=0
replacement=""
retract_flag=0
supersede_flag=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --store) [ "$#" -ge 2 ] || die "--store requires a value"; store_arg="$2"; shift 2 ;;
    --repo)  [ "$#" -ge 2 ] || die "--repo requires a value";  repo_arg="$2";  shift 2 ;;
    --areas) [ "$#" -ge 2 ] || die "--areas requires a value"; areas_arg="$2"; shift 2 ;;
    --confirm) confirm=1; shift ;;
    --target)      [ "$#" -ge 2 ] || die "--target requires a value";      curate_target="$2"; shift 2 ;;
    --reason)      [ "$#" -ge 2 ] || die "--reason requires a value";      curate_reason="$2"; shift 2 ;;
    --replacement) [ "$#" -ge 2 ] || die "--replacement requires a value"; replacement_set=1; replacement="$2"; shift 2 ;;
    --retract)    retract_flag=1;   shift ;;
    --supersedes) supersede_flag=1; shift ;;
    -h|--help)
      grep -E '^# ' "$0" | sed -E 's/^# ?//'
      exit 0 ;;
    --*) die "unknown flag: $1 (see --help)" ;;
    *)
      pos=$((pos + 1))
      case "$pos" in
        1) slug="$1" ;;
        2) summary="$1" ;;
        3) body_src="$1" ;;
        *) die "too many positional arguments (see --help)" ;;
      esac
      shift ;;
  esac
done

# ---------------------------------------------------------------------------
# Slug containment helper — shared by the create/update path's area-slug AND the curation
# actions' --target/--replacement. REJECT hostile slugs, never sanitize (the write can never
# escape the store dir). Explicit cases first for clear diagnostics; the final class check is
# the containment invariant itself. $3 = exit code (default 1, matching the original
# create-path behavior); curation callers pass 2 (fail-loud, per curate-postmortem.sh).
# ---------------------------------------------------------------------------
validate_slug() {
  local s="$1" label="$2" ec="${3:-1}"
  case "$s" in
    "")   die "rejected: $label is empty" "$ec" ;;
    */*)  die "rejected: $label may not contain '/': $s" "$ec" ;;
    *..*) die "rejected: $label may not contain '..': $s" "$ec" ;;
    .*)   die "rejected: $label may not start with a dot: $s" "$ec" ;;
    -*|*-) die "rejected: $label may not start or end with '-': $s" "$ec" ;;
    readme) die "rejected: $label 'readme' is reserved (collides with the store's README.md on case-insensitive filesystems)" "$ec" ;;
  esac
  case "$s" in
    *[!a-z0-9-]*) die "rejected: $label must be a single [a-z0-9-]+ segment (no spaces/metachars/uppercase): $s" "$ec" ;;
  esac
}

# ---------------------------------------------------------------------------
# Resolve repo + store (flags > env > defaults) — needed by BOTH the curation actions and
# the create/update path below, so resolve once, early.
# ---------------------------------------------------------------------------
REPO_DIR="${repo_arg:-${ORIENTATION_REPO_DIR:-}}"
if [ -z "$REPO_DIR" ]; then
  REPO_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
STORE_DIR="${store_arg:-${ORIENTATION_STORE_DIR:-}}"
[ -n "$STORE_DIR" ] || STORE_DIR="$REPO_DIR/.agent/orientation"

# ---- Worktree guard (red-team F1) — AC10b ---------------------------------
# This writer shipped with NO worktree guard: `git rev-parse --show-toplevel` in a LINKED worktree
# returns the WORKTREE's own toplevel, so a worker in a worktree wrote to the worktree's committed
# store and lost it on `git worktree remove`. A linked worktree's top-level carries a `.git` FILE;
# the main checkout carries a directory.
# The guard evaluates the RESOLVED $REPO_DIR, NOT $PWD. That is load-bearing here and has no
# write-lessons.sh analogue: this writer accepts `--repo` / $ORIENTATION_REPO_DIR, so a cwd-only
# guard would pass an explicit --repo pointing straight at a worktree.
# DELIBERATELY NOT COPIED from write-lessons.sh: its hard `exit 2` outside a git repo. This
# writer's documented non-repo fallback stays `pwd`, UNCHANGED — only the worktree case is refused.
if [ -f "$REPO_DIR/.git" ]; then
  die "refusing to write from a git worktree ($REPO_DIR) — orientation memos are written only from the repo root (red-team F1): a write here would diverge and be lost on \`git worktree remove\`." 3
fi

# ---------------------------------------------------------------------------
# Curation actions: --retract and --supersedes. Both take NO positional area-slug/summary/
# body — --target/--reason(/--replacement)/--confirm only. Exit codes: 0 = applied,
# dry-run also exits 0 (nothing written) — matching add-rule.sh and this file's create path;
# 2 = validation/write error (store left byte-identical).
# ---------------------------------------------------------------------------
do_retract() {
  [ -n "$curate_target" ] || die "rejected: --target is required for --retract" 2
  validate_slug "$curate_target" "--target" 2
  [ -n "$curate_reason" ] || die "rejected: --reason is required for --retract" 2
  [ "$replacement_set" -ne 1 ] \
    || die "rejected: --replacement is only meaningful for --supersedes (a retract has no replacement — use --supersedes if you meant to supersede)" 2

  local retract_path="$STORE_DIR/$curate_target.md"
  [ -f "$retract_path" ] || die "rejected: no memo found for --target '$curate_target' at $retract_path" 2

  if [ "$confirm" -ne 1 ]; then
    printf 'PLANNED RETRACT (not applied — pass --confirm to apply):\n'
    printf '  target: %s\n' "$retract_path"
    printf '  reason: %s\n' "$curate_reason"
    printf '%s: dry-run, pass --confirm to retract (nothing removed)\n' "$PROG" >&2
    exit 0
  fi

  rm -f "$retract_path" || die "removal failed: $retract_path" 2
  [ ! -f "$retract_path" ] || die "read-back verify failed: file still present after rm: $retract_path" 2

  printf '%s: retracted orientation memo %s (reason: %s) from %s\n' \
    "$PROG" "$curate_target" "$curate_reason" "$STORE_DIR"
  exit 0
}

do_supersede() {
  [ -n "$curate_target" ] || die "rejected: --target is required for --supersedes" 2
  validate_slug "$curate_target" "--target" 2
  [ "$replacement_set" -eq 1 ] \
    || die "rejected: --supersedes requires --replacement <new-slug> (a supersede without a replacement is indistinguishable from a retract — use --retract instead)" 2
  validate_slug "$replacement" "--replacement" 2
  [ -n "$curate_reason" ] || die "rejected: --reason is required for --supersedes" 2
  [ "$curate_target" != "$replacement" ] \
    || die "rejected: --target and --replacement must differ (a memo cannot supersede itself): $curate_target" 2

  local supersede_target_path="$STORE_DIR/$curate_target.md"
  local repl_path="$STORE_DIR/$replacement.md"
  [ -f "$supersede_target_path" ] || die "rejected: no memo found for --target '$curate_target' at $supersede_target_path" 2
  [ -f "$repl_path" ] || die "rejected: no memo found for --replacement '$replacement' at $repl_path" 2

  # --target must ALSO be a parseable memo, not merely a file that happens to exist at that
  # path (matches the doc contract in this file's header comment + commands/dreaming.md: "both
  # ... must already exist as parseable memos"). This is enforced even though the write itself
  # only needs the target's SLUG (not its header content) — an unparseable target would fail PASS
  # A validation in read-orientation.sh, silently downgrading the freshly-written supersedes edge
  # to "dangling" (ignored) at read time; fail loud here instead of authoring a no-op edge.
  local thline twritten_at thead_sha
  thline="$(head -n 1 "$supersede_target_path" 2>/dev/null)"
  twritten_at="$(printf '%s' "$thline" | sed -nE 's/^<!-- written_at: ([^|]+) \|.*-->$/\1/p' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  thead_sha="$(printf '%s' "$thline"   | sed -nE 's/^<!-- written_at: [^|]+ \| head_sha: ([^|]+) \|.*-->$/\1/p' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  if [ -z "$twritten_at" ] || [ -z "$thead_sha" ]; then
    die "rejected: --target memo header is unparseable: $supersede_target_path" 2
  fi

  local rhline rwritten_at rhead_sha rareas
  rhline="$(head -n 1 "$repl_path" 2>/dev/null)"
  rwritten_at="$(printf '%s' "$rhline" | sed -nE 's/^<!-- written_at: ([^|]+) \|.*-->$/\1/p' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  rhead_sha="$(printf '%s' "$rhline"   | sed -nE 's/^<!-- written_at: [^|]+ \| head_sha: ([^|]+) \|.*-->$/\1/p' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  rareas="$(printf '%s' "$rhline"      | sed -nE 's/^<!-- .*areas: (.*) -->$/\1/p' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  if [ -z "$rwritten_at" ] || [ -z "$rhead_sha" ]; then
    die "rejected: --replacement memo header is unparseable: $repl_path" 2
  fi

  local new_header="<!-- written_at: ${rwritten_at} | head_sha: ${rhead_sha} | supersedes: ${curate_target} | areas: ${rareas} -->"

  local rwork rcompose rtotal
  rwork="$(mktemp -d)" || die "mktemp failed" 2
  rcompose="$rwork/compose"
  {
    printf '%s\n' "$new_header"
    tail -n +2 "$repl_path" 2>/dev/null
  } > "$rcompose"

  rtotal="$(wc -c < "$rcompose" | tr -d '[:space:]')"
  if [ "$rtotal" -gt 1000 ]; then
    rm -rf "$rwork" 2>/dev/null
    die "rejected: replacement memo would exceed the 1000-char hard cap ($rtotal chars) after adding the supersedes field" 2
  fi

  if [ "$confirm" -ne 1 ]; then
    printf 'PLANNED SUPERSEDE (not applied — pass --confirm to apply):\n'
    printf '  target: %s\n' "$curate_target"
    printf '  replacement: %s\n' "$repl_path"
    printf '  reason: %s\n' "$curate_reason"
    printf '  new header: %s\n' "$new_header"
    rm -rf "$rwork" 2>/dev/null
    printf '%s: dry-run, pass --confirm to apply (nothing written)\n' "$PROG" >&2
    exit 0
  fi

  local rprior rtmp_in_store
  rprior="$rwork/prior"
  cat "$repl_path" > "$rprior" || { rm -rf "$rwork" 2>/dev/null; die "could not stash prior replacement memo before update: $repl_path" 2; }

  rtmp_in_store="$(mktemp "$STORE_DIR/.add-orientation.XXXXXX")" || { rm -rf "$rwork" 2>/dev/null; die "mktemp in store failed" 2; }
  cat "$rcompose" > "$rtmp_in_store" || { rm -f "$rtmp_in_store"; rm -rf "$rwork" 2>/dev/null; die "could not stage memo in store dir" 2; }
  if ! mv -f "$rtmp_in_store" "$repl_path"; then
    rm -f "$rtmp_in_store" 2>/dev/null
    rm -rf "$rwork" 2>/dev/null
    die "atomic move failed (replacement left untouched): $repl_path" 2
  fi

  local rfirst_line rverify_total
  rfirst_line="$(head -n 1 "$repl_path" 2>/dev/null)"
  if ! printf '%s' "$rfirst_line" \
     | grep -qE '^<!-- written_at: .+ \| head_sha: .+ \| supersedes: .+ \| areas: .* -->$'; then
    cat "$rprior" > "$repl_path" 2>/dev/null
    rm -rf "$rwork" 2>/dev/null
    die "read-back verify failed: header line missing/unparseable after supersede — restored prior replacement memo at $repl_path" 2
  fi
  rverify_total="$(wc -c < "$repl_path" | tr -d '[:space:]')"
  if [ "$rverify_total" -gt 1000 ]; then
    cat "$rprior" > "$repl_path" 2>/dev/null
    rm -rf "$rwork" 2>/dev/null
    die "read-back verify failed: written file $rverify_total chars exceeds cap after supersede — restored prior replacement memo at $repl_path" 2
  fi

  rm -rf "$rwork" 2>/dev/null
  printf '%s: replacement %s now supersedes %s (reason: %s); %s chars\n' \
    "$PROG" "$replacement" "$curate_target" "$curate_reason" "$rverify_total"
  exit 0
}

if [ "$retract_flag" -eq 1 ] || [ "$supersede_flag" -eq 1 ]; then
  if [ "$retract_flag" -eq 1 ] && [ "$supersede_flag" -eq 1 ]; then
    die "rejected: cannot combine --retract and --supersedes in one invocation" 2
  fi
  [ "$pos" -eq 0 ] \
    || die "rejected: --retract/--supersedes take no positional area-slug/summary/body arguments — use --target/--replacement" 2
  if [ "$retract_flag" -eq 1 ]; then
    do_retract
  else
    do_supersede
  fi
  exit 3   # unreachable — do_retract/do_supersede always exit themselves
fi

[ "$pos" -eq 3 ] || die "usage: $PROG <area-slug> <summary-line> <body-file-or-'-'> [--confirm] [--store <dir>] [--repo <dir>] [--areas \"<paths>\"]"

# ---------------------------------------------------------------------------
# 1. Slug containment (see validate_slug() above).
# ---------------------------------------------------------------------------
validate_slug "$slug" "area-slug"

# ---------------------------------------------------------------------------
# Summary + body intake.
# ---------------------------------------------------------------------------
[ -n "$summary" ] || die "rejected: summary-line is empty"
NL=$'\n'   # NB: $(printf '\n') would strip to "" and match everything — use $'\n' (bash-3.2 ok)
case "$summary" in
  *"$NL"*) die "rejected: summary-line must be a single line" ;;
esac

work="$(mktemp -d)" || die "mktemp failed"
tmp_in_store=""
trap 'rm -rf "$work" 2>/dev/null; [ -n "$tmp_in_store" ] && rm -f "$tmp_in_store" 2>/dev/null || true' EXIT

body_tmp="$work/body"
if [ "$body_src" = "-" ]; then
  cat > "$body_tmp"
else
  [ -f "$body_src" ] || die "body file not found: $body_src"
  cat "$body_src" > "$body_tmp"
fi

# ---------------------------------------------------------------------------
# 2. Cap: summary+body ≤ 1000 chars (the composed-file cap is re-checked below).
# ---------------------------------------------------------------------------
body_len="$(wc -c < "$body_tmp" | tr -d '[:space:]')"
sum_len="${#summary}"
if [ $((body_len + sum_len)) -gt 1000 ]; then
  die "rejected: summary+body total $((body_len + sum_len)) chars exceeds the 1000-char hard cap"
fi

# ---------------------------------------------------------------------------
# 3. Hostile / instruction-injection markers ⇒ REJECT (same list the reader scans;
#    case-insensitive, fixed-string; memo text is grepped as data, never executed).
#    The grep runs against a WHITESPACE-NORMALIZED copy (newlines/tabs → single spaces,
#    runs squeezed) so a marker split across lines cannot evade the line-scoped scan.
#    Keep the marker list AND this normalization in sync with read-orientation.sh.
# ---------------------------------------------------------------------------
scan="$work/scan"
{ printf '%s\n' "$summary"; cat "$body_tmp"; } \
  | LC_ALL=C tr '\r\n\t' '   ' | tr -s ' ' > "$scan"
for m in "ignore previous" "ignore all previous" "system prompt" "you must now" \
         "disregard" "<system>" "[INST]"; do
  if LC_ALL=C grep -qiF -- "$m" "$scan" 2>/dev/null; then
    die "rejected: summary/body contains a hostile instruction-injection marker: '$m'"
  fi
done

# ---------------------------------------------------------------------------
# 4. Header stamp: UTC now + short HEAD sha + areas (default: the slug as a path prefix).
#    (REPO_DIR / STORE_DIR were already resolved early, above, for both curation actions and
#    this create/update path.)
# ---------------------------------------------------------------------------
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
sha="$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null)" \
  || die "cannot resolve HEAD sha in repo: $REPO_DIR (is it a git repo with commits?)"

areas_val="${areas_arg:-$slug}"
# Bare-slug fallback rarely matches a real tracked path, so the reader's staleness
# check would never fire for this memo — surface the sharp edge (fail-safe: warn only).
if [ -z "$areas_arg" ]; then
  echo "warning: --areas not given; defaulting to bare slug '$slug' — if that matches no tracked path, staleness detection will never fire for this memo. Pass --areas \"<repo-relative path prefixes>\"." >&2
fi
[ -n "$areas_val" ] || die "rejected: --areas is empty"
# Benign character set only (letters, digits, dot, underscore, slash, space, hyphen) — a '|'
# or '<'/'>' etc. would break the pipe-delimited header comment; '..' is traversal-shaped.
bad_chars="$(printf '%s' "$areas_val" | tr -d 'A-Za-z0-9._/ -')"
[ -z "$bad_chars" ] || die "rejected: --areas contains disallowed characters: $bad_chars"
case "$areas_val" in
  *..*) die "rejected: --areas may not contain '..': $areas_val" ;;
esac

header="<!-- written_at: ${ts} | head_sha: ${sha} | areas: ${areas_val} -->"

# ---------------------------------------------------------------------------
# 2b. Compose OUTSIDE the store first; the COMPOSED file must also be ≤ 1000 chars, so a
#     writer-authored memo can never be reader-skipped as over-cap.
# ---------------------------------------------------------------------------
compose="$work/compose"
{
  printf '%s\n' "$header"
  printf '%s\n' "$summary"
  cat "$body_tmp"
} > "$compose"

total="$(wc -c < "$compose" | tr -d '[:space:]')"
if [ "$total" -gt 1000 ]; then
  die "rejected: composed memo file ($total chars incl. header) exceeds the 1000-char hard cap"
fi

# ---------------------------------------------------------------------------
# 5. Confirm-only gate (per-item human approval, cloned from add-rule.sh). Write only when
#    --confirm OR an interactive TTY confirms y. Otherwise DRY-RUN: print the planned memo +
#    target path and DO NOT write (exit 0) — an automated non-TTY run without --confirm can
#    never mutate the committed store.
# ---------------------------------------------------------------------------
write_target="$STORE_DIR/$slug.md"

# ---------------------------------------------------------------------------
# THE VALIDATOR CALL SITE (see the LOAD GUARD block above). Before the confirm gate, for the same
# reason as add-rule.sh's. This writer has no --source flag at all, so provenance rests entirely on
# the memo text — the summary line or body must name the finding / PR / session that motivated it.
#
# WHAT --store POINTS AT, and why it is not the memo's own file. This store is a DIRECTORY of memo
# documents, so it has the same shape problem write-agent-memory.sh had: `--store "$write_target"`
# handed the validator ONE memo split into lines while --entry was a whole memo. Both comparison
# checks score shared/max(|entry|,|line|), so every line's ceiling sat far under the 90/60
# thresholds and the checks returned "examined and clean" having been arithmetically unable to
# return anything else. MEASURED on the live writer before this fix: an identical body reposted
# under a SECOND slug was written with no refusal (the second slug's target file does not exist
# yet, so there was nothing to compare against at all), and a memo compared against ITSELF scored
# 26%. The duplicate check did not "only bite above ~90 body tokens" as this writer's suite used to
# assert — it never bit.
#
# So --store is now the DERIVED MEMO CORPUS: one flattened line per stored memo, built by
# build_compare_corpus() below (the name and the return-code discipline are write-agent-memory.sh's,
# deliberately — one precedent, three call sites). The corpus lives under $work, never in the store,
# so a refusal leaves the store byte-identical and the existing EXIT trap removes it on every path.
# ---------------------------------------------------------------------------

# memo_compare_line <file> — a stored memo as ONE comparable line. The `<!-- ... -->` header is
# DROPPED, matching both the validator's store-side reader (_ve_store_lines skips whole-line HTML
# comments) and its entry side (_ve_comparable_entry does the same), so the two sides of the
# comparison are the same kind of text. Keeping the header in would put this writer's own machine
# stamp — timestamp, sha, areas — into one side only and depress every score; measured, that alone
# pulled a byte-identical repost from 100% down to 70%, i.e. under the threshold.
memo_compare_line() {
  awk '
    /^[[:space:]]*<!--/ { next }
    { b = b " " $0 }
    END {
      gsub(/[\r\t]/, " ", b); gsub(/  +/, " ", b)
      sub(/^[ ]+/, "", b); sub(/[ ]+$/, "", b); sub(/^[#>-]+[ ]*/, "", b)
      if (b ~ /[^ ]/) print b
    }
  ' "$1"
}

# build_compare_corpus <store-dir> <out-file> <self-basename> — one line per stored memo.
# README.md is excluded because it is the store's documentation, not a memo (the slug `readme` is
# rejected outright above, so a memo can never occupy that name). The memo being written is excluded
# too, and that is the difference between "duplicate" and "update": this writer REPLACES an existing
# <area-slug>.md by design, and an update necessarily re-posts most of its own text — measured on
# write-agent-memory.sh, a one-word typo fix scored ~98% against itself and was refused. Every OTHER
# memo stays in, so a body reposted under a DIFFERENT slug — the actual defect — is still refused.
# Return codes are the could-not-examine discipline, not a convenience:
#   0 usable (possibly empty: no prior memos is a real clean verdict) · 2 corpus could not be staged
#   3 the store dir exists but cannot be listed · 4 a memo exists but cannot be read (a hole in the
#     corpus, never reported as clean)
build_compare_corpus() {
  local dir="$1" out="$2" self="${3:-}" f
  : > "$out" || return 2
  [ -d "$dir" ] || return 0
  [ -r "$dir" ] && [ -x "$dir" ] || return 3
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue                     # unmatched glob stays literal under bash 3.2
    [ "${f##*/}" = "README.md" ] && continue
    [ -n "$self" ] && [ "${f##*/}" = "$self" ] && continue
    [ -r "$f" ] || { CORPUS_BAD_PATH="$f"; return 4; }
    memo_compare_line "$f" >> "$out" || return 2
  done
  return 0
}

_ve_load_validator

COMPARE_STORE="$work/store-memos.corpus"
CORPUS_BAD_PATH=""
set +e
build_compare_corpus "$STORE_DIR" "$COMPARE_STORE" "$slug.md"
_corpus_rc=$?
set -e
case "$_corpus_rc" in
  0) : ;;
  3) die "refusing to write — the store dir '$STORE_DIR' exists but could not be listed, so the memos this write would be compared against could not be examined; refusing rather than reporting it clean. Nothing was written." 2 ;;
  4) die "refusing to write — the stored memo '$CORPUS_BAD_PATH' exists but could not be read, so it could not be compared against — a hole in the corpus would make a duplicate or contradiction verdict of 'clean' meaningless. Nothing was written." 2 ;;
  *) die "refusing to write — the comparison corpus derived from '$STORE_DIR' could not be staged (status $_corpus_rc), so this memo could not be compared against the store. Nothing was written." 2 ;;
esac

# ---- VALIDATOR CALL BEGIN ---------------------------------------------------
set +e
validate_entry_all --entry "$(cat "$compose")" --store "$COMPARE_STORE" \
  --source "" --root "$REPO_DIR"
_ve_rc=$?
set -e
case "$_ve_rc" in
  0) : ;;
  1) printf '%s: (the store quoted below is the memo corpus derived from %s — one line per stored memo.)\n' "$PROG" "$STORE_DIR" >&2
     die "refusing to write — the memo was examined and violates a write-time check (see the reason above). Nothing was written." 1 ;;
  *) die "refusing to write — the memo COULD NOT BE EXAMINED (see the reason above); refusing rather than reporting it clean. Nothing was written." 2 ;;
esac
# ---- VALIDATOR CALL END -----------------------------------------------------

proceed=0
if [ "$confirm" -eq 1 ]; then
  proceed=1
elif [ -t 0 ] && [ -t 1 ]; then
  printf 'Write this orientation memo to %s ?\n' "$write_target" >&2
  cat "$compose" >&2
  printf 'Confirm write? [y/N] ' >&2
  read -r reply || reply=""
  case "$reply" in y|Y|yes|YES) proceed=1 ;; *) proceed=0 ;; esac
fi

if [ "$proceed" -ne 1 ]; then
  printf 'PLANNED WRITE (not written — pass --confirm to apply):\n'
  printf '  target: %s\n' "$write_target"
  printf '  memo:\n'
  sed 's/^/    /' "$compose"
  exit 0
fi

# ---------------------------------------------------------------------------
# 6. Write via temp file INSIDE the store dir + atomic mv over the target. On a memo UPDATE,
#    stash the prior memo first so a failed read-back verify can restore it (never leave the
#    area memo-less because an update went bad).
# ---------------------------------------------------------------------------
mkdir -p "$STORE_DIR" || die "could not create store dir: $STORE_DIR"

prior="$work/prior"
had_prior=0
if [ -f "$write_target" ]; then
  cat "$write_target" > "$prior" || die "could not stash prior memo before update: $write_target"
  had_prior=1
fi

tmp_in_store="$(mktemp "$STORE_DIR/.add-orientation.XXXXXX")" || die "mktemp in store failed"
cat "$compose" > "$tmp_in_store" || die "could not stage memo in store dir"
mv -f "$tmp_in_store" "$write_target" || die "atomic move failed (target left untouched): $write_target"
tmp_in_store=""   # consumed by mv; nothing for the trap to clean

# ---------------------------------------------------------------------------
# 7. Read-back verify: header line parses + written file is under the cap. On failure of a
#    NEW memo remove the written file; on failure of an UPDATE restore the stashed prior memo.
# ---------------------------------------------------------------------------
undo_write() {
  # $1 = diagnostic reason. Restore prior memo (update) or remove the bad file (new), then die.
  if [ "$had_prior" -eq 1 ]; then
    cat "$prior" > "$write_target" 2>/dev/null \
      || die "read-back verify failed ($1) AND prior-memo restore failed: $write_target"
    die "read-back verify failed: $1 — restored prior memo at $write_target"
  fi
  rm -f "$write_target"
  die "read-back verify failed: $1 — removed $write_target"
}

first_line="$(head -n 1 "$write_target" 2>/dev/null)"
if ! printf '%s' "$first_line" \
   | grep -qE '^<!-- written_at: .+ \| head_sha: .+ \| areas: .+ -->$'; then
  undo_write "header line missing/unparseable"
fi
verify_total="$(wc -c < "$write_target" | tr -d '[:space:]')"
if [ "$verify_total" -gt 1000 ]; then
  undo_write "written file $verify_total chars exceeds cap"
fi

printf 'wrote orientation memo %s (%s chars) to %s\n' "$slug" "$verify_total" "$write_target"
exit 0
