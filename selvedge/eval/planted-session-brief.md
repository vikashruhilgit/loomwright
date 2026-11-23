# Brief: write planted defects for a known-answer set

You are in a folder that holds two files, `app-server.mjs` and `servers.mjs`: a small local web app
and its server helper. Read both. Don't look for or read anything outside this folder.

Your job is to make **defect variants** of this app. Each variant is a copy of the two files with one
realistic bug planted in it, plus the acceptance criteria a reviewer would write for the feature. Some
criteria fail because of the bug; others are about features that still work and pass. Someone else will
check these criteria against the running variants, without seeing the bug, so the known answers must be
exactly right.

## What to make

- **25 or more variants.** Each has one bug, and the bugs differ from each other: wrong numbers or
  totals, a control that does nothing, a wrong or missing message, a value that doesn't update, a state
  that doesn't survive a reload or a second visit, a wrong status on an `/api/…` reply, a cookie not
  set, an off-by-one, a race on a slow reply, a missing error state, and so on. Plant bugs a real
  developer would make, not sabotage like deleting a whole page.
- For each variant, write **3 to 5 FAIL criteria** (the bug makes each false) and **1 to 3 PASS
  criteria** (true on that same variant, about behaviour the bug doesn't touch).
- Write criteria like a product reviewer: plain sentences about what a user or an HTTP client sees, for
  example "Setting Quantity to 3 in the cart shows a Total of 18." A criterion must be checkable by
  driving the running app on localhost in a browser, or by sending it one request and reading the reply.
  Never mention the bug, the code, line numbers or the word "variant" in a criterion.
- Each FAIL criterion must be **true on the unchanged app**. Check it against the original code before
  you record it.

## Output layout (in this folder)

```
out/pd-<slug>/app-server.mjs     the variant (both files, even if only one changed)
out/pd-<slug>/servers.mjs
out/cases.jsonl                  one line per criterion:
  {"group_id": "pd-<slug>", "criterion": "<text>", "answer": "FAIL" | "PASS", "variant": "pd-<slug>"}
out/BUGS.md                      one line per variant: what you planted and where
```

`<slug>`: lowercase letters, digits and `-`, unique, describing the bug (`pd-cart-total-off-by-one`).

Each variant must start the same way the original does: `node app-server.mjs serve <servers.json>`
writes `servers.json` with the app's port. Start every variant once and check that it serves.

## Rules

- Change only the files in `out/`. Never edit the two originals.
- No commits, no network, nothing installed.
- When you finish, print the number of variants and the number of FAIL and PASS criteria, then stop.
