#!/usr/bin/env bash
# check-vendor-coupling.sh — CI-enforced vendor-coupling ratchet.
#
# WHY: this plugin's portability to non-Claude harnesses is asserted in docs and
# in a requirement, and nothing enforced it — so every release was free to weld
# more harness-specific coupling onto the vendor-neutral core, and did. This gate
# turns that assertion into a mechanically checked contract: the core's count of
# vendor references may FALL or stay FLAT, but it may not RISE without a reviewed,
# REASONED edit to the manifest. It fails CLOSED (exit 1) on any breach.
#
# HOW IT COUNTS — AND WHAT IT CANNOT SEE (read this before trusting a green run):
#   * It counts LITERAL, fixed-string occurrences of the tokens declared in the
#     manifest's `token_classes` (named classes, each a list of tokens — the
#     manifest is the one place the class names live; they are not restated
#     here). The gate hard-codes NO token: every string it
#     looks for comes from the manifest. It reports a reference total PER CLASS and
#     a flat total; allowances stay per path and are compared with the flat total.
#   * OVERLAP RULE — leftmost-longest, each byte counted at most once. A line is
#     scanned left to right; at the leftmost position where any token matches, the
#     LONGEST token matching there wins, is counted once for ITS class, and the
#     scan resumes after it. So one occurrence of a long token that contains a
#     shorter token (a session-id variable that begins with the install-root
#     prefix token) is ONE reference in ONE class, never two. This is done in awk
#     on purpose: which `-e` pattern `grep -oF` prefers on an overlap is not
#     specified, and BSD and GNU grep need not agree. A token declared twice (in
#     one class or across two) is an ERROR, because the class it counts for would
#     be ambiguous.
#   * Multiple hits on ONE line each count, deliberately: a line-based count would
#     let a second reference hide on an existing line.
#   * It therefore CANNOT see a reference ASSEMBLED AT RUNTIME — a path or
#     variable name built by concatenation, indirection, or a lookup table
#     contains no literal token and is invisible to this mechanism (the SDK spike
#     loads its SDK through a variable; it is caught only because that variable's
#     one string constant spells the package scope — a name built by
#     concatenation would not be). That is a real limit of literal matching,
#     stated here rather than papered over. A green run means
#     "no new LITERAL coupling", not "no new coupling".
#   * It CANNOT see a token class nobody declared. A coupling mechanism with no
#     token in `token_classes` (a new harness tool name, a new hook field) is
#     invisible until someone adds it — and adding it raises allowances, which
#     needs reasons (below).
#   * `model_names` tokens are deliberately CODE/CONFIG-SHAPED strings (a quoted
#     alias, a `model:` key with an alias), not the bare alias words, so prose
#     mentioning a model by name is NOT counted. The measurement behind that choice
#     is recorded in the manifest's `model_names` note.
#   * Files are enumerated with `git -c core.quotePath=false ls-files -z`, so the
#     scanned set is exactly the TRACKED tree and every name arrives verbatim
#     (NUL-separated; a non-ASCII or backslash-bearing name is never C-quoted
#     into a path that does not exist). A listed path that is not a regular file
#     is an ERROR — unless the work tree simply deleted it (`git ls-files
#     --deleted`), which is a pending local change, not a hidden file. A path
#     containing a tab, CR or newline is an ERROR too: it cannot be carried
#     through the gate's line/tab-separated tables without being misread.
#     The enumeration is the TRACKED tree. Untracked scratch files and gitignored build output
#     (node_modules/, dist/, .supervisor/) are never scanned, which is what keeps
#     a developer's checkout and CI measuring the identical file set. CONSEQUENCE
#     FOR LOCAL RUNS: a brand-new file is invisible to this gate until it has been
#     `git add`ed. That is moot in CI, where the checkout is fully committed, but a
#     developer establishing or re-measuring a baseline must stage first or they
#     will measure a tree that is missing their own new files.
#   * NUL-bearing ("binary") files ARE counted — a NUL byte must not be a way to
#     make a file invisible. Such a file is read with every NUL turned into a
#     line break (no token contains a NUL or a newline, so no occurrence is lost
#     or split) and is always counted WHOLE, never frontmatter-exempt: a NUL must
#     not be able to manufacture a frontmatter delimiter. A file that cannot be
#     READ is an ERROR, never a silent zero.
#   * FRONTMATTER IS BOUNDED. A YAML frontmatter block can carry a block scalar
#     (`key: |` followed by any amount of indented text), so an unbounded
#     exemption would let body-style prose — tokens and all — hide in the header.
#     The manifest declares `classes.adapter_frontmatter.max_frontmatter_lines`
#     (the lines BETWEEN the two `---` delimiters); a block longer than that is
#     not frontmatter for this gate and the file is counted WHOLE (fail toward
#     counting). Within the bound a block scalar is still exempt — that residue is
#     the bound's size, and raising the bound needs a reason (below).
#
# CLASSIFICATION (declared in the manifest, justified there in per-class `note`s):
#   ADAPTER             — may name any harness freely; NOT counted at all. These
#                         files exist to speak the harness's language.
#   ADAPTER_FRONTMATTER — counted EXCEPT for a leading YAML frontmatter block:
#                         that block (the harness's own agent/command header) is
#                         the adapter surface; the body is prose a non-Claude
#                         harness would have to run, so it is ratcheted like CORE.
#                         Frontmatter is a `---` on LINE 1 up to the first later
#                         line that is exactly `---`. A file whose line 1 is not
#                         `---` is counted whole; a frontmatter that never closes
#                         is counted whole too (an unclosed block must not be able
#                         to hide a whole file), and so is one longer than
#                         max_frontmatter_lines. A `---` rule later in the body
#                         is body.
#   CORE                — must be vendor-neutral; ratcheted against a per-path
#                         allowance.
#   COUPLED             — grandfathered debt; also ratcheted, just from a higher
#                         baseline.
#   A path matched by no class glob falls to the manifest's
#   `unclassified_default` (a new directory cannot silently become a coupling
#   haven). That default may be `core` or `coupled` only — `adapter` is rejected,
#   because a blanket adapter default would silently exempt the whole tree.
#   Precedence: adapter, adapter_frontmatter, coupled, core.
#
# THE RATCHET IS ONE-DIRECTIONAL: breach = actual > allowance. actual < allowance
# PASSES — that is debt being paid down, and pinning counts to exact equality
# would turn every improvement into a CI failure.
#
# TO RAISE AN ALLOWANCE: raise it in loomwright/docs/vendor-coupling-manifest.json
# in the SAME PR that adds the reference, AND add or change its one-line reason in
# the manifest's `allowance_reasons` map. The raise_check enforces the second half:
#   * The base is $VENDOR_COUPLING_BASE when set, else `origin/main`.
#   * The base manifest is the manifest's path RELATIVE TO the scan root's git work
#     tree, read with `git show <base>:<relpath>` — the object store, so a
#     temporary GIT_INDEX_FILE (scripts/ci-local.sh) cannot affect it.
#   * Every allowance that is NEW or HIGHER than the base's must carry an
#     `allowance_reasons["<path>"]` that is ADDED or CHANGED versus the base
#     manifest (absent there, or a different string). An INHERITED, unchanged
#     reason does not justify a new raise — otherwise one old reason would
#     pre-authorise every later raise of that path. Missing ⇒ BREACH.
#   * Reasons are compared NORMALISED (leading/trailing whitespace trimmed,
#     internal runs collapsed to one space), so a whitespace-only edit of an old
#     reason is still INHERITED and never certifies a new raise.
#   * Coupling can also grow by SHRINKING what is counted rather than by raising
#     a number, so three policy moves need a reason of their own, in the
#     manifest's `policy_reasons` map (ADDED or CHANGED versus the base, compared
#     normalised, exactly like allowance_reasons), keyed by a namespaced id:
#       `exempt:<path>` — a path that held a base allowance > 0, still exists, and
#                         is no longer counted the way it was: now ADAPTER, newly
#                         ADAPTER_FRONTMATTER, or outside the scanned set (a
#                         narrowed scan root, an untracked file).
#       `token:<token>` — a token the base declared (in token_classes, or the
#                         retired flat vendor_tokens list) that the head no
#                         longer declares in any class.
#       `bound:max_frontmatter_lines` — the frontmatter bound RAISED versus the
#                         base's.
#     Missing or inherited ⇒ BREACH. A policy_reasons entry certifies nothing once
#     the base carries it unchanged, so a stale one is harmless and may be pruned;
#     its key must still use one of the three namespaces and its value must be a
#     non-empty one-line string, or it is an ERROR.
#   * `raise_check: skipped (<reason>)` is printed, and the run does NOT fail on
#     that account, when the base does not resolve (`skipped (no base)`: shallow
#     clone, no remote, ref missing), when the manifest lies outside the scan
#     root's work tree (the hermetic self-test's override case), or when the
#     manifest path does not exist at the base. VENDOR_COUPLING_REQUIRE_BASE=1
#     turns any skip into an ERROR; CI sets it, so a broken base fetch there fails
#     loudly instead of skipping forever.
#   * Every `allowance_reasons` value must be a non-empty one-line string, and a
#     key with no matching `allowances` entry is an ERROR — the map stays
#     self-cleaning, like the allowance table.
#   * HONEST LIMIT: the check reads the base MANIFEST, so it cannot tell a raise
#     reviewed in an older PR from one in this PR when the base ref is stale; it
#     compares with whatever the base ref names right now.
#
# BREACH DETAIL (what to do about a breach — it changes no verdict):
#   Under every BREACH row the gate prints a detail block:
#   * the token-bearing lines the path ADDED versus the base (`git diff -U0` `+`
#     lines, line numbers from the hunk headers), each with its token(s) and
#     class(es), counted by the SAME `scan()` awk function as the ratchet (one
#     counter, held in SCAN_AWK_FN, never a second matcher). When the base does
#     not resolve it lists the path's token-bearing lines instead, capped and
#     labelled `base unavailable — showing all, not only added`;
#   * the ways out, in order: reword prose, reuse the file's existing reference,
#     move the code into an adapter-classed file (the manifest's
#     `classes.adapter.globs`, read as data), raise the allowance;
#   * a ready-to-paste raise: the `allowances` and `allowance_reasons` entries,
#     the reason being a fixed placeholder that carries RAISE_REASON_SENTINEL.
#     raise_check treats a reason equal to or containing the sentinel as
#     MISSING (BREACH), so pasting the row without writing a reason still fails.
#   The block never advises hiding a reference from the literal count — that is
#   the blind spot named above, not a way out.
#
# EXIT CODES
#   0 = every scanned path at or under its declared allowance, every raise reasoned.
#   1 = at least one BREACH, or an ERROR (missing/malformed/unreadable manifest,
#       a wrong-typed manifest field — an allowance that is not a JSON
#       integer in 0..999999999 (the string "3", a negative, a fractional and a
#       larger value are all refused; the cap keeps shell arithmetic far from
#       overflow), a max_frontmatter_lines that is not a JSON integer in
#       1..10000 or is missing while adapter_frontmatter declares globs, a
#       non-string mode or
#       default, a non-object map, a non-string scan root or glob — in the head
#       or, for the maps raise_check reads, the base manifest;
#       empty or duplicated token set, illegal unclassified_default, an allowance
#       entry for a path that does not exist or is ADAPTER-classified, an orphaned
#       or malformed reason, a policy_reasons entry with an unknown namespace or
#       a malformed value, a listed path that is not a regular file or carries a
#       tab/CR/newline, an unreadable file or base manifest, an empty scan, or a
#       missing dependency). An unreadable manifest is a FAILURE, never a
#       silent pass.
#   There is no third state and no `|| true`: this is a correctness gate, not a
#   runtime emitter (CLAUDE.md §"Failure-Mode Invariants").
#
# USAGE
#   bash scripts/check-vendor-coupling.sh                    # the gate
#   bash scripts/check-vendor-coupling.sh --print-allowances # emit the measured
#       allowance map as JSON, for pasting into the manifest when establishing or
#       re-baselining it. Its output is a MEASUREMENT, not an approval — the diff
#       still has to be read by a human, and every raise still needs a reason.
#
# Env overrides:
#   VENDOR_COUPLING_MANIFEST     — path to the manifest JSON (hermetic self-test)
#   VENDOR_COUPLING_ROOT         — root of the tree to scan (must be a git work tree)
#   VENDOR_COUPLING_BASE         — base ref for the raise_check (default origin/main)
#   VENDOR_COUPLING_REQUIRE_BASE — `1` makes a skipped raise_check an ERROR (CI)
#
# Portability: bash 3.2 / BSD userland safe (macOS dev, GNU CI). No `timeout`, no
# GNU-only stat/sed/date flags, no `${var//...}` pattern substitution on large
# strings. Counting is LC_ALL=C (byte semantics) in POSIX awk, so BSD awk, mawk
# and gawk agree. Counts are validated numeric BEFORE any arithmetic under
# `set -u`. Deterministic and fully offline.

