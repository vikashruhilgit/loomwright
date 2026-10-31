#!/usr/bin/env bash
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
# test-provider-cli-single-launcher.sh — regrowth guard: a provider CLI is started in ONE place.
#
# Why: `setup-providers.sh check` and `lens-run.sh` used to start a provider CLI two different ways
# (the check under the real HOME through its own bounded runner, lens-run under `env -i` with an
# empty temp HOME), so the check reported a provider usable while every routed step failed at
# login. adapters/providers/launch-provider-cli.sh is now the one launcher (allow-list env,
# isolated HOME with the declared login copies, own process group, TERM -> KILL). This guard fails
# when a script starts a provider CLI itself again.
#
# Scope: every `*.sh` under loomwright/scripts/ EXCEPT the launcher itself, self-tests
# (`test-*.sh`, `test-*.d/`) and `fixtures/`. Matching runs on logical lines (the shared
# logical-lines-lib.sh: continuations joined, whole-line comments dropped, a trailing ` # comment`
# stripped), so prose that NAMES a form is never red.
#
# A "provider CLI variable" is `$cli` / `$CLI`, `$PROVIDER_CLI_NAME`, or any name ending `_cli`,
# `_cli_name` or `_cli_bin` (any case), quoted or not, braced or not — the names the provider table
# and its callers use for the binary. `$LENS_CLI_TIMEOUT` and `$CLICK_MODE` are not one.
#
# Rules (id — what it catches):
#   direct    a provider CLI variable in shell command position: `"$cli" …`,
#             `"$PROVIDER_CLI_NAME" …`, `out="$("$cli" --version)"`, `exec "$cli"`, `x=1 "$cli"`,
#             `if "$cli" …; then`. Command position is defined ONCE, in CMD_POS below.
#   wrapped   a launcher-like command in command position — `env`, `nohup`, `nice`, `perl`,
#             `python`/`python3`, `setsid`, `timeout`/`gtimeout`, `stdbuf`, `xargs`, `sudo`, or any
#             word containing `exec` (`rb_exec`, `lens_exec_cli`, …) — with a provider CLI variable
#             as a later word on the same logical line: `env -i … "$PROVIDER_CLI_NAME" …`,
#             `perl -e 'setpgrp; exec …' "$cli" "$@"`.
# Not caught (by design): `command -v "$cli"`, `[ -n "$cli" ]`, `printf '%s' "$cli"`, and the
# launcher call `launch_provider_cli <mode> … "$cli" "${argv[@]}"`, where the variable is data.
#
# Separators inside quoted strings are masked first (mask_quoted below), so a `(` in
# `label="$name ($cli)"` does not open a command position.
#
# Honest limit: a line reader, not a shell parser — a CLI started through a variable with an
# unrelated name, or via `eval`, is not seen. It guards against regrowth of the forms that existed.
#
# ALLOWLIST (below) names each genuine exception as `<path> <rule|*> <reason>`; an entry that no
# longer matches anything is STALE and red, so the list only shrinks. It is empty today.
#
# Controls (a red control means the detector is broken, not that the tree is dirty): the real tree's
# scope is non-empty and holds both launcher callers; each removed form is appended to a SCRATCH
# copy of a caller and must be caught — each mutant gated on non-empty, differs-from-original and
# `bash -n`; a commented form, the launcher call and the read-only uses above are not caught.
# Exit 0 = clean, 1 = a violation or a broken control. Portability: bash 3.2 + BSD userland.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAUNCHER_REL="adapters/providers/launch-provider-cli.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

ALLOWLIST=''

# CLI_VAR — a provider CLI variable reference (POSIX ERE): quoted or bare, braced or not.
CLI_NAME='(([A-Za-z0-9_]*_)?([Cc][Ll][Ii]|[Cc][Ll][Ii]_[Nn][Aa][Mm][Ee]|[Cc][Ll][Ii]_[Bb][Ii][Nn])|PROVIDER_CLI_NAME)'
CLI_VAR='"?\$(\{'"$CLI_NAME"'\}|'"$CLI_NAME"')"?([^A-Za-z0-9_]|$)'

