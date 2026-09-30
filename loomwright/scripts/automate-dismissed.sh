#!/usr/bin/env bash
# automate-dismissed.sh — the `/automate` engine's dismissed-findings drafts.
# PROTOCOL AUTHORITY: `skills/automate-loop/SKILL.md` §6 "Dismissed-findings
# decision step (before the park)" — the THRESHOLD rule, the ask order, fix-now
# and the next-PICK ask are written there once; this script implements the
# mechanical half. Dispatched from `automate-helpers.sh`
# (`exec bash "$(dirname "$0")/automate-dismissed.sh" <subcmd>`).
#
# SCOPE OF ITS WRITES (the whole list — anything else is a bug):
#   * draft files `<run_id>--<item_stem>--dismissed-<h8|summary>.md` in
#     `<repo>/.supervisor/requirements/proposed/`, every one of them through
#     propose-common.sh's `pc_guarded_write` (the ONE canonical `proposed/`
#     write guard — no second name check here, so its mutation control stays
#     live), plus `rm` of THIS run's draft on a `drop` / `fix-now` decision;
#   * the gitignored decision ledger `<run_id>.dismissed-decisions` beside the
#     run file (`draft_name<TAB>decision<TAB>ts`, keyed by draft NAME, last row
#     wins), and ONE `## Progress` line per decision via
#     `automate-helpers.sh progress-append`.
# It never runs `gh`, `git commit`, `git push` or any other git mutation (only
# `git rev-parse --show-toplevel`), and never merges anything.
#
# Subcommands:
#   dismissed-drafts <runfile> <item> <pr_url> [--after-fix-now]
#       Reads `<run_id>.supervisor-result.md` (key `heal_dismissed`, origin
#       `phase_4_5`, round = `heal_iterations`) then `<run_id>.review-heal-result.md`
#       (key `dismissed`, origin `drain`, round = `rounds`) from the run file's
#       directory with result_block_parser.py. Dedupes on
#       (origin, source, whitespace-normalized finding), then applies the
#       threshold (SKILL §6 subsection; mirrored here): an item gets its OWN
#       draft when severity ∈ {BLOCKING, HIGH, MEDIUM}, OR reason == pre_existing,
#       OR severity is absent/unrecognized and reason != nit; every other item is
#       listed in ONE summary draft. Zero items ⇒ no files. Names are content
#       addressed: h8 = first 8 hex of sha1("origin\tsource\tnormalized finding").
#       The ledger decides what is (re)written: no row ⇒ written (deterministic,
#       no timestamp, so an undecided re-run is byte-identical); `follow-up` ⇒
#       kept as is, never rewritten or recreated; `drop` ⇒ never recreated;
#       `fix-now` ⇒ suppressed, EXCEPT a drain-origin name that reappears when
#       `--after-fix-now` is passed (the loop passes it only after the fix-now
#       re-drain ran, i.e. `fix_now_reentered: true`) ⇒ re-written
#       `undecided (fix-now unconfirmed)` + a `fix-now-unconfirmed` ledger row.
#       A phase_4_5-origin fix-now name stays suppressed: its sidecar is never
#       rewritten by the re-pass, so it can neither confirm nor refute the fix.
#       Output: one `draft<TAB><k|summary><TAB><severity|-><TAB><path>` row per
#       file written or kept, message lines (`dismissed-drafts: no <sidecar> —
#       skipped`, `dismissed-drafts: unreadable <path>`, `dismissed-drafts:
#       refused <name> — <reason>`), then ONE summary line
#       `dismissed-drafts: <n> per-finding + <0|1> summary (<m> listed in summary)`.
#   dismissed-decide <runfile> <draft_path> <fix-now|follow-up|drop>
#       Refuses (`dismissed-decide: refused — <reason>`) a path that is not a
#       regular file directly under `proposed/` named `<this run_id>--*--dismissed-*.md`.
#       Appends the ledger row FIRST (nothing is deleted without a record), then
#       rewrites the draft's `- **Decision:**` line (follow-up) or deletes the
#       draft (drop / fix-now), then progress-appends ONE line
#       `dismissed: <decision> <draft_name> — <first 80 chars of finding>`.
#   dismissed-pending <runfile>
#       Prints the count of this run's drafts whose first `- **Decision:**` value
#       STARTS WITH `undecided` (so `undecided (fix-now unconfirmed)` counts), or
#       `unknown` when it cannot tell (the caller treats `unknown` as non-zero —
#       fail closed toward asking).
#
# Finding text is DATA ONLY: python string I/O / `printf '%s'`, never eval, never
# an unquoted expansion; every line of a finding is written `> `-prefixed inside
# a fence longer than any backtick run in it, and every single-line metadata
# value has its line breaks folded to spaces, so no finding byte can begin a
# column-0 `#` / `## Status:` / `- **…:**` line (line-anchored scanners —
# automate-trail.sh's evidence gate, is_done / is_not_ready — ignore fences).
#
# Always exits 0 (a runtime side-effect emitter — CLAUDE.md §"Failure-Mode
# Invariants"). `set -uo pipefail`, no `-e`; bash 3.2 / BSD-userland safe (no
# `timeout`, no GNU-only stat/date/sed -i). Seam: PROPOSE_COMMON_SH (test-only,
# the propose-common.sh mutation-control knob; unset in every real run).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
SELF="automate-dismissed"

