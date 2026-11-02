# Criterion 22 fixtures: expected requirement-fit ratings

This file is the answer key for the four requirement + brief pairs in this directory. It is **never shown to a
reviewer**: a live Plan Reviewer run receives the brief text and the requirement text only (the requirement between
`--- SOURCE REQUIREMENT ---` markers, as Launch Pad's spawn contract pastes it), never a file name. So no brief or
requirement carries a rating, a label, a criterion number or a header comment.

The four `*-requirement.md` files are byte-identical: one requirement (exit-code tables on three command pages, two
non-goals, one Validation entry), copied once per pair so each pair stands alone. The briefs share its title and
task; only their coverage and their units differ:

- `fulfils-brief.md` — one subtask; its acceptance criteria cover every requirement line, and its File Impact Map
  groups are the three command pages plus the budget rows and changelog fragment.
- `missing-brief.md` — the same brief with the `/obsidian` criterion and its command page dropped, so requirement
  AC3 has no covering unit.
- `extra-brief.md` — three subtasks; Subtask 2 adds `## Troubleshooting` sections to three other command pages,
  which no requirement line asks for and no non-goal forbids.
- `supporting-brief.md` — three subtasks; besides the exit-code tables, Subtask 2 is a new test and Subtask 3 is
  the budget rows and the changelog fragment.

Only the `requirement_fit` and Criterion 22 columns are the answer key. Other criteria may add their own notes on a
fixture, so the decision is listed as the one Criterion 22 implies on its own.

| Pair | Expected `requirement_fit` | Expected Criterion 22 issues | Decision Criterion 22 implies |
|---|---|---|---|
| `fulfils-*` | `fulfils` | none | PASS |
| `missing-*` | `under` | HIGH `requirement_fit`: requirement AC3 (`/obsidian` table) is `missing` | FAIL |
| `extra-*` | `over` | MEDIUM `requirement_fit`: Subtask 2 (troubleshooting sections) is `extra` | PASS (Launch Pad refines it at its fix floor) |
| `supporting-*` | `fulfils` | none: Subtask 2 (test) and Subtask 3 (budgets, changelog fragment) are `supporting` | PASS |

Live run: `docs/evidence/plan-review-requirement-fit.md` records the exact command and each pair's verbatim
`requirement_fit` line and decision.
