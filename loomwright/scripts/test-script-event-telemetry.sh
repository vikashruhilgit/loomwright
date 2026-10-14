#!/usr/bin/env bash
# test-script-event-telemetry.sh — plugin SCRIPT events (docs/TELEMETRY.md §"Script events"):
# emit-script-event.sh -> send-telemetry.sh -> send-telemetry-core.sh, one thread per script step
# and code, closed by the step's next pass; plugin facts only.
#
# WHAT IT PROVES (each against the real scripts):
#   S1  a fail event dry-runs to an OPEN with the script/step/code title, the script-event labels,
#       its counts and managed-KIND counts
#   S2  field selection: an extra key (a path, a message, a repo slug), a non-integer or path-shaped
#       count, a kind outside the enum and an unknown kind group never reach the posted text — they
#       are dropped and counted; an unknown script, a code or step that is not a token, an unknown
#       outcome or a missing event_id skips the event (exit 5, nothing posted)
#   S3  live, recording gh stub: code A opens, a repeat of code A comments on it, code B of the SAME
#       step opens its own thread, the step's pass comments + labels + closes BOTH; the next pass is
#       interest-skipped; a pass of ANOTHER step closes nothing; the same thread key in another
#       source repo is a separate thread
#   S3b a group close that FAILS on one of two threads (the gh stub's GH_FAIL_CLOSE_ISSUE knob
#       fails `issue close <n>`): the core exits 1, the OTHER thread is recorded closed in the map,
#       the failed one stays open, and the next pass retries and closes it (never re-closing the other)
#   S4  no user-scope consent -> exit 3, gh never called
#   S5  the emitter: exit 0 and no output in every case (core missing, python3 absent from PATH,
#       too few args, LOOMWRIGHT_SCRIPT_EVENTS=0 sends nothing); LOOMWRIGHT_SCRIPT_EVENT_TEE gets
#       the payload line
#   S6  wiring: migrate-branch-mode.sh seed on a branch holding a managed file this disk never had
#       reports `fail ab_names_mismatch` with a/u/b counts and kinds.b_only.md=1; a passing step
#       reports `pass ok`; plan and state report nothing; the step's exit code and stderr are
#       unchanged by the trap; setup-memory.sh apply reports its readiness with the migrate caller
#   S7  mutation controls: copying the raw payload into the body (no field selection) turns S2 red;
#       dropping the group close turns S3's close red
#
# HERMETIC: isolated $HOME (user-scope egress.json + thread map), scratch git repos as $PWD, `gh`
# is a recording stub on PATH — no network. bash-3.2-safe.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -u
set -o pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE="$HERE/send-telemetry-core.sh"
EMIT="$HERE/emit-script-event.sh"
unset LOOMWRIGHT_TELEMETRY_REPO LOOMWRIGHT_PR_HEAD_REF LOOMWRIGHT_SCRIPT_EVENTS LOOMWRIGHT_SCRIPT_EVENT_TEE LOOMWRIGHT_SCRIPT_EVENT_CALLER 2>/dev/null || true

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }
check() { if [ "$1" -eq 0 ]; then ok "$2"; else no "$2"; fi; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=tester GIT_AUTHOR_EMAIL=tester@test.invalid GIT_COMMITTER_NAME=tester GIT_COMMITTER_EMAIL=tester@test.invalid
SB_HOME="$T/home"; LW="$SB_HOME/.claude/loomwright"; MAP="$LW/telemetry-threads.json"
mkdir -p "$LW" "$T/bin" "$T/bodies"
export HOME="$SB_HOME"
mkrepo() { git init -q "$1"; git -C "$1" remote add origin "https://github.com/$2.git"; }
mkrepo "$T/r1" acme/secret-repo
mkrepo "$T/r2" acme/other-repo
consent() { printf '{"schema_version":1,"repos":{"acme/secret-repo":{"telemetry":"always_allow","telemetry_repo":"example/sink"},"acme/other-repo":{"telemetry":"always_allow","telemetry_repo":"example/sink"}}}' > "$LW/egress.json"; }
consent

GH_LOG="$T/gh.log"; GH_BODIES="$T/bodies"
cat > "$T/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
# GH_FAIL_CLOSE_ISSUE=<n>: `issue close <n>` fails (logged first, so the attempt is visible)
[ "$1 ${2:-}" = "issue close" ] && [ -n "${GH_FAIL_CLOSE_ISSUE:-}" ] && [ "${3:-}" = "$GH_FAIL_CLOSE_ISSUE" ] && exit 1
body=""; prev=""; for a in "$@"; do [ "$prev" = "--body-file" ] && body="$a"; prev="$a"; done
n="$(ls "$GH_BODIES" | wc -l | tr -d ' ')"
[ -n "$body" ] && cp "$body" "$GH_BODIES/$n.md"
case "$1 ${2:-}" in
  "issue create") printf 'https://github.com/example/sink/issues/%s\n' "$((100 + $(grep -c '^issue create' "$GH_LOG")))" ;;
  "issue comment") printf 'https://github.com/example/sink/issues/%s#c\n' "$3" ;;
