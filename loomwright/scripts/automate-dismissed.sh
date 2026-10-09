#!/usr/bin/env bash
# automate-dismissed.sh — the `/automate` engine's dismissed-findings drafts.
# PROTOCOL AUTHORITY: `skills/automate-loop/SKILL.md` §6 "Dismissed-findings
# decision step (before the park)" — the THRESHOLD rule, the ask order, fix-now
# and the next-PICK ask are written there once; this script implements the
# mechanical half. Dispatched from `automate-helpers.sh`
# (`exec bash "$(dirname "$0")/automate-dismissed.sh" <subcmd>`).
#
# SCOPE OF ITS WRITES (the whole list — anything else is a bug):
#   * draft files `<run_id>--<item_stem>-<ih6>--dismissed-<h8|summary|summary-<N>>.md`
#     (ih6 = first 6 hex of sha1 of the FULL Queue item path, so two items that
#     share a basename in different directories never share a namespace) in
#     `<repo>/.supervisor/requirements/proposed/`, every one of them through
#     propose-common.sh's `pc_guarded_write` (the ONE canonical `proposed/`
#     write guard — no second name check here, so its mutation control stays
#     live), plus `rm` of THIS run's draft on a `drop` / `fix-now` decision, and
#     of an UNDECIDED draft of THIS run retired because its finding moved to the
#     other bucket (a `moved` ledger row first);
#   * the gitignored decision ledger `<run_id>.dismissed-decisions` beside the
#     run file (`draft_name<TAB>decision<TAB>ts`, keyed by draft NAME, last row
#     wins; plus `summary-member<TAB><h8><TAB>summary_name` rows recording which
#     entries a DECIDED summary listed; `moved` rows are placement records, never
#     decisions), and ONE `## Progress` line per decision via
#     `automate-helpers.sh progress-append`.
# It never runs `gh`, `git commit`, `git push` or any other git mutation (only
# `git rev-parse --show-toplevel`), and never merges anything. `dismissed-cost`
# writes NOTHING (read-only advisory estimator).
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
#       listed in a summary draft. Zero items ⇒ no files. Per-finding names are
#       content addressed: h8 = first 8 hex of sha1("origin\tsource\tnormalized
#       finding"). Summary SLOTS are `summary.md`, `summary-2.md`, …: a decided
#       slot covers exactly the entries its `summary-member` rows name; every
#       below-threshold entry no decided slot covers is (re)written into the first
#       slot with no ledger row — so a decided summary never hides a finding it did
#       not list, and there is at most one undecided summary per item.
#       DECISIONS ARE PER FINDING, ACROSS BUCKETS (h8 omits severity, so a
#       rewritten sidecar can move a finding between its own draft and a
#       summary): a decision on its own-draft name governs it wherever it now
#       falls (a fix-now finding is never put in a summary), else a decided
#       summary that listed it does; an undecided finding is placed by the
#       threshold, and an UNDECIDED draft of it left in the other bucket is
#       retired (`moved` ledger row, then removed; a `retired <name>` line) —
#       only AFTER the finding's new draft was written in this pass (a refused
#       write keeps the old draft, `kept <name> — …`), only while that old
#       draft's on-disk `- **Decision:**` still starts with `undecided` (a
#       hand-edited one is kept, `kept <name> — …`), and an undecided summary
#       slot only when EVERY entry it lists is a current finding (one that
#       vanished from the sidecars may have no other record — the slot stays
#       and is asked about).
#       LEDGER: missing ⇒ empty. EXISTING but unreadable (EACCES, a non-UTF-8
#       byte, …) ⇒ ONE `dismissed-drafts: skipped — unreadable ledger <path>`
#       line and nothing written, retired or appended (read as empty it would
#       reset every decision and resurrect dropped drafts).
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
#       refused <name> — <reason>`, `dismissed-drafts: retired <name> — its
#       finding moved to the other bucket`, `dismissed-drafts: kept <name> — …`),
#       then ONE summary line
#       `dismissed-drafts: <n> per-finding + <s> summary (<m> listed in summary)`
#       (s = summary files written or kept; m = current entries listed in one of
#       them — an entry in a DROPPED summary is not counted; an above-threshold
#       entry that inherits a kept summary's follow-up counts in m, not in n).
#   dismissed-decide <runfile> <draft_path> <fix-now|follow-up|drop>
#       Refuses (`dismissed-decide: refused — <reason>`) a path that is not a
#       regular file directly under `proposed/` named `<this run_id>--*--dismissed-*.md`
#       (or, given a `--parallel` PARENT run file, `<run_id>-L<n>--*--dismissed-*.md` —
#       a lane draft, decided against that lane's ledger when present, else this one),
#       and `fix-now` on a summary draft (Keep / Drop only there), and any
#       decision while the ledger EXISTS but cannot be read back (a row nobody
#       can read is no record, and drop / fix-now delete the draft on it).
#       Appends the ledger row FIRST (nothing is deleted without a record; for a
#       summary, its `summary-member` rows precede it in the same append), then
#       rewrites the draft's `- **Decision:**` line (follow-up) or deletes the
#       draft (drop / fix-now), then progress-appends ONE line
#       `dismissed: <decision> <draft_name> — <first 80 chars of finding>`.
#   dismissed-pending <runfile>
#       Prints the count of this run's drafts (and its lanes' `<run_id>-L<n>--…`
#       drafts — parallel-automate/05) whose first `- **Decision:**` value
#       STARTS WITH `undecided` (so `undecided (fix-now unconfirmed)` counts), or
#       `unknown` when it cannot tell — including a draft with no readable
#       `- **Decision:**` value and an existing but unreadable ledger (the
#       caller treats `unknown` as non-zero — fail closed toward asking).
#   dismissed-cost <runfile>
#       READ-ONLY advisory estimate of what a fix-now costs (Part T02; never feeds
#       a gate). Prints exactly ONE line `fix_now_cost: <estimate> (<basis>)`.
#       Samples: every `*.dismissed-decisions` ledger in the run file's directory
#       with its sibling `<run_id>.md`. Its `fix-now` rows group into decision
#       batches (a row within 600 s of the previous one joins its batch; start =
#       the batch's earliest ts). End = the first fix-now re-drain TERMINAL line
#       in that run's `## Progress` after the batch's own `dismissed: fix-now
#       <draft>` line (none ⇒ after the previous batch's terminal; each terminal
#       ends at most one batch): the pinned `<ts> fix-now re-drain READY|ESCALATED`
#       (SKILL §6 step 3), or a legacy `<ts> [fix-now ]re-drain …` line carrying
#       READY / ESCALATED / `SETTLED required=green`. A span with end <= start
#       (an out-of-order pairing) or > 12 h (owner think-time, an overnight
#       stall) is dropped. With samples the basis is `median of <n> recorded
#       fix-now re-drains in this repo, range <min>–<max>`; with none (or an
#       unreadable ledger / run file, which only skips that run, or no python3)
#       the line is loomwright's own 2026-10 baseline, labelled as such.
#
# Every draft carries the planner's `## Depends on` (`none`) and `## Touches` sections (parallel-
# automate/10) before its `## Finding(s)` heading: Touches = the existing repo files the finding's
# source / text names (existence test only), else `unknown`; they never feed a name or a decision.
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

