#!/usr/bin/env bash
# test-agent-memory-permission.sh — the agent-memory write-permission contract is STATED, in the
# shared agent contract and in every `memory: project` agent prompt, and says the same three things
# in all seven places.
#
# WHY THIS EXISTS
#   Decision (c) of the write-time-validation item: a `memory: project` agent may NOT write its own
#   `.claude/agent-memory/` store. It writes PROPOSALS; every store write goes through the sole
#   writer write-agent-memory.sh under a human --confirm. Decision (d): the proposal trigger is
#   SURPRISE-ONLY. Neither was written down anywhere before this change, and the silence was the
#   defect — six prompts each had to infer the answer, and the tool surface gives the WRONG answer
#   (see below), so inference was actively misleading.
#
# WHY IT ASSERTS CONTENT AND NOT A HEADING
#   A `grep -q '^### Agent memory write permission'` gate is satisfiable by adding seven EMPTY
#   headings. That is the vacuous-guard class this repo keeps catching: a check that cannot
#   distinguish the stated contract from a section title. So each surface is reduced to the text
#   UNDER its heading (heading to the next heading of any level) and four substrings are required
#   in that slice:
#     (1) the refusal rule      — the agent may NOT write its own store
#     (2) the sole writer       — where the write actually goes instead
#     (3) the surprise-only trigger, verbatim from decision (d)
#     (4) the Bash caveat       — see below; without it the reader draws the wrong conclusion
#   Substring tests are plain shell `case` globs, not regexes: the literals contain backticks,
#   slashes and dots, and there is no escaping to get wrong.
#
# THE BASH CAVEAT IS PART OF THE CONTRACT, NOT COLOUR
#   `disallowedTools` blocks Write/Edit for some of these agents, so a reader checking the tool
#   list concludes the store is already unreachable. It is not: the code-reviewer prompt records
#   that Bash is NOT restricted by the harness, which makes a shell-redirection store write
#   reachable for all six agents whatever the allowlist says. The prohibition is therefore a
#   prompt-level contract, and a prompt that omits the caveat leaves the reader with a false sense
#   that the tool surface enforces it. Required text, checked like the rest.
#
# MUTATION CONTROL (mandatory)
#   Every assertion above is re-run against a fixture in which the refusal sentence has been
#   deleted from exactly ONE prompt, through the SAME scan_permission() code path as the real run.
#   The control asserts three things, because the obvious one does not discriminate: the mutant is
#   reported, the mutant is reported with the RIGHT verdict, and NO other file is reported. The
#   mutation itself is verified to have changed the file — a `sed` that matched nothing would make
#   the control vacuous while it still looked green.
#
# Portability: macOS bash 3.2 + BSD userland dev host, GNU/Linux CI. No `mapfile`, no `sed -i`, no
# `stat` flavour, no `pipefail` (a `producer | grep -q` reports the producer's SIGPIPE under it).
# Exit 0 = all pass, 1 = any fail — matching the sibling test-*.sh suites CI picks up by glob.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$HERE/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_ROOT/.." && pwd)"

PASS=0
FAIL=0
ok() { echo "PASS: $1"; PASS=$((PASS + 1)); }
no() { echo "FAIL: $1" >&2; FAIL=$((FAIL + 1)); }

HEADING='### Agent memory write permission'

# The four required literals. Chosen to be the load-bearing CLAUSE of each rule rather than a
# whole sentence, so ordinary copy-editing does not trip the gate while a deleted rule does.
LIT_REFUSAL='may NOT write its own `.claude/agent-memory/` store directly'
LIT_WRITER='write-agent-memory.sh'
LIT_SURPRISE='The proposal trigger is SURPRISE-ONLY'
LIT_BASH='Bash is not restricted by the harness'

# The seven surfaces: the shared contract at the REPO ROOT (there is no loomwright/ copy, and
# creating one would fork the contract into a file no gate scans), plus the six `memory: project`
# prompts.
#
# CROSS-PLUGIN SINCE THE SELVEDGE SPLIT. Two of those six prompts (the QA pair) now live in the
# SELVEDGE plugin. The contract itself stays SINGLE-COPY in loomwright — duplicating this suite
# into selvedge would fork the rule into two files that can disagree — so the SURFACE LIST reaches
# across the plugin boundary instead. The selvedge paths are spelled out rather than discovered:
# this suite asserts a named contract over a NAMED set of prompts, so a list that silently shrank
# when a plugin was renamed would be a false green, which is the opposite of what discovery buys a
# gate that iterates over "whatever exists".
SELVEDGE_ROOT="$REPO_ROOT/selvedge"

