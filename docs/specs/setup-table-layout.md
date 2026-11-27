# Spec: step 04 of the table setup, "Lay out the table"

Status: accepted, built in small steps. The table setup of the main menu gains a fourth step that lays out the
terrain before the table is created. "The mockup" below is the design picture the step is built towards.

**What the player sees.** The setup page has two states: the first with steps 01-03 open, the second with steps 01-03
folded and step 04 open.
- State one gains one row at the foot of the left column, in the place of the block "+ Your terrain. Your layout. /
  Place and rearrange terrain freely ..." (which goes - step 04 says it): "04  Lay out the table", at its right the
  chosen way's name ("Empty table", "Auto-generated", "Ruined Borderland", "Loaded layout") and "Change" in accent -
  the look of the folded rows of the second mockup without the tick. A press (or Tab past the size cards and Enter) opens
  state two. "Create table" works in both states and uses the way the row names.
- State two, left column (1,040 px at 1920): three folded rows, 52 px, 8 px apart - "01 ✓" in mono in the OK colour
  (the tick drawn), the step's name muted ("Game system", "Biome", "Table size"), its value at the right ("Grimdark
  Future", "Urban ruins", "72 × 48 in"), "Change" in accent (back to state one with the focus in that step). Then the
  heading "04  Lay out the table" (number in mono gold, 22 px weight 500) with "Terrain can still be moved at the
  table." at its right (15 px muted).
- Four way cards in one row (min height 196, 12 px apart; icon 28 px accent, name 20 px weight 500, caption 15 px
  muted; the chosen one with the lighter fill and the 2 px gold rim):
  1. "Empty table" - "Place terrain yourself once you are at the table."
  2. "Auto-Generate Layout" - "A balanced layout for this table size. Generate again until you like it."
  3. "Ruined Borderland" - "A ready-made table: evening light, 14 pieces." (count and mood read from the theme file;
     the mockup also says "grassland", but the theme names no biome and is laid in the table's biome - the word is
     left out rather than shown wrong), foot line in mono "NEEDS 6 × 4 FT"; on any other size the card is disabled.
  4. "Load a layout" - "Open a layout file you saved in the layout editor." A press opens a file dialog (`*.json`,
     title "Load Terrain Layout"); a file made for another table size is refused with one line under the cards
     ("This layout is for a 4 × 4 ft table.") and the way does not change.
- A tools card under them: "Generate again" with the circular-arrow icon (enabled on way 2 only), the switch "Point
  Symmetry (Mirror)" (way 2 only; switching it generates again), and at the right "Edit in the layout editor ›" -
  it opens today's layout editor over the setup, with whatever the chosen way has laid out; its Close returns to
  step 04 and the way's name reads "Edited layout". The editor's own "Ruined Borderland" entry chooses way 3 and
  closes; its game-system row is locked ("Chosen in step 01").
- Two cards side by side: "DEPLOYMENT ZONES" with the segment row "None | Front Line (12") | Custom Zones" (the
  editor's own three types; "Custom Zones" opens the editor on its deployment tab, because zones are drawn there);
  "MISSION OBJECTIVES" with "No objectives placed" / "<n> objectives placed" and "Deploy Objectives" (opens the
  editor in its objectives mode).
