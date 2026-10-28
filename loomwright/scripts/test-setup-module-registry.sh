#!/usr/bin/env bash
# test-setup-module-registry.sh — the `/setup` module list has ONE authority, the Pattern 2
# registry table in skills/setup/SKILL.md; every surface that restates it is checked against it.
#
# Checks (each a function over file paths, so the mutation controls re-run the same check):
#   R. the registry parses: at least one row, every row has a backticked module name and a
#      non-empty Subcommands cell (the cell `/setup --help` prints);
#   P. PARITY — commands/setup.md's `## Parameters` `- **module**` list and the registry name the
#      same set of modules (each direction reported);
#   U. commands/setup.md's Usage block has a `/setup <module>` line for every registry module and a
#      `/setup --help` line;
#   H. HELP — commands/setup.md's help dispatch names all three aliases `--help`, `-h`, `help`, and
#      the help is generated from the registry (a line naming the Subcommands cell and Pattern 2);
#   N. UNKNOWN MODULE — commands/setup.md prints `Setup: unknown module '<arg>'` followed by the help;
#   S. RESTATING SURFACES — the dashboard status table (docs/command-parts/setup/dashboard.md), the
#      `/setup` entry of docs/command-parts/agent-help/more.md, and README.md's "Optional
#      integrations" sentence and Setup row each name every registry module (case-insensitive,
#      `-` read as a space) or point to the registry;
#   C. COUNT-FREE — none of those surfaces, commands/setup.md or the skill carries a literal module
#      count (`<number> modules`, `across <number> modules`, a spelled-out number of modules);
#   D. the dashboard's top-level question keeps exactly four options, and each nested question at
#      most four.
#   M. MUTATION CONTROLS — gated on non-empty + differs: `statusline` dropped from the Parameters
#      list (P), an extra registry row (P), `-h` dropped from the help dispatch (H), the unknown
#      module line deleted (N), `base-branch` or `providers` dropped from the dashboard table (S), a literal
#      module count added to the dashboard (C), a fifth top-level dashboard option (D).
# Read-only; scratch files under mktemp -d. Exit 0 = all pass, 1 = any failure.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
export LC_ALL=C
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
REPO="$(cd "$PLUGIN/.." && pwd)"
SKILL="$PLUGIN/skills/setup/SKILL.md"
CMD="$PLUGIN/commands/setup.md"
DASH="$PLUGIN/docs/command-parts/setup/dashboard.md"
MORE="$PLUGIN/docs/command-parts/agent-help/more.md"
README="$REPO/README.md"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" 2>/dev/null' EXIT

for f in "$SKILL" "$CMD" "$DASH" "$MORE" "$README"; do
  [ -s "$f" ] || { echo "SETUP BROKEN: missing $f" >&2; exit 1; }
done

# registry_rows <skill> — the Pattern 2 table's data rows, verbatim.
registry_rows() {
  awk '/^### Pattern 2/ {s = 1; next} s && /^### / {exit} s && /^\| `[^`]+` \|/ {print}' "$1"
}
# registry_modules <skill> — the module names, one per line, in registry order.
registry_modules() { registry_rows "$1" | awk -F '|' '{m = $2; gsub(/[ `]/, "", m); print m}'; }
# param_modules <setup.md> — the backticked names on the `## Parameters` `- **module**` line.
param_modules() {
  awk '/^## Parameters/ {s = 1; next} s && /^## / {exit} s && /^- \*\*module\*\*/ {print; exit}' "$1" \
    | grep -oE '`[a-z0-9-]+`' | tr -d '`'
}

check_registry() {
  local probs=0 n
  n="$(registry_rows "$1" | wc -l | tr -d ' ')"
  [ "$n" -gt 0 ] || { echo "    no registry rows under ### Pattern 2"; return 1; }
  registry_rows "$1" | awk -F '|' '{c = $3; gsub(/^ +| +$/, "", c); if (c == "") print "    row " $2 " has an empty Subcommands cell"}' > "$TMP/r.$$"
  [ -s "$TMP/r.$$" ] && { cat "$TMP/r.$$"; probs=1; }
  grep -q '| Subcommands |' < <(awk '/^### Pattern 2/ {s = 1; next} s && /^\| Module \|/ {print; exit}' "$1") \
    || { echo "    the registry header has no Subcommands column"; probs=1; }
  [ "$probs" -eq 0 ]
}

