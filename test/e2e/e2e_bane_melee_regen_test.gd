extends GdUnitTestSuite
## E2E — the unit-level Bane names "Bane in Melee" (gf common) and "Bane in Melee Buff"
## (human_defense_force) on the REAL main.tscn.
##
## The sixes-re-roll half resolves: the table's own Bane ladder (main.gd:6672) scopes the melee
## name to melee. The Regeneration BYPASS half did not: `_solo_ignores_regen` scanned only the
## weapon-printed Bane rules and the Lacerate/Rending primitive entries, so a unit-level
## "Bane in Melee" carrier's melee wounds stayed Regeneration-able while the core refuses the
## heal (unit.rs:2519, the melee-scoped arm at 2549-2551) — a Regeneration unit heals on the
## table and dies in the sim.

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
	var u := E2EBoot.make_unit(_main, 2, "Bane Carrier", [Vector3.ZERO])
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["faction_folder"] = "human_defense_force"
	u.unit_properties["special_rules"] = rules
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## The claim: a unit-level "Bane in Melee" carrier's MELEE wounds ignore Regeneration.
func test_bane_in_melee_melee_wounds_bypass_regeneration() -> void:
	var striker := _carrier(["Bane in Melee"])
	assert_bool(_main._solo_ignores_regen(striker, {"range": 0, "rules": []})) \
		.override_failure_message("melee profile: the name's regen bypass must fire") \
		.is_true()


## ROT: the melee scope — a ranged profile of the same carrier stays Regeneration-able
## (shooting untouched, exactly how main.gd:6672 scopes the name).
func test_bane_in_melee_ranged_wounds_do_not_bypass_regeneration() -> void:
	var striker := _carrier(["Bane in Melee"])
	assert_bool(_main._solo_ignores_regen(striker, {"range": 24, "rules": []})).is_false()


## The Buff variant (human_defense_force, unit-level) makes the same claim — same melee scope.
func test_bane_in_melee_buff_melee_wounds_bypass_regeneration() -> void:
	var striker := _carrier(["Bane in Melee Buff"])
	assert_bool(_main._solo_ignores_regen(striker, {"range": 0, "rules": []})) \
		.override_failure_message("the Buff shares the 'Bane in Melee' melee scope") \
		.is_true()


func test_bane_in_melee_buff_ranged_wounds_do_not_bypass_regeneration() -> void:
	var striker := _carrier(["Bane in Melee Buff"])
	assert_bool(_main._solo_ignores_regen(striker, {"range": 24, "rules": []})).is_false()


## CENSUS (#782 rule, the #489 lesson): the bypass is gated on the melee-scoped NAME, never a
## bare "Bane" prefix on the unit level — the twin name "Bane when Shooting" must not inherit
## the melee bypass.
func test_bane_when_shooting_does_not_inherit_the_melee_bypass() -> void:
	var striker := _carrier(["Bane when Shooting"])
	assert_bool(_main._solo_ignores_regen(striker, {"range": 0, "rules": []})) \
		.override_failure_message("the bypass is name-gated to the 'Bane in Melee' scope") \
		.is_false()


## CONTROL: a weapon-embedded Bane still bypasses (the weapon-printed loop, unchanged).
func test_weapon_level_bane_still_bypasses() -> void:
	var striker := _carrier([])
	assert_bool(_main._solo_ignores_regen(striker, {"range": 0, "rules": ["Bane"]})).is_true()
