# Spec: the save list and the lesson page of the main menu

Status: accepted, built in small steps. Two screens of the main menu replace engine windows: "Load game" opens a
list of the saves, "Learn to play" opens one page for both lesson tracks. "The mockup" below is the design
picture each screen is built towards.

**A. Save list - what the player sees.** "Load game" opens one sheet over the dimmed menu instead of the
engine's file browser: `min(1200, window width - 128)` x `min(780, window height - 120)`, centred, sheet box, scrim
as every menu window (the mockup blurs the scene; the game dims it - same call as for settings, no blur step).
- Header: eyebrow "LOAD GAME" (accent), title "Open a saved game" (30 px, weight 500), close box 32 px top right.
- One row per save file, newest first, 98 px high, 10 px apart, in a scroll box that scrolls inside the sheet:
  picture 150 x 78 (the save's biome picture, `TableSizeDialog.preview_path(biome)`, as the Continue card; no biome =
  no picture, the text moves left), name 22 px weight 500 (the file's base name, cut with an ellipsis), under it ONE
  mono line 14 px muted, upper case: system · round · biome · size ("GRIMDARK FUTURE · ROUND 1 · GRASSLAND · 6 x 4 FT";
  a fact the file does not hold is left out, a file that cannot be read shows no line), right the date
  "26 Nov 2026 · 07:31" (16 px muted, local time), then a "Load" button 130 px wide.
- The selected row (the first on opening; it follows keyboard focus and the pointer) has the accent fill at 10 %, a
  1 px gold rim, and its button is gold with an Enter cap; every other row's button is the plain button.
- Footer row: "<n> SAVES IN YOUR SAVES FOLDER" (mono, muted; "1 SAVE ..." for one) left; right "Open saves folder"
  and "Browse files…" (plain buttons). "Browse files…" opens exactly today's file dialog (any folder, `*.nml`).
- No saves: in place of the rows, centred, "No saved games yet." (body) and "Games you save at the table appear
  here." (caption); the footer reads "0 SAVES IN YOUR SAVES FOLDER" and keeps both buttons.
- Not on the sheet and not built: delete, rename, sort. Autosaves are listed like every other file, by file name.

**A. Data and where it comes from.** Everything is in the code today, only for one file:
`SaveManager.latest_save_info(dir)` (path, name, modified time) and `SaveManager.save_facts(path)` (system, round,
biome, size; parses the save's JSON, gives nothing above 8 MB or on a broken file); the folder is
`SaveManager.get_default_save_dir()` (`<user data>/saves`, also where the autosave slots `autosave_<n>.nml` live);
the two fact lines are built by the static `MenuView.facts_lines(info)`. New: `SaveManager.list_saves(dir_path := "")
-> Array[Dictionary]` - every `*.nml` of the folder as `{path, name, modified_unix}`, newest first, WITHOUT the facts
(listing must not parse every file). The sheet fills the facts one file per frame after it is open (`save_facts`
costs a JSON parse of up to 8 MB; fifty saves must not freeze the opening). The date: `Time.get_datetime_dict_from_unix_time`
gives UTC, so the sheet adds `Time.get_time_zone_from_system().bias * 60` first (the Continue card shows the UTC day
today - noted, not changed here).

**A. Modules.** New `scripts/save_browser.gd` (`class_name SaveBrowser`, a `Control` overlay with its own scrim, like
the modal settings sheet - not a `Window`, so it can fade with the family's 220 / 180 ms): `open(host: Node, dir := "")`,
signal `load_requested(path: String, button: Button)`, `closed`. It owns the file dialog (moved from
`startup_menu.gd` `_open_load_battle_dialog`, same settings, same pinned English labels). `startup_menu.gd` shrinks:
`_load_dialog` and `_open_load_battle_dialog` (24 lines) go, `_on_load_battle_pressed` opens the browser,
`load_requested` runs `_commit_beat(button)` and then today's `_on_load_file_selected(path)`. `main.gd` is not touched.

**A. MP, save, load.** Read-only on the save folder; the save format and the load path
(`niemandsland/pending_load_path` -> `main.gd`) do not change; a file outside the folder stays reachable through
"Browse files…"; the command-line `.nml` start does not pass the sheet. No network.

**A. Accessibility.** 1280x720: the sheet is 600 px high, rows are 78 px (picture 120 x 62, name 19 px) below 800 px
of window height, three rows show, the rest scrolls with `follow_focus`. Keyboard and controller: focus opens on the
first row's Load button; Up / Down walk the rows (the row with focus is the selected row), Tab goes on to "Open saves
folder", "Browse files…", the close box and back; Enter / `ui_accept` loads the focused row; Esc / `ui_cancel` closes
and returns focus to "Load game". Reduce Motion: no fade.

**B. Lesson page - what the player sees.** "Learn to play" opens a page in place of the menu's list (not
a window): the backdrop stays, the list, the footer links, the news card and the scene caption go, the wordmark stands
small (28 px, with a 250 px signature rule) top left, the version line stays at the bottom left.
- Left column, 470 px, from y = 150: the way back "‹ Main menu" with an Esc cap (16 px, muted), eyebrow "LEARN TO
  PLAY", title "Find your starting point." (44 px, weight 500), then two track cards (panel box, 20 px padding, 18 px
  apart), each: eyebrow; title 24 px weight 500; caption; a 4 px progress bar; a mono line "<done> / <total> LESSONS"
  left and "NEXT: <TITLE OF THE NEXT LESSON>" right; a full-width button.
  - Classic tutorial: eyebrow "CLASSIC TUTORIAL" (muted), "Learn the controls", "Camera, miniatures and tools, on a
    prepared table."; button "Start" with a chevron when nothing is done, "Continue with lesson <n>" otherwise, "All
    lessons done - pick one to replay" (disabled) when all are; it launches the tutorial in resume mode (today's
    `_launch_tutorial("")`: the first-timer's questions and the first open lesson are the director's own logic).
  - Trial by Fire: eyebrow "TRIAL BY FIRE · IN DEVELOPMENT" (accent), "Short practice scenarios", "Eleven short
    lessons — play them in any order, replay any time."; the same three button states; it launches the first lesson
    that is not done and can be played.
  - Exactly one track is the selected one: gold rim, gold corner brackets, "NEXT: ..." in gold, its button gold with
    an Enter cap. On opening: Trial by Fire when any of its lessons is done or the page was opened by a return from a
    lesson (`niemandsland/open_game_school`), else the classic tutorial. A click on a card (or focus on its button)
    selects it.
