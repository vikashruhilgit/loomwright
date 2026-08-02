#!/usr/bin/env node
/**
 * runner.ts — QUARANTINED Agent SDK spike (loomwright/sdk-spike/).
 *
 * Ports ONLY Execute Manager's Phase 3 poll loop (agents/execute-manager.md
 * §"Execution Protocol" Steps 1–5) to code:
 *
 *   Step 1  Parse inputs        → parse the brief's Subtask Structure table +
 *                                 `### Subtask contracts` YAML (tolerant line parser)
 *   Step 2  Worktree creation   → one git worktree per LAUNCHABLE subtask
 *                                 (skipped entirely in --dry-run)
 *   Step 3  Spawn workers       → one `query()` per worker, structured output
 *                                 forced to WORKER_RESULT_SCHEMA (schema_version 2)
 *   Step 4  Poll loop           → deterministic in-code scheduling: Promise-pool
 *                                 up to --max-workers (default 2); on each worker
 *                                 completion, one reviewer `query()` forced to
 *                                 CODE_REVIEW_RESULT_SCHEMA (schema_version 3);
 *                                 wave recompute unblocks dependent subtasks
 *                                 (the "launch newly launchable" branch of the loop)
 *   Step 5  Output result       → EXECUTE_RESULT-equivalent JSON block on stdout;
 *                                 worker output is COMMITTED on each per-subtask
 *                                 branch before worktree removal — worktrees are
 *                                 removed on exit, branches are KEPT and listed
 *                                 (merge_order / branches) for the caller to
 *                                 merge and then delete
 *
 * CLI contract:
 *   node dist/runner.js --brief <path> [--dry-run] [--max-workers N] [--model M]
 *     [--effort E] [--worker-effort E] [--reviewer-effort E] [--task-budget N] [--branch B]
 *
 * Spike simplifications vs the real Execute Manager (documented in README.md):
 *   - no fix-worker retry loop on review FAIL (single attempt; FAIL = subtask failed)
 *   - no Context-Keeper batching (state lives in-process)
 *   - no tool-call budget / EXECUTE_CHECKPOINT — failures land in
 *     subtasks_failed of the final block instead
 *
 * FIXED 2026-07-28 (was the blocker that aborted FABLE_PARITY_EVAL arm 3):
 *   - dependency materialization. Previously dependents branched from the feature
 *     branch after producers completed, and producer branches were never merged
 *     during the run — so `requires` bought ordering in TIME but nothing in
 *     CONTENT, and any dependent importing a producer's symbol could not compile.
 *     `materializeWave` now merges each completed wave into the feature branch
 *     BEFORE the next wave's worktrees are created, so `git worktree add …
 *     featureBranch` inherits everything already landed. Fails CLOSED on conflict
 *     (merge aborted, tree left clean, run marked failed).
 *   - branch lifecycle: the runner commits worker output on each per-subtask
 *     branch (mirroring FINALIZE step 2 of skills/async-orchestration/SKILL.md)
 *     AND now merges each wave into the feature branch as it goes. The caller
 *     still owns the FINAL merge of the feature branch and branch deletion.
 */

import * as fs from "fs";
import * as path from "path";
import { execFileSync } from "child_process";
import {
  WORKER_RESULT_SCHEMA,
  CODE_REVIEW_RESULT_SCHEMA,
  WorkerResult,
  CodeReviewResult,
  ExecuteResultEquivalent,
  RoleTokenUsage,
  SubtaskTokenUsage,
  validateAgainstSchema,
} from "./schemas";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface ContractItem {
  kind: string;
  path: string;
  name?: string;
  from?: string; // producing subtask id (requires entries) — string: Launch Pad emits "1a"/"1b" as well as "1"
}

interface Subtask {
  id: string;
  title: string;
  tableStatus: string; // Status cell from the Subtask Structure table (informational)
  provides: ContractItem[];
  requires: ContractItem[];
  // Verbatim `lanes:` glob list from the brief's Subtask Contracts YAML — the
  // paths this subtask is expected to modify/create. Named `laneGlobs`, NOT
  // `lanes` (that bare name is already an unrelated `Promise<void>[]`
  // concurrency local in runPool, below). Empty when the subtask has no
  // declared lane (pre-lane-declaration brief).
  laneGlobs: string[];
  /** True once a contract key was SEEN for this subtask -- regardless of whether the list
   *  turned out empty. This is what distinguishes "the author declared nothing" (a sanctioned
   *  shape) from "the parser never found the block" (the defect the fail-closed guard exists
   *  for). Counting list LENGTHS cannot tell those apart.
   *
   *  The recognized set is exactly `provides:`/`requires:`/`lanes:` -- the list-header regex
   *  below. `external_requires:` deliberately does NOT set this: it is a free-text list naming
   *  things OUTSIDE the brief's scope, never cross-referenced from `requires`, so it proves
   *  nothing about whether this subtask's own dependency contract was found. (A subtask
   *  declaring `external_requires:` and none of the other three is not a realistic authoring
   *  shape, so this narrowing costs no real coverage -- but the flag must not claim breadth
   *  it does not have.) */
  sawContractKey: boolean;
  /** True when an INLINE contract value was present but yielded ZERO parseable items --
   *  e.g. `provides: [some free-text prose describing the work]`. The key was seen, so
   *  `sawContractKey` alone would call this "declared", but nothing addressable was
   *  actually captured, so the subtask still ends up vacuously LAUNCHABLE. Tracked
   *  separately so the guard keeps catching this while no longer false-positiving on a
   *  legitimately empty `provides: []`. */
  sawUnparseableValue: boolean;
  /** Contract keys that were declared with a NON-EMPTY, non-`[]` value. Resolved at the END of
   *  parsing: if such a key still has zero parsed items, its value was prose where addressable
   *  {kind, path} entries belong, and the subtask is vacuously LAUNCHABLE. Recorded as a
   *  DEFERRED list rather than decided at header time because items may legitimately arrive on
   *  following lines, and shape-independently rather than per-branch because a branch-local
   *  check covered only the bracketed form -- `requires: [free text]` threw while the
   *  non-bracketed twin `requires: free text` silently dropped the edge. */
  declaredNonEmpty: string[];
}

type DryRunFixtureSet = "default" | "fail" | "review-fail" | "throw-usage" | "throw-usage-worker";

interface CliArgs {
  brief: string;
  dryRun: boolean;
  dryRunFixtureSet: DryRunFixtureSet;
  maxWorkers: number;
  model?: string;
  /** global effort override — applies to BOTH roles (per-role flags win) */
  effort?: EffortLevel;
  /** per-role overrides (win over --effort; default comes from ROLE_CONFIG) */
  workerEffort?: EffortLevel;
  reviewerEffort?: EffortLevel;
  /** opt-in per-WORKER-query token budget (>= TASK_BUDGET_MIN_TOKENS); omitted from Options entirely when unset */
  taskBudget?: number;
  branch?: string;
}

interface WorktreeRecord {
  taskId: string;
  wtPath: string;
  branch: string;
  created: boolean; // false in dry-run
  removed: boolean;
}

type QueryKind = "worker" | "reviewer";

// ---------------------------------------------------------------------------
// ROLE CONFIG TABLE — the single source of per-role query configuration.
// Call sites MUST resolve effort via resolveRoleConfig() (this table), never
// hard-code a level inline.
//
// Effort defaults (SDK EffortLevel set, sdk.d.ts:522; Options.effort at :1620):
//   worker   → "medium"  (mechanical, schema-bounded implementation subtasks)
//   reviewer → "high"    (deliberately a higher named level from the same
//                         table: review is the spike's only quality gate —
//                         no fix-worker retry loop — so it gets deeper
//                         reasoning than the worker default)
//
// Override precedence (all values fail-closed validated at parse time,
// BEFORE any query is issued):
//   --worker-effort / --reviewer-effort  >  --effort (both roles)  >  ROLE_CONFIG
// ---------------------------------------------------------------------------
const EFFORT_LEVELS = ["low", "medium", "high", "xhigh", "max"] as const;
type EffortLevel = (typeof EFFORT_LEVELS)[number];

const ROLE_CONFIG: Readonly<Record<QueryKind, { effort: EffortLevel }>> = {
  worker: { effort: "medium" },
  reviewer: { effort: "high" },
};

/**
 * Documented minimum for the SDK's @alpha `taskBudget` option
 * (sdk.d.ts:1647-1649, beta header task-budgets-2026-03-13). The type carries
 * no floor, so the runner enforces the documented 20k-token minimum itself —
 * fail CLOSED below it, before any query is issued.
 */
const TASK_BUDGET_MIN_TOKENS = 20000;

function resolveRoleConfig(kind: QueryKind, args: CliArgs): { effort: EffortLevel } {
  const perRole = kind === "worker" ? args.workerEffort : args.reviewerEffort;
  return { effort: perRole ?? args.effort ?? ROLE_CONFIG[kind].effort };
}

/** What a query() invocation reports back through the seam: the structured
 * payload plus per-query token accounting. `proxy: true` marks synthesized
 * (dry-run) numbers — never invented, always zeros (mirrors the plugin's
 * token-ledger convention). */
interface QueryOutcome {
  payload: unknown;
  usage: RoleTokenUsage;
  proxy: boolean;
}

/**
 * Live-mode fail-closed error that CARRIES the token usage captured from the
 * terminal result message before the throw. Without this, a failing query's
 * real spend (usage was already read at the top of the result handler) would
 * escape aggregateTokenUsage entirely and the failed entry's token_usage
 * would silently under-report. runSubtask's catch folds `usage` back into
 * the failing role's outcome. Never thrown on the dry-run path.
 */
