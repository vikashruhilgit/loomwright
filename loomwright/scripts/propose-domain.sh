#!/usr/bin/env bash
# propose-domain.sh - the DOMAIN basis of `/propose`: what a competent app in this project's
# domain does that this app does not, emitted as CANDIDATE requirement files under
# .supervisor/requirements/proposed/ for a human to promote or delete.
#
# It is the second basis of one command. The default basis (propose-work.sh) reads the churn
# ledger - our own recorded mistakes, inward. This one reads outward. Both emit the same kind of
# artefact into the same folder under the same contract, and THE TWO NEVER RUN IN ONE INVOCATION:
# the default basis is local jq over a local file and costs nothing, while this one spends fetch
# budget and emits judgment-class output, so bare `/propose` must never trigger a network call.
#
# THE CONTRACT (identical to the default basis, and restated inside every emitted file):
#   `.supervisor/requirements/proposed/` is deliberately NOT an `/automate --folder` target;
#   promotion is a human moving a file out of it.
# It is restated in committed source on purpose: `.gitignore` ignores `.supervisor/*`, so a fresh
# clone carries no record of the contract from the runtime directory itself.
#
# IT PROPOSES; IT NEVER QUEUES. Nothing here enqueues, dispatches, ranks, scores or merges.
#
# WHY THIS SCRIPT WRITES NO proposed/README.md, DELIBERATELY:
#   propose-work.sh already authors that directory contract. A second author of the same
#   filename would make the two bases collide on the one file the namespacing rule exists to
#   prevent collisions on, and would put the same contract text in two committed places to drift
#   apart. So this script writes ONLY `domain--<slug>.md` files, and each of them restates the
#   contract in its own body.
#
# ---------------------------------------------------------------------------------------------
# THREE INPUTS, AND EACH ONE'S EVIDENCE CLASS TRAVELS WITH IT INTO THE OUTPUT:
#   (a) THE PRODUCT STORE - domain, stance, audience, competitors. Read by SHELLING OUT to
#       read-product.sh, never by re-parsing `.agent/product.json` here: one parser, and
#       `stance_default_action` has exactly one home (read-product.sh's jq `def STANCE_ACTIONS`).
#       This script NEVER re-derives that mapping - it prints the value the reader emitted.
#       Absent store => the absence is NAMED with the bootstrap offer, nothing is written, exit 0.
#   (b) THE CAPABILITY INVENTORY - grep/glob over this project's own code and docs plus any
#       `.agent/orientation/` memos. Class DERIVED. NO CODE GRAPH: the graphify tier was retired
#       on measurement, and `graphify-out/`, `read-bridge.sh` and `brain_context` are not read,
#       built or resurrected here.
#   (c) THE DOMAIN EXPECTATION SET - fetched from the store's competitors[] through fetch_source.
#       Class EXTERNAL/JUDGMENT, and stated in every emitted file as THE WEAKEST INPUT
#       (competitor marketing overstates).
#
# UNVERIFIED IS NOT ABSENT. "We don't have X" is the claim this basis will get wrong, so it is
# never asserted from silence alone. A capability the inventory cannot confirm either way - named
# in the docs or an orientation memo but not confirmed in code, or searched against an empty
# surface - is emitted as `unverified`, NEVER as missing. Absent evidence is omitted, never
# defaulted (build-floor.sh's rule, applied to the input this lane is most likely to fabricate).
#
# EVIDENCE-ONLY EMISSION. A gap is written ONLY when at least one FETCHED source corroborates the
# expectation. With no fetcher there is no corroboration, so nothing is written at all - the run
# says so, reports coverage as partial, and reports every domain expectation as unverified. The
# catalogue below is a list of things to LOOK FOR; it is never by itself evidence that this
# domain expects them.
#
# CLASSIFICATION, NEVER A SCORE. Every gap is exactly one of TABLE-STAKES / DIFFERENTIATOR /
# NOT-FOR-US (classify_gap). There is no score, no rank, no priority, no top-N and no ordering
# field anywhere in the output.
#   READ THIS BEFORE WRITING THE NO-SCORE ASSERTION: the ONE place an emitted file can contain
#   the substring "priorit" is inside the `stance_default_action` VALUE read verbatim from
#   read-product.sh (`build-highest-priority`). That is a stance default action, not a priority
#   field, and re-deriving or renaming it here is forbidden. So the no-score check must be
#   FIELD-SHAPED (`^- score:`, `^- rank:`, `^- priority:`, `^- order:`), never a bare word grep.
#
# DETERMINISM. Two runs against an unchanged basis produce byte-identical content. No run
# timestamp reaches any emitted byte - a cited fetch date is the store's recorded `last_fetched`,
# and this script never writes the store, so a fetch performed by this run does not restamp
# anything. The wall clock is read exactly once, only to decide staleness, and is pinnable with
# PROPOSE_DOMAIN_SOURCE_DATE_EPOCH. Every collection is sorted before emission.
#
# ---------------------------------------------------------------------------------------------
# PORTABILITY (each of these has already shipped a defect in this repo):
#   * NO `stat` AT ALL. `stat -f %m` is BSD and SUCCEEDS WITH GARBAGE on GNU/Linux, which under
#     `set -u` silently empties an arithmetic probe - macOS-green, CI-red. This script takes no
#     mtime dependency, so the trap cannot bite. Do not add one casually.
#   * NO `date -d` (GNU-only) and no `date -j -f` (BSD-only). An ISO-8601 `last_fetched` is
#     converted to an epoch by JQ (`fromdateiso8601`), which is the same on both platforms, and
#     an unparseable date degrades to "staleness unknown" rather than to a number.
#   * NO `timeout` - stock macOS has none. A fetcher that hangs hangs this run; that is the
#     fetcher's responsibility and is documented at PROPOSE_DOMAIN_FETCH_CMD below.
#   * `grep -q` IS RUN ONLY DIRECTLY AGAINST A FILE, never as the right-hand side of a pipe:
#     under `pipefail` a `producer | grep -q` returns 141 on a MATCH.
#   * Counts come from an `awk END`, never from `... || echo 0`, which APPENDS a second line.
#   * Assignment and status check are separate statements - `x="$(...)"` discards the status.
#   * bash 3.2: no associative arrays, no `${var^^}`, and `${var//[[:space:]]/}` is O(n^2).
#
# INJECTION SAFETY. Store text (domain, audience, competitor names and urls) is NEVER string-
# interpolated into a shell command or into a jq program: jq programs here are fixed text and
# store content arrives as data through `--arg`, following read-product.sh. A url reaches the
# fetcher as its own argv element - never through eval, sh -c or a command substitution of
# untrusted text - and is refused unless it is http:// or https://.
#
# FAIL-SAFE. `set -uo pipefail` with NO `set -e`, a `command -v jq` guard that SKIPS rather than
# fails, and `exit 0` ALWAYS. Every degraded path names its reason on stderr before exiting.
#
# BLAST RADIUS. Writes ONLY files directly under the output directory, through guarded_write.
# `mkdir -p` additionally creates that directory's missing PARENTS, outside the guard. Working
# state lives in a `mktemp -d` outside the project tree and is removed on exit. read-product.sh
# is invoked with `--repo <that temp dir>` for one reason: its best-effort `memory.log` append
# would otherwise land inside the project tree, and this basis creates nothing there.
#
# Usage:  propose-domain.sh
#   env PROPOSE_DOMAIN_STORE=<path>                 product store (default <root>/.agent/product.json)
#       PROPOSE_DOMAIN_OUT_DIR=<path>               where candidates are written
#                                                   (default .supervisor/requirements/proposed)
#       PROPOSE_DOMAIN_REQUIREMENTS_DIR=<path>      root scanned for `## Status: done` supersession
#                                                   (default .supervisor/requirements)
#       PROPOSE_DOMAIN_FETCH_CMD=<cmd>              THE ONLY external transport. Invoked as
#                                                   `<cmd> <url>`, source text read from its
#                                                   stdout. It must be ONE executable command
#                                                   with no arguments (wrap it in a script if you
#                                                   need any), and it owns its own timeout.
#                                                   UNSET OR EMPTY => NOTHING IS FETCHED. There is
#                                                   no implicit curl and no shell default, ever.
#       PROPOSE_DOMAIN_MAX_FETCHES=<n>              hard cap on external calls for the WHOLE run
#                                                   (default 5). Local reads - the store, the
#                                                   inventory, `.agent/orientation/` - are not
#                                                   external calls and never draw on it.
#       PROPOSE_DOMAIN_MAX_SOURCE_AGE_SECONDS=<n>   a source recorded older than this is named
#                                                   STALE in the output (default 7776000 = 90d)
#       PROPOSE_DOMAIN_SOURCE_DATE_EPOCH=<n>        pin the staleness "now" (reproducible runs)
# Exit:   0 always.