# _ledger_unreadable <path> — true (0) when the decision ledger EXISTS (or is a
# dangling symlink) but cannot be read back as UTF-8 text (EACCES, a non-UTF-8
# byte, a directory, no python3 to tell). A missing ledger is fine (false).
_ledger_unreadable() {
  { [ -e "$1" ] || [ -L "$1" ]; } || return 1
  command -v python3 >/dev/null 2>&1 || return 0
  python3 -c 'import sys
with open(sys.argv[1], encoding="utf-8") as fh:
    fh.read()' "$1" >/dev/null 2>&1 && return 1
  return 0
}

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
  python3 - "$SCRIPT_DIR" "$rf_dir" "$run_id" "$item" "$pr_url" "$after_fix_now" "$ledger" "$tmp" "$root/.supervisor/requirements/proposed" "$root" <<'PY' > "$manifest" 2>/dev/null
import hashlib, os, re, sys
here, rf_dir, run_id, item, pr_url, after_fix_now, ledger_path, tmp, prop_dir, repo_root = sys.argv[1:11]
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

# INFO is reachable only from a drain main-pass item (review-heal stated_severity(f), raw stated text);
# Phase 4.5 heal_dismissed and Earned-Fallback items carry CODE_REVIEW_RESULT's closed BLOCKING|HIGH|MEDIUM|LOW.
SEVS = ("BLOCKING", "HIGH", "MEDIUM", "LOW", "INFO")

# The ledger FIRST. Missing ⇒ empty (no decision yet). EXISTING but unreadable
# (EACCES, a non-UTF-8 byte, a directory, a dangling symlink) ⇒ abort the whole
# pass: read as empty, every decision would look undecided, a dropped draft
# would be resurrected and a `moved` row appended after a follow-up row would
# make that reset permanent (last row wins) once the ledger is repaired.
ledger, members = {}, {}
if os.path.lexists(ledger_path):
    try:
        with open(ledger_path, encoding="utf-8") as fh:
            ledger_lines = fh.read().split("\n")
    except Exception:
        print("abort\tdismissed-drafts: skipped — unreadable ledger %s" % one_line(ledger_path).replace("\t", " "))
        sys.exit(0)
    for line in ledger_lines:
        parts = line.split("\t")
        if len(parts) >= 3 and parts[0] == "summary-member":
            members.setdefault(parts[2], set()).add(parts[1])
        elif len(parts) >= 2 and parts[0]:
            ledger[parts[0]] = parts[1]

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