set -uo pipefail
export LC_ALL=C

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

MANIFEST="${VENDOR_COUPLING_MANIFEST:-$repo_root/loomwright/docs/vendor-coupling-manifest.json}"
SCAN_ROOT="${VENDOR_COUPLING_ROOT:-$repo_root}"
BASE_REF="${VENDOR_COUPLING_BASE:-origin/main}"
REQUIRE_BASE="${VENDOR_COUPLING_REQUIRE_BASE:-}"
# The placeholder reason the BREACH detail block prints in its ready-to-paste
# raise row. raise_check reads any reason containing it as MISSING (see header).
RAISE_REASON_SENTINEL="REASON-NOT-WRITTEN"
RAISE_REASON_PLACEHOLDER="$RAISE_REASON_SENTINEL: replace this with one line saying why this reference is needed"

MODE="check"
case "${1:-}" in
  "")                  : ;;
  --print-allowances)  MODE="print" ;;
  *) echo "check-vendor-coupling: unknown argument '$1' (expected none or --print-allowances)" >&2; exit 1 ;;
esac

command -v jq  >/dev/null 2>&1 || { echo "check-vendor-coupling: jq required"  >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "check-vendor-coupling: git required" >&2; exit 1; }
command -v awk >/dev/null 2>&1 || { echo "check-vendor-coupling: awk required" >&2; exit 1; }

[ -f "$MANIFEST" ] || { echo "check-vendor-coupling: manifest not found: $MANIFEST" >&2; exit 1; }
jq -e . "$MANIFEST" >/dev/null 2>&1 || {
  echo "check-vendor-coupling: manifest is not valid JSON: $MANIFEST (fail CLOSED — an unreadable manifest is never a silent pass)" >&2
  exit 1
}
# Absolute, physical manifest path, resolved BEFORE the cd below (a relative
# override must keep meaning what the caller meant).
MANIFEST="$(cd "$(dirname "$MANIFEST")" && pwd -P)/$(basename "$MANIFEST")"
[ -d "$SCAN_ROOT" ] || { echo "check-vendor-coupling: scan root not found: $SCAN_ROOT" >&2; exit 1; }

cd "$SCAN_ROOT" || exit 1

