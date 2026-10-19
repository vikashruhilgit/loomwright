### Memory PR (delivery queue)

Accepted project-memory facts, LESSONS (including the writes a `Supersede` or `Retract` makes) and agent-memory promotions are written **in place** by their sole writers, on whatever branch you are standing on (Phase 4 above). Left there, they sit uncommitted until someone opens a pull request by hand. After every Phase 4 item has been answered, `/dreaming` may offer **ONE** pull request carrying exactly those writes. Declining it — or not being offered it — is the pre-existing behaviour: the writes stay where they are, uncommitted.

**Two branches, not one (decision).** The memory PR has its own branch, `dreaming/memory-<session_id>`, separate from `dreaming/rules-<session_id>`. The two sequences are shaped differently: the rules PR writes its files **on** the delivery branch (`add-rule.sh` runs after `git checkout -b`), while the memory PR commits writes that were **already made in place before any branch exists**. One shared branch would force one sequence into the other's shape. Separate branches also let a reviewer merge one PR without the other, and they leave the rules delivery sequence above in its own shape — the memory PR adds no step to it.

**What it carries, and what it does not.** It carries only the files in this run's **write record** (Step 1 below) that `git status` shows changed — never a whole prefix. Staging, committing and the pre-push verify all name those files explicitly, so anything outside the record is excluded by construction, not by assertion. It does **not** carry:

