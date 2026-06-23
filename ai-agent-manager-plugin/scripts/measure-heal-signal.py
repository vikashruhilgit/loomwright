#!/usr/bin/env python3
"""measure-heal-signal.py — Local Twin path, Step 2 instrument (LOCAL_TWIN_PATH.md §1 Step 2).

READ-ONLY own-run confusion-matrix measurement of the self-heal signal, graduated from the
Step-1 scratch spike (`.supervisor/scratch/local-twin-step1/measure_heal_signal.py`) into a
permanent, re-runnable plugin tool. Same HARVEST → LOAD → JOIN → MATRIX pipeline and the same
confusion-matrix + JSONL output shape as Step 1; the Step-1 logic is PRESERVED, not reinvented.

What Step 2b adds on top of the Step-1 spike:
  * Parameterized repo list (default: the current repo; overridable via the wrapper) so
    "what is the self-heal catch-rate?" becomes a dial re-runnable anytime, across all repos.
  * Floor-RAISING label dedup: review_rounds / self_heal_misses are documented FLOORS (the
    churn counter under-counts — CI-channel churn, repo-shape regex gaps). When a PR carries
    multiple postmortem re-gathers, this takes the MAX observed count rather than latest-ts only,
    so a re-gather that corrected an undercount (e.g. #47: 0 → 6) wins. Makes the counts less of
    a floor without rewriting the test-pinned gather heuristics.
  * Label-quality diagnostics surfaced in the report (model-guessed labels, zero-churn-signal
    labels, floor-raised labels) so the floor is VISIBLE rather than silently trusted.
  * A one-line append to a trend ledger (`<out>/results.jsonl`) so `/insights` can plot the
    catch-rate over time (the MEASURE leg).
  * A bounded `--backfill N` PLANNER: lists up to N unlabeled heal-signal PRs + the estimated
    cost and STOPS — it never dispatches /pr-postmortem (the label needs full model
    classification, not just gather). Surfaces backfill as a decision, not an action.

Pipeline:
  HARVEST  heal signal from done-brief `## Outcome` blocks across the configured repos
           -> rows {local_repo, owner_repo, number, pr_url, heal_decision, heal_iterations, ...}
  LOAD     postmortem outcome labels from each repo's .supervisor/postmortem/results.jsonl
           -> floor-raising dedup per (repo, number): rep entry = max review_rounds (tie-break
              latest ts) for categories/summary/flow_stages context, with review_rounds /
              self_heal_misses RAISED to the max across ALL re-gathers
  JOIN     inner-join on (owner/repo, PR number) -> confusion matrix for the heal signal
  OUTPUT   signal.jsonl, labels.jsonl, joined.jsonl, _summary.json, report.md (under --out),
           plus one appended line to results.jsonl (the trend ledger)

Invariants (LOCAL_TWIN_PATH.md §5): READ-ONLY toward the repos it measures (it only ever READS
their done briefs + postmortem ledgers); no network; writes ONLY under --out. Label source =
churn (`/pr-postmortem`), the cheapest rung of the label ladder -> the numbers are DIRECTIONAL,
not gating-grade. Advisory only; never blocks a run, never changes a heal_decision.
"""
import argparse
import glob
import json
import os
import re
import statistics
import sys
from collections import defaultdict
from datetime import datetime, timezone

# ---- regexes (PR_URL preserved from the Step-1 spike) -----------------------
PR_URL_RE = re.compile(r"github\.com/([^/\s]+)/([^/\s)]+?)(?:\.git)?/pull/(\d+)", re.I)
# Outcome bullets: tolerate BOTH bold-key (`- **heal_decision:** PASS`, the inline-Supervisor
# format) AND plain-key (`- heal_decision: PASS`, the /automate brief format). The Step-1 spike's
# bold-only form silently dropped every plain-bullet brief — e.g. all /automate runs (BetterBlocks:
# 16 of 21 briefs invisible). Key class `[\w .\-]` accepts real Outcome keys (heal_decision /
# Heal decision / PR) while rejecting punctuation-heavy prose; bounded to the first colon.
BULLET_RE = re.compile(r"^\s*-\s*\*{0,2}\s*([\w .\-]+?)\s*:\s*\*{0,2}\s*(.*)$")
INT_RE = re.compile(r"-?\d+")


def repo_label(path):
    return os.path.basename(path.rstrip("/"))


def norm_key(k):
    return re.sub(r"[\s\-]+", "_", k.strip().lower())


def extract_outcome_block(text):
    """Return the lines of the first exact `## Outcome` block (until next `## ` / EOF)."""
    lines = text.splitlines()
    out, flag = [], False
    for ln in lines:
        if re.match(r"^##\s+Outcome\s*$", ln):
            flag = True
            continue
        if flag and re.match(r"^##\s+", ln):
            break
        if flag:
            out.append(ln)
    return out


