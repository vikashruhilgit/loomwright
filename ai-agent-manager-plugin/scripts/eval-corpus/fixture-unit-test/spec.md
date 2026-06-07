# Task: fixture-unit-test

## What this task asks

Demonstrate the "a function plus its passing unit test" eval shape,
end-to-end, fully self-contained inside one corpus task (no repo
dependency).

The task ships two small files in its own directory:

- **`slugify.sh`** — a tiny, pure-shell fixture function `slugify()`.
  Contract: given a string, it
  - lowercases all characters,
  - replaces every run of non-alphanumeric characters with a single `-`,
  - trims leading/trailing `-`,
  - and yields the empty string for empty input or input with no
    alphanumerics.
- **`slugify_test.sh`** — the unit test, with assertions covering:
  `"Hello World" -> hello-world`; leading/trailing junk trimmed and
  internal punctuation collapsed (`"  --Foo_Bar!!  " -> foo-bar`); empty
  input -> empty; all-punctuation -> empty; and run-squeezing
  (`"A  B   C" -> a-b-c`).

## How it's checked

`check.sh` runs the bundled unit test (`bash slugify_test.sh`) and exits
with its status — exit 0 (all assertions pass) = pass, non-zero = fail.
The check is deterministic and self-contained; it touches nothing outside
the task directory.
