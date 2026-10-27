#!/usr/bin/env bash
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
# test-base-branch-single-resolver.sh — regrowth guard: the base branch is resolved in ONE place.
#
# Why: the base used to be resolved in four unrelated ways — inline `symbolic-ref
# refs/remotes/origin/HEAD` copies with a silent `main` fallback in the /automate trail and lane
# modules and verify-run.sh, a bare `base=main` in supervisor-next-step.sh, `BASE_REF="main"` in
# wait-for-checks.sh and an origin/main > origin/development probe in reconcile-jobs.sh — so item
# PRs, lanes, waves and trail PRs could each pick a different base. resolve-base-branch.sh is now
# the one resolver (flag > brief > .supervisor/config.json .base_branch > origin/HEAD > gh >
# fail closed `base_branch_unresolved`). This guard fails when a new inline copy appears.
#
# Scope: every `*.sh` under loomwright/scripts/ EXCEPT self-tests (`test-*.sh`, `test-*.d/`) and
# `fixtures/`. The root scripts/check-*.sh gates are out of scope on purpose: they diff against
# origin/main for this plugin repo's own release checks and are not base-branch consumers of a
# user project. Matching runs on logical lines (backslash continuations joined), whole-line
# comments dropped and a trailing ` # comment` stripped, so prose that NAMES a form is never red.
#
# Rules (id — what it catches):
#   origin-head    `symbolic-ref … refs/remotes/origin/HEAD` — an inline origin/HEAD read
#   set-head       `remote set-head` — the resolver owns the one `set-head -a` attempt
#   main-assign    a variable whose name contains `base` or `branch` (any case) assigned the
#                  literal `main`: `base=main`, `base="main"`, `base_branch="main"`, `BASE_REF='main'`,
#                  `default_branch=main`
#   main-default   a `${var:-main}` / `${var-main}` / `${var:=main}` default expansion
#   main-echo      `|| echo main` / `|| printf … main` — a fallback printed by a command
#   origin-main    a literal `origin/main` ref in code (a hardcoded base probe)
#   main-arg       a literal `main` passed as the first positional argument to a script — `bash
#                  "$risk_bin" main "$head"`, `classify-risk.sh main HEAD` — the base handed to a
#                  base-taking script (classify-risk.sh, module-shape-facts.sh) by name; also
#                  `bash -- "$x" main` and a quoted variable in command position (`"$risk_bin" main`,
#                  after `$(`, `;`, `&&`, `|`, `(`, line start, or then/do/else/exec/command)
#
# ALLOWLIST (below) names each genuine exception as `<path> <rule|*> <reason>`. An entry that no
# longer matches anything is STALE and red, so the list only shrinks.
#
# Controls (a red control means the detector is broken, not that the tree is dirty): the real tree's
# scope is non-empty; each fallback form found at the base commit, plus the inline
# `symbolic-ref … || … main` line, is appended to a SCRATCH copy of a non-test script and must be
# caught — each mutant is gated on non-empty, differs-from-original and `bash -n`; a commented
# form is not caught; an allowlisted rule is not caught while another rule on the same file is.
# Exit 0 = clean, 1 = a violation or a broken control. Portability: bash 3.2 + BSD userland.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

ALLOWLIST='resolve-base-branch.sh * the ONE resolver — its origin/HEAD read and set-head -a step are the implementation this guard protects
send-telemetry-core.sh origin-head telemetry target ref, not a base: it compares the current branch with the remote default to key a feedback thread, is a fail-SAFE emitter (always exit 0, never fails closed) and must not run set-head or read a project config
eval-corpus/review-churn-canary/check.sh main-assign not a resolution: `-c init.defaultBranch=main` names the first branch of the throwaway fixture repo this corpus check creates
automate-lanes.d/create.sh set-head not a resolution: the base was resolved in the primary; a fresh --local clone inherits origin/HEAD pointing at the primary current branch, so it is re-pointed at the real origin HEAD'

# rule_re <id> — the ERE for one rule id
rule_re() {
  case "$1" in
    origin-head)  printf '%s' 'symbolic-ref[^|;&]*refs/remotes/origin/HEAD' ;;
    set-head)     printf '%s' 'remote[[:space:]]+set-head' ;;
    main-assign)  printf '%s' '(^|[^A-Za-z0-9_])[A-Za-z0-9_]*([Bb][Aa][Ss][Ee]|[Bb][Rr][Aa][Nn][Cc][Hh])[A-Za-z0-9_]*=["'"'"']?main["'"'"']?([^A-Za-z0-9_./-]|$)' ;;
    main-default) printf '%s' '\$\{[A-Za-z_][A-Za-z0-9_]*:?[-=]["'"'"']?main["'"'"']?\}' ;;
    main-echo)    printf '%s' '\|\|[[:space:]]*(echo|printf)([[:space:]][^|;&]*)?[[:space:]]["'"'"']?main["'"'"']?([^A-Za-z0-9_./-]|$)' ;;
    origin-main)  printf '%s' '(^|[^A-Za-z0-9_./-])origin/main([^A-Za-z0-9_./-]|$)' ;;
    main-arg)     printf '%s' '(bash[[:space:]]+(--[[:space:]]+)?("[^"]*"|[^[:space:]"]+)|[A-Za-z0-9_.-]+\.sh["'"'"']?|(^[0-9]+:|[;&|(]|\$\(|[:[:space:];&|(](then|do|else|exec|command)[[:space:]])[[:space:]]*"\$[{]?[A-Za-z_][A-Za-z0-9_]*[}]?")[[:space:]]+["'"'"']?main["'"'"']?([[:space:]]|$|[;&|)])' ;;
  esac
}
RULES='origin-head set-head main-assign main-default main-echo origin-main main-arg'

