---
name: case-glob-dotdot-and-shared-index
title: case-glob-dotdot-and-shared-index
description: Path predicates written as bash `case` globs (`dir/*.md`) accept `..` segments because `*` matches `/`; and a fixed-name GIT_INDEX_FILE in a shared gitdir removed by an EXIT trap lets one invocation empty another's index mid-push
metadata:
  type: project
source: Phase 4.5 review of PR #334 (meta-sync.sh), 2026-10-02 — both reproduced in scratch: a `..` tree entry on the meta branch made `pull` overwrite tracked CLAUDE.md; a concurrent `status` on the same default root made `push` publish a 1-file tree (4 files deleted, propagated to a sibling clone)
written_at: 2026-10-02T07:21:34Z
head_sha: c594e83
---

Path predicates written as bash `case` globs (`dir/*.md`) accept `..` segments because `*` matches `/`; and a fixed-name GIT_INDEX_FILE in a shared gitdir removed by an EXIT trap lets one invocation empty another's index mid-push

**Evidence / how to apply:** Phase 4.5 review of PR #334 (meta-sync.sh), 2026-10-02 — both reproduced in scratch: a `..` tree entry on the meta branch made `pull` overwrite tracked CLAUDE.md; a concurrent `status` on the same default root made `push` publish a 1-file tree (4 files deleted, propagated to a sibling clone)