class QueryFailedError extends Error {
  constructor(
    message: string,
    public readonly kind: QueryKind,
    public readonly usage: RoleTokenUsage,
    /** True when `usage` is synthesized (test fixtures), never on live throws. */
    public readonly proxy: boolean = false
  ) {
    super(message);
    this.name = "QueryFailedError";
  }
}

/**
 * The injected query seam. Live mode wires this to the Agent SDK's `query()`;
 * --dry-run injects a fake that returns canned fixtures (no API calls, no
 * network, deterministic) — the "MockTransport" of this spike.
 */
type QueryFn = (
  kind: QueryKind,
  prompt: string,
  schema: object,
  opts: { cwd?: string; model?: string; effort?: string; taskBudget?: number }
) => Promise<QueryOutcome>;

function zeroUsage(): RoleTokenUsage {
  return {
    input_tokens: 0,
    output_tokens: 0,
    cache_creation_input_tokens: 0,
    cache_read_input_tokens: 0,
    total_cost_usd: 0,
    num_turns: 0,
  };
}

function asFiniteNumber(v: unknown): number {
  return typeof v === "number" && Number.isFinite(v) ? v : 0;
}

/** Aggregate worker + reviewer per-query usage into the additive
 * `token_usage` object emitted on the EXECUTE_RESULT-equivalent block. */
function aggregateTokenUsage(
  worker: QueryOutcome | null,
  reviewer: QueryOutcome | null
): SubtaskTokenUsage {
  const roles = [worker, reviewer].filter((r): r is QueryOutcome => r !== null);
  return {
    worker: worker ? worker.usage : null,
    reviewer: reviewer ? reviewer.usage : null,
    // total_tokens is a VOLUME figure (cache-read tokens counted 1:1), not a
    // cost proxy — cost lives in total_cost_usd.
    total_tokens: roles.reduce(
      (sum, r) =>
        sum +
        r.usage.input_tokens +
        r.usage.output_tokens +
        r.usage.cache_creation_input_tokens +
        r.usage.cache_read_input_tokens,
      0
    ),
    total_cost_usd: roles.reduce((sum, r) => sum + r.usage.total_cost_usd, 0),
    // No real query behind the numbers (empty roles) is proxy by definition;
    // otherwise proxy iff any contributing query was synthesized (dry-run).
    proxy: roles.length === 0 ? true : roles.some((r) => r.proxy),
  };
}

// ---------------------------------------------------------------------------
// CLI parsing
// ---------------------------------------------------------------------------

function usage(): string {
  return "Usage: node dist/runner.js --brief <path> [--dry-run] [--dry-run-fixture-set default|fail|review-fail|throw-usage|throw-usage-worker (throw-* test-internal)] [--max-workers N] [--model M] [--effort E] [--worker-effort E] [--reviewer-effort E] [--task-budget N] [--branch B]";
}

/** FAIL CLOSED on any effort value outside the SDK's EffortLevel set
 * (sdk.d.ts:522) — thrown from parseArgs, i.e. before ANY query is issued. */
function parseEffortValue(flag: string, value: string | undefined): EffortLevel {
  if (!value || !(EFFORT_LEVELS as readonly string[]).includes(value)) {
    throw new Error(
      `${flag} must be one of ${EFFORT_LEVELS.join("|")} (got "${value ?? ""}"). ${usage()}`
    );
  }
  return value as EffortLevel;
}

function parseArgs(argv: string[]): CliArgs {
  const args: CliArgs = { brief: "", dryRun: false, dryRunFixtureSet: "default", maxWorkers: 2 };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    switch (a) {
      case "--brief":
        args.brief = argv[++i] ?? "";
        break;
      case "--dry-run":
        args.dryRun = true;
        break;
      case "--dry-run-fixture-set": {
        const set = argv[++i] ?? "";
        if (set !== "default" && set !== "fail" && set !== "review-fail" && set !== "throw-usage" && set !== "throw-usage-worker") {
          throw new Error(`--dry-run-fixture-set must be default|fail|review-fail|throw-usage|throw-usage-worker. ${usage()}`);
        }
        args.dryRunFixtureSet = set;
        break;
      }
      case "--max-workers": {
        const n = Number(argv[++i]);
        if (!Number.isInteger(n) || n < 1) throw new Error(`--max-workers must be a positive integer. ${usage()}`);
        args.maxWorkers = n;
        break;
      }
      case "--model":
        args.model = argv[++i];
        break;
      case "--effort":
        args.effort = parseEffortValue("--effort", argv[++i]);
        break;
      case "--worker-effort":
        args.workerEffort = parseEffortValue("--worker-effort", argv[++i]);
        break;
      case "--reviewer-effort":
        args.reviewerEffort = parseEffortValue("--reviewer-effort", argv[++i]);
        break;
      case "--task-budget": {
        // FAIL CLOSED: non-integer or below the documented 20k minimum aborts
        // here in parseArgs — before ANY query is issued.
        const n = Number(argv[++i]);
        if (!Number.isInteger(n)) {
          throw new Error(`--task-budget must be an integer token count. ${usage()}`);
        }
        if (n < TASK_BUDGET_MIN_TOKENS) {
          throw new Error(
            `--task-budget must be >= ${TASK_BUDGET_MIN_TOKENS} (the documented task-budget minimum); got ${n}. ${usage()}`
          );
        }
        args.taskBudget = n;
        break;
      }
      case "--branch":
        args.branch = argv[++i];
        break;
      default:
        throw new Error(`Unknown argument: ${a}. ${usage()}`);
    }
  }
  if (!args.brief) throw new Error(`--brief is required. ${usage()}`);
  return args;
}

// ---------------------------------------------------------------------------
// Step 1: Parse the brief (Subtask Structure table + Subtask contracts YAML)
// Tolerant regex/line parser — NOT a full markdown/YAML implementation.
// ---------------------------------------------------------------------------

