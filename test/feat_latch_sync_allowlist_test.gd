extends GdUnitTestSuite
## MP1: every once-per-game latch a spend can write must be a key NetworkManager may carry, or the
## other table never learns of the spend and a guest-side spend is lost on rejoin. The keys are built
## from rule names, so the allowlist names them one by one; this suite walks the registry and fails
## when a once-per-game rule of a latching primitive has no listed key.

const NetworkManagerScript := preload("res://scripts/network_manager.gd")
const MAIN := preload("res://scripts/main.gd")

## Latching primitive -> the flag builder the spend site uses.
const SHOT_PRIMITIVES := ["Shot Modifier", "Piercing Assault"]   # main._solo_spend_shot_feats
const IGNORE_PRIMITIVES := ["Regeneration"]                       # main._solo_roll_ignore_group
const SPEED_PRIMITIVES := ["Quick"]                               # main (D22 Speed Feat)


func _once_rules(primitives: Array) -> Array:
	var out: Array = []
	for system in RulesRegistry.SYSTEMS:
		var m: Dictionary = RulesRegistry.map_for(system)
		var maps: Array = [m.get("common", {})]
		for f in (m.get("factions", {}) as Dictionary).values():
			maps.append(f)
		for rules in maps:
			for name in (rules as Dictionary).keys():
				var e: Variant = rules[name]
				if e is Dictionary and str((e as Dictionary).get("primitive")) in primitives \
						and int(((e as Dictionary).get("params", {}) as Dictionary).get("uses_per_game", 0)) > 0 \
						and not out.has(str(name)):
					out.append(str(name))
	return out


func _unlisted(keys: Array) -> Array:
	return keys.filter(func(k: String) -> bool: return not NetworkManagerScript.SYNCABLE_UNIT_PROPERTIES.has(k))


func test_every_once_per_game_shot_feat_latch_is_syncable() -> void:
	var rules := _once_rules(SHOT_PRIMITIVES)
	assert_bool(rules.has("Piercing Feat") and rules.has("Precision Feat")).override_failure_message(
		"the registry walk lost the known rules: %s" % [rules]).is_true()
	var keys: Array = rules.map(func(n: String) -> String: return SoloController.shot_feat_flag(n))
	assert_array(_unlisted(keys)).is_empty()


func test_every_once_per_game_ignore_latch_is_syncable() -> void:
	var rules := _once_rules(IGNORE_PRIMITIVES)
	assert_bool(rules.has("Protection Feat")).override_failure_message(
		"the registry walk lost the known rules: %s" % [rules]).is_true()
	var keys: Array = rules.map(func(n: String) -> String: return MAIN._solo_ignore_feat_flag(n))
	assert_array(_unlisted(keys)).is_empty()


func test_every_once_per_game_speed_feat_latch_is_syncable() -> void:
	var keys: Array = _once_rules(SPEED_PRIMITIVES).map(func(n: String) -> String: return SoloController.speed_feat_flag(n))
	assert_array(keys).is_not_empty()
	assert_array(_unlisted(keys)).is_empty()