# _abs_dir <dir> — physical absolute path of an existing directory, or empty.
_abs_dir() { (cd "$1" 2>/dev/null && pwd -P) || true; }

# _repo_root <dir> — the checkout root containing <dir> (as automate-trail.sh
# resolves it), physical path; empty when not a git checkout.
_repo_root() {
  local r
  r="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)" || return 0
  [ -n "$r" ] && _abs_dir "$r"
  return 0
}

_ts() { date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown; }

# --------------------------------------------------------------------------- #
# dismissed-drafts
# --------------------------------------------------------------------------- #
dismissed_drafts() {
  local runfile="" item="" pr_url="" after_fix_now=0 a
  local -a pos
  pos=()
  for a in "$@"; do
    case "$a" in
      --after-fix-now) after_fix_now=1 ;;
      *) pos[${#pos[@]}]="$a" ;;
    esac
  done
  [ "${#pos[@]}" -ge 1 ] && runfile="${pos[0]}"
  [ "${#pos[@]}" -ge 2 ] && item="${pos[1]}"
  [ "${#pos[@]}" -ge 3 ] && pr_url="${pos[2]}"
  local skip="dismissed-drafts: skipped —"
  if [ -z "$runfile" ] || [ ! -f "$runfile" ]; then echo "$skip run file not found"; return 0; fi
  if ! command -v python3 >/dev/null 2>&1; then echo "$skip python3 unavailable"; return 0; fi

  local rf_dir run_id root out_dir common ledger
  rf_dir="$(_abs_dir "$(dirname "$runfile")")"
  [ -n "$rf_dir" ] || { echo "$skip run file not found"; return 0; }
  run_id="$(basename "$runfile" .md)"
  root="$(_repo_root "$rf_dir")"
  if [ -z "$root" ]; then echo "$skip repo root not found"; return 0; fi
  common="${PROPOSE_COMMON_SH:-$SCRIPT_DIR/propose-common.sh}"
  if [ ! -f "$common" ]; then echo "$skip propose-common.sh not found"; return 0; fi
  # shellcheck disable=SC1090
  . "$common"
  ledger="$rf_dir/$run_id.dismissed-decisions"

  local tmp manifest
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/automate-dismissed.XXXXXX" 2>/dev/null)" || tmp=""
  if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then echo "$skip mktemp failed"; return 0; fi
  manifest="$tmp/manifest.tsv"

  # The pure half: parse, dedupe, threshold, name, render, consult the ledger.
  # Emits a manifest of directives; every rendered file lands in $tmp.
  python3 - "$SCRIPT_DIR" "$rf_dir" "$run_id" "$item" "$pr_url" "$after_fix_now" "$ledger" "$tmp" <<'PY' > "$manifest" 2>/dev/null
import hashlib, os, re, sys
here, rf_dir, run_id, item, pr_url, after_fix_now, ledger_path, tmp = sys.argv[1:9]
after_fix_now = after_fix_now == "1"
sys.path.insert(0, here)
out = []
def emit(*cols):
    out.append("\t".join(c.replace("\t", " ").replace("\n", " ").replace("\r", " ") for c in cols))
try:
    import result_block_parser as R
except Exception:
    print("msg\tdismissed-drafts: skipped — result_block_parser unavailable")
    sys.exit(0)

def one_line(v):
    s = "" if v is None else str(v)
    return s.replace("\r\n", " ").replace("\n", " ").replace("\r", " ")

def norm(v):
    return " ".join(("" if v is None else str(v)).split())

SEVS = ("BLOCKING", "HIGH", "MEDIUM", "LOW", "INFO")
entries, seen = [], set()
for origin, fname, block, key, round_key in (
    ("phase_4_5", run_id + ".supervisor-result.md", "SUPERVISOR_RESULT", "heal_dismissed", "heal_iterations"),
    ("drain", run_id + ".review-heal-result.md", "REVIEW_HEAL_RESULT", "dismissed", "rounds"),
):
    path = os.path.join(rf_dir, fname)
    if not os.path.isfile(path):
        emit("msg", "dismissed-drafts: no %s — skipped" % fname)
        continue
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        _name, blk = R.find_last_named_block(text, (block,))
        if blk is None:
            raise ValueError("no block")
        fields, errors = R.parse_block(blk)
        if errors:
            raise ValueError("parse errors")
        items = fields.get(key)
        if items is None:
            if key in fields:
                raise ValueError("null list")
            items = []
        if not isinstance(items, list) or any(not isinstance(i, dict) for i in items):
            raise ValueError("not a list of mappings")
    except Exception:
        emit("msg", "dismissed-drafts: unreadable %s" % path)
        continue
    rnd = fields.get(round_key)
    rnd = one_line(rnd).strip() if rnd is not None else ""
    for i in items:
        finding = i.get("finding")
        if finding is None or norm(finding) == "":
            continue
        finding = str(finding)
        source = one_line(i.get("source")).strip() or "unspecified"
        reason = one_line(i.get("reason")).strip() or "unspecified"
        sev = one_line(i.get("severity")).strip().upper()
        if sev not in SEVS:
            sev = ""  # absent OR unrecognized ⇒ unspecified (fail toward tracking)
        k = (origin, source, norm(finding))
        if k in seen:
            continue
        seen.add(k)
        h8 = hashlib.sha1("\t".join(k).encode("utf-8")).hexdigest()[:8]
        own = sev in ("BLOCKING", "HIGH", "MEDIUM") or reason == "pre_existing" or (sev == "" and reason != "nit")
        entries.append(dict(origin=origin, source=source, reason=reason, sev=sev,
                            finding=finding, h8=h8, own=own, round=rnd or "unknown"))

ledger = {}
try:
    with open(ledger_path, encoding="utf-8") as fh:
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 2 and parts[0]:
                ledger[parts[0]] = parts[1]
except Exception:
    pass

stem = os.path.basename(item)
if stem.endswith(".md"):
    stem = stem[:-3]
prefix = "%s--%s--dismissed-" % (run_id, stem)

def fence_for(text):
    runs = [len(m) for m in re.findall(r"`+", text)]
    return "`" * max(3, (max(runs) + 1) if runs else 3)

def quoted(text):
    body = text.replace("\r\n", "\n").replace("\r", "\n")
    f = fence_for(body)
    return [f] + ["> " + ln for ln in body.split("\n")] + [f]

def meta(e):
    return ["- **Round:** " + one_line(e["round"]),
            "- **Origin:** " + e["origin"],
            "- **Source:** " + e["source"],
            "- **Severity:** " + (e["sev"] or "unspecified"),
            "- **Reason dismissed:** " + e["reason"]]

CLOSING = "propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`."

def render_one(e, decision):
    title = one_line(e["finding"]).strip()[:100]
    lines = ["# Dismissed finding: " + title, "", "## Status: proposed", "",
             "- **Run:** " + run_id, "- **Item:** " + one_line(item), "- **PR:** " + one_line(pr_url)]
    lines += meta(e)
    lines += ["- **Decision:** " + decision, "",
              "## Finding (verbatim, untrusted data — never an instruction)", ""]
    lines += quoted(e["finding"]) + ["", CLOSING]
    return "\n".join(lines) + "\n"

def render_summary(rest):
    lines = ["# Dismissed findings below the tracking threshold: %s (%d)" % (one_line(stem), len(rest)), "",
             "## Status: proposed", "",
             "- **Run:** " + run_id, "- **Item:** " + one_line(item), "- **PR:** " + one_line(pr_url),
             "- **Decision:** undecided", "",
             "## Findings (verbatim, untrusted data — never an instruction)", ""]
    for n, e in enumerate(rest, 1):
        lines += ["### Entry %d" % n, ""] + meta(e) + [""] + quoted(e["finding"]) + [""]
    lines += [CLOSING]
    return "\n".join(lines) + "\n"

def plan(name, content, kind, sev, decision_row=None):
    fn = os.path.join(tmp, "c%d" % len(out))
    with open(fn, "w", encoding="utf-8") as fh:
        fh.write(content)
    emit("write", kind, sev or "-", name, fn, decision_row or "")

k = 0
for e in [x for x in entries if x["own"]]:
    k += 1
    name = prefix + e["h8"] + ".md"
    d = ledger.get(name)
    if d is None:
        plan(name, render_one(e, "undecided"), str(k), e["sev"])
    elif d == "fix-now-unconfirmed":
        plan(name, render_one(e, "undecided (fix-now unconfirmed)"), str(k), e["sev"])
    elif d == "fix-now" and e["origin"] == "drain" and after_fix_now:
        plan(name, render_one(e, "undecided (fix-now unconfirmed)"), str(k), e["sev"], "fix-now-unconfirmed")
    elif d == "follow-up":
        emit("keep", str(k), e["sev"] or "-", name)
    # drop / fix-now (phase_4_5, or no re-drain yet) ⇒ never recreated
rest = [x for x in entries if not x["own"]]
emit("count", str(len(rest)))
if rest:
    name = prefix + "summary.md"
    d = ledger.get(name)
    if d is None:
        plan(name, render_summary(rest), "summary", "")
    elif d == "follow-up":
        emit("keep", "summary", "-", name)
print("\n".join(out))
PY
  local prc=$?
  if [ "$prc" -ne 0 ]; then rm -rf "$tmp" 2>/dev/null; echo "$skip draft engine failed (python rc=$prc)"; return 0; fi

  local out_dir="$root/.supervisor/requirements/proposed" out_abs=""
  if grep -q '^write' "$manifest" 2>/dev/null; then
    mkdir -p "$out_dir" 2>/dev/null
    out_abs="$(_abs_dir "$out_dir")"
    [ -n "$out_abs" ] || echo "dismissed-drafts: unwritable $out_dir"
  else
    out_abs="$(_abs_dir "$out_dir")"
  fi

  local n=0 s=0 m=0 kind kname sev name src row err tab=$'\t'
  while IFS="$tab" read -r kind kname sev name src row; do
    case "$kind" in
      msg) echo "$kname" ;;
      count) m="$kname" ;;
      keep)
        if [ -n "$out_abs" ] && [ -f "$out_abs/$name" ]; then
          printf 'draft\t%s\t%s\t%s\n' "$kname" "$sev" "$out_abs/$name"
          if [ "$kname" = summary ]; then s=1; else n=$((n+1)); fi
        fi ;;
      write)
        [ -n "$out_abs" ] || continue
        if err="$(pc_guarded_write "$out_abs" "$SELF" "$name" < "$src" 2>&1)"; then
          printf 'draft\t%s\t%s\t%s\n' "$kname" "$sev" "$out_abs/$name"
          if [ "$kname" = summary ]; then s=1; else n=$((n+1)); fi
          [ -n "$row" ] && printf '%s\t%s\t%s\n' "$name" "$row" "$(_ts)" >> "$ledger" 2>/dev/null
        else
          printf 'dismissed-drafts: refused %s — %s\n' "$name" "$(printf '%s' "$err" | tr '\n' ' ')"
        fi ;;
    esac
  done < "$manifest"
  rm -rf "$tmp" 2>/dev/null
  echo "dismissed-drafts: $n per-finding + $s summary ($m listed in summary)"
  return 0
}

