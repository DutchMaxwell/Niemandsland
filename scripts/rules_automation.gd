class_name RulesAutomation
extends RefCounted
## Rules-automation level of a game: MANUAL (players use the dice tray) or AUTOMATIC (the game rolls
## and applies the rules). Step 1.1 only STORES the level (army manager + save); nothing in gameplay
## reads it yet. Pure static helpers, no scene state.

enum Level { MANUAL, AUTOMATIC }

## Key in the saved `game_state` dictionary. Optional: a save without it is a Manual game.
const SAVE_KEY := "rules_automation"


## Level stored in a serialized game state; absent or invalid values read as MANUAL.
static func from_game_state(d: Dictionary) -> int:
	var v: Variant = d.get(SAVE_KEY, Level.MANUAL)
	if v is int or v is float:
		var i := int(v)
		if i == Level.AUTOMATIC:
			return Level.AUTOMATIC
	return Level.MANUAL


static func label(level: int) -> String:
	return "Automatic" if level == Level.AUTOMATIC else "Manual"


## The level that actually applies: a game with an AI-designated slot is always AUTOMATIC.
static func effective(level: int, ai_designated: bool) -> int:
	return Level.AUTOMATIC if ai_designated else level


## Flipped on by plan step 2.10, when hotseat Automatic works; until then the table-setup row stays hidden.
const UI_ENABLED := false
## Test seam: a suite sets this to exercise the row, the pick and the log line with the flag forced on.
static var ui_enabled_override := false
const MENU_CFG := "user://menu.cfg"


static func ui_enabled() -> bool:
	return UI_ENABLED or ui_enabled_override


## The pick a fresh table-setup dialog starts on: the remembered one for a local game (default AUTOMATIC),
## always MANUAL online and while the row is hidden.
static func default_pick(online: bool, cfg_path: String = MENU_CFG) -> int:
	if online or not ui_enabled():
		return Level.MANUAL
	var cfg := ConfigFile.new()
	if cfg.load(cfg_path) != OK:
		return Level.AUTOMATIC
	return from_game_state({SAVE_KEY: cfg.get_value("menu", SAVE_KEY, Level.AUTOMATIC)})


static func remember_pick(level: int, cfg_path: String = MENU_CFG) -> void:
	var cfg := ConfigFile.new()
	cfg.load(cfg_path)   # keep the other menu keys (biome); a missing file is fine
	cfg.set_value("menu", SAVE_KEY, level)
	cfg.save(cfg_path)


## Applies the "rules" key of a pending table setup to the army manager; returns the first battle-log
## line ("" when there is nothing to log: no key, or the row is hidden).
static func apply_table_setup(setup: Dictionary, manager: Object) -> String:
	if not setup.has("rules") or manager == null:
		return ""
	manager.rules_automation = from_game_state({SAVE_KEY: setup["rules"]})
	if not ui_enabled():
		return ""
	return "Rules automation: %s" % label(manager.rules_automation)