def parse_outcome(block_lines):
    """Map normalized bullet keys -> raw value strings within an Outcome block."""
    kv = {}
    for ln in block_lines:
        m = BULLET_RE.match(ln)
        if m:
            kv.setdefault(norm_key(m.group(1)), m.group(2).strip())
    return kv


def first_token(s):
    if not s:
        return None
    t = s.split()[0].strip().rstrip(".,:;)")
    return t or None


def first_int(s):
    if s is None:
        return None
    m = INT_RE.search(s)
    return int(m.group(0)) if m else None


# ---- HARVEST ----------------------------------------------------------------
def harvest(repos):
    """Parse done-brief `## Outcome` blocks across `repos`. Pure read."""
    signal = []
    stats = defaultdict(lambda: defaultdict(int))
    for repo in repos:
        rlab = repo_label(repo)
        done_glob = os.path.join(repo, ".supervisor/jobs/done/*.md")
        for f in sorted(glob.glob(done_glob)):
            stats[rlab]["done_briefs"] += 1
            try:
                text = open(f, encoding="utf-8", errors="replace").read()
            except OSError:
                continue
            block = extract_outcome_block(text)
            if not block:
                stats[rlab]["no_outcome_block"] += 1
                continue
            stats[rlab]["with_outcome_block"] += 1
            kv = parse_outcome(block)

            heal_decision = first_token(kv.get("heal_decision"))
            pr_raw = kv.get("pr") or kv.get("pr_url")
            m = PR_URL_RE.search(pr_raw or "")
            if not m:
                # fall back: a PR url may sit in another bullet value
                m = PR_URL_RE.search("\n".join(block))

            if not m:
                stats[rlab]["outcome_no_pr"] += 1
            if heal_decision is None:
                stats[rlab]["outcome_no_heal_decision"] += 1
            if not m or heal_decision is None:
                continue

            owner, name, number = m.group(1), m.group(2), int(m.group(3))
            owner_repo = f"{owner}/{name}"
            signal.append({
                "local_repo": rlab,
                "owner_repo": owner_repo,
                "number": number,
                "pr_url": f"https://github.com/{owner_repo}/pull/{number}",
                "heal_decision": heal_decision.upper(),
                "heal_loop_ran": kv.get("heal_loop_ran"),
                "heal_iterations": first_int(kv.get("heal_iterations")),
                "heal_remaining": first_int(kv.get("heal_remaining_issues")
                                            or kv.get("heal_remaining")),
                "brief": os.path.relpath(f, repo),
            })
            stats[rlab]["signal_rows"] += 1

    # dedup signal per (owner_repo, number): keep last brief (latest date-named file),
    # record how many briefs referenced the PR + any heal_decision conflict.
    sig_by_key = {}
    sig_briefs = defaultdict(list)
    for r in signal:
        key = (r["owner_repo"], r["number"])
        sig_briefs[key].append((r["brief"], r["heal_decision"]))
        prev = sig_by_key.get(key)
        if prev is None or r["brief"] > prev["brief"]:
            sig_by_key[key] = r
    for key, r in sig_by_key.items():
        r["n_briefs"] = len(sig_briefs[key])
        decisions = {d for _, d in sig_briefs[key]}
        r["decision_conflict"] = sorted(decisions) if len(decisions) > 1 else None
    return sig_by_key, stats


# ---- LOAD labels (floor-raising dedup) --------------------------------------
def load_labels(repos):
    """Read each repo's postmortem ledger and dedup per (repo, number) by FLOOR-RAISING.

    review_rounds / self_heal_misses are documented FLOORS (the churn counter under-counts —
    CI-check-channel churn invisible to review_rounds; repo-shape regex gaps). The Step-1 spike
    kept the latest-ts entry only, which is fragile: a later re-gather run in a degraded
    environment (e.g. gh unauthenticated -> the bot-comment fetch fails -> a LOWER count) would
    win over an earlier good gather. Here we instead:
      * pick a REPRESENTATIVE entry = max review_rounds (tie-break latest ts) for the
        categories / summary / flow_stages context (the richest gather), then
      * RAISE review_rounds / self_heal_misses to the MAX observed across ALL re-gathers.
    So the corrected-upward re-gather (e.g. #47: first gather 0 rounds, later gather 6) wins,
    making the counts less of a floor — without touching the test-pinned gather heuristics.
    """
    label_entries = []
    for repo in repos:
        rlab = repo_label(repo)
        path = os.path.join(repo, ".supervisor/postmortem/results.jsonl")
        if not os.path.exists(path):
            continue
        for ln in open(path, encoding="utf-8", errors="replace"):
            ln = ln.strip()
            if not ln:
                continue
            try:
                obj = json.loads(ln)
            except json.JSONDecodeError:
                continue
            obj["_source_repo"] = rlab
            label_entries.append(obj)

    by_key = defaultdict(list)
    for obj in label_entries:
        repo = obj.get("repo")
        number = obj.get("number")
        if repo is None or number is None:
            continue
        by_key[(repo, int(number))].append(obj)

    lab_by_key = {}
    for key, entries in by_key.items():
        def rr(o):
            return int(o.get("review_rounds", 0) or 0)

        def shm(o):
            return int(o.get("self_heal_misses", 0) or 0)

        # representative = richest gather (max review_rounds, tie-break latest ts)
        rep = max(entries, key=lambda o: (rr(o), o.get("ts", "")))
        max_rr = max(rr(o) for o in entries)
        max_shm = max(shm(o) for o in entries)
        out = dict(rep)
        # whether floor-raising actually corrected the representative entry upward
        out["_label_floor_raised"] = (max_rr > rr(rep)) or (max_shm > shm(rep))
        out["review_rounds"] = max_rr
        out["self_heal_misses"] = max_shm
        out["_n_label_entries"] = len(entries)
        lab_by_key[key] = out
    return label_entries, lab_by_key


