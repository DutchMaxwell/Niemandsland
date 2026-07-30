extends GdUnitTestSuite
## E2E — transparency wave stage 2 (grilled 2026-07-30): applied rules announce themselves
## AT the table as rising billboard texts on the affected unit, stagger-cascaded. Pinned
## here: the float spawns from the combat seams, and a full burst cascades instead of
## overlapping (distinct stack slots).

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
	_main._solo_batch = false


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _float_labels() -> Array:
	var out: Array = []
	for c in _main.rule_floats.get_children():
		if c is Label3D:
			out.append(c)
	return out


func test_combat_seams_float_their_rules(timeout := 120000) -> void:
	var foe := E2EBoot.make_unit(_main, 2, "Foe", [Vector3.ZERO, Vector3(0.05, 0, 0)])
	_main.opr_army_manager.game_units[foe.unit_id] = foe
	# A Surge six + Blast volley: both rule texts must appear at the table.
	var _hits: int = await _main._solo_hits([6, 3], 3, {"surge": true, "blast": 3}, 14.0, foe)
	await _runner.simulate_frames(2)
	var texts := ""
	for l in _float_labels():
		texts += (l as Label3D).text + "\n"
	assert_str(texts) \
		.override_failure_message("stage 2 — no rule floats spawned at the table (labels: %s)" % texts.strip_edges()) \
		.contains("Surge +1")
	assert_str(texts).contains("Blast")


func test_burst_cascades_into_distinct_slots(timeout := 120000) -> void:
	var foe := E2EBoot.make_unit(_main, 2, "Foe", [Vector3.ZERO])
	_main.opr_army_manager.game_units[foe.unit_id] = foe
	for i in range(4):
		_main._solo_rule_float(foe, "Rule %d" % i)
	await _runner.simulate_frames(2)
	var ys := {}
	for l in _float_labels():
		ys["%.3f" % (l as Label3D).position.y] = true
	assert_int(ys.size()) \
		.override_failure_message("stage 2 — burst texts overlap on one spot (distinct heights: %d)" % ys.size()) \
		.is_greater_equal(4)


func test_toggle_silences_the_floats(timeout := 120000) -> void:
	var foe := E2EBoot.make_unit(_main, 2, "Foe", [Vector3.ZERO])
	_main.opr_army_manager.game_units[foe.unit_id] = foe
	_main.rule_floats.enabled = false
	_main._solo_rule_float(foe, "Hidden")
	assert_int(_float_labels().size()).is_equal(0)
