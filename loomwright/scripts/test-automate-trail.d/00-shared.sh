# 00-shared.sh — the fixture builders, stubs and constants more than one part uses, hoisted VERBATIM from
# the part that first defined them (named above each block), so every pool group (part-groups-lib.sh)
# runs on the same definitions whichever parts it holds. Sourced by test-automate-trail.sh after its
# own setup and before any part, in every group. Definitions only: no leg, no ok/no call.

# ---- from 01-sidecar-trail-pr.sh ----
# fixture builder: bare origin + primary clone on a feature branch with trail state
RUN_ID="automate-2026-01-01-000000"
REQ=".supervisor/requirements/f/01-a.md"
new_fixture() {
  FX="$TOP/fx$1"; mkdir -p "$FX"
  git init -q --bare "$FX/origin.git"
  git -C "$FX/origin.git" symbolic-ref HEAD refs/heads/main
  git clone -q "$FX/origin.git" "$FX/primary" 2>/dev/null
  P="$FX/primary"
  ( cd "$P"
    git checkout -q -b main 2>/dev/null || true
    cat > .gitignore <<'GI'
.supervisor/*
!.supervisor/requirements/
!.supervisor/jobs/
.supervisor/jobs/*
!.supervisor/jobs/done/
!.supervisor/jobs/failed/
!.supervisor/automate/
.supervisor/automate/*
!.supervisor/automate/*.md
!.supervisor/postmortem/
.supervisor/postmortem/*
!.supervisor/postmortem/results.jsonl
GI
    mkdir -p .supervisor/requirements/f .supervisor/postmortem
    echo "# req a" > "$REQ"; echo "# req b" > .supervisor/requirements/f/02-b.md
    echo "base readme" > README
    echo '{"automate_key":"old-run\u001fx","source":"automate_drain"}' > .supervisor/postmortem/results.jsonl
    git add .gitignore README .supervisor/requirements .supervisor/postmortem/results.jsonl
    git commit -qm init; git push -q origin main 2>/dev/null
    git remote set-head origin main >/dev/null 2>&1
    git checkout -q -b feature/x; echo feat > feat.txt; git add feat.txt; git commit -qm feat
    mkdir -p .supervisor/automate .supervisor/jobs/done .supervisor/jobs/in-progress
    cat > ".supervisor/automate/$RUN_ID.md" <<RF
# Automate Run: fixture
## Status: paused
## Queue
- [ ] $REQ
- [x] .supervisor/requirements/f/02-b.md  # skipped: owner said so
## Current
- item: $REQ | status: awaiting_merge | pr: https://github.com/acme/widgets/pull/7 | branch: feature/x
- pause_reason: awaiting_merge
## Progress
- t0 picked $REQ
RF
    printf '# req a\n\nlocal notes (no done heading: Phase 4.5 stamps are set per leg)\n' > "$REQ"
    printf '# Brief\n## Environment\n- **Source requirement:** %s\n' "$REQ" > .supervisor/jobs/done/brief-a.md
    printf '# Brief\n## Environment\n- **Source requirement:** .supervisor/requirements/zz.md\n' > .supervisor/jobs/done/brief-other.md
    printf '# Brief\n- **Source requirement:** %s\n' "$REQ" > .supervisor/jobs/in-progress/brief-live.md
    printf '%s\n' "$RH_GOOD" > ".supervisor/automate/$RUN_ID.review-heal-result.md"
    printf '%s\n' "$SUP_GOOD" | sed 's/^  risk_classification: .*/  risk_classification: {high_risk: true}/' > ".supervisor/automate/$RUN_ID.supervisor-result.md"
    printf '{"automate_key":"%s\\u001f%s\\u001fpr7\\u001fautomate_drain\\u001fcomplete","source":"automate_drain"}\n' "$RUN_ID" "$REQ" >> .supervisor/postmortem/results.jsonl
    echo '{"automate_key":"other-run\u001fy","source":"automate_drain"}' >> .supervisor/postmortem/results.jsonl
    echo stray > stray.txt
    echo "edited readme" > README
  )
  export GH_STUB_DIR="$FX/gh"; mkdir -p "$GH_STUB_DIR"; echo '[]' > "$GH_STUB_DIR/prs.json"; : > "$GH_STUB_DIR/argv.log"
}
count_creates() { grep -c '^pr create' "$GH_STUB_DIR/argv.log" 2>/dev/null || true; }