# ---- JOIN -------------------------------------------------------------------
def join(sig_by_key, lab_by_key, low_rounds):
    joined = []
    for key, s in sig_by_key.items():
        lab = lab_by_key.get(key)
        if lab is None:
            continue
        misses = int(lab.get("self_heal_misses", 0) or 0)
        rounds = int(lab.get("review_rounds", 0) or 0)
        decision = s["heal_decision"]
        had_problem = misses > 0
        # heal "fires" on anything that is not a clean PASS
        if decision == "PASS":
            predicted_problem = False
        elif decision in ("ESCALATED", "NEEDS_HUMAN"):
            predicted_problem = True
        else:
            predicted_problem = None  # unrecognized token -> excluded from matrix

        if predicted_problem is None:
            cell = "OTHER"
        elif predicted_problem and had_problem:
            cell = "TP"
        elif predicted_problem and not had_problem:
            cell = "FP"
        elif not predicted_problem and had_problem:
            cell = "FN"
        else:  # PASS & clean
            cell = "TN"

        tn_kind = None
        if cell == "TN":
            tn_kind = "clean" if rounds <= low_rounds else "churn_elsewhere"

        joined.append({
            "owner_repo": key[0],
            "number": key[1],
            "pr_url": s["pr_url"],
            "heal_decision": decision,
            "heal_iterations": s["heal_iterations"],
            "heal_remaining": s["heal_remaining"],
            "review_rounds": rounds,
            "self_heal_misses": misses,
            "flow_stages": lab.get("flow_stages", {}),
            "agent_generated_guess": lab.get("agent_generated_guess"),
            "review_rounds_source": lab.get("review_rounds_source"),
            "label_floor_raised": lab.get("_label_floor_raised", False),
            "n_label_entries": lab.get("_n_label_entries", 1),
            "had_problem": had_problem,
            "cell": cell,
            "tn_kind": tn_kind,
            "brief": s["brief"],
            "label_summary": (lab.get("summary", "") or "")[:240],
        })
    return joined


# ---- MATRIX -----------------------------------------------------------------
def matrix_for(rows):
    cells = defaultdict(int)
    tn_clean = tn_churn = 0
    for r in rows:
        cells[r["cell"]] += 1
        if r["cell"] == "TN":
            if r["tn_kind"] == "clean":
                tn_clean += 1
            else:
                tn_churn += 1
    tp, fp, fn, tn = cells["TP"], cells["FP"], cells["FN"], cells["TN"]
    recall = tp / (tp + fn) if (tp + fn) else None
    fpr = fp / (fp + tn) if (fp + tn) else None
    precision = tp / (tp + fp) if (tp + fp) else None
    return {
        "n": len(rows), "TP": tp, "FP": fp, "FN": fn, "TN": tn,
        "OTHER": cells["OTHER"],
        "tn_clean": tn_clean, "tn_churn_elsewhere": tn_churn,
        "recall": recall, "false_positive_rate": fpr, "precision": precision,
        "had_problem": sum(1 for r in rows if r["had_problem"]),
        "pass_rows": sum(1 for r in rows if r["heal_decision"] == "PASS"),
    }


def pct(x):
    return "n/a" if x is None else f"{x*100:.0f}%"


