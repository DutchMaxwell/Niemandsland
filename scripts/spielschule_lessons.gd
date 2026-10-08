class_name SpielschuleLessons
extends RefCounted
## Static lesson data for Game School chapters: the ordered lesson steps (text + completion check)
## and the AI behaviour mode for a chapter's table. See scripts/lesson_checks.gd for check names and
## scripts/lesson_runner.gd for how a chapter's steps are driven.

## Step shape: {id: String, text: String, rule: String ("p.5" or ""), all: Array} — `all` is the
## LessonChecks.passes() check list that completes this step.
const _S01_STEPS := [
	{"id": "camera_turn", "text": "Hold the right mouse button and drag to turn the camera.",
		"rule": "", "all": [{"check": "camera_turned", "args": {"deg": 20}}]},
	{"id": "camera_zoom", "text": "Roll the mouse wheel to zoom in or out.",
		"rule": "", "all": [{"check": "camera_zoomed", "args": {"ratio": 0.18}}]},
	{"id": "camera_pan", "text": "Press W, A, S or D to slide across the table.",
		"rule": "", "all": [{"check": "camera_panned", "args": {"m": 0.15}}]},
	{"id": "select_whole", "text": "Double-click one of your models: the whole squad is selected.",
		"rule": "", "all": [{"check": "unit_selected_whole", "args": {"tag": "alpha"}}]},
	{"id": "move_squad", "text": "Drag the squad about 6 inches forward and let go.",
		"rule": "", "all": [{"check": "unit_moved", "args": {"tag": "alpha", "inches": 3.0}}]},
	{"id": "measure", "text": "Hold Shift and drag to measure a distance. (Rulebook p.5)",
		"rule": "p.5", "all": [{"check": "counter_grew", "args": {"key": "measure"}}]},
]


const _S02_STEPS := [
	{"id": "table_size", "text": "Open the menu (top left) and set the table to 6' x 4', the standard size. (p.6)",
		"rule": "p.6", "all": [{"check": "value_is", "args": {"key": "table_size", "value": Vector2(6, 4)}}]},
	{"id": "biome", "text": "Pick a different battlefield biome.",
		"rule": "", "all": [{"check": "value_changed", "args": {"key": "biome"}}]},
	{"id": "terrain_piece", "text": "Turn on Terrain Mode and place at least three pieces of scenery, one of them a forest. (p.12)",
		"rule": "p.12", "all": [
			{"check": "at_least", "args": {"key": "terrain_pieces", "n": 3}},
			{"check": "at_least", "args": {"key": "forest_pieces", "n": 1}}]},
	{"id": "autogen", "text": "Open Map Layout and press Auto-Generate: the rulebook asks for 15 or more pieces. (p.6, p.12)",
		"rule": "p.12", "all": [{"check": "at_least", "args": {"key": "layout_pieces", "n": 1}}]},
	{"id": "deploy_type", "text": "In Map Layout, pick a deployment type.",
		"rule": "", "all": [{"check": "value_changed", "args": {"key": "deploy_type"}}]},
]


const _S03_STEPS := [
	{"id": "menu", "text": "Open the menu (top left).",
		"rule": "", "all": [{"check": "flag", "args": {"key": "menu_open"}}]},
	{"id": "import", "text": "Import an army: paste an Army Forge link — or press Use the practice army (works offline).",
		"rule": "", "all": [{"check": "at_least", "args": {"key": "units_p1", "n": 1}}],
		"action": {"label": "Use the practice army",
			"fixture": "res://assets/tutorial/tutorial_army_p1.json"}},
	{"id": "deploy", "text": "Drag every unit into your deployment zone, the shaded strip on your side. (p.6)",
		"rule": "p.6", "all": [{"check": "flag", "args": {"key": "p1_all_in_zone"}}]},
	{"id": "start", "text": "Press Start Game.",
		"rule": "", "all": [{"check": "value_is", "args": {"key": "phase", "value": 1}}]},
]


const _S04_STEPS := [
	{"id": "bands", "text": "Select Alpha Squad and press M: the rings show Advance 6\" and Rush 12\". (p.7)",
		"rule": "p.7", "all": [{"check": "flag", "args": {"key": "bands"}}]},
	{"id": "advance_alpha", "text": "Advance: drag Alpha Squad up to 6\", then right-click it and choose Activate.",
		"rule": "", "all": [
			{"check": "unit_moved", "args": {"tag": "alpha", "inches": 1.0}},
			{"check": "tag_flag", "args": {"key": "activated", "tag": "alpha", "value": true}}]},
	{"id": "ai_turn", "text": "Now NACHTMAHR activates one unit — turns alternate, one unit each. (p.7)",
		"rule": "p.7", "all": [{"check": "tag_flag", "args": {"key": "activated", "tag": "target", "value": true}}]},
	{"id": "rush_bravo", "text": "Rush: drag Bravo Squad more than 6\" (up to 12\") and activate it. A rushing unit may not shoot.",
		"rule": "", "all": [
			{"check": "unit_moved", "args": {"tag": "bravo", "inches": 6.5}},
			{"check": "at_least", "args": {"key": "round", "n": 2}}]},
	{"id": "next_round", "text": "Every unit has acted, so the round ends by itself: round 2 begins and all units may act again.",
		"rule": "", "all": [{"check": "counter_grew", "args": {"key": "continue"}}]},
]


