# _lanes_click_action <notify-desktop.sh path> <checkout root> — the click action notify-desktop.sh
# resolves for this call, derived its own way: LOOMWRIGHT_NOTIFY_CLICK (default activate), `off` or no
# readable notify-click-target.sh beside the notifier ⇒ `none`, else that resolver's ACTION= line, fed
# the same session-id / entrypoint env inputs (the park payload carries no session id, so the env wins).
# The notifier's dir is resolved from <root>, the cwd it runs in; an unresolvable dir reads `none`.
_lanes_click_action() {
  local nd="$1" root="$2" mode="${LOOMWRIGHT_NOTIFY_CLICK:-activate}" dir out act=""
  dir="$(cd "$root" 2>/dev/null && cd "$(dirname "$nd")" 2>/dev/null && pwd)" || dir=""
  if [ "$mode" != off ] && [ -n "$dir" ] && [ -r "$dir/notify-click-target.sh" ]; then
    out="$(bash "$dir/notify-click-target.sh" "$mode" "${CLAUDE_CODE_SESSION_ID:-}" "${CLAUDE_CODE_ENTRYPOINT:-}" 2>/dev/null)" || true
    act="$(printf '%s\n' "$out" | sed -n 's/^ACTION=//p' | head -1)" || act=""
  fi
  echo "${act:-none}"
}

# _lanes_os_notifier <notify-desktop.sh path> <checkout root> — prints NOTHING when the platform
# notifier notify-desktop.sh dispatches to is present, else the `failed (…)` reason. Mirrors that
# script's own dispatch conditions: Darwin uses terminal-notifier ONLY with a click action other than
# `none` (else it falls through to osascript), Linux needs notify-send plus a display; any other OS has
# no notifier there either. LOOMWRIGHT_LANES_UNAME is the existing uname seam of this file.
_lanes_os_notifier() {
  local nd="${1:-}" root="${2:-.}"
  case "${LOOMWRIGHT_LANES_UNAME:-$(uname -s 2>/dev/null)}" in
    Darwin)
      if command -v terminal-notifier >/dev/null 2>&1 && [ "$(_lanes_click_action "$nd" "$root")" != none ]; then :
      elif command -v osascript >/dev/null 2>&1; then :
      else echo "no OS notifier on PATH"; fi ;;
    Linux)
      if ! command -v notify-send >/dev/null 2>&1; then echo "no OS notifier on PATH"
      elif [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then echo "no display for notify-send"; fi ;;
    *) echo "no OS notifier on PATH" ;;
  esac
}

