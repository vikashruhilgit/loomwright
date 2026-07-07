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
 *   node dist/runner.js --brief <path> [--dry-run] [--max-workers N] [--model M] [--effort E] [--branch B]
 *
 * Spike simplifications vs the real Execute Manager (documented in README.md):
 *   - no fix-worker retry loop on review FAIL (single attempt; FAIL = subtask failed)
 *   - no Context-Keeper batching (state lives in-process)
 *   - dependency materialization is simplified: dependents branch from the
 *     feature branch after producers complete; producer branches are NOT
 *     merged into the dependent worktree (Step 2a of the real protocol)
 *   - no tool-call budget / EXECUTE_CHECKPOINT — failures land in
 *     subtasks_failed of the final block instead
 *   - branch lifecycle: the runner commits worker output (mirroring FINALIZE
 *     step 2 of skills/async-orchestration/SKILL.md) but does NOT merge —
 *     merging the branches in merge_order and deleting them is the caller's job
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
  validateAgainstSchema,
} from "./schemas";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface ContractItem {
  kind: string;
  path: string;
  name?: string;
  from?: number; // producing subtask id (requires entries)
}

interface Subtask {
  id: number;
  title: string;
  tableStatus: string; // Status cell from the Subtask Structure table (informational)
  provides: ContractItem[];
  requires: ContractItem[];
}