# ---------------------------------------------------------------------------
# Manifest field TYPES — checked once, before anything reads a field.
# Every field below is read by `jq -r` into the shell AND (for some) compared
# inside jq. `jq -r` flattens types: the JSON string "3" and the number 3 both
# print `3`, `false // "default"` silently becomes the default, a non-string
# array entry prints as JSON text, and `.[]?` on a string yields nothing at all.
# So a wrong-typed value could mean one thing to the shell path and another to
# the jq path (a string allowance once passed every shell integer check while
# raise_check, which compares numbers only, never saw it). Rejecting the wrong
# type up front makes both paths read the same, validated value — fail CLOSED.
# ---------------------------------------------------------------------------
TYPE_ERRS="$(jq -r '
  def strfield($k): if has($k) and ((.[$k] | type) != "string") then "\($k) must be a string (got \(.[$k] | type))" else empty end;
  def objfield($k): if has($k) and ((.[$k] | type) != "object") then "\($k) must be an object (got \(.[$k] | type))" else empty end;
  def strlist($v; $name): if ($v | type) != "array" then "\($name) must be an array of strings (got \($v | type))"
    else ($v[] | select((type != "string") or (. == "") or test("[\t\n\r]")) | "\($name) entries must be non-empty one-line strings (got \(tojson))") end;
  if type != "object" then "the manifest must be a JSON object (got \(type))" else
    strfield("count_mode"), strfield("token_overlap_rule"), strfield("unclassified_default"),
    objfield("allowances"), objfield("allowance_reasons"), objfield("policy_reasons"), objfield("classes"),
    (if has("scan_roots") then strlist(.scan_roots; "scan_roots") else empty end),
    # A key that carries a tab, CR or newline cannot travel through the gate s
    # tab-separated tables intact; refuse it rather than misread it.
    ((.allowances, .allowance_reasons, .policy_reasons) | select(type == "object") | keys[] |
       select(test("[\t\n\r]") or (. == "")) | "a map key must be a non-empty one-line string without tabs (got \(tojson))"),
    (if (.classes | type) == "object" then
       (.classes | to_entries[] | .key as $c |
        if (.value | type) != "object" then "classes.\($c) must be an object (got \(.value | type))"
        elif (.value | has("globs")) then strlist(.value.globs; "classes.\($c).globs")
        else empty end),
       (if (.classes.adapter_frontmatter | type) == "object" then
          (.classes.adapter_frontmatter as $f |
           if ($f | has("max_frontmatter_lines")) then
             ($f.max_frontmatter_lines |
              if (type != "number") or (. != floor) or (. < 1) or (. > 10000)
              then "classes.adapter_frontmatter.max_frontmatter_lines must be a JSON integer in 1..10000 (got \(tojson))"
              else empty end)
           elif ((($f.globs // []) | type) == "array") and (($f.globs // []) | length) > 0
           then "classes.adapter_frontmatter.max_frontmatter_lines is required when adapter_frontmatter declares globs — an unbounded frontmatter exemption could hide a body in a block scalar"
           else empty end)
        else empty end)
     else empty end)
  end' "$MANIFEST" 2>/dev/null)" || TYPE_ERRS="the manifest field types could not be checked"
if [ -n "$TYPE_ERRS" ]; then
  printf '%s\n' "$TYPE_ERRS" | while IFS= read -r e; do
    echo "check-vendor-coupling: manifest type error: $e (fail CLOSED — a wrong-typed field is never read as a default)" >&2
  done
  exit 1
fi

# ---------------------------------------------------------------------------
# Manifest -> shell
# ---------------------------------------------------------------------------
SCAN_ROOTS="$(jq -r '.scan_roots[]? // empty' "$MANIFEST")"
if [ -z "$SCAN_ROOTS" ]; then
  echo "check-vendor-coupling: manifest declares no scan_roots — refusing to pass a zero-scope ratchet" >&2
  exit 1
fi
# The roots are word-split into the `git ls-files` pathspec below, so a root
# containing whitespace would silently split into two wrong pathspecs and quietly
# shrink the scanned set. Reject it rather than mis-scan.
case "$SCAN_ROOTS" in
  *[[:blank:]]*)
    echo "check-vendor-coupling: a scan_roots entry contains whitespace, which would silently split the scan pathspec — rename the path or extend this gate to handle it" >&2
    exit 1 ;;
esac

UNCLASSIFIED_DEFAULT="$(jq -r '.unclassified_default // ""' "$MANIFEST")"
case "$UNCLASSIFIED_DEFAULT" in
  core|coupled) : ;;
  *)
    echo "check-vendor-coupling: unclassified_default must be 'core' or 'coupled' (got '$UNCLASSIFIED_DEFAULT'). 'adapter' is rejected — a blanket adapter default would exempt the entire tree." >&2
    exit 1 ;;
esac

# count_mode is declared in the manifest, so it must MEAN something. This gate
# implements exactly one counting mode — occurrences (every match counted, so a
# second reference cannot hide on a line that already has one). The field is
# validated rather than merely read, because a knob that silently accepts any
# value implies an alternate mode that does not exist: someone setting
# "lines" would reasonably expect line-based counting and would instead get
# occurrence counting with no warning. Rejecting the unknown value keeps the
# manifest's declaration and the gate's behaviour in agreement — the same reason
# unclassified_default is validated above rather than defaulted.
COUNT_MODE="$(jq -r '.count_mode // "occurrences"' "$MANIFEST")"
case "$COUNT_MODE" in
  occurrences) : ;;
  *)
    echo "check-vendor-coupling: count_mode must be 'occurrences' (got '$COUNT_MODE'). This gate implements occurrence counting only — a second reference must not be able to hide on a line that already carries one. Remove the field to accept the default, or implement the mode you are asking for." >&2
    exit 1 ;;
esac

# token_overlap_rule is declared for the same reason count_mode is validated:
# the field must MEAN something. Exactly one rule is implemented (see the
# header's OVERLAP RULE), so any other value is rejected, not ignored.
OVERLAP_RULE="$(jq -r '.token_overlap_rule // "leftmost-longest"' "$MANIFEST")"
case "$OVERLAP_RULE" in
  leftmost-longest) : ;;
  *)
    echo "check-vendor-coupling: token_overlap_rule must be 'leftmost-longest' (got '$OVERLAP_RULE'). It is the only rule this gate implements: each occurrence counted once, for the longest token matching at the leftmost position." >&2
    exit 1 ;;
esac

ADAPTER_GLOBS="$(jq -r '.classes.adapter.globs[]? // empty' "$MANIFEST")"
FRONTMATTER_GLOBS="$(jq -r '.classes.adapter_frontmatter.globs[]? // empty' "$MANIFEST")"
COUPLED_GLOBS="$(jq -r '.classes.coupled.globs[]? // empty' "$MANIFEST")"
CORE_GLOBS="$(jq -r '.classes.core.globs[]? // empty'       "$MANIFEST")"
# The frontmatter bound (type-checked above). With no adapter_frontmatter globs
# the value is never consulted; 0 keeps the awk pass well-defined regardless.
FM_MAX="$(jq -r '.classes.adapter_frontmatter.max_frontmatter_lines // 0' "$MANIFEST")"
case "$FM_MAX" in ''|*[!0-9]*) echo "check-vendor-coupling: could not read max_frontmatter_lines (fail CLOSED)" >&2; exit 1 ;; esac

TMPDIR_GATE="$(mktemp -d "${TMPDIR:-/tmp}/vendor-coupling.XXXXXX")" || exit 1
trap 'rm -rf "$TMPDIR_GATE"' EXIT

# Token classes -> TOKENS_TSV (class \t token, manifest order) + a `grep -e tok`
# argument vector for the cheap per-file prefilter. `-e` keeps a token that
# starts with `-` from being read as an option; `-F` keeps `.` and `-` literal.
# The schema-1 flat list is refused rather than ignored: a manifest that still
# carries it would otherwise be read as declaring a different token set from the
# one its author believes it declares.
if jq -e 'has("vendor_tokens")' "$MANIFEST" >/dev/null 2>&1; then
  echo "check-vendor-coupling: manifest carries the retired flat 'vendor_tokens' list — tokens are declared per class in 'token_classes' now; move them there and delete the old key" >&2
  exit 1
fi
if ! jq -e '(.token_classes | type) == "object" and (.token_classes | length) > 0' "$MANIFEST" >/dev/null 2>&1; then
  echo "check-vendor-coupling: manifest declares no token_classes — a ratchet with an empty token set matches nothing and would pass forever" >&2
  exit 1
