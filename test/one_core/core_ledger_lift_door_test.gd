extends GdUnitTestSuite
## PLAN H, OD-H8 (the ledger round trip, lead lane "stealth"): the Teleport and Infiltrate primitives leave the `ledger_not_round_tripped` deny
## group once a REAL AI activation (`_solo_activate_one_ai`: the activation-start beat, the move, the Teleport beat, the volley) reads the same
## with the door ON (the core takes the activation) as with it OFF (the table alone): the same dice in the same order, the same end state of
## both units (alive, shaken, fatigued, the table's own ledger, where the models stand) and the same battle-log lines of the rule, 16 seeds per
## fixture. Surprise Attack (primitive Infiltrate) fires at the activation start on the table AND from the core's own copy: the door must not
## roll it twice (the beats family's failure, #3029).
## Measured (16 seeds each, door on against door off): Teleport and Ethereal 0 differing (the table's beat acts in 16 / 16 and the core runs the
## activation in 16 / 16), plain Infiltrate 0 differing, Surprise Attack 16 / 16 differing (the burst rolls twice), so that NAME stays refused.
## RED: put the group back into the deny file -> `CoreSlice.takes` refuses the bearer and the first assertion of each case fails. The comparison
## can fail: lifting the Surprise Attack name makes every seed unequal (the last test).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const Harness := preload("res://test/one_core/golden_witness_harness.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DICE := "user://ledger_lift_dice"
const SEEDS := 16

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	CoreSlice.path_override = ""
	CoreSlice.reset_cache()
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	RosterSweep.arm(_main, ProjectSettings.globalize_path(DICE))
	CoreActivation._env = 1
	CoreActivation.ai_runs = 0
	CoreActivation.ai_refusals = 0


func after_test() -> void:
	CoreActivation._env = 1
	RosterSweep.disarm(_main)
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _rolls() -> Array:
	AiDiceRecorder.close()
	var path := ProjectSettings.globalize_path(DICE).path_join("dice.jsonl")
	var rolls: Array = []
	if FileAccess.file_exists(path):
		for line in FileAccess.get_file_as_string(path).split("\n", false):
			var r: Dictionary = JSON.parse_string(line)
			rolls.append("%s:%d@%d:%s:%s" % [r.get("roll_kind", "?"), int(r["count"]), int(r["target"]), str(r["owner"]), str(r.get("faces", []))])
		DirAccess.remove_absolute(path)
	return rolls


## The end state a replay can disagree on, per unit by name: life, flags, the table's own ledger and the centroid of the living models (cm).
func _digest(units: Array) -> Dictionary:
	var out := {}
	for u in units:
		var gu := u as GameUnit
		var cx := 0.0
		var cz := 0.0
		var alive := gu.get_alive_models()
		for m in alive:
			cx += (m as ModelInstance).node.global_position.x
			cz += (m as ModelInstance).node.global_position.z
		var n := maxf(float(alive.size()), 1.0)
		out[gu.get_name()] = {"alive": gu.get_alive_count(), "shaken": gu.is_shaken, "fatigued": gu.is_fatigued,
			"ledger": JSON.parse_string(JSON.stringify(AiActRecorder._ledger_of(gu), "", true, true)),
			"props": {"surprise_attack_used": gu.unit_properties.get("surprise_attack_used", false),
				"teleport_used": gu.unit_properties.get("teleport_used_this_activation", false)},
			"at": [roundi(cx / n * 100.0), roundi(cz / n * 100.0)]}
	return out


## One real AI activation of "Att" (the bearer) against "Def", door ON or OFF; `swap` flips one recorded die on the door side (the control).
func _activation(sys: String, faction: String, rule: String, seed: int, gap_x: float, door: bool) -> Dictionary:
	CoreActivation._env = 1 if door else 0
	var side := {"quality": 4, "defense": 4, "tough": 3, "z_step_in": 1.2, "game_system": sys, "faction_folder": faction, "rules": [rule]}
	var att := ParityTable._make_unit(_main, side.merged({"player": 2, "name": "Att", "models": 5, "x_in": -gap_x}, true),
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 5, "rules": []})
	var foe := ParityTable._make_unit(_main, side.merged({"player": 1, "name": "Def", "models": 5, "x_in": gap_x, "rules": []}, true),
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 5, "rules": []})
	var units: Array = [att, foe]
	var takes := CoreSlice.takes(att)
	_main.seed_tray_rng(seed)
	var runs_before := CoreActivation.ai_runs
	var lines: Array = []
	var tap: Callable = Harness._line_tap(lines)
	_main.battle_log.entry_added.connect(tap)
	await _main._solo_activate_one_ai()
	_main.battle_log.entry_added.disconnect(tap)
	var out := {"takes": takes, "ran": CoreActivation.ai_runs - runs_before, "lines": lines, "rolls": _rolls(), "digest": _digest(units)}
	Harness._free_units(_main, units)
	_main.solo_controller._peeked_unit = null
	await _main.get_tree().process_frame
	return out