check_parity() {
  local probs=0 m
  registry_modules "$1" | sort -u > "$TMP/reg.$$"
  param_modules "$2" | sort -u > "$TMP/par.$$"
  [ -s "$TMP/par.$$" ] || { echo "    no module list under ## Parameters"; return 1; }
  for m in $(comm -23 "$TMP/reg.$$" "$TMP/par.$$"); do echo "    registry module '$m' missing from the Parameters module list"; probs=1; done
  for m in $(comm -13 "$TMP/reg.$$" "$TMP/par.$$"); do echo "    Parameters names '$m', which is not a registry module"; probs=1; done
  [ "$probs" -eq 0 ]
}

check_usage() {
  local probs=0 m
  awk '/^## Usage/ {s = 1; next} s && /^## / {exit} s' "$2" > "$TMP/usage.$$"
  for m in $(registry_modules "$1"); do
    grep -qE "^/setup $m( |$)" "$TMP/usage.$$" || { echo "    Usage block has no '/setup $m' line"; probs=1; }
  done
  grep -qE '^/setup --help( |$)' "$TMP/usage.$$" || { echo "    Usage block has no '/setup --help' line"; probs=1; }
  [ "$probs" -eq 0 ]
}

check_help() {
  local line probs=0 a
  line="$(grep -E '^- \*\*Help dispatch:\*\*' "$1" | head -1)"
  [ -n "$line" ] || { echo "    no '- **Help dispatch:**' line"; return 1; }
  for a in '`--help`' '`-h`' '`help`'; do
    case "$line" in *"$a"*) ;; *) echo "    the help dispatch does not name $a"; probs=1 ;; esac
  done
  grep -q 'Subcommands cell' < <(grep -E '^- \*\*Help = the registry' "$1") \
    && grep -q 'Pattern 2' < <(grep -E '^- \*\*Help = the registry' "$1") \
    || { echo "    no line generating the help from the registry's Subcommands cell (Pattern 2)"; probs=1; }
  [ "$probs" -eq 0 ]
}

check_unknown() {
  grep -q 'STOPS' < <(grep -F "prints \`Setup: unknown module '<arg>'\`, then the help" "$1") && return 0
  echo "    no line printing \`Setup: unknown module '<arg>'\` followed by the help (and stopping)"
  return 1
}

# names_all <segment file> <label> — every registry module named (or a registry pointer).
names_all() {
  local m norm probs=0
  [ -s "$1" ] || { echo "    $2: segment not found"; return 1; }
  grep -qi 'registry' "$1" && return 0
  tr 'A-Z-' 'a-z ' < "$1" > "$1.n"
  for m in $(registry_modules "$SKILL_UNDER_TEST"); do
    norm="$(printf '%s' "$m" | tr 'A-Z-' 'a-z ')"
    grep -qF -- "$norm" "$1.n" || { echo "    $2 does not name module '$m'"; probs=1; }
  done
  [ "$probs" -eq 0 ]
}

check_surfaces() {
  local probs=0
  SKILL_UNDER_TEST="$1"
  awk '/^\| Module +\| Status/ {s = 1} s && /^```/ {exit} s' "$2" > "$TMP/s-dash.$$"
  names_all "$TMP/s-dash.$$" "dashboard status table" || probs=1
  awk '/^### .*\/setup/ {s = 1; next} s && /^### / {exit} s' "$3" > "$TMP/s-more.$$"
  names_all "$TMP/s-more.$$" "agent-help more.md /setup entry" || probs=1
  grep -F '**Optional integrations in one place:**' "$4" > "$TMP/s-r1.$$"
  names_all "$TMP/s-r1.$$" "README Optional integrations sentence" || probs=1
  grep -E '^\| \*\*Setup\*\* \(command\)' "$4" > "$TMP/s-r2.$$"
  names_all "$TMP/s-r2.$$" "README Setup row" || probs=1
  [ "$probs" -eq 0 ]
}

COUNT_RE='([0-9]+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen)[ -]+(optional[ -]+)?modules|(tenth|eleventh|twelfth|thirteenth)[ -]+module'
check_count_free() {
  local f probs=0 hits
  for f in "$@"; do
    hits="$(grep -niE -- "$COUNT_RE" "$f" | cut -c1-160)"
    [ -z "$hits" ] || { echo "    literal module count in ${f#"$REPO"/}:"; printf '%s\n' "$hits" | sed 's/^/      /'; probs=1; }
  done
  [ "$probs" -eq 0 ]
}