DECISIONS = ("follow-up", "drop", "fix-now", "fix-now-unconfirmed")
def decided(name):
    # A `moved` row (this script retired an UNDECIDED draft because its finding
    # now belongs in the other bucket) is a placement record, never a decision.
    d = ledger.get(name)
    return d if d in DECISIONS else None

stem = os.path.basename(item)
if stem.endswith(".md"):
    stem = stem[:-3]
# The per-item namespace is keyed by the FULL item path as written in the Queue,
# not its basename: `f/01-a.md` and `g/01-a.md` in one run get disjoint drafts,
# summary slots and ledger rows (the stem stays for readability; ih6 disambiguates).
ih6 = hashlib.sha1(item.encode("utf-8")).hexdigest()[:6]
prefix = "%s--%s-%s--dismissed-" % (run_id, stem, ih6)
ITEM_LINE = "- **Item:** " + one_line(item)

def foreign(name):
    # Defence in depth (never trust the namespace alone): a draft on disk whose
    # first column-0 `- **Item:**` line is not this item's (or is missing, so
    # ownership cannot be shown) is never rewritten or retired by this item.
    # Only a regular file is judged here: a symlink or other non-regular entry is
    # left to pc_guarded_write, the ONE canonical guard (its mutation control).
    p = os.path.join(prop_dir, name)
    if os.path.islink(p) or not os.path.isfile(p):
        return False
    try:
        with open(p, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if line.startswith("- **Item:** "):
                    return line.rstrip("\n") != ITEM_LINE
    except Exception:
        return True
    return True

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

# `## Depends on` / `## Touches` (parallel-automate/10) — the planner's machine-read sections, so a
# promoted draft is lint-clean (`automate-helpers.sh plan-waves --lint`). Depends on is always
# `none`. Touches = every token of the finding's `source` and text that is a repo-relative FILE path
# under the Touches grammar (chars [A-Za-z0-9._/@+-], contains `/` or `.`, no leading `/`, no `//`,
# no `.`/`..` segment) AND passes the CONTAINMENT rule — else `unknown`. Containment: the token's
# first segment is not `.git` (any case); its parent directory, physically resolved (os.path.realpath
# here, `cd -P … && pwd -P` in vt_touches), is the resolved repo root or strictly under it and not in
# its `.git` dir; and its final component is a regular file that is NOT itself a symlink. So a
# committed symlink can never turn an existence test into a probe of a path outside the checkout
# (an in-repo symlinked DIRECTORY that resolves inside the root is accepted as written; a symlinked
# FILE is always rejected, wherever it points). The text is untrusted: a token is only ever matched
# by regex and passed to stat-style tests (realpath / islink / isfile), never opened, executed or
# interpolated; grammar-valid tokens cannot start a `#`/`-` line. The
# sections do NOT feed the draft's identity: h8 and every ledger decision come from origin/source/
# finding only, so a named file appearing or vanishing between passes rewrites the body of an
# undecided draft under the SAME name and never touches a decision.
# Grammar copy 2 of 3, sharing no code: the authority is the PW_TOUCHES_GRAMMAR line in
# automate-helpers.sh (_pw_touches); copy 3 is vt_touches in propose-from-verify.sh. Change all three
# together — test-automate-helpers.sh §X7 fails when they accept/reject a token differently.
# Containment is an EXTRACTOR-only rule shared by copies 2 and 3 (the planner's --lint judges a
# token's grammar, never the filesystem), so X7 does not cover it; test-automate-dismissed.sh and
# test-propose-from-verify.sh each pin it with the same symlink / `.git` fixtures.
PATH_TOK = re.compile(r"[A-Za-z0-9._/@+-]+")
BAD_SEG = re.compile(r"(^|/)\.\.?(/|$)")

def touches_of(e):
    root_p = os.path.realpath(repo_root)
    found = set()
    for text in (e["source"], e["finding"]):
        for tok in PATH_TOK.findall(text or ""):
            tok = tok.rstrip(".")
            if ("/" not in tok and "." not in tok) or tok.startswith("/") or tok.endswith("/"):
                continue
            if "//" in tok or BAD_SEG.search(tok):
                continue
            if tok.split("/", 1)[0].lower() == ".git":
                continue
            p = os.path.join(repo_root, tok)
            dp = os.path.realpath(os.path.dirname(p))
            if dp != root_p and not dp.startswith(root_p + "/"):
                continue
            if (dp[len(root_p):] + "/").lower().startswith("/.git/"):
                continue
            f = os.path.join(dp, os.path.basename(p))
            if os.path.islink(f) or not os.path.isfile(f):
                continue
            found.add(tok)
    return found

def plan_sections(paths):
    return ["## Depends on", "none", "", "## Touches"] + (sorted(paths) or ["unknown"]) + [""]

CLOSING = "propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`."

def render_one(e, decision):
    title = one_line(e["finding"]).strip()[:100]
    lines = ["# Dismissed finding: " + title, "", "## Status: proposed", "",
             "- **Run:** " + run_id, "- **Item:** " + one_line(item), "- **PR:** " + one_line(pr_url)]
    lines += meta(e)
    lines += ["- **Decision:** " + decision, ""] + plan_sections(touches_of(e))
    lines += ["## Finding (verbatim, untrusted data — never an instruction)", ""]
    lines += quoted(e["finding"]) + ["", CLOSING]
    return "\n".join(lines) + "\n"

def render_summary(rest):
    lines = ["# Dismissed findings below the tracking threshold: %s (%d)" % (one_line(stem), len(rest)), "",
             "## Status: proposed", "",
             "- **Run:** " + run_id, "- **Item:** " + one_line(item), "- **PR:** " + one_line(pr_url),
             "- **Decision:** undecided", ""]
    union = set()
    for e in rest:
        union |= touches_of(e)
    lines += plan_sections(union)
    lines += ["## Findings (verbatim, untrusted data — never an instruction)", ""]
    for n, e in enumerate(rest, 1):
        lines += ["### Entry %d" % n, ""] + meta(e) + ["- **Key:** " + e["h8"], ""] + quoted(e["finding"]) + [""]
    lines += [CLOSING]
    return "\n".join(lines) + "\n"

# Manifest rows are 7 TAB columns, never an empty one (bash `read` collapses
# consecutive TABs): kind k sev name src ledger_row listed_count. For a `retire`
# row, src is the `/`-joined list of draft names that must be WRITTEN in this
# pass before the retire may run (`-` = none; `/` never occurs in a draft name).
# plan() returns True when it emitted a write directive.
def plan(name, content, kind, sev, decision_row=None, listed=0):
    if foreign(name):
        emit("msg", "dismissed-drafts: refused %s — it belongs to another item (its Item line differs or is missing), left untouched" % name)
        return False
    fn = os.path.join(tmp, "c%d" % len(out))
    with open(fn, "w", encoding="utf-8") as fh:
        fh.write(content)
    emit("write", kind, sev or "-", name, fn, decision_row or "-", str(listed))
    return True

# DECISIONS ARE PER FINDING, ACROSS BUCKETS. h8 omits severity, so a rewritten
# sidecar can move one finding between its OWN draft and a summary (e.g. the
# re-drain re-dismisses it at another severity). Its decision follows it:
#   * a ledger decision on its own-draft name (`<prefix><h8>.md`) governs it
#     wherever the threshold now puts it — follow-up ⇒ that draft is kept; drop ⇒
#     never recreated (no summary line either); fix-now ⇒ suppressed, or, when
#     drain-origin and `--after-fix-now`, its OWN draft re-written
#     `undecided (fix-now unconfirmed)` (never a summary line: fix-now is refused
#     on summaries);
#   * else a `summary-member` row in a DECIDED summary slot governs it — follow-up
#     ⇒ that summary is kept (not re-asked); drop ⇒ not recreated as own or summary;
#   * else it is undecided and placed by the threshold. An UNDECIDED draft of it
#     left in the other bucket (its own draft, or the undecided summary slot when
#     no current entry belongs in it and it lists one now placed elsewhere) is
#     retired: a `moved` ledger row
#     FIRST, then the file is removed — so the finding is never listed (or asked,
#     or counted) twice, and the trail retracts the stale blob by that row.
# Summary SLOTS: `summary.md`, then `summary-2.md`, `summary-3.md`, … A DECIDED
# slot (a decision row) covers exactly the entries it listed when decided — its
# `summary-member<TAB><h8><TAB><slot name>` rows, written by dismissed-decide
# from the slot's `- **Key:**` lines. Every undecided below-threshold entry goes
# into the first slot with no decision (rewritten in place on a re-run, so there
# is never a second undecided one): a decided summary never hides a finding it
# did not list. A genuinely NEW finding (new h8) has no decision anywhere and is
# always drafted.
def own_name(e):
    return prefix + e["h8"] + ".md"

decided_slots, i = [], 1
while True:
    nm = prefix + ("summary.md" if i == 1 else "summary-%d.md" % i)
    d = decided(nm)
    if d is None:
        undecided_slot = nm
        break
    decided_slots.append((nm, d, members.get(nm, set())))
    i += 1

def inherited(h8):
    for nm, d, mem in decided_slots:
        if h8 in mem:
            return nm, d
    return None, None

def on_disk(name):
    p = os.path.join(prop_dir, name)
    return os.path.isfile(p) and not os.path.islink(p)

# home[h8] — where the finding lives after this pass: a draft name this pass
# writes (a retire of its old draft waits on that write), "" (a decision or a
# kept follow-up covers it — no new draft needed), or None (its new draft was
# refused here — nothing of it may be retired).
k, kept_slot, to_summary, home, own_retires = 0, {}, [], {}, []
for e in [x for x in entries if x["own"]] + [x for x in entries if not x["own"]]:
    name = own_name(e)
    d = decided(name)
    if e["own"] or d is not None:
        k += 1
    if d is not None:
        home[e["h8"]] = ""
        if d == "fix-now-unconfirmed":
            home[e["h8"]] = name if plan(name, render_one(e, "undecided (fix-now unconfirmed)"), str(k), e["sev"]) else None
        elif d == "fix-now" and e["origin"] == "drain" and after_fix_now:
            home[e["h8"]] = name if plan(name, render_one(e, "undecided (fix-now unconfirmed)"), str(k), e["sev"], "fix-now-unconfirmed") else None
        elif d == "follow-up":
            emit("keep", str(k), e["sev"] or "-", name, "-", "-", "0")
        # drop / fix-now (phase_4_5, or no re-drain yet) ⇒ never recreated
        continue
    snm, sd = inherited(e["h8"])
    if snm is not None:
        home[e["h8"]] = ""
        if sd == "follow-up":
            kept_slot[snm] = kept_slot.get(snm, 0) + 1
        continue  # drop ⇒ never recreated, in either bucket
    if e["own"]:
        home[e["h8"]] = name if plan(name, render_one(e, "undecided"), str(k), e["sev"]) else None
    else:
        to_summary.append(e)
        if on_disk(name) and not foreign(name):
            own_retires.append(name)
for nm, d, mem in decided_slots:
    if nm in kept_slot:
        emit("keep", "summary", "-", nm, "-", "-", str(kept_slot[nm]))
# Every retire is emitted AFTER every write and names the write(s) it waits on:
# the bash half runs it only once each of them succeeded (pc_guarded_write can
# still refuse one), so a finding is never left with no draft.
if to_summary:
    if plan(undecided_slot, render_summary(to_summary), "summary", "", None, len(to_summary)):
        for nm in own_retires:
            emit("retire", "-", "-", nm, undecided_slot, "moved", "0")
elif on_disk(undecided_slot) and not foreign(undecided_slot):
    keys = set()
    try:
        with open(os.path.join(prop_dir, undecided_slot), encoding="utf-8") as fh:
            for line in fh:
                m = re.match(r"^- \*\*Key:\*\* ([0-9a-f]{8})$", line.rstrip("\n"))
                if m:
                    keys.add(m.group(1))
    except Exception:
        keys = set()
    # No current finding belongs in it. Retired ONLY when every entry it lists
    # is a CURRENT finding with a home (a draft written in this pass, or a
    # decision) — an entry absent from the current sidecars (vanished, or both
    # sidecars missing / unreadable) may have no other record, so the slot is
    # left on disk and asked about (fails toward asking; SKILL §6 honest limits).
    cur = set(x["h8"] for x in entries)
    if keys and keys <= cur and all(home.get(h) is not None for h in keys):
        deps = sorted(set(home[h] for h in keys if home[h]))
        emit("retire", "-", "-", undecided_slot, "/".join(deps) or "-", "moved", "0")
print("\n".join(out))
PY
  local prc=$?
  if [ "$prc" -ne 0 ]; then rm -rf "$tmp" 2>/dev/null; echo "$skip draft engine failed (python rc=$prc)"; return 0; fi
  # An EXISTING but unreadable ledger: the engine emitted only an `abort` row.
  # Write nothing, retire nothing, append no ledger row — ONE skipped line.
  local abort_line
  abort_line="$(awk -F'\t' '$1 == "abort" { print $2; exit }' "$manifest" 2>/dev/null)"
  if [ -n "$abort_line" ]; then rm -rf "$tmp" 2>/dev/null; echo "$abort_line"; return 0; fi

  local out_dir="$root/.supervisor/requirements/proposed" out_abs=""
  if grep -q '^write' "$manifest" 2>/dev/null; then
    mkdir -p "$out_dir" 2>/dev/null
    out_abs="$(_abs_dir "$out_dir")"
    [ -n "$out_abs" ] || echo "dismissed-drafts: unwritable $out_dir"
  else
    out_abs="$(_abs_dir "$out_dir")"
  fi

  local n=0 s=0 m=0 kind kname sev name src row cnt err tab=$'\t' nl=$'\n'
  local written="$nl" rest dep dep_ok v
  while IFS="$tab" read -r kind kname sev name src row cnt; do
    case "$cnt" in ''|*[!0-9]*) cnt=0 ;; esac
    case "$kind" in
      msg) echo "$kname" ;;
      retire)
        # An UNDECIDED draft whose finding the ledger/threshold now places in the
        # other bucket: the `moved` row FIRST (the trail retracts the blob by it),
        # then the file. Only a regular file, never a symlink. The engine emits
        # every retire after every write; `src` names the write(s) it waits on —
        # one that pc_guarded_write refused keeps the old draft (the finding is
        # never left with no draft). A draft whose on-disk Decision value does
        # not start with `undecided` (hand-edited) is kept too.
        if [ -n "$out_abs" ] && [ -f "$out_abs/$name" ] && [ ! -L "$out_abs/$name" ]; then
          dep_ok=1; rest="$src"; [ "$rest" = "-" ] && rest=""
          while [ -n "$rest" ]; do
            dep="${rest%%/*}"
            case "$rest" in */*) rest="${rest#*/}" ;; *) rest="" ;; esac
            case "$written" in *"$nl$dep$nl"*) ;; *) dep_ok=0 ;; esac
          done
          if [ "$dep_ok" -ne 1 ]; then
            printf 'dismissed-drafts: kept %s — the new draft for its finding was not written, not retired\n' "$name"
            continue
          fi
          v="$(awk '/^- \*\*Decision:\*\* /{ sub(/^- \*\*Decision:\*\* /, ""); print; exit }' "$out_abs/$name" 2>/dev/null)"
          case "$v" in
            undecided*) ;;
            *) printf 'dismissed-drafts: kept %s — its on-disk Decision is not undecided (hand-edited), not retired\n' "$name"
               continue ;;
          esac
          if printf '%s\t%s\t%s\n' "$name" moved "$(_ts)" >> "$ledger" 2>/dev/null; then
            rm -f -- "$out_abs/$name" 2>/dev/null
            printf 'dismissed-drafts: retired %s — its finding moved to the other bucket\n' "$name"
          fi
        fi ;;
      keep)
        if [ -n "$out_abs" ] && [ -f "$out_abs/$name" ]; then
          printf 'draft\t%s\t%s\t%s\n' "$kname" "$sev" "$out_abs/$name"
          if [ "$kname" = summary ]; then s=$((s+1)); m=$((m+cnt)); else n=$((n+1)); fi
        fi ;;
      write)
        [ -n "$out_abs" ] || continue
        if err="$(pc_guarded_write "$out_abs" "$SELF" "$name" < "$src" 2>&1)"; then
          printf 'draft\t%s\t%s\t%s\n' "$kname" "$sev" "$out_abs/$name"
          written="$written$name$nl"
          if [ "$kname" = summary ]; then s=$((s+1)); m=$((m+cnt)); else n=$((n+1)); fi
          [ "$row" != "-" ] && printf '%s\t%s\t%s\n' "$name" "$row" "$(_ts)" >> "$ledger" 2>/dev/null
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
# lane drafts (parallel-automate/05, Scope 7)
# --------------------------------------------------------------------------- #
# A lane of a `--parallel N>1` parent run `<parent>` has run id `<parent>-L<n>`, so
# its drafts are named `<parent>-L<n>--…--dismissed-*.md` — invisible to the
# parent's own `<parent>--*` glob. dismissed-pending / dismissed-decide given the
# PARENT run file also see them; each lane draft is decided against its lane's
# ledger `<parent>-L<n>.dismissed-decisions` beside the parent run file when that
# file exists (a managed metadata path, D9 — it reaches the primary on the pull),
# else the parent's. A lane run file (or any non-parent run) has no `-L<n>` lanes,
# so nothing changes for it.

