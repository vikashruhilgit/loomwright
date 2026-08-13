#!/usr/bin/env bash
# validate-entry.sh — the SHARED write-time validator for every curated store.
#
# Five deterministic checks, held ONCE instead of copied into each sole writer. THREE BLOCK A WRITE
# AND TWO DO NOT, and which is which is the first thing to know about this file:
#   BLOCKING — structured input, a refusal is a refusal to write:
#   1. contradiction   — an existing entry says the opposite about the same subject
#   2. duplicate       — a near-identical entry is already stored
#   3. provenance      — the entry cites what motivated it (a finding, a PR, a session)
#   ADVISORY — free-prose scanning, REPORTED on stderr and NEVER a refusal:
#   4. dead-reference  — a file path the entry cites does not resolve
#   5. cross-repo      — a repo-shaped token the entry cites is OUTSIDE this repo's allowlist
#
# WHY TWO CHECKS ARE ADVISORY — this contradicts the source requirement's scope 2 ("a validation
# failure is a refusal to write"), it is an OWNER DECISION, and it is written here in full rather
# than softened, because a reader who does not know the measurement will read it as a weakening.
# SIX CONSECUTIVE REVIEW ROUNDS FOUND FALSE REFUSALS, AND EVERY ONE OF THEM WAS IN THESE TWO CHECKS.
# The other three have never produced one. The reason is structural, not a run of bad luck: checks
# 1-3 key on input whose SHAPE the writer controls (a store of stored entries, a --source), while
# 4 and 5 scan FREE ENGLISH PROSE for file paths and repository names, where a citation and an
# ordinary sentence are frequently the same characters. The measured cost of pretending otherwise:
#   · round 1 — 12 of 21 live curated entries refused (57%), every one a false positive;
#   · rounds 2-5 — prose pairs (`YAML/JSON`, `ground-truth/conformance`, `Count/version`), numeric
#     ratios (`117/117`), branch names (`fix/v14.23.1-combined`), in-repo directory paths
#     (`docs/Spikes`) and prose shorthand (`CHANGELOG/CLAUDE.md`) each refused a legitimate write;
#   · round 6 — the fix for "gitignored but real files are unresolvable" (union the on-disk `find`
#     with the git index) made the VERDICT MACHINE-DEPENDENT: green on the author's working tree
#     because `.supervisor/state.md` exists there, red on every clean checkout. MEASURED with a
#     `git archive HEAD` extraction: 231/0 in the working tree, 229/1 clean, 3 of 28 live entries
#     falsely refused. A write-time gate whose answer depends on which files happen to be lying
#     around is not a gate.
# Each round's narrowing was correct and none of them ended the class, because the class is the
# ambiguity of prose itself. So the trade is made explicitly instead of being re-litigated a
# seventh time: THESE TWO CHECKS NOW REPORT AND NEVER REFUSE. What is bought is that a false
# positive can no longer block a legitimate write, and the verdict of a write no longer depends on
# the machine it runs on. WHAT IS SOLD, stated plainly: a genuinely dead reference and a genuinely
# foreign repository citation are now WRITTEN, with a warning, and only a human reading that
# warning will act on it. Nothing here treats an advisory finding as clean — see below.
#
# AN ADVISORY CHECK HAS NOTHING TO FAIL CLOSED FOR. Their could-not-examine paths (an unusable
# --root, absent jq, an unparseable record, an unresolvable allowlist) are advisories too. Decision
# (b) — "could not examine is never reported as clean" — still governs checks 1-3 exactly as
# before, and it is why those three keep the 0/1/2 verdict codes; for 4 and 5 there is no refusal
# left for a fail-closed path to fall back to, so the honest report is a warning that says the
# check could not run, not a refusal issued on behalf of a check that would not have refused anyway.
#
# A WARNING NOBODY SEES IS WORTHLESS, which is the way "advisory" usually decays into "deleted".
# Three things keep that from happening here: every advisory prints a stable, greppable `ADVISORY:`
# marker on stderr carrying the SAME detail the refusal used to carry; the count and the tokens are
# left in $VALIDATE_ENTRY_ADVISORY_COUNT / $VALIDATE_ENTRY_ADVISORY_TOKENS for the caller; and all
# six sole writers call validate_entry_advisory_notice on the write path, so the finding is repeated
# at the call site in the writer's own voice rather than scrolling past inside a helper's output.
#
# SHAPE — this file is a LIBRARY, sourced by the sole writers, and is ALSO directly executable
# (`validate-entry.sh <check> --entry ...`) so its own suite and a human can exercise one check.
# It deliberately does NOT `set -uo pipefail` at file scope: sourcing would then mutate the
# caller's shell options. The executable path sets `-u` for itself only. Every function is written
# to be safe under a caller that already runs `set -uo pipefail` (all five writers do), which is
# also why no function pipes into an EARLY-EXIT consumer (`grep -q`, `head`): under pipefail the
# producer takes SIGPIPE and the pipeline reports 141 EVEN ON A MATCH. `grep -q` is fed by a
# here-string throughout, and files are handed to awk directly rather than `cat`-piped.
#
# VERDICTS — three, never two, FOR THE THREE BLOCKING CHECKS. This is decision (b) of the brief:
#   0  PASS           — examined, and clean
#   1  REFUSE         — examined, and a violation was found
#   2  REFUSE         — COULD NOT EXAMINE (unreadable store, missing argument, or a COMPARISON
#                       SHAPE that could not discriminate — see below). NEVER reported as clean.
# A caller that treats any non-zero as "do not write" is correct by default; a caller that wants to
# distinguish the two refusal classes can, and no caller can accidentally read 2 as 0. Conflating
# "could not examine" with "examined and clean" is the exact fail-open class this file exists to
# close — it has bitten this repo repeatedly, so it is encoded in the return values, not in prose.
# THE TWO ADVISORY CHECKS RETURN 0 ALWAYS, on every path, including their own could-not-examine
# paths. Their findings live on stderr and in the two counters, never in a status.
#
# REFUSAL REASONS are machine-greppable tokens on stderr (`REFUSE_DUPLICATE`,
# `REFUSE_CONTRADICTION_UNCOMPARABLE_SHAPE`, ...), never a bare non-zero status: a refusal that
# does not name its reason is indistinguishable from a crash. ADVISORY findings carry the same
# discipline in a DELIBERATELY DIFFERENT SHAPE — `validate-entry: ADVISORY: ADVISORY_DEAD_REFERENCE
# — ...` — so that no reader, and no grep, can mistake one for the other: the `ADVISORY:` marker is
# the stable thing to match on, and no advisory token begins with `REFUSE_`.
#
# COMPARISON SHAPE — the store must hold ONE ENTRY PER LINE, and checks 1 and 2 now say so instead
# of pretending otherwise. Both score `shared / max(|entry|, |store_line|)`, and `shared` can never
# exceed `min(|entry|, |store_line|)`, so the highest score a pair can reach is
# `100 * min / max` — a CEILING fixed by the two sizes alone, before a single word is compared.
# Hand `--store` a whole DOCUMENT split into lines while `--entry` is that document, and every
# ceiling sits far under the 90 / 60 thresholds: the loop cannot fire, falls out the bottom, and
# returns 0. That is "could not examine" wearing "examined and clean"'s clothes, and it is the exact
# fail-open this file exists to close. MEASURED on the live stores before the guard landed: an
# orientation memo scored 26% against ITSELF, a twin contract 17% against ITSELF. Three writers had
# shipped that shape. So both checks now detect it and return 2 with a named reason
# (REFUSE_DUPLICATE_UNCOMPARABLE_SHAPE / REFUSE_CONTRADICTION_UNCOMPARABLE_SHAPE); the five
# conditions, the measurements that shaped them, and — importantly — what the guard does NOT cover
# are documented at _ve_shape_incommensurable below. It reports an unusable comparison; it does not
# repair one. Note that the two sharers correctly disagree on the SAME store: the guard fires only
# when a REAL verdict is being hidden by the shape, never when the correctly-shaped answer would
# have been clean anyway. That rule, not the arithmetic, is the thing to read first.
#
# ALLOWLIST RESOLUTION IS DELEGATED, NEVER RE-IMPLEMENTED. The cross-repo check obtains the
# allowlist by invoking `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-memory.sh" allowlist`. It MUST
# NOT parse LOOMWRIGHT_MEMORY_REPO_ALLOWLIST (or any other layer) itself: that env var is only
# layer 2 of four in setup-memory.sh's `load_allowlist` precedence
# (`--allow` -> env -> .supervisor/config.json array -> git-remote default). A second parser here
# would agree with the ledger filter on layer 2 and diverge on layers 1, 3 and 4 — reproducing the
# config-vs-remote divergence that has already turned one gate green locally and red in CI.
# One resolver, two consumers (the ledger filter and this check).
#
# ALLOWLIST DIRECTION — read this before touching the cross-repo check. The allowlist is THIS
# repo's own permitted slugs (it defaults to the current git remote), NOT a deny-list of other
# people's repos. Therefore: REFUSE a repo-shaped token that is NOT in the allowlist; PASS one
# that IS. Implementing it the other way round refuses citations of this repo, passes genuinely
# foreign ones, and goes fully green on every acceptance test while behaving backwards.
# COROLLARY, load-bearing: never add a foreign slug to the LIVE allowlist, in a fixture or
# anywhere else — `setup-memory.sh apply` would then judge foreign ledger records clean and emit
# the negation that un-ignores the postmortem ledger from this PUBLIC repo. Fixtures move the list
# with LOOMWRIGHT_MEMORY_REPO_ALLOWLIST in their own environment, or a `--root` fixture repo.
# (The name is written here WITHOUT a leading `$` on purpose: the suite's static half greps for any
# `$`-expansion of it in this file, and a comment carrying one would make that check unaimable.)
#
# COVERAGE BOUND — the cross-repo check is NOT complete coverage, and every message it prints says
# so. The other four checks key on structured input; this one scans free prose, where a foreign
# reference is just a word and a number. It recognises exactly two shapes, and BOTH require a
# citation marker, not merely a suggestive shape:
#   · an `owner/repo` slug that is MARKED as a repository citation, by ANY ONE of four markers:
#       (1) structure — `github.com/owner/repo`, `owner/repo#123`, `owner/repo@sha`, `owner/repo.git`
#       (2) a neighbouring repo cue word — `landed in otherco/othersvc`, `the otherco/othersvc repo`
#       (3) a KNOWN owner — the owner half appears in the resolved allowlist or in the postmortem
#           ledger's `.repo` values, i.e. it is an owner this system has actually seen
#       (4) slug-only structure — a DIGIT anywhere, or an INTERNAL capital (CamelCase) in either
#           half (`octocat/repo2`, `octocat/Hello-World`), NARROWED by the suppressors below
#           because bare structure is also the shape of an in-repo directory path.
#           NOTE, because it is easy to read this bullet as wider than it is: an owner-half HYPHEN
#           is NOT structure (narrowing (vi) retracted it), a version tag is NOT structure
#           (narrowing (v)), and a LEADING capital is NOT CamelCase (narrowing (vii)) — so
#           `acme-corp/widget-svc` and `Microsoft/vscode` earn NOTHING here and are recognised only
#           if cued, structurally marked, or owned by a known owner
#   · a `NAME #123` citation whose NAME is identifier-shaped (ALL-CAPS, or carrying a hyphen,
#     underscore or digit) and is not a generic citation word
#
# IN-REPO DIRECTORY PATHS ARE NOT SLUGS — the second false-positive class, found by review after the
# first one shipped. An extensionless two-segment path (`docs/Spikes`, `agents/code-reviewer`,
# `scripts/gates`, `review-heal/SKILL`, `worktrees/subtask-1`, `phase-2/plan`) is character-for-
# character an `owner/repo` slug, and every one of those six tripped a marker: a hyphen in the owner
# half, a digit anywhere, CamelCase, or a neighbouring `in`/`from`. The live corpus could not catch
# it — every path IT cites carries an extension or a trailing slash — so the shape is now pinned by
# its own committed replay corpus (`fixtures/curated-shape-corpus.md`). Four narrowings, each aimed
# at the SIGNAL that misfired rather than at the token that misfired (a stoplist of paths would be
# unbounded by construction, the same argument as for prose pairs):
#   (i)   THE IN-REPO PATH VETO — a token whose OWNER half names a directory that exists anywhere in
#         this repo's tree is a path, not a foreign owner, and is SKIPPED. It reads the world (the
#         same `_ve_repo_index` the dead-reference check builds), not the shape, which is the only
#         thing that can separate `docs/Spikes` from `octocat/Hello-World`. It vetoes the three SOFT
#         markers (cue word, known owner, slug-only structure) and deliberately NOT the structural
#         ones: `github.com/docs/spikes` and `docs/spikes#12` say "repository" explicitly.
#   (ii)  ORDINAL SUFFIXES ARE NOT STRUCTURE — a trailing `-<digits>` (`subtask-1`, `phase-2`) is how
#         prose NUMBERS things, so it is stripped before marker (4) looks for a digit. `octocat/repo2`
#         (digits fused to letters) and `hashicorp/terraform-aws-v2` (`v2` is not all-digits) keep it.
#   (iii) AN ALL-CAPS REPO HALF IS A FILE STEM, not a repository name (`review-heal/SKILL`,
#         `docs/README`), so it does not earn marker (4) on its own.
#   (iv)  A NUMERIC RATIO IS NOT A SLUG — BOTH halves all digits (`117/117`, `11/11`, `85/100`) is
#         how prose writes a count, a score or a test tally, and it satisfies "a digit anywhere"
#         unconditionally, so no other narrowing can reach it: (ii) strips only a `-<digits>` TAIL
#         and (iii) touches only an all-caps repo half. Found by replaying the AGENT-MEMORY store,
#         which the corpus replay did not read until this round; `117/117` refused a live entry.
# (ii), (iii) and (iv) are index-INDEPENDENT and hold with no repo to read; (i) needs a usable root,
# which every one of the six sole writers passes (`--root "$GITROOT"`). WHAT THIS DOES NOT COVER: an
# in-repo directory path whose owner half is NOT itself a directory in the tree AND whose structure
# survives (ii)+(iii)+(iv) — e.g. `phase-2b/plan` or `feature-x/Notes` in a repo holding neither — is
# still refused.
#
# THE THREE CATCHES TRADED AWAY BY (v), (vi) AND (vii), stated with the measurement rather than left
# for a later reader to discover as a silently weakened check. Each was decided the same way, and the
# rule is worth naming because it is this branch's standing bias applied consistently: THE FALSE
# REFUSALS ARE MEASURED ON THIS REPO'S REAL CURATED PROSE, WHILE THE CATCHES THEY COST ARE AUTHORED
# FIXTURES NOBODY HAS EVER WRITTEN IN A LIVE ENTRY. Live data beats a hypothetical catch — that is
# the same reasoning the corpus replay itself rests on.
#   · (v) VERSION TAG — `hashicorp/terraform-aws-v2` no longer earns marker (4). A release-tagged
#     repo name carrying NO other structure is now invisible unless it is cued, structurally marked
#     or owned by a known owner. Bought: `fix/v14.23.1-combined`, a git branch name, in a live entry.
#   · (vi) OWNER-HALF HYPHEN — `acme-corp/widget-svc` no longer earns marker (4); a hyphenated
#     foreign owner standing bare in prose is now a miss. Bought: `ground-truth/conformance`, an
#     English alternative pair, in a live entry.
#   · (vii) LEADING CAPITAL — `Microsoft/vscode` (a capital only in position 1) no longer earns
#     marker (4). Bought: `Count/version`, a live entry's opening words.
# All three losses collapse into the residual bound already documented below: a bare `word/word` with
# no cue, no known owner and no remaining structure is a deliberate miss. They make that bound WIDER,
# not different in kind, and every refusal message already says a clean verdict is not proof of
# absence.
#
# ONE FALSE REFUSAL IS UNFIXABLE AND IS STATED, NOT HIDDEN — it belongs to the dead-reference check,
# not this one. An entry that RECORDS A DELETION necessarily cites a path that no longer resolves
# ("v14.38.0 removed the stale-terminal-state.md short-circuit"). The check sees a citation; nothing
# in the text distinguishes "this file should exist" from "this file was removed", and no narrowing
# of a path recogniser can recover an author's intent. The live agent-memory replay pins it as a
# known refusal rather than pretending it is clean.
#
# The seven narrowings only ever REMOVE recognition; none of them can make the check
# refuse something it previously passed.
# The marker requirement is the SAME discipline on both shapes, and the reason is identical in both
# cases: the shape alone is ambiguous prose. `fixed in #146` has the `NAME #123` shape and would be
# read as a repository called `in`; `parse YAML/JSON`, `the dev/CI shell`, `no shell/wget` and
# `WORKER_RESULT/CODE_REVIEW_RESULT payloads` all have the `x/y` shape and are not repositories at
# all. An earlier build applied this discipline to the `#123` form only, and refused 12 of the 21
# live curated entries — every one a false positive — because ordinary prose pairs were read as
# slugs. Tightening the RECOGNISER is the fix; extending a stoplist pair-by-pair is not, because the
# next prose pair breaks a legitimate write again.
#
# THE RESIDUAL BOUND, stated because it is real and must not be sold as complete coverage: an
# all-lowercase `word/word` carrying NONE of the four markers — no cue word beside it, an owner this
# system has never seen, no hyphen, digit or CamelCase — is a DELIBERATE MISS. `otherco/othersvc` standing
# alone in a sentence is indistinguishable FROM THE TEXT ALONE from `budget/zone`; they are the same
# shape, and the only thing that could separate them is knowledge of which owners exist, which is
# precisely what marker (3) contributes and precisely what is unavailable for an owner nobody here
# has ever recorded. (Measured, not assumed: the committed ledger holds two `.repo` values, both
# ours.) Choosing to refuse that shape would refuse `budget/zone` too — six live curated entries.
# So `landed in otherco/othersvc`, `the otherco/othersvc repo` and `otherco/othersvc#12` are recognised while a bare
# `otherco/othersvc` is not; prose naming a repo in any other shape ("the othersvc repository") is likewise
# invisible. Under-recognition is the deliberate trade, and it is the reversal of this file's usual
# bias: a missed foreign reference is a documented gap, a false refusal blocks a legitimate write
# and destroys the only thing that makes the check worth running — that a human trusts it.
#
# Usage (library):
#   . "${CLAUDE_PLUGIN_ROOT}/scripts/validate-entry.sh"     # then check VALIDATE_ENTRY_CONTRACT
#   validate_entry_all --entry "<text>" --store <file> --source <id> [--root <dir>]
#   validate_entry_advisory_notice "<writer-name>"          # on the WRITE path, after rc 0
#   validate_duplicate            --entry "<text>" --store <file>          # blocking
#   validate_contradiction        --entry "<text>" --store <file>          # blocking
#   validate_provenance           --entry "<text>" [--source <id>]         # blocking
#   validate_dead_reference       --entry "<text>" [--root <dir>] [--json '<json>' --field <name>]
#                                                                          # ADVISORY: always rc 0
#   validate_cross_repo_reference --entry "<text>" [--root <dir>]          # ADVISORY: always rc 0
#
# Usage (executable):
#   validate-entry.sh contract
#   validate-entry.sh all|duplicate|contradiction|provenance|dead-reference|cross-repo <flags>
#
# LOAD GUARD CONTRACT (for the sole writers that source this file). A file with a syntax error
# still defines every function ABOVE the error before bash aborts the parse, so a truncated helper
# leaves the writer with SOME validators — "examined and clean" over a half-loaded validator is the
# could-not-examine trap applied to the LOADER. The writer's guard is therefore three clauses:
#   (i)   the `source` itself must exit 0  — and `|| true` is FORBIDDEN on that line,
#   (ii)  all five validator functions must be present (`command -v` each), plus
#         validate_entry_all and validate_entry_advisory_notice,
#   (iii) $VALIDATE_ENTRY_CONTRACT must equal the value the writer expects.
# $VALIDATE_ENTRY_CONTRACT is assigned on the LAST line of this file, deliberately: truncation
# anywhere above it cannot produce a matching sentinel.
#
# THE CONTRACT SENTINEL IS `validate-entry/2`, and the bump from /1 is not cosmetic. A writer built
# against /1 was entitled to read "validate_entry_all returned 0" as "all five checks passed"; under
# /2 it means "the three blocking checks passed, and any advisory finding is on stderr and in
# $VALIDATE_ENTRY_ADVISORY_COUNT". That is a different promise, so a /1-era writer paired with this
# file — a stale copy under ~/.claude/, a partial upgrade — must refuse rather than silently write
# under a contract it does not implement. Truncation detection is unchanged; this adds SKEW
# detection, which is the same failure class one layer up.

