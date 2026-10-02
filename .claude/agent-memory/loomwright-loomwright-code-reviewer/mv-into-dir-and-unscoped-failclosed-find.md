---
name: mv-into-dir-and-unscoped-failclosed-find
title: mv-into-dir-and-unscoped-failclosed-find
description: Two sync-script miss-classes. (1) `mv -f tmp dst` where dst is an existing directory moves INTO it and reports success, so a 3-way sync records agreement it never reached and the next push deletes the sibling's file. (2) A fail-closed `find` over a whole state dir fails on unrelated churn (worktrees), blocking legitimate syncs.
metadata:
  type: project
source: PR #334 meta-sync.sh Phase 4.5 iteration-3 review, 2026-10-02 (scratch repros: dir.md directory at a managed path; 3/10 pushes refused under .supervisor/worktrees churn)
written_at: 2026-10-02T07:21:37Z
head_sha: c594e83
---

When reviewing a sync or atomic-replace script, run two repros. First, put a DIRECTORY at the destination path of a `mv -f tmp dst` and check whether the "write" quietly lands inside it. Second, churn files in an unmanaged sibling subtree while the fail-closed enumeration runs. BSD find exits 1 on a vanishing entry (`No such file or directory`).
**Why:** both looked correct statically, and only the scratch repro surfaced them. The first caused a silent deletion on the branch. The second made a parallel-automate lane fail whenever a worker was building.
**How to apply:** scope fail-closed enumeration to the managed roots only. Refuse when a managed destination exists as a directory.
