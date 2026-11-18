extends GdUnitTestSuite
## P4.D-42: before the human split goes through the core, this gate pins that the core's split result equals the
## table's `_run_human_attack_split` for the same clicks and dice. The table declares the Pistol group on target B and
## fires the rest at A; the core gets the same aim as a `split` intent on the step driver. Two shapes over 40 seeds
## each: two targets, and a target the first group empties. Dice by parity_compare.py (RosterSweep), end state of all
## three units here. RED (planted fault, `_run(shape, "swap")`): the second group's target is swapped on the core path.
## Real: the main scene, NmlCore, the importer's unit builder, the table's human split door and the step driver.
## Constructed: the units, their kit and their positions.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SEEDS := 40
const DICE := "user://human_split_dice"
const OUT := "user://human_split_out"
const INCH := 0.0254
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}
const KIT := [["Rifle", 5, 24], ["Pistol", 5, 12]]
const B_NAMES := ["Pistol"]
const TWO := {"name": "two_targets", "a_models": 5, "a_defense": 4, "attacks": 1, "quality": 4}
## The second shape: one model, Defense 7 (saves only on a 6) and 10 dice, so the first group empties it every seed.
const EMPTY := {"name": "a_emptied", "a_models": 1, "a_defense": 7, "attacks": 2, "quality": 1, "empties": true}

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	RosterSweep.arm(_main, ProjectSettings.globalize_path(DICE))
	_main.solo_ai_slots = {2: true}   # seat 1 is the human whose split this is; seat 2 the AI targets
	_main.combat_stage.force_for_tests = true
	GraphicsSettings.combat_stage_hold_s = 0.0


func after_test() -> void:
	GraphicsSettings.combat_stage_hold_s = 2.5
	RosterSweep.disarm(_main)
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## A block of `models` models at `x_in`, moved `z_off` inches in z, with the kit's weapons on its OPR data.
func _kit(pid: int, uname: String, models: int, x_in: float, z_off: float, kit: Array, attacks := 1, quality := 4,
		defense := 4) -> GameUnit:
	var u := ParityTable._make_unit(_main, SIDE.merged({"player": pid, "name": uname, "models": models, "x_in": x_in,
		"quality": quality, "defense": defense}, true), {"name": str(kit[0][0]), "range_in": int(kit[0][2]),
		"attacks": attacks, "count": int(kit[0][1]), "rules": []})
	for e in kit.slice(1):
		var w := OPRApiClient.OPRWeapon.new()
		w.name = str(e[0])
		w.range_value = int(e[2])
		w.attacks = attacks
		w.count = int(e[1])
		(u.source_data as OPRApiClient.OPRUnit).weapons.append(w)
	for m in u.models:
		(m as ModelInstance).node.global_position.z += z_off * INCH
	return u


## The aim the table's declared split stands for: every weapon at A except the second group's names, which go to B.
## `fault` "swap" puts the second group on A as well (the core then fires one target, the table two).
func _aim(att: GameUnit, a: GameUnit, b: GameUnit, fault: String) -> Array:
	var out: Array = []
	for w in (att.source_data as OPRApiClient.OPRUnit).weapons:
		var to := b if B_NAMES.has(str(w.name)) else a
		if fault == "swap" and B_NAMES.has(str(w.name)):
			to = a
		out.append({"member": att.get_name(), "weapon": str(w.name), "target": to.unit_id})
	return out


