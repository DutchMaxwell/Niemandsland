# Startup update check

When the desktop game starts, Niemandsland checks whether a newer release has been
published and, if so, offers the player a download — without ever blocking the menu.
This is the launcher-style "an update is available" prompt you know from Steam and
similar clients.

> **Status:** live — releases are published on GitHub and the checker compares against them.
> With no GitHub Releases the check resolves to "up to date" and the menu shows
> nothing. Publishing a release (see [Activating it](#activating-it)) turns it on with
> no code change.

## How it works

| Piece | File | Role |
|---|---|---|
| `UpdateChecker` (autoload) | `scripts/update_checker.gd` | Fetches releases, compares versions, emits signals. Holds the pure, unit-tested SemVer logic. |
| `UpdatePrompt` (dialog) | `scripts/update_prompt.gd` | Non-blocking "Update & Restart / Later / Skip this version" popup. |
| `SelfUpdater` | `scripts/self_updater.gd` | Downloads the release `.zip` and installs it over the running install, then relaunches. On Windows a helper script swaps every file of the release (see [Windows updates and the rules core](#windows-updates-and-the-rules-core)). |
| `CoreSelfHeal` | `scripts/core_self_heal.gd` | Windows export only, at boot: restores a missing `nml_core_godot.dll` once after an in-game update from `0.3.12.0`. |
| Startup wiring | `scripts/startup_menu.gd` | Starts the check and shows the prompt on a hit. |

Flow on launch:

1. `startup_menu.gd` → `_maybe_check_for_updates()` runs **only** for the live main
   scene (so gdUnit's `scene_runner` tests never hit the network).
2. `UpdateChecker.check_for_updates()` GETs the project's GitHub Releases list.
3. The newest non-draft release tag is compared against the running
   `application/config/version` (the same string the multiplayer version handshake
   uses — see `network_manager.gd`).
4. If it is strictly newer and not skipped, `update_available` fires and the menu pops
   the `UpdatePrompt` over itself.
5. **Update & Restart** downloads this platform's release `.zip`, installs it over the running
   install and relaunches; with no matching `.zip` asset, or when the self-update fails, it opens
   the release page instead (`OS.shell_open`). **Later** dismisses it;
   **Skip this version** persists so that exact version is never offered again.

Everything is best-effort: offline, rate-limited, or malformed responses emit
`check_failed` and the menu simply carries on.

## Windows updates and the rules core

The Windows exports carry the Rust rules core (`nml_core_godot.dll`) next to `Niemandsland.exe`.
Both files are locked while the game runs, so `SelfUpdater` writes a small helper script that waits
for the game to exit (at most about 30 s), backs up and replaces **every** top-level file of the
release, and restores all backups if any copy fails — never a half-swapped install
(`SelfUpdater.windows_helper_script`, `scripts/self_updater.gd:173-208`).

The `0.3.12.0` helper replaced only the `.exe`, so an in-game update from `0.3.12.0` leaves the new
build without its core file and NACHTMAHR would quietly play the decision tree. On its first start a
Windows export without `NmlCore` therefore looks in the release the old updater left in
`user://_update/extracted`. Only if that staged `Niemandsland.exe` is byte-identical (sha256) to the
running one does it copy `nml_core_godot.dll` next to the game and restart once
(`CoreSelfHeal`, started from `UpdateChecker._ready`). A marker in `user://core_selfheal.txt` is
written before the restart, so a start that is still without the core gives up: the tree plays and
the game never restarts again. A failed copy, or no matching staged release, also restarts nothing. Every outcome prints exactly one log line starting with `core self-heal:`; after a successful
heal it reads `core self-heal: NmlCore loaded after the self-heal relaunch`. Updates that start from
`0.3.13.0` or later install every file, and the self-heal stays silent.

## Why the list endpoint (not `/releases/latest`)

GitHub's `/releases/latest` returns the latest **stable** release and skips
prereleases and drafts. Alpha releases used to be published as GitHub *prereleases*
(since 25.09.2026 every release is published as the current one). We read the list
endpoint and pick the highest version ourselves (`INCLUDE_PRERELEASES = true`).

## Version comparison

`UpdateChecker` implements a SemVer-precedence subset that handles the project's
`MAJOR.MINOR.PATCH.BUILD-prerelease` scheme (up to four numeric core fields):

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

The release job enforces the match: it fails right after checkout when the tag differs from
`config/version` (`.github/workflows/build.yml:354-360`). A tag ahead of `project.godot` would ship a
build that reports the old version, sees its own release as newer and offers the same update on
every start.

## Privacy

The check is a single unauthenticated `GET` to the public GitHub API. No telemetry,
identifiers, or game data are sent. Players can turn it off (persisted in
`user://update_check.cfg`, key `update_check/enabled`) or skip a specific version from
the prompt.

## Repointing at a self-hosted endpoint

If GitHub's unauthenticated rate limit (60 req/h per IP) ever becomes a concern, or you
prefer to serve version info from the existing asset host (see `scripts/asset_cdn.gd`), the
source is isolated to a few constants in `update_checker.gd`
(`RELEASES_API_URL`, `RELEASES_PAGE_URL`) and the response parsing in
`_on_request_completed()`/`_select_newest_release()`. Point those at a small
`version.json` and the rest of the flow (comparison, prompt, skip) is unchanged.
