#!/usr/bin/env bash
# test-hermetic-egress.sh — the hermeticity PROBE for hermetic-test-env.sh.
#
# Re-creates the dangerous environment an owner's terminal hands every test — LOOMWRIGHT_WEBHOOK_URL
# and LOOMWRIGHT_TELEMETRY_REPO exported, the real OS notifiers on PATH — INSIDE a sandbox, then runs
# the known leak sites and asserts nothing escapes:
#   - a local TCP listener stands in for the ntfy host (LOOMWRIGHT_WEBHOOK_URL=http://127.0.0.1:<port>);
#   - OUTER recording osascript / notify-send / terminal-notifier / gh shims stand in for the real ones;
#   - every leak site runs under a sandbox HOME (never the real one).
# Leak sites:
#   (D) dispatch-pr-review.sh's real launch whose runner dies without a REVIEW_HEAL_RESULT — the
#       minimal `run_real` path test-dispatch-pr-review.sh case 37 exercises. Its detached trap child
#       fires notify-desktop.sh + send-webhook.sh --gate-type drain_died ASYNCHRONOUSLY, so the probe
#       polls for the `.died` marker and then for that detached child to exit before reading anything.
#   (P) test-propose-from-verify.sh run ALONE (its AC9 used to stage the REAL notify-desktop.sh).
#   (N) notify-desktop.sh fired directly (see mutant (iii) below for why (D) cannot show the banner).
#   (T) send-telemetry-core.sh non-dry-run with consent granted but no repo in the user-scope entry, so
#       only LOOMWRIGHT_TELEMETRY_REPO could route it to `gh issue create`.
# Mutation controls (AC6) — one sed-built mutant of the helper per layer, because the curl stub masks
# the unset layer. Each runs in a subshell that first strips the real helper's shim dir from PATH and
# unsets its markers, then sets the dangerous env + a PRIVATE HERMETIC_EGRESS_LOG, then sources the
# MUTANT and drives (D) directly — never a whole test file, which would re-source the real helper:
#   (i)   unset line AND curl/wget stubs removed  => the listener records hits;
#   (ii)  only the unset line removed             => zero listener hits, but the private egress log
#                                                    records a curl call naming the listener URL
#                                                    (and (T) reaches the outer gh shim);
#   (iii) notifier stubs AND the notifications=0 export removed => the OUTER notifier shim records
#         the banner from leak site (N) — so the unmutated "outer notifier shim is silent" assertions
#         are evidence, not just a regression guard.
# (N) is notify-desktop.sh fired directly with a drain_died payload from a sandbox cwd — the notifier
# layer on its own. (D) cannot serve as mutant (iii)'s observable: its trap child runs the notifier
# from inside the worktree it has just removed, so notify-desktop.sh's log redirect fails and the
# detached notifier never starts, with or without the helper.
# Every mutant is gated: non-empty, differs from the original, `bash -n`, and the specific override
# verifiably injected (with the original as the positive control that the pattern matched).
# Lifecycle arm:
#   (R)  TMPDIR points at a missing dir => the helper's one retry under /tmp still builds the shim
#        dir; mutant (Rm) points that retry nowhere too => HERMETIC_SHIM_DIR is left empty with a
#        warning (the state run-self-tests.sh fails closed on — see test-run-self-tests.sh (G3)).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$HERE/hermetic-test-env.sh"
DISPATCH="$HERE/dispatch-pr-review.sh"
CORE="$HERE/send-telemetry-core.sh"
PR="https://github.com/acme/widgets/pull/42"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

for tool in python3 git jq curl; do
  command -v "$tool" >/dev/null 2>&1 || PATH="$(hermetic_path_without_shims)" command -v "$tool" >/dev/null 2>&1 \
    || { echo "test-hermetic-egress: FATAL $tool is required" >&2; exit 1; }
done

