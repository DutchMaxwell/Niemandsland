# Known Issues & Limitations — Alpha

Niemandsland is an **alpha**. This is the honest, player-facing list of what is intentionally
not there yet and what to watch for. The full done / in-progress / planned breakdown is in
[`../PROJECT_STATUS.md`](../PROJECT_STATUS.md); the release plan is in
[`ROAD_TO_ALPHA.md`](ROAD_TO_ALPHA.md).

## By design (not bugs)

- **No rules automation.** The simulator **shows, it does not decide.** It presents ranges,
  coherency, movement bands and unit state, but it does **not** resolve turns, shooting, melee
  or morale, and **terrain has no gameplay effect** (it's visual + line-of-sight only). You play
  the game; the table assists.
- **OPR army data is loaded live, not bundled.** Army import calls the **Army Forge API** at
  runtime — you need an internet connection to import, and stats are never redistributed.
- **3D models are delivered on demand.** The first time you use a faction, its models download
  from the asset CDN (cached afterwards). First import of a new faction needs internet and a
  moment to fetch. Generated minis are **base-less** (the app makes the base) and licensed
  **CC-BY-SA**.

## Multiplayer

- **Both players must run the same version.** The version handshake is exact — a host and guest
  on different builds won't connect. The first log line `[Boot] Niemandsland <version> build
  <hash>` tells you exactly which build you're on.
- **Built and validated for 2 players.** 3+ players may work but isn't hardened for this Alpha.
- **Reconnect after a drop isn't seamless yet.** If a guest loses connection mid-game, the
  cleanest recovery is to rejoin the room. The deep reconnect-sync issues are fixed (no more
  "reconnected but nothing syncs"); fully *graceful* guest reconnect is post-Alpha.
- **Import while a guest is mid-join** was a source of missing/duplicated models — fixed; if you
  ever see it, send a diagnostics report (below).

## Platforms

- **Windows and Linux** are the supported Alpha targets.
- **macOS and the in-browser (web) build are post-Alpha.** A macOS export preset exists but is
  untested/unsigned (expect Gatekeeper friction); the web build is parked.

## Smaller things to know

- **Walker orientation** on oval bases is decided by the unit **name** containing "Walker" (the
  only signal available at runtime). A walker-type unit named otherwise won't be auto-oriented
  crosswise — tell us the name and we'll extend it.
- **Auto buff-tokens** from special rules use a curated list + a heuristic (auras / buffs /
  `+1`-`-1` / re-rolls). It won't catch every faction's custom rule; missed ones are a one-line map
  addition.
- **Large armies** can briefly hitch on first import while each new model is parsed (cached after).

## Found a bug? Send us a report

Use **"Report a problem"** in the start menu. It writes an **anonymised** diagnostics bundle
(version + build hash + OS/GPU + recent log + MP error counts — **no** username, player names or
room codes) and opens the folder, so you can attach it to a [GitHub
issue](../../issues/new/choose). That's the fastest way to get something fixed.
