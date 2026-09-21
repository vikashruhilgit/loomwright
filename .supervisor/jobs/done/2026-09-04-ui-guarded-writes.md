# Supervisor Job: The floor acts — guarded writes from the page

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — its "Latest change" banner describes item 06, the immediate predecessor)
- **Git:** clean except one engine artefact (` M .supervisor/postmortem/results.jsonl`), HEAD detached at `c5f4e46` = `origin/main`
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 3 (see Risk Assessment R6, R7, R11; the seven breaking-gate risks R1/R2/R9/R10/R12/R13/R14 are CAUTION findings, not environment warnings)
- **Source requirement:** `.supervisor/requirements/loom-floor-ui/07-ui-guarded-writes.md`

> **Base-branch note (read before Phase 1 ACQUIRE).** The checkout is DETACHED at `origin/main`
> on purpose. Local `main` is checked out by a *live* sibling worktree
> (`.claude/worktrees/nice-engelbart-44b362`, clean, touched minutes ago by another session), so
> **`git checkout main` will fail here** with *"'main' is already used by worktree at …"*. Create
> the feature branch from the current detached HEAD (`git checkout -b <branch>`), which already
> *is* fresh `origin/main`; do **not** try to check out or fast-forward local `main`, and do not
> remove that worktree — it is not this run's to delete. Open the PR with `--base main` as usual.

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | `python3 --version` = 3.9.6 on this machine; `ThreadingHTTPServer` + `BaseHTTPRequestHandler` are stdlib from 3.7. The engine is bash 3.2 + BSD userland (macOS), which the module already targets. |
| 2 | Dependency Availability | GO | Zero new dependencies. The requirement forbids Node/npm/CDN and nothing in the design needs them. `jq` is already an optional-with-honest-degradation dependency of the registry path and that posture is unchanged. |
| 3 | Architecture Fit | GO | `setup-ui.sh` is CORE in `docs/vendor-coupling-manifest.json` (allowance 3) and already owns the whole module lifecycle; this replaces one line of `do_serve` with a routed handler and adds four endpoints that call the four subcommand bodies that already exist (`do_add` / `do_forget` / `do_scan` / `do_stop`). |
| 4 | Scope vs Supervisor Capability | CAUTION | Large but **not splittable**: every candidate split (server / endpoints / guard / page / tests) lands in the same two files, `setup-ui.sh` (60 KB) and `test-setup-ui.sh` (238 KB), so a split trips `file-conflict` rather than earning `genuine-parallelism`. Kept as ONE subtask; the context-bound risk that creates is R6. |
| 5 | Hard Blockers | CAUTION | No blocker, but **eight existing gate groups break on contact** and must each be updated deliberately, not loosened: R1 `do_stop`'s command-line guard · R2 `(a4)` one `fetch(` call site · R9 `(j13)/(j14)` `no_write_verbs` · R10 `(h1)/(h2)` one `http.server … --bind` · R12 `(l19)` the `no_write_verbs` **re-run** · R13 `(l21)` motion budget (`setTimeout` must stay **0**) · R14 `(l22)` `fetchText` call sites must equal exactly **3** · R15 `(b10)/(b11)` the SECOND, comment-inclusive motion budget. Every one was located by the scanner-name sweep below and confirmed by reading the line. |

**Overall Verdict:** GO (with the CAUTION findings carried into Risk Assessment as R1–R17)

