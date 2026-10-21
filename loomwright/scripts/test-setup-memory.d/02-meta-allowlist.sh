# ============================================================================
echo "== (ma) the tracked request file .agent/meta-allowlist.txt — it REQUESTS, only a gh id match GRANTS =="
# WHY: .supervisor/config.json is gitignored, so a fresh clone resolves the allowlist to the remote
# alone and refuses every pre-rename record. The tracked request file travels — so it must never
# GRANT on its own (the ledger collects records about OTHER repos; a granting committed list would
# let whoever controls the file publish them). Granted only when `gh api repos/<slug> --jq .id`
# equals origin's id. NO NETWORK: `gh` is a recording stub on PATH (every invocation appended to
# $MA_LOG), and the absent-gh legs run on a hermetic PATH of symlinks that has no gh at all.
MA_D="$(mkfix)"
mkdir -p "$MA_D/bin"
cat > "$MA_D/bin/gh" <<'GH'
#!/bin/sh
printf '%s\n' "$*" >> "$GH_STUB_LOG"
if [ -n "${GH_STUB_FAIL:-}" ]; then echo "gh: stub failure (not logged in)" >&2; exit 1; fi
# A HUNG gh: `exec` so the stub IS the sleep — the bound's kill reaches it, and a leaked process
# is findable by its unique duration.
if [ -n "${GH_STUB_HANG:-}" ]; then exec sleep "$GH_STUB_HANG"; fi
p="$(printf '%s' "$2" | tr 'A-Z' 'a-z')"
case "$p" in
  repos/acme/widget|repos/acme/old-name) echo 101 ;;   # old-name: the rename redirect, SAME id
  repos/stranger/elsewhere) echo 202 ;;                # a DIFFERENT repository
  *) echo "gh: HTTP 404: Not Found" >&2; exit 1 ;;