# ---- from 01-sidecar-trail-pr.sh ----
RF_REL0=".supervisor/automate/$RUN_ID.md"

# ---- from 01-sidecar-trail-pr.sh ----
precedes() { # <regex identifying the line> <label>
  local line; line="$(grep -m1 -E "$1" "$SKILL")"
  local a="${line%%trail-pr*}" b="${line%%run-lock.sh release*}"
  if [ -n "$line" ] && [ "$a" != "$line" ] && [ "$b" != "$line" ] && [ "${#a}" -lt "${#b}" ]; then ok "$2: trail-pr before run-lock.sh release"; else no "$2: ordering not stated"; fi
}

# ---- from 02-closeout.sh ----
PRURL="https://github.com/acme/widgets/pull/7"
RF_REL=".supervisor/automate/$RUN_ID.md"

# spy copy of the scripts dir: automate-helpers.sh is a logging shim that execs
# the real helper (renamed), and captures the run-lock meta while trail-pr runs;
# notify-desktop.sh / send-webhook.sh are counters. Everything else is real.
# Every scripts-dir copy here also takes automate-helpers.d/ — the dispatcher
# sources its helper families from beside itself (parallel-automate/11).
SPYD="$TOP/spyd"; mkdir -p "$SPYD"
cp "$HERE"/*.sh "$HERE"/*.py "$SPYD/"; cp -R "$HERE/automate-helpers.d" "$SPYD/"; cp -R "$HERE/automate-trail.d" "$SPYD/"; cp -R "$HERE/setup-memory.d" "$HERE/meta-sync.d" "$HERE/automate-lanes.d" "$SPYD/"
mv "$SPYD/automate-helpers.sh" "$SPYD/automate-helpers.real.sh"
cat > "$SPYD/automate-helpers.sh" <<'SHIM'
#!/usr/bin/env bash
echo "$*" >> "$SPYLOG"
if [ "${1:-}" = trail-pr ]; then cat .supervisor/run.lock/meta >> "$SPYLOG.meta" 2>/dev/null; echo "--" >> "$SPYLOG.meta"; fi
exec bash "$(dirname "$0")/automate-helpers.real.sh" "$@"
SHIM
printf '#!/usr/bin/env bash\ncat >/dev/null\necho notify >> "$SPYLOG.notify"\nexit 0\n' > "$SPYD/notify-desktop.sh"
printf '#!/usr/bin/env bash\necho "$*" >> "$SPYLOG.webhook"\nexit 0\n' > "$SPYD/send-webhook.sh"
export SPYLOG="$TOP/spy.log"
spy_reset() { rm -f "$SPYLOG" "$SPYLOG.meta" "$SPYLOG.notify" "$SPYLOG.webhook"; }
spy_count() { grep -c "$1" "$2" 2>/dev/null || true; }

# closeout_fixture <n> [oid-override]: new_fixture, then a merged-PR world —
# feature/x pushed and SQUASH-merged into origin/main (a new commit, not the
# branch tip), the primary back on main with the PR's branch in its own
# worktree, plus an unrelated branch+worktree, and the feature PR in the stub.
closeout_fixture() {
  new_fixture "$1"
  ( cd "$P"
    git checkout -q -- README; rm -f stray.txt
    git push -q origin feature/x 2>/dev/null
    git checkout -q main
    git worktree add -q "$FX/wt-pr" feature/x 2>/dev/null
    git worktree add -q -b other "$FX/wt-other" main 2>/dev/null
  )
  git clone -q "$FX/origin.git" "$FX/merger" 2>/dev/null
  ( cd "$FX/merger" && git checkout -q main && git merge -q --squash origin/feature/x >/dev/null 2>&1 && git commit -qm "feat (#7)" && git push -q origin main 2>/dev/null )
  OID="${2:-$(git -C "$P" rev-parse feature/x)}"
  jq -n --arg u "$PRURL" --arg o "$OID" '[{number:7,url:$u,state:"MERGED",headRefName:"feature/x",headRefOid:$o}]' > "$GH_STUB_DIR/prs.json"
}
run_closeout() { (cd "$P" && bash "$SPYD/automate-helpers.sh" closeout "$RF_REL" "$REQ" "$PRURL" "$@"); }

# ---- from 02-closeout.sh ----
it_count() { jq -c 'select(.event=="item_timing")' "$1" 2>/dev/null | wc -l | tr -d ' '; }

# ---- from 02-closeout.sh ----
cur_block() { awk '/^## Current/{c=1} /^## Progress/{c=0} c' "$1"; }

# ---- from 03-stamps-gate.sh ----
stamp_req() { # <path> <status> <pr-line or empty>
  printf '# req\n\n<!-- loomwright:requirement-closeout -->\n## Status: %s\n- **Completed:** 2026-01-01T00:00:00Z\n- **Brief:** .supervisor/jobs/done/brief-a.md\n%s' "$2" "$3" > "$P/$1"
}
set_pr() { # <url> <state> [<url> <state>]
  jq -n --arg u "$1" --arg s "$2" --arg u2 "${3:-}" --arg s2 "${4:-}" \
    '[{number:7,url:$u,state:$s,headRefName:"feature/x"}] + (if $u2 == "" then [] else [{number:8,url:$u2,state:$s2,headRefName:"feature/y"}] end)' > "$GH_STUB_DIR/prs.json"
}

# ---- from 03-stamps-gate.sh ----
PRL="- **PR:** $PRURL
"

# ---- from 04-watcher-branch-mode.sh ----
BM_MEM="$HERE/setup-memory.sh"; BM_MS="$HERE/meta-sync.sh"; BMB="loomwright-meta"
# bm_switch: run history IGNORED (the post-migration shape, so a kept check-ignore drop would push
# nothing), the branch-mode block, an allowlisted ledger, and an initialised metadata branch.
bm_switch() {
  ( cd "$P"
    printf '.supervisor/\n' > .gitignore
    bash "$BM_MEM" --root "$P" apply --branch-mode "$BMB" >/dev/null 2>&1; rm -f .gitignore.backup.*
    printf '{"repo":"acme/widgets","automate_key":"%s\\u001fx","source":"automate_drain"}\n' "$RUN_ID" > .supervisor/postmortem/results.jsonl
    bash "$BM_MS" init --root "$P" --branch "$BMB" >/dev/null 2>&1 )
}
bm_tree() { git --git-dir="$FX/origin.git" ls-tree -r --name-only "refs/heads/$BMB" 2>/dev/null; }
bm_show() { git --git-dir="$FX/origin.git" show "refs/heads/$BMB:$1" 2>/dev/null; }
bm_trail() { (cd "$P" && bash "${BM_HELPER:-$H}" trail-pr "$RF_REL0" --reason "${1:-done}"); }

# ---- from 01-sidecar-trail-pr.sh (its K legs; 04-watcher-branch-mode reads $nopark too) ----
sect="$(awk '/^### Trail PR after merge and at run end/{s=1;next} s&&/^##/{exit} s' "$SKILL")"
when="$(grep -m1 -F -- '- **When — this is the ONE authoritative trigger list' <<<"$sect")"
nopark="${when#*No park calls it:\*\*}"