# _dismissed_lane_id <run_id> <draft_name> — prints `<run_id>-L<digits>` when the
# name is a lane draft of <run_id> (`<run_id>-L<digits>--*--dismissed-*.md`), else nothing.
_dismissed_lane_id() {
  local rid="$1" n="$2" rest num
  case "$n" in "$rid"-L[0-9]*--*--dismissed-*.md) ;; *) return 0 ;; esac
  rest="${n#"$rid"-L}"; num="${rest%%--*}"
  case "$num" in ""|*[!0-9]*) return 0 ;; esac
  printf '%s-L%s\n' "$rid" "$num"
}

# _dismissed_lane_drafts <proposed_dir> <run_id> — one path per line: every
# regular, non-symlink lane draft of <run_id> in <proposed_dir> (sorted).
_dismissed_lane_drafts() {
  local d="$1" rid="$2" f
  for f in "$d/$rid"-L[0-9]*--*--dismissed-*.md; do
    [ -f "$f" ] && [ ! -L "$f" ] || continue
    [ -n "$(_dismissed_lane_id "$rid" "${f##*/}")" ] && printf '%s\n' "$f"
  done | env LC_ALL=C sort
}

# _dismissed_lane_ledger <rf_dir> <run_id> <lane_id> — the ledger a lane draft is
# decided against: the lane's own when it exists (or is a dangling entry), else the parent's.
_dismissed_lane_ledger() {
  if [ -e "$1/$3.dismissed-decisions" ] || [ -L "$1/$3.dismissed-decisions" ]; then
    printf '%s\n' "$1/$3.dismissed-decisions"
  else
    printf '%s\n' "$1/$2.dismissed-decisions"
  fi
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
  local lane_id=""
  case "$name" in
    "$run_id"--*--dismissed-*.md) ;;
    *) lane_id="$(_dismissed_lane_id "$run_id" "$name")"
       [ -n "$lane_id" ] || { echo "$refuse not a draft of run $run_id"; return 0; } ;;
  esac
  if [ -L "$prop_abs/$name" ] || [ ! -f "$prop_abs/$name" ]; then echo "$refuse draft not found (or not a regular file)"; return 0; fi
  local is_summary=0
  case "$name" in *--dismissed-summary.md|*--dismissed-summary-[0-9]*.md) is_summary=1 ;; esac
  if [ "$is_summary" -eq 1 ] && [ "$decision" = fix-now ]; then
    echo "$refuse fix-now is not offered on a summary draft (follow-up|drop)"; return 0
  fi

  local ledger="$rf_dir/$run_id.dismissed-decisions" f="$prop_abs/$name" snippet rows="" ts
  # A lane draft (parallel-automate/05) is decided against ITS lane's ledger when
  # present beside the parent run file, else the parent's.
  [ -n "$lane_id" ] && ledger="$(_dismissed_lane_ledger "$rf_dir" "$run_id" "$lane_id")"
  # A row appended to a ledger that cannot be read back is no record at all
  # (dismissed-drafts skips the whole pass on it), yet drop / fix-now would
  # delete the draft on its strength — so refuse, touching nothing.
  if _ledger_unreadable "$ledger"; then echo "$refuse unreadable ledger $ledger"; return 0; fi
  ts="$(_ts)"
  # A summary's decision covers exactly the entries it lists: one
  # `summary-member<TAB><h8><TAB><name>` row per `- **Key:**` line (script-written,
  # column 0 — a quoted finding line can never forge one), BEFORE the decision
  # row, in the same append. dismissed-drafts routes every uncovered entry to a
  # new undecided slot.
  if [ "$is_summary" -eq 1 ]; then
    rows="$(awk -v n="$name" '/^- \*\*Key:\*\* [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]$/ { printf "summary-member\t%s\t%s\n", $3, n }' "$f" 2>/dev/null)"
    [ -n "$rows" ] && rows="$rows"$'\n'
  fi
  if ! printf '%s%s\t%s\t%s\n' "$rows" "$name" "$decision" "$ts" >> "$ledger" 2>/dev/null; then
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
  # iq02 T04 3b: the same leading UTC `<ts>` every other Progress line carries —
  # the moment the owner's decision was recorded (phase-timing.sh reads it).
  local dts; dts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
  bash "$SCRIPT_DIR/automate-helpers.sh" progress-append "$runfile" "${dts:+$dts }dismissed: $decision $name — $snippet" >/dev/null 2>&1 \
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
  # An existing but unreadable ledger ⇒ the drafts on disk may not reflect the
  # decisions (dismissed-drafts skipped) ⇒ cannot tell (fail closed toward asking).
  if _ledger_unreadable "$rf_dir/$run_id.dismissed-decisions"; then echo unknown; return 0; fi
  dir="$root/.supervisor/requirements/proposed"
  if [ ! -e "$dir" ]; then echo 0; return 0; fi
  if [ ! -d "$dir" ] || [ ! -r "$dir" ] || [ ! -x "$dir" ]; then echo unknown; return 0; fi
  local lanes l
  lanes="$(_dismissed_lane_drafts "$dir" "$run_id")"
  # A lane's ledger that exists but cannot be read ⇒ unknown, as for the parent's.
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    if _ledger_unreadable "$rf_dir/$(_dismissed_lane_id "$run_id" "${l##*/}").dismissed-decisions"; then echo unknown; return 0; fi
  done <<LANES
$lanes
LANES
  local ifs0="$IFS"; IFS=$'\n'   # $lanes splits on newlines only (paths may hold spaces)
  for f in "$dir/$run_id"--*--dismissed-*.md $lanes; do
    IFS="$ifs0"
    [ -e "$f" ] || continue
    if [ ! -r "$f" ]; then echo unknown; return 0; fi
    v="$(awk '/^- \*\*Decision:\*\* /{ sub(/^- \*\*Decision:\*\* /, ""); print; exit }' "$f" 2>/dev/null)"
    # No readable Decision value ⇒ cannot tell ⇒ unknown (fail closed toward asking).
    if [ -z "$v" ]; then echo unknown; return 0; fi
    case "$v" in undecided*) c=$((c+1)) ;; esac
  done
  IFS="$ifs0"
  echo "$c"
  return 0
}

