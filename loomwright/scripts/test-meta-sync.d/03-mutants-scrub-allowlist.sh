# ---------------------------------------------------------------------------------------------
# Mutation controls — sed-patched copies; the sibling setup-memory.sh is copied beside each.
# build_mutant <dir> <sed-expr> <must-appear> — 0 = mutant built and differs; 1 = inconclusive.
build_mutant() {
  mkdir -p "$1"; cp "$HERE/setup-memory.sh" "$1/"
  [ -d "$HERE/setup-memory.d" ] && cp -R "$HERE/setup-memory.d" "$1/"
  sed -e "$2" "$SUTB" > "$1/meta-sync.sh" || return 1
  cmp -s "$SUTB" "$1/meta-sync.sh" && return 1
  grep -qF "$3" "$1/meta-sync.sh" || return 1
  bash -n "$1/meta-sync.sh" || return 1
  return 0
}

echo "== 20. mutation control (i): drop the base comparison -> stale-copy assertion must turn red =="
MUT_I="$TROOT/mutant-i"
if build_mutant "$MUT_I" 's/else if (l == b) {/else if (0) {/; s/else if (r == b) {/else if (l != r) {/' 'else if (l != r) {'; then
  SCRIPT="$MUT_I/meta-sync.sh"
  if scenario_stale; then
    no "mutation control (i) REFUTED: the base-less mutant kept A's X — the stale-copy assertion is not load-bearing"
  else
    ok "mutation control (i): the base-less mutant turns the stale-copy assertion red — $STALE_DETAIL"
  fi
  SCRIPT="$SUT"
else
  no "mutation control (i): could not build the mutant (sed did not apply or bash -n failed) — control inconclusive"
fi

echo "== 21. mutation control (ii): directory add -> ignored-file assertion must turn red =="
MUT_II="$TROOT/mutant-ii"
if build_mutant "$MUT_II" 's/^is_managed() {$/is_managed() { return 0/' 'is_managed() { return 0'; then
  SCRIPT="$MUT_II/meta-sync.sh"
  roundtrip_world
  ms A push
  if [ "$RC" -eq 0 ] && assert_ignored_clean; then
    no "mutation control (ii) REFUTED: the directory-add mutant published nothing extra — the ignored-file assertion is not load-bearing"
  elif [ "$RC" -ne 0 ]; then
    no "mutation control (ii): the mutant push itself failed (rc=$RC: $OUT) — control inconclusive"
  else
    ok "mutation control (ii): the directory-add mutant turns the ignored-file assertion red — leaked: $(br_names | grep -vE '\.md$|(^|/)results\.jsonl$' | tr '\n' ' ')$(br_names | grep -E '/\.supervisor/|jobs/pending/' | tr '\n' ' ')"
  fi
  SCRIPT="$SUT"
else
  no "mutation control (ii): could not build the mutant (sed did not apply or bash -n failed) — control inconclusive"
fi

echo "== 36. mutation control (iii): exhausted retries exit 0 -> push-retry-exhaustion assertion must turn red =="
# The mutant replaces only the final `die "push_failed ..."` line; the loop stays bounded.
MUT_III="$TROOT/mutant-iii"
if build_mutant "$MUT_III" '/die "push_failed/s/.*/  exit 0  # mutant (iii)/' 'exit 0  # mutant (iii)'; then
  push_exhaust_world
  SCRIPT="$MUT_III/meta-sync.sh"
  push_exhaust_run
  SCRIPT="$SUT"
  if px_failed_closed; then
    no "mutation control (iii) REFUTED: the exit-0 mutant still reported push_failed — the push-retry-exhaustion assertion is not load-bearing"
  elif [ "$(px_hooks)" != "$PX_N" ] || [ "$(br_tip)" != "$PX_TIP" ]; then
    no "mutation control (iii): the mutant did not exhaust the same $PX_N rejected attempts (hooks=$(px_hooks), rc=$RC: $OUT) — control inconclusive"
  else
    ok "mutation control (iii): the exit-0 mutant turns the push-retry-exhaustion assertion red — rc=$RC after $(px_hooks) rejected attempts, no push_failed line (output: $(printf '%s' "$OUT" | tr '\n' '|'))"
  fi
else
  no "mutation control (iii): could not build the mutant (sed did not apply or bash -n failed) — control inconclusive"
fi

echo "== 37. mutation control (iv): missing base read as the EMPTY tree -> missing-base push assertion must turn red =="
MUT_IV="$TROOT/mutant-iv"
if build_mutant "$MUT_IV" 's/^    BASE_TREE=""$/    HAVE_BASE=1; BASE_TREE=4b825dc642cb6eb9a060e54bf8d69288fbee4904/' 'HAVE_BASE=1; BASE_TREE=4b825dc642cb6eb9a060e54bf8d69288fbee4904'; then
  if missing_base_world; then
    put B "$RQ/new35.md" "brand new from B"
    SCRIPT="$MUT_IV/meta-sync.sh"
    ms B push
    SCRIPT="$SUT"
    if [ "$RC" -eq 0 ] && ! br_has "$RQ/d.md" && [ "$(br_show "$RQ/new35.md")" = "brand new from B" ]; then
      no "mutation control (iv) REFUTED: the empty-tree mutant did not re-add d.md — the missing-base push assertion is not load-bearing"
    elif [ "$RC" -ne 0 ] || grep -qF 'could not list the meta-base tree' < <(printf '%s\n' "$OUT"); then
      no "mutation control (iv): the mutant push crashed instead of re-adding (rc=$RC: $OUT) — control inconclusive"
    elif br_has "$RQ/d.md"; then
      ok "mutation control (iv): the empty-tree mutant turns the missing-base push assertion red — it re-added the branch-deleted d.md (branch d.md: '$(br_show "$RQ/d.md")', rc=$RC)"
    else
      no "mutation control (iv): the mutant neither re-added d.md nor pushed the new file (rc=$RC: $OUT) — control inconclusive"
    fi
  else
    no "mutation control (iv): the missing-base fixture did not take — control inconclusive"
  fi
else
  no "mutation control (iv): could not build the mutant (sed did not apply or bash -n failed) — control inconclusive"
fi

echo "== 44. mutation control (v): the old unconditional x.md probe -> the design.png assertion (38) must turn red =="
MUT_V="$TROOT/mutant-v"
if build_mutant "$MUT_V" '/^  if \[ -d "\$ROOT\/\$1" \] || \[ ! -e "\$ROOT\/\$1" \]; then is_managed "\$1\/x.md"; else return 1; fi$/s#.*#  is_managed "$1" || is_managed "$1/x.md"#' '  is_managed "$1" || is_managed "$1/x.md"'; then
  design_png_world
  SCRIPT="$MUT_V/meta-sync.sh"
  design_png_sync; mv_rc=$?
  SCRIPT="$SUT"
  if [ "$mv_rc" -eq 0 ]; then
    no "mutation control (v) REFUTED: the unconditional-probe mutant still synced past design.png — the assertion is not load-bearing"
  elif grep -qF "meta_sync: symlink $RQ/design.png" < <(printf '%s' "$DP_DETAIL" | tr '|' '\n'); then
    ok "mutation control (v): the unconditional-probe mutant turns the design.png assertion red — $DP_DETAIL"
  else
    no "mutation control (v): the mutant failed for another reason ($DP_DETAIL) — control inconclusive"
  fi