# CMD_POS — "the next word is in shell command position" (POSIX ERE, BSD-grep safe): a command
# boundary — logical-line start (`N:`), `;` `&` `|` `(` `$(` or a backtick — then any run of words
# that keep the next word in command position: a reserved word or prefix builtin
# (if elif while until then do else ! { time exec command) or a `NAME=value` assignment prefix.
CMD_POS='(^[0-9]+:|[;&|(`]|\$\()([[:space:]]*((if|elif|while|until|then|do|else|time|exec|command|!|[{])[[:space:]]|[A-Za-z_][A-Za-z0-9_]*=("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:];&|()"'"'"']*)[[:space:]]))*[[:space:]]*'

WRAPPER='(env|nohup|nice|perl|python3?|setsid|g?timeout|stdbuf|xargs|sudo|[A-Za-z_]*exec[A-Za-z0-9_]*)'

# rule_re <id> — the ERE for one rule id
rule_re() {
  case "$1" in
    direct)  printf '%s' "$CMD_POS$CLI_VAR" ;;
    wrapped) printf '%s' "$CMD_POS$WRAPPER"'[[:space:]]([^|&]*[[:space:]])?'"$CLI_VAR" ;;
  esac
}
RULES='direct wrapped'

# logical_lines <file> — shared with the other source-linting guards
. "$HERE/logical-lines-lib.sh"

# mask_quoted — on `N:text` lines from stdin, replace every command separator (`;` `&` `|` `(`
# and a backtick) that sits INSIDE a quoted string with `_`, so `label="$name ($cli)"` is not read
# as a subshell. Tracks single quotes, double quotes and `$( … )` / `( … )` nesting (a `$(` inside
# double quotes is code again until its `)`); a backslash escapes the next character outside
# single quotes. Still a line reader: a quote opened on one logical line and closed on another is
# not followed.
mask_quoted() {
  awk '{
    line = $0; n = length(line); out = ""; st = 0; sp = 0
    for (i = 1; i <= n; i++) {
      c = substr(line, i, 1)
      if (st == 2) {                                   # inside single quotes
        if (c == "\047") st = 0; else if (c ~ /[;&|(`]/) c = "_"
        out = out c; continue
      }
      if (c == "\\") { out = out c substr(line, i + 1, 1); i++; continue }
      if (st == 1) {                                   # inside double quotes
        if (c == "\"") st = 0
        else if (c == "$" && substr(line, i + 1, 1) == "(") { stk[++sp] = 1; st = 0; out = out "$("; i++; continue }
        else if (c ~ /[;&|(`]/) c = "_"
        out = out c; continue
      }
      if (c == "\047") st = 2
      else if (c == "\"") st = 1
      else if (c == "(") stk[++sp] = 0
      else if (c == ")" && sp > 0) { st = stk[sp--] }
      out = out c
    }
    print out
  }'
}

# scope <root> — every non-test *.sh under <root> except the launcher, relative, sorted
scope() {
  ( cd "$1" && find . -type f -name '*.sh' 2>/dev/null ) | sed 's|^\./||' \
    | grep -vE '(^|/)test-[^/]*\.sh$|(^|/)test-[^/]*\.d/|(^|/)fixtures/' \
    | grep -vxF "$LAUNCHER_REL" | env LC_ALL=C sort
  return 0
}

# raw_hits <root> — `rel:line:rule:text` for every rule hit, allowlist NOT applied
raw_hits() {
  local root="$1" rel rule ll
  scope "$root" | while IFS= read -r rel; do
    ll="$(logical_lines "$root/$rel" | mask_quoted)"
    [ -n "$ll" ] || continue
    for rule in $RULES; do
      grep -E -- "$(rule_re "$rule")" <<<"$ll" | sed "s|^\([0-9]*\):|$rel:\1:$rule:|"
    done
  done
  return 0
}

