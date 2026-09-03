---
name: loomwright:alpha
description: SYNTHETIC fixture agent for test-build-floor.sh. Not a real agent, never distributed, never spawned. Deliberately not a copy of any file under loomwright/agents/ - a copy would re-key this fixture every time the real agent it mirrored was edited.
tools: Read, Glob, Grep
model: sonnet
maxTurns: 12
color: "#1E90FF"
disallowedTools: Write, Edit, NotebookEdit
---

# Alpha (fixture)

The READ-ONLY row: `disallowedTools` covers BOTH `Write` and `Edit`, so the projector's
`read_only` derivation must be true. The extra `NotebookEdit` token is deliberate - it is
the whole-token trap in the other direction (a naive `*Edit*` substring test cannot tell
this row apart from beta's).

Nothing reads this body. Only the frontmatter between the first two `---` lines is parsed.