- `CLAUDE.md` — those edits remain **paste-to-apply** and reach the repo through a hand PR;
- `.agent/orientation/` promotions — that committed store is written in place by `add-orientation.sh` and is left uncommitted for a hand PR;
- the harness-memory pointer line (see "Harness-memory pointer" below) — its target is the harness's own memory index, whose exact path this command does not fix, so it could sit inside the agent-memory store. It is therefore recorded **separately**, as an excluded path, never as a writer output, is never staged, and is left out of the Step 0 snapshot. If its target is itself one of the recorded writer files, that file cannot be committed without the pointer line, so the memory PR is not offered (Step 1);
- `.agent/rules/` (the rules PR's job), or anything else in the working tree.

**Why the Pre-push confirmation is ONE question per run, not per item.** Memory Accepts write in place into **shared** files: `LESSONS.md`, `PROJECT_MEMORY.md`, the provenance JSONL files beside them (`.provenance.jsonl`, `.lessons-provenance.jsonl`), and each agent's `MEMORY.md` index, which `write-agent-memory.sh` regenerates on every write. Two accepted lessons land in the same `LESSONS.md`, and path staging takes a whole file or none of it, so "push lesson A but not lesson B" is not expressible without hunk-staging writer-owned files — which this command never does. The per-item gate therefore stays the **Accept** (what gets written), and the push gate is one per-run question over the whole changed set. (The rules PR can ask per item because a rule is authored on the delivery branch at delivery time: an unconfirmed rule is simply never written.)

**Step 0 — the dirt snapshot (before the first Phase 4 write).** Before `/dreaming` performs its first Phase 4 write of any kind, it records:

```bash
git status --porcelain --untracked-files=all -- .supervisor/memory .claude/agent-memory ':(exclude)<pointer target>'
```

`--untracked-files=all` is required, not cosmetic: a plain `git status` obeys the user's `status.showUntrackedFiles`, and with that set to `no` an untracked file left by an earlier run (a `LESSONS.md` from a declined push, say) prints nothing here — while Step 1's own `--untracked-files=all` would then put it in the changed set and commit the earlier run's content. The flag overrides that config, so both checks see the same files.

`<pointer target>` is the **harness-memory pointer's** file — the same path Step 1 puts on its **excluded** list: the harness memory index the pointer write (see "Harness-memory pointer" below) puts its line in, resolved here the same way that write resolves it, before anything is written. It is excluded because the pointer is never committed by design: if it sits inside the agent-memory store, an earlier run's pointer line stays uncommitted forever, and without the exclusion every later run would refuse here and never offer the memory PR again. Excluding it is safe because that file is never staged either way (and Step 1 refuses if it is also a recorded writer file). If the path cannot be resolved, leave the `:(exclude)` term out — the snapshot then sees more, never less, so it can only refuse more often. If it resolves **outside the repository** (a harness memory index under the user's home directory, say), leave the term out too: a file outside the repo can never appear in this snapshot, and git rejects such a pathspec outright (`fatal: … is outside repository`, exit 128), which would otherwise refuse the memory PR on every run.

A **non-zero exit** means the snapshot could not run, so nothing is known about the stores. The memory PR is then **not offered** this run, and the run report says `memory PR not offered: dirt snapshot could not run (exit <n>)` with git's message — a reason of its own, never reported as pre-existing changes. Fail-safe: the run refuses rather than guess.

Non-empty output means those stores already carried uncommitted changes `/dreaming` did not author. The memory PR is then **not offered** this run. Accepts still write in place exactly as before, nothing is staged, branched or pushed, and the run report says `memory PR not offered: pre-existing uncommitted changes under <stores>`, where `<stores>` names whichever of the two store prefixes had a listed path (one or both), and lists the paths. If a listed path is the harness-memory pointer's file (the exclusion was left out because its path could not be resolved), the message says so: `the harness-memory pointer's file <path> is uncommitted by design — commit it by hand, or remove the line, to have the memory PR offered again`. This matches the rules PR's `.agent/rules` refusal: a commit must never carry edits `/dreaming` did not author. The snapshot is taken once, at this point, because it is the only moment the distinction is knowable — after the first write the store is dirty either way.

**Step 1 — the write record (at Accept time) and the changed set (after every Accept, before asking).** The record is kept **as each write happens**, not reconstructed afterwards: by the time the push question is asked, a promoted agent-memory proposal file has already been deleted, so its frontmatter can no longer be read. For each **successful** (exit 0) sole-writer call in Phase 4, `/dreaming` appends to the run's write record the repo-relative files that call wrote:

- `write-project-memory.sh` ⇒ `.supervisor/memory/PROJECT_MEMORY.md` and `.supervisor/memory/.provenance.jsonl`;
- `write-lessons.sh` (incl. `supersede` / `retract`) ⇒ `.supervisor/memory/LESSONS.md` and `.supervisor/memory/.lessons-provenance.jsonl`;
- `write-agent-memory.sh --proposal` ⇒ `.claude/agent-memory/<agent>/<name>.md` and `.claude/agent-memory/<agent>/MEMORY.md`, with `<agent>` / `<name>` read from the proposal's `agent:` / `name:` frontmatter **before** the writer runs (cross-checked against the entry path in the writer's `wrote agent-memory entry <name> to <path>` success line).

A failed or refused call records nothing. When a LESSON Accept also writes the **harness-memory pointer**, its target path goes into a separate **excluded** list, never into the write record. Then, in this order:

1. **Ignored ⇒ refuse.** Run `git check-ignore -q -- <file>` on **every file in the write record**. Exit `0` means ignored. An ignored write is **invisible** to `git status --porcelain`, and a check on the prefix is not enough — a nested ignore on just the new entry leaves the prefix un-ignored while `git add` silently skips that one file, so the commit would carry the `MEMORY.md` index without the entry it points at. Common in user projects that ignore the harness's project directory without `/setup memory`'s negation. Any hit refuses the whole memory PR, naming the file and the reason (e.g. "`.claude/agent-memory/` is gitignored in this project — run `/setup memory` to add the negation, or commit it by hand"). Nothing is staged, branched or pushed.
2. **Pointer overlap ⇒ refuse.** If an excluded path (the pointer's target) is also in the write record, that file cannot be committed without the pointer line: refuse the whole memory PR, naming the file.
3. **Changed ⇒ in the set.** `git status --porcelain --untracked-files=all -- <recorded files>` lists the **changed set** — the recorded files that differ from HEAD (`--untracked-files=all` so a new entry file is listed by name, not as its directory). A recorded file the write left byte-identical to HEAD is not in it. Only recorded files are ever named in a pathspec, so a store this run did not write, an absent store, the pointer, and any other file under either prefix are never staged. A changed path under either prefix that is **not** in the record (the pointer, or a concurrent writer) is never staged and stays where it is, uncommitted; the unrecorded-changes re-scan below is the command that finds it for the run report.
4. **Stageable ⇒ proceed.** `git add --dry-run -- <changed files>` must exit `0` **and** list every changed file. It writes nothing. A non-zero exit or a missing file — for example a file under an ignored directory that is force-tracked, where a real `git add` would stage part of the set and then fail — refuses the whole memory PR, naming the file and git's message, before any branch exists.

An empty changed set ⇒ **nothing to offer**: ask nothing, and report "no memory PR: nothing changed".

**Unrecorded changes — the Step 0 snapshot command, re-run after the writes.** Once, after the last Phase 4 write and before the Pre-push question (whatever points 1–4 decided), `/dreaming` re-runs the Step 0 snapshot command exactly as Step 0 ran it — same stores, same `--untracked-files=all`, same `:(exclude)` decision for the pointer's file. Every path it lists that is not in the changed set is an **unrecorded change**: it is never staged, it is left in place, uncommitted, and the run report names it (`unrecorded changes left uncommitted: <paths>`). When the excluded list is non-empty and its path was excluded from the pathspec, the report names the pointer's file from that list instead (`<path>: the harness-memory pointer, uncommitted by design`). The re-scan is read-only and only informs the report: a **non-zero exit** reports `could not list unrecorded changes (exit <n>)` with git's message, and never refuses, blocks or widens the memory PR — nothing it lists ever enters a pathspec.

**Step 2 — the Pre-push confirmation (ONE question per run).** Asked once, after **every** Phase 4 item (memory Accepts and both rules gates alike) has been answered and before either delivery runs, so every push decision of the run is collected before any branch-creating, committing or pushing git command runs. The question lists the changed files and the accepted items they carry; header `Push`, options `Do not push` · `Push and open a PR`, in that order, **never recommended** (see "Approval Option Contract" below). **Default to NOT pushing. If the answer is ambiguous, treat it as no** — the same rule as the rules PR's gate 2. On no or ambiguous: no `git checkout -b`, no commit, no push and no `gh pr create` for memory; the accepted writes stay in place, uncommitted, and the run report says so.

**Step 3 — order when both PRs run.** The rules delivery sequence runs **first**, as written above; the memory delivery runs **after** it. The rules sequence stages and commits `.agent/rules` only, so the dirty memory files carry across its `git checkout -b` and back across its `git checkout -` untouched. If the rules delivery did not leave you on the branch you started on, the memory delivery does not run — report that instead.

**Delivery sequence (runs at the repo root, on the main thread, never from a worktree):**

1. **Pre-flight — the rules PR's own pre-flight, reused; every check aborts cleanly before any branch exists.** The current branch is recorded so it can be restored; `gh` must be authenticated (`gh auth status`); and HEAD must already be contained in the base branch, resolved here and never assumed to be `main`:

   ```bash
   BASE="$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)"   # empty/failed ⇒ abort
   git fetch --quiet origin "$BASE" || true                                   # freshness; failure is tolerated
   git merge-base --is-ancestor HEAD "origin/$BASE"                           # non-zero ⇒ abort delivery
   ```

   The reasons are the rules pre-flight's, unchanged: a PR presents the branch-versus-base diff, not the commit; a stale `origin/$BASE` can only make the test stricter; abort rather than silently branching from `origin/$BASE`. Then the delivery branch must not exist yet. **Slug `<session_id>` to `[A-Za-z0-9._-]` in every `dreaming/memory-<session_id>` branch name below** (anything else becomes `-`), as the rules step 2 does; the commit message and PR title keep `<session_id>` as-is:

   ```bash
   git show-ref --verify --quiet "refs/heads/dreaming/memory-<session_id>"    # exit 0 ⇒ exists locally ⇒ abort
   git ls-remote --exit-code --heads origin "dreaming/memory-<session_id>"    # exit 0 ⇒ exists remotely ⇒ abort; any exit but 2 ⇒ abort
   ```

   `ls-remote --exit-code` exits `2` only when no such ref exists; any other non-zero exit is "could not tell" and aborts too. `/dreaming` never force-creates, never resets, and never force-pushes. Nothing has changed at this point: an abort leaves no branch and no commit, and the accepted writes stay in place, uncommitted.
2. `git checkout -b dreaming/memory-<session_id>` from the **current HEAD**. The dirty memory files carry across unchanged — they are what this branch will commit.
3. `git add -- <changed files>` — **explicitly scoped to the changed set from Step 1, file by file, never a prefix, never `git add -A` or `git add .`**.
4. `git commit -m 'dreaming: curated memory from session <session_id>' -- <changed files>` — **pathspec-limited**, so an entry you had already staged elsewhere stays staged and stays out of this commit.
5. **Verify before any push:** the set of paths `git show --name-only --format= HEAD` lists must **equal** the changed set — no stray path (something outside the record rode along) and no missing one (a recorded write was silently not committed). Either mismatch ⇒ abort before the push: `git checkout -` to restore the original branch, **keep** the local branch (it carries the commit, for inspection), report the stray or missing paths, and push nothing.
6. `git push -u origin dreaming/memory-<session_id>`, then open the PR against the **`$BASE` resolved and tested in step 1**:

   ```bash
   gh pr create --base "$BASE" --head dreaming/memory-<session_id> \
     --title 'dreaming: curated memory from session <session_id>' \
     --body '<the accepted items, one line each, grouped by store, plus the changed files>'
   ```

   `--title` and `--body` are part of the literal for the same reason as in the rules step 5 (non-interactively `gh pr create` errors without them, after the push). Pass both as literal argv values, or use `--body-file <path>`.
7. `git checkout -` to restore the branch you started on.
8. Report the PR URL in the run report. **`/dreaming` never merges the PR it opens** — it runs no merge verb of any kind, and the plugin's single sanctioned merge executor is unchanged by this command. Opening the PR is terminal for `/dreaming`; a human reviews and merges.

**Your working tree after delivery.** The accepted writes now live on `dreaming/memory-<session_id>`. Once `git checkout -` returns you to the original branch, `LESSONS.md`, `PROJECT_MEMORY.md` and the agent-memory files **read the original branch's content again**, and newly created agent-memory entry files are absent. They return when the PR merges and you pull. This is expected, not lost work. Do not "fix" it by skipping the checkout — that would leave you standing on the delivery branch. Until then, readers on the original branch (`read-lessons.sh`, Supervisor Phase 1 ACQUIRE) do not see the accepted items, and the run report says so.

**If a step fails, restore the original branch before reporting, then say what state it left behind rather than retrying** — the rules sequence's rule, applied here. Run step 7's `git checkout -` on the failure path too. A failure at step 3 or 4 leaves no commit: restore the original branch (the memory writes come back with you, still uncommitted — staged, if step 3 ran), delete the now-empty local branch, and report. A step-5 verification failure is handled as described in step 5. A failed push leaves a *local* branch only — report its name. A failed `gh pr create` after a successful push leaves a *pushed* branch with no PR — report the branch name so the PR can be opened by hand. `/dreaming` does not retry, does not force, and does not delete a branch that carries commits.

