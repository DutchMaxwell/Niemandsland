extends GdUnitTestSuite

## Havocbound Boost — the table never pays the printed "always AP(+1)".
## STANDALONE_SWEEP_F_2026-09-14, row `Havocbound Boost` (CORE-ONLY). The sim's
## epoch-6 named arm (core/nml-core/src/unit.rs:5444-5515) folds the Boost's
## `always` leg unconditionally (core/nml-core/src/combat.rs:402-407) and
## REPLACES the base Havocbound's two conditional legs with it ("always …
## instead of only when …", unit.rs:5452-5456; the entry's `upgrades` coupling
## is checked with has_exact_rule, unit.rs:5499-5510). The table's generic
## conditional-AP pass (main.gd `_solo_conditional_ap_parts`) fires only when
## an entry's params carry a condition/gate — the Boost entry carries NEITHER,
## so a boosted unit shooting under the old 9" bound (or swinging without a
## charge) keeps AP(0) on the table's own dice, and at 12" the trace names the
## WRONG rule (the base's ranged leg, which the printed rule replaced).

const Boot := preload("res://test/e2e/e2e_boot.gd")
var _runner: GdUnitSceneRunner
var _main: Node
var _roots: Array


func before_test() -> void:
	Boot.arm_harness_mode()
	_roots = Boot.root_children(get_tree())
	_runner = scene_runner(Boot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	Boot.free_stray_root_nodes(get_tree(), _roots)
	_main = null
	_runner = null


func _unit(rules: Array, system: String, faction: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "boost_%d" % rules.size()
	u.unit_properties = {"player_id": 2, "name": "Fixture", "quality": 4, "defense": 2,
		"special_rules": rules, "game_system": system, "faction_folder": faction}
	var model := ModelInstance.new()
	model.is_alive = true
	u.models.append(model)
	return u


# The Boost entries are faction-scoped in the mechanics maps (gf/havoc_brothers,
# aof|aofs|aofr: havoc_dwarves + havoc_warriors) — the same contexts the
# Piercing Warrior sibling suite (e2e_piercing_warrior_test.gd) exercises.
const CONTEXTS := [["gf", "havoc_brothers"], ["aof", "havoc_dwarves"], ["aof", "havoc_warriors"]]


func test_boost_pays_always_ap_and_replaces_the_base_legs() -> void:
	for context in CONTEXTS:
		var unit := _unit(["Havocbound", "Havocbound Boost"], context[0], context[1])
		var foe := _unit([], context[0], context[1])
		# Shooting at 12": AP +1 — and the trace must name the BOOST (the base's
		# ranged leg was replaced by the printed "always … instead of only when …").
		assert_array(_main._solo_conditional_ap_parts({"rules": []}, unit, foe, false, 12.0, false)) \
			.is_equal([{"name": "Havocbound Boost", "bonus": 1}])
		# Shooting at 6": under the base's 9" bound — only the always leg pays.
		assert_array(_main._solo_conditional_ap_parts({"rules": []}, unit, foe, false, 6.0, false)) \
			.is_equal([{"name": "Havocbound Boost", "bonus": 1}])
		# Swinging WITHOUT a charge: the base's on_charge leg stays shut, the always leg pays.
		assert_array(_main._solo_conditional_ap_parts({"rules": []}, unit, foe, false, -1.0, true)) \
			.is_equal([{"name": "Havocbound Boost", "bonus": 1}])


func test_boost_without_the_base_and_the_base_alone_stay_as_printed() -> void:
	for context in CONTEXTS:
		var foe := _unit([], context[0], context[1])
		# The printed coupling ("If this model has Havocbound"): a Boost without the
		# base pays nothing — the same refusal as the sim's has_exact_rule.
		var orphan := _unit(["Havocbound Boost"], context[0], context[1])
		assert_array(_main._solo_conditional_ap_parts({"rules": []}, orphan, foe, false, 12.0, false)).is_empty()
		# The base alone keeps its two conditional legs (no over-credit, no regression).
		var base := _unit(["Havocbound"], context[0], context[1])
		assert_array(_main._solo_conditional_ap_parts({"rules": []}, base, foe, false, 6.0, false)).is_empty()
		assert_array(_main._solo_conditional_ap_parts({"rules": []}, base, foe, false, 12.0, false)) \
			.is_equal([{"name": "Havocbound", "bonus": 1}])
		assert_array(_main._solo_conditional_ap_parts({"rules": []}, base, foe, true, -1.0, true)) \
			.is_equal([{"name": "Havocbound", "bonus": 1}])


func test_boost_names_the_rule_in_the_ap_trace() -> void:
	# Rules-must-log: the save step's AP trace names the rule (main.gd:6500-6506).
	var unit := _unit(["Havocbound", "Havocbound Boost"], "aof", "havoc_dwarves")
	var foe := _unit([], "aof", "havoc_dwarves")
	var start: int = _main.battle_log.entries().size()
	await _main._solo_resolve_saves(unit, foe, "Rifle", [], 1, 4,
		{"range": 24, "ap": 0, "rules": []}, false, false, true, false, 6.0)
	var named := 0
	for entry in _main.battle_log.entries().slice(start):
		if str(entry["text"]).contains("Havocbound Boost: AP(+1)"):
			named += 1
	assert_int(named).is_equal(1)