esac
GH
chmod +x "$MA_D/bin/gh"
MA_LOG="$MA_D/gh.log"
# A PATH with every tool setup-memory.sh's allowlist path uses EXCEPT gh (CI's ubuntu image and a
# Homebrew mac both ship a real gh in a directory that also holds git/awk, so dropping one
# directory is not enough): a hermetic dir of symlinks, as test-meta-sync.sh builds for no-jq.
MA_NOGH="$MA_D/nogh-bin"; mkdir -p "$MA_NOGH"
for t in bash sh git cat dirname sed awk mktemp rm mkdir tr sort grep env cksum date wc cut head \
         tail jq cp mv ls printf test true false; do
  tp="$(command -v "$t" 2>/dev/null)"
  case "$tp" in /*) ln -sf "$tp" "$MA_NOGH/$t" ;; esac
done
MA_NOGH_PATH="${HERMETIC_SHIM_DIR:+$HERMETIC_SHIM_DIR:}$MA_NOGH"
{ [ -z "$(PATH="$MA_NOGH_PATH" command -v gh)" ] && [ -n "$(PATH="$MA_NOGH_PATH" command -v git)" ]; } \
  || setup_fail "(ma) the no-gh PATH must have git and no gh"
MA_SUT="$MEM"
# ma_run <dir> [VAR=value ...] — `allowlist` on the gh-stub PATH, env allowlist scrubbed; sets
# MA_OUT (stdout), MA_ERR (stderr) and MA_CALLS (gh invocations, one per line).
ma_run() {
  local d="$1"; shift
  : > "$MA_LOG"
  env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST GH_STUB_LOG="$MA_LOG" PATH="$MA_D/bin:$PATH" "$@" \
    bash "$MA_SUT" --root "$d" allowlist > "$MA_D/out" 2> "$MA_D/err"
  MA_OUT="$(cat "$MA_D/out")"; MA_ERR="$(cat "$MA_D/err")"; MA_CALLS="$(cat "$MA_LOG")"
}
# ma_run_nogh <dir> — the same on the hermetic PATH with NO gh at all.
ma_run_nogh() {
  : > "$MA_LOG"
  env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST PATH="$MA_NOGH_PATH" "$MA_NOGH/bash" "$MA_SUT" --root "$1" allowlist \
    > "$MA_D/out" 2> "$MA_D/err"
  MA_OUT="$(cat "$MA_D/out")"; MA_ERR="$(cat "$MA_D/err")"; MA_CALLS="$(cat "$MA_LOG")"
}
# ma_stdout_is_list — 0 iff every stdout line is an owner/repo slug (no status text leaked in).
ma_stdout_is_list() {
  local l
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    printf '%s\n' "$l" | env LC_ALL=C grep -Eq '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$' || return 1
  done <<EOF_MA
$MA_OUT
EOF_MA
  return 0
}
ma_req() { mkdir -p "$1/.agent"; printf '%s\n' "${@:2}" > "$1/.agent/meta-allowlist.txt"; }
ma_ncalls() { [ -n "$MA_CALLS" ] && printf '%s\n' "$MA_CALLS" | wc -l | tr -d ' ' || echo 0; }

# (ma1) A9 — NO request file ⇒ ZERO gh calls on a GitHub-shaped origin.
MA1="$(newgit https://github.com/acme/widget.git)"
ma_run "$MA1"
{ [ "$MA_OUT" = "acme/widget" ] && [ -z "$MA_CALLS" ]; } \
  && ok "(ma1) A9: no request file ⇒ the remote alone and ZERO gh calls (lazy lookup)" \
  || no "(ma1) A9: no request file made gh calls or changed the list (out: $MA_OUT; gh: $MA_CALLS)"
# (ma2) A9 + A5 — a file holding only origin's own slug (any case), comments and blanks ⇒ ZERO calls.
MA2="$(newgit https://github.com/acme/widget.git)"
ma_req "$MA2" '# requested slugs' '' '   ' 'ACME/Widget' '  acme/widget  ' '# trailing comment'
ma_run "$MA2"
{ [ "$MA_OUT" = "acme/widget" ] && [ -z "$MA_CALLS" ]; } \
  && ok "(ma2) A9/A5: own slug (case-insensitive) + comments + blanks ⇒ granted with ZERO gh calls" \
  || no "(ma2) A9/A5: own-slug-only request file made gh calls or changed the list (out: $MA_OUT; gh: $MA_CALLS)"
hasF 'allowlist: granted ACME/Widget — current remote' "$MA_ERR" \
  && ok "(ma2) the own slug's grant is named on stderr" || no "(ma2) own-slug status missing (err: $MA_ERR)"
hasF '# source: default (current git remote)' "$MA_ERR" && ! hasF 'request file' "$(printf '%s\n' "$MA_ERR" | grep '^# source:')" \
  && ok "(ma2) the # source: line does not credit the request file when it contributed nothing" \
  || no "(ma2) wrong # source: line (err: $MA_ERR)"

# (ma3) THE GRANT AND THE REFUSAL — same-id slug granted, different-id slug ignored + named.
MA3="$(newgit https://github.com/acme/widget.git)"
ma_req "$MA3" '# request' 'acme/old-name' 'stranger/elsewhere'
ma_run "$MA3"
[ "$MA_OUT" = "$(printf 'acme/widget\nacme/old-name')" ] \
  && ok "(ma3) A1: the same-id (renamed) slug acme/old-name is GRANTED beside the remote" \
  || no "(ma3) A1: same-id slug not granted (out: $MA_OUT; err: $MA_ERR)"
# THE A2 assertion — the one the id-comparison mutant below must turn red.
ma3_a2() { ! hasF 'stranger/elsewhere' "$MA_OUT" && hasF 'allowlist: ignored stranger/elsewhere — not this repository' "$MA_ERR"; }
ma3_a2 && ok "(ma3) A2: the different-id slug is NOT granted and is named: 'allowlist: ignored stranger/elsewhere — not this repository'" \
  || no "(ma3) A2: different-id slug granted or not named (out: $MA_OUT; err: $MA_ERR)"
# A6 — stdout is the list and nothing else; the status lines are on stderr.
ma_stdout_is_list && ! hasF 'allowlist:' "$MA_OUT" \
  && ok "(ma3) A6: stdout stays one owner/repo per line — no status text leaked into the list" \
  || no "(ma3) A6: status text reached STDOUT, where meta-sync.sh/validate-entry.sh read it as entries (out: $MA_OUT)"
src_ma3="$(printf '%s\n' "$MA_ERR" | grep '^# source:')"
{ hasF 'default (current git remote)' "$src_ma3" && hasF '.agent/meta-allowlist.txt' "$src_ma3"; } \
  && ok "(ma3) A6: the # source: line names the request file AND keeps 'default (current git remote)'" \
  || no "(ma3) A6: # source: line wrong (got: $src_ma3)"
n_origin="$(printf '%s\n' "$MA_CALLS" | grep -c 'repos/acme/widget ' || true)"
{ [ "$n_origin" = "1" ] && [ "$(ma_ncalls)" = "3" ]; } \
  && ok "(ma3) origin's id looked up exactly ONCE per call (3 gh calls for 2 entries)" \
  || no "(ma3) gh call count wrong (origin lookups $n_origin; calls: $(printf '%s' "$MA_CALLS" | tr '\n' '|'))"
# The scrub consumer: filter-ledger (the same resolver meta-sync.sh's push scrub reads) refuses the
# different-id slug's record and keeps the granted old slug's record.
cat > "$MA3/ledger.jsonl" <<'LEDGER'
{"repo":"acme/old-name","number":1}
{"repo":"stranger/elsewhere","number":2}
LEDGER
ma3_led="$(env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST GH_STUB_LOG="$MA_LOG" PATH="$MA_D/bin:$PATH" bash "$MEM" --root "$MA3" filter-ledger --ledger "$MA3/ledger.jsonl" 2>/dev/null)"
if [ -z "$JQ" ]; then
  ok "(ma3) jq unavailable — the ledger-filter consumer leg is skipped (pass)"
else
  { ledger_has_repo "$ma3_led" "acme/old-name" && ! ledger_has_repo "$ma3_led" "stranger/elsewhere"; } \
    && ok "(ma3) A2: the ledger filter keeps the granted old slug's record and REFUSES the different-id slug's" \
    || no "(ma3) A2: ledger filter verdict wrong (kept: $ma3_led)"
fi

# (ma4) A3 — a FAILING gh grants NOTHING from the request file and says why.
ma_run "$MA3" GH_STUB_FAIL=1
{ [ "$MA_OUT" = "acme/widget" ] && hasF 'allowlist: ignored acme/old-name — gh could not resolve origin acme/widget' "$MA_ERR"; } \
  && ok "(ma4) A3: failing gh ⇒ no request entry granted (remote alone) and the reason is named" \
  || no "(ma4) A3: failing gh granted an entry or named no reason (out: $MA_OUT; err: $MA_ERR)"
# (ma5) A3 — an ABSENT gh grants nothing either, and says why.
ma_run_nogh "$MA3"
{ [ "$MA_OUT" = "acme/widget" ] && hasF 'allowlist: ignored acme/old-name — gh is not installed' "$MA_ERR"; } \
  && ok "(ma5) A3: absent gh ⇒ no request entry granted (remote alone) and the reason is named" \
  || no "(ma5) A3: absent gh granted an entry or named no reason (out: $MA_OUT; err: $MA_ERR)"

# (ma6) A4 + A3 — layers 1–3 win as before: the request file is NOT read and gh is NEVER called.
if [ -z "$JQ" ]; then
  ok "(ma6) jq unavailable — the config-layer legs are skipped (pass)"
else
  MA6="$(newgit https://github.com/acme/widget.git)"
  ma_req "$MA6" 'acme/old-name' 'stranger/elsewhere'
  mkdir -p "$MA6/.supervisor"; printf '{"setup_memory":{"repo_allowlist":["acme/widget","fixture-org/kept"]}}\n' > "$MA6/.supervisor/config.json"
  ma_run "$MA6"
  ma6_a4() { [ "$MA_OUT" = "$(printf 'acme/widget\nfixture-org/kept')" ] && [ -z "$MA_CALLS" ] && ! hasF 'allowlist:' "$MA_ERR"; }
  ma6_a4 && ok "(ma6) A4: a present config.json wins — the request file is not read and ZERO gh calls" \
    || no "(ma6) A4: config layer did not win cleanly (out: $MA_OUT; gh: $MA_CALLS; err: $MA_ERR)"
  ma_run_nogh "$MA6"
  [ "$MA_OUT" = "$(printf 'acme/widget\nfixture-org/kept')" ] \
    && ok "(ma6) A3: with gh absent, config.json entries are still granted" \
    || no "(ma6) A3: config entries lost when gh is absent (out: $MA_OUT)"
fi
ma_run "$MA3" LOOMWRIGHT_MEMORY_REPO_ALLOWLIST=acme/only
{ [ "$MA_OUT" = "acme/only" ] && [ -z "$MA_CALLS" ]; } \
  && ok "(ma6) A4: the env layer wins — request file not read, ZERO gh calls" \
  || no "(ma6) A4: env layer did not win cleanly (out: $MA_OUT; gh: $MA_CALLS)"
: > "$MA_LOG"
ma6_flag="$(env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST GH_STUB_LOG="$MA_LOG" PATH="$MA_D/bin:$PATH" bash "$MEM" --root "$MA3" --allow acme/flag allowlist 2>/dev/null)"
{ [ "$ma6_flag" = "acme/flag" ] && [ ! -s "$MA_LOG" ]; } \
  && ok "(ma6) A4: --allow wins — request file not read, ZERO gh calls" \
  || no "(ma6) A4: --allow layer did not win cleanly (out: $ma6_flag; gh: $(cat "$MA_LOG"))"

# (ma7) A5 — a malformed entry is NEVER passed to gh and is named as ignored.
MA7="$(newgit https://github.com/acme/widget.git)"
ma_req "$MA7" 'not-a-slug' 'a/b/c' '../x' 'owner/repo name' '$(touch pwned)/x' 'stranger/elsewhere'
ma_run "$MA7"
ma7_a5() {
  [ "$(ma_ncalls)" = "2" ] && hasF 'repos/acme/widget ' "$MA_CALLS" && hasF 'repos/stranger/elsewhere ' "$MA_CALLS" || return 1
  ! hasF 'not-a-slug' "$MA_CALLS" && ! hasF 'a/b/c' "$MA_CALLS" && ! hasF '../x' "$MA_CALLS" \
    && ! hasF 'repo name' "$MA_CALLS" && ! hasF 'pwned' "$MA_CALLS"
}
ma7_a5 && ok "(ma7) A5: malformed entries never reach gh (only origin + the well-formed entry were looked up)" \
  || no "(ma7) A5: a malformed entry reached gh (calls: $(printf '%s' "$MA_CALLS" | tr '\n' '|'))"
{ hasF 'allowlist: ignored not-a-slug — not an owner/repo slug' "$MA_ERR" && hasF 'allowlist: ignored a/b/c — not an owner/repo slug' "$MA_ERR" \
  && hasF 'allowlist: ignored ../x — not an owner/repo slug' "$MA_ERR" && [ "$MA_OUT" = "acme/widget" ] && [ ! -e "$MA7/pwned" ]; } \
  && ok "(ma7) A5: each malformed entry is named as ignored; none granted; nothing executed" \
  || no "(ma7) A5: malformed entries not named or granted (out: $MA_OUT; err: $MA_ERR)"

# (ma8) A5 — a filesystem-path origin grants NO request entry and makes NO gh call.
MA8="$(newgit /Users/someone/parent-dir/myrepo)"
ma_req "$MA8" 'acme/old-name'
ma_run "$MA8"
{ [ -z "$MA_OUT" ] && [ -z "$MA_CALLS" ] && hasF 'allowlist: ignored acme/old-name — origin has no owner/repo slug' "$MA_ERR"; } \
  && ok "(ma8) A5: a filesystem-path origin grants nothing, calls no gh, and says why" \
  || no "(ma8) A5: filesystem-path origin granted or called gh (out: $MA_OUT; gh: $MA_CALLS; err: $MA_ERR)"

# (ma9) a NON-github.com origin grants NOTHING and makes ZERO gh calls. `gh api` defaults to
# github.com, so for a GitLab / GHE origin it would compare two github.com NAMESAKES: the stub
# answers acme/widget and acme/old-name with the SAME id 101, which a host-blind check would grant.
MA9_OK=1; MA9_DETAIL=""
ma9_leg() {
  local u d
  MA9_OK=1; MA9_DETAIL=""
  for u in https://gitlab.com/acme/widget.git git@ghe.corp.example:acme/widget.git ssh://git@bitbucket.org/acme/widget.git; do
    d="$(newgit "$u")"
    ma_req "$d" 'acme/old-name'
    ma_run "$d"
    if ! { [ "$MA_OUT" = "acme/widget" ] && [ -z "$MA_CALLS" ] \
           && hasF 'allowlist: ignored acme/old-name — origin is not on github.com' "$MA_ERR"; }; then
      MA9_OK=0; MA9_DETAIL="$MA9_DETAIL [$u: out=$(printf '%s' "$MA_OUT" | tr '\n' ' ') gh=$(printf '%s' "$MA_CALLS" | tr '\n' '|')]"
    fi
  done
  [ "$MA9_OK" = 1 ]
}
ma9_leg && ok "(ma9) non-github.com origins (https gitlab, scp GHE, ssh:// bitbucket) grant nothing, call no gh, and say why" \
  || no "(ma9) a non-github.com origin granted a same-id namesake or called gh:$MA9_DETAIL"
# ... and the host match is case-insensitive and accepts the scp / ssh:// github.com forms.
MA9G=1
for u in https://GitHub.COM/acme/widget.git git@github.com:acme/widget.git ssh://git@github.com/acme/widget.git; do
  d="$(newgit "$u")"; ma_req "$d" 'acme/old-name'; ma_run "$d"
  [ "$MA_OUT" = "$(printf 'acme/widget\nacme/old-name')" ] || MA9G=0
done
[ "$MA9G" = 1 ] && ok "(ma9) github.com origins in https (any case), scp and ssh:// form still grant the same-id slug" \
  || no "(ma9) the host check rejected a github.com origin form (last out: $MA_OUT; err: $MA_ERR)"

# (ma10) a HUNG gh is BOUNDED: killed after LOOMWRIGHT_ALLOWLIST_GH_TIMEOUT seconds, treated as gh
# failing (nothing granted, reason named), no further gh call after the overrun, no sleeping child
# left behind, and nothing written to TMPDIR (the runner is file-free — `allowlist` writes nothing).
MA10="$(newgit https://github.com/acme/widget.git)"
ma_req "$MA10" 'acme/old-name' 'stranger/elsewhere'
MA10_TMP="$MA_D/ma10-tmpdir"; mkdir -p "$MA10_TMP"
# A per-run duration (7.<pid>) and an anchored pattern, so a concurrent run of this suite in another
# checkout can never be mistaken for a leak here.
MA10_HANG="7.$$"
MA10_PAT="^sleep 7\\.$$\$"
ma10_leg() {
  local t0 t1
  t0="$(date +%s)"
  ma_run "$MA10" LOOMWRIGHT_ALLOWLIST_GH_TIMEOUT=1 GH_STUB_HANG="$MA10_HANG" TMPDIR="$MA10_TMP"
  t1="$(date +%s)"
  MA10_ELAPSED=$((t1 - t0))
  [ "$MA_OUT" = "acme/widget" ] && [ "$MA10_ELAPSED" -lt 5 ] && [ "$(ma_ncalls)" = "1" ] \
    && hasF 'allowlist: ignored acme/old-name — gh timed out after 1s resolving origin acme/widget' "$MA_ERR" \
    && hasF 'allowlist: ignored stranger/elsewhere — gh timed out after 1s resolving origin' "$MA_ERR"
}
MA10_ELAPSED=""
ma10_leg && ok "(ma10) a hung gh is killed at the 1s bound (${MA10_ELAPSED}s total), grants nothing, names why, and is not asked again" \
  || no "(ma10) a hung gh was not bounded or granted something (elapsed ${MA10_ELAPSED}s; out: $MA_OUT; gh: $(printf '%s' "$MA_CALLS" | tr '\n' '|'); err: $MA_ERR)"
{ ! pgrep -f "$MA10_PAT" >/dev/null 2>&1 && [ -z "$(ls -A "$MA10_TMP" 2>/dev/null)" ]; } \
  && ok "(ma10) the killed gh was reaped (no 'sleep $MA10_HANG' left running) and no temp file was left in TMPDIR" \
  || no "(ma10) the bounded runner leaked a process or a temp file (procs: $(pgrep -f "$MA10_PAT" | tr '\n' ' '); tmp: $(ls -A "$MA10_TMP" 2>/dev/null | tr '\n' ' '))"
pkill -f "$MA10_PAT" 2>/dev/null || true
# A hang on an ENTRY lookup (origin answers) is bounded too, and stops further lookups.
# The bound covers EVERY gh call, so the answering origin stub must finish inside it too: at 1s a
# loaded host (load ~12, wave 8 of automate-2026-10-15-163325) killed the ORIGIN lookup first and the
# leg read red. 3s keeps the answering call well inside the bound and the hang (7.<pid>s) well past it.
cat > "$MA_D/bin-entryhang-gh" <<'GH'
#!/bin/sh
printf '%s\n' "$*" >> "$GH_STUB_LOG"
case "$2" in
  repos/acme/widget) echo 101 ;;
  *) exec sleep "$GH_STUB_HANG" ;;
esac
GH
mkdir -p "$MA_D/bin-entryhang"; mv "$MA_D/bin-entryhang-gh" "$MA_D/bin-entryhang/gh"; chmod +x "$MA_D/bin-entryhang/gh"
: > "$MA_LOG"
env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST GH_STUB_LOG="$MA_LOG" GH_STUB_HANG="$MA10_HANG" LOOMWRIGHT_ALLOWLIST_GH_TIMEOUT=3 \
  TMPDIR="$MA10_TMP" PATH="$MA_D/bin-entryhang:$PATH" bash "$MEM" --root "$MA10" allowlist > "$MA_D/out" 2> "$MA_D/err"
MA_OUT="$(cat "$MA_D/out")"; MA_ERR="$(cat "$MA_D/err")"; MA_CALLS="$(cat "$MA_LOG")"
{ [ "$MA_OUT" = "acme/widget" ] && [ "$(ma_ncalls)" = "2" ] \
  && hasF 'allowlist: ignored acme/old-name — gh timed out after 3s' "$MA_ERR" \
  && hasF 'allowlist: ignored stranger/elsewhere — gh timed out after 3s' "$MA_ERR" \
  && ! pgrep -f "$MA10_PAT" >/dev/null 2>&1 && [ -z "$(ls -A "$MA10_TMP" 2>/dev/null)" ]; } \
  && ok "(ma10) a hung ENTRY lookup is bounded, grants nothing, and stops further gh calls (2 calls: origin + one entry)" \
  || no "(ma10) a hung entry lookup was not bounded cleanly (out: $MA_OUT; gh: $(printf '%s' "$MA_CALLS" | tr '\n' '|'); err: $MA_ERR)"
pkill -f "$MA10_PAT" 2>/dev/null || true

# (ma13) the bound holds on the PIPE, not just gh's pid: anything gh forks inherits the capture
# pipe, so a child left behind must be killed at the bound too. (a) gh dies on TERM but its child
# IGNORES TERM and is re-parented once gh is reaped; (b) gh EXITS 0 at once, printing the matching
# id, and leaves a child holding the pipe. Both must finish inside the bound + the 1s TERM grace,
# grant nothing (a gh whose group outlives the bound is a timeout, its output discarded) and leave
# no child running. Per-run sleep durations (8.1<pid> / 8.2<pid>) are the leak markers.
MA13="$(newgit https://github.com/acme/widget.git)"
ma_req "$MA13" 'acme/old-name'
MA13A_HANG="8.1$$"; MA13A_PAT="^sleep 8\\.1$$\$"
MA13B_HANG="8.2$$"; MA13B_PAT="^sleep 8\\.2$$\$"
mkdir -p "$MA_D/bin-orphan-term" "$MA_D/bin-orphan-exit0"
cat > "$MA_D/bin-orphan-term/gh" <<'GH'
#!/bin/sh
printf '%s\n' "$*" >> "$GH_STUB_LOG"
( trap '' TERM; exec sleep "$GH_STUB_HANG" ) &
wait
GH
cat > "$MA_D/bin-orphan-exit0/gh" <<'GH'
#!/bin/sh
printf '%s\n' "$*" >> "$GH_STUB_LOG"
( sleep "$GH_STUB_HANG" ) &
echo 101
exit 0
GH
chmod +x "$MA_D/bin-orphan-term/gh" "$MA_D/bin-orphan-exit0/gh"
# ma13_leg <bin-dir> <hang> <pattern> — 0 iff bounded (< 5s), nothing granted, timeout named, one
# gh call, no child left. Sets MA13_ELAPSED.
ma13_leg() {
  local t0 t1
  : > "$MA_LOG"
  t0="$(date +%s)"
  env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST GH_STUB_LOG="$MA_LOG" GH_STUB_HANG="$2" LOOMWRIGHT_ALLOWLIST_GH_TIMEOUT=1 \
    TMPDIR="$MA10_TMP" PATH="$1:$PATH" bash "$MA_SUT" --root "$MA13" allowlist > "$MA_D/out" 2> "$MA_D/err"
  t1="$(date +%s)"
  MA13_ELAPSED=$((t1 - t0))
  MA_OUT="$(cat "$MA_D/out")"; MA_ERR="$(cat "$MA_D/err")"; MA_CALLS="$(cat "$MA_LOG")"
  [ "$MA_OUT" = "acme/widget" ] && [ "$MA13_ELAPSED" -lt 5 ] && [ "$(ma_ncalls)" = "1" ] \
    && hasF 'allowlist: ignored acme/old-name — gh timed out after 1s resolving origin acme/widget' "$MA_ERR" \
    && ! hasF 'Terminated' "$MA_ERR" && ! pgrep -f "$3" >/dev/null 2>&1 \
    && [ -z "$(ls -A "$MA10_TMP" 2>/dev/null)" ]
}
MA13_ELAPSED=""
ma13_leg "$MA_D/bin-orphan-term" "$MA13A_HANG" "$MA13A_PAT" \
  && ok "(ma13) a TERM-ignoring child of a killed gh is killed with it: bounded (${MA13_ELAPSED}s), nothing granted, no 'sleep $MA13A_HANG' left" \
  || no "(ma13) a TERM-ignoring child outlived the bound or leaked (elapsed ${MA13_ELAPSED}s; out: $MA_OUT; procs: $(pgrep -f "$MA13A_PAT" | tr '\n' ' '); err: $MA_ERR)"
pkill -f "$MA13A_PAT" 2>/dev/null || true
ma13_leg "$MA_D/bin-orphan-exit0" "$MA13B_HANG" "$MA13B_PAT" \
  && ok "(ma13) a gh that exits 0 leaving a child on the pipe is bounded (${MA13_ELAPSED}s), counted as a timeout (its id not granted), no 'sleep $MA13B_HANG' left" \
  || no "(ma13) an exit-0 gh's lingering child was not bounded or its id was granted (elapsed ${MA13_ELAPSED}s; out: $MA_OUT; procs: $(pgrep -f "$MA13B_PAT" | tr '\n' ' '); err: $MA_ERR)"
pkill -f "$MA13B_PAT" 2>/dev/null || true

# (ma11) the WORK the request file drives is CAPPED, not just each call: 25 non-own entries (the
# first one the same-id old slug) ⇒ at most cap + 1 = 21 gh calls (origin + 20 entries), the same-id
# entry still granted in file order, and each of the 5 entries past the cap named and never passed to gh.
MA11="$(newgit https://github.com/acme/widget.git)"
MA11_ENTRIES="acme/old-name"; i=2
while [ "$i" -le 25 ]; do MA11_ENTRIES="$MA11_ENTRIES
fill-org/repo-$i"; i=$((i + 1)); done
mkdir -p "$MA11/.agent"; printf '%s\n' "$MA11_ENTRIES" > "$MA11/.agent/meta-allowlist.txt"
ma11_leg() {
  local j
  ma_run "$MA11"
  [ "$(ma_ncalls)" -le 21 ] && [ "$MA_OUT" = "$(printf 'acme/widget\nacme/old-name')" ] || return 1
  [ "$(printf '%s\n' "$MA_ERR" | grep -c 'over the 20-entry cap')" = "5" ] || return 1
  for j in 21 22 23 24 25; do
    hasF "allowlist: ignored fill-org/repo-$j — over the 20-entry cap" "$MA_ERR" || return 1
    ! hasF "repos/fill-org/repo-$j " "$MA_CALLS" || return 1
  done
  return 0
}
ma11_leg && ok "(ma11) 25 request entries ⇒ $(ma_ncalls) gh calls (cap 20 + origin), same-id slug still granted, the 5 over-cap entries named and never passed to gh" \
  || no "(ma11) the request file drove uncapped gh work or mis-named the over-cap entries (calls: $(ma_ncalls); out: $MA_OUT; err: $(printf '%s' "$MA_ERR" | tail -n 6 | tr '\n' '|'))"
# ... the env override is clamped: 0 / junk fall back to the default, a huge value to the ceiling.
ma_run "$MA11" LOOMWRIGHT_ALLOWLIST_MAX_ENTRIES=3
{ [ "$(ma_ncalls)" = "4" ] && hasF 'allowlist: ignored fill-org/repo-5 — over the 3-entry cap' "$MA_ERR"; } \
  && ok "(ma11) LOOMWRIGHT_ALLOWLIST_MAX_ENTRIES=3 ⇒ 4 gh calls, entry 5 named over the 3-entry cap" \
  || no "(ma11) the cap override was not honoured (calls: $(ma_ncalls); err: $(printf '%s' "$MA_ERR" | tail -n 3 | tr '\n' '|'))"
ma_run "$MA11" LOOMWRIGHT_ALLOWLIST_MAX_ENTRIES=999999999999999999999999
{ [ "$(ma_ncalls)" = "26" ] && ! hasF 'entry cap' "$MA_ERR"; } \
  && ok "(ma11) an oversized override is clamped to the ceiling (100), not overflowed: all 25 entries compared" \
  || no "(ma11) oversized cap override mishandled (calls: $(ma_ncalls); err: $(printf '%s' "$MA_ERR" | tail -n 3 | tr '\n' '|'))"
# ... and READING is capped too: an entry past line 200 is never read (zero gh calls), named once.
MA12="$(newgit https://github.com/acme/widget.git)"
mkdir -p "$MA12/.agent"
awk 'BEGIN { for (i = 1; i <= 200; i++) print "# filler " i; print "acme/old-name" }' > "$MA12/.agent/meta-allowlist.txt"
ma_run "$MA12"
{ [ "$MA_OUT" = "acme/widget" ] && [ -z "$MA_CALLS" ] \
  && [ "$(printf '%s\n' "$MA_ERR" | grep -c 'allowlist: stopped reading .agent/meta-allowlist.txt after 200 lines')" = "1" ]; } \
  && ok "(ma11) a line past the 200-line read cap is never read or passed to gh, and the stop is named once" \
  || no "(ma11) the read cap did not hold (out: $MA_OUT; gh: $MA_CALLS; err: $(printf '%s' "$MA_ERR" | tail -n 2 | tr '\n' '|'))"

# (ma14) ONE origin read per resolution, ONE parse for slug AND host. A git shim on PATH logs every
# `remote get-url` and execs the real git. Each URL form must resolve the slug (acme/widget), gate
# on the host it came from (github.com forms grant the same-id acme/old-name; a scheme-less gitlab
# origin grants nothing with zero gh calls), and read origin's URL EXACTLY ONCE — the request file
# needs both slug and host, so two parsers would read twice.
MA_GITC="$MA_D/bin-gitcount"; mkdir -p "$MA_GITC"
MA_REAL_GIT="$(command -v git)"
printf '#!/bin/sh\ncase " $* " in *" remote get-url "*) printf "%%s\\n" "$*" >> "$GIT_COUNT_LOG" ;; esac\nexec "%s" "$@"\n' \
  "$MA_REAL_GIT" > "$MA_GITC/git"
chmod +x "$MA_GITC/git"
MA_GITLOG="$MA_D/git-count.log"
MA14_DETAIL=""
ma14_leg() {
  local u d want n
  MA14_DETAIL=""
  for u in https://github.com/acme/widget.git ssh://git@github.com:22/acme/widget.git git@github.com:acme/widget.git \
           github.com/acme/widget https://user:tok@GitHub.com:443/acme/widget.git gitlab.com/acme/widget; do
    d="$(newgit "$u")"; ma_req "$d" 'acme/old-name'
    : > "$MA_GITLOG"
    ma_run "$d" PATH="$MA_GITC:$MA_D/bin:$PATH" GIT_COUNT_LOG="$MA_GITLOG"
    n="$(grep -c 'remote get-url' "$MA_GITLOG" 2>/dev/null || true)"
    case "$u" in
      gitlab.com/*) want="acme/widget"
        { [ -z "$MA_CALLS" ] && hasF 'allowlist: ignored acme/old-name — origin is not on github.com' "$MA_ERR"; } \
          || MA14_DETAIL="$MA14_DETAIL [$u: host gate wrong gh=$(printf '%s' "$MA_CALLS" | tr '\n' '|')]" ;;
      *) want="$(printf 'acme/widget\nacme/old-name')" ;;
    esac
    [ "$MA_OUT" = "$want" ] || MA14_DETAIL="$MA14_DETAIL [$u: out=$(printf '%s' "$MA_OUT" | tr '\n' ' ')]"
    [ "$n" = "1" ] || MA14_DETAIL="$MA14_DETAIL [$u: $n origin reads]"
  done
  [ -z "$MA14_DETAIL" ]
}
ma14_leg && ok "(ma14) https / ssh:// / scp / scheme-less / userinfo+port origins: slug and host agree, and origin is read EXACTLY ONCE per resolution" \
  || no "(ma14) slug/host disagreed or origin was read more than once:$MA14_DETAIL"

# (ma15) a request file that EXISTS but cannot be read (mode 000, or a directory at that path) is
# NAMED on stderr and grants nothing; an ABSENT file stays silent (ma1's fixture, re-run).
MA15_DETAIL=""
ma15_leg() {
  local d
  MA15_DETAIL=""
  d="$(newgit https://github.com/acme/widget.git)"; ma_req "$d" 'acme/old-name'; chmod 000 "$d/.agent/meta-allowlist.txt" \
    || setup_fail "(ma15) chmod 000 failed on $d/.agent/meta-allowlist.txt"
  if [ -r "$d/.agent/meta-allowlist.txt" ]; then
    MA15_ROOT=1   # running as root: mode 000 is still readable, so only the directory case is meaningful
  else
    ma_run "$d"
    { [ "$MA_OUT" = "acme/widget" ] && [ -z "$MA_CALLS" ] \
      && hasF 'allowlist: ignored .agent/meta-allowlist.txt — not readable' "$MA_ERR"; } || MA15_DETAIL="$MA15_DETAIL [mode 000: out=$MA_OUT err=$MA_ERR]"
  fi
  chmod 600 "$d/.agent/meta-allowlist.txt"
  d="$(newgit https://github.com/acme/widget.git)"; mkdir -p "$d/.agent/meta-allowlist.txt"
  ma_run "$d"
  { [ "$MA_OUT" = "acme/widget" ] && [ -z "$MA_CALLS" ] \
    && hasF 'allowlist: ignored .agent/meta-allowlist.txt — not readable' "$MA_ERR"; } || MA15_DETAIL="$MA15_DETAIL [directory: out=$MA_OUT err=$MA_ERR]"
  ma_run "$MA1"
  hasF 'not readable' "$MA_ERR" && MA15_DETAIL="$MA15_DETAIL [absent file was named: $MA_ERR]"
  [ -z "$MA15_DETAIL" ]
}
MA15_ROOT=0
ma15_leg && ok "(ma15) an unreadable request file (mode 000$([ "$MA15_ROOT" = 1 ] && printf ' skipped — root'), a directory) is named on stderr and grants nothing; an absent one stays silent" \
  || no "(ma15) an unreadable request file was skipped silently or granted something:$MA15_DETAIL"

# Mutation controls — each gated on the mutant being NON-EMPTY, DIFFERENT from the original and
# `bash -n`-clean (an unapplied or broken mutant would otherwise "pass" silently).
# ma_mutant <name> <sed-expr> → prints the mutant path, status 1 when the gate fails.
ma_mutant() {
  local m="$MA_D/mut-$1.sh"
  sed -e "$2" "$MEMB" > "$m" 2>/dev/null || return 1
  [ -s "$m" ] && ! cmp -s "$MEMB" "$m" && bash -n "$m" 2>/dev/null || return 1
  printf '%s' "$m"
}
# ma_mutant_awk <name> <exact-line> <line-to-insert-before-it>
ma_mutant_awk() {
  local m="$MA_D/mut-$1.sh"
  awk -v t="$2" -v ins="$3" '$0 == t { print ins } { print }' "$MEMB" > "$m" 2>/dev/null || return 1
  [ -s "$m" ] && ! cmp -s "$MEMB" "$m" && bash -n "$m" 2>/dev/null || return 1
  printf '%s' "$m"
}
# The A3 / A5 sed programs, read from quoted heredocs so no shell quoting touches them (`read -d ''`,
# not `$(cat <<…)`: bash 3.2 mis-parses a heredoc holding an unbalanced `)` inside `$( )`).
MA_SED_A3=""; IFS= read -r -d '' MA_SED_A3 <<'SED'
s/if \[ "\$origin_state" != "ok" \]; then/if false; then/
s/^      ''|\*\[!0-9\]\*)$/      __mutant_never__)/
SED
MA_SED_A5=""; IFS= read -r -d '' MA_SED_A5 <<'SED'
s/^    if ! printf /    if false \&\& printf /
s@^    case "/\$e/" in \*/\./\*|\*/\.\./\*)$@    case "/$e/" in __mutant_never__)@
SED
# (A2) the id comparison removed ⇒ every well-formed entry granted ⇒ the A2 leg must turn red.
if M="$(ma_mutant a2 's/if \[ "\$id" = "\$origin_id" \]; then/if true; then/')"; then
  MA_SUT="$M"; ma_run "$MA3"; MA_SUT="$MEM"
  ma3_a2 && no "(ma-mut A2) REFUTED: with the id comparison removed the A2 leg still passes — it is not load-bearing" \
    || ok "(ma-mut A2) removing the id comparison grants stranger/elsewhere, so the A2 leg turns red"