else
  no "mutation control (v): could not build the mutant (sed did not apply or bash -n failed) — control inconclusive"
fi

echo "== 45. mutation control (vi): drop the plain-fetch retry -> the fetch-fallback assertion (39) must turn red =="
MUT_VI="$TROOT/mutant-vi"
if build_mutant "$MUT_VI" 's@^    g fetch -q --no-tags origin "refs/heads/\$BRANCH" >/dev/null 2>"\$WORK/fetch.err" || return 1$@    return 1  # mutant (vi)@' 'return 1  # mutant (vi)'; then
  SCRIPT="$MUT_VI/meta-sync.sh"
  fetch_fallback_ok; mvi_rc=$?
  SCRIPT="$SUT"
  if [ "$mvi_rc" -eq 0 ]; then
    no "mutation control (vi) REFUTED: the no-retry mutant still pulled and pushed — the fetch-fallback assertion is not load-bearing"
  elif grep -qF 'fetch_failed' < <(printf '%s' "$FF_DETAIL"); then
    ok "mutation control (vi): the no-retry mutant turns the fetch-fallback assertion red — $FF_DETAIL"
  else
    no "mutation control (vi): the mutant failed for another reason ($FF_DETAIL) — control inconclusive"
  fi
else
  no "mutation control (vi): could not build the mutant (sed did not apply or bash -n failed) — control inconclusive"
fi

echo "== 46. mutation control (vii): drop the union's hash re-check -> the changed-during-the-sync assertion (40) must turn red =="
MUT_VII="$TROOT/mutant-vii"
if build_mutant "$MUT_VII" 's@|| { warn "\$4 changed during the sync"; return 1; }@|| :  # mutant (vii)@' '|| :  # mutant (vii)'; then
  cds_world
  SCRIPT="$MUT_VII/meta-sync.sh"
  cds_run
  SCRIPT="$SUT"
  if [ -e "$W/cds.mark" ]; then
    no "mutation control (vii): the hook never fired (rc=$RC: $OUT) — control inconclusive"
  elif [ "$RC" -ne 0 ] && grep -qF 'changed during the sync' < <(printf '%s\n' "$OUT"); then
    no "mutation control (vii) REFUTED: the no-re-check mutant still refused — the assertion is not load-bearing"
  elif [ "$RC" -eq 0 ]; then
    ok "mutation control (vii): the no-re-check mutant turns the changed-during-the-sync assertion red — rc=0 ($(printf '%s' "$OUT" | tr '\n' '|')), meta-base rewritten: $(cmp -s "$W/cds-base.before" "$W/B/.git/meta-base" && echo no || echo yes), $AUTO now '$(get B "$AUTO")'"
  else
    no "mutation control (vii): the mutant failed for another reason (rc=$RC: $OUT) — control inconclusive"
  fi
else
  no "mutation control (vii): could not build the mutant (sed did not apply or bash -n failed) — control inconclusive"
fi

echo "== 47. mutation control (viii): drop the one-level-up reclaim -> the nested-reclaim assertion (41) must turn red =="
MUT_VIII="$TROOT/mutant-viii"
if build_mutant "$MUT_VIII" 's/^  if lock_is_stale "\$m" "\$w"; then reclaim_lock "\$m" "\$w" \$((depth + 1)); fi$/  :  # mutant (viii)/' ':  # mutant (viii)'; then
  nested_lock_world
  SCRIPT="$MUT_VIII/meta-sync.sh"
  nested_lock_run 3
  SCRIPT="$SUT"
  if nested_lock_ok; then
    no "mutation control (viii) REFUTED: the no-nested-reclaim mutant still reclaimed both — the assertion is not load-bearing"
  elif grep -qF 'meta_sync: locked' "$NL_D/push.out"; then
    ok "mutation control (viii): the no-nested-reclaim mutant turns the nested-reclaim assertion red — it waited out the lock and died locked ($NL_DETAIL)"
  else
    no "mutation control (viii): the mutant failed for another reason ($NL_DETAIL) — control inconclusive"
  fi
else
  no "mutation control (viii): could not build the mutant (sed did not apply or bash -n failed) — control inconclusive"
fi

echo "== 48. mutation control (ix): drop the up-front meta-base check -> the directory-meta-base assertion (42) must turn red =="
MUT_IX="$TROOT/mutant-ix"
if build_mutant "$MUT_IX" 's/^refuse_bad_base() {$/refuse_bad_base() { return 0  # mutant (ix)/' 'refuse_bad_base() { return 0  # mutant (ix)'; then
  dirbase_world
  SCRIPT="$MUT_IX/meta-sync.sh"
  ms B push
  SCRIPT="$SUT"
  if db_refused && ! br_has "$RQ/new42.md"; then
    no "mutation control (ix) REFUTED: the no-up-front-check mutant still refused before publishing — the assertion is not load-bearing"
  elif br_has "$RQ/new42.md" && [ "$(br_tip)" != "$DB_TIP" ]; then
    ok "mutation control (ix): the no-up-front-check mutant turns the directory-meta-base assertion red — it PUBLISHED new42.md, then: $(printf '%s' "$OUT" | tr '\n' '|')"
  else
    no "mutation control (ix): the mutant failed for another reason (rc=$RC: $OUT) — control inconclusive"
  fi
else
  no "mutation control (ix): could not build the mutant (sed did not apply or bash -n failed) — control inconclusive"
fi

echo "== 49. mutation control (x): ignore the mode line (default stays the constant) -> the throwaway-clone assertion (43) must turn red =="
MUT_X="$TROOT/mutant-x"
if build_mutant "$MUT_X" '/^  \[ "\$BRANCH_SET" = "1" \] || \[ "\$MODE_STATE" != "on" \] || BRANCH="\$MODE_BRANCH"$/s/.*/  :  # mutant (x)/' ':  # mutant (x)'; then
  tw_world
  SCRIPT="$MUT_X/meta-sync.sh"
  tw_push_ok; mx_rc=$?
  SCRIPT="$SUT"
  if [ "$mx_rc" -eq 0 ]; then
    no "mutation control (x) REFUTED: the mode-blind mutant still pushed $TW — the throwaway-clone assertion is not load-bearing"
  elif [ "$RC" -eq 0 ] && [ "$(br_show_of "$BR" "$RQ/tw.md")" = "on the throwaway branch" ]; then
    ok "mutation control (x): the mode-blind mutant turns the throwaway-clone assertion red — it pushed the REAL $BR instead ($BR tip moved off $LM_TIP; $TW lacks tw.md)"
  else
    no "mutation control (x): the mutant failed for another reason (rc=$RC: $OUT) — control inconclusive"
  fi
else
  no "mutation control (x): could not build the mutant (sed did not apply or bash -n failed) — control inconclusive"
fi

