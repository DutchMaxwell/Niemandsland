extends GdUnitTestSuite
## C-19 (gate soak 18.11., game 2): "Pistoleer Sisters" (Devout + Point-Blank Surge, a joined hero) fired a split volley
## whose first group stood in base contact. The table measured the edge gap as -0.01" and `_solo_hits` took `dist_in > 0.0`
## as its only "this is a shot" test, so the Surge alias (Devout; rules 3.6: no distance condition when shooting) paid
## nothing, while the core paid +1 hit per unmodified 6: core 6 defense dice, table 4. The shooting callers now say
## `shooting`. Fixture shape: test/one_core/split_door_test.gd (the table body vs the production door, deny slice,
## `SEEDS` seeds, dice by parity_compare.py, end state of shooter and both targets). RED before the fix: the contact
## cases differ on 16 of 16 seeds (first difference the defense count); GREEN after. The split cases (Point-Blank Surge
## within 12", a joined hero with Devout alone) were equal before and stay equal: they pin the lift of the deny name.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SEEDS := 16
const DICE := "user://surge_contact_dice"
const OUT := "user://surge_contact_out"

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _hero_entry: Dictionary = {}


func before_test() -> void:
	_hero_entry = {}
	CoreSlice.path_override = CoreSlice.DENY_PATH
	CoreSlice.reset_cache()
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.combat_stage.force_for_tests = true   # the stage runs headless: its headline says which group was staged last
	GraphicsSettings.combat_stage_hold_s = 0.0


func after_test() -> void:
	GraphicsSettings.combat_stage_hold_s = 2.5
	CoreSlice.path_override = ""
	CoreSlice.reset_cache()
	RosterSweep.disarm(_main)
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _weapon(wname: String, rules: Array, attacks := 2, rng := 24, count := 1) -> OPRApiClient.OPRWeapon:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = wname
	w.range_value = rng
	w.attacks = attacks
	w.count = count
	w.special_rules.assign(rules)
	return w


func _entry(uname: String, size: int, rules: Array, weapons: Array, faction := "battle_brothers", defense := 4) -> Dictionary:
	var ou := OPRApiClient.OPRUnit.new()
	ou.name = uname
	ou.size = size
	ou.quality = 4
	ou.defense = defense
	ou.game_system = "gf"
	ou.special_rules.assign(rules)
	for w in weapons:
		ou.weapons.append(w)
	return {"unit": ou, "faction": faction, "system": "gf"}


## One activation of `shooter` at the two targets on one path. `core` = the production door (a live capture handed to `_run_ai_shooting`).
func _volley(shooter: Dictionary, targets: Array, seed_n: int, core: bool) -> Dictionary:
	var att := RosterSweep.spawn(_main, shooter, RosterSweep.SEAT_SHOOTER, 0.0)
	var hero: GameUnit = null
	if _hero_entry.size() > 0:
		hero = RosterSweep.spawn(_main, _hero_entry, RosterSweep.SEAT_SHOOTER, -2.0)
		hero.unit_properties["attached_to"] = att
		att.unit_properties["attached_heroes"] = [hero]
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
	RosterSweep.free_units(_main, ([att] if hero == null else [att, hero]) + foes)
	await _main.get_tree().process_frame
	return out