- Right panel, from x = 640 to 64 px before the right edge: eyebrow = the selected track's name, title "Pick a
  lesson" (22 px), right "Everything stays replayable" (15 px muted); below it the selected track's lessons as cards,
  four in a row, 150 px high, 12 px apart: the position in mono 14 px ("01" ... "11"; with a drawn tick in the OK
  colour when done - an icon, not a glyph: the mono font's coverage of U+2713 is not proven), the title 19 px
  weight 500, the one-line goal 15 px muted (Trial by Fire has one per lesson; the classic lessons have none and show
  none), and a state line at the bottom: "Done · replay", or "Next lesson" in gold on the one next lesson (that card
  has the gold rim and the lighter fill), or nothing; a lesson without a bundled scenario is disabled with the tag
  "Coming soon". The last Trial by Fire card spans two columns, reads "11 · FINALE", has the gold wash from the left
  and the tag "Finale". A click on a card launches that lesson (classic: `_launch_tutorial(id)`; Trial:
  `_launch_scenario(chapter)`).
- Under the cards, only while the classic track is selected: "Reset tutorial progress" (danger text button, right
  aligned; today's function and behaviour, the page redraws after it).
- Deviations from the mockup, on purpose: (1) the mockup's foot line "Lesson numbers replace the working codes (S-01 …
  S-SPELL) ..." is a note to the reviewer and would itself show working codes - not built; (2) the mockup draws only
  the Trial grid; the classic track's lessons use the same grid when that track is selected, and the reset link
  stands in the foot line's place, so no function of today's picker is lost; (3) titles keep the data's spelling
  ("First Steps", "Build the Table" - the mockup has "First steps", "Build the table"): the same strings are the
  lesson card's title at the table and are pinned by ten suites; the case change is a text-only PR for the lead to
  order, not part of these steps; (4) numbers are the position in the list, so Spellcasting is 09, Mission Objectives
  10 and the finale 11 as drawn (today's `lesson_number` reads the digits of the code and gives 00, 09 and 10).

**B. Data and where it comes from.** Classic track: `TutorialFlow.build_tool_track()` (11 lessons `{id, title,
steps}`), `TutorialProgress` (`load_from_disk`, `is_lesson_completed`, `completed_count`, `first_incomplete`,
`reset`). Trial by Fire: `Spielschule.chapters()` (11 chapters `{id, title, goal, scenario}`),
`Spielschule.is_available`, `SpielschuleProgress` (`is_completed`, `completed_count`). Launching:
`startup_menu.gd` `_launch_tutorial(lesson_id)` and `_launch_scenario(chapter)` (runtime-only project settings read
by `main.gd`; unchanged). The return from a lesson: `niemandsland/open_game_school`, read in `_ready`. No id changes
in data, progress files or saves.

**B. Modules.** New `scripts/menu_page.gd` (`class_name MenuPage`, a `Control`): the page skeleton both this page and
the online hub use - small wordmark with its rule, the way back (emits `closed`; handles Esc / `ui_cancel`
itself in `_unhandled_key_input`), eyebrow, title, a `left: VBoxContainer` and a `right: PanelContainer`; `_layout`
places them (left = the menu's left margin, column width a parameter: 470 here, 520 for the hub). `MenuView` gets
`open_page(page)` / `close_page()`: hides `_masthead`, `_scroll`, `_footer`, `news_card`, `status`, adds the page
full-rect, remembers and restores focus; and loses the "learn" route (two rows). New `scripts/learn_page.gd`
(`class_name LearnPage extends MenuPage`): the two track cards and the grid; signals `tutorial_requested(lesson_id)`,
`scenario_requested(chapter)`. `startup_menu.gd` shrinks by about 140 lines: `_show_tutorial_picker` (55),
`_on_spielschule_pressed` (43), `_add_chapter_row` (30), `lesson_number` (8), `TRIAL_LABEL_WIDTH`, `TRIAL_LIST_MIN`,
`tutorial_btn`, `spielschule_btn`; `_on_tutorial_pressed` (the Help route's "Learn the controls") opens the page.
`main.gd` is not touched.

**B. MP, save, load.** None: local progress files only; "Reset tutorial progress" is the one write and exists today.

**B. Accessibility.** The page never grows past the window: below 800 px of window height the track captions hide
and the card padding is 14; the left column and the grid each scroll inside (`follow_focus`). Columns of the grid:
four from 1,150 px of panel width, three from 860, two below (1280x720: two; the finale card spans two everywhere).
Focus order: way back, the two track buttons, then the cards row by row (arrow keys move inside the grid by the
engine's neighbour search), then the reset link; Enter launches; Esc returns to the menu with focus on "Learn to play".