# options_after <file> <header literal> — numbered options of the question whose `header` is given.
options_after() {
  awk -v h="- \`header\`: \"$2\"" 'index($0, h) == 1 {s = 1; next}
    s && /^- `options`/ {o = 1; next}
    s && o && /^  [0-9]+\. \*\*/ {n++; next}
    s && o && n > 0 && !/^  [0-9]+\. / {exit}
    END {print n + 0}' "$1"
}
check_dashboard_options() {
  local probs=0 n h
  n="$(options_after "$1" Configure)"
  [ "$n" = "4" ] || { echo "    the top-level dashboard question has $n option(s) (want exactly 4)"; probs=1; }
  for h in $(grep -oE '^- `header`: "[^"]+"' "$1" | sed 's/.*: "//; s/"$//' | grep -v '^Configure$'); do
    n="$(options_after "$1" "$h")"
    { [ "$n" -ge 1 ] && [ "$n" -le 4 ]; } || { echo "    nested question '$h' has $n option(s) (want 1..4)"; probs=1; }
  done
  [ "$probs" -eq 0 ]
}

run_all() { # <skill> <setup.md> <dashboard> <more> <readme> — prints problems, returns 0 iff none
  local probs=0
  check_registry "$1" || probs=1
  check_parity "$1" "$2" || probs=1
  check_usage "$1" "$2" || probs=1
  check_help "$2" || probs=1
  check_unknown "$2" || probs=1
  check_surfaces "$1" "$3" "$4" "$5" || probs=1
  check_count_free "$1" "$2" "$3" "$4" "$5" || probs=1
  check_dashboard_options "$3" || probs=1
  [ "$probs" -eq 0 ]
}

echo "== R/P/U/H/N/S/C/D on the live tree =="
t() { if out="$("$@")"; then ok "$label"; else no "$label"; printf '%s\n' "$out"; fi; }
label="R: the Pattern 2 registry parses ($(registry_modules "$SKILL" | wc -l | tr -d ' ') rows, each with a Subcommands cell)"; t check_registry "$SKILL"
label="P: the Parameters module list and the registry name the same modules"; t check_parity "$SKILL" "$CMD"
label="U: the Usage block has a /setup line per registry module and a /setup --help line"; t check_usage "$SKILL" "$CMD"
label="H: the help dispatch names --help, -h and help, and the help is generated from the registry"; t check_help "$CMD"
label="N: an unknown module prints 'Setup: unknown module' then the help, and stops"; t check_unknown "$CMD"
label="S: dashboard table, more.md /setup entry and README's two lines name every module (or point to the registry)"; t check_surfaces "$SKILL" "$DASH" "$MORE" "$README"
label="C: no literal module count on any /setup surface"; t check_count_free "$SKILL" "$CMD" "$DASH" "$MORE" "$README"
label="D: the dashboard keeps exactly four top-level options; nested questions have at most four"; t check_dashboard_options "$DASH"

echo "== M. mutation controls (each must be REJECTED) =="
# mutate <name> <which: skill|cmd|dash> <awk program> — run_all on a copy with one file mutated.
mutate() {
  local name="$1" which="$2" prog="$3" s="$SKILL" c="$CMD" d="$DASH" src dst
  case "$which" in skill) src="$SKILL" ;; cmd) src="$CMD" ;; dash) src="$DASH" ;; esac
  dst="$TMP/m-$name.md"
  awk "$prog" "$src" > "$dst"
  if [ ! -s "$dst" ] || cmp -s "$dst" "$src"; then no "MUTATION CONTROL $name: mutant empty or identical — inconclusive"; return 0; fi
  case "$which" in skill) s="$dst" ;; cmd) c="$dst" ;; dash) d="$dst" ;; esac
  if run_all "$s" "$c" "$d" "$MORE" "$README" >/dev/null 2>&1; then no "MUTATION CONTROL $name: ACCEPTED"
  else ok "MUTATION CONTROL $name: rejected"; fi
}
if run_all "$SKILL" "$CMD" "$DASH" "$MORE" "$README" >/dev/null 2>&1; then
  mutate param-drops-statusline cmd '/^- \*\*module\*\*/ {sub(/, `statusline`/, "")} {print}'
  mutate registry-extra-row skill '{print} /^\| `statusline` \|/ {print "| `frob` | `status` | x | x | x |"}'
  mutate help-drops-h cmd '/^- \*\*Help dispatch:\*\*/ {sub(/, `-h`/, "")} {print}'
  mutate unknown-line-deleted cmd 'index($0, "Setup: unknown module") {next} {print}'
  mutate dash-drops-base-branch dash '/^\| base-branch / {next} {print}'
  mutate dash-drops-providers dash '/^\| providers / {next} {print}'
  mutate dash-literal-count dash '{print} /^Print the dashboard:/ {print "(10 modules)"}'
  mutate dash-fifth-option dash '{print} /^  4\. \*\*Nothing/ {print "  5. **More** — x."}'
else
  no "the live tree fails run_all, so the mutation controls are inconclusive"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
