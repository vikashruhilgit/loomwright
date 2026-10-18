warn_if_not_configured() {
  local _slug=""
  case "$REPORT_VERDICT" in
    configured) return 0 ;;
    unknown*)
      echo
      echo "apply: WARNING — readiness is '$REPORT_VERDICT'."
      echo "       The ignore status was never probed here, so nothing above confirms the negation took effect."
      return 0 ;;
    partial*)
      echo
      echo "apply: WARNING — readiness is '$REPORT_VERDICT', not 'configured'; a path that must stay"
      echo "       IGNORED is now COMMITTABLE. This is OVER-inclusion — the opposite of a surviving"
      echo "       exclude — so something is re-including MORE than the managed block asks for."
      echo "       These unintended paths are now COMMITTABLE, each with the rule that actually wins for it:"
      print_path_rules "$REPORT_LEAKED_UNINTENDED"
      if [ -n "$REPORT_BLOCKED_INTENDED" ]; then
        echo "       (Separately, these intended paths are STILL IGNORED — an under-inclusion failure on top:)"
        print_path_rules "$REPORT_BLOCKED_INTENDED"
      fi
      echo "       An over-broad '!' re-include is the cause: a '!.claude/**'-shaped line, or a '!' rule"
      echo "       in a NESTED .gitignore (e.g. .claude/.gitignore), which takes PRECEDENCE over the root"
      echo "       file and so survives this block. NARROW or delete the re-include named above — do NOT"
      echo "       comment out an exclude here; an exclude is not what is failing, and removing one would"
      echo "       leak more. Nothing else about the write is in doubt: the managed block IS in place and"
      echo "       a backup of the previous file sits beside it."
      return 0 ;;
    gated*)
      # MUST sit AHEAD of the fall-through below, which is the UNDER-inclusion copy. A gated repo is
      # not under-including anything: the two memory stores ARE applied and the ledger is withheld
      # ON PURPOSE. Telling the user to "comment out the surviving exclude" would point them at this
      # module's own `.supervisor/*` line and un-ignore the contaminated ledger — the exact outcome
      # the gate exists to prevent. Pinned by test-setup-memory.sh group (m).
      echo
      echo "apply: WITHHELD — the two memory stores are applied, but the findings ledger"
      echo "       ($LEDGER_INTENDED_PATH) is NOT un-ignored. This is the gate"
      echo "       working, not a failure of the ignore rules — do NOT comment out any exclude."
      if [ -n "$REPORT_GATED_SLUGS" ]; then
        echo "       These repo slugs appear in the ledger but are NOT in this repo's allowlist:"
        while IFS= read -r _slug; do
          [ -n "$_slug" ] || continue
          echo "         · $_slug"
        done <<EOF
$REPORT_GATED_SLUGS
EOF
        echo "       Remedy — either drop the foreign records, or widen the allowlist if they really"
        echo "       are this repo's:"
        echo "         bash setup-memory.sh filter-ledger --ledger $LEDGER_INTENDED_PATH > /tmp/ledger.filtered"
        echo "         mv /tmp/ledger.filtered $LEDGER_INTENDED_PATH   # review it first"
        echo "         # …or: jq '.setup_memory.repo_allowlist += [\"owner/repo\"]' .supervisor/config.json"
        echo "       then re-run apply. The two memory stores stay applied throughout."
      else
        # COULD-NOT-EXAMINE. NO slug is named (none was observed), and the filter-ledger remedy is
        # deliberately NOT offered: `filter-ledger > tmp && mv tmp ledger` against a ledger jq cannot
        # read prints nothing and would TRUNCATE it to zero bytes. Fix the readability instead.
        echo "       No foreign repo slug was observed — the gate could not EXAMINE the ledger:"
        while IFS= read -r _slug; do
          [ -n "$_slug" ] || continue
          echo "         · $_slug"
        done <<EOF
