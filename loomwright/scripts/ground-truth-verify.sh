# ground-truth-verify.sh — the Selvedge driver behind run-ground-truth.sh's `verify:` kind (alias
# `qa-executor:`). SOURCED (never executed directly) by run-ground-truth.sh, exactly as it sources
# exec-acceptance-lib.sh, and called ONCE per ground-truth run with every `verify:` line of that run,
# so all of them are checked in ONE Selvedge run folder.
#
# Selvedge is reached ONLY through its public CLI — no file of the plugin is sourced or imported:
#   1. `criteria from-text`   stdin, one `- <criterion>` list item per verify line -> criteria.json
#                             (written to a private temp dir, never into the project)
#   2. `plan <criteria.json> --base <ref>`
#                             the one-go form: init, the planner, validate and freeze, all reading
#                             `selvedge.json` from `<ref>` (the base branch), never from the PR head.
#                             It prints the run folder (`.selvedge/runs/<run-id>/`, last stdout line).
#   3. `run --non-interactive <run-dir>`
#                             only on the folder step 2 printed, and only when step 2 exited 0. `run`
#                             takes no `--base` (it reads `selvedge.json` from the run folder's
#                             checkout), so the base-branch read holds at plan time only; nothing here
#                             works around that or passes `run` a flag it does not list.
#                             `--non-interactive`: never wait for a sign-in (BLOCKED needs_auth).
#   4. `<run-dir>/verdict.json`
#                             read as DATA with jq: `schema_version` must be 1 (the same version
#                             propose-from-verify.sh supports) and `criteria` an object keyed by the
#                             ids criteria.json assigned. `run`'s own exit code is NEVER read as a
#                             verdict (it exits 1 on any FAIL) — the file decides.
# Hook approval is never touched: an unapproved env hook makes Selvedge report every criterion
# BLOCKED env_hooks_unapproved, which maps through unchanged. Only a human approves a hook.
#
# CLI discovery: `SELVEDGE_BIN` when it is set and non-empty (it must then be an executable file —
# a set-but-broken SELVEDGE_BIN never falls back to PATH, where a stale copy may sit), else
# `command -v selvedge`. Neither -> every line `unverified`, reason `verify_plugin_absent`.
# Base ref: `GROUND_TRUTH_VERIFY_BASE` when set and non-empty (passed as given), else
# `origin/<branch>` where <branch> is what the ONE base resolver, the sibling
# `resolve-base-branch.sh --repo <project-root>`, prints (no --flag/--brief is passed, so its
# config -> origin-head -> gh steps apply, with its one `git remote set-head origin -a` side
# effect — see its header). There is no hardcoded fallback branch: when the resolver fails CLOSED
# (`base_branch_unresolved` / `base_branch_invalid:config`), every line is `verify_refused` and
# Selvedge is never called. A ref Selvedge cannot read is Selvedge's refusal (`base_config_unreadable`), which
# also maps to `verify_refused` — never a silent fall-back to the working-tree `selvedge.json`.
#
# Mapping (the Selvedge verdict set PASS | FAIL | BLOCKED | NOT_VERIFIABLE, verdict.json
# schema_version 1 — the same set and version propose-from-verify.sh reads):
#   PASS            -> status `pass`
#   FAIL            -> status `fail`, reason `FAIL`
#   BLOCKED         -> status `unverified`, reason `BLOCKED <selvedge reason>`
#   NOT_VERIFIABLE  -> status `unverified`, reason `NOT_VERIFIABLE <selvedge reason>`
#   anything else, or a criterion verdict.json does not hold -> `unverified`,
#                      reason `verify_verdict_unreadable` (an unread criterion is NEVER a pass)
# Loomwright-side reasons (every line of the run gets the same one):
#   verify_plugin_absent       no CLI found (see discovery)
#   verify_refused             `criteria from-text` or `plan` exited non-zero, printed no usable
#                              output, or printed no existing run folder (`run` is then never
#                              called); also a `verify:` line with no criterion text, and every
#                              line when no base ref resolves (see Base ref)
#   verify_verdict_unreadable  the run folder has no readable verdict.json, or its schema_version
#                              is not 1, or it is not an object with a `criteria` object
# Lines map to criteria.json ids IN ORDER when criteria.json holds exactly one criterion per sent
# line; otherwise (Selvedge folds identical criteria into one id) each line is matched to the
# criterion whose text equals the line's text after Selvedge's own normalization, and a line with
# no match is `verify_verdict_unreadable`.
#
# Functions:
#   gt_verify_target <line>            -> the criterion text of a `verify:`/`qa-executor:` line
#   gt_verify_resolve_bin              -> prints the CLI path; returns 1 when none is usable
#   gt_verify_base_ref <project-root>  -> prints the base ref `plan --base` gets; returns 1 (prints
#                                         nothing) when the base resolver fails
#   gt_verify_check <project-root> <criterion-text>...
#                                      -> runs the chain once; sets, per argument position i
#                                         (0-based), GT_VERIFY_STATUS[i] (pass|fail|unverified),
#                                         GT_VERIFY_REASON[i] and GT_VERIFY_VERDICT[i]
#                                         (PASS|FAIL|BLOCKED|NOT_VERIFIABLE, or `-` for a
#                                         Loomwright-side reason), plus GT_VERIFY_RUN_DIR (the one
#                                         run folder, or empty). Always returns 0.
#
# Every child runs with cwd = the project root and stdin </dev/null. The run folder Selvedge
# creates lives under `<project-root>/.selvedge/` (Selvedge's own layout; `selvedge env init` adds
# it to .gitignore). Selvedge's own budgets bound the planner and the browser run; this driver
# adds no timeout.
#
# Portability: bash 3.2 + BSD userland safe; needs jq (run-ground-truth.sh checks jq before any
# check runs). Sets no shell options (it inherits the caller's `set -uo pipefail`).