fi
TOKENS_RAW="$TMPDIR_GATE/tokens.raw"
jq -r '.token_classes | to_entries[] | .key as $c |
  if ((.value | type) != "object") or ((.value.tokens | type) != "array") or ((.value.tokens | length) == 0)
  then "BADCLASS\t\($c)"
  else (.value.tokens[] |
        if (type != "string") or (. == "") or test("[\t\n\r]") then "BADTOK\t\($c)"
        else "TOK\t\($c)\t\(.)" end)
  end' "$MANIFEST" > "$TOKENS_RAW" 2>/dev/null || {
  echo "check-vendor-coupling: could not read token_classes from the manifest (fail CLOSED)" >&2
  exit 1
}
TOKENS_TSV="$TMPDIR_GATE/tokens.tsv"
: > "$TOKENS_TSV"
GREP_ARGS=()
ntokens=0
cfg_err=0
while IFS="$(printf '\t')" read -r kind tcls tok; do
  case "$kind" in
    BADCLASS)
      echo "check-vendor-coupling: token class '$tcls' must be an object with a non-empty 'tokens' array — a class with no tokens counts nothing and reads as clean" >&2
      cfg_err=1; continue ;;
    BADTOK)
      echo "check-vendor-coupling: token class '$tcls' declares a token that is not a non-empty single-line string" >&2
      cfg_err=1; continue ;;
    TOK) : ;;
    *) continue ;;
  esac
  case "$tcls" in
    ''|*[!a-z0-9_]*)
      echo "check-vendor-coupling: token class name '$tcls' must match [a-z0-9_]+ (it is printed in the per-class report and used as a field key)" >&2
      cfg_err=1; continue ;;
  esac
  # ENVIRON, not `-v`: awk processes escape sequences in a `-v` value, so a
  # token carrying a backslash would be compared mangled.
  if T="$tok" awk -F'\t' '($2 "") == (ENVIRON["T"] "") { found=1 } END { exit !found }' "$TOKENS_TSV"; then
    echo "check-vendor-coupling: token '$tok' is declared more than once (class '$tcls' and an earlier one) — the class it counts for would be ambiguous" >&2
    cfg_err=1; continue
  fi
  printf '%s\t%s\n' "$tcls" "$tok" >> "$TOKENS_TSV"
  GREP_ARGS[${#GREP_ARGS[@]}]="-e"
  GREP_ARGS[${#GREP_ARGS[@]}]="$tok"
  ntokens=$((ntokens + 1))
done < "$TOKENS_RAW"
[ "$cfg_err" -eq 0 ] || exit 1
if [ "$ntokens" -eq 0 ]; then
  echo "check-vendor-coupling: manifest declares no tokens in token_classes — a ratchet with an empty token set matches nothing and would pass forever" >&2
  exit 1
fi
nclasses="$(cut -f1 "$TOKENS_TSV" | awk '!seen[$0]++' | wc -l | tr -d '[:space:]')"

# Allowance table -> a TSV side file, read ONCE. (bash 3.2 has no associative
# arrays; per-path `jq` calls would be one process per file.)
# The TYPE is decided HERE, in jq, where it is still visible: only a JSON
# non-negative integer (bounded, so shell arithmetic cannot overflow) is emitted
# as its digits. Anything else — the string "3", -1, 1.5, null, an array — is
# emitted as `!<its JSON>`, which every shell integer check below rejects as an
# ERROR. Interpolating `.value` directly would print the string "3" as `3` and
# let it pass the shell checks while raise_check (numbers only) never saw it.
ALLOW_TSV="$TMPDIR_GATE/allowances.tsv"
if ! jq -r '(.allowances // {}) | to_entries[] |
    "\(.key)\t\(if ((.value | type) == "number") and (.value >= 0) and (.value == (.value | floor)) and (.value <= 999999999)
                     and ((.value | tojson | startswith("-")) | not)
                then (.value | floor | tostring) else "!" + (.value | tojson) end)"' "$MANIFEST" > "$ALLOW_TSV" 2>/dev/null; then
  echo "check-vendor-coupling: could not read the allowances table from the manifest (fail CLOSED)" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# match_any PATH GLOBLIST -> rc 0 if PATH matches any glob in the list.
# Globs are shell `case` patterns; `*` matches `/` (so "loomwright/skills/*"
# covers the whole subtree). The pattern must stay UNQUOTED in the `case` to
# keep its pattern meaning.
match_any() {
  local p="$1" list="$2" g
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    case "$p" in $g) return 0 ;; esac
  done <<EOF
$list
EOF
  return 1
}

# classify PATH -> echoes adapter | adapter_frontmatter | coupled | core
# ADAPTER is tested FIRST so a single-file adapter exemption (the
# LOOMWRIGHT_ROOT resolver) wins over the broader CORE glob that contains it.
classify() {
  local p="$1"
  if match_any "$p" "$ADAPTER_GLOBS";     then echo "adapter"; return; fi
  if match_any "$p" "$FRONTMATTER_GLOBS"; then echo "adapter_frontmatter"; return; fi
  if match_any "$p" "$COUPLED_GLOBS";     then echo "coupled"; return; fi
  if match_any "$p" "$CORE_GLOBS";        then echo "core";    return; fi
  echo "$UNCLASSIFIED_DEFAULT"
}

# allowance_for PATH -> echoes the declared allowance (0 when undeclared).
# The path travels through ENVIRON, not `-v`: awk would turn a backslash in a
# `-v` value into an escape sequence and miss a backslash-bearing path's entry.
allowance_for() {
  P="$1" awk -F'\t' '($1 "") == (ENVIRON["P"] "") { print $2; found=1; exit } END { if (!found) print 0 }' "$ALLOW_TSV"
}

# ---------------------------------------------------------------------------
# Scan
# ---------------------------------------------------------------------------
FILES="$TMPDIR_GATE/files.z"
DELETED="$TMPDIR_GATE/deleted.txt"
# `git ls-files` fixes the scanned set to the TRACKED tree, identically on a dev
# checkout and in CI. A non-git tree is a hard failure, not a fallback to `find`:
# a fallback would mean the self-test exercises a different enumeration path from
# the one CI runs. `-z` (with quotePath off for good measure) delivers every name
# verbatim: without it git C-quotes a non-ASCII or backslash-bearing name into a
# string that names no file, and such a file used to drop out of the scan
# silently. `--deleted` lists the paths the WORK TREE removed (still in the
# index): those are the only listed paths allowed to be missing.
if ! git -c core.quotePath=false ls-files -z -- $SCAN_ROOTS > "$FILES" 2>/dev/null \
   || ! git -c core.quotePath=false ls-files -z --deleted -- $SCAN_ROOTS 2>/dev/null | tr '\000' '\n' > "$DELETED"; then
  echo "check-vendor-coupling: 'git ls-files' failed in $SCAN_ROOT — the scan root must be a git work tree" >&2
  exit 1
fi

scanned=0
counted=0
adapter_files=0
frontmatter_files=0
nulfiles=0
CAND="$TMPDIR_GATE/candidates.tsv"    # path \t class \t mode \t read-from   (files the prefilter matched)
UNREAD="$TMPDIR_GATE/unreadable.txt"  # paths grep, tr or awk could not read
BADPATH="$TMPDIR_GATE/badpath.tsv"    # path-ish \t why   (listed paths the gate cannot scan)
SCANNED="$TMPDIR_GATE/scanned.txt"    # every scanned path (raise_check's exemption arm reads it)
NULDIR="$TMPDIR_GATE/nul"
mkdir -p "$NULDIR" || exit 1
: > "$CAND"
: > "$UNREAD"
: > "$BADPATH"
: > "$SCANNED"
NL='
'
CR="$(printf '\r')"
TAB="$(printf '\t')"

while IFS= read -r -d '' f; do
  [ -n "$f" ] || continue
  case "$f" in
    *"$NL"*|*"$CR"*|*"$TAB"*)
      # Printed with the control bytes made visible; it cannot be scanned or
      # reported faithfully through the gate's tab/line tables.
      printf '%s\tpath carries a tab, CR or newline — the gate cannot carry it through its tables; rename it\n' \
        "$(printf '%s' "$f" | tr '\t\r\n' '???')" >> "$BADPATH"
      continue ;;
  esac
  if [ ! -f "$f" ]; then
    if [ -e "$f" ] || [ -L "$f" ] || ! grep -qFx -- "$f" "$DELETED"; then
      printf '%s\tlisted by git ls-files but not a regular file (a directory, gitlink, dangling symlink or unreachable path) — it cannot be scanned, so it is never passed as clean\n' "$f" >> "$BADPATH"
    fi
    continue                       # deleted in the work tree, still indexed
  fi
  scanned=$((scanned + 1))
  printf '%s\n' "$f" >> "$SCANNED"
  cls="$(classify "$f")"
  if [ "$cls" = "adapter" ]; then
    adapter_files=$((adapter_files + 1))
    continue
  fi
  counted=$((counted + 1))
  mode="whole"
  if [ "$cls" = "adapter_frontmatter" ]; then
    mode="frontmatter"
    frontmatter_files=$((frontmatter_files + 1))
  fi
  # Prefilter only: does the file mention ANY token (anywhere, frontmatter
  # included, NUL-bearing or not — no -I)? The authoritative per-class count is
  # the awk pass below. grep's rc 2 (unreadable) is an ERROR, never a silent zero.
  grep -qaF "${GREP_ARGS[@]}" -- "$f" 2>/dev/null
  grc=$?
  case "$grc" in
    0) : ;;
    1) continue ;;
    *) printf '%s\n' "$f" >> "$UNREAD"; continue ;;
  esac
  # A NUL-bearing candidate is read through a copy whose NULs are line breaks
  # (awk implementations disagree about NUL bytes; tokens never contain one),
  # and is always counted WHOLE (see the header).
  src="./$f"
  if ! tr -d '\000' < "$f" 2>/dev/null | cmp -s - "$f" 2>/dev/null; then
    nulfiles=$((nulfiles + 1))
    src="$NULDIR/$nulfiles"
    if ! tr '\000' '\n' < "$f" > "$src" 2>/dev/null; then
      printf '%s\n' "$f" >> "$UNREAD"; continue
    fi
    mode="whole"
  fi
  printf '%s\t%s\t%s\t%s\n' "$f" "$cls" "$mode" "$src" >> "$CAND"
