class_name GameSystem
extends RefCounted
## The five game systems a table can play (PLAN_GAME_SYSTEM_SWITCH, step 1): ids, display labels, setting
## (grimdark / fantasy), scale (battle / skirmish) and the board size a system starts on. Pure data and lookups -
## nothing here changes a rule. The ids ARE RulesRegistry.SYSTEMS (and rules.rs SYSTEMS); the board sizes are
## rules.rs `Book.default_board_in` in feet, both pinned by test/game_system_test.gd.

## Same ids, same order as RulesRegistry.SYSTEMS and rules.rs SYSTEMS.
const IDS: Array = ["gf", "gff", "aof", "aofs", "aofr"]
const DEFAULT_ID: String = "gf"
const TERRAIN_PATH: String = "res://assets/terrain_systems.json"

const SETTING_GRIMDARK := "grimdark"
const SETTING_FANTASY := "fantasy"
const SCALE_BATTLE := "battle"
const SCALE_SKIRMISH := "skirmish"

## Official system names (maintainer / lead M-9); working ids never show as labels.
const _LABELS := {
	"gf": "Grimdark Future",
	"gff": "Grimdark Future: Firefight",
	"aof": "Age of Fantasy",
	"aofs": "Age of Fantasy: Skirmish",
	"aofr": "Age of Fantasy: Regiments",
}
const _SHORT := {"gf": "GF", "gff": "GFF", "aof": "AoF", "aofs": "AoFS", "aofr": "AoFR"}
const _SETTINGS := {
	"gf": SETTING_GRIMDARK, "gff": SETTING_GRIMDARK,
	"aof": SETTING_FANTASY, "aofs": SETTING_FANTASY, "aofr": SETTING_FANTASY,
}
const _SCALES := {
	"gf": SCALE_BATTLE, "gff": SCALE_SKIRMISH,
	"aof": SCALE_BATTLE, "aofs": SCALE_SKIRMISH, "aofr": SCALE_BATTLE,
}
## Board the setup screen starts on, in feet (rules.rs Book.default_board_in is inches: 72 x 48 / 48 x 48).
const _BOARD_FEET := {
	"gf": Vector2i(6, 4), "gff": Vector2i(4, 4),
	"aof": Vector2i(6, 4), "aofs": Vector2i(4, 4), "aofr": Vector2i(6, 4),
}


## A known id (case / whitespace tolerant), or the default for anything else - the same fold the core's
## `book()` and RulesRegistry.normalize_system use.
static func normalize(id: String) -> String:
	return RulesRegistry.normalize_system(id)


## True for exactly the five known ids (no folding): the guard before a switch value is stored.
static func is_known(id: String) -> bool:
	return IDS.has(id.strip_edges().to_lower())


const MENU_CFG := "user://menu.cfg"
const PICK_KEY := "game_system"


## The pick a fresh table-setup dialog starts on: the remembered one (the menu config), else gf. Same file and pattern as
## RulesAutomation.default_pick; a value that is no system reads as gf.
static func default_pick(cfg_path: String = MENU_CFG) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(cfg_path) != OK:
		return DEFAULT_ID
	var id := str(cfg.get_value("menu", PICK_KEY, DEFAULT_ID)).strip_edges().to_lower()
	return id if IDS.has(id) else DEFAULT_ID


## Remembers the player's pick for the next table (keeps the other menu keys: biome, rules).
static func remember_pick(id: String, cfg_path: String = MENU_CFG) -> void:
	if not is_known(id):
		return
	var cfg := ConfigFile.new()
	cfg.load(cfg_path)   # a missing file is fine
	cfg.set_value("menu", PICK_KEY, id.strip_edges().to_lower())
	cfg.save(cfg_path)


## Applies the "system" key of a pending table setup (what the setup screen picked) to the army manager and returns
## the battle-log line ("" when the setup has no key: harness, tutorial, scenario and old paths stay "never set").
## A value that is no system changes nothing and says so.
static func apply_table_setup(setup: Dictionary, manager: Object) -> String:
	if manager == null or not setup.has("system"):
		return ""
	var raw := str(setup["system"])
	if not is_known(raw):
		return "Game system: \"%s\" is not a game system, the table keeps none" % raw
	manager.table_system = raw.strip_edges().to_lower()
	return "Game system: %s" % label(manager.table_system)


static func label(id: String) -> String:
	return str(_LABELS[normalize(id)])


## Short form for a crowded list ("GF", "GFF", "AoF", "AoFS", "AoFR").
static func short(id: String) -> String:
	return str(_SHORT[normalize(id)])


## The faction keys of an AI-list manifest a table of `system` is offered: exactly the lists of that system, no family
## folding ("" = nothing names a system yet: all of them). An entry without a "system" is a gf list.
static func manifest_keys(manifest: Dictionary, system: String) -> Array:
	var out: Array = []
	for fk in manifest:
		var of_system := normalize(str((manifest[fk] as Dictionary).get("system", DEFAULT_ID)))
		if system.is_empty() or of_system == normalize(system):
			out.append(fk)
	return out


## "grimdark" (gf, gff) or "fantasy" (aof, aofs, aofr).
static func setting(id: String) -> String:
	return str(_SETTINGS[normalize(id)])


## "battle" (gf, aof, aofr) or "skirmish" (gff, aofs).
static func scale(id: String) -> String:
	return str(_SCALES[normalize(id)])


## The board the setup screen preselects for this system, in feet (width, depth).
static func default_board_feet(id: String) -> Vector2i:
	return _BOARD_FEET[normalize(id)]


static var _rows: Dictionary = {}
static var _rows_loaded := false


static func reset_cache() -> void:
	_rows = {}
	_rows_loaded = false


static func _terrain_rows() -> Dictionary:
	if not _rows_loaded:
		_rows_loaded = true
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TERRAIN_PATH))
		if parsed is Dictionary:
			_rows = parsed
		else:
			push_warning("[GAME SYSTEM] %s missing or unparseable - every terrain item is offered" % TERRAIN_PATH)
	return _rows


## Does a table of `system` OFFER terrain item `id` of `kind` (assets/terrain_systems.json)? It filters offers only,
## never what already stands on a table. Fails OPEN: a kind or id with no row is offered (test/game_system_offers_test.gd
## fails CLOSED for every catalogued id), and so is an empty or unknown system (it folds to the default, today's offers).
## A row with `available: false` is offered nowhere yet.
static func offers(kind: String, id: String, system: String) -> bool:
	var of_kind: Variant = _terrain_rows().get(kind)
	if not (of_kind is Dictionary) or not ((of_kind as Dictionary).get(id) is Dictionary):
		return true
	var row: Dictionary = (of_kind as Dictionary)[id]
	if not bool(row.get("available", true)):
		return false
	var settings: Variant = row.get("settings")
	if settings is Array and not (settings as Array).has(setting(system)):
		return false
	var scales: Variant = row.get("scales")
	if scales is Array and not (scales as Array).has(scale(system)):
		return false
	return true
