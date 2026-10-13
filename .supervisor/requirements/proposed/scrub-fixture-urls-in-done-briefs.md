# Done briefs quoting test-fixture URLs are refused by the metadata scrub at wave close

## Status: proposed

> Propose-only follow-up from run `automate-2026-10-12-181635` (lane L2, af36-remainder/02). First sighting; cost ~2
> minutes. Not enqueued.

## What happened
At wave close, L2's done brief `.supervisor/jobs/done/2026-10-12-af36-02-meta-allowlist-grant.md` was refused by
`meta-sync.sh push`'s scrub (`email` + `forge_slug`). The hits were test-fixture examples the brief quoted:
an scp-style git SSH address (`git` + at-sign + the GitHub host + colon) and two fixture repo URLs on the GitHub host (owner `acme`, repo `widget`; owner `owner`, repo `repo`). The coordinator replaced
the three strings with `<forge>/<owner>/<repo>` placeholders and the push went through. No other managed file trips
these rules today.

## Two separate causes
1. **Scrub false positive (email).** The email regex matches `git` + at-sign + `<forge host>:` — a git SSH address, not a person's
   e-mail. Exempt exactly the `git` user at the three forge hosts the forge_slug rule knows from the email rule; test it, keep a real
   address refused.
2. **Writer side (forge_slug).** The scrub cannot tell a fixture slug from a real repo (`acme` is a real GitHub
   account), so the scrub is right. Briefs/plans should write fixture URLs as `<owner>/<repo>` placeholders: add the
   rule to Launch Pad's brief-writing guidance (and the worker's, for done-brief Outcome text).

## Timing gap
The refusal surfaces only after the owner merged, because a done brief is held back (`excluded — pr not merged`)
until then. Optional: run a dry scrub of the done brief at the lane's `ready_for_release` park so the lane can fix it
before the wave PR is built.
