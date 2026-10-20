#!/usr/bin/env bash
# migrate-branch-mode.sh — take ANY repo from the default `/setup memory` mode to BRANCH MODE (run
# history lives on a metadata branch synced by meta-sync.sh), one human-gated, resumable step at a
# time. Deterministic, dry-run first, and it stops at every owner-only step: it NEVER merges a pull
# request and NEVER creates or edits a ruleset. The only `git add` / `git rm` / `git commit` it runs
# happen on a NEW branch (mode-pr, untrack-pr, rollback); the default branch is never committed to.
#
# Usage:
#   migrate-branch-mode.sh <step> [--root <checkout>] [--branch <name>] [--repo <owner/repo>]
#
#   plan                read-only: detect the case and print the step sequence. Detects "already
#                       migrated" BEFORE any precondition (a run lock is legitimately held during an
#                       /automate run). Writes nothing at all — no state file, no ref, no index.
#                         fresh    no run-history path tracked; mode `off`
#                         history  run-history paths tracked (whatever the mode line says)
#                         already  mode `on <b>` and no run history tracked -> `already in branch
#                                  mode on <b>` (a tracked learning store never changes the case)
#                         refused  mode `unknown <reason>` -> exit 1 naming the reason
#                       It also prints the metadata branch init defaults to (see init).
#   preflight           print every precondition with its result; record PASS/FAIL. THE GATE: every
#                       step EXCEPT `plan`, `state` and `rollback` refuses (exit 1, nothing changed)
#                       while the recorded preflight result is not PASS. `plan` and `state` are
#                       read-only; `rollback` undoes an already-merged migration (possibly after a
#                       later preflight FAILed) and carries its own guards instead: a recorded
#                       branch, on <default>, clean, fast-forwarded, --commit a real commit. This
#                       paragraph is the one authoritative statement of the gate's exemptions.
#   scrub               dry-run meta-sync.sh's scrub over every would-be-pushed file (list-managed);
#                       a hit stops the flow BEFORE init with file, line and rule.
#   rehearse [--branch <b>] run the sibling meta-sync-rehearsal.sh (scratch clone + local bare remote)
#                       with the RECORDED --branch (before init: <b>, else init's default); a <b>
#                       disagreeing with the recorded name is refused. No harness -> exit 1. A
#                       half-migrated checkout (mode line `on <b>`, history still tracked) is
#                       rehearsed too: the harness resets its SCRATCH clone's mode block to off.
#   init [--branch <b>] vet <b> with `setup-memory.sh valid-branch` BEFORE anything is written, then
#                       `meta-sync.sh init --branch <b>`; records <b>. Default <b>: the mode line's
#                       branch when `setup-memory.sh mode` reads `on <x>` (a half-migrated repo),
#                       else loomwright-meta. An explicit --branch disagreeing with `on <x>` is
#                       refused (nothing written) — never silently overridden.
#   protect [--verify]  print the exact ruleset JSON (target the branch; block deletion and
#                       non-fast-forward; no bypass) and the `gh api` command the OWNER runs.
#                       --verify reads `gh api repos/<o>/<r>/rulesets` (+ each ruleset) and records
#                       PASS only when an active ruleset covers the branch with both rules, no bypass.
#                       A PASS supersedes a recorded waiver (its waive keys are deleted); a FAIL
#                       leaves a recorded waiver standing (protect stays WAIVED, exit 1).
#   protect --waive --reason <text>
#                       the OWNER's recorded decision to run UNPROTECTED where GitHub cannot apply a
#                       ruleset — never a silent skip, and never chosen by the script. EVIDENCE-GATED
#                       (the decision): it reads `gh api repos/<o>/<r>/rulesets` and waives ONLY when
#                       GitHub answers HTTP 403 (the JSON body's `"status": "403"` — e.g. "Upgrade to
#                       GitHub Pro or make this repository public to enable this feature." on a
#                       private Free-plan repo). A readable ruleset list means the feature exists, so
#                       the owner can create the ruleset: refused. Any other failure (network, 401,
#                       404, unparseable) proves nothing: refused. Matching the status, not the
#                       message text, keeps the gate stable if GitHub rewords the message; a 403
#                       for a missing permission is waivable too, because the reason is recorded
#                       and shown to the merger — except a rate-limit 403 (the message names a rate
#                       limit), which says nothing about rulesets: refused. Needs a non-empty --reason (whitespace collapsed to
#                       one line). Records protect=WAIVED + protect_waive_reason / _evidence / _at,
#                       and prints the exposure: the branch can be deleted or force-pushed by anyone
#                       with push access; meta-sync.sh itself never force-pushes, and every synced
#                       checkout keeps its files on disk. Refused once protect is PASS.
#   mode-pr             (fresh) on a NEW branch: `setup-memory.sh apply --branch-mode <b>`, one commit
#                       of `.gitignore` only, push, open a PR — never merged. Returns to the default.
#   seed                (history) `meta-sync.sh push --branch <b>`, then the A/B check against the
#                       CURRENT origin/<default> (A = `list-managed --tracked --run-history`, B =
#                       the WHOLE branch tree MINUS its learning-store paths — both sides are run
#                       history: learning stores travel only with consent and the migration never
#                       untracks one; an unmanaged stray on the branch stays in B, so it still
#                       breaks A = B):
#                       A = B, every blob equal, nothing on the branch but the managed kinds
#                       (*.md, results.jsonl, brain-baseline.jsonl, .provenance.jsonl,
#                       *.dismissed-decisions). "A = B" in full is B = A + U: U = the managed run
#                       history on disk that git does NOT track (the default block keeps every
#                       automate/<run>.dismissed-decisions ledger ignored, and the postmortem ledger
#                       while the allowlist gate fails), which the push sends too; each U blob must
#                       equal the local file. U is listed, never untracked, and stays on disk.
#                       Tracked .supervisor/ paths outside the run-history set (a tracked learning
#                       store included) are LISTED for an owner decision, never dropped or
#                       untracked; git alone owns a tracked learning store from then on —
#                       meta-sync.sh pull / push leave it alone (`learning_tracked`), so a branch
#                       copy that diverges never dirties after-merge's or rollback's clean tree.
#                       A != B stops the flow before untrack-pr.
#   untrack-pr          (history) on a NEW branch: `git rm -r --cached` of the seeded A set, THEN the
#                       branch-mode block (so apply's readiness verify judges the tree being committed
#                       — a still-tracked ledger would read as committable), one commit, push, open a
#                       PR carrying the A/B counts, the empty diffs, the pre-migration SHA and the
#                       verify-pr instruction — never merged.
#   verify-pr <n>       run IMMEDIATELY before merging PR <n>: fast-forward to the then-current
#                       default, push anything new to the branch, repeat the seed check, and check
#                       the PR untracks every tracked managed path.
#   after-merge         `git pull`; (history) PROVE the untrack PR merged before anything else — a
#                       path of this round's A set (a.list) still tracked, with the PR's head commit
#                       not in HEAD, means it is still open: refuse, recording nothing (verify_pr
#                       PASS stays; no followup) — the mode line alone is no proof. Then put back
#                       the run-history files the pull deleted (from the
#                       pre-pull commit, which verify-pr proved equal to the branch), `meta-sync.sh
#                       pull --branch <b>`, confirm the files are back, NO managed path is still
#                       tracked (`list-managed --tracked --run-history` — catches a file committed after verify-pr;
#                       a FAIL there records followup=1 and marks seed / untrack_pr / verify_pr
#                       STALE, so recovery re-runs seed -> untrack-pr -> verify-pr, and only in that
#                       recorded follow-up round (followup=1 AND <default> already on <b>) does the
#                       A/B check accept A ⊆ B — a first migration always needs A = B) and
#                       `git status --porcelain` is empty; prints the two commands every other
#                       checkout must run.
#   rollback --commit <sha>
#                       the corrected #361 recipe on a NEW branch: push local edits to the branch,
#                       `git revert --no-commit` the untrack commit, re-track the CURRENT branch files
#                       (`git checkout <branch tip> -- <every branch path>`), drop paths deleted on
#                       the branch since migration, commit, push, open a PR — never merged. Every
#                       branch path EXCEPT the learning stores is re-tracked: the migration never
#                       untracks one (twin contracts, provenance, proposals, eval files), so a
#                       rollback never commits a branch learning store to the default branch; one
#                       tracked before the migration stays tracked, and none is deleted from disk.
#   state               print the state file and the next step (resume point).
#
#   --root    checkout (default: `git rev-parse --show-toplevel` of $PWD)
#   --branch  metadata branch; `init` / `rehearse` only (later steps use the RECORDED name, passed as --branch
#             to EVERY meta-sync.sh call — never a fallback to loomwright-meta)
#   --repo    owner/repo for `gh` (default: parsed from the origin URL); recorded once given
#   --waive / --reason <text>   `protect` only (above); --reason without --waive is a usage error
#
# protect=WAIVED satisfies every gate protect=PASS does (mode-pr, seed) and counts as done for
# `state`; the mode-pr / untrack-pr bodies then say the branch is UNPROTECTED and quote the reason,
# `state` and after-merge repeat the warning, and rollback (which needs no protect result) is
# unchanged — its push, like every meta-sync.sh push, is fast-forward only.
#
# STATE FILE — `<root>/.supervisor/migrate-branch-mode/state` (preflight refuses unless it is
# gitignored). Plain `key=value` lines, one key per line, last write wins, values single-line:
#   case=fresh|history   default=<default branch>   repo=<owner/repo>   branch=<metadata branch>
#   pre_migration_sha=<HEAD at preflight>
#   step results: preflight scrub rehearse init protect mode_pr seed untrack_pr verify_pr
#                 after_merge rollback  =  PASS | FAIL (protect: PRINTED before --verify,
#                 WAIVED after `protect --waive`;
#                 seed / untrack_pr / verify_pr: STALE once a later step invalidated them — a
#                 re-run seed staled untrack_pr + verify_pr, a re-cut untrack-pr staled verify_pr,
#                 an after-merge tracked-path FAIL staled all three)
#   seed_a / seed_u / seed_b=<counts>  seed_sha=<origin/<default> the seed check ran against>
#   seed_check=equal | subset (the A/B relation seed proved)   verify_pr_sha=<HEAD at verify-pr PASS>
#   followup=1  after-merge found managed paths still tracked after a merged untrack PR (merge
#               proven: no a.list path still tracked, or the PR head is in HEAD) — the only
#               evidence that enables the A ⊆ B follow-up check. Deleted by rollback, and by a
#               preflight unless after_merge is still FAIL (the fresh-case mid-round re-preflight)
#   mode_pr_branch / untrack_branch / rollback_branch=<new branch>  pr_mode / pr_untrack /
#   pr_rollback=<PR url>  backup_mode_pr / backup_untrack_pr=<moved .gitignore.backup.<ts> path>
#   protect_waive_reason=<the owner's reason, one line>  protect_waive_evidence=<GitHub's 403
#   message, one line>  protect_waive_at=<UTC ISO-8601>  (written by protect --waive; deleted by a
#   protect --verify PASS)
# Side files in the same folder: a.list (the A set), u.list (the U set), ab-names.diff,
# ab-blobs.diff, extra.list, ruleset.json, *.body (PR bodies), backups. Nothing there is ever tracked.
#
# Exit: 0 step passed; 1 refused / failed (a reason line says which); 2 usage error.
# Portability: bash 3.2 + BSD userland (no `xargs -r`, no `sed -i`, no `timeout`).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MS="$HERE/meta-sync.sh"
SM="$HERE/setup-memory.sh"
RL="$HERE/run-lock.sh"
AH="$HERE/automate-helpers.sh"
REH="$HERE/meta-sync-rehearsal.sh"
GH="${LOOMWRIGHT_GH_BIN:-gh}"