# ---- verdict codes ----------------------------------------------------------
VALIDATE_ENTRY_RC_PASS=0
VALIDATE_ENTRY_RC_REFUSE=1
VALIDATE_ENTRY_RC_UNEXAMINABLE=2

# Where this file lives — used only to locate a sibling setup-memory.sh when CLAUDE_PLUGIN_ROOT is
# unset (the build-handoff.sh precedent: CLAUDE_PLUGIN_ROOT is the plugin ROOT, helpers live under
# its scripts/ subdir).
_VE_SELF="${BASH_SOURCE[0]:-$0}"
_VE_SELF_DIR="$(cd "$(dirname "$_VE_SELF")" 2>/dev/null && pwd)"
[ -n "$_VE_SELF_DIR" ] || _VE_SELF_DIR="."

# Words dropped before similarity is measured. Kept SEPARATE from the negation list below because
# negations are dropped from the overlap (so polarity never depresses similarity) yet are the sole
# input to polarity itself.
_VE_STOPWORDS=" the a an and or of to in is it for on with that this these those be as at by from was were are its their there here when then than so if but you your we our they them not_a_word "
_VE_NEGATIONS=" not never no none cannot cant dont doesnt didnt isnt arent wasnt werent wont shouldnt without neither nor unsupported disabled forbidden refuses refused fails failed broken wrong "

# `x/y` pairs that are English prose, not repo slugs. A BACKSTOP, not the mechanism: the cue-word
# requirement below is what keeps prose pairs out of the check, because a stoplist extended
# pair-by-pair is unbounded by construction — the next pair nobody listed refuses a legitimate
# write. These stay listed so that even a cued `... in and/or ...` cannot be read as a slug.
# Documented bound: a repository genuinely named after one of these pairs is invisible to the check.
_VE_SLUG_STOPLIST=" and/or input/output read/write pass/fail yes/no true/false on/off either/or before/after open/closed owner/repo he/she she/he km/h w/o n/a "

# Words that may immediately PRECEDE a bare `owner/repo` slug and mark it as a repository citation.
# This is one of four markers (see COVERAGE BOUND); an `x/y` carrying none of them is SKIPPED rather
# than judged. The list is an ALLOWLIST of positions and is deliberately short — every word added
# widens recognition, which is the direction that produces false refusals, so a word belongs here
# only if prose that uses it to mean something other than "the repository named next" is implausible.
_VE_SLUG_CUE_WORDS=" in from into repo repos repository repositories github org fork forks upstream remote clone mirror "
# Words that may immediately FOLLOW a slug and mark it the same way ("the otherco/othersvc repo"). Kept
# separate and even shorter: a trailing word only names the thing when it names a repository.
_VE_SLUG_TRAILING_CUE_WORDS=" repo repos repository repositories fork upstream remote mirror "

# Words that precede a `#123` citation without naming a repository. `PR #146` must not be read as a
# repo named `pr`; `OTHERSVC #146` must be. Documented bound: a repository actually named `pr`, `issue`,
# `run` ... is invisible to the short-name recogniser.
_VE_NOT_REPO_WORDS=" pr prs issue issues ticket tickets bug bugs item items run runs job jobs line lines col cols no number num commit commits release releases build builds step steps case cases test tests round rounds phase v version "

# ---- refusal emitters -------------------------------------------------------
# Both print a machine-greppable token. _ve_unexaminable exists as a SEPARATE emitter so that
# "could not examine" can never be typed as a plain refusal by accident. Both belong to the THREE
# BLOCKING CHECKS; the two advisory checks call _ve_advise below and nothing else.
_ve_refuse() {
  printf 'validate-entry: %s — %s\n' "${1:-REFUSE}" "${2:-}" >&2
  return 1
}
_ve_unexaminable() {
  printf 'validate-entry: %s — %s [could not examine; refusing rather than reporting clean]\n' \
    "${1:-REFUSE_UNEXAMINABLE}" "${2:-}" >&2
  return 2
}

# ---- the ADVISORY emitter ---------------------------------------------------
# The two prose-scanning checks report through THIS and never through the two above. It is a third
# emitter rather than a flag on _ve_refuse for the same reason _ve_unexaminable is separate: a
# refusal and a warning must not be one keystroke apart, and `return 0` must be visible in the
# emitter itself so no advisory path can leak a blocking status by inheriting one.
#
# Three obligations, all met here, because the whole risk of "advisory" is that it quietly becomes
# "deleted":
#   · the line carries the marker `ADVISORY:` — stable, greppable, and shaped so that a grep for
#     `REFUSE_` can never match it and a grep for `ADVISORY:` can never match a refusal;
#   · it carries the SAME detail the refusal used to carry, so a human learns exactly what the
#     check found and nothing is lost but the enforcement;
#   · it leaves the count and the tokens in shell variables, which is what lets the caller repeat
#     the finding in its own voice at the write site (validate_entry_advisory_notice below).
# The two variables are assigned at file scope so a caller running `set -u` can read them even when
# nothing was advised.
VALIDATE_ENTRY_ADVISORY_COUNT=0
VALIDATE_ENTRY_ADVISORY_TOKENS=""
_ve_advisory_reset() { VALIDATE_ENTRY_ADVISORY_COUNT=0; VALIDATE_ENTRY_ADVISORY_TOKENS=""; return 0; }
_ve_advise() {
  VALIDATE_ENTRY_ADVISORY_COUNT=$(( ${VALIDATE_ENTRY_ADVISORY_COUNT:-0} + 1 ))
  VALIDATE_ENTRY_ADVISORY_TOKENS="${VALIDATE_ENTRY_ADVISORY_TOKENS:-}${1:-ADVISORY} "
  printf 'validate-entry: ADVISORY: %s — %s [ADVISORY: this check REPORTS, it does not block; the write was NOT refused for this]\n' \
    "${1:-ADVISORY}" "${2:-}" >&2
  return 0
}