esac
exit 0
STUB
chmod +x "$T/bin/gh"
export GH_LOG GH_BODIES
gh_reset() { : > "$GH_LOG"; rm -f "$GH_BODIES"/*; }
SCRIPT_CORE="$CORE"
# core <repo> <payload json> [--dry-run] — OUT / RC
core() { local r="$1" p="$2"; shift 2; OUT="$(cd "$r" && printf '%s' "$p" | PATH="$T/bin:$PATH" bash "$SCRIPT_CORE" "$@" 2>&1)"; RC=$?; }
has() { grep -qF -- "$1" <<<"$OUT"; }
ev() { # ev <script> <step> <outcome> <code> <event_id> [extra json members]
  printf '{"kind":"script_event","script":"%s","step":"%s","outcome":"%s","code":"%s","event_id":"%s"%s}' "$1" "$2" "$3" "$4" "$5" "${6:+,$6}"
}

echo "== S1. a fail event dry-runs to an open thread =="
gh_reset; rm -f "$MAP"
core "$T/r1" "$(ev migrate-branch-mode seed fail ab_names_mismatch e1 '"counts":{"a":63,"u":0,"b":66},"kinds":{"b_only":{"dismissed-decisions":3}}')" --dry-run
{ [ "$RC" -eq 0 ] && has "THREAD_ACTION=open" && has "TITLE=[Telemetry] migrate-branch-mode seed: ab_names_mismatch" \
  && has "  - telemetry:script-event" && has "  - script:migrate-branch-mode" && has "  - outcome:fail" \
  && has "- a: 63" && has "- b: 66" && has "## Kinds (b_only)" && has "- dismissed-decisions: 3" && has "WOULD_EXIT=0"; }
check $? "fail event -> open, title / labels / counts / kinds (rc=$RC)"
[ ! -s "$GH_LOG" ]; check $? "dry-run calls no gh"

echo "== S2. field selection: only allow-listed shapes reach the text =="
LEAKY='"counts":{"a":1,"bad":"x","/Users/someone/":2,"neg":-1,"flt":1.5,"t":true},"kinds":{"b_only":{"md":1,"secret.md":4},"evil":{"md":1}},"message":"/Users/someone/proj/app.py line 12","repo":"acme/secret-repo","branch":"feature/secret","pr":"https://github.com/acme/secret-repo/pull/9","caller":"acme/secret-repo"'
core "$T/r1" "$(ev migrate-branch-mode seed fail ab_names_mismatch e2 "$LEAKY")" --dry-run
LEAK=""; for n in "/Users/someone" "app.py" "secret-repo" "feature/secret" "pull/9" "secret.md" "evil" '"bad"' "neg" "flt"; do has "$n" && LEAK="$LEAK $n"; done
{ [ "$RC" -eq 0 ] && has "THREAD_ACTION=open" && [ -z "$LEAK" ] && has '"dropped": 8' && has "- a: 1"; }
check $? "extra keys, non-integer / path-shaped counts, off-enum kinds and a slug caller never reach the body; 8 dropped (rc=$RC leaked:${LEAK:- none})"
REFUSE_OK=1
for bad in "$(ev some-other-script seed fail x e3)" "$(ev migrate-branch-mode seed fail 'a/b' e3)" \
           "$(ev migrate-branch-mode 'Seed Step' fail x e3)" "$(ev migrate-branch-mode seed broken x e3)" \
           '{"kind":"script_event","script":"migrate-branch-mode","step":"seed","outcome":"fail","code":"x"}'; do
  core "$T/r1" "$bad" --dry-run
  { has "script_event_invalid" && has "WOULD_EXIT=5" && ! has "THREAD_ACTION"; } || { REFUSE_OK=0; echo "    not refused: $bad -> $OUT"; }
done
[ "$REFUSE_OK" = 1 ]; check $? "unknown script, non-token code / step, unknown outcome, missing event_id -> skipped (exit 5)"

echo "== S3. live threads: one per code, the step's pass closes them all =="
gh_reset; rm -f "$MAP"
core "$T/r1" "$(ev migrate-branch-mode seed fail ab_names_mismatch L1 '"counts":{"a":63,"u":0,"b":66}')"; R1="$RC"
core "$T/r1" "$(ev migrate-branch-mode seed fail ab_names_mismatch L2)"; R2="$RC"
core "$T/r1" "$(ev migrate-branch-mode seed fail meta_push_failed L3)"; R3="$RC"
{ [ "$R1$R2$R3" = 000 ] && [ "$(grep -c '^issue create' "$GH_LOG")" = 2 ] && [ "$(grep -c '^issue comment 101' "$GH_LOG")" = 1 ]; }
check $? "code A opens #101, its repeat comments on #101, code B opens #102 (rc=$R1$R2$R3)"
core "$T/r1" "$(ev migrate-branch-mode scrub pass ok L4)"; R4="$RC"
{ [ "$R4" = 5 ] && ! grep -q '^issue close' "$GH_LOG"; }; check $? "a pass of ANOTHER step closes nothing (interest-skipped, rc=$R4)"
core "$T/r2" "$(ev migrate-branch-mode seed pass ok L5)"; R5="$RC"
{ [ "$R5" = 5 ] && ! grep -q '^issue close' "$GH_LOG"; }; check $? "the same step's pass in ANOTHER source repo closes nothing (rc=$R5)"
core "$T/r1" "$(ev migrate-branch-mode seed pass ok L6)"; R6="$RC"
{ [ "$R6" = 0 ] && grep -q '^issue close 101 ' "$GH_LOG" && grep -q '^issue close 102 ' "$GH_LOG" \
  && [ "$(grep -c 'add-label telemetry:healed-in-loop' "$GH_LOG")" = 2 ] && [ "$(grep -c '^issue comment 10[12]' "$GH_LOG")" = 3 ]; }
check $? "the step's pass comments on, labels and closes BOTH code threads (rc=$R6)"
core "$T/r1" "$(ev migrate-branch-mode seed pass ok L7)"; R7="$RC"
[ "$R7" = 5 ]; check $? "the next pass is interest-skipped (rc=$R7)"
core "$T/r1" "$(ev migrate-branch-mode seed fail ab_names_mismatch L8)"; R8="$RC"
{ [ "$R8" = 0 ] && [ "$(grep -c '^issue create' "$GH_LOG")" = 3 ]; }; check $? "a new failure after the close opens a NEW thread (rc=$R8)"
LEAK=""; for f in "$GH_BODIES"/*.md; do grep -qE 'secret-repo|other-repo|/Users/|acme' "$f" && LEAK="$LEAK $(basename "$f")"; done
grep -qE 'secret-repo|other-repo|acme' "$GH_LOG" && LEAK="$LEAK gh-args"
[ -z "$LEAK" ]; check $? "no source repo slug or path in any posted body or gh argument (${LEAK:-clean})"

echo "== S3b. a group close that fails on ONE thread: the rest close, a later pass retries =="
# map_state <issue> — that thread's recorded state in the user-scope thread map ("" when absent)
map_state() { python3 -I -c 'import json, sys
d = json.load(open(sys.argv[1]))
print("".join(t.get("state", "") for t in d.get("threads", {}).values() if isinstance(t, dict) and t.get("issue") == int(sys.argv[2])))' "$MAP" "$1" 2>/dev/null; }
gh_reset; rm -f "$MAP"
core "$T/r1" "$(ev migrate-branch-mode seed fail code_a P1)"; P1="$RC"
core "$T/r1" "$(ev migrate-branch-mode seed fail code_b P2)"; P2="$RC"
# fail the thread the group close visits FIRST (decide() walks the map keys sorted), so the
# OTHER thread's close proves the loop continues past a failure rather than stopping at it
FIRST="$(python3 -I -c 'import json, sys
d = json.load(open(sys.argv[1]))
print([t["issue"] for k, t in sorted(d["threads"].items()) if t.get("state") == "open"][0])' "$MAP" 2>/dev/null)"
OTHER=101; [ "$FIRST" = 101 ] && OTHER=102
export GH_FAIL_CLOSE_ISSUE="$FIRST"; core "$T/r1" "$(ev migrate-branch-mode seed pass ok P3)"; P3="$RC"; unset GH_FAIL_CLOSE_ISSUE
CL="$(sed -n 's/^issue close \(10[12]\) .*/\1/p' "$GH_LOG" | tr '\n' ' ')"
{ [ "$P1$P2" = 00 ] && [ "$P3" = 1 ] && [ "$CL" = "$FIRST $OTHER " ] && [ "$(map_state "$FIRST")" = open ] && [ "$(map_state "$OTHER")" = closed ] \
  && has "thread_close_group closed=1 of=2"; }
check $? "close of #$FIRST (visited first) fails: the core exits 1, continues to close #$OTHER (recorded closed), #$FIRST stays open (rc=$P3; closes: ${CL}; $FIRST=$(map_state "$FIRST") $OTHER=$(map_state "$OTHER"))"
core "$T/r1" "$(ev migrate-branch-mode seed pass ok P4)"; P4="$RC"
{ [ "$P4" = 0 ] && [ "$(grep -c "^issue close $FIRST " "$GH_LOG")" = 2 ] && [ "$(grep -c "^issue close $OTHER " "$GH_LOG")" = 1 ] \
  && [ "$(map_state "$FIRST")" = closed ] && [ "$(map_state "$OTHER")" = closed ]; }
check $? "the next pass retries and closes #$FIRST only, never re-closing #$OTHER (rc=$P4; $FIRST=$(map_state "$FIRST") $OTHER=$(map_state "$OTHER"))"

echo "== S4. no consent -> nothing sent =="
gh_reset; rm -f "$LW/egress.json"
core "$T/r1" "$(ev migrate-branch-mode seed fail ab_names_mismatch N1)"
{ [ "$RC" = 3 ] && [ ! -s "$GH_LOG" ]; }; check $? "no user-scope consent -> exit 3, gh never called (rc=$RC)"
consent

echo "== S5. the emitter is fire-and-forget =="
E_OUT="$(bash "$EMIT" --root "$T/r1" migrate-branch-mode seed fail x 2>&1)"; E_RC=$?
{ [ "$E_RC" = 0 ] && [ -z "$E_OUT" ]; }; check $? "a normal emit: exit 0, no output"
mkdir -p "$T/lonely"; cp "$EMIT" "$T/lonely/"
E_OUT="$(bash "$T/lonely/emit-script-event.sh" --root "$T/r1" migrate-branch-mode seed fail x 2>&1)"; E_RC=$?
{ [ "$E_RC" = 0 ] && [ -z "$E_OUT" ]; }; check $? "no telemetry wrapper beside it: exit 0, no output"
mkdir -p "$T/nopy"; for c in bash date dirname cat; do ln -sf "$(command -v "$c")" "$T/nopy/$c"; done
E_OUT="$(PATH="$T/nopy" "$T/nopy/bash" "$EMIT" --root "$T/r1" migrate-branch-mode seed fail x 2>&1)"; E_RC=$?
{ [ "$E_RC" = 0 ] && [ -z "$E_OUT" ]; }; check $? "python3 absent: exit 0, no output"
E_OUT="$(bash "$EMIT" --root "$T/r1" migrate-branch-mode 2>&1)"; E_RC=$?
{ [ "$E_RC" = 0 ] && [ -z "$E_OUT" ]; }; check $? "too few arguments: exit 0, no output"
TEE="$T/tee.jsonl"; : > "$TEE"; gh_reset; rm -f "$MAP"
LOOMWRIGHT_SCRIPT_EVENTS=0 LOOMWRIGHT_SCRIPT_EVENT_TEE="$TEE" PATH="$T/bin:$PATH" bash "$EMIT" --root "$T/r1" migrate-branch-mode seed fail x
{ [ ! -s "$TEE" ] && [ ! -s "$GH_LOG" ]; }; check $? "LOOMWRIGHT_SCRIPT_EVENTS=0 sends nothing"
LOOMWRIGHT_SCRIPT_EVENT_TEE="$TEE" PATH="$T/bin:$PATH" bash "$EMIT" --root "$T/r1" migrate-branch-mode seed fail ab_names_mismatch --count a=63 --kind b_only.md=2 --caller migrate-branch-mode.untrack-pr
{ grep -q '"code": "ab_names_mismatch"' "$TEE" && grep -q '"a": 63' "$TEE" && grep -q '"md": 2' "$TEE" && grep -q '"caller": "migrate-branch-mode.untrack-pr"' "$TEE" \
  && grep -q '^issue create' "$GH_LOG"; }
check $? "the TEE seam gets the payload line, and the event reaches gh through the wrapper"

echo "== S6. wiring: migrate-branch-mode.sh and setup-memory.sh report their steps =="
W="$T/mig"; mkdir -p "$W"; git init -q --bare "$W/origin.git"; git --git-dir="$W/origin.git" symbolic-ref HEAD refs/heads/main
git init -q "$W/seed"
( cd "$W/seed" && git symbolic-ref HEAD refs/heads/main && printf '.supervisor/\n' > .gitignore && echo code > app.txt \
  && mkdir -p .supervisor/jobs/done && echo '# a' > .supervisor/jobs/done/a.md && git add .gitignore app.txt && git add -f .supervisor \
  && git commit -qm code && git remote add origin "$W/origin.git" && git push -q origin main )
git clone -q "$W/origin.git" "$W/A" 2>/dev/null
cat > "$T/bin/gh-mig" <<'STUB'
#!/bin/bash
case "$1 $2" in "pr list") exit 0 ;; esac
exit 0
STUB
chmod +x "$T/bin/gh-mig"
MB="$HERE/migrate-branch-mode.sh"
mig() { : > "$TEE"; OUT="$(LOOMWRIGHT_SCRIPT_EVENT_TEE="$TEE" LOOMWRIGHT_GH_BIN="$T/bin/gh-mig" bash "$MB" "$@" --root "$W/A" 2>&1)"; RC=$?; }
rm -f "$LW/egress.json"   # wiring only: the TEE records what would be sent; nothing is posted
mig plan; { [ "$RC" = 0 ] && [ ! -s "$TEE" ]; }; check $? "plan reports nothing (rc=$RC)"
mig state; [ ! -s "$TEE" ]; check $? "state reports nothing"
mig preflight --repo owner/repo
{ [ "$RC" = 0 ] && grep -q '"step": "preflight"' "$TEE" && grep -q '"outcome": "pass"' "$TEE" && grep -q '"code": "ok"' "$TEE"; }
check $? "a passing preflight reports pass ok (rc=$RC)"
mig scrub; mig init --branch team-meta
printf 'protect=PASS\n' >> "$W/A/.supervisor/migrate-branch-mode/state"
( cd "$T" && rm -rf O && git clone -q "$W/origin.git" O && cd O && git checkout -q -b team-meta origin/team-meta && mkdir -p .supervisor/jobs/done \
  && echo '# remote only' > .supervisor/jobs/done/remote-only.md && git add -f .supervisor && git commit -qm r && git push -q origin team-meta ) >/dev/null 2>&1
