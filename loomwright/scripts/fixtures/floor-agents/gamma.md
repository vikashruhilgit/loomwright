---
name: loomwright:gamma
description: SYNTHETIC fixture agent for test-build-floor.sh. Not a real agent. Carries neither maxTurns: nor disallowedTools:.
model: haiku
color: forestgreen
---

# Gamma (fixture)

The two-omissions row: no `maxTurns:` and no `disallowedTools:`.

`max_turns` is omitted because the frontmatter does not state one. `read_only` is omitted
for the same reason and NOT emitted as `false`: "this file lists no disallowed tools" is a
statement about the file, and the projector reports what it read rather than what it
would guess. `color:` here is an unquoted CSS name, so the quote-stripping in the parser
is exercised in both directions across the three rows.