done < "$FILES"

# Anti-drift: a zero-file scan of a fail-closed ratchet is a false green (the
# same guard check-token-budget.sh puts on an empty agents dir).
if [ "$scanned" -eq 0 ]; then
  echo "check-vendor-coupling: scanned 0 files under scan_roots [$(echo $SCAN_ROOTS)] in $SCAN_ROOT — refusing to pass an empty ratchet" >&2
  exit 1
fi

# The counting pass: leftmost-longest, non-overlapping, per class (see the
# header's OVERLAP RULE). Writes HITS (path \t class \t total \t breakdown, only
# files with total > 0) and CLASS_TOTALS (class \t total, manifest order, every
# class even at 0). An unreadable file is appended to UNREAD. A frontmatter
# block longer than FM_MAX lines (between its delimiters) is not frontmatter: the
# moment it passes the bound, what was held aside is counted and the rest of the
# file is read as body (fail toward counting — see the header).
# THE counter. Both awk programs that count (this pass and the BREACH detail
# block) are built from this one string, so the detail block can never disagree
# with the verdict. It also records what it matched in `scan_seen` ("token
# (class)" list) for the detail block; callers reset scan_seen per line.
SCAN_AWK_FN='
  # scan s, adding one count per non-overlapping leftmost-longest match to arr[class]
  function scan(s, arr,    i, p, best, bl, bi) {
    while (s != "") {
      best = 0; bl = 0; bi = 0
      for (i = 1; i <= ntok; i++) {
        p = index(s, tok[i])
        if (p > 0 && (bi == 0 || p < best || (p == best && tlen[i] > bl))) { best = p; bl = tlen[i]; bi = i }
      }
      if (bi == 0) return
      arr[tcls[bi]]++
      scan_seen = scan_seen (scan_seen == "" ? "" : ", ") tok[bi] " (" tcls[bi] ")"
      s = substr(s, best + bl)
    }
  }
'
HITS="$TMPDIR_GATE/hits.tsv"
CLASS_TOTALS="$TMPDIR_GATE/class-totals.tsv"
: > "$HITS"
if ! awk -F'\t' -v hits="$HITS" -v ctot="$CLASS_TOTALS" -v unread="$UNREAD" -v fmmax="$FM_MAX" "$SCAN_AWK_FN"'
  NR == FNR {
    ntok++; tcls[ntok] = $1; tok[ntok] = $2; tlen[ntok] = length($2)
    if (!($1 in isclass)) { isclass[$1] = 1; ncls++; cname[ncls] = $1; total[$1] = 0 }
    next
  }
  {
    path = $1; cls = $2; mode = $3; src = $4
    split("", cnt); split("", fmcnt)
    ln = 0; infm = 0; fml = 0
    while ((rc = (getline line < src)) > 0) {
      ln++
      chk = line; sub(/\r$/, "", chk)
      if (mode == "frontmatter") {
        if (ln == 1 && chk == "---") { infm = 1; continue }
        if (infm && chk == "---")    { infm = 0; split("", fmcnt); continue }
        if (infm && ++fml > fmmax + 0) {
          # Over the bound: release what was held aside and stop treating
          # anything in this file as frontmatter (a later `---` is body).
          for (c in fmcnt) cnt[c] += fmcnt[c]
          split("", fmcnt); infm = 0; mode = "whole"
        }
      }
      scan_seen = ""
      if (infm) scan(line, fmcnt); else scan(line, cnt)
    }
    close(src)
    if (rc < 0) { print path >> unread; next }
    # A frontmatter block that never closes is counted whole: an unterminated
    # `---` on line 1 must not be able to hide an entire file.
    if (infm) for (c in fmcnt) cnt[c] += fmcnt[c]
    t = 0; bd = ""
    for (i = 1; i <= ncls; i++) {
      c = cname[i]
      if ((c in cnt) && cnt[c] > 0) { t += cnt[c]; total[c] += cnt[c]; bd = bd (bd == "" ? "" : " ") c "=" cnt[c] }
    }
    if (t > 0) printf "%s\t%s\t%d\t%s\n", path, cls, t, bd >> hits
  }
  END { for (i = 1; i <= ncls; i++) printf "%s\t%d\n", cname[i], total[cname[i]] > ctot }
' "$TOKENS_TSV" "$CAND"; then
  echo "check-vendor-coupling: the counting pass (awk) failed — fail CLOSED, no count is trusted" >&2
  exit 1
fi
[ -f "$CLASS_TOTALS" ] || { echo "check-vendor-coupling: the counting pass produced no class totals — fail CLOSED" >&2; exit 1; }

# ---------------------------------------------------------------------------
# --print-allowances: emit the measured map, then stop.
# ---------------------------------------------------------------------------
if [ "$MODE" = "print" ]; then
  if [ -s "$UNREAD" ]; then
    echo "check-vendor-coupling: cannot measure — unreadable file(s): $(tr '\n' ' ' < "$UNREAD")" >&2
    exit 1
  fi
  if [ -s "$BADPATH" ]; then
    echo "check-vendor-coupling: cannot measure — listed path(s) the gate cannot scan: $(cut -f1 "$BADPATH" | tr '\n' ' ')" >&2
    exit 1
  fi
  echo "{"
  first=1
  while IFS="$(printf '\t')" read -r p c n bd; do
    [ -n "$p" ] || continue
    if [ "$first" -eq 1 ]; then first=0; else echo ","; fi
    printf '    "%s": %s' "$p" "$n"
  done < "$HITS"
  echo ""
  echo "}"
  exit 0
fi

