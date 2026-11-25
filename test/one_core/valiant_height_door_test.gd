extends GdUnitTestSuite
## One core C-21 (EPOCH_86_VOLLEY_HEIGHT_REACH, lane S1's soak, 17.11.): Battle Tank -> Hive Swarms, the Hive Bond +1 to the morale roll: table
## 4+ (passes on 4+), core 5+. Valiant-family rules (Valiant, Hold the Line, Hive Bond) count only when the volley came from over 9". The table
## measures that distance with `nearest_melee_gap_in`: model pairs more than the vertical reach apart do not
## count, and a unit with no pair in reach keeps the horizontal unit-centre distance. The core measured the plain base gap, so a target on a platform
## was "inside 9"" there and "beyond" on the table. The fixture: a block of rifles 9" from a ten-model unit that carries Hive Bond (nearest base gap
## 8", unit centres 11" apart), the target raised 5", `SEEDS` seeds, table (AI body) vs core door (live capture + step driver); the morale roll's
## target is what differs. RED at epoch 85, GREEN from 86; the control without the platform is equal at both epochs.
## Real: the main scene, NmlCore, the importer's unit builder, the table's AI body. Constructed: the two units.
## PLAN_FIRST_DELETION 34 FT-C2: the table arm left before step 31 (the AI table resolver retires); door values are pinned as literals read on main af5c83610.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SEEDS := 16
const DICE := "user://valiant_height_dice"

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


func _morale_target(rolls: Array) -> int:
	for x in rolls:
		if str(x["kind"]) == "morale":
			return int(x["target"])
	return -1


## `SEEDS` door volleys at `epoch`: {"morale": volleys where the door rolled a morale die, "targets": the morale roll target per seed}.
func _run(epoch: int, raise_in: float) -> Dictionary:
	AiActRecorder.rules_epoch = epoch
	RosterSweep.arm(_main, ProjectSettings.globalize_path(DICE))
	var volleys: Array = []
	for s in SEEDS:
		volleys.append(await _volley(true, s, raise_in))
	var morale := volleys.filter(func(v: Dictionary) -> bool: return (v["rolls"] as Array).any(
		func(x: Dictionary) -> bool: return str(x["kind"]) == "morale")).size()
	var targets := volleys.map(func(v: Dictionary) -> int: return _morale_target(v["rolls"]))
	print("VALIANT_HEIGHT epoch=%d raise=%s seeds=%d door_morale=%d" % [epoch, raise_in, SEEDS, morale])
	return {"morale": morale, "targets": targets}


## Per-seed morale-roll target on the door, read on main af5c83610.
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_MORALE_86 := 12
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_TARGETS_85 := [5, 5, 5, 5, 5, 5, -1, 5, 5, -1, -1, 5, -1, 5, 5, 5]
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_TARGETS_86 := [4, 4, 4, 4, 4, 4, -1, 4, 4, -1, -1, 4, -1, 4, 4, 4]
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_TARGETS_LEVEL_85 := [5, 5, 5, 5, 5, 5, -1, 5, 5, -1, -1, 5, -1, 5, 5, 5]
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_TARGETS_LEVEL_86 := [5, 5, 5, 5, 5, 5, -1, 5, 5, -1, -1, 5, -1, 5, 5, 5]


func test_a_target_on_a_platform_gets_its_valiant_bonus_in_both_halves() -> void:
	var old := await _run(85, 5.0)
	assert_int(int(old["morale"])).override_failure_message("the fixture must reach the morale roll").is_greater(3)
	assert_array(old["targets"]).override_failure_message("epoch 85: the door's morale target (the old core gap: 5+)").is_equal(WANT_TARGETS_85)
	var now := await _run(86, 5.0)
	assert_int(int(now["morale"])).override_failure_message("the fixture must reach the morale roll").is_equal(WANT_MORALE_86)
	assert_array(now["targets"]).override_failure_message("epoch 86: the door's morale target (4+)").is_equal(WANT_TARGETS_86)


## Control: on level ground the base gap (8") is inside 9" for both, so both drop the Valiant share (5+), at both epochs.
func test_level_ground_is_equal_at_both_epochs() -> void:
	for epoch in [85, 86]:
		var level := await _run(epoch, 0.0)
		assert_int(int(level["morale"])).is_greater(3)
		var want: Array = WANT_TARGETS_LEVEL_85 if epoch == 85 else WANT_TARGETS_LEVEL_86
		assert_array(level["targets"]).override_failure_message("epoch %d, level ground" % epoch).is_equal(want)