say() { printf 'migrate-branch-mode: %s\n' "$*"; }
die() { # die <message> — the reason line, then exit 1. The step's telemetry code (evt below) is
  # the one a site set, else the message CLASS: never the message text itself.
  if [ -z "${EVT_CODE:-}" ]; then
    case "$*" in
      refused*|*": refused"*) EVT_CODE=refused ;;
      *": FAIL"*) EVT_CODE=step_failed ;;
      *) EVT_CODE=error ;;
    esac
  fi
  printf 'migrate-branch-mode: %s\n' "$*" >&2; exit 1
}
# ---- script-event telemetry (docs/TELEMETRY.md §"Script events") ---------------------------------
# Every mutating step reports pass / fail to emit-script-event.sh from the EXIT trap armed at the
# dispatch below — plugin facts only: the step, a plugin-defined code, integer counts and managed-
# file KIND counts. Opt-in like all telemetry (nothing is sent without user-scope consent), and
# fire-and-forget: the trap keeps the step's exit code and prints nothing. plan / state are read-
# only and never emit (plan writes nothing at all). A command substitution or `( )` subshell that
# dies does not run the EXIT trap (bash), so only the step's own exit reports. A step that exits 0
# on a recorded owner override (protect --waive) sets EVT_WARN: it reports `warn` with that code,
# never a `pass` that would close the step's open threads as healed.
EVT_CODE=""; EVT_ARGS=""; EVT_WARN=""
evt() { # evt <code> [--count k=v | --kind g.k=n]... — set the code AND counts a following failure
  # reports. It REPLACES both (never accumulates), so a later, unrelated failure in the same step
  # never reports counts an earlier check left behind.
  EVT_CODE="$1"; EVT_ARGS=""; shift
  while [ $# -gt 0 ]; do EVT_ARGS="$EVT_ARGS$1"$'\n'; shift; done
}
evt_emit() { # evt_emit <exit code> — the EXIT trap body
  local rc="$1" outcome code
  case "$rc" in 0) outcome=pass; code=ok; [ -z "$EVT_WARN" ] || { outcome=warn; code="$EVT_WARN"; } ;; 1) outcome=fail; code="${EVT_CODE:-error}" ;; *) return 0 ;; esac
  local IFS=$'\n' a args=()
  for a in $EVT_ARGS; do [ -n "$a" ] && args+=("$a"); done
  bash "$HERE/emit-script-event.sh" --root "$ROOT" migrate-branch-mode "$STEP" "$outcome" "$code" ${args[@]+"${args[@]}"} >/dev/null 2>&1 || true
}
kind_of() { # kind_of <path> — the managed-file KIND enum the telemetry core accepts
  case "$1" in
    *.dismissed-decisions) echo dismissed-decisions ;;
    */brain-baseline.jsonl|brain-baseline.jsonl) echo brain-baseline-jsonl ;;
    */results.jsonl|results.jsonl) echo results-jsonl ;;
    */.provenance.jsonl|.provenance.jsonl) echo provenance-jsonl ;;
    *.md) echo md ;;
    *) echo other ;;
  esac
}
kind_counts() { # kind_counts <group> <file of paths> — `--kind <group>.<kind>=<n>` lines
  local p; while IFS= read -r p; do [ -n "$p" ] && kind_of "$p"; done < "$2" | env LC_ALL=C sort | uniq -c \
    | while read -r n k; do printf -- '--kind\n%s.%s=%s\n' "$1" "$k" "$n"; done
}
usage() { sed -n '2,/^# Portability/p' "$0" | sed 's/^# \{0,1\}//'; }

STEP="${1:-}"; [ $# -gt 0 ] && shift
ROOT=""; OPT_BRANCH=""; OPT_REPO=""; OPT_VERIFY=0; OPT_COMMIT=""; POS=""; OPT_WAIVE=0; OPT_REASON=""; HAVE_REASON=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root|--branch|--repo|--commit)
      [ $# -ge 2 ] && [ -n "$2" ] && [ "${2#-}" = "$2" ] || { echo "migrate-branch-mode: $1 needs a value" >&2; exit 2; }
      case "$1" in --root) ROOT="$2" ;; --branch) OPT_BRANCH="$2" ;; --repo) OPT_REPO="$2" ;; --commit) OPT_COMMIT="$2" ;; esac
      shift 2 ;;
    --verify) OPT_VERIFY=1; shift ;;
    --waive) OPT_WAIVE=1; shift ;;
    --reason) # its own case: a reason may be empty or blank here, so protect --waive refuses it by name
      [ $# -ge 2 ] && [ "${2#-}" = "$2" ] || { echo "migrate-branch-mode: --reason needs a value" >&2; exit 2; }
      OPT_REASON="$2"; HAVE_REASON=1; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "migrate-branch-mode: unknown flag $1" >&2; exit 2 ;;
    *) [ -z "$POS" ] || { echo "migrate-branch-mode: unexpected argument $1" >&2; exit 2; }; POS="$1"; shift ;;
  esac
done
case "$STEP" in
  -h|--help|'') usage; [ -n "$STEP" ]; exit $? ;;
esac
if [ "$OPT_WAIVE" -eq 1 ] || [ "$HAVE_REASON" -eq 1 ]; then
  [ "$STEP" = protect ] || { echo "migrate-branch-mode: --waive / --reason belong to the protect step" >&2; exit 2; }
  [ "$OPT_WAIVE" -eq 1 ] || { echo "migrate-branch-mode: --reason needs --waive" >&2; exit 2; }
  [ "$OPT_VERIFY" -eq 0 ] || { echo "migrate-branch-mode: --waive and --verify are separate invocations" >&2; exit 2; }
fi

[ -n "$ROOT" ] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || true
[ -n "$ROOT" ] && [ -d "$ROOT" ] || die "not inside a git checkout (use --root)"
ROOT="$(cd "$ROOT" && pwd -P)"
g() { git -C "$ROOT" -c core.quotepath=off "$@"; }
SD="$ROOT/.supervisor/migrate-branch-mode"
SF="$SD/state"

