/**
 * schemas.ts — JSON Schemas for schema-forced structured outputs.
 *
 * QUARANTINED SPIKE (loomwright/sdk-spike/). Field shapes are derived from
 * loomwright/docs/RESULT_SCHEMAS.md:
 *   - WORKER_RESULT       schema_version 2  (§WORKER_RESULT)
 *   - CODE_REVIEW_RESULT  schema_version 3  (§CODE_REVIEW_RESULT)
 *   - EXECUTE_RESULT      schema_version 1  (§EXECUTE_RESULT) — emitted by the
 *     runner itself as an "EXECUTE_RESULT-equivalent" JSON block, NOT forced
 *     onto a model, so it is expressed as a TypeScript type rather than a
 *     JSON Schema.
 *
 * Schemas are intentionally NON-RECURSIVE (no $ref cycles) per the SDK's
 * structured-output limits (capability matrix row 2 in the brief;
 * https://code.claude.com/docs/en/agent-sdk/structured-outputs.md).
 *
 * `schema_version` is expressed as a single-value enum rather than `const`
 * to stay inside the most conservative JSON Schema subset.
 * // NEEDS VERIFICATION vs docs: whether the SDK's json_schema subset accepts
 * // `const`; single-value `enum` is equivalent and safer.
 *
 * STRICT-MODE POSTURE: every declared property is listed in `required`, with
 * previously-optional fields made nullable (`"type": ["string","null"]`, enums
 * including null, arrays default-able to []). Several structured-output
 * backends (OpenAI strict mode canonically) reject `additionalProperties:
 * false` combined with properties absent from `required`; whether the Agent
 * SDK enforces the same is a NEEDS VERIFICATION item in
 * docs/SPIKES/SDK_RUNNER_SPIKE.md — this shape is valid either way.
 */

// ---------------------------------------------------------------------------
// WORKER_RESULT (schema_version 2)
// Mandatory keys per docs/RESULT_SCHEMAS.md §WORKER_RESULT validation rules:
// schema_version, task_id, status, files_modified, outputs_verified,
// outputs_gap, summary. `error` is conditionally required (status=failed) —
// JSON Schema conditionals are avoided to keep the schema simple/subset-safe;
// the runner re-checks that invariant in code. Per the strict-mode posture
// above, ALL declared properties are in `required`; docs-optional ones are
// nullable / default-[] instead of absent.
// ---------------------------------------------------------------------------
export const WORKER_RESULT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: [
    "schema_version",
    "task_id",
    "status",
    "files_modified",
    "files_created",
    "tests_added",
    "tests_passed",
    "outputs_verified",
    "outputs_gap",
    "memory_candidates",
    "summary",
    "error",
  ],
  properties: {
    schema_version: { type: "integer", enum: [2] },
    task_id: { type: "string", minLength: 1 },
    status: { type: "string", enum: ["completed", "failed", "partial"] },
    files_modified: { type: "array", items: { type: "string" } },
    files_created: { type: "array", items: { type: "string" } },
    tests_added: { type: "array", items: { type: "string" } },
    tests_passed: { type: ["boolean", "null"] },
    outputs_verified: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["kind", "path", "name", "status"],
        properties: {
          kind: { type: "string", enum: ["file", "symbol", "type"] },
          path: { type: "string" },
          name: { type: ["string", "null"] },
          status: { type: "string", enum: ["present", "missing"] },
        },
      },
    },
    outputs_gap: { type: "string" },
    memory_candidates: { type: "array", items: { type: "string" } },
    summary: { type: "string" },
    error: { type: ["string", "null"] },
  },
} as const;