# drop_allowed — raw hits on stdin minus the allowlisted ones (list via the environment: BSD awk
# refuses a newline in a `-v` value)
drop_allowed() {
  PCSL_ALLOW="$ALLOWLIST" awk -F: 'BEGIN { n = split(ENVIRON["PCSL_ALLOW"], L, "\n"); for (i = 1; i <= n; i++) { if (L[i] == "") continue; split(L[i], w, " "); ok[w[1] SUBSEP w[2]] = 1 } }
    !(($1 SUBSEP $3) in ok) && !(($1 SUBSEP "*") in ok)'
}

violations() { raw_hits "$1" | drop_allowed; return 0; }

echo "== real tree: loomwright/scripts =="
n_scope="$(scope "$HERE" | wc -l | tr -d ' ')"
if [ "$n_scope" -gt 50 ]; then ok "scope holds $n_scope non-test scripts"; else no "scope holds only $n_scope scripts — the scope walk is broken"; fi
for caller in setup-providers.sh adapters/providers/lens-run.sh; do
  if scope "$HERE" | grep -qxF "$caller"; then ok "scope holds the launcher caller $caller"; else no "scope is missing the launcher caller $caller"; fi
done
if scope "$HERE" | grep -qxF "$LAUNCHER_REL"; then no "scope includes the launcher itself"; else ok "scope excludes the launcher itself"; fi
case "$(scope "$HERE" | grep -cE '(^|/)(test-[^/]*\.sh$|test-[^/]*\.d/|fixtures/)')" in
  0) ok "scope excludes self-tests and fixtures" ;;
  *) no "scope leaked a self-test or fixture" ;;
esac
for caller in setup-providers.sh adapters/providers/lens-run.sh; do
  if grep -q 'launch_provider_cli ' "$HERE/$caller"; then ok "$caller calls the shared launcher"; else no "$caller no longer calls launch_provider_cli"; fi
done
raw="$(raw_hits "$HERE")"
v="$(printf '%s\n' "$raw" | grep -v '^$' | drop_allowed)"
if [ -z "$v" ]; then
  ok "no provider CLI started outside $LAUNCHER_REL"
else
  no "a provider CLI is started directly — call launch_provider_cli instead (or add a reasoned ALLOWLIST entry):"
  printf '%s\n' "$v" | sed 's/^/      /'
fi
while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  e_path="$(printf '%s\n' "$entry" | awk '{ print $1 }')"
  e_rule="$(printf '%s\n' "$entry" | awk '{ print $2 }')"
  if [ ! -f "$HERE/$e_path" ]; then no "allowlist entry '$e_path $e_rule' names a missing file"; continue; fi
  if printf '%s\n' "$raw" | awk -F: -v p="$e_path" -v r="$e_rule" '$1 == p && (r == "*" || $3 == r) { f = 1 } END { exit !f }'; then
    ok "allowlist entry still needed: $e_path ($e_rule)"
  else
    no "STALE allowlist entry '$e_path $e_rule' — nothing matches; delete it"
  fi
done <<EOF
$ALLOWLIST
EOF

echo "== mutation controls (scratch copies; the real tree is never edited) =="
SCR="$(mktemp -d "${TMPDIR:-/tmp}/provider-cli-single-launcher.XXXXXX")" || { echo "cannot mktemp"; exit 1; }
trap 'rm -rf "$SCR"' EXIT