SURFACES="$REPO_ROOT/AGENT_GUIDELINES.md
$PLUGIN_ROOT/agents/code-reviewer.md
$PLUGIN_ROOT/agents/launch-pad.md
$PLUGIN_ROOT/agents/product-owner.md
$SELVEDGE_ROOT/agents/qa-executor.md
$SELVEDGE_ROOT/agents/qa-strategist.md
$PLUGIN_ROOT/agents/red-team-reviewer.md"

# ---------------------------------------------------------------------------------------------
# section_of <file> — the text under the heading, up to the next heading of ANY level or EOF.
# `/^#+ /` rather than an interval expression, which BSD awk and gawk disagree about.
# ---------------------------------------------------------------------------------------------
section_of() {
  awk -v h="$HEADING" '
    !inside && index($0, h) == 1 && length($0) == length(h) { inside = 1; next }
    inside && /^#+ / { inside = 0 }
    inside { print }
  ' "$1" 2>/dev/null
}

# ---------------------------------------------------------------------------------------------
# CORE SCANNER — shared by the real run and by the mutation controls.
#
# scan_permission <file>...
#   Emits one TAB-separated verdict per file:
#     OK          <file>            heading present and all four literals under it
#     UNREADABLE  <file>            could not examine — never reported as clean (decision (b))
#     NOHEADING   <file>            no `### Agent memory write permission` section
#     NOREFUSAL   <file>            heading present, refusal rule absent
#     NOWRITER    <file>            heading present, sole writer unnamed
#     NOSURPRISE  <file>            heading present, surprise-only trigger absent
#     NOBASH      <file>            heading present, Bash-reachability caveat absent
#   A file can emit several defect verdicts; classification is the caller's job.
# ---------------------------------------------------------------------------------------------
has_lit() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

scan_permission() {
  local f sect bad
  for f in "$@"; do
    [ -n "$f" ] || continue
    if [ ! -e "$f" ]; then printf 'NOHEADING\t%s\n' "$f"; continue; fi
    if [ ! -r "$f" ]; then printf 'UNREADABLE\t%s\n' "$f"; continue; fi
    # Heading presence is decided SEPARATELY from section content. Deriving "no heading" from an
    # empty extraction would conflate the two, and one of them — a heading with nothing under it —
    # is the exact vacuity this suite exists to reject: it would be reported as a missing section
    # rather than as an unstated contract, and (M5) below would silently stop discriminating.
    if ! grep -q "^$HEADING\$" "$f" 2>/dev/null; then printf 'NOHEADING\t%s\n' "$f"; continue; fi
    sect="$(section_of "$f")"
    bad=0
    has_lit "$sect" "$LIT_REFUSAL"  || { printf 'NOREFUSAL\t%s\n'  "$f"; bad=1; }
    has_lit "$sect" "$LIT_WRITER"   || { printf 'NOWRITER\t%s\n'   "$f"; bad=1; }
    has_lit "$sect" "$LIT_SURPRISE" || { printf 'NOSURPRISE\t%s\n' "$f"; bad=1; }
    has_lit "$sect" "$LIT_BASH"     || { printf 'NOBASH\t%s\n'     "$f"; bad=1; }
    [ "$bad" -eq 0 ] && printf 'OK\t%s\n' "$f"
  done
}

# ---------------------------------------------------------------------------------------------
# REAL RUN
# ---------------------------------------------------------------------------------------------
# shellcheck disable=SC2086
RESULTS="$(scan_permission $SURFACES)"

n_surfaces="$(printf '%s\n' "$SURFACES" | grep -c .)"
n_ok="$(printf '%s\n' "$RESULTS" | grep -c '^OK	')"

# Anti-vacuity: the surface list itself must not have collapsed. A glob or path change that
# emptied it would make every check below pass over nothing.
if [ "$n_surfaces" -eq 7 ]; then
  ok "surface list is intact: 7 files (the root shared contract + six \`memory: project\` prompts)"
else
  no "surface list has $n_surfaces entries, expected 7 — the list has drifted from the six memory: project agents"
fi

if [ "$n_ok" -eq "$n_surfaces" ]; then
  ok "all $n_ok surfaces state the write-permission contract in full (refusal + sole writer + surprise-only + Bash caveat)"
