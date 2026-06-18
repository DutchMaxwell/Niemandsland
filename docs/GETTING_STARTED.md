# Getting Started with Niemandsland

Niemandsland is a 3D tabletop sandbox for [OnePageRules](https://onepagerules.com/) miniature games (Grimdark Future, Age of Fantasy, and related systems). It follows a **"show, don't decide"** design philosophy: it presents ranges, coherency, and unit state on the table; it does not enforce rules or automate turns.

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

From the start menu, choose **Start New Battle** to open the 3D sandbox. Pick a table size (4×4 ft default) and a map layout, or generate one automatically.

### Camera

| Action | Control |
|---|---|
| Rotate | Right-drag |
| Pan | Middle-drag |
| Zoom | Mouse wheel |
| Reset | `Home` |

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
