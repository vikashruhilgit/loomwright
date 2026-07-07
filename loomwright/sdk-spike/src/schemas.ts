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
 */

// ---------------------------------------------------------------------------
// WORKER_RESULT (schema_version 2)
// Required keys mirror docs/RESULT_SCHEMAS.md §WORKER_RESULT validation rules:
// schema_version, task_id, status, files_modified, outputs_verified,
// outputs_gap, summary. `error` is conditionally required (status=failed) —
// JSON Schema conditionals are avoided to keep the schema simple/subset-safe;
// the runner re-checks that invariant in code.
// ---------------------------------------------------------------------------
export const WORKER_RESULT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: [
    "schema_version",
    "task_id",
    "status",
    "files_modified",
    "outputs_verified",
    "outputs_gap",
    "summary",
  ],
  properties: {
    schema_version: { type: "integer", enum: [2] },
    task_id: { type: "string", minLength: 1 },
    status: { type: "string", enum: ["completed", "failed", "partial"] },
    files_modified: { type: "array", items: { type: "string" } },
    files_created: { type: "array", items: { type: "string" } },
    tests_added: { type: "array", items: { type: "string" } },
    tests_passed: { type: "boolean" },
    outputs_verified: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["kind", "path", "status"],
        properties: {
          kind: { type: "string", enum: ["file", "symbol", "type"] },
          path: { type: "string" },
          name: { type: "string" },
          status: { type: "string", enum: ["present", "missing"] },
        },
      },
    },
    outputs_gap: { type: "string" },
    memory_candidates: { type: "array", items: { type: "string" } },
    summary: { type: "string" },
    error: { type: "string" },
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
    "decision",
    "issues",
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
      type: "object",
      additionalProperties: false,
      properties: {
        mirrored_prompts: { type: "string", enum: ["pass", "fail", "not_applicable"] },
        version_strings: { type: "string", enum: ["pass", "fail", "not_applicable"] },
        counts: { type: "string", enum: ["pass", "fail", "not_applicable"] },
        workflow_alignment: { type: "string", enum: ["pass", "fail", "not_applicable"] },
        hooks_parity: { type: "string", enum: ["pass", "fail", "not_applicable"] },
      },
    },
    consistency_summary: { type: "string" },
    decision: { type: "string", enum: ["PASS", "FAIL", "NEEDS_HUMAN"] },
    issues: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["severity", "category", "file", "description"],
        properties: {
          severity: { type: "string", enum: ["BLOCKING", "HIGH", "MEDIUM", "LOW"] },
          category: { type: "string", enum: ["new", "pre_existing", "nit", "drift"] },
          drift_kind: {
            type: "string",
            enum: [
              "version_authoritative",
              "version_secondary",
              "mirrored_prompt",
              "count",
              "workflow",
              "hooks_parity",
              "wording",
            ],
          },
          file: { type: "string" },
          line: { type: "integer" },
          description: { type: "string" },
          suggestion: { type: "string" },
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
  files_created?: string[];
  tests_added?: string[];
  tests_passed?: boolean;
  outputs_verified: Array<{
    kind: "file" | "symbol" | "type";
    path: string;
    name?: string;
    status: "present" | "missing";
  }>;
  outputs_gap: string;
  memory_candidates?: string[];
  summary: string;
  error?: string;
}

export interface CodeReviewResult {
  schema_version: number;
  review_mode: "diff_review" | "consistency_audit";
  audit_focus: string[];
  trigger_paths_detected: string[];
  scope_expanded: string[];
  files_checked: string[];
  consistency_checks?: Record<string, string>;
  consistency_summary?: string;
  decision: "PASS" | "FAIL" | "NEEDS_HUMAN";
  issues: Array<{
    severity: "BLOCKING" | "HIGH" | "MEDIUM" | "LOW";
    category: "new" | "pre_existing" | "nit" | "drift";
    drift_kind?: string;
    file: string;
    line?: number;
    description: string;
    suggestion?: string;
  }>;
  pattern_proposals?: Array<{ pattern: string; file: string; description: string }>;
  knowledge_sources_used?: string[];
  summary: string;
}

// ---------------------------------------------------------------------------
// EXECUTE_RESULT-equivalent — the block the runner prints to stdout.
// Field names and shapes mirror docs/RESULT_SCHEMAS.md §EXECUTE_RESULT
// (schema_version 1). The extra `mode` field is spike-local telemetry
// ("live" | "dry-run"); the block is NOT hook-validated (this is a spike,
// not the plugin runtime path), so the additive field is safe.
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
  }>;
  subtasks_failed: Array<{
    task_id: string;
    status: "failed";
    error: string;
    retry_count: number;
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
// Minimal local validator — required keys, enums, array-ness, plus ONE level
// of recursion into array items (object items validated against `items`'s
// required/properties; scalar items checked against `items.enum`/type).
// Used (a) to validate dry-run fixtures deterministically offline and
// (b) as a fail-closed double-check on live structured outputs (the SDK
// already retries/errors on schema violations; this is belt-and-suspenders).
// Deliberately NOT a full JSON Schema implementation (no deps in the spike).
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
      } else if (prop.items) {
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
    if (prop.type === "integer" && typeof value !== "number") {
      errors.push(`key ${label} must be a number`);
    }
    if (Array.isArray(prop.enum) && (typeof value === "string" || typeof value === "number")) {
      if (!prop.enum.includes(value as never)) {
        errors.push(`key ${label} value ${JSON.stringify(value)} not in enum ${JSON.stringify(prop.enum)}`);
      }
    }
  }
  return errors;
}
