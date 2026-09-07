extends GdUnitTestSuite
## E2E — the wave-4 family name "Rending in Melee" (aof common: `on6_ap 4, bypass_regen, melee_only`)
## on the REAL main.tscn.
##
## The rending HALF resolves: the facet stamp (ai_ev.gd, Rending aliases) puts `rending` on the melee
## profiles only, and the AP(+4) sub-batch reads it. The Regeneration-BYPASS half did not: the dice
## path's `_solo_ignores_regen` consulted the profile's weapon rules and the Lacerate-primitive
## aliases, but a unit-level "Rending in Melee" (direct or aura-granted — the only way the books
## field it) sits in neither, so its melee wounds stayed Regeneration-able while the entry's own
## `bypass_regen: true` says they must not be.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _carrier(rules: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, 2, "Rending Carrier", [Vector3.ZERO])
	u.unit_properties["game_system"] = "aof"
	u.unit_properties["faction_folder"] = "saurians"
	u.unit_properties["special_rules"] = rules
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## The claim: a unit-level "Rending in Melee" carrier's MELEE wounds ignore Regeneration.
func test_rending_in_melee_melee_wounds_bypass_regeneration() -> void:
	var striker := _carrier(["Rending in Melee"])
	assert_bool(_main._solo_ignores_regen(striker, {"range": 0, "rules": []})) \
		.override_failure_message("melee profile: the entry's bypass_regen must fire") \
		.is_true()


## ROT: the melee_only facet — a ranged profile of the same carrier stays Regeneration-able.
func test_rending_in_melee_ranged_wounds_do_not_bypass_regeneration() -> void:
	var striker := _carrier(["Rending in Melee"])
	assert_bool(_main._solo_ignores_regen(striker, {"range": 24, "rules": []})).is_false()


## CONTROL: a weapon-embedded plain Rending still bypasses (loop 1, unchanged by the fix).
func test_weapon_level_rending_still_bypasses() -> void:
	var striker := _carrier([])
	assert_bool(_main._solo_ignores_regen(striker, {"range": 0, "rules": ["Rending"]})).is_true()
