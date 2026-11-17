extends GdUnitTestSuite
## One core C-21 (EPOCH_86_VOLLEY_HEIGHT_REACH, lane S1's soak, 17.11.): Battle Tank -> Hive Swarms, the Hive Bond +1 to the morale roll: table
## 4+ (passes on 4+), core 5+. Valiant-family rules (Valiant, Hold the Line, Hive Bond) count only when the volley came from over 9". The table
## measures that distance with `_solo_ai_volley_distance_in` over `nearest_melee_gap_in`: model pairs more than the vertical reach apart do not
## count, and a unit with no pair in reach keeps the horizontal unit-centre distance. The core measured the plain base gap, so a target on a platform
## was "inside 9"" there and "beyond" on the table. The fixture: a block of rifles 9" from a ten-model unit that carries Hive Bond (nearest base gap
## 8", unit centres 11" apart), the target raised 5", `SEEDS` seeds, table (AI body) vs core door (live capture + step driver); the morale roll's
## target is what differs. RED at epoch 85, GREEN from 86; the control without the platform is equal at both epochs.
## Real: the main scene, NmlCore, the importer's unit builder, the table's AI body. Constructed: the two units.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SEEDS := 16
const DICE := "user://valiant_height_dice"
const OUT := "user://valiant_height_out"

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


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	RosterSweep.disarm(_main)
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _entry(uname: String, size: int, rules: Array, guns: int) -> Dictionary:
	var ou := OPRApiClient.OPRUnit.new()
	ou.name = uname
	ou.size = size
	ou.quality = 3 if guns > 0 else 5
	ou.defense = 6
	ou.game_system = "gf"
	ou.special_rules.assign(rules)
	if guns > 0:
		var w := OPRApiClient.OPRWeapon.new()
		w.name = "Rifle"
		w.range_value = 24
		w.attacks = 1
		w.count = guns
		ou.weapons.append(w)
	return {"unit": ou, "faction": "alien_hives", "system": "gf"}


## One HOLD activation of the rifles at the target (raised `raise_in` inches) on one path; returns the dice as "kind@target" strings.
func _volley(core: bool, seed_n: int, raise_in: float) -> Dictionary:
	var att := RosterSweep.spawn(_main, _entry("Rifles", 12, [], 12), RosterSweep.SEAT_SHOOTER, 0.0)
	var tgt := RosterSweep.spawn(_main, _entry("Swarm", 10, ["Hive Bond"], 0), RosterSweep.SEAT_TARGET, 9.0)
	for m in tgt.models:
		(m as ModelInstance).node.global_position.y += raise_in * RosterSweep.INCH
	_main.seed_tray_rng(seed_n)
	if core:
		CoreActivation.reset_all(_main)
		var h := CoreActivation.capture(_main)
		var at: Array = att.get_alive_models().map(func(m: ModelInstance) -> Vector3: return m.node.global_position)
		var trails: Array = att.get_alive_models().map(func(_m: ModelInstance) -> Array: return [])
		var t: Array = [{"t": "begin"}, {"t": "placed", "positions": at, "trails": trails},
			{"t": "intent", "kind": AiDecision.Action.HOLD, "shoot": tgt.unit_id}]
		var r: Dictionary = await CoreActivation.drive(_main, h, att, t, true)
		if str(r["step"]) != "done":
			_main.solo_controller._core_node_ready().release(h)
	else:
		_main._solo_core_ai_h = 0
		await _main._run_ai_shooting({"unit": att, "moved": false, "action": AiDecision.Action.HOLD})
	AiDiceRecorder.close()
	var out := {"rolls": ParityTable._read_dice(ProjectSettings.globalize_path(DICE)), "state": RosterSweep.state_of(att, tgt),
		"labels": {"att": [], "tgt": []}, "names": [att.get_name(), tgt.get_name()]}
	RosterSweep.free_units(_main, [att, tgt])
	await _main.get_tree().process_frame
	return out


## `SEEDS` volleys on both paths at `epoch`: {"bad": mismatching volleys, "morale": volleys where the TABLE rolled a morale die}.
func _run(epoch: int, raise_in: float) -> Dictionary:
	AiActRecorder.rules_epoch = epoch
	RosterSweep.arm(_main, ProjectSettings.globalize_path(DICE))
	var rows: Array = []
	for s in SEEDS:
		var table := await _volley(false, s, raise_in)
		var core := await _volley(true, s, raise_in)
		rows.append({"id": s, "pair": "fixture", "dir": 0, "seed": s, "att": (table["names"] as Array)[0], "tgt": (table["names"] as Array)[1],
			"table": table, "core": core})
	var cmp := RosterSweep.compare(rows, OUT)
	var bad := (cmp["verdicts"] as Array).filter(func(v: Dictionary) -> bool: return str(v["first_diff"]) != "").size()
	var morale := rows.filter(func(r: Dictionary) -> bool: return (r["table"]["rolls"] as Array).any(
		func(x: Dictionary) -> bool: return str(x["kind"]) == "morale")).size()
	print("VALIANT_HEIGHT epoch=%d raise=%s seeds=%d table_morale=%d mismatches=%d" % [epoch, raise_in, SEEDS, morale, bad])
	return {"bad": bad, "morale": morale}


func test_a_target_on_a_platform_gets_its_valiant_bonus_in_both_halves() -> void:
	var old := await _run(85, 5.0)
	assert_int(int(old["morale"])).override_failure_message("the fixture must reach the morale roll").is_greater(3)
	assert_int(int(old["bad"])).override_failure_message("epoch 85 must differ (the red leg: core 5+, table 4+)").is_equal(int(old["morale"]))
	var now := await _run(86, 5.0)
	assert_int(int(now["bad"])).override_failure_message("epoch 86: table and core differ").is_equal(0)


## Control: on level ground the base gap (8") is inside 9" for both, so both drop the Valiant share (5+), at both epochs.
func test_level_ground_is_equal_at_both_epochs() -> void:
	for epoch in [85, 86]:
		var level := await _run(epoch, 0.0)
		assert_int(int(level["morale"])).is_greater(3)
		assert_int(int(level["bad"])).override_failure_message("epoch %d, level ground" % epoch).is_equal(0)