echo "== 52. mutation control (xi): drop the meta-base branch check -> the branch-switch assertion (50) must turn red =="
MUT_XI="$TROOT/mutant-xi"
if build_mutant "$MUT_XI" 's@^  if \[ -n "\$bb" \] && \[ "\$bb" != "\$BRANCH" \]; then$@  if false; then  # mutant (xi)@' 'if false; then  # mutant (xi)'; then
  bsw_world
  SCRIPT="$MUT_XI/meta-sync.sh"
  ms A pull
  SCRIPT="$SUT"
  if [ "$RC" -eq 1 ] && bsw_untouched; then
    no "mutation control (xi) REFUTED: the branch-blind mutant still refused the switched pull — the branch-switch assertion is not load-bearing"
  elif [ "$RC" -eq 0 ] && [ ! -e "$W/A/$RQ/a.md" ] && [ ! -e "$W/A/$RQ/b.md" ]; then
    ok "mutation control (xi): the branch-blind mutant turns the branch-switch assertion red — it planned $LZ against $BR's base and DELETED a.md + b.md: $(printf '%s' "$OUT" | tr '\n' '|')"
  else
    no "mutation control (xi): the mutant failed for another reason (rc=$RC: $OUT) — control inconclusive"
  fi
else
  no "mutation control (xi): could not build the mutant (sed did not apply or bash -n failed) — control inconclusive"
fi

echo "== 53. home_path is ANCHORED: real home paths hit, an API route's users/<id>/ segment does not (ms/11) =="
synced_pair
put B "$RQ/h-start.md" "/Users/alice/project/notes"
put B "$RQ/h-tick.md" 'see `/Users/alice/x` for the path'
put B "$RQ/h-flag.md" "bash x.sh --state-dir /Users/alice/.supervisor --jsonl"
put B "$RQ/h-dq.md" 'path "/home/bob/src" in the config'
put B "$RQ/h-file.md" "open file:///Users/alice/doc.md"
put B "$RQ/h-env.md" "HOME=/Users/alice/"
put B "$RQ/h-win.md" "C:/Users/alice/proj"
put B "$RQ/h-rel.md" "../Users/alice/x"
put B "$RQ/h-paren.md" "(/home/bob/)"
put B "$RQ/h-lower.md" "/users/alice/lower-case volume"
# negatives in the SAME push: the S3 false positive verbatim (s3-c's run file), plus other routes/URLs
put B "$RQ/n-api.md" 'after rewriting the sidecar'"'"'s literal /api/users/42/ example to a scrub-safe place'
put B "$RQ/n-v1.md" "GET /v1/users/abc/profile"
put B "$RQ/n-url.md" "https://example.com/home/page/"
put B "$RQ/n-ph.md" 'write /Users/<name>/myapp and /api/users/<id>/orders'
tip="$(br_tip)"; base_before="$(base_of B)"
ms B push
{ [ "$RC" -eq 2 ] && [ "$(br_tip)" = "$tip" ] && [ "$(base_of B)" = "$base_before" ]; }
check $? "home-path positives -> exit 2, branch tip and meta-base unchanged (rc=$RC)"
for h in h-start h-tick h-flag h-dq h-file h-env h-win h-rel h-paren h-lower; do
  grep -qxF "meta_sync: scrub $RQ/$h.md: home_path" < <(printf '%s\n' "$OUT")
  check $? "home path still hits: $h ($(get B "$RQ/$h.md"))"
done
for n in n-api n-v1 n-url n-ph; do
  ! grep -qF "meta_sync: scrub $RQ/$n.md:" < <(printf '%s' "$OUT")
  check $? "not a home path, not named: $n ($(get B "$RQ/$n.md"))"
done
rm -f "$W/B/$RQ"/h-*.md
ms B push
{ [ "$RC" -eq 0 ] && br_has "$RQ/n-api.md" && br_has "$RQ/n-v1.md" && br_has "$RQ/n-url.md" && br_has "$RQ/n-ph.md"; }
check $? "the S3 false positive (/api/users/42/) and the other routes push (rc=$RC: $OUT)"

echo "== 54. no literal home-path example in the shipped prompts (ms/04's acceptance grep, now a guard) =="
# The guard reads the SHIPPED home_path rule out of meta-sync.sh, so it can never drift from the scrub.
HP_RE="$(sed -n 's/^home_path\${TAB}i\${TAB}//p' "$SUTB")"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
# docs/command-parts/ holds the split command docs' moved text (automate-speed/22) — same prose
# surface as commands/, so the guard scans it too.
home_examples() { env LC_ALL=C grep -rniE -e "$HP_RE" "$1/loomwright/agents" "$1/loomwright/commands" "$1/loomwright/docs/command-parts" "$1/loomwright/skills" 2>/dev/null; }
[ -n "$HP_RE" ]; check $? "the home_path rule was read from meta-sync.sh ($HP_RE)"
hits="$(home_examples "$REPO_ROOT")"
[ -z "$hits" ]; check $? "agents/commands/command-parts/skills carry no literal home-path example — use /Users/<name>/ (got: $(printf '%s' "$hits" | head -3 | tr '\n' '|'))"
FX="$TROOT/guard-fixture"; mkdir -p "$FX/loomwright/agents" "$FX/loomwright/commands" "$FX/loomwright/skills/x"
printf '%s\n' '- **Project:** /Users/name/my-project' > "$FX/loomwright/skills/x/SKILL.md"
[ -n "$(home_examples "$FX")" ]; check $? "the guard fires on a fixture that reintroduces a literal example (/Users/name/)"
FXP="$TROOT/guard-fixture-parts"; mkdir -p "$FXP/loomwright/docs/command-parts/setup"
printf '%s\n' '- **Project:** /Users/name/my-project' > "$FXP/loomwright/docs/command-parts/setup/x.md"
[ -n "$(home_examples "$FXP")" ]; check $? "the guard fires on a literal example in a split command part (docs/command-parts/)"

echo "== 55. mutation control (xii): the old unanchored home_path rule -> the API-route assertion (53) must turn red =="
MUT_XII="$TROOT/mutant-xii"
if build_mutant "$MUT_XII" 's@^home_path\${TAB}i\${TAB}(^|\[^A-Za-z0-9_-\])/(Users|home)/@home_path${TAB}i${TAB}/(Users|home)/@' 'home_path${TAB}i${TAB}/(Users|home)/[A-Za-z0-9._-]+/'; then
  synced_pair
  put B "$RQ/n-api.md" 'the literal /api/users/42/ example'
  SCRIPT="$MUT_XII/meta-sync.sh"
  ms B push
  SCRIPT="$SUT"
  if [ "$RC" -eq 0 ]; then
    no "mutation control (xii) REFUTED: the unanchored mutant pushed the API route — the anchoring assertion is not load-bearing"
  elif [ "$RC" -eq 2 ] && grep -qxF "meta_sync: scrub $RQ/n-api.md: home_path" < <(printf '%s\n' "$OUT"); then
    ok "mutation control (xii): the unanchored mutant refuses /api/users/42/ as home_path — the anchoring assertion is load-bearing"
  else
    no "mutation control (xii): the mutant failed for another reason (rc=$RC: $OUT) — control inconclusive"
  fi
else
  no "mutation control (xii): could not build the mutant (sed did not apply or bash -n failed) — control inconclusive"
fi

echo "== 56. list-managed: exactly the is_managed set (local tree / --tracked), no branch, no lock =="
roundtrip_world   # A: managed files + every ignored / unmanaged fixture (logs, nested .supervisor/, pending, sidecars)
exp_lm="$(printf '%s\n' "$RQ/sub/deep.md" "$RQ/x.md" .supervisor/automate/automate-2026-01-01-000000.md \
  .supervisor/jobs/done/2026-01-01-brief.md .supervisor/postmortem/results.jsonl | env LC_ALL=C sort)"
