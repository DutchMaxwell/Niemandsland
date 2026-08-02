# Getting Started with Niemandsland

Niemandsland is a 3D tabletop sandbox for [OnePageRules](https://onepagerules.com/) miniature games (Grimdark Future, Age of Fantasy, and related systems). Between two human players it follows a **"show, don't decide"** design philosophy: it presents ranges, coherency, and unit state on the table; it does not enforce rules or automate turns. **The exception is solo play against the built-in AI opponent, NACHTMAHR** — that mode *does* resolve activations, dice, shooting, melee, morale, spells, terrain effects and hundreds of special rules for both sides (see [Play solo vs NACHTMAHR](#play-solo-vs-nachtmahr)).

---

## Install and launch

**Windows**

1. Download the latest release from the [Releases](../../releases) page.
2. Unzip the archive.
3. Run `Niemandsland.exe` — no installer needed.

**Linux**

1. Download and unzip the release.
2. Make the binary executable if needed: `chmod +x Niemandsland.x86_64`
3. Run `./Niemandsland.x86_64` (the `.pck` file must stay in the same directory).

The start menu shows the version number. The first line of the log reads `[Boot] Niemandsland <version> build <hash>` — use this when reporting bugs.

---

## First steps

### Start a game

From the start menu, choose **Start New Battle** to open the 3D sandbox. Pick a table size (6×4 ft default) and a map layout, or generate one automatically.

The table opens in the **Deployment** phase — place your army, then press **Start Game** (left panel) to begin play. In multiplayer both players signal ready and the host starts once both are. During play, dragging a model paints a measured **move trail** (`T` hides / `Shift`+`T` clears); an optional *Enforce Movement Limit* setting stops the drag at the model's Advance/Rush-Charge band.

The game **autosaves** every 5 minutes and at every round change into three rotating slots; **CONTINUE** on the start menu reloads the newest one.

### Play solo vs NACHTMAHR

To play a full game against the built-in AI opponent:

1. Give NACHTMAHR an army — either **import a second list** and tick **AI-controlled (Solo)**, or press **AI Opponent** and let NACHTMAHR bring one of its own pre-built lists (pick a faction and 1000–3000 pts; the list is fetched from the asset CDN and cached for offline play).
2. Follow the **guided deployment**: a roll-off decides who picks a table edge and deploys first, then both sides place units alternately with explicit hand-over clicks (Scout, Ambush and Infiltrate reserves are handled for you).
3. On **Start Game**, play alternates unit by unit. You act through the **radial menu** — **Shoot**, **Fight**, **Cast** — with real dice in the tray for both sides; NACHTMAHR takes its own activations, and **every applied rule writes a battle-log line** so you can follow (and audit) each decision. The thirteen rules the automation does not cover yet are named per unit in the log for you to apply by hand.

NACHTMAHR is a rules-based, deterministic game AI (no LLM, no neural net) that runs entirely offline and never cheats. One difficulty ships (full strength); see [`KNOWN_ISSUES.md`](KNOWN_ISSUES.md) for the solo caveats.

### Camera

| Action | Control |
|---|---|
| Rotate | Right-drag |
| Pan | Middle-drag |
| Zoom | Mouse wheel |

### Select and move objects

| Action | Control |
|---|---|
| Select | Left-click |
| Add to selection | `Alt`+Left-click |
| Box select | Left-drag on the table |
| Move | Left-drag the selected object |
| Rotate | `R` |
| Delete | `Del` / `Backspace` |
| Copy / Paste / Duplicate | `Ctrl`+`C` / `V` / `D` |
| Take back the last finished move | `Ctrl`+`Z` (until dice roll / next activation) |
| Arrange selected (rows) | `1`–`9` |
| Arrange selected (arrow) | `A` |

### Measuring and display aids

| Action | Control |
|---|---|
| Range rings (3″ / 6″ / … / 24″) | `G` — cycles; `Shift`+`G` clears |
| Movement reach (Advance + Rush/Charge bands) | `M` — toggles |
| Pin a ruler on the table | `P` — persists for all players; `K` clears yours; `Shift`+`K` clears all |

### Dice

Press `Space` to roll physics D6 dice. Results appear in the shared dice log (visible to all players in multiplayer).

For the full control reference, see the **Controls** section in [`README.md`](../README.md).

---

## Import an army

1. Open your army list in [Army Forge](https://army-forge.onepagerules.com/) and copy the share link.
2. In Niemandsland, choose **Import Army** from the menu and paste the link.
3. The game fetches the list via the OPR API and downloads the faction's 3D models from the asset CDN on first use (internet required; cached afterwards).

Each model appears on the table with its base size, wound counter, and status tokens. Units show coherency indicators and a docked info card.

---

## Multiplayer

Multiplayer supports **2 players** over LAN or the internet. Both players must run the **same version** — the version handshake will reject a mismatch.

**Host a game**

1. Choose **Host** from the start menu.
2. Share your **room code** with the other player (or make the room public so it appears in the room browser).

**Join a game**

- Enter the host's room code and click **Join**, or
- Open the **Room Browser** to see listed public rooms and join by clicking.

State (models, terrain, dice) syncs automatically. Player names, cursors, and avatars are visible to both sides.

---

## Reporting a bug

- **In-game:** Press `F12` to capture a screenshot and bundle it with the anonymised log into a zip on your Desktop — attach it to a bug report.
- **Start menu:** Use **"Report a problem"** to export a scrubbed diagnostic bundle.
- **GitHub:** [Open an issue](../../issues/new/choose) using the Bug report template.

For known limitations and alpha caveats, see [`docs/KNOWN_ISSUES.md`](KNOWN_ISSUES.md).
