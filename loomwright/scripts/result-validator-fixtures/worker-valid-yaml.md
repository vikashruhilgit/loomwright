Implemented the guard. Emitting the block in the docs/RESULT_SCHEMAS.md YAML shape.

```yaml
WORKER_RESULT:
  schema_version: 2
  task_id: add-jwt-guard
  status: partial
  files_modified: [src/auth/jwt.guard.ts]
  files_created: []
  outputs_verified:
    - kind: file
      path: src/auth/jwt.guard.ts
      status: present
    - kind: file
      path: src/auth/jwt.guard.spec.ts
      status: missing
  outputs_gap: "src/auth/jwt.guard.spec.ts"
  summary: Guard implemented but the spec file was deferred; status partial because outputs_gap names the missing spec.
```