- The rail (684 px, panel box with brackets): on top the picture of the layout, 456 px high - a top-down drawing in
  the editor's colours on a 3-inch grid, deployment bands and objective marks included, with the tagline "TOP-DOWN ·
  6 × 4 FT · 3 IN GRID" (the mockup's "· THE EDITOR'S OWN PICTURE" is a note to the reviewer and is left out); for
  way 1 the bare grid, for way 3 the theme's picture (`res://assets/whats_new/borderland.webp`). Below: the legend
  with counts ("Ruins 5", "Forest 6", "Container 4", "Dangerous 2"); the mono line "17 PIECES · COVERAGE 12.2 %"; the
  editor's first two guideline lines exactly as the editor prints them, a failing one in the warn colour with a
  cross ("15-20 terrain pieces (have: 17)", "At least 25% table coverage (12.2%)") - shown for ways 2 and 4 and an
  edited layout, not for ways 1 and 3; three rows "SYSTEM", "BIOME · SIZE", "LAYOUT" ("Auto-generated · Front Line
  (12")"); and the gold "Create table" with its Enter cap, full width, 56 px.
- Key legend at the foot: Tab next step · ← → choose · G generate again · Enter create table · Esc back.

**Data and where it comes from.** The layout editor is its own scene (`scenes/map_layout.tscn`, script without a class
name) and holds everything: the generator (`_on_autogen_pressed` -> `_generate_terrain_layout`, unseeded, 15-20
pieces on 6 x 4 ft scaled by area), `point_symmetry_enabled`, `deployment_type` (enum `DeploymentType` NONE /
FRONT_LINE / CUSTOM), `mission_objectives`, `grid_cells` (cell -> type) with `TERRAIN_COLORS`, `_count_terrain_pieces()`,
the guideline text (`recommendations_label.text`, lines starting with the tick or the cross), `set_table_size`,
`set_game_system(id, locked_reason)`, `save_layout(path)` / `load_layout(path)` (JSON 1.5, carries the table size),
`layout_closed`, `theme_requested`. The ready-made table: `TableTheme.load_theme("ruined_borderland")` (`fits(size)`,
`pieces.size()`, `mood`); at the table `main.apply_table_theme(id)`.
**Point (b), answered by reading:** the scene does not need the table - its only look outside itself is
`get_node_or_null("/root/Main")` in `_table_system()`, which returns "" without a main scene, and eleven test suites
already instance it alone (`map_layout_*_test.gd`). The first test of the layout behind the step is the probe that proves it in the engine
(instance under a plain node, set the size, generate, save, load back). The fallback stays written down: if that
test cannot be made green in two tries, the four ways and the rail stay as specified with the facts taken from the
saved file, and "Edit in the layout editor" opens the editor at the table right after arrival.

**The carrier (point a).** New project setting `niemandsland/pending_table_layout` beside `pending_table_setup`
(which `main.gd` reads and clears itself; it is not changed): `{}` for the empty table, `{"theme": "ruined_borderland"}`,
or `{"path": "user://pending_layout.json"}` - the file is written by the setup with the editor's own `save_layout`.
At the table the reveal gate (mode "new") applies it one frame after `Table.table_resized` (so `_set_table_size` has
finished clearing the editor and the overlay): a path goes through `main.map_layout_editor.load_layout(path)` and
then the editor's `_on_close_pressed()` - the exact path a player's own "load, then close" takes today, so the 3D
build, the objectives, the deployment zones, undo and the broadcast to other players run through today's code; a
theme goes through `main.apply_table_theme(id)`. Then the setting is cleared, the file deleted, and the gate ticks
"Table" and "Terrain" - the loading picture's stage "Terrain" now waits for real work.

**Modules (new scripts; `table_size_dialog.gd` grows by one flag, one row and the state switch).**
- `scripts/pending_layout.gd` (`class_name PendingLayout`): `static store(choice: Dictionary)`,
  `static apply(main: Node) -> bool`.
- `scripts/setup_layout.gd` (`class_name SetupLayout`, a `Node`): owns one hidden instance of the editor scene; the
  only script that touches the editor from the menu. `set_table(size_feet, system_id)`, `choose(way)`, `generate()`,
  `set_mirror(on)`, `set_deployment(type)`, `load_file(path) -> String` (error text or ""), `open_editor(mode)`,
  `facts() -> Dictionary` (`{pieces_by_type, pieces, coverage_pct, lines: [{ok, text}], objectives, deployment}`),
  `label()`, `commit()` (saves the file when the way needs one and calls `PendingLayout.store`), signal `changed`.
  `const DEFAULT_WAY`.
- `scripts/layout_preview.gd` (`class_name LayoutPreview`, a `Control`): draws from a `SetupLayout`; redraws on `changed`.
- `scripts/setup_layout_step.gd` (`class_name SetupLayoutStep`, a `Control`): state two's body - folded rows, way
  cards, tools, the two cards, the rail; signals `change_requested(step)`, `create_requested`.
- `table_size_dialog.gd`: `var layout_step := false` (the menu sets it before `add_child`, like `online`; the table's
  own direct chooser keeps today's page), the row of state one, `_show_state(two: bool)` (hides `_columns` and the
  footer's summary, shows the step; `_layout` skips `_fill_height` in state two), and `layout: SetupLayout`.
  `startup_menu.gd` `_on_table_setup_chosen`: one line, `_table_setup.layout.commit()` when the flag is set.
- `table_reveal_gate.gd`: three lines in mode "new".

**Point (d): what a way does when size or system rules it out.** Way 3 is disabled off 6 x 4 ft; if it was chosen and
the size changes, the choice falls back to `DEFAULT_WAY` and the row of state one says so by its new name. A change
of table size clears a generated layout (`set_table_size` does that) and generates again; a loaded or edited layout
is dropped with the line "The layout was made for another table size." under the cards. A game system with a
generated board gets a fifth card in the same row - the slot is kept (the four cards are a container that takes a
fifth), the entry itself belongs to the later work on generated boards. The editor's type
names follow the system (`set_game_system`).

**Point (e): what step 04 starts on.** The maintainer chose "Auto-Generate Layout". It is the constant `SetupLayout.DEFAULT_WAY`; the
steps build with "empty" (today's behaviour) and the last step flips it, because of point (g).

**Point (g): the generator against the editor's own guideline.** One press of the generator covers at most 13.2 % of a
6 x 4 ft table; the editor's line asks for 25 %, so on the default way the rail would greet every new table with a
failed line of the game's own check. Decided: the guideline is right (it is the rulebook's terrain advice) - the
generator's piece list is raised until a generated 6 x 4 ft table reaches 25 % before the default flips to
"Auto-Generate Layout". Until then the step exists, the default is the empty table, and the rail prints the editor's
lines as they are.

**MP, save, load.** A host's setup ("Create a room") has step 04 too; the layout is on the host's table before a
guest joins and reaches guests in the host's first state, as any terrain laid at the table does (no new message). A
guest never sees the setup. Saves hold the terrain as today; the pending file is not a save and is deleted when
applied (a leftover from a crashed start is overwritten by the next setup and ignored without the setting). A loaded
game and a join never apply a pending layout (the gate applies in mode "new" only). Way 3 at the table shows today's
toast ("Ruined Borderland laid out - Ctrl+Z puts the old table back") and is one undo step, as from the editor.

**Accessibility.** State two must fit 1280x720 without scrolling (the page's standing rule): below 800 px of window
height the folded rows are 38 px, the way cards 112 px without their captions (name and icon in one line; the foot
line stays), the tools card and the two lower cards 52 px, the rail's picture is as high as the space leaves (at
least 200 px) and the legend and the facts share one line. Keys: Tab walks the folded rows' "Change", the four cards
(one stop; ← → choose inside, as the system cards of step 01), Generate again, the switch, Edit, the segments, Deploy
Objectives, Create table; G generates again whenever way 2 is chosen and no text field has focus; Enter creates the
table; Esc goes back to state one, and from state one to the menu. The editor opened from the setup keeps its own
keys and returns the focus to "Edit in the layout editor".