// ---------------------------------------------------------------------------
// CODE_REVIEW_RESULT (schema_version 3)
// Required keys mirror docs/RESULT_SCHEMAS.md §CODE_REVIEW_RESULT v3 rules.
// Cross-field invariants (trigger_paths_detected non-empty ⇒ consistency_audit;
// FAIL requires a new/drift BLOCKING|HIGH issue; drift_kind severity caps) are
// not expressible in the plain subset — the runner treats them as advisory and
// re-checks the FAIL invariant in code where it matters.
// ---------------------------------------------------------------------------
export const CODE_REVIEW_RESULT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: [
    "schema_version",
    "review_mode",
    "audit_focus",
    "trigger_paths_detected",
    "scope_expanded",
    "files_checked",
    "consistency_checks",
    "consistency_summary",
    "decision",
    "issues",
    "pattern_proposals",
    "knowledge_sources_used",
    "summary",
  ],
  properties: {
    schema_version: { type: "integer", enum: [3] },
    review_mode: { type: "string", enum: ["diff_review", "consistency_audit"] },
    audit_focus: {
      type: "array",
      items: {
        type: "string",
        enum: ["mirrored_prompt", "metadata", "counts", "docs", "hooks", "plan_prompt"],
      },
    },
    trigger_paths_detected: { type: "array", items: { type: "string" } },
    scope_expanded: { type: "array", items: { type: "string" } },
    files_checked: { type: "array", items: { type: "string" }, minItems: 1 },
    consistency_checks: {
      type: ["object", "null"],
      additionalProperties: false,
      required: [
        "mirrored_prompts",
        "version_strings",
        "counts",
        "workflow_alignment",
        "hooks_parity",
      ],
      properties: {
        mirrored_prompts: { type: "string", enum: ["pass", "fail", "not_applicable"] },
        version_strings: { type: "string", enum: ["pass", "fail", "not_applicable"] },
        counts: { type: "string", enum: ["pass", "fail", "not_applicable"] },
        workflow_alignment: { type: "string", enum: ["pass", "fail", "not_applicable"] },
        hooks_parity: { type: "string", enum: ["pass", "fail", "not_applicable"] },
      },
    },
    consistency_summary: { type: ["string", "null"] },
    decision: { type: "string", enum: ["PASS", "FAIL", "NEEDS_HUMAN"] },
    issues: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: [
          "severity",
          "category",
          "drift_kind",
          "file",
          "line",
          "description",
          "suggestion",
        ],
        properties: {
          severity: { type: "string", enum: ["BLOCKING", "HIGH", "MEDIUM", "LOW"] },
          category: { type: "string", enum: ["new", "pre_existing", "nit", "drift"] },
          drift_kind: {
            type: ["string", "null"],
            enum: [
              "version_authoritative",
              "version_secondary",
              "mirrored_prompt",
              "count",
              "workflow",
              "hooks_parity",
              "wording",
              null,
            ],
          },
          file: { type: "string" },
          line: { type: ["integer", "null"] },
          description: { type: "string" },
          suggestion: { type: ["string", "null"] },
        },
      },
    },
    pattern_proposals: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["pattern", "file", "description"],
        properties: {
          pattern: { type: "string" },
          file: { type: "string" },
          description: { type: "string" },
        },
      },
    },
    knowledge_sources_used: { type: "array", items: { type: "string" } },
    summary: { type: "string" },
  },
} as const;

// ---------------------------------------------------------------------------
// TypeScript views of the payloads (loose — the JSON Schemas above are the
// enforcement surface; these types are for runner-internal plumbing).
// ---------------------------------------------------------------------------
export interface WorkerResult {
  schema_version: number;
  task_id: string;
  status: "completed" | "failed" | "partial";
  files_modified: string[];
  files_created?: string[] | null;
  tests_added?: string[] | null;
  tests_passed?: boolean | null;
  outputs_verified: Array<{
    kind: "file" | "symbol" | "type";
    path: string;
    name?: string | null;
    status: "present" | "missing";
  }>;
  outputs_gap: string;
  memory_candidates?: string[] | null;
  summary: string;
  error?: string | null;
}

export interface CodeReviewResult {
  schema_version: number;
  review_mode: "diff_review" | "consistency_audit";
  audit_focus: string[];
  trigger_paths_detected: string[];
  scope_expanded: string[];
  files_checked: string[];
  consistency_checks?: Record<string, string> | null;
  consistency_summary?: string | null;
  decision: "PASS" | "FAIL" | "NEEDS_HUMAN";
  issues: Array<{
    severity: "BLOCKING" | "HIGH" | "MEDIUM" | "LOW";
    category: "new" | "pre_existing" | "nit" | "drift";
    drift_kind?: string | null;
    file: string;
    line?: number | null;
    description: string;
    suggestion?: string | null;
  }>;
  pattern_proposals?: Array<{ pattern: string; file: string; description: string }> | null;
  knowledge_sources_used?: string[] | null;
  summary: string;
}

// ---------------------------------------------------------------------------
// Per-subtask token accounting (ADDITIVE — token-levers job).
// Captured from each query()'s terminal result message (SDKResultSuccess,
// sdk.d.ts:4024: `usage` / `total_cost_usd` / `num_turns` at :4037-4042).
// In --dry-run the fixtures carry no real usage, so the runner emits zeros
// with `proxy: true` — mirroring the plugin's token-ledger convention
// (never invent token counts; label synthetic numbers as proxy).
// ---------------------------------------------------------------------------
export interface RoleTokenUsage {
  input_tokens: number;
  output_tokens: number;
  cache_creation_input_tokens: number;
  cache_read_input_tokens: number;
  total_cost_usd: number;
  num_turns: number;
}

export interface SubtaskTokenUsage {
  /** null when the role's query never ran (e.g. worker failed before review) */
  worker: RoleTokenUsage | null;
  reviewer: RoleTokenUsage | null;
  /** sum of input+output+cache_creation+cache_read across both roles */
  total_tokens: number;
  total_cost_usd: number;
  /** true when the numbers are synthesized (dry-run), false when read from real result messages */
  proxy: boolean;
}