# ---------------------------------------------------------------------------
# BREACH detail block (see the header's BREACH DETAIL). It prints only; the
# verdict is decided by the compare loop and is never changed here.
# ---------------------------------------------------------------------------
DETAIL_CAP=40
DETAIL_ADAPTER_GLOBS="$(printf '%s\n' "$ADAPTER_GLOBS" | awk 'NF' | tr '\n' ' ' | sed 's/ *$//')"
breach_detail() { # breach_detail <path> <class> <actual>
  local p="$1" cls="$2" n="$3" bsha="" lines="$TMPDIR_GATE/detail-lines.tsv" label
  bsha="$(git rev-parse --verify -q "$BASE_REF^{commit}" 2>/dev/null)" || bsha=""
  # Every line goes in as "<line number>\t<text>"; the text keeps any tab.
  if [ -n "$bsha" ] && git diff --no-color --no-ext-diff -U0 "$bsha" -- "$p" 2>/dev/null | awk '
      /^@@ / { h = $3; sub(/^\+/, "", h); split(h, a, ","); ln = a[1] + 0; inh = 1; next }
      !inh { next }
      /^\+/ { print ln "\t" substr($0, 2); ln++ }' > "$lines"; then
    label="added lines vs $BASE_REF ($(printf '%.12s' "$bsha")) that carry tokens"
  else
    awk '{ print NR "\t" $0 }' "$p" > "$lines" 2>/dev/null || : > "$lines"
    label="base unavailable — showing all, not only added (first $DETAIL_CAP token-bearing lines)"
  fi
  echo "    detail: $label:"
  awk -F'\t' -v cap="$DETAIL_CAP" "$SCAN_AWK_FN"'
    NR == FNR { ntok++; tcls[ntok] = $1; tok[ntok] = $2; tlen[ntok] = length($2); next }
    {
      ln = $1; text = substr($0, length($1) + 2); sub(/\r$/, "", text)
      scan_seen = ""; split("", c); scan(text, c)
      if (scan_seen == "") next
      shown++
      if (shown <= cap) printf "      line %s: %s\n", ln, scan_seen
    }
    END {
      if (shown == 0) print "      (none — the breach comes from the allowance side: a lowered, removed or never-declared entry)"
      if (shown > cap) printf "      ... %d more token-bearing line(s) not shown\n", shown - cap
    }' "$TOKENS_TSV" "$lines"
  if [ "$cls" = "adapter_frontmatter" ]; then
    echo "      (a listed line inside this file's bounded frontmatter header is not counted; body lines are)"
  fi
  echo "    ways out, in this order:"
  echo "      (a) reword — in prose, name the concept, not the token"
  echo "      (b) reuse — go through the reference this file already has (an existing path variable or helper) instead of adding another"
  echo "      (c) adapter — move the harness-specific code into an adapter-classed file; classes.adapter.globs: ${DETAIL_ADAPTER_GLOBS:-(none declared)}"
  echo "      (d) raise — paste both manifest entries below, then replace the placeholder with a real one-line reason"
  echo "    rule: every reference stays a literal this gate can count; a reference the gate cannot see is not a way out."
  echo "    ready-to-paste raise (an unedited placeholder is still a BREACH):"
  printf '      allowances:        "%s": %s,\n' "$p" "$n"
  printf '      allowance_reasons: "%s": "%s",\n' "$p" "$RAISE_REASON_PLACEHOLDER"
}

# ---------------------------------------------------------------------------
# Compare
# ---------------------------------------------------------------------------
exit_code=0
breaches=0
errors=0
total_refs=0
ROWFMT="%-62s %-19s %7s %7s  %s\n"

echo "check-vendor-coupling — literal token occurrences per tracked file, by token class (leftmost-longest, each occurrence counted once; a runtime-assembled reference is invisible to it)"
echo "authoritative manifest: $MANIFEST"
echo "scan roots: $(echo $SCAN_ROOTS) | token classes: $nclasses | tokens: $ntokens | unclassified default: $UNCLASSIFIED_DEFAULT"
echo "---------------------------------------------------------------------------------------------"
printf "$ROWFMT" "PATH" "CLASS" "ACTUAL" "ALLOW" "STATUS [per-class breakdown]"

while IFS= read -r p; do
  [ -n "$p" ] || continue
  printf "$ROWFMT" "$p" "-" "-" "-" "ERROR   file could not be read — an unreadable file is never counted as clean"
  errors=$((errors + 1))
  exit_code=1
done < "$UNREAD"

while IFS="$(printf '\t')" read -r p why; do
  [ -n "$p" ] || continue
  printf "$ROWFMT" "$p" "-" "-" "-" "ERROR   $why"
  errors=$((errors + 1))
  exit_code=1
done < "$BADPATH"

while IFS="$(printf '\t')" read -r p cls n bd; do
  [ -n "$p" ] || continue
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  total_refs=$((total_refs + n))
  allow="$(allowance_for "$p")"
  case "$allow" in ''|*[!0-9]*)
    printf "$ROWFMT" "$p" "$cls" "$n" "${allow#!}" "ERROR   allowance is not a JSON non-negative integer <= 999999999 (a quoted \"3\", a negative, a fractional or a larger value is refused) [$bd]"
    errors=$((errors + 1))
    exit_code=1
    continue ;;
  esac
  if [ "$n" -gt "$allow" ]; then
    printf "$ROWFMT" "$p" "$cls" "$n" "$allow" "BREACH  +$((n - allow)) over the declared allowance — remove the reference, or raise the allowance in the manifest in this same PR (with an allowance_reasons entry) [$bd]"
    breach_detail "$p" "$cls" "$n"
    breaches=$((breaches + 1))
    exit_code=1
  elif [ "$n" -lt "$allow" ]; then
    printf "$ROWFMT" "$p" "$cls" "$n" "$allow" "OK      $((allow - n)) below allowance (debt paid down — the ratchet never requires exact equality) [$bd]"
  else
    printf "$ROWFMT" "$p" "$cls" "$n" "$allow" "OK      at allowance [$bd]"
  fi
done < "$HITS"

# Orphaned / illegitimate allowance entries. Symmetric with the breach check and
# with check-token-budget.sh's orphaned-budget rule: it keeps the manifest
# self-cleaning, and it closes the loophole of "grant an allowance to a path the
# gate would never have counted" as a way to quietly reclassify something. An
# adapter_frontmatter path is COUNTED (its body is), so it may hold an allowance;
# only a whole-file ADAPTER path may not.
while IFS="$(printf '\t')" read -r p allow; do
  [ -n "$p" ] || continue
  if [ ! -f "$p" ]; then
    printf "$ROWFMT" "$p" "-" "-" "$allow" "ERROR   allowance declared for a path that does not exist — remove the stale entry"
    errors=$((errors + 1))
    exit_code=1
    continue
  fi
  if [ "$(classify "$p")" = "adapter" ]; then
    printf "$ROWFMT" "$p" "adapter" "-" "$allow" "ERROR   allowance declared for an ADAPTER-classified path — adapters are never counted, so the entry is meaningless (remove it)"
    errors=$((errors + 1))
    exit_code=1
    continue
  fi
  # Value sanity, for EVERY declared allowance — not only the ones that happen to
  # have references today. The breach loop above also rejects a non-integer, but it
  # only ever iterates files with actual > 0, so a garbage value on a currently-CLEAN
  # path used to sit inert and undetected until the day someone added a reference to
  # that file — surfacing an ERROR far later than a manifest sanity check should.
  # Validating here makes "the manifest stays self-cleaning" true for the whole table
  # rather than for its referenced subset.
  case "$allow" in ''|*[!0-9]*)
    printf "$ROWFMT" "$p" "$(classify "$p")" "-" "${allow#!}" "ERROR   allowance is not a JSON non-negative integer <= 999999999 (a quoted \"3\", a negative, a fractional or a larger value is refused)"
    errors=$((errors + 1))
    exit_code=1
    continue ;;
  esac
done < "$ALLOW_TSV"

# allowance_reasons sanity — the reasons map is self-cleaning exactly like the
# allowance table: every value a non-empty one-line string, every key an existing
# allowances entry.
if ! jq -e '(.allowance_reasons // {}) | type == "object"' "$MANIFEST" >/dev/null 2>&1; then
  printf "$ROWFMT" "allowance_reasons" "-" "-" "-" "ERROR   allowance_reasons must be an object mapping path -> one-line reason"
  errors=$((errors + 1))
  exit_code=1