T="$(mktemp -d "${TMPDIR:-/tmp}/test-hermetic-egress.XXXXXX")" || { echo "mktemp failed" >&2; exit 1; }
LISTENER_PID=""
cleanup() { [ -n "$LISTENER_PID" ] && kill "$LISTENER_PID" 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT

# ---- the stand-in ntfy host: a local HTTP listener that records every request ------------------
HITS="$T/listener-hits.log"; : > "$HITS"
python3 - "$T/listener.port" "$HITS" <<'PY' >/dev/null 2>&1 &
import http.server, sys
port_file, hits = sys.argv[1], sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def _hit(self):
        with open(hits, "a") as fh:
            fh.write("%s %s\n" % (self.command, self.path))
        self.send_response(200); self.end_headers()
    do_POST = do_GET = do_PUT = _hit
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(port_file + ".tmp", "w").write(str(s.server_address[1]))
import os; os.rename(port_file + ".tmp", port_file)
s.serve_forever()
PY
LISTENER_PID=$!
i=0; while [ ! -s "$T/listener.port" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i+1)); done
PORT="$(cat "$T/listener.port" 2>/dev/null || true)"
case "$PORT" in ''|*[!0-9]*) echo "test-hermetic-egress: FATAL listener never reported a port" >&2; exit 1 ;; esac
URL="http://127.0.0.1:$PORT/probe"
hits() { awk 'END{print NR+0}' "$HITS"; }

echo "== (L) listener positive control: a REAL curl to the stand-in host IS recorded =="
PATH="$(hermetic_path_without_shims)" curl -fs --max-time 5 -X POST -d x "$URL/control" >/dev/null 2>&1
[ "$(hits)" -eq 1 ] && ok "(L) the listener records a real POST (so zero hits below means zero egress, not a deaf listener)" \
  || no "(L) listener recorded $(hits) hit(s) for the control POST, expected 1"
: > "$HITS"

# ---- OUTER recording shims: stand-ins for the REAL notifiers and gh ----------------------------
OUTER="$T/outer-bin"; OUTER_LOG="$T/outer.log"; mkdir -p "$OUTER"; : > "$OUTER_LOG"
for s in osascript notify-send terminal-notifier gh; do
  printf '#!/bin/sh\nprintf "%%s %%s\\n" "%s" "$*" >> "%s"\n[ "%s" = gh ] && echo "https://github.com/probe/probe/issues/1"\nexit 0\n' \
    "$s" "$OUTER_LOG" "$s" > "$OUTER/$s"
  chmod +x "$OUTER/$s"
done
outer_notifier_calls() { grep -cE '^(osascript|notify-send|terminal-notifier) ' "$OUTER_LOG" 2>/dev/null || true; }
outer_gh_calls() { grep -c '^gh ' "$OUTER_LOG" 2>/dev/null || true; }

# The dangerous PATH: OUTER shims first, the real helper's shim dir removed.
DANGER_PATH="$OUTER:$(hermetic_path_without_shims)"