# validate_entry_advisory_notice <caller-name> — the CALL-SITE half of "a warning nobody sees is
# worthless". Every sole writer calls this on the write path after validate_entry_all returns 0, so
# an advisory finding is stated once by the check and once by the writer, in the writer's own name,
# next to the fact that the write went ahead. Prints NOTHING when there is nothing to report, so an
# ordinary clean write is as quiet as it was before. Always returns 0: a notice that could fail a
# write would reintroduce, at the call site, exactly the blocking this change removed.
validate_entry_advisory_notice() {
  [ "${VALIDATE_ENTRY_ADVISORY_COUNT:-0}" -gt 0 ] || return 0
  printf '%s: ADVISORY: %d advisory finding(s) reported above (%s) — dead-reference and cross-repo are ADVISORY checks: they report, they do not block, and THE WRITE PROCEEDED. Read the detail above and fix the entry if the finding is real; nothing else will.\n' \
    "${1:-validate-entry}" "${VALIDATE_ENTRY_ADVISORY_COUNT:-0}" "${VALIDATE_ENTRY_ADVISORY_TOKENS:-}" >&2
  return 0
}

# ---- shared argument parsing -----------------------------------------------
# One parser for all five checks so every call site has the same shape. Unknown flags are ignored
# rather than fatal (a writer passing an extra flag must not crash a fail-safe path), but a MISSING
# required argument is never ignored — each check turns that into an explicit `could not examine`.
_ve_reset_args() {
  _VE_ENTRY=""; _VE_STORE=""; _VE_STORE_SET=0; _VE_SOURCE=""
  _VE_ROOT=""; _VE_ROOT_SET=0; _VE_JSON=""; _VE_JSON_SET=0; _VE_FIELD=""
}
_ve_parse_args() {
  _ve_reset_args
  while [ $# -gt 0 ]; do
    case "$1" in
      --entry)    _VE_ENTRY="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
      --entry=*)  _VE_ENTRY="${1#--entry=}"; shift ;;
      --store)    _VE_STORE="${2:-}"; _VE_STORE_SET=1; shift; [ $# -gt 0 ] && shift ;;
      --store=*)  _VE_STORE="${1#--store=}"; _VE_STORE_SET=1; shift ;;
      --source)   _VE_SOURCE="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
      --source=*) _VE_SOURCE="${1#--source=}"; shift ;;
      --root)     _VE_ROOT="${2:-}"; _VE_ROOT_SET=1; shift; [ $# -gt 0 ] && shift ;;
      --root=*)   _VE_ROOT="${1#--root=}"; _VE_ROOT_SET=1; shift ;;
      --json)     _VE_JSON="${2:-}"; _VE_JSON_SET=1; shift; [ $# -gt 0 ] && shift ;;
      --json=*)   _VE_JSON="${1#--json=}"; _VE_JSON_SET=1; shift ;;
      --field)    _VE_FIELD="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
      --field=*)  _VE_FIELD="${1#--field=}"; shift ;;
      *)          shift ;;
    esac
  done
  return 0   # explicit: the trailing `[ $# -gt 0 ] && shift` above is falsy on the last flag
}

# ---- text primitives --------------------------------------------------------
# _ve_norm — lowercase, collapse every non-alphanumeric byte to a single space, trim. The result is
# guaranteed to contain ONLY [a-z0-9 ], which is why the awk helpers below may pass it through
# `-v` (awk interprets backslash escapes in a -v value; normalised text has no backslashes left).
_ve_norm() {
  printf '%s' "${1:-}" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -c 'a-z0-9' ' ' \
    | tr -s ' ' \
    | sed -e 's/^ //' -e 's/ $//'
}

# _ve_polarity <normalised-text> -> 1 if it contains a negation token, else 0.
_ve_polarity() {
  awk -v t="${1:-}" -v neg="$_VE_NEGATIONS" 'BEGIN{
    n = split(neg, g, " "); for (i = 1; i <= n; i++) if (g[i] != "") N[g[i]] = 1
    m = split(t, w, " ")
    for (i = 1; i <= m; i++) if (w[i] in N) { print 1; exit }
    print 0
  }'
}

# _ve_overlap <normA> <normB> -> THREE space-separated numbers: the overlap SCORE (0..100), then
# the significant-token COUNT of A and of B. The score is the share of significant tokens common to
# both, over the LARGER of the two token sets (so a short entry cannot score 100 against a long one
# merely by being a subset of it). Stopwords, negations and tokens shorter than 3 chars are excluded.
#
# The two counts are returned, not merely used, because the SHAPE GUARD below is built out of them:
# `sh <= min(ca, cb)` is an identity, so `score <= 100 * min(ca,cb) / max(ca,cb)` is a CEILING on
# what this pair could ever score, computable without looking at the content at all. A caller that
# only sees the score cannot tell "these differ" from "these could not have matched". See the
# COMPARISON SHAPE note in the header.
_ve_overlap() {
  awk -v a="${1:-}" -v b="${2:-}" -v skip="$_VE_STOPWORDS$_VE_NEGATIONS" 'BEGIN{
    n = split(skip, s, " "); for (i = 1; i <= n; i++) if (s[i] != "") K[s[i]] = 1
    na = split(a, ta, " "); nb = split(b, tb, " ")
    ca = 0
    for (i = 1; i <= na; i++) { t = ta[i]
      if (t == "" || length(t) < 3 || (t in K) || (t in A)) continue
      A[t] = 1; ca++ }
    cb = 0
    for (i = 1; i <= nb; i++) { t = tb[i]
      if (t == "" || length(t) < 3 || (t in K) || (t in B)) continue
      B[t] = 1; cb++ }
    if (ca == 0 || cb == 0) { printf "0 %d %d\n", ca, cb; exit }
    sh = 0; for (t in A) if (t in B) sh++
    max = (ca > cb) ? ca : cb
    printf "%d %d %d\n", int(sh * 100 / max), ca, cb
  }'
}

# _ve_score <normA> <normB> — one call to _ve_overlap, unpacked into $_VE_SCORE / $_VE_CA / $_VE_CB.
# A function rather than three command substitutions so the awk runs ONCE per compared line.
_ve_score() {
  local out
  out="$(_ve_overlap "${1:-}" "${2:-}")"
  _VE_SCORE="${out%% *}"; out="${out#* }"
  _VE_CA="${out%% *}"; _VE_CB="${out##* }"
  case "$_VE_SCORE$_VE_CA$_VE_CB" in *[!0-9]*|"") _VE_SCORE=0; _VE_CA=0; _VE_CB=0 ;; esac
  return 0
}

# _ve_comparable_entry <text> — the entry as the two COMPARISON checks see it: whole-line HTML
# comments dropped. This is a SYMMETRY rule, not a new filter: _ve_store_lines already skips those
# lines when reading the STORE side, so leaving them on the entry side compares a memo's machine
# stamp (`<!-- written_at: ... | head_sha: ... -->`) against stored text that never contains one.
# MEASURED on add-orientation.sh's composed memo: the ~9 header tokens (timestamp, sha, areas) pulled
# a byte-identical repost from 100% down to 70%, i.e. under the 90% threshold — the header alone was
# laundering duplicates. The three OTHER checks still see the entry verbatim (provenance,
# dead-reference and cross-repo all have legitimate business with header metadata), so this changes
# nothing outside the two comparisons.
#
# It can only ever REMOVE text, so it could turn a comparable entry into an empty one and manufacture
# a could-not-examine refusal out of nothing. It therefore falls back to the raw entry whenever the
# strip leaves no comparable text: a symmetry aid must never become a new refusal path.
_ve_comparable_entry() {
  local raw="${1:-}" stripped
  stripped="$(printf '%s\n' "$raw" | awk '/^[[:space:]]*<!--/ { next } { print }')"
  if [ -n "$(_ve_norm "$stripped")" ]; then printf '%s' "$stripped"; else printf '%s' "$raw"; fi
}

# ---- THE SHAPE GUARD (shared by checks 1 and 2) -----------------------------
# Decision (b) says an input that cannot be EXAMINED is a refusal, never a clean verdict. Both
# comparison checks were violating it silently: they scored entry-vs-STORE-LINE, and when the entry
# is a whole multi-line DOCUMENT while the store's lines are that document's own fragments, the
# denominator max(ca,cb) is always the entry's own size and the numerator can never approach it —
# the loop then falls out the bottom and returns 0, "examined and clean", having been arithmetically
# incapable of returning anything else. MEASURED before the fix: an orientation memo compared
# against ITSELF scored 26%, a twin contract against ITSELF 17%. Not a threshold that was too tight;
# a comparison that could not discriminate.
#
# WHAT A REFUSAL FROM THIS GUARD MEANS — read this before touching any condition below.
# The guard does NOT ask "was this per-line comparison inert?". It asks the sharper question:
#
#     WOULD A REAL VERDICT HAVE EXISTED UNDER THE CORRECT SHAPE, AND IS THIS SHAPE HIDING IT?
#
# "The correct shape" is the one the corpus builders produce: ONE LINE PER STORED ENTRY. Feed the
# same content that way and the check returns a real verdict. So the guard refuses exactly when that
# verdict would have been a REFUSAL and this shape turned it into a silent "clean", and it stays
# SILENT when that verdict would have been clean anyway — because then nothing is being hidden and
# "could not examine" would simply be untrue.
#
# That is why the two sharers correctly disagree on the SAME store, and the disagreement is the
# design, not a bug to be smoothed away. MEASURED on a document stored as its own fragments (a
# 6-line store, --entry = the whole document), each against the same content shaped as one line:
#   · duplicate      correctly-shaped verdict = REFUSE(1). A real verdict is being hidden, so the
#                    guard REFUSES(2): the store does hold this entry, only the shape conceals it.
#   · contradiction  correctly-shaped verdict = CLEAN(0). The store as a whole carries the SAME
#                    polarity as the entry, so the contradiction check would have SKIPPED it under
#                    ANY shape. No shape could produce a refusal here, the answer is already
#                    determined, and the guard STANDS DOWN.
# Both halves are pinned by test, each next to the correctly-shaped control that justifies it.
#
# Five conditions, ALL required, each earning its place against the real corpora (the numbers below
# were measured on this repo's live stores and fixtures, not reasoned):
#   (1) at least one comparable store line was seen — an ABSENT or entry-less store is already a
#       real verdict handled above, not this;
#   (2) EVERY store line is strictly smaller than the entry, so the denominator is ALWAYS ca. The
#       reverse case (a short entry against long stored ones) is the subset penalty _ve_overlap was
#       designed to impose, not a blind spot: measured, a legitimate 20-token agent-memory entry
#       against its 317-token corpus scores 34%, and refusing that would block a real write;
#   (3) the ceiling 100*maxline/ca is below the check's threshold — not even a byte-identical copy
#       of the largest stored line could reach it;
#   (4) the entry DOES reach the threshold against the store's lines taken TOGETHER. That is the
#       whole difference between "this store cannot express my entry" and "this store does not
#       contain it": the entry's counterpart IS in there, spread across lines the check can only
#       look at one at a time;
#   (5) the store taken TOGETHER would still be JUDGED by THIS check — the polarity of the flattened
#       whole, which is the single line the check would see under the correct shape, satisfies this
#       check's own judging rule (duplicate judges SAME polarity, contradiction OPPOSITE). When it
#       would not, the correctly-shaped verdict is a definite clean and there is nothing to hide.
#
# (5) IS THE FIX FOR THIS GUARD'S SECOND FALSE REFUSAL, and two earlier attempts are recorded here
# because each looked right and was measured wrong — the failure mode of this guard is confident
# reasoning, so nothing below is kept on argument alone:
#   · SHAPE-ONLY (entry is multi-line AND no store line exceeds the entry's longest) — refused a
#     legitimate 10-token agent-memory write into a 4-entry store of ~6-token entries (ceiling 60%).
#     Tiny WHOLE entries are shape-indistinguishable from fragments, and the writer it broke is the
#     working precedent this whole file is modelled on. Replaced by (4)'s positive evidence.
#   · PER-FRAGMENT POLARITY (restrict (4) to just the lines this check's judging loop would look at)
#     — the obvious reading of "mirror the judging loop", and it is wrong because POLARITY IS A
#     PROPERTY OF A WHOLE STORED ENTRY, NOT OF A FRAGMENT. In a document split into lines the
#     per-fragment polarities are noise: MEASURED, the 6-line fixture above splits 4 positive /
#     2 negative while the document as a whole is negative. Restricting (4) to same-polarity
#     fragments dropped duplicate's evidence from 100% to 29% — under its 90 threshold — and turned
#     duplicate's refusal into the exact fail-open this guard exists to close. Contradiction survived
#     that version at 72% ONLY because its threshold is 60: the same noise clearing a lower bar.
#     A guard shared by two checks with DIFFERENT thresholds must be measured on BOTH; measuring the
#     low-threshold sharer alone is precisely how that version was reported as having no trade-off.
# (5) therefore asks the polarity of the store AS A WHOLE, and never a fragment's.
#
# (4) is the false-refusal firewall, and it replaced an earlier shape-only condition (entry is
# multi-line AND no store line exceeds the entry's own longest line) that was MEASURED WRONG — not
# reasoned wrong. Run against the existing suites, that version refused a legitimate 10-token
# agent-memory write into a 4-entry store of ~6-token entries (ceiling 60%): tiny whole entries are
# shape-indistinguishable from fragments, and the writer it broke is the WORKING precedent this
# whole fix is modelled on. A false refusal blocks a real write, so the guard now demands positive
# evidence that the store holds what the entry says, rather than inferring it from line lengths.
# Conditions (1)-(3) are still what makes the verdict honest — with the ceiling reachable there is
# no arithmetic impossibility to report.
#
# WHAT THIS DOES NOT COVER, stated rather than discovered later. Every gap below makes the guard
# SILENT, never more eager: each one can only cost a catch, and none can manufacture a refusal.
# That direction is chosen, and it is this guard's local restatement of the file-wide bias that a
# false refusal (which blocks a legitimate write) is worse than a miss:
#   · a document-shaped comparison whose entry is genuinely NEW — nothing like it in the store — is
#     still reported clean. The shape was just as unable to discriminate; the guard is silent
#     because it has no evidence, and inferring the shape from lengths alone is what produced the
#     first false refusal above. This is the guard's biggest gap and it is deliberate;
#   · a fragment store large enough that the entry cannot reach the threshold against the WHOLE of
#     it either (one file holding many documents) — condition (4) fails and it passes through;
#   · content-level dilution, where the ceiling IS reachable but padding on one side keeps the score
#     under the threshold. That is not a shape defect and this guard is silent about it;
#   · (5) reads ONE polarity for the flattened store, so a store legitimately holding MANY entries of
#     MIXED polarity is summarised by whichever polarity its combined text carries. A hidden verdict
#     against one individual stored entry inside such a store can therefore be missed. Reading each
#     fragment's polarity instead is exactly the attempt measured wrong above, so this is a miss the
#     guard accepts rather than a bound it can tighten cheaply;
#   · conditions (1)-(3) still measure over ALL comparable lines, including ones this check would
#     never judge. That can only make (2) and (3) HARDER to satisfy — a line the check ignores can
#     raise the ceiling and stand the guard down — so it costs catches and cannot cause a refusal.
# The guard REPORTS an unusable comparison; it does not repair one, and the repair is not always the
# store's shape: see the refusal messages, which name the caller's move in BOTH situations (reshape
# the store when it is one document split into lines; split the ENTRY when the store already is one
# line per stored entry and the entry spans several of them).
_ve_shape_reset() {
  _VE_SHAPE_LINES=0; _VE_SHAPE_MAXLINE=0; _VE_SHAPE_ALL_SMALLER=1; _VE_SHAPE_CA=0
}
# _ve_shape_observe — called once per compared store line, with $_VE_CA/$_VE_CB already set.
_ve_shape_observe() {
  _VE_SHAPE_LINES=$((_VE_SHAPE_LINES + 1))
  _VE_SHAPE_CA="$_VE_CA"
  [ "$_VE_CB" -gt "$_VE_SHAPE_MAXLINE" ] && _VE_SHAPE_MAXLINE="$_VE_CB"
  [ "$_VE_CB" -ge "$_VE_CA" ] && _VE_SHAPE_ALL_SMALLER=0
  return 0
}
# _ve_shape_incommensurable <normalised-entry> <threshold> <store> <judges> <entry-polarity>
#   -> 0 when this shape is HIDING a verdict the correct shape would have produced (see the header
#   above for what that means and why the two sharers disagree on the same store).
# <judges> is the calling check's own judging rule, `same` or `opposite`, and it is REQUIRED: an
# absent or unrecognised rule means this function cannot know what the caller would have judged, so
# it stands the guard DOWN rather than guessing — a wrongly-wired future sharer loses a catch, it
# never gains a false refusal. The suite's static assertion is what stops such a sharer shipping.
# Conditions (1)-(3) are pure arithmetic over what the loop already measured; (4) and (5) cost one
# more pass over the store, so they are evaluated last and only when the cheap ones already hold —
# on every ordinary write the function returns at (2) or (3) having read nothing.
# $_VE_SHAPE_CEILING and $_VE_SHAPE_WHOLE are left set for the refusal message.
_VE_SHAPE_CEILING=0
_VE_SHAPE_WHOLE=0
_ve_shape_incommensurable() {
  local ne="${1:-}" thr="${2:-100}" store="${3:-}" judges="${4:-}" np="${5:-}" flat
  [ "${_VE_SHAPE_LINES:-0}" -gt 0 ] || return 1                   # (1)
  [ "${_VE_SHAPE_ALL_SMALLER:-0}" -eq 1 ] || return 1             # (2)
  [ "${_VE_SHAPE_CA:-0}" -gt 0 ] || return 1
  _VE_SHAPE_CEILING=$(( _VE_SHAPE_MAXLINE * 100 / _VE_SHAPE_CA ))
  [ "$_VE_SHAPE_CEILING" -lt "$thr" ] || return 1                 # (3)
  # (4) the store's lines TAKEN TOGETHER do reach the threshold. `tr` (not an early-exit consumer)
  # keeps this pipeline safe under a caller's `set -o pipefail`.
  flat="$(_ve_norm "$(_ve_store_lines "$store" | tr '\n' ' ')")"
  [ -n "$flat" ] || return 1
  _ve_score "$ne" "$flat"
  _VE_SHAPE_WHOLE="$_VE_SCORE"
  [ "$_VE_SHAPE_WHOLE" -ge "$thr" ] || return 1
  # (5) ...and that flattened whole — the ONE line this check would see under the correct shape — is
  # a line this check would actually JUDGE. If the calling check would skip it on polarity, then the
  # correctly-shaped verdict is a definite CLEAN, no shape could have produced a refusal, and there
  # is nothing for this guard to report. The polarity is taken from the WHOLE, never from a fragment:
  # see the PER-FRAGMENT POLARITY note above for the measurement that settled that.
  case "$judges" in                                                          # POLARITY_OF_THE_WHOLE
    same)     [ "$(_ve_polarity "$flat")" =  "$np" ] || return 1 ;;          # POLARITY_OF_THE_WHOLE
    opposite) [ "$(_ve_polarity "$flat")" != "$np" ] || return 1 ;;          # POLARITY_OF_THE_WHOLE
    *)        return 1 ;;                                                    # POLARITY_OF_THE_WHOLE
  esac                                                                       # POLARITY_OF_THE_WHOLE
  return 0
}

