# Spec: step 04 of the table setup, "Who is at the table?"

Status: accepted, built in small steps. The opponent is chosen in the table setup of the main menu, before the table
exists; the table's own AI Opponent dialog goes, with no twin. "The mockup" below is the design picture the step is
built towards. "Lay out the table" (spec `setup-table-layout.md`) becomes step 05.

**What the player sees.** The setup has three states.
- State one: steps 01-03 open, and at their foot two rows: "04  Who is at the table?" (its value, e.g.
  "NACHTMAHR · Alien Hives · 3000", and "Change") and "05  Lay out the table". The summary above Create table gains
  "Opponent" (hidden below 800 px of height, where row 04 already names it).
- The "who" page: steps 01-03 folded into rows with "Change", the heading "04  Who is at the table?" (number in mono
  gold) and three cards in one row, the chosen one with the lighter fill and the 2 px gold rim:
  1. "Solo against NACHTMAHR" - "The computer opponent builds its own list and plays by the rules."
  2. "Two players, one screen" - "Share this computer and take turns like at a real table."
  3. "Online room" - "Create a room for your group and share the invitation code."
  Only for Solo, one card with three dropdowns under the eyebrows FACTION, POINTS, AI PLAYS AS. Under it the row
  "05  Lay out the table · <way> · Change", which opens the layout page. At the right the rail YOUR TABLE with SYSTEM,
  BIOME, SIZE, OPPONENT, the gold "Create table" with the Enter cap, and "Next at the table: bring your own army, then
  deploy."
- The layout page gains a fourth folded row "04 Opponent <value> Change" (it opens the who page); its heading number
  is 05. "Create table" works in all three states; Esc from either inner page returns to state one.

**Values.** OPPONENT reads "NACHTMAHR · <faction> · <points>", "Two players, one screen" or "Online room". The
factions are the AI-list manifest's factions of exactly the game system picked in step 01, sorted; a change of
system refills them and keeps the faction while it is still offered. Points are that faction's brackets as
"<n> points", the largest by default unless a remembered pick exists. AI plays as "Player 2 (Red)" (default) or
"Player 1 (Blue)". The default card is the remembered one, else Solo; opened from the online hub it is Online room.
Solo is off, with one muted line in the card's place, while the lists load ("Loading NACHTMAHR's lists ..."),
without a manifest ("NACHTMAHR's lists need a connection the first time.") or when the system has no list ("No
NACHTMAHR lists for <system> yet."); the choice then falls to "Two players, one screen". There is no points
preselect from the mission or the player's army (the setup knows neither); the Solo panel's advice line stays.

**At the table.** The choice travels as `niemandsland/pending_table_opponent` (`PendingOpponent`, the pattern of
`PendingLayout`): {who, file, slot, label}. On a new table the reveal gate, after the layout, starts the table's list
loader for Solo without waiting (the table shows first, the list arrives with its toast). Without the core nothing
is loaded and the core's own line is logged. A load and a join clear the pending choice.
- The arrival card's line 2, offline: Solo reads "NACHTMAHR brings <faction>" and is done once NACHTMAHR's army
  stands (a press loads it again if it did not arrive); two players read "Bring the second army", which opens the
  army import on Player 2. Line 1 is done with an army in a seat that is not NACHTMAHR's. Online: unchanged.
- "Online room" picked from "Start battle" is a private room on the default relay under the saved player name; a
  public table and another relay stay the online hub's. The hub's settings travel only if Online room is still chosen
  at Create. Online room locks the rules automation pick to Manual; the other two cards free it.
- A table for a different opponent is a new table. At the table, any imported list can still be handed to NACHTMAHR
  (the import's "AI-controlled (Solo)" box, the Solo panel's toggle). The table's direct chooser (a developer entry)
  has neither step 04 nor step 05.

**Where the lists come from.** `AiLists` is the one owner: the dev bundle, the user cache of earlier downloads and
the asset CDN. The menu reads the manifest; the table reads the list. No test contacts the CDN.

**Remembered.** The menu config (`user://menu.cfg`, section "menu") keeps `opponent_who`, `opponent_faction`,
`opponent_points` and `opponent_seat`; unknown values read as the defaults, and a faction or bracket the manifest no
longer offers falls back silently.