# ---- (D) fixture: git repo + stub gh + a stub runner that dies with no REVIEW_HEAL_RESULT ------
# fresh_dispatch_fixture — sets FX_REPO / FX_BIN / FX_HOME (mirrors test-dispatch-pr-review.sh's
# fresh_git_repo + stub_claude_no_result, trimmed to what the death path needs).
fresh_dispatch_fixture() {
  local d; d="$(mktemp -d "$T/fx.XXXXXX")"
  # Canonical (pwd -P) path: the dispatcher hands its detached child the RESOLVED git dir, and on
  # macOS $TMPDIR sits behind the /var -> /private/var symlink — detached_alive must match that form.
  d="$(cd "$d" && pwd -P)"
  FX_REPO="$d/repo"; FX_BIN="$d/bin"; FX_HOME="$d/home"
  mkdir -p "$FX_REPO" "$FX_BIN" "$FX_HOME"
  ( cd "$FX_REPO" && git init -q && git config user.email t@t.t && git config user.name t \
      && git config commit.gpgsign false && printf '.supervisor/\n' > .gitignore && printf 'b\n' > b.txt \
      && git add -A && git commit -qm base && git checkout -q -b feature/x && printf 'h\n' > h.txt \
      && git add -A && git commit -qm head ) >/dev/null 2>&1
  mkdir -p "$FX_REPO/.supervisor"
  local sha; sha="$(cd "$FX_REPO" && git rev-parse HEAD)"
  cat > "$FX_BIN/gh" <<GHEOF
#!/usr/bin/env bash
if [ "\$1" = "pr" ] && [ "\$2" = "view" ]; then
  printf '{"headRefOid":"%s","headRefName":"feature/x","isCrossRepository":false,"headRepositoryOwner":{"login":"o"}}\n' "$sha"
fi
exit 0
GHEOF
  cat > "$FX_BIN/stub-runner" <<'CLEOF'
#!/usr/bin/env bash
if [ "$1" = "--help" ]; then
  printf -- '--permission-mode <mode> (choices: "acceptEdits", "auto", "bypassPermissions", "manual", "dontAsk", "plan")\n'
  printf -- '--allowedTools, --allowed-tools <tools...>\n'
  printf -- '--disallowedTools, --disallowed-tools <tools...>\n'
  exit 0
fi
printf 'partial output, then the process just stops\n'
exit 0
CLEOF
  chmod +x "$FX_BIN/gh" "$FX_BIN/stub-runner"
}

pr_hash() { if command -v shasum >/dev/null 2>&1; then printf '%s' "$PR" | shasum | cut -d' ' -f1; else printf '%s' "$PR" | sha1sum | cut -d' ' -f1; fi; }

# detached_alive <needle> — is any process whose command line carries <needle> still running? (ps
# prints awk's own argv as `awk -v n <needle>`, hence the self-exclusion.)
detached_alive() { ps -A -o command= 2>/dev/null | awk -v n="$1" 'index($0, n) && !index($0, "awk -v n") {f=1} END{exit !f}'; }

# drive_dispatch_death — run the dispatcher for real from FX_REPO (caller's env already set), then
# poll for the .died marker (L3) and for the detached trap child to EXIT, so the async drain_died
# notify + webhook have fully happened before anything is read. Sets D_DIED / D_DRAIN_DIED / D_SETTLED.
drive_dispatch_death() {
  ( cd "$FX_REPO" && PATH="$FX_BIN:$PATH" HOME="$FX_HOME" LOOMWRIGHT_CLAUDE_BIN="$FX_BIN/stub-runner" \
      bash "$DISPATCH" "$PR" ) >/dev/null 2>&1 </dev/null
  local died="$FX_REPO/.supervisor/review-dispatch/$(pr_hash).died" n=0
  while [ ! -f "$died" ] && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n+1)); done
  n=0; while detached_alive "$FX_REPO" && [ "$n" -lt 150 ]; do sleep 0.1; n=$((n+1)); done
  D_DIED=0; [ -f "$died" ] && D_DIED=1
  D_SETTLED=1; detached_alive "$FX_REPO" && { D_SETTLED=0; ps -A -o pid=,command= | awk -v n="$FX_REPO" 'index($0, n) && !index($0, "awk -v n")' >> "$T/alive-debug.log"; }
  D_DRAIN_DIED=0; grep -qh '^DRAIN_DIED' "$FX_REPO"/.supervisor/logs/review-pr-dispatch-*.log 2>/dev/null && D_DRAIN_DIED=1
}

# in_danger <helper-or-empty> <private-egress-log> <cmd...> — run <cmd> in a subshell carrying the
# owner's dangerous env, with the given helper (real or mutant) sourced first (M1 isolation).
in_danger() {
  local helper="$1" elog="$2"; shift 2
  ( PATH="$DANGER_PATH"
    unset HERMETIC_SHIM_DIR HERMETIC_TEST_ENV HERMETIC_EGRESS_LOG LOOMWRIGHT_DESKTOP_NOTIFICATIONS
    export LOOMWRIGHT_WEBHOOK_URL="$URL" LOOMWRIGHT_TELEMETRY_REPO="probe-owner/probe-repo"
    export HERMETIC_EGRESS_LOG="$elog" DISPLAY="${DISPLAY:-:99}"
    # shellcheck disable=SC1090
    [ -n "$helper" ] && . "$helper"
    "$@" )
}