OUT="$(bash "$SCRIPT" list-managed --root "$W/A" 2>"$W/lm.err")"; RC=$?
{ [ "$RC" -eq 0 ] && [ "$OUT" = "$exp_lm" ] && [ ! -s "$W/lm.err" ]; }
check $? "list-managed prints exactly the managed local paths, sorted, on stdout, exit 0 — no log, nested .supervisor/, pending or sidecar (rc=$RC: $(printf '%s' "$OUT" | tr '\n' '|'))"
lm_local="$OUT"
{ [ ! -e "$W/A/.git/meta-sync.lock" ] && [ ! -e "$W/A/.git/meta-base" ] && [ -z "$(br_names)" ]; }
check $? "list-managed takes no lock, writes no meta-base and publishes nothing"
ms A push
[ "$(br_names | env LC_ALL=C sort)" = "$lm_local" ]; check $? "list-managed equals the set a whole-set push publishes (branch: $(br_names | tr '\n' '|'))"
git -C "$W/A" add -f "$RQ/x.md" "$RQ/notes.log" "$RQ/.supervisor/logs/nested.md" .supervisor/jobs/pending/2026-01-02-pending.md \
  .supervisor/logs/session.jsonl .supervisor/jobs/done/2026-01-01-brief.md
ms A list-managed --tracked
{ [ "$RC" -eq 0 ] && [ "$OUT" = "$(printf '%s\n' .supervisor/jobs/done/2026-01-01-brief.md "$RQ/x.md" | env LC_ALL=C sort)" ]; }
check $? "list-managed --tracked prints only the TRACKED managed paths (index), none of the force-added unmanaged ones (rc=$RC: $(printf '%s' "$OUT" | tr '\n' '|'))"
git -C "$W/A" reset -q
ms A list-managed --tracked; { [ "$RC" -eq 0 ] && [ -z "$OUT" ]; }; check $? "nothing tracked -> --tracked prints nothing, exit 0 (rc=$RC: $OUT)"
ln -s "$W/A/.supervisor/jobs/done" "$W/A/$RQ/linkdir"
ms A list-managed
{ [ "$RC" -eq 1 ] && grep -qF "meta_sync: symlink $RQ/linkdir" < <(printf '%s\n' "$OUT"); }
check $? "list-managed fails closed on a symlinked folder where run history lives, exactly like push (rc=$RC: $OUT)"
rm -f "$W/A/$RQ/linkdir"
for args in "pull --tracked" "push --tracked" "status --tracked" "push --paths" "pull --paths" "list-managed --paths" "list-managed --branch $BR" "list-managed --branch $BR --allow-branch-mismatch"; do
  # shellcheck disable=SC2086
  ms A $args
  [ "$RC" -eq 1 ] && grep -q '^meta_sync: usage: ' < <(printf '%s\n' "$OUT")
  check $? "'$args' -> usage error exit 1 (rc=$RC: $OUT)"
done
echo "-- an unknown mode: list-managed and scrub still run (no branch resolution); status still refuses --"
mkworld; clone M
(cd "$W/M" && bash "$HERE/setup-memory.sh" --root "$W/M" apply --branch-mode team-meta >/dev/null 2>&1; rm -f .gitignore.backup.*)
sed "s/^# loomwright-meta-branch: .*/# loomwright-meta-branch: off/" "$W/M/.gitignore" > "$W/M/.gitignore.new" && mv "$W/M/.gitignore.new" "$W/M/.gitignore"
mm="$(bash "$HERE/setup-memory.sh" --root "$W/M" mode)"
case "$mm" in "unknown "*) true ;; *) false ;; esac; check $? "fixture: M's mode reads unknown (got '$mm')"
put M "$RQ/m.md" "see /home/bob/x"
ms M status; [ "$RC" -eq 1 ] && grep -q 'meta_sync: mode_unknown' < <(printf '%s\n' "$OUT"); check $? "control: status under the unknown mode -> exit 1 mode_unknown (rc=$RC)"
ms M list-managed; { [ "$RC" -eq 0 ] && [ "$OUT" = "$RQ/m.md" ]; }; check $? "list-managed under an unknown mode -> exit 0, lists $RQ/m.md (rc=$RC: $OUT)"
printf '%s\n' "$RQ/m.md" > "$W/m.list"
ms M scrub --paths-from "$W/m.list"
{ [ "$RC" -eq 2 ] && grep -qxF "meta_sync: scrub-hit $RQ/m.md:1: home_path" < <(printf '%s\n' "$OUT"); }
check $? "scrub under an unknown mode -> runs, exit 2 naming the hit (rc=$RC: $OUT)"
{ [ ! -e "$W/M/.git/meta-sync.lock" ] && [ ! -e "$W/M/.git/meta-base" ] && [ -z "$(git --git-dir="$W/origin.git" for-each-ref refs/heads/team-meta refs/heads/$BR)" ]; }
check $? "neither took a lock, wrote meta-base or created a branch"

echo "== 57. scrub --paths-from: one scrub-hit line per hit (path:line: rule), same rules as push, writes nothing =="
synced_pair
mkdir -p "$W/B/.agent"; printf '%s\n' '# project deny terms' 'ACME-SECRET-[0-9]+' > "$W/B/.agent/meta-sync-deny.txt"
git -C "$W/B" add .agent/meta-sync-deny.txt && git -C "$W/B" commit -qm 'deny patterns'
put B "$RQ/p-email.md" "$(printf '%s\n' 'clean first line' 'clean second' 'contact someone@example.org')"
put B "$RQ/p-home.md" "$(printf '%s\n' 'x' '/Users/alice/notes')"
put B "$RQ/p-tok.md" "token ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij"
put B "$RQ/p-slug.md" "$(printf '%s\n' 'a' 'b' 'https://github.com/evilcorp/secret-repo/pull/3')"
put B "$RQ/p-deny.md" "$(printf '%s\n' 'one' 'two' 'ticket ACME-SECRET-42')"
put B "$RQ/p-clean.md" "nothing to see here"
printf '%s\n' '{"repo":"evilcorp/private","n":9}' >> "$W/B/.supervisor/postmortem/results.jsonl"
printf '%s\n' '# would-be-pushed files' "$RQ/p-email.md" "./$RQ/p-home.md" "$RQ/p-tok.md" "$RQ/p-slug.md" "$RQ/p-deny.md" \
  "$RQ/p-clean.md" '' .supervisor/postmortem/results.jsonl "$RQ/p-tok.md" > "$W/scrub.list"
tip="$(br_tip)"; base_before="$(base_of B)"; por_before="$(porcelain B)"
SOUT="$(bash "$SCRIPT" scrub --paths-from "$W/scrub.list" --root "$W/B" 2>"$W/scrub.err")"; RC=$?
SERR="$(cat "$W/scrub.err")"
exp_hits="$(printf '%s\n' "meta_sync: scrub-hit $RQ/p-email.md:3: email" "meta_sync: scrub-hit $RQ/p-home.md:2: home_path" \
  "meta_sync: scrub-hit $RQ/p-tok.md:1: token_github" "meta_sync: scrub-hit $RQ/p-slug.md:-: forge_slug" \
  "meta_sync: scrub-hit $RQ/p-deny.md:3: deny_pattern:2" "meta_sync: scrub-hit .supervisor/postmortem/results.jsonl:-: forge_slug" \
  "meta_sync: scrub-hit .supervisor/postmortem/results.jsonl:-: ledger_repo" | env LC_ALL=C sort)"