# _ve_store_lines <file> — the store's comparable entry lines, one per line, still raw.
# Generic across every curated store shape: skips blank lines, markdown headings / `#` comments and
# whole-line HTML comments; strips a trailing `<!-- ... -->` metadata trailer, a leading list
# bullet, and a leading `[8-hex-id]` label. awk reads the file directly (never `cat |`) so no
# early-exit consumer can take SIGPIPE under a caller's `set -o pipefail`.
_ve_store_lines() {
  awk '
    /^[[:space:]]*$/      { next }
    /^[[:space:]]*#/      { next }
    /^[[:space:]]*<!--/   { next }
    {
      line = $0
      sub(/<!--.*-->[[:space:]]*$/, "", line)
      sub(/^[[:space:]]*[-*][[:space:]]+/, "", line)
      sub(/^\[[0-9a-fA-F]+\][[:space:]]*/, "", line)
      if (line ~ /[^[:space:]]/) print line
    }
  ' "${1:-/dev/null}" 2>/dev/null
}

# _ve_store_readable <path> -> 0 usable, 1 absent (no prior entries — a real, clean verdict),
# 2 present but not examinable. Mirrors the `[ -e ] || never; [ -r ] || unknown` shape: an ABSENT
# store and an UNREADABLE store are different facts and must never collapse into one `[ -r ]` test.
_ve_store_readable() {
  local p="${1:-}"
  [ -n "$p" ] || return 2
  [ -e "$p" ] || return 1
  [ -d "$p" ] && return 2
  [ -r "$p" ] || return 2
  return 0
}

# _ve_resolve_root — the repo root paths are resolved against. An explicit --root wins; otherwise
# the git toplevel; otherwise $PWD.
_ve_resolve_root() {
  if [ "${_VE_ROOT_SET:-0}" -eq 1 ]; then printf '%s' "$_VE_ROOT"; return 0; fi
  local g
  g="$(git rev-parse --show-toplevel 2>/dev/null)"
  if [ -n "$g" ]; then printf '%s' "$g"; else printf '%s' "$PWD"; fi
}

# ---- check 1: duplicate -----------------------------------------------------
# Refuses an entry that is near-identical to one already stored. Similarity is measured on
# significant tokens, so wording/order changes do not launder a duplicate past it; polarity must
# also MATCH, otherwise "X is safe" vs "X is not safe" would be reported as a duplicate when it is
# in fact the contradiction check's business.
VALIDATE_ENTRY_DUPLICATE_THRESHOLD=90
validate_duplicate() {
  _ve_parse_args "$@"
  [ -n "$_VE_ENTRY" ] || { _ve_unexaminable "REFUSE_DUPLICATE_NO_ENTRY" "no --entry text was supplied, so nothing could be compared"; return 2; }
  [ "$_VE_STORE_SET" -eq 1 ] || { _ve_unexaminable "REFUSE_DUPLICATE_NO_STORE" "no --store was supplied, so the existing entries were never read"; return 2; }
  _ve_store_readable "$_VE_STORE"
  case $? in
    1) return 0 ;;   # store absent: there are no prior entries — examined, clean
    2) _ve_unexaminable "REFUSE_DUPLICATE_STORE_UNREADABLE" "store '$_VE_STORE' exists but could not be read"; return 2 ;;
  esac

  local ecmp ne np line lo lp
  ecmp="$(_ve_comparable_entry "$_VE_ENTRY")"
  ne="$(_ve_norm "$ecmp")"
  np="$(_ve_polarity "$ne")"
  [ -n "$ne" ] || { _ve_unexaminable "REFUSE_DUPLICATE_EMPTY_ENTRY" "the entry normalises to no comparable text"; return 2; }
  _ve_shape_reset
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    lo="$(_ve_norm "$line")"
    [ -n "$lo" ] || continue
    _ve_score "$ne" "$lo"
    # Observed BEFORE the polarity filter: polarity decides which lines this check JUDGES, the shape
    # question is whether any line in the store is commensurable with the entry at all.
    _ve_shape_observe
    lp="$(_ve_polarity "$lo")"
    [ "$lp" = "$np" ] || continue
    if [ "$_VE_SCORE" -ge "$VALIDATE_ENTRY_DUPLICATE_THRESHOLD" ]; then
      _ve_refuse "REFUSE_DUPLICATE" "a near-identical entry is already stored in '$_VE_STORE': \"$line\" — nothing was written"
      return 1
    fi
  done <<EOF
$(_ve_store_lines "$_VE_STORE")
EOF
  if _ve_shape_incommensurable "$ne" "$VALIDATE_ENTRY_DUPLICATE_THRESHOLD" "$_VE_STORE" same "$np"; then
    _ve_unexaminable "REFUSE_DUPLICATE_UNCOMPARABLE_SHAPE" "the entry is a ${_VE_SHAPE_CA}-significant-token document that matches store '$_VE_STORE' AS A WHOLE at ${_VE_SHAPE_WHOLE}%, but every one of its ${_VE_SHAPE_LINES} comparable lines is smaller than the entry (largest: ${_VE_SHAPE_MAXLINE}), so the best score any SINGLE line could reach is ${_VE_SHAPE_CEILING}% — below the ${VALIDATE_ENTRY_DUPLICATE_THRESHOLD}% threshold no matter what either side says. The same content shaped as one line per stored entry WOULD have produced a real verdict, and this shape turned it into a silent 'clean', so THIS CHECK COULD NOT DECIDE: the verdict is unknown, not clean. Two ways out, and which one applies depends on the store you passed: (a) if --store is one document split into lines, hand it ONE LINE PER STORED ENTRY instead (build_compare_corpus in write-agent-memory.sh is the worked example); (b) if --store ALREADY is one line per stored entry, then reshaping it cannot help and it is the ENTRY that spans several of them — validate it in stored-entry-sized pieces, which is the only granularity this check can judge"
    return 2
  fi
  return 0
}

# ---- check 2: contradiction -------------------------------------------------
# Refuses an entry that is ABOUT the same subject as a stored one but of the OPPOSITE polarity, and
# proposes the supersede path rather than silently appending a contradicting entry. Flag, never
# delete: this check refuses the write, it never edits or removes the stored entry.
VALIDATE_ENTRY_CONTRADICTION_THRESHOLD=60
validate_contradiction() {
  _ve_parse_args "$@"
  [ -n "$_VE_ENTRY" ] || { _ve_unexaminable "REFUSE_CONTRADICTION_NO_ENTRY" "no --entry text was supplied, so nothing could be compared"; return 2; }
  [ "$_VE_STORE_SET" -eq 1 ] || { _ve_unexaminable "REFUSE_CONTRADICTION_NO_STORE" "no --store was supplied, so the existing entries were never read"; return 2; }
  _ve_store_readable "$_VE_STORE"
  case $? in
    1) return 0 ;;
    2) _ve_unexaminable "REFUSE_CONTRADICTION_STORE_UNREADABLE" "store '$_VE_STORE' exists but could not be read"; return 2 ;;
  esac

  local ecmp ne np line lo lp
  ecmp="$(_ve_comparable_entry "$_VE_ENTRY")"
  ne="$(_ve_norm "$ecmp")"
  [ -n "$ne" ] || { _ve_unexaminable "REFUSE_CONTRADICTION_EMPTY_ENTRY" "the entry normalises to no comparable text"; return 2; }
  np="$(_ve_polarity "$ne")"
  _ve_shape_reset
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    lo="$(_ve_norm "$line")"
    [ -n "$lo" ] || continue
    _ve_score "$ne" "$lo"
    _ve_shape_observe
    lp="$(_ve_polarity "$lo")"
    [ "$lp" != "$np" ] || continue
    if [ "$_VE_SCORE" -ge "$VALIDATE_ENTRY_CONTRADICTION_THRESHOLD" ]; then
      _ve_refuse "REFUSE_CONTRADICTION" "the entry contradicts a stored one in '$_VE_STORE': \"$line\" — supersede it explicitly instead of appending a second, opposite entry (nothing was written, and nothing was removed)"
      return 1
    fi
  done <<EOF