else no "(ma-mut A2) could not build the mutant (empty, unchanged or bash -n failed) — inconclusive"; fi
# (A3) the gh-failure guards dropped ⇒ "" = "" grants on a failing gh ⇒ (ma4) must turn red.
if M="$(ma_mutant a3 "$MA_SED_A3")"; then
  MA_SUT="$M"; ma_run "$MA3" GH_STUB_FAIL=1; MA_SUT="$MEM"
  [ "$MA_OUT" = "acme/widget" ] && no "(ma-mut A3) REFUTED: with the failure guards dropped a failing gh still grants nothing — (ma4) is not load-bearing" \
    || ok "(ma-mut A3) dropping the gh-failure guards grants on a failing gh, so (ma4) turns red (out: $(printf '%s' "$MA_OUT" | tr '\n' ' '))"
else no "(ma-mut A3) could not build the mutant — inconclusive"; fi
# (A6) the `>&2` dropped from the 'not this repository' line ⇒ (ma3)'s stdout-is-the-list leg red.
if M="$(ma_mutant a6 's/\(echo "allowlist: ignored \$e — not this repository"\) >&2/\1/')"; then
  MA_SUT="$M"; ma_run "$MA3"; MA_SUT="$MEM"
  ma_stdout_is_list && no "(ma-mut A6) REFUTED: status on stdout still reads as a clean list" \
    || ok "(ma-mut A6) a status line on stdout is caught by the A6 leg"