$REPORT_UNEXAMINED_REASON
EOF
        echo "       Remedy — make the ledger examinable, then re-run apply. Do NOT pipe it through"
        echo "       filter-ledger while it is unreadable: that prints nothing and would truncate it."
        echo "         · install/repair jq if it is missing or broken ('printf {} | jq -e .' must succeed)"
        echo "         · make the file readable (e.g. chmod u+r $LEDGER_INTENDED_PATH)"
        echo "         · repair the malformed record(s) named above (one interrupted append is enough)"
        echo "       The two memory stores stay applied throughout."
      fi
      echo "       NOTE: withholding does NOT un-track a ledger that is ALREADY COMMITTED —"
      echo "       .gitignore only governs UNTRACKED files. If it is already tracked, filter it and"
      echo "       run 'git rm -r --cached $LEDGER_INTENDED_PATH' yourself, then re-commit."
      if [ -n "$REPORT_LEAKED_UNINTENDED" ]; then
        echo "       Separately — and independently of the gate — these paths that must stay IGNORED"
        echo "       are COMMITTABLE (OVER-inclusion; NARROW the '!' rule named for each):"
        print_path_rules "$REPORT_LEAKED_UNINTENDED"
      fi
      if [ -n "$REPORT_BLOCKED_INTENDED" ]; then
        echo "       Separately — and independently of the gate — these MEMORY-STORE paths are still"
        echo "       IGNORED (UNDER-inclusion; neutralise or re-order the rule named for each):"
        print_path_rules "$REPORT_BLOCKED_INTENDED"
      fi
      return 0 ;;
  esac
  echo
  echo "apply: WARNING — readiness is '$REPORT_VERDICT', not 'configured'; the negation did NOT fully take effect."
  if [ -n "$REPORT_BLOCKED_INTENDED" ]; then
    echo "       These intended paths are STILL IGNORED, each with the rule that actually wins for it:"
    print_path_rules "$REPORT_BLOCKED_INTENDED"
  fi
  echo "       A surviving recursive or deeper exclude is the usual cause — this helper only"
  echo "       neutralises the directory-shaped excludes it recognises (.claude, .supervisor and"
  echo "       their /**, **/ and / forms). Comment out the rule named above, or move it ABOVE the"
  echo "       managed block, then re-run. Nothing else about the write is in doubt: the managed"
  echo "       block IS in place and a backup of the previous file sits beside it."
}

# ---- subcommand: check ------------------------------------------------------
do_check() {
  render_report
  echo
  print_consent_disclosure
  exit 0
}

