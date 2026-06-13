# Security Policy

Niemandsland is in alpha. If you find a security issue — especially anything
affecting the multiplayer relay or that could expose other players — please report
it **privately** rather than opening a public issue.

## Reporting

Use GitHub's **private vulnerability reporting**: the *Report a vulnerability*
button under this repository's **Security** tab. That reaches the maintainers
privately.

Please include reproduction steps and the affected version. We acknowledge and work
on fixes on a best-effort basis (this is a hobby alpha).

## Scope

In scope: the game client, the WebSocket relay (`relay/`), save/load, and the
multiplayer protocol. Out of scope: third-party services the game integrates with
(e.g. the OnePageRules Army Forge API).
