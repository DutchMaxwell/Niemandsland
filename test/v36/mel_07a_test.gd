extends GdUnitTestSuite
## Rules 3.6 wave, row MEL-07a: from rules epoch 73 (the core's EPOCH_73_V36) one melee strike rolls
## every hit of the attacking unit before any save (no rule, only the draw order; Parry will sit between
## the two). Epoch 72 keeps today's order: each weapon rolls its hits and then its saves before the next
## weapon rolls. The faces are the core's for the same seeded strike
## (core/nml-core/src/tests/dice/v36_melee.rs, `mod mel_07a`): both engines draw the same dice in the
## same order.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const SEED := 7360

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
	_main._solo_batch = true


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests — restore
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _weapon(weapon_name: String) -> OPRApiClient.OPRWeapon:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = weapon_name
	w.range_value = 0
	w.attacks = 4
	w.count = 1
	return w


## A Quality 4 model with two plain 4-attack melee weapons (the e2e_shaken_strikeback shape, two weapons).
func _two_weapon_striker() -> GameUnit:
	var u := E2EBoot.make_unit(_main, 1, "Guards", [Vector3.ZERO])
	(u.models[0] as ModelInstance).model_index = 0
	var src := OPRApiClient.OPRUnit.new()
	src.weapons = [_weapon("Blade"), _weapon("Spear")]
	u.source_type = "opr"
	u.source_data = src
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## A Defense 4 AI unit of 10 in reach: its saves roll in the tray, and no model dies between batches.
func _foe() -> GameUnit:
	var spots: Array = []
	for i in 10:
		spots.append(Vector3(0.5 * INCH, 0, (float(i) - 4.5) * 0.3 * INCH))
	var foe := E2EBoot.make_unit(_main, 2, "Grunts", spots)
	_main.opr_army_manager.game_units[foe.unit_id] = foe
	return foe


## The strike-back (no charge) at `epoch` on tray seed 7360: every tray roll as [roll kind, faces].
func _strike_rolls(epoch: int) -> Array:
	AiActRecorder.rules_epoch = epoch
	var striker := _two_weapon_striker()
	var foe := _foe()
	_main._solo_dice_trace_enabled = true
	_main.solo_controller.decision_log.clear()
	_main.seed_tray_rng(SEED)
	await _main._solo_melee_strike_phase(striker, foe, false, 0)   # 0 = SoloStrike.ALL
	var rolls: Array = []
	for rec in _main.solo_controller.decision_log:
		if str((rec as Dictionary).get("kind", "")) == "dice":
			rolls.append([str(rec["roll_kind"]), Array(rec["faces"])])
	await E2EBoot.settle(get_tree())
	return rolls


func test_each_weapon_rolls_its_hits_then_its_saves_at_epoch_72() -> void:
	var rolls: Array = await _strike_rolls(AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	assert_str(str(rolls)) \
		.override_failure_message("epoch 72 keeps the interleaved order (hits, saves, hits, saves): %s" % str(rolls)) \
		.is_equal(str([["attack", [2, 2, 6, 5]], ["defense", [4, 3]], ["attack", [3, 5, 2, 4]], ["defense", [4, 2]]]))


func test_every_hit_roll_comes_before_any_save_at_epoch_73() -> void:
	var rolls: Array = await _strike_rolls(AiActRecorder.EPOCH_73_V36)
	assert_str(str(rolls)) \
		.override_failure_message("epoch 73 rolls both weapons' hits before any save: %s" % str(rolls)) \
		.is_equal(str([["attack", [2, 2, 6, 5]], ["attack", [4, 3, 3, 5]], ["defense", [2, 4]], ["defense", [4, 2]]]))
