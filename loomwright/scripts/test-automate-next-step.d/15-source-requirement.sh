# test-automate-next-step.d/15-source-requirement.sh — part of test-automate-next-step.sh (TNS_PARTS / TNS_GROUPS / its
# `pg_want 15-source-requirement` line): the item's path reaches Launch Pad through the explicit `--source-requirement`
# flag, so a story kept outside `.supervisor/requirements/` gets the brief's `Source requirement` line and the normal
# close-out stamp. Sourced by the runner (its setup, helpers and counters); run directly — e.g. by
# run-pin-mutations.sh — it re-enters the runner for this part.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  exec "${BASH:-bash}" "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test-automate-next-step.sh" --part 15-source-requirement
fi
#
# LEGS (each names the acceptance criterion it pins; the brief's Pin mutations turn each red):
#   S1 (AC1/AC8)  the fresh `plan` step's Launch Pad spawn: invocation `/loomwright:launch-pad goal: <item>
#                 --source-requirement <item>` for a folder story AND a `.supervisor/requirements/` item, the prompt
#                 begins with it; a non-interactive run ends `--source-requirement <item> --non-interactive`
#   S2 (AC2/4/7/9) the Launch Pad authority states the flag's rule (prose): the setter, the exact-as-passed pointer,
#                 the literal-goal sentence kept, the unresolved WARNING; the command doc and the flag tables name it
#   S3 (AC3)      `/autonomous` PLAN step 1 passes `<requirement_path> --source-requirement <requirement_path>`
echo "-- SR. explicit --source-requirement from the driver and /autonomous to Launch Pad"

SR_ROOT="$(cd "$HERE/.." && pwd)"
sr_item_leg() { # <driver> <item> <ni|int> — the plan step's Launch Pad spawn for <item>; sets LEG_MSG on failure
  local drv="$1" item="$2" mode="$3" want sp
  new_scratch "$FIX/reconcile-closeout-merged" || { LEG_MSG="scratch"; return 1; }
  f_claude 1
  sed "s|$F_ITEM|$item|" "$CASE_RF" > "$CASE_RF.t" && mv "$CASE_RF.t" "$CASE_RF"
  want="/loomwright:launch-pad goal: $item --source-requirement $item"
  if [ "$mode" = ni ]; then
    want="$want --non-interactive"
    f_call "$drv" --start pick --non-interactive --session-id coord-1; sp="$NC_OUT"
  else
    f_call "$drv" --start pick --session-id coord-1; sp="$NC_OUT"
  fi
  [ "$NC_RC" = 0 ] && f_spawn_ok "$sp" plan launch-pad \
    && printf '%s' "$sp" | jq -e --arg w "$want" '.what == "launch pad phase" and .invocation == $w and (.prompt | startswith($w + " — "))' >/dev/null 2>&1 \
    || { LEG_MSG="$item ($mode) ⇒ exit $NC_RC '${sp:0:300}' ${NC_ERR:0:200}"; return 1; }
  return 0
}
leg_sr_spawn() { # <driver> — S1
  local drv="$1" m
  for m in ni int; do
    sr_item_leg "$drv" "stories/02-x.md" "$m" || return 1
    sr_item_leg "$drv" "$F_ITEM" "$m" || return 1
  done
  return 0
}
LEG_MSG=""
if leg_sr_spawn "$DRIVER"; then ok "S1 (AC1/AC8): the fresh plan step's Launch Pad spawn is '/loomwright:launch-pad goal: <item> --source-requirement <item>' (then --non-interactive on a non-interactive run) for a folder story and a .supervisor/requirements/ item alike, the prompt beginning with it"
else no "S1: $LEG_MSG"; fi
sr_mutant() { # <name> <mutant path or "" > — a driver edit that must turn S1 red
  local m="$2"
  if [ -n "$m" ]; then
    LEG_MSG=""
    if leg_sr_spawn "$m"; then no "S1-M ($1): the mutant still passes S1 — the pin is vacuous"
    else ok "S1-M ($1): the mutant turns S1 red (${LEG_MSG:0:120})"; fi
  else no "S1-M ($1): mutant not built: $(cat "$WORK/sr.err")"; fi
}
# the flag dropped from ns_plan's inv= line
sr_mutant dropped "$(build_mutant sr-dropped 'inv="/loomwright:launch-pad goal: $ITEM --source-requirement $ITEM"' 'inv="/loomwright:launch-pad goal: $ITEM"' 2>"$WORK/sr.err")"
# the flag appended after --non-interactive instead of before it
sr_mutant after-noninteractive "$(build_mutant2 sr-after 'goal: $ITEM --source-requirement $ITEM"' 'goal: $ITEM"' \
  'p="$inv — If the requirement file at' 'inv="$inv --source-requirement $ITEM"; p="$inv — If the requirement file at' 2>"$WORK/sr.err")"