// ---------------------------------------------------------------------------
// EXECUTE_RESULT-equivalent — the block the runner prints to stdout.
// Field names and shapes mirror docs/RESULT_SCHEMAS.md §EXECUTE_RESULT
// (schema_version 1). The extra `mode` field is spike-local telemetry
// ("live" | "dry-run"); the block is NOT hook-validated (this is a spike,
// not the plugin runtime path), so the additive fields (`mode`,
// `token_usage`) are safe.
// ---------------------------------------------------------------------------
export interface ExecuteResultEquivalent {
  schema_version: 1;
  mode: "live" | "dry-run";
  subtasks_completed: Array<{
    task_id: string;
    status: "completed";
    branch: string;
    files_modified: string[];
    review_decision: string;
    /** ADDITIVE per-subtask token accounting (worker + reviewer queries) */
    token_usage: SubtaskTokenUsage;
  }>;
  subtasks_failed: Array<{
    task_id: string;
    status: "failed";
    error: string;
    retry_count: number;
    /** ADDITIVE — present where available; null when no query ran (e.g. blocked-forever) */
    token_usage: SubtaskTokenUsage | null;
  }>;
  merge_order: string[];
  worktrees: Array<{
    task_id: string;
    path: string;
    branch: string;
    status: "completed" | "failed" | "cleaned";
  }>;
  branches: string[];
  summary: string;
}

// ---------------------------------------------------------------------------
// Minimal local validator — enforces what the schemas above declare:
// required keys, enums, array-ness, `minItems` on arrays, `minLength` on
// strings, ONE level of recursion into array items (object items validated
// against `items`'s required/properties; scalar items checked against
// `items.enum`/type), and recursion into non-array OBJECT properties that
// carry their own required/properties (e.g. consistency_checks — null is
// accepted where the type union permits it).
// Used (a) to validate dry-run fixtures deterministically offline and
// (b) as a fail-closed double-check on live structured outputs (the SDK
// already retries/errors on schema violations; this is belt-and-suspenders).
// Deliberately NOT a full JSON Schema implementation (no deps in the spike).
// Still deliberately NON-enforced: `additionalProperties: false` (unknown
// keys are ignored, not rejected), type checks on nullable union types
// (`["boolean","null"]` etc. — enums still apply, but a wrong-typed value
// with no enum passes), and any keyword not listed above.
// ---------------------------------------------------------------------------
export function validateAgainstSchema(
  obj: unknown,
  schema: { required?: readonly string[]; properties?: Record<string, any> },
  keyPrefix = ""
): string[] {
  const errors: string[] = [];
  if (obj === null || typeof obj !== "object" || Array.isArray(obj)) {
    return [`${keyPrefix || "payload"} is not a JSON object`];
  }
  const record = obj as Record<string, unknown>;
  for (const key of schema.required ?? []) {
    if (!(key in record)) errors.push(`missing required key: ${keyPrefix}${key}`);
  }
  for (const [key, prop] of Object.entries(schema.properties ?? {})) {
    if (!(key in record)) continue;
    const value = record[key];
    const label = `${keyPrefix}${key}`;
    if (prop.type === "array") {
      if (!Array.isArray(value)) {
        errors.push(`key ${label} must be an array`);
      } else if (typeof prop.minItems === "number" && value.length < prop.minItems) {
        errors.push(`key ${label} must have at least ${prop.minItems} item(s), got ${value.length}`);
      }
      if (Array.isArray(value) && prop.items) {
        // One level of item recursion (our schemas are non-recursive, so this
        // covers outputs_verified[], issues[], etc. completely).
        (value as unknown[]).forEach((el, i) => {
          if (prop.items.type === "object") {
            errors.push(...validateAgainstSchema(el, prop.items, `${label}[${i}].`));
          } else if (prop.items.type === "string" && typeof el !== "string") {
            errors.push(`key ${label}[${i}] must be a string`);
          } else if (
            Array.isArray(prop.items.enum) &&
            (typeof el === "string" || typeof el === "number") &&
            !prop.items.enum.includes(el as never)
          ) {
            errors.push(`key ${label}[${i}] value ${JSON.stringify(el)} not in enum ${JSON.stringify(prop.items.enum)}`);
          }
        });
      }
    }
    if (prop.type === "string" && typeof value !== "string") {
      errors.push(`key ${label} must be a string`);
    }
    if (
      typeof prop.minLength === "number" &&
      typeof value === "string" &&
      value.length < prop.minLength
    ) {
      errors.push(`key ${label} must have length >= ${prop.minLength}`);
    }
    if (prop.type === "integer" && typeof value !== "number") {
      errors.push(`key ${label} must be a number`);
    }
    // Recurse into non-array OBJECT properties that declare their own shape
    // (e.g. consistency_checks). Applies when the declared type is/includes
    // "object" and the value is a non-null object; null is left to the type
    // union (["object","null"]).
    const typeIncludesObject =
      prop.type === "object" || (Array.isArray(prop.type) && prop.type.includes("object"));
    if (
      typeIncludesObject &&
      (prop.required || prop.properties) &&
      value !== null &&
      typeof value === "object" &&
      !Array.isArray(value)
    ) {
      errors.push(...validateAgainstSchema(value, prop, `${label}.`));
    }
    if (Array.isArray(prop.enum) && (typeof value === "string" || typeof value === "number")) {
      if (!prop.enum.includes(value as never)) {
        errors.push(`key ${label} value ${JSON.stringify(value)} not in enum ${JSON.stringify(prop.enum)}`);
      }
    }
  }
  return errors;
}