run_d() { fresh_dispatch_fixture; drive_dispatch_death; printf '%s %s %s\n' "$D_DIED" "$D_DRAIN_DIED" "$D_SETTLED"; }

# ---- (N) the notifier alone: a drain_died banner fired from a sandbox cwd ----------------------
# run_n — notify-desktop.sh fires DETACHED (fire_detached), so poll briefly for an outer record.
run_n() {
  local d; d="$(mktemp -d "$T/n.XXXXXX")"; mkdir -p "$d/home"
  ( cd "$d" && printf '{"hook_event_name":"Notification","notification_type":"drain_died","message":"review drain died without a result: %s"}' "$PR" \
      | HOME="$d/home" bash "$HERE/notify-desktop.sh" ) >/dev/null 2>&1 </dev/null
  local n=0; while [ "$(outer_notifier_calls)" -eq 0 ] && [ "$n" -lt 30 ]; do sleep 0.1; n=$((n+1)); done
}

# ---- (T) fixture: sandbox repo + sandbox HOME granting consent WITHOUT a repo -------------------
# The user-scope config path is read from resolve-egress-config.sh's own USER_SCOPE_FILE line rather
# than restated here, so this probe follows the resolver if the path ever moves.
USER_SCOPE_REL="$(sed -n 's/^USER_SCOPE_FILE="\${HOME:-}\/\(.*\)"$/\1/p' "$HERE/resolve-egress-config.sh" | head -1)"
TSB="$T/telemetry"; mkdir -p "$TSB/home"
( cd "$TSB" && git init -q && git remote add origin "https://github.com/probe-owner/probe-sandbox.git" ) >/dev/null 2>&1
if [ -n "$USER_SCOPE_REL" ]; then
  mkdir -p "$(dirname "$TSB/home/$USER_SCOPE_REL")"
  printf '{"schema_version":1,"repos":{"probe-owner/probe-sandbox":{"telemetry":"always_allow"}}}\n' > "$TSB/home/$USER_SCOPE_REL"
fi
jq -n '{session_id:"probe-hermetic", agent_type:"loomwright:supervisor-runner",
        result_block:"## SUPERVISOR_RESULT\n- schema_version: 1\n- task_id: probe-hermetic-task\n- status: failed\n- subtasks_failed: [BD-1x]\n- summary: hermetic probe fixture\n"}' > "$TSB/fixture.json"
run_t() { ( cd "$TSB" && HOME="$TSB/home" bash "$CORE" < "$TSB/fixture.json" ) >/dev/null 2>&1; echo $?; }

echo "== (T0) telemetry fixture sanity: the user-scope path was derived and consent is readable =="
[ -n "$USER_SCOPE_REL" ] && [ -s "$TSB/home/$USER_SCOPE_REL" ] \
  && ok "(T0) user-scope config path derived from the resolver ($USER_SCOPE_REL) and written under the sandbox HOME" \
  || no "(T0) could not derive the user-scope path from resolve-egress-config.sh's USER_SCOPE_FILE line"

# ======================= the REAL helper: nothing escapes ======================================
echo "== (D) dispatcher death path under the owner's env, real helper sourced =="
ELOG="$T/egress-real.log"; : > "$ELOG"; : > "$HITS"; : > "$OUTER_LOG"
read -r d_died d_dd d_set <<<"$(in_danger "$HELPER" "$ELOG" run_d)"
[ "$d_died" = 1 ] && [ "$d_dd" = 1 ] && ok "(D) the death path really ran: .died marker written and DRAIN_DIED logged (AC2 assertions still hold)" \
  || no "(D) death path did not run (died=$d_died drain_died=$d_dd) — the probe would be vacuous"
[ "$d_set" = 1 ] && ok "(D) the detached trap child exited before the probe read the listener (async notify+webhook settled)" \
  || no "(D) detached trap child still alive after 15s — reads below may be premature: $(cat "$T/alive-debug.log" 2>/dev/null)"
