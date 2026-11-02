extends GdUnitTestSuite
## Rules 3.6 row MOR-19b follow-up: the Ethereal placement latch is consumed by the band pass that
## reads it, not by the post-move Teleport beat. The placement therefore prices exactly ONE move
## read — the move it was made for — and the next activation is clean. Below EPOCH_73_V36 the
## penalty stays permanently folded and the latch is untouched (today's 3.5 behaviour).
##
## The latch is set through the LIVE stamp (`_solo_apply_teleport` with a controller whose policy
## takes the placement), never hand-written into `unit_properties`, so the test drives the same
## seam the AI does.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

class FixedTeleportController extends SoloController:
	func teleport_decision(_unit: GameUnit, _rush: bool) -> Dictionary:
		return {"rule": "Ethereal", "used": true, "to": Vector2(0.2, 0.0)}

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
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
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests — restore
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _ethereal_unit() -> GameUnit:
	var unit := E2EBoot.make_unit(_main, 2, "Ghost", [Vector3(0.2, 0, 0)])
	unit.unit_properties["game_system"] = "aof"
	unit.unit_properties["faction_folder"] = "ghostly_undead"
	unit.unit_properties["special_rules"] = ["Ethereal"]
	_main.opr_army_manager.game_units[unit.unit_id] = unit
	return unit


func _place(unit: GameUnit) -> void:
	var controller: FixedTeleportController = auto_free(FixedTeleportController.new())
	_main.add_child(controller)
	controller.setup(_main.opr_army_manager, _main.network_manager, null)
	_main.solo_controller = controller
	await _main._solo_apply_teleport(unit, {"action": AiDecision.Action.HOLD})


func _bands(unit: GameUnit) -> Dictionary:
	return SoloController.move_bands_for_unit(
		unit, _main.movement_range_controller as MovementRangeController)


func test_the_placement_penalty_is_consumed_by_the_band_read() -> void:
	var unit := _ethereal_unit()
	await _place(unit)
	# Control: a placement nobody read keeps its latch.
	assert_bool(unit.unit_properties.has("teleport_used_this_activation")).is_true()

	# The placement move carries the penalty exactly once.
	var placed: Dictionary = _bands(unit)
	assert_int(placed["advance"]).is_equal(0)   # 6 - 6
	assert_int(placed["rush"]).is_equal(6)      # 12 - 6
	assert_bool(unit.unit_properties.has("teleport_used_this_activation")).is_false()

	# The following activation does not.
	var following: Dictionary = _bands(unit)
	assert_int(following["advance"]).is_equal(6)
	assert_int(following["rush"]).is_equal(12)


func test_below_epoch_73_the_penalty_is_permanent_and_the_latch_is_not_consumed() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var unit := _ethereal_unit()
	await _place(unit)

	var bands: Dictionary = _bands(unit)
	assert_int(bands["advance"]).is_equal(0)   # always-on penalty at 72
	assert_int(bands["rush"]).is_equal(6)
	assert_bool(unit.unit_properties.has("teleport_used_this_activation")).is_true()