got_hits="$(printf '%s\n' "$SERR" | grep '^meta_sync: scrub-hit ' | env LC_ALL=C sort)"
[ "$RC" -eq 2 ]; check $? "a planted hit -> scrub exits 2 (rc=$RC)"
[ "$got_hits" = "$exp_hits" ]; check $? "exactly one scrub-hit line per hit with the first matching line (line rules) or '-' (whole-file rules); the duplicate listing is scanned once (got: $(printf '%s' "$got_hits" | tr '\n' '|'))"
{ [ -z "$SOUT" ] && grep -q '^meta_sync: aborted — scrub hit(s) above in 6 of 7 file(s)' < <(printf '%s\n' "$SERR"); }
check $? "hit lines and the 'aborted' summary go to stderr; stdout is empty (stdout: '$SOUT')"
! grep -q '^meta_sync: scrub ' < <(printf '%s\n' "$SERR"); check $? "no line starts with push's 'meta_sync: scrub ' prefix (that contract is untouched)"
{ [ "$(br_tip)" = "$tip" ] && [ "$(base_of B)" = "$base_before" ] && [ "$(porcelain B)" = "$por_before" ] && [ ! -e "$W/B/.git/meta-sync.lock" ]; }
check $? "scrub writes nothing: branch tip, meta-base, code-branch status unchanged, no lock"
echo "-- the same planted files through push report the same (path, rule) pairs --"
ms B push
push_pairs="$(printf '%s\n' "$OUT" | sed -n 's/^meta_sync: scrub //p' | env LC_ALL=C sort)"
scrub_pairs="$(printf '%s\n' "$got_hits" | sed -E 's/^meta_sync: scrub-hit ([^:]*):[^:]*: /\1: /' | env LC_ALL=C sort)"
{ [ "$RC" -eq 2 ] && [ -n "$push_pairs" ] && [ "$push_pairs" = "$scrub_pairs" ] && [ "$(br_tip)" = "$tip" ]; }
check $? "push (exit 2) and scrub name the same rule for every planted file (push: $(printf '%s' "$push_pairs" | tr '\n' '|'))"
echo "-- clean / unreadable / usage --"
printf '%s\n' "$RQ/p-clean.md" "$RQ/x.md" > "$W/clean.list"
SOUT="$(bash "$SCRIPT" scrub --paths-from "$W/clean.list" --root "$W/B" 2>"$W/scrub.err")"; RC=$?
{ [ "$RC" -eq 0 ] && [ "$SOUT" = "meta_sync: clean (2 file(s) scanned)" ] && [ ! -s "$W/scrub.err" ]; }
check $? "a clean list -> exit 0, 'meta_sync: clean (2 file(s) scanned)' on stdout, nothing on stderr (rc=$RC: $SOUT)"
mkdir -p "$W/B/$RQ/adir"
printf '%s\n' "$RQ/nope.md" "$RQ/adir" > "$W/miss.list"
ms B scrub --paths-from "$W/miss.list"
{ [ "$RC" -eq 2 ] && grep -qxF "meta_sync: scrub-hit $RQ/nope.md:-: unreadable" < <(printf '%s\n' "$OUT") \
  && grep -qxF "meta_sync: scrub-hit $RQ/adir:-: unreadable" < <(printf '%s\n' "$OUT"); }
check $? "a missing path and a directory -> 'unreadable' hits with line '-', exit 2 (rc=$RC: $OUT)"
ms B scrub; { [ "$RC" -eq 1 ] && grep -qF 'meta_sync: usage: scrub requires --paths-from' < <(printf '%s\n' "$OUT"); }; check $? "scrub without --paths-from -> usage error exit 1 (rc=$RC: $OUT)"
ms B scrub --paths-from "$W/no-such-list"; [ "$RC" -eq 1 ]; check $? "scrub --paths-from <missing file> -> exit 1 (rc=$RC: $OUT)"
ms B scrub --paths-from "$W/clean.list" --branch "$BR"; [ "$RC" -eq 1 ]; check $? "scrub --branch -> usage error exit 1, never silently ignored (rc=$RC: $OUT)"

echo "== 58. mutation control (xiii): scrub-hit never locates the line -> the line assertion (57) must turn red =="
MUT_XIII="$TROOT/mutant-xiii"
if build_mutant "$MUT_XIII" 's/^  case "\$n" in .*) n="-" ;; esac$/  n="-"  # mutant (xiii)/' 'n="-"  # mutant (xiii)'; then
  OUT="$(bash "$MUT_XIII/meta-sync.sh" scrub --paths-from "$W/scrub.list" --root "$W/B" 2>&1)"; RC=$?
  if [ "$RC" -eq 2 ] && grep -qxF "meta_sync: scrub-hit $RQ/p-email.md:-: email" < <(printf '%s\n' "$OUT"); then
    ok "mutation control (xiii): the mutant reports 'p-email.md:-: email' instead of ':3:' — the line assertion is load-bearing"
  else
    no "mutation control (xiii): the mutant failed for another reason (rc=$RC: $OUT) — control inconclusive"
  fi
else
  no "mutation control (xiii): could not build the mutant (sed did not apply or bash -n failed) — control inconclusive"
fi

echo "== 59. D9: the top-level <name>.dismissed-decisions ledger is managed (and scrubbed); look-alikes are not =="
D9_LEDGER=".supervisor/automate/automate-2026-10-07-000000-L1.dismissed-decisions"
d9_world() {
  mkworld; clone A
  ms A init
  put A ".supervisor/automate/automate-2026-10-07-000000.md" "# Automate Run: automate-2026-10-07-000000"
  printf 'automate-2026-10-07-000000-L1--a-1a2b3c--dismissed-0123abcd.md\tdrop\t2026-10-07T00:00:00Z\n' > "$W/A/$D9_LEDGER"
  put A ".supervisor/automate/sub/nested.dismissed-decisions" "x"
  put A ".supervisor/automate/.dismissed-decisions" "x"
  put A ".supervisor/automate/automate-2026-10-07-000000.lanes" "L1"
  put A ".supervisor/automate/automate-2026-10-07-000000.dismissed-decisions.bak" "x"
}
d9_world
d9_exp="$(printf '%s\n' .supervisor/automate/automate-2026-10-07-000000.md "$D9_LEDGER" | env LC_ALL=C sort)"
ms A list-managed
{ [ "$RC" -eq 0 ] && [ "$OUT" = "$d9_exp" ]; }
check $? "list-managed lists the top-level ledger and the run file only — no nested / bare / .lanes / .bak look-alike (rc=$RC: $(printf '%s' "$OUT" | tr '\n' '|'))"
D9_LM="$OUT"
ms A push
{ [ "$RC" -eq 0 ] && [ "$(br_names | env LC_ALL=C sort)" = "$d9_exp" ] && [ "$(br_show "$D9_LEDGER")" = "$(cat "$W/A/$D9_LEDGER")" ]; }
check $? "a whole-set push publishes the ledger byte-for-byte beside the run file, nothing else (rc=$RC: $(br_names | tr '\n' '|'))"
d9_world
printf 'note\t/Users/bob/x\n' >> "$W/A/$D9_LEDGER"
ms A push
{ [ "$RC" -eq 2 ] && grep -qF "meta_sync: scrub $D9_LEDGER: home_path" < <(printf '%s\n' "$OUT") && [ -z "$(br_names)" ]; }
check $? "a ledger carrying a home path is refused by push's scrub (exit 2), nothing published (rc=$RC: $OUT)"

