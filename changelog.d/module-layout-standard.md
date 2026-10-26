<!-- bump: minor -->
Module layout is a quality standard: Launch Pad plans each new responsibility's module, Plan Reviewer checks the plan, the worker follows it and Phase 4.5 reviews structure from facts
The size default lives once, in `skills/supervisor-readiness/SKILL.md` §"Module layout", together with the File
Impact Map facts it requires: a line count per MODIFY path, one home per new responsibility (a CREATE module, the
shared module it extends, or a one-line reason for appending), and an extract row when 2+ sibling files already copy
a helper the change needs. Test files count like source, and a committed `.agent/rules/` house rule that states
another size overrides the default for its paths only. Launch Pad Phase 3 applies it, Plan Reviewer's conditional
Criterion 21 reports a missing plan as a MEDIUM `module_layout` issue that never fails a brief on its own (the
Launch Pad surfaces that restated the criteria count now say "every review criterion"), and the worker follows the
map's module plan and records a departure as a `plan:` deviation. The new fail-safe
`loomwright/scripts/module-shape-facts.sh <base> [<head>] [--root <dir>]` prints each touched file's line count
before and after the diff and each name the diff adds that 2+ files define, with the file count and a capped file
list; it holds no threshold, always exits 0, and prints nothing (with a one-line stderr reason) when it cannot
produce facts. Self-heal step 1h runs it on every Phase 4.5 iteration and threads the output as the MODULE-SHAPE
ADVISORY line, a hint to the review lens only, whose absence means "facts unavailable", not "no structural issue".
The code reviewer's new structure dimension raises a MEDIUM `category: new` finding for a helper copied into 2+
files only after reading both definitions, never for a deliberate per-file convention such as each test script's
own harness helpers, and a LOW finding for a file grown with an unrelated responsibility; neither is ever BLOCKING
or HIGH. `test-module-shape-facts.sh` pins every filter and every no-facts reason.
