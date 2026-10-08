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