# ---- state file ----------------------------------------------------------------------------------
state_get() { [ -f "$SF" ] && sed -n "s/^$1=//p" "$SF" | tail -n 1; return 0; }
state_set() {
  mkdir -p "$SD" || die "cannot create $SD"
  { [ -f "$SF" ] && grep -v "^$1=" "$SF"; printf '%s=%s\n' "$1" "$2"; } > "$SF.tmp.$$" && mv "$SF.tmp.$$" "$SF"
}
state_del() { # state_del <key> — drop every line of <key> (a no-op when absent)
  [ -f "$SF" ] || return 0
  { grep -v "^$1=" "$SF"; true; } > "$SF.tmp.$$" && mv "$SF.tmp.$$" "$SF"
}
need() { # need <key> <accepted value>... — refuse (nothing changed) unless the recorded result matches
  local k="$1" v; shift; v="$(state_get "$k")"
  for want in "$@"; do [ "$v" = "$want" ] && return 0; done
  evt "needs_$k"
  die "refused: step '$k' is '${v:-not run}' (needs $*); run it first — nothing was changed"
}
need_preflight() { need preflight PASS; }
stale_if_recorded() { # stale_if_recorded <key>... — a downstream result that no longer describes this flow's latest round
  local k; for k in "$@"; do [ -n "$(state_get "$k")" ] && state_set "$k" STALE; done; return 0
}
rec_branch() { local b; b="$(state_get branch)"; [ -n "$b" ] || die "refused: no metadata branch recorded — run init first"; printf '%s' "$b"; }