export function parseBrief(text: string): { subtasks: Subtask[]; suggestedBranch?: string } {
  const lines = text.split(/\r?\n/);
  const byId = new Map<string, Subtask>();

  // --- Subtask Structure table: | # | Title | Est. files | Status | ---
  let inStructure = false;
  for (const line of lines) {
    if (/^##\s+Subtask Structure\b/.test(line)) {
      inStructure = true;
      continue;
    }
    if (inStructure && /^##\s/.test(line)) inStructure = false; // next H2 ends the section (### stays inside)
    if (!inStructure) continue;
    // Ids are matched as `\d+[a-z]?` — Launch Pad emits BOTH `1`..`N` and `1a`/`1b` for the same
    // requirement across runs (verified 2026-07-28: the arm-2 and arm-3 briefs, produced from a
    // byte-identical prompt, used different schemes). A `\d+`-only pattern silently DROPPED the
    // `1a`/`1b` rows, which is how arm 3 ended up with every dependency edge missing.
    const m = line.match(/^\|\s*(\d+[a-z]?)\s*\|([^|]+)\|[^|]*\|([^|]+)\|/);
    if (m) {
      const id = m[1];
      byId.set(id, {
        id,
        sawContractKey: false, sawUnparseableValue: false, declaredNonEmpty: [],
        title: m[2].trim(),
        tableStatus: m[3].trim(),
        provides: [],
        requires: [],
        laneGlobs: [],
      });
    }
  }

  // --- Subtask contracts YAML block ---
  // Parses a single `{...}` brace item (both the multi-line `- {...}` form and each element of
  // an inline flow-style array `provides: [ {...}, {...} ]` share this exact body grammar).
  // `from: 1`, `from: "1a"` and `from: 1a` all appear in the wild — accept all three. An optional
  // `S`/`ST` prefix (`from: S3`, `from: "ST1"`) is stripped so it resolves to the SAME plain
  // numeric id the Subtask Structure table and the `S<N>:`/`ST<N>:` id-key form above use
  // (measured `script-test-gaps-and-roadmap-remainders.md`: `from: S3` must resolve to table id
  // "3", not the literal string "S3", or the wave scheduler's `completed.has(r.from)` check can
  // never match and the dependent subtask blocks forever).
  function parseBraceItem(body: string): ContractItem {
    const item: ContractItem = { kind: "", path: "" };
    // `subtask_1` is the PRODUCER'S OWN canonical spelling (agents/launch-pad.md's complete
    // Subtask Contracts example) and appears in archived briefs. It must come FIRST in the
    // alternation: `S` would otherwise never match lowercase `subtask_`, the group would fall
    // through to `(\d+...)`, hit `s`, and the whole match would fail -- yielding
    // `from: undefined`, which the wave scheduler reads as NO DEPENDENCY.
    const from = body.match(/\bfrom:\s*"?(?:subtask[_-]|ST-?|S-?)?(\d+[a-z]?)"?/i);
    if (from) item.from = from[1];
    // FAIL-CLOSED on an unparseable `from:`. A silently-dropped edge is the exact
    // silent-empty-graph failure this file already guards against at the contract level, and
    // the contractless guard CANNOT see it: `provides`/`lanes` parse fine, so nothing throws
    // while every dependent subtask is scheduled into wave 1. Prefix drift has now bitten this
    // parser four times (heading spelling, id-key form, `S`/`ST` refs, `subtask_` refs), so the
    // rule is inverted here: any `from:` we cannot resolve is an ERROR, not a dropped edge.
    else if (/\bfrom:/.test(body)) {
      throw new Error(
        `parseBrief: unparseable \`from:\` reference in contract item {${body}} — refusing to ` +
          `silently drop a dependency edge (an unresolved \`from\` is read by the wave scheduler ` +
          `as NO dependency, which schedules dependents into wave 1). Accepted forms: ` +
          `1, "1a", S3, S-3, ST1, ST-1, subtask_1, subtask-1.`
      );
    }
    const kind = body.match(/\bkind:\s*([A-Za-z_]+)/);
    if (kind) item.kind = kind[1];
    const p = body.match(/\bpath:\s*"([^"]*)"/) ?? body.match(/\bpath:\s*([^,}]+)/);
    if (p) item.path = p[1].trim();
    const name = body.match(/\bname:\s*"([^"]*)"/) ?? body.match(/\bname:\s*([^,}]+)/);
    if (name) item.name = name[1].trim();
    return item;
  }

  // Three accepted umbrella heading spellings, all in live use across this repo's archived
  // briefs (measured 2026-07-31 over 73 briefs: 8 use "### Subtask contracts", 6 use
  // "### Provides / Requires Contracts", 10 use "### Provides / Requires Schema"). Matching only
  // a subset silently skipped the entire YAML block on a brief using an unmatched spelling —
  // every subtask parsed with EMPTY provides/requires, and the wave scheduler below
  // (`s.requires.every(...)`) marked EVERY subtask LAUNCHABLE in wave 1, running subtasks
  // concurrently that the brief ordered sequentially onto shared files. Same silent-empty-graph
  // class already documented below at the `subtask_(\d+[a-z]?):` fix.
  //
  // `inContracts` and `inYaml` are now two INDEPENDENT flags (previously `inYaml` could only be
  // entered from inside `inContracts`) — content is scanned whenever EITHER is true
  // (`active = inContracts || inYaml`, computed per line below). This closes three more
  // silent-empty-graph gaps measured 2026-07-31 across archived real briefs, on top of the two
  // above:
  //   - a ```yaml fence containing `provides:`/`requires:` with NO preceding recognized heading
  //     at all (e.g. `curation-corpora-and-eval-scaffold.md`: the fence sits directly under
  //     "## Subtask Structure" with no "Subtask Contracts" heading of its own). `inYaml` now
  //     opens on ANY ```yaml/```yml fence unconditionally, so this parses via the existing
  //     in-fence `subtask_N:` / `# Subtask N` id forms with no other change needed.
  //   - an umbrella heading followed by MULTIPLE SEPARATE per-subtask fences, each with NO id
  //     marker inside it at all — only bold prose (`**Subtask 1 — ...**`, not a markdown
  //     heading) immediately before each fence (e.g. `read-before-write-rule.md`,
  //     `handoff-digest.md`, `setup-twin-bootstrap.md`, `rules-substrate.md`,
  //     `rules-enforcement.md`). See the POSITIONAL FALLBACK block below.
  //   - contracts content with NO fence at all — raw `provides:`/`requires:` lines directly
  //     under the umbrella heading, subtasks separated only by a bare "Subtask N" text line
  //     (e.g. `prove-the-loop.md`). `active` now includes `inContracts` on its own (not gated on
  //     `inYaml`), so un-fenced content under a recognized heading is scanned too.
  let inContracts = false;
  let inYaml = false;
  let current: Subtask | null = null;
  let listKey: "provides" | "requires" | "lanes" | null = null;
  // POSITIONAL FALLBACK bookkeeping: some real briefs (enumerated above) declare a
  // `provides:`/`requires:` block with NO id-anchor of any kind — id is implied purely by
  // POSITION, matching the Subtask Structure table's row order. `tableOrder` is exactly that
  // order (Map insertion order from the table-parsing loop above, i.e. top-to-bottom row order).
  // Whenever a `provides:`/`requires:` header line is reached with `current` still null (no
  // subtask_N:/`# Subtask N`/`S<N>:`/bare "Subtask N"/markdown-heading anchor bound it), claim
  // the next NOT-YET-CLAIMED id from `tableOrder`, in order. This is a last resort — every
  // explicit id form above always wins when present.
  const tableOrder = Array.from(byId.keys());
  const claimed = new Set<string>();
  let positionalIdx = 0;
  function claimNextPositional(): Subtask | null {
    while (positionalIdx < tableOrder.length && claimed.has(tableOrder[positionalIdx])) positionalIdx++;
    if (positionalIdx >= tableOrder.length) return null;
    return byId.get(tableOrder[positionalIdx])!;
  }

  for (const line of lines) {
    // Fence toggles are checked FIRST and UNCONDITIONALLY — a ```yaml fence can legally appear
    // with or without a preceding recognized heading (see the curation-corpora case above).
    if (!inYaml && /^```ya?ml\s*$/.test(line)) {
      inYaml = true;
      current = null; // require an explicit (re-)bind inside this fence: id anchor or positional
      listKey = null;
      continue;
    }
    if (inYaml && /^```\s*$/.test(line)) {
      inYaml = false;
      current = null;
      listKey = null;
      continue;
    }

    // Case-INSENSITIVE and heading-depth-tolerant (`##` or `###`), deliberately.
    // `agents/launch-pad.md` — the producer — emits BOTH `### Subtask Contracts`
    // (Title-Case, :422) and `## Subtask Contracts` (H2, in its complete example
    // at :796), and archived briefs additionally use `### Subtask contracts`,
    // `### Provides / Requires Contracts`, and `### Provides / Requires Schema`. A
    // case-sensitive `###`-only match covers NONE of the producer's own two templates. That
    // was previously a latent silent-empty-graph bug; once the fail-closed guard below landed
    // it would have become a hard throw on every real multi-subtask brief, so the guard made
    // getting this right load-bearing. Mirrors the deliberately case-insensitive /
    // depth-agnostic `extract_section` in `scripts/build-context-digest.sh`.
    if (/^#{2,3}\s+(Subtask contracts|Provides \/ Requires Contracts|Provides \/ Requires Schema)\b/i.test(line)) {
      inContracts = true;
      continue;
    }
    // Per-subtask MARKDOWN heading anchor, e.g. `### Subtask 1 — Title (LAUNCHABLE)`: measured
    // 2026-07-31, some real briefs (e.g. archived `fix7-two-review-lenses.md`,
    // `one-writer-derived-state.md`) carry NO umbrella "Subtask Contracts" heading at all —
    // each subtask's own `### Subtask N — Title` markdown heading is followed directly by prose
    // and then its OWN ```yaml fence with `provides:`/`requires:` at column 0. Without this
    // branch `inContracts` never became true for those briefs and the entire YAML block for
    // every subtask was silently skipped (same silent-empty-graph class as above). Requires a
    // digit immediately after "Subtask " so it never collides with the umbrella headings above
    // (none of which are followed by a number) or with the in-fence `# Subtask N` YAML-comment
    // anchor below (single `#`, this pattern requires 2–4). Binds `current` directly from the
    // heading itself — this layout has no separate `# Subtask N` comment inside its fence.
    const subtaskHeading = line.match(/^#{2,4}\s+Subtask\s+(\d+[a-z]?)\b/i);
    if (subtaskHeading) {
      const id = subtaskHeading[1];
      if (!byId.has(id)) {
        byId.set(id, { id, title: `subtask_${id}`, tableStatus: "", provides: [], requires: [], laneGlobs: [], sawContractKey: false, sawUnparseableValue: false, declaredNonEmpty: [] });
      }
      current = byId.get(id)!;
      listKey = null;
      inContracts = true;
      continue;
    }

    const active = inContracts || inYaml;
    if (!active) continue;

    // Any OTHER heading-like line reaching this point (i.e. not the umbrella/per-subtask forms
    // matched above, and not inside a fence — headings inside a fence would be unusual YAML and
    // are left alone) ends the un-fenced `inContracts` region: a genuinely different section has
    // started (e.g. "## Parallelism Analysis").
    if (!inYaml && /^#{1,4}\s+/.test(line)) {
      inContracts = false;
      continue;
    }

    // Id-anchor forms recognized INSIDE contracts content. All are reachable fenced or
    // un-fenced EXCEPT the `# Subtask N` comment form, which is FENCE-ONLY — see its own
    // note below; do not generalize this header to "fenced or not" for all four.
    //   subtask_1:            — the runner's original contract
    //   # Subtask 1a — ...    — a YAML comment Launch Pad writes inside a fence. FENCE-ONLY
    //                           BY CONSTRUCTION, not by intent: the generic un-fenced
    //                           heading-terminator a few lines above (`!inYaml &&
    //                           /^#{1,4}\s+/`) matches a single `#` too, so an un-fenced
    //                           `# Subtask N` line always hits that terminator and
    //                           `continue`s before ever reaching this match. Harmless today
    //                           (Launch Pad only ever writes this form inside a fence, and an
    //                           un-fenced brief authored this way fails CLOSED on the
    //                           contractless guard rather than mis-scheduling) — but a future
    //                           editor reordering these checks would silently change it, so
    //                           the limitation is PINNED by a test in test/digest-lanes.test.sh
    //                           ("un-fenced `# Subtask N` is fence-only") rather than left implied.
    //   S1: / ST1:            — a bare map-key id form (measured `script-test-gaps-and-
    //                           roadmap-remainders.md`: "S1:"/"S2:"/... keyed directly off the
    //                           Subtask Structure table's plain numeric ids)
    //   Subtask 1             — a bare, punctuation-free text line (measured `prove-the-loop.md`:
    //                           un-fenced contracts content separated only by this line, never a
    //                           markdown heading and never inside a fence)
    let m =
      line.match(/^subtask_(\d+[a-z]?):/) ??
      line.match(/^#\s*[Ss]ubtask\s+(\d+[a-z]?)\b/) ??
      line.match(/^(?:ST|S)(\d+[a-z]?):\s*$/) ??
      line.match(/^Subtask\s+(\d+[a-z]?)\s*$/i);
    if (m) {
      const id = m[1];
      if (!byId.has(id)) {
        byId.set(id, { id, title: `subtask_${id}`, tableStatus: "", provides: [], requires: [], laneGlobs: [], sawContractKey: false, sawUnparseableValue: false, declaredNonEmpty: [] });
      }
      current = byId.get(id)!;
      listKey = null;
      continue;
    }
    // Leading whitespace is OPTIONAL: real Launch Pad briefs put `provides:` / `requires:` at
    // column 0 under a `# Subtask <id>` comment, while the runner's own fixture indents them. The
    // `^\s+` form matched only the fixture, so every list header in a real brief was skipped and
    // the dependency graph came out empty. The `^` anchor still keeps `external_requires:` from
    // matching `requires:`.
    // `lanes` is now a recognized list header too (alongside `provides`/`requires`) so it
    // RESETS `listKey`. Before this fix `lanes:` never matched here, so `listKey` stayed
    // whatever it was left at by the PRECEDING list (typically `requires`) — a brace-form
    // item authored under `lanes:` would have silently been appended into `requires` instead
    // of being ignored. Today real briefs quote lane entries as plain strings (never brace
    // form), so this was latent, not yet observed in the wild — but it is a live landmine the
    // moment a brief's authoring convention drifts, and is fixed here defensively.
    // The header's VALUE now also accepts an INLINE flow-style array on the same line, e.g.
    // `provides: [ { kind: file, path: foo } ]` (measured 2026-06-19-automate-engine.md: every
    // `provides:`/`requires:` line uses this single-line form, never the multi-line `- {...}`
    // form). Before this fix that line matched NEITHER the explicit-empty-list branch (content
    // between the brackets is non-empty) NOR the bare-key branch (there IS trailing content) —
    // the whole regex failed to match, the line was silently skipped, and every item inside it
    // was lost with no error.
    m = line.match(/^\s*(provides|requires|lanes):\s*(.*)$/);
    if (m) {
      // POSITIONAL FALLBACK: no id-anchor of any kind preceded this header — claim the next
      // not-yet-claimed subtask from the Subtask Structure table, in table order (see the
      // bookkeeping comment above `claimNextPositional`).
      if (!current) current = claimNextPositional();
      if (current) {
        listKey = m[1] as "provides" | "requires" | "lanes";
        // A contract key was SEEN for this subtask -- even if its list is empty. This is the
        // fail-closed guard's real discriminator (see the guard below): an all-empty but
        // explicitly-declared subtask is a SANCTIONED shape per
        // skills/supervisor-readiness/SKILL.md, while a subtask the parser never reached is
        // the defect. Length-based counting conflates the two.
        current.sawContractKey = true;
        claimed.add(current.id);
        const rest = m[2].replace(/\s*#.*$/, "").trim();
        // Shape-INDEPENDENT: a key CLAIMS to declare items when its value is a non-empty,
        // non-`[]` inline value OR when it is a BARE key (whose items must then arrive on
        // following lines). Only the explicit `[]` spelling declares emptiness. Whether the
        // claim was actually honored is resolved after parsing (see declaredNonEmpty).
        //
        // The bare-key half closes the last escape hatch in this guard: a bare `requires:`
        // followed by unstructured PROSE continuation lines (no `- {...}` dash-brace form)
        // parses to an empty list, and with only the inline form recorded here nothing ever
        // marked it unparseable -- so `sawContractKey` said "declared" and the wave scheduler
        // read the dependency as vacuously satisfied. Reproduced: a 2-subtask brief whose
        // table marks subtask 2 BLOCKED scheduled BOTH subtasks into wave 1. Same
        // silent-empty-graph class this parser already fails closed on four other ways, in the
        // one shape none of them covered. The sanctioned spelling for "genuinely nothing" is
        // the explicit `requires: []` (skills/supervisor-readiness/SKILL.md), so treating a
        // bare key that yields nothing as unparseable costs no legitimate authoring shape.
        if (!/^\[\s*\]$/.test(rest)) current.declaredNonEmpty.push(m[1]);
        if (rest === "") {
          // Bare key — items follow on subsequent lines (existing multi-line path below).
        } else if (/^\[\s*\]$/.test(rest)) {
          // Explicit empty list, e.g. `requires: []` / `lanes: []`.
          if (listKey === "lanes") current.laneGlobs = [];
          else current[listKey] = [];
          listKey = null;
        } else if (rest.startsWith("[") && rest.endsWith("]")) {
          // Inline flow-style array on one line: extract every `{...}` group inside the brackets.
          const inner = rest.slice(1, -1);
          if (listKey === "lanes") {
            // Lanes ARE plain strings, never brace objects -- which is exactly why scanning for
            // `{...}` groups here found nothing and silently produced an EMPTY laneGlobs for the
            // perfectly natural single-line form `lanes: ["a.ts", "b.ts"]`. That is not a
            // harmless miss: workerPrompt only emits the lane-boundary text when
            // laneGlobs.length > 0, so a worker spawned from an inline-authored brief received
            // NO lane boundaries at all -- quietly defeating this feature for that authoring
            // style. (The multi-line `lanes:` + `- "a.ts"` block form always worked.)
            // Split on commas OUTSIDE quotes, then strip quotes/whitespace.
            for (const rawLane of inner.split(/,(?=(?:[^"]*"[^"]*")*[^"]*$)/)) {
              const lane = rawLane.trim().replace(/^["']|["']$/g, "").trim();
              if (lane) current.laneGlobs.push(lane);
            }
          } else {
            // Scoped to this branch: lanes never carry `{...}` groups, so computing them
            // for the lanes arm above was dead work.
            for (const raw of inner.match(/\{[^}]*\}/g) ?? []) {
              current[listKey].push(parseBraceItem(raw.slice(1, -1)));
            }
          }
          listKey = null; // fully consumed on this one line — nothing to continue on the next
        }
        // Any other shape (unrecognized inline value, or free-text prose that is not a `{...}`
        // list — e.g. a brief whose `provides:`/`requires:` values are unstructured description
        // text rather than `{kind, path}` items) falls through with listKey still set to the
        // header's key; the multi-line brace-item scan below simply finds nothing to push, which
        // is the CORRECT behavior — such a brief has declared no verifiable contract item. The
        // key was recorded in `declaredNonEmpty` above, so the end-of-parse resolution below
        // marks it unparseable and the fail-closed guard fires. (This comment previously
        // asserted the guard covered this case while nothing actually set the flag on this
        // path — the check lived inside the bracketed branch only.)
      }
      continue;
    }
    if (listKey === "lanes" && current) {
      // Lane entries are plain quoted (or bare) strings, e.g. `- "loomwright/agents/worker.md"`
      // — never the brace-object form `provides`/`requires` items use. A bare `#`-prefixed
      // comment line (briefs sometimes annotate lane lists) matches neither pattern below and
      // is skipped, same as everywhere else in this parser.
      const laneItem = line.match(/^\s+-\s+"([^"]*)"/) ?? line.match(/^\s+-\s+([^\s#][^#]*?)\s*(#.*)?$/);
      if (laneItem) current.laneGlobs.push(laneItem[1].trim());
      continue;
    }
    m = line.match(/^\s+-\s+\{(.+)\}/);
    if (m && current && listKey) {
      // Narrowed explicitly (not just `listKey`'s truthiness): the "lanes" arm above always
      // `continue`s before reaching here, but TS does not carry that flow-narrowing across a
      // mutable outer-scope `let` inside a loop, so `current[listKey]` would otherwise widen
      // to include a nonexistent `current["lanes"]` index.
      if (listKey === "provides" || listKey === "requires") {
        current[listKey].push(parseBraceItem(m[1]));
      }
      continue;
    }

    // BARE SUBTASK REFERENCE under `requires:` -- `- subtask_1`, `- 1`, `- S2`, `- ST-3`,
    // optionally with a trailing `# comment`. A real, measured authoring shape (archived
    // `2026-06-02-preflight-sync-gate.md`, `2026-06-06-auto-pr-review-heal.md`) that carries
    // the dependency in the ITEM rather than in a `{from: ...}` map. Before this, only the
    // brace form was parsed, so these briefs produced `requires: []` and the wave scheduler
    // marked every subtask LAUNCHABLE -- the silent-empty-graph failure again, in the shape
    // that made the bare-key guard above look like it was false-positiving when it was in fact
    // detecting a genuinely unparsed edge. Parsing it is strictly better than throwing on it:
    // it RESTORES the ordering the brief actually declared.
    //
    // Scoped to `requires` deliberately. Under `provides`, a bare dash item is prose, not an
    // addressable output -- there is no id to resolve and nothing to schedule on, so it must
    // keep falling through to the unparseable-value guard rather than silently counting as a
    // declared output.
    if (current && listKey === "requires") {
      const bare = line.match(
        /^\s+-\s+"?(?:subtask[_-]|ST-?|S-?)?(\d+[a-z]?)"?\s*(?:#.*)?$/i
      );
      if (bare) {
        current.requires.push({ kind: "", path: "", from: bare[1] });
        continue;
      }
    }
  }

  const subtasksList = Array.from(byId.values());

  // Resolve deferred unparseable-value declarations. A key declared with a non-empty, non-`[]`
  // value that still holds ZERO items got prose where addressable {kind, path} entries belong:
  // the key was seen (so the block WAS found), but nothing verifiable was captured, and the
  // subtask would schedule as unconstrained. Done here, after the whole block is parsed, so a
  // value whose items legitimately arrive on FOLLOWING lines is not mis-flagged.
  for (const st of subtasksList) {
    for (const key of st.declaredNonEmpty) {
      const got =
        key === "lanes" ? st.laneGlobs.length
        : key === "provides" ? st.provides.length
        : st.requires.length;
      if (got === 0) { st.sawUnparseableValue = true; break; }
    }
  }

  // FAIL CLOSED (v15.20.0, AC12): a Subtask Structure table with more than one row but ZERO
  // provides/requires items parsed is the exact silent-empty-graph signature — every subtask's
  // `requires` stays the vacuous `[]` it was initialized with, `s.requires.every(...)` in the
  // wave scheduler is vacuously true for all of them, and the runner spawns every subtask
  // CONCURRENTLY in wave 1 regardless of what the brief's Subtask Structure table ordered
  // sequentially. This is exactly the class of defect that dropped all 9 dependency edges in
  // FABLE_PARITY_EVAL arm 3 (see the file-header comment) — except this variant produces NO
  // thrown error at all today, only a silently-wrong schedule. A single-subtask brief is exempt:
  // with nothing to sequence against a sibling, an all-LAUNCHABLE "wave" of one is correct
  // regardless of whether any contracts were authored.
  // The check is PER-SUBTASK, not a whole-brief sum. A whole-brief total is too weak: a brief
  // where subtask 1 declares contracts and subtask 2 declares none sums to > 0 and passes, while
  // subtask 2 silently keeps the vacuous `requires: []` and is scheduled as unconstrained — the
  // very failure this guard exists to stop, just narrowed to one row instead of all of them.
  // The authoring rules in `agents/launch-pad.md` explicitly permit `provides: []` for a
  // pure-deletion subtask and `requires: []` for a dependency-free one — a subtask that is BOTH
  // is legal. So a count over provides+requires(+lanes) would throw on that sanctioned shape,
  // indistinguishable from a block the parser never found. `laneGlobs` was tried as the
  // discriminator and is NOT sufficient either: `lanes: []` is permitted under the same
  // empty-with-justification carve-out (`skills/supervisor-readiness/SKILL.md`), so an
  // all-empty coordination-only subtask still summed to zero. The shipped discriminator is
  // `sawContractKey || sawUnparseableValue` — see the block immediately below.
  // LEGACY-BRIEF CARVE-OUT. A brief carrying an explicit top-level `legacy_brief: true` marker
  // in its Environment section is a SANCTIONED contract-free shape: `agents/plan-reviewer.md`
  // Criterion 12 exempts exactly this marker from the `provides:`/`requires:` mandate, and
  // Criterion 16 "shares that same gate". Without this carve-out the guard below hard-throws on
  // a brief the repo's own plan gate declared legal, and the thrown message directs the operator
  // to fix a contracts anchor that legitimately does not exist — measured on the archived
  // `.supervisor/jobs/done/2026-07-07-stackpack-mysql-mcp-spinoff.md`. Matched over the whole
  // brief text (not a parsed field) because the marker's spelling varies across real briefs
  // (`- **legacy_brief:** true`, `| **legacy_brief:** false`, bare `legacy_brief: true`) and the
  // marker is, per Criterion 12, "the sole observable signal" — there is no structured source.
  // NOTE this exempts ONLY the fail-closed guard. A legacy brief still parses to empty
  // `requires` and therefore still schedules all-LAUNCHABLE — which is CORRECT for a brief that
  // genuinely declares no ordering, and is precisely the distinction the guard could not draw.
  const legacyBrief = /^[\s|>*-]*\**legacy_brief\**\s*:\**\s*true\b/im.test(text);
  if (subtasksList.length > 1 && !legacyBrief) {
    // Discriminate on whether a contract key was SEEN, not on list lengths. A subtask that
    // explicitly declares `provides: []` / `requires: []` / `lanes: []` (a coordination-only
    // subtask that "genuinely touches nothing addressable", sanctioned by
    // skills/supervisor-readiness/SKILL.md) sums to zero on every list and would otherwise be
    // reported as unparsed -- a false positive that aborts a perfectly valid brief.
    const contractless = subtasksList.filter((s) => !s.sawContractKey || s.sawUnparseableValue);
    if (contractless.length > 0) {
      const ids = contractless.map((s) => s.id).join(", ");
      const allEmpty = contractless.length === subtasksList.length;
      throw new Error(
        `parseBrief: Subtask Structure table lists ${subtasksList.length} subtasks but zero ` +
          `provides/requires items were parsed for ${allEmpty ? "ANY of them" : `subtask(s) [${ids}]`} ` +
          `— refusing to emit an all-LAUNCHABLE wave for ` +
          `${allEmpty ? "them" : "those rows"}. Check the contracts anchor (matched ` +
          `case-insensitively at "##"/"###" depth: an umbrella "Subtask contracts" / ` +
          `"Provides / Requires Contracts" / "Provides / Requires Schema" heading, OR a ` +
          `per-subtask "### Subtask N — Title" markdown heading), the \`\`\`yaml fence, an ` +
          `inline flow-style \`provides: [ {...} ]\` array being well-formed, and that ids match ` +
          `the Subtask Structure table (both "subtask_1:" and "# Subtask 1a — ..." forms are accepted).`
      );
    }
  }

  const branchMatch = text.match(/Suggested branch:\s*([^\s|`]+)/);
  return {
    // Natural order: numeric prefix first, then any alpha suffix, so "1" < "1a" < "1b" < "2" < "10".
    // A plain string sort would put "10" before "2" and break wave ordering on 10+ subtasks.
    subtasks: subtasksList.sort((a, b) => {
      const na = parseInt(a.id, 10);
      const nb = parseInt(b.id, 10);
      if (na !== nb) return na - nb;
      return a.id.localeCompare(b.id);
    }),
    suggestedBranch: branchMatch ? branchMatch[1] : undefined,
  };
}

// ---------------------------------------------------------------------------
// Git helpers (live mode only — --dry-run never shells out to git)
// ---------------------------------------------------------------------------

function git(cwd: string, ...argv: string[]): string {
  return execFileSync("git", argv, { cwd, encoding: "utf8" }).trim();
}

function addWorktree(repoRoot: string, wtPath: string, subtaskId: string, featureBranch: string): string {
  // Always create the deterministic per-subtask branch off the feature branch
  // (the real Execute Manager's pattern — git refuses to double-checkout the
  // feature branch itself, and a shared branch would interleave subtask work).
  const branch = `sdk-spike/subtask-${subtaskId}`;
  let branchExists = true;
  try {
    git(repoRoot, "rev-parse", "--verify", "--quiet", `refs/heads/${branch}`);
  } catch {
    branchExists = false;
  }
  if (branchExists) {
    // FAIL CLOSED — never silently reuse or overwrite a stale branch from a
    // previous run (its commits may not have been merged yet), and never fall
    // back to checking out the feature branch itself.
    throw new Error(
      `stale branch ${branch} already exists — merge or delete it (git branch -D ${branch}) before re-running`
    );
  }
  git(repoRoot, "worktree", "add", "-b", branch, wtPath, featureBranch);
  return branch;
}

/**
 * Persist the worker's output: commit inside the worktree so the per-subtask
 * branch actually carries the work after the worktree is removed. Mirrors
 * FINALIZE step 2 of skills/async-orchestration/SKILL.md — work lives on
 * branches; the caller merges them per merge_order and deletes them.
 * Returns true if a commit was created; skips when the worktree is clean.
 */
function commitWorktree(wtPath: string, subtask: Subtask): boolean {
  const dirty = git(wtPath, "status", "--porcelain");
  if (dirty === "") return false;
  git(wtPath, "add", "-A");
  git(wtPath, "commit", "-m", `subtask ${subtask.id}: ${subtask.title}`);
  return true;
}

/**
 * Materialize a completed wave's output into the feature branch.
 *
 * WHY THIS EXISTS — this was residual divergence 3, and it made the runner unusable on any brief
 * whose subtasks consume each other's files (measured 2026-07-28, FABLE_PARITY_EVAL arm 3).
 *
 * The wave scheduler already honours `requires` correctly: subtask 2 does not START until subtask 1
 * has COMPLETED. But `addWorktree` branches every worktree from `featureBranch`, and worker output
 * is committed to the per-subtask branch `sdk-spike/subtask-N` — which was never merged back during
 * the run. So a dependent got ordering in TIME but nothing in CONTENT: it started after its producer
 * finished and still could not see one line the producer wrote. On a brief where subtask 2 imports a
 * type subtask 1 creates, that is a guaranteed compile failure, not a subtle difference.
 *
 * Merging each wave into `featureBranch` before the next wave's worktrees are created closes the
 * gap without touching `addWorktree` — the next `git worktree add … featureBranch` now inherits
 * everything already landed, which is exactly how the prompt-driven Execute Manager behaves via its
 * sequential merges.
 *
 * FAILS CLOSED. A conflicting merge is aborted and thrown, never left half-applied: continuing with
 * a conflicted index would hand the next wave a broken tree and corrupt every downstream subtask.
 * The caller marks the run failed. This mirrors FINALIZE's pre-merge safety gate
 * (skills/async-orchestration/SKILL.md) — the merge is the dangerous step, so it is the guarded one.
 */
export function materializeWave(repoRoot: string, featureBranch: string, branches: string[]): void {
  if (branches.length === 0) return;

  // The merge target must actually be checked out in the main worktree. Supervisor's ACQUIRE leaves
  // repoRoot on the feature branch; assert rather than assume, because merging into whatever happens
  // to be checked out would silently corrupt an unrelated branch.
  const head = git(repoRoot, "branch", "--show-current");
  if (head !== featureBranch) {
    throw new Error(
      `cannot materialize wave: repo root is on "${head}", expected feature branch "${featureBranch}". ` +
        `Check out ${featureBranch} in the main worktree before running.`
    );
  }

  for (const branch of branches) {
    // Ask git whether this branch actually carries work, rather than trusting a plumbed flag: a
    // worker that produced no changes leaves nothing to commit, and `git merge` on an
    // already-ancestor branch is a no-op we skip explicitly so the log stays honest.
    let ahead = "0";
    try {
      ahead = git(repoRoot, "rev-list", "--count", `${featureBranch}..${branch}`);
    } catch {
      // Unresolvable branch — nothing to merge, and addWorktree already failed closed if it mattered.
      continue;
    }
    if (ahead === "0") continue;

    try {
      git(repoRoot, "merge", "--no-ff", "-m", `merge: ${branch}`, branch);
    } catch (err) {
      try {
        git(repoRoot, "merge", "--abort");
      } catch {
        // A merge that never started leaves nothing to abort; the throw below is the real signal.
      }
      throw new Error(
        `dependency materialization failed: merging ${branch} into ${featureBranch} conflicted. ` +
          `The merge was aborted and the tree left clean. ${(err as Error).message}`
      );
    }
  }
}

function removeWorktree(repoRoot: string, wtPath: string): void {
  try {
    git(repoRoot, "worktree", "remove", "--force", wtPath);
  } catch (err) {
    // Cleanup is best-effort; surface but don't mask the primary result.
    console.error(`WARN: failed to remove worktree ${wtPath}: ${(err as Error).message}`);
  }
}

// ---------------------------------------------------------------------------
// Query implementations (the injected seam)
// ---------------------------------------------------------------------------

function tryParseJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

/** Locate src/dry-run-fixtures whether running compiled (dist/) or via tsx (src/). */
function fixtureDir(): string {
  const candidates = [
    path.join(__dirname, "dry-run-fixtures"), // running from src/ via tsx
    path.join(__dirname, "..", "src", "dry-run-fixtures"), // running from dist/
  ];
  for (const c of candidates) {
    if (fs.existsSync(c)) return c;
  }
  throw new Error(`dry-run fixtures directory not found (tried: ${candidates.join(", ")})`);
}

/**
 * --dry-run query: NO API calls, NO network, NO worktrees. Returns canned
 * schema-valid objects from src/dry-run-fixtures/, re-validated against the
 * same schema the live path would force. Deterministic and fully offline.
 *
 * Fixture sets (--dry-run-fixture-set) exercise the failure paths offline:
 *   default     — success fixtures (both roles succeed)
 *   fail        — workers return status "failed" (worker gate + blocked-forever sweep)
 *   review-fail — workers succeed, reviewers return decision FAIL
 *                 (review-FAIL branch + blocked-forever sweep)
 *   throw-usage — workers succeed, reviewers throw QueryFailedError carrying
 *                 synthetic captured usage (proxy:true — never invented as
 *                 real) to exercise the runSubtask catch fold-back offline
 *   throw-usage-worker — the WORKER query throws the same QueryFailedError
 *                 shape, exercising the symmetric worker arm of the fold-back
 *                 (reviewer never runs; its usage stays null)
 */
function makeDryRunQuery(fixtureSet: DryRunFixtureSet): QueryFn {
  const dir = fixtureDir();
  return async (kind, _prompt, schema, opts) => {
    // Opt-in trace (stderr, dry-run only, gated on SDK_SPIKE_TRACE_OPTS=1):
    // echo the RESOLVED effort/taskBudget the call site passed through the
    // seam, so the offline self-test can assert ROLE_CONFIG precedence and
    // taskBudget omit-when-unset / worker-only end-to-end. Dry-run never
    // acts on these opts; gated so default dry-run output stays byte-stable.
    if (process.env["SDK_SPIKE_TRACE_OPTS"] === "1") {
      console.error(
        `DRY-RUN ${kind} opts: effort=${opts.effort ?? "(unset)"} taskBudget=${
          opts.taskBudget !== undefined ? opts.taskBudget : "(omitted)"
        }`
      );
    }
    if (fixtureSet === "throw-usage-worker" && kind === "worker") {
      // Symmetric worker-arm variant of throw-usage: the WORKER query dies
      // after usage capture, so the fold-back's worker branch is dry-run-
      // proven too (reviewer never runs for the subtask).
      throw new QueryFailedError(
        "worker query failed after usage capture (throw-usage-worker fixture)",
        "worker",
        {
          input_tokens: 700,
          output_tokens: 150,
          cache_creation_input_tokens: 40,
          cache_read_input_tokens: 250,
          total_cost_usd: 0.008,
          num_turns: 2,
        },
        true
      );
    }
    if (fixtureSet === "throw-usage" && kind === "reviewer") {
      // Offline stand-in for the live fail-closed throws: the reviewer query
      // dies AFTER usage was captured. Synthetic numbers, labeled proxy:true
      // (never invent token counts); the catch must fold them into the
      // failed entry's token_usage.
      throw new QueryFailedError(
        "reviewer query failed after usage capture (throw-usage fixture)",
        "reviewer",
        {
          input_tokens: 1000,
          output_tokens: 200,
          cache_creation_input_tokens: 50,
          cache_read_input_tokens: 300,
          total_cost_usd: 0.01,
          num_turns: 3,
        },
        true
      );
    }
    const file =
      kind === "worker"
        ? fixtureSet === "fail"
          ? "worker-result-fail.fixture.json"
          : "worker-result.fixture.json"
        : fixtureSet === "review-fail"
          ? "code-review-result-fail.fixture.json"
          : "code-review-result.fixture.json";
    const raw = JSON.parse(fs.readFileSync(path.join(dir, file), "utf8"));
    const errors = validateAgainstSchema(raw, schema as never);
    if (errors.length > 0) {
      throw new Error(`dry-run fixture ${file} fails its schema: ${errors.join("; ")}`);
    }
    // Fixtures are WORKER_RESULT/CODE_REVIEW_RESULT payloads — usage lives on
    // the result MESSAGE, not the payload — so the dry-run seam synthesizes a
    // zero-usage outcome instead of touching the fixtures. `proxy: true`
    // labels the zeros as synthetic (never invent token counts; mirrors the
    // plugin's token-ledger convention).
    return { payload: raw, usage: zeroUsage(), proxy: true };
  };
}

/**
 * Live query: one `query()` per worker/reviewer with structured output forced
 * to the given JSON Schema (capability matrix row 2 — per-worker schemas mean
 * one query() per role instance, which is exactly this spike's shape).
 *
 * The SDK is loaded lazily via a variable import specifier so that `tsc`
 * compiles and --dry-run runs even when node_modules/@anthropic-ai is absent.
 */
function makeLiveQuery(): QueryFn {
  return async (kind, prompt, schema, opts) => {
    const modName = "@anthropic-ai/claude-agent-sdk";
    let sdk: { query: (args: { prompt: string; options: Record<string, unknown> }) => AsyncIterable<Record<string, unknown>> };
    try {
      sdk = (await import(modName)) as never;
    } catch (err) {
      throw new Error(
        `Agent SDK not installed (run \`npm install\` in loomwright/sdk-spike): ${(err as Error).message}`
      );
    }

    const outputFormat = { type: "json_schema", schema };
    const options: Record<string, unknown> = {
      // Structured outputs, per the brief's verified capability matrix (row 2,
      // https://code.claude.com/docs/en/agent-sdk/structured-outputs.md):
      output_format: outputFormat,
      // NEEDS VERIFICATION vs docs: the TS SDK may spell this option camelCase
      // (`outputFormat`). Both spellings are set defensively; whichever the SDK
      // ignores is inert.
      outputFormat,
      maxTurns: 40,
    };
    if (opts.cwd) options.cwd = opts.cwd; // per-query cwd = the subtask's worktree (capability row 7)
    if (opts.model) options.model = opts.model;
    if (opts.effort !== undefined) {
      // Per-role effort resolved via ROLE_CONFIG / resolveRoleConfig at the
      // call sites. `Options.effort` is typed at sdk.d.ts:1620 (EffortLevel
      // set at :522); values are fail-closed validated in parseArgs.
      options.effort = opts.effort;
    }
    if (opts.taskBudget !== undefined) {
      // Opt-in per-query task budget: `taskBudget?: { total: number }` at
      // sdk.d.ts:1647-1649 (@alpha, beta header task-budgets-2026-03-13).
      // When unset the field is OMITTED entirely (never null/0); the
      // documented 20k-token minimum is enforced fail-closed in parseArgs.
      options.taskBudget = { total: opts.taskBudget };
    }

    let structured: unknown = null;
    let sawResult = false;
    let usage: RoleTokenUsage = zeroUsage();
    for await (const msg of sdk.query({ prompt, options })) {
      if (!msg || msg["type"] !== "result") continue;
      sawResult = true;
      // Per-subtask token accounting: capture `usage` / `total_cost_usd` /
      // `num_turns` from the terminal result message (SDKResultSuccess at
      // sdk.d.ts:4024, fields :4037-4042). Absent fields default to 0 via
      // asFiniteNumber — nothing is invented.
      const u = (msg["usage"] ?? {}) as Record<string, unknown>;
      usage = {
        input_tokens: asFiniteNumber(u["input_tokens"]),
        output_tokens: asFiniteNumber(u["output_tokens"]),
        cache_creation_input_tokens: asFiniteNumber(u["cache_creation_input_tokens"]),
        cache_read_input_tokens: asFiniteNumber(u["cache_read_input_tokens"]),
        total_cost_usd: asFiniteNumber(msg["total_cost_usd"]),
        num_turns: asFiniteNumber(msg["num_turns"]),
      };
      const subtype = String(msg["subtype"] ?? "");
      if (subtype === "error_max_structured_output_retries") {
        // FAIL CLOSED: the SDK exhausted its structured-output retries — never
        // fabricate or accept a schema-invalid result. Usage was captured
        // above, so the typed error carries the real spend of the failed query.
        throw new QueryFailedError(
          `error_max_structured_output_retries: ${kind} query() could not produce schema-valid output — failing closed`,
          kind,
          usage
        );
      }
      if (subtype.startsWith("error")) {
        throw new QueryFailedError(
          `${kind} query() returned an error result (subtype: ${subtype}) — failing closed`,
          kind,
          usage
        );
      }
      // NEEDS VERIFICATION vs docs: exact field name carrying the structured
      // payload on the final result message; both snake_case and camelCase are
      // probed, with a JSON-parse of the plain `result` text as last resort.
      structured =
        msg["structured_output"] ??
        msg["structuredOutput"] ??
        (typeof msg["result"] === "string" ? tryParseJson(msg["result"]) : null);
    }
    if (!sawResult) {
      // No result message at all — no usage was ever captured, so a plain
      // Error is honest here (nothing to carry; do NOT claim real zero spend).
      throw new Error(`${kind} query() produced no structured result — failing closed`);
    }
    if (structured === null || structured === undefined) {
      throw new QueryFailedError(
        `${kind} query() produced no structured result — failing closed`,
        kind,
        usage
      );
    }
    const errors = validateAgainstSchema(structured, schema as never);
    if (errors.length > 0) {
      throw new QueryFailedError(
        `${kind} structured output failed local re-validation: ${errors.join("; ")} — failing closed`,
        kind,
        usage
      );
    }
    return { payload: structured, usage, proxy: false };
  };
}

// ---------------------------------------------------------------------------
// Prompt builders (worker + reviewer)
// ---------------------------------------------------------------------------

/**
 * Build the context-digest pointer line handed to every worker spawn — the SDK-runner carrier
 * named in docs/RESULT_SCHEMAS.md §CONTEXT_DIGEST ("... on both the Task-spawn carrier and the
 * SDK-runner carrier ... `sdk-spike/src/runner.ts`'s `contextDigestPointer`"), mirroring the
 * Task-spawn carrier's wording in skills/async-orchestration/SKILL.md §"Context digest pointer":
 * path + a bounded (<=200 char) summary + "Read only the sections you need" — never the digest
 * body itself (pointer, not payload).
 *
 * Every subtask this runner spawns a worker for is worktree-resident (`addWorktree` always
 * creates one per live-mode subtask — this runner has no project-root-resident/sequential
 * shape), so the ONLY correct form is the MAIN-CHECKOUT ABSOLUTE path: gitignored
 * `.supervisor/` artifacts do not exist inside linked git worktrees
 * (docs/POINTER_AUDIT.md §"Worktree reality"), the same rule already governing the brief
 * pointer. `repoRoot` MUST be the main checkout (git's `--show-toplevel` captured in `main()`
 * BEFORE any subtask worktree is created), never a worktree path.
 *
 * Advisory only: returns `undefined` (never a placeholder string pointing at nothing) when the
 * digest file has not been produced yet (a pre-v15.20.0 brief, or a job whose Launch Pad
 * Phase 5 has not run) — callers omit the line entirely rather than spawning a dead pointer.
 */
export function contextDigestPointer(repoRoot: string, briefPath: string): string | undefined {
  const digestPath = path.resolve(repoRoot, ".supervisor", "jobs", "context-digests", path.basename(briefPath));
  if (!fs.existsSync(digestPath)) return undefined;
  const summary =
    "File Impact Map, interfaces touched, conventions, sibling-subtask summary, and cross-lane " +
    "provides/requires/lanes contracts for this job."; // 141 chars, kept <=200 per the pointer contract
  return (
    `Context digest: ${digestPath} — MAIN-CHECKOUT ABSOLUTE path (resolves for you even though ` +
    `you run in a worktree; gitignored .supervisor/ artifacts do not exist inside linked worktrees). ` +
    `Summary: ${summary} Read only the sections you need. Advisory only — proceed without it if the ` +
    `file does not exist.`
  );
}

// Exported (alongside parseBrief / materializeWave / contextDigestPointer) so
// digest-lanes.test.sh can assert the digest pointer + lane text actually land in the
// composed prompt, without shelling out to a live SDK query().
export function workerPrompt(subtask: Subtask, wtPath: string, digestPointer?: string): string {
  const provides =
    subtask.provides.length > 0
      ? subtask.provides
          .map((p) => `- {kind: ${p.kind}, path: ${p.path}${p.name ? `, name: "${p.name}"` : ""}}`)
          .join("\n")
      : "(none listed)";
  const lines = [
    `You are an implementation worker. Implement subtask ${subtask.id}: ${subtask.title}.`,
    `Work ONLY inside this directory (your git worktree): ${wtPath}`,
    `Do NOT run any git commit/branch/push operations.`,
    ``,
  ];
  if (digestPointer) {
    lines.push(digestPointer, ``);
  }
  if (subtask.laneGlobs.length > 0) {
    // Verbatim from the brief's Subtask Contracts `lanes:` — the paths this subtask is expected
    // to modify/create, mirroring agents/worker.md's "Lane declaration" spawn input. Pasted
    // directly (not a pointer) because, unlike the Task-spawn worker, this SDK-spawned worker
    // has no separate brief-read step of its own to re-derive its lane from — same "deliberate
    // paste exception" reasoning docs/POINTER_AUDIT.md already applies to `provides:` below.
    lines.push(
      `Your declared lane (paths you are expected to modify/create — touching a path outside`,
      `this list is reportable via out_of_lane, never blocking):`,
      ...subtask.laneGlobs.map((g) => `- ${g}`),
      ``
    );
  }
  lines.push(
    `Promised outputs (provides) — verify each before finishing and report`,
    `them in outputs_verified; list anything missing in outputs_gap:`,
    provides,
    ``,
    `Report your result as a WORKER_RESULT object (schema_version 2).`
  );
  return lines.join("\n");
}

function reviewerPrompt(subtask: Subtask, workerResult: WorkerResult, wtPath: string): string {
  const files = [...workerResult.files_modified, ...(workerResult.files_created ?? [])];
  return [
    `You are a code reviewer. Review the changes for subtask ${subtask.id}: ${subtask.title}.`,
    `Worktree: ${wtPath}`,
    `Files reported by the worker (review these):`,
    ...files.map((f) => `- ${f}`),
    ``,
    `Worker summary: ${workerResult.summary}`,
    ``,
    `Report your result as a CODE_REVIEW_RESULT object (schema_version 3,`,
    `review_mode diff_review). decision: PASS, FAIL, or NEEDS_HUMAN.`,
  ].join("\n");
}

// ---------------------------------------------------------------------------
// Step 4: deterministic in-code poll loop
// (Promise-pool over concurrent workers, wave recompute for unblocking)
// ---------------------------------------------------------------------------

async function runPool<T>(items: T[], limit: number, fn: (item: T) => Promise<void>): Promise<void> {
  const queue = items.slice();
  const lanes: Promise<void>[] = [];
  const laneCount = Math.max(1, Math.min(limit, queue.length));
  for (let i = 0; i < laneCount; i++) {
    lanes.push(
      (async () => {
        for (;;) {
          const item = queue.shift();
          if (item === undefined) return;
          await fn(item);
        }
      })()
    );
  }
  await Promise.all(lanes);
}

interface SubtaskOutcome {
  subtask: Subtask;
  branch: string;
  wtPath: string;
  workerResult?: WorkerResult;
  reviewResult?: CodeReviewResult;
  /** aggregated worker+reviewer token accounting; undefined when no query ran */
  tokenUsage?: SubtaskTokenUsage;
  error?: string;
}

async function main(): Promise<number> {
  const args = parseArgs(process.argv.slice(2));

  const briefPath = path.resolve(args.brief);
  if (!fs.existsSync(briefPath)) {
    throw new Error(`Brief not found: ${briefPath}`);
  }
  const briefText = fs.readFileSync(briefPath, "utf8");

  // Step 1: parse inputs
  const { subtasks, suggestedBranch } = parseBrief(briefText);
  if (subtasks.length === 0) {
    throw new Error("No subtasks found in brief (need a Subtask Structure table and/or Subtask contracts YAML)");
  }

  // Live-mode git context (never touched in --dry-run)
  let repoRoot = "";
  let repoName = "spike";
  let featureBranch = args.branch ?? suggestedBranch ?? "";
  if (!args.dryRun) {
    repoRoot = git(process.cwd(), "rev-parse", "--show-toplevel");
    repoName = path.basename(repoRoot);
    if (!featureBranch) featureBranch = git(repoRoot, "branch", "--show-current");
    if (!featureBranch) throw new Error("Could not determine feature branch (pass --branch)");
  } else if (!featureBranch) {
    featureBranch = "dry-run/feature";
  }

  const queryFn: QueryFn = args.dryRun ? makeDryRunQuery(args.dryRunFixtureSet) : makeLiveQuery();

  // Advisory pointer, computed once per run (not per subtask — same digest file for every
  // worker on this job). Skipped in --dry-run: repoRoot is never resolved there (no worktrees,
  // no live queries — the dry-run query seam ignores its `prompt` argument entirely), so there
  // is nothing meaningful to point at.
  const digestPointer = args.dryRun ? undefined : contextDigestPointer(repoRoot, briefPath);

  const completed = new Map<string, SubtaskOutcome>();
  const failed = new Map<string, SubtaskOutcome>();
  const worktrees: WorktreeRecord[] = [];
  const mergeOrder: string[] = [];

  const runSubtask = async (subtask: Subtask): Promise<void> => {
    const taskId = `subtask-${subtask.id}`;
    // Both modes record the INTENDED deterministic per-subtask branch name up
    // front (dry-run synthesizes it; live addWorktree creates exactly this
    // name) — so an early failure (e.g. addWorktree throwing) never records
    // the feature branch as the subtask's branch.
    let branch = `sdk-spike/subtask-${subtask.id}`;
    let wtPath = "(dry-run: worktree skipped)";
    const record: WorktreeRecord = { taskId, wtPath, branch, created: false, removed: false };
    worktrees.push(record);
    // Per-query outcomes tracked outside the try so a mid-subtask failure
    // (e.g. review FAIL after a successful worker query) still reports the
    // token usage accumulated up to that point.
    let workerQuery: QueryOutcome | null = null;
    let reviewerQuery: QueryOutcome | null = null;
    try {
      // Step 2: worktree per launchable subtask (SKIPPED entirely in --dry-run)
      if (!args.dryRun) {
        wtPath = path.resolve(repoRoot, "..", `${repoName}-sdk-${subtask.id}`);
        branch = addWorktree(repoRoot, wtPath, subtask.id, featureBranch);
        record.wtPath = wtPath;
        record.branch = branch;
        record.created = true;
      }

      // Step 3: one worker query(), schema-forced to WORKER_RESULT v2.
      // Effort resolves via the ROLE_CONFIG table (never hard-coded here);
      // the opt-in --task-budget applies to WORKER queries only.
      workerQuery = await queryFn("worker", workerPrompt(subtask, wtPath, digestPointer), WORKER_RESULT_SCHEMA, {
        cwd: args.dryRun ? undefined : wtPath,
        model: args.model,
        effort: resolveRoleConfig("worker", args).effort,
        taskBudget: args.taskBudget,
      });
      const workerResult = { ...(workerQuery.payload as WorkerResult), task_id: taskId };

      // Mirror of the real loop's v12 outputs gate: partial/failed workers do
      // NOT proceed to review (execute-manager.md Step 4).
      if (workerResult.status === "failed") {
        throw new Error(`worker reported status=failed: ${workerResult.error ?? "(no error given)"}`);
      }
      if (workerResult.status === "partial" || (workerResult.outputs_gap ?? "") !== "") {
        throw new Error(`worker reported outputs_gap: "${workerResult.outputs_gap}" — not proceeding to review`);
      }

      // Persist the worker's output on the per-subtask branch BEFORE review,
      // so worktree removal at exit never destroys work (mirrors FINALIZE
      // step 2: branches carry the work; the caller merges + deletes them).
      if (!args.dryRun) {
        const committed = commitWorktree(wtPath, subtask);
        if (!committed) {
          console.error(`WARN: worker for ${taskId} left the worktree clean — nothing to commit on ${branch}`);
        }
      }

      // Step 4 (per-completion): one reviewer query(), schema-forced to CODE_REVIEW_RESULT v3.
      // Effort resolves via ROLE_CONFIG (reviewer default is the table's
      // higher level). Reviewer queries deliberately get NO taskBudget:
      // reviewer output is bounded by the CODE_REVIEW_RESULT schema (a
      // structured verdict, not open-ended implementation work), so a token
      // budget adds mid-review truncation risk without a cost upside.
      reviewerQuery = await queryFn("reviewer", reviewerPrompt(subtask, workerResult, wtPath), CODE_REVIEW_RESULT_SCHEMA, {
        cwd: args.dryRun ? undefined : wtPath,
        model: args.model,
        effort: resolveRoleConfig("reviewer", args).effort,
      });
      const reviewResult = reviewerQuery.payload as CodeReviewResult;

      if (reviewResult.decision !== "PASS") {
        // Spike simplification: no fix-worker retry loop; FAIL/NEEDS_HUMAN = subtask failed.
        throw new Error(`review decision ${reviewResult.decision}: ${reviewResult.summary}`);
      }

      completed.set(subtask.id, {
        subtask,
        branch,
        wtPath,
        workerResult,
        reviewResult,
        tokenUsage: aggregateTokenUsage(workerQuery, reviewerQuery),
      });
      mergeOrder.push(branch);
    } catch (err) {
      // Live-mode fail-closed throws (QueryFailedError) carry the failing
      // query's captured usage — fold it into that role's outcome so the
      // failed entry's token_usage includes the real spend of the query
      // that threw (never overwrite a role outcome that already returned).
      if (err instanceof QueryFailedError) {
        const failedOutcome: QueryOutcome = { payload: null, usage: err.usage, proxy: err.proxy };
        if (err.kind === "worker" && workerQuery === null) workerQuery = failedOutcome;
        else if (err.kind === "reviewer" && reviewerQuery === null) reviewerQuery = failedOutcome;
      }
      failed.set(subtask.id, {
        subtask,
        branch,
        wtPath,
        error: (err as Error).message,
        // Report usage where available (e.g. worker ran, review failed);
        // undefined when no query completed for this subtask.
        tokenUsage:
          workerQuery || reviewerQuery ? aggregateTokenUsage(workerQuery, reviewerQuery) : undefined,
      });
    }
  };

  // Wave scheduling: LAUNCHABLE = every `requires` producer already completed.
  // This is the deterministic in-code equivalent of the poll loop's
  // "check workers → launch newly launchable" cycle.
  let pending = subtasks.slice();
  for (;;) {
    const launchable = pending.filter((s) =>
      s.requires.every((r) => r.from === undefined || completed.has(r.from))
    );
    if (launchable.length === 0) break;
    pending = pending.filter((s) => !launchable.includes(s));
    await runPool(launchable, args.maxWorkers, runSubtask);

    // Materialize this wave into the feature branch BEFORE the next wave's worktrees are created
    // (addWorktree branches from featureBranch). Without this the next wave sees an empty tree —
    // `requires` would buy spawn ordering and nothing else. Only branches that actually carry a
    // commit are merged: a subtask whose worker produced no changes has no branch to merge.
    if (!args.dryRun) {
      const waveBranches = launchable
        .map((s) => completed.get(s.id))
        .filter((o): o is SubtaskOutcome => o !== undefined && Boolean(o.branch))
        .map((o) => o.branch);
      materializeWave(repoRoot, featureBranch, waveBranches);
    }
  }

  // Anything still pending is blocked forever (producer failed or never ran).
  for (const s of pending) {
    const unmet = s.requires
      .filter((r) => r.from !== undefined && !completed.has(r.from))
      .map((r) => `subtask ${r.from}`);
    failed.set(s.id, {
      subtask: s,
      branch: "",
      wtPath: "",
      error: `blocked: unmet requires from ${unmet.join(", ") || "(unknown)"}`,
    });
  }

  // Cleanup: remove worktrees on exit. Branches are KEPT — worker output was
  // committed on them (commitWorktree) and the caller merges per merge_order,
  // then deletes the branches.
  if (!args.dryRun) {
    for (const record of worktrees) {
      if (record.created && !record.removed) {
        removeWorktree(repoRoot, record.wtPath);
        record.removed = true;
      }
    }
  }

  // Step 5: EXECUTE_RESULT-equivalent block on stdout
  const result: ExecuteResultEquivalent = {
    schema_version: 1,
    mode: args.dryRun ? "dry-run" : "live",
    subtasks_completed: Array.from(completed.values()).map((o) => ({
      task_id: `subtask-${o.subtask.id}`,
      status: "completed" as const,
      branch: o.branch,
      files_modified: [
        ...(o.workerResult?.files_modified ?? []),
        ...(o.workerResult?.files_created ?? []),
      ],
      review_decision: o.reviewResult?.decision ?? "PASS",
      // ADDITIVE per-subtask token accounting. Completed subtasks always have
      // it (both queries ran); the fallback is defensive-only and honestly
      // proxy-labeled zeros (never invent token counts).
      token_usage: o.tokenUsage ?? aggregateTokenUsage(null, null),
    })),
    subtasks_failed: Array.from(failed.values()).map((o) => ({
      task_id: `subtask-${o.subtask.id}`,
      status: "failed" as const,
      error: o.error ?? "(unknown)",
      retry_count: 0,
      // ADDITIVE — where available (e.g. worker ran before the failure);
      // null when no query ran (e.g. blocked-forever sweep).
      token_usage: o.tokenUsage ?? null,
    })),
    merge_order: mergeOrder,
    worktrees: worktrees.map((w) => ({
      task_id: w.taskId,
      path: w.wtPath,
      branch: w.branch,
      // Outcome first, so "failed"/"completed" stay meaningful in live mode
      // (where every created worktree is removed on exit): a failed subtask
      // reports "failed" even after its worktree was cleaned up.
      status: failed.has(w.taskId.replace("subtask-", ""))
        ? ("failed" as const)
        : w.removed
          ? ("cleaned" as const)
          : ("completed" as const),
    })),
    branches: Array.from(new Set(worktrees.filter((w) => w.created || args.dryRun).map((w) => w.branch))),
    summary: `${completed.size}/${subtasks.length} subtasks completed${failed.size > 0 ? `, ${failed.size} failed` : ""} (${args.dryRun ? "dry-run: no API calls, no worktrees" : "live: worker output committed per subtask branch; worktrees removed; branches kept — merge per merge_order, then delete"}).`,
  };

  console.log(JSON.stringify(result, null, 2));
  return failed.size > 0 ? 1 : 0;
}

// Run the CLI only when executed directly. Without this guard, `require()`-ing this module for a
// unit test starts the CLI, which exits(2) on the missing --brief — so a test that imports an
// exported helper is killed by an unrelated argv check while its own assertion is still in flight.
// (Found 2026-07-28 while adding the materializeWave regression: the merge under test actually
// succeeded, then the async main() rejection exited the process and the harness read it as failure.)
if (require.main === module) {
  main()
    .then((code) => process.exit(code))
    .catch((err) => {
      console.error(`FATAL: ${(err as Error).message}`);
      process.exit(2);
    });
}