[ "$(hits)" -eq 0 ] && ok "(D) zero listener hits — the drain_died webhook never left the machine" \
  || no "(D) $(hits) listener hit(s): $(cat "$HITS")"
grep -q '^curl ' "$ELOG" && no "(D) the curl stub was reached — the unset layer did not scrub the URL: $(cat "$ELOG")" \
  || ok "(D) no curl call recorded in the private egress log — the env scrub alone stopped the send"
[ "$(outer_notifier_calls)" -eq 0 ] && ok "(D) zero calls reached the OUTER (stand-in real) notifiers" \
  || no "(D) outer notifier calls: $(cat "$OUTER_LOG")"

echo "== (P) test-propose-from-verify.sh run ALONE under the owner's env (the file sources the helper itself) =="
: > "$HITS"; : > "$OUTER_LOG"; P_HOME="$T/p-home"; mkdir -p "$P_HOME"
in_danger "" "$T/egress-p.log" env HOME="$P_HOME" bash "$HERE/test-propose-from-verify.sh" > "$T/p.out" 2>&1; rc_p=$?
[ "$rc_p" -eq 0 ] && grep -q 'AC9: the needs_auth desktop notification went to the AC9 stub notifier' "$T/p.out" \
  && ok "(P) test-propose-from-verify.sh passes, AC9 included, with the owner's env exported" \
  || no "(P) rc=$rc_p: $(grep -E 'FAIL|passed' "$T/p.out" | tail -5)"
[ "$(outer_notifier_calls)" -eq 0 ] && ok "(P) no osascript/notify-send/terminal-notifier call reached the outer shims (AC3)" \
  || no "(P) outer notifier calls: $(cat "$OUTER_LOG")"
[ "$(hits)" -eq 0 ] && ok "(P) zero listener hits" || no "(P) $(hits) listener hit(s): $(cat "$HITS")"

echo "== (N) notify-desktop.sh drain_died banner under the owner's env, real helper sourced =="
: > "$OUTER_LOG"
in_danger "$HELPER" "$T/egress-n.log" run_n
[ "$(outer_notifier_calls)" -eq 0 ] && ok "(N) zero calls reached the OUTER (stand-in real) notifiers" \
  || no "(N) outer notifier calls: $(cat "$OUTER_LOG")"

echo "== (T) telemetry non-dry-run under the owner's env (LOOMWRIGHT_TELEMETRY_REPO exported), real helper =="
: > "$OUTER_LOG"
rc_t="$(in_danger "$HELPER" "$T/egress-t.log" run_t)"
[ "$rc_t" = 4 ] && ok "(T) send-telemetry-core.sh stopped at no_repo_configured (exit 4) — the exported repo was scrubbed" \
  || no "(T) expected exit 4 (no_repo_configured), got $rc_t"
[ "$(outer_gh_calls)" -eq 0 ] && ok "(T) zero gh calls reached the outer shim — no telemetry issue could be filed" \
  || no "(T) gh calls: $(cat "$OUTER_LOG")"

# ======================= AC6 mutation controls ================================================
# make_mutant <name> <inject-check> <sed-args...> — build + gate a mutant; echo its path on success.
make_mutant() {
  local name="$1" check="$2"; shift 2
  local m="$T/mut-$name/hermetic-test-env.sh"; mkdir -p "$(dirname "$m")"
  sed "$@" "$HELPER" > "$m"
  if [ -s "$m" ] && ! cmp -s "$HELPER" "$m" && bash -n "$m" 2>/dev/null && eval "$check"; then
    printf '%s' "$m"; return 0
  fi
  return 1
}
UNSET_RE='^unset LOOMWRIGHT_WEBHOOK_URL LOOMWRIGHT_WEBHOOK_FORMAT LOOMWRIGHT_TELEMETRY_REPO$'
STUBS_RE='^_hermetic_stub_names="osascript notify-send terminal-notifier curl wget"$'
DESK_RE='^export LOOMWRIGHT_DESKTOP_NOTIFICATIONS=0$'