set -uo pipefail   # `set -e` intentionally omitted - an advisory producer must never break its caller.

SELF="propose-domain"

say() { echo "$SELF: $1" >&2; }

# ---------------------------------------------------------------------------
# 1. Root, script directory, tooling.
# ---------------------------------------------------------------------------
GITROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$GITROOT" 2>/dev/null || true
ROOT="$(pwd)"

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
READ_PRODUCT="$SCRIPT_DIR/read-product.sh"

command -v jq >/dev/null 2>&1 || {
  say "jq required - skipping, nothing proposed"
  exit 0
}

if [ ! -f "$READ_PRODUCT" ]; then
  say "the product-context reader is missing at $READ_PRODUCT - skipping, nothing proposed"
  exit 0
fi

# ---------------------------------------------------------------------------
# 2. Env knobs. Every numeric knob is validated; a non-numeric value is NAMED and ignored rather
#    than allowed to empty an arithmetic expression under `set -u`.
# ---------------------------------------------------------------------------
STORE="${PROPOSE_DOMAIN_STORE:-$ROOT/.agent/product.json}"
OUT_DIR="${PROPOSE_DOMAIN_OUT_DIR:-.supervisor/requirements/proposed}"
REQ_DIR="${PROPOSE_DOMAIN_REQUIREMENTS_DIR:-.supervisor/requirements}"
FETCH_CMD="${PROPOSE_DOMAIN_FETCH_CMD:-}"
MAX_FETCHES="${PROPOSE_DOMAIN_MAX_FETCHES:-5}"
MAX_SOURCE_AGE_SECONDS="${PROPOSE_DOMAIN_MAX_SOURCE_AGE_SECONDS:-7776000}"

case "$MAX_FETCHES" in ''|*[!0-9]*)
  say "PROPOSE_DOMAIN_MAX_FETCHES='$MAX_FETCHES' is not a number - ignoring it, using 5"
  MAX_FETCHES=5 ;;
esac
case "$MAX_SOURCE_AGE_SECONDS" in ''|*[!0-9]*)
  say "PROPOSE_DOMAIN_MAX_SOURCE_AGE_SECONDS='$MAX_SOURCE_AGE_SECONDS' is not a number - ignoring it, using 7776000"
  MAX_SOURCE_AGE_SECONDS=7776000 ;;
esac

# The fetcher is resolved ONCE, here, and nowhere else. An unresolvable value degrades to NO
# FETCHER - it never falls back to another transport.
if [ -n "$FETCH_CMD" ] && ! command -v "$FETCH_CMD" >/dev/null 2>&1; then
  say "PROPOSE_DOMAIN_FETCH_CMD='$FETCH_CMD' is not an executable command - this run has NO fetcher and will fetch nothing"
  FETCH_CMD=""
fi

# The wall clock, read EXACTLY ONCE, used ONLY for staleness.
NOW_EPOCH="${PROPOSE_DOMAIN_SOURCE_DATE_EPOCH:-}"
case "$NOW_EPOCH" in ''|*[!0-9]*) NOW_EPOCH="$(date -u +%s 2>/dev/null)" ;; esac
case "$NOW_EPOCH" in ''|*[!0-9]*)
  say "could not read the clock - source staleness will be reported as unknown"
  NOW_EPOCH="" ;;
esac

# ---------------------------------------------------------------------------
# 3. The store must be present and readable. Absent => NAME IT, offer the bootstrap, write
#    nothing, exit 0. Never a silent skip: the reader's silence is its contract, not an answer.
# ---------------------------------------------------------------------------
bootstrap_offer() {
  say 'To record it once in a committed file that travels with the repo, run the propose-only bootstrap; it scans the project, prints a proposal, and writes nothing without `--confirm`:'
  say '    bash "${CLAUDE_PLUGIN_ROOT}/scripts/propose-product.sh"'
  say 'Run it bare, exactly as written. The dry run then prints the one field the bootstrap will never guess for you: `--stance`, which decides the DEFAULT ACTION on a discovered gap - `product` means build the highest-priority one, `tool` means do not build by default.'
}

if [ ! -f "$STORE" ] || [ ! -r "$STORE" ]; then
  say '**No product context: `.agent/product.json` is absent.** (looked for it at: '"$STORE"')'
  say 'The domain basis has no subject without it - the domain, the stance and the competitors all come from that store. Nothing was written and nothing was fetched.'
  bootstrap_offer
  exit 0
fi

# ---------------------------------------------------------------------------
# 4. Working directory, OUTSIDE the project tree. Nothing here is ever written into the project.
# ---------------------------------------------------------------------------
WORK="$(mktemp -d 2>/dev/null)" || WORK=""
if [ -z "$WORK" ] || [ ! -d "$WORK" ]; then
  say "could not allocate a temp working directory - skipping, nothing proposed"
  exit 0
fi
trap 'rm -rf "$WORK" 2>/dev/null' EXIT

# ---------------------------------------------------------------------------
# 5. Read the product store through read-product.sh. `--repo "$WORK"` keeps the reader's
#    best-effort memory.log append out of the project tree (see BLAST RADIUS above); `--store`
#    is passed explicitly, so `--repo` decides nothing about which store is read.
# ---------------------------------------------------------------------------
bash "$READ_PRODUCT" --store "$STORE" --repo "$WORK" > "$WORK/product.txt" 2>"$WORK/product.err"
# Status and assignment kept apart on purpose; the reader always exits 0, so emptiness is the
# real signal, not the status.
if [ ! -s "$WORK/product.txt" ]; then
  say "the product store at $STORE produced no readable product context (the reader's reason follows) - nothing was written and nothing was fetched"
  while IFS= read -r perr; do [ -n "$perr" ] && say "  read-product said: $perr"; done < "$WORK/product.err"
  bootstrap_offer
  exit 0
fi
while IFS= read -r perr; do [ -n "$perr" ] && say "read-product: $perr"; done < "$WORK/product.err"

P_DOMAIN=""
P_STANCE=""
P_DEFAULT_ACTION=""
P_AUDIENCE=""
: > "$WORK/competitors.tsv"
while IFS= read -r line; do
  case "$line" in
    '- domain: '*)                P_DOMAIN="${line#- domain: }" ;;
    '- stance: '*)                P_STANCE="${line#- stance: }" ;;
    '- stance_default_action: '*) P_DEFAULT_ACTION="${line#- stance_default_action: }" ;;
    '- audience: '*)              P_AUDIENCE="${line#- audience: }" ;;
    '  - name: '*)
      # Split from the RIGHT so a competitor name containing " | " cannot shift the fields.
      crest="${line#  - name: }"
      clf="${crest##* | last_fetched: }"
      chead="${crest% | last_fetched: *}"
      curl="${chead##* | url: }"
      cname="${chead% | url: *}"
      printf '%s\t%s\t%s\n' "$cname" "$curl" "$clf" >> "$WORK/competitors.tsv"
      ;;
  esac