# ---- subcommand: apply ------------------------------------------------------
do_apply() {
  local gate
  gate="$(gitignore_gate)"

  if [ "$gate" = "absent" ]; then
    echo "apply: ABORTED — no .gitignore at $GI, so nothing is ignoring these stores; there is nothing to negate."
    echo "       Nothing was written. If a parent .gitignore or a global excludesfile is ignoring them, edit that file."
    exit 0
  fi
  case "$gate" in
    unparseable:*)
      echo "apply: ABORTED — $gate"
      echo "       Nothing was written (no partial write, no backup). Fix .gitignore by hand, then re-run."
      exit 0 ;;
  esac

  # Evaluate the ledger gate ONCE, in THIS shell, BEFORE the headline is chosen. proposed_applied_content
  # runs managed_block inside a command substitution, so the gate it evaluates there cannot reach us —
  # and the no-op headline must NOT read "already configured" for a repo whose ledger is withheld
  # (commands/setup.md mandates relaying that headline verbatim, which would state the opposite of the
  # truth the `gated` class exists to tell).
  ledger_gate_blocks_foreign_records || true

  # A plain apply PRESERVES the mode line; when the block's mode cannot be read it cannot be
  # preserved either, so refuse rather than guess (an explicit --branch-mode resolves it).
  if [ "$BRANCH_MODE_SET" = 0 ]; then
    case "$CURRENT_MODE" in
      unknown*)
        echo "apply: ABORTED — the managed block's branch mode reads '$CURRENT_MODE'; re-run with --branch-mode <branch> or --branch-mode off. Nothing was written."
        exit 0 ;;
    esac
  fi

  local current proposed neg_line ledger_withdrawn=no
  current="$(cat "$GI")"
  proposed="$(proposed_applied_content)"
  # WITHDRAWAL: the file on disk carries the ledger negation and the file we are about to write does
  # NOT. That is the gate-passed → contaminated → re-apply transition. It is correct behaviour, but it
  # must be ANNOUNCED — never a bare `apply: applied`.
  #
  # ANCHORED, WHOLE-LINE, IN-BLOCK on BOTH sides — deliberately not a `case *"!$LEDGER_INTENDED_PATH"*`
  # substring test. This repo has already paid for the unanchored-entry-shape class once (the memory
  # writer matched an entry shape with an unanchored `grep -F` and hit the MIDDLE of another entry's
  # free text), and the shape recurs here for a specific reason: the managed block's OWN explanatory
  # comment quotes `!.supervisor/postmortem/results.jsonl` verbatim to explain why the naive one-line
  # form does nothing. A substring test therefore matches the COMMENT as readily as the RULE.
  #
  # No reachable false positive was demonstrated — user-authored lines are carried through into
  # `proposed`, so a decoy appears on both sides and cancels out — so this is defence-in-depth against
  # a documented recurring class, not a fix for an observed defect. It also makes this site agree with
  # `existing_ledger_negation_present()`, which was already anchored; having two different notions of
  # "the negation is present" in one file is the inconsistency worth removing.
  if [ -z "$EFFECTIVE_BRANCH" ] && negation_line_in_block "$current" && ! negation_line_in_block "$proposed"; then
    ledger_withdrawn=yes
  fi

  if [ "$current" = "$proposed" ]; then
    if ledger_negation_in_block && [ "$LEDGER_GATE_STATE" != "pass" ]; then
      # PRESERVED: the negation stays because it was already there, not because we re-verified it.
      # Saying "already configured" would over-claim; saying "GATED" would be false (it is not
      # withheld). Say exactly what happened.
      echo "apply: no-op — already configured; the findings ledger negation is PRESERVED as-is because the gate could not examine the ledger this run ($(printf '%s' "$LEDGER_UNEXAMINED_REASON" | tr '\n' ' ')). Nothing was written and nothing new is published."
    elif [ -z "$EFFECTIVE_BRANCH" ] && [ "$LEDGER_GATE_STATE" = "refuse" ] && [ -n "$LEDGER_FOREIGN_SLUGS" ]; then
      echo "apply: no-op — the two memory stores are already configured, but the findings ledger is GATED and stays IGNORED (records outside the allowlist: $(printf '%s' "$LEDGER_FOREIGN_SLUGS" | tr '\n' ' ')). Nothing was written."
    elif [ -z "$EFFECTIVE_BRANCH" ] && [ "$LEDGER_GATE_STATE" = "refuse" ]; then
      echo "apply: no-op — the two memory stores are already configured, but the findings ledger is GATED and stays IGNORED (the gate could not examine it: $(printf '%s' "$LEDGER_UNEXAMINED_REASON" | tr '\n' ' ')). Nothing was written."
    else
      echo "apply: no-op — already configured (the managed block and the disabled bare excludes are exactly as apply would write them). Nothing was written."
    fi
    seed_allowlist
    echo
    echo "== verify =="
    render_report
    warn_if_not_configured
    apply_readiness_event
    exit 0
  fi

  echo "== what you are about to version-control =="
  print_consent_disclosure
  echo

  local backup
  backup="$(write_gitignore "$proposed")" || { echo "apply: ABORTED — the rewrite could not be staged; .gitignore is unchanged."; exit 0; }
  if [ "$ledger_withdrawn" = "yes" ]; then
    echo "apply: applied (ledger negation WITHDRAWN) — managed block written to $GI"
  elif [ -n "$EFFECTIVE_BRANCH" ]; then
    echo "apply: applied (branch mode: $EFFECTIVE_BRANCH) — managed block written to $GI; run history is no longer re-included here. Already-committed run history is NOT untracked by this helper."
  else
    echo "apply: applied — managed block written to $GI"
  fi
  echo "  backup:  $backup   (delete it once you are happy; it is untracked)"
  if [ "$ledger_withdrawn" = "yes" ]; then
    echo "apply: ledger negation WITHDRAWN — these repo slugs appeared in $LEDGER_INTENDED_PATH"
    echo "       since the last apply and are NOT in this repo's allowlist: $(printf '%s' "$LEDGER_FOREIGN_SLUGS" | tr '\n' ' ')"
    echo "       The ledger is IGNORED again from now on. THIS DOES NOT UN-TRACK AN ALREADY-COMMITTED"
    echo "       LEDGER — .gitignore only governs UNTRACKED files, so if you already committed it the"
    echo "       foreign records are still published. Filter it and stop tracking it yourself:"
    echo "         bash setup-memory.sh filter-ledger --ledger $LEDGER_INTENDED_PATH > /tmp/ledger.filtered"
    echo "         mv /tmp/ledger.filtered $LEDGER_INTENDED_PATH && git rm -r --cached $LEDGER_INTENDED_PATH"
    echo "       then commit. The withdrawal alone unpublishes nothing."
  fi
  seed_allowlist
  echo
  echo "== verify =="
  render_report
  warn_if_not_configured
  apply_readiness_event
  echo
  if [ -n "$EFFECTIVE_BRANCH" ]; then
    echo "Next: the two memory stores are only UN-IGNORED — nothing is committed yet. Review with"
    echo "  git status --short .claude/agent-memory .supervisor/memory"
    echo "and commit deliberately. Run history lives on the metadata branch '$EFFECTIVE_BRANCH' (meta-sync.sh),"
    echo "not on this branch — there is nothing to commit for it here. Untracking run history ALREADY"
    echo "committed on this branch is a separate operator step (migrate-branch-mode.sh plan), never this"
    echo "helper. This helper never runs git add / git rm / git commit."
    exit 0
  fi
  echo "Next: the stores are only UN-IGNORED — nothing is committed yet. Review with"
  echo "  git status --short .claude/agent-memory .supervisor/memory .supervisor/requirements .supervisor/jobs .supervisor/automate $LEDGER_INTENDED_PATH"
  echo "and commit deliberately. This helper never runs git add / git rm / git commit."
  exit 0
}