# The zero-sample default (Part T02 Scope 2): loomwright's own measured
# baseline — the six fix-now re-drains of 2026-09-30 → 10-08 — never a bare
# number, and it says whose baseline it is.
DISMISSED_COST_DEFAULT="fix_now_cost: ≈ 1h06m (default: loomwright's own 2026-10 baseline; no fix-now re-drain recorded here yet — median of 6 fix-now re-drains 2026-09-30 → 10-08, range 14m–2h53m)"

# _dismissed_cost_py <dir> — prints the derived line, or nothing when no sample
# survives. Kept in its own function: no heredoc inside a `$( )` (bash 3.2).
_dismissed_cost_py() {
  python3 - "$1" <<'PY'
import calendar, glob, os, re, sys, time
d = sys.argv[1]
TS = re.compile(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$')
def epoch(ts):
    return calendar.timegm(time.strptime(ts, '%Y-%m-%dT%H:%M:%SZ'))
ANCHOR = re.compile(r'^- (?:\S+ )?dismissed: fix-now (\S+)')
LINE = re.compile(r'^- (\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ) (.*)$')
PINNED = re.compile(r'^fix-now re-drain (READY|ESCALATED)\b')
LEGACY = re.compile(r'^(fix-now )?re-drain\b')
STARTED = re.compile(r'^(fix-now )?re-drain started\b')
def terminal(text):
    if PINNED.match(text):
        return True
    if not LEGACY.match(text) or STARTED.match(text):
        return False
    return 'READY' in text or 'ESCALATED' in text or 'SETTLED required=green' in text
spans = []
for led in sorted(glob.glob(os.path.join(d, '*.dismissed-decisions'))):
    run = led[:-len('.dismissed-decisions')] + '.md'
    try:
        with open(led, encoding='utf-8') as f:
            rows = f.read().splitlines()
        with open(run, encoding='utf-8') as f:
            body = f.read().splitlines()
    except Exception:
        continue                      # an unreadable ledger or run file: skip that run
    fix = []
    for r in rows:
        p = r.split('\t')
        if len(p) == 3 and p[1] == 'fix-now' and TS.match(p[2]):
            fix.append((epoch(p[2]), p[0]))
    if not fix:
        continue
    fix.sort()
    batches = []                      # a row within 600 s of the previous = the same decision batch
    for t, name in fix:
        if batches and t - batches[-1]['last'] <= 600:
            batches[-1]['last'] = t
            batches[-1]['names'].add(name)
        else:
            batches.append({'start': t, 'last': t, 'names': {name}})
    prog, inside = [], False
    for l in body:
        if l.startswith('## '):
            inside = l.split()[1:2] == ['Progress']
            continue
        if inside:
            prog.append(l)
    cursor = -1                       # each terminal line ends at most one batch
    for b in batches:
        lo = cursor
        for i, l in enumerate(prog):
            m = ANCHOR.match(l)
            if m and m.group(1) in b['names']:
                lo = max(lo, i)
                break
        end = None
        for i in range(lo + 1, len(prog)):
            m = LINE.match(prog[i])
            if m and terminal(m.group(2)):
                end = (i, epoch(m.group(1)))
                break
        if end is None:
            continue
        cursor = end[0]
        span = end[1] - b['start']
        if span <= 0:
            continue                  # end before start: an out-of-order pairing, never a sample
        if span > 12 * 3600:
            continue                  # owner think-time or an overnight stall
        spans.append(span)
def fmt(s):
    m = int((s + 30) // 60)
    return '%dh%02dm' % (m // 60, m % 60) if m >= 60 else '%dm' % m
if spans:
    spans.sort()
    n = len(spans)
    med = spans[n // 2] if n % 2 else (spans[n // 2 - 1] + spans[n // 2]) / 2.0
    print('fix_now_cost: \u2248 %s (median of %d recorded fix-now re-drain%s in this repo, range %s\u2013%s)'
          % (fmt(med), n, '' if n == 1 else 's', fmt(spans[0]), fmt(spans[-1])))
PY
}

# dismissed_cost <runfile> — READ-ONLY advisory estimator (never feeds a gate).
# Prints exactly ONE `fix_now_cost:` line; every failure path prints the default.
dismissed_cost() {
  local runfile="${1:-}" dir="" line=""
  [ -n "$runfile" ] && dir="$(_abs_dir "$(dirname "$runfile")")"
  if [ -n "$dir" ] && command -v python3 >/dev/null 2>&1; then
    line="$(_dismissed_cost_py "$dir" 2>/dev/null)" || line=""
  fi
  case "$line" in
    *$'\n'*) line="" ;;
    "fix_now_cost: "*) ;;
    *) line="" ;;
  esac
  printf '%s\n' "${line:-$DISMISSED_COST_DEFAULT}"
  return 0
}

main() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    dismissed-drafts)  dismissed_drafts "$@" ;;
    dismissed-decide)  dismissed_decide "$@" ;;
    dismissed-pending) dismissed_pending "$@" ;;
    dismissed-cost)    dismissed_cost "$@" ;;
    *) echo "automate-dismissed: unknown subcommand: ${cmd:-<none>} (dismissed-drafts|dismissed-decide|dismissed-pending|dismissed-cost)" ;;
  esac
  return 0
}

main "$@"
exit 0