else
  REASON_ERRS="$TMPDIR_GATE/reason-errors.tsv"
  jq -r '(.allowances // {}) as $a | (.allowance_reasons // {}) | to_entries[] | .key as $k |
    if (($a | type) != "object") or ($a | has($k) | not) then "\(.key)\torphan"
    elif (.value | type) != "string" then "\(.key)\tnotstring"
    elif (.value | test("^[[:space:]]*$")) then "\(.key)\tempty"
    elif (.value | test("[\n\r]")) then "\(.key)\tmultiline"
    else empty end' "$MANIFEST" > "$REASON_ERRS" 2>/dev/null || {
    printf "$ROWFMT" "allowance_reasons" "-" "-" "-" "ERROR   allowance_reasons could not be read"
    errors=$((errors + 1)); exit_code=1; : > "$REASON_ERRS"
  }
  while IFS="$(printf '\t')" read -r p why; do
    [ -n "$p" ] || continue
    case "$why" in
      orphan)    msg="allowance_reasons entry with no matching allowances entry — remove the stale reason" ;;
      notstring) msg="allowance_reasons value is not a string" ;;
      empty)     msg="allowance_reasons value is empty — a reason must say why" ;;
      multiline) msg="allowance_reasons value spans lines — a reason is ONE line" ;;
      *)         msg="allowance_reasons value is malformed" ;;
    esac
    printf "$ROWFMT" "$p" "-" "-" "-" "ERROR   $msg"
    errors=$((errors + 1))
    exit_code=1
  done < "$REASON_ERRS"
fi

# policy_reasons sanity — the ids are namespaced (see the header's TO RAISE AN
# ALLOWANCE): an unknown namespace is a typo that would certify nothing while
# reading as if it did, so it is an ERROR; every value is a non-empty one-line
# string. (The map's type was checked up front.)
POLICY_ERRS="$TMPDIR_GATE/policy-errors.tsv"
if ! jq -r '(.policy_reasons // {}) | to_entries[] |
    if (.key | test("^(exempt:.+|token:.+|bound:max_frontmatter_lines)$") | not) then "\(.key)\tnamespace"
    elif (.value | type) != "string" then "\(.key)\tnotstring"
    elif (.value | test("^[[:space:]]*$")) then "\(.key)\tempty"
    elif (.value | test("[\n\r]")) then "\(.key)\tmultiline"
    else empty end' "$MANIFEST" > "$POLICY_ERRS" 2>/dev/null; then
  printf "$ROWFMT" "policy_reasons" "-" "-" "-" "ERROR   policy_reasons could not be read"
  errors=$((errors + 1)); exit_code=1; : > "$POLICY_ERRS"
fi
while IFS="$(printf '\t')" read -r p why; do
  [ -n "$p" ] || continue
  case "$why" in
    namespace) msg="policy_reasons key must be exempt:<path>, token:<token> or bound:max_frontmatter_lines" ;;
    notstring) msg="policy_reasons value is not a string" ;;
    empty)     msg="policy_reasons value is empty — a reason must say why" ;;
    multiline) msg="policy_reasons value spans lines — a reason is ONE line" ;;
    *)         msg="policy_reasons value is malformed" ;;
  esac
  printf "$ROWFMT" "$p" "-" "-" "-" "ERROR   $msg"
  errors=$((errors + 1))
  exit_code=1
done < "$POLICY_ERRS"

# ---------------------------------------------------------------------------
# raise_check — every new or raised allowance needs an ADDED or CHANGED reason
# versus the base manifest (see the header's TO RAISE AN ALLOWANCE).
# ---------------------------------------------------------------------------
RAISE_STATE="not-run"
raise_skip() { # raise_skip <reason>
  RAISE_STATE="skipped"
  echo "raise_check: skipped ($1)"
  if [ "$REQUIRE_BASE" = "1" ]; then
    echo "raise_check: ERROR — VENDOR_COUPLING_REQUIRE_BASE=1 demands the raise check run here, and it was skipped ($1)"
    errors=$((errors + 1))
    exit_code=1
  fi
}