LOOMWRIGHT_SCRIPT_EVENTS=0 LOOMWRIGHT_GH_BIN="$T/bin/gh-mig" bash "$MB" seed --root "$W/A" >/dev/null 2>&1   # settle: the first push really pushes
SEED_OFF="$(LOOMWRIGHT_SCRIPT_EVENTS=0 LOOMWRIGHT_GH_BIN="$T/bin/gh-mig" bash "$MB" seed --root "$W/A" 2>&1)"; SEED_RC0=$?
mig seed
{ [ "$RC" = 1 ] && [ "$SEED_RC0" = 1 ] && grep -q '"code": "ab_names_mismatch"' "$TEE" && grep -q '"outcome": "fail"' "$TEE" \
  && grep -q '"a": 1' "$TEE" && grep -q '"b": 2' "$TEE" && grep -q '"u": 0' "$TEE" && grep -q '"md": 1' "$TEE" && grep -q '"b_only"' "$TEE"; }
check $? "seed with a branch-only managed file reports fail ab_names_mismatch, a=1 u=0 b=2, kinds.b_only.md=1 (rc=$RC)"
{ [ "$OUT" = "$SEED_OFF" ] && has "A != B"; } || diff <(printf '%s\n' "$SEED_OFF") <(printf '%s\n' "$OUT") | head -n 8 | sed 's/^/    /'
[ "$OUT" = "$SEED_OFF" ] && has "A != B"
check $? "the trap leaves the step's output and exit code byte-identical to a run with events off"
grep -qE 'remote-only|/Users/|team-meta|origin.git' "$TEE" && no "the payload carries a path or name: $(cat "$TEE")" || ok "the payload carries no path, branch or file name"
mig seed --bogus 2>/dev/null; [ "$RC" = 2 ] && [ ! -s "$TEE" ]; check $? "a usage error (exit 2) reports nothing"
# setup-memory apply: its readiness with the caller the migration step passes
mkrepo "$T/sm" acme/secret-repo; printf '*.log\n' > "$T/sm/.gitignore"
: > "$TEE"; LOOMWRIGHT_SCRIPT_EVENT_TEE="$TEE" LOOMWRIGHT_SCRIPT_EVENT_CALLER=migrate-branch-mode.untrack-pr bash "$HERE/setup-memory.sh" --root "$T/sm" apply >/dev/null 2>&1
{ grep -q '"script": "setup-memory"' "$TEE" && grep -q '"step": "apply"' "$TEE" && grep -q '"caller": "migrate-branch-mode.untrack-pr"' "$TEE" \
  && grep -q '"leaked_unintended"' "$TEE"; }
