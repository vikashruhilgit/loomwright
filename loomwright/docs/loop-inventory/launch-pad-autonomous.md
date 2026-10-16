# Loop inventory — launch-pad-autonomous

This file lists every branch (condition → action) and every standing rule stated in the Launch Pad and `/autonomous` loop prose — one row per `###`/`####` heading outside fenced code blocks, plus one row per list item that states a branch or a rule — so that a later change which moves or deletes prose cannot silently drop an edge case. It restates the prose on purpose; `loomwright/scripts/test-loop-inventory.sh` keeps it in sync (heading coverage, live anchors, real script subcommands, existing test files, unique ids, and the gap list and counts below, which are computed from the table and never hand-maintained). Every `home` is `prose` today; later automate-speed items move rows out.

## Sources
- `agents/launch-pad.md`
- `commands/launch-pad.md`
- `skills/autonomous-loop/SKILL.md`
- `commands/autonomous.md`

## Inventory

| id | file | anchor | condition | action | kind | home | implemented by | test |
|----|------|--------|-----------|--------|------|------|----------------|------|
| LP-001 | agents/launch-pad.md | h: ### Core Principles | every Launch Pad run | the plan-first principles below govern every phase | rule | prose | - | GAP |
| LP-002 | agents/launch-pad.md | q: **Plan, don't execute:** Never invoke Supervisor | always | save the brief to a file; the user starts Supervisor in a fresh session | rule | prose | - | GAP |
| LP-003 | agents/launch-pad.md | q: **Conservative parallelism:** Only mark subtasks LAUNCHABLE | a subtask is not genuinely independent (file overlap) | do not mark it LAUNCHABLE | rule | prose | - | GAP |
| LP-004 | agents/launch-pad.md | q: **Honest estimation:** Assign confidence levels | every file prediction | assign a HIGH/MEDIUM/LOW confidence | rule | prose | - | GAP |
| LP-005 | agents/launch-pad.md | q: **Verify everything:** Confirm every file path exists | a path is about to enter the impact map | confirm it exists first | rule | prose | - | GAP |
| LP-006 | agents/launch-pad.md | q: **Interactive refinement:** Always present brief for user review | before saving | present the brief for user review | rule | prose | - | GAP |
| LP-007 | agents/launch-pad.md | q: **Lightweight:** Minimal subagent spawning | spawning subagents | spawn only the one targeted Plan Reviewer | rule | prose | - | GAP |
| LP-008 | agents/launch-pad.md | h: ### Inputs | a run starts | goal / requirement file / CLAUDE.md / git state / flags are the inputs (enumeration) | story | prose | - | GAP |
| LP-009 | agents/launch-pad.md | q: **Requirement file (optional):** When the | the goal value is an existing .md path under .supervisor/requirements/ | read that file as the requirement source; any path outside that directory stays a literal goal | deterministic | prose | - | GAP |
| LP-010 | agents/launch-pad.md | h: ### Outputs | a run completes | brief file + /supervisor command + environment report (enumeration) | story | prose | - | GAP |
| LP-011 | agents/launch-pad.md | h: ### Critical Rules | every run | the critical rules below apply across all phases | rule | prose | - | GAP |
| LP-012 | agents/launch-pad.md | q: **Never invoke Supervisor** — saves to file | always | save to file; never invoke Supervisor | rule | prose | - | GAP |
| LP-013 | agents/launch-pad.md | q: **Conservative parallelism** — only LAUNCHABLE if genuinely independent | subtask not genuinely independent | not LAUNCHABLE | rule | prose | - | GAP |
| LP-014 | agents/launch-pad.md | q: **Honest estimation** — confidence levels on file predictions | every file prediction | carry a confidence level | rule | prose | - | GAP |
| LP-015 | agents/launch-pad.md | q: **Verify every file path** exists before including in impact map | a path enters the impact map | verify it exists | rule | prose | - | GAP |
| LP-016 | agents/launch-pad.md | q: **If environment has blockers:** output fix instructions | Phase 1 reports a BLOCKER | output fix instructions; do not offer save | deterministic | prose | - | GAP |
| LP-017 | agents/launch-pad.md | q: for requirement clarification | clarification is needed | ask at most 2 question rounds (Max 2 rounds) | rule | prose | - | GAP |
| LP-018 | agents/launch-pad.md | q: **Can't-ask rule:** this run cannot ask when | --non-interactive / --non-interactive-fallback set, or running as a subagent (never a TTY probe alone) | every question gate takes its named can't-ask status branch, never improvises | deterministic | prose | - | test-non-interactive-gates-seam.sh |
| LP-019 | agents/launch-pad.md | q: Each named status rides in `LAUNCH_PAD_RESULT.summary` as its leading token | a can't-ask status is emitted | put it as the summary's leading token, never a new key (the key set is closed; the validator blocks unknown keys) | deterministic | prose | script:validate-launch-pad-result.py | GAP |
| LP-020 | agents/launch-pad.md | q: **Mandatory plan review** — Phase 5.5 is non-skippable | Plan Review verdict | PASS enables save; NEEDS_HUMAN only with explicit user override; FAIL never | deterministic | prose | - | GAP |
| LP-021 | agents/launch-pad.md | q: **Feasibility gate (Phase 2.5)** — soft gate | feasibility verdict | NO-GO stops the pipeline (user may override); CAUTION feeds Risk Assessment | deterministic | prose | - | GAP |
| LP-022 | agents/launch-pad.md | h: ### Phase 1: VALIDATE (Environment Readiness) | start of run (unless --skip-validation) | run the environment checks and report blockers vs warnings | deterministic | prose | - | GAP |
| LP-023 | agents/launch-pad.md | q: **BLOCKER** (must fix before proceeding): Dirty git state with conflicts, missing CLAUDE.md | conflicted dirty tree or missing CLAUDE.md | classify as BLOCKER; must fix before proceeding | deterministic | prose | - | GAP |
| LP-024 | agents/launch-pad.md | q: **WARNING** (can proceed): Dirty git state (uncommitted changes) | uncommitted changes / no gh auth / orphaned worktrees / stale CLAUDE.md | classify as WARNING; proceed | deterministic | prose | - | GAP |
| LP-025 | agents/launch-pad.md | q: **Source-doc provenance check (advisory, trigger-gated):** | input resolves to a specific source doc that is modified or untracked | emit a WARNING (never a BLOCKER) scoped to that one file; otherwise skip silently | deterministic | prose | - | GAP |
| LP-026 | agents/launch-pad.md | q: **Shared local services check (optional, host-CLAUDE.md-gated):** | host CLAUDE.md has a level-2 Shared local services heading whose bounded body is non-empty | hold the bounded one-line body as shared_local_services; absent or zero lines leaves it unset, never empty | deterministic | prose | - | GAP |
| LP-027 | agents/launch-pad.md | q: **Skip condition:** If `--skip-validation` flag is set, skip to Phase 2 | --skip-validation set | skip to Phase 2 and report skipped | deterministic | prose | - | GAP |
| LP-028 | agents/launch-pad.md | h: ### Phase 2: DISCOVER (Requirement Refinement) | after VALIDATE | refine the requirement into acceptance criteria; the section names its can't-ask status | deterministic | prose | - | test-non-interactive-gates-seam.sh |
| LP-029 | agents/launch-pad.md | q: **Resolve requirement-file input (do FIRST):** | goal value is a .md path under .supervisor/requirements/ that passes test -f (relative to project root) | read it as the requirement source, carry forward its AC, record source_requirement; any other value is a literal goal | deterministic | prose | - | GAP |
| LP-030 | agents/launch-pad.md | q: If the file resolves but is empty or clearly not a requirement/story, stop and ask | resolved requirement file is empty or not a story | stop and ask rather than plan from it | judgment | prose | - | GAP |
| LP-031 | agents/launch-pad.md | q: path that fails `test -f` falls back to literal-string handling and is noted | a .supervisor/requirements/ path fails test -f | fall back to literal-string handling and note it; never invent a file | deterministic | prose | - | GAP |
| LP-032 | agents/launch-pad.md | q: If goal is vague (no clear outcome or acceptance criteria) | goal is vague and no requirement file supplied criteria | apply product discovery and ask (max 2 rounds); cannot ask ⇒ status aborted, clarification_needed_non_interactive | judgment | prose | - | test-non-interactive-gates-seam.sh |
| LP-033 | agents/launch-pad.md | q: If goal is clear (specific outcome described, or a requirement file was read) | goal is clear or a requirement file was read | extract acceptance criteria directly | judgment | prose | - | GAP |
| LP-034 | agents/launch-pad.md | q: A criterion whose evidence would live in the PR body | a criterion's evidence would live in the PR body | write it in evidence-file form; its docs/evidence file joins the File Impact Map as a create (Criterion 20 FAILs otherwise) | rule | prose | - | test-pr-body-evidence-seam.sh |
| LP-035 | agents/launch-pad.md | q: If `--discovery` flag is set: force full product discovery | --discovery set | force full product discovery even for a clear goal | deterministic | prose | - | GAP |
| LP-036 | agents/launch-pad.md | h: ### Phase 2.5: FEASIBILITY (Soft Gate) | after DISCOVER | run the five feasibility checks; the section names its can't-ask status | deterministic | prose | - | test-non-interactive-gates-seam.sh |
| LP-037 | agents/launch-pad.md | q: **Tech Stack Compatibility** — Parse CLAUDE.md tech stack | goal needs a different stack / a major new dependency | NO-GO / CAUTION | judgment | prose | - | GAP |
| LP-038 | agents/launch-pad.md | q: **Dependency Availability** — Check if external libraries/services | required dependency deprecated or nonexistent / new dependencies needed | NO-GO / CAUTION | judgment | prose | - | GAP |
| LP-039 | agents/launch-pad.md | q: **Architecture Fit** — From CLAUDE.md, identify architecture pattern | goal contradicts / stretches the architecture | NO-GO / CAUTION | judgment | prose | - | GAP |
| LP-040 | agents/launch-pad.md | q: **Scope vs Supervisor Capability** — Does the goal fit the single-agent default | too large even under a justified split / borderline | NO-GO / CAUTION (needs a stated split reason) | judgment | prose | - | GAP |
| LP-041 | agents/launch-pad.md | q: **Hard Blockers** — Check for showstoppers | hard blocker found / potential blocker the user might resolve | NO-GO / CAUTION | judgment | prose | - | GAP |
| LP-042 | agents/launch-pad.md | q: Any check NO-GO → overall **NO-GO** | any check is NO-GO | overall verdict NO-GO | deterministic | prose | - | GAP |
| LP-043 | agents/launch-pad.md | q: Any check CAUTION (no NO-GO) → overall **CAUTION** | some CAUTION, no NO-GO | overall verdict CAUTION | deterministic | prose | - | GAP |
| LP-044 | agents/launch-pad.md | q: All GO → overall **GO** | all checks GO | overall verdict GO | deterministic | prose | - | GAP |
| LP-045 | agents/launch-pad.md | q: **GO:** Proceed to Phase 3 silently | verdict GO | proceed to Phase 3 silently | deterministic | prose | - | GAP |
| LP-046 | agents/launch-pad.md | q: **CAUTION:** Proceed to Phase 3. Findings auto-injected into Risk Assessment | verdict CAUTION | proceed; inject findings into Risk Assessment sourced "Feasibility (Phase 2.5)" | deterministic | prose | - | GAP |
| LP-047 | agents/launch-pad.md | q: **NO-GO:** Stop pipeline. | verdict NO-GO | stop and ask with three options | deterministic | prose | - | GAP |
| LP-048 | agents/launch-pad.md | q: **"Override and continue"** → proceed to Phase 3 | user picks Override | proceed; NO-GO findings become HIGH risks in Phase 5 | deterministic | prose | - | GAP |
| LP-049 | agents/launch-pad.md | q: **"Revise goal"** → loop back to Phase 2 DISCOVER (max 1 revision) | user picks Revise goal | loop back to Phase 2 at most once | deterministic | prose | - | GAP |
| LP-050 | agents/launch-pad.md | q: **"Abort"** → exit Launch Pad | user picks Abort | exit Launch Pad | deterministic | prose | - | GAP |
| LP-051 | agents/launch-pad.md | q: **Cannot ask** (Can't-ask rule) → no option is auto-picked | NO-GO and the run cannot ask | pick no option; status aborted, no_go_non_interactive, findings in output | deterministic | prose | - | test-non-interactive-gates-seam.sh |
| LP-052 | agents/launch-pad.md | q: **Fallback:** If CLAUDE.md is sparse/missing tech stack info | CLAUDE.md lacks tech-stack info | checks 1-3 default to CAUTION (not NO-GO) noting insufficient context | deterministic | prose | - | GAP |
| LP-053 | agents/launch-pad.md | h: ### Phase 3: ANALYZE (Codebase Impact Estimation) | after FEASIBILITY (GO, CAUTION, or overridden NO-GO) | estimate the File Impact Map, overlap, skills, confidence and the advisory reads below | deterministic | prose | - | GAP |
| LP-054 | agents/launch-pad.md | q: **Consult project memory (advisory, v14.3.0):** | always | run read-project-memory.sh and fold facts in, subordinate to CLAUDE.md; nothing emitted ⇒ proceed normally | deterministic | prose | script:read-project-memory.sh | test-project-memory.sh |
| LP-055 | agents/launch-pad.md | q: **Consult verified lessons (advisory):** | always | run read-lessons.sh, keep only relevant categories; never blocks or changes a verdict; may be cited in Risk Assessment | deterministic | prose | script:read-lessons.sh | test-read-lessons.sh |
| LP-056 | agents/launch-pad.md | q: **Consult the prior-churn ledger (advisory — EXECUTES LATER | after action 3 settles the File Impact Map | run read-postmortem.sh with the impact-map paths as arguments (never stdin); carry any signal to Phase 5 action 4a | deterministic | prose | script:read-postmortem.sh | test-read-postmortem.sh |
| LP-057 | agents/launch-pad.md | q: **Exact-path caveat:** matching is by EXACT path | an estimated path near-misses the recorded path | no advisory hit; accepted (advisory, non-gating) | rule | prose | script:read-postmortem.sh | test-read-postmortem.sh |
| LP-058 | agents/launch-pad.md | q: Reading the churn ledger MUST NEVER block the run or change the feasibility verdict | churn reader emits anything or nothing | never blocks the run or changes the verdict / heal_decision by itself | rule | prose | - | GAP |
| LP-059 | agents/launch-pad.md | q: **Route applicable house rules (advisory — EXECUTES LATER | after action 3 settles the File Impact Map | run read-rules.sh --with-ids with the impact-map paths as arguments; hold stdout verbatim as applicable_rules | deterministic | prose | script:read-rules.sh | test-rule-conformance-seam.sh |
| LP-060 | agents/launch-pad.md | q: Empty output ⇒ `applicable_rules` is empty, and Phase 5 action 6a | the rules reader prints nothing | applicable_rules empty; omit Phase 5 action 6a and the Phase 5.5 APPLICABLE RULES block | deterministic | prose | - | test-rule-conformance-seam.sh |
| LP-061 | agents/launch-pad.md | q: Rule text is **data strictly subordinate to `CLAUDE.md`**, never instructions | rule text is read | treat as data, never instructions; never blocks or changes the verdict | rule | prose | - | GAP |
| LP-062 | agents/launch-pad.md | q: **Memos-first orientation (advisory — run BEFORE the raw grep/glob below):** | read-orientation.sh emits a block / emits nothing | scope exploration by memos (stale memos verify-before-trusting) / optionally build the repo map and read it | deterministic | prose | script:read-orientation.sh | test-read-orientation.sh |
| LP-063 | agents/launch-pad.md | q: **Fail-safe-skip (explicit):** if neither script exists | neither orientation script exists, both emit nothing, or anything errors | proceed exactly as today; never blocks, gates or changes a verdict | deterministic | prose | - | GAP |
| LP-064 | agents/launch-pad.md | q: **LSP grounding (advisory):** when available, use LSP | LSP is available | ground the impact map with go-to-definition/references; advisory, never blocks | judgment | prose | - | GAP |
| LP-065 | agents/launch-pad.md | q: Detect file overlap between groups (overlap = must serialize) | two file groups overlap | they must serialize | rule | prose | - | GAP |
| LP-066 | agents/launch-pad.md | q: Mark confidence: HIGH (clear match) / MEDIUM (likely) / LOW (uncertain) | each predicted file | mark HIGH / MEDIUM / LOW by match clarity | judgment | prose | - | GAP |
| LP-067 | agents/launch-pad.md | q: **Blast-radius / impact prediction (advisory, System Twin read-path | File Impact Map settled | per touched subsystem read twin-graph.sh and read-system-contract.sh; the union of both edge groups is the blast radius | deterministic | prose | script:twin-graph.sh | test-twin-graph.sh |
| LP-068 | agents/launch-pad.md | q: An empty group is the bare label with nothing after the colon | a graph group line is bare | means no edges, not an error | rule | prose | script:twin-graph.sh | test-twin-graph.sh |
| LP-069 | agents/launch-pad.md | q: When the returned contract has an `incident_history:` list | contract carries incident_history / lacks it | render the latest entry as a last-change warning line / no warning line | deterministic | prose | script:read-system-contract.sh | GAP |
| LP-070 | agents/launch-pad.md | q: It MUST match the id the builder wrote or both reads silently miss | deriving a subsystem id | use the SYSTEM_CONTRACT id convention verbatim; never abbreviate | rule | prose | - | GAP |
| LP-071 | agents/launch-pad.md | q: **Graceful fallback (REQUIRED):** when a subsystem has NO verified contract | no verified contract and both graph groups empty | omit the Blast-Radius subsection entirely; emit it only with ≥1 contract or edge | deterministic | prose | - | GAP |
| LP-072 | agents/launch-pad.md | q: It **never blocks, gates, or serializes** anything | blast-radius prediction exists | advisory only; never blocks, gates or serializes | rule | prose | - | GAP |
| LP-073 | agents/launch-pad.md | q: **Validator-owned-surfaces check (trigger-gated):** | a task's acceptance depends on a generated/mechanical validation script | add its scanned files to the map, or a may-need-updates note; otherwise skip silently; never trigger by hard-coded filename | judgment | prose | - | GAP |
| LP-074 | agents/launch-pad.md | q: **Cited-line premise check (advisory, harness-port/03 | the goal / requirement cites path:line refs | resolve against origin/$BASE_BRANCH and judge HOLDS / STALE / UNCLEAR; never changes a verdict; edits mirror preflight-sync signal (d) | judgment | prose | - | GAP |
| LP-075 | agents/launch-pad.md | q: **Reference extraction:** a ref is a token matching | a token is path:digits with a slash or .ext left side | extract it (range uses first line), strip trailing punctuation, dedupe; domain:port is an accepted false positive | deterministic | prose | - | GAP |
| LP-076 | agents/launch-pad.md | q: **if that direct lookup fails** (not gated on whether | direct git show lookup fails | resolve by unique suffix match; zero or many ⇒ resolves no, premise UNCLEAR; phrase found elsewhere ⇒ HOLDS (moved), never STALE | deterministic | prose | - | GAP |
| LP-077 | agents/launch-pad.md | q: **Judgment** (made by you, the running model, from the excerpt alone | excerpt read | HOLDS if present; STALE if absent and the phrase search finds nothing; UNCLEAR otherwise | judgment | prose | - | GAP |
| LP-078 | agents/launch-pad.md | q: **Honest age column (decision H6):** | computing the as-of column | FETCH_HEAD absent ⇒ never, else find -mmin buckets; check existence first; resolve via git-common-dir; no network call | deterministic | prose | - | GAP |
| LP-079 | agents/launch-pad.md | q: **Emission:** when ≥1 ref is found, emit `### Cited-line premise check` | ≥1 ref / 0 refs | one table row per ref and one MEDIUM risk row per STALE ref / emit nothing at all | deterministic | prose | - | GAP |
| LP-080 | agents/launch-pad.md | q: **Touched-file invariants (conditional — whenever the File Impact Map modifies ≥1 existing script):** | the map modifies ≥1 existing script / only creates or non-script edits | read each and record keep/reuse/mirror/fired-by/pinned-by literals / skip silently | judgment | prose | - | test-rule-conformance-seam.sh |
| LP-081 | agents/launch-pad.md | q: **Closed enumerations and pin mutations (conditional):** | the change adds an enum/status/reason value, or adds/changes test pins | grep a sibling value repo-wide and add closed lists to the map; write one mutation per pin; neither ⇒ skip | judgment | prose | - | test-closed-enum-pins-seam.sh |
| LP-082 | agents/launch-pad.md | h: ### Phase 4: DECOMPOSE (Subtask Structure) | after ANALYZE | default to one subtask; split only on a named threshold reason | judgment | prose | - | GAP |
| LP-083 | agents/launch-pad.md | q: **Subtask id scheme (RULE):** number subtasks **plain numeric, 1-based, sequential** | numbering subtasks | plain numeric 1-based sequential ids in the table and every from: reference; never alpha-suffixed | rule | prose | - | GAP |
| LP-084 | agents/launch-pad.md | q: Default to a single subtask whose acceptance criteria are the **checklist for one worker** | a threshold reason fires / none fires | split that group off and record the Split reason in Configuration / keep one subtask, no Split reason line | judgment | prose | - | GAP |
| LP-085 | agents/launch-pad.md | q: derive these from `requires` entries, not free-form prose | analyzing dependencies | derive them from requires entries only | rule | prose | - | GAP |
| LP-086 | agents/launch-pad.md | q: **LAUNCHABLE:** Empty `requires` + no file overlap with other LAUNCHABLE subtasks | empty requires and no overlap | mark LAUNCHABLE | deterministic | prose | - | GAP |
| LP-087 | agents/launch-pad.md | q: **BLOCKED:** Non-empty `requires`, OR file overlap with a LAUNCHABLE subtask | non-empty requires or overlap with a LAUNCHABLE subtask | mark BLOCKED | deterministic | prose | - | GAP |
| LP-088 | agents/launch-pad.md | q: single-subtask brief: 1 batch, 1 worker | brief has a single subtask | 1 batch, 1 worker | deterministic | prose | - | GAP |
| LP-089 | agents/launch-pad.md | h: #### Provides / Requires / External Requires / Lanes Schema | every subtask | declare provides / requires / external_requires / lanes lists (Plan Reviewer Criteria 12 and 16) | rule | prose | - | test-verify-provides.sh |
| LP-090 | agents/launch-pad.md | q: **Anchor every contract block with `# Subtask N`** | writing a contract block | anchor with # Subtask N, ### Subtask N or subtask_N:; never a slug key (checked at Phase 5.5 action 1b) | deterministic | prose | script:verify-provides.sh | test-verify-provides.sh |
| LP-091 | agents/launch-pad.md | q: Purely-deletion subtasks may use `provides: []` but MUST include a justification comment | a subtask is purely deletion | provides: [] with a justification comment on the line above | rule | prose | - | GAP |
| LP-092 | agents/launch-pad.md | q: Reject vague provides like `"adds feature"` or `"updates code"` | a provides entry is vague | reject; every entry is an addressable kind/path/name | rule | prose | - | GAP |
| LP-093 | agents/launch-pad.md | q: `external_requires` is for things outside the brief's scope; do NOT cross-reference it from `requires` | an outside-scope dependency | list it in external_requires; requires.from always names a sibling subtask | rule | prose | - | GAP |
| LP-094 | agents/launch-pad.md | q: A subtask with non-empty `requires` is BLOCKED. | requires is non-empty | show it BLOCKED by its requires.from producers, never LAUNCHABLE | deterministic | prose | - | GAP |
| LP-095 | agents/launch-pad.md | q: Every subtask MUST also declare `lanes:` (non-empty | every subtask | declare non-empty lanes (same []-with-justification exception) | rule | prose | - | GAP |
| LP-096 | agents/launch-pad.md | h: ### Phase 5: PACKAGE (Assemble Brief) | after DECOMPOSE | assemble the Supervisor-Ready Brief from Phases 1-4 | deterministic | prose | - | GAP |
| LP-097 | agents/launch-pad.md | q: **Source-requirement provenance (conditional):** If a `source_requirement` path was resolved | source_requirement resolved / not resolved | emit the Source requirement Environment line / omit it, no placeholder | deterministic | prose | - | GAP |
| LP-098 | agents/launch-pad.md | q: **Base-commit freshness anchor (unconditional, v15.19.0 — 4g(a)):** | every brief | emit a Base commit line with git rev-parse HEAD inside Environment | deterministic | prose | - | GAP |
| LP-099 | agents/launch-pad.md | q: A brief written before this change simply has no `Base commit` line | the brief has no Base commit line | preflight signal (c) degrades silently; never fails brief assembly | deterministic | prose | - | GAP |
| LP-100 | agents/launch-pad.md | q: **Shared local services (conditional, from Phase 1 action 8):** When `shared_local_services` was set | shared_local_services set / unset | emit the Shared local services line after Base commit / omit it, no placeholder | deterministic | prose | - | GAP |
| LP-101 | agents/launch-pad.md | q: **Home-path rule (scrub-safe briefs | an absolute home path appears anywhere in the brief | write Project home-relative and every home path with a placeholder, or the meta-sync home_path scrub blocks the trail push | rule | prose | - | GAP |
| LP-102 | agents/launch-pad.md | q: For each CAUTION finding from Phase 2.5, add a Risk Assessment row | a CAUTION finding / an overridden NO-GO | add a MEDIUM row (HIGH if scope-related) / every NO-GO finding becomes a HIGH risk | deterministic | prose | - | GAP |
| LP-103 | agents/launch-pad.md | q: **Prior-churn risk row (conditional, from the Phase 3 churn consult — action 0b).** | churn surfaced on a touched path / nothing surfaced | add a Prior churn row (HIGH on a recurred self_heal_miss, else MEDIUM or LOW) / no row; never changes the verdict | deterministic | prose | - | GAP |
| LP-104 | agents/launch-pad.md | q: **Cited-line premise risk row (conditional, from the Phase 3 cited-line premise check — action 10).** | ≥1 STALE ref / none | one MEDIUM row per STALE ref / no row; never changes the verdict | deterministic | prose | - | GAP |
| LP-105 | agents/launch-pad.md | q: **Touched-file invariants (conditional, from Phase 3 action 11):** emit | action 11 ran / skipped | emit the section before Subtask Structure stamped with Base commit / emit nothing | deterministic | prose | - | test-rule-conformance-seam.sh |
| LP-106 | agents/launch-pad.md | q: **Closed enumerations / pin mutations (conditional, from Phase 3 action 12):** | action 12 produced either section | emit it after Touched-file invariants and before Subtask Structure | deterministic | prose | - | test-closed-enum-pins-seam.sh |
| LP-107 | agents/launch-pad.md | q: If Phase 2.5 ran, include a `## Feasibility` section | Phase 2.5 ran | include the Feasibility section (verdict + checks table) | deterministic | prose | - | GAP |
| LP-108 | agents/launch-pad.md | q: **NEVER emit `cmd:` / bare-shell bullets** | machine-authoring Executable Acceptance | emit corpus-task: bullets only; cmd: is reserved for humans (Criterion 14 flags it) | rule | prose | - | GAP |
| LP-109 | agents/launch-pad.md | q: **Affirmative rule (v14.21.0)** — emit the section when BOTH conditions hold | target is this plugin's repo AND the brief modifies the plugin doc surface / otherwise | emit corpus-task doc-currency-green + version-consistent / omit unless a bundled corpus-task genuinely matches | deterministic | prose | - | GAP |
| LP-110 | agents/launch-pad.md | q: **House Rules + `rule:` bullets (conditional, from Phase 3 action 0c).** | applicable_rules non-empty | emit a House Rules section with the reader banner demoted to a blockquote | deterministic | prose | - | test-rule-conformance-seam.sh |
| LP-111 | agents/launch-pad.md | q: For every `enforcement: must` rule in the block whose `check` is not `(none)` | a must rule with a check | emit a rule: bullet in Executable Acceptance; never relaxes the cmd: prohibition | deterministic | prose | - | test-rule-conformance-seam.sh |
| LP-112 | agents/launch-pad.md | q: When `applicable_rules` is empty, emit NEITHER | applicable_rules empty | emit neither section nor bullets; brief byte-identical to a rules-free one | deterministic | prose | - | test-rule-conformance-seam.sh |
| LP-113 | agents/launch-pad.md | q: when the `source_requirement` carries a `## Rule conflicts (open decisions)` section | the source requirement carries Rule conflicts | copy it verbatim after House Rules; never author a Rule override line here | deterministic | prose | - | test-rule-conformance-seam.sh |
| LP-114 | agents/launch-pad.md | q: **Outcomes Rubric auto-authoring (guarded — fires ONLY on the `/autonomous` producer seam).** | /autonomous inline directive requests authoring (multi-iteration, requirement lacks a rubric) / any other invocation | derive 3-7 diff-checkable bullets into an Outcomes Rubric section / no-op | judgment | prose | - | test-non-interactive-gates-seam.sh |
| LP-115 | agents/launch-pad.md | q: **Never when this run cannot ask** (Can't-ask rule | the run cannot ask | no-op even if asked; run takes the no_rubric_in_non_interactive gate | deterministic | prose | - | test-non-interactive-gates-seam.sh |
| LP-116 | agents/launch-pad.md | q: **Fallback:** if fewer than 3 diff-checkable bullets are derivable | fewer than 3 bullets derivable | emit no rubric section; note the no-rubric gate | deterministic | prose | - | GAP |
| LP-117 | agents/launch-pad.md | q: **MATERIALIZE — scratch file + context digest (unconditional, v15.20.0 — D6).** | brief assembled (regardless of later Plan Review) | serialize the brief to a scratch file and build the context digest under the shared basename | deterministic | prose | script:build-context-digest.sh | test-context-digest.sh |
| LP-118 | agents/launch-pad.md | q: **MATERIALIZE is IDEMPOTENT and RE-RUNNABLE, and it is the ONLY step that writes either artifact.** | any revision after this point (5.5 retry, Phase 6 refine or edit) | re-run MATERIALIZE before re-review or save | rule | prose | - | GAP |
| LP-119 | agents/launch-pad.md | q: Compute the job's basename exactly as Phase 6 will | naming the digest | use the same date-slug basename as the eventual brief | rule | prose | - | GAP |
| LP-120 | agents/launch-pad.md | q: if it reports a write failure, proceed with brief assembly regardless | digest builder reports a write failure | proceed; a missing digest never blocks Plan Review or save | deterministic | prose | script:build-context-digest.sh | test-context-digest.sh |
| LP-121 | agents/launch-pad.md | h: ### Phase 5.5: PLAN REVIEW (Mandatory Gate) | brief assembled | spawn the Plan Reviewer (max 3 spawns) and branch on its decision; the section names its can't-ask status | deterministic | prose | - | test-non-interactive-gates-seam.sh |
| LP-122 | agents/launch-pad.md | q: Reuse the scratch file **as last written by Phase 5 step 9 MATERIALIZE** | scratch file present / missing | review the scratch file as MATERIALIZE last wrote it (never re-assemble) / serialize the brief inline as a fallback | deterministic | prose | - | GAP |
| LP-123 | agents/launch-pad.md | q: **Gate-parse check (mechanical, before every spawn):** | a parse line is unverifiable, shows provides_count 0 for a listed block, or carries parse_warnings | fix the anchor or quoting, re-run MATERIALIZE, re-check; paste the final lines into the GATE PARSE block | deterministic | prose | script:verify-provides.sh | test-verify-provides.sh |
| LP-124 | agents/launch-pad.md | q: a pre-spawn fix consumes no review attempt | a gate-parse fix before spawning | consumes no Plan Review attempt | rule | prose | - | GAP |
| LP-125 | agents/launch-pad.md | q: **Fix floor (once, before the first spawn):** | before the first spawn / the resolver exits 2 | resolve the floor (flag > config > MEDIUM) / stop, save nothing, aborted with fix_floor_invalid | deterministic | prose | script:fix-floor.sh resolve | test-fix-floor.sh |
| LP-126 | agents/launch-pad.md | q: **PASS carrying an issue at the fix floor (attempt < 3):** | PASS with an at-floor issue (not an executable_acceptance visibility finding) and attempt < 3 | refine it like a FAIL issue, re-run MATERIALIZE, re-spawn (consumes an attempt) on both paths | deterministic | prose | script:fix-floor.sh meets | GAP |
| LP-127 | agents/launch-pad.md | q: **PASS** (no issue at the floor, or attempt = 3): Proceed to Phase 6 | PASS with no at-floor issue, or attempt = 3 | proceed to Phase 6 with save enabled; a still-open at-floor issue is listed deferred and never blocks | deterministic | prose | - | GAP |
| LP-128 | agents/launch-pad.md | q: **FAIL (attempt < 3):** Fix issues identified in the review | FAIL and attempt < 3 | fix, re-assemble, re-spawn; 17c fixed by honoring the rule, Criterion 20 by rewriting to evidence-file form, never deleting | deterministic | prose | - | test-pr-body-evidence-seam.sh |
| LP-129 | agents/launch-pad.md | q: **FAIL (attempt = 3):** Present all unresolved issues to user | FAIL and attempt = 3 | offer Refine offline (blocked) or Discard; never save; the 3-spawn cap is never reset | deterministic | prose | - | GAP |
| LP-130 | agents/launch-pad.md | q: **NEEDS_HUMAN:** Proceed to Phase 6, which branches on WHY | NEEDS_HUMAN | Criterion 14 ⇒ action 2a; 17c ⇒ action 2b; other ⇒ generic prompt or needs_human_non_interactive | deterministic | prose | - | test-rule-conformance-seam.sh |
| LP-131 | agents/launch-pad.md | h: ### Phase 6: REFINE & SAVE (Interactive) | Plan Review allowed save (PASS, or NEEDS_HUMAN with override) | present, refine and save the brief; the section names every Phase 6 can't-ask status | deterministic | prose | - | test-non-interactive-gates-seam.sh |
| LP-132 | agents/launch-pad.md | q: **first check whether the escalation is (at least in part) a Criterion 14 `executable_acceptance` issue** | NEEDS_HUMAN carries an executable_acceptance issue / a 17c issue / neither | action 2a / action 2b (after 2a when both) / generic 3-option prompt | deterministic | prose | - | GAP |
| LP-133 | agents/launch-pad.md | q: **"Override and save"** — User acknowledges warnings and takes responsibility | user picks Override and save | write the brief to pending/ with a NEEDS_HUMAN (user override) section | deterministic | prose | - | GAP |
| LP-134 | agents/launch-pad.md | q: **"Refine further"** — Loop back to fix issues, **re-run Phase 5 step 9 MATERIALIZE** | user picks Refine further on NEEDS_HUMAN | fix, re-run MATERIALIZE, re-run Plan Review | deterministic | prose | - | GAP |
| LP-135 | agents/launch-pad.md | q: **"Discard"** — Cancel without saving | user picks Discard | cancel without saving | deterministic | prose | - | GAP |
| LP-136 | agents/launch-pad.md | q: **Non-interactive fallback for the generic (non-`executable_acceptance`) NEEDS_HUMAN case:** | generic NEEDS_HUMAN and a non-interactive flag | abort: status aborted, needs_human_non_interactive; never auto-pick an option | deterministic | prose | - | test-non-interactive-gates-seam.sh |
| LP-137 | agents/launch-pad.md | q: **Executable Acceptance `cmd:`/bare-bullet NEEDS_HUMAN (Criterion 14, red-team-hardening item 05).** | a Criterion 14 executable_acceptance issue | quote the flagged bullets verbatim, never paraphrase | rule | prose | - | GAP |
| LP-138 | agents/launch-pad.md | q: quoting every flagged bullet verbatim in the question text | interactive run | ask with exactly three options: approve-and-stamp / strip-cmd-bullets / discard | deterministic | prose | - | GAP |
| LP-139 | agents/launch-pad.md | q: **`approve-and-stamp`** — compute the current stamp | user picks approve-and-stamp | write the Executable Acceptance Approved stamp into Configuration, re-run MATERIALIZE and Plan Review (consumes an attempt) | deterministic | prose | script:exec-acceptance-hash.sh | test-exec-acceptance-hash.sh |
| LP-140 | agents/launch-pad.md | q: **`strip-cmd-bullets`** — remove every flagged | user picks strip-cmd-bullets | remove flagged cmd:/bare bullets (keep corpus-task:/qa-executor:), re-run MATERIALIZE and Plan Review | deterministic | prose | - | GAP |
| LP-141 | agents/launch-pad.md | q: **`discard`** — Cancel without saving (`status: discarded`). | user picks discard (action 2a) | cancel without saving; status discarded | deterministic | prose | - | GAP |
| LP-142 | agents/launch-pad.md | q: and never proceed with an unreviewed executable brief — automatically strip | non-interactive run with a Criterion 14 issue | auto-strip the flagged bullets, re-run MATERIALIZE and Plan Review, record cmd_bullets_stripped_non_interactive | deterministic | prose | - | GAP |
| LP-143 | agents/launch-pad.md | q: **Idempotency / cap exhaustion:** both branches consume an attempt | the 3-spawn cap is exhausted | fall through to the FAIL x3 handling (action 4) rather than loop | deterministic | prose | - | GAP |
| LP-144 | agents/launch-pad.md | q: **House-rule override NEEDS_HUMAN (Criterion 17c, #432).** | a rule_conformance issue whose description starts 17c: | quote it verbatim and resolve per rule id | deterministic | prose | - | test-rule-conformance-seam.sh |
| LP-145 | agents/launch-pad.md | q: per flagged rule id, with no header code | interactive run | one human-only question (LP-RULE-OVR) per flagged id with three options | deterministic | prose | - | test-rule-conformance-seam.sh |
| LP-146 | agents/launch-pad.md | q: **`record-override`** — the answer's note is the owner's reason | owner picks record-override / note empty | write the Rule override line verbatim into Rule conflicts / record nothing and ask again | deterministic | prose | - | test-rule-conformance-seam.sh |
| LP-147 | agents/launch-pad.md | q: **`honor-rule`** — revise the contradicting AC, design or scope text | owner picks honor-rule | revise the brief so it honors the rule | deterministic | prose | - | test-rule-conformance-seam.sh |
| LP-148 | agents/launch-pad.md | q: **`discard`** — cancel without saving (`status: discarded`). | owner picks discard (action 2b) | cancel without saving; status discarded | deterministic | prose | - | test-rule-conformance-seam.sh |
| LP-149 | agents/launch-pad.md | q: After `record-override` or `honor-rule`, **re-run Phase 5 step 9 MATERIALIZE** | after record-override or honor-rule | re-run MATERIALIZE and Plan Review (consumes an attempt; exhausted cap ⇒ action 4) | deterministic | prose | - | GAP |
| LP-150 | agents/launch-pad.md | q: **Cannot ask** (Can't-ask rule): write no override and revise nothing | 17c conflict and the run cannot ask | write and revise nothing, save nothing; aborted, summary leads rule_conflict_non_interactive | deterministic | prose | - | test-rule-conformance-seam.sh |
| LP-151 | agents/launch-pad.md | q: **Never author an override.** A `Rule override:` line reaches the brief only | any refine loop | a Rule override line comes only from the source requirement or the owner's answer, never from FAIL/at-floor refine | rule | prose | - | test-rule-conformance-seam.sh |
| LP-152 | agents/launch-pad.md | q: If Plan Review returned PASS: use | PASS with zero issues / PASS with any issue or note | ask with header LP-SAVE / ask with no header code so a human always answers | deterministic | prose | script:lane-policy.sh | test-lane-policy.sh |
| LP-153 | agents/launch-pad.md | q: **"Save and exit"** — Write brief to `.supervisor/jobs/pending/{date}-{slug}.md` | user picks Save and exit | write the brief to pending/ and output the /supervisor job command | deterministic | prose | - | GAP |
| LP-154 | agents/launch-pad.md | q: **"Refine further"** — Ask clarifying questions, update sections | user picks Refine further on PASS | update, re-run MATERIALIZE, re-run Plan Review before save (the PASS is void once mutated) | deterministic | prose | - | GAP |
| LP-155 | agents/launch-pad.md | q: **"Edit sections"** — User specifies what to change | user picks Edit sections | edit in place, re-run MATERIALIZE, re-run Plan Review before save | deterministic | prose | - | GAP |
| LP-156 | agents/launch-pad.md | q: **Corner case:** if the PASS landed on the 3rd (final) spawn | PASS on the 3rd spawn | offer only Save and exit (unmutated) or Discard | deterministic | prose | - | GAP |
| LP-157 | agents/launch-pad.md | q: **explicit `--non-interactive`/`--non-interactive-fallback` set:** "Save and exit" | PASS and an explicit non-interactive flag | save the unmutated PASSed brief, noted saved_on_pass_non_interactive; never Refine/Edit | deterministic | prose | - | test-non-interactive-gates-seam.sh |
| LP-158 | agents/launch-pad.md | q: **Cannot ask only because this is a subagent (no flag):** | PASS, running as a subagent, no flag | save nothing; aborted with save_requires_flag_non_interactive, scratch path in output | deterministic | prose | - | test-non-interactive-gates-seam.sh |
| LP-159 | agents/launch-pad.md | q: If Plan Review returned FAIL (after 3 attempts — the cap is exhausted) | FAIL after 3 attempts | ask with 2 options; FAIL never enables save; cap never reset | deterministic | prose | - | GAP |
| LP-160 | agents/launch-pad.md | q: **"Refine offline"** — Exit without saving (`status: blocked`) | user picks Refine offline | exit without saving; status blocked | deterministic | prose | - | GAP |
| LP-161 | agents/launch-pad.md | q: **"Discard"** — Cancel without saving (`status: discarded`) | user picks Discard after FAIL x3 | cancel; status discarded | deterministic | prose | - | GAP |
| LP-162 | agents/launch-pad.md | q: `status: blocked, status_reason: "plan_review_fail_non_interactive"` (the Refine-offline outcome | FAIL x3 and the run cannot ask | status blocked, plan_review_fail_non_interactive; nothing saved | deterministic | prose | - | test-non-interactive-gates-seam.sh |
| LP-163 | agents/launch-pad.md | q: Create `.supervisor/jobs/pending/` directory if not exists | on save | mkdir -p pending/, write the date-slug brief, confirm the path | deterministic | prose | - | GAP |
| LP-164 | agents/launch-pad.md | q: Output the exact Supervisor command for a fresh-context session | after save | print the /supervisor job command | deterministic | prose | - | GAP |
| LP-165 | agents/launch-pad.md | q: **Propose project-memory candidates (human-gated, v14.3.0, optional):** | durable, decision-changing facts learned and not already recorded | propose each individually; write each approved fact with write-project-memory.sh --confirm | judgment | prose | script:write-project-memory.sh | test-project-memory.sh |
| LP-166 | agents/launch-pad.md | q: **Never auto-write** — memory promotion is human-gated in v1. | writing memory | only after explicit approval and with --confirm; the writer refuses without it | rule | prose | script:write-project-memory.sh | test-project-memory.sh |
| LP-167 | agents/launch-pad.md | q: Cannot ask (Can't-ask rule) ⇒ write nothing; list the candidates under `memory_candidates_deferred_non_interactive` | memory candidates and the run cannot ask | write nothing; list them as memory_candidates_deferred_non_interactive | deterministic | prose | - | test-non-interactive-gates-seam.sh |
| LP-168 | agents/launch-pad.md | q: If environment has BLOCKERS from Phase 1: output fix instructions, don't offer save | Phase 1 BLOCKERS | output fix instructions; no save offered | deterministic | prose | - | GAP |
| LP-169 | agents/launch-pad.md | q: If Plan Review did not pass (FAIL after 3 attempts): don't offer save | FAIL after 3 attempts | no save; only Refine offline or Discard | deterministic | prose | - | GAP |
| LP-170 | agents/launch-pad.md | q: If Plan Review returned NEEDS_HUMAN for a non-`executable_acceptance` reason | generic NEEDS_HUMAN | offer Override and save / Refine further / Discard; non-interactive ⇒ needs_human_non_interactive | deterministic | prose | - | GAP |
| LP-171 | agents/launch-pad.md | q: If Plan Review returned NEEDS_HUMAN for a Criterion 17c house-rule conflict (action 2b) | 17c NEEDS_HUMAN | offer record-override / honor-rule / discard; non-interactive ⇒ rule_conflict_non_interactive | deterministic | prose | - | GAP |
| LP-172 | agents/launch-pad.md | q: If Plan Review returned NEEDS_HUMAN for a Criterion 14 `executable_acceptance` reason (action 2a) | Criterion 14 NEEDS_HUMAN | interactive 3 options; non-interactive auto-strip and re-review; never an unreviewed executable brief | deterministic | prose | - | GAP |
| LP-173 | agents/launch-pad.md | q: Slug derived from goal (lowercase, hyphens, max 40 chars) | naming the brief | slug lowercase, hyphenated, at most 40 chars | rule | prose | - | GAP |
| LP-174 | agents/launch-pad.md | q: Date in ISO format (YYYY-MM-DD) | naming the brief | ISO date prefix | rule | prose | - | GAP |
| LP-175 | agents/launch-pad.md | h: ### Phase 7: EMIT LAUNCH_PAD_RESULT (Required, Non-Interactive) | every invocation, abort paths included | emit one LAUNCH_PAD_RESULT block as the last structured output | deterministic | prose | script:validate-launch-pad-result.py | test-result-validators.sh |
| LP-176 | agents/launch-pad.md | q: **`saved`** — Phase 6 chose "Save and exit" OR "Override and save" | Save and exit or Override and save wrote the brief | status saved | deterministic | prose | - | GAP |
| LP-177 | agents/launch-pad.md | q: **`discarded`** — Phase 6 chose "Discard"; no file written. | Phase 6 Discard | status discarded | deterministic | prose | - | GAP |
| LP-178 | agents/launch-pad.md | q: **`blocked`** — Phase 1 had BLOCKERS that suppressed the save offer | Phase 1 BLOCKERS, or FAIL x3 then Refine offline / no choice | status blocked; an explicit Discard always wins (FAIL x3 then Discard is discarded) | deterministic | prose | - | GAP |
| LP-179 | agents/launch-pad.md | q: **`aborted`** — User aborted the run mid-flight | in-session abort, or /autonomous cleanup after rubric-dropped | status aborted (a killed session emits nothing) | deterministic | prose | - | GAP |
| LP-180 | agents/launch-pad.md | q: When `status: saved` → the exact path of the file written in Phase 6 | status saved / any other status | saved_brief_path is the written file's path / the literal YAML null, never the string or empty | deterministic | prose | script:validate-launch-pad-result.py | test-result-validators.sh |
| LP-181 | agents/launch-pad.md | q: Compose `summary`: a single line, ≤ 200 characters | composing the summary / a can't-ask branch decided the outcome | one line of at most 200 chars / the line starts with that branch's named status (read by /autonomous PLAN step 4) | deterministic | prose | script:validate-launch-pad-result.py | GAP |
| LP-182 | agents/launch-pad.md | q: **Compute the additive `cmd_bullets_stripped_non_interactive` field | the non-interactive auto-strip removed ≥1 bullet / any other case | emit true / omit the field entirely, never false | deterministic | prose | script:validate-launch-pad-result.py | GAP |
| LP-183 | agents/launch-pad.md | q: Emit the YAML block verbatim as the **last** structured output of the run | inline slash-command run / agent-runner run | consumers read the last block / the stop hook validates the same block | deterministic | prose | script:validate-launch-pad-result.py | test-result-validators.sh |
| LP-184 | agents/launch-pad.md | q: **Constraint reminder:** the YAML must conform to the validation rules | status saved / otherwise / any extra field | saved_brief_path non-empty and existing on disk / literal null / the one additive exception only, invent no field | rule | prose | script:validate-launch-pad-result.py | test-result-validators.sh |
| LP-185 | agents/launch-pad.md | h: ### Token Budget | every run | keep phase outputs compact; at most 3 Plan Reviewer spawns per session; no state file | rule | prose | - | GAP |
| LP-186 | agents/launch-pad.md | q: Accepted as either spelling so a caller forwarding | --non-interactive or --non-interactive-fallback passed | treat both spellings identically (a subagent run has the same effect) | deterministic | prose | - | GAP |
| LP-187 | agents/launch-pad.md | q: CLAUDE.md missing \| BLOCKER: output instructions to create one | CLAUDE.md missing | BLOCKER with create instructions | deterministic | prose | - | GAP |
| LP-188 | agents/launch-pad.md | q: Git state has conflicts \| BLOCKER: output resolution instructions | git conflicts | BLOCKER with resolution instructions | deterministic | prose | - | GAP |
| LP-189 | agents/launch-pad.md | q: gh not authenticated \| WARNING: note PR creation will fail | gh not authenticated | WARNING noting PR creation will fail | deterministic | prose | - | GAP |
| LP-190 | agents/launch-pad.md | q: Orphaned worktrees \| WARNING: output cleanup commands | orphaned worktrees | WARNING with cleanup commands | deterministic | prose | - | GAP |
| LP-191 | agents/launch-pad.md | q: Goal too vague after 2 rounds \| Save what we have with LOW confidence markers | goal still vague after 2 rounds | save what exists with LOW confidence markers | judgment | prose | - | GAP |
| LP-192 | agents/launch-pad.md | q: No files found matching goal \| Flag as greenfield, estimate new file structure | no files match the goal | flag greenfield and estimate a new file structure | judgment | prose | - | GAP |
| LP-193 | agents/launch-pad.md | q: Feasibility NO-GO (Phase 2.5) \| Present reason + suggestion | feasibility NO-GO | present reason + suggestion; offer Override / Revise (max 1) / Abort | deterministic | prose | - | GAP |
| LP-194 | agents/launch-pad.md | q: Environment validated (or --skip-validation acknowledged) | before offering save | environment validated or skip acknowledged | rule | prose | - | GAP |
| LP-195 | agents/launch-pad.md | q: Feasibility check passed (GO, CAUTION acknowledged, or NO-GO user-overridden) | before offering save | feasibility GO, CAUTION acknowledged, or NO-GO overridden | rule | prose | - | GAP |
| LP-196 | agents/launch-pad.md | q: File impact map includes only verified paths | before offering save | impact map holds only verified paths, each with a confidence level | rule | prose | - | GAP |
| LP-197 | agents/launch-pad.md | q: Subtask count follows `skills/supervisor-readiness/SKILL.md` §"Decomposition Threshold" | before offering save | default 1 subtask; a split only for a named reason recorded as Split reason | rule | prose | - | GAP |
| LP-198 | agents/launch-pad.md | q: Parallelism analysis is conservative (no false LAUNCHABLE) | before offering save | no false LAUNCHABLE | rule | prose | - | GAP |
| LP-199 | agents/launch-pad.md | q: Plan Review gate cleared — PASS, or NEEDS_HUMAN with explicit user override | before offering save | Plan Review PASS, or NEEDS_HUMAN with explicit override | rule | prose | - | GAP |
| LP-200 | agents/launch-pad.md | h: ### Agent memory write permission | the agent wants to persist a memory | never write its own agent-memory store; write proposals only, via the confirm-gated sole writer | rule | prose | script:write-agent-memory.sh | test-agent-memory-permission.sh |
| LP-201 | agents/launch-pad.md | q: **The proposal trigger is SURPRISE-ONLY:** | something contradicted an expectation and would have changed a decision / otherwise | propose / do not propose (not once per run) | judgment | prose | - | test-agent-memory-permission.sh |
| LP-202 | agents/launch-pad.md | q: **Bash is not restricted by the harness** | tool restrictions appear to forbid store writes | treat the no-write rule as a prompt-level contract regardless | rule | prose | - | test-agent-memory-permission.sh |
| LP-203 | agents/launch-pad.md | q: **To propose:** write one file to | proposing a memory | write one file to the gitignored proposals dir with agent/name/description/source, then stop | deterministic | prose | - | GAP |
| LP-204 | commands/launch-pad.md | q: **Execute this workflow inline as the main thread.** | /launch-pad invoked | run inline on the main thread; never delegate to the runner (a delegated subagent cannot ask and spends nesting depth) | rule | prose | - | GAP |
| LP-205 | commands/launch-pad.md | q: You MUST still spawn the `plan-reviewer` child agent via the Task tool at the Plan Review gate | inline execution reaches Plan Review | still spawn the plan-reviewer child; never self-validate on the main thread | rule | prose | - | GAP |
| LP-206 | commands/launch-pad.md | q: A PASS carrying an issue at the floor is refined and re-reviewed | --fix-floor given / invalid value | refine at-floor PASS issues (one attempt each), save with issues deferred once attempts run out / abort fix_floor_invalid | deterministic | prose | script:fix-floor.sh resolve | test-fix-floor.sh |
| LP-207 | commands/launch-pad.md | q: forwarded from `/autonomous`'s own `--non-interactive-fallback` flag (accepts either spelling) | either non-interactive spelling passed | every question gate takes its named can't-ask branch; a subagent run has the same effect | deterministic | prose | - | GAP |
| LP-208 | commands/launch-pad.md | h: ### Why Use Launch Pad? | choosing Launch Pad | rationale: frees planning context, enables plan review, pre-flight validation, overlap analysis, clean handoff, early infeasibility | story | prose | - | GAP |
| LP-209 | commands/launch-pad.md | q: **Note:** "Save and exit" is disabled when Plan Review returns FAIL | Plan Review FAIL | Save and exit disabled; after FAIL x3 only Refine offline or Discard; cap never reset | deterministic | prose | - | GAP |
| LP-210 | commands/launch-pad.md | h: ### Step 1: Run Launch Pad | user starts | run /launch-pad with a goal (usage walkthrough) | story | prose | - | GAP |
| LP-211 | commands/launch-pad.md | h: ### Step 2: Review the Brief | brief presented | user checks criteria, impact map, subtask boundaries, parallelism | story | prose | - | GAP |
| LP-212 | commands/launch-pad.md | h: ### Step 3: Refine or Save | brief reviewed | user picks Save and exit / Refine further / Edit sections | story | prose | - | GAP |
| LP-213 | commands/launch-pad.md | h: ### Step 4: Start Fresh Session | brief saved | run /supervisor job in a new session | story | prose | - | GAP |
| LP-214 | commands/launch-pad.md | h: ### When to Use Launch Pad vs Direct Supervisor | complex (>3 subtasks) or plan review wanted / simple, resume or quick fix | /launch-pad then /supervisor job / /supervisor directly (or --continue) | judgment | prose | - | GAP |
| LP-215 | commands/launch-pad.md | q: **Git repository:** Project must be a git repo | not a git repo | prerequisite fails | rule | prose | - | GAP |
| LP-216 | commands/launch-pad.md | q: **CLAUDE.md:** Should exist for best results (Launch Pad warns if missing) | CLAUDE.md missing | Launch Pad warns | rule | prose | - | GAP |
| LP-217 | commands/launch-pad.md | q: **Use `--discovery` for vague goals:** | goal is vague | pass --discovery to force full discovery | judgment | prose | - | GAP |
| LP-218 | commands/launch-pad.md | q: **Start fresh session for Supervisor:** The whole point is clean context | about to run the brief | never run /supervisor job in the same session | rule | prose | - | GAP |
| LP-219 | commands/launch-pad.md | q: **One brief per task:** Don't try to pack multiple goals into one brief | several goals | one brief per goal | rule | prose | - | GAP |
| LP-220 | commands/launch-pad.md | q: **Check the risk assessment:** Known risks are documented | HIGH risks listed | address them before launching Supervisor | judgment | prose | - | GAP |
| LP-221 | commands/launch-pad.md | q: **"BLOCKER: CLAUDE.md missing"** | CLAUDE.md-missing BLOCKER | create a CLAUDE.md with tech stack, structure, key patterns | deterministic | prose | - | GAP |
| LP-222 | commands/launch-pad.md | q: **"File impact map seems wrong"** | wrong file predictions | choose Edit sections to correct them | judgment | prose | - | GAP |
| LP-223 | commands/launch-pad.md | q: **"Too many subtasks (>7)"** | more than 7 subtasks | split into several Launch Pad runs or Refine further to narrow scope | judgment | prose | - | GAP |
| LP-224 | commands/launch-pad.md | q: **"All subtasks marked BLOCKED"** | every subtask BLOCKED | check dependencies; Edit sections to adjust parallelism | judgment | prose | - | GAP |
| LP-225 | commands/launch-pad.md | q: **"Brief is stale (>24h old)"** | brief older than 24h | Supervisor warns; re-run Launch Pad if the codebase changed | judgment | prose | - | GAP |
| LP-226 | commands/launch-pad.md | h: ### Core Principles | every run (command mirror) | plan-first principles mirror the agent | rule | prose | - | GAP |
| LP-227 | commands/launch-pad.md | q: **Plan, don't execute:** Never invoke Supervisor | always | save the brief; never invoke Supervisor | rule | prose | - | GAP |
| LP-228 | commands/launch-pad.md | q: **Conservative parallelism:** Only mark subtasks LAUNCHABLE | subtask overlaps | not LAUNCHABLE | rule | prose | - | GAP |
| LP-229 | commands/launch-pad.md | q: **Verify everything:** Confirm every file path exists | path enters impact map | confirm it exists | rule | prose | - | GAP |
| LP-230 | commands/launch-pad.md | q: **Interactive refinement:** Always present brief for user review | before saving | present for review | rule | prose | - | GAP |
| LP-231 | commands/launch-pad.md | h: ### Inputs | run starts (command mirror) | input enumeration | story | prose | - | GAP |
| LP-232 | commands/launch-pad.md | q: **Requirement file (optional):** When the | goal value is a .md path under .supervisor/requirements/ | read it as the requirement source; other paths stay literal | deterministic | prose | - | GAP |
| LP-233 | commands/launch-pad.md | h: ### Outputs | run completes (command mirror) | output enumeration | story | prose | - | GAP |
| LP-234 | commands/launch-pad.md | h: ### Critical Rules | every run (command mirror) | critical rules mirror the agent | rule | prose | - | GAP |
| LP-235 | commands/launch-pad.md | q: **If environment has blockers:** output fix instructions | BLOCKERS | fix instructions, no save | deterministic | prose | - | GAP |
| LP-236 | commands/launch-pad.md | q: **Can't-ask rule:** this run cannot ask when | flag set or running as a subagent | named can't-ask branches; must stay byte-identical to the agent's rule | deterministic | prose | - | test-non-interactive-gates-seam.sh |
| LP-237 | commands/launch-pad.md | q: **Never invent files/APIs/paths** — ask if unsure | unsure about a file/API/path | ask; never invent | rule | prose | - | GAP |
| LP-238 | commands/launch-pad.md | q: **Feasibility gate (Phase 2.5)** — soft gate | NO-GO / CAUTION | stop (overridable) / feed Risk Assessment | deterministic | prose | - | GAP |
| LP-239 | commands/launch-pad.md | h: ### Phase 1: VALIDATE (Environment Readiness) | start (command mirror) | environment checks | deterministic | prose | - | GAP |
| LP-240 | commands/launch-pad.md | q: Report blockers (must fix) vs warnings (can proceed) | a check fails | BLOCKER must be fixed; WARNING may proceed | deterministic | prose | - | GAP |
| LP-241 | commands/launch-pad.md | q: Skip if `--skip-validation` flag is set. | --skip-validation | skip Phase 1 | deterministic | prose | - | GAP |
| LP-242 | commands/launch-pad.md | h: ### Phase 2: DISCOVER (Requirement Refinement) | after VALIDATE (command mirror) | requirement refinement | deterministic | prose | - | GAP |
| LP-243 | commands/launch-pad.md | q: **Resolve requirement-file input (do FIRST):** | .md under .supervisor/requirements/ passing test -f | read it; any other value literal; a failing path falls back and is noted | deterministic | prose | - | GAP |
| LP-244 | commands/launch-pad.md | q: If goal is vague (and no requirement file supplied criteria) | vague goal | product discovery, max 2 rounds of questions | judgment | prose | - | GAP |
| LP-245 | commands/launch-pad.md | q: If goal is clear (or a requirement file was read): extract acceptance criteria directly | clear goal | extract criteria directly | judgment | prose | - | GAP |
| LP-246 | commands/launch-pad.md | q: a criterion whose evidence would live in the PR body (a carried-forward one included) is written in the evidence-file form instead | PR-body evidence criterion | evidence-file form, its file a File Impact Map create | rule | prose | - | test-pr-body-evidence-seam.sh |
| LP-247 | commands/launch-pad.md | q: If `--discovery` flag: force full discovery even if goal seems clear | --discovery | force full discovery | deterministic | prose | - | GAP |
| LP-248 | commands/launch-pad.md | h: ### Phase 2.5: FEASIBILITY (Soft Gate) | after DISCOVER (command mirror) | five checks; section names no_go_non_interactive | deterministic | prose | - | test-non-interactive-gates-seam.sh |
| LP-249 | commands/launch-pad.md | q: **Tech Stack Compatibility** — goal matches project's stack? | stack mismatch | NO-GO / CAUTION | judgment | prose | - | GAP |
| LP-250 | commands/launch-pad.md | q: **Dependency Availability** — required libs/services present or addable? | dependency missing | NO-GO / CAUTION | judgment | prose | - | GAP |
| LP-251 | commands/launch-pad.md | q: **Architecture Fit** — goal aligns with CLAUDE.md architecture? | architecture misfit | NO-GO / CAUTION | judgment | prose | - | GAP |
| LP-252 | commands/launch-pad.md | q: **Scope vs Supervisor Capability** — Does the goal fit the single-agent default | too large / borderline | NO-GO / CAUTION | judgment | prose | - | GAP |
| LP-253 | commands/launch-pad.md | q: **Hard Blockers** — migration framework, credentials, missing modules? | hard blocker | NO-GO / CAUTION | judgment | prose | - | GAP |
| LP-254 | commands/launch-pad.md | q: GO → proceed silently | GO | proceed silently | deterministic | prose | - | GAP |
| LP-255 | commands/launch-pad.md | q: CAUTION → proceed, findings injected into Risk Assessment | CAUTION | proceed; inject findings into Risk Assessment | deterministic | prose | - | GAP |
| LP-256 | commands/launch-pad.md | q: Override / Revise (max 1 loop back to Phase 2) / Abort | NO-GO | stop and ask: Override / Revise (max 1) / Abort | deterministic | prose | - | GAP |
| LP-257 | commands/launch-pad.md | q: NO-GO + cannot ask (Can't-ask rule) → `status: aborted, status_reason: "no_go_non_interactive"` | NO-GO and cannot ask | aborted no_go_non_interactive; no option auto-picked | deterministic | prose | - | test-non-interactive-gates-seam.sh |
| LP-258 | commands/launch-pad.md | q: **Fallback:** Sparse CLAUDE.md → checks 1-3 default to CAUTION | sparse CLAUDE.md | checks 1-3 default to CAUTION | deterministic | prose | - | GAP |
| LP-259 | commands/launch-pad.md | h: ### Phase 3: ANALYZE (Codebase Impact Estimation) | after FEASIBILITY (command mirror) | impact estimation | deterministic | prose | - | GAP |
| LP-260 | commands/launch-pad.md | q: Detect file overlap between groups (overlap = must serialize) | groups overlap | must serialize | rule | prose | - | GAP |
| LP-261 | commands/launch-pad.md | q: Mark confidence: HIGH / MEDIUM / LOW | each prediction | mark confidence | judgment | prose | - | GAP |
| LP-262 | commands/launch-pad.md | q: Touched-file invariants (conditional — the File Impact Map modifies ≥1 existing script) | the map modifies an existing script | record grounded invariants per modified file | judgment | prose | - | test-rule-conformance-seam.sh |
| LP-263 | commands/launch-pad.md | q: Closed enumerations and pin mutations (conditional | adds an enum/status value or test pins | closed lists via sibling grep; one mutation per pin | judgment | prose | - | test-closed-enum-pins-seam.sh |
| LP-264 | commands/launch-pad.md | h: ### Phase 4: DECOMPOSE (Subtask Structure) | after ANALYZE (command mirror) | decomposition | judgment | prose | - | GAP |
| LP-265 | commands/launch-pad.md | q: **Subtask id scheme (RULE):** plain numeric, 1-based, sequential | numbering subtasks | plain numeric 1-based sequential, never alpha-suffixed | rule | prose | - | GAP |
| LP-266 | commands/launch-pad.md | q: Default to a single subtask whose acceptance criteria are the checklist for one worker | a threshold reason fires / none | split and record Split reason / one subtask | judgment | prose | - | GAP |
| LP-267 | commands/launch-pad.md | q: Compute parallelism: LAUNCHABLE (no deps + no overlap) vs BLOCKED | no deps and no overlap / otherwise | LAUNCHABLE / BLOCKED | deterministic | prose | - | GAP |
| LP-268 | commands/launch-pad.md | h: ### Phase 5: PACKAGE (Assemble Brief) | after DECOMPOSE (command mirror) | assemble the brief | deterministic | prose | - | GAP |
| LP-269 | commands/launch-pad.md | q: For each Phase 2.5 CAUTION finding, add a Risk Assessment row | CAUTION finding / overridden NO-GO | Feasibility risk row / HIGH risk | deterministic | prose | - | GAP |
| LP-270 | commands/launch-pad.md | q: When Phase 3 step 8 ran, emit `## Touched-file invariants` | step 8 ran / not | emit the section before Subtask Structure / none | deterministic | prose | - | test-rule-conformance-seam.sh |
| LP-271 | commands/launch-pad.md | q: When Phase 3 step 9 ran, emit | step 9 ran / not | emit Closed enumerations / Pin mutations / neither | deterministic | prose | - | test-closed-enum-pins-seam.sh |
| LP-272 | commands/launch-pad.md | q: When the source requirement carries a `## Rule conflicts (open decisions)` section | the source requirement carries Rule conflicts | copy verbatim after House Rules; never author a Rule override line | deterministic | prose | - | GAP |
| LP-273 | commands/launch-pad.md | h: ### Phase 5.5: PLAN REVIEW (Mandatory Gate) | brief assembled (command mirror) | spawn the Plan Reviewer | deterministic | prose | - | GAP |
| LP-274 | commands/launch-pad.md | q: Plan Reviewer checks all 20 criteria | each conditional criterion's gating section/field/claim absent / present | skip it silently / run it (17 on pasted rules, 18 on script edits, 19 on enum/pin, 20 on PR-body evidence) | deterministic | prose | - | test-closed-enum-pins-seam.sh |
| LP-275 | commands/launch-pad.md | q: PASS with an issue at the fix floor | PASS with an at-floor issue and attempt < 3 | refine like a FAIL issue, re-spawn (consumes an attempt) | deterministic | prose | - | GAP |
| LP-276 | commands/launch-pad.md | q: PASS → proceed to Phase 6 (save enabled | PASS | proceed with save enabled; open at-floor issue deferred | deterministic | prose | - | GAP |
| LP-277 | commands/launch-pad.md | q: FAIL (attempt < 3) → fix issues (a Criterion 20 PR-body criterion is rewritten | FAIL and attempt < 3 | fix (rewrite Criterion 20 criteria, never delete), re-assemble, re-spawn | deterministic | prose | - | test-pr-body-evidence-seam.sh |
| LP-278 | commands/launch-pad.md | q: FAIL (attempt = 3) → present issues, offer "Refine offline" | FAIL and attempt = 3 | Refine offline (blocked) or Discard; no save; cap never reset | deterministic | prose | - | GAP |
| LP-279 | commands/launch-pad.md | q: NEEDS_HUMAN → present issues, offer "Override and save" | NEEDS_HUMAN generic / 17c conflict | Override and save / Refine / Discard; 17c ⇒ record-override / honor-rule / discard, rule_conflict_non_interactive when it cannot ask | deterministic | prose | - | test-rule-conformance-seam.sh |
| LP-280 | commands/launch-pad.md | h: ### Phase 6: REFINE & SAVE (Interactive) | review allowed save (command mirror) | refine and save | deterministic | prose | - | GAP |
| LP-281 | commands/launch-pad.md | q: Options: Save (PASS or user override) / Refine / Edit / Discard | presenting the brief | offer Save / Refine / Edit / Discard | deterministic | prose | - | GAP |
| LP-282 | commands/launch-pad.md | q: On save: `mkdir -p .supervisor/jobs/pending`, write `{date}-{slug}.md` | on save | create pending/ and write the date-slug brief; print the /supervisor command | deterministic | prose | - | GAP |
| LP-283 | commands/launch-pad.md | q: If blockers exist or Plan Review FAIL: don't offer save | blockers or FAIL | do not offer save | deterministic | prose | - | GAP |
| LP-284 | commands/launch-pad.md | q: Brief follows complete template (9 required sections, plus optional Feasibility) | before offering save | brief follows the complete template | rule | prose | - | GAP |
| LP-285 | commands/launch-pad.md | q: Plan Review gate cleared — PASS, or NEEDS_HUMAN with explicit user override | before offering save | Plan Review PASS or overridden NEEDS_HUMAN | rule | prose | - | GAP |
| LP-286 | skills/autonomous-loop/SKILL.md | q: The loop owns no schema, mutates no agent. | always | read SUPERVISOR_RESULT and three dirs; write only the session dir, fresh requirement files and one session log line | rule | prose | - | GAP |
| LP-287 | skills/autonomous-loop/SKILL.md | q: **Multi-iteration is the default mode in v14.0.0** (cap 10, default 3, stacked branches) | no mode flag / --single-iteration / --allow-multi-iteration | multi-iteration (default 3, cap 10) / single-iteration / no-op with a deprecation warning | deterministic | prose | - | GAP |
| LP-288 | skills/autonomous-loop/SKILL.md | q: Never auto-pick on adjudication. | an adjudication fires | surface the 4 options to the user via Supervisor; never auto-pick | rule | prose | - | GAP |
| LP-289 | skills/autonomous-loop/SKILL.md | q: Two — and only two — signals trigger re-iteration | rubric_score N<M / failed + inter_subtask_gap on this brief / no rubric | re-iterate (Signal 1) / re-iterate (Signal 2) / no-rubric gate asks continue or stop | deterministic | prose | - | GAP |
| LP-290 | skills/autonomous-loop/SKILL.md | q: `current_brief_path` (captured at PLAN via `ls`-diff) is the iteration-scoping anchor | jobs/failed/{basename(current_brief_path)} exists | this iteration failed (prior runs can never collide) | deterministic | prose | - | GAP |
| LP-291 | skills/autonomous-loop/SKILL.md | q: **Non-interactive safety:** if `[ ! -t 0 ]` OR `$CI` is set | non-TTY or CI, multi-iter, no --non-interactive-fallback | INIT aborts immediately (non_interactive_without_fallback) | deterministic | prose | - | test-non-interactive-gates-seam.sh |
| LP-292 | skills/autonomous-loop/SKILL.md | q: **Stacked branches:** iter N+1's feature branch is created from | default / --no-stacked-branches | iter N+1 branches from iterations[N].branch / from main (v13 cadence) | deterministic | prose | - | GAP |
| LP-293 | skills/autonomous-loop/SKILL.md | q: **All gate webhook POSTs go through | --notify set and a webhook URL resolves (env, else user-scope egress entry) | POST through send-webhook.sh --event-type gate; never build gate JSON inline; repo-relative URL is a request, never a grant | rule | prose | script:send-webhook.sh | test-webhook.sh |
| LP-294 | skills/autonomous-loop/SKILL.md | q: **Fail-loud-on-misconfig (v14.2.2, resolution updated v15.87.0):** | --notify set but no webhook URL resolves | print one visible warning and proceed (never abort); a repo-relative URL alone does not satisfy the check | deterministic | prose | - | GAP |
| LP-295 | skills/autonomous-loop/SKILL.md | q: **N=1 is degenerate but valid:** | --max-iterations 1 and Signal 1/2 would fire | cap-check exits paused_max_iterations, max_iterations_reached | deterministic | prose | - | GAP |
| LP-296 | skills/autonomous-loop/SKILL.md | q: **N=0 or N>10** rejected at INIT | N=0 or N>10 | aborted, invalid_max_iterations | deterministic | prose | - | GAP |
| LP-297 | skills/autonomous-loop/SKILL.md | q: Equivalent to `--max-iterations 1` semantically but skips EVALUATE entirely | --single-iteration | INIT, PLAN, EXECUTE, DONE; no EVALUATE, no paused_max_iterations | deterministic | prose | - | GAP |
| LP-298 | skills/autonomous-loop/SKILL.md | h: ### Migration hint (AC-1) | default multi-iter path with no mode flag / a mode flag passed | print the one-line hint once per INIT (informational) / suppress it | deterministic | prose | - | GAP |
| LP-299 | skills/autonomous-loop/SKILL.md | q: Before INIT, the main thread `Read`s the canonical command files **and this skill** end-to-end. | every /autonomous invocation | read the launch-pad and supervisor commands and this skill via the plugin-root path; never loomwright/ paths at runtime | rule | prose | - | GAP |
| LP-300 | skills/autonomous-loop/SKILL.md | h: ### INIT step 0 — non-interactive detection (AC-6) + flag validation | before any state-writing step | resolve mode, detect non-interactive, validate flags | deterministic | prose | - | test-non-interactive-gates-seam.sh |
| LP-301 | skills/autonomous-loop/SKILL.md | q: When `--non-interactive-fallback` IS set, gates do not call | --non-interactive-fallback set | rubric gate ⇒ aborted rubric_gate_closed_non_interactive; no-rubric gate ⇒ done no_rubric_in_non_interactive; forward --non-interactive to /supervisor and Launch Pad | deterministic | prose | - | test-non-interactive-gates-seam.sh |
| LP-302 | skills/autonomous-loop/SKILL.md | q: **Main-thread-only by construction:** | gate keys | key on the explicit flag; the TTY / CI probe is an additional signal, never the only one | rule | prose | - | GAP |
| LP-303 | skills/autonomous-loop/SKILL.md | q: **max-iterations validation (AC-10):** | max_iterations < 1 or > 10 | aborted, invalid_max_iterations, error on stderr | deterministic | prose | - | GAP |
| LP-304 | skills/autonomous-loop/SKILL.md | q: **Conflicting-flag detection (AC-11):** | --allow-multi-iteration and --single-iteration both set | aborted, conflicting_mode_flags | deterministic | prose | - | GAP |
| LP-305 | skills/autonomous-loop/SKILL.md | q: If `--allow-multi-iteration` is the only mode-flag passed | only --allow-multi-iteration | log a deprecation warning, proceed multi-iter | deterministic | prose | - | GAP |
| LP-306 | skills/autonomous-loop/SKILL.md | q: **`--cheap` cost-profile flag (v15.2.0+):** | --cheap passed | carry in memory (not state.json); append --cheap to every inlined /supervisor job | deterministic | prose | - | GAP |
| LP-307 | skills/autonomous-loop/SKILL.md | q: **`--max-tokens N` token ceiling (red-team-hardening/06):** | --max-tokens N passed / absent | persist max_tokens in state.json and forward to every /supervisor job / byte-identical behaviour | deterministic | prose | - | GAP |
| LP-308 | skills/autonomous-loop/SKILL.md | q: `scripts/run-lock.sh acquire --owner autonomous:<session_id> --session-id "<session_id>"` | INIT acquires the run lock: held by another run / reentrant / degraded | abort run_lock_held / proceed (own release a no-op) / note once and proceed | deterministic | prose | script:run-lock.sh acquire | test-run-lock.sh |
| LP-309 | skills/autonomous-loop/SKILL.md | q: the lock is released at the loop's own completion tail or any abort exit | loop completes or aborts | release the run lock | deterministic | prose | script:run-lock.sh release | test-run-lock.sh |
| LP-310 | skills/autonomous-loop/SKILL.md | q: the loop sums its own session's ledger via `scripts/read-token-ledger.sh --session <session_id>` | before each iteration: TOTAL breaches max_tokens or LEDGER_UNREADABLE=1 | aborted, token_ceiling_reached; never a silent continue | deterministic | prose | script:read-token-ledger.sh | test-read-token-ledger.sh |
| LP-311 | skills/autonomous-loop/SKILL.md | q: **Honest limit:** the ledger counts only what a | reading the token ceiling | ledger excludes main-thread and CI spend; no dollar conversion | rule | prose | - | GAP |
| LP-312 | skills/autonomous-loop/SKILL.md | h: ### INIT step 1+ — requirement intake | INIT | read the requirement, write/keep the requirement file, generate session_id, init state.json + summary.md, log start | deterministic | prose | - | GAP |
| LP-313 | skills/autonomous-loop/SKILL.md | q: If string-argument: write `.supervisor/requirements/{session_id}-{slug}.md` | requirement given as a string | write a requirement file with a non-header rubric placeholder hint | deterministic | prose | - | GAP |
| LP-314 | skills/autonomous-loop/SKILL.md | q: **The placeholder MUST NOT begin a line with `## Outcomes Rubric`:** | writing the placeholder | never start a line with the rubric header (has_rubric would treat it as real) | rule | prose | - | GAP |
| LP-315 | skills/autonomous-loop/SKILL.md | q: If `--requirement <path>` is used and the file already has a real `## Outcomes Rubric` section | --requirement file already has a real rubric | leave it intact | deterministic | prose | - | GAP |
| LP-316 | skills/autonomous-loop/SKILL.md | q: **Collision risk in v1:** two sessions started in the same second | concurrent activity seen by the brief-save ls-diff | abort concurrent_session_detected | deterministic | prose | - | GAP |
| LP-317 | skills/autonomous-loop/SKILL.md | h: ### state.json schema | writing state.json | advisory-only schema; never authoritative for resume (summary.md and SUPERVISOR_RESULT are) | rule | prose | - | GAP |
| LP-318 | skills/autonomous-loop/SKILL.md | h: ### state.json ACQUIRE signals (hook-readable — carve-out from the advisory-only rule) | PR-create hook disambiguates the session | it may read current_branch / current_status (written by the inlined Supervisor at ACQUIRE) | deterministic | prose | script:hook-dispatch-on-pr-create.sh | test-hook-dispatch-on-pr-create.sh |
| LP-319 | skills/autonomous-loop/SKILL.md | q: The write is best-effort / non-fatal (jq atomic update | ACQUIRE write errors / direct /supervisor job path | logged no-op / write skipped | deterministic | prose | - | GAP |
| LP-320 | skills/autonomous-loop/SKILL.md | q: **Terminal-status set (consumer treats these as NOT-active), exactly:** | current_status in the terminal set / outside it | session not active / active | deterministic | prose | script:hook-dispatch-on-pr-create.sh | test-hook-dispatch-on-pr-create.sh |
| LP-321 | skills/autonomous-loop/SKILL.md | q: **No completion flip in state.json:** | ended_at set or brief not in jobs/in-progress/ | hook rejects the session as stale | deterministic | prose | script:hook-dispatch-on-pr-create.sh | test-hook-dispatch-on-pr-create.sh |
| LP-322 | skills/autonomous-loop/SKILL.md | q: **Residual window (accepted):** | a crashed run leaves its brief in in-progress/ and no ended_at, and a later PR's branch collides | Source 2 may dispatch against it; accepted (narrow, fail-safe, never merges) | story | prose | - | GAP |
| LP-323 | skills/autonomous-loop/SKILL.md | q: **Rubric-presence test (canonical — used by PLAN step 2, step 6, and step 7).** | checking a rubric | real only with a line-anchored header and ≥1 bullet (has_rubric); never a substring grep | deterministic | prose | - | GAP |
| LP-324 | skills/autonomous-loop/SKILL.md | q: Reference the loaded `commands/launch-pad.md` workflow. Invoke it inline on the main thread | every iteration | invoke Launch Pad inline with the current requirement; on loop-back set and persist requirement_path to the iter file | deterministic | prose | - | GAP |
| LP-325 | skills/autonomous-loop/SKILL.md | q: **Launch Pad forward (separate from the `/supervisor` forward set):** | --non-interactive-fallback at INIT / interactive run | append --non-interactive to Launch Pad every iteration / pass the requirement path alone; /supervisor set stays four flags | deterministic | prose | - | test-non-interactive-gates-seam.sh |
| LP-326 | skills/autonomous-loop/SKILL.md | q: **Inline-instruction to Launch Pad (no source change):** | the requirement has an Outcomes Rubric | instruct Launch Pad to copy it verbatim into the brief at Phase 5 | deterministic | prose | - | GAP |
| LP-327 | skills/autonomous-loop/SKILL.md | q: **Conditional auto-authoring directive (multi-iteration only, no rubric at intake):** | multi mode AND no real rubric AND no --non-interactive-fallback | also instruct Launch Pad to auto-author a 3-7 bullet rubric | deterministic | prose | - | test-non-interactive-gates-seam.sh |
| LP-328 | skills/autonomous-loop/SKILL.md | q: **When the conditional directive does NOT apply:** | single mode, or the requirement already has a real rubric | preserve-verbatim directive only | deterministic | prose | - | GAP |
| LP-329 | skills/autonomous-loop/SKILL.md | q: **Never under `--non-interactive-fallback`:** an auto-authored rubric's only approval | --non-interactive-fallback run with no rubric | request no authoring; brief saved without a rubric; iteration ends done, no_rubric_in_non_interactive | deterministic | prose | - | test-non-interactive-gates-seam.sh |
| LP-330 | skills/autonomous-loop/SKILL.md | q: **Degenerate-rubric fallback:** if Launch Pad cannot derive ≥3 diff-checkable bullets | fewer than 3 bullets derivable | no rubric section; proceed under the no-rubric gate (Signal 1 skipped) | deterministic | prose | - | GAP |
| LP-331 | skills/autonomous-loop/SKILL.md | q: Under the Launch Pad forward (step 1) none of these asks | the Launch Pad forward is active | every inner Launch Pad gate takes its named can't-ask branch (PASS saves) | deterministic | prose | - | GAP |
| LP-332 | skills/autonomous-loop/SKILL.md | q: **Brief-save detection — primary path: `LAUNCH_PAD_RESULT` (v14.2.0+):** | Launch Pad finished inline | read the last LAUNCH_PAD_RESULT block in the transcript | deterministic | prose | - | GAP |
| LP-333 | skills/autonomous-loop/SKILL.md | q: **Validate the block before trusting it (closes the inline-path validation gap):** | inline path (the stop hook does not fire) | pipe the block to validate-launch-pad-result.py --raw | deterministic | prose | script:validate-launch-pad-result.py | test-result-validators.sh |
| LP-334 | skills/autonomous-loop/SKILL.md | q: `{}` (no `decision` key) → block well-formed | validator prints {} | treat as well-formed; take the per-status branch | deterministic | prose | script:validate-launch-pad-result.py | test-result-validators.sh |
| LP-335 | skills/autonomous-loop/SKILL.md | q: `decision: block` → malformed. Record `policy_decisions[].decision = "launch_pad_result_malformed"` | validator blocks | record launch_pad_result_malformed and fall through to the ls-diff fallback; never abort | deterministic | prose | - | GAP |
| LP-336 | skills/autonomous-loop/SKILL.md | q: `status: saved` → set `current_brief_path = LAUNCH_PAD_RESULT.saved_brief_path` | status saved / the path fails test -f | set current_brief_path / treat as malformed, fall back | deterministic | prose | - | GAP |
| LP-337 | skills/autonomous-loop/SKILL.md | q: `status: discarded` → `status: aborted, status_reason: "user_discarded_at_phase_6"` | status discarded | aborted, user_discarded_at_phase_6; exit | deterministic | prose | - | GAP |
| LP-338 | skills/autonomous-loop/SKILL.md | q: whose `summary` (quotes stripped) begins with a named can't-ask status | blocked/aborted and summary leads with a name_non_interactive token (checked first) | aborted, launch_pad_cant_ask_non_interactive; Launch Pad summary kept verbatim in summary.md | deterministic | prose | - | test-non-interactive-gates-seam.sh |
| LP-339 | skills/autonomous-loop/SKILL.md | q: `status: blocked` (any other summary) → `status: aborted, status_reason: "launch_pad_blocked"` | blocked, any other summary | aborted, launch_pad_blocked; exit | deterministic | prose | - | GAP |
| LP-340 | skills/autonomous-loop/SKILL.md | q: `status: aborted` (any other summary) → `status: aborted, status_reason: "user_aborted_at_launch_pad"` | aborted, any other summary | aborted, user_aborted_at_launch_pad; exit | deterministic | prose | - | GAP |
| LP-341 | skills/autonomous-loop/SKILL.md | q: **If the block is absent or fails validation** | block absent or invalid | fall through to ls-diff; record launch_pad_result_fallback or launch_pad_result_malformed | deterministic | prose | - | GAP |
| LP-342 | skills/autonomous-loop/SKILL.md | q: **Pre-snapshot stale-session-id sanity check (catches the rubric_dropped_from_brief retry footgun):** | a session_id-shaped brief already sits in pending/ | warn with a cleanup hint; ask abort / move and continue / force (recorded); no can't-ask branch is named | deterministic | prose | - | GAP |
| LP-343 | skills/autonomous-loop/SKILL.md | q: If `new_briefs` is empty → user picked discard or refine failed | ls-diff finds no new brief | aborted, user_discarded_at_phase_6; exit | deterministic | prose | - | GAP |
| LP-344 | skills/autonomous-loop/SKILL.md | q: If `new_briefs` has exactly one entry → that path is `current_brief_path` | exactly one new brief | record it as current_brief_path; proceed | deterministic | prose | - | GAP |
| LP-345 | skills/autonomous-loop/SKILL.md | q: If `new_briefs` has >1 entries → ambiguity | more than one new brief | abort concurrent_session_detected | deterministic | prose | - | GAP |
| LP-346 | skills/autonomous-loop/SKILL.md | q: For v14.2.0+ plugins, `LAUNCH_PAD_RESULT.saved_brief_path` is authoritative | plugin emits Phase 7 / pre-v14.2.0 plugin | saved_brief_path authoritative, ls-diff informational / ls-diff is the only mechanism | rule | prose | - | GAP |
| LP-347 | skills/autonomous-loop/SKILL.md | q: User aborted at NO-GO → `status_reason: "user_aborted_at_no_go"` | user aborted at NO-GO | user_aborted_at_no_go; exit | deterministic | prose | - | GAP |
| LP-348 | skills/autonomous-loop/SKILL.md | q: User aborted after Plan Review FAIL × 3 → `status_reason: "user_aborted_at_plan_review_fail"` | user aborted after FAIL x3 | user_aborted_at_plan_review_fail; exit | deterministic | prose | - | GAP |
| LP-349 | skills/autonomous-loop/SKILL.md | q: **Rubric preservation verification (when applicable):** | requirement had a real rubric and the saved brief lacks one | aborted, rubric_dropped_from_brief | deterministic | prose | - | GAP |
| LP-350 | skills/autonomous-loop/SKILL.md | q: **Persist + freeze an authored rubric (multi-iteration only):** | a rubric was authored into the brief | write it back into the requirement body so iteration 2+ templates inherit it | rule | prose | - | GAP |
| LP-351 | skills/autonomous-loop/SKILL.md | q: **Fires ONLY when ALL of:** `mode == "multi"` AND the **current** requirement file | multi AND current requirement lacks a rubric AND brief has one | freeze exactly once (idempotent); never gate on a run-global had-rubric flag | deterministic | prose | - | GAP |
| LP-352 | skills/autonomous-loop/SKILL.md | q: **Extract + append + verify (all inside one idempotency guard):** | inside the guard: the append did not take | print a rubric-freeze-failed warning (verification never runs outside the guard) | deterministic | prose | - | GAP |
| LP-353 | skills/autonomous-loop/SKILL.md | q: **Non-interactive no-op:** under `--non-interactive-fallback` PLAN step 2 requests no authoring | --non-interactive-fallback and the brief carries an unrequested rubric | skip the freeze; never freeze an unapproved rubric | deterministic | prose | - | test-non-interactive-gates-seam.sh |
| LP-354 | skills/autonomous-loop/SKILL.md | q: **Degenerate-case no-op:** if Launch Pad fell back | no rubric authored | skip append and verification (no misleading warning); no-rubric gate | deterministic | prose | - | GAP |
| LP-355 | skills/autonomous-loop/SKILL.md | q: Reference the loaded `commands/supervisor.md` workflow. Invoke it inline on the main thread | every iteration | invoke /supervisor inline with job: current_brief_path plus the forward set | deterministic | prose | - | GAP |
| LP-356 | skills/autonomous-loop/SKILL.md | q: **`--base-branch` passthrough (v14.0.0 stacked-mode belt-and-suspenders):** | iteration > 1 and stacked | pass --base-branch iterations[-2].branch | deterministic | prose | - | GAP |
| LP-357 | skills/autonomous-loop/SKILL.md | q: The CLI flag is the **authoritative source** | CLI flag and brief Base Branch field | CLI wins; both must agree at Plan Review or Criterion 13 FAILs | rule | prose | - | GAP |
| LP-358 | skills/autonomous-loop/SKILL.md | q: **`--no-stacked-branches` mode and iter 1:** do NOT pass `--base-branch` | --no-stacked-branches or iteration 1 | omit --base-branch (Supervisor defaults to main) | deterministic | prose | - | GAP |
| LP-359 | skills/autonomous-loop/SKILL.md | q: **`--non-interactive-fallback` mode:** also pass `--non-interactive` to Supervisor | --non-interactive-fallback at INIT | forward --non-interactive to /supervisor | deterministic | prose | - | GAP |
| LP-360 | skills/autonomous-loop/SKILL.md | q: **`--cheap` cost-profile forward (v15.2.0+):** | --cheap at INIT | append --cheap to every iteration's /supervisor exactly once; not gated on the fallback flag | deterministic | prose | - | GAP |
| LP-361 | skills/autonomous-loop/SKILL.md | q: **`--max-tokens N` token-ceiling forward (red-team-hardening/06):** | --max-tokens N at INIT | append --max-tokens N to every iteration's /supervisor; not gated on the fallback flag | deterministic | prose | - | GAP |
| LP-362 | skills/autonomous-loop/SKILL.md | q: **Auto-forwarded flags (the complete `/supervisor` forward set):** | building the /supervisor invocation | forward exactly four flags, each under its own condition | rule | prose | - | test-non-interactive-gates-seam.sh |
| LP-363 | skills/autonomous-loop/SKILL.md | q: `--skip-preflight-sync` in particular is NOT passed through | any other flag | never forward it to /supervisor (the one other forward goes to Launch Pad) | rule | prose | - | GAP |
| LP-364 | skills/autonomous-loop/SKILL.md | q: **The Supervisor Phase 4.5 enumeration MUST NOT stop at Rubric Grader.** | inline Supervisor run completes Phase 4.5 | run step 5.5's default-on detached until-mergeable dispatch (opt-outs honoured); it never gates the run | rule | prose | script:dispatch-pr-review.sh | test-dispatch-pr-review.sh |
| LP-365 | skills/autonomous-loop/SKILL.md | q: **Parity consequence — single-iteration mode reaches the post-PR drain.** | single-iteration run produced a PR | the drain still dispatches via step 5.5 (and the PR-create hook); the per-PR marker keeps it to one dispatch | rule | prose | script:hook-dispatch-on-pr-create.sh | test-hook-dispatch-on-pr-create.sh |
| LP-366 | skills/autonomous-loop/SKILL.md | q: **The loop's own EVALUATE review-heal is an ADDITIONAL gate, not the only drain.** | multi-iteration EVALUATE | run the extra diff-only review-heal (no --until-mergeable, never merges); never a substitute for step 5.5 | rule | prose | - | GAP |
| LP-367 | skills/autonomous-loop/SKILL.md | q: **Multi-iteration interplay with the detached drain (R9 — do NOT duplicate or redesign).** | the detached drain may still push to the PR branch | a stacked iter N+1 or a human merge SHOULD wait for a terminal READY / ESCALATED | rule | prose | - | GAP |
| LP-368 | skills/autonomous-loop/SKILL.md | q: The autonomous loop never touches the job lifecycle. | job moves pending/ → in-progress/ → done/ or failed/ | Supervisor moves it; the loop never does | rule | prose | - | GAP |
| LP-369 | skills/autonomous-loop/SKILL.md | q: Capture the emitted `SUPERVISOR_RESULT` block (the last one in the transcript | Supervisor emitted a result | record n, brief_path, status, pr_url, rubric_score, branch, summary, error, heal_decision, escalation_reason into iterations[] | deterministic | prose | - | GAP |
| LP-370 | skills/autonomous-loop/SKILL.md | q: **`review_heal` field (added for the chained EVALUATE review-heal step):** | review-heal skipped / ran | review_heal null / the parsed REVIEW_HEAL_RESULT (never READY from EVALUATE) | deterministic | prose | - | GAP |
| LP-371 | skills/autonomous-loop/SKILL.md | q: **Fallback when Supervisor emits no `SUPERVISOR_RESULT`** | zero SUPERVISOR_RESULT blocks this iteration | infer the loop outcome from filesystem evidence | deterministic | prose | - | GAP |
| LP-372 | skills/autonomous-loop/SKILL.md | q: If `.supervisor/jobs/in-progress/{basename(current_brief_path)}` still exists | brief still in in-progress/ | half-state; terminate as below | deterministic | prose | - | GAP |
| LP-373 | skills/autonomous-loop/SKILL.md | q: If `.supervisor/jobs/done/{basename(current_brief_path)}` exists but no `SUPERVISOR_RESULT` was emitted | brief in done/ but no result | result-emission failure; terminate as below | deterministic | prose | - | GAP |
| LP-374 | skills/autonomous-loop/SKILL.md | q: If `.supervisor/jobs/failed/{basename(current_brief_path)}` exists but no `SUPERVISOR_RESULT` was emitted | brief in failed/ but no result | crash before emission; terminate as below | deterministic | prose | - | GAP |
| LP-375 | skills/autonomous-loop/SKILL.md | q: In all three cases, v1 terminates the loop with `AUTONOMOUS_RUN.status: failed` | any of the three no-result cases | failed, supervisor_failed_other, plus a synthetic iteration entry (error no_supervisor_result_emitted) | deterministic | prose | - | GAP |
| LP-376 | skills/autonomous-loop/SKILL.md | q: **AC-2 single-iteration short-circuit:** | single-iteration mode | done, status_reason null, last_phase EXECUTE; never enter EVALUATE | deterministic | prose | - | GAP |
| LP-377 | skills/autonomous-loop/SKILL.md | h: ### EVALUATE PR-base verification (AC-3 + AC-15) | multi-iteration EVALUATE, before signals | verify the iteration's PR targets the expected base (second line of defense) | deterministic | prose | - | GAP |
| LP-378 | skills/autonomous-loop/SKILL.md | q: `iteration == 1` — first iteration has no parent iter | iteration 1 | skip PR-base verification | deterministic | prose | - | GAP |
| LP-379 | skills/autonomous-loop/SKILL.md | q: `--no-stacked-branches` is active — every iter branches from `main` | --no-stacked-branches | skip PR-base verification | deterministic | prose | - | GAP |
| LP-380 | skills/autonomous-loop/SKILL.md | q: `pr_url` is null — Supervisor failed before creating a PR (merge conflict, env error, etc.) | pr_url null | skip (never gh pr view null); a failed status then takes default termination, supervisor_failed_other | deterministic | prose | - | GAP |
| LP-381 | skills/autonomous-loop/SKILL.md | q: decision: "pr_base_verify_skipped_non_interactive" | gh pr view baseRefName fails twice and the run is non-interactive | log, record pr_base_verify_skipped_non_interactive, go to signal evaluation | deterministic | prose | - | test-non-interactive-gates-seam.sh |
| LP-382 | skills/autonomous-loop/SKILL.md | q: AC-14 interactive fallback | gh pr view fails twice, interactive | ask retry / skip-verify-once / abort | deterministic | prose | - | GAP |
| LP-383 | skills/autonomous-loop/SKILL.md | q: auto-abort with status_reason="user_aborted_gh_retry" | third retry fails, then a second retry pick fails / abort picked | at most one re-prompt, then aborted user_aborted_gh_retry | deterministic | prose | - | GAP |
| LP-384 | skills/autonomous-loop/SKILL.md | q: status_reason="iter_pr_base_mismatch" | actual base differs from expected base | aborted, iter_pr_base_mismatch; exit | deterministic | prose | - | GAP |
| LP-385 | skills/autonomous-loop/SKILL.md | q: The verification site here is the **second line of defense** | Supervisor's own Phase 4 self-verify was silenced | this site still catches the mismatch; identical retry policy on both sites | rule | prose | - | GAP |
| LP-386 | skills/autonomous-loop/SKILL.md | h: ### EVALUATE review-heal step (chained PR review-and-heal — fresh isolated Task context) | PR-base verification passed, before any signal | run the chained review-and-heal step and record its outcome | deterministic | prose | - | GAP |
| LP-387 | skills/autonomous-loop/SKILL.md | q: **This is an ADDITIONAL multi-iteration-only gate, not the post-PR drain.** | multi-iteration EVALUATE | diff-only review-heal feeding the stacking decision; never replaces step 5.5's drain | rule | prose | - | GAP |
| LP-388 | skills/autonomous-loop/SKILL.md | q: `pr_url` is null — the iteration did not produce a PR (Supervisor failed | pr_url null | skip review-heal; go to signal evaluation | deterministic | prose | - | GAP |
| LP-389 | skills/autonomous-loop/SKILL.md | q: `SUPERVISOR_RESULT.status == failed` — the iteration did not complete successfully | Supervisor status failed | skip review-heal (runs only after completed / completed_with_escalation with a PR) | deterministic | prose | - | GAP |
| LP-390 | skills/autonomous-loop/SKILL.md | q: **Execution form (AC6 — Task step, NOT a nested `claude` process):** | running review-heal from /autonomous | a fresh-context Task step runs the loop body inline; never a nested process, never spawn review-pr-runner | rule | prose | - | GAP |
| LP-391 | skills/autonomous-loop/SKILL.md | q: **Record the outcome:** attach the parsed `REVIEW_HEAL_RESULT` | review-heal returned | attach the result to iterations[] under review_heal | deterministic | prose | - | GAP |
| LP-392 | skills/autonomous-loop/SKILL.md | q: **`PASS`** → the PR diff is clean | decision PASS | continue to signal evaluation; no change to iterate-or-stop | deterministic | prose | - | GAP |
| LP-393 | skills/autonomous-loop/SKILL.md | q: **`ESCALATED`** → review-heal exhausted its bound or the reviewer returned `NEEDS_HUMAN` | decision ESCALATED: interactive / --non-interactive-fallback | surface via the existing escalation prompt (continue / stop), record review_heal_escalated / aborted review_heal_escalated_non_interactive | deterministic | prose | - | test-non-interactive-gates-seam.sh |
| LP-394 | skills/autonomous-loop/SKILL.md | q: **`READY` / any unrecognized decision** → EVALUATE **never emits `READY`** | READY or an unknown decision | treat as terminal non-re-iterate; fall through like PASS; never loop to PLAN or ask | deterministic | prose | - | GAP |
| LP-395 | skills/autonomous-loop/SKILL.md | q: **Forward-compat with the additive v2 drain fields** | additive drain fields present | ignore them; key only off decision and the v1 core fields | rule | prose | - | GAP |
| LP-396 | skills/autonomous-loop/SKILL.md | q: Review-heal **never merges** the PR | review-heal runs | never merges, so it cannot retrigger the loop | rule | prose | - | GAP |
| LP-397 | skills/autonomous-loop/SKILL.md | h: ### Signal 1 — `status: completed` AND `rubric_score N/M` with N<M (stacked rubric gate) | completed with rubric_score N<M | pause at the rubric gate | deterministic | prose | - | GAP |
| LP-398 | skills/autonomous-loop/SKILL.md | q: **AC-5 webhook gate POST (when `--notify` AND `$LOOMWRIGHT_WEBHOOK_URL` are set)** | --notify and a webhook URL | background send-webhook.sh gate rubric POST before asking; never wait for delivery | deterministic | prose | script:send-webhook.sh | test-webhook.sh |
| LP-399 | skills/autonomous-loop/SKILL.md | q: **Stacked-branch mode (v14 default):** | stacked mode | offer continue-to-next-iteration / stop-here / force-continue-anyway (same as continue) | deterministic | prose | - | GAP |
| LP-400 | skills/autonomous-loop/SKILL.md | q: **`--no-stacked-branches` mode (v13-compat cadence):** | --no-stacked-branches | offer merge-and-continue / stop-here / force-continue-anyway (risk of conflicting PRs) | deterministic | prose | - | GAP |
| LP-401 | skills/autonomous-loop/SKILL.md | q: **Non-interactive fallback:** when `--non-interactive-fallback` is set AND no TTY, the gate does NOT call | rubric gate under --non-interactive-fallback | aborted, rubric_gate_closed_non_interactive (never auto-continue or auto-stop) | deterministic | prose | - | test-non-interactive-gates-seam.sh |
| LP-402 | skills/autonomous-loop/SKILL.md | q: **Stacked mode — `continue-to-next-iteration` (no merge verification needed):** | stacked continue | write the stacked-mode refined requirement; no merge check | deterministic | prose | - | GAP |
| LP-403 | skills/autonomous-loop/SKILL.md | q: block MUST contain the line `Base Branch: <iter_N_branch_name>` verbatim | stacked iteration brief | Configuration carries Base Branch; Criterion 13 FAILs it otherwise; re-discovery compares against the parent branch | rule | prose | - | GAP |
| LP-404 | skills/autonomous-loop/SKILL.md | q: Out-of-order merge of stacked PRs corrupts the stack. | merging stacked PRs | merge iter 1 first, then iter 2, in iterations[] order | rule | prose | - | GAP |
| LP-405 | skills/autonomous-loop/SKILL.md | q: **If user picks `merge-and-continue`, the loop verifies the merge before re-planning.** | merge-and-continue picked | gh state MERGED, else local ancestry on the default branch; unverified ⇒ re-prompt | deterministic | prose | - | GAP |
| LP-406 | skills/autonomous-loop/SKILL.md | q: **Implementation note — `jq` is illustrative, not required.** | looking up iteration branches | keep them in memory; state.json writes are for persistence only | story | prose | - | GAP |
| LP-407 | skills/autonomous-loop/SKILL.md | q: **If both `gh` is unavailable AND `iter_N_branch_sha` is unresolvable** | merge cannot be positively verified | re-prompt the user; never proceed | deterministic | prose | - | GAP |
| LP-408 | skills/autonomous-loop/SKILL.md | q: The loop **never** advances to iteration N+1 on `merge-and-continue` until | merge-and-continue without a confirmed merge | never advance | rule | prose | - | GAP |
| LP-409 | skills/autonomous-loop/SKILL.md | q: **If `merge-and-continue` (verified):** create refined requirement | merge verified | write the merge-and-continue refined requirement, loop to PLAN, record user_picked_merge_and_continue | deterministic | prose | - | GAP |
| LP-410 | skills/autonomous-loop/SKILL.md | q: **If `stop-here`:** summary status=done | stop-here picked | done, record rubric_final_score, last_phase EVALUATE; exit | deterministic | prose | - | GAP |
| LP-411 | skills/autonomous-loop/SKILL.md | q: **If `force-continue-anyway`:** create refined requirement as above | force-continue-anyway picked | write the refined requirement unverified, record user_picked_force_continue_anyway, loop to PLAN | deterministic | prose | - | GAP |
| LP-412 | skills/autonomous-loop/SKILL.md | h: ### Signal 2 — `status: failed` AND Option C triggered this iteration | Supervisor returned failed | run the Option C detection algorithm | deterministic | prose | - | GAP |
| LP-413 | skills/autonomous-loop/SKILL.md | q: **Iteration-scoping anchor — anchor by filename, not by global grep:** | detecting this iteration's Option C | anchor on jobs/failed/{basename(current_brief_path)} existence | rule | prose | - | GAP |
| LP-414 | skills/autonomous-loop/SKILL.md | q: **Why not `grep "inter_subtask_gap" .supervisor/state.md` directly:** | tempted to grep state.md | never consult state.md (atomic rewrites can leave stale content) | rule | prose | - | GAP |
| LP-415 | skills/autonomous-loop/SKILL.md | q: Supervisor failed for some reason that didn't move this iteration's | failed brief absent from failed/ | not Option C; default termination | deterministic | prose | - | GAP |
| LP-416 | skills/autonomous-loop/SKILL.md | q: the grep-stable substring "inter_subtask_gap" (any match = Option C) | failed brief exists | gap detected iff the brief, SUPERVISOR_RESULT.error or .summary contains inter_subtask_gap (error/summary primary) | deterministic | prose | - | GAP |
| LP-417 | skills/autonomous-loop/SKILL.md | q: Failed brief exists but no gap signal | failed brief, no gap substring | default termination | deterministic | prose | - | GAP |
| LP-418 | skills/autonomous-loop/SKILL.md | q: If `gap_detected=true`: Option C was the trigger. **No merge prompt** | gap detected | write the Option-C refined requirement, loop to PLAN, record supervisor_option_c_detected; no merge prompt | deterministic | prose | - | GAP |
| LP-419 | skills/autonomous-loop/SKILL.md | q: The `_detected` suffix is a deliberate naming convention | a policy decision is inferred, not chosen by a user at a loop gate | name it with the _detected suffix | rule | prose | - | GAP |
| LP-420 | skills/autonomous-loop/SKILL.md | h: ### No-rubric gate (v14.0.0+ — `status: completed` AND `rubric_score` is null) | completed, no rubric, multi-iter | fire the no-rubric gate (continue / stop) | deterministic | prose | - | GAP |
| LP-421 | skills/autonomous-loop/SKILL.md | q: **AC-5 webhook gate POST first (when `--notify` set):** | --notify set at the no-rubric gate | background send-webhook.sh gate no_rubric POST before asking | deterministic | prose | script:send-webhook.sh | test-webhook.sh |
| LP-422 | skills/autonomous-loop/SKILL.md | q: **Non-interactive fallback:** when `--non-interactive-fallback` is set AND no TTY, the gate exits with | no-rubric gate under --non-interactive-fallback | done, no_rubric_in_non_interactive (clean exit, not an abort) | deterministic | prose | - | test-non-interactive-gates-seam.sh |
| LP-423 | skills/autonomous-loop/SKILL.md | q: **`continue`:** create refined requirement (same template shape as Signal 1's | user picks continue | write the refined requirement, loop to PLAN, record user_continued_no_rubric | deterministic | prose | - | GAP |
| LP-424 | skills/autonomous-loop/SKILL.md | q: **`stop`:** emit AUTONOMOUS_RUN.status=done, status_reason="user_stopped_at_no_rubric_gate" | user picks stop | done, user_stopped_at_no_rubric_gate; exit | deterministic | prose | - | GAP |
| LP-425 | skills/autonomous-loop/SKILL.md | h: ### Default termination — any other SUPERVISOR_RESULT outcome ends the loop | no signal or gate fired | emit the AUTONOMOUS_RUN summary and exit per the table | deterministic | prose | - | GAP |
| LP-426 | skills/autonomous-loop/SKILL.md | q: rubric_score = `N/N` (perfect score) | completed with a perfect score | terminate; done, null | deterministic | prose | - | GAP |
| LP-427 | skills/autonomous-loop/SKILL.md | q: user picks `stop-here` at rubric gate | completed N<M and stop-here | terminate; done, user_stopped_at_rubric_gate | deterministic | prose | - | GAP |
| LP-428 | skills/autonomous-loop/SKILL.md | q: rubric_score is null, user picks `stop` at no-rubric gate | completed, no rubric, stop | terminate; done, user_stopped_at_no_rubric_gate | deterministic | prose | - | GAP |
| LP-429 | skills/autonomous-loop/SKILL.md | q: rubric_score is null, non-interactive fallback | completed, no rubric, non-interactive | terminate; done, no_rubric_in_non_interactive | deterministic | prose | - | GAP |
| LP-430 | skills/autonomous-loop/SKILL.md | q: terminate; populate `escalations_seen` | completed_with_escalation | terminate; done, caveat recorded in escalations_seen | deterministic | prose | - | GAP |
| LP-431 | skills/autonomous-loop/SKILL.md | q: `pr_url == null` (Supervisor pre-PR failure, AC-15) | failed with no PR | terminate; failed, supervisor_failed_other | deterministic | prose | - | GAP |
| LP-432 | skills/autonomous-loop/SKILL.md | q: inter_subtask_gap NOT detected, `pr_url` non-null | failed, no gap, PR exists | terminate; failed, supervisor_failed_other | deterministic | prose | - | GAP |
| LP-433 | skills/autonomous-loop/SKILL.md | q: `base_branch_mismatch` from Supervisor Phase 4.5 cleanup (S3-added path) | failed with base_branch_mismatch | terminate; failed, supervisor_base_branch_mismatch | deterministic | prose | - | GAP |
| LP-434 | skills/autonomous-loop/SKILL.md | q: terminate (loop stops; do NOT re-iterate) | failed with preflight_overlap_detected | terminate, never re-iterate; failed, preflight_overlap_detected | deterministic | prose | - | GAP |
| LP-435 | skills/autonomous-loop/SKILL.md | q: terminate (no auto-resume in v1) | Supervisor checkpoint | terminate; aborted, supervisor_checkpoint | deterministic | prose | - | GAP |
| LP-436 | skills/autonomous-loop/SKILL.md | h: ### Phase 1.5 pre-flight gate — CI fail-closed termination (v14.8.0+) | Supervisor pre-flight classifies OVERLAP / SUPERSEDED | the loop sees it only through SUPERVISOR_RESULT | deterministic | prose | - | GAP |
| LP-437 | skills/autonomous-loop/SKILL.md | q: **CI fail-closed behavior.** When the inlined `/supervisor` invocation | non-interactive or non-TTY inner Supervisor hits OVERLAP / SUPERSEDED | Supervisor fails closed; the loop terminates with preflight_overlap_detected and does not re-iterate | deterministic | prose | - | GAP |
| LP-438 | skills/autonomous-loop/SKILL.md | q: **Flag-forwarding note:** the loop's complete `/supervisor` forward set | every iteration | --skip-preflight-sync is never forwarded, so Phase 1.5 runs every iteration; skip only via a manual /supervisor run | rule | prose | - | GAP |
| LP-439 | skills/autonomous-loop/SKILL.md | q: **Complements — does NOT double-fire with — EVALUATE PR-base verification | pre-flight overlap vs PR base after FINALIZE | distinct gates, timing and status reasons; never overlap | rule | prose | - | GAP |
| LP-440 | skills/autonomous-loop/SKILL.md | q: Because the pre-flight gate scopes its overlap scan to `$BASE_BRANCH` (AC6) | stacked run's own parent commits / PR | not flagged as overlap | story | prose | - | GAP |
| LP-441 | skills/autonomous-loop/SKILL.md | h: ### Max-iterations cap | Signal 1 or 2 would re-plan and iteration + 1 > max_iterations | paused_max_iterations, max_iterations_reached; record the unprocessed intent | deterministic | prose | - | GAP |
| LP-442 | skills/autonomous-loop/SKILL.md | q: The status enum is **autonomous-layer-only** | emitting AUTONOMOUS_RUN.status | only done / paused_max_iterations / aborted / failed, never a SUPERVISOR_RESULT value | rule | prose | - | GAP |
| LP-443 | skills/autonomous-loop/SKILL.md | h: ### summary.md format | run ends | write summary.md with the listed fields and closed status_reason set | deterministic | prose | - | GAP |
| LP-444 | skills/autonomous-loop/SKILL.md | q: **launch_pad_summary:** `LAUNCH_PAD_RESULT.summary` verbatim — written only when | status_reason launch_pad_cant_ask_non_interactive / otherwise | write the line verbatim / omit it | deterministic | prose | - | GAP |
| LP-445 | skills/autonomous-loop/SKILL.md | h: ### state.json (machine-readable sidecar) | writing state.json | same fields as summary.md; not authoritative for resume; no hook validates it | rule | prose | - | GAP |
| LP-446 | skills/autonomous-loop/SKILL.md | q: **v1-only `_v1_note` field:** | tooling finds _v1_note | refuse it for resume / recovery / cross-session queries; only the two ACQUIRE signals are hook-readable | rule | prose | - | GAP |
| LP-447 | skills/autonomous-loop/SKILL.md | q: **Concurrent-session safety (v14.2.0+).** | a concurrent /launch-pad writes to pending/ | the result block isolates this loop's save; ls-diff fallback stays single-session-only | rule | prose | - | GAP |
| LP-448 | skills/autonomous-loop/SKILL.md | q: User discards at Phase 6 \| `new_briefs` empty after Phase 6 | discard at Phase 6 | clean exit, aborted | deterministic | prose | - | GAP |
| LP-449 | skills/autonomous-loop/SKILL.md | q: Launch Pad ignores rubric-preservation inline instruction | saved brief has no rubric | abort rubric_dropped_from_brief; the user must move the stale pending brief before re-running | deterministic | prose | - | GAP |
| LP-450 | skills/autonomous-loop/SKILL.md | q: Concurrent autonomous run or manual launch-pad | more than one new brief | abort concurrent_session_detected | deterministic | prose | - | GAP |
| LP-451 | skills/autonomous-loop/SKILL.md | q: Session terminated mid-loop | process killed / terminal closed | unsupported in v1; manual cleanup and restart | story | prose | - | GAP |
| LP-452 | skills/autonomous-loop/SKILL.md | q: `gh` unavailable for merge check | gh pr view fails | fall back to git merge-base --is-ancestor; neither confirms ⇒ re-prompt | deterministic | prose | - | GAP |
| LP-453 | skills/autonomous-loop/SKILL.md | q: `inter_subtask_gap` string drift | the grep-stable string changes | Signal 2 silently fails; default termination supervisor_failed_other | story | prose | - | GAP |
| LP-454 | skills/autonomous-loop/SKILL.md | q: **Launch Pad inline workflow:** referenced via Step 0 + PLAN invocation | reusing Launch Pad | only the inlined rubric instruction; no Launch Pad source change | rule | prose | - | GAP |
| LP-455 | skills/autonomous-loop/SKILL.md | q: **Supervisor inline workflow:** referenced via Step 0 + EXECUTE invocation | reusing Supervisor | no instruction modifications | rule | prose | - | GAP |
| LP-456 | skills/autonomous-loop/SKILL.md | q: **Adjudication 4-option escalation:** Supervisor surfaces existing options | adjudication | Supervisor surfaces A/B/C/D; the loop never auto-picks; Option C yields failed + inter_subtask_gap | rule | prose | - | GAP |
| LP-457 | skills/autonomous-loop/SKILL.md | q: **SUPERVISOR_RESULT schema (v12.2):** v1 reads existing fields only | reading SUPERVISOR_RESULT | existing fields only; no schema change | rule | prose | - | GAP |
| LP-458 | skills/autonomous-loop/SKILL.md | q: **`.supervisor/jobs/` lifecycle:** Supervisor remains sole writer/mover | job files | Supervisor is the sole mover; the loop only reads pending/ and failed/ | rule | prose | - | GAP |
| LP-459 | skills/autonomous-loop/SKILL.md | q: **`.supervisor/state.md`:** the `## Session` block | state.md | the Session block is hook-projected; Context-Keeper writes the other sections; the loop never greps it | rule | prose | - | GAP |
| LP-460 | commands/autonomous.md | q: **Execute this workflow inline as the main thread.** Do not delegate to any `autonomous-*-runner` | /autonomous invoked | run inline; never add a delegation layer (it could not ask and pushes Task descendants one nesting layer deeper) | rule | prose | - | GAP |
| LP-461 | commands/autonomous.md | q: **Foreground-assisted automation, not fire-and-forget.** | gates fire in-session | the user must be at the terminal unless --non-interactive-fallback is passed (gates then fail closed) | rule | prose | - | GAP |
| LP-462 | commands/autonomous.md | q: if no URL is resolvable, `--notify` warns once at INIT rather than silently doing nothing | --notify with no resolvable URL | warn once at INIT; never silently no-op | deterministic | prose | - | GAP |
| LP-463 | commands/autonomous.md | q: **Post-PR until-mergeable drain — runs in BOTH single- and multi-iteration mode | any mode produced a PR | Supervisor step 5.5 dispatches the detached drain (never gates); downstream work waits for READY / ESCALATED (R9) | rule | prose | script:dispatch-pr-review.sh | test-dispatch-pr-review.sh |
| LP-464 | commands/autonomous.md | q: **Chained review-and-heal (after PR-base verification, before Signal evaluation):** | iteration completed with a PR / skipped when no PR or failed | Task-step review-heal; PASS ⇒ signals, ESCALATED ⇒ existing escalation prompt (fail closed non-interactive), READY or unknown ⇒ terminal non-re-iterate | deterministic | prose | - | GAP |
| LP-465 | commands/autonomous.md | q: **CI / non-interactive note:** if `[ ! -t 0 ]` OR `$CI` is set | non-TTY or CI, multi-iter, no fallback flag | INIT aborts non_interactive_without_fallback with two recovery commands | deterministic | prose | - | GAP |
| LP-466 | commands/autonomous.md | q: **Cost-profile note:** `--cheap` **is forwarded** (v15.2.0+) | --cheap passed | appended to every inlined /supervisor job in every iteration | deterministic | prose | - | GAP |
| LP-467 | commands/autonomous.md | q: **Terminology note:** an **iteration** (this command) | naming units | iteration = one pass on the same goal; /automate item = one goal from a queue | story | prose | - | GAP |
| LP-468 | commands/autonomous.md | q: Inline requirement string. Loop writes it to | requirement given inline | write it to the session-id requirement file with an optional rubric placeholder | deterministic | prose | - | GAP |
| LP-469 | commands/autonomous.md | q: in that auto-author case the loop appends the human-approved rubric back into this file in place | --requirement file without a rubric, multi-iter, rubric approved | the freeze modifies the file on disk (pass a copy to keep the original) | deterministic | prose | - | GAP |
| LP-470 | commands/autonomous.md | q: Disable multi-iter mode; run Launch Pad + Supervisor once and exit | --single-iteration | one Launch Pad + Supervisor pass, then exit | deterministic | prose | - | GAP |
| LP-471 | commands/autonomous.md | q: Iter N+1 branches from `main` instead of `iterations[N].branch` | --no-stacked-branches (multi-iter only) | each iteration's PR branches from main | deterministic | prose | - | GAP |
| LP-472 | commands/autonomous.md | q: if neither resolves, `--notify` **fails loud** with one warning at INIT step 0 | --notify, neither env nor user-scope URL | one warning at INIT; desktop banners unaffected | deterministic | prose | - | GAP |
| LP-473 | commands/autonomous.md | q: **and separately to the inlined Launch Pad** | --non-interactive-fallback | forward --non-interactive to /supervisor and separately to Launch Pad; one flag suffices for CI | deterministic | prose | - | test-non-interactive-gates-seam.sh |
| LP-474 | commands/autonomous.md | q: `N=0` or `N>10` rejected at INIT with `status: aborted, status_reason: "invalid_max_iterations"` | N outside 1..10 | aborted, invalid_max_iterations | deterministic | prose | - | GAP |
| LP-475 | commands/autonomous.md | q: **Edge case `N=1`:** valid but degenerate | N=1 and Signal 1/2 would fire | paused_max_iterations, max_iterations_reached | deterministic | prose | - | GAP |
| LP-476 | commands/autonomous.md | q: Combining with `--single-iteration` aborts at INIT with `status_reason: "conflicting_mode_flags"` | --allow-multi-iteration alone / with --single-iteration | no-op with a deprecation warning / abort conflicting_mode_flags | deterministic | prose | - | GAP |
| LP-477 | commands/autonomous.md | q: **Forward the Sonnet cost profile (v15.2.0+).** | --cheap passed | appended to every /supervisor job; not gated on the fallback flag | deterministic | prose | - | GAP |
| LP-478 | commands/autonomous.md | q: **Opt-in token-spend ceiling (red-team-hardening/06).** | --max-tokens N: before each iteration the ledger total breaches N or is unreadable | aborted, token_ceiling_reached; persisted in state.json and forwarded to /supervisor | deterministic | prose | script:read-token-ledger.sh | test-read-token-ledger.sh |
| LP-479 | commands/autonomous.md | q: A `run_lock_reentrant owner=<outer> …` line (exit 0) is NOT an abort | INIT lock acquire answers reentrant / degraded | proceed (own release a no-op) / note once and proceed | deterministic | prose | script:run-lock.sh acquire | test-run-lock.sh |
| LP-480 | commands/autonomous.md | q: **`--cheap` interaction note (and the complete `/supervisor` forward set):** | building the /supervisor call | exactly four flags under their conditions; no other flag; the one other forward goes to Launch Pad | rule | prose | - | test-non-interactive-gates-seam.sh |
| LP-481 | commands/autonomous.md | q: **`--skip-preflight-sync` interaction note:** | every iteration | never forwarded; Phase 1.5 runs each iteration; OVERLAP / SUPERSEDED fails closed under the fallback flag | rule | prose | - | GAP |
| LP-482 | commands/autonomous.md | h: ### Not shipped in v14.0.0 | deferred flags | gate-timeout, status/continue/abort/background/auto-merge are not shipped | story | prose | - | GAP |
| LP-483 | commands/autonomous.md | q: **`--gate-timeout-minutes`** — explicitly deferred. | unattended run | MUST pass --non-interactive-fallback (no gate timeout exists) | rule | prose | - | GAP |
| LP-484 | commands/autonomous.md | q: **`--status` / `--continue` / `--abort` / `--background` / `--auto-merge`** — still deferred. | resume or auto-merge wanted | not available | story | prose | - | GAP |
| LP-485 | commands/autonomous.md | q: **Quoting paths with spaces:** if the `--requirement <path>` value contains spaces | path contains spaces | double-quote the whole path | rule | prose | - | GAP |
| LP-486 | commands/autonomous.md | h: ### Step 0 — Load Canonical Workflow Bodies + Protocol Skill (always) | every run | read the three canonical files via the plugin-root path, never loomwright/ | rule | prose | - | GAP |
| LP-487 | commands/autonomous.md | h: ### Multi-Iteration Mode (v14.0.0 default) | multi-iteration run | INIT → PLAN → EXECUTE → EVALUATE loop; branch per the table | deterministic | prose | - | GAP |
| LP-488 | commands/autonomous.md | q: Run **chained review-and-heal** as a `Task` step | completed / completed_with_escalation with a PR | run review-heal before signals; PASS continue, ESCALATED surface, READY terminal | deterministic | prose | - | GAP |
| LP-489 | commands/autonomous.md | q: Fire **Signal 1 rubric gate | completed with rubric N<M | stacked: continue / stop-here / force-continue; non-stacked: merge-and-continue with gh verification | deterministic | prose | - | GAP |
| LP-490 | commands/autonomous.md | q: Fire **no-rubric gate** (new in v14): `continue / stop` | completed, no rubric, multi-iter | no-rubric gate continue / stop | deterministic | prose | - | GAP |
| LP-491 | commands/autonomous.md | q: Re-plan immediately (no merge needed; job was abandoned via adjudication Option C) | failed with inter_subtask_gap | re-plan immediately | deterministic | prose | - | GAP |
| LP-492 | commands/autonomous.md | q: Skip PR-base verification entirely (AC-15) | failed with pr_url null | skip base verification; default termination supervisor_failed_other | deterministic | prose | - | GAP |
| LP-493 | commands/autonomous.md | q: Terminate the loop. Specifically: `completed_with_escalation` → done with escalations_seen | anything else | completed_with_escalation done; failed other failed; checkpoint aborted | deterministic | prose | - | GAP |
| LP-494 | commands/autonomous.md | h: ### Single-Iteration Mode (`--single-iteration`) | --single-iteration | INIT → PLAN → EXECUTE → DONE; EVALUATE short-circuits to done | deterministic | prose | - | GAP |
| LP-495 | commands/autonomous.md | h: ### Stacked-branch behavior (v14 default) | iteration N+1 reached | branch per the stacked / non-stacked rules below | deterministic | prose | - | GAP |
| LP-496 | commands/autonomous.md | q: v13-style (`--no-stacked-branches`): iter N+1's feature branch is created from `main` | --no-stacked-branches | branch iter N+1 from main; merge iter N first or accept independent PRs | deterministic | prose | - | GAP |
| LP-497 | commands/autonomous.md | q: v14 default (stacked): iter N+1's feature branch is created from `iterations[N].branch` | stacked default | branch from iter N's branch, open the PR with --base iter N branch, verify baseRefName (AC-14 retry) | deterministic | prose | - | GAP |
| LP-498 | commands/autonomous.md | q: Out-of-order merge of a stacked PR can corrupt `main` | merging a stack | merge bottom-first in iterations[] order | rule | prose | - | GAP |
| LP-499 | commands/autonomous.md | h: ### What runs inline (Launch Pad's existing AskUserQuestion gates bubble up) | Launch Pad gates fire / --non-interactive-fallback | prompts surface in-session / Launch Pad gets --non-interactive and takes named branches | deterministic | prose | - | GAP |
| LP-500 | commands/autonomous.md | h: ### What runs inline (Supervisor's existing AskUserQuestion gates bubble up) | adjudication fires | user answers in-session; never auto-picked; Option C ⇒ failed + inter_subtask_gap ⇒ re-plan | deterministic | prose | - | GAP |
| LP-501 | commands/autonomous.md | h: ### Inline instruction to Launch Pad (rubric preservation + auto-authoring) | invoking Launch Pad | add the preserve-verbatim directive; multi-iter without a rubric also requests auto-authoring | deterministic | prose | - | GAP |
| LP-502 | commands/autonomous.md | q: If a real rubric is missing from the saved brief, the iteration aborts cleanly | requirement rubric not in the saved brief (has_rubric) | abort rubric_dropped_from_brief | deterministic | prose | - | GAP |
| LP-503 | commands/autonomous.md | q: **Single-iteration mode and the already-has-a-rubric case are unchanged — preserve-only, never auto-authored.** | single-iteration or rubric present | preserve only; never author | rule | prose | - | GAP |
| LP-504 | commands/autonomous.md | h: ### Single-iteration smoke test | example | single-iteration walkthrough | story | prose | - | GAP |
| LP-505 | commands/autonomous.md | h: ### Multi-iteration with rubric-driven re-planning | example | rubric-gate merge-and-continue walkthrough | story | prose | - | GAP |
| LP-506 | commands/autonomous.md | h: ### Multi-iteration with Option-C re-planning | example | Option-C re-plan walkthrough | story | prose | - | GAP |
| LP-507 | commands/autonomous.md | q: **Brief-save detection (v14.2.0+): primary path is `LAUNCH_PAD_RESULT.saved_brief_path` | detecting the saved brief | validated result block primary; ls-diff fallback only (single-session constraint, concurrent_session_detected) | rule | prose | script:validate-launch-pad-result.py | test-result-validators.sh |
| LP-508 | commands/autonomous.md | q: **Multi-iteration requires user merge between iterations.** | multi-iteration risk | user merge verified via gh or ancestry; force-continue risks conflicting PRs | story | prose | - | GAP |
| LP-509 | commands/autonomous.md | q: **Rubric per-item PASS/FAIL is not available** | refining a requirement | only the N/M score is available; rely on re-discovery | story | prose | - | GAP |
| LP-510 | commands/autonomous.md | q: **Crash recovery is unsupported.** | re-run after a crash | may duplicate work; clean up manually first | story | prose | - | GAP |
| LP-511 | commands/autonomous.md | q: **No QA integration in the loop.** | quality in the loop | trust Phase 4.5 + Rubric Grader; QA is deferred | story | prose | - | GAP |
| LP-512 | commands/autonomous.md | q: **Cost: multi-iteration loops are genuinely expensive.** | cost | each iteration is a full Launch Pad + Supervisor run | story | prose | - | GAP |
| LP-513 | commands/autonomous.md | q: **`.gitignore` coverage.** The loop writes to | loop writes under .supervisor/ | state-management keeps .supervisor/ gitignored; re-add it if stripped | rule | prose | - | GAP |
| LP-514 | commands/autonomous.md | h: ### Loop aborts with `status_reason: "rubric_dropped_from_brief"` | rubric_dropped_from_brief abort | move the stale pending brief to failed/ before re-running | judgment | prose | - | GAP |
| LP-515 | commands/autonomous.md | h: ### Loop aborts with `status_reason: "concurrent_session_detected"` | concurrent_session_detected abort | kill the other session, clean stray briefs, restart | judgment | prose | - | GAP |
| LP-516 | commands/autonomous.md | h: ### Iteration N reported `completed` but I don't see PR N's changes in iteration N+1 | force-continue without merging | merge PR N and pick merge-and-continue next time | judgment | prose | - | GAP |
| LP-517 | commands/autonomous.md | h: ### `inter_subtask_gap` re-plan trigger doesn't fire even though I picked Option C | Option C picked, no re-plan | check the failed/ brief exists or the grep-stable string drifted; re-run manually | judgment | prose | - | GAP |
| LP-518 | commands/autonomous.md | h: ### Supervisor returned `checkpoint` and the loop aborted | checkpoint abort | run /supervisor --continue manually, then start a new /autonomous | judgment | prose | - | GAP |
| LP-519 | agents/launch-pad.md | h: ### Dependency Graph | Phase 4 output template (outside a fence under a CommonMark closer rule) | draw edges from requires.from entries, each from: X an edge consumer → X | deterministic | prose | - | GAP |
| LP-520 | agents/launch-pad.md | h: ### Parallelism Analysis | Phase 4 output template (outside a fence under a CommonMark closer rule) | batch subtasks with empty requires first; dependents in later batches | deterministic | prose | - | GAP |

## Gap list (ordered by risk)

1. LP-019 — the leading-token status contract feeds /autonomous PLAN step 4; the validator's closed-key rejection is not exercised for LAUNCH_PAD_RESULT
2. LP-020 — FAIL-never-saves is the mandatory Plan Review gate's core invariant and no test exercises the save decision
3. LP-108 — the never-machine-author-cmd: rule guards arbitrary shell execution; untested
4. LP-118 — skipping the MATERIALIZE re-run silently collapses the mandatory 3-attempt Plan Review into one effective review; nothing pins it
5. LP-129 — FAIL at attempt 3 must not save and must not reset the cap; untested
6. LP-142 — non-interactive auto-strip of unstamped cmd: bullets is a security gate (arbitrary shell in Phase 4.5) with no test
7. LP-159 — FAIL x3 save suppression and the never-reset cap are untested
8. LP-169 — FAIL x3 must never offer save; the branch is pure prose with no test
9. LP-172 — Criterion 14 save rule (never an unreviewed executable brief) is untested
10. LP-181 — /autonomous maps can't-ask outcomes by the summary's leading token; nothing tests that the token is emitted
11. LP-204 — delegating /launch-pad to a runner turns every question gate into a can't-ask branch; no test pins the inline rule
12. LP-205 — collapsing Plan Review into main-thread self-validation would remove the mandatory gate; untested
13. LP-290 — the filename anchor is the only failed-iteration signal; untested
14. LP-296 — N=0 or N>10 rejection is untested
15. LP-303 — invalid --max-iterations must abort before any state write; untested
16. LP-304 — conflicting mode flags must abort; untested
17. LP-323 — has_rubric is inline awk with no test; a regression silently suppresses rubric auto-authoring or accepts an empty placeholder
18. LP-342 — the stale-session-id pre-snapshot check asks the user but names no can't-ask branch, so an unattended run would hang or improvise at this gate
19. LP-349 — rubric_dropped_from_brief is the only guard against multi-iteration silently degrading; untested
20. LP-351 — the freeze idempotency guard is untested; gating on a run-global flag would append duplicate rubric sections every iteration
21. LP-356 — the stacked --base-branch passthrough is untested; a missing flag stacks iteration N+1 on main
22. LP-363 — forwarding --skip-preflight-sync would silently disable the Phase 1.5 overlap gate in every iteration; untested
23. LP-367 — R9: stacking on or merging a branch the detached drain still mutates; the wait rule is untested prose
24. LP-371 — the no-SUPERVISOR_RESULT fallback is untested; a crash could be read as success
25. LP-375 — synthetic iteration entry + supervisor_failed_other on missing result is untested
26. LP-384 — iter_pr_base_mismatch is the second line of defense against a corrupted PR stack; untested
27. LP-394 — READY / unknown decisions must not re-plan; untested, a wrong branch could loop
28. LP-415 — failed-brief-absent ⇒ default termination is untested; a wrong branch would mis-fire Signal 2
29. LP-416 — Option C detection is a substring match across three sources; untested, a drift ends the loop as supervisor_failed_other
30. LP-418 — Option C re-plan (template + supervisor_option_c_detected) is untested
31. LP-437 — preflight_overlap_detected must terminate without re-iterating; an untested branch could loop on a precondition violation
32. LP-438 — the Phase 1.5 every-iteration guarantee rests on the forward set excluding --skip-preflight-sync; untested
33. LP-441 — the max-iterations cap is the loop's only spend bound besides --max-tokens; untested
34. LP-460 — delegating /autonomous adds a nesting layer and strips the ask tool from every inner gate; no test pins it
35. LP-481 — command mirror of the skip-preflight non-forward rule; drift would disable the overlap gate
36. LP-016 — blockers must suppress save; untested
37. LP-023 — BLOCKER classification decides whether save is offered; untested
38. LP-029 — requirement-file resolution scoping (only .supervisor/requirements/) is untested; a wrong scope hijacks literal goals
39. LP-031 — test -f failure must fall back to a literal goal, never invent a file; untested
40. LP-083 — verify-provides locates blocks by numeric id; a non-numeric scheme breaks the outputs gate
41. LP-086 — a false LAUNCHABLE lets overlapping workers run in parallel; untested
42. LP-087 — BLOCKED classification is untested
43. LP-094 — non-empty requires must be BLOCKED; untested
44. LP-101 — a home path anywhere in a brief blocks the lane's whole trail push; the authoring rule is untested
45. LP-122 — reviewing anything other than the MATERIALIZE scratch file reviews stale text; untested
46. LP-124 — pre-spawn gate-parse fixes must not consume review attempts; untested
47. LP-126 — the at-floor PASS refine loop consumes review attempts; the branch is untested
48. LP-127 — deferred at-floor issues must never block save; untested
49. LP-132 — NEEDS_HUMAN routing (2a / 2b / generic) is untested
50. LP-140 — strip-cmd-bullets must keep corpus-task:/qa-executor: bullets; untested
51. LP-143 — cap exhaustion in action 2a must fall through to FAIL handling; untested
52. LP-149 — 17c resolution must re-run MATERIALIZE and Plan Review; untested
53. LP-168 — blockers suppress save (save rules copy); untested
54. LP-170 — generic NEEDS_HUMAN save rule is untested
55. LP-171 — 17c NEEDS_HUMAN save rule is untested
56. LP-302 — keying gates on the TTY probe alone false-positives inside the host Bash tool; untested
57. LP-335 — a malformed LAUNCH_PAD_RESULT must fall back, never abort; untested
58. LP-336 — a saved path that fails test -f must be treated as malformed; untested
59. LP-337 — user_discarded_at_phase_6 mapping is untested
60. LP-339 — launch_pad_blocked mapping is untested
61. LP-340 — user_aborted_at_launch_pad mapping is untested
62. LP-341 — absent/invalid result block fallback and its audit record are untested
63. LP-343 — ls-diff empty ⇒ discard is untested
64. LP-344 — ls-diff single new brief selection is untested
65. LP-345 — concurrent_session_detected is untested
66. LP-358 — iteration 1 / non-stacked must omit --base-branch; untested
67. LP-359 — --non-interactive forward to /supervisor is untested at this paragraph
68. LP-380 — pr_url null must skip verification (never gh pr view null); untested
69. LP-382 — interactive gh-failure prompt is untested
70. LP-383 — the gh retry loop must be bounded to one re-prompt; untested
71. LP-386 — the chained review-heal step placement is untested
72. LP-388 — review-heal must be skipped without a PR; untested
73. LP-389 — review-heal must be skipped for a failed iteration; untested
74. LP-405 — merge-and-continue verification is untested; a premature click could stack on an unmerged base
75. LP-407 — unverifiable merge must re-prompt, never proceed; untested
76. LP-408 — never advance without a confirmed merge; untested
77. LP-465 — command mirror of the CI fail-closed rule is untested
78. LP-449 — the recovery path tells the user to drop --allow-multi-iteration, which is already a no-op (stale prose)
79. LP-501 — the command's auto-authoring paragraph omits the skill's no-authoring-under-fallback exception (mirror drift)
80. LP-505 — the worked example uses the deprecated --allow-multi-iteration and the non-stacked merge prompt (stale example)
81. LP-508 — states a merge is required between iterations, contradicting the stacked-branch default (stale prose)
82. LP-512 — says token budget caps are deferred though --max-tokens exists (stale prose)
83. LP-009 — untested deterministic branch in agents/launch-pad.md: the goal value is an existing .md path under .supervisor/requirements/
84. LP-021 — untested deterministic branch in agents/launch-pad.md: feasibility verdict
85. LP-022 — untested deterministic branch in agents/launch-pad.md: start of run (unless --skip-validation)
86. LP-024 — untested deterministic branch in agents/launch-pad.md: uncommitted changes / no gh auth / orphaned worktrees / stale CLAUDE.md
87. LP-025 — untested deterministic branch in agents/launch-pad.md: input resolves to a specific source doc that is modified or untracked
88. LP-026 — untested deterministic branch in agents/launch-pad.md: host CLAUDE.md has a level-2 Shared local services heading whose bounded body is non-empty
89. LP-027 — untested deterministic branch in agents/launch-pad.md: --skip-validation set
90. LP-035 — untested deterministic branch in agents/launch-pad.md: --discovery set
91. LP-042 — untested deterministic branch in agents/launch-pad.md: any check is NO-GO
92. LP-043 — untested deterministic branch in agents/launch-pad.md: some CAUTION, no NO-GO
93. LP-044 — untested deterministic branch in agents/launch-pad.md: all checks GO
94. LP-045 — untested deterministic branch in agents/launch-pad.md: verdict GO
95. LP-046 — untested deterministic branch in agents/launch-pad.md: verdict CAUTION
96. LP-047 — untested deterministic branch in agents/launch-pad.md: verdict NO-GO
97. LP-048 — untested deterministic branch in agents/launch-pad.md: user picks Override
98. LP-049 — untested deterministic branch in agents/launch-pad.md: user picks Revise goal
99. LP-050 — untested deterministic branch in agents/launch-pad.md: user picks Abort
100. LP-052 — untested deterministic branch in agents/launch-pad.md: CLAUDE.md lacks tech-stack info
101. LP-053 — untested deterministic branch in agents/launch-pad.md: after FEASIBILITY (GO, CAUTION, or overridden NO-GO)
102. LP-063 — untested deterministic branch in agents/launch-pad.md: neither orientation script exists, both emit nothing, or anything errors
103. LP-069 — untested deterministic branch in agents/launch-pad.md: contract carries incident_history / lacks it
104. LP-071 — untested deterministic branch in agents/launch-pad.md: no verified contract and both graph groups empty
105. LP-075 — untested deterministic branch in agents/launch-pad.md: a token is path:digits with a slash or .ext left side
106. LP-076 — untested deterministic branch in agents/launch-pad.md: direct git show lookup fails
107. LP-078 — untested deterministic branch in agents/launch-pad.md: computing the as-of column
108. LP-079 — untested deterministic branch in agents/launch-pad.md: ≥1 ref / 0 refs
109. LP-088 — untested deterministic branch in agents/launch-pad.md: brief has a single subtask
110. LP-096 — untested deterministic branch in agents/launch-pad.md: after DECOMPOSE
111. LP-097 — untested deterministic branch in agents/launch-pad.md: source_requirement resolved / not resolved
112. LP-098 — untested deterministic branch in agents/launch-pad.md: every brief
113. LP-099 — untested deterministic branch in agents/launch-pad.md: the brief has no Base commit line
114. LP-100 — untested deterministic branch in agents/launch-pad.md: shared_local_services set / unset
115. LP-102 — untested deterministic branch in agents/launch-pad.md: a CAUTION finding / an overridden NO-GO
116. LP-103 — untested deterministic branch in agents/launch-pad.md: churn surfaced on a touched path / nothing surfaced
117. LP-104 — untested deterministic branch in agents/launch-pad.md: ≥1 STALE ref / none
118. LP-107 — untested deterministic branch in agents/launch-pad.md: Phase 2.5 ran
119. LP-109 — untested deterministic branch in agents/launch-pad.md: target is this plugin's repo AND the brief modifies the plugin doc surface / otherwise
120. LP-116 — untested deterministic branch in agents/launch-pad.md: fewer than 3 bullets derivable
121. LP-133 — untested deterministic branch in agents/launch-pad.md: user picks Override and save
122. LP-134 — untested deterministic branch in agents/launch-pad.md: user picks Refine further on NEEDS_HUMAN
123. LP-135 — untested deterministic branch in agents/launch-pad.md: user picks Discard
124. LP-138 — untested deterministic branch in agents/launch-pad.md: interactive run
125. LP-141 — untested deterministic branch in agents/launch-pad.md: user picks discard (action 2a)
126. LP-153 — untested deterministic branch in agents/launch-pad.md: user picks Save and exit
127. LP-154 — untested deterministic branch in agents/launch-pad.md: user picks Refine further on PASS
128. LP-155 — untested deterministic branch in agents/launch-pad.md: user picks Edit sections
129. LP-156 — untested deterministic branch in agents/launch-pad.md: PASS on the 3rd spawn
130. LP-160 — untested deterministic branch in agents/launch-pad.md: user picks Refine offline
131. LP-161 — untested deterministic branch in agents/launch-pad.md: user picks Discard after FAIL x3
132. LP-163 — untested deterministic branch in agents/launch-pad.md: on save
133. LP-164 — untested deterministic branch in agents/launch-pad.md: after save
134. LP-176 — untested deterministic branch in agents/launch-pad.md: Save and exit or Override and save wrote the brief
135. LP-177 — untested deterministic branch in agents/launch-pad.md: Phase 6 Discard
136. LP-178 — untested deterministic branch in agents/launch-pad.md: Phase 1 BLOCKERS, or FAIL x3 then Refine offline / no choice
137. LP-179 — untested deterministic branch in agents/launch-pad.md: in-session abort, or /autonomous cleanup after rubric-dropped
138. LP-182 — untested deterministic branch in agents/launch-pad.md: the non-interactive auto-strip removed ≥1 bullet / any other case
139. LP-186 — untested deterministic branch in agents/launch-pad.md: --non-interactive or --non-interactive-fallback passed
140. LP-187 — untested deterministic branch in agents/launch-pad.md: CLAUDE.md missing
141. LP-188 — untested deterministic branch in agents/launch-pad.md: git conflicts
142. LP-189 — untested deterministic branch in agents/launch-pad.md: gh not authenticated
143. LP-190 — untested deterministic branch in agents/launch-pad.md: orphaned worktrees
144. LP-193 — untested deterministic branch in agents/launch-pad.md: feasibility NO-GO
145. LP-203 — untested deterministic branch in agents/launch-pad.md: proposing a memory
146. LP-207 — untested deterministic branch in commands/launch-pad.md: either non-interactive spelling passed
147. LP-209 — untested deterministic branch in commands/launch-pad.md: Plan Review FAIL
148. LP-221 — untested deterministic branch in commands/launch-pad.md: CLAUDE.md-missing BLOCKER
149. LP-232 — untested deterministic branch in commands/launch-pad.md: goal value is a .md path under .supervisor/requirements/
150. LP-235 — untested deterministic branch in commands/launch-pad.md: BLOCKERS
151. LP-238 — untested deterministic branch in commands/launch-pad.md: NO-GO / CAUTION
152. LP-239 — untested deterministic branch in commands/launch-pad.md: start (command mirror)
153. LP-240 — untested deterministic branch in commands/launch-pad.md: a check fails
154. LP-241 — untested deterministic branch in commands/launch-pad.md: --skip-validation
155. LP-242 — untested deterministic branch in commands/launch-pad.md: after VALIDATE (command mirror)
156. LP-243 — untested deterministic branch in commands/launch-pad.md: .md under .supervisor/requirements/ passing test -f
157. LP-247 — untested deterministic branch in commands/launch-pad.md: --discovery
158. LP-254 — untested deterministic branch in commands/launch-pad.md: GO
159. LP-255 — untested deterministic branch in commands/launch-pad.md: CAUTION
160. LP-256 — untested deterministic branch in commands/launch-pad.md: NO-GO
161. LP-258 — untested deterministic branch in commands/launch-pad.md: sparse CLAUDE.md
162. LP-259 — untested deterministic branch in commands/launch-pad.md: after FEASIBILITY (command mirror)
163. LP-267 — untested deterministic branch in commands/launch-pad.md: no deps and no overlap / otherwise
164. LP-268 — untested deterministic branch in commands/launch-pad.md: after DECOMPOSE (command mirror)
165. LP-269 — untested deterministic branch in commands/launch-pad.md: CAUTION finding / overridden NO-GO
166. LP-272 — untested deterministic branch in commands/launch-pad.md: the source requirement carries Rule conflicts
167. LP-273 — untested deterministic branch in commands/launch-pad.md: brief assembled (command mirror)
168. LP-275 — untested deterministic branch in commands/launch-pad.md: PASS with an at-floor issue and attempt < 3
169. LP-276 — untested deterministic branch in commands/launch-pad.md: PASS
170. LP-278 — untested deterministic branch in commands/launch-pad.md: FAIL and attempt = 3
171. LP-280 — untested deterministic branch in commands/launch-pad.md: review allowed save (command mirror)
172. LP-281 — untested deterministic branch in commands/launch-pad.md: presenting the brief
173. LP-282 — untested deterministic branch in commands/launch-pad.md: on save
174. LP-283 — untested deterministic branch in commands/launch-pad.md: blockers or FAIL
175. LP-287 — untested deterministic branch in skills/autonomous-loop/SKILL.md: no mode flag / --single-iteration / --allow-multi-iteration
176. LP-289 — untested deterministic branch in skills/autonomous-loop/SKILL.md: rubric_score N<M / failed + inter_subtask_gap on this brief / no rubric
177. LP-292 — untested deterministic branch in skills/autonomous-loop/SKILL.md: default / --no-stacked-branches
178. LP-294 — untested deterministic branch in skills/autonomous-loop/SKILL.md: --notify set but no webhook URL resolves
179. LP-295 — untested deterministic branch in skills/autonomous-loop/SKILL.md: --max-iterations 1 and Signal 1/2 would fire
180. LP-297 — untested deterministic branch in skills/autonomous-loop/SKILL.md: --single-iteration
181. LP-298 — untested deterministic branch in skills/autonomous-loop/SKILL.md: default multi-iter path with no mode flag / a mode flag passed
182. LP-305 — untested deterministic branch in skills/autonomous-loop/SKILL.md: only --allow-multi-iteration
183. LP-306 — untested deterministic branch in skills/autonomous-loop/SKILL.md: --cheap passed
184. LP-307 — untested deterministic branch in skills/autonomous-loop/SKILL.md: --max-tokens N passed / absent
185. LP-312 — untested deterministic branch in skills/autonomous-loop/SKILL.md: INIT
186. LP-313 — untested deterministic branch in skills/autonomous-loop/SKILL.md: requirement given as a string
187. LP-315 — untested deterministic branch in skills/autonomous-loop/SKILL.md: --requirement file already has a real rubric
188. LP-316 — untested deterministic branch in skills/autonomous-loop/SKILL.md: concurrent activity seen by the brief-save ls-diff
189. LP-319 — untested deterministic branch in skills/autonomous-loop/SKILL.md: ACQUIRE write errors / direct /supervisor job path
190. LP-324 — untested deterministic branch in skills/autonomous-loop/SKILL.md: every iteration
191. LP-326 — untested deterministic branch in skills/autonomous-loop/SKILL.md: the requirement has an Outcomes Rubric
192. LP-328 — untested deterministic branch in skills/autonomous-loop/SKILL.md: single mode, or the requirement already has a real rubric
193. LP-330 — untested deterministic branch in skills/autonomous-loop/SKILL.md: fewer than 3 bullets derivable
194. LP-331 — untested deterministic branch in skills/autonomous-loop/SKILL.md: the Launch Pad forward is active
195. LP-332 — untested deterministic branch in skills/autonomous-loop/SKILL.md: Launch Pad finished inline
196. LP-347 — untested deterministic branch in skills/autonomous-loop/SKILL.md: user aborted at NO-GO
197. LP-348 — untested deterministic branch in skills/autonomous-loop/SKILL.md: user aborted after FAIL x3
198. LP-352 — untested deterministic branch in skills/autonomous-loop/SKILL.md: inside the guard: the append did not take
199. LP-354 — untested deterministic branch in skills/autonomous-loop/SKILL.md: no rubric authored
200. LP-355 — untested deterministic branch in skills/autonomous-loop/SKILL.md: every iteration
201. LP-360 — untested deterministic branch in skills/autonomous-loop/SKILL.md: --cheap at INIT
202. LP-361 — untested deterministic branch in skills/autonomous-loop/SKILL.md: --max-tokens N at INIT
203. LP-369 — untested deterministic branch in skills/autonomous-loop/SKILL.md: Supervisor emitted a result
204. LP-370 — untested deterministic branch in skills/autonomous-loop/SKILL.md: review-heal skipped / ran
205. LP-372 — untested deterministic branch in skills/autonomous-loop/SKILL.md: brief still in in-progress/
206. LP-373 — untested deterministic branch in skills/autonomous-loop/SKILL.md: brief in done/ but no result
207. LP-374 — untested deterministic branch in skills/autonomous-loop/SKILL.md: brief in failed/ but no result
208. LP-376 — untested deterministic branch in skills/autonomous-loop/SKILL.md: single-iteration mode
209. LP-377 — untested deterministic branch in skills/autonomous-loop/SKILL.md: multi-iteration EVALUATE, before signals
210. LP-378 — untested deterministic branch in skills/autonomous-loop/SKILL.md: iteration 1
211. LP-379 — untested deterministic branch in skills/autonomous-loop/SKILL.md: --no-stacked-branches
212. LP-391 — untested deterministic branch in skills/autonomous-loop/SKILL.md: review-heal returned
213. LP-392 — untested deterministic branch in skills/autonomous-loop/SKILL.md: decision PASS
214. LP-397 — untested deterministic branch in skills/autonomous-loop/SKILL.md: completed with rubric_score N<M
215. LP-399 — untested deterministic branch in skills/autonomous-loop/SKILL.md: stacked mode
216. LP-400 — untested deterministic branch in skills/autonomous-loop/SKILL.md: --no-stacked-branches
217. LP-402 — untested deterministic branch in skills/autonomous-loop/SKILL.md: stacked continue
218. LP-409 — untested deterministic branch in skills/autonomous-loop/SKILL.md: merge verified
219. LP-410 — untested deterministic branch in skills/autonomous-loop/SKILL.md: stop-here picked
220. LP-411 — untested deterministic branch in skills/autonomous-loop/SKILL.md: force-continue-anyway picked
221. LP-412 — untested deterministic branch in skills/autonomous-loop/SKILL.md: Supervisor returned failed
222. LP-417 — untested deterministic branch in skills/autonomous-loop/SKILL.md: failed brief, no gap substring
223. LP-420 — untested deterministic branch in skills/autonomous-loop/SKILL.md: completed, no rubric, multi-iter
224. LP-423 — untested deterministic branch in skills/autonomous-loop/SKILL.md: user picks continue
225. LP-424 — untested deterministic branch in skills/autonomous-loop/SKILL.md: user picks stop
226. LP-425 — untested deterministic branch in skills/autonomous-loop/SKILL.md: no signal or gate fired
227. LP-426 — untested deterministic branch in skills/autonomous-loop/SKILL.md: completed with a perfect score
228. LP-427 — untested deterministic branch in skills/autonomous-loop/SKILL.md: completed N<M and stop-here
229. LP-428 — untested deterministic branch in skills/autonomous-loop/SKILL.md: completed, no rubric, stop
230. LP-429 — untested deterministic branch in skills/autonomous-loop/SKILL.md: completed, no rubric, non-interactive
231. LP-430 — untested deterministic branch in skills/autonomous-loop/SKILL.md: completed_with_escalation
232. LP-431 — untested deterministic branch in skills/autonomous-loop/SKILL.md: failed with no PR
233. LP-432 — untested deterministic branch in skills/autonomous-loop/SKILL.md: failed, no gap, PR exists
234. LP-433 — untested deterministic branch in skills/autonomous-loop/SKILL.md: failed with base_branch_mismatch
235. LP-434 — untested deterministic branch in skills/autonomous-loop/SKILL.md: failed with preflight_overlap_detected
236. LP-435 — untested deterministic branch in skills/autonomous-loop/SKILL.md: Supervisor checkpoint
237. LP-436 — untested deterministic branch in skills/autonomous-loop/SKILL.md: Supervisor pre-flight classifies OVERLAP / SUPERSEDED
238. LP-443 — untested deterministic branch in skills/autonomous-loop/SKILL.md: run ends
239. LP-444 — untested deterministic branch in skills/autonomous-loop/SKILL.md: status_reason launch_pad_cant_ask_non_interactive / otherwise
240. LP-448 — untested deterministic branch in skills/autonomous-loop/SKILL.md: discard at Phase 6
241. LP-450 — untested deterministic branch in skills/autonomous-loop/SKILL.md: more than one new brief
242. LP-452 — untested deterministic branch in skills/autonomous-loop/SKILL.md: gh pr view fails
243. LP-462 — untested deterministic branch in commands/autonomous.md: --notify with no resolvable URL
244. LP-464 — untested deterministic branch in commands/autonomous.md: iteration completed with a PR / skipped when no PR or failed
245. LP-466 — untested deterministic branch in commands/autonomous.md: --cheap passed
246. LP-468 — untested deterministic branch in commands/autonomous.md: requirement given inline
247. LP-469 — untested deterministic branch in commands/autonomous.md: --requirement file without a rubric, multi-iter, rubric approved
248. LP-470 — untested deterministic branch in commands/autonomous.md: --single-iteration
249. LP-471 — untested deterministic branch in commands/autonomous.md: --no-stacked-branches (multi-iter only)
250. LP-472 — untested deterministic branch in commands/autonomous.md: --notify, neither env nor user-scope URL
251. LP-474 — untested deterministic branch in commands/autonomous.md: N outside 1..10
252. LP-475 — untested deterministic branch in commands/autonomous.md: N=1 and Signal 1/2 would fire
253. LP-476 — untested deterministic branch in commands/autonomous.md: --allow-multi-iteration alone / with --single-iteration
254. LP-477 — untested deterministic branch in commands/autonomous.md: --cheap passed
255. LP-487 — untested deterministic branch in commands/autonomous.md: multi-iteration run
256. LP-488 — untested deterministic branch in commands/autonomous.md: completed / completed_with_escalation with a PR
257. LP-489 — untested deterministic branch in commands/autonomous.md: completed with rubric N<M
258. LP-490 — untested deterministic branch in commands/autonomous.md: completed, no rubric, multi-iter
259. LP-491 — untested deterministic branch in commands/autonomous.md: failed with inter_subtask_gap
260. LP-492 — untested deterministic branch in commands/autonomous.md: failed with pr_url null
261. LP-493 — untested deterministic branch in commands/autonomous.md: anything else
262. LP-494 — untested deterministic branch in commands/autonomous.md: --single-iteration
263. LP-495 — untested deterministic branch in commands/autonomous.md: iteration N+1 reached
264. LP-496 — untested deterministic branch in commands/autonomous.md: --no-stacked-branches
265. LP-497 — untested deterministic branch in commands/autonomous.md: stacked default
266. LP-499 — untested deterministic branch in commands/autonomous.md: Launch Pad gates fire / --non-interactive-fallback
267. LP-500 — untested deterministic branch in commands/autonomous.md: adjudication fires
268. LP-502 — untested deterministic branch in commands/autonomous.md: requirement rubric not in the saved brief (has_rubric)
269. LP-519 — untested deterministic branch in agents/launch-pad.md: Phase 4 output template (outside a fence under a CommonMark closer rule)
270. LP-520 — untested deterministic branch in agents/launch-pad.md: Phase 4 output template (outside a fence under a CommonMark closer rule)
271. LP-001 — untested standing rule in agents/launch-pad.md (silent deletion undetected): every Launch Pad run
272. LP-002 — untested standing rule in agents/launch-pad.md (silent deletion undetected): always
273. LP-003 — untested standing rule in agents/launch-pad.md (silent deletion undetected): a subtask is not genuinely independent (file overlap)
274. LP-004 — untested standing rule in agents/launch-pad.md (silent deletion undetected): every file prediction
275. LP-005 — untested standing rule in agents/launch-pad.md (silent deletion undetected): a path is about to enter the impact map
276. LP-006 — untested standing rule in agents/launch-pad.md (silent deletion undetected): before saving
277. LP-007 — untested standing rule in agents/launch-pad.md (silent deletion undetected): spawning subagents
278. LP-011 — untested standing rule in agents/launch-pad.md (silent deletion undetected): every run
279. LP-012 — untested standing rule in agents/launch-pad.md (silent deletion undetected): always
280. LP-013 — untested standing rule in agents/launch-pad.md (silent deletion undetected): subtask not genuinely independent
281. LP-014 — untested standing rule in agents/launch-pad.md (silent deletion undetected): every file prediction
282. LP-015 — untested standing rule in agents/launch-pad.md (silent deletion undetected): a path enters the impact map
283. LP-017 — untested standing rule in agents/launch-pad.md (silent deletion undetected): clarification is needed
284. LP-058 — untested standing rule in agents/launch-pad.md (silent deletion undetected): churn reader emits anything or nothing
285. LP-061 — untested standing rule in agents/launch-pad.md (silent deletion undetected): rule text is read
286. LP-065 — untested standing rule in agents/launch-pad.md (silent deletion undetected): two file groups overlap
287. LP-070 — untested standing rule in agents/launch-pad.md (silent deletion undetected): deriving a subsystem id
288. LP-072 — untested standing rule in agents/launch-pad.md (silent deletion undetected): blast-radius prediction exists
289. LP-085 — untested standing rule in agents/launch-pad.md (silent deletion undetected): analyzing dependencies
290. LP-091 — untested standing rule in agents/launch-pad.md (silent deletion undetected): a subtask is purely deletion
291. LP-092 — untested standing rule in agents/launch-pad.md (silent deletion undetected): a provides entry is vague
292. LP-093 — untested standing rule in agents/launch-pad.md (silent deletion undetected): an outside-scope dependency
293. LP-095 — untested standing rule in agents/launch-pad.md (silent deletion undetected): every subtask
294. LP-119 — untested standing rule in agents/launch-pad.md (silent deletion undetected): naming the digest
295. LP-137 — untested standing rule in agents/launch-pad.md (silent deletion undetected): a Criterion 14 executable_acceptance issue
296. LP-173 — untested standing rule in agents/launch-pad.md (silent deletion undetected): naming the brief
297. LP-174 — untested standing rule in agents/launch-pad.md (silent deletion undetected): naming the brief
298. LP-185 — untested standing rule in agents/launch-pad.md (silent deletion undetected): every run
299. LP-194 — untested standing rule in agents/launch-pad.md (silent deletion undetected): before offering save
300. LP-195 — untested standing rule in agents/launch-pad.md (silent deletion undetected): before offering save
301. LP-196 — untested standing rule in agents/launch-pad.md (silent deletion undetected): before offering save
302. LP-197 — untested standing rule in agents/launch-pad.md (silent deletion undetected): before offering save
303. LP-198 — untested standing rule in agents/launch-pad.md (silent deletion undetected): before offering save
304. LP-199 — untested standing rule in agents/launch-pad.md (silent deletion undetected): before offering save
305. LP-215 — untested standing rule in commands/launch-pad.md (silent deletion undetected): not a git repo
306. LP-216 — untested standing rule in commands/launch-pad.md (silent deletion undetected): CLAUDE.md missing
307. LP-218 — untested standing rule in commands/launch-pad.md (silent deletion undetected): about to run the brief
308. LP-219 — untested standing rule in commands/launch-pad.md (silent deletion undetected): several goals
309. LP-226 — untested standing rule in commands/launch-pad.md (silent deletion undetected): every run (command mirror)
310. LP-227 — untested standing rule in commands/launch-pad.md (silent deletion undetected): always
311. LP-228 — untested standing rule in commands/launch-pad.md (silent deletion undetected): subtask overlaps
312. LP-229 — untested standing rule in commands/launch-pad.md (silent deletion undetected): path enters impact map
313. LP-230 — untested standing rule in commands/launch-pad.md (silent deletion undetected): before saving
314. LP-234 — untested standing rule in commands/launch-pad.md (silent deletion undetected): every run (command mirror)
315. LP-237 — untested standing rule in commands/launch-pad.md (silent deletion undetected): unsure about a file/API/path
316. LP-260 — untested standing rule in commands/launch-pad.md (silent deletion undetected): groups overlap
317. LP-265 — untested standing rule in commands/launch-pad.md (silent deletion undetected): numbering subtasks
318. LP-284 — untested standing rule in commands/launch-pad.md (silent deletion undetected): before offering save
319. LP-285 — untested standing rule in commands/launch-pad.md (silent deletion undetected): before offering save
320. LP-286 — untested standing rule in skills/autonomous-loop/SKILL.md (silent deletion undetected): always
321. LP-288 — untested standing rule in skills/autonomous-loop/SKILL.md (silent deletion undetected): an adjudication fires
322. LP-299 — untested standing rule in skills/autonomous-loop/SKILL.md (silent deletion undetected): every /autonomous invocation
323. LP-311 — untested standing rule in skills/autonomous-loop/SKILL.md (silent deletion undetected): reading the token ceiling
324. LP-314 — untested standing rule in skills/autonomous-loop/SKILL.md (silent deletion undetected): writing the placeholder
325. LP-317 — untested standing rule in skills/autonomous-loop/SKILL.md (silent deletion undetected): writing state.json
326. LP-346 — untested standing rule in skills/autonomous-loop/SKILL.md (silent deletion undetected): plugin emits Phase 7 / pre-v14.2.0 plugin
327. LP-350 — untested standing rule in skills/autonomous-loop/SKILL.md (silent deletion undetected): a rubric was authored into the brief
328. LP-357 — untested standing rule in skills/autonomous-loop/SKILL.md (silent deletion undetected): CLI flag and brief Base Branch field
329. LP-366 — untested standing rule in skills/autonomous-loop/SKILL.md (silent deletion undetected): multi-iteration EVALUATE
330. LP-368 — untested standing rule in skills/autonomous-loop/SKILL.md (silent deletion undetected): job moves pending/ → in-progress/ → done/ or failed/
331. LP-385 — untested standing rule in skills/autonomous-loop/SKILL.md (silent deletion undetected): Supervisor's own Phase 4 self-verify was silenced
332. LP-387 — untested standing rule in skills/autonomous-loop/SKILL.md (silent deletion undetected): multi-iteration EVALUATE
333. LP-390 — untested standing rule in skills/autonomous-loop/SKILL.md (silent deletion undetected): running review-heal from /autonomous
334. LP-395 — untested standing rule in skills/autonomous-loop/SKILL.md (silent deletion undetected): additive drain fields present
335. LP-396 — untested standing rule in skills/autonomous-loop/SKILL.md (silent deletion undetected): review-heal runs
336. LP-403 — untested standing rule in skills/autonomous-loop/SKILL.md (silent deletion undetected): stacked iteration brief
337. LP-404 — untested standing rule in skills/autonomous-loop/SKILL.md (silent deletion undetected): merging stacked PRs
338. LP-413 — untested standing rule in skills/autonomous-loop/SKILL.md (silent deletion undetected): detecting this iteration's Option C
339. LP-414 — untested standing rule in skills/autonomous-loop/SKILL.md (silent deletion undetected): tempted to grep state.md
340. LP-419 — untested standing rule in skills/autonomous-loop/SKILL.md (silent deletion undetected): a policy decision is inferred, not chosen by a user at a loop gate
341. LP-439 — untested standing rule in skills/autonomous-loop/SKILL.md (silent deletion undetected): pre-flight overlap vs PR base after FINALIZE
342. LP-442 — untested standing rule in skills/autonomous-loop/SKILL.md (silent deletion undetected): emitting AUTONOMOUS_RUN.status
343. LP-445 — untested standing rule in skills/autonomous-loop/SKILL.md (silent deletion undetected): writing state.json
344. LP-446 — untested standing rule in skills/autonomous-loop/SKILL.md (silent deletion undetected): tooling finds _v1_note
345. LP-447 — untested standing rule in skills/autonomous-loop/SKILL.md (silent deletion undetected): a concurrent /launch-pad writes to pending/
346. LP-454 — untested standing rule in skills/autonomous-loop/SKILL.md (silent deletion undetected): reusing Launch Pad
347. LP-455 — untested standing rule in skills/autonomous-loop/SKILL.md (silent deletion undetected): reusing Supervisor
348. LP-456 — untested standing rule in skills/autonomous-loop/SKILL.md (silent deletion undetected): adjudication
349. LP-457 — untested standing rule in skills/autonomous-loop/SKILL.md (silent deletion undetected): reading SUPERVISOR_RESULT
350. LP-458 — untested standing rule in skills/autonomous-loop/SKILL.md (silent deletion undetected): job files
351. LP-459 — untested standing rule in skills/autonomous-loop/SKILL.md (silent deletion undetected): state.md
352. LP-461 — untested standing rule in commands/autonomous.md (silent deletion undetected): gates fire in-session
353. LP-483 — untested standing rule in commands/autonomous.md (silent deletion undetected): unattended run
354. LP-485 — untested standing rule in commands/autonomous.md (silent deletion undetected): path contains spaces
355. LP-486 — untested standing rule in commands/autonomous.md (silent deletion undetected): every run
356. LP-498 — untested standing rule in commands/autonomous.md (silent deletion undetected): merging a stack
357. LP-503 — untested standing rule in commands/autonomous.md (silent deletion undetected): single-iteration or rubric present
358. LP-513 — untested standing rule in commands/autonomous.md (silent deletion undetected): loop writes under .supervisor/
359. LP-030 — model judgment with no check in agents/launch-pad.md: resolved requirement file is empty or not a story
360. LP-033 — model judgment with no check in agents/launch-pad.md: goal is clear or a requirement file was read
361. LP-037 — model judgment with no check in agents/launch-pad.md: goal needs a different stack / a major new dependency
362. LP-038 — model judgment with no check in agents/launch-pad.md: required dependency deprecated or nonexistent / new dependencies needed
363. LP-039 — model judgment with no check in agents/launch-pad.md: goal contradicts / stretches the architecture
364. LP-040 — model judgment with no check in agents/launch-pad.md: too large even under a justified split / borderline
365. LP-041 — model judgment with no check in agents/launch-pad.md: hard blocker found / potential blocker the user might resolve
366. LP-064 — model judgment with no check in agents/launch-pad.md: LSP is available
367. LP-066 — model judgment with no check in agents/launch-pad.md: each predicted file
368. LP-073 — model judgment with no check in agents/launch-pad.md: a task's acceptance depends on a generated/mechanical validation script
369. LP-074 — model judgment with no check in agents/launch-pad.md: the goal / requirement cites path:line refs
370. LP-077 — model judgment with no check in agents/launch-pad.md: excerpt read
371. LP-082 — model judgment with no check in agents/launch-pad.md: after ANALYZE
372. LP-084 — model judgment with no check in agents/launch-pad.md: a threshold reason fires / none fires
373. LP-191 — model judgment with no check in agents/launch-pad.md: goal still vague after 2 rounds
374. LP-192 — model judgment with no check in agents/launch-pad.md: no files match the goal
375. LP-214 — model judgment with no check in commands/launch-pad.md: complex (>3 subtasks) or plan review wanted / simple, resume or quick fix
376. LP-217 — model judgment with no check in commands/launch-pad.md: goal is vague
377. LP-220 — model judgment with no check in commands/launch-pad.md: HIGH risks listed
378. LP-222 — model judgment with no check in commands/launch-pad.md: wrong file predictions
379. LP-223 — model judgment with no check in commands/launch-pad.md: more than 7 subtasks
380. LP-224 — model judgment with no check in commands/launch-pad.md: every subtask BLOCKED
381. LP-225 — model judgment with no check in commands/launch-pad.md: brief older than 24h
382. LP-244 — model judgment with no check in commands/launch-pad.md: vague goal
383. LP-245 — model judgment with no check in commands/launch-pad.md: clear goal
384. LP-249 — model judgment with no check in commands/launch-pad.md: stack mismatch
385. LP-250 — model judgment with no check in commands/launch-pad.md: dependency missing
386. LP-251 — model judgment with no check in commands/launch-pad.md: architecture misfit
387. LP-252 — model judgment with no check in commands/launch-pad.md: too large / borderline
388. LP-253 — model judgment with no check in commands/launch-pad.md: hard blocker
389. LP-261 — model judgment with no check in commands/launch-pad.md: each prediction
390. LP-264 — model judgment with no check in commands/launch-pad.md: after ANALYZE (command mirror)
391. LP-266 — model judgment with no check in commands/launch-pad.md: a threshold reason fires / none
392. LP-514 — model judgment with no check in commands/autonomous.md: rubric_dropped_from_brief abort
393. LP-515 — model judgment with no check in commands/autonomous.md: concurrent_session_detected abort
394. LP-516 — model judgment with no check in commands/autonomous.md: force-continue without merging
395. LP-517 — model judgment with no check in commands/autonomous.md: Option C picked, no re-plan
396. LP-518 — model judgment with no check in commands/autonomous.md: checkpoint abort
397. LP-008 — narrative / rationale only, low risk (agents/launch-pad.md): a run starts
398. LP-010 — narrative / rationale only, low risk (agents/launch-pad.md): a run completes
399. LP-208 — narrative / rationale only, low risk (commands/launch-pad.md): choosing Launch Pad
400. LP-210 — narrative / rationale only, low risk (commands/launch-pad.md): user starts
401. LP-211 — narrative / rationale only, low risk (commands/launch-pad.md): brief presented
402. LP-212 — narrative / rationale only, low risk (commands/launch-pad.md): brief reviewed
403. LP-213 — narrative / rationale only, low risk (commands/launch-pad.md): brief saved
404. LP-231 — narrative / rationale only, low risk (commands/launch-pad.md): run starts (command mirror)
405. LP-233 — narrative / rationale only, low risk (commands/launch-pad.md): run completes (command mirror)
406. LP-322 — narrative / rationale only, low risk (skills/autonomous-loop/SKILL.md): a crashed run leaves its brief in in-progress/ and no ended_at, and a later PR's branch collides
407. LP-406 — narrative / rationale only, low risk (skills/autonomous-loop/SKILL.md): looking up iteration branches
408. LP-440 — narrative / rationale only, low risk (skills/autonomous-loop/SKILL.md): stacked run's own parent commits / PR
409. LP-451 — narrative / rationale only, low risk (skills/autonomous-loop/SKILL.md): process killed / terminal closed
410. LP-453 — narrative / rationale only, low risk (skills/autonomous-loop/SKILL.md): the grep-stable string changes
411. LP-467 — narrative / rationale only, low risk (commands/autonomous.md): naming units
412. LP-482 — narrative / rationale only, low risk (commands/autonomous.md): deferred flags
413. LP-484 — narrative / rationale only, low risk (commands/autonomous.md): resume or auto-merge wanted
414. LP-504 — narrative / rationale only, low risk (commands/autonomous.md): example
415. LP-506 — narrative / rationale only, low risk (commands/autonomous.md): example
416. LP-509 — narrative / rationale only, low risk (commands/autonomous.md): refining a requirement
417. LP-510 — narrative / rationale only, low risk (commands/autonomous.md): re-run after a crash
418. LP-511 — narrative / rationale only, low risk (commands/autonomous.md): quality in the loop

## Counts

- rows: 520
- deterministic: 330
- judgment: 46
- rule: 119
- story: 25
- GAP: 418
