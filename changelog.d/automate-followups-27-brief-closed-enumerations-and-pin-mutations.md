<!-- bump: minor -->
Briefs name the closed lists a new enum value must join and the mutation each new test pin must catch
Two runs of the same item missed the same two things: a new escalation value left out of a closed list that must
name every value, and seam pins that stayed green when the code they pinned was deleted. The brief template gains two
sections, required only when they apply: `## Closed enumerations touched` (each new value, the repo-wide grep of a
sibling value with its hits, and every closed list that must name it) and `## Pin mutations` (per new or changed pin,
the one-line code mutation that must turn it red). Launch Pad fills them in Phase 3 action 12. Plan Reviewer's new
conditional Criterion 19 raises a MEDIUM `closed_enumerations` finding for a new value without its entry or a listed
closed list outside the brief's File Impact Map and `lanes:`, and a MEDIUM `pin_mutations` finding for a pin without
its row. Under the EXECUTION DIRECTIVE, Phase 4.5's code reviewer runs each listed mutation in a scratch copy; a pin
that stays green on its mutant is a BLOCKING finding. A brief with no new value and no pin needs neither section.
