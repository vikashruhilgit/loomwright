<!-- bump: minor -->
meta-sync carries the learning stores (twin pair rule, per-file merge, consent before first publish)
`meta-sync.sh`'s managed set now also holds the learning stores: the System Twin contracts plus
`.supervisor/twin/.provenance.jsonl`, `.supervisor/agent-memory-proposals/*.md` and the two eval JSONL
files (`.supervisor/worker-summaries/` stays unmanaged until its files get unique names). The twin set
syncs as a whole: a contract without a chain-valid `add` entry (the same chain rules
`read-system-contract.sh` applies) or a provenance fork refuses the twin set on the side being written,
named on stderr as `meta_sync: twin_refused <path>: <reason>`, while run history still syncs, the exit
code stays the one run history gives, and `meta-base` keeps every twin path's previous entry so the
next sync re-refuses instead of deleting the other side's contracts. The eval files line-union like the
postmortem ledger (the union is now a predicate over the union paths), and a `.dismissed-decisions`
ledger merges in timestamp order so the newer decision wins. A push publishes a learning-store path
only with this repo's user-scope consent: one record under `~/.claude/loomwright/`, keyed by origin,
written only by the new `setup-memory.sh consent grant | decline | status` and asked once by
`/setup memory` in branch mode; without it each path is named `learning_skipped` and run history still
pushes. `status`'s first line counts run history only (`lane-remove` is unchanged) and the opt-in
`status --learning` reports the learning stores; `list-managed` gains `--run-history` and `--tree`, which
the rehearsal and `migrate-branch-mode.sh` (A/B check, branch-kind check, rollback re-track) now use.
`trail-pr` and the lanes do not carry the learning stores (a follow-up). Owner follow-up: the
branch-only M1 operator-run file still states the old managed set and must be updated on the metadata
branch by hand (`meta-sync.sh push`).