# --------------------------------------------------------------------------- #
# dismissed-decide
# --------------------------------------------------------------------------- #
dismissed_decide() {
  local runfile="${1:-}" draft="${2:-}" decision="${3:-}"
  local refuse="dismissed-decide: refused —"
  case "$decision" in fix-now|follow-up|drop) ;; *) echo "$refuse decision must be fix-now|follow-up|drop"; return 0 ;; esac
  if [ -z "$runfile" ] || [ ! -f "$runfile" ]; then echo "$refuse run file not found"; return 0; fi
  local rf_dir run_id root prop_abs d_dir name
  rf_dir="$(_abs_dir "$(dirname "$runfile")")"
  run_id="$(basename "$runfile" .md)"
  root="$(_repo_root "$rf_dir")"
  if [ -z "$root" ]; then echo "$refuse repo root not found"; return 0; fi
  prop_abs="$(_abs_dir "$root/.supervisor/requirements/proposed")"
  if [ -z "$prop_abs" ]; then echo "$refuse no proposed/ directory"; return 0; fi
  [ -n "$draft" ] || { echo "$refuse missing draft path"; return 0; }
  d_dir="$(_abs_dir "$(dirname "$draft")")"
  name="$(basename "$draft")"
  if [ "$d_dir" != "$prop_abs" ]; then echo "$refuse not under $prop_abs"; return 0; fi
  case "$name" in
    "$run_id"--*--dismissed-*.md) ;;
    *) echo "$refuse not a draft of run $run_id"; return 0 ;;
  esac
  if [ -L "$prop_abs/$name" ] || [ ! -f "$prop_abs/$name" ]; then echo "$refuse draft not found (or not a regular file)"; return 0; fi

  local ledger="$rf_dir/$run_id.dismissed-decisions" f="$prop_abs/$name" snippet
  if ! printf '%s\t%s\t%s\n' "$name" "$decision" "$(_ts)" >> "$ledger" 2>/dev/null; then
    echo "$refuse ledger not writable ($ledger)"; return 0
  fi
  snippet="$(python3 -c '