# ==================================================================================================
# lane-park-notify <runfile> — the ONE notify step of a lane's ready_for_release park (§14 "Terminal
# park"; parallel-automate/24 F6). Sends the desktop notification and the `automate_ready_for_release`
# webhook ("do not merge yet — wave open"), both fail-SAFE, then appends ONE `## Progress` line naming
# what each channel actually did. Both notifiers are silent on stdout, so delivery is read from their
# observable outcomes only — never assumed:
#   desktop  `sent` (notify-desktop.sh wrote its `notify group=` audit line to <root>/.supervisor/logs/
#            notifications.log AND the platform notifier it dispatches to is present — Darwin:
#            osascript, or terminal-notifier with a click action other than `none` (LOOMWRIGHT_NOTIFY_CLICK
#            not `off` and notify-click-target.sh beside it), on PATH; Linux: notify-send on PATH plus DISPLAY or
#            WAYLAND_DISPLAY — the OS banner itself is best-effort and not observable) · `disabled
#            (LOOMWRIGHT_DESKTOP_NOTIFICATIONS=0)` · `suppressed (no audit line …)` (debounce, or the
#            notifier skipped it) · `failed (<why>)` — incl. `failed (no OS notifier on PATH)` and
#            `failed (no display for notify-send)`, because notify-desktop.sh writes its audit line on
#            EVERY host BEFORE its platform dispatch, so the audit line alone cannot prove a banner
#   webhook  a LOOMWRIGHT_WEBHOOK_DRY_RUN=1 probe of send-webhook.sh first says whether a webhook URL
#            resolves (it prints the payload only then): none ⇒ `ignored (repo_webhook_ignored slug=…
#            — no user-scope egress grant)` or `not configured`; one ⇒ the real call, then `attempted
#            (POST sent; delivery not reported by send-webhook.sh)` — it never reports the HTTP result,
#            so never `sent` — or `failed (<its stderr line>)`; `dry-run …` when the caller already set
#            LOOMWRIGHT_WEBHOOK_DRY_RUN
# Not at the ready_for_release park ⇒ `lane-park-notify: skipped — …`, nothing sent, nothing written.
# Always exits 0 except a usage error. Seams: LOOMWRIGHT_LANES_NOTIFY_DESKTOP, LOOMWRIGHT_LANES_SEND_WEBHOOK.
lanes_park_notify() {
  local rf="${1:-}" nd="${LOOMWRIGHT_LANES_NOTIFY_DESKTOP:-$HERE/notify-desktop.sh}"
  local sw="${LOOMWRIGHT_LANES_SEND_WEBHOOK:-$HERE/send-webhook.sh}"
  local root run status pause pr item msg payload nlog before after desk web probe perr err line osn
  [ -n "$rf" ] && [ "$#" -le 1 ] || die "usage: lane-park-notify <runfile>"
  [ -f "$rf" ] || die "lane-park-notify: run file not found: $rf"
  root="$(cd "$(dirname "$rf")/../.." 2>/dev/null && pwd -P)" || die "lane-park-notify: cannot resolve the checkout of $rf"
  run="$(basename "$rf" .md)"
  IFS="$(printf '\t')" read -r status pause pr _ <<<"$(_lanes_runfile_fields "$rf")"
  if [ "$status/$pause" != "ready_for_release/ready_for_release" ]; then
    echo "lane-park-notify: skipped — $run — run file reads status ${status:--} / pause_reason ${pause:--}, not the ready_for_release park; nothing sent"
    return 0
  fi
  item="$(_lanes_current_item "$rf")"
  case "$pr" in ''|-|null) pr="(no PR recorded)" ;; esac
  msg="$pr READY — do not merge yet — wave open (/automate item ${item:--}, run $run)"
  # desktop — the merge watcher's notify_as payload shape, judged by the notifier's own audit line.
  nlog="$root/.supervisor/logs/notifications.log"
  if [ "${LOOMWRIGHT_DESKTOP_NOTIFICATIONS:-1}" = 0 ]; then desk="disabled (LOOMWRIGHT_DESKTOP_NOTIFICATIONS=0)"
  elif [ ! -f "$nd" ]; then desk="failed (notify-desktop.sh absent)"
  elif ! payload="$(jq -cn --arg t automate_ready_for_release --arg m "$msg" \
      '{hook_event_name:"Notification",notification_type:$t,message:$m}' 2>/dev/null)" || [ -z "$payload" ]; then
    desk="failed (payload not built — jq)"
  else
    before="$(grep -c ' notify group=' "$nlog" 2>/dev/null)"; before="${before:-0}"
    printf '%s' "$payload" | (cd "$root" && bash "$nd" >/dev/null 2>&1) || true
    after="$(grep -c ' notify group=' "$nlog" 2>/dev/null)"; after="${after:-0}"
    osn="$(_lanes_os_notifier "$nd" "$root")"
    if [ "$after" -gt "$before" ] 2>/dev/null; then
      if [ -z "$osn" ]; then desk="sent"; else desk="failed ($osn)"; fi
    else desk="suppressed (no audit line in .supervisor/logs/notifications.log — debounced or skipped by notify-desktop.sh)"; fi
  fi
  # webhook — probe first (dry run prints the payload only when a URL resolves), then the real call.
  if [ ! -f "$sw" ]; then web="failed (send-webhook.sh absent)"
  else
    perr="$root/.supervisor/logs/.lane-park-notify.$$.err"; mkdir -p "$root/.supervisor/logs" 2>/dev/null
    probe="$(cd "$root" && LOOMWRIGHT_WEBHOOK_DRY_RUN=1 bash "$sw" --event-type gate --gate-type automate_ready_for_release \
      --context "$msg" 2>"$perr" </dev/null)" || true
    err="$(grep -m1 -E '^(repo_webhook_ignored|send-webhook:)' "$perr" 2>/dev/null)"
    case "$probe" in
      "{"*)
        if [ -n "${LOOMWRIGHT_WEBHOOK_DRY_RUN:-}" ]; then web="dry-run (LOOMWRIGHT_WEBHOOK_DRY_RUN set — nothing posted)"
        else
          (cd "$root" && bash "$sw" --event-type gate --gate-type automate_ready_for_release --context "$msg" \
            >/dev/null 2>"$perr" </dev/null) || true
          err="$(grep -m1 '^send-webhook:' "$perr" 2>/dev/null)"
          if [ -n "$err" ]; then web="failed ($err)"; else web="attempted (POST sent; delivery not reported by send-webhook.sh)"; fi
        fi ;;
      *)
        case "$err" in
          repo_webhook_ignored*) web="ignored ($err — no user-scope egress grant)" ;;
          send-webhook:*) web="failed ($err)" ;;
          *) web="not configured" ;;
        esac ;;
    esac
    rm -f "$perr" 2>/dev/null
  fi
  line="lane park notify: ready_for_release ($run) — desktop: $desk; webhook: $web"
  bash "$HELPERS" progress-append "$rf" "$(now_utc) $line" >/dev/null 2>&1 \
    || echo "lane-park-notify: WARNING — the ## Progress line could not be appended to $rf" >&2
  echo "lane-park-notify: $line"
  return 0
}

