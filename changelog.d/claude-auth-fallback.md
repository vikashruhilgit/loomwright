<!-- bump: patch -->
CI Claude workflows fall back between an API key and the subscription login
The `claude-review` and `@claude` workflows now try two Claude logins in one run instead of one. Attempt 1 uses the
login named by the `CLAUDE_AUTH_FIRST` repository variable (`api` for the `ANTHROPIC_API_KEY` secret, the default,
or `oauth` for `CLAUDE_CODE_OAUTH_TOKEN`); attempt 2 uses the other one and runs only when attempt 1's login is not
saved or the run died at startup (`is_error` on turn 1 with $0 spent: a revoked login, no credit, the weekly cap or
a transient API rejection). A review that ran and then failed is never retried, so a fallback cannot pay for or post
a second review. Each attempt receives exactly one login, the log names the login that ran, and the job fails with
a named reason when no login worked. Motivated by an account-wide "log out everywhere" that revoked the stored OAuth
token and turned every review red at $0.