> **How the breaking-gate list was made exhaustive — and why the FIRST TWO attempts at this list
> were wrong.** Draft 1 named two gates (recalled, not swept). Draft 2 added two more via a sweep
> that grepped for **the tokens a scanner matches** — which is structurally blind, because a
> re-run of a scanner 1,400 lines away contains none of those tokens. Plan Review found a third
> `no_write_verbs` call site the token sweep provably could not return. **The correct method is to
> grep for the SCANNER NAME and for the assertion's subject, not for the strings it matches:**
>
> ```bash
> cd loomwright/scripts
> grep -n 'no_write_verbs'  test-setup-ui.sh   # 8 hits -> (j13) :1586-1589, (j14) :1599, AND (l19) :3010
> grep -n 'code_occ'        test-setup-ui.sh   # -> (a4) :370, (a4b) :385, (a4c) :396, (l21) :3027-3029, (l22) :3041
> grep -n 'scan_egress'     test-setup-ui.sh   # -> (a1) :336, its control :411, AND (l20) :3016
> grep -n 'http[.]server'   test-setup-ui.sh   # 4 hits -> :1328 header, (h1) :1335-1336, (h2) :1340
> #   NB the assertion machinery itself is at :1332 [pins: `n_bind` awk] and :1342 — those spell
> #   the pattern bracketed as http[.]server, so this command does NOT return them. Cite, don't grep.
> # --- and the other half of the method: grep the assertion's SUBJECT, not only the scanner name.
> # Skipping this half is what hid (b10)/(b11) behind the differently-named `occ` scanner.
> grep -n 'setTimeout\|setInterval\|requestAnimationFrame' test-setup-ui.sh   # 13 hits -> BOTH motion budgets: (b10)/(b11) :491-499, (b13) :510-512, (l21) :3027-3032
> grep -n 'occ "'           test-setup-ui.sh   # 21 hits -> the SUPERSET; `code_occ` alone misses every `occ`-based gate
> grep -c 'not killed\|not-ours' test-setup-ui.sh   # -> 0  (R1's uncovered refusal path)
> grep -n 'serve[.]pid'     test-setup-ui.sh   # -> 17 pidfile call sites AC11 must exercise
> ```
>
> Each command's expected result is stated so a zero-hit or wrong-count run is **visibly** wrong
> rather than silently empty. (`grep -c 'not killed\|not-ours'` returning `0` is the finding;
> `grep -c` on the same file with `serve[.]pid` OR-ed in returns 17 and proves nothing — draft 2
> conflated the two and annotated the combined command "ZERO hits", which was false as written.)
>
> **Both halves are required.** Draft 3 applied only the scanner-name half and therefore missed
> `(b10)`/`(b11)` — a second motion budget built on `occ` rather than `code_occ`, which a
> `code_occ` grep structurally cannot return. Grep the scanner names **and** the subjects.
>
> **Re-run this sweep after the implementation lands.** A gate that breaks and is merely *deleted*
> leaves a green suite with a hole in it, which is the failure mode every AC below is shaped
> against.

## Task

**Goal:** Replace the module's static `python3 -m http.server` with a stdlib request handler that
preserves `GET` byte-for-byte and adds exactly four mutating endpoints — `add`, `forget`, `scan`,
`stop` — behind a four-part guard (per-run bearer token in a custom header, `Origin` validation,
`Host` validation) with untrusted-path confinement, so the projects the floor shows can be managed
from the floor.

**Problem Statement:**
An operator running The Floor needs to add, forget, re-scan and stop projects *from the page*,
because leaving the page for a terminal command is the same friction that produced item 06 one
level up. Currently the page can only render: the module serves the bundle with
`python3 -m http.server`, a static file server that answers `501` to every write, so there is no
endpoint to call. This costs the operator a context switch for the most routine action the page
exists to support. Success looks like the four registry operations and a server stop performed
from the page, with a hostile page in another tab provably unable to invoke any of them — each
guard proven load-bearing by a control that removes it and watches the attack succeed.

**The security content is the point, not a wrapper around it.** Item 04 justified having no
authentication with *"there is nothing to authenticate against on loopback"*. That was sound for a
read-only page and stops being sound the moment a write exists: a loopback port is not a security
boundary in a browser. Any site open in another tab can `fetch` a `POST` at `127.0.0.1:<port>`;
the attacker never reads the response, but the write has already landed. DNS rebinding extends the
same reach to a remote origin, and an `Origin` check alone does not stop it — that is why `Host`
validation is a separate, required part of the guard.

## Acceptance Criteria

