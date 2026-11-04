extends GdUnitTestSuite
## G4-T5 (lead ruling O6): the table's shooting reach must measure the true OVAL edge instead of the
## circumscribed radius. Two 70x105 mm oval bases stand 10.4" apart edge to edge along their short
## axes, so a 9" weapon is out of reach. The old centre distance plus both circumscribed radii reads
## 8.2" and lets the shot through. Below EPOCH_73_V36 the old read stands (recorded corpora replay).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

const IN2M := 0.0254
const OVAL_W_MM := 70.0
const OVAL_D_MM := 105.0
const TRUE_GAP_IN := 10.4
const WEAPON_RANGE_IN := 9

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	AiActRecorder.rules_epoch = _epoch0
	RulesRegistry.reset_cache()


## A real unit on a 70x105 mm oval base with one 9" ranged weapon.
func _oval_unit(pid: int, unit_name: String, pos: Vector3) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [pos])
	u.unit_properties["base_is_oval"] = true
	u.unit_properties["base_width_mm"] = int(OVAL_W_MM)
	u.unit_properties["base_depth_mm"] = int(OVAL_D_MM)
	u.unit_properties["base_size_round"] = 0
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Pistol"
	w.range_value = WEAPON_RANGE_IN
	w.attacks = 2
	w.count = 1
	var src := OPRApiClient.OPRUnit.new()
	src.weapons = [w]
	u.source_type = "opr"
	u.source_data = src
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## X offset (metres) that puts the two short axes 10.4" apart edge to edge.
func _oval_target_x() -> float:
	return TRUE_GAP_IN * IN2M + OVAL_W_MM * 0.001


func _pair() -> Array:
	var gunner := _oval_unit(1, "Oval Gunners", Vector3.ZERO)
	var target := _oval_unit(2, "Oval Grunts", Vector3(_oval_target_x(), 0, 0))
	return [gunner, target]


# ===== fixture control (green on main) =====

func test_control_the_fixture_is_10_4_inches_edge_to_edge() -> void:
	var pair := _pair()
	var gap: float = _main.solo_controller.nearest_melee_pair_info(pair[0], pair[1], false)["gap_in"]
	assert_float(gap).override_failure_message("fixture broken: true edge gap is %.2f\"" % gap) \
		.is_equal_approx(TRUE_GAP_IN, 0.02)


# ===== the defect (RED on main: both doors take the 9" shot) =====

func test_the_ai_sight_gate_refuses_the_shot_past_the_oval_edge() -> void:
	var pair := _pair()
	var sighted: int = _main._solo_sighted_count(pair[0], pair[1], WEAPON_RANGE_IN)
	assert_int(sighted).override_failure_message(
		"the 9\" weapon reached a 10.4\" oval edge: the circumscribed slack is still in the gate") \
		.is_equal(0)


func test_the_human_profile_gate_refuses_the_same_shot() -> void:
	var pair := _pair()
	var dist: float = _main.solo_controller.nearest_melee_gap_in(pair[0], pair[1])
	var groups: Array = _main._solo_attack_groups(pair[0], dist, false, pair[1])
	assert_array(groups).override_failure_message(
		"the human gate offered a weapon at a 10.4\" oval edge with 9\" range").is_empty()


# ===== epoch control (must stay green: recorded corpora replay byte-exact) =====

func test_below_epoch_73_the_circumscribed_read_still_takes_the_shot() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var pair := _pair()
	assert_int(_main._solo_sighted_count(pair[0], pair[1], WEAPON_RANGE_IN)) \
		.override_failure_message("epoch 72 must keep the recorded circumscribed read") \
		.is_equal(1)
	var dist: float = _main.solo_controller.nearest_melee_gap_in(pair[0], pair[1])
	assert_array(_main._solo_attack_groups(pair[0], dist, false, pair[1])) \
		.override_failure_message("epoch 72 must keep the recorded human gate") \
		.is_not_empty()