## `SEEDS` activations on both paths: {"differing": seeds whose dice, end state or `needle` lines differ, "named": seeds where the table said a
## line containing `needle`, "taken": seeds the door was allowed to take, "ran": seeds where the core really ran the activation}.
func _compare(sys: String, faction: String, rule: String, gap_x: float, needle: String) -> Dictionary:
	var differing := 0
	var dice_differing := 0   # D-PAR3 15a: the seeds whose roll streams differ (a second burst) ...
	var state_differing := 0   # ... and those whose end state differs (a volley on a stale board)
	var named := 0
	var taken := 0
	var ran := 0
	for s in SEEDS:
		var on := await _activation(sys, faction, rule, s, gap_x, true)
		var off := await _activation(sys, faction, rule, s, gap_x, false)
		var l_on: Array = (on["lines"] as Array).filter(func(l: String) -> bool: return l.contains(needle))
		var l_off: Array = (off["lines"] as Array).filter(func(l: String) -> bool: return l.contains(needle))
		named += 0 if l_off.is_empty() else 1
		taken += 1 if bool(on["takes"]) else 0
		ran += 1 if int(on["ran"]) > 0 else 0
		dice_differing += 1 if on["rolls"] != off["rolls"] else 0
		state_differing += 1 if JSON.stringify(on["digest"]) != JSON.stringify(off["digest"]) else 0
		if on["rolls"] != off["rolls"] or JSON.stringify(on["digest"]) != JSON.stringify(off["digest"]) or l_on != l_off:
			differing += 1
			print("LEDGER_LIFT_DIFF ", JSON.stringify({"rule": rule, "seed": s, "rolls_on": on["rolls"], "rolls_off": off["rolls"],
				"dig_on": on["digest"], "dig_off": off["digest"], "l_on": l_on, "l_off": l_off}).substr(0, 1500))
	print("LEDGER_LIFT ", JSON.stringify({"rule": rule, "seeds": SEEDS, "taken": taken, "ran": ran, "named": named, "differing": differing}))
	CoreActivation._env = 1
	return {"differing": differing, "named": named, "taken": taken, "ran": ran, "dice_differing": dice_differing, "state_differing": state_differing}


## [label, system, faction folder, rule, gap in inches, a needle that proves the rule acted ("" = equality alone)]
func _cases() -> Array:
	return [
		["Teleport", "gf", "knight_brothers", "Teleport", 14.0, "Teleport"],
		["Ethereal", "aof", "ghostly_undead", "Ethereal", 14.0, "Ethereal"],
		["Infiltrate", "gf", "robot_legions", "Infiltrate", 7.0, ""],
	]


func test_a_lifted_primitive_is_taken_and_reads_the_same_in_a_real_activation() -> void:
	for c in _cases():
		var r := await _compare(c[1], c[2], c[3], c[4], c[5])
		assert_int(int(r["taken"])).override_failure_message("%s: the deny slice refuses the bearer" % c[0]).is_equal(SEEDS)
		assert_int(int(r["ran"])).override_failure_message("%s: the core never ran the activation, the check proved nothing" % c[0]).is_equal(SEEDS)
		if c[5] != "":
			assert_int(int(r["named"])).override_failure_message("%s: the rule never acted, the check proved nothing" % c[0]).is_equal(SEEDS)
		assert_int(int(r["differing"])).override_failure_message("%s: %d of %d seeds differ" % [c[0], r["differing"], SEEDS]).is_equal(0)


## The Surprise Attack burst (an Infiltrate-primitive entry) fires at the activation start on the table, and the core rolled its own copy
## again: with the name lifted (a COPY of the deny file) every seed differed. D-PAR3 15a: the AI transcript says the table paid the start
## (`paid {start}`), so the core's copy of the burst is gone - the roll streams are equal on every seed. But the AI board is captured
## BEFORE the table's burst (main.gd: the capture at the activation start, the burst after it), so the core resolves the volley on a board
## without the burst's casualties and its delta puts them back: the end state differs (measured: seed 12, the burst's kill stands up
## again). So the committed file keeps refusing the bearer by NAME (not a group of kind `activation_start`, which 15a lets through);
## 15b's recapture after the burst lifts it.
func test_the_surprise_attack_burst_rolls_once_with_the_start_paid() -> void:
	var committed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CoreSlice.DENY_PATH))
	assert_bool((committed["deny_names"] as Dictionary).has("Surprise Attack")).override_failure_message("the name is refused").is_true()
	var refused := await _compare("gf", "alien_hives", "Surprise Attack", 2.0, "Surprise Attack")
	assert_int(int(refused["taken"])).override_failure_message("the committed deny file takes a Surprise Attack bearer").is_equal(0)
	assert_int(int(refused["ran"])).override_failure_message("the core ran a refused activation").is_equal(0)
	assert_int(int(refused["named"])).override_failure_message("the table never fired the burst").is_equal(SEEDS)
	(committed["deny_names"] as Dictionary).erase("Surprise Attack")
	var tmp := "user://deny_without_surprise_attack.json"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	f.store_string(JSON.stringify(committed))
	f.close()
	CoreSlice.path_override = tmp
	CoreSlice.reset_cache()
	var lifted := await _compare("gf", "alien_hives", "Surprise Attack", 2.0, "Surprise Attack")
	CoreSlice.path_override = ""
	CoreSlice.reset_cache()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	assert_int(int(lifted["ran"])).override_failure_message("with the name lifted the core runs the activation").is_equal(SEEDS)
	assert_int(int(lifted["dice_differing"])).override_failure_message("the start is paid: the core rolls no second burst (%d of %d roll streams differ)" % [lifted["dice_differing"], SEEDS]).is_equal(0)
	assert_int(int(lifted["state_differing"])).override_failure_message("the stale board: the burst's casualties are not on the core's board, some end state must differ").is_greater(0)