- [ ] **AC1 — Static behaviour is unchanged.** Given the new handler, when every `GET` the current
      server answers is requested, then the response bytes are identical to the current server's.
      Asserted by diffing responses for each bundle file (`index.html`, `floor.css`, `floor.js`)
      and the served JSON (`index.json`, `floor.json`), captured from BOTH servers in the same
      test. An unrouted write (e.g. `PUT /`, `POST /floor.json`) still returns `501`.
- [ ] **AC2 — A mutating request with no token is refused.** Given each of the four endpoints, when
      it is called without the bearer token, then the response is `403` and the registry file is
      byte-identical afterwards. Asserted per endpoint with a hash of the registry before and after.
- [ ] **AC3 — A wrong or stale token is refused, proving the token is per-run.** Given a token
      captured from a *previous* `serve` run, when it is presented to the current run, then the
      request is refused; likewise for a syntactically valid but wrong token.
- [ ] **AC4 — A cross-origin request is refused.** Given a mutating request carrying a foreign
      `Origin`, and separately one carrying no `Origin` at all, when either is sent, then both are
      rejected and the registry is unchanged in each case.
- [ ] **AC5 — A non-loopback `Host` is refused (the DNS-rebinding case).** Given a forged `Host`
      header (e.g. `evil.example.com`) sent to the loopback socket, when a mutating request is
      made, then it is refused. The loopback names accepted are `127.0.0.1`, `localhost` and
      `[::1]`, each with and without the `:<port>` suffix.
- [ ] **AC6 — The token never appears where it could leak.** Asserted by grepping (a) the served
      bytes of every bundle file and the served JSON, (b) every file the module writes anywhere
      under the ui directory AND the registry, and (c) the server's own stdout/stderr. The token
      appears in exactly one place a human sees: the one-line URL `serve` prints.
- [ ] **AC7 — `add` rejects untrusted paths and still discriminates.** Given a traversal sequence
      (`../../etc`), a path that is not a directory, and a symlink resolving outside the permitted
      root, when each is submitted, then each is refused with a *named* reason and registers
      nothing. Given a legitimate absolute path to a real directory, it succeeds — proving the
      check discriminates rather than blanket-refusing.
- [ ] **AC8 — `scan` from the page proposes and does not write.** Given a `scan` request without
      confirmation, when it is made, then the response lists candidates and the registry is
      byte-identical; only an explicit confirming request registers anything. This matches
      `do_scan`'s existing `--confirm` contract.
- [ ] **AC9 — `forget` removes only a registry entry.** Given a registered project, when `forget`
      is called from the page, then the registry entry is gone and the project directory is
      byte-identical — asserted by hashing the project tree before and after.
- [ ] **AC10 — `stop` stops the server AND the page says so.** After the stop, the page renders a
      distinct *stopped* state — not a spinner, not a stale floor presented as current, and with no
      uncaught console error. Browser-verified with the console read.
- [ ] **AC11 — `stop` actually kills the new server process (R1 regression guard).** Given the
      replaced server, when `stop` runs, then the process is gone and `stop` reports it as stopped —
      **not** as `not killed … (not-ours)`. Asserted on the real process, plus a case proving the
      pidfile guard still REFUSES a pid whose command line is not this module's (that refusal path
      currently has zero coverage — see R1).
- [ ] **AC12 — Every failure path still exits 0 and writes nothing.** The engine's fail-safe
      convention (refuse-to-write plus a named reason, never a non-zero exit) holds for the server
      exactly as it does for the subcommands, including handler startup failure and a bad request.