$(_ve_store_lines "$_VE_STORE")
EOF
  if _ve_shape_incommensurable "$ne" "$VALIDATE_ENTRY_CONTRADICTION_THRESHOLD" "$_VE_STORE" opposite "$np"; then
    _ve_unexaminable "REFUSE_CONTRADICTION_UNCOMPARABLE_SHAPE" "the entry is a ${_VE_SHAPE_CA}-significant-token document that is contradicted by store '$_VE_STORE' TAKEN AS A WHOLE at ${_VE_SHAPE_WHOLE}%, but every one of its ${_VE_SHAPE_LINES} comparable lines is smaller than the entry (largest: ${_VE_SHAPE_MAXLINE}), so the best score any SINGLE line could reach is ${_VE_SHAPE_CEILING}% — below the ${VALIDATE_ENTRY_CONTRADICTION_THRESHOLD}% threshold no matter what either side says. The same content shaped as one line per stored entry WOULD have produced a real verdict, and this shape turned it into a silent 'clean', so THIS CHECK COULD NOT DECIDE: the verdict is unknown, not clean. Two ways out, and which one applies depends on the store you passed: (a) if --store is one document split into lines, hand it ONE LINE PER STORED ENTRY instead (build_compare_corpus in write-agent-memory.sh is the worked example); (b) if --store ALREADY is one line per stored entry, then reshaping it cannot help and it is the ENTRY that spans several of them — validate it in stored-entry-sized pieces, which is the only granularity this check can judge"
    return 2
  fi
  return 0
}

# ---- check 3: provenance ----------------------------------------------------
# An entry must cite what motivated it. Satisfied by a REAL --source, or by a REFERENCE TOKEN in the
# entry text itself: a `#123` issue/PR citation, a `PR 123`, a URL, or a 7-40 char commit sha.
#
# ONE STANDARD ON BOTH HALVES. This comment used to promise that the text scan required a
# `session|finding|postmortem|... <id>` PHRASE; the pattern below required no id at all and matched
# the bare WORDS `session`, `finding`, `postmortem`, `incident`, `commit`, `issue`, `ticket` and
# `review` anywhere in the entry — a TOPIC, not a citation. Measured on the 21 live curated entries,
# that let 5 of them satisfy provenance while citing nothing ("... in only 3/7 recent twin sessions"),
# and it made the strict --source rule directly bypassable: `--source dreaming` was rejected above and
# then fell through to a scan that passed on any entry containing the word "review". Both halves now
# demand the same thing — an actual reference. The keyword alternation is DELETED rather than propped
# up with a "keyword near a number" adjacency window, because an adjacency heuristic over free prose
# is the same over-recognition machinery that produced this file's worst defect (see COVERAGE BOUND).
# THE COST, stated rather than discovered later: an entry whose motivation is a session or a finding
# with no id anywhere in its text is now refused unless the writer passes a real --source. All six
# sole writers do pass one, and the refusal message names both ways out. The direction is deliberate —
# provenance is one of the four fail-CLOSED checks; "a false refusal is worse than a miss" is the
# cross-repo recogniser's LOCAL reversal of this file's bias, not this file's default.
#
# STRICT --source (decision (f)), and it lives HERE so all six writers inherit it. A source
# qualifies only when it carries an actual REFERENCE: a digit (PR/issue number, commit sha, dated
# session id) or a `:` / `/` / `#` / `@` separator binding a label to an id — `dreaming:<session_id>`,
# `pr-138`, `PR #146`. A bare command name (`dreaming`) names the mechanism that ran, not what
# motivated the entry, so it cites nothing and does NOT qualify. Accepting any non-placeholder
# string was offered and rejected: it would make the check assert only that a caller passed SOME
# string. A source that does not qualify is not itself the refusal — it falls through to the entry-
# text scan below, so an entry that names its finding/PR/session in its own prose still passes.
_VE_PLACEHOLDER_SOURCES=" unknown unspecified none n/a na tbd todo - _ null nil "
_VE_PROVENANCE_RE='(^|[^A-Za-z0-9_])#[0-9]+|https?://|(^|[[:space:]])[Pp][Rr][[:space:]]*#?[0-9]+|(^|[[:space:]])[0-9a-f]{7,40}([[:space:]]|$)'
validate_provenance() {
  _ve_parse_args "$@"
  [ -n "$_VE_ENTRY" ] || { _ve_unexaminable "REFUSE_PROVENANCE_NO_ENTRY" "no --entry text was supplied, so provenance could not be examined"; return 2; }

  local src
  src="$(printf '%s' "$_VE_SOURCE" | tr '[:upper:]' '[:lower:]' | tr -d '[:cntrl:]' | sed -e 's/^ *//' -e 's/ *$//')"
  if [ -n "$src" ]; then
    case "$_VE_PLACEHOLDER_SOURCES" in
      *" $src "*) : ;;      # a placeholder source cites nothing — fall through to the text scan
      *)
        # STRICT: the source must carry a real reference, not merely be non-placeholder.
        case "$src" in
          *[0-9]*|*:*|*/*|*"#"*|*@*) return 0 ;;
          *) : ;;           # a bare command name cites nothing — fall through to the text scan
        esac ;;
    esac
  fi
  if grep -qE "$_VE_PROVENANCE_RE" <<<"$_VE_ENTRY"; then
    return 0
  fi
  _ve_refuse "REFUSE_PROVENANCE" "the entry cites nothing that motivated it — pass a real --source (one carrying an id, such as 'pr-138' or 'dreaming:<session_id>', not a bare command name), or name the reference itself in the entry text (a '#123', a URL or a commit sha). NOTE: the bare WORDS 'session', 'finding', 'postmortem' and 'review' are a topic, not a citation, and no longer satisfy this check on their own. Nothing was written."
  return 1
}

# ---- check 4: dead reference ------------------------------------------------
# Every file path the entry cites must still resolve. Recognised path shapes:
#   · any token containing a `/` and ending in an extension  (`loomwright/scripts/foo.sh`)
#   · a bare `NAME.md` / `NAME.sh` with no other dot         (`CLAUDE.md`)
# A trailing `:<N>` line citation, surrounding punctuation, quotes and backticks are stripped
# first; URLs are removed before scanning. Documented bound (deliberate, to keep false refusals
# rare): an extensionless path, and a bare filename with any other extension, are not recognised.
#
# SKIP vs REFUSE — the distinction this check turns on, and it is NOT a relaxation of decision (b).
# A token that is UNRESOLVABLE BY SHAPE is not a path this check can have an opinion about: a glob
# (`test-*.sh`), a `~/`-rooted home path, a `<placeholder>` or a `$VAR`-bearing token names no single
# file, so "does it still resolve" is not a question about it. Those are SKIPPED at extraction —
# never examined, never a verdict. That is different from could-not-examine (an unusable --root,
# absent jq, an unparseable record), which still REFUSES with rc 2. The rule: "I examined this and
# it is a real violation" is a refusal; "this token is not the kind of thing I recognise at all" is
# a skip. Conflating the two is what made a live corpus replay refuse 12 of 21 legitimate entries.
#
# PROSE `A/B` SHORTHAND IS NOT A PATH — the skip class added after review found this check refusing
# it, and the asymmetry it closes is the point. English writes alternatives with a slash, and when
# the second alternative happens to be a filename the result is character-for-character a
# two-segment path: `CHANGELOG/CLAUDE.md both drifted`, `see README/AGENT_GUIDELINES.md`. MEASURED,
# both were REFUSED, and the first is a live curated entry. The CROSS-REPO check was given a
# stoplist and a four-marker discipline for exactly this prose shape; this check was given none, so
# the same prose that cross-repo carefully skips, dead-reference refused.
#
# THE NARROWING, aimed at the signal rather than at the tokens (a stoplist of prose pairs is
# unbounded by construction — the same argument the cross-repo check records): a token with EXACTLY
# TWO segments is a path candidate only when its OWNER half NAMES A DIRECTORY IN THIS REPO'S TREE,
# reusing `_ve_owner_is_repo_dir` — the one signal that reads the world rather than the shape, which
# is the only thing that can separate `docs/PITFALLS.md` (a real citation, still refused when dead)
# from `CHANGELOG/CLAUDE.md` (prose). Failing that, the token is SKIPPED — never examined, never a
# verdict — which is this check's own SKIP-vs-REFUSE rule applied to a shape it cannot have an
# opinion about, not a relaxation of decision (b).
# Deliberately scoped to TWO segments: `loomwright/scripts/foo.sh` has three and is unambiguous, so
# it stays a candidate unconditionally, as do absolute paths and `./`-rooted ones. A bare `NAME.md`
# has no owner half and is untouched.
# WHAT THIS COSTS: a dead two-segment path whose owner half is not itself a directory in the tree —
# a citation of `oldrenameddir/file.md` after the directory was removed entirely — is now missed.
# That is a real catch lost, and it is the file-wide bias applied on purpose: the same citation with
# the directory still present is still checked, and a false refusal blocks a legitimate write.
# An UNBUILDABLE index makes the veto skip every two-segment token, which costs catches and can
# never manufacture a refusal.
_ve_extract_paths() {
  local root="${2:-}" cand owner
  while IFS= read -r cand; do
    [ -n "$cand" ] || continue
    case "$cand" in
      /*)      printf '%s\n' "$cand"; continue ;;   # absolute: unambiguous, judged as before
      */*/*)   printf '%s\n' "$cand"; continue ;;   # three or more segments: unambiguous
      ./*|../*) printf '%s\n' "$cand"; continue ;;  # explicitly cwd-relative: unambiguous
      */*)     : ;;                                 # exactly two segments: the prose-shorthand shape
      *)       printf '%s\n' "$cand"; continue ;;   # bare NAME.md / NAME.sh: no owner half
    esac
    owner="$(printf '%s' "${cand%%/*}" | tr '[:upper:]' '[:lower:]')"
    _ve_owner_is_repo_dir "$owner" "$root" || continue
    printf '%s\n' "$cand"
  done <<EOF
$(printf '%s\n' "${1:-}" \
    | sed -e 's#https\{0,1\}://[^[:space:]]*# #g' \
    | tr -s '[:space:]' '\n' \
    | sed -e 's/^[][(){}<>"'"'"'`*,;]*//' -e 's/[][(){}<>"'"'"'`*,;.!?]*$//' \
          -e 's/:[0-9][0-9]*$//' -e 's/[][(){}<>"'"'"'`*,;.!?]*$//' \
    | awk '
        $0 == "" { next }
        /[][*?{}$<>]/ { next }        # a glob or a placeholder resolves to no single file: SKIP
        /^~/          { next }        # a home-relative path is outside any repo root: SKIP
        /\// && /\.[A-Za-z][A-Za-z0-9]*$/ { print; next }
        /^[^.\/]+\.(md|sh)$/ { print }
      ')
EOF
}

# _ve_repo_index <root> — every file path in the repo, one per line, relative to <root>. Built ONCE
# per root per process (curated entries cite several paths each, and re-listing the tree per token
# is the difference between a validator and a pause). The index is the UNION of two sources:
# `git ls-files` (the tracked set) and a pruned `find` (everything actually on disk).
#
# THE UNION REPLACED A FALLBACK, and the fallback was DEAD CODE — the third false-refusal class
# found by review. The `find` used to run only when `git ls-files` came back EMPTY, which in a real
# work tree never happens, so the index was the TRACKED set and nothing else. Every GITIGNORED BUT
# REAL file was therefore unresolvable and refused: MEASURED on this repo, `.supervisor/state.md`
# exists on disk, `git ls-files` does not list it, and an entry saying "the projector writes
# state.md each phase" was refused as a dead reference — as was `graphify-out/graph.json`. Both are
# files a curated entry has every reason to cite: the gitignored scratch dirs are precisely where
# this system's own runtime state lives. Unioning can only ever make MORE paths resolve, so it can
# only ever remove refusals; it can never manufacture one.
#
# THE COST, stated rather than discovered later: the `find` now runs on every root instead of
# almost never, so it is memoised exactly as the git listing was (one build per root per process,
# read out of $_VE_INDEX by the callers that need it in THIS shell). MEASURED on this repo: ~3,750
# files in ~30ms against ~400 tracked, which is noise next to the awk scans it feeds.
# THE OTHER COST, and it is a real one: a path that is dead in git but still present in some
# untracked leftover under the root (a stale worktree, a build artifact) now RESOLVES, so a
# genuinely dead reference to it is missed. That is the file-wide bias applied deliberately — a
# missed dead reference is a documented gap, a false refusal blocks a legitimate write.
# Documented bound: the `find` half prunes `.git` and `node_modules` and stops at depth 8, so a
# file buried deeper than that is indexed only if git tracks it.
_VE_INDEX_ROOT=""
_VE_INDEX=""
_ve_repo_index() {
  local root="${1:-}"
  [ -n "$root" ] && [ -d "$root" ] || return 1
  if [ "$_VE_INDEX_ROOT" = "$root" ]; then printf '%s' "$_VE_INDEX"; return 0; fi
  local tracked ondisk out
  tracked="$(git -C "$root" ls-files 2>/dev/null)"
  ondisk="$(find "$root" -maxdepth 8 \( -name .git -o -name node_modules \) -prune -o -type f -print 2>/dev/null \
    | awk -v r="$root/" '{ if (index($0, r) == 1) $0 = substr($0, length(r) + 1); print }')"
  # `printf | awk` (never an early-exit consumer) keeps this safe under a caller's `set -o pipefail`.
  out="$(printf '%s\n%s\n' "$tracked" "$ondisk" | awk 'NF && !seen[$0]++')"
  _VE_INDEX_ROOT="$root"; _VE_INDEX="$out"
  printf '%s' "$out"
}