else no "(ma-mut A6) could not build the mutant — inconclusive"; fi
# (A5) the owner/repo shape check dropped ⇒ malformed entries reach gh ⇒ (ma7) red.
if M="$(ma_mutant a5 "$MA_SED_A5")"; then
  MA_SUT="$M"; ma_run "$MA7"; MA_SUT="$MEM"
  ma7_a5 && no "(ma-mut A5) REFUTED: without the shape check malformed entries still never reach gh" \
    || ok "(ma-mut A5) without the shape check a malformed entry reaches gh, so (ma7) turns red"
else no "(ma-mut A5) could not build the mutant — inconclusive"; fi
# (A9) origin's id looked up EAGERLY at the top of the layer ⇒ (ma1)'s zero-call leg red.
if M="$(ma_mutant_awk a9 '  [ -f "$f" ] && [ -r "$f" ] || return 0' '  [ -n "$own" ] && gh api "repos/$own" --jq .id </dev/null >/dev/null 2>&1')"; then
  MA_SUT="$M"; ma_run "$MA1"; MA_SUT="$MEM"
  [ -z "$MA_CALLS" ] && no "(ma-mut A9) REFUTED: an eager origin lookup still made zero gh calls" \
    || ok "(ma-mut A9) an eager origin lookup makes a gh call with no request file, so (ma1) turns red"