# ---- S2 / S3: the prose pins ------------------------------------------------------------------------------
sr_has() { grep -qF -- "$2" "$SR_ROOT/$1"; }
LP_AGENT=agents/launch-pad.md
sr_step0() { awk '/^0\. \*\*Resolve requirement-file input/ { p = 1 } p { print } /^1\. / && p { exit }' "$SR_ROOT/$LP_AGENT"; }
s0="$(sr_step0)"
s2_ok=1
case "$s0" in *'`--source-requirement <path>`'*'`source_requirement`'*) ;; *) s2_ok=0 ;; esac                        # AC2/AC4 the setter
case "$s0" in *'is treated as a literal goal string'*'`.supervisor/requirements/`'*) ;; *) s2_ok=0 ;; esac          # AC7 kept
case "$s0" in *'only `--source-requirement` extends `source_requirement` outside'*) ;; *) s2_ok=0 ;; esac          # AC7 only the flag
case "$s0" in *'exactly as passed'*) ;; *) s2_ok=0 ;; esac                                                          # AC2
case "$s0" in *'WARNING'*'source_requirement_unresolved: <path>'*) ;; *) s2_ok=0 ;; esac                           # AC9
case "$s0" in *'no `..` segment'*'ends in `.md`'*'`test -f`'*) ;; *) s2_ok=0 ;; esac                                # AC9 the checks
sr_has "$LP_AGENT" '| `--source-requirement` |' || s2_ok=0
sr_has commands/launch-pad.md '`--source-requirement`' || s2_ok=0
sr_has "$LP_AGENT" 'Source requirement:** {repo-root-relative path}' || s2_ok=0
if [ "$s2_ok" = 1 ] && [ -n "$s0" ]; then ok "S2 (AC2/AC4/AC7/AC9): Launch Pad's Phase 2 step 0 names --source-requirement as the second setter of source_requirement (path exactly as passed, relative / no .. / .md / test -f), keeps its literal-goal sentence and the .supervisor/requirements/ scope, and carries the source_requirement_unresolved WARNING; both flag tables name the flag"
else no "S2: Launch Pad step 0 / flag tables miss the --source-requirement rule (step 0 found: $([ -n "$s0" ] && echo yes || echo no))"; fi

s3_ok=1
al_plan1="$(grep -F -- 'Reference the loaded `commands/launch-pad.md` workflow' "$SR_ROOT/skills/autonomous-loop/SKILL.md" | head -n 1)"
case "$al_plan1" in *'`<requirement_path> --source-requirement <requirement_path>`'*) ;; *) s3_ok=0 ;; esac
al_fwd="$(grep -F -- '**Launch Pad forward' "$SR_ROOT/skills/autonomous-loop/SKILL.md" | head -n 1)"
case "$al_fwd" in *'`--source-requirement <requirement_path>` always'*) ;; *) s3_ok=0 ;; esac
if [ "$s3_ok" = 1 ]; then ok "S3 (AC3): /autonomous PLAN step 1 hands Launch Pad '<requirement_path> --source-requirement <requirement_path>'"
else no "S3: skills/autonomous-loop/SKILL.md PLAN step 1 does not pass --source-requirement <requirement_path>"; fi