# logical_lines <file> — `startline:text`, continuations joined, comments dropped/stripped; shared
# with test-no-pipefail-grep-q.sh through the sourced logical-lines-lib.sh
. "$HERE/logical-lines-lib.sh"

# scope <root> — every non-test *.sh under <root>, relative, sorted
scope() {
  ( cd "$1" && find . -type f -name '*.sh' 2>/dev/null ) | sed 's|^\./||' \
    | grep -vE '(^|/)test-[^/]*\.sh$|(^|/)test-[^/]*\.d/|(^|/)fixtures/' | env LC_ALL=C sort
  return 0
}

# raw_hits <root> — `rel:line:rule:text` for every rule hit, allowlist NOT applied
raw_hits() {
  local root="$1" rel rule ll
  scope "$root" | while IFS= read -r rel; do
    ll="$(logical_lines "$root/$rel")"
    [ -n "$ll" ] || continue
    for rule in $RULES; do
      grep -E -- "$(rule_re "$rule")" <<<"$ll" | sed "s|^\([0-9]*\):|$rel:\1:$rule:|"
    done
  done
  return 0
}

# drop_allowed — filter raw hits on stdin down to the violations (allowlist applied). The list goes
# in through the environment: BSD awk refuses a newline in a `-v` value.
drop_allowed() {
  BBSR_ALLOW="$ALLOWLIST" awk -F: 'BEGIN { n = split(ENVIRON["BBSR_ALLOW"], L, "\n"); for (i = 1; i <= n; i++) { split(L[i], w, " "); ok[w[1] SUBSEP w[2]] = 1 } }
    !(($1 SUBSEP $3) in ok) && !(($1 SUBSEP "*") in ok)'
}

# violations <root> — raw hits minus the allowlisted ones
violations() { raw_hits "$1" | drop_allowed; return 0; }

echo "== real tree: loomwright/scripts =="
n_scope="$(scope "$HERE" | wc -l | tr -d ' ')"
if [ "$n_scope" -gt 50 ]; then ok "scope holds $n_scope non-test scripts"; else no "scope holds only $n_scope scripts — the scope walk is broken"; fi
case "$(scope "$HERE" | grep -cE '(^|/)(test-|fixtures/)')" in
  0) ok "scope excludes self-tests and fixtures" ;;
  *) no "scope leaked a self-test or fixture" ;;
esac
raw="$(raw_hits "$HERE")"
v="$(printf '%s\n' "$raw" | grep -v '^$' | drop_allowed)"
if [ -z "$v" ]; then
  ok "no inline base-branch resolution outside resolve-base-branch.sh"
else
  no "inline base-branch resolution — call resolve-base-branch.sh instead (or add a reasoned ALLOWLIST entry):"
  printf '%s\n' "$v" | sed 's/^/      /'
fi
while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  e_path="$(printf '%s\n' "$entry" | awk '{ print $1 }')"   # never `set -- $entry`: the `*` rule would glob
  e_rule="$(printf '%s\n' "$entry" | awk '{ print $2 }')"
  if [ ! -f "$HERE/$e_path" ]; then no "allowlist entry '$e_path $e_rule' names a missing file"; continue; fi
  if printf '%s\n' "$raw" | awk -F: -v p="$e_path" -v r="$e_rule" '$1 == p && (r == "*" || $3 == r) { f = 1 } END { exit !f }'; then
    ok "allowlist entry still needed: $e_path ($e_rule)"
  else
    no "STALE allowlist entry '$e_path $e_rule' — nothing matches; delete it"
  fi
  case "$(printf '%s\n' "$entry" | awk '{ $1 = ""; $2 = ""; sub(/^[[:space:]]+/, ""); print length($0) }')" in
    0|1|2|3|4|5|6|7|8|9) no "allowlist entry '$e_path $e_rule' carries no reason" ;;
  esac
done <<EOF
$ALLOWLIST
EOF

echo "== mutation controls (scratch copies; the real tree is never edited) =="
SCR="$(mktemp -d "${TMPDIR:-/tmp}/bb-single-resolver.XXXXXX")" || { echo "cannot mktemp"; exit 1; }
trap 'rm -rf "$SCR"' EXIT
VICTIM="automate-trail.d/trail-pr.sh"   # a non-test consumer that carried the inline copy at base
ORIG="$HERE/$VICTIM"
if [ ! -s "$ORIG" ]; then no "mutation victim $VICTIM missing"; fi