# ---- report.md (generic — computed from the data, no hard-coded repo) -------
def write_report(out_dir, summary, joined, labels, signal):
    p = summary["pooled"]
    flow = summary["flow_agg"]
    flow_total = sum(flow.values()) or 1
    sh_share = flow.get("self_heal", 0) / flow_total
    repos_csv = ", ".join(f"`{r}`" for r in summary["repos"]) or "(none)"
    joined_repos = sorted({j["owner_repo"] for j in joined})
    joined_repos_csv = ", ".join(f"`{r}`" for r in joined_repos) or "(none)"

    L = []
    w = L.append
    w("# Local Twin · Heal-Signal Confusion Matrix (own-run, re-runnable instrument)")
    w("")
    w("> **READ-ONLY measurement.** Step-2 instrument of `docs/SPIKES/LOCAL_TWIN_PATH.md` "
      "(graduated from the Step-1 scratch spike). It only READS the measured repos' done briefs "
      "+ postmortem ledgers; it writes only under its `--out` dir. Advisory / directional — never "
      "gating-grade, never blocks a run.")
    w("")
    w(f"_Generated {summary['recorded_at']} over {len(summary['repos'])} repo(s): {repos_csv}._")
    w("")
    w("**Question:** is the self-heal `heal_decision: PASS` signal correlated with reality? "
      "**Label source = churn** (`/pr-postmortem`'s model-classified `self_heal_misses` + "
      "`review_rounds`) — the cheapest rung of the label ladder. Numbers are **DIRECTIONAL.**")
    w("")
    w("---")
    w("")
    w("## TL;DR")
    w("")
    if p["n"] == 0:
        w("- **No joined rows** — no PR carried BOTH a harvested heal signal (done-brief "
          "`## Outcome`) AND a model-classified postmortem label in the configured repos. "
          "Nothing to score yet; see §1 coverage + the backfill note.")
    else:
        w(f"- **Joined matrix N = {p['n']}** PRs across {len(joined_repos)} repo(s) "
          f"({joined_repos_csv}).")
        w(f"- **Recall (catch-rate) = {pct(p['recall'])}** · "
          f"**False-positive = {pct(p['false_positive_rate'])}**.")
        w(f"- **TP={p['TP']} · FP={p['FP']} · FN={p['FN']} "
          f"(the dangerous miss: heal PASS but rework followed) · "
          f"TN={p['TN']}** ({p['tn_clean']} clean / {p['tn_churn_elsewhere']} churn-elsewhere).")
        if summary["pass_dispersion"]["rounds"]:
            pr_ = summary["pass_dispersion"]["rounds"]
            pm_ = summary["pass_dispersion"]["misses"]
            w(f"- **PASS dispersion:** PASS PRs span review_rounds "
              f"{int(pr_[0])}→{int(pr_[2])} and self_heal_misses {int(pm_[0])}→{int(pm_[2])}.")
        w(f"- **Self-heal-lane churn share:** {flow.get('self_heal',0)}/{flow_total} "
          f"({sh_share*100:.0f}%) of joined churn rounds attribute to the **self_heal** stage "
          f"(worker {flow.get('worker',0)}, launch_pad {flow.get('launch_pad',0)}, "
          f"unknowable {flow.get('unknowable',0)}).")
    w("")
    w("---")
    w("")
    # ---- provenance / coverage ----
    w("## 1. Data provenance & coverage")
    w("")
    w("Signal harvested from done-brief `## Outcome` blocks (tolerant of the inline-Supervisor "
      "bold form `- **Heal decision:**`, its lowercase bold variant `- **heal_decision:**`, AND the "
      "plain `/automate` form `- heal_decision:` with no bold). "
      "Labels read from each repo's `.supervisor/postmortem/results.jsonl`.")
    w("")
    w("| repo | done briefs | w/ `## Outcome` | heal signal rows | no PR | no heal field |")
    w("|---|--:|--:|--:|--:|--:|")
    for r in summary["repos"]:
        st = summary["harvest_stats"].get(r, {})
        w(f"| `{r}` | {st.get('done_briefs',0)} | {st.get('with_outcome_block',0)} | "
          f"{st.get('signal_rows',0)} | {st.get('outcome_no_pr',0)} | "
          f"{st.get('outcome_no_heal_decision',0)} |")
    w(f"| **total** | — | — | **{summary['n_signal_prs']} distinct PRs** | | |")
    w("")
    cov = (summary["n_joined"] / summary["n_signal_prs"] * 100) if summary["n_signal_prs"] else 0
    w(f"- **Labels:** {summary['n_label_lines']} raw postmortem lines → "
      f"**{summary['n_label_prs']} distinct (repo, PR)** after floor-raising dedup "
      f"(rep = max `review_rounds` / tie-break latest `ts`; counts raised to the max across "
      f"re-gathers).")
    w(f"- **Join (inner, on `owner/repo` + PR number):** **{summary['n_joined']} rows**.")
    w(f"- **Coverage gap (the dominant caveat):** {summary['n_signal_prs']} PRs carry a heal "
      f"signal but only {summary['n_joined']} have a model-classified label → the matrix sees "
      f"**{cov:.0f}%** of the signal. {len(summary['signal_unlabeled'])} heal-signal PRs are "
      f"**unlabeled**; {len(summary['labels_unjoined'])} labels are **unjoinable** "
      f"(no local done brief). Close it with a bounded `--backfill N` (see §5).")
    w("")
    w("---")
    w("")
    # ---- joined rows ----
    if joined:
        w("## 2. The joined rows")
        w("")
        w("| PR | heal_decision | heal_iters | self_heal_misses | review_rounds | cell |")
        w("|---|---|--:|--:|--:|---|")
        for j in sorted(joined, key=lambda r: (r["owner_repo"], r["number"])):
            cell = j["cell"] + (f" ({j['tn_kind']})" if j["tn_kind"] else "")
            w(f"| [{j['owner_repo']}#{j['number']}]({j['pr_url']}) | {j['heal_decision']} | "
              f"{j['heal_iterations']} | {j['self_heal_misses']} | {j['review_rounds']} | "
              f"**{cell}** |")
        w("")
        w("---")
        w("")
    # ---- confusion matrix ----
    w("## 3. Confusion matrix (heal as a problem-detector)")
    w("")
    w("Ground-truth positive = `self_heal_misses > 0` (the PR had a self-heal-catchable problem). "
      "Prediction positive = heal *fired* (`ESCALATED`/`NEEDS_HUMAN`); `PASS` = predicted clean.")
    w("")
    w("```")
    w("                     reality: HAD self-heal miss   reality: NO self-heal miss")
    w(f"  heal FIRED (!=PASS)       TP = {p['TP']:<3}                    FP = {p['FP']:<3}")
    w(f"  heal PASS                 FN = {p['FN']:<3}  <- dangerous      TN = {p['TN']:<3}  "
      f"({p['tn_clean']} clean / {p['tn_churn_elsewhere']} churn-elsewhere)")
    w("```")
    w("")
    w("| metric | pooled |")
    w("|---|---|")
    w(f"| Recall / catch-rate `TP/(TP+FN)` | **{pct(p['recall'])}** |")
    w(f"| False-positive `FP/(FP+TN)` | **{pct(p['false_positive_rate'])}** |")
    w(f"| Precision `TP/(TP+FP)` | {pct(p['precision'])} |")
    w("")
    if summary["per_repo"]:
        w("**Per-repo:**")
        w("")
        w("| repo | n | recall | FN | self_heal share |")
        w("|---|--:|--:|--:|--:|")
        for orepo, m in sorted(summary["per_repo"].items()):
            fa = summary["per_repo_flow"].get(orepo, {})
            ft = sum(fa.values()) or 1
            w(f"| `{orepo}` | {m['n']} | {pct(m['recall'])} | {m['FN']} | "
              f"{fa.get('self_heal',0)}/{ft} ({fa.get('self_heal',0)/ft*100:.0f}%) |")
        w("")
    w("---")
    w("")
    # ---- FN candidates ----
    fns = [j for j in joined if j["cell"] == "FN"]
    if fns:
        w("## 4. FN candidates — surfaced for human verification")
        w("")
        w("The dangerous misses: heal said **PASS**, reality logged self-heal-class rework. "
          "`self_heal_misses` is `agent_generated_guess` for most labels — **verify each before "
          "trusting it** (the trusted-holdout work).")
        w("")
        w("| PR | misses | rounds | heal_iters | guess? | brief |")
        w("|---|--:|--:|--:|:--:|---|")
        for j in sorted(fns, key=lambda r: -r["self_heal_misses"]):
            g = "guess" if j.get("agent_generated_guess") else "human"
            w(f"| [{j['owner_repo']}#{j['number']}]({j['pr_url']}) | {j['self_heal_misses']} | "
              f"{j['review_rounds']} | {j['heal_iterations']} | {g} | `{j['brief']}` |")
        w("")
        w("---")
        w("")
    # ---- caveats ----
    w("## 5. Honest caveats (why these numbers are DIRECTIONAL only)")
    w("")
    w("1. **Label = churn, often `agent_generated_guess`.** `self_heal_misses` is a model's "
      "post-hoc classification of each review round, not ground truth. Verify the FN set before "
      f"trusting it. (This run: {summary['label_quality']['agent_guess']} of "
      f"{summary['n_joined']} joined labels are model-guessed.)")
    w("2. **Churn counter is a FLOOR.** `review_rounds` misses review feedback that flows through "
      "CI check channels rather than GitHub review objects, and the gather's review-fix regex has "
      "repo-shape gaps. This tool RAISES the floor by taking the max count across re-gathers "
      f"(this run: {summary['label_quality']['floor_raised']} label(s) corrected upward; "
      f"{summary['label_quality']['zero_signal']} joined label(s) found NO churn signal at all "
      "— a likely undercount). Fully closing the regex gaps is the gather script's domain.")
    w("3. **Coverage is partial.** The matrix sees only the PRs that carry BOTH a harvested heal "
      f"signal AND a model-classified label ({cov:.0f}% this run). Do not over-generalize.")
    w("4. **Backfill needs model classification, not just gather.** Raising coverage means running "
      "the full `/pr-postmortem` (model-classified) on the unlabeled PRs — bounded via "
      "`--backfill N` (a PLAN, never auto-run; see §6).")
    w(f"5. **Dedup choices are recorded, not neutral:** floor-raising max per (repo,PR); "
      f"`LOW_ROUNDS <= {summary['low_rounds_threshold']}` splits clean-TN from churn-elsewhere-TN.")
    w("")
    if summary.get("backfill"):
        b = summary["backfill"]
        w("---")
        w("")
        w("## 6. Backfill plan (bounded — a PLAN, not an action)")
        w("")
        w(f"`--backfill {b['requested']}` requested. **Nothing was dispatched.** Raising coverage "
          f"means running the full `/pr-postmortem` (model-classified) on the PRs below, then "
          f"re-running this tool. Estimated wall-clock ≈ **{b['est_human']}** "
          f"(~{b['gather_secs']}s gather each, plus model classification).")
        w("")
        if b["prs"]:
            w("| # | PR | heal | brief |")
            w("|--:|---|---|---|")
            for i, pr in enumerate(b["prs"], 1):
                w(f"| {i} | [{pr['owner_repo']}#{pr['number']}]({pr['pr_url']}) | "
                  f"{pr['heal_decision']} | `{pr['brief']}` |")
            w("")
            w("**Next step (human decision):** decide how many to backfill, then for each PR run "
              "`/pr-postmortem <pr-url>` and re-run `measure-heal-signal.sh`.")
        else:
            w("_No unlabeled heal-signal PRs to backfill — coverage is already complete for the "
              "configured repos._")
        w("")
    report = "\n".join(L) + "\n"
    with open(os.path.join(out_dir, "report.md"), "w", encoding="utf-8") as fh:
        fh.write(report)
    return report