func _run(shooter: Dictionary, targets: Array) -> Dictionary:
	RosterSweep.arm(_main, ProjectSettings.globalize_path(DICE))
	CoreActivation._env = 1   # the door ON: `arm` set the table half's kill switch
	var rows: Array = []
	var split_table := 0
	var core_runs := 0
	var core_refusals := 0
	var b_bad := 0
	var stage_bad := 0
	for s in SEEDS:
		var table := await _volley(shooter, targets, s, false)
		var core := await _volley(shooter, targets, s, true)
		split_table += int(table["split"])
		core_runs += int(core["runs"])
		core_refusals += int(core["refusals"])
		if table["stage"] != core["stage"]:
			stage_bad += 1
			print("SPLIT_DOOR stage seed=%d table=%s core=%s" % [s, table["stage"], core["stage"]])
		if RosterSweep.first_state_diff({"tgt": table["state_b"]["tgt"], "att": table["state_b"]["att"]}, {"tgt": core["state_b"]["tgt"], "att": core["state_b"]["att"]}) != "":
			b_bad += 1
		rows.append({"id": s, "pair": "fixture", "dir": 0, "seed": s, "att": (table["names"] as Array)[0], "tgt": (table["names"] as Array)[1],
			"table": table, "core": core})
	var cmp := RosterSweep.compare(rows, OUT)
	var bad := (cmp["verdicts"] as Array).filter(func(v: Dictionary) -> bool: return str(v["first_diff"]) != "").size()
	print("SPLIT_DOOR seeds=%d table_splits=%d core_runs=%d core_refusals=%d mismatches=%d b_state_mismatches=%d stage_mismatches=%d" % [
		SEEDS, split_table, core_runs, core_refusals, bad, b_bad, stage_bad])
	return {"split_table": split_table, "core_runs": core_runs, "core_refusals": core_refusals, "bad": bad, "b_bad": b_bad, "stage_bad": stage_bad,
		"problems": cmp["problems"]}


func _check(r: Dictionary, split := true) -> void:
	assert_int(int(r["split_table"])).override_failure_message("the fixture's split shape changed on the table").is_equal(SEEDS if split else 0)
	assert_int(int(r["core_runs"])).override_failure_message("the core did not take the split volley (the red leg)").is_equal(SEEDS)
	assert_int(int(r["core_refusals"])).is_equal(0)
	assert_int(int(r["bad"])).override_failure_message("table and core differ on dice or on the shooter / first target").is_equal(0)
	assert_int(int(r["b_bad"])).override_failure_message("the last target ends differently").is_equal(0)
	assert_int(int(r["stage_bad"])).override_failure_message("the stage did not end on the table's last group").is_equal(0)
	assert_array(r["problems"]).is_empty()



func _sisters(rules: Array) -> Dictionary:
	return _entry("Pistol Sisters", 10, rules, [_weapon("Twin Heavy Pistol", ["AP(1)"], 2, 12, 6),
		_weapon("Twin Light Fusion Pistols", ["AP(4)"], 2, 6, 4)], "blessed_sisters")


func _hero() -> Dictionary:
	return _entry("Sister Hero", 1, ["Hero", "Tough(3)", "Devout"], [_weapon("Flamer Pistol", ["Blast(3)", "Reliable"], 1, 6)], "blessed_sisters")


## The near target's front rank overlaps the shooter's by a hair (edge gap just under 0"): the soak's shape.
func _contact_targets() -> Array:
	return [[_entry("Guards", 5, [], [], "battle_brothers", 4), 0.98, 0.0], [_entry("Veterans", 3, ["Tough(3)"], [], "battle_brothers", 2), 4.0, 6.0]]


func _split_targets() -> Array:
	return [[_entry("Guards", 5, [], [], "battle_brothers", 4), 8.0, -5.0], [_entry("Veterans", 3, ["Tough(3)"], [], "battle_brothers", 2), 4.0, 5.0]]


func test_devout_at_base_contact_pays_on_the_table_as_in_the_core() -> void:
	await _check(await _run(_sisters(["Devout"]), _contact_targets()), false)


func test_point_blank_surge_at_base_contact_pays_on_the_table_as_in_the_core() -> void:
	await _check(await _run(_sisters(["Devout", "Point-Blank Surge"]), _contact_targets()), false)


func test_point_blank_surge_split_volley_with_a_joined_hero_is_equal() -> void:
	_hero_entry = _hero()
	await _check(await _run(_sisters(["Devout", "Point-Blank Surge"]), _split_targets()))
