<!-- bump: patch -->
verify-provides.sh reads escaped quotes in a provides name, and Plan Review blocks a name it cannot read
`verify-provides.sh`'s `field()` ended a quoted value at the first matching quote with no escape handling, so v2-b's
entry `name: "PINS=\"1 2 3 4 5 6 7 8 9 10\""` was searched as `PINS=\` and reported a false `missing`, which stops
a green worker at the fail-closed `outputs_verified` gate. Inside double quotes `\"` now reads as a literal `"` and
`\\` as one backslash, and the value ends at the first unescaped `"`; every other backslash sequence is kept as
written, single-quoted names have no escapes, and an unterminated quote reads as before. A name the parser still
cannot read faithfully (an unterminated quote, or text between the closing quote and the next `,`/`}`) now adds an
additive `parse_warnings` array to the `--parse-only` object, naming the entry's path and the parser's reading; a
clean brief prints the same object as before. Plan Reviewer Criterion 12 makes such a GATE PARSE line a BLOCKING
`dep_graph` finding that quotes that reading, instead of a LOW note. The gate run also names the quoting problem on
stderr; its JSON is unchanged. New `test-verify-provides.sh` cases cover both escapes, single quotes, v2-b's entry
verbatim against a copy and the real file, the unterminated case, `parse_warnings` present and absent, and a mutation
control proving the `\"` case goes red without the escape handling.