echo "== 60. mutation control (xiv): drop the D9 is_managed arm -> the list-managed assertion (59) must turn red =="
MUT_XIV="$TROOT/mutant-xiv"
if build_mutant "$MUT_XIV" 's/^    \.supervisor\/automate\/?\*\.dismissed-decisions) return 0 ;;$/    # mutant (xiv) D9 arm dropped/' '# mutant (xiv) D9 arm dropped'; then
  d9_world
  OUT="$(bash "$MUT_XIV/meta-sync.sh" list-managed --root "$W/A" 2>&1)"; RC=$?
  if [ "$RC" -eq 0 ] && [ "$OUT" != "$D9_LM" ] && [ "$OUT" = ".supervisor/automate/automate-2026-10-07-000000.md" ]; then
    ok "mutation control (xiv): the mutant drops the ledger from list-managed — the D9 assertion is load-bearing"
  else
    no "mutation control (xiv): the mutant failed for another reason (rc=$RC: $OUT) — control inconclusive"
  fi
else
  no "mutation control (xiv): could not build the mutant (sed did not apply or bash -n failed) — control inconclusive"
fi

echo "== 61. an UNREADABLE meta-base: pull and push refuse base_branch_mismatch, nothing changed (af/36 A6) =="
# load_base's `[ ! -r "$META_BASE" ]` arm: the branch the base was recorded against is unknown, so
# the sync refuses rather than plan against it (or fall back to the no-base derivation).
UNR_MSG="meta_sync: base_branch_mismatch — meta-base"
UNR_TAIL="is unreadable, so the branch it was recorded against is unknown; nothing was changed"
# unr_world — synced pair; B holds a local edit and a pending take-R; B's meta-base chmod 000.
unr_world() {
  synced_pair
  put A "$RQ/x.md" "x v2 from A"; ms A push
  put B "$RQ/y.md" "y v2 local to B"
  UNR_TIP="$(br_tip)"; cp "$W/B/.git/meta-base" "$W/unr-base.before"
  chmod 000 "$W/B/.git/meta-base"
}
# unr_untouched — 0 iff B's files, the branch tip and B's meta-base bytes are as unr_world left them.
unr_untouched() {
  chmod 644 "$W/B/.git/meta-base"
  local same=1; cmp -s "$W/unr-base.before" "$W/B/.git/meta-base" || same=0
  chmod 000 "$W/B/.git/meta-base"
  [ "$same" = 1 ] && [ "$(br_tip)" = "$UNR_TIP" ] && [ "$(get B "$RQ/x.md")" = "x v1" ] \
    && [ "$(get B "$RQ/y.md")" = "y v2 local to B" ] && [ ! -e "$W/B/.git/meta-sync.lock" ]
}
UNR_SKIP=0
if [ "$(id -u)" = "0" ]; then
  echo "  SKIP: unreadable meta-base legs (running as root, permissions are not enforced)"; UNR_SKIP=1
else
  unr_world
  ms B pull
  { [ "$RC" -eq 1 ] && grep -qF "$UNR_MSG" < <(printf '%s\n' "$OUT") && grep -qF "$UNR_TAIL" < <(printf '%s\n' "$OUT") && unr_untouched; }
  check $? "pull with an unreadable meta-base -> exit 1 base_branch_mismatch (unreadable), pending x.md NOT written, meta-base bytes and branch unchanged (rc=$RC: $OUT)"
  ms B push
  { [ "$RC" -eq 1 ] && grep -qF "$UNR_MSG" < <(printf '%s\n' "$OUT") && grep -qF "$UNR_TAIL" < <(printf '%s\n' "$OUT") && unr_untouched; }
  check $? "push with an unreadable meta-base -> exit 1 base_branch_mismatch (unreadable), nothing published, meta-base bytes unchanged (rc=$RC: $OUT)"
  chmod 644 "$W/B/.git/meta-base"
fi

echo "== 62. mutation control (xv): drop load_base's unreadable-meta-base arm -> the unreadable assertion (61) must turn red =="
MUT_XV="$TROOT/mutant-xv"
if [ "$UNR_SKIP" = 1 ]; then
  echo "  SKIP: mutation control (xv) (its leg 61 is skipped under root)"
elif build_mutant "$MUT_XV" 's@^  if \[ ! -r "\$META_BASE" \]; then$@  if false; then  # mutant (xv)@' 'if false; then  # mutant (xv)'; then
  unr_world
  SCRIPT="$MUT_XV/meta-sync.sh"
  ms B push
  SCRIPT="$SUT"
  chmod 644 "$W/B/.git/meta-base"
  if [ "$RC" -eq 1 ] && grep -qF "$UNR_TAIL" < <(printf '%s\n' "$OUT"); then
    no "mutation control (xv) REFUTED: the mutant still printed the unreadable refusal — leg 61 is not load-bearing"
  else
    ok "mutation control (xv): without the arm the unreadable meta-base is no longer refused as unreadable, so leg 61 turns red (rc=$RC: $(printf '%s' "$OUT" | tr '\n' '|'))"
  fi
else
  no "mutation control (xv): could not build the mutant (sed did not apply or bash -n failed) — control inconclusive"
fi

echo "== 63. the tracked request file .agent/meta-allowlist.txt: a fresh clone with NO config.json pushes old-slug history (af36-remainder/02 A1/A2) =="
# WHY: the allowlist's config.json is gitignored, so a fresh clone resolved it to the remote alone
# and refused every push that touched a pre-rename ledger line or an old-slug forge URL. The tracked
# request file travels; setup-memory.sh grants an entry only when gh says it is the SAME repository
# as origin. These legs run with the file-level LOOMWRIGHT_MEMORY_REPO_ALLOWLIST scrubbed (env -u),
# so layer 4 is genuinely what resolves. TWO PATH stubs, no network:
#   · git: `git remote get-url` expands url.<x>.insteadOf, so a clone fetching from the local bare
#     origin can never REPORT a GitHub-shaped origin. The shim answers only
#     `git -C <root> remote get-url origin` (resolve_origin's single read) with https://github.com/owner/repo.git;
#     every other git call — ls-remote, fetch, push — still reaches the local bare origin.
#   · gh: owner/repo and owner/repo-old (the rename redirect) answer id 7; other/private answers 9.
RA_BIN="$TROOT/ra-bin"; mkdir -p "$RA_BIN"
RA_LOG="$TROOT/ra-gh.log"
cat > "$RA_BIN/git" <<SHIM
#!/bin/sh
if [ "\$1" = "-C" ] && [ "\$3" = "remote" ] && [ "\$4" = "get-url" ] && [ "\$5" = "origin" ]; then
  echo "https://github.com/owner/repo.git"; exit 0
