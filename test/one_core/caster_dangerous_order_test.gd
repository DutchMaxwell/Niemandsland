extends GdUnitTestSuite
## C-19 lane cc2c (deny mode): a caster that casts this activation must pay its Dangerous test BEFORE the cast, exactly as the table
## does with the core door off. In deny mode (`NML_CORE_SLICE=deny`) a Caster unit is taken by the door (the deny file lists no caster),
## `takes_ai_activation` said yes, the body DEFERRED the Dangerous test to the core's one call, the table resolved the casts, the core
## refused the call because of the casts, and the owed test was paid only afterwards: cast -> Dangerous. A caster the test killed had
## already cast. Now `takes_ai_activation` answers false for an activation whose report has casts, so the activation stays whole on the
## table in the old order (Dangerous -> casts -> beats -> volley); a caster that casts nothing is still taken.
## RED: `takes_ai_activation` without the cast clause -> the dice log shows a `dangerous` leg AFTER a `cast` / `spell` leg.
## Real: the main scene, NmlCore, the deny slice file, the AI's decision, the cast plan and the body (`_solo_activate_one_ai`), the
## tray and the dice tap (`dice.jsonl`, the `leg` field). Constructed: the units, the painted Dangerous block under the caster, a token
## count on the caster (2 with a spell book to cast from, 0 for the non-casting case), both seats AI.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const Harness := preload("res://test/one_core/golden_witness_harness.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DICE := "user://caster_dangerous_order_dice"
const SEEDS := 10
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf",
	"faction_folder": "battle_brothers", "rules": []}

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	CoreSlice.path_override = CoreSlice.DENY_PATH
	CoreSlice.reset_cache()
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	RosterSweep.arm(_main, ProjectSettings.globalize_path(DICE))
	CoreActivation._env = 1   # the door ON: `arm` set the table half's kill switch
	CoreActivation.ai_runs = 0
	CoreActivation.ai_refusals = 0


func after_test() -> void:
	CoreSlice.path_override = ""
	CoreSlice.reset_cache()
	RosterSweep.disarm(_main)
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## Every tray roll of the one activation, in order, read from the dice dump (the file the soak's detector reads).
func _rolls() -> Array:
	AiDiceRecorder.close()
	var path := ProjectSettings.globalize_path(DICE).path_join("dice.jsonl")
	var rolls: Array = []
	if FileAccess.file_exists(path):
		for line in FileAccess.get_file_as_string(path).split("\n", false):
			rolls.append(JSON.parse_string(line))
		DirAccess.remove_absolute(path)
	return rolls


## The `leg` of each roll, in order.
static func _legs_of(rolls: Array) -> Array:
	return rolls.map(func(r: Dictionary) -> String: return str(r.get("leg", "?")))


## Did the activation roll the Dangerous test's dice (5 models, Tough 1: five dice on a 6+; the table tags them `dangerous`, the core's
## own roll carries the volley's `main` leg)?
static func _dangerous_rolled(rolls: Array) -> bool:
	return rolls.any(func(r: Dictionary) -> bool: return int(r.get("count", 0)) == 5 and int(r.get("target", 0)) == 6)


## One real AI activation of a 5-model caster (`tokens` spell tokens) standing in a Dangerous block, a foe 14" away. Returns the legs in
## order and whether the door ran the activation.
func _body(seed: int, tokens: int) -> Dictionary:
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Att", "models": 5, "x_in": -7.0,
		"rules": ["Caster(2)"]}, true), {"name": "Rifle", "range_in": 24, "attacks": 1, "count": 5, "rules": []})
	att.casts_current = tokens
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Def", "models": 5, "x_in": 7.0}, true),
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 5, "rules": []})
	var painted: Dictionary = Harness._paint_cover(_main, att, _main.terrain_overlay.TerrainType.DANGEROUS)
	_main.seed_tray_rng(seed)
	var runs_before := CoreActivation.ai_runs
	var lines: Array = []
	var tap: Callable = Harness._line_tap(lines)
	_main.battle_log.entry_added.connect(tap)
	await _main._solo_activate_one_ai()
	_main.battle_log.entry_added.disconnect(tap)
	var rolls := _rolls()
	var out := {"legs": _legs_of(rolls), "dangerous": _dangerous_rolled(rolls), "ran": CoreActivation.ai_runs - runs_before, "lines": lines,
		"cast_planned": (_main.solo_controller.last_report.get("casts", []) as Array).size()}
	Harness._unpaint_cover(_main, painted)
	Harness._free_units(_main, [att, foe])
	_main.solo_controller._peeked_unit = null
	await _main.get_tree().process_frame
	return out


## The first index of a leg in `legs`, or -1.
static func _first(legs: Array, names: Array) -> int:
	for i in legs.size():
		if str(legs[i]) in names:
			return i
	return -1


func test_a_casting_caster_pays_its_dangerous_test_before_the_cast() -> void:
	var cast_seeds := 0
	for s in SEEDS:
		var r := await _body(s, 2)
		var legs: Array = r["legs"]
		var why := "seed %d: legs %s, door ran %d\n%s" % [s, legs, r["ran"], "\n".join(r["lines"])]
		var d := _first(legs, ["dangerous"])
		var c := _first(legs, ["cast", "spell"])
		assert_bool(d >= 0).override_failure_message("fixture: the caster rolled no Dangerous test: " + why).is_true()
		if c < 0:
			continue
		cast_seeds += 1
		assert_bool(d < c).override_failure_message("the Dangerous test came AFTER the cast: " + why).is_true()
		assert_int(int(r["ran"])).override_failure_message("a casting activation must stay on the table: " + why).is_equal(0)
	assert_int(cast_seeds).override_failure_message("fixture: no seed's caster cast").is_greater(0)


func test_a_caster_that_casts_nothing_is_still_taken_by_the_door() -> void:
	var taken := 0
	for s in SEEDS:
		var r := await _body(s, 0)
		var legs: Array = r["legs"]
		var why := "seed %d: legs %s, door ran %d\n%s" % [s, legs, r["ran"], "\n".join(r["lines"])]
		assert_int(int(r["cast_planned"])).override_failure_message("fixture: a tokenless caster planned a cast: " + why).is_equal(0)
		assert_int(_first(legs, ["cast", "spell"])).override_failure_message("fixture: it cast: " + why).is_equal(-1)
		assert_bool(bool(r["dangerous"])).override_failure_message("fixture: no Dangerous test: " + why).is_true()
		taken += int(r["ran"])
	assert_int(taken).override_failure_message("a caster without a cast this activation is no longer taken by the door").is_equal(SEEDS)
