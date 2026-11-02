extends GdUnitTestSuite
## Rules 3.6 row MOR-19b follow-up: the Ethereal band penalty is keyed to the activation that
## took the placement. The Teleport beat stamps `teleport_activation` with the live activation
## serial; the band pass is PURE and prices the -6"/-6" only while that stamp still equals the
## serial. Every read in the placement activation (preview, preview, move) therefore agrees, and
## the next activation's serial drops it. Below EPOCH_73_V36 the penalty stays permanently folded
## and the post-move beat keeps its old activation-start clear, so a second activation still
## places.
##
## The latch is set through the LIVE stamp (`_solo_apply_teleport` with a controller whose policy
## takes the placement), never hand-written into `unit_properties`, so the test drives the same
## seam the AI does.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

class FixedTeleportController extends SoloController:
	var latch_at_decision := false

	func teleport_decision(unit: GameUnit, _rush: bool) -> Dictionary:
		latch_at_decision = bool(unit.unit_properties.get("teleport_used_this_activation", false))
		return {"rule": "Ethereal", "used": true, "to": Vector2(0.2, 0.0)}

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch0: int
var _serial0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	_serial0 = AiActRecorder.activation_serial
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	AiActRecorder.activation_serial = 0
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
	AiActRecorder.activation_serial = _serial0
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


func _place(unit: GameUnit) -> FixedTeleportController:
	var controller: FixedTeleportController = auto_free(FixedTeleportController.new())
	_main.add_child(controller)
	controller.setup(_main.opr_army_manager, _main.network_manager, null)
	_main.solo_controller = controller
	await _main._solo_apply_teleport(unit, {"action": AiDecision.Action.HOLD})
	return controller


func _bands(unit: GameUnit) -> Dictionary:
	return SoloController.move_bands_for_unit(
		unit, _main.movement_range_controller as MovementRangeController)


func test_the_placement_penalty_is_keyed_to_the_placement_activation() -> void:
	var unit := _ethereal_unit()
	await _place(unit)
	# Control: a placement nobody read keeps its latch.
	assert_bool(unit.unit_properties.has("teleport_used_this_activation")).is_true()

	# Two previews and the move read all happen in the placement activation: all carry it.
	for _i in 3:
		var bands: Dictionary = _bands(unit)
		assert_int(bands["advance"]).is_equal(0)   # 6 - 6
		assert_int(bands["rush"]).is_equal(6)      # 12 - 6

	# Reads never mutate the latch or its stamp.
	assert_bool(unit.unit_properties.has("teleport_used_this_activation")).is_true()
	assert_bool(unit.unit_properties.has("teleport_activation")).is_true()

	# The next activation advances the live serial: full bands, no penalty.
	AiActRecorder.activation_serial += 1
	var following: Dictionary = _bands(unit)
	assert_int(following["advance"]).is_equal(6)
	assert_int(following["rush"]).is_equal(12)


func test_below_epoch_73_the_penalty_is_permanent_and_the_latch_is_not_consumed() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var unit := _ethereal_unit()
	await _place(unit)

	for _i in 3:
		var bands: Dictionary = _bands(unit)
		assert_int(bands["advance"]).is_equal(0)   # always-on penalty at 72
		assert_int(bands["rush"]).is_equal(6)
	assert_bool(unit.unit_properties.has("teleport_used_this_activation")).is_true()


func test_below_epoch_73_a_second_activation_still_places() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var unit := _ethereal_unit()
	await _place(unit)
	assert_bool(unit.unit_properties.has("teleport_used_this_activation")).is_true()

	# The old epoch's post-move beat still clears the latch at activation start, so the
	# once-per-activation policy is not refused and the placement works again.
	var second: FixedTeleportController = await _place(unit)
	assert_bool(second.latch_at_decision).is_false()
	assert_bool(unit.unit_properties.has("teleport_used_this_activation")).is_true()