fi
exec "$REAL_GIT" "\$@"
SHIM
cat > "$RA_BIN/gh" <<'GH'
#!/bin/sh
printf '%s\n' "$*" >> "$RA_GH_LOG"
if [ -n "${RA_GH_FAIL:-}" ]; then echo "gh: stub failure (not logged in)" >&2; exit 1; fi
case "$2" in
  repos/owner/repo|repos/owner/repo-old) echo 7 ;;
  repos/other/private) echo 9 ;;
  *) echo "gh: HTTP 404: Not Found" >&2; exit 1 ;;
esac
GH
chmod +x "$RA_BIN/git" "$RA_BIN/gh"
# ra_ms <clone> <args...> [— env: RA_EXTRA="VAR=value"] — the SUT with the allowlist env scrubbed
# and both stubs first on PATH; sets OUT / RC like ms.
RA_EXTRA=""
ra_ms() {
  local d="$1"; shift
  # shellcheck disable=SC2086
  OUT="$(env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST RA_GH_LOG="$RA_LOG" PATH="$RA_BIN:$PATH" $RA_EXTRA bash "$SCRIPT" "$@" --root "$W/$d" 2>&1)"; RC=$?
}
RA_REQ='# requested slugs (only a gh repository-id match with origin grants one)
owner/repo
owner/repo-old'
# ra_world — origin's code branch carries the request file; A (env allowlist: both slugs) publishes
# old-slug history; C is a FRESH clone with no .supervisor/config.json that pulls it.
ra_world() {
  mkworld
  ( cd "$W/seed" && mkdir -p .agent && printf '%s\n' "$RA_REQ" > .agent/meta-allowlist.txt \
      && git add .agent/meta-allowlist.txt && git commit -qm 'request file' && git push -q origin main ) >/dev/null 2>&1
  clone A; ms A init
  put A "$RQ/old.md" "see https://github.com/owner/repo-old/pull/3"
  mkdir -p "$W/A/.supervisor/postmortem"
  printf '%s\n' '{"repo":"owner/repo-old","n":1}' '{"repo":"owner/repo","n":2}' > "$W/A/.supervisor/postmortem/results.jsonl"
  ms A push
  clone C
}
# ra_scenario — 0 iff C (no config) pulls, then pushes a new old-slug ledger line + an old-slug edit.
RA_DETAIL=""
ra_scenario() {
  ra_world
  [ -f "$W/C/.agent/meta-allowlist.txt" ] && [ ! -e "$W/C/.supervisor/config.json" ] || { RA_DETAIL="fixture: request file missing or config present in C"; return 1; }
  ra_ms C pull
  [ "$RC" -eq 0 ] || { RA_DETAIL="pull rc=$RC: $OUT"; return 1; }
  printf '%s\n' '{"repo":"owner/repo-old","n":3}' >> "$W/C/.supervisor/postmortem/results.jsonl"
  printf '%s\n' "and https://github.com/owner/repo-old/issues/9" >> "$W/C/$RQ/old.md"
  ra_ms C push
  RA_DETAIL="push rc=$RC: $(printf '%s' "$OUT" | tr '\n' '|')"
  [ "$RC" -eq 0 ] && grep -q 'meta_sync: pushed' < <(printf '%s' "$OUT") \
    && grep -qF '"n":3' < <(br_show .supervisor/postmortem/results.jsonl) \
    && grep -qF 'owner/repo-old/issues/9' < <(br_show "$RQ/old.md")
}
ra_scenario; check $? "A1: a fresh clone with no config.json pulls, then pushes an old-slug ledger line + an old-slug edit — the old slug resolves to origin's id ($RA_DETAIL)"
# A3 in the scrub: the same push with gh FAILING grants nothing, so the scrub refuses (fail closed).
ra_world; ra_ms C pull
printf '%s\n' '{"repo":"owner/repo-old","n":3}' >> "$W/C/.supervisor/postmortem/results.jsonl"
tip="$(br_tip)"
RA_EXTRA="RA_GH_FAIL=1"; ra_ms C push; RA_EXTRA=""
{ [ "$RC" -eq 2 ] && grep -qxF "meta_sync: scrub .supervisor/postmortem/results.jsonl: ledger_repo" < <(printf '%s\n' "$OUT") && [ "$(br_tip)" = "$tip" ]; }
check $? "A3: with gh failing, no request entry is granted — the old-slug ledger line is refused (exit 2 ledger_repo, branch unchanged) (rc=$RC: $OUT)"
# A2 in the scrub: a requested slug that is a DIFFERENT repository is not granted — its record is refused.
printf '%s\n' 'other/private' >> "$W/C/.agent/meta-allowlist.txt"
printf '%s\n' '{"repo":"other/private","n":1}' >> "$W/C/.supervisor/postmortem/results.jsonl"
ra_ms C push
{ [ "$RC" -eq 2 ] && grep -qxF "meta_sync: scrub .supervisor/postmortem/results.jsonl: ledger_repo" < <(printf '%s\n' "$OUT") && [ "$(br_tip)" = "$tip" ]; }
check $? "A2: a requested slug resolving to a DIFFERENT repository is not granted — its ledger record is refused by the scrub (rc=$RC: $OUT)"
ra_allow="$(env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST RA_GH_LOG="$RA_LOG" PATH="$RA_BIN:$PATH" bash "$HERE/setup-memory.sh" --root "$W/C" allowlist 2>&1)"
grep -qF 'allowlist: ignored other/private — not this repository' < <(printf '%s\n' "$ra_allow")
check $? "A2: ... and the resolver names it on stderr: 'allowlist: ignored other/private — not this repository' (got: $(printf '%s' "$ra_allow" | tr '\n' '|'))"

echo "== 64. mutation control (xvi): delete the request-file layer call from setup-memory.sh -> the A1 assertion (63) must turn red =="
MUT_XVI="$TROOT/mutant-xvi"; mkdir -p "$MUT_XVI"
cp "$SUT" "$MUT_XVI/meta-sync.sh"
cp -R "$HERE/meta-sync.d" "$MUT_XVI/"
# The mutant's source is setup-memory.sh as ONE file (its own _sm_bundle output, automate-speed/20):
# load_allowlist now lives in setup-memory.d/allowlist.sh, and a mutant written from the bundle is
# self-contained beside the copied meta-sync.sh.
SMB_XVI="$TROOT/setup-memory.bundle-xvi.sh"
( eval "$(awk '/^_sm_bundle\(\) \{$/,/^}$/' "$HERE/setup-memory.sh")"; _sm_bundle "$HERE/setup-memory.sh" ) > "$SMB_XVI"
sed -e 's/^    granted="\$(meta_allowlist_grants "\$own")"$/    granted=""  # mutant (xvi)/' "$SMB_XVI" > "$MUT_XVI/setup-memory.sh"
if [ -s "$MUT_XVI/setup-memory.sh" ] && ! cmp -s "$SMB_XVI" "$MUT_XVI/setup-memory.sh" \
   && grep -qF 'granted=""  # mutant (xvi)' "$MUT_XVI/setup-memory.sh" && bash -n "$MUT_XVI/setup-memory.sh"; then
  SCRIPT="$MUT_XVI/meta-sync.sh"
  if ra_scenario; then
    no "mutation control (xvi) REFUTED: without the request-file layer the fresh clone still pushed — leg 63 is not load-bearing"
  else
    ok "mutation control (xvi): without the request-file layer the old-slug push is refused, so leg 63 turns red ($RA_DETAIL)"
  fi
  SCRIPT="$SUT"
