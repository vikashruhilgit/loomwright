I implemented the guard and its unit tests, then verified the promised outputs.

## WORKER_RESULT
- schema_version: 2
- task_id: add-jwt-guard
- status: completed
- files_modified: [src/auth/auth.module.ts]
- files_created: [src/auth/jwt.guard.ts, src/auth/jwt.guard.spec.ts]
- files_deleted: none
- lines_added: 145
- lines_removed: 3
- tests_run: 8
- tests_passed: 8
- tests_failed: 0
- outputs_verified: [{kind: file, path: src/auth/jwt.guard.ts, status: present}, {kind: symbol, path: src/auth/jwt.guard.ts, name: JwtGuard, status: present}, {kind: file, path: src/auth/jwt.guard.spec.ts, status: present}]
- outputs_gap: ""
- error: none
- summary: Implemented JwtGuard with token validation and refresh support. Added unit tests covering valid, expired and malformed tokens.