# ---- subcommand: remove -----------------------------------------------------
do_remove() {
  local gate
  gate="$(gitignore_gate)"

  if [ "$gate" = "absent" ]; then
    echo "remove: no-op — no .gitignore at $GI; there is no managed block to remove. Nothing was written."
    exit 0
  fi
  case "$gate" in
    unparseable:*)
      echo "remove: ABORTED — $gate"
      echo "        Nothing was written (no partial write). Fix .gitignore by hand, then re-run."
      exit 0 ;;
  esac

  local current proposed
  current="$(cat "$GI")"
  proposed="$(proposed_removed_content)"

  if [ "$current" = "$proposed" ]; then
    echo "remove: no-op — no managed block and no disabled excludes to restore. Nothing was written."
  else
    local backup
    backup="$(write_gitignore "$proposed")" || { echo "remove: ABORTED — the rewrite could not be staged; .gitignore is unchanged."; exit 0; }
    echo "remove: removed — managed block deleted and the original bare excludes restored in $GI"
    echo "  backup:  $backup"
  fi

  local tam tsm tlg
  tam="$(tracked_count '.claude/agent-memory')"
  tsm="$(tracked_count '.supervisor/memory')"
  tlg="$(tracked_count "$LEDGER_INTENDED_PATH")"
  cat <<EOF

READ THIS — removal stops FUTURE tracking. It does NOT unpublish anything:
  · Git HISTORY RETAINS everything already committed. Every commit that ever contained these
    files still contains them, on this clone and on every remote, fork and clone that has them.
    If it was pushed, it is published — removing the ignore rule cannot take it back.
  · To actually purge published content you must REWRITE HISTORY (e.g. git filter-repo) and
    force-push every affected ref, then ask collaborators to re-clone — and rotate anything
    secret that was exposed, because it must be assumed compromised.
  · Files that are ALREADY TRACKED stay tracked. .gitignore only affects UNTRACKED files.
    Currently tracked: .claude/agent-memory/ → $tam file(s), .supervisor/memory/ → $tsm file(s),
    $LEDGER_INTENDED_PATH → $tlg file(s).
    All THREE stores are covered — the findings ledger is un-ignored by the same managed block
    (behind the repo-allowlist gate), so removing the block re-ignores it too, and that likewise
    unpublishes nothing that was already committed.
    To stop tracking them going forward (keeping the working copies), run yourself:
      git rm -r --cached .claude/agent-memory .supervisor/memory $LEDGER_INTENDED_PATH
    then commit. This helper NEVER runs git rm / git add / git commit.
EOF
  echo
  echo "== verify =="
  render_report
  exit 0
}

# ---- subcommand: allowlist --------------------------------------------------
do_allowlist() {
  load_allowlist
  [ -n "$ALLOWLIST" ] && printf '%s\n' "$ALLOWLIST"
  echo "# source: $ALLOWLIST_SOURCE" >&2
  exit 0
}

# ---- subcommand: filter-ledger ----------------------------------------------
do_filter_ledger() {
  if [ -z "$LEDGER" ]; then
    echo "setup-memory: filter-ledger requires --ledger <path>" >&2
    exit 0
  fi
  local entries
  entries="$(resolve_allowlist)"
  if [ -z "$entries" ]; then
    filter_ledger_by_allowlist "$LEDGER"
  else
    # bash-3.2-safe expansion of the newline-separated list into positional args.
    local oldIFS="$IFS"
    IFS='
'
    # shellcheck disable=SC2086
    set -- $entries
    IFS="$oldIFS"
    filter_ledger_by_allowlist "$LEDGER" "$@"
  fi
  exit 0
}

resolve_effective_branch

do_mode() {
  # The answer resolve_effective_branch already normalized: an empty / unrecognised reader output
  # prints `unknown …`, never nothing and never `off`.
  printf '%s\n' "$CURRENT_MODE"
  exit 0
}