done < "$WORK/product.txt"

[ -n "$P_DOMAIN" ] || P_DOMAIN="unset"
[ -n "$P_STANCE" ] || P_STANCE="unset"
[ -n "$P_DEFAULT_ACTION" ] || P_DEFAULT_ACTION="unset"
[ -n "$P_AUDIENCE" ] || P_AUDIENCE="unset"

# The text classify_gap tests a scope term against. Store data only - never a guess.
SCOPE_TEXT="$P_DOMAIN $P_AUDIENCE"

# The store path as it is NAMED in the output: relative when it lives inside the project tree
# (the ordinary case, `.agent/product.json`), absolute otherwise. Keeping a path that happens to
# sit under a temp root out of the emitted bytes is what lets two runs from two different working
# copies of the same basis be compared byte for byte.
STORE_SHOWN="$STORE"
case "$STORE" in
  "$ROOT"/*) STORE_SHOWN="${STORE#$ROOT/}" ;;
esac

# Sorted before use: fetch order, citation order and cap effects are a function of CONTENT, not
# of the store's serialisation order.
LC_ALL=C sort "$WORK/competitors.tsv" > "$WORK/competitors.sorted.tsv"

n_competitors="$(awk 'END{print NR+0}' "$WORK/competitors.sorted.tsv")"

# ---------------------------------------------------------------------------
# 6. guarded_write <plain-file-name> - the SINGLE enforcement point for the blast radius,
#    copied in shape from propose-work.sh's guard. Content arrives on stdin.
#
#    Deliberately the ONLY sanitisation in this script: a second, redundant check elsewhere
#    would make this guard's mutation control vacuous - a self-test could delete the guard and
#    nothing would escape, so the test would stay green with the mechanism removed.
# ---------------------------------------------------------------------------
guarded_write() {
  name="$1"
  # >>> WRITE-PATH GUARD (a self-test's mutation control deletes this marked block)
  case "$name" in
    ''|.|..|.*|*/*|*'\'*)
      say "refusing to write '$name' - not a plain file name under $OUT_DIR"
      cat >/dev/null; return 1 ;;
  esac
  # Unreachable defence-in-depth: the case above already rejects any name containing "/", so
  # dirname is always $OUT_DIR_ABS and this cannot fire. Kept so the guard still holds if that
  # case is ever narrowed. Not load-bearing - the case above is the traversal defence.
  guard_parent="$(cd "$(dirname "$OUT_DIR_ABS/$name")" 2>/dev/null && pwd)"
  if [ "$guard_parent" != "$OUT_DIR_ABS" ]; then
    say "refusing to write '$name' - resolves outside $OUT_DIR_ABS"
    cat >/dev/null; return 1
  fi
  # A legal plain name can still be a pre-existing SYMLINK planted in the output directory, and
  # `cat >` FOLLOWS a symlink - which walks the write outside the directory the name guard just
  # proved it was inside. Refuse rather than unlink: this basis never removes a file it did not
  # write, and a symlink here is hostile input, not a stale artefact to tidy.
  if [ -L "$OUT_DIR_ABS/$name" ]; then
    say "refusing to write '$name' - it is a symlink, and writing through it would leave $OUT_DIR_ABS"
    cat >/dev/null; return 1
  fi
  # A pre-existing entry that is not a REGULAR file. This matters specifically because the write
  # below is `mv -f`: mv into a DIRECTORY succeeds, moving the temp entry inside it and returning
  # 0, so the run counts a candidate it never wrote and abandons a PID-named temp in a tree this
  # basis promises to leave nothing in. `cat >` used to fail on a directory and name it; the
  # staged-write rewrite lost that for free, so the refusal is now explicit rather than inherited.
  if [ -e "$OUT_DIR_ABS/$name" ] && [ ! -f "$OUT_DIR_ABS/$name" ]; then
    say "refusing to write '$name' - something that is not a regular file already occupies that name"
    cat >/dev/null; return 1
  fi
  # <<< END WRITE-PATH GUARD
  # Write to a temp entry inside the output dir and `mv -f` it into place. `mv` REPLACES the
  # directory entry rather than writing through whatever occupies it, which closes three things
  # the `-L` test above cannot: a HARDLINK at a legal name (`[ -L ]` is false for one, and
  # `cat >` truncates the shared inode - measured: a planted hardlink took 5856 bytes into a
  # file outside the output dir with no refusal), the check-then-write TOCTOU race on the
  # symlink path, and any future link type. The `-L` refusal is kept above because naming a
  # planted symlink is more useful to a human than silently replacing it.
  gw_tmp="$OUT_DIR_ABS/.tmp.propose-domain.$$"
  { cat > "$gw_tmp"; } 2>/dev/null || {
    rm -f "$gw_tmp" 2>/dev/null
    say "cannot write $OUT_DIR_ABS/$name - skipping this candidate"
    return 1
  }
  mv -f "$gw_tmp" "$OUT_DIR_ABS/$name" 2>/dev/null && [ -f "$OUT_DIR_ABS/$name" ] || {
    rm -f "$gw_tmp" 2>/dev/null
    say "cannot move the staged candidate into place at $OUT_DIR_ABS/$name - skipping this candidate"
    return 1
  }
  return 0
}

