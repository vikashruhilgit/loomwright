---
name: self-heal-three-fixer-sites
description: Self-heal fix-worker prompts live at THREE sites that must stay in sync; review-heal drain loop is the one most prone to gate-omission drift
metadata:
  type: project
---

There are THREE self-heal fix-worker prompt sites that any "add an instruction/gate to the fixer" change must touch in sync:
1. `agents/supervisor.md` Phase 4.5 loop (~line 742-774) — the `Task(general-purpose)` fixer prompt + a `# ...gate` comment after the Task close + the FIX_RESULT.summary emit clause.
2. `skills/review-heal/SKILL.md` DEFAULT loop (~line 146-166).
3. `skills/review-heal/SKILL.md` DRAIN loop / `--until-mergeable` (~line 404-420).

**Why:** intent like "fixer must emit X and the loop must treat its absence as incomplete" needs BOTH an emit instruction (inside the `prompt: "..."` string) AND a co-located gate comment at EACH site. The DRAIN site is the recurring weak spot — edits tend to add the emit instruction to the drain prompt but leave the gate as only a forward cross-reference in the DEFAULT loop's comment ("Same gate applies in the drain loop") ~250 lines earlier, so the drain's emit->gate trace is weaker than the other two. Flag a missing co-located drain gate as MEDIUM (mechanism present via back-ref, but observability weaker).

**How to apply:** when reviewing any self-heal fixer-prompt change, grep all three sites and confirm each has emit + a LOCAL gate comment, not a back-reference. FIX_RESULT stays schema_version 1 / 5 fields (issues_addressed, files_modified, commit_sha, summary + schema_version) — observable notes ride in `summary`, never as a new field; RESULT_SCHEMAS.md must stay unchanged for such notes. See [[absolute-line-refs-drift-in-prose-edits]], [[agent-command-mirror-drift-on-fixes]].