# ---- subcommand: consent (the user-scope learning-store consent record — header: CONSENT) ----
CONSENT_FILE_REL=".claude/loomwright/meta-sync-consent.json"

# consent_key — this repo's key: origin's owner/repo, else the literal origin URL (any
# `user[:password]@` userinfo stripped, so a credential never becomes a key), else nothing.
consent_key() {
  resolve_origin
  if [ -n "$ORIGIN_SLUG" ]; then printf '%s' "$ORIGIN_SLUG"; return 0; fi
  git -C "$repo" remote get-url origin 2>/dev/null | head -n 1 | sed -E 's#^([A-Za-z][A-Za-z0-9+.-]*://)[^/@]*@#\1#'
  return 0
}

do_consent() {
  local key file val cur dir tmp ts
  if [ "$BRANCH_MODE_SET" = 1 ] || [ -n "$LEDGER" ] || [ -n "$ALLOW_FLAGS" ]; then
    echo "setup-memory: consent takes only grant | decline | status (got --branch-mode / --ledger / --allow). Nothing was written." >&2
    [ "$CONSENT_ACTION" = "status" ] && echo "unknown usage error"
    exit 0
  fi
  case "$CONSENT_ACTION" in
    grant) val="granted" ;;
    decline) val="declined" ;;
    status) val="" ;;
    *) echo "setup-memory: consent requires grant | decline | status (got '${CONSENT_ACTION}'). Nothing was written." >&2; exit 0 ;;
  esac
  case "${HOME:-}" in
    /*) file="$HOME/$CONSENT_FILE_REL" ;;
    *) if [ -z "$val" ]; then echo "unknown HOME is not an absolute path"; else echo "consent: NOT recorded — HOME is not an absolute path. Nothing was written."; fi; exit 0 ;;
  esac
  key="$(consent_key)"
  if [ -z "$val" ]; then
    # STATUS — the one reader; writes nothing.
    [ -n "$key" ] || { echo "setup-memory: consent: this repo has no origin remote, so no record can be keyed" >&2; echo "none"; exit 0; }
    [ -e "$file" ] || { echo "none"; exit 0; }
    command -v jq >/dev/null 2>&1 || { echo "unknown jq is not available"; exit 0; }
    cur="$(jq -r --arg k "$key" 'if type == "object" then ((.repos // {}) | if type == "object" then (.[$k].learning_stores // "none") else "@bad" end) else "@bad" end' "$file" 2>/dev/null)" \
      || { echo "unknown $CONSENT_FILE_REL is not valid JSON"; exit 0; }
    case "$cur" in
      granted|declined|none) echo "$cur" ;;
      *) echo "unknown $CONSENT_FILE_REL holds an unrecognised record for this repo" ;;
    esac
    exit 0
  fi
  # GRANT / DECLINE — the only writers of the record.
  [ -n "$key" ] || { echo "consent: NOT recorded — this repo has no origin remote, so the record cannot be keyed. Nothing was written."; exit 0; }
  command -v jq >/dev/null 2>&1 || { echo "consent: NOT recorded — jq is not available. Nothing was written."; exit 0; }
  dir="$(dirname "$file")"
  if [ -e "$file" ]; then
    { [ -f "$file" ] && jq -e 'type == "object" and ((.repos // {}) | type == "object")' "$file" >/dev/null 2>&1; } \
      || { echo "consent: NOT recorded — ~/$CONSENT_FILE_REL exists but is not a JSON object with an object .repos; repair or remove it by hand. Nothing was written."; exit 0; }
  fi
  mkdir -p "$dir" 2>/dev/null || { echo "consent: NOT recorded — could not create ~/$(dirname "$CONSENT_FILE_REL")/. Nothing was written."; exit 0; }
  tmp="$(mktemp "$file.tmp.XXXXXX" 2>/dev/null)" || { echo "consent: NOT recorded — could not create a temp file beside ~/$CONSENT_FILE_REL. Nothing was written."; exit 0; }
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if { if [ -e "$file" ]; then cat "$file"; else printf '{}'; fi; } \
      | jq --arg k "$key" --arg v "$val" --arg t "$ts" \
          '.schema_version = (.schema_version // 1) | .repos = ((.repos // {}) | .[$k] = ((.[$k] // {}) + {learning_stores: $v, recorded_at: $t}))' > "$tmp" 2>/dev/null \
     && chmod 600 "$tmp" && mv -f "$tmp" "$file"; then
    echo "consent: recorded $val for $key (~/$CONSENT_FILE_REL)"
  else
    rm -f "$tmp"
    echo "consent: NOT recorded — the record could not be written. Nothing was changed."
  fi
  exit 0
}
