extends GdUnitTestSuite
## C-4 (shadow run): `CoreShadow.compare` replays the table's AI volley in the core on the shadow board with the table's
## own faces and records {equal, first_diff, labels, unported}. A plain pair is equal; a planted face in the tap is a
## roll-stream difference; a wound-ignore rule not named Regeneration against a Bane weapon (the #2595 table-ahead
## exception, slice design 1a) was NOT equal up to epoch 81 - pinned as a live fact - and is equal from 82 (C-R1a). RED: compare without feeding the faces (or a
## comparator that always says equal) turns the second and third case red; a comparator that never says equal, the first.
## Real: the main scene, NmlCore, the table's `_solo_resolve_ai_volley`, its tray and the tap. Constructed: golden-grid units.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const Harness := preload("res://test/one_core/golden_witness_harness.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch_before: int


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {1: true, 2: true}
	_main._ensure_solo_controller()
	_main.solo_controller.ai_slot = 2
	_main.solo_controller.human_slot = 1
	_main.solo_controller.last_move_paths = []
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true
	CoreActivation._env = 1
	CoreShadow._env = 1
	CoreShadow.records.clear()


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	CoreShadow._env = -1
	CoreShadow.records.clear()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## One table volley of `weapon` from the golden attacker at `defender`, shadowed; `plant` edits the tap before the
## compare. Returns the shadow record.
func _shadowed(weapon: Dictionary, defender: Dictionary, seed: int, plant: Callable = Callable()) -> Dictionary:
	var att := ParityTable._make_unit(_main, Harness.ATTACKER, weapon.duplicate(true))
	var dfn := ParityTable._make_unit(_main, defender, {})
	var dist_in := float(defender["x_in"]) - float(Harness.ATTACKER["x_in"])
	var plist: Array = AiShooting.profiles_in_range([(att.source_data as OPRApiClient.OPRUnit).weapons[0]], dist_in)
	var shots: Array = []
	for p in plist:
		shots.append({"member": att, "quality": att.get_quality(), "alive": att.get_alive_count(), "max": att.models.size(),
			"reach": float(weapon["range_in"]), "profile": p})
	_main._solo_core_shadow_h = CoreShadow.capture(_main, att)
	assert_int(_main._solo_core_shadow_h).override_failure_message("no shadow board").is_not_equal(0)
	_main.seed_tray_rng(seed)
	await _main._solo_resolve_ai_volley(att, dfn, shots)
	if plant.is_valid():
		plant.call(CoreShadow.tap)
	CoreShadow.compare(_main, att, {"action": AiDecision.Action.HOLD, "moved": false}, {dfn.unit_id: {"target": dfn, "shots": shots}},
		[dfn.unit_id])
	CoreShadow.release(_main)
	Harness._free_units(_main, [att, dfn])
	await _main.get_tree().process_frame
	assert_int(CoreShadow.records.size()).override_failure_message("no shadow record").is_greater(0)
	return CoreShadow.records[-1]


func test_a_plain_pair_replays_equal() -> void:
	for seed in [1, 2, 3, 4]:
		var rec := await _shadowed(Harness.RIFLE, Harness.DEFENDER, seed)
		assert_dict(rec).override_failure_message("seed %d: %s" % [seed, rec]).contains_key_value("equal", true)
		assert_array(rec["unported"]).is_empty()
		assert_array(rec["deny"]).override_failure_message("C-18: the deny-mode slice takes a plain pair").is_empty()


## The first hit roll's faces all set to 6 (the table had misses): the core asks a save roll of another size.
func test_a_planted_face_is_a_roll_stream_difference() -> void:
	var plant := func(tap: Array) -> void:
		var faces: Array = tap[0]["faces"]
		assert_bool(faces.has(6) and faces.any(func(f: Variant) -> bool: return int(f) < 4)) \
			.override_failure_message("fixture: the first roll needs a hit and a miss: %s" % [faces]).is_true()
		for i in faces.size():
			faces[i] = 6
	var rec := await _shadowed(Harness.RIFLE, Harness.DEFENDER, 3, plant)
	assert_dict(rec).contains_key_value("equal", false).contains_key_value("first_diff", "rolls")


## Slice design 1a, closed by C-R1a (epoch 82): Self-Repair (a wound-ignore rule not named Regeneration) still rolls against Bane on the
## table. Up to epoch 81 the core's one-family roll was bypassed whole, so some seed with an unsaved wound replayed unequal (the red leg,
## the difference pinned as a live fact); from 82 the core rolls the bypassed wounds too and every seed replays equal.
func _self_repair_vs_bane_unequal(epoch: int) -> int:
	AiActRecorder.rules_epoch = epoch
	var unequal := 0
	for seed in [1, 2, 3, 4, 5, 6]:
		var rec := await _shadowed(Harness._weapon(["Bane"]), Harness._with(Harness.DEFENDER, {"rules": ["Self-Repair"]}), seed)
		unequal += 0 if bool(rec["equal"]) else 1
		assert_bool(rec["labels"].has("target_rule:Self-Repair")).override_failure_message("labels %s" % [rec["labels"]]).is_true()
		# C-R1 lifted the wound-ignore entry: deny mode no longer refuses the Self-Repair target (the pair's own verdict is the gate).
		assert_array(rec["deny"]).override_failure_message("Self-Repair left the deny list with C-R1").not_contains(["target_unit_rule:Self-Repair"])
	return unequal


func test_a_wound_ignore_by_name_pair_is_not_equal_at_epoch_81() -> void:
	assert_int(await _self_repair_vs_bane_unequal(81)).override_failure_message("Self-Repair vs Bane replayed equal on every seed").is_greater(0)


func test_a_wound_ignore_by_name_pair_is_equal_from_epoch_82() -> void:
	assert_int(await _self_repair_vs_bane_unequal(82)).override_failure_message("Self-Repair vs Bane still differs at 82").is_equal(0)
