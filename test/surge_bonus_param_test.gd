extends GdUnitTestSuite
## RED (dead-parameter recount 2026-09-15, family 2) — the Surge family's
## `bonus_hits_per_six` and Bloodthirsty Fighter's
## `extra_attack_per_enemy_save_one` ride the registry unread: the alias
## stamp (ai_ev.gd's Surge coverage wave) and the surge fold (main.gd
## `_solo_hits`) pay the hard-coded +1, and the melee strike fold counts ONE
## extra attack per blocked 1. A fixture entry that says 2 must reach the
## stamp AND the fold; on main the constant wins, so the surge tests below
## fail (RED). The shipped books all print 1 — exactly the constant — so a
## real-book run cannot tell the read apart and no recorded game changes.

const MainScript := preload("res://scripts/main.gd")


func _unit_with(rules: Array, system: String, faction: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "t_1"
	u.unit_properties = {"player_id": 2, "name": "T", "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": system, "faction_folder": faction}
	var m := ModelInstance.new()
	m.is_alive = true
	u.models.append(m)
	return u


func _inject(system: String, name: String, primitive: String, params: Dictionary) -> void:
	# The rules_registry_test fixture shape: a cache override, reset before
	# and after (statics leak across gdUnit tests).
	RulesRegistry.reset_cache()
	RulesRegistry._cache[system] = {"factions": {"testfac": {name: {
		"primitive": primitive, "rated": false, "book_version": "3.5.3",
		"params": params}}}, "common": {}}


func test_a_surge_alias_entry_stamps_its_bonus_hits_per_six_onto_the_profiles() -> void:
	_inject("gf", "War Cry", "Surge", {"bonus_hits_per_six": 2})
	var u := _unit_with(["War Cry"], "gf", "testfac")
	var shoot := {"range": 24, "attacks": 2, "ap": 0, "rules": []}
	var melee := {"range": 0, "attacks": 2, "ap": 0, "rules": []}
	AiEv.stamp_sergeant([shoot, melee], u)
	assert_bool(bool(shoot.get("surge", false))) \
		.override_failure_message("the alias lost its facet").is_true()
	assert_int(int(shoot.get("bonus_hits_per_six", 1))) \
		.override_failure_message("the alias stamp must carry the entry's per-six bonus") \
		.is_equal(2)
	assert_int(int(melee.get("bonus_hits_per_six", 1))) \
		.override_failure_message("the melee profile carries the same bonus").is_equal(2)
	RulesRegistry.reset_cache()


func test_the_surge_fold_pays_the_entry_param_per_six() -> void:
	# The dice fold itself (main.gd _solo_hits, shared by shooting and
	# melee): 2 base hits + two unmodified 6s x the entry's 2. On main the
	# hard-coded +1 wins (4) — RED. The param-less profile replays the
	# recorded 4. battle_log is null on the fresh instance, so no log line.
	var main: Node3D = auto_free(MainScript.new())
	var doubled: Dictionary = {"name": "Rifle", "range": 24, "attacks": 4, "surge": true,
		"bonus_hits_per_six": 2, "rules": []}
	assert_int(await main._solo_hits([6, 6, 2, 3], 4, doubled, 12.0)) \
		.override_failure_message("two sixes at bonus 2 must pay 4 bonus hits").is_equal(6)
	var plain: Dictionary = {"name": "Rifle", "range": 24, "attacks": 4, "surge": true, "rules": []}
	assert_int(await main._solo_hits([6, 6, 2, 3], 4, plain, 12.0)) \
		.override_failure_message("no param: the recorded +1-per-six replay").is_equal(4)
	RulesRegistry.reset_cache()


func test_the_shipped_bloodthirsty_entry_carries_its_per_one_param() -> void:
	# The real map: the aof/war_disciples entry carries the param the strike
	# fold reads — pinning the data, every shipped row prints 1.
	RulesRegistry.reset_cache()
	var e := RulesRegistry.lookup("aof", "war_disciples", "Bloodthirsty Fighter")
	assert_str(str(e.get("primitive", ""))).is_equal("Bloodthirsty Fighter")
	assert_int(int((e.get("params", {}) as Dictionary)
		.get("extra_attack_per_enemy_save_one", 0))).is_equal(1)
	RulesRegistry.reset_cache()


func test_a_bloodthirsty_entrys_extra_attack_param_surfaces_to_the_strike_seam() -> void:
	# The seam the melee strike fold reads (main.gd's
	# unit_rules_of_primitive("Bloodthirsty Fighter") loop): a fixture entry
	# saying 2 must surface it — the fold then rolls TWO extra attacks per
	# blocked 1 (the arithmetic is twin-pinned by the core dice test).
	_inject("aof", "Bloodthirsty Fighter", "Bloodthirsty Fighter",
		{"melee_only": true, "extra_attack_per_enemy_save_one": 2})
	var u := _unit_with(["Bloodthirsty Fighter"], "aof", "testfac")
	var hits := RulesRegistry.unit_rules_of_primitive(u, "Bloodthirsty Fighter")
	assert_int(hits.size()).is_equal(1)
	assert_int(int((((hits[0] as Dictionary).get("params", {}) as Dictionary)
		.get("extra_attack_per_enemy_save_one", 1)))).is_equal(2)
	RulesRegistry.reset_cache()