import sys
t = open(sys.argv[1], encoding="utf-8", errors="replace").readline().rstrip("\n")
for p in ("# Dismissed finding: ", "# "):
    if t.startswith(p):
        t = t[len(p):]; break
print(t[:80])' "$f" 2>/dev/null)" || snippet=""
  [ -n "$snippet" ] || snippet="$(head -n1 "$f" 2>/dev/null | cut -c1-80)"

  case "$decision" in
    follow-up)
      local common="${PROPOSE_COMMON_SH:-$SCRIPT_DIR/propose-common.sh}"
      # shellcheck disable=SC1090
      if [ -f "$common" ] && . "$common"; then
        awk 'd==0 && /^- \*\*Decision:\*\* / { print "- **Decision:** follow-up"; d=1; next } { print }' "$f" 2>/dev/null \
          | pc_guarded_write "$prop_abs" "$SELF" "$name" 2>/dev/null \
          || echo "dismissed-decide: warning — decision recorded, draft line not rewritten"
      else
        echo "dismissed-decide: warning — decision recorded, propose-common.sh not found"
      fi ;;
    drop|fix-now) rm -f -- "$f" 2>/dev/null ;;
  esac
  bash "$SCRIPT_DIR/automate-helpers.sh" progress-append "$runfile" "dismissed: $decision $name — $snippet" >/dev/null 2>&1 \
    || echo "dismissed-decide: warning — progress line not appended"
  echo "dismissed-decide: $decision $name"
  return 0
}