else no "(ma-mut A9) could not build the mutant — inconclusive"; fi
# (HOST) the github.com host check dropped ⇒ a GitLab/GHE origin compares github.com namesakes and
# grants acme/old-name ⇒ (ma9) must turn red.
if M="$(ma_mutant host 's/^      elif \[ "\$ORIGIN_HOST" != "github.com" \]; then$/      elif false; then/')"; then
  MA_SUT="$M"; ma9_leg; MA9_RC=$?; MA_SUT="$MEM"
  [ "$MA9_RC" -eq 0 ] && no "(ma-mut HOST) REFUTED: without the host check a non-github.com origin still grants nothing — (ma9) is not load-bearing" \
    || ok "(ma-mut HOST) dropping the github.com host check grants a namesake for a non-github origin, so (ma9) turns red"
else no "(ma-mut HOST) could not build the mutant — inconclusive"; fi
# (ONE-READ) the host gate re-resolves origin lazily (a second `git remote get-url`) ⇒ (ma14) red.
if M="$(ma_mutant oneread 's/^      elif \[ "\$ORIGIN_HOST" != "github.com" \]; then$/      elif resolve_origin; [ "$ORIGIN_HOST" != "github.com" ]; then/')"; then
  MA_SUT="$M"; ma14_leg; MA14_RC=$?; MA_SUT="$MEM"
  [ "$MA14_RC" -eq 0 ] && no "(ma-mut ONE-READ) REFUTED: a second origin read still counted as one — (ma14) is not load-bearing" \
    || ok "(ma-mut ONE-READ) re-reading origin for the host gate makes 2 reads, so (ma14) turns red"
