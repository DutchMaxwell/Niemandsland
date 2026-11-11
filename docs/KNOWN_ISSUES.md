# Known Issues & Limitations — Alpha

Niemandsland is an **alpha**. This is the honest, player-facing list of what is intentionally
not there yet and what to watch for. The full done / in-progress / planned breakdown is in
[`../PROJECT_STATUS.md`](../PROJECT_STATUS.md); the forward-looking plan is in
[`ROADMAP.md`](ROADMAP.md).

## By design (not bugs)

- **Per table: Automatic or Manual.** Set to **Automatic**, the simulator **decides** — it
  resolves activations, dice, wounds, morale, terrain effects and the modelled special rules for
  **both** sides, online as well as local: one unit per side in turn, the host owns the turn, and
  each player rolls their own dice on their own tray. Set to **Manual**, it **shows, it does not
  decide** — ranges, coherency, movement bands and unit state are presented, but turns, shooting,
  melee and morale are yours to call, and **terrain has no gameplay effect** there (visual +
  line-of-sight only) — though since `0.3.12` the measure tool's own LOS verdict is volumetric and
  height-aware in every mode. In a room the two players agree on the level (one asks, the other
  confirms); either can drop back to Manual at once.
- **Some rules still stay by hand.** Even on Automatic, the rules the game lists at start under
  "apply by hand" are yours — and the ones that say "may" (Teleport/Ethereal movement, Hit & Run,
  Guerrilla/Harassing) are deliberately left to you for now. In an online Automatic room the turn
  is enforced on each machine, and the host refuses an out-of-turn activation message (an out-of-turn
  drag snaps back). The battle log names every rule
  it applies — or asks you to apply it.
- **Solo against NACHTMAHR is the automated baseline.** When an army is AI-controlled the game
  resolves activations, dice, wounds, morale, terrain effects and hundreds of special rules for
  both sides (see [`../PROJECT_STATUS.md`](../PROJECT_STATUS.md)). Solo is **alpha**: four selectable difficulty grades
  (Dämmerung, Zwielicht, Finsternis, Albtraum; Albtraum is the default), co-op against the AI in multiplayer is a first version, and the UI is English
  (the privacy & data screens also come in German).
- **Automodus (Charge / Advance & Shoot / Rush) is switched off in this version.** The radial does not
  offer the three verbs while their move preview and target selection are reworked (issue #1828);
  move and attack by hand (the radial's Shoot / Fight, or drag). NACHTMAHR's own activations are
  unaffected.
- **Rules 3.6 for Grimdark Future and Age of Fantasy only.** Firefight, Skirmish and Regiments still
  play rules 3.5.1. Army Forge serves their 3.6 books, which import with a warning that names both
  versions; a save, or a player in an online room, on other rules is refused.
- **AI thinking time has been measured on one machine only** (a developer laptop). On a slower PC
  the opponent may take longer per decision — if it feels slow, send a diagnostics report (below);
  its header names which AI path your machine ran.
- **OPR army data is loaded live, not bundled.** Army import calls the **Army Forge API** at
  runtime — you need an internet connection to import, and stats are never redistributed.
- **3D models are delivered on demand.** The first time you use a faction, its models download
  from the asset CDN (cached afterwards). First import of a new faction needs internet and a
  moment to fetch. Generated minis are **base-less** (the app makes the base) and licensed
  **CC-BY-SA**.
- **The biome dresses the table only on Medium and above.** The biome you pick before the match
  sets the ground, light and trees of the table on the Medium, High and Ultra graphics presets;
  Performance, Low and the Compatibility renderer keep the plain battlemap. Display only — line of
  sight and rules are never affected.

## Multiplayer

- **Both players must run the same version.** The version handshake is exact — a host and guest
  on different builds won't connect. The first log line `[Boot] Niemandsland <version> build
  <hash>` tells you exactly which build you're on.
- **Built and validated for 2 players.** 3+ players may work but isn't hardened for this Alpha.
- **Automodus online (once switched back on, see above).** In an agreed Automatic room the player whose
  turn it is runs the verb on their own machine; only that player sees the landing preview, the other
  player sees the move and rolls their own saves. A two-machine test covers Advance & Shoot only.
- **Reconnect after a drop isn't seamless yet.** If a guest loses connection mid-game, the
  cleanest recovery is to rejoin the room. The deep reconnect-sync issues are fixed (no more
  "reconnected but nothing syncs"); fully *graceful* guest reconnect is post-Alpha.
- **Online rules automation after the host's connection drops (#1887, #1886).** Right after the
  host's link comes back, a question the host stopped waiting for can stay open on the other screen;
  close it with ×. A fix is planned. (The spell that was cast without asking for interference after a
  rejoin is fixed on main, #1890.)
- **Import while a guest is mid-join** was a source of missing/duplicated models — fixed; if you
  ever see it, send a diagnostics report (below).

## Platforms

- **Windows, Linux and macOS** builds ship with every release.
- **macOS is ad-hoc signed but not notarized** (no Apple Developer account): first launch needs
  **right-click → Open**, or the one-time `xattr -dr com.apple.quarantine` fallback — see the
  README's macOS note. The in-browser (web) build is parked (post-Alpha).
- **macOS: the rules core is verified on GitHub's macOS runners only.** Like Windows and Linux, the
  macOS build carries the Rust rules core (a universal arm64 + x86_64 library inside the app), so
  NACHTMAHR plays with Erlkönig. The release build proves on a macOS runner that the exported app
  loads the core and plays; no person has tried it on a real Mac yet. If the start line or the
  diagnostics report names the decision tree on your Mac, the core did not load — please report it.
- **Windows: an in-game update from 0.3.12.0 restarts the game once.** The 0.3.12.0 updater
  replaces only `Niemandsland.exe`; on its first start 0.3.13.0 copies the missing rules-core file
  (`nml_core_godot.dll`) from the downloaded update next to the game and restarts once by itself.
  If the diagnostics report (below) still names the decision tree after that, download the 0.3.13.0
  Windows zip and unzip it over your game folder. Updates from 0.3.13.0 onward install every file.
- **Windows: from 0.3.12.0 or older, download the 0.3.15.0 zip by hand once.** Since 0.3.15.0 the game
  data ships as `Niemandsland.pck` next to `Niemandsland.exe`, and the in-game updater of 0.3.12.0 and
  older replaces only the executable. Unzip the Windows zip over your game folder; keep
  `Niemandsland.pck` and `nml_core_godot.dll` beside the executable. From 0.3.13.0 on, the in-game
  update installs every file.

## Smaller things to know

- **Walker orientation** on oval bases is decided by the unit **name** containing "Walker" (the
  only signal available at runtime). A walker-type unit named otherwise won't be auto-oriented
  crosswise — tell us the name and we'll extend it.
- **Auto buff-tokens** from special rules use a curated list + a heuristic (auras / buffs /
  `+1`-`-1` / re-rolls). It won't catch every faction's custom rule; missed ones are a one-line map
  addition.
- **Large armies** can briefly hitch on first import while each new model is parsed (cached after).

## Found a bug? Send us a report

- **In-game:** Press **`F12`** to grab a screenshot and bundle it with the anonymised log into a
  zip on your Desktop — attach it when you file the issue. Useful for visual glitches that never
  appear in the log.
- **Start menu:** Use **Help & feedback → Report a problem** to export an anonymised diagnostics bundle (version +
  OS/GPU/CPU + which AI path ran + recent log — **no** username, player names or room codes).
- **GitHub:** [Open an issue](../../../issues/new/choose) using the Bug report or Feedback template.

That's the fastest way to get something fixed.
