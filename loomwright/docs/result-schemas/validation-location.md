## Validation Location

Schema validation occurs in the **hook execution layer**:
- Per-agent `SubagentStop` hooks (in agent frontmatter) validate Worker and Execute Manager results
- Cross-cutting `SubagentStop` hooks (in `hooks.json`, the authoritative matcher list) validate the other result-emitting agents, Code Reviewer's results included
- Validation is never duplicated in Supervisor or plugin runtime