check $? "setup-memory apply reports its readiness verdict with the migrate caller ($(sed -n 's/.*"code": "\([^"]*\)".*/\1/p' "$TEE" | head -n 1))"

echo "== S7. mutation controls =="
consent   # S6 ran without consent (TEE only); the mutants below need a would-send path
mutant() { # mutant <name> <python replace: old> <new> — a core copy with one edit; 0 = built
  local d="$T/mut-$1"; mkdir -p "$d"
  for f in send-telemetry-core.sh resolve-egress-config.sh result_block_parser.py validate-code-review-result.py validate-qa-result.py validate-supervisor-result.py; do cp "$HERE/$f" "$d/"; done
  python3 - "$d/send-telemetry-core.sh" "$2" "$3" <<'PY' || return 1
import sys
p, a, b = sys.argv[1:4]
s = open(p).read()
if s.count(a) != 1:
    sys.exit(1)
open(p, "w").write(s.replace(a, b))
PY
  bash -n "$d/send-telemetry-core.sh" && MUT_CORE="$d/send-telemetry-core.sh"
}
# no home path in this payload: the secondary privacy tripwire would block that before any body
# printed, hiding the leak the field selection itself prevents
LEAKY2='"message":"app.py line 12","branch":"feature/secret","pr":"pull/9"'
if mutant raw-body '+ "## Raw Data\n```json\n" + json.dumps(se_raw, indent=2, sort_keys=True)' '+ "## Raw Data\n```json\n" + json.dumps(payload, indent=2, sort_keys=True)'; then
  SCRIPT_CORE="$MUT_CORE"; core "$T/r1" "$(ev migrate-branch-mode seed fail ab_names_mismatch m1 "$LEAKY2")" --dry-run; SCRIPT_CORE="$CORE"
  if has "feature/secret" && has "app.py"; then ok "mutation control: posting the raw payload leaks the branch / file name S2 guards"; else no "mutation control REFUTED: the raw-payload mutant leaked nothing"; fi
else no "mutation control (raw body) did not build — counts as FAIL"; fi
if mutant no-group-close '    if rec["success"] and GROUP_KEY:' '    if False:'; then
  gh_reset; rm -f "$MAP"; consent; SCRIPT_CORE="$MUT_CORE"
  core "$T/r1" "$(ev migrate-branch-mode seed fail code_a g1)"; core "$T/r1" "$(ev migrate-branch-mode seed fail code_b g2)"; core "$T/r1" "$(ev migrate-branch-mode seed pass ok g3)"
  SCRIPT_CORE="$CORE"
  if grep -q '^issue close 101 ' "$GH_LOG" && grep -q '^issue close 102 ' "$GH_LOG"; then no "mutation control REFUTED: both threads closed without the group close"; else ok "mutation control: without the group close the step's pass leaves its code threads open"; fi
else no "mutation control (group close) did not build — counts as FAIL"; fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
