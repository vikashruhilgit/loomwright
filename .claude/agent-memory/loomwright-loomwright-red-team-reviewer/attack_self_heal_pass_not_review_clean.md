---
name: attack-self-heal-pass-not-review-clean
description: A green heal_decision=PASS does NOT mean the PR is reviewer-clean; probe whether ground_truth/conformance actually ran before crediting it
metadata:
  type: project
---

A green `heal_decision: PASS` does NOT mean the PR is reviewer-clean. Do not treat PASS as proof of quality.

**Why:** 11/11 supervisor sessions ended PASS, yet the highest-ground-truth session (system-twin-foundation) still needed 3+ human PR-review-fix rounds after PASS. PASS only means "no NEW BLOCKING/HIGH in the Phase-4.5 diff," not "no findings a reviewer would raise."

**How to apply:** When auditing the self-heal gate, treat PASS as a weak signal. Probe whether ground-truth/conformance actually ran (they're often skipped) before crediting a PASS. See also code-reviewer `self-heal-rubber-stamp` and project MEMORY "PR churn = self-heal blind spot".
