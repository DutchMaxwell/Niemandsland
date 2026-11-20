class_name GameSystem
extends RefCounted
## The five game systems a table can play (PLAN_GAME_SYSTEM_SWITCH, step 1): ids, display labels, setting
## (grimdark / fantasy), scale (battle / skirmish) and the board size a system starts on. Pure data and lookups -
## nothing here changes a rule. The ids ARE RulesRegistry.SYSTEMS (and rules.rs SYSTEMS); the board sizes are
## rules.rs `Book.default_board_in` in feet, both pinned by test/game_system_test.gd.

## Same ids, same order as RulesRegistry.SYSTEMS and rules.rs SYSTEMS.
const IDS: Array = ["gf", "gff", "aof", "aofs", "aofr"]
const DEFAULT_ID: String = "gf"

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


static func label(id: String) -> String:
	return str(_LABELS[normalize(id)])


## "grimdark" (gf, gff) or "fantasy" (aof, aofs, aofr).
static func setting(id: String) -> String:
	return str(_SETTINGS[normalize(id)])


## "battle" (gf, aof, aofr) or "skirmish" (gff, aofs).
static func scale(id: String) -> String:
	return str(_SCALES[normalize(id)])


## The board the setup screen preselects for this system, in feet (width, depth).
static func default_board_feet(id: String) -> Vector2i:
	return _BOARD_FEET[normalize(id)]
