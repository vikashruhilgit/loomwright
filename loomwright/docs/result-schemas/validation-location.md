## Validation Location

Schema validation occurs in the **hook execution layer**:
- Per-agent `SubagentStop` hooks (in agent frontmatter) validate Worker and Execute Manager results
- Cross-cutting `SubagentStop` hooks (in `hooks.json`) validate Code Reviewer and QA Executor results
- Validation is never duplicated in Supervisor or plugin runtime
- The `SubagentStop (qa-executor)` command hook — `scripts/validate-qa-result.py` — validates a `QA_RESULT` block (default mode) OR a `VERIFY_RESULT` block (`--verify` mode; §VERIFY_RESULT), `QA_RESULT` winning whenever both are present; one hook command, two block schemas