const _S05_STEPS := [
	{"id": "card", "text": "Right-click Alpha Squad and open its card: the Heavy Rifle shoots 24\". (p.5)",
		"rule": "p.5", "all": [{"check": "flag", "args": {"key": "card_presented"}}]},
	{"id": "shoot", "text": "Right-click Alpha Squad, choose Shoot, click the nearer Warriors squad: the Heavy Rifle reaches 24\". (p.5)",
		"rule": "p.5", "all": [{"check": "counter_grew", "args": {"key": "shoot:alpha"}}]},
	{"id": "read_log", "text": "Read the log: hits roll against Quality, the enemy blocks with Defense. (p.8)",
		"rule": "p.8", "all": [{"check": "counter_grew", "args": {"key": "continue"}}]},
	{"id": "blocked", "text": "Try to shoot the Guardians squad behind the building: it stands in range, but the building blocks the line of sight — no line of sight, no shot. (p.5)",
		"rule": "p.5", "all": [{"check": "counter_grew", "args": {"key": "log:nolos"}}]},
]


const _S06_STEPS := [
	{"id": "charge", "text": "Move Alpha Squad into base contact with the enemy squad (within 1\"). (p.9)",
		"rule": "p.9", "all": [{"check": "gap_at_most", "args": {"tag": "target", "inches": 1.0}}]},
	{"id": "fight", "text": "Right-click Alpha Squad, choose Fight, click the enemy squad.",
		"rule": "", "all": [{"check": "counter_grew", "args": {"key": "melee:alpha"}}]},
	{"id": "pile_in", "text": "The charged squad piles in up to 3\" — read the log, then press Continue. (p.9)",
		"rule": "p.9", "all": [
			{"check": "counter_at_least", "args": {"key": "log:pile_in", "n": 1}},
			{"check": "counter_grew", "args": {"key": "continue"}}]},
	{"id": "strike_back", "text": "The defender strikes back, then both sides are Fatigued — then press Continue. (p.9)",
		"rule": "p.9", "all": [
			{"check": "counter_at_least", "args": {"key": "strike:target", "n": 1}},
			{"check": "counter_grew", "args": {"key": "continue"}}]},
	{"id": "consolidate", "text": "The winner consolidates — read the log, then press Continue. (p.10)",
		"rule": "p.10", "all": [
			{"check": "counter_at_least", "args": {"key": "log:consolidate", "n": 1}},
			{"check": "counter_grew", "args": {"key": "continue"}}]},
]


const _S08_STEPS := [
	{"id": "move_forest", "text": "Move Alpha Squad into the forest ahead. Forests are difficult terrain: no model moves more than 6\". (p.11)",
		"rule": "p.11", "all": [{"check": "tag_terrain_is", "args": {"tag": "alpha", "type": 2}}]},
	{"id": "difficult", "text": "Drag a model past 6\" through the forest: difficult terrain hard-caps the move at 6\". (p.11)",
		"rule": "p.11", "all": [{"check": "counter_grew", "args": {"key": "move_capped"}}]},
	{"id": "cover", "text": "The enemy stands inside a forest: most of it is in cover, so it gets +1 to its Defense rolls against shooting, then press Continue. (p.11)",
		"rule": "p.11", "all": [{"check": "counter_grew", "args": {"key": "continue"}}]},
	{"id": "shoot_cover", "text": "Shoot the enemy in cover and watch the +1 in the log. (p.11)",
		"rule": "p.11", "all": [{"check": "counter_grew", "args": {"key": "shoot:alpha"}}]},
	{"id": "dangerous", "text": "Right-click Alpha Squad, pick Rush, then click the enemy: the shortest path crosses the dangerous ground between the two forests, and the engine rolls one test die per model — a 1 wounds it. (p.12)",
		"rule": "p.12", "all": [{"check": "counter_grew", "args": {"key": "log:dangerous"}}]},
	{"id": "wall", "text": "Ruins are area terrain: units can see into and out of them, but not through — nobody shoots through the ruins, then press Continue. (p.11)",
		"rule": "p.11", "all": [{"check": "counter_grew", "args": {"key": "continue"}}]},
]