else no "(ma-mut ONE-READ) could not build the mutant — inconclusive"; fi
# (UNREADABLE) the unreadable-file status line dropped ⇒ the skip is silent again ⇒ (ma15) red.
if M="$(ma_mutant unreadable 's/^  if \[ -e "\$f" \] && ! .*; then$/  if false; then/')"; then
  MA_SUT="$M"; ma15_leg; MA15_RC=$?; MA_SUT="$MEM"
  [ "$MA15_RC" -eq 0 ] && no "(ma-mut UNREADABLE) REFUTED: without the status line an unreadable request file is still named — (ma15) is not load-bearing" \
    || ok "(ma-mut UNREADABLE) dropping the status line skips an unreadable request file silently, so (ma15) turns red"
else no "(ma-mut UNREADABLE) could not build the mutant — inconclusive"; fi
# (BOUND) the overrun check dropped ⇒ the runner waits out the hung gh ⇒ (ma10)'s bound leg red.
if M="$(ma_mutant bound 's/^          if \[ "\$ticks" -ge "\$max" \]; then$/          if false; then/')"; then
  MA_SUT="$M"; ma10_leg; MA10_RC=$?; MA_SUT="$MEM"
  pkill -f "$MA10_PAT" 2>/dev/null || true
  [ "$MA10_RC" -eq 0 ] && no "(ma-mut BOUND) REFUTED: without the overrun check the hung gh still finished inside the bound — (ma10) is not load-bearing" \
    || ok "(ma-mut BOUND) without the overrun check the hung gh is waited out (${MA10_ELAPSED}s), so (ma10) turns red"
