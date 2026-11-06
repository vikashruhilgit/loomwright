# Evidence — trust-unprotected-private-free, Validation 2 (the live paid-plan refusal)

A read-only `GET` of the branch-protection endpoint on a private repo owned by the authenticated `gh` account
(personal account, `owner.type: User`, `private: true`), run 2026-11-06 with gh 2.102.0. Nothing was written to any
repo. The owner and repo are redacted to `<owner>/<repo>` below; no other byte of the output is changed.

The account's plan is not readable with this token (`gh api user --jq .plan` prints `null`). The refusal text
itself is GitHub's statement that the plan cannot protect a branch of a private repo.

## Command and output (stdout and stderr captured separately)

```
$ gh api repos/<owner>/<repo>/branches/main/protection >out.txt 2>err.txt; echo rc=$?
rc=1
$ cat out.txt        # 205 bytes, no trailing newline
{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.","documentation_url":"https://docs.github.com/rest/branches/branch-protection#get-branch-protection","status":"403"}
$ cat err.txt        # 92 bytes
gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)
```

## The same call as `gate-eval` makes it (stdout and stderr merged, `2>&1`)

gh prints the JSON body with no trailing newline, so the merged capture puts the body and the `gh:` line on one
line. The gate's classifier reads the status from the last line that ends in `(HTTP NNN)`, so it still finds the
403 and the refusal message on that line.

```
$ gh api repos/<owner>/<repo>/branches/main/protection >merged.txt 2>&1; echo rc=$?
rc=1
$ cat merged.txt     # 297 bytes
{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.","documentation_url":"https://docs.github.com/rest/branches/branch-protection#get-branch-protection","status":"403"}gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)
```

## Byte comparison with the test stub's 403 text

The stub's `protection-error` file was filled exactly as `test-automate-helpers.d/05-gate-eval.sh` fills it
(`printf '%s\n' "$E_PAID_403"`, with `E_PAID_403` read from `05-gate-eval-harness.sh`), and the stub `gh` from
`test-automate-helpers.sh`'s `make_stub_bin` was called the same three ways. Every capture is byte-identical:

```
stub rc=1
out: identical (205 bytes)
err: identical (92 bytes)
merged: identical (297 bytes)
live sha256:
679d5e86a2d0420e39e3231784b69b41386d12599f70ff4fc4ed7c0438095272  out.txt
dbf87ea4a345f4e73a9582fd3cefce7cc3f1871e16dba5e56523eff7fdf6cca4  err.txt
03bc633c7f1735f2f98853f758e945676281823caf34a38c325aa47ed8d7244f  merged.txt
stub sha256:
679d5e86a2d0420e39e3231784b69b41386d12599f70ff4fc4ed7c0438095272  stub-out.txt
dbf87ea4a345f4e73a9582fd3cefce7cc3f1871e16dba5e56523eff7fdf6cca4  stub-err.txt
03bc633c7f1735f2f98853f758e945676281823caf34a38c325aa47ed8d7244f  stub-merged.txt
```

## The gate's classifier on the live captures

`_ge_protection_class` (extracted from this branch's `automate-helpers.sh`) run on the live merged capture above,
and on a live merged capture of a public repo whose `main` has no protection (`gh: Branch not protected (HTTP 404)`):

```
paid-plan 403 (live) -> not_enforceable
404 (live, public repo) -> not_enforceable
```

Verdict: PASS for Validation 2

## Honest limits

- This checks the protection read only. The gate's MERGE / PARK outcomes on this text are covered by the stubbed
  cases in `test-automate-helpers.d/05-gate-eval.sh` and `06-gate-eval-tail.sh`, not by a live merge.
- The drain's own protection read (`wait-for-checks.sh`) is unchanged and still reads this 403 as `required=unknown`,
  so an end-to-end `/automate --auto-merge --trust-unprotected` run on a private Free repo escalates in the drain
  before the gate runs, unless `--required-checks all-non-neutral` is set.
- If GitHub changes the refusal text, the gate parks `protection_unreadable` (fail-closed) until the stub and the
  matcher are updated.
