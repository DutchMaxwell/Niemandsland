class_name Spielschule
extends RefCounted
## The Game School curriculum: the ordered list of lesson CHAPTERS the start-menu picker shows.
## (Internal/working name "Spielschule"; the shipped UI reads "GAME SCHOOL" — the game is
## English-only, see project.godot i18n note.)
##
## This is a CHAPTER registry, deliberately separate from TutorialFlow.build_tool_track() (which is a
## STEP track of the OLD guided tutorial). Each chapter loads its OWN prepared mini-scene — a normal
## .nml save the maintainer hand-builds in the sandbox and drops under res://assets/tutorial/scenarios/.
## Chapters are isolated, repeatable and skippable; the finale is a small real game vs the solo AI.
##
## Chapter shape (Dictionary):
##   id       : String  fresh Game School id "S-01".."S-10" / "S-SPELL" — NEVER a W-/T-track id, so
##                      progress (SpielschuleProgress) can never migrate/collide with the old tutorial.
##   title    : String  short chapter name (English — the game has no i18n).
##   goal     : String  one-line "what you'll learn".
##   scenario : String  res:// path to the bundled .nml lesson, or "" when none is bundled yet
##                      (the picker then shows "scenario coming soon" and disables the row).

## The eleven curriculum chapters, in menu order (the spell lesson follows S-08, printed-rulebook
## order p.11 terrain then p.13 caster).
static func chapters() -> Array:
	return [
		{"id": "S-01", "title": "First Steps",
			"goal": "Camera, selection and movement — the core tools.",
			"scenario": "res://assets/tutorial/scenarios/s01_werkzeug_grundlagen.nml"},
		{"id": "S-02", "title": "Build the Table",
			"goal": "Set the table size, biome and terrain.",
			"scenario": "res://assets/tutorial/scenarios/s02_table_setup.nml"},
		{"id": "S-03", "title": "Bring Your Army",
			"goal": "Import a OnePageRules army.",
			"scenario": "res://assets/tutorial/scenarios/s03_bring_your_army.nml"},
		{"id": "S-04", "title": "Activate & Move",
			"goal": "Activate units and read the movement bands.",
			"scenario": "res://assets/tutorial/scenarios/s04_activate_and_move.nml"},
		{"id": "S-05", "title": "Shooting",
			"goal": "Ranged attacks: range, dice and hits.",
			"scenario": "res://assets/tutorial/scenarios/s05_shooting.nml"},
		{"id": "S-06", "title": "Melee",
			"goal": "Charge in and resolve close combat.",
			"scenario": "res://assets/tutorial/scenarios/s06_melee.nml"},
		{"id": "S-07", "title": "Morale & Shaken",
			"goal": "Pass morale tests and clear Shaken.", "scenario": "res://assets/tutorial/scenarios/s07_morale.nml"},
		{"id": "S-08", "title": "Terrain",
			"goal": "Use cover, terrain and line of sight.", "scenario": "res://assets/tutorial/scenarios/s08_terrain.nml"},
		{"id": "S-SPELL", "title": "Spellcasting",
			"goal": "Casters, tokens and spell range.", "scenario": "res://assets/tutorial/scenarios/s_spell_casting.nml"},
		{"id": "S-09", "title": "Mission Objectives",
			"goal": "Hold objectives and win the mission.", "scenario": "res://assets/tutorial/scenarios/s09_objectives.nml"},
		{"id": "S-10", "title": "Ins Niemandsland — face NACHTMAHR",
			"goal": "A short real game against the solo AI.", "scenario": "res://assets/tutorial/scenarios/s10_finale.nml"},
	]


## The chapter ids in menu order (progress lookups, tests).
static func ids() -> Array[String]:
	var out: Array[String] = []
	for c in chapters():
		out.append(String(c.get("id", "")))
	return out


## The chapter dict for an id, or {} when unknown.
static func chapter(id: String) -> Dictionary:
	for c in chapters():
		if String(c.get("id", "")) == id:
			return c
	return {}


## The ids of the PLAYABLE chapters (the eleven curriculum lessons).
static func lesson_ids() -> Array[String]:
	var out: Array[String] = []
	for c in chapters():
		out.append(String(c.get("id", "")))
	return out


## Whether a chapter can be PLAYED now: its bundled scenario file actually exists. Reads the real
## filesystem (res:// resolves in editor/source AND in an exported .pck), so a chapter whose
## scenario has not been authored yet stays disabled ("scenario coming soon") in the picker.
static func is_available(chapter_data: Dictionary) -> bool:
	var path := String(chapter_data.get("scenario", ""))
	return not path.is_empty() and FileAccess.file_exists(path)