GT_VERIFY_STATUS=()
GT_VERIFY_REASON=()
GT_VERIFY_VERDICT=()
GT_VERIFY_RUN_DIR=""

# gt_verify_target <line> — strip the `verify:` / `qa-executor:` prefix, then trim.
gt_verify_target() {
  local l="$1"
  case "$l" in
    verify:*)      l="${l#verify:}" ;;
    qa-executor:*) l="${l#qa-executor:}" ;;
  esac
  l="${l#"${l%%[![:space:]]*}"}"
  l="${l%"${l##*[![:space:]]}"}"
  printf '%s' "$l"
}

# gt_verify_resolve_bin — SELVEDGE_BIN (set and non-empty) wins and must be an executable file;
# otherwise the first `selvedge` on PATH. Prints nothing and returns 1 when neither is usable.
gt_verify_resolve_bin() {
  local p=""
  if [ -n "${SELVEDGE_BIN:-}" ]; then
    p="$SELVEDGE_BIN"
    [ -f "$p" ] && [ -x "$p" ] || return 1
  else
    p="$(command -v selvedge 2>/dev/null || true)"
    [ -n "$p" ] || return 1
  fi
  printf '%s\n' "$p"
}

# gt_verify_base_ref <project-root> — GROUND_TRUTH_VERIFY_BASE (set and non-empty) as given, else
# `origin/<branch>` from the sibling resolve-base-branch.sh. Prints nothing and returns 1 when the
# resolver fails (its status token goes to stderr); there is no hardcoded fallback branch.
gt_verify_base_ref() {
  local root="$1" b="" rc=0 err=""
  if [ -n "${GROUND_TRUTH_VERIFY_BASE:-}" ]; then
    printf '%s\n' "$GROUND_TRUTH_VERIFY_BASE"
    return 0
  fi
  err="$(mktemp "${TMPDIR:-/tmp}/gt-verify-base.XXXXXX" 2>/dev/null)" || err="/dev/null"
  b="$(bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/resolve-base-branch.sh" --repo "$root" \
        </dev/null 2>"$err")" || rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$b" ]; then
    _gt_verify_diag "resolve-base-branch.sh exited $rc ($(head -n 1 "$err" 2>/dev/null)), no base ref for plan --base, plan not called (verify_refused)" "$err"
    [ "$err" = "/dev/null" ] || rm -f "$err"
    return 1
  fi
  [ "$err" = "/dev/null" ] || rm -f "$err"
  printf 'origin/%s\n' "$b"
}

# _gt_verify_set <i> <status> <reason> <verdict>
_gt_verify_set() {
  GT_VERIFY_STATUS[$1]="$2"
  GT_VERIFY_REASON[$1]="$3"
  GT_VERIFY_VERDICT[$1]="$4"
}