else no "(ma-mut BOUND) could not build the mutant — inconclusive"; fi
# (GROUP-KILL) TERM/KILL sent to gh's pid instead of its group ⇒ the TERM-ignoring child survives
# and holds the pipe ⇒ (ma13)'s (a) leg red.
if M="$(ma_mutant groupkill 's/kill -TERM -- "-\$gpid" 2>\/dev\/null$/kill -TERM "$gpid" 2>\/dev\/null/;s/kill -KILL -- "-\$gpid" 2>\/dev\/null$/kill -KILL "$gpid" 2>\/dev\/null/')"; then
  MA_SUT="$M"; ma13_leg "$MA_D/bin-orphan-term" "$MA13A_HANG" "$MA13A_PAT"; MA13_RC=$?; MA_SUT="$MEM"
  pkill -f "$MA13A_PAT" 2>/dev/null || true
  [ "$MA13_RC" -eq 0 ] && no "(ma-mut GROUP-KILL) REFUTED: signalling gh's pid alone still bounded the TERM-ignoring child — (ma13a) is not load-bearing" \
    || ok "(ma-mut GROUP-KILL) signalling gh's pid instead of its group leaves the child on the pipe (${MA13_ELAPSED}s), so (ma13a) turns red"
else no "(ma-mut GROUP-KILL) could not build the mutant — inconclusive"; fi
# (GROUP-POLL) the watchdog polls gh's pid instead of its group ⇒ it stops when gh exits 0 and
# nothing bounds the lingering child ⇒ (ma13)'s (b) leg red.
if M="$(ma_mutant grouppoll 's/^        while kill -0 -- "-\$gpid" 2>\/dev\/null; do$/        while kill -0 "$gpid" 2>\/dev\/null; do/')"; then
  MA_SUT="$M"; ma13_leg "$MA_D/bin-orphan-exit0" "$MA13B_HANG" "$MA13B_PAT"; MA13_RC=$?; MA_SUT="$MEM"
  pkill -f "$MA13B_PAT" 2>/dev/null || true
  [ "$MA13_RC" -eq 0 ] && no "(ma-mut GROUP-POLL) REFUTED: polling gh's pid alone still bounded the exit-0 gh's child — (ma13b) is not load-bearing" \
    || ok "(ma-mut GROUP-POLL) polling gh's pid instead of its group stops at gh's exit and the child holds the pipe (${MA13_ELAPSED}s), so (ma13b) turns red"