else
  no "mutation control (xvi): could not build the mutant (empty, unchanged or bash -n failed) — control inconclusive"
fi

echo "== 65. email exemption: only git@<forge host>: (scp-style SSH remote) passes; real addresses still hit =="
synced_pair
put B "$RQ/fx-github.md" "$(printf '%s\n' 'clone it:' 'git clone git@github.com:owner/repo.git')"
put B "$RQ/fx-gitlab.md" "remote: git@gitlab.com:owner/repo"
put B "$RQ/fx-bitbucket.md" "origin git@bitbucket.org:owner/repo-old.git (fetch)"
for h in github gitlab bitbucket; do
  printf '%s\n' "$RQ/fx-$h.md" > "$W/fx.list"
  SOUT="$(bash "$SCRIPT" scrub --paths-from "$W/fx.list" --root "$W/B" 2>"$W/fx.err")"; RC=$?
  { [ "$RC" -eq 0 ] && [ "$SOUT" = "meta_sync: clean (1 file(s) scanned)" ] && [ ! -s "$W/fx.err" ]; }
  check $? "the git SSH remote at $h passes the email rule: scrub exit 0, clean (rc=$RC: $SOUT $(tr '\n' '|' < "$W/fx.err"))"
done
ms B push
{ [ "$RC" -eq 0 ] && br_has "$RQ/fx-github.md" && br_has "$RQ/fx-gitlab.md" && br_has "$RQ/fx-bitbucket.md"; }
check $? "a push carrying all three forge remotes lands (rc=$RC: $OUT)"
# fx_refused <file> <content> <expected scrub-hit line(s), newline-separated> — scrub names exactly those
fx_refused() {
  put B "$RQ/$1" "$2"
  printf '%s\n' "$RQ/$1" > "$W/fx.list"
  SOUT="$(bash "$SCRIPT" scrub --paths-from "$W/fx.list" --root "$W/B" 2>"$W/fx.err")"; RC=$?
  FX_GOT="$(grep '^meta_sync: scrub-hit ' "$W/fx.err" | env LC_ALL=C sort | tr '\n' '|')"
  [ "$RC" -eq 2 ] && [ "$FX_GOT" = "$(printf '%s\n' "$3" | env LC_ALL=C sort | tr '\n' '|')" ]
}
fx_refused fr-forge-user.md "mail someone@github.com about it" "meta_sync: scrub-hit $RQ/fr-forge-user.md:1: email"
check $? "a real address at a forge host (someone@github.com) still exits 2: email (got: $FX_GOT)"
fx_refused fr-nonforge.md "remote git@example.com:owner/repo.git" "meta_sync: scrub-hit $RQ/fr-nonforge.md:1: email"
check $? "a non-forge git@ host (git@example.com:) still exits 2: email (got: $FX_GOT)"
fx_refused fr-lookalike.md "remote git@github.company.com:owner/repo.git" "meta_sync: scrub-hit $RQ/fr-lookalike.md:1: email"
check $? "a look-alike forge host (git@github.company.com:) still exits 2: email (got: $FX_GOT)"
fx_refused fr-xgit.md "remote xgit@github.com:owner/repo.git" "meta_sync: scrub-hit $RQ/fr-xgit.md:1: email"
check $? "a longer user (xgit@github.com:) still exits 2: email (got: $FX_GOT)"
fx_refused fr-nocolon.md "write to git@github.com today" "meta_sync: scrub-hit $RQ/fr-nocolon.md:1: email"
check $? "a colon-less git@github.com (mailbox shape, not a remote) still exits 2: email (got: $FX_GOT)"
fx_refused fr-upper.md "remote GIT@GITHUB.COM:owner/repo" "meta_sync: scrub-hit $RQ/fr-upper.md:1: email"
check $? "an upper-case GIT@GITHUB.COM: is not the exact exemption and still exits 2: email (got: $FX_GOT)"
fx_refused fr-mixed.md "$(printf '%s\n' 'git@github.com:owner/repo.git' 'remote git@github.com:owner/repo.git, ask someone@example.org')" \
  "meta_sync: scrub-hit $RQ/fr-mixed.md:2: email"
check $? "a line holding a forge remote AND a real address still exits 2: email at line 2, past the exempt-only line 1 (got: $FX_GOT)"
fx_refused fr-slug.md "git clone git@github.com:evilcorp/secret-repo.git" "meta_sync: scrub-hit $RQ/fr-slug.md:-: forge_slug"
check $? "an unallowlisted slug after git@github.com: is still forge_slug, and the remote is not email (got: $FX_GOT)"
tip="$(br_tip)"; base_before="$(base_of B)"
ms B push
{ [ "$RC" -eq 2 ] && [ "$(br_tip)" = "$tip" ] && [ "$(base_of B)" = "$base_before" ] \
  && grep -qxF "meta_sync: scrub $RQ/fr-xgit.md: email" < <(printf '%s\n' "$OUT") \
  && grep -qxF "meta_sync: scrub $RQ/fr-mixed.md: email" < <(printf '%s\n' "$OUT"); }
check $? "push over the refusals exits 2 naming them, branch tip and meta-base unchanged (rc=$RC)"

echo "== 66. mutation control (xvii): a widened exemption must turn a refusal leg of (65) red =="
MUT_XVII="$TROOT/mutant-xvii"
if build_mutant "$MUT_XVII" "s/^EMAIL_FORGE_EXEMPT='git@/EMAIL_FORGE_EXEMPT='[a-z0-9._%+-]*git@/" "EMAIL_FORGE_EXEMPT='[a-z0-9._%+-]*git@"; then
  SCRIPT="$MUT_XVII/meta-sync.sh"
  if fx_refused fr-xgit.md "remote xgit@github.com:owner/repo.git" "meta_sync: scrub-hit $RQ/fr-xgit.md:1: email"; then
    no "mutation control (xvii) REFUTED: an any-user exemption still refused xgit@github.com: — leg 65 is not load-bearing"
  else
    ok "mutation control (xvii): an any-user exemption lets xgit@github.com: through (rc=$RC), so leg 65 turns red"
  fi
  SCRIPT="$SUT"
else
  no "mutation control (xvii): could not build the any-user mutant — control inconclusive"
fi
MUT_XVIIB="$TROOT/mutant-xvii-b"
if build_mutant "$MUT_XVIIB" "s/^EMAIL_FORGE_EXEMPT='\\(.*\\)):'\$/EMAIL_FORGE_EXEMPT='\\1):?'/" "bitbucket\\.org):?'"; then
  SCRIPT="$MUT_XVIIB/meta-sync.sh"
  if fx_refused fr-nocolon.md "write to git@github.com today" "meta_sync: scrub-hit $RQ/fr-nocolon.md:1: email"; then
    no "mutation control (xvii-b) REFUTED: an optional-colon exemption still refused a colon-less git@github.com — leg 65 is not load-bearing"
  else
    ok "mutation control (xvii-b): an optional-colon exemption lets a colon-less git@github.com through (rc=$RC), so leg 65 turns red"
  fi
  SCRIPT="$SUT"
else
  no "mutation control (xvii-b): could not build the optional-colon mutant — control inconclusive"
fi