# _gt_verify_all <count> <status> <reason> — the same Loomwright-side result for every line not yet set.
_gt_verify_all() {
  local n="$1" i=0
  while [ "$i" -lt "$n" ]; do
    [ -n "${GT_VERIFY_STATUS[$i]:-}" ] || _gt_verify_set "$i" "$2" "$3" "-"
    i=$((i+1))
  done
}

# _gt_verify_diag <what> <stderr-file> — one stderr line naming the step and Selvedge's last word.
_gt_verify_diag() {
  local last=""
  [ -f "$2" ] && last="$(grep -v '^[[:space:]]*$' "$2" 2>/dev/null | tail -n 1)"
  echo "run-ground-truth: verify: $1${last:+ — $last}" >&2
}

# _gt_verify_map <verdict> <reason> <i> — one Selvedge verdict to a per-check result.
_gt_verify_map() {
  local v="$1" r="$2" i="$3"
  case "$r" in
    *[!a-z0-9_]*) v="-" ;;   # a reason is a Selvedge reason token; anything else is not read
  esac
  case "$v" in
    PASS)                    _gt_verify_set "$i" "pass" "" "PASS" ;;
    FAIL)                    _gt_verify_set "$i" "fail" "FAIL" "FAIL" ;;
    BLOCKED|NOT_VERIFIABLE)  _gt_verify_set "$i" "unverified" "$v${r:+ $r}" "$v" ;;
    *)                       _gt_verify_set "$i" "unverified" "verify_verdict_unreadable" "-" ;;
  esac
}