else
  printf '%s\n' "$RESULTS" | grep -v '^OK	' | while IFS="$(printf '\t')" read -r verdict f; do
    [ -z "${f:-}" ] && continue
    case "$verdict" in
      NOHEADING)  echo "    $f has no '$HEADING' section" >&2 ;;
      UNREADABLE) echo "    $f could not be read — unexamined, not clean" >&2 ;;
      NOREFUSAL)  echo "    $f does not state the no-direct-write rule ('$LIT_REFUSAL')" >&2 ;;
      NOWRITER)   echo "    $f does not name the sole writer ('$LIT_WRITER')" >&2 ;;
      NOSURPRISE) echo "    $f does not state the surprise-only trigger ('$LIT_SURPRISE')" >&2 ;;
      NOBASH)     echo "    $f does not state that Bash is unrestricted, so a reader would take the tool list as enforcement" >&2 ;;
    esac
  done
  no "$((n_surfaces - n_ok)) of $n_surfaces surfaces are missing part of the write-permission contract"
fi

# The heading form is identical in all seven, so a later edit cannot split the contract into two
# spellings that each look present on their own surface.
h_count=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  c="$(grep -c "^$HEADING\$" "$f" 2>/dev/null)"
  case "$c" in ''|*[!0-9]*) c=0 ;; esac
  [ "$c" -eq 1 ] && h_count=$((h_count + 1))
done <<EOF
$SURFACES
EOF
if [ "$h_count" -eq 7 ]; then
  ok "the heading form '$HEADING' appears exactly once in each of the seven files"
else
  no "$h_count of 7 files carry exactly one '$HEADING' heading — the form has drifted"
fi

# There must be no forked copy of the shared contract under the plugin dir. Decision (c) written
# into loomwright/AGENT_GUIDELINES.md would satisfy a self-reported outputs check while landing in
# a document nothing reads — the pinned false-completion path for this work.
if [ -e "$PLUGIN_ROOT/AGENT_GUIDELINES.md" ]; then
  no "a forked shared contract exists at loomwright/AGENT_GUIDELINES.md — the contract lives at the REPO ROOT only"
else
  ok "no forked shared contract under loomwright/ — the root AGENT_GUIDELINES.md is the only copy"
fi

# ---------------------------------------------------------------------------------------------
# MUTATION CONTROLS — prove the assertions above CAN fail, and fail NARROWLY.
# ---------------------------------------------------------------------------------------------
FIX="$(mktemp -d "${TMPDIR:-/tmp}/agent-memory-permission.XXXXXX")" || FIX=""
if [ -z "$FIX" ] || [ ! -d "$FIX" ]; then
  no "(M) could not create a fixture dir — the mutation controls did not run, so the checks above are UNPROVEN"
