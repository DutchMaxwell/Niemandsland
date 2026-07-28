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
##   reserved : bool    a placeholder slot with no scenario planned this wave (the spell lesson,
##                      "coming with the spell wave") — always disabled.

## The ten curriculum chapters + the reserved spell slot, in menu order.
## Only chapter 1 ships a bundled scenario this wave (a PLACEHOLDER — a copy of the existing
## tutorial board — so the loader has a real save to round-trip; the maintainer replaces it with a
## hand-built scene). Every other chapter carries scenario == "" until its scene is authored.
static func chapters() -> Array:
	return [
		{"id": "S-01", "title": "Tools & Basics",
			"goal": "Camera, selection and movement — the core tools.",
			"scenario": "res://assets/tutorial/scenarios/s01_werkzeug_grundlagen.nml"},
		{"id": "S-02", "title": "Table Setup",
			"goal": "Set the table size, biome and terrain.", "scenario": ""},
		{"id": "S-03", "title": "Get an Army",
			"goal": "Import a OnePageRules army.", "scenario": ""},
		{"id": "S-04", "title": "Activation & Movement Bands",
			"goal": "Activate units and read the movement bands.", "scenario": ""},
		{"id": "S-05", "title": "Shooting",
			"goal": "Ranged attacks: range, dice and hits.", "scenario": ""},
		{"id": "S-06", "title": "Melee",
			"goal": "Charge in and resolve close combat.", "scenario": ""},
		{"id": "S-07", "title": "Morale & Shaken",
			"goal": "Pass morale tests and clear Shaken.", "scenario": ""},
		{"id": "S-08", "title": "Terrain",
			"goal": "Use cover, terrain and line of sight.", "scenario": ""},
		{"id": "S-09", "title": "Mission Objectives",
			"goal": "Hold objectives and win the mission.", "scenario": ""},
		{"id": "S-10", "title": "Into No Man's Land — face NACHTMAHR",
			"goal": "A short real game against the solo AI.", "scenario": ""},
		# Reserved: the spell lesson arrives with the spell wave (kept visible so players see it is
		# coming). Never playable this wave.
		{"id": "S-SPELL", "title": "Spellcasting",
			"goal": "Coming with the spell wave.", "scenario": "", "reserved": true},
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


## The ids of the PLAYABLE chapters (exactly the ten curriculum lessons — excludes the reserved slot).
static func lesson_ids() -> Array[String]:
	var out: Array[String] = []
	for c in chapters():
		if not bool(c.get("reserved", false)):
			out.append(String(c.get("id", "")))
	return out


## Whether a chapter can be PLAYED now: not reserved, and its bundled scenario file actually exists.
## Reads the real filesystem (res:// resolves in editor/source AND in an exported .pck), so a chapter
## whose scenario has not been authored yet stays disabled ("scenario coming soon") in the picker.
static func is_available(chapter_data: Dictionary) -> bool:
	if bool(chapter_data.get("reserved", false)):
		return false
	var path := String(chapter_data.get("scenario", ""))
	return not path.is_empty() and FileAccess.file_exists(path)