# ---- backfill planner (bounded; PLAN only, never executes) ------------------
def plan_backfill(sig_by_key, lab_by_key, n, gather_secs):
    """List up to N unlabeled heal-signal PRs + a cost estimate. Never dispatches anything."""
    unlabeled = [s for key, s in sig_by_key.items() if key not in lab_by_key]
    # most-recent first (date-named briefs sort lexicographically); cap at N
    unlabeled.sort(key=lambda s: s["brief"], reverse=True)
    chosen = unlabeled[:max(0, n)]
    est_secs = len(chosen) * gather_secs
    if est_secs >= 3600:
        est_human = f"{est_secs/3600:.1f} h"
    elif est_secs >= 60:
        est_human = f"{est_secs/60:.0f} min"
    else:
        est_human = f"{est_secs} s"
    return {
        "requested": n,
        "available_unlabeled": len(unlabeled),
        "gather_secs": gather_secs,
        "est_seconds": est_secs,
        "est_human": est_human,
        "prs": [{
            "owner_repo": s["owner_repo"], "number": s["number"],
            "pr_url": s["pr_url"], "heal_decision": s["heal_decision"],
            "brief": s["brief"],
        } for s in chosen],
    }


# ---- trend ledger -----------------------------------------------------------
def append_ledger(out_dir, summary):
    """Append ONE trend line to <out>/results.jsonl (the MEASURE-leg trend /insights reads)."""
    p = summary["pooled"]
    flow = summary["flow_agg"]
    flow_total = sum(flow.values()) or 0
    sh_share = (flow.get("self_heal", 0) / flow_total) if flow_total else None
    cov = (summary["n_joined"] / summary["n_signal_prs"]) if summary["n_signal_prs"] else None
    line = {
        "schema_version": 1,
        "recorded_at": summary["recorded_at"],
        "repos": summary["repos"],
        "n": p["n"],
        "tp": p["TP"], "fp": p["FP"], "fn": p["FN"], "tn": p["TN"],
        "recall_pct": (round(p["recall"] * 100) if p["recall"] is not None else None),
        "false_positive_pct": (round(p["false_positive_rate"] * 100)
                               if p["false_positive_rate"] is not None else None),
        "self_heal_share_pct": (round(sh_share * 100) if sh_share is not None else None),
        "coverage_pct": (round(cov * 100) if cov is not None else None),
        "coverage_signal_prs": summary["n_signal_prs"],
        "coverage_joined": summary["n_joined"],
        "agent_guess_labels": summary["label_quality"]["agent_guess"],
        "floor_raised_labels": summary["label_quality"]["floor_raised"],
        "zero_signal_labels": summary["label_quality"]["zero_signal"],
        "low_rounds": summary["low_rounds_threshold"],
    }
    with open(os.path.join(out_dir, "results.jsonl"), "a", encoding="utf-8") as fh:
        fh.write(json.dumps(line, ensure_ascii=False) + "\n")
    return line