# ---------------------------------------------------------------------------
# 7. superseded_by <token> - path of the first file whose text already carries this gap's token,
#    or empty. Two arms, mirroring propose-work.sh: an existing file in the output dir (dedup,
#    which is what stops a recorded NOT-FOR-US gap being raised again), and any requirement file
#    under REQ_DIR carrying `## Status: done` (durable dismissal).
#
#    grep is run directly against FILES, never as the right-hand side of a pipe: under
#    `pipefail` a `producer | grep -q` returns 141 on a match, silently inverting this check.
# ---------------------------------------------------------------------------
superseded_by() {
  sb_tok="$1"
  for sb_f in "$OUT_DIR_ABS"/*.md; do
    [ -f "$sb_f" ] || continue
    if grep -Fq -- "$sb_tok" "$sb_f" 2>/dev/null; then printf '%s' "$sb_f"; return 0; fi
  done
  # >>> DONE-SUPERSESSION CHECK (a self-test's mutation control deletes this block)
  if [ -d "$REQ_DIR" ]; then
    sb_list="$(find "$REQ_DIR" -type f -name '*.md' 2>/dev/null | LC_ALL=C sort)"
    while IFS= read -r sb_f; do
      [ -n "$sb_f" ] && [ -f "$sb_f" ] || continue
      grep -Eq '^##[[:space:]]+Status:[[:space:]]*done[[:space:]]*$' "$sb_f" 2>/dev/null || continue
      if grep -Fq -- "$sb_tok" "$sb_f" 2>/dev/null; then printf '%s' "$sb_f"; return 0; fi
    done <<EOF
$sb_list
EOF
  fi
  # <<< END DONE-SUPERSESSION CHECK
  return 1
}

# ---------------------------------------------------------------------------
# 8. fetch_source <url> <dest-file> - THE SOLE EXTERNAL-CALL SITE IN THIS SCRIPT.
#
#    Nothing else in this file reaches the network, and there is exactly one invocation of
#    "$FETCH_CMD" in the whole script - the line marked below. The fetcher is whatever
#    PROPOSE_DOMAIN_FETCH_CMD names; UNSET OR EMPTY MEANS NO FETCH AT ALL. There is deliberately
#    no curl fallback, no wget fallback and no shell default: "bare /propose makes zero network
#    calls" and "cap=1 makes exactly one call" are only mechanically assertable if the transport
#    is a single named, overridable seam.
#
#    It is called from the MAIN SHELL (never inside a command substitution) so that its
#    increment of FETCHES_USED survives - an increment inside a `$(...)` subshell is discarded,
#    which would silently uncap the run.
#
#    The url is passed as its own argv element and is refused unless http(s): store text never
#    becomes shell syntax.
#
#    Returns 0 and leaves the source text in <dest-file>; otherwise returns 1 with the reason in
#    FETCH_REASON. A call that was ATTEMPTED counts against the cap even if it failed - an
#    attempted external call is an external call.
# ---------------------------------------------------------------------------
FETCHES_USED=0
FETCH_REASON=""

fetch_source() {
  fs_url="$1"
  fs_dest="$2"
  FETCH_REASON=""

  if [ -z "$FETCH_CMD" ]; then
    FETCH_REASON="no usable fetcher (PROPOSE_DOMAIN_FETCH_CMD is unset, empty, or was rejected as not executable) - nothing was fetched"
    return 1
  fi
  if [ -z "$fs_url" ] || [ "$fs_url" = "unset" ]; then
    FETCH_REASON="the store records no url for this source"
    return 1
  fi
  case "$fs_url" in
    http://*|https://*) : ;;
    *) FETCH_REASON="url is not http(s) - refused, not fetched"; return 1 ;;
  esac
  if [ "$FETCHES_USED" -ge "$MAX_FETCHES" ]; then
    FETCH_REASON="the run's fetch cap of $MAX_FETCHES was already spent - not reached"
    return 1
  fi

  FETCHES_USED=$(( FETCHES_USED + 1 ))
  # >>> THE EXTERNAL CALL. The only one. stdin is closed off so a fetcher can never consume
  #     this script's own stdin, and stderr is dropped so a chatty fetcher cannot pose as ours.
  "$FETCH_CMD" "$fs_url" < /dev/null > "$fs_dest" 2>/dev/null
  fs_rc=$?
  # <<< END EXTERNAL CALL
  if [ "$fs_rc" -ne 0 ]; then
    FETCH_REASON="the fetcher exited $fs_rc for this url"
    return 1
  fi
  if [ ! -s "$fs_dest" ]; then
    FETCH_REASON="the fetcher returned no text for this url"
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# 9. classify_gap <kind> <scope-terms> <scope-text> - TABLE-STAKES / DIFFERENTIATOR /
#    NOT-FOR-US, and nothing else. Exactly one value, never a score.
#
#    The rule, in order:
#      1. An expectation carrying SCOPE TERMS none of which appear in the store's own domain +
#         audience text belongs to an ADJACENT domain this project is not in => NOT-FOR-US.
#         (Card-data vaulting is table stakes for a payments product and not for us otherwise;
#         that judgment is made from the STORE's text, not from a constant.)
#      2. Otherwise a baseline expectation => TABLE-STAKES.
#      3. Otherwise => DIFFERENTIATOR.
#
#    NOTE WHAT IS NOT AN INPUT: `stance`. Stance decides the DEFAULT ACTION on a gap (read from
#    read-product.sh's `stance_default_action`), never the classification - which is why the same
#    fixture under `product` and under `tool` yields the SAME classifications and DIFFERENT
#    default actions. Nor is the number of sources an input, so the fetch cap changes coverage
#    without ever changing a classification.
# ---------------------------------------------------------------------------
classify_gap() {
  cg_kind="$1"
  cg_scope_terms="$2"
  cg_text="$3"
  if [ -n "$cg_scope_terms" ]; then
    cg_in_scope=0
    # WORD BOUNDARIES, the same rule the inventory matcher uses - this was a bare substring
    # glob and is the second instance of the defect that made a bare `sso` match "processor".
    # Scope terms are short and generic (`card`, `payment`, `commerce`), so a substring match
    # is not a near-miss but a routine wrong answer: a store whose domain reads "a flashcard-
    # based spaced-repetition app" contains "flashcard", which substring-matches `card`, and
    # card-data-vaulting is then classified TABLE-STAKES for an app with no payments at all.
    # The file's own header, propose.md and the CHANGELOG all claim boundary matching; this is
    # the place that did not do it.
    terms_to_patterns "$cg_scope_terms" "$WORK/scope.pat"
    printf '%s\n' "$cg_text" > "$WORK/scope.txt"
    # grep -q runs DIRECTLY against a file, never as the right-hand side of a pipe, where it
    # returns 141 under pipefail even on a match.
    if [ -s "$WORK/scope.pat" ] && grep -q -I -i -E -f "$WORK/scope.pat" "$WORK/scope.txt" 2>/dev/null; then
      cg_in_scope=1
    fi
    if [ "$cg_in_scope" -eq 0 ]; then
      printf 'NOT-FOR-US'
      return 0
    fi
  fi
  if [ "$cg_kind" = "baseline" ]; then
    printf 'TABLE-STAKES'
  else
    printf 'DIFFERENTIATOR'
  fi
  return 0
}

# ---------------------------------------------------------------------------
# 9b. The output directory, resolved BEFORE the inventory is enumerated - the order matters.
#     `mkdir -p` creates missing PARENTS, outside the guard (as in propose-work.sh). The
#     resolved path is then excluded from the inventory surfaces below, so a candidate this
#     script wrote on an EARLIER run can never be the doc-surface "evidence" that the capability
#     it describes is documented. Measured, not theoretical: with the output directory inside the
#     project root and left in the surface, a second run read its own first run's files and
#     flipped an inventory status from `missing` to `unverified`. The default output directory
#     lives under `.supervisor/`, which is pruned anyway; this is what makes an OVERRIDDEN one
#     safe. The requirements directory is excluded for the same reason.
# ---------------------------------------------------------------------------
mkdir -p "$OUT_DIR" 2>/dev/null || {
  say "cannot create $OUT_DIR - skipping, nothing proposed"
  exit 0
}
OUT_DIR_ABS="$(cd "$OUT_DIR" 2>/dev/null && pwd)"
[ -n "$OUT_DIR_ABS" ] || {
  say "cannot resolve $OUT_DIR - skipping, nothing proposed"
  exit 0
}
REQ_DIR_ABS=""
if [ -d "$REQ_DIR" ]; then
  REQ_DIR_ABS="$(cd "$REQ_DIR" 2>/dev/null && pwd)"
fi

# ---------------------------------------------------------------------------
# 10. The capability inventory - DERIVED, direct reads only.
#
#     Two surfaces are enumerated once and reused for every expectation: CODE and DOCS (the
#     latter includes `.agent/orientation/` memos, which are counted separately because they are
#     a named input). `.git`, `node_modules` and the whole `.supervisor/` runtime tree are
#     pruned - the last of these matters: the output directory lives there by default, and
#     grepping it would let a previously emitted candidate "confirm" the very capability it says
#     is missing. Any file named `domain--*.md` is excluded wherever it sits, for the same
#     reason and as the belt to that brace: an OUTPUT DIRECTORY FROM AN EARLIER RUN, pointed
#     somewhere else inside the tree, is not the current run's output directory and would
#     otherwise be read as ordinary project documentation. That is a measured failure, not a
#     hypothetical one - it flipped an inventory status from `missing` to `unverified` between
#     two runs whose only intended difference was the store's stance. The lists are capped so a large repo cannot make this run unbounded; the cap
#     and the counts are REPORTED in every emitted file, because a truncated surface is exactly
#     the case where "not found" must not be read as "absent".
# ---------------------------------------------------------------------------
# Env-overridable so the TRUNCATION case below is reachable in a test. This repo is far under
# the default cap, so a fixed 4000 would make the truncation arm unreachable here - and an
# unreachable branch is exactly the "claim no check backs" defect this file keeps guarding against.
SURFACE_FILE_CAP="${PROPOSE_DOMAIN_SURFACE_FILE_CAP:-4000}"
# ONE named refusal covering every rejected value. The clamp used to be a silent `||` fallback,
# so `0`, a negative, and a value large enough to overflow the arithmetic test were all replaced
# with 4000 with no message - while the documented promise said an out-of-range value is NAMED.
# A doc claiming behaviour the code does not have is the defect class this file keeps meeting.
case "$SURFACE_FILE_CAP" in
  ''|*[!0-9]*) SURFACE_FILE_CAP_BAD=1 ;;
  *) if [ "$SURFACE_FILE_CAP" -ge 1 ] 2>/dev/null; then SURFACE_FILE_CAP_BAD=0; else SURFACE_FILE_CAP_BAD=1; fi ;;
esac
if [ "$SURFACE_FILE_CAP_BAD" = "1" ]; then
  say "ignoring unusable PROPOSE_DOMAIN_SURFACE_FILE_CAP '$SURFACE_FILE_CAP' (must be an integer >= 1) - using 4000"
  SURFACE_FILE_CAP=4000
fi
# The product store is INPUT (a), not an inventory surface. It is a `.json` file inside the tree,
# so without this exclusion its own competitor names and domain prose would sit in the code
# surface and could "confirm" the very capability the store is being used to ask about.
STORE_ABS="$(cd "$(dirname "$STORE")" 2>/dev/null && pwd)/$(basename "$STORE")"
# This script itself is excluded too, and for a reason that was measured rather than imagined: its
# own catalogue below contains every inventory term it searches for, so when the project being
# scanned is the one that SHIPS this script (this plugin's own repo, or a vendored copy), the file
# confirms every capability in the catalogue and every real gap silently disappears as "already
# present". A tool must not measure itself.
SELF_ABS="$SCRIPT_DIR/$(basename "$0")"
# THE SEARCHER IS NOT THE SEARCHED, and excluding only $0 was not enough. Two more of this
# basis's OWN artefacts sit inside any tree it scans and each one falsely CONFIRMS capabilities:
#   * its self-test, which must name every catalogue term literally in order to assert on it;
#   * its committed fixture tree, whose stand-in "project" files are not this project's code.
# A false `present` is worse than a false `missing`: the candidate is never written at all, so
# nothing reports it and the gap silently disappears. Measured on this repo: excluding only $0
# left `single-sign-on` and `two-factor-authentication` confirmed by the self-test and
# `usage-analytics` confirmed by a fixture, dropping 5 real candidates to 3.
SELFTEST_ABS="$SCRIPT_DIR/test-$(basename "$0")"
FIXTURES_ABS="$SCRIPT_DIR/fixtures/$(basename "$0" .sh)"
CODE_GLOBS='*.sh *.py *.js *.jsx *.ts *.tsx *.go *.rb *.java *.kt *.rs *.php *.cs *.sql *.tf *.yml *.yaml *.json'
DOC_GLOBS='*.md *.mdx *.rst *.adoc'

find "$ROOT" \
  \( -name .git -o -name node_modules -o -name .supervisor -o -name vendor \) -prune -o \
  -type f \( -name '*.sh' -o -name '*.py' -o -name '*.js' -o -name '*.jsx' -o -name '*.ts' \
  -o -name '*.tsx' -o -name '*.go' -o -name '*.rb' -o -name '*.java' -o -name '*.kt' \
  -o -name '*.rs' -o -name '*.php' -o -name '*.cs' -o -name '*.sql' -o -name '*.tf' \
  -o -name '*.yml' -o -name '*.yaml' -o -name '*.json' \) -print 2>/dev/null \
  | LC_ALL=C sort | awk -v store="$STORE_ABS" -v self="$SELF_ABS" -v selftest="$SELFTEST_ABS" -v fixtures="$FIXTURES_ABS" -v out="$OUT_DIR_ABS/" -v req="$REQ_DIR_ABS/" '
      $0 == store || $0 == self || $0 == selftest { next }
      fixtures != "" && index($0, fixtures "/") == 1 { next }
      index($0, out) == 1 { next }
      req != "/" && index($0, req) == 1 { next }
      { base = $0; sub(/^.*\//, "", base) }
      base ~ /^domain--.*\.md$/ { next }
      { print }' \
  > "$WORK/code.all"
# Count BEFORE the cap is applied. Counting the truncated list would make n_code_files equal the
# cap on every truncated surface, so the "empty surface" arm could never fire and a capability
# whose evidence sits past the cap would be reported `missing` - in a file that simultaneously
# states truncation is why it would not be. That defect shipped once; this ordering is the fix.
n_code_total="$(awk 'END{print NR+0}' "$WORK/code.all")"
awk -v cap="$SURFACE_FILE_CAP" 'NR<=cap' "$WORK/code.all" > "$WORK/code.list"

find "$ROOT" \
  \( -name .git -o -name node_modules -o -name .supervisor -o -name vendor \) -prune -o \
  -type f \( -name '*.md' -o -name '*.mdx' -o -name '*.rst' -o -name '*.adoc' \) -print 2>/dev/null \
  | LC_ALL=C sort | awk -v store="$STORE_ABS" -v self="$SELF_ABS" -v selftest="$SELFTEST_ABS" -v fixtures="$FIXTURES_ABS" -v out="$OUT_DIR_ABS/" -v req="$REQ_DIR_ABS/" '
      $0 == store || $0 == self || $0 == selftest { next }
      fixtures != "" && index($0, fixtures "/") == 1 { next }
      index($0, out) == 1 { next }
      req != "/" && index($0, req) == 1 { next }
      { base = $0; sub(/^.*\//, "", base) }
      base ~ /^domain--.*\.md$/ { next }
      { print }' \
  > "$WORK/doc.all"
n_doc_total="$(awk 'END{print NR+0}' "$WORK/doc.all")"
awk -v cap="$SURFACE_FILE_CAP" 'NR<=cap' "$WORK/doc.all" > "$WORK/doc.list"

n_code_files="$(awk 'END{print NR+0}' "$WORK/code.list")"
n_doc_files="$(awk 'END{print NR+0}' "$WORK/doc.list")"
code_truncated=0; [ "$n_code_total" -gt "$n_code_files" ] && code_truncated=1
doc_truncated=0;  [ "$n_doc_total"  -gt "$n_doc_files"  ] && doc_truncated=1

ORIENT_DIR="$ROOT/.agent/orientation"
n_orient_files=0
if [ -d "$ORIENT_DIR" ]; then
  find "$ORIENT_DIR" -type f -name '*.md' -print 2>/dev/null | LC_ALL=C sort > "$WORK/orient.list"
  n_orient_files="$(awk 'END{print NR+0}' "$WORK/orient.list")"
fi

# terms_to_patterns <comma-list> <dest> - writes the RAW terms to <dest>.raw (one per line, the
# list every emitted file quotes as "the exact terms used") and the SEARCH PATTERNS to <dest>.
#
# Two things this guards, both measured on the fixtures:
#   * EMPTY LINES ARE REMOVED. An empty pattern line makes `grep -f` match every file, which turns
#     "we already have it" into a guaranteed false positive; awk 'NF' is that guard.
#   * MATCHING IS WORD-BOUNDED, not substring. A plain `grep -F` for the acronym `sso` matches
#     the word "processor", which silently invented a corroborating source on the first fixture
#     run of this script. `\b` is GNU-only and `[[:<:]]` is BSD-only, so the boundary is written
#     as a portable ERE both greps accept. Catalogue terms must therefore stay plain text
#     (letters, digits, spaces, hyphens) - a term containing ERE metacharacters would change
#     meaning here.
terms_to_patterns() {
  printf '%s\n' "$1" | tr ',' '\n' | awk 'NF{ sub(/^[ \t]+/,""); sub(/[ \t]+$/,""); if (length($0)) print }' > "$2.raw"
  awk '{ printf "(^|[^[:alnum:]])%s([^[:alnum:]]|$)\n", $0 }' "$2.raw" > "$2"
}

# search_surface <list-file> <pattern-file> - up to 3 matching paths, sorted, relative to ROOT.
# Empty output means no match OR an empty surface; the caller distinguishes the two by the
# surface's own file count, because those two facts are not the same fact.
search_surface() {
  ss_list="$1"
  ss_pat="$2"
  [ -s "$ss_list" ] || return 0
  [ -s "$ss_pat" ] || return 0
  LC_ALL=C tr '\n' '\0' < "$ss_list" \
    | xargs -0 grep -l -I -i -E -f "$ss_pat" -- 2>/dev/null \
    | LC_ALL=C sort \
    | awk -v root="$ROOT/" 'NR<=3 { print (index($0, root) == 1) ? substr($0, length(root) + 1) : $0 }'
}

# ---------------------------------------------------------------------------
# 11. THE DOMAIN EXPECTATION CATALOGUE - the things this basis knows how to LOOK FOR.
#
# SCOPE-COLUMN RULE (learned the hard way): every scope term must be a WHOLE WORD, never a stem.
# The scope column was originally authored against a substring match, so it carried the stem
# `invoic` to cover invoice/invoicing at once. When classify_gap was corrected to match on word
# boundaries - the right fix for a real over-matching bug - that stem became UNMATCHABLE: there
# is no English word "invoic", so `(^|[^[:alnum:]])invoic([^[:alnum:]]|$)` fires on nothing.
# The over-matching fix silently introduced under-matching, and an invoicing product was told
# PCI vaulting and multi-currency were NOT-FOR-US - never written, so nothing reported them.
# A false NOT-FOR-US is the same "silently disappears" class as a false `present`.
# When adding a term here, spell every inflection you mean (invoice, invoices, invoicing) and
# every spelling (commerce, ecommerce, e-commerce). AC20 asserts exactly this.
#
#     Fields, pipe-separated: slug|title|source terms|inventory terms|scope terms|kind
#       source terms     matched against FETCHED source text; a hit is what makes an expectation
#                        live in this domain at all (evidence class external/judgment).
#       inventory terms  matched against this project's own code and docs (evidence class
#                        derived). These are the "exact terms used" reported in every gap file.
#       scope terms      classify_gap rule 1; empty means "in scope for any domain".
#       kind             baseline => TABLE-STAKES, edge => DIFFERENTIATOR (classify_gap rules
#                        2-3). This column is a JUDGMENT about the domain, not a measurement,
#                        and every emitted file says so.
#
#     THE CATALOGUE IS NOT EVIDENCE. Nothing here is emitted unless a fetched source corroborates
#     it. Terms are deliberately multi-word where a single word would be ambiguous in source code
#     ("export" is a JavaScript keyword; "data export" is a capability).
# ---------------------------------------------------------------------------
read_catalogue() {
  cat <<'CATALOGUE'
api-rate-limiting|Per-client API rate limiting|rate limit,rate-limiting,rate limiting,throttling,quota per|rate limit,rate-limit,ratelimit,rate_limit,throttle,x-ratelimit||baseline
audit-log|An append-only audit log of user-visible actions|audit log,audit trail,audit history,activity log|audit log,audit_log,auditlog,audit trail,audit-log||baseline
bulk-data-export|Bulk data export a customer can run themselves|data export,bulk export,export to csv,export your data|data export,bulk export,export to csv,export-csv||edge
card-data-vaulting|Cardholder-data vaulting and PCI scope reduction|pci,cardholder data,card vault,card tokenization,tokenized card|cardholder,card vault,pci-dss,pci dss,card tokenization|payment,payments,billing,invoice,invoices,invoicing,checkout,commerce,ecommerce,e-commerce,card|baseline
multi-currency|Multi-currency amounts and per-currency rounding|multi-currency,multiple currencies,currency support,foreign currency|multi-currency,multicurrency,currency code,currency_code,iso 4217|payment,payments,billing,invoice,invoices,invoicing,pricing,commerce,ecommerce,e-commerce,accounting|baseline
role-based-access-control|Role-based access control over shared data|rbac,role-based access,roles and permissions,permission model|rbac,role-based access,permission model,permissions model,role_id||baseline
single-sign-on|Single sign-on against a customer identity provider|sso,single sign-on,saml,openid connect,oidc|single sign-on,single-sign-on,saml,oidc,openid connect||baseline
two-factor-authentication|Two-factor authentication on account login|two-factor,2fa,multi-factor,mfa,authenticator app|two-factor,two factor,2fa,multi-factor,mfa,totp||baseline
usage-analytics|Usage analytics the customer can see for themselves|usage analytics,usage dashboard,usage reporting,product analytics|usage analytics,usage dashboard,usage reporting||edge
webhook-delivery|Outbound webhooks with delivery retries|webhook,webhooks,event subscription,outbound events|webhook,webhooks,event subscription||edge
CATALOGUE
}

# ---------------------------------------------------------------------------
# 12. Fetch the domain expectation set. Sources are visited in sorted name order, so which ones
#     a cap reaches is a function of the store's CONTENT.
#
#     Per-source record (sources.tsv): name, url, last_fetched, state, staleness, body-file.
#       state      fetched | not-fetched: <reason>
#       staleness  fresh | stale | never-fetched | unknown
#     NEVER FETCHED IS NOT STALE and is never rendered as a date: unknown is not old.
# ---------------------------------------------------------------------------
: > "$WORK/sources.tsv"
n_fetched=0
: > "$WORK/notreached.txt"

src_i=0
while IFS="$(printf '\t')" read -r cname curl clf; do
  [ -n "${cname:-}" ] || continue
  src_i=$(( src_i + 1 ))
  body="$WORK/src.$src_i.body"

  state=""
  if fetch_source "$curl" "$body"; then
    state="fetched"
    n_fetched=$(( n_fetched + 1 ))
  else
    state="not-fetched: $FETCH_REASON"
    printf '%s (%s)\n' "$cname" "$FETCH_REASON" >> "$WORK/notreached.txt"
    body=""
  fi

  # Staleness of the STORE'S RECORDED fetch date. jq does the ISO->epoch conversion because
  # `date -d` is GNU-only and `date -j -f` is BSD-only; an unparseable date degrades to unknown.
  staleness="unknown"
  case "$clf" in
    'never fetched')       staleness="never-fetched" ;;
    'unset (key missing)') staleness="unknown" ;;
    'unset (malformed)')   staleness="unknown" ;;
    '')                    staleness="unknown" ;;
    *)
      lf_epoch="$(jq -rn --arg d "$clf" 'try ($d|fromdateiso8601) catch empty' 2>/dev/null)"
      case "$lf_epoch" in
        ''|*[!0-9]*) staleness="unknown" ;;
        *)
          if [ -n "$NOW_EPOCH" ]; then
            src_age=$(( NOW_EPOCH - lf_epoch ))
            [ "$src_age" -lt 0 ] && src_age=0
            if [ "$src_age" -ge "$MAX_SOURCE_AGE_SECONDS" ]; then staleness="stale"; else staleness="fresh"; fi
          fi ;;
      esac ;;
  esac

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$cname" "$curl" "$clf" "$state" "$staleness" "$body" >> "$WORK/sources.tsv"
done < "$WORK/competitors.sorted.tsv"

n_notreached="$(awk 'END{print NR+0}' "$WORK/notreached.txt")"

COVERAGE="complete"
if [ "$n_fetched" -eq 0 ] || [ "$n_notreached" -gt 0 ]; then
  COVERAGE="partial"
fi

if [ -z "$FETCH_CMD" ]; then
  say "NO FETCHER: there is no usable PROPOSE_DOMAIN_FETCH_CMD (unset, empty, or rejected above as not executable), so this run made ZERO external calls and fetched no domain sources. Coverage: partial. Every domain expectation is therefore UNVERIFIED, and no candidate is written from an uncorroborated expectation."
fi
say "external calls made: $FETCHES_USED of a cap of $MAX_FETCHES; sources fetched: $n_fetched of $n_competitors recorded in the store; coverage: $COVERAGE"
if [ "$n_notreached" -gt 0 ]; then
  while IFS= read -r nr; do [ -n "$nr" ] && say "  not reached: $nr"; done < "$WORK/notreached.txt"
fi

# ---------------------------------------------------------------------------
# 13. One pass per catalogue expectation, in sorted slug order.
# ---------------------------------------------------------------------------
emitted=0
read_catalogue | LC_ALL=C sort > "$WORK/catalogue.txt"

while IFS='|' read -r slug title source_terms inv_terms scope_terms kind; do
  [ -n "${slug:-}" ] || continue

  # Delimiter safety, as in propose-work.sh: the filename is "domain--<slug>.md", so a slug
  # containing "--" could make two distinct expectations resolve to one name and silently
  # overwrite through guarded_write's `cat >`. Refuse loudly; a skipped expectation is named.
  case "$slug" in
    *--*) say "refusing '$slug' - '--' inside a slug collides with the filename delimiter - not proposed"; continue ;;
  esac

  # ---- (c) the domain expectation: is it corroborated by any FETCHED source? ---------------
  terms_to_patterns "$source_terms" "$WORK/src.pat"
  : > "$WORK/cites.tsv"
  n_cites=0
  if [ -s "$WORK/src.pat" ]; then
    while IFS="$(printf '\t')" read -r sname surl slf sstate sstale sbody; do
      [ -n "${sname:-}" ] || continue
      [ "${sstate:-}" = "fetched" ] || continue
      [ -n "${sbody:-}" ] && [ -f "$sbody" ] || continue
      # grep -q directly against a FILE - never the right-hand side of a pipe.
      if grep -q -I -i -E -f "$WORK/src.pat" "$sbody" 2>/dev/null; then
        printf '%s\t%s\t%s\t%s\n' "$sname" "$surl" "$slf" "$sstale" >> "$WORK/cites.tsv"
      fi
    done < "$WORK/sources.tsv"
    n_cites="$(awk 'END{print NR+0}' "$WORK/cites.tsv")"
  fi

  if [ "$n_cites" -eq 0 ]; then
    say "unverified domain expectation '$slug' - no fetched source corroborates it, so nothing is claimed and nothing is written for it"
    continue
  fi

  # ---- (b) the inventory: do WE do it? ----------------------------------------------------
  terms_to_patterns "$inv_terms" "$WORK/inv.pat"
  code_hits=""
  doc_hits=""
  if [ -s "$WORK/inv.pat" ]; then
    code_hits="$(search_surface "$WORK/code.list" "$WORK/inv.pat")"
    doc_hits="$(search_surface "$WORK/doc.list" "$WORK/inv.pat")"
  fi

  # THE UNVERIFIED RULE. Confirmed present => not a gap at all. Named in docs but unconfirmed in
  # code, or searched against an empty/termless surface => UNVERIFIED, never missing. Only a
  # search that actually ran against a non-empty code surface and found nothing may say missing.
  inv_status=""
  inv_reason=""
  if [ -n "$code_hits" ]; then
    inv_status="present"
  elif [ ! -s "$WORK/inv.pat" ]; then
    inv_status="unverified"
    inv_reason="this expectation carries no inventory terms, so the inventory was never actually interrogated for it"
  elif [ "$n_code_files" -eq 0 ]; then
    inv_status="unverified"
    inv_reason="the code surface was empty - zero files matched the code globs under the project root, so a no-match here is a fact about the search, not about the project"
  elif [ "$code_truncated" = "1" ] || [ "$doc_truncated" = "1" ]; then
    # EITHER surface, not just the code one. The doc surface feeds the documented-but-unconfirmed
    # arm below, so a truncated doc surface can hide the very mention that would have made this
    # `unverified` - and reporting `missing` off a half-read surface is the same defect one
    # surface over. The printed cap line fires on either too; these two must agree or the file
    # states a rule its own verdict did not follow.
    inv_status="unverified"
    inv_reason="a search surface was TRUNCATED at the per-surface cap of $SURFACE_FILE_CAP (code: $n_code_total matched, $n_code_files searched; docs: $n_doc_total matched, $n_doc_files searched), so a no-match may simply lie past the cap - the search was incomplete, which is a fact about the search and not about the project"
  elif [ -n "$doc_hits" ]; then
    inv_status="unverified"
    inv_reason="the terms appear in the doc surface but in no code file, so the inventory cannot confirm this either way - it is documented but unconfirmed, which is not the same as absent"
  else
    inv_status="missing"
    inv_reason="the terms matched nothing in either surface, and both surfaces were non-empty and were searched"
  fi

  if [ "$inv_status" = "present" ]; then
    say "not a gap: '$slug' is already confirmed in this project's code surface - $(printf '%s' "$code_hits" | awk 'NR==1{print}')"
    continue
  fi

  classification="$(classify_gap "$kind" "$scope_terms" "$SCOPE_TEXT")"
  token="domain-gap: $slug@$classification"

  covered_by="$(superseded_by "$token")"
  if [ -n "$covered_by" ]; then
    say "suppressed '$slug' ($classification) - its token is already recorded in $covered_by"
    continue
  fi

  {
    printf '# Proposed (domain basis): %s\n\n' "$title"
    printf '%s\n\n' "$token"
    printf -- '- basis: the domain expectation set, fetched through `fetch_source` from the product store'"'"'s `competitors[]`\n'
    printf -- '- product store: `%s`, read through `read-product.sh`\n' "$STORE_SHOWN"
    printf -- '- domain: %s\n' "$P_DOMAIN"
    printf -- '- stance: %s\n' "$P_STANCE"
    printf -- '- default action: %s\n' "$P_DEFAULT_ACTION"
    printf -- '  (read verbatim from `read-product.sh`'"'"'s `stance_default_action`; the stance-to-action mapping has exactly one home and is never re-derived here)\n'
    printf -- '- classification: %s\n' "$classification"
    printf -- '- inventory status: %s\n' "$inv_status"
    printf -- '- coverage: %s\n' "$COVERAGE"
    if [ "$n_notreached" -gt 0 ]; then
      printf -- '- not reached: '
      awk 'NF{printf "%s%s", (c++?"; ":""), $0} END{printf "\n"}' "$WORK/notreached.txt"
    fi
    printf -- '- sources corroborating this expectation: %s of the %s fetched (%s recorded in the store)\n' \
      "$n_cites" "$n_fetched" "$n_competitors"
    printf -- '- external calls made by this run: %s of a cap of %s\n' "$FETCHES_USED" "$MAX_FETCHES"

    printf '\n## Problem\n\n'
    printf 'Fetched domain sources describe **%s**. This project'"'"'s own code and docs do not\n' "$title"
    printf 'confirm it: the inventory status is `%s`.\n\n' "$inv_status"
    if [ "$inv_status" = "unverified" ]; then
      printf 'READ THE STATUS BEFORE THE CLAIM: `unverified` does NOT mean the capability is absent. It\n'
      printf 'means %s.\n' "$inv_reason"
      printf 'Confirming or refuting it by hand is the first thing to do with this file.\n\n'
    else
      printf 'The `missing` status rests on a search that actually ran: %s.\n\n' "$inv_reason"
    fi
    printf 'The domain half of this claim is the WEAKEST of the three inputs - it is competitor and\n'
    printf 'vendor text, which overstates. Nothing below is a demand claim: no user has been observed\n'
    printf 'asking for this.\n'

    printf '\n## Goal\n\n'
    printf 'Decide whether this project should do **%s**, given a stance of `%s`\n' "$title" "$P_STANCE"
    printf 'whose default action on a discovered gap is `%s` - or record why not, and\n' "$P_DEFAULT_ACTION"
    printf 'dismiss this candidate durably.\n'

    printf '\n## Scope\n\n'
    printf -- '- Confirm or refute the inventory status `%s` by hand at the surfaces named under Evidence.\n' "$inv_status"
    printf -- '- Confirm or correct the classification `%s`.\n' "$classification"
    printf -- '- If it is worth doing, hand the decided gap to `/product-owner`; this file deliberately stops\n'
    printf -- '  short of user stories and acceptance criteria for the work itself.\n'

    printf '\n## Acceptance criteria\n\n'
    printf -- '- [ ] The inventory status has been checked by hand at the surfaces and terms listed below.\n'
    printf -- '- [ ] The classification `%s` is confirmed or corrected.\n' "$classification"
    printf -- '- [ ] Either the work is scoped elsewhere, or this candidate is dismissed durably.\n'
    printf -- '      Deleting this file only silences it until the next run recomputes the same token. To\n'
    printf -- '      dismiss it permanently, paste the `%s`\n' "$token"
    printf -- '      line above into a requirement file stamped `## Status: done` anywhere under the\n'
    printf -- '      requirements directory. The next run finds that token and suppresses this candidate,\n'
    printf -- '      naming the file it found it in.\n'

    printf '\n## Evidence\n\n'
    printf 'Two classes, and they are not equal.\n\n'

    printf '### Where this looked for the capability (evidence class: derived)\n\n'
    printf 'Direct reads only - grep over this project'"'"'s own files. No code graph is built or read.\n\n'
    printf -- '- code surface: %s file(s) matching `%s` under `%s`\n' "$n_code_files" "$CODE_GLOBS" "$ROOT"
    printf -- '- doc surface: %s file(s) matching `%s` under the same root\n' "$n_doc_files" "$DOC_GLOBS"
    printf -- '- orientation memos: %s file(s) under `.agent/orientation/` (inside the doc surface above)\n' "$n_orient_files"
    printf -- '- pruned from both surfaces: `.git`, `node_modules`, `vendor`, the whole `.supervisor/`\n'
    printf -- '  runtime tree, the output and requirements directories, every `domain--*.md` file\n'
    printf -- '  wherever it sits, the product store, and this basis'"'"'s OWN artefacts - the script, its\n'
    printf -- '  self-test and its fixture tree - so that neither a candidate written by an earlier run,\n'
    printf -- '  nor the store being asked about, nor the search terms of the searcher itself can\n'
    printf -- '  "confirm" a capability and make a real gap silently disappear\n'
    if [ "$code_truncated" = "1" ] || [ "$doc_truncated" = "1" ]; then
      # Name the surface(s) ACTUALLY truncated. Leading with the code surface unconditionally
      # told a reader the code surface was cut short on a doc-only truncation, where every code
      # file had in fact been searched. The numbers were true and the sentence was not, and an
      # evidence narrative that misidentifies the incomplete surface undercuts the whole artefact.
      if [ "$code_truncated" = "1" ] && [ "$doc_truncated" = "1" ]; then
        cap_which="BOTH surfaces were truncated"
      elif [ "$code_truncated" = "1" ]; then
        cap_which="the CODE surface was truncated (every doc file was searched)"
      else
        cap_which="the DOC surface was truncated (every code file was searched)"
      fi
      printf -- '- per-surface file cap: %s - **REACHED**: %s.\n' "$SURFACE_FILE_CAP" "$cap_which"
      printf -- '  code: %s matched, %s searched. docs: %s matched, %s searched.\n' "$n_code_total" "$n_code_files" "$n_doc_total" "$n_doc_files"
      printf -- '  A no-match on a truncated surface is reported `unverified`, never absent - the\n'
      printf -- '  evidence may lie past the cap.\n'
    else
      printf -- '- per-surface file cap: %s - not reached; every matching file was searched, so a\n' "$SURFACE_FILE_CAP"
      printf -- '  no-match here is a fact about the project rather than about the cap.\n'
    fi
    printf -- '- exact terms used (matched case-insensitively, on word boundaries, never as bare substrings): '
    awk '{printf "%s`%s`", (c++?", ":""), $0} END{printf "\n"}' "$WORK/inv.pat.raw"
    if [ -n "$doc_hits" ]; then
      printf -- '- matched in the doc surface:\n'
      printf '%s\n' "$doc_hits" | awk 'NF{printf "  - `%s`\n", $0}'
    else
      printf -- '- matched in the doc surface: nothing\n'
    fi
    printf -- '- matched in the code surface: nothing\n'
    printf -- '- conclusion: `%s` - %s.\n' "$inv_status" "$inv_reason"

    printf '\n### What the domain expects (evidence class: external/judgment - the weakest input)\n\n'
    printf 'Each line is a source this run actually fetched through `fetch_source`, with the url and the\n'
    printf 'fetch date **as recorded in the product store**. This basis never writes the store, so a fetch\n'
    printf 'performed by this run does not restamp any date below.\n\n'
    awk -F'\t' -v maxage="$MAX_SOURCE_AGE_SECONDS" 'NF>=4 {
      date_txt = $3
      if ($4 == "never-fetched") { date_txt = "never fetched (no date has ever been recorded for it)" }
      else if ($4 == "stale")    { date_txt = $3 " - STALE: older than the " maxage "s staleness threshold" }
      else if ($4 == "unknown")  { date_txt = $3 " - staleness unknown (the recorded date could not be read as a date; unknown is not old)" }
      printf "- %s - url: %s - fetch date: %s\n", $1, $2, date_txt
    }' "$WORK/cites.tsv"
    printf '\n'
    printf 'Terms searched for in that source text (at least one of them matched in every source listed above): '
    awk '{printf "%s`%s`", (c++?", ":""), $0} END{printf "\n"}' "$WORK/src.pat.raw"
    printf '\n'
    printf 'The judgment in this section is that a capability named by sources like these is a\n'
    printf '`%s` for a project in this domain. That is a judgment, not a measurement.\n' "$classification"

    printf '\n### Coverage\n\n'
    printf -- '- coverage: %s (%s external call(s) made against a cap of %s; %s of %s recorded source(s) fetched)\n' \
      "$COVERAGE" "$FETCHES_USED" "$MAX_FETCHES" "$n_fetched" "$n_competitors"
    if [ "$n_notreached" -gt 0 ]; then
      printf -- '- not reached, by name:\n'
      awk 'NF{printf "  - %s\n", $0}' "$WORK/notreached.txt"
    else
      printf -- '- every source recorded in the store was reached.\n'
    fi

    printf '\n---\n\n'
    printf 'This file is a candidate, not a decision and not a queue entry.\n'
    printf '`.supervisor/requirements/proposed/` is deliberately NOT an `/automate --folder` target;\n'
    printf 'promotion is a human moving a file out of it.\n'
  } | guarded_write "domain--${slug}.md" || continue

  emitted=$(( emitted + 1 ))
  say "proposed '$slug' ($classification, inventory $inv_status, $n_cites corroborating source(s)) -> $OUT_DIR/domain--${slug}.md"
done < "$WORK/catalogue.txt"

say "$emitted candidate(s) written to $OUT_DIR - nothing was queued, and nothing will be until a human moves a file out of it"
exit 0