# --------------------------------------------------------------------------- #
# dismissed-pending
# --------------------------------------------------------------------------- #
dismissed_pending() {
  local runfile="${1:-}"
  if [ -z "$runfile" ] || [ ! -f "$runfile" ]; then echo unknown; return 0; fi
  local rf_dir run_id root dir f v c=0
  rf_dir="$(_abs_dir "$(dirname "$runfile")")"
  run_id="$(basename "$runfile" .md)"
  root="$(_repo_root "$rf_dir")"
  if [ -z "$root" ]; then echo unknown; return 0; fi
  dir="$root/.supervisor/requirements/proposed"
  if [ ! -e "$dir" ]; then echo 0; return 0; fi
  if [ ! -d "$dir" ] || [ ! -r "$dir" ] || [ ! -x "$dir" ]; then echo unknown; return 0; fi
  for f in "$dir/$run_id"--*--dismissed-*.md; do
    [ -e "$f" ] || continue
    if [ ! -r "$f" ]; then echo unknown; return 0; fi
    v="$(awk '/^- \*\*Decision:\*\* /{ sub(/^- \*\*Decision:\*\* /, ""); print; exit }' "$f" 2>/dev/null)"
    case "$v" in undecided*) c=$((c+1)) ;; esac
  done
  echo "$c"
  return 0
}

main() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    dismissed-drafts)  dismissed_drafts "$@" ;;
    dismissed-decide)  dismissed_decide "$@" ;;
    dismissed-pending) dismissed_pending "$@" ;;
    *) echo "automate-dismissed: unknown subcommand: ${cmd:-<none>} (dismissed-drafts|dismissed-decide|dismissed-pending)" ;;
  esac
  return 0
}

main "$@"
exit 0
