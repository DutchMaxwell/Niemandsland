extends GdUnitTestSuite
## Rules 3.6 row SHO-09b: the conditional-AP condition that reads the TARGET's surroundings —
## MOST of its models stand within 1" of terrain. The arm reuses the Stealth-alias terrain
## sampler; no shipped map entry spells the name, so it needs no epoch gate (the SHO-09
## precedent): the _at_epoch_72 control pins every existing condition unchanged.

const MainScript := preload("res://scripts/main.gd")

const NEAR := {"ap_bonus": 1, "condition": "near_terrain"}
const ATT := {"quality": 4, "models": 5}


## The stand-in overlay: every probe answers FOREST, so every model is by terrain.
class FakeOverlay extends Node3D:
	func get_terrain_at_world_position(_p: Vector3) -> int:
		return TerrainRules.TerrainType.FOREST


func after_test() -> void:
	RulesRegistry.reset_cache()


func _rifle(over: Dictionary = {}) -> Dictionary:
	var p := {"name": "Probe Gun", "attacks": 8, "ap": 0, "range": 24, "rules": []}
	for k in over:
		p[k] = over[k]
	return p


func _unit(defense: int, models: int = 1, nodes := false) -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = "sho09b_%d_%d_%s" % [defense, models, str(nodes)]
	u.unit_properties = {"player_id": 2, "name": "U", "quality": 4, "defense": defense,
		"special_rules": [], "game_system": "gf", "faction_folder": ""}
	for i in models:
		var m := ModelInstance.new()
		m.is_alive = true
		m.wounds_max = 1
		m.wounds_current = 1
		if nodes:
			m.node = auto_free(Node3D.new())
		u.models.append(m)
	return u


func test_the_pure_arm_reads_the_target_surroundings_at_epoch_73() -> void:
	assert_int(AiCombatMath.conditional_ap_bonus(NEAR, 1, 4, false, 6.0, false,
		{"near_terrain": true})).is_equal(1)
	assert_int(AiCombatMath.conditional_ap_bonus(NEAR, 1, 4, false, 6.0, false,
		{"near_terrain": false})).is_equal(0)
	assert_int(AiCombatMath.conditional_ap_bonus(NEAR, 1, 4, false, 6.0, false, {})).is_equal(0)
	assert_str(AiCombatMath.conditional_ap_why(NEAR)).is_equal("target stands within 1\" of terrain")


func test_the_snapshot_ctx_is_blind_without_a_board_at_epoch_73() -> void:
	var snap := {"unit": _unit(4, 4), "alive": 4, "in_cover": false, "shaken": false,
		"fatigued": false, "wounds": [1, 1, 1, 1]}
	assert_bool(bool(BattleSim._ctx_of(snap).get("near_terrain", false))).is_false()


func test_the_table_pays_and_names_the_condition_at_epoch_73() -> void:
	RulesRegistry.reset_cache()
	RulesRegistry._cache["gf"] = {"common": {
		"Probe Near": {"params": NEAR.duplicate()}}}
	var main: Node3D = auto_free(MainScript.new())
	main.terrain_overlay = auto_free(FakeOverlay.new())
	assert_array(main._solo_conditional_ap_parts(_rifle({"rules": ["Probe Near"]}), _unit(4), _unit(4, 5, true), false, 6.0, false)) \
		.contains_exactly([{"name": "Probe Near", "bonus": 1, "why": "target stands within 1\" of terrain"}])
	assert_array(main._solo_conditional_ap_parts(_rifle({"rules": ["Probe Near"]}), _unit(4), _unit(4, 5), false, 6.0, false)).is_empty()


func test_the_ev_prices_the_same_flag_at_epoch_73() -> void:
	var armed := _rifle({"cond_ap": [NEAR]})
	var plain := _rifle()
	var near := {"defense": 4, "tough": 1, "models": 5, "near_terrain": true}
	var away := {"defense": 4, "tough": 1, "models": 5, "near_terrain": false}
	assert_bool(AiEv.profile_ev(armed, ATT, near, 6.0, false) > AiEv.profile_ev(plain, ATT, near, 6.0, false)) \
		.override_failure_message("near terrain: the AP(+1) must lower the save").is_true()
	assert_float(AiEv.profile_ev(armed, ATT, away, 6.0, false)) \
		.is_equal_approx(AiEv.profile_ev(plain, ATT, away, 6.0, false), 0.0001)


func test_existing_conditions_answer_unchanged_at_epoch_72() -> void:
	var tough := {"ap_bonus": 2, "condition": "vs_tough_ge", "threshold": 3}
	assert_int(AiCombatMath.conditional_ap_bonus(tough, 3, 4, false)).is_equal(2)
	assert_int(AiCombatMath.conditional_ap_bonus(tough, 2, 4, false)).is_equal(0)
	var armor := {"ap_bonus": 2, "condition": "vs_armor", "threshold": 3}
	assert_int(AiCombatMath.conditional_ap_bonus(armor, 1, 3, false)).is_equal(2)
	assert_int(AiCombatMath.conditional_ap_bonus(armor, 1, 5, false)).is_equal(0)
	var ranged := {"ap_bonus": 2, "condition": "ranged_over", "over_in": 9.0}
	assert_int(AiCombatMath.conditional_ap_bonus(ranged, 1, 5, false, 12.0, false)).is_equal(2)
	assert_int(AiCombatMath.conditional_ap_bonus(ranged, 1, 5, false, 6.0, false)).is_equal(0)
	var charge := {"ap_bonus": 2, "condition": "on_charge"}
	assert_int(AiCombatMath.conditional_ap_bonus(charge, 1, 5, true, 0.0, true)).is_equal(2)
	assert_int(AiCombatMath.conditional_ap_bonus(charge, 1, 5, false, 0.0, true)).is_equal(0)