# mutant <name> <victim-rel> <expected-rule|-> <line> — copy the victim into a fresh scratch root,
# append <line>, and check the scan reports <expected-rule> on it (or, with `-`, nothing)
mutant() {
  local name="$1" victim="$2" want="$3" line="$4" root="$SCR/$1" got
  mkdir -p "$root/$(dirname "$victim")" || { no "$name: scratch dir"; return 0; }
  cp "$HERE/$victim" "$root/$victim" || { no "$name: copy"; return 0; }
  printf '%s\n' "$line" >> "$root/$victim"
  if [ ! -s "$root/$victim" ] || cmp -s "$HERE/$victim" "$root/$victim"; then no "$name: mutant empty or identical — control void"; return 0; fi
  if ! bash -n "$root/$victim" 2>/dev/null; then no "$name: mutant does not parse — control void"; return 0; fi
  got="$(violations "$root" | awk -F: -v p="$victim" '$1 == p { print $3 }' | env LC_ALL=C sort -u | tr '\n' ' ')"
  if [ "$want" = "-" ]; then
    if [ -z "$got" ]; then ok "$name: not caught (as intended)"; else no "$name: wrongly caught ($got)"; fi
  else
    case " $got" in
      *" $want "*) ok "$name: caught by $want" ;;
      *) no "$name: NOT caught (wanted $want, got '${got% }')" ;;
    esac
  fi
  return 0
}

SP=setup-providers.sh
LR=adapters/providers/lens-run.sh
# the unmutated copies are clean (otherwise every "caught" below proves nothing)
for victim in "$SP" "$LR"; do
  mkdir -p "$SCR/clean/$(dirname "$victim")" && cp "$HERE/$victim" "$SCR/clean/$victim"
done
if [ -z "$(violations "$SCR/clean")" ]; then ok "clean: the unmutated caller copies scan clean"; else no "clean: an unmutated caller copy is already dirty"; fi

mutant smoke-direct "$SP" direct '"$cli" "${PROBE_ARGV[@]}" > "$work/smoke.out" 2> "$work/smoke.err" </dev/null'
mutant version-subst "$SP" direct 'ver="$("$cli" --version 2>/dev/null)"'
mutant braced-bare "$SP" direct 'true && ${cli} --help >/dev/null'
mutant if-cond "$SP" direct 'if "$cli" auth status >/dev/null 2>&1; then :; fi'
mutant assign-prefix "$SP" direct 'HOME="$x" "$cli" --help'
mutant exec-direct "$SP" direct '( exec "$cli" --help )'
mutant backtick "$SP" direct 'v=`"$cli" --version`'
mutant lens-direct "$LR" direct '"$PROVIDER_CLI_NAME" "${PROVIDER_ARGV[@]}" > "$RAW_OUT" 2> "$RAW_ERR"'
mutant lens-env-i "$LR" wrapped '( cd "$WT_PATH" && env -i PATH="$PATH" HOME="$SCRUB_HOME" TMPDIR="$SCRUB_HOME" "$PROVIDER_CLI_NAME" "${PROVIDER_ARGV[@]}" ) > "$RAW_OUT"'
mutant perl-setpgrp "$SP" wrapped '( exec perl -e '"'"'setpgrp; exec { $ARGV[0] } @ARGV'"'"' "$cli" "$@" ) </dev/null &'
mutant helper-copy "$SP" wrapped '( cd "$cwd" || exit 90; rb_exec "$cli" "$@" ) >"$out" 2>"$err" </dev/null &'
mutant named-cli-var "$SP" direct '"$provider_cli" --version'
mutant commented "$SP" - '# a comment naming "$cli" --help and env -i … "$PROVIDER_CLI_NAME" is prose, not code'
mutant launcher-call "$SP" - 'launch_provider_cli isolated 5 "$work/cwd" "$o" "$e" "$cli" "${PROBE_ARGV[@]}"'
mutant read-only-uses "$SP" - 'command -v "$cli" >/dev/null; [ -n "$cli" ]; printf "%s\n" "$cli"; case "$cli" in x) : ;; esac'
mutant quoted-paren "$SP" - 'label="$name ($cli)"; msg="run; ($cli) | x"; s='"'"'a ($cli) b'"'"''
mutant dq-subst-direct "$SP" direct 'msg="version: $("$cli" --version)"'
mutant unrelated-vars "$LR" - 'sleep "$LENS_CLI_TIMEOUT"; echo "$CLICK_MODE"; env LC_ALL=C sort </dev/null'

echo
echo "test-provider-cli-single-launcher: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