# mutant <name> <expected-rule|-> <line> — copy the victim (and the allowlisted create.sh) into a
# fresh scratch root, append <line>, and check the scan reports <expected-rule> on the victim (or,
# with `-`, reports nothing)
mutant() {
  local name="$1" want="$2" line="$3" root="$SCR/$1" got
  mkdir -p "$root/automate-trail.d" "$root/automate-lanes.d" || { no "$name: scratch dir"; return 0; }
  cp "$ORIG" "$root/$VICTIM" || { no "$name: copy"; return 0; }
  printf '%s\n' "$line" >> "$root/$VICTIM"
  if [ ! -s "$root/$VICTIM" ] || cmp -s "$ORIG" "$root/$VICTIM"; then no "$name: mutant empty or identical — control void"; return 0; fi
  if ! bash -n "$root/$VICTIM" 2>/dev/null; then no "$name: mutant does not parse — control void"; return 0; fi
  got="$(violations "$root" | awk -F: -v p="$VICTIM" '$1 == p { print $3 }' | env LC_ALL=C sort -u | tr '\n' ' ')"
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

# the unmutated copy is clean (otherwise every "caught" below proves nothing)
mkdir -p "$SCR/clean/automate-trail.d" && cp "$ORIG" "$SCR/clean/$VICTIM"
if [ -z "$(violations "$SCR/clean")" ]; then ok "clean: the unmutated victim copy scans clean"; else no "clean: the unmutated victim copy is already dirty"; fi

mutant inline-origin-head-or-main origin-head \
  'base_branch="$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || echo main)"'
mutant inline-or-main main-echo \
  'base_branch="$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || echo main)"'
mutant regrown-trail-pr-fallback main-assign '[ -n "$base_branch" ] || base_branch="main"'
mutant bare-base-eq-main main-assign '[ -n "$base" ] || base=main'
mutant quoted-base-eq-main main-assign '[ -n "$base" ] || base="main"'
mutant base-ref-eq-main main-assign '[ -n "$BASE_REF" ] || BASE_REF="main"'
mutant default-expansion main-default 'printf '"'"'%s'"'"' "${b:-main}"'
mutant assign-default-expansion main-default ': "${base_ref:=main}"'
mutant default-branch-eq-main main-assign 'default_branch=main'
mutant origin-main-probe origin-main 'for ref in origin/main origin/development; do :; done'
mutant set-head-copy set-head 'git remote set-head origin -a >/dev/null 2>&1'
mutant positional-main-var-script main-arg 'risk_json="$(bash "$risk_bin" main "$live_head" --root "$root" 2>/dev/null)"'
mutant positional-main-named-script main-arg 'bash "$HERE/module-shape-facts.sh" main HEAD >/dev/null'
mutant positional-main-bare-script main-arg 'classify-risk.sh "main" HEAD >/dev/null'
mutant positional-main-var-cmd main-arg 'risk_json="$("$risk_bin" main "$live_head")"'
mutant positional-main-var-cmd-chain main-arg 'true && "${risk_bin}" main HEAD >/dev/null'
mutant positional-main-var-cmd-line main-arg '"$risk_bin" main HEAD >/dev/null'
mutant positional-main-bash-dashdash main-arg 'bash -- "$risk_bin" main "$live_head" >/dev/null'
mutant positional-var-mainline - '"$x" mainline >/dev/null; "$x" "$main_ref" >/dev/null'
mutant positional-var-arg-not-cmd - 'printf "%s %s\\n" "$x" main >/dev/null'
mutant positional-resolved-base - 'risk_json="$(bash "$risk_bin" "origin/$base_b" "$live_head" --root "$root" 2>/dev/null)"'
mutant commented-form - '# a comment naming base="main" and refs/remotes/origin/HEAD is prose, not code'
mutant unrelated-main - 'kind="main"; AGENT_ID_KEY="main"; x="origin/maintenance"'

# allowlist scoping: create.sh may run set-head, but an origin-head read there is still caught
CR="$SCR/allow/automate-lanes.d/create.sh"
mkdir -p "$SCR/allow/automate-lanes.d"
printf '%s\n' 'git -C "$C" remote set-head origin -a >/dev/null 2>&1' > "$CR"
if [ -z "$(violations "$SCR/allow")" ]; then ok "allowlist: create.sh set-head is allowed"; else no "allowlist: create.sh set-head wrongly caught"; fi
printf '%s\n' 'b="$(git symbolic-ref --short refs/remotes/origin/HEAD)"' >> "$CR"
case "$(violations "$SCR/allow" | awk -F: '{ print $3 }' | tr '\n' ' ')" in
  "origin-head ") ok "allowlist: create.sh origin-head read is still caught (entries are per rule)" ;;
  *) no "allowlist: create.sh origin-head read not caught — an entry leaked beyond its rule" ;;
esac

echo
echo "test-base-branch-single-resolver: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