# _ve_index_has <relative-path> <index> -> 0 when some indexed file IS that path or ENDS WITH it.
# The suffix match is the point: an entry that cites `check-doc-currency.sh` or `docs/PITFALLS.md`
# is citing a REAL file that simply does not sit at the repo root — resolving only against the root
# refused nine live entries for existing. A suffix match still refuses a genuinely dead path,
# because nothing in the tree ends with it.
_ve_index_has() {
  local p="${1:-}" idx="${2:-}"
  [ -n "$p" ] && [ -n "$idx" ] || return 1
  awk -v p="$p" '
    BEGIN { n = length(p) + 1; sfx = "/" p }
    $0 == p { found = 1; exit }
    length($0) > n && substr($0, length($0) - n + 1) == sfx { found = 1; exit }
    END { exit(found ? 0 : 1) }
  ' <<EOF
$idx
EOF
}

# _ve_path_resolves <path> <root> -> 0 when it resolves (absolute, under root, relative to CWD, or
# anywhere in the repo as a path SUFFIX — see _ve_index_has).
_ve_path_resolves() {
  local p="${1:-}" root="${2:-}"
  [ -n "$p" ] || return 1
  case "$p" in
    /*) [ -e "$p" ] && return 0; return 1 ;;
  esac
  [ -n "$root" ] && [ -e "$root/$p" ] && return 0
  [ -e "$p" ] && return 0
  # Build the index in THIS shell and read $_VE_INDEX, never `$(_ve_repo_index ...)`: a command
  # substitution runs in a subshell, so the cache assignment would be discarded and every cited
  # path in every entry would re-list the whole tree.
  _ve_repo_index "$root" >/dev/null || return 1
  _ve_index_has "$p" "$_VE_INDEX" && return 0
  return 1
}

# ADVISORY (see the header): every path below reports and returns 0. There is no `return 1` and no
# `return 2` anywhere in this function, deliberately — the absence is the contract, and a static
# assertion in the suite pins it so a future edit cannot quietly reintroduce a blocking path.
validate_dead_reference() {
  _ve_parse_args "$@"
  local root
  root="$(_ve_resolve_root)"
  if [ -n "$root" ]; then
    [ -d "$root" ] || { _ve_advise "ADVISORY_DEAD_REFERENCE_ROOT_MISSING" "root '$root' is not a directory, so no cited path could be resolved — this check could not run at all, which is reported and is not a refusal"; return 0; }
    [ -r "$root" ] || { _ve_advise "ADVISORY_DEAD_REFERENCE_ROOT_UNREADABLE" "root '$root' could not be read, so no cited path could be resolved — this check could not run at all, which is reported and is not a refusal"; return 0; }
  fi

  # --- JSON record mode: a nullable-but-REQUIRED field carrying a cited path ---
  # Key PRESENCE is asserted with `jq has()` BEFORE the value is looked at. A MISSING key and an
  # explicit `null` are different facts: null is a valid "this record cites no path", a missing key
  # means the record is not the shape we were asked to examine — which is could-not-examine, not
  # clean. Reading the value alone cannot tell them apart, which is how a nullable-required field
  # silently accepts a malformed record.
  if [ "$_VE_JSON_SET" -eq 1 ]; then
    command -v jq >/dev/null 2>&1 || { _ve_advise "ADVISORY_DEAD_REFERENCE_NO_JQ" "jq is not available, so the JSON record could not be examined"; return 0; }
    printf '%s' "$_VE_JSON" | jq -e . >/dev/null 2>&1 || { _ve_advise "ADVISORY_DEAD_REFERENCE_JSON_UNPARSEABLE" "the --json record is not valid JSON, so it could not be examined"; return 0; }
    if [ -n "$_VE_FIELD" ]; then
      local has ftype fval
      has="$(printf '%s' "$_VE_JSON" | jq -r --arg f "$_VE_FIELD" 'if type == "object" then (has($f) | tostring) else "not-an-object" end' 2>/dev/null)"
      case "$has" in
        true)  : ;;
        false) _ve_advise "ADVISORY_DEAD_REFERENCE_FIELD_ABSENT" "the --json record has no '$_VE_FIELD' key at all (an explicit null would be valid; a missing key is not), so it could not be examined"; return 0 ;;
        *)     _ve_advise "ADVISORY_DEAD_REFERENCE_JSON_NOT_OBJECT" "the --json record is not an object, so '$_VE_FIELD' could not be examined"; return 0 ;;
      esac
      ftype="$(printf '%s' "$_VE_JSON" | jq -r --arg f "$_VE_FIELD" '.[$f] | type' 2>/dev/null)"
      case "$ftype" in
        null)   : ;;   # present and explicitly null — nullable, cites no path, valid
        string)
          fval="$(printf '%s' "$_VE_JSON" | jq -r --arg f "$_VE_FIELD" '.[$f]' 2>/dev/null)"
          if [ -n "$fval" ] && ! _ve_path_resolves "$fval" "$root"; then
            _ve_advise "ADVISORY_DEAD_REFERENCE" "the '$_VE_FIELD' field cites '$fval', which does not resolve under '$root'"
          fi ;;
        *) _ve_advise "ADVISORY_DEAD_REFERENCE_FIELD_TYPE" "'$_VE_FIELD' is a $ftype, not a string or null, so it could not be examined as a path"; return 0 ;;
      esac
    fi
  fi

  # --- prose mode ---
  [ -n "$_VE_ENTRY" ] || {
    # With a JSON record already examined above, an absent --entry is simply nothing more to do.
    [ "$_VE_JSON_SET" -eq 1 ] && return 0
    _ve_advise "ADVISORY_DEAD_REFERENCE_NO_ENTRY" "no --entry text was supplied, so no cited path could be examined"; return 0
  }
  local p
  # Build the directory set in THIS shell BEFORE the command substitution below. `_ve_extract_paths`
  # needs it for the two-segment prose veto, and a `$(...)` subshell INHERITS these caches but cannot
  # export one back — building it there would re-list the whole tree on every call and throw the
  # result away. Failure is not fatal: an unbuildable index leaves the veto unable to fire, which
  # costs catches and never manufactures a refusal.
  _ve_repo_dirs "$root" >/dev/null 2>&1 || true
  # EVERY unresolved path is reported, not just the first. The old code returned on the first one
  # because it was refusing and the rest could not change that verdict; an advisory that stops at
  # the first finding hands the reader one item of a list and hides the others.
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if ! _ve_path_resolves "$p" "$root"; then
      _ve_advise "ADVISORY_DEAD_REFERENCE" "the entry cites '$p', which does not resolve under '$root'. NOTE: whether a path resolves depends on what is present in THIS tree — a gitignored runtime artifact resolves on the machine that produced it and not on a clean checkout — which is one of the reasons this check reports instead of refusing"
    fi
  done <<EOF
$(_ve_extract_paths "$_VE_ENTRY" "$root")
EOF
  return 0
}

# ---- check 5: cross-repo reference ------------------------------------------
# REFUSE a repo-shaped token that is NOT in this repo's allowlist; PASS one that IS. See the
# ALLOWLIST DIRECTION note in the header before changing either side of that test.

# _ve_setup_memory_path — the ONE resolver. $VALIDATE_ENTRY_SETUP_MEMORY exists so a test can point
# the check at an absent or broken resolver and prove the could-not-examine path; it is never a
# second parser of the allowlist itself.
_ve_setup_memory_path() {
  if [ -n "${VALIDATE_ENTRY_SETUP_MEMORY:-}" ]; then printf '%s' "$VALIDATE_ENTRY_SETUP_MEMORY"; return 0; fi
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/setup-memory.sh" ]; then
    printf '%s' "${CLAUDE_PLUGIN_ROOT}/scripts/setup-memory.sh"; return 0
  fi
  printf '%s' "$_VE_SELF_DIR/setup-memory.sh"
}

# _ve_load_allowlist <root> — prints the resolved allowlist, one `owner/repo` per line. Empty
# output means UNRESOLVED, which callers must treat as could-not-examine (setup-memory.sh always
# exits 0, so the status is not the signal — the emptiness is). Its `# source: ...` provenance
# line goes to stderr and is discarded here.
_ve_load_allowlist() {
  local sm="$1" root="${2:-}"
  [ -n "$sm" ] && [ -f "$sm" ] && [ -r "$sm" ] || return 0
  if [ -n "$root" ]; then
    bash "$sm" --root "$root" allowlist 2>/dev/null
  else
    bash "$sm" allowlist 2>/dev/null
  fi
}

# _ve_extract_repo_tokens <text> <known-owners> <root> — the recognised repo-reference shapes, one
# per line, as `slug:<owner/repo>` or `short:<name>`. Those are the only two kinds emitted and the
# only two `validate_cross_repo_reference` dispatches on; an earlier draft of this comment advertised
# `strong:` and `weak:` kinds that were never implemented. Everything else in the prose is invisible
# to the check, by design; see the COVERAGE BOUND note in the header.
#
# Slugs are taken from WHITESPACE-DELIMITED tokens, never from a `grep -o` substring. A substring
# match on `loomwright/scripts/read-rules.sh` yields the first two segments, `loomwright/scripts`,
# which then looks exactly like an `owner/repo` slug outside the allowlist — every entry citing any
# three-segment path would be refused. Splitting on whitespace keeps the path whole so the
# "more than one slash" test can actually reject it.
#
# _ve_known_owners <allowlist-entries> <root> — the OWNER halves this system has actually seen, as
# a space-delimited lowercase list. Two sources, both already in hand, neither a new parser of the
# allowlist: the owner side of each resolved allowlist slug (obtained from the ONE delegated
# resolver, passed in by the caller), and the `.repo` values in the postmortem ledger — the target
# root's, and this plugin's own, since the ledger is committed and therefore present in CI.
# Read-only and fail-safe: an absent or unreadable ledger contributes nothing, which costs
# recognition (a miss) and never produces a refusal.
_VE_OWNERS_KEY=""
_VE_OWNERS=""
_ve_known_owners() {
  local entries="${1:-}" root="${2:-}" key out e led got
  key="$entries|$root"
  if [ "$_VE_OWNERS_KEY" = "$key" ]; then printf '%s' "$_VE_OWNERS"; return 0; fi
  out=""
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    case "$e" in */*) : ;; *) continue ;; esac
    out="$out $(printf '%s' "${e%%/*}" | tr '[:upper:]' '[:lower:]')"
  done <<EOF
$entries
EOF
  for led in "$root/.supervisor/postmortem/results.jsonl" \
             "$_VE_SELF_DIR/../../.supervisor/postmortem/results.jsonl"; do
    case "$led" in /*) : ;; *) continue ;; esac
    [ -f "$led" ] && [ -r "$led" ] || continue
    got="$(awk '{
      s = $0
      while (match(s, /"repo"[[:space:]]*:[[:space:]]*"[^"]+"/)) {
        v = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
        sub(/^"repo"[[:space:]]*:[[:space:]]*"/, "", v); sub(/"$/, "", v)
        if (index(v, "/") > 1) {
          o = tolower(substr(v, 1, index(v, "/") - 1))
          if (!(o in seen)) { seen[o] = 1; printf " %s", o }
        }
      }
    }' "$led" 2>/dev/null)"
    out="$out$got"
  done
  _VE_OWNERS_KEY="$key"; _VE_OWNERS="$out"
  printf '%s' "$out"
}

# _ve_emit_slug_token <token> <preceding-word> <following-word> <structural-marker> <known-owners>
# <root> — prints `slug:<owner/repo>` when
# the token is a MARKED repo citation, and prints nothing otherwise. Held apart from the scanning
# loop so that "is this a slug" is one readable list of reject reasons, and so a mutation control
# can aim at exactly one of them.

# _ve_strip_ordinal <half> -> the half with a trailing `-<digits>` ORDINAL suffix removed
# (`subtask-1` -> `subtask`, `phase-2` -> `phase`), unchanged otherwise. A `-<digits>` tail is how
# prose NUMBERS things, and it is the commonest way an in-repo directory path picks up the digit that
# marker (4) reads as repo structure. Digits fused to letters (`repo2`) and a non-numeric tail
# (`terraform-aws-v2`) are not ordinals and keep their structure. See narrowing (ii) in the header.
# _ve_strip_trailing_dots <word> -> the word with any trailing `.` characters removed.
# NARROWLY SCOPED, and that scoping is the point: it is applied ONLY to the two NEIGHBOUR words
# before they are matched against the cue-word lists, never to the candidate token itself. The
# neighbour words reach here normalized by `tr -cd 'a-z0-9._/-'`, which strips a comma but KEEPS a
# period — so `landed in the acme-corp/widget-svc repo,` matched the trailing cue `repo` while the
# far commoner sentence-final `... repo.` yielded `repo.` and matched nothing. That asymmetry was
# unintentional; a sentence-final period is punctuation, not part of the cue word. Trailing dots
# only: an INTERNAL dot is meaningful in a neighbour (`example.com`, `v1.2`) and is untouched, and
# the token's own extension/host recognition happens elsewhere and is not affected by this at all.
_ve_strip_trailing_dots() {
  local v="${1:-}"
  while [ -n "$v" ] && [ "${v%.}" != "$v" ]; do v="${v%.}"; done
  printf '%s' "$v"
}

_ve_strip_ordinal() {
  local v="${1:-}" tail
  case "$v" in *-*) : ;; *) printf '%s' "$v"; return 0 ;; esac
  tail="${v##*-}"
  [ -n "$tail" ] || { printf '%s' "$v"; return 0; }
  case "$tail" in *[!0-9]*) printf '%s' "$v"; return 0 ;; esac
  printf '%s' "${v%-*}"
}

# _ve_repo_dirs <root> — caches, in $_VE_DIRS, the space-delimited lowercase set of every DIRECTORY
# NAME appearing anywhere in <root>'s tree. Derived from the SAME index the dead-reference check
# builds, so a process reads the tree once, not once per token. Returns non-zero when no index could
# be built, which costs recognition (the veto cannot fire) and never invents one.
_VE_DIRS_ROOT=""
_VE_DIRS=""
_ve_repo_dirs() {
  local root="${1:-}"
  [ -n "$root" ] && [ -d "$root" ] || return 1
  [ "$_VE_DIRS_ROOT" = "$root" ] && return 0
  _VE_DIRS_ROOT="$root"; _VE_DIRS=""
  # Build the index in THIS shell and read $_VE_INDEX (the same reason _ve_path_resolves does): a
  # command substitution would run in a subshell and throw the cache away.
  _ve_repo_index "$root" >/dev/null || return 1
  _VE_DIRS=" $(awk '{
      n = split($0, p, "/")
      for (i = 1; i < n; i++) if (p[i] != "" && !(p[i] in seen)) { seen[p[i]] = 1; printf "%s ", tolower(p[i]) }
    }' <<EOF
$_VE_INDEX
EOF
)"
  return 0
}

# _ve_owner_is_repo_dir <lowercase-owner> <root> -> 0 when the owner half names a directory that
# exists in this repo's tree, i.e. the token is an IN-REPO PATH and not a foreign `owner/repo`.
# Narrowing (i) in the header — the one signal that reads the world rather than the shape, which is
# the only thing that can tell `docs/Spikes` from `octocat/Hello-World`.
_ve_owner_is_repo_dir() {
  local owner="${1:-}" root="${2:-}"
  [ -n "$owner" ] || return 1
  _ve_repo_dirs "$root" || return 1
  case "$_VE_DIRS" in *" $owner "*) return 0 ;; esac
  return 1
}

# _ve_slug_structured <owner> <repo> -> 0 when the token carries structure an English word pair does
# not. THIS LIST IS THE SIGNALS AS THEY STAND AFTER narrowings (v)-(vii), not as they were
# authored — the narrowings are implemented inline in the body below and each one only ever REMOVES
# recognition:
#   · a digit ANYWHERE                       — `octocat/repo2`. The owner half is tested first and
#     separately (and the "anywhere" test then subsumes it); both are kept because narrowing (vi)
#     retracted the owner-half HYPHEN and only the hyphen — a digit in the owner half is still
#     structure. An owner-half hyphen alone is NOT: `acme-corp/widget-svc` and
#     `hashicorp/terraform-aws` earn nothing here.
#   · an INTERNAL capital in either half     — `octocat/Hello-World`, on the `W` of `World`. A
#     capital followed by a LOWERCASE letter, which is what separates a repo name from SHOUTED
#     prose: `YAML/JSON` and `dev/CI` are all-caps and carry no such pair, so they stay ordinary
#     prose. Narrowing (vii) drops the FIRST character of each half first, so a leading capital
#     (`Microsoft/vscode`, `Count/version`) is not CamelCase.
# SUPPRESSOR (iii): an ALL-CAPS repo half is a FILE STEM, not a repository name — `review-heal/SKILL`
# and `docs/README` are citations of files in this tree, and neither is separable from a slug by any
# other means. SUPPRESSOR (ii): ordinal `-<digits>` suffixes are stripped first, so `worktrees/
# subtask-1` and `phase-2/plan` no longer read as "carries a digit". Both only ever REMOVE
# recognition, so neither can make this function claim structure it did not claim before.
_ve_slug_structured() {
  local left="${1:-}" right="${2:-}" h l r
  # SUPPRESSOR (iv): BOTH HALVES ALL DIGITS IS A RATIO, NOT A REPOSITORY. Checked FIRST, before any
  # signal below is consulted, because the "a digit anywhere" signal is unconditionally satisfied by
  # a numeric pair and no other narrowing can reach it: ordinal stripping (ii) only touches a
  # `-<digits>` TAIL, and the ALL-CAPS suppressor (iii) only touches a repo half with no lowercase.
  # MEASURED on the live corpus, every one a false refusal of a legitimate entry: `117/117`,
  # `11/11`, `21/21`, `59/59`, `85/100` — counting prose ("a repo-root re-run (117/117 pass)") is how
  # this codebase writes down test results, so this shape is not rare in curated memory, it is
  # characteristic of it. Index-INDEPENDENT: it holds with no repo to read, which is why it is here
  # and not in the IN-REPO PATH VETO that needs a usable root.
  # It can only ever REMOVE recognition. The residual, deliberate: a genuinely numeric GitHub owner
  # (logins may be all digits) carrying ONLY this marker is now invisible — but a real citation of
  # one still carries a STRUCTURAL marker (`github.com/117/117`, `117/117#12`, `117/117.git`), and
  # those bypass this function entirely, so the recognised shapes are unaffected.
  case "$left$right" in
    *[!0-9]*) : ;;                            # some non-digit somewhere: judge it below
    *) return 1 ;;                            # all digits (or empty): a ratio, never a slug
  esac
  case "$right" in
    *[[:lower:]]*) : ;;                       # has lowercase: an ordinary name, judge it below
    *[[:upper:]]*) return 1 ;;                # ALL-CAPS repo half: a file stem, not a repo name
  esac
  l="$(_ve_strip_ordinal "$left")"; r="$(_ve_strip_ordinal "$right")"
  # NARROWING (v): a VERSION TAG is not repo structure. A `v<digits>(.<digits>)*` run, at the start
  # of a half or as a hyphen-delimited segment, is how this project names releases and branches, and
  # it is the digit that made `fix/v14.23.1-combined` — an ordinary GIT BRANCH NAME — read as a
  # foreign repository, refusing a live curated entry. Same family as (ii): strip the numbering
  # prose adds, then ask whether any structure remains. `octocat/repo2` keeps its digit (fused to
  # letters, not a `v`-prefixed tag) and is still recognised, which is the line this narrowing walks.
  l="$(printf '%s' "$l" | sed -E 's/(^|-)v[0-9]+(\.[0-9]+)*/\1/g')"
  r="$(printf '%s' "$r" | sed -E 's/(^|-)v[0-9]+(\.[0-9]+)*/\1/g')"
  # NARROWING (vi): the OWNER-HALF HYPHEN is no longer structure on its own. `ground-truth/conformance`
  # is an English alternative pair and was refused as a repository; a hyphen is simply how prose
  # compounds words, so it cannot carry the reading "repository" by itself. A DIGIT in the owner half
  # still does.
  case "$l" in *[0-9]*) return 0 ;; esac
  case "$l$r" in *[0-9]*) return 0 ;; esac
  # NARROWING (vii): CamelCase means an INTERNAL capital, not a leading one. A capital in position 1
  # is how every English sentence begins, and `Count/version drift is the top late-stage failure`
  # opened a live curated entry that this check then refused. The first character of each half is
  # therefore dropped before the capital-followed-by-lowercase test; `octocat/Hello-World` still
  # qualifies on the `W` of `World`.
  for h in "$l" "$r"; do
    case "${h#?}" in *[[:upper:]][[:lower:]]*) return 0 ;; esac
  done
  return 1
}