## One split activation of seed `seed_n` on fresh units; `core` = the step driver with the split intent, else the
## table's `_run_human_attack_split`. Returns the dice stream and the three units' end state.
func _volley(shape: Dictionary, seed_n: int, core: bool, fault: String) -> Dictionary:
	var att := _kit(1, "Squad", 10, 0.0, 0.0, KIT, int(shape["attacks"]), int(shape["quality"]))
	var a := _kit(2, "DefA", int(shape["a_models"]), 18.0, -8.0, [["Rifle", int(shape["a_models"]), 24]], 1, 4,
		int(shape["a_defense"]))
	var b := _kit(2, "DefB", 5, 10.0, 12.0, [["Rifle", 5, 24]], 1, 4)
	var r := {"step": "table"}
	_main.seed_tray_rng(seed_n)
	CoreActivation.reset_all(_main)
	if core:
		CoreActivation._env = 1
		assert_bool(CoreActivation.open_session(_main, att)).override_failure_message("the core opened no session").is_true()
		var s: Dictionary = CoreActivation._sessions[att.unit_id]
		var t: Array = (s["transcript"] as Array).duplicate()
		t.append({"t": "intent", "kind": AiDecision.Action.HOLD, "shoot": a.unit_id, "split": _aim(att, a, b, fault)})
		r = await CoreActivation.drive(_main, int(s["handle"]), att, t, false)
		CoreActivation.close_session(_main, att.unit_id)
	else:
		CoreActivation._env = 0
		_main._solo_ai_busy = true   # the AI's reply is not part of this gate: no pump dice in the dump
		await _main._run_human_attack_split(att, a, b, B_NAMES)
		_main._solo_ai_busy = false
	AiDiceRecorder.close()
	var out := {"rolls": ParityTable._read_dice(ProjectSettings.globalize_path(DICE)),
		"state_a": RosterSweep.state_of(att, a), "state_b": RosterSweep.state_of(att, b),
		"names": [att.get_name(), a.get_name()], "step": str(r.get("step", "")), "a_alive": a.get_alive_count()}
	RosterSweep.free_units(_main, [att, a, b])
	await _main.get_tree().process_frame
	return out


func _run(shape: Dictionary, fault := "") -> Dictionary:
	var rows: Array = []
	var b_bad := 0
	var done := 0
	var emptied := 0
	for s in SEEDS:
		var table := await _volley(shape, s, false, fault)
		var core := await _volley(shape, s, true, fault)
		if int(table["a_alive"]) == 0:
			emptied += 1
		if RosterSweep.first_state_diff(table["state_b"], core["state_b"]) != "":
			b_bad += 1
		if str(core["step"]) == "done":
			done += 1
		rows.append({"id": s, "pair": "human_split", "dir": 0, "seed": s, "att": (table["names"] as Array)[0],
			"tgt": (table["names"] as Array)[1],
			"table": {"rolls": table["rolls"], "state": table["state_a"], "labels": {"att": [], "tgt": []}},
			"core": {"rolls": core["rolls"], "state": core["state_a"], "labels": {"att": [], "tgt": []}}})
	var cmp := RosterSweep.compare(rows, OUT)
	var bad := (cmp["verdicts"] as Array).filter(func(v: Dictionary) -> bool: return str(v["first_diff"]) != "").size()
	print("ONE_CORE_HUMAN_SPLIT shape=%s fault=%s seeds=%d core_done=%d emptied=%d first_or_a_mismatches=%d b_state_mismatches=%d" % [
		str(shape["name"]), fault, SEEDS, done, emptied, bad, b_bad])
	return {"done": done, "emptied": emptied, "bad": bad, "b_bad": b_bad, "problems": cmp["problems"]}


func _green(shape: Dictionary) -> void:
	var r := await _run(shape)
	assert_int(int(r["done"])).override_failure_message("the core did not resolve the split (the red leg)").is_equal(SEEDS)
	assert_int(int(r["bad"])).override_failure_message("table and core differ on dice or on the first target").is_equal(0)
	assert_int(int(r["b_bad"])).override_failure_message("the second target ends differently").is_equal(0)
	assert_array(r["problems"]).is_empty()
	if bool(shape.get("empties", false)):
		assert_int(int(r["emptied"])).override_failure_message("the first group did not empty the target: not the shape asked for").is_equal(SEEDS)


func test_two_targets_land_as_they_do_on_the_table(timeout := 600000) -> void:
	await _green(TWO)


func test_the_first_group_empties_its_target_and_the_second_still_fires(timeout := 600000) -> void:
	await _green(EMPTY)


## The planted fault: the core's second group is aimed at the first group's target. The gate must see it.
func test_a_swapped_second_group_turns_the_gate_red(timeout := 600000) -> void:
	var r := await _run(TWO, "swap")
	assert_int(int(r["bad"]) + int(r["b_bad"])).override_failure_message("the gate did not see the swapped second group").is_greater(0)
