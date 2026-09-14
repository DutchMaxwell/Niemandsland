extends GdUnitTestSuite
## E2E — STANDALONE_SWEEP_E_2026-09-14 row "Empyrean Spirit Boost" (DIVERGES).
##
## The Boost is the printed UNCONDITIONAL form of Empyrean Spirit's own -1
## ("enemies attacking them always get -1 to hit"): it REPLACES the base's
## over-9" conditional alias, it does not add a second -1. The core's named
## gate stands the base's alias down (core/nml-core/src/unit.rs:2176-2200);
## the table used to stack the two into a -2 on any shot past 9".
## This suite boots the real scene and calls the very function the dice path
## calls (_solo_hit_mod_info), the e2e_dead_aura_effects_test.gd precedent.

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


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _unit(rules: Array) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "esb_%d" % rules.size()
	u.unit_properties = {"player_id": 2, "name": "Wraith", "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": "aof", "faction_folder": "ghostly_undead"}
	var m := ModelInstance.new()
	m.is_alive = true
	u.models.append(m)
	return u


func test_a_shot_from_twelve_inches_at_a_boosted_wraith_carries_one_minus_one_not_two() -> void:
	# The defect: the base's over-9" alias subtracted ON TOP of the Boost's
	# unconditional Evasive — a -2 no book reading supports.
	var target := _unit(["Empyrean Spirit", "Empyrean Spirit Boost"])
	var shooter := _unit([])
	var far: Dictionary = _main._solo_hit_mod_info(shooter, target, 12.0, false)
	assert_int(int(far.get("mod", 0))) \
		.override_failure_message("a 12\" shot at a Boosted wraith stacked the base alias onto the Boost (note: %s)" % far.get("note", "")) \
		.is_equal(-1)
	assert_str(str(far.get("note", ""))) \
		.override_failure_message("the rules-must-log trace must name the rule once (note: %s)" % far.get("note", "")) \
		.contains("Empyrean Spirit Boost: -1 to hit (base Evasive stood down)")


func test_the_single_minus_one_holds_at_any_range() -> void:
	# "at any range" — inside 9" the base alias never fired; the Boost keeps
	# exactly one -1 there too.
	var target := _unit(["Empyrean Spirit", "Empyrean Spirit Boost"])
	var shooter := _unit([])
	var near: Dictionary = _main._solo_hit_mod_info(shooter, target, 6.0, false)
	assert_int(int(near.get("mod", 0))) \
		.override_failure_message("a 6\" shot at a Boosted wraith lost the Boost's -1 (note: %s)" % near.get("note", "")) \
		.is_equal(-1)


func test_the_base_alias_still_fires_for_a_plain_carrier() -> void:
	# Control: without the Boost the conditional over-9" alias keeps its -1 —
	# the stand-down must not break the plain Empyrean Spirit carrier.
	var target := _unit(["Empyrean Spirit"])
	var shooter := _unit([])
	var far: Dictionary = _main._solo_hit_mod_info(shooter, target, 12.0, false)
	assert_int(int(far.get("mod", 0))) \
		.override_failure_message("fixture broken: the plain carrier's over-9\" alias must still fire (note: %s)" % far.get("note", "")) \
		.is_equal(-1)
	assert_str(str(far.get("note", ""))).contains("Empyrean Spirit -1")


func test_melee_keeps_one_minus_one_and_names_the_rule() -> void:
	# Melee never stacked (best single penalty), but the rules-must-log trace
	# must name the applied rule, the core's melee seam precedent.
	var target := _unit(["Empyrean Spirit", "Empyrean Spirit Boost"])
	var shooter := _unit([])
	var melee: Dictionary = _main._solo_hit_mod_info(shooter, target, 0.0, true)
	assert_int(int(melee.get("mod", 0))) \
		.override_failure_message("melee at a Boosted wraith lost the single -1 (note: %s)" % melee.get("note", "")) \
		.is_equal(-1)
	assert_str(str(melee.get("note", ""))) \
		.override_failure_message("the melee trace must name the rule once (note: %s)" % melee.get("note", "")) \
		.contains("Empyrean Spirit Boost: -1 to hit (base Evasive stood down)")