echo "== (M0) mutation positive control: every pattern the mutants delete matches the real helper once =="
[ "$(grep -cE "$UNSET_RE" "$HELPER")" -eq 1 ] && [ "$(grep -cE "$STUBS_RE" "$HELPER")" -eq 1 ] && [ "$(grep -cE "$DESK_RE" "$HELPER")" -eq 1 ] \
  && ok "(M0) unset line, stub list and notifications=0 export each match exactly once in the real helper" \
  || no "(M0) a mutation pattern no longer matches hermetic-test-env.sh — update the probe with the helper"

echo "== (Mi) mutant: unset line AND curl/wget stubs removed => the listener records hits =="
if MI="$(make_mutant i '[ "$(grep -cE "$UNSET_RE" "$m")" -eq 0 ] && grep -qx "_hermetic_stub_names=\"osascript notify-send terminal-notifier\"" "$m"' \
      -e "/$UNSET_RE/d" -e 's/^_hermetic_stub_names=.*$/_hermetic_stub_names="osascript notify-send terminal-notifier"/')"; then
  : > "$HITS"; ELOG="$T/egress-mi.log"; : > "$ELOG"
  read -r mi_died _ _ <<<"$(in_danger "$MI" "$ELOG" run_d)"
  [ "$mi_died" = 1 ] && [ "$(hits)" -ge 1 ] && ok "(Mi) $(hits) listener hit(s) — the helper as a whole is load-bearing" \
    || no "(Mi) expected listener hits with both layers removed (died=$mi_died hits=$(hits))"
else
  no "(Mi) mutant failed its gates (empty / identical / bash -n / override not injected)"
fi

echo "== (Mii) mutant: ONLY the unset line removed => zero hits, but the stub records curl -> listener =="
if MII="$(make_mutant ii '[ "$(grep -cE "$UNSET_RE" "$m")" -eq 0 ] && [ "$(grep -cE "$STUBS_RE" "$m")" -eq 1 ]' -e "/$UNSET_RE/d")"; then
  : > "$HITS"; ELOG="$T/egress-mii.log"; : > "$ELOG"
  read -r mii_died _ _ <<<"$(in_danger "$MII" "$ELOG" run_d)"
  if [ "$mii_died" = 1 ] && [ "$(hits)" -eq 0 ] && grep -qF "$URL" < <(grep -E '^curl ' "$ELOG"); then
    ok "(Mii) zero listener hits AND the private egress log recorded curl -> $URL — the stub layer alone catches it"
  else
    no "(Mii) died=$mii_died hits=$(hits) egress-log='$(cat "$ELOG")'"
  fi
  : > "$OUTER_LOG"
  rc_mt="$(in_danger "$MII" "$T/egress-mt.log" run_t)"
  [ "$(outer_gh_calls)" -ge 1 ] && ok "(Mii-T) telemetry positive control: without the unset line the exported repo reaches gh (rc=$rc_mt) — (T) is not vacuous" \
    || no "(Mii-T) expected the outer gh shim to record an issue create without the unset line (rc=$rc_mt log='$(cat "$OUTER_LOG")')"
else
  no "(Mii) mutant failed its gates (empty / identical / bash -n / override not injected)"
fi

echo "== (Miii) mutant: notifier stubs AND notifications=0 removed => the OUTER notifier records the banner =="
if MIII="$(make_mutant iii '[ "$(grep -cE "$DESK_RE" "$m")" -eq 0 ] && grep -qx "_hermetic_stub_names=\"curl wget\"" "$m"' \
      -e "/$DESK_RE/d" -e 's/^_hermetic_stub_names=.*$/_hermetic_stub_names="curl wget"/')"; then
  : > "$OUTER_LOG"
  in_danger "$MIII" "$T/egress-miii.log" run_n
  [ "$(outer_notifier_calls)" -ge 1 ] \
    && ok "(Miii) the outer notifier shim recorded the drain_died banner — the unmutated (N)/(D)/(P) silence is evidence" \
    || no "(Miii) expected an outer notifier call (outer='$(cat "$OUTER_LOG")')"