def dump_jsonl(out_dir, name, rows):
    with open(os.path.join(out_dir, name), "w", encoding="utf-8") as fh:
        for r in rows:
            fh.write(json.dumps(r, ensure_ascii=False) + "\n")


# ---- main -------------------------------------------------------------------
def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Read-only own-run confusion matrix for the self-heal signal "
                    "(Local Twin path, Step 2 instrument).")
    ap.add_argument("--repos", nargs="+", required=True,
                    help="Repo paths to measure (READ-ONLY). The wrapper resolves the default.")
    ap.add_argument("--self-repo", default=None,
                    help="Repo whose .supervisor/ owns the output (default: first --repos entry).")
    ap.add_argument("--out", default=None,
                    help="Output dir (default: <self-repo>/.supervisor/heal-signal).")
    ap.add_argument("--low-rounds", type=int, default=2,
                    help="review_rounds <= this == a clean TN (above it: churn-elsewhere).")
    ap.add_argument("--backfill", type=int, default=None, metavar="N",
                    help="Print a bounded PLAN to backfill N unlabeled heal-signal PRs and STOP "
                         "(never dispatches /pr-postmortem).")
    ap.add_argument("--gather-secs", type=int, default=140,
                    help="Per-PR gather cost estimate for the --backfill plan (default 140).")
    ap.add_argument("--no-ledger", action="store_true",
                    help="Do not append a trend line to results.jsonl (tests / dry runs).")
    ap.add_argument("--recorded-at", default=None,
                    help="Override the timestamp stamp (UTC ISO-8601); default = now.")
    ap.add_argument("--quiet", action="store_true", help="Suppress the console summary.")
    args = ap.parse_args(argv)

    repos = [os.path.abspath(os.path.expanduser(r)) for r in args.repos]
    self_repo = os.path.abspath(os.path.expanduser(args.self_repo)) if args.self_repo else repos[0]
    out_dir = args.out or os.path.join(self_repo, ".supervisor/heal-signal")
    os.makedirs(out_dir, exist_ok=True)
    recorded_at = args.recorded_at or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    # ---- pipeline ----
    sig_by_key, harvest_stats = harvest(repos)
    label_entries, lab_by_key = load_labels(repos)
    joined = join(sig_by_key, lab_by_key, args.low_rounds)

    joined_keys = {(j["owner_repo"], j["number"]) for j in joined}
    labels_unjoined = [k for k in lab_by_key if k not in joined_keys]
    signal_unlabeled = [k for k in sig_by_key if k not in joined_keys]

    pooled = matrix_for(joined)
    per_repo, per_repo_flow = {}, {}
    by_repo = defaultdict(list)
    for j in joined:
        by_repo[j["owner_repo"]].append(j)
    for orepo, rows in sorted(by_repo.items()):
        per_repo[orepo] = matrix_for(rows)
        fa = defaultdict(int)
        for r in rows:
            for k, v in (r["flow_stages"] or {}).items():
                fa[k] += int(v or 0)
        per_repo_flow[orepo] = dict(fa)

    flow_agg = defaultdict(int)
    for j in joined:
        for k, v in (j["flow_stages"] or {}).items():
            flow_agg[k] += int(v or 0)

    pass_rows = [j for j in joined if j["heal_decision"] == "PASS"]
    pass_rounds = [j["review_rounds"] for j in pass_rows]
    pass_misses = [j["self_heal_misses"] for j in pass_rows]

    label_quality = {
        "agent_guess": sum(1 for j in joined if j.get("agent_generated_guess")),
        "floor_raised": sum(1 for j in joined if j.get("label_floor_raised")),
        # explicit "none" only — the gather affirmatively found NO churn signal (likely
        # undercount). An ABSENT review_rounds_source means "unknown" (older label / not
        # stored), NOT "zero", so it is deliberately not counted here.
        "zero_signal": sum(1 for j in joined
                           if (j.get("review_rounds_source") == "none")),
    }

    summary = {
        "recorded_at": recorded_at,
        "repos": [repo_label(r) for r in repos],
        "harvest_stats": {k: dict(v) for k, v in harvest_stats.items()},
        "n_signal_prs": len(sig_by_key),
        "n_label_lines": len(label_entries),
        "n_label_prs": len(lab_by_key),
        "n_joined": len(joined),
        "labels_unjoined": [f"{r}#{n}" for r, n in sorted(labels_unjoined)],
        "signal_unlabeled": [f"{r}#{n}" for r, n in sorted(signal_unlabeled)],
        "pooled": pooled,
        "per_repo": per_repo,
        "per_repo_flow": per_repo_flow,
        "flow_agg": dict(flow_agg),
        "pass_dispersion": {
            "rounds": ([min(pass_rounds), statistics.median(pass_rounds), max(pass_rounds)]
                       if pass_rounds else None),
            "misses": ([min(pass_misses), statistics.median(pass_misses), max(pass_misses)]
                       if pass_misses else None),
            "n_pass": len(pass_rows),
        },
        "label_quality": label_quality,
        "low_rounds_threshold": args.low_rounds,
    }
    if args.backfill is not None:
        summary["backfill"] = plan_backfill(sig_by_key, lab_by_key,
                                             args.backfill, args.gather_secs)

    # ---- write artifacts ----
    dump_jsonl(out_dir, "signal.jsonl", list(sig_by_key.values()))
    dump_jsonl(out_dir, "labels.jsonl", list(lab_by_key.values()))
    dump_jsonl(out_dir, "joined.jsonl", joined)
    with open(os.path.join(out_dir, "_summary.json"), "w", encoding="utf-8") as fh:
        json.dump(summary, fh, indent=2)
    write_report(out_dir, summary, joined, list(lab_by_key.values()),
                 list(sig_by_key.values()))
    ledger_line = None
    if not args.no_ledger:
        ledger_line = append_ledger(out_dir, summary)

    # ---- console summary ----
    if not args.quiet:
        print("=== HARVEST ===")
        for rlab, st in harvest_stats.items():
            print(f"  {rlab}: done={st['done_briefs']} outcome={st['with_outcome_block']} "
                  f"signal_rows={st['signal_rows']} no_pr={st['outcome_no_pr']} "
                  f"no_heal={st['outcome_no_heal_decision']}")
        print(f"  distinct PRs with heal signal: {len(sig_by_key)}")
        print("=== LABELS ===")
        print(f"  raw label lines: {len(label_entries)}  "
              f"distinct (repo,number): {len(lab_by_key)}  "
              f"floor_raised={label_quality['floor_raised']}")
        print("=== JOIN ===")
        print(f"  joined rows: {len(joined)}  labels_unjoined: {len(labels_unjoined)}  "
              f"signal_unlabeled: {len(signal_unlabeled)}")
        print("=== POOLED MATRIX ===")
        print(f"  n={pooled['n']} TP={pooled['TP']} FP={pooled['FP']} "
              f"FN={pooled['FN']} TN={pooled['TN']} (clean={pooled['tn_clean']} "
              f"churn_elsewhere={pooled['tn_churn_elsewhere']}) OTHER={pooled['OTHER']}")
        print(f"  recall(catch-rate)={pct(pooled['recall'])}  "
              f"false-positive={pct(pooled['false_positive_rate'])}")
        flow_total = sum(flow_agg.values()) or 1
        print(f"  self_heal-stage churn share: {flow_agg.get('self_heal',0)}/{flow_total} "
              f"({flow_agg.get('self_heal',0)/flow_total*100:.0f}%)")
        if pass_rounds:
            print(f"=== PASS dispersion: rounds min/med/max="
                  f"{min(pass_rounds)}/{statistics.median(pass_rounds):.0f}/{max(pass_rounds)} "
                  f"misses min/med/max="
                  f"{min(pass_misses)}/{statistics.median(pass_misses):.0f}/{max(pass_misses)}")
        cov = (len(joined) / len(sig_by_key) * 100) if sig_by_key else 0
        print(f"=== COVERAGE: {len(joined)}/{len(sig_by_key)} signal PRs labeled+joined "
              f"({cov:.0f}%) ===")
        if "backfill" in summary:
            b = summary["backfill"]
            print(f"=== BACKFILL PLAN (--backfill {b['requested']}) — a PLAN, NOT an action ===")
            print(f"  {len(b['prs'])} of {b['available_unlabeled']} unlabeled heal-signal PRs; "
                  f"est ~{b['est_human']} ({b['gather_secs']}s gather each + model classification)")
            for i, pr in enumerate(b["prs"], 1):
                print(f"  {i:>3}. {pr['owner_repo']}#{pr['number']}  {pr['pr_url']}  ({pr['brief']})")
            print("  NEXT STEP (human decision): run /pr-postmortem <pr-url> on the chosen PRs, "
                  "then re-run measure-heal-signal.sh. Nothing was dispatched.")
        elif signal_unlabeled:
            print(f"  hint: {len(signal_unlabeled)} unlabeled heal-signal PRs — raise coverage "
                  f"with a bounded --backfill N (prints a plan + cost, never auto-runs).")
        print(f"\nwrote: signal.jsonl labels.jsonl joined.jsonl _summary.json report.md "
              f"{'results.jsonl ' if ledger_line else ''}-> {out_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
