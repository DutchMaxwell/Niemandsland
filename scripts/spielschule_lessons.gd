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


## The ordered steps for a chapter id, or [] when the chapter has no lesson data yet (so it can
## never fake completion — see LessonRunner).
static func steps_for(chapter_id: String) -> Array:
	match chapter_id:
		"S-01":
			return _S01_STEPS
	return []


## How the solo AI behaves on a chapter's table: "none" (no AI present), "hold" (the AI activates
## but never moves or shoots — the lesson puppet, D-TUT-3), "live" (the real AI, the finale only).
static func ai_mode(chapter_id: String) -> String:
	match chapter_id:
		"S-01":
			return "none"
	return "none"
