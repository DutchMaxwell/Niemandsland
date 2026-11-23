extends GdUnitTestSuite
## One core C-17 (split fire through the door, P4.D-14): an AI activation whose weapons pick DIFFERENT targets (the table's overlay pick: a
## plain rifle at the nearest unit, a Deadly lance at the Tough one) used to stay on the table whole (`order.size() == 1`); the 52 split
## volleys of the 17.11. soak were the table's. Now `run_ai` takes the further groups, sends the split aim (member NAME, weapon, target key;
## `sim.rs split_plan`) and stages each group as its own volley. This is the soak's volley shape as a fixture: one shooter, two targets, two
## weapons, `SEEDS` seeds, on the table (no core handle) and through the production door (`_run_ai_shooting` with the live capture) under the
## deny slice (the plain slice refuses every weapon rule, so only deny mode meets a split). Dice by parity_compare.py, end state of all
## three units here. RED before the door took groups: `CoreActivation.ai_runs` stays 0 (the core never ran it); GREEN: it ran, dice and
## state equal. Real: the main scene, NmlCore, the importer's unit builder, the table's AI body and target pick. Constructed: the units.
##
## PLAN_FIRST_DELETION 34 FT-C5: the table arm left before step 31 (the AI table resolver retires); door values are pinned as literals read on main af5c83610.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const SlicePin := preload("res://test/one_core/slice_pin.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SEEDS := 16
const DICE := "user://split_door_dice"

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	SlicePin.dice_only()   # the dice are the subject: the production deny list minus its line refusals (DLINES2)
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.combat_stage.force_for_tests = true   # the stage runs headless: its headline says which group was staged last
	GraphicsSettings.combat_stage_hold_s = 0.0


func after_test() -> void:
	GraphicsSettings.combat_stage_hold_s = 2.5
	SlicePin.release_dice_only()
	RosterSweep.disarm(_main)
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _weapon(wname: String, rules: Array, attacks := 2) -> OPRApiClient.OPRWeapon:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = wname
	w.range_value = 24
	w.attacks = attacks
	w.count = 1
	w.special_rules.assign(rules)
	return w


func _entry(uname: String, size: int, rules: Array, weapons: Array) -> Dictionary:
	var ou := OPRApiClient.OPRUnit.new()
	ou.name = uname
	ou.size = size
	ou.quality = 4
	ou.defense = 4
	ou.game_system = "gf"
	ou.special_rules.assign(rules)
	for w in weapons:
		ou.weapons.append(w)
	return {"unit": ou, "faction": "battle_brothers", "system": "gf"}


## One activation of `shooter` at the two targets on one path. `core` = the production door (a live capture handed to `_run_ai_shooting`).
func _volley(shooter: Dictionary, targets: Array, seed_n: int, core: bool) -> Dictionary:
	var att := RosterSweep.spawn(_main, shooter, RosterSweep.SEAT_SHOOTER, 0.0)
	var foes: Array = []   # [GameUnit]; targets = [[entry, x_in, z_in]]
	for t in targets:
		var gu := RosterSweep.spawn(_main, t[0], RosterSweep.SEAT_TARGET, float(t[1]))
		for m in gu.models:
			(m as ModelInstance).node.global_position.z += float(t[2]) * RosterSweep.INCH
		foes.append(gu)
	var a: GameUnit = foes[0]
	var b: GameUnit = foes[foes.size() - 1]
	_main.seed_tray_rng(seed_n)
	var split_before := int((CoreActivation.legacy.get("ai_volley", {}) as Dictionary).get("split", 0))
	var runs_before := CoreActivation.ai_runs
	var refusals_before := CoreActivation.ai_refusals
	CoreActivation.reset_all(_main)
	_main._solo_core_ai_h = CoreActivation.capture(_main) if core else 0
	await _main._run_ai_shooting({"unit": att, "moved": false, "action": AiDecision.Action.HOLD})
	if _main._solo_core_ai_h != 0:
		_main.solo_controller._core_node_ready().release(_main._solo_core_ai_h)
		_main._solo_core_ai_h = 0
	AiDiceRecorder.close()
	var out := {"rolls": ParityTable._read_dice(ProjectSettings.globalize_path(DICE)), "state": RosterSweep.state_of(att, a),
		"state_b": RosterSweep.state_of(att, b), "labels": {"att": [], "tgt": []}, "names": [att.get_name(), a.get_name()],
		"split": int((CoreActivation.legacy.get("ai_volley", {}) as Dictionary).get("split", 0)) - split_before,
		"runs": CoreActivation.ai_runs - runs_before, "refusals": CoreActivation.ai_refusals - refusals_before,
		"stage": _main.combat_stage._headline}
	RosterSweep.free_units(_main, [att] + foes)
	await _main.get_tree().process_frame
	return out


func _run(shooter: Dictionary, targets: Array) -> Dictionary:
	RosterSweep.arm(_main, ProjectSettings.globalize_path(DICE))
	CoreActivation._env = 1   # the door ON: `arm` set the table half's kill switch
	var core_runs := 0
	var core_refusals := 0
	for s in SEEDS:
		var core := await _volley(shooter, targets, s, true)
		core_runs += int(core["runs"])
		core_refusals += int(core["refusals"])
	print("SPLIT_DOOR seeds=%d core_runs=%d core_refusals=%d" % [SEEDS, core_runs, core_refusals])
	return {"core_runs": core_runs, "core_refusals": core_refusals}


## Two weapons of one name aimed at two targets: the core would fire one of them and pool the rest (`split_weapon_reaimed`), so the door
## refuses before any die.
func test_one_weapon_name_aimed_at_two_targets_stays_on_the_table() -> void:
	var shooter := _entry("Squad", 6, [], [_weapon("Gun", []), _weapon("Gun", ["Deadly(3)"], 1)])
	var r := await _run(shooter, [[_entry("Grunts", 5, [], []), 10.0, -5.0], [_entry("Brute", 1, ["Tough(6)"], []), 16.0, 5.0]])
	assert_int(int(r["core_runs"])).override_failure_message("the core took an aim it would pool").is_equal(0)
	assert_int(int(r["core_refusals"])).is_equal(0)