_ve_emit_slug_token() {
  local tok="${1:-}" prev="${2:-}" next="${3:-}" structural="${4:-0}" owners="${5:-}" root="${6:-}"
  local left right lower prev_cue next_cue
  # Cue-word forms ONLY. $prev/$next themselves are left untouched so nothing else in this function
  # can be affected by the stripping; the two `_cue` copies are used by the marker (2) tests below
  # and nowhere else.
  prev_cue="$(_ve_strip_trailing_dots "$prev")"
  next_cue="$(_ve_strip_trailing_dots "$next")"
  [ -n "$tok" ] || return 0
  case "$tok" in *"/"*) : ;; *) return 0 ;; esac
  left="${tok%%/*}"; right="${tok#*/}"
  case "$right" in */*) return 0 ;; esac                        # more than one `/` is a path
  # THE FILE-EXTENSION GUARD — a repo half ending in a dot plus 1-5 letters is a FILENAME, so the
  # token is a path (`docs/PITFALLS.md`, `postmortem/results.jsonl`) and never an `owner/repo` slug.
  # WIDENED FROM 4 TO 5: this repo's own curated prose cites `.jsonl` constantly (the postmortem
  # ledger) and a 4-letter bound left it outside the guard, falling short of the blanket claim this
  # function's header makes. 5 is the stopping point on purpose — it covers the real extensions in
  # play (`.json`, `.jsonl`, `.patch`, `.yaml`) while `.github`-length and beyond starts eating
  # legitimate dotted repo names, and the guard can only ever REMOVE recognition, so over-widening
  # is a silent loss of coverage rather than a loud one.
  case "$right" in *.[A-Za-z]|*.[A-Za-z][A-Za-z]|*.[A-Za-z][A-Za-z][A-Za-z]|*.[A-Za-z][A-Za-z][A-Za-z][A-Za-z]|*.[A-Za-z][A-Za-z][A-Za-z][A-Za-z][A-Za-z]) return 0 ;; esac
  [ "${#left}" -ge 2 ] && [ "${#right}" -ge 2 ] || return 0
  # Both halves must be plain slug characters; anything else (an apostrophe, a colon, a brace that
  # survived stripping) means this was never an `owner/repo` citation.
  case "$left$right" in *[!A-Za-z0-9._-]*) return 0 ;; esac
  # The OWNER half must be a legal GitHub login: letters, digits and single hyphens only.
  case "$left" in *[!A-Za-z0-9-]*) return 0 ;; -*|*-) return 0 ;; esac
  lower="$(printf '%s' "$tok" | tr '[:upper:]' '[:lower:]')"
  case "$_VE_SLUG_STOPLIST" in *" $lower "*) return 0 ;; esac
  # THE MARKER TEST — four ways a bare `x/y` earns the reading "repository", any one of which is
  # enough. Carrying NONE of them, it is skipped and never judged; see COVERAGE BOUND for why that
  # residual miss is deliberate and what it costs.
  if [ "$structural" != "1" ]; then
    case "$_VE_SLUG_CUE_WORDS" in
      *" $prev_cue "*) : ;;
      *) case "$_VE_SLUG_TRAILING_CUE_WORDS" in
           *" $next_cue "*) : ;;
           *) case " $owners " in
                *" ${lower%%/*} "*) : ;;                     # a KNOWN repo owner
                *) _ve_slug_structured "$left" "$right" || return 0 ;;
              esac ;;
         esac ;;
    esac
    # THE IN-REPO PATH VETO, applied only after a SOFT marker has already fired and deliberately not
    # to the structural ones: `github.com/docs/spikes` and `docs/spikes#12` name a repository
    # explicitly, so no amount of local directory naming should suppress them. See narrowing (i).
    _ve_owner_is_repo_dir "${lower%%/*}" "$root" && return 0
  fi
  printf 'slug:%s\n' "$lower"
}

# A `NAME #123` candidate counts only when NAME is IDENTIFIER-SHAPED — ALL-CAPS, or containing a
# hyphen, underscore or digit. The shape alone is ambiguous: "fixed in #146" has it too, and
# reading `in` as a repository would refuse ordinary prose, which is far worse than missing a
# reference. So `OTHERSVC #146` is recognised and a plain lowercase `word #123` is NOT — including a
# lowercase FOREIGN one. That is under-recognition: the documented, deliberate failure direction,
# stated in every refusal message and pinned by its own test.
#
# An `owner/repo` candidate carries the SAME requirement, for the same reason (see COVERAGE BOUND):
# it counts only when the citation is MARKED — structurally (`github.com/o/r`, `o/r#12`, `o/r@sha`,
# `o/r.git`), by a neighbouring cue word, by a KNOWN owner, or by slug-only structure. Two shape
# constraints apply on top, both checked before the marker so a marked non-slug is still rejected:
# the OWNER half must be a legal
# GitHub login (`[A-Za-z0-9-]`, never `_` or `.`, no leading/trailing hyphen — which is why
# `WORKER_RESULT/CODE_REVIEW_RESULT` and `example.com/path` can never be slugs), and the repo half
# must not end in a file extension (so `docs/PITFALLS.md` stays a path).
_ve_extract_repo_tokens() {
  local text="${1:-}" owners="${2:-}" root="${3:-}" raw tok prev next lower left right name structural
  # (a) `owner/repo` slugs, from whitespace-delimited tokens, with the NEIGHBOURING tokens in hand.
  # awk emits each token as a THREE-LINE record (prev, token, next), one field per line, each field
  # prefixed with `>` — a deliberately separator-free encoding. A single-line record needs a
  # delimiter, and every candidate is a trap here: a tab is IFS-WHITESPACE, so `read` strips leading
  # runs of it and shifts a token with an empty neighbour into the wrong variable (a single-token
  # entry then emits nothing at all), and a control byte did not survive the expansion intact. The
  # `>` prefix is what keeps an empty field from becoming an empty LINE, which `$(...)`'s trailing-
  # newline stripping would swallow, silently dropping the last token of every entry.
  while IFS= read -r prev; do
    IFS= read -r raw  || break
    IFS= read -r next || break
    prev="${prev#>}"; raw="${raw#>}"; next="${next#>}"
    [ -n "$raw" ] || continue
    structural=0
    # Strip the URL scheme first: a `github.com/` prefix is a structural marker, any other host
    # leaves two slashes (or a dotted owner) and is rejected by the shape tests below.
    tok="$(printf '%s' "$raw" \
      | sed -e 's#^https\{0,1\}://##' -e 's/^[][(){}<>"'"'"'\`*,;]*//' -e 's/[][(){}<>"'"'"'\`*,;.!?]*$//')"
    case "$tok" in
      www.github.com/*) structural=1; tok="${tok#www.github.com/}" ;;
      github.com/*)     structural=1; tok="${tok#github.com/}" ;;
    esac
    case "$tok" in
      *"#"*) case "${tok%%#*}" in *"/"*) structural=1 ;; esac; tok="${tok%%#*}" ;;
    esac
    case "$tok" in
      *"@"*) case "${tok%%@*}" in *"/"*) structural=1 ;; esac; tok="${tok%%@*}" ;;
    esac
    case "$tok" in
      *.git) structural=1; tok="${tok%.git}" ;;
    esac
    tok="${tok%%:*}"
    _ve_emit_slug_token "$tok" \
      "$(printf '%s' "$prev" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9._/-')" \
      "$(printf '%s' "$next" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9._/-')" \
      "$structural" "$owners" "$root"
  done <<EOF
$(printf '%s\n' "$text" | tr -s '[:space:]' '\n' \
  | awk '{ a[NR] = $0 }
      END { for (i = 1; i <= NR; i++) printf ">%s\n>%s\n>%s\n", (i > 1 ? a[i-1] : ""), a[i], (i < NR ? a[i+1] : "") }')
EOF
  # (b) `NAME #123` citations. The leading `[^A-Za-z0-9._/-]` guard stops the name half from
  # starting mid-path (`.../read-rules.sh #12` must not yield a repo called `read-rules.sh`).
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    name="$(printf '%s' "$tok" | sed -e 's/[[:space:]]*#.*$//')"
    [ -n "$name" ] || continue
    # Same 1-5 letter file-extension bound as the slug guard above, kept in lockstep on purpose:
    # `results.jsonl #12` is a file citation, not a repository called `results.jsonl`.
    case "$name" in *.[A-Za-z]|*.[A-Za-z][A-Za-z]|*.[A-Za-z][A-Za-z][A-Za-z]|*.[A-Za-z][A-Za-z][A-Za-z][A-Za-z]|*.[A-Za-z][A-Za-z][A-Za-z][A-Za-z][A-Za-z]) continue ;; esac
    lower="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
    case "$_VE_NOT_REPO_WORDS" in *" $lower "*) continue ;; esac
    if [ "${#name}" -ge 2 ] && [ "$name" = "$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')" ]; then
      printf 'short:%s\n' "$lower"          # ALL-CAPS: OTHERSVC #146
    else
      case "$name" in
        *[-_0-9]*) printf 'short:%s\n' "$lower" ;;   # identifier-shaped: ai-agent-manager #12
        # a plain lowercase word (`in #146`, `see #146`) is NOT a recognised repo reference
      esac
    fi
  done <<EOF