- [ ] **AC21 — The string-index-anchored control `(l8)` still EXECUTES (R16).** `(l8)` at
      `:2828`-`:2862` builds its naive-scheduling mutant by exact string index into `setup-ui.sh`,
      anchored on two literals that are live today at `setup-ui.sh:985` and `:998`. If either is
      reflowed, `s.index` raises, the heredoc writes an empty mutant, `mutant_ok` returns false and
      `(l8)` is **SKIPPED inside its `if`** — neither red nor green — taking with it the only
      control proving `(l6)` can detect scheduling starvation, while `(l9)`'s null-mutation control
      survives so the suite still *looks* controlled. This change targets `do_serve` (`:1092`), not
      `serve_tick`, so the risk is adjacency rather than certainty: either leave those two literals
      **verbatim**, or re-author `(l8)`'s anchors and **confirm `mutant_ok` returns true** — the
      same standard AC14 sets for `(h2)`.
- [ ] **AC13 — Each of the four guard parts is proven load-bearing by removing it.** For token,
      custom header, `Origin` and `Host`: a mutation control disables **that part alone** and shows
      the previously-refused request **succeeding**. A mutant must be valid (non-empty, changed,
      syntax-clean — the suite's existing `mutant_ok`) before its result counts. Without these four
      controls the tests cannot distinguish a working guard from a guard that never fires.
- [ ] **AC14 — Loopback-only binding and zero egress are re-asserted, not inherited — and gates
      `(h1)`/`(h2)` are repaired, not deleted.** The server binds `127.0.0.1` only and the three
      bundle files still carry no remote reference of any kind. **`(h1)`** currently requires
      *exactly one* non-comment `python3 -m http.server` invocation carrying `--bind 127.0.0.1`;
      this change removes that invocation, taking both counts to `0` and reddening it. It must be
      **re-expressed against the new handler's bind expression while keeping its exactly-one shape**
      — not deleted. **`(h2)` fails silently and is the more dangerous half:** its mutant is
      `sed 's/python3 -m http.server --bind 127.0.0.1/…/'`, so once that literal is gone the sed is
      a no-op, `mutant_ok` sees an unchanged file, and the control is **SKIPPED inside its `if`
      rather than reported red**. `(h2)` must be re-authored so its mutant genuinely differs from
      the new engine, and the implementer must **confirm `mutant_ok` returns true** — i.e. that the
      control still EXECUTES. A green suite in which `(h2)` never ran fails this criterion.
- [ ] **AC15 — The `fetch(` call-site gate is re-baselined deliberately, not loosened (R2).** Test
      `(a4)` currently hard-asserts **exactly ONE** `fetch(` call site in `floor.js`. Writes add a
      second. The gate must be updated to the new exact count (a read helper and a write helper —
      **two**, not "at least one"), and `(a4a)` anti-vacuity plus mutation controls `(a4b)`/`(a4c)`
      must still pass and still be meaningful. A change to `>= 1`, or deleting a control, fails
      this criterion. **Two consequences must be handled in the same commit:** `(a4b)` at `:385`-
      `:388` hard-asserts `[ "$m_f2" = "2" ]` on a mutant that appends one real call — once `(a4)`
      is `2`, that expected value becomes **`3`** or the control goes red; and two pieces of prose
      this change falsifies without reddening anything — the suite header at `:53` ("ONE call site
      COUNTED IN CODE") and `(a3)`'s ok-string at `:365` ("the one call site passes
      `cache: 'no-store'`") — must be updated, since `(a3)` is presence-only and stays green while
      its own message goes stale.
- [ ] **AC16 — The vendor-coupling ratchet is measured and reported.** Run
      `bash scripts/check-vendor-coupling.sh --print-allowances` **after staging every new file**,
      commit the measured value (never hand-typed), and report the before/after delta. If the
      handler is split into its own file, classify it **explicitly** in
      `docs/vendor-coupling-manifest.json` rather than letting it fall to `unclassified_default`
      (which is CORE with allowance 0).
- [ ] **AC17 — `FLOOR_UI.md` documents the threat model in plain terms.** It states *why* a
      loopback port needs a token at all (the other-tab `fetch` and DNS-rebinding cases), so a
      future reader does not remove the guard as ceremony. Its "What it writes — the whole list"
      section stays exhaustive.

- [ ] **AC18 — `no_write_verbs` is re-baselined to an exact set at BOTH its assertion sites, and
      is not widened (R9, R12).** `(j13)` greps all three bundle files case-insensitively for a
      POST/PUT/DELETE *method position* **and** for the bare quoted tokens `'post'|'put'|'delete'`;
      the write helper cannot avoid matching it. The scanner's literal name is pinned by a prior
      subtask's `provides` and grepped by the deterministic `outputs_verified` gate, so **it cannot
      be deleted or renamed**. **`no_write_verbs` has THREE call sites, not two** — the definition
      (`:1569`), `(j13)`/`(j14)` (`:1586`-`:1600`), and **`(l19)` at `:3010`**, which re-runs the
      same scanner over the same shipped bundle 1,400 lines later and therefore reddens
      byte-for-byte identically. Re-baseline to the new *exact, enumerated* set — write-helper
      occurrences in `floor.js` only, with `index.html` and `floor.css` remaining at **zero** —
      **by changing the single shared scanner so `(j13)` and `(l19)` cannot drift apart**, and keep
      `(j14)` flagging an ADDED lowercase verb *beyond* that baseline. Relaxing the pattern, giving
      `(l19)` its own private copy of the rule, or deleting any of the three, fails this criterion.
      **`(j14)` already holds exactly such a private copy** — at `:1597` the control does NOT call
      `no_write_verbs`, it re-inlines the regex verbatim. Left alone, the moment the shared scanner
      is re-baselined `(j14)` keeps grepping with the OLD rule, its mutant still matches, and it
      stays **GREEN while controlling nothing** — the `(h2)`/R10 silent-vacuity class in a quieter
      form. `(j14)` must therefore be re-pointed to CALL the shared `no_write_verbs` against the
      mutant (e.g. by parameterising the function over a file list), and that third private copy
      removed in the same commit.
- [ ] **AC19 — The motion budget survives the write path at BOTH its assertion sites (R13, R15).**
      The budget is asserted **twice, by two different scanners**, and the stricter one is the easy
      one to miss:
      **(a) `(b10)`/`(b11)` at `:491`-`:499`** counts with **`occ`** — raw text, **comments
      included** — and `(b11)` requires `requestAnimationFrame == 0` **and `setTimeout == 0``.
      **(b) `(l21)` at `:3027`-`:3029`** counts the same three with **`code_occ`** (comments
      stripped) and requires `setInterval == 1`, `rAF == 0`, `setTimeout == 0`.
      Because `(b11)` is comment-inclusive it is **strictly stricter**: a mere *comment* in
      `floor.js` mentioning `setTimeout(` reddens `(b11)` while leaving `(l21)` green — so
      satisfying AC19 against `code_occ` alone is not enough, and the write path must avoid the
      token even in prose. A write path is exactly where a retry, debounce, "saved" flash or
      post-action re-poll gets reached for; drive it from the ONE existing poll instead. If a timer
      genuinely cannot be avoided, **both** sites must be re-baselined to the new exact counts with
      a stated reason — plus `(b13)`'s control at `:510`-`:512`, whose expected `m_int` is `2` —
      never relaxed to an inequality, and never by deleting a gate.
- [ ] **AC20 — The built-URL guarantee survives the write path (R14).** `(l22)` (`:3041`) asserts
      `code_occ "$JS" 'fetchText[(]'` is exactly **3**, alongside two `has_lit` checks that the two
      read URLs are built in `floor.js` (a fixed constant and `projectUrl(<encoded slug>)`) rather
      than read out of the served index, with mutation control `(l23)` proving a URL taken from the
      index is caught. The write path must preserve that property for its own endpoint URLs: they
      are **built in `floor.js` from a fixed prefix**, never read from any served document. If the
      write helper routes through `fetchText`, re-baseline the `3` to the new exact count; if it
      does not, `3` must still hold. `(l23)` must still execute (confirm `mutant_ok` returns true).

## Outcomes Rubric

- Managing which projects the floor shows never requires leaving the floor.
- A hostile page in another tab cannot add, forget, scan or stop anything.
- Every guard is proven to fire by a control that removes it and watches the attack succeed.
- A path supplied through the browser is treated as untrusted input, not as a filename.
- Static rendering, loopback-only binding and zero egress survive the server being replaced.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Routed stdlib server, four guarded endpoints, page write path, tests + docs | AC1–AC21 | 5 modify, 0 create | `frontend-ui`, `error-handling`, `unit-testing`, `quality-checklist` | LAUNCHABLE |

**Single subtask by the Decomposition Threshold default — no split, so no split reason is declared.**
A split was considered and rejected: server / endpoints / guard / page / tests all land in
`setup-ui.sh` and `test-setup-ui.sh`, so any division trips `file-conflict` rather than earning
`genuine-parallelism`.

**The handler stays inside `setup-ui.sh`** (hence `0 create`). Extracting it to a new top-level
script would be matched by the **explicit `core` glob `loomwright/scripts/*`** (in these shell
`case` patterns `*` does match `/`, per the manifest's own `glob_syntax_note`) with **no entry in
the `allowances` map — i.e. allowance 0** — so its first vendor reference would fail CI until it
was classified. (It never reaches `unclassified_default`; an earlier draft of this note said it
did. Same outcome, different mechanism.) If the implementer nonetheless extracts it, the
path is `loomwright/scripts/floor-server.py`, it must be added to `lanes` below AND classified
explicitly in `docs/vendor-coupling-manifest.json` in the same commit (AC16).

```yaml
# Subtask 1 — routed server + guarded endpoints + page + tests + docs (LAUNCHABLE)
provides:
  - {kind: "file",   path: "loomwright/scripts/setup-ui.sh"}
  - {kind: "symbol", path: "loomwright/scripts/setup-ui.sh", name: "serve_http"}
  - {kind: "file",   path: "loomwright/scripts/floor-ui/floor.js"}
  - {kind: "symbol", path: "loomwright/scripts/floor-ui/floor.js", name: "postAction"}
  - {kind: "file",   path: "loomwright/scripts/test-setup-ui.sh"}
  - {kind: "file",   path: "loomwright/docs/FLOOR_UI.md"}
  - {kind: "symbol", path: "loomwright/docs/FLOOR_UI.md", name: "## Why the guard exists"}
requires: []
lanes:
  - "loomwright/scripts/setup-ui.sh"
  - "loomwright/scripts/floor-ui/*"
  - "loomwright/scripts/test-setup-ui.sh"
  - "loomwright/docs/FLOOR_UI.md"
  - "loomwright/docs/vendor-coupling-manifest.json"
external_requires:
  - "python3 >= 3.7 (ThreadingHTTPServer + BaseHTTPRequestHandler; 3.9.6 confirmed present)"
```

> **`provides` naming note.** `serve_http` and `postAction` are the two new named units this
> subtask must create; if the implementer picks different names, update this contract in the same
> commit — the deterministic `outputs_verified` gate matches these names literally. The
> `FLOOR_UI.md` symbol is an **H2** because that file's top-level sections are H2 and this is a new
> top-level section. (Its actual heading structure, re-checked: one **H1** title at the top, eleven
> **H2** sections, and one **H3** subsection under `## The serve loop` — so H3 *is* an established
> level there. An earlier draft of this note claimed every heading was H2, which was false: it was
> inferred from a `grep '^## '` that could only ever return H2s. The token choice is unchanged; the
> reason for it is.)

## Parallelism Analysis

single-agent (no fan-out)

- Recommended workers: 1
- Rationale: one subtask, five files, all in one lane. Nothing to overlap.

## Skill References

- `skills/quality-checklist/SKILL.md` — pre/post-task gates
- `skills/error-handling/SKILL.md` — the fail-safe refuse-and-name-the-reason convention (AC12)
- `skills/unit-testing/SKILL.md` — mutation-control discipline for AC13/AC15
- `skills/frontend-ui/SKILL.md` — the page's stopped-state render (AC10)

## Risk Assessment

| # | Risk | Severity | Source | Mitigation |
|---|------|----------|--------|------------|
| R1 | **`do_stop` silently becomes a no-op.** It kills only a pid whose command line matches `*http.server*` or `*setup-ui.sh*`. Replacing `python3 -m http.server` changes that command line, so `stop` would report `0 process(es) stopped` while the server keeps running — and **`grep -c 'not killed' test-setup-ui.sh` = 0**, so no existing test covers that refusal path. | HIGH | Feasibility (Phase 2.5) | AC11. Either invoke the handler so its command line still contains `setup-ui.sh`, or extend the guard — and assert BOTH the kill and the still-refuses-a-foreign-pid case. |
| R2 | **The `(a4)` one-`fetch(`-call-site gate breaks on contact.** ``test-setup-ui.sh:372 [pins: `[ "$n_fetch" = "1" ]`]`` asserts exactly `1`; a write path makes it `2`. The tempting fix (relax to `>= 1`) destroys the gate. | HIGH | Feasibility (Phase 2.5) | AC15 — re-baseline to the new exact count and keep `(a4a)` anti-vacuity and both mutation controls meaningful. |
| R3 | **A guard that never fires still passes every test.** Four-part guards are exactly where a vacuous assertion hides. | HIGH | Requirement | AC13 — a per-part mutation control that removes one part and watches the attack succeed, gated on the suite's existing `mutant_ok` validity check. |
| R4 | **Path handling reaches a directory the projector runs in.** A path from the browser becomes a working directory, so traversal / symlink escape is a real write-primitive, not a lint concern. | HIGH | Requirement | AC7 — resolve, confine, reject non-directories, with a positive case proving it is not blanket-refusing. |
| R5 | **CSP is asserted verbatim.** `index.html` carries a CSP meta the suite compares literally. | MEDIUM | Phase 3 analysis | `connect-src 'self'` already permits a same-origin `POST`, so **no CSP change is needed**; if one is made anyway, the verbatim assertion must be updated in the same commit. |
| R6 | **Context-bound single subtask.** `test-setup-ui.sh` is 238 KB and `setup-ui.sh` 60 KB; one worker must edit both. | MEDIUM | Feasibility (Phase 2.5) | Splitting is worse (R4 of the threshold: same-file conflict). Worker should read only the regions it edits and append test groups rather than re-reading the whole suite. |
| R7 | **Release-surface obligations are easy to half-do.** Command count stays 22 and `/ui` gains no verb; no new agent, no new hook. | MEDIUM | Requirement | If a verb *does* prove necessary, bump every doc surface in the same commit. AC16 covers the ratchet; AC17 covers `FLOOR_UI.md`. `check-doc-currency.sh` verifies claims that ARE made — it cannot tell you a claim should not have been made. |
| R8 | **A stale-token test can pass for the wrong reason.** A "previous run" token is refused by a server that refuses *everything*. | MEDIUM | Plan analysis | AC3 must pair the stale-token refusal with a same-run *accepted* request, or it proves nothing. |
| R9 | **`no_write_verbs` goes red on contact and cannot be deleted.** It greps all three bundle files case-insensitively for a POST/PUT/DELETE method position AND for the bare quoted tokens; the write helper necessarily matches. Its literal name is pinned by a prior subtask's `provides` and grepped by the deterministic `outputs_verified` gate. | HIGH | Plan Review (attempt 1) | AC18 — re-baseline the single shared scanner to an exact enumerated set (write helper in `floor.js` only; `index.html`/`floor.css` stay at zero) and keep `(j14)` meaningful. Widening the pattern or deleting the gate fails AC18. |
| R10 | **`(h1)` goes red and its control `(h2)` vanishes SILENTLY.** `(h1)` needs exactly one non-comment `python3 -m http.server … --bind 127.0.0.1`; this change removes it (counts → 0/0). `(h2)` mutates by sed-replacing that exact literal, so once it is gone the sed is a no-op, `mutant_ok` sees an unchanged file, and the control is **skipped inside its `if` rather than reported red** — leaving one red assertion a worker is tempted to delete and one control that already stopped running. | HIGH | Plan Review (attempt 1) | AC14 — re-express `(h1)` against the new bind expression keeping its exactly-one shape, re-author `(h2)`'s mutant to genuinely differ, and **confirm `mutant_ok` returns true** so the control actually executes. |
| R11 | **A breaking-gate list assembled the wrong way stays incomplete — twice over.** Draft 1 recalled gates (found 2 of 7). Draft 2 swept for *the tokens a scanner matches* (found 4 of 7) — structurally blind to a re-run of that scanner elsewhere in the file, which contains none of those tokens. | MEDIUM | Plan Review (attempts 1 & 2) | The sweep in §Feasibility now greps for **scanner names and assertion subjects**, with each command's expected hit count stated so a wrong run is visibly wrong. Re-run it after implementation. |
| R12 | **`(l19)` at `test-setup-ui.sh:3010` re-runs `no_write_verbs` over the same bundle**, 1,400 lines from `(j13)`, and reddens identically. A worker who fixes only `(j13)` lands a red `(l19)` that no criterion protects — and the tempting fix there is deletion. | HIGH | Plan Review (attempt 2) | AC18 covers BOTH sites and requires the fix to land in the one shared scanner so they cannot drift. |
| R13 | **`(l21)` requires `setTimeout == 0` in `floor.js`.** A write path is exactly where a retry, debounce, "saved" flash or post-action re-poll gets reached for, and any of them reddens the motion budget. | HIGH | Own sweep (attempt 3) | AC19 — drive the write path from the ONE existing poll; if a timer is unavoidable, re-baseline to exact counts with a stated reason, never to an inequality. |
| R14 | **`(l22)` requires exactly 3 `fetchText(` call sites** and that both fetched URLs are BUILT in `floor.js` rather than read from the served index (control `(l23)`). | MEDIUM | Own sweep (attempt 3) | AC20 — endpoint URLs are built from a fixed prefix; re-baseline the count only if the write helper genuinely routes through `fetchText`, and confirm `(l23)` still executes. |
| R15 | **The motion budget is asserted TWICE and the stricter site is comment-inclusive.** `(b10)`/`(b11)` at `:491`-`:499` count with `occ` (comments included), so a *comment* mentioning `setTimeout(` reddens `(b11)` while `(l21)`'s `code_occ` count stays green. | HIGH | Plan Review (attempt 3) | AC19 names BOTH sites plus `(b13)`'s `m_int = 2`; the write path avoids the token even in prose. |
| R16 | **`(l8)` is a second string-index-anchored control that skips silently.** Its mutant is built by `s.index` on two literals live at `setup-ui.sh:985`/`:998`; reflow either and the control is skipped, not failed — while `(l9)` survives so the suite still looks controlled. | MEDIUM | Plan Review (attempt 3) | AC21 — keep the literals verbatim, or re-author the anchors and confirm `mutant_ok` returns true. |
| R17 | **`(j14)` holds a private copy of the `no_write_verbs` regex** (`:1597` re-inlines it rather than calling the function), so re-baselining the shared scanner leaves `(j14)` green and controlling nothing. | MEDIUM | Plan Review (attempt 3) | AC18 — re-point `(j14)` to CALL the shared scanner and delete the private copy in the same commit. |

## Configuration

- **Base Branch:** main
- **Worktrees:** not required (single subtask, single lane)
- **Cost profile:** inherit (no `--cheap` passed by the driver)
- **Review lane:** deterministic `outputs_verified` + tests/lint per subtask; Phase 4.5 integrated review is the sole LLM gate
- **Test command:** `bash loomwright/scripts/test-setup-ui.sh`
- **Ratchet command:** `bash scripts/check-vendor-coupling.sh --print-allowances` (run after staging)

## Handoff

/supervisor job: .supervisor/jobs/pending/2026-09-04-ui-guarded-writes.md