else
  trap 'rm -rf "$FIX"' EXIT

  # The VICTIM is deliberately still a QA prompt — now the SELVEDGE copy. Re-pointing it at a
  # loomwright prompt would have quietly removed the only mutation control that exercises a
  # cross-plugin surface, i.e. exactly the path this split newly made breakable.
  VICTIM="$SELVEDGE_ROOT/agents/qa-strategist.md"
  MUTANT="$FIX/qa-strategist.md"

  # (M0) Control for the control: an unmutated COPY must scan clean, so a red verdict below can
  # only have come from the mutation and not from copying the file.
  cp "$VICTIM" "$MUTANT" 2>/dev/null
  M_COPY="$(scan_permission "$MUTANT")"
  case "$M_COPY" in
    OK*) ok "(M0) control: an unmutated copy of a prompt scans clean" ;;
    *)   no "(M0) control FAILED: an unmutated copy did not scan clean — verdict was '$M_COPY'" ;;
  esac

  # Delete the refusal sentence. `sed` on a plain, metacharacter-free substring of the rule.
  sed '/may NOT write its own/d' "$VICTIM" > "$MUTANT" 2>/dev/null

  # (M1) The mutation must have CHANGED the file. A sed that matched nothing leaves a byte-identical
  # copy, and every control below would then be asserting things about the unmutated original.
  if cmp -s "$VICTIM" "$MUTANT"; then
    no "(M1) VACUOUS CONTROL: the mutation left the file byte-identical — nothing below proves anything"
  else
    ok "(M1) the mutation really removed the refusal sentence (the fixture differs from the original)"
  fi

  M_ONE="$(scan_permission "$MUTANT")"

  # (M2) The deleted rule is CAUGHT — the content check is not vacuous. Asserted on the verdict,
  # not merely on non-emptiness: NOHEADING would also be non-empty and would mean the section
  # extraction broke rather than that the rule check fired.
  case "$M_ONE" in
    *"NOREFUSAL	$MUTANT"*) ok "(M2) mutation: deleting the refusal sentence IS caught, and reported as NOREFUSAL" ;;
    *) no "(M2) VACUOUS GUARD: a prompt with the refusal rule deleted was not reported as NOREFUSAL — verdict was '$M_ONE'" ;;
  esac

  # (M3) …and it is still recognisably the same SECTION: the heading, the surprise-only trigger and
  # the Bash caveat all survive the mutation, so the failure is attributable to the deleted rule
  # alone rather than to the whole section vanishing.
  case "$M_ONE" in
    *NOHEADING*|*NOSURPRISE*|*NOBASH*)
      no "(M3) the mutation collapsed more than the refusal rule — the control is not narrow: '$M_ONE'" ;;
    *)
      ok "(M3) the mutation is NARROW: only the refusal rule is reported, the rest of the section still passes" ;;
  esac

  # (M4) The failure NAMES ONLY the mutated file. The real (unmutated) six must stay green in the
  # very same scan — a gate that goes red everywhere on one bad file cannot be acted on.
  M_MIX="$(scan_permission "$MUTANT" $SURFACES)"
  others_bad=0
  while IFS="$(printf '\t')" read -r verdict f; do
    [ -z "${f:-}" ] && continue
    case "$verdict" in OK) continue ;; esac
    [ "$f" = "$MUTANT" ] && continue
    echo "    collateral: $f reported $verdict alongside the mutant" >&2
    others_bad=$((others_bad + 1))
  done <<EOF
$M_MIX
EOF
  if [ "$others_bad" -eq 0 ]; then
    ok "(M4) the mutation control names ONLY the mutated file — the other six stay green in the same scan"
  else
    no "(M4) $others_bad unmutated file(s) were reported alongside the mutant — the gate does not localise"
  fi

  # (M5) An EMPTY section is rejected. This is the heading-grep vacuity this suite exists to close,
  # stated as an executable control rather than as a comment: seven empty headings must NOT pass.
  printf '%s\n\n## Something Else\n' "$HEADING" > "$FIX/empty-section.md"
  M_EMPTY="$(scan_permission "$FIX/empty-section.md")"
  case "$M_EMPTY" in
    *NOREFUSAL*) ok "(M5) an EMPTY '$HEADING' section is rejected — a heading alone does not satisfy this gate" ;;
    *)           no "(M5) an empty section passed — the gate degenerates into a heading grep: '$M_EMPTY'" ;;
  esac

  # (M6) A file with no heading at all is NOHEADING, not silently clean.
  printf 'nothing to see here\n' > "$FIX/no-heading.md"
  M_NOHEAD="$(scan_permission "$FIX/no-heading.md")"
  case "$M_NOHEAD" in
    NOHEADING*) ok "(M6) a file with no permission section is reported, not silently passed" ;;
    *)          no "(M6) a file with no permission section was not reported — verdict was '$M_NOHEAD'" ;;
  esac

  # (M7) An UNREADABLE surface is reported as unexamined rather than as clean — decision (b)'s
  # examined-vs-could-not-examine split, applied to this gate's own inputs. Skipped when the test
  # runs as root, where chmod 000 does not deny the owner and the control would be vacuous.
  cp "$VICTIM" "$FIX/unreadable.md" 2>/dev/null
  chmod 000 "$FIX/unreadable.md" 2>/dev/null
  if [ -r "$FIX/unreadable.md" ]; then
    ok "(M7) SKIPPED: the fixture stayed readable (running as root?) — nothing to assert"
  else
    M_UNREAD="$(scan_permission "$FIX/unreadable.md")"
    case "$M_UNREAD" in
      UNREADABLE*) ok "(M7) an unreadable surface is reported UNREADABLE — could-not-examine is never reported as clean" ;;
      *)           no "(M7) an unreadable surface was not distinguished from a clean one: '$M_UNREAD'" ;;
    esac
  fi
  chmod 644 "$FIX/unreadable.md" 2>/dev/null
fi

echo
echo "agent-memory-permission: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
