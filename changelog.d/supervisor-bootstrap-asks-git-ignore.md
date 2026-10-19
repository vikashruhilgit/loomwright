<!-- bump: patch -->
The Supervisor bootstrap no longer appends `.supervisor/` to a `/setup memory` .gitignore
Phase 0 step 4 of `scripts/supervisor-next-step.sh` used to test `.gitignore` for the exact line `.supervisor/`.
`/setup memory`'s managed block ignores the directory's contents (`.supervisor/*` plus `!.supervisor/memory/`) and
has no bare line, so every run appended one. That line re-ignored `.supervisor/memory/` and left the tracked
`.gitignore` dirty, which blocked closeout's main sync and `lane-remove` (#615). Step 4 now asks git:
`git check-ignore -q --no-index` on `.supervisor/state.md` and `.supervisor/logs/x.json`. When both are ignored
it writes nothing. When either is not, it appends the bare line on its own line. Outside a repo or without git it
falls back to the exact-line test. The prose that prescribed a bare line now says `.supervisor/` must stay ignored
(a bare line, or `/setup memory`'s managed block), and the `state-management` snippet mirrors the probe. New test
leg B18 runs two real inits over the managed block, with a mutation control.