$(printf '%s\n' "$text" | grep -oE '(^|[^A-Za-z0-9._/-])[A-Za-z][A-Za-z0-9._-]*[[:space:]]*#[0-9]+' 2>/dev/null | sed -e 's/^[^A-Za-z]*//')
EOF
}

# _ve_in_list <needle> <space-delimited-haystack> -> 0 when the needle IS a member.
# THE membership test — deliberately the single point where "in the allowlist" is decided, so that
# inverting it (the mandated mutation control) is one edit and moves every verdict at once. Read
# the ALLOWLIST DIRECTION note in the header before changing the sense of this function: IN means
# "ours, allowed"; NOT IN means "foreign, refuse".
_ve_in_list() {
  case "${2:-}" in
    *" ${1:-} "*) return 0 ;;
  esac
  return 1
}

# ADVISORY (see the header): every path below reports and returns 0. As in validate_dead_reference,
# the ABSENCE of any `return 1` / `return 2` in this function is the contract, and the suite asserts
# it statically as well as behaviourally.
validate_cross_repo_reference() {
  _ve_parse_args "$@"
  [ -n "$_VE_ENTRY" ] || { _ve_advise "ADVISORY_CROSS_REPO_NO_ENTRY" "no --entry text was supplied, so no repo reference could be examined"; return 0; }

  local root idx_root tokens sm entries owners
  root=""
  [ "${_VE_ROOT_SET:-0}" -eq 1 ] && root="$_VE_ROOT"
  # A SECOND root, for the IN-REPO PATH VETO only. It is resolved the way the dead-reference check
  # resolves one (explicit --root, else the git toplevel, else $PWD) rather than reusing $root above,
  # because $root is ALSO the allowlist resolver's `--root` and must keep meaning exactly "the caller
  # named one": passing a defaulted root into `setup-memory.sh --root` would silently change which
  # config layer the allowlist comes from. Two roots, two jobs, neither borrowed from the other.
  idx_root="$(_ve_resolve_root)"

  # The allowlist is resolved BEFORE extraction because the owner half of each allowlisted slug is
  # one of the markers the recogniser reads. Resolution failures are deliberately NOT reported at
  # this point: they are only a verdict once something repo-shaped was actually recognised, which is
  # why the two could-not-examine guards stay below the token test.
  sm="$(_ve_setup_memory_path)"
  entries=""
  if [ -f "$sm" ] && [ -r "$sm" ]; then entries="$(_ve_load_allowlist "$sm" "$root")"; fi
  owners="$(_ve_known_owners "$entries" "$root")"
  tokens="$(_ve_extract_repo_tokens "$_VE_ENTRY" "$owners" "$idx_root")"
  # No repo reference of any recognised shape: the verdict does not depend on the allowlist at all,
  # so it is honest to pass without resolving one. This is also why a fresh clone with no remote
  # does not refuse every ordinary write — only entries that DO cite a repo need a resolvable list.
  [ -n "$tokens" ] || return 0

  if [ ! -f "$sm" ] || [ ! -r "$sm" ]; then
    _ve_advise "ADVISORY_CROSS_REPO_ALLOWLIST_UNRESOLVED" "the entry cites a repo reference but the allowlist resolver '$sm' is missing or unreadable, so membership could not be examined — reported as unknown, not as clean, and not as a refusal"
    return 0
  fi
  if [ -z "$entries" ]; then
    _ve_advise "ADVISORY_CROSS_REPO_ALLOWLIST_UNRESOLVED" "the entry cites a repo reference but the allowlist resolved to nothing (no --allow, no LOOMWRIGHT_MEMORY_REPO_ALLOWLIST, no .supervisor/config.json entry, no git remote) — membership could not be examined, so this is neither a pass nor a refusal but an unknown, reported as one"
    return 0
  fi

  # Membership sets, lowercased: full slugs, and each slug's short (repo) name.
  local allow_slugs allow_shorts e le shown
  allow_slugs=" "; allow_shorts=" "
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    le="$(printf '%s' "$e" | tr '[:upper:]' '[:lower:]')"
    allow_slugs="$allow_slugs$le "
    allow_shorts="$allow_shorts${le##*/} "
  done <<EOF
$entries
EOF
  shown="$(printf '%s' "$entries" | tr '\n' ' ')"

  # EVERY foreign token is reported, not just the first — same reason as the dead-reference loop.
  local t kind name
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    kind="${t%%:*}"; name="${t#*:}"
    case "$kind" in
      slug)
        _ve_in_list "$name" "$allow_slugs" && continue
        _ve_advise "ADVISORY_CROSS_REPO" "the entry cites '$name', a repository outside this repo's allowlist ($shown). NOTE: this check recognises only a MARKED 'owner/repo' slug (marked by a github.com URL or a '#123'/'@sha'/'.git' citation, by a neighbouring cue word such as 'in' or a trailing 'repo', by a known owner, or by slug-only structure such as a hyphen, digit or CamelCase) and an identifier-shaped 'NAME #123' citation; a repo named in any other shape — including a bare all-lowercase 'owner/repo' standing alone in prose, which is not separable from an English word pair such as 'budget/zone' — is invisible to it, so a clean verdict is not proof that no cross-repo reference is present." ;;
      short)
        _ve_in_list "$name" "$allow_shorts" && continue
        _ve_advise "ADVISORY_CROSS_REPO" "the entry cites '$name #...', a repository outside this repo's allowlist ($shown). NOTE: this check recognises only a MARKED 'owner/repo' slug (marked by a github.com URL or a '#123'/'@sha'/'.git' citation, by a neighbouring cue word such as 'in' or a trailing 'repo', by a known owner, or by slug-only structure such as a hyphen, digit or CamelCase) and an identifier-shaped 'NAME #123' citation; a repo named in any other shape — including a bare all-lowercase 'owner/repo' standing alone in prose, which is not separable from an English word pair such as 'budget/zone' — is invisible to it, so a clean verdict is not proof that no cross-repo reference is present." ;;
    esac
  done <<EOF
$tokens
EOF
  return 0
}

# ---- aggregate --------------------------------------------------------------
# Runs all five in a fixed order. The THREE BLOCKING checks run first and the FIRST non-zero verdict
# among them is returned, preserving the 1-vs-2 distinction. The TWO ADVISORY checks run after them
# and CANNOT reach the exit status. Sole writers call this rather than five checks each, so a writer
# cannot silently omit one — the per-writer mutation control then only has to prove the single call
# site exists.
#
# THE SEPARATION IS ENFORCED HERE, IN ONE PLACE, and not merely trusted to the two functions. Both
# of them already return 0 on every path, and the suite asserts that both statically and
# behaviourally — but "this long function contains no `return 1`" is a property a future edit can
# break silently, and if it broke, the failure would be an advisory finding blocking a write again:
# precisely the defect this change exists to remove. So the aggregate ABSORBS their status and, when
# it is non-zero, says so as an advisory naming validate-entry.sh as the defect. It never converts
# it back into a refusal.
#
# The advisory counters are reset at entry, so $VALIDATE_ENTRY_ADVISORY_COUNT read by the caller
# after this returns describes THIS entry and not the accumulated history of the process.
_ve_absorb_advisory_status() {
  [ "${2:-0}" -eq 0 ] && return 0
  _ve_advise "ADVISORY_INTERNAL_NONZERO" "the advisory check '${1:-?}' returned status ${2:-?}. Advisory checks never block a write, so the status was absorbed and the write was NOT refused — but a non-zero status from one of them is a DEFECT IN validate-entry.sh, not a finding about this entry, and should be reported as such"
  return 0
}
validate_entry_all() {
  local rc
  _ve_advisory_reset
  # --- the three BLOCKING checks: a non-zero verdict here is a refusal to write ---
  validate_duplicate "$@";            rc=$?; [ "$rc" -eq 0 ] || return "$rc"
  validate_contradiction "$@";        rc=$?; [ "$rc" -eq 0 ] || return "$rc"
  validate_provenance "$@";           rc=$?; [ "$rc" -eq 0 ] || return "$rc"
  # --- the two ADVISORY checks: reported, absorbed, never propagated ---
  validate_dead_reference "$@";       rc=$?; _ve_absorb_advisory_status dead-reference "$rc"
  validate_cross_repo_reference "$@"; rc=$?; _ve_absorb_advisory_status cross-repo "$rc"
  return 0
}

# The five names a sourcing writer's load guard must find (clause ii of the LOAD GUARD CONTRACT).
VALIDATE_ENTRY_FUNCTIONS="validate_contradiction validate_duplicate validate_provenance validate_dead_reference validate_cross_repo_reference"

# The value each writer's load guard compares against $VALIDATE_ENTRY_CONTRACT. It is assigned HERE
# rather than beside the sentinel because the executable block below reads it, and that block runs
# while the file is being executed top-to-bottom — an assignment after it would be unset at use.
# `/2` because two of the five checks stopped blocking; see THE CONTRACT SENTINEL in the header.
VALIDATE_ENTRY_CONTRACT_EXPECTED="validate-entry/2"

# ---- executable entry point -------------------------------------------------
# Only when run directly, never when sourced. `set -u` is scoped here so sourcing cannot change the
# caller's shell options; `pipefail` is deliberately NOT set (see the SHAPE note in the header).
_ve_usage() {
  awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$_VE_SELF"
}
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
  set -u
  _ve_cmd="${1:-}"
  [ $# -gt 0 ] && shift
  case "$_ve_cmd" in
    contract)       printf '%s\n' "$VALIDATE_ENTRY_CONTRACT_EXPECTED"; exit 0 ;;
    all)            validate_entry_all "$@"; exit $? ;;
    duplicate)      validate_duplicate "$@"; exit $? ;;
    contradiction)  validate_contradiction "$@"; exit $? ;;
    provenance)     validate_provenance "$@"; exit $? ;;
    dead-reference) validate_dead_reference "$@"; exit $? ;;
    cross-repo)     validate_cross_repo_reference "$@"; exit $? ;;
    -h|--help|"")   _ve_usage; exit 0 ;;
    *)              printf 'validate-entry: unknown check %s (try --help)\n' "$_ve_cmd" >&2; exit 2 ;;
  esac
fi

# ---- SENTINEL — MUST REMAIN THE LAST LINE OF THIS FILE ----------------------
# Clause (iii) of the LOAD GUARD CONTRACT. Bash defines every function ABOVE a syntax error before
# it aborts the parse, so a truncated helper leaves a writer holding SOME validators. Because this
# assignment is last, a truncated file can never produce a matching sentinel and the writer's guard
# refuses instead of validating with half a validator. Do not move it, and do not add lines below it.
VALIDATE_ENTRY_CONTRACT="validate-entry/2"