else no "(ma-mut GROUP-POLL) could not build the mutant — inconclusive"; fi
# (CAP) the comparison cap dropped ⇒ every entry reaches gh ⇒ (ma11)'s cap leg red.
if M="$(ma_mutant cap 's/^    if \[ "\$compared" -ge "\$cap" \]; then$/    if false; then/')"; then
  MA_SUT="$M"; ma11_leg; MA11_RC=$?; MA_SUT="$MEM"
  [ "$MA11_RC" -eq 0 ] && no "(ma-mut CAP) REFUTED: without the cap 25 entries still made at most cap+1 gh calls — (ma11) is not load-bearing" \
    || ok "(ma-mut CAP) without the cap every entry reaches gh ($(ma_ncalls) calls), so (ma11) turns red"
else no "(ma-mut CAP) could not build the mutant — inconclusive"; fi
# (A4) the request-file layer moved ABOVE the config layer ⇒ (ma6)'s config-wins leg red.
if [ -n "$JQ" ]; then
  if M="$(ma_mutant_awk a4 '  if [ -z "$out" ] && command -v jq >/dev/null 2>&1 && [ -f "$CFG" ]; then' '  [ -z "$out" ] && out="$(meta_allowlist_grants "$(remote_slug)")"')"; then
    MA_SUT="$M"; ma_run "$MA6"; MA_SUT="$MEM"
    ma6_a4 && no "(ma-mut A4) REFUTED: with the request layer above config the A4 leg still passes" \
      || ok "(ma-mut A4) moving the request layer above config reads it and calls gh, so (ma6) turns red"
  else no "(ma-mut A4) could not build the mutant — inconclusive"; fi
fi