# gt_verify_check <project-root> <criterion-text>... — see the file header.
gt_verify_check() {
  local root="$1"; shift
  local n="$#" bin base work rc run_dir i j sent=0
  local sent_pos=() texts=() ids=() id_texts=() pairs="" line v r t k
  GT_VERIFY_STATUS=(); GT_VERIFY_REASON=(); GT_VERIFY_VERDICT=(); GT_VERIFY_RUN_DIR=""
  [ "$n" -gt 0 ] || return 0

  if ! bin="$(gt_verify_resolve_bin)"; then
    echo "run-ground-truth: verify: no Selvedge CLI (SELVEDGE_BIN unset/unusable, no selvedge on PATH) — verify_plugin_absent" >&2
    _gt_verify_all "$n" "unverified" "verify_plugin_absent"
    return 0
  fi
  if ! base="$(gt_verify_base_ref "$root")"; then
    _gt_verify_all "$n" "unverified" "verify_refused"
    return 0
  fi

  # The criteria list: one `- <text>` item per non-empty line; an empty line is refused on its own.
  i=0
  for t in "$@"; do
    if [ -z "$t" ]; then
      _gt_verify_set "$i" "unverified" "verify_refused" "-"
    else
      sent_pos+=("$i"); texts+=("$t"); sent=$((sent+1))
    fi
    i=$((i+1))
  done
  [ "$sent" -gt 0 ] || return 0

  work="$(mktemp -d "${TMPDIR:-/tmp}/gt-verify.XXXXXX" 2>/dev/null)" || work=""
  if [ -z "$work" ] || [ ! -d "$work" ]; then
    echo "run-ground-truth: verify: cannot create a temp dir for criteria.json — verify_refused" >&2
    _gt_verify_all "$n" "unverified" "verify_refused"
    return 0
  fi

  for t in "${texts[@]}"; do printf -- '- %s\n' "$t"; done > "$work/input.md"
  ( cd "$root" && "$bin" criteria from-text --source loomwright-ground-truth \
      < "$work/input.md" > "$work/criteria.json" 2> "$work/criteria.err" )
  rc=$?
  if [ "$rc" -ne 0 ]; then
    _gt_verify_diag "selvedge criteria from-text exited $rc (verify_refused)" "$work/criteria.err"
    _gt_verify_all "$n" "unverified" "verify_refused"
    rm -rf "$work"; return 0
  fi
  # id<TAB>text per criterion; a criteria.json that is not that shape is a refusal.
  if ! jq -e '(.criteria | type) == "array" and (.criteria | length) > 0
              and all(.criteria[]; (.id | type) == "string" and (.text | type) == "string")' \
        "$work/criteria.json" >/dev/null 2>&1; then
    echo "run-ground-truth: verify: selvedge criteria from-text printed no usable criteria.json (verify_refused)" >&2
    _gt_verify_all "$n" "unverified" "verify_refused"
    rm -rf "$work"; return 0
  fi
  while IFS=$'\t' read -r k t; do
    ids+=("$k"); id_texts+=("$t")
  done < <(jq -r '.criteria[] | [.id, .text] | @tsv' "$work/criteria.json" 2>/dev/null)

  ( cd "$root" && "$bin" plan "$work/criteria.json" --base "$base" \
      </dev/null > "$work/plan.out" 2> "$work/plan.err" )
  rc=$?
  run_dir="$(grep -v '^[[:space:]]*$' "$work/plan.out" 2>/dev/null | tail -n 1)"
  if [ "$rc" -ne 0 ]; then
    _gt_verify_diag "selvedge plan --base $base exited $rc, run not called (verify_refused)" "$work/plan.err"
    _gt_verify_all "$n" "unverified" "verify_refused"
    rm -rf "$work"; return 0
  fi
  case "$run_dir" in
    "") : ;;
    /*) : ;;
    *) run_dir="$root/$run_dir" ;;
  esac
  if [ -z "$run_dir" ] || [ ! -d "$run_dir" ]; then
    echo "run-ground-truth: verify: selvedge plan printed no run folder (verify_refused)" >&2
    _gt_verify_all "$n" "unverified" "verify_refused"
    rm -rf "$work"; return 0
  fi
  GT_VERIFY_RUN_DIR="$run_dir"

  # The run's exit code is not a verdict (1 on any FAIL, 2 on any BLOCKED, 3 on NOT_VERIFIABLE).
  ( cd "$root" && SELVEDGE_ENTRY=loomwright "$bin" run --non-interactive "$run_dir" \
      </dev/null > "$work/run.out" 2> "$work/run.err" )
  rc=$?
  [ "$rc" -eq 0 ] || _gt_verify_diag "selvedge run exited $rc (verdicts are read from verdict.json)" "$work/run.err"

  if ! jq -e '.schema_version == 1 and (.criteria | type) == "object"' \
        "$run_dir/verdict.json" >/dev/null 2>&1; then
    echo "run-ground-truth: verify: no readable schema_version 1 verdict.json in $run_dir (verify_verdict_unreadable)" >&2
    _gt_verify_all "$n" "unverified" "verify_verdict_unreadable"
    rm -rf "$work"; return 0
  fi
  # verdict<TAB>reason for every criteria.json id, in criteria.json order (`-` when not held).
  pairs="$(jq -r --argjson ids "$(jq -c '[.criteria[].id]' "$work/criteria.json")" '
      . as $v | $ids[] | ($v.criteria[.] // null)
      | if type == "object"
        then [(.verdict // "-" | tostring), (.reason // "" | tostring)]
        else ["-", ""] end
      | @tsv' "$run_dir/verdict.json" 2>/dev/null)"
  local verdicts=() reasons=()
  while IFS=$'\t' read -r v r; do
    verdicts+=("$v"); reasons+=("$r")
  done <<EOF
$pairs
EOF

  j=0
  while [ "$j" -lt "$sent" ]; do
    i="${sent_pos[$j]}"
    k=-1
    if [ "${#ids[@]}" -eq "$sent" ]; then
      k="$j"                                   # one criterion per sent line: map in order
    else
      # Selvedge folded criteria: match on the line's text as Selvedge normalizes it.
      t="$(jq -rn --arg s "${texts[$j]}" '$s | gsub("\\s+"; " ") | sub("^ "; "") | sub(" $"; "")
            | sub("^(?:[-*+]|[0-9]{1,9}[.)]) +"; "") | sub("^\\[[ xX]\\](?: +|$)"; "")
            | sub("^ +"; "") | sub(" +$"; "")' 2>/dev/null)"
      line=0
      while [ "$line" -lt "${#ids[@]}" ]; do
        if [ "${id_texts[$line]}" = "$t" ]; then k="$line"; break; fi
        line=$((line+1))
      done
    fi
    if [ "$k" -ge 0 ] && [ "$k" -lt "${#verdicts[@]}" ]; then
      _gt_verify_map "${verdicts[$k]}" "${reasons[$k]}" "$i"
    else
      _gt_verify_set "$i" "unverified" "verify_verdict_unreadable" "-"
    fi
    j=$((j+1))
  done
  _gt_verify_all "$n" "unverified" "verify_verdict_unreadable"
  rm -rf "$work"
  return 0
}