# ---- repo facts ----------------------------------------------------------------------------------
default_branch() {
  local d; d="$(state_get default)"
  [ -n "$d" ] || { d="$(g symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)"; d="${d#origin/}"; }
  [ -n "$d" ] || d="$(g ls-remote --symref origin HEAD 2>/dev/null | sed -n 's|^ref: refs/heads/\([^	]*\)	HEAD$|\1|p' | head -n 1)"
  printf '%s' "$d"
}
repo_slug() {
  local r; r="${OPT_REPO:-$(state_get repo)}"
  if [ -z "$r" ]; then
    r="$(g remote get-url origin 2>/dev/null | sed -n -e 's|^git@[^:]*:\(.*\)$|\1|p' -e 's|^[a-z+]*://[^/]*/\(.*\)$|\1|p' | head -n 1)"
    r="${r%.git}"
  fi
  case "$r" in */*/*|''|/*) printf '' ;; */*) printf '%s' "$r" ;; *) printf '' ;; esac
}
ghr() { # ghr <gh args...> — gh in the checkout, scoped to the recorded repo when known
  local r; r="$(repo_slug)"
  if [ -n "$r" ] && [ "$1" = "pr" ]; then local sub="$2"; shift 2; (cd "$ROOT" && "$GH" pr "$sub" --repo "$r" "$@"); else (cd "$ROOT" && "$GH" "$@"); fi
}
read_mode() { bash "$SM" --root "$ROOT" mode 2>/dev/null | head -n 1; }
mode_branch() { local m; m="$(read_mode)"; case "$m" in "on "*) printf '%s' "${m#on }" ;; esac; return 0; } # <x> of `on <x>`, else empty
init_default_branch() { local x; x="$(mode_branch)"; printf '%s' "${x:-loomwright-meta}"; } # what init records without --branch
# tracked_managed — the TRACKED RUN-HISTORY paths: the one set this flow moves to the branch and
# untracks. Every consumer (detect_case, ab_check's A, untrack-pr via a.list, after-merge's
# re-checks) compares run history only. A TRACKED learning store (twin contracts, provenance,
# proposals, eval files) is never in it: the migration never untracks one — it stays tracked and
# ab_check lists it as an OWNER DECISION extra, exactly as before the managed set grew; meta-sync.sh
# leaves a tracked learning store to git (its TRACKED LEARNING STORES rule), so no pull dirties it.
tracked_managed() { bash "$MS" list-managed --tracked --run-history --root "$ROOT"; }
# tracked_learning <out> — the TRACKED learning-store paths (index), sorted: the managed set minus
# run history, read through the same predicate (rb_retrack_from_branch never deletes one from disk)
tracked_learning() {
  bash "$MS" list-managed --tracked --root "$ROOT" | env LC_ALL=C sort > "$1.all" || return 1
  tracked_managed | env LC_ALL=C sort > "$1.rh" || return 1
  env LC_ALL=C comm -23 "$1.all" "$1.rh" > "$1" || return 1
  rm -f "$1.all" "$1.rh"
}
# branch_learning <tree-ish> <out> — the LEARNING-STORE paths of that tree, sorted: its managed set
# minus its run-history set (meta-sync.sh is the one predicate; nothing here restates it). The ONE
# excluded class — callers subtract it from the whole tree, so unmanaged strays are never dropped.
branch_learning() {
  bash "$MS" list-managed --tree "$1" --root "$ROOT" | env LC_ALL=C sort > "$2.all" || return 1
  bash "$MS" list-managed --tree "$1" --run-history --root "$ROOT" | env LC_ALL=C sort > "$2.rh" || return 1
  env LC_ALL=C comm -23 "$2.all" "$2.rh" > "$2" || return 1
  rm -f "$2.all" "$2.rh"
}
detect_case() { # prints fresh | history | already <b> | unknown <reason>; exit 1 when unreadable
  local mode tm
  mode="$(read_mode)"
  case "$mode" in off|on\ *) ;; unknown\ *) printf '%s' "$mode"; return 0 ;; *) printf 'unknown unreadable mode line: %s' "${mode:-<empty>}"; return 0 ;; esac
  tm="$(tracked_managed)" || { printf 'unknown list-managed --tracked --run-history failed'; return 0; }
  if [ -n "$tm" ]; then printf 'history'
  elif [ "$mode" = off ]; then printf 'fresh'
  else printf 'already %s' "${mode#on }"; fi
}
steps_for() {
  case "$1" in
    fresh)   echo "preflight -> scrub -> init -> protect (owner) -> protect --verify -> mode-pr (mode block; owner merges) -> after-merge -> done" ;;
    history) echo "preflight -> scrub -> rehearse -> init -> protect (owner) -> protect --verify -> seed -> untrack-pr -> verify-pr <n> (immediately before the owner merges) -> after-merge -> done" ;;
  esac
}
seq_keys() { case "$1" in fresh) echo "preflight scrub init protect mode_pr after_merge" ;; *) echo "preflight scrub init protect seed untrack_pr verify_pr after_merge" ;; esac; }
on_default_clean() { # refuse unless on <default>, clean, HEAD fast-forwarded to origin/<default>
  local d="$1" cur
  cur="$(g symbolic-ref -q --short HEAD)"; [ "$cur" = "$d" ] || die "refused: on '${cur:-detached}', not the default branch '$d'"
  [ -z "$(g status --porcelain)" ] || die "refused: the working tree is not clean"
  g fetch -q origin "+refs/heads/$d:refs/remotes/origin/$d" || die "refused: could not fetch origin/$d"
  if [ "$(g rev-parse HEAD)" != "$(g rev-parse "refs/remotes/origin/$d")" ]; then
    g merge -q --ff-only "refs/remotes/origin/$d" >/dev/null 2>&1 || die "refused: $d cannot fast-forward to origin/$d"
  fi
}
fetch_meta() { g fetch -q origin "+refs/heads/$1:refs/remotes/origin/$1" || die "could not fetch origin/$1"; }
new_branch_name() { # new_branch_name <base> — a name free locally and on origin
  local n="$1" i=2
  while g rev-parse -q --verify "refs/heads/$n" >/dev/null || [ -n "$(g ls-remote --heads origin "$n" 2>/dev/null)" ]; do n="$1-$i"; i=$((i+1)); done
  printf '%s' "$n"
}
untrack_a_set() { # `git rm -r --cached` every path of the seeded A set (a.list) — the files stay on disk
  tr '\n' '\0' < "$SD/a.list" | (cd "$ROOT" && xargs -0 git rm -r -q --cached --)
}
apply_mode_block() { # apply_mode_block <b> <state key for the backup> — on the CURRENT (new) branch
  local b="$1" out bk dest
  out="$(LOOMWRIGHT_SCRIPT_EVENT_CALLER="migrate-branch-mode.$STEP" bash "$SM" --root "$ROOT" apply --branch-mode "$b" 2>&1)"
  printf '%s\n' "$out" | grep -E '^ *(apply|backup):' | sed 's/^ */  /'
  [ "$(read_mode)" = "on $b" ] || { echo "migrate-branch-mode: apply did not leave the mode line at 'on $b'" >&2; return 1; }
  bk="$(printf '%s\n' "$out" | sed -n 's/^  backup:  \(.*\)   (delete it.*$/\1/p' | head -n 1)"
  if [ -n "$bk" ]; then
    case "$bk" in /*) ;; *) bk="$ROOT/$bk" ;; esac
    if [ -f "$bk" ]; then
      mkdir -p "$SD"; dest="$SD/$(basename "$bk")"
      mv "$bk" "$dest" || return 1
      state_set "$2" "$dest"; say "moved apply's backup to $dest"
    fi
  fi
  return 0
}
pr_create() { # pr_create <head> <base> <title> <body file> — prints the PR url; never merges
  ghr pr create --head "$1" --base "$2" --title "$3" --body-file "$4" | tail -n 1
}

# ---- A/B check -----------------------------------------------------------------------------------
# ab_check <b> <default> — A = the tracked RUN-HISTORY paths at HEAD (== origin/<default>;
# tracked_managed), B = the WHOLE branch tree MINUS its learning-store paths. Both sides compare run
# history only: a learning store on the branch travels with consent and is subtracted from B, and a
# TRACKED learning store is not in A (tracked_managed is run-history only) — it lands in extra.list
# as an OWNER DECISION and stays tracked. B is "everything but the excluded class", never "only the
# included class": an UNMANAGED entry on the branch (a stray NOTES.md, jobs/pending/x.md) stays in
# B, so it still breaks A = B.
# U = the managed run history on DISK that git does not track (u.list): seed's push sends the LOCAL
# managed set, and the default block keeps some of it ignored on purpose — every
# `.supervisor/automate/<run>.dismissed-decisions` ledger, and the postmortem ledger while the repo
# allowlist gate fails — so those files reach B without ever being in A. The first-round relation is
# therefore B = A + U exactly (names, and every blob: A's from HEAD, U's hashed from disk), not
# A = B: `A = B` assumed U is empty, and every repo whose /automate run recorded a dismissed-findings
# decision failed seed on it. U is never untracked (it is not tracked) and stays on disk. A branch
# entry that is neither in A nor a local file (another checkout's push, a stray) still breaks it.
ab_check() {
  local b="$1" d="$2" an un bn rc=0 nonmd extra
  fetch_meta "$b"
  tracked_managed | env LC_ALL=C sort > "$SD/a.list" || { echo "migrate-branch-mode: list-managed --tracked --run-history failed" >&2; return 1; }
  g ls-tree -r --full-tree HEAD | awk -F'\t' 'NR==FNR { want[$0] = 1; next } ($2 in want) { split($1, m, " "); print m[3] "\t" $2 }' "$SD/a.list" - | env LC_ALL=C sort > "$SD/a.ent"
  branch_learning "refs/remotes/origin/$b" "$SD/b.learn" \
    || { echo "migrate-branch-mode: could not list the learning-store paths on origin/$b" >&2; return 1; }
  g ls-tree -r "refs/remotes/origin/$b" | awk -F'\t' '{ split($1, m, " "); print m[3] "\t" $2 }' | env LC_ALL=C sort > "$SD/b.all" \
    || { echo "migrate-branch-mode: could not read the origin/$b tree" >&2; return 1; }
  awk -F'\t' -v LS="$SD/b.learn" 'FILENAME == LS { ls[$0] = 1; next } !($2 in ls)' "$SD/b.learn" "$SD/b.all" > "$SD/b.ent"
  cut -f2 "$SD/b.ent" | env LC_ALL=C sort > "$SD/b.list"
  # U (header above): local managed run history minus A, each blob hashed from disk (--no-filters,
  # as meta-sync.sh hashes what it pushes); --stdin-paths keeps the order, so paste pairs them
  bash "$MS" list-managed --run-history --root "$ROOT" | env LC_ALL=C sort | env LC_ALL=C comm -23 - "$SD/a.list" > "$SD/u.list" \
    || { echo "migrate-branch-mode: list-managed --run-history failed" >&2; return 1; }
  : > "$SD/u.sha"
  if [ -s "$SD/u.list" ]; then
    g hash-object --no-filters --stdin-paths < "$SD/u.list" > "$SD/u.sha" \
      || { echo "migrate-branch-mode: could not hash the untracked managed files" >&2; return 1; }
  fi
  paste "$SD/u.sha" "$SD/u.list" | env LC_ALL=C sort > "$SD/u.ent"
  env LC_ALL=C sort "$SD/a.list" "$SD/u.list" > "$SD/au.list"; env LC_ALL=C sort "$SD/a.ent" "$SD/u.ent" > "$SD/au.ent"
  an="$(wc -l < "$SD/a.list" | tr -d ' ')"; un="$(wc -l < "$SD/u.list" | tr -d ' ')"; bn="$(wc -l < "$SD/b.list" | tr -d ' ')"
  say "A (tracked managed on origin/$d) = $an; U (managed run history on disk, gitignored) = $un; B (origin/$b tree) = $bn"
  [ "$un" -gt 0 ] && { say "U — pushed by seed, never tracked, so nothing to untrack; they stay on disk:"; sed 's/^/  /' "$SD/u.list"; }
  AB_REL=equal
  # A ⊆ B is accepted ONLY in a follow-up round this flow RECORDED (after-merge found paths still
  # tracked after a merged untrack PR -> followup=1) — never on the mode line alone: a first
  # migration of a half-migrated repo (mode line already `on $b`, history still tracked) needs A = B.
  if [ "$(state_get followup)" = 1 ] && [ "$(read_mode)" = "on $b" ]; then
    AB_REL=subset
    # $d is ALREADY in branch mode on $b, so B legitimately holds every earlier-migrated path too
    env LC_ALL=C comm -23 "$SD/a.list" "$SD/b.list" > "$SD/ab-names.diff"; env LC_ALL=C comm -23 "$SD/a.ent" "$SD/b.ent" > "$SD/ab-blobs.diff"
    say "follow-up round (recorded after-merge FAIL; $d already on $b): checking A is a subset of B"
  else
    diff "$SD/au.list" "$SD/b.list" > "$SD/ab-names.diff"; diff "$SD/au.ent" "$SD/b.ent" > "$SD/ab-blobs.diff"
  fi
  if [ -s "$SD/ab-names.diff" ]; then
    evt ab_names_mismatch
    if [ "$AB_REL" = subset ]; then echo "migrate-branch-mode: A ⊄ B — path(s) in A missing from B:" >&2
    elif [ "$un" -gt 0 ]; then echo "migrate-branch-mode: A + U != B — path lists differ (< A + U, > B):" >&2
    else echo "migrate-branch-mode: A != B — path lists differ:" >&2; fi
    sed 's/^/  /' "$SD/ab-names.diff" >&2; rc=1
  elif [ "$AB_REL" = subset ]; then say "A ⊆ B (B has $((bn - an)) extra) — every A path is on B"
  elif [ "$un" -gt 0 ]; then say "path lists equal: B = A + U (empty diff)"
  else say "path lists equal (empty diff)"; fi
  if [ -s "$SD/ab-blobs.diff" ]; then [ -n "$EVT_CODE" ] || evt ab_blob_mismatch; echo "migrate-branch-mode: blob mismatch:" >&2; sed 's/^/  /' "$SD/ab-blobs.diff" >&2; rc=1; else say "every blob equal (empty diff)"; fi
  # every branch entry (learning stores included) must be a managed KIND (meta-sync.sh: MANAGED SET)
  nonmd="$(cut -f2 "$SD/b.all" | grep -v -E '\.md$|(^|/)results\.jsonl$|(^|/)brain-baseline\.jsonl$|(^|/)\.provenance\.jsonl$|\.dismissed-decisions$')"
  if [ -n "$nonmd" ]; then [ -n "$EVT_CODE" ] || evt ab_nonmanaged_kind; echo "migrate-branch-mode: entries of a non-managed kind on $b:" >&2; printf '  %s\n' $nonmd >&2; rc=1; fi
  # The index read clears the caller's GIT_INDEX_FILE / GIT_DIR / GIT_WORK_TREE, as A's read does
  # (meta-sync.sh list-managed --tracked): git reads an inherited GIT_INDEX_FILE naming a missing file
  # as an EMPTY index with exit 0, which would silently report no extra tracked path.
  env -u GIT_INDEX_FILE -u GIT_DIR -u GIT_WORK_TREE git -C "$ROOT" -c core.quotepath=off ls-files -- .supervisor | env LC_ALL=C sort | env LC_ALL=C comm -23 - "$SD/a.list" > "$SD/extra.list"
  extra="$(wc -l < "$SD/extra.list" | tr -d ' ')"
  if [ "$extra" -gt 0 ]; then
    say "OWNER DECISION: $extra tracked .supervisor/ path(s) are OUTSIDE the run-history set (a tracked learning store included); they stay tracked and are NOT untracked or moved to $b by this flow:"
    sed 's/^/  /' "$SD/extra.list"
  fi
  AB_A="$an"; AB_B="$bn"; AB_U="$un"
  # telemetry for the step's failure report — ONLY when this check failed (a passing check leaves
  # nothing behind for a later, unrelated failure to carry): the set sizes and the KINDS of the paths
  # each side holds alone, and of the paths whose blobs differ — never a path. Names diff: `diff`
  # output (`<` = A [+ U] only, `>` = B only), except in a subset round, where `comm -23` wrote bare
  # A-only paths (B-only is legitimate there, so nothing is B-only); blobs diff: `<sha><TAB><path>`
  # rows (prefixed `< ` / `> ` unless subset).
  if [ "$rc" -ne 0 ]; then
    if [ "$AB_REL" = subset ]; then
      cp "$SD/ab-names.diff" "$SD/ab-a-only.list"; : > "$SD/ab-b-only.list"
    else
      sed -n 's/^> //p' "$SD/ab-names.diff" > "$SD/ab-b-only.list"; sed -n 's/^< //p' "$SD/ab-names.diff" > "$SD/ab-a-only.list"
    fi
    sed -n 's/^[<>] //; /\t/s/^[^\t]*\t//p' "$SD/ab-blobs.diff" | env LC_ALL=C sort -u > "$SD/ab-blob.list"
    evt "${EVT_CODE:-error}" --count "a=$an" --count "u=$un" --count "b=$bn" --count "extra_owner_decision=$extra" \
      $(kind_counts b_only "$SD/ab-b-only.list") $(kind_counts a_only "$SD/ab-a-only.list") $(kind_counts blob_mismatch "$SD/ab-blob.list")
  fi
  return $rc
}

# ---- steps ---------------------------------------------------------------------------------------
cmd_plan() {
  local c b
  c="$(detect_case)"
  case "$c" in
    unknown\ *) die "refused: mode is ${c} — fix the managed block (setup-memory.sh check) first" ;;
    already\ *) b="${c#already }"; say "already in branch mode on $b — nothing to do"; return 0 ;;
  esac
  say "case: $c"
  say "default branch: $(default_branch)"
  local mb; mb="$(mode_branch)"
  if [ -n "$mb" ]; then say "metadata branch: $mb (init's default, from the mode line 'on $mb'; init refuses any other --branch)"
  else say "metadata branch: $(init_default_branch) (init's default; init --branch <name> chooses another)"; fi
  say "steps: $(steps_for "$c")"
  [ -f "$SF" ] && say "state file present — run 'state' to see the resume point"
  return 0
}

cmd_preflight() {
  local d cur fails=0 lk wt prs c
  check() { if [ "$1" -eq 0 ]; then echo "  [PASS] $2"; else echo "  [FAIL] $2"; fails=$((fails+1)); fi; }
  c="$(detect_case)"
  d="$(default_branch)"
  [ -n "$d" ] && check 0 "default branch resolved ($d)" || check 1 "default branch resolved (origin/HEAD unreadable)"
  case "$c" in fresh|history) check 0 "case detected ($c)" ;; *) check 1 "case detected (got: $c)" ;; esac
  cur="$(g symbolic-ref -q --short HEAD)"
  [ -n "$d" ] && [ "$cur" = "$d" ]; check $? "on the default branch (on '${cur:-detached}')"
  [ -z "$(g status --porcelain 2>/dev/null)" ]; check $? "working tree clean"
  if [ -n "$d" ] && g fetch -q origin "+refs/heads/$d:refs/remotes/origin/$d" 2>/dev/null; then
    [ "$(g rev-parse HEAD)" = "$(g rev-parse "refs/remotes/origin/$d" 2>/dev/null)" ]; check $? "HEAD equals origin/$d"
  else check 1 "HEAD equals origin/$d (fetch failed)"; fi
  if [ -d "$ROOT/.supervisor/automate" ]; then
    lk="$(bash "$AH" resume-glob "$ROOT/.supervisor/automate" 2>/dev/null)"; [ $? -eq 0 ] && [ -z "$lk" ]
    check $? "no /automate run in flight (resume-glob: ${lk:-none})"
  else check 0 "no /automate run in flight (no .supervisor/automate)"; fi
  lk="$(bash "$RL" status --root "$ROOT" 2>/dev/null)"
  [ "$lk" = "UNLOCKED" ]; check $? "run lock free (run-lock.sh status: ${lk:-<no answer>})"
  if prs="$(ghr pr list --state open --json headRefName --jq '.[].headRefName' 2>/dev/null)"; then
    prs="$(printf '%s\n' "$prs" | grep -E '^chore/.*-trail-' | tr '\n' ' ')"
    [ -z "$prs" ]; check $? "no open chore/*-trail-* PR (${prs:-none})"
  else check 1 "no open chore/*-trail-* PR (gh pr list failed)"; fi
  wt="$(g worktree list --porcelain | sed -n 's/^worktree //p' | while IFS= read -r p; do
          [ "$(cd "$p" 2>/dev/null && pwd -P)" = "$ROOT" ] && continue
          [ -d "$p" ] && [ -n "$(git -C "$p" status --porcelain 2>/dev/null)" ] && printf '%s ' "$p"
        done)"
  [ -z "$wt" ]; check $? "no dirty linked worktree (${wt:-none})"
  mkdir -p "$SD" && g check-ignore -q ".supervisor/migrate-branch-mode/state"; check $? "state file is gitignored"
  [ -n "$(repo_slug)" ]; check $? "owner/repo known for gh (${OPT_REPO:-$(repo_slug)}; --repo to set)"
  if [ "$fails" -gt 0 ]; then
    g check-ignore -q ".supervisor/migrate-branch-mode/state" && state_set preflight FAIL
    evt preflight_checks_failed --count "failed=$fails"
    say "preflight: FAIL ($fails check(s) failed)"; exit 1
  fi
  state_set preflight PASS; state_set case "$c"; state_set default "$d"
  state_set repo "$(repo_slug)"; state_set pre_migration_sha "$(g rev-parse HEAD)"
  # followup=1 survives a preflight ONLY while the after-merge that recorded it is still the open
  # FAIL (the fresh-case recovery re-runs preflight mid-round); any other preflight starts a new
  # migration, which needs A = B
  [ "$(state_get followup)" = 1 ] && [ "$(state_get after_merge)" = FAIL ] || state_del followup
  say "preflight: PASS"
}

cmd_scrub() {
  need_preflight
  bash "$MS" list-managed --root "$ROOT" > "$SD/push.list" || { state_set scrub FAIL; die "list-managed failed"; }
  if [ ! -s "$SD/push.list" ]; then state_set scrub PASS; say "scrub: PASS (no run-history file to push)"; return 0; fi
  if bash "$MS" scrub --paths-from "$SD/push.list" --root "$ROOT"; then
    state_set scrub PASS; say "scrub: PASS"
  else
    state_set scrub FAIL; evt scrub_hit; die "scrub: FAIL — the hits above (file:line: rule) must be fixed before init; nothing was pushed"
  fi
}

cmd_rehearse() {
  need_preflight
  if [ ! -f "$REH" ]; then state_set rehearse FAIL; die "rehearse: the harness is not available ($(basename "$REH") missing)"; fi
  local b rec; rec="$(state_get branch)"; b="${OPT_BRANCH:-$rec}"
  [ -z "$rec" ] || [ "$b" = "$rec" ] || die "refused: --branch '$b' disagrees with the recorded branch '$rec' — nothing was run"
  b="${b:-$(init_default_branch)}" # before init nothing is recorded: rehearse the name init would default to
  bash "$SM" valid-branch "$b" || die "refused: '$b' is not a valid metadata branch name — nothing was run"
  say "rehearsing on a scratch clone + local bare remote with --branch $b (the real remote is never touched)"
  if bash "$REH" --root "$ROOT" --branch "$b"; then state_set rehearse PASS; say "rehearse: PASS"
  else state_set rehearse FAIL; evt rehearse_failed; die "rehearse: FAIL"; fi
}

cmd_init() {
  need_preflight; need scrub PASS
  local b mb rec
  mb="$(mode_branch)"; b="${OPT_BRANCH:-$(init_default_branch)}"
  bash "$SM" valid-branch "$b" || die "refused: '$b' is not a valid metadata branch name — nothing was written"
  # a half-migrated repo already names its branch in the tracked mode line: a different name would
  # seed one branch while the merged block points every checkout at another
  [ -z "$mb" ] || [ "$b" = "$mb" ] || die "refused: --branch '$b' disagrees with the mode line 'on $mb' already in .gitignore — use --branch $mb (or omit it); nothing was written"
  rec="$(state_get branch)"
  if [ -n "$(g ls-remote --heads origin "$b" 2>/dev/null)" ]; then
    [ "$rec" = "$b" ] && [ "$(state_get init)" = PASS ] && { say "init: PASS (origin/$b already created by this flow)"; return 0; }
    die "refused: origin already has a branch '$b' this flow did not create — pick another name or decide by hand"
  fi
  state_set branch "$b"
  if bash "$MS" init --branch "$b" --root "$ROOT"; then state_set init PASS; say "init: PASS (origin/$b created; name recorded)"
  else state_set init FAIL; die "init: FAIL (meta-sync.sh init --branch $b)"; fi
}

cmd_protect() {
  need_preflight; need init PASS
  local b r rid ok=0 j
  b="$(rec_branch)" || exit 1; r="$(repo_slug)"
  [ "$OPT_WAIVE" -eq 0 ] || { protect_waive "$b" "$r"; return $?; }
  if [ "$OPT_VERIFY" -eq 0 ]; then
    cat > "$SD/ruleset.json" <<EOF
{
  "name": "loomwright-metadata-branch-$b",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/heads/$b"], "exclude": [] } },
  "rules": [ { "type": "deletion" }, { "type": "non_fast_forward" } ],
  "bypass_actors": []
}
EOF
    say "OWNER STEP — protect origin/$b with this ruleset (this script never creates or edits one):"
    sed 's/^/  /' "$SD/ruleset.json"
    say "run:  gh api --method POST repos/${r:-<owner>/<repo>}/rulesets --input $SD/ruleset.json"
    say "then: migrate-branch-mode.sh protect --verify"
    say "(only when GitHub refuses rulesets on this repo with HTTP 403: the OWNER may instead record migrate-branch-mode.sh protect --waive --reason <text>)"
    case "$(state_get protect)" in PASS|WAIVED) ;; *) state_set protect PRINTED ;; esac
    return 0
  fi
  command -v jq >/dev/null 2>&1 || verify_fail "jq is required"
  [ -n "$r" ] || verify_fail "owner/repo unknown (--repo)"
  j="$(ghr api "repos/$r/rulesets")" || verify_fail "gh api repos/$r/rulesets failed"
  for rid in $(printf '%s' "$j" | jq -r '.[] | select(.target == "branch") | .id' 2>/dev/null); do
    ghr api "repos/$r/rulesets/$rid" | jq -e --arg ref "refs/heads/$b" '
      .enforcement == "active" and .target == "branch"
      and ((.conditions.ref_name.include // []) | index($ref) != null)
      and ([.rules[]?.type] | index("deletion") != null and index("non_fast_forward") != null)
      and ((.bypass_actors // []) | length == 0)' >/dev/null 2>&1 && { ok=1; break; }
  done
  if [ "$ok" -eq 1 ]; then
    # a verified ruleset supersedes a recorded waiver: no PR body or `state` may call $b unprotected now
    state_set protect PASS; state_del protect_waive_reason; state_del protect_waive_evidence; state_del protect_waive_at
    say "protect --verify: PASS (ruleset $rid covers refs/heads/$b)"
  else verify_fail "no active ruleset targets refs/heads/$b with deletion + non_fast_forward and no bypass"; fi
}
verify_fail() { # verify_fail <why> — FAIL, except that a recorded owner waiver stands (exit 1 either way)
  if [ "$(state_get protect)" = WAIVED ]; then
    die "protect --verify: FAIL — $1; the recorded waiver stands (protect=WAIVED, origin/$(state_get branch) still UNPROTECTED)"
  fi
  state_set protect FAIL; die "protect --verify: FAIL — $1"
}
one_line() { printf '%s' "$1" | tr '\t\r\n' '   ' | sed -e 's/   */ /g' -e 's/^ //' -e 's/ $//'; }
protect_waive() { # protect_waive <b> <owner/repo> — the evidence-gated owner waiver (header: protect --waive)
  local b="$1" r="$2" reason j rc st msg
  [ "$(state_get protect)" != PASS ] || die "refused: protect is PASS (a verified ruleset covers refs/heads/$b) — there is nothing to waive; nothing was changed"
  reason="$(one_line "$OPT_REASON")"
  [ -n "$reason" ] || { evt waive_no_reason; die "refused: protect --waive needs a non-empty --reason <text> (the owner's recorded decision) — nothing was changed"; }
  command -v jq >/dev/null 2>&1 || die "refused: protect --waive: jq is required to read GitHub's answer — nothing was changed"
  [ -n "$r" ] || die "refused: protect --waive: owner/repo unknown (--repo) — nothing was changed"
  # the evidence: GitHub's own answer to the rulesets read. gh prints the error body on stdout and
  # exits non-zero; a list (exit 0) means rulesets exist here, so the owner can create one
  j="$(ghr api "repos/$r/rulesets" 2>/dev/null)"; rc=$?
  if [ "$rc" -eq 0 ] && printf '%s' "$j" | jq -e 'type == "array"' >/dev/null 2>&1; then
    evt waive_rulesets_available
    die "refused: GitHub serves rulesets for $r (gh api repos/$r/rulesets succeeded) — the owner can create the printed ruleset, then run protect --verify; a waiver is only for a repo where GitHub cannot apply one. Nothing was changed"
  fi
  st="$(printf '%s' "$j" | jq -r 'if type == "object" then (.status // "" | tostring) else "" end' 2>/dev/null)"
  msg="$(printf '%s' "$j" | jq -r 'if type == "object" then (.message // "" | tostring) else "" end' 2>/dev/null)"
  if [ "$st" != 403 ]; then
    evt waive_no_evidence
    die "refused: no evidence GitHub cannot apply a ruleset to $r (gh api repos/$r/rulesets: exit $rc, status '${st:-none}') — only an HTTP 403 is waivable; fix the gh error and retry. Nothing was changed"
  fi
  msg="$(one_line "${msg:-HTTP 403}")"
  # GitHub's secondary rate limit also answers 403: a throttled read is no evidence about rulesets
  case "$msg" in *[Rr]ate\ limit*) evt waive_no_evidence; die "refused: gh api repos/$r/rulesets was rate-limited (HTTP 403: $msg) — retry later. Nothing was changed" ;; esac
  state_set protect WAIVED; state_set protect_waive_reason "$reason"
  state_set protect_waive_evidence "HTTP 403: $msg"; state_set protect_waive_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  EVT_WARN=protect_waived
  say "protect --waive: WAIVED — GitHub refused rulesets for $r (HTTP 403: $msg)"
  say "reason recorded: $reason"
  say "WARNING — origin/$b is UNPROTECTED: anyone with push access can delete it or force-push it, and"
  say "  no ruleset will stop them. meta-sync.sh itself never force-pushes (every push is fast-forward"
  say "  only), and every synced checkout keeps its files on disk, so the exposure is a human deleting"
  say "  or force-pushing the branch by hand. The PRs this flow opens say so and quote the reason."
  say "  Once rulesets become available (plan upgrade, public repo), create the printed ruleset and run"
  say "  protect --verify: a PASS supersedes this waiver."
  say "then: $(steps_next_after_protect)"
}
steps_next_after_protect() { case "$(state_get case)" in fresh) printf 'migrate-branch-mode.sh mode-pr' ;; *) printf 'migrate-branch-mode.sh seed' ;; esac; }
unprotected_note() { # unprotected_note <b> — the PR-body block when protect is WAIVED (prints nothing otherwise)
  [ "$(state_get protect)" = WAIVED ] || return 0
  printf '%s\n' "> [!WARNING]" \
    "> **The metadata branch \`$1\` is UNPROTECTED** — no ruleset guards it against deletion or force-push by anyone with push access. The owner waived \`protect\` on $(state_get protect_waive_at) because GitHub cannot apply a ruleset here ($(state_get protect_waive_evidence))." \
    ">" "> Owner's recorded reason: $(state_get protect_waive_reason)" \
    ">" "> \`meta-sync.sh\` never force-pushes, and every synced checkout keeps its files on disk; the exposure is a human deleting or force-pushing \`$1\` by hand." ""
}

