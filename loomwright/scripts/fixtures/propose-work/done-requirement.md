# Worker-stage convention mismatches - the citation-drift batch

## Status: done

This is a FIXTURE. It exists so `test-propose-work.sh` has a reproducible positive case for
the second supersession arm (a requirement file marked done that already covers a candidate's
evidence set). Done-stamped requirement files DO exist in the real working store, but
`.gitignore` ignores `.supervisor/*`, so none of them is committed and none of them is present
on a fresh clone or a CI runner. Driving that arm off the live store would make it pass on the
author's machine and never run in CI.

The token below is the evidence set `propose-work.sh` computes for the
`convention_mismatch` / `worker` pair of `fixtures/propose-work/floor-golden.json`: the pair
identity plus the exact `L<line>.<index>` ledger coordinates it would cite. It is deliberately
human-readable so a person can retire a candidate by pasting it into a real requirement file.

evidence-set: convention_mismatch/worker@L3.0,L7.1,L11.0,L14.0,L19.1

## Problem

Worker-stage findings kept restating values the repo holds in one authoritative place, and
kept citing absolute line numbers that the next insertion above them falsified.

## Goal

Closed. Recorded here so the proposer does not re-raise the same evidence set.

## Acceptance criteria

- [x] The evidence set above is covered by this file.