# ==================================================================================================
# lane-info [--root <dir>]
lanes_info() {
  local root=""
  [ "${1:-}" = "--root" ] && { root="${2:-}"; [ -n "$root" ] || die "lane-info: --root needs a directory"; }
  [ -n "$root" ] || root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  local j="$root/.supervisor/lane.json"
  if [ -s "$j" ] && jq -e '.schema_version == 1 and (.run_id | type == "string")' "$j" >/dev/null 2>&1; then cat "$j"; return 0; fi
  echo "lane-info: not a lane (no valid .supervisor/lane.json under $root)" >&2
  return 1
}

# init-check --parallel N [--auto-merge]
lanes_init_check() {
  local n="" am=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --parallel) [ "$#" -ge 2 ] || { echo "refuse: parallel_out_of_range"; return 1; }; n="$2"; shift 2 ;;
      --auto-merge) am=1; shift ;;
      *) echo "refuse: unknown_argument $1"; return 1 ;;
    esac
  done
  case "$n" in ''|*[!0-9]*) echo "refuse: parallel_out_of_range"; return 1 ;; esac
  n=$((10#$n))
  if [ "$n" -lt 1 ] || [ "$n" -gt 10 ]; then echo "refuse: parallel_out_of_range"; return 1; fi
  # `--auto-merge` is refused with ANY lane (N = 1 included): a lane never runs the §10 merge gate.
  if [ "$am" = 1 ]; then echo "refuse: auto_merge_with_parallel"; return 1; fi
  # N = 1 (single-lane mode) only: branch mode must be ON — with it off a single lane's close-out would
  # open its own trail PR the parent never sees and fleet-closeout could never finalize the lane. Fail
  # CLOSED: anything but a first line `on <branch>` (off, unknown, empty, a failing reader) refuses.
  # N > 1 never reads the mode here.
  if [ "$n" = 1 ]; then
    local root m
    root="$(git rev-parse --show-toplevel 2>/dev/null)" || root=""
    m="$(bash "$SETUP_MEMORY" --root "${root:-$PWD}" mode 2>/dev/null </dev/null | head -1)"
    case "$m" in "on "?*) ;; *) echo "refuse: single_lane_requires_branch_mode"; return 1 ;; esac
  fi
  echo ok
}

# pick-guard <automate_dir> — a lane is live when its process is (lanes_proc_alive) or it holds an
# unanswered question (a deferred session is a lane mid-flight). The run lock alone is reclaimable.
lanes_pick_guard() {
  local d="${1:-}" t lane path run pid st
  [ -n "$d" ] && [ -d "$d" ] || { echo "refuse: automate_dir_missing ${d:-<none>}"; return 1; }
  for t in "$d"/*.lanes; do
    [ -f "$t" ] || continue
    while IFS="$(printf '\t')" read -r lane path _ run pid st _; do
      case "$lane" in L[0-9]*) ;; *) continue ;; esac
      if lanes_proc_alive "$pid" "$st" "$path" || { [ -d "$path/.supervisor/inbox" ] && _lanes_pending_question "$path/.supervisor/inbox" >/dev/null; }; then
        echo "refuse: live_lane $run $lane"; return 1
      fi
    done < "$t"
  done
  echo ok
}

# branch-check <lane_dir> <branch> — prints the branch name to use; a remote hit ⇒ `<branch>-L<n>`;
# both taken ⇒ `refuse: remote_branch_exists <branch>` (exit 1). Never a force push.
lanes_branch_check() {
  local dir="${1:-}" b="${2:-}" hit
  _lane_ctx "$dir" || die "branch-check: not a lane: ${dir:-<none>}"
  [ -n "$b" ] || die "branch-check: usage: branch-check <lane_dir> <branch>"
  hit="$(git -C "$LN_DIR" ls-remote --heads origin "$b" 2>/dev/null)" || { echo "refuse: remote_unreachable $b"; return 1; }
  [ -z "$hit" ] && { echo "$b"; return 0; }
  hit="$(git -C "$LN_DIR" ls-remote --heads origin "$b-$LN_LANE" 2>/dev/null)" || { echo "refuse: remote_unreachable $b"; return 1; }
  [ -z "$hit" ] && { echo "$b-$LN_LANE"; return 0; }
  echo "refuse: remote_branch_exists $b"; return 1
}