const _S07_STEPS := [
	{"id": "shaken_idle", "text": "Charlie Squad carries an S token: Shaken units must spend their activation idle. (p.10)",
		"rule": "p.10", "all": [{"check": "counter_grew", "args": {"key": "continue"}}]},
	{"id": "tough_half", "text": "Open the Nachtmahr Leader card: a single Tough(3) model with 2 of 3 wounds lost counts as at half strength, then press Continue. (p.10)",
		"rule": "p.10", "all": [
			{"check": "tag_flag", "args": {"tag": "tough", "key": "card_presented", "value": true}},
			{"check": "counter_grew", "args": {"key": "continue"}}]},
	{"id": "recover", "text": "Activate Charlie Squad (right-click, then Activate). It idles and recovers — if the S token stays, remove it from the same menu (Shaken) — then press Continue.",
		"rule": "p.10", "all": [
			{"check": "tag_flag", "args": {"tag": "shaken", "key": "activated", "value": true}},
			{"check": "tag_flag", "args": {"tag": "shaken", "key": "shaken", "value": false}},
			{"check": "counter_grew", "args": {"key": "continue"}}]},
	{"id": "morale_test", "text": "The enemy squad is at half strength. Shoot it with Alpha Squad: at the end of the activation it takes a morale test. (p.10)",
		"rule": "p.10", "all": [{"check": "counter_grew", "args": {"key": "shoot:alpha"}}]},
	{"id": "outcome", "text": "Read the log: a unit at half strength that loses models tests morale — fail and it is Shaken, at half strength or less it Routs, then press Continue. (p.10)",
		"rule": "p.10", "all": [{"check": "counter_grew", "args": {"key": "continue"}}]},
]


const _S09_STEPS := [
	{"id": "left_marker", "text": "Move Alpha Squad within 3\" of the left marker. (p.6)",
		"rule": "p.6", "all": [{"check": "obj_within", "args": {"tag": "alpha", "index": 0, "inches": 3.0}}]},
	{"id": "right_marker", "text": "Move Bravo Squad within 3\" of the right marker — the enemy stands there too. (p.6)",
		"rule": "p.6", "all": [{"check": "obj_within", "args": {"tag": "bravo", "index": 2, "inches": 3.0}}]},
	{"id": "seize", "text": "The round ended: the left marker is seized because only your side is within 3\" — the right marker stays contested while both sides are near it, then press Continue. (p.6)",
		"rule": "p.6", "all": [{"check": "counter_grew", "args": {"key": "continue"}}]},
	{"id": "outcome", "text": "A marker is seized when only one side is within 3\" at the end of a round. After 4 rounds, the side holding more markers wins, then press Continue. (p.6)",
		"rule": "p.6", "all": [{"check": "counter_grew", "args": {"key": "continue"}}]},
]


const _SSPELL_STEPS := [
	{"id": "preview", "text": "Open the Archivist's card and hover a spell: a ring shows its range. (p.13)",
		"rule": "p.13", "all": [{"check": "flag", "args": {"key": "spell_preview"}}]},
	{"id": "cast", "text": "Right-click the Archivist, choose Cast, then pick the spell and a squad.",
		"rule": "p.13", "all": [{"check": "counter_grew", "args": {"key": "cast:alpha"}}]},
	{"id": "tokens", "text": "Explained, nothing to do here: casters gain a token every round and spend one to cast, and a spell succeeds on a 4+. Read it, then press Continue. (p.13)",
		"rule": "p.13", "all": [{"check": "counter_grew", "args": {"key": "continue"}}]},
]


const _S10_STEPS := [
	{"id": "finish", "text": "Play the mission to the end: NACHTMAHR plays for real at its easiest grade, Dämmerung, over 4 rounds and holds the markers. Win, lose or draw, the lesson ends when the game does. (p.6)",
		"rule": "p.6", "all": [{"check": "flag", "args": {"key": "game_finished"}}]},
]


## The ordered steps for a chapter id, or [] when the chapter has no lesson data yet (so it can
## never fake completion — see LessonRunner).
static func steps_for(chapter_id: String) -> Array:
	match chapter_id:
		"S-01":
			return _S01_STEPS
		"S-02":
			return _S02_STEPS
		"S-03":
			return _S03_STEPS
		"S-04":
			return _S04_STEPS
		"S-05":
			return _S05_STEPS
		"S-06":
			return _S06_STEPS
		"S-07":
			return _S07_STEPS
		"S-08":
			return _S08_STEPS
		"S-SPELL":
			return _SSPELL_STEPS
		"S-09":
			return _S09_STEPS
		"S-10":
			return _S10_STEPS
	return []


## How the solo AI behaves on a chapter's table: "none" (no AI present), "hold" (the AI activates
## but never moves or shoots — the lesson puppet, D-TUT-3), "live" (the real AI, the finale only).
static func ai_mode(chapter_id: String) -> String:
	match chapter_id:
		"S-01":
			return "none"
		"S-02":
			return "none"
		"S-03":
			return "none"
		"S-04":
			return "hold"
		"S-05":
			return "hold"
		"S-06":
			return "hold"
		"S-07":
			return "hold"
		"S-08":
			return "hold"
		"S-SPELL":
			return "hold"
		"S-09":
			return "hold"
		"S-10":
			return "live"
	return "none"