else
  no "(Miii) mutant failed its gates (empty / identical / bash -n / override not injected)"
fi

echo "== (R) shim-dir mktemp retry: an unusable TMPDIR still yields the stubs, made under /tmp =="
# probe_shim_dir <helper> — source <helper> in a stripped subshell (the real helper's shim dir off
# PATH, its markers unset, so nothing is reused) with TMPDIR pointing at a dir that does not exist;
# print "<HERMETIC_SHIM_DIR>|<first PATH entry>|<helper stderr>".
R_TMPDIR="$T/absent-tmpdir/nested"
probe_shim_dir() {
  ( PATH="$(hermetic_path_without_shims)"
    unset HERMETIC_SHIM_DIR HERMETIC_EGRESS_LOG HERMETIC_TEST_ENV
    export TMPDIR="$R_TMPDIR"
    . "$1" 2>"$T/r.err"
    printf '%s|%s|%s' "${HERMETIC_SHIM_DIR:-}" "${PATH%%:*}" "$(tr '\n' ' ' < "$T/r.err")" )
}
[ ! -e "$R_TMPDIR" ] || no "(R) precondition: $R_TMPDIR unexpectedly exists"
IFS='|' read -r r_dir r_first r_err <<<"$(probe_shim_dir "$HELPER")"
r_stubs=1
for s in osascript notify-send terminal-notifier curl wget; do [ -x "$r_dir/$s" ] || r_stubs=0; done
case "$r_dir" in /tmp/hermetic-shims.*) r_under_tmp=1 ;; *) r_under_tmp=0 ;; esac
if [ "$r_under_tmp" = 1 ] && [ -d "$r_dir" ] && [ -f "$r_dir/.hermetic-shim-dir" ] && [ "$r_stubs" = 1 ] \
   && [ "$r_first" = "$r_dir" ] && [ -z "$r_err" ]; then
  ok "(R) TMPDIR unusable => the helper retried under /tmp: shim dir $r_dir built, marked, first on PATH, no warning"
else
  no "(R) retry failed: dir='$r_dir' first-PATH='$r_first' stubs=$r_stubs err='$r_err'"
fi
case "$r_dir" in /tmp/hermetic-shims.*) rm -rf "$r_dir" ;; esac

# Mutation control: point the retry at a path that cannot exist either => the helper must leave
# HERMETIC_SHIM_DIR EMPTY and warn (the state run-self-tests.sh fails closed on), proving (R)'s
# green came from the retry and not from a TMPDIR that silently worked.
RETRY_RE='mktemp -d "/tmp/hermetic-shims\.XXXXXX"'
if RM="$(make_mutant r '[ "$(grep -cE "$RETRY_RE" "$m")" -eq 0 ] && [ "$(grep -cE "$RETRY_RE" "$HELPER")" -eq 1 ]' \
      -e "s|mktemp -d \"/tmp/hermetic-shims\.XXXXXX\"|mktemp -d \"$R_TMPDIR/hermetic-shims.XXXXXX\"|")"; then
  IFS='|' read -r rm_dir rm_first rm_err <<<"$(probe_shim_dir "$RM")"
  case "$rm_err" in *"WARNING: mktemp failed"*) rm_warned=1 ;; *) rm_warned=0 ;; esac
  if [ -z "$rm_dir" ] && [ "$rm_warned" = 1 ] && [ ! -f "$rm_first/.hermetic-shim-dir" ]; then
    ok "(Rm) without a working retry the helper leaves HERMETIC_SHIM_DIR empty and warns — (R) is not vacuous"
  else
    no "(Rm) expected an empty shim dir + warning, got dir='$rm_dir' first-PATH='$rm_first' err='$rm_err'"
  fi
else
  no "(Rm) mutant failed its gates (empty / identical / bash -n / retry pattern not matched exactly once)"
fi

echo
echo "test-hermetic-egress: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
