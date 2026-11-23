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
## PLAN_FIRST_DELETION 34 FT-C7: the table arm left before step 31 (the AI table resolver retires); door values are pinned as literals read on main 97fa324e9.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const Harness := preload("res://test/one_core/golden_witness_harness.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DICE := "user://ledger_lift_dice"
const SEEDS := 16
## Per seed: door battle-log lines containing the rule name (Teleport, Ethereal), and door dice records per label (read on main).
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_NAMED := {"Teleport": [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2],
	"Ethereal": [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2]}
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_ROLLS := {"Teleport": [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2],
	"Ethereal": [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2],
	"Infiltrate": [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2]}
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_BURST_LINES := [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_ROLLS_SURPRISE := [4, 4, 4, 3, 4, 4, 4, 4, 4, 3, 4, 3, 4, 4, 4, 3]

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


## `SEEDS` activations through the door: {"named": seeds whose door lines contain `needle`, "taken": seeds the door was allowed to
## take, "ran": seeds where the core really ran the activation, "named_counts"/"rolls_counts": the per-seed door counts}.
func _compare(sys: String, faction: String, rule: String, gap_x: float, needle: String) -> Dictionary:
	var named := 0
	var taken := 0
	var ran := 0
	var named_counts: Array = []
	var rolls_counts: Array = []
	for s in SEEDS:
		var on := await _activation(sys, faction, rule, s, gap_x, true)
		var l_on: Array = (on["lines"] as Array).filter(func(l: String) -> bool: return l.contains(needle))
		named += 0 if l_on.is_empty() else 1
		taken += 1 if bool(on["takes"]) else 0
		ran += 1 if int(on["ran"]) > 0 else 0
		named_counts.append(l_on.size())
		rolls_counts.append((on["rolls"] as Array).size())
	print("LEDGER_LIFT ", JSON.stringify({"rule": rule, "seeds": SEEDS, "taken": taken, "ran": ran, "named": named}))
	CoreActivation._env = 1
	return {"named": named, "taken": taken, "ran": ran, "named_counts": named_counts, "rolls_counts": rolls_counts}


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
			assert_array(r["named_counts"]).override_failure_message("%s: the rule's line count per seed" % c[0]).is_equal(WANT_NAMED[c[0]])
		assert_array(r["rolls_counts"]).override_failure_message("%s: the door's roll count per seed" % c[0]).is_equal(WANT_ROLLS[c[0]])


## The Surprise Attack burst (an Infiltrate-primitive entry) fires at the activation start on the table, and the core rolled its own copy
## again (16 / 16 seeds differed with the name lifted). 15a's `paid {start}` removed the core's second burst but left the volley on the
## board captured before the burst (an end state differed). D-PAR3 15b: a Surprise Attack chain is never `core_takes` - the table pays the
## burst and the volley goes to the core on a RECAPTURE with `paid {start, dangerous, beats}`, so the name left the deny file: taken, run
## by the core, the burst named, and no seed differs - neither the dice nor the end state.
func test_the_surprise_attack_burst_is_taken_and_rolls_once() -> void:
	var committed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CoreSlice.DENY_PATH))
	assert_bool((committed["deny_names"] as Dictionary).has("Surprise Attack")).override_failure_message("the name left the deny file").is_false()
	var r := await _compare("gf", "alien_hives", "Surprise Attack", 2.0, "Surprise Attack")
	assert_int(int(r["taken"])).override_failure_message("the deny file takes a Surprise Attack bearer").is_equal(SEEDS)
	assert_int(int(r["ran"])).override_failure_message("the core runs the volley").is_equal(SEEDS)
	assert_int(int(r["named"])).override_failure_message("the table fired the burst").is_equal(SEEDS)
	assert_array(r["named_counts"]).override_failure_message("the burst is named once per seed").is_equal(WANT_BURST_LINES)
	assert_array(r["rolls_counts"]).override_failure_message("the burst rolls once (%s)" % [r["rolls_counts"]]).is_equal(WANT_ROLLS_SURPRISE)
