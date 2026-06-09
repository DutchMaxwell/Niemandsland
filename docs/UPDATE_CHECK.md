# Startup update check

When the desktop game starts, Niemandsland checks whether a newer release has been
published and, if so, offers the player a download — without ever blocking the menu.
This is the launcher-style "an update is available" prompt you know from Steam and
similar clients.

> **Status:** the plumbing ships now but is **inert until releases are published**.
> With no GitHub Releases the check resolves to "up to date" and the menu shows
> nothing. Publishing a release (see [Activating it](#activating-it)) turns it on with
> no code change.

## How it works

| Piece | File | Role |
|---|---|---|
| `UpdateChecker` (autoload) | `scripts/update_checker.gd` | Fetches releases, compares versions, emits signals. Holds the pure, unit-tested SemVer logic. |
| `UpdatePrompt` (dialog) | `scripts/update_prompt.gd` | Non-blocking "Download / Later / Skip this version" popup. |
| Startup wiring | `scripts/startup_menu.gd` | Starts the check and shows the prompt on a hit. |

Flow on launch:

1. `startup_menu.gd` → `_maybe_check_for_updates()` runs **only** for the live main
   scene (so gdUnit's `scene_runner` tests never hit the network) and **only** off the
   web (itch/web is always the latest deploy).
2. `UpdateChecker.check_for_updates()` GETs the project's GitHub Releases list.
3. The newest non-draft release tag is compared against the running
   `application/config/version` (the same string the multiplayer version handshake
   uses — see `network_manager.gd`).
4. If it is strictly newer and not skipped, `update_available` fires and the menu pops
   the `UpdatePrompt` over itself.
5. **Download** opens the release page (`OS.shell_open`); **Later** dismisses it;
   **Skip this version** persists so that exact version is never offered again.

Everything is best-effort: offline, rate-limited, or malformed responses emit
`check_failed` and the menu simply carries on.

## Why the list endpoint (not `/releases/latest`)

GitHub's `/releases/latest` returns the latest **stable** release and skips
prereleases and drafts. The whole project is on its alpha line, so every release is a
GitHub *prerelease* — `/releases/latest` would 404. We therefore read the list
endpoint and pick the highest version ourselves (`INCLUDE_PRERELEASES = true`).

## Version comparison

`UpdateChecker` implements a SemVer-precedence subset that handles the project's
`MAJOR.MINOR.PATCH-prerelease` scheme:

- A leading `v` and any `+build` metadata are tolerated/ignored.
- Numeric core fields compare numerically (`0.4.0 > 0.3.9`).
- A stable release outranks its matching prerelease (`0.3.1 > 0.3.1-alpha`).
- Prerelease identifiers compare per SemVer §11 (`alpha < beta`, `alpha.2 > alpha`).
- Malformed input never counts as "newer" — the check fails safe.

## Activating it

Publish a GitHub Release whose **tag matches `config/version`** in `project.godot`
(e.g. tag `0.4.0-alpha` for version `0.4.0-alpha`). A leading `v` (`v0.4.0-alpha`) is
fine. The next time a player on an older build launches the desktop game, they get the
prompt. Mark alpha/beta builds as *prereleases* — they are still picked up.

## Privacy

The check is a single unauthenticated `GET` to the public GitHub API. No telemetry,
identifiers, or game data are sent. Players can turn it off (persisted in
`user://update_check.cfg`, key `update_check/enabled`) or skip a specific version from
the prompt.

## Repointing at a self-hosted endpoint

If GitHub's unauthenticated rate limit (60 req/h per IP) ever becomes a concern, or you
prefer to serve version info from the existing asset host (`<legacy-cdn-host>`), the
source is isolated to a few constants in `update_checker.gd`
(`RELEASES_API_URL`, `RELEASES_PAGE_URL`) and the response parsing in
`_on_request_completed()`/`_select_newest_release()`. Point those at a small
`version.json` and the rest of the flow (comparison, prompt, skip) is unchanged.