raise_check() {
  local top toplp mdir rel base_sha base_manifest raise_tsv policy_ids policy_tsv base_adapter base_fm bcls hcls nraised=0 nbad=0 npolicy=0 npbad=0 p cur bv state why what
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || top=""
  if [ -z "$top" ]; then raise_skip "scan root is not inside a git work tree"; return; fi
  toplp="$(cd "$top" && pwd -P)" || { raise_skip "scan root's work tree is not resolvable"; return; }
  mdir="$(dirname "$MANIFEST")"
  case "$mdir/" in
    "$toplp/"*) rel="${MANIFEST#"$toplp"/}" ;;
    *) raise_skip "manifest is outside the scan root's git work tree"; return ;;
  esac
  base_sha="$(git rev-parse --verify -q "$BASE_REF^{commit}" 2>/dev/null)" || base_sha=""
  if [ -z "$base_sha" ]; then
    raise_skip "no base"
    echo "  (base ref '$BASE_REF' does not resolve to a commit here: shallow clone, no remote, or ref missing — set VENDOR_COUPLING_BASE or fetch it)"
    return
  fi
  if ! git cat-file -e "$base_sha:$rel" 2>/dev/null; then
    raise_skip "manifest path $rel does not exist at base $BASE_REF"
    return
  fi
  base_manifest="$TMPDIR_GATE/base-manifest.json"
  if ! git show "$base_sha:$rel" > "$base_manifest" 2>/dev/null || ! jq -e . "$base_manifest" >/dev/null 2>&1; then
    echo "raise_check: ERROR — the base manifest ($BASE_REF:$rel) could not be read as JSON (fail CLOSED — an unreadable base never certifies a raise)"
    errors=$((errors + 1)); exit_code=1
    return
  fi
  # The base is typed as strictly as the head: a base whose allowances or
  # reasons map is not an object would make every base lookup below read as
  # "absent", and an absent base REASON reads as "added" — so a wrong-typed base
  # could certify an inherited reason. (A wrong-typed base allowance VALUE is
  # safe by construction: it reads as absent, so the head value counts as a NEW
  # allowance and still needs an added/changed reason.)
  # The same holds for the policy arms below: a wrong-typed base token list
  # would read as "the base declared fewer tokens", hiding a removal.
  if ! jq -e 'type == "object"
              and ((has("allowances") | not) or ((.allowances | type) == "object"))
              and ((has("allowance_reasons") | not) or ((.allowance_reasons | type) == "object"))
              and ((has("policy_reasons") | not) or ((.policy_reasons | type) == "object"))
              and ((has("vendor_tokens") | not) or ((.vendor_tokens | type) == "array"))
              and ((has("token_classes") | not) or ((.token_classes | type) == "object"
                   and all(.token_classes[]; (type == "object") and ((.tokens | type) == "array"))))' "$base_manifest" >/dev/null 2>&1; then
    echo "raise_check: ERROR — the base manifest ($BASE_REF:$rel) is not an object, or its allowances / allowance_reasons / policy_reasons / token_classes / vendor_tokens is wrong-typed (fail CLOSED — a wrong-typed base never certifies a raise)"
    errors=$((errors + 1)); exit_code=1
    return
  fi
  raise_tsv="$TMPDIR_GATE/raises.tsv"
  # Reasons are compared NORMALISED (trimmed, internal whitespace collapsed), so
  # a whitespace-only edit of an inherited reason does not read as "changed".
  if ! jq -r --slurpfile b "$base_manifest" --arg sent "$RAISE_REASON_SENTINEL" '
      def int_str: if . == floor then (floor | if . == 0 then "0" else tostring end) else tostring end;
      def norm: if type == "string" then gsub("[[:space:]]+"; " ") | sub("^ "; "") | sub(" $"; "") else null end;
      ($b[0].allowances // {}) as $ba |
      ($b[0].allowance_reasons // {}) as $br |
      (.allowance_reasons // {}) as $rs |
      (.allowances // {}) | to_entries[] |
      select((.value | type) == "number") |
      .key as $p | .value as $v |
      (if ($ba | type) == "object" and (($ba[$p] | type) == "number") then $ba[$p] else null end) as $bv |
      select($v > ($bv // 0)) |
      ($rs[$p]) as $r |
      [ $p, ($v | int_str), (if $bv == null then "new" else ($bv | int_str) end),
        (if ($r | type) != "string" or (($r | norm) == "") then "missing"
         elif ($r | contains($sent)) then "sentinel"
         elif (($br | type) == "object") and (($br[$p] | norm) == ($r | norm)) then "inherited"
         else "ok" end) ] | @tsv' "$MANIFEST" > "$raise_tsv" 2>/dev/null; then
    echo "raise_check: ERROR — could not compare allowances with the base manifest (fail CLOSED)"
    errors=$((errors + 1)); exit_code=1
    return
  fi
  while IFS="$(printf '\t')" read -r p cur bv state; do
    [ -n "$p" ] || continue
    nraised=$((nraised + 1))
    [ "$state" = "ok" ] && continue
    case "$state" in
      sentinel)  why="its allowance_reasons entry is the unfilled placeholder (it contains $RAISE_REASON_SENTINEL) — write the one-line reason for THIS raise in its place" ;;
      inherited) why="its allowance_reasons entry is INHERITED unchanged from the base — an old reason does not justify a new raise; change it to say why THIS raise is needed" ;;
      *)         why="it has no allowance_reasons entry — add a one-line reason for this raise" ;;
    esac
    printf "$ROWFMT" "$p" "-" "-" "$cur" "BREACH  allowance raised ($bv -> $cur vs $BASE_REF) without an added/changed reason: $why"
    nbad=$((nbad + 1))
    breaches=$((breaches + 1))
    exit_code=1
  done < "$raise_tsv"
  echo "raise_check: executed against $BASE_REF ($(printf '%.12s' "$base_sha")) — allowances new or raised vs base: $nraised, without an added/changed reason: $nbad"

  # --- policy arms: coupling can also grow by counting LESS (header) --------
  # Ids are collected one per line; none can carry a newline (paths with one
  # were refused at enumeration, tokens are one-line by validation).
  policy_ids="$TMPDIR_GATE/policy-ids.txt"
  : > "$policy_ids"
  # exempt:<path> — base allowance > 0, the file still exists, and it is now
  # ADAPTER, newly ADAPTER_FRONTMATTER, or outside the scanned set. The base
  # classification uses the BASE globs (a wrong-typed base glob list reads as
  # empty, which only makes a path look MORE newly exempt — the safe side).
  base_adapter="$(jq -r '(.classes.adapter.globs // []) | if type == "array" then .[] | strings else empty end' "$base_manifest" 2>/dev/null)"
  base_fm="$(jq -r '(.classes.adapter_frontmatter.globs // []) | if type == "array" then .[] | strings else empty end' "$base_manifest" 2>/dev/null)"
  if ! jq -r '(.allowances // {}) | to_entries[] | select(((.value | type) == "number") and (.value > 0)) | .key
              | select(test("[\t\n\r]") | not)' "$base_manifest" > "$TMPDIR_GATE/base-allowed.txt" 2>/dev/null; then
    echo "raise_check: ERROR — could not read the base allowances (fail CLOSED)"
    errors=$((errors + 1)); exit_code=1
    return
  fi
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ -f "$p" ] || continue          # deleted: its references left with it
    hcls="$(classify "$p")"
    if match_any "$p" "$base_adapter"; then bcls="adapter"
    elif match_any "$p" "$base_fm";    then bcls="adapter_frontmatter"
    else bcls="counted"; fi
    if [ "$hcls" = "adapter" ] && [ "$bcls" != "adapter" ]; then
      printf 'exempt:%s\tnow ADAPTER-classified (whole file uncounted)\n' "$p" >> "$policy_ids"
    elif [ "$hcls" = "adapter_frontmatter" ] && [ "$bcls" != "adapter_frontmatter" ]; then
      printf 'exempt:%s\tnewly ADAPTER_FRONTMATTER (its frontmatter uncounted)\n' "$p" >> "$policy_ids"
    elif ! grep -qFx -- "$p" "$SCANNED"; then
      printf 'exempt:%s\tno longer in the scanned set (scan_roots narrowed, or the file untracked)\n' "$p" >> "$policy_ids"
    fi
  done < "$TMPDIR_GATE/base-allowed.txt"
  # token:<token> and bound:max_frontmatter_lines — decided in jq.
  if ! jq -r --slurpfile b "$base_manifest" '
      ([.token_classes[]?.tokens[]? | strings]) as $head |
      (([($b[0].token_classes // {})[]?.tokens[]? | strings] + [($b[0].vendor_tokens // [])[]? | strings]) | unique) as $base |
      ( ($base - $head)[] | select(test("[\t\n\r]") | not)
        | "token:\(.)\tdeclared at the base, no longer declared in any token class" ),
      ( ($b[0].classes.adapter_frontmatter.max_frontmatter_lines) as $bb |
        (.classes.adapter_frontmatter.max_frontmatter_lines) as $hb |
        if (($bb | type) == "number") and (($hb | type) == "number") and ($hb > $bb)
        then "bound:max_frontmatter_lines\traised \($bb) -> \($hb)" else empty end )' \
      "$MANIFEST" >> "$policy_ids" 2>/dev/null; then
    echo "raise_check: ERROR — could not compare token_classes / the frontmatter bound with the base manifest (fail CLOSED)"
    errors=$((errors + 1)); exit_code=1
    return
  fi
  policy_tsv="$TMPDIR_GATE/policy.tsv"
  if ! jq -R -r --slurpfile b "$base_manifest" --slurpfile h "$MANIFEST" '
      def norm: if type == "string" then gsub("[[:space:]]+"; " ") | sub("^ "; "") | sub(" $"; "") else null end;
      ($b[0].policy_reasons // {}) as $br | ($h[0].policy_reasons // {}) as $hr |
      select(length > 0) | (split("\t")) as $f | $f[0] as $id | ($hr[$id]) as $r |
      [ $id, ($f[1:] | join("\t")),
        (if ($r | type) != "string" or (($r | norm) == "") then "missing"
         elif (($br[$id] | norm) == ($r | norm)) then "inherited"
         else "ok" end) ] | @tsv' "$policy_ids" > "$policy_tsv" 2>/dev/null; then
    echo "raise_check: ERROR — could not read policy_reasons (fail CLOSED)"
    errors=$((errors + 1)); exit_code=1
    return
  fi
  while IFS="$(printf '\t')" read -r p what state; do
    [ -n "$p" ] || continue
    npolicy=$((npolicy + 1))
    [ "$state" = "ok" ] && continue
    case "$state" in
      inherited) why="its policy_reasons entry is INHERITED unchanged from the base — say why THIS change is needed" ;;
      *)         why="it has no policy_reasons[\"$p\"] entry — add a one-line reason" ;;
    esac
    printf "$ROWFMT" "$p" "-" "-" "-" "BREACH  counted coupling shrank ($what vs $BASE_REF) without an added/changed reason: $why"
    npbad=$((npbad + 1))
    breaches=$((breaches + 1))
    exit_code=1
  done < "$policy_tsv"
  echo "raise_check: policy changes that count less vs base (exemptions, removed tokens, a raised frontmatter bound): $npolicy, without an added/changed reason: $npbad"
  RAISE_STATE="executed"
}
raise_check

echo "---------------------------------------------------------------------------------------------"
echo "per token class (references in counted files):"
while IFS="$(printf '\t')" read -r c n; do
  [ -n "$c" ] || continue
  printf "  %-24s %7s\n" "$c" "$n"
done < "$CLASS_TOTALS"
printf "  %-24s %7s\n" "TOTAL (flat)" "$total_refs"
echo "---------------------------------------------------------------------------------------------"
echo "files scanned: $scanned (counted: $counted, of which frontmatter-bounded (header exempt, body counted): $frontmatter_files; adapter-exempt: $adapter_files) | files with references: $(wc -l < "$HITS" | tr -d '[:space:]') | total references: $total_refs | breaches: $breaches | errors: $errors"

if [ "$exit_code" -ne 0 ]; then
  echo "check-vendor-coupling: FAILED — vendor-coupling ratchet tripped (see BREACH/ERROR rows above)." >&2
else
  if [ "$RAISE_STATE" = "executed" ]; then
    echo "check-vendor-coupling: OK — no path exceeds its declared vendor-coupling allowance, and every raise or exemption carries a reason."
  else
    echo "check-vendor-coupling: OK — no path exceeds its declared vendor-coupling allowance (raise_check did not run, so reasons were NOT verified against a base)."
  fi
fi
exit "$exit_code"