cmd_mode_pr() {
  need_preflight; need protect PASS WAIVED
  [ "$(state_get case)" = fresh ] || die "refused: mode-pr is the fresh-case step; the history case writes the block in untrack-pr"
  local b d nb url
  b="$(rec_branch)" || exit 1; d="$(default_branch)"
  on_default_clean "$d"
  nb="$(new_branch_name "chore/loomwright-branch-mode-$b")"
  g checkout -q -b "$nb" || die "could not create $nb"
  if ! apply_mode_block "$b" backup_mode_pr; then
    g checkout -q -- .gitignore 2>/dev/null; g checkout -q "$d"; g branch -q -D "$nb"
    state_set mode_pr FAIL; die "mode-pr: FAIL — apply did not write the branch-mode block"
  fi
  g add -- .gitignore
  if [ "$(g diff --cached --name-only)" != ".gitignore" ]; then
    g reset -q; g checkout -q -- .gitignore; g checkout -q "$d"; g branch -q -D "$nb"
    state_set mode_pr FAIL; die "mode-pr: FAIL — the staged change is not exactly .gitignore"
  fi
  g commit -q -m "chore(memory): switch /setup memory to branch mode on $b" || { state_set mode_pr FAIL; die "commit failed"; }
  g push -q origin "refs/heads/$nb:refs/heads/$nb" || { state_set mode_pr FAIL; die "push of $nb failed"; }
  g checkout -q "$d" || die "could not return to $d"
  state_set mode_pr_branch "$nb"
  { unprotected_note "$b"; cat <<EOF
Switches \`/setup memory\` to branch mode: run history now lives on \`$b\` (meta-sync.sh).
One commit, \`.gitignore\` only. No run history was tracked, so nothing is untracked.

Pre-migration SHA: $(state_get pre_migration_sha)

The owner merges this PR; then run \`migrate-branch-mode.sh after-merge\`.
EOF
  } > "$SD/mode-pr.body"
  url="$(pr_create "$nb" "$d" "chore(memory): branch mode on $b" "$SD/mode-pr.body")" || { state_set mode_pr FAIL; die "gh pr create failed (branch $nb is pushed)"; }
  state_set pr_mode "$url"; state_set mode_pr PASS
  say "mode-pr: PASS — opened $url (NOT merged)"
  say "OWNER STEP — review and merge $url, then run: migrate-branch-mode.sh after-merge"
}

cmd_seed() {
  need_preflight; need protect PASS WAIVED
  [ "$(state_get case)" = history ] || die "refused: seed is the history-case step"
  local b d; b="$(rec_branch)" || exit 1; d="$(default_branch)"
  on_default_clean "$d"
  # a (re-)seed starts a new round: an earlier untrack PR / verify-pr no longer describes it
  stale_if_recorded untrack_pr verify_pr
  bash "$MS" push --branch "$b" --root "$ROOT" || { state_set seed FAIL; evt meta_push_failed; die "seed: FAIL — meta-sync.sh push --branch $b"; }
  if ab_check "$b" "$d"; then
    state_set seed PASS; state_set seed_a "$AB_A"; state_set seed_u "$AB_U"; state_set seed_b "$AB_B"; state_set seed_sha "$(g rev-parse HEAD)"
    state_set seed_check "$AB_REL"
    say "seed: PASS"
  else state_set seed FAIL; die "seed: FAIL — A/B check failed; the flow stops before untrack-pr"; fi
}

ab_body_lines() { # ab_body_lines <equal|subset> <A> <B> <U> — the PR body's A/B claim; never claims equality that does not hold
  if [ "$1" = subset ]; then
    printf -- '- path-list check: A ⊆ B (B has %s extra, migrated in an earlier round); A minus B: empty\n' "$(($3 - $2))"
    printf -- '- blob check: every A blob equals its B blob'
  elif [ "${4:-0}" -gt 0 ]; then
    printf -- '- U (managed run history on disk, gitignored — pushed to the branch, never tracked, so nothing to untrack): %s\n' "$4"
    printf -- '- path-list diff A + U vs B: empty\n- blob diff A + U vs B: empty'
  else
    printf -- '- path-list diff A vs B: empty\n- blob diff A vs B: empty'
  fi
}

cmd_untrack_pr() {
  need_preflight; need seed PASS
  local b d nb url n
  b="$(rec_branch)" || exit 1; d="$(default_branch)"
  on_default_clean "$d"
  [ "$(g rev-parse HEAD)" = "$(state_get seed_sha)" ] || die "refused: origin/$d moved since seed — run seed again"
  [ -s "$SD/a.list" ] || die "refused: the seeded A set ($SD/a.list) is missing or empty"
  stale_if_recorded verify_pr # a verify-pr of an earlier PR never vouches for the one cut now
  nb="$(new_branch_name "chore/loomwright-untrack-run-history-$b")"
  g checkout -q -b "$nb" || die "could not create $nb"
  # Untrack BEFORE writing the block: apply's post-write readiness verify probes `git check-ignore`,
  # which never reports a TRACKED path as ignored, so with the A set still in the index a tracked
  # findings ledger read as "committable" and apply printed a false `WARNING — readiness is
  # 'partial …'` for a commit whose tree reads `configured`. In this order the verify judges the
  # tree this step commits, so a WARNING it prints is real.
  untrack_a_set || { g reset -q; g checkout -q "$d"; g branch -q -D "$nb"; state_set untrack_pr FAIL; die "untrack-pr: FAIL — git rm --cached failed (nothing committed)"; }
  if ! apply_mode_block "$b" backup_untrack_pr; then
    g reset -q; g checkout -q -- .gitignore; g checkout -q "$d"; g branch -q -D "$nb"
    state_set untrack_pr FAIL; die "untrack-pr: FAIL — apply did not write the branch-mode block"
  fi
  g add -- .gitignore
  g commit -q -m "chore(memory): untrack run history — it lives on $b now" || { state_set untrack_pr FAIL; die "commit failed"; }
  g push -q origin "refs/heads/$nb:refs/heads/$nb" || { state_set untrack_pr FAIL; die "push of $nb failed"; }
  g checkout -q "$d" || die "could not return to $d"
  state_set untrack_branch "$nb"
  { unprotected_note "$b"; cat <<EOF
Moves run history to the metadata branch \`$b\`: writes the branch-mode \`.gitignore\` block and
untracks the managed paths (\`git rm -r --cached\`; the files stay on disk and on \`$b\`).

- A (tracked managed paths on \`$d\`): $(state_get seed_a)
- B (\`$b\` tree): $(state_get seed_b)
$(ab_body_lines "$(state_get seed_check)" "$(state_get seed_a)" "$(state_get seed_b)" "$(state_get seed_u)")
- pre-migration SHA: $(state_get pre_migration_sha)

**Immediately before merging, run \`migrate-branch-mode.sh verify-pr <this PR's number>\`** — it
re-checks against the then-current \`$d\` and pushes anything new to \`$b\` first.
After the merge: \`migrate-branch-mode.sh after-merge\`.
EOF
  } > "$SD/untrack-pr.body"
  url="$(pr_create "$nb" "$d" "chore(memory): untrack run history (branch mode on $b)" "$SD/untrack-pr.body")" || { state_set untrack_pr FAIL; die "gh pr create failed (branch $nb is pushed)"; }
  n="${url##*/}"
  state_set pr_untrack "$url"; state_set untrack_pr PASS
  say "untrack-pr: PASS — opened $url (NOT merged)"
  say "OWNER STEP — immediately before merging, run: migrate-branch-mode.sh verify-pr $n"
}

cmd_verify_pr() {
  need_preflight; need untrack_pr PASS
  [ -n "$POS" ] || { echo "migrate-branch-mode: verify-pr needs the PR number" >&2; exit 2; }
  local b d nb st head missing mbase
  b="$(rec_branch)" || exit 1; d="$(default_branch)"; nb="$(state_get untrack_branch)"
  st="$(ghr pr view "$POS" --json state,headRefName --jq '.state + " " + .headRefName' 2>/dev/null)" || die "verify-pr: gh pr view $POS failed"
  head="${st#* }"
  [ "${st%% *}" = OPEN ] || { state_set verify_pr FAIL; evt pr_not_open; die "verify-pr: FAIL — PR $POS is '${st%% *}', not OPEN"; }
  [ "$head" = "$nb" ] || { state_set verify_pr FAIL; evt pr_head_mismatch; die "verify-pr: FAIL — PR $POS head is '$head', not the untrack branch '$nb'"; }
  on_default_clean "$d"
  bash "$MS" push --branch "$b" --root "$ROOT" || { state_set verify_pr FAIL; evt meta_push_failed; die "verify-pr: FAIL — meta-sync.sh push --branch $b"; }
  ab_check "$b" "$d" || { state_set verify_pr FAIL; die "verify-pr: FAIL — A/B check failed against the current origin/$d; do NOT merge"; }
  g fetch -q origin "+refs/heads/$nb:refs/remotes/origin/$nb" || die "could not fetch $nb"
  # every tracked managed path must be in the PR's deletion set, or it stays tracked after the merge
  mbase="$(g merge-base HEAD "refs/remotes/origin/$nb")" || die "verify-pr: no merge base between $d and $nb"
  missing="$(g diff --name-only --diff-filter=D "$mbase" "refs/remotes/origin/$nb" | env LC_ALL=C sort | env LC_ALL=C comm -13 - "$SD/a.list" | tr '\n' ' ')"
  if [ -n "$missing" ]; then state_set verify_pr FAIL; evt pr_leaves_tracked --count "paths=$(printf '%s' "$missing" | wc -w | tr -d ' ')"; die "verify-pr: FAIL — PR $POS leaves tracked managed path(s) tracked: $missing— re-cut it (untrack-pr after seed); do NOT merge"; fi
  state_set verify_pr PASS; state_set verify_pr_sha "$(g rev-parse HEAD)"
  local rel="A = B = $AB_A"; [ "$AB_U" -gt 0 ] && rel="B = A + U ($AB_B = $AB_A + $AB_U)"
  [ "$AB_REL" = subset ] && rel="A ⊆ B (A = $AB_A, B = $AB_B; B has $((AB_B - AB_A)) extra)"
  say "verify-pr: PASS — PR $POS is safe to merge now ($rel against origin/$d $(g rev-parse --short HEAD))"
}

untrack_head_merged() { # 0 = the untrack PR's head commit is an ancestor of HEAD (a merge commit; a squash never is)
  local nb t; nb="$(state_get untrack_branch)"; [ -n "$nb" ] || return 1
  t="$(g rev-parse -q --verify "refs/remotes/origin/$nb^{commit}")" || return 1
  g merge-base --is-ancestor "$t" HEAD
}

cmd_after_merge() {
  need_preflight
  case "$(state_get case)" in fresh) need mode_pr PASS ;; *) need verify_pr PASS ;; esac
  local b d pre p miss=0 deleted tm open
  b="$(rec_branch)" || exit 1; d="$(default_branch)"
  [ "$(g symbolic-ref -q --short HEAD)" = "$d" ] || die "refused: not on $d"
  pre="$(g rev-parse HEAD)"
  g pull -q --ff-only origin "$d" || { state_set after_merge FAIL; evt pull_failed; die "after-merge: git pull failed"; }
  [ "$(read_mode)" = "on $b" ] || { state_set after_merge FAIL; evt mode_not_on_branch; die "after-merge: FAIL — mode line is '$(read_mode)', not 'on $b' (is the PR merged?)"; }
  # The mode line is NOT proof the untrack PR merged (a half-migrated repo reads `on $b` before it).
  # Proof: no path this round's PR untracks ($SD/a.list, the A set verify-pr just checked the PR
  # deletes) is still tracked — or the PR's head commit is in HEAD. Otherwise the PR is still open:
  # refuse and write NOTHING, so verify_pr PASS stays valid and no follow-up round is recorded.
  if [ "$(state_get case)" != fresh ]; then
    [ -s "$SD/a.list" ] || die "refused: this round's untracked set ($SD/a.list) is missing — re-run verify-pr <n>; nothing was changed"
    tm="$(tracked_managed)" || die "after-merge: list-managed --tracked --run-history failed; nothing was recorded"
    open="$(printf '%s\n' "$tm" | env LC_ALL=C sort | env LC_ALL=C comm -12 "$SD/a.list" -)"
    if [ -n "$open" ] && ! untrack_head_merged; then
      printf '%s\n' "$open" | sed 's/^/  still tracked (this round untracks it): /' >&2
      evt untrack_pr_not_merged
      die "after-merge: refused — untrack PR not merged yet — merge PR $(state_get pr_untrack | sed 's|.*/||'), then re-run after-merge (nothing was recorded)"
    fi
  fi
  # The pull deletes the untracked run history from disk. Put back exactly what it deleted, from the
  # pre-pull commit (verify-pr proved those blobs equal the branch), so meta-sync pull sees L == R.
  deleted="$(g diff --name-only --diff-filter=D "$pre" HEAD -- .supervisor)"
  printf '%s\n' "$deleted" | while IFS= read -r p; do
    [ -n "$p" ] && [ ! -e "$ROOT/$p" ] || continue
    mkdir -p "$(dirname "$ROOT/$p")" && g cat-file blob "$pre:$p" > "$ROOT/$p"
  done
  bash "$MS" pull --branch "$b" --root "$ROOT" || { state_set after_merge FAIL; evt meta_pull_failed; die "after-merge: FAIL — meta-sync.sh pull --branch $b"; }
  fetch_meta "$b"
  # One path per line, verbatim (a space is part of the name; no word-split, no glob); the
  # process substitution keeps `miss` in this shell so it still gates the FAIL below.
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ -f "$ROOT/$p" ] || { echo "migrate-branch-mode: missing after pull: $p" >&2; miss=$((miss+1)); }
  done < <(g ls-tree -r --name-only "refs/remotes/origin/$b")
  [ "$miss" -eq 0 ] || { state_set after_merge FAIL; evt files_not_back --count "paths=$miss"; die "after-merge: FAIL — $miss branch file(s) not back"; }
  # Re-read the ground truth, not verify-pr's snapshot: a managed file committed to $d between
  # verify-pr and the merge is still TRACKED (the PR never untracked it) and absent from $b, yet the
  # mode block ignores it, so `git status --porcelain` stays empty. Any tracked managed path = not done.
  tm="$(tracked_managed)" || { state_set after_merge FAIL; die "after-merge: FAIL — list-managed --tracked --run-history failed"; }
  if [ -n "$tm" ]; then
    printf '%s\n' "$tm" | sed 's/^/  still tracked on '"$d"': /' >&2
    state_set after_merge FAIL
    # record the follow-up round and stale round 1's results, so `state` points at seed and
    # after-merge's `need verify_pr PASS` can only be met by a round-2 verify-pr
    state_set followup 1; state_set seed STALE; state_set untrack_pr STALE; state_set verify_pr STALE
    evt still_tracked --count "paths=$(printf '%s\n' "$tm" | grep -c .)"
    die "after-merge: FAIL — the managed path(s) above are still tracked on $d (committed after verify-pr; the merged PR did not untrack them) — run seed, then a follow-up untrack-pr (verify-pr before its merge), then after-merge again$([ "$(state_get case)" = fresh ] && printf ' (fresh case: re-run preflight first — it re-detects the case as history)')"
  fi
  [ -z "$(g status --porcelain)" ] || { g status --porcelain >&2; state_set after_merge FAIL; evt porcelain_dirty; die "after-merge: FAIL — git status --porcelain is not empty"; }
  state_set after_merge PASS
  say "after-merge: PASS — run history is back from $b and the working tree is clean"
  say "every OTHER checkout must run:"
  echo "  git pull"
  echo "  bash <plugin>/scripts/meta-sync.sh pull --branch $b"
  [ "$(state_get protect)" != WAIVED ] || say "WARNING — origin/$b is UNPROTECTED (protect WAIVED: $(state_get protect_waive_reason)); create the ruleset and run protect --verify once GitHub allows it"
}

cmd_rollback() {
  [ -n "$OPT_COMMIT" ] || { echo "migrate-branch-mode: rollback needs --commit <sha of the merged untrack PR commit>" >&2; exit 2; }
  local b d c br_sha nb url par
  b="$(rec_branch)" || exit 1; d="$(default_branch)"
  on_default_clean "$d"
  c="$(g rev-parse -q --verify "$OPT_COMMIT^{commit}")" || die "refused: '$OPT_COMMIT' is not a commit"
  # 1. publish every post-migration local edit / addition / deletion, so the branch tip is newest
  bash "$MS" push --branch "$b" --root "$ROOT" || { state_set rollback FAIL; die "rollback: FAIL — meta-sync.sh push --branch $b (nothing changed)"; }
  fetch_meta "$b"; br_sha="$(g rev-parse "refs/remotes/origin/$b")"
  nb="$(new_branch_name "chore/loomwright-rollback-branch-mode-$b")"
  g checkout -q -b "$nb" || die "could not create $nb"
  # 2. revert the untrack commit (re-tracks the PRE-migration bytes and restores .gitignore)
  par="$(g rev-list --parents -n 1 "$c" | wc -w | tr -d ' ')"
  if [ "$par" -gt 2 ]; then g revert --no-commit -m 1 "$c"; else g revert --no-commit "$c"; fi || { state_set rollback FAIL; die "rollback: git revert failed on $nb"; }
  # 3. re-track the CURRENT branch files: newest bytes for every path the branch has
  rb_retrack_from_branch "$br_sha" || { state_set rollback FAIL; die "rollback: re-track from $b failed on $nb"; }
  g commit -q -m "chore(memory): revert untrack; re-track run history at $b $br_sha" || { state_set rollback FAIL; die "rollback: commit failed on $nb"; }
  g push -q origin "refs/heads/$nb:refs/heads/$nb" || { state_set rollback FAIL; die "rollback: push of $nb failed"; }
  state_set rollback_branch "$nb"
  printf 'Rolls back branch mode: reverts %s and re-tracks run history at %s %s (the corrected #361 recipe: nothing written since migration is lost).\n' "$c" "$b" "$br_sha" > "$SD/rollback.body"
  url="$(pr_create "$nb" "$d" "chore(memory): roll back branch mode" "$SD/rollback.body")" || { state_set rollback FAIL; die "gh pr create failed (branch $nb is pushed)"; }
  state_set pr_rollback "$url"; state_set rollback PASS
  state_del followup # the rolled-back migration's follow-up round is over; a new one needs A = B
  say "rollback: PASS — opened $url (NOT merged); you are on $nb"
  say "OWNER STEP — merge it, then: git checkout $d && git pull"
}
rb_retrack_from_branch() { # the step the old M1 order (revert -> meta-sync pull -> git add) got wrong
  local br="$1" p
  # every branch path MINUS the learning stores (never untracked by the migration — see rollback above); subtracting
  # the excluded class keeps the pre-learning-store behaviour for every other branch entry
  branch_learning "$br" "$SD/onbranch.learn" || return 1
  g ls-tree -r --name-only "$br" > "$SD/onbranch.all" || return 1
  grep -vxF -f "$SD/onbranch.learn" "$SD/onbranch.all" > "$SD/onbranch.list"
  [ $? -le 1 ] || return 1
  if [ -s "$SD/onbranch.list" ]; then
    tr '\n' '\0' < "$SD/onbranch.list" | (cd "$ROOT" && xargs -0 git checkout "$br" --) || return 1
  fi
  # paths the revert re-added that were deleted on the branch since migration. `rm -f` below deletes
  # from disk, so a learning store is never among them: the untrack commit never removes one
  # (tracked_managed is run history only), and should a hand-picked --commit have removed one, the
  # revert's re-tracked copy is left exactly as the revert restored it — never deleted.
  tracked_learning "$SD/staged.learn" || return 1
  g diff --cached --name-only --diff-filter=A HEAD -- .supervisor | grep -vxF -f "$SD/onbranch.list" \
    | grep -vxF -f "$SD/staged.learn" > "$SD/gone.list"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    g rm -q --cached -- "$p" && rm -f -- "$ROOT/$p"
  done < "$SD/gone.list"
  return 0
}

cmd_state() {
  [ -f "$SF" ] || { say "no state file ($SF) — start with plan, then preflight"; return 0; }
  sed 's/^/  /' "$SF"
  local k nxt=done
  for k in $(seq_keys "$(state_get case)"); do
    # an owner waiver completes protect (header: protect=WAIVED satisfies every gate PASS does)
    case "$k=$(state_get "$k")" in *=PASS|protect=WAIVED) ;; *) nxt="$k"; break ;; esac
  done
  [ "$(state_get protect)" != WAIVED ] || say "WARNING — protect is WAIVED: origin/$(state_get branch) is UNPROTECTED (reason: $(state_get protect_waive_reason))"
  say "next: $(printf '%s' "$nxt" | tr '_' '-')"
}

case "$STEP" in
  plan|state) ;;   # read-only: never report (plan writes nothing at all)
  *) trap 'evt_emit $?' EXIT ;;
esac
case "$STEP" in
  plan) cmd_plan ;;
  preflight) cmd_preflight ;;
  scrub) cmd_scrub ;;
  rehearse) cmd_rehearse ;;
  init) cmd_init ;;
  protect) cmd_protect ;;
  mode-pr) cmd_mode_pr ;;
  seed) cmd_seed ;;
  untrack-pr) cmd_untrack_pr ;;
  verify-pr) cmd_verify_pr ;;
  after-merge) cmd_after_merge ;;
  rollback) cmd_rollback ;;
  state) cmd_state ;;
  *) echo "migrate-branch-mode: unknown step '$STEP' (try --help)" >&2; exit 2 ;;
esac