interface CliArgs {
  brief: string;
  dryRun: boolean;
  maxWorkers: number;
  model?: string;
  effort?: string;
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

/**
 * The injected query seam. Live mode wires this to the Agent SDK's `query()`;
 * --dry-run injects a fake that returns canned fixtures (no API calls, no
 * network, deterministic) — the "MockTransport" of this spike.
 */
type QueryFn = (
  kind: QueryKind,
  prompt: string,
  schema: object,
  opts: { cwd?: string; model?: string; effort?: string }
) => Promise<unknown>;

// ---------------------------------------------------------------------------
// CLI parsing
// ---------------------------------------------------------------------------

function usage(): string {
  return "Usage: node dist/runner.js --brief <path> [--dry-run] [--max-workers N] [--model M] [--effort E] [--branch B]";
}

function parseArgs(argv: string[]): CliArgs {
  const args: CliArgs = { brief: "", dryRun: false, maxWorkers: 2 };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    switch (a) {
      case "--brief":
        args.brief = argv[++i] ?? "";
        break;
      case "--dry-run":
        args.dryRun = true;
        break;
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
        args.effort = argv[++i];
        break;
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
  const byId = new Map<number, Subtask>();

  // --- Subtask Structure table: | # | Title | Est. files | Status | ---
  let inStructure = false;
  for (const line of lines) {
    if (/^##\s+Subtask Structure\b/.test(line)) {
      inStructure = true;
      continue;
    }
    if (inStructure && /^##\s/.test(line)) inStructure = false; // next H2 ends the section (### stays inside)
    if (!inStructure) continue;
    const m = line.match(/^\|\s*(\d+)\s*\|([^|]+)\|[^|]*\|([^|]+)\|/);
    if (m) {
      const id = Number(m[1]);
      byId.set(id, {
        id,
        title: m[2].trim(),
        tableStatus: m[3].trim(),
        provides: [],
        requires: [],
      });
    }
  }

  // --- ### Subtask contracts YAML block ---
  let inContracts = false;
  let inYaml = false;
  let current: Subtask | null = null;
  let listKey: "provides" | "requires" | null = null;
  for (const line of lines) {
    if (/^###\s+Subtask contracts\b/.test(line)) {
      inContracts = true;
      continue;
    }
    if (inContracts && !inYaml) {
      if (/^```ya?ml\s*$/.test(line)) inYaml = true;
      else if (/^##/.test(line)) inContracts = false; // section ended without a yaml fence
      continue;
    }
    if (!inYaml) continue;
    if (/^```\s*$/.test(line)) {
      inYaml = false;
      inContracts = false;
      continue;
    }
    let m = line.match(/^subtask_(\d+):/);
    if (m) {
      const id = Number(m[1]);
      if (!byId.has(id)) {
        byId.set(id, { id, title: `subtask_${id}`, tableStatus: "", provides: [], requires: [] });
      }
      current = byId.get(id)!;
      listKey = null;
      continue;
    }
    m = line.match(/^\s+(provides|requires):\s*(\[\s*\])?\s*(#.*)?$/);
    if (m && current) {
      listKey = m[1] as "provides" | "requires";
      if (m[2]) {
        current[listKey] = []; // explicit empty list, e.g. `requires: []`
        listKey = null;
      }
      continue;
    }
    m = line.match(/^\s+-\s+\{(.+)\}/);
    if (m && current && listKey) {
      const body = m[1];
      const item: ContractItem = { kind: "", path: "" };
      const from = body.match(/\bfrom:\s*(\d+)/);
      if (from) item.from = Number(from[1]);
      const kind = body.match(/\bkind:\s*([A-Za-z_]+)/);
      if (kind) item.kind = kind[1];
      const p = body.match(/\bpath:\s*"([^"]*)"/) ?? body.match(/\bpath:\s*([^,}]+)/);
      if (p) item.path = p[1].trim();
      const name = body.match(/\bname:\s*"([^"]*)"/) ?? body.match(/\bname:\s*([^,}]+)/);
      if (name) item.name = name[1].trim();
      current[listKey].push(item);
    }
  }

  const branchMatch = text.match(/Suggested branch:\s*([^\s|`]+)/);
  return {
    subtasks: Array.from(byId.values()).sort((a, b) => a.id - b.id),
    suggestedBranch: branchMatch ? branchMatch[1] : undefined,
  };
}

// ---------------------------------------------------------------------------
// Git helpers (live mode only — --dry-run never shells out to git)
// ---------------------------------------------------------------------------

function git(cwd: string, ...argv: string[]): string {
  return execFileSync("git", argv, { cwd, encoding: "utf8" }).trim();
}

function addWorktree(repoRoot: string, wtPath: string, subtaskId: number, featureBranch: string): string {
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
 */
function makeDryRunQuery(): QueryFn {
  const dir = fixtureDir();
  return async (kind, _prompt, schema, _opts) => {
    const file = kind === "worker" ? "worker-result.fixture.json" : "code-review-result.fixture.json";
    const raw = JSON.parse(fs.readFileSync(path.join(dir, file), "utf8"));
    const errors = validateAgainstSchema(raw, schema as never);
    if (errors.length > 0) {
      throw new Error(`dry-run fixture ${file} fails its schema: ${errors.join("; ")}`);
    }
    return raw;
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
    if (opts.effort) {
      // NEEDS VERIFICATION vs docs: `effort` is documented on AgentDefinition
      // (capability row 6, low..max); whether a top-level query() accepts it
      // directly is unverified — passed through defensively.
      options.effort = opts.effort;
    }

    let structured: unknown = null;
    let sawResult = false;
    for await (const msg of sdk.query({ prompt, options })) {
      if (!msg || msg["type"] !== "result") continue;
      sawResult = true;
      const subtype = String(msg["subtype"] ?? "");
      if (subtype === "error_max_structured_output_retries") {
        // FAIL CLOSED: the SDK exhausted its structured-output retries — never
        // fabricate or accept a schema-invalid result.
        throw new Error(
          `error_max_structured_output_retries: ${kind} query() could not produce schema-valid output — failing closed`
        );
      }
      if (subtype.startsWith("error")) {
        throw new Error(`${kind} query() returned an error result (subtype: ${subtype}) — failing closed`);
      }
      // NEEDS VERIFICATION vs docs: exact field name carrying the structured
      // payload on the final result message; both snake_case and camelCase are
      // probed, with a JSON-parse of the plain `result` text as last resort.
      structured =
        msg["structured_output"] ??
        msg["structuredOutput"] ??
        (typeof msg["result"] === "string" ? tryParseJson(msg["result"]) : null);
    }
    if (!sawResult || structured === null || structured === undefined) {
      throw new Error(`${kind} query() produced no structured result — failing closed`);
    }
    const errors = validateAgainstSchema(structured, schema as never);
    if (errors.length > 0) {
      throw new Error(`${kind} structured output failed local re-validation: ${errors.join("; ")} — failing closed`);
    }
    return structured;
  };
}

// ---------------------------------------------------------------------------
// Prompt builders (worker + reviewer)
// ---------------------------------------------------------------------------

function workerPrompt(subtask: Subtask, wtPath: string): string {
  const provides =
    subtask.provides.length > 0
      ? subtask.provides
          .map((p) => `- {kind: ${p.kind}, path: ${p.path}${p.name ? `, name: "${p.name}"` : ""}}`)
          .join("\n")
      : "(none listed)";
  return [
    `You are an implementation worker. Implement subtask ${subtask.id}: ${subtask.title}.`,
    `Work ONLY inside this directory (your git worktree): ${wtPath}`,
    `Do NOT run any git commit/branch/push operations.`,
    ``,
    `Promised outputs (provides) — verify each before finishing and report`,
    `them in outputs_verified; list anything missing in outputs_gap:`,
    provides,
    ``,
    `Report your result as a WORKER_RESULT object (schema_version 2).`,
  ].join("\n");
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

  const queryFn: QueryFn = args.dryRun ? makeDryRunQuery() : makeLiveQuery();

  const completed = new Map<number, SubtaskOutcome>();
  const failed = new Map<number, SubtaskOutcome>();
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
    try {
      // Step 2: worktree per launchable subtask (SKIPPED entirely in --dry-run)
      if (!args.dryRun) {
        wtPath = path.resolve(repoRoot, "..", `${repoName}-sdk-${subtask.id}`);
        branch = addWorktree(repoRoot, wtPath, subtask.id, featureBranch);
        record.wtPath = wtPath;
        record.branch = branch;
        record.created = true;
      }

      // Step 3: one worker query(), schema-forced to WORKER_RESULT v2
      const workerRaw = await queryFn("worker", workerPrompt(subtask, wtPath), WORKER_RESULT_SCHEMA, {
        cwd: args.dryRun ? undefined : wtPath,
        model: args.model,
        effort: args.effort,
      });
      const workerResult = { ...(workerRaw as WorkerResult), task_id: taskId };

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

      // Step 4 (per-completion): one reviewer query(), schema-forced to CODE_REVIEW_RESULT v3
      const reviewRaw = await queryFn("reviewer", reviewerPrompt(subtask, workerResult, wtPath), CODE_REVIEW_RESULT_SCHEMA, {
        cwd: args.dryRun ? undefined : wtPath,
        model: args.model,
        effort: args.effort,
      });
      const reviewResult = reviewRaw as CodeReviewResult;

      if (reviewResult.decision !== "PASS") {
        // Spike simplification: no fix-worker retry loop; FAIL/NEEDS_HUMAN = subtask failed.
        throw new Error(`review decision ${reviewResult.decision}: ${reviewResult.summary}`);
      }

      completed.set(subtask.id, { subtask, branch, wtPath, workerResult, reviewResult });
      mergeOrder.push(branch);
    } catch (err) {
      failed.set(subtask.id, { subtask, branch, wtPath, error: (err as Error).message });
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
    })),
    subtasks_failed: Array.from(failed.values()).map((o) => ({
      task_id: `subtask-${o.subtask.id}`,
      status: "failed" as const,
      error: o.error ?? "(unknown)",
      retry_count: 0,
    })),
    merge_order: mergeOrder,
    worktrees: worktrees.map((w) => ({
      task_id: w.taskId,
      path: w.wtPath,
      branch: w.branch,
      // Outcome first, so "failed"/"completed" stay meaningful in live mode
      // (where every created worktree is removed on exit): a failed subtask
      // reports "failed" even after its worktree was cleaned up.
      status: failed.has(Number(w.taskId.replace("subtask-", "")))
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

main()
  .then((code) => process.exit(code))
  .catch((err) => {
    console.error(`FATAL: ${(err as Error).message}`);
    process.exit(2);
  });
