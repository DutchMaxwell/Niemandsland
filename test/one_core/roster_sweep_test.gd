extends GdUnitTestSuite
## One core C-7: the roster sweep harness (test/one_core/roster_sweep.gd) on the bundled real lists. The instrument is checked here
## (it covers every unit on both paths, the parity files and the compare work, the coverage and gate mechanics can fail); the
## sweep over a fleet's per-faction lists is the CLI (roster_sweep_cli.gd). The control pairing below is equal on both paths today:
## a rule or capture change that makes the table and the core diverge on a real roster turns it red with the first difference.
## Real: the main scene, NmlCore, the importer and `EquipmentDistributor` on real list JSON, the table's AI body, the live capture
## and the step driver, tools/parity/parity_compare.py. Constructed: only the unit placement (two blocks, 14" apart).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DoorLines := preload("res://test/one_core/door_lines.gd")
const LISTS := ["res://assets/arena_lists/p1_2000.json", "res://assets/arena_lists/p2_2000.json"]
const WOLF := "res://test/fixtures/wolf_brothers_3000.json"
const DICE := "user://roster_sweep_dice"
const OUT := "user://roster_sweep_out"

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	RosterSweep.aura_pass = true
	RosterSweep.disarm(_main)
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _lists() -> Array:
	return LISTS.map(func(p: String) -> Dictionary: return RosterSweep.load_list(p))


func test_the_sweep_fires_every_unit_and_targets_every_unit_on_both_paths() -> void:
	var lists := _lists()
	var pairs := RosterSweep.ring(lists)
	assert_int(pairs.size()).is_equal(1)
	RosterSweep.arm(_main, ProjectSettings.globalize_path(DICE))
	var seeds := 2
	var rows: Array = await RosterSweep.sweep_pair(_main, lists[0], lists[1], seeds, ProjectSettings.globalize_path(DICE))
	var units: Array = (lists[0]["units"] as Array) + (lists[1]["units"] as Array)
	var n := maxi((lists[0]["units"] as Array).size(), (lists[1]["units"] as Array).size())
	assert_int(rows.size()).override_failure_message("2 directions x the longer list x seeds").is_equal(2 * n * seeds)
	var shot := {}
	var hit := {}
	for r in rows:
		shot[r["att"]] = true
		hit[r["tgt"]] = true
	for e in units:
		var nm := str((e["unit"] as OPRApiClient.OPRUnit).name)
		assert_bool(shot.has(nm)).override_failure_message("%s never shot" % nm).is_true()
		assert_bool(hit.has(nm)).override_failure_message("%s was never a target" % nm).is_true()
	var cmp := RosterSweep.compare(rows, OUT)
	assert_array(cmp["problems"]).override_failure_message("the compare's own problems: %s" % [cmp["problems"]]).is_empty()
	var fired := (cmp["verdicts"] as Array).filter(func(v: Dictionary) -> bool: return bool(v["fired"])).size()
	var verdict := RosterSweep.gate(cmp["verdicts"], {})
	print("ROSTER_SWEEP volleys=%d fired=%d roll_mismatches=%d state_mismatches=%d" % [rows.size(), fired, cmp["roll_mismatches"], verdict["mismatches"] - int(cmp["roll_mismatches"])])
	assert_int(fired).override_failure_message("only %d of %d volleys threw a die: the sweep compares nothing" % [fired, rows.size()]).is_greater(rows.size() / 4)
	assert_array(verdict["unexplained"]).override_failure_message("table and core differ on a real roster: %s" % [(verdict["unexplained"] as Array).slice(0, 3)]).is_empty()
	for half in ["table", "core"]:
		var lines := FileAccess.get_file_as_string(OUT.path_join("sweep_%s.jsonl" % half)).split("\n", false)
		assert_int(lines.size()).override_failure_message("one parity row per volley (%s)" % half).is_equal(rows.size())
	assert_bool((cmp["verdicts"] as Array).all(func(x: Dictionary) -> bool: return x.has("deny"))).override_failure_message("every verdict says what deny mode would refuse").is_true()
	var cov := RosterSweep.coverage(cmp["verdicts"])
	assert_bool(cov.has("AP") and int(cov["AP"]["att"]) > 0 and int(cov["AP"]["tgt"]) > 0).override_failure_message("coverage: %s" % [cov.keys()]).is_true()


func test_an_uncovered_rule_name_is_listed() -> void:
	var cov := {"AP": {"att": 5, "tgt": 5}, "Fear": {"att": 5, "tgt": 0}, "Slow": {"att": 2, "tgt": 9}}
	assert_array(RosterSweep.uncovered(cov, ["AP", "Fear", "Slow", "Zap"], 3)).is_equal(["Fear", "Slow", "Zap"])
	assert_array(RosterSweep.uncovered(cov, ["AP"], 5)).is_empty()
	assert_array(RosterSweep.rule_names("gf")).contains(["AP", "Fear", "Tough"])


func test_a_mismatch_is_explained_only_by_a_label_of_the_deny_list() -> void:
	var v := [{"first_diff": "", "labels": {"att": ["AP"], "tgt": []}},
		{"first_diff": "rolls", "labels": {"att": ["AP"], "tgt": ["Guardian"]}},
		{"first_diff": "tgt.alive", "labels": {"att": [], "tgt": ["Fear"]}}]
	var g := RosterSweep.gate(v, {"Guardian": "alias not ported"})
	assert_int(int(g["mismatches"])).is_equal(2)
	assert_int(int(g["explained"])).is_equal(1)
	assert_int((g["unexplained"] as Array).size()).is_equal(1)
	assert_int((RosterSweep.gate(v, {})["unexplained"] as Array).size()).is_equal(2)


## The deny-mode share counts only fired volleys the deny slice takes ("deny" empty) and lists the unequal ones. RED: count every
## fired volley as taken -> taken 3.
func test_the_deny_mode_share_counts_only_taken_fired_volleys() -> void:
	var v := [{"fired": true, "first_diff": "", "deny": []},
		{"fired": true, "first_diff": "rolls", "deny": []},
		{"fired": true, "first_diff": "rolls", "deny": ["unit_rule:Tear"]},
		{"fired": false, "first_diff": "", "deny": []}]
	var s := RosterSweep.deny_share(v)
	assert_dict(s).contains_key_value("fired", 3).contains_key_value("taken", 2).contains_key_value("equal", 1)
	assert_int((s["unequal"] as Array).size()).is_equal(1)


## Gate 18.11. (main 213bbbf6d): the gate script ran twice, two sweep processes wrote one `dice.jsonl`, and 1513 volleys read
## another row's dice. A second process must not get the dice directory while the first holds it; a dead holder's lock is
## taken over; the holder's own release frees it. RED without `claim`'s lock (a claim that always answers ""): the live
## holder is not refused; RED with `OS.is_process_running` as the liveness check: the foreign holder (pid 1) reads as gone.
func test_one_sweep_process_holds_a_dice_directory() -> void:
	var dice := ProjectSettings.globalize_path("user://roster_sweep_claim")
	var lock := dice.path_join(RosterSweep.LOCK_DIR)
	RosterSweep.release(dice)
	assert_str(RosterSweep.claim(dice)).override_failure_message("a free directory is taken").is_empty()
	assert_str(RosterSweep.claim(dice)).override_failure_message("the holder claims again").is_empty()
	RosterSweep.release(dice)
	assert_bool(DirAccess.dir_exists_absolute(lock)).override_failure_message("release frees the lock").is_false()
	_plant_lock(lock, 1)   # a live process that is NOT this one's child (OS.is_process_running reads those as gone)
	assert_str(RosterSweep.claim(dice)).override_failure_message("a live foreign holder must refuse a second sweep").contains("held by sweep process 1")
	var other := OS.create_process("sleep", ["30"])   # a live process of this user stands in for a second sweep
	assert_int(other).is_greater(0)
	_plant_lock(lock, other)
	assert_str(RosterSweep.claim(dice)).override_failure_message("a live holder must refuse a second sweep").contains("held by sweep process %d" % other)
	RosterSweep.release(dice)
	assert_bool(DirAccess.dir_exists_absolute(lock)).override_failure_message("release leaves another holder's lock").is_true()
	OS.kill(other)   # the holder is gone (reaped below): its lock is stale
	for _i in 50:
		if not OS.is_process_running(other):
			break
		OS.delay_msec(20)
	assert_str(RosterSweep.claim(dice)).override_failure_message("a stale lock is taken over").is_empty()
	assert_int(int(FileAccess.get_file_as_string(lock.path_join("pid")))).is_equal(OS.get_process_id())
	RosterSweep.release(dice)
	assert_bool(DirAccess.dir_exists_absolute(lock)).is_false()


func _plant_lock(lock: String, pid: int) -> void:
	DirAccess.make_dir_recursive_absolute(lock)
	var f := FileAccess.open(lock.path_join("pid"), FileAccess.WRITE)
	f.store_string(str(pid))
	f.close()


func test_the_ring_puts_every_list_in_two_pairings() -> void:
	var ls := [{"system": "gf", "name": "a"}, {"system": "gf", "name": "b"}, {"system": "gf", "name": "c"}]
	var pairs := RosterSweep.ring(ls)
	assert_int(pairs.size()).is_equal(3)
	for l in ls:
		assert_int(pairs.filter(func(p: Array) -> bool: return p[0] == l or p[1] == l).size()).is_equal(2)
	assert_array(RosterSweep.ring([ls[0]])).is_empty()


## DS-RG: a 12 in weapon at the sweep's 14 in centre distance. The nearest bases are 11.7 in apart, inside the weapon, so the
## table fires; the core reads the same measure only when the header carries the shipped preset's table-fidelity switch
## (`range_by_base_edge`, AiPlanner.table_fidelity_stamp), which `arm()` must stamp or every such volley is a false G1.
## RED before the stamp: the core half records no roll at all.
func test_a_twelve_inch_weapon_fires_across_the_base_edge_on_both_paths() -> void:
	var l := RosterSweep.load_list(WOLF)
	var att := {}
	var tgt := {}
	for e in l["units"]:
		var nm := str((e["unit"] as OPRApiClient.OPRUnit).name)
		if nm == "Wolf Support Brothers" and att.is_empty():
			att = e
		if nm == "Wolf Battle Tank" and tgt.is_empty():
			tgt = e
	RosterSweep.arm(_main, ProjectSettings.globalize_path(DICE))
	var dice := ProjectSettings.globalize_path(DICE)
	var t := await RosterSweep.volley(_main, att, tgt, 0, false, dice)
	var c := await RosterSweep.volley(_main, att, tgt, 0, true, dice)
	var table_attacks := _attacks(t["rolls"])
	assert_int(table_attacks).override_failure_message("the table never fired the 12 in flamer: %s" % [t["rolls"]]).is_greater(0)
	assert_int(_attacks(c["rolls"])).override_failure_message("the core fired nothing at 11.7 in base edge: %s" % [c["rolls"]]).is_equal(table_attacks)


## Plan H (H-10): the sweep harness runs the import's aura pass (`OPRArmyManager.expand_auras_of`). A shooter with Relentless Aura (gf robot_legions:
## "this model and its unit get Relentless") gets one extra hit per unmodified 6 from over 9 in: the core reads the aura through its registry, the table only
## through the base rule the import's pass adds. RED (the first leg): switch the pass off and 16 seeds show the dice differing on the extra hits;
## GREEN: with it the two halves' dice are equal on all 16.
func test_the_aura_pass_makes_an_aura_shooter_equal_on_both_paths() -> void:
	RosterSweep.arm(_main, ProjectSettings.globalize_path(DICE))
	var dice := ProjectSettings.globalize_path(DICE)
	var shooter := DoorLines.entry("Auras", 10, ["Relentless Aura"], [], "robot_legions", 5)
	var target := DoorLines.entry("Plain", 10, [], [], "battle_brothers", 0)
	for pass_on in [false, true]:
		RosterSweep.aura_pass = pass_on
		var differing := 0
		for seed_n in 16:
			var t := await RosterSweep.volley(_main, shooter, target, seed_n, false, dice)
			var c := await RosterSweep.volley(_main, shooter, target, seed_n, true, dice)
			if _faces(t["rolls"]) != _faces(c["rolls"]):
				differing += 1
		if pass_on:
			assert_int(differing).override_failure_message("with the aura pass the halves still differ on %d of 16 seeds" % differing).is_equal(0)
		else:
			assert_int(differing).override_failure_message("without the pass the check saw no difference: it cannot fail").is_greater(0)


func _faces(rolls: Array) -> Array:
	return rolls.map(func(r: Dictionary) -> String: return "%s:%d:%s" % [r["kind"], int(r["count"]), r["faces"]])


func _attacks(rolls: Array) -> int:
	return rolls.filter(func(r: Dictionary) -> bool: return str(r["kind"]) == "attack").size()


## Plan E (step 4a): `RosterSweep.charge` runs the door-vs-table pair (control EQUAL, planted fault UNEQUAL) and accepts real
## `load_list` entries with `bypass_slice` for step 4b's melee sweep. RED: stub `compare_charge` -> planted faults read equal.
func test_charge_helper_compares_door_against_table_and_catches_planted_faults() -> void:
	RosterSweep.arm(_main, ProjectSettings.globalize_path(DICE))
	CoreActivation._charge_env = 1
	var side := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.3, "game_system": "gf", "faction_folder": "robot_legions", "rules": []}
	var blade := {"name": "Blade", "range_in": 0, "attacks": 2, "count": 5, "rules": []}
	var att_fn := func() -> GameUnit: return ParityTable._make_unit(_main, side.merged({"player": 2, "name": "Att", "models": 5, "x_in": 0.0}, true), blade)
	var foe_fn := func() -> GameUnit:
		var u := ParityTable._make_unit(_main, side.merged({"player": 1, "name": "Def", "models": 8, "x_in": 7.0, "z_step_in": 1.4}, true), blade.merged({"count": 8, "attacks": 1}))
		for i in u.models.size():
			(u.models[i] as ModelInstance).node.global_position.z += float((i * 7) % 5) * 0.0001
		return u
	var ctrl := await RosterSweep.charge(_main, att_fn, foe_fn, 0)
	assert_bool(bool(ctrl["taken"])).override_failure_message("control charge was not taken by the door").is_true()
	# Dice, state and lines are equal; both 1" back-steps end short of 1" from the defenders (ticket SEPARATE-1IN, ds/meleepos.md):
	# the checker reads `enemy_within_1in` on both halves, the core's is the row's `core_illegal`.
	assert_array(ctrl["diffs"]).override_failure_message("control charge differed: %s" % [ctrl["diffs"]]).is_empty()
	assert_str(str(ctrl["first_diff"])).is_equal("core_illegal")
	for half in ["table", "core"]:
		var kinds: Array = (ctrl[half]["illegal"] as Array).map(func(i: Dictionary) -> String: return str(i["kind"]))
		assert_bool(not kinds.is_empty() and kinds.all(func(k: String) -> bool: return k == "enemy_within_1in")) \
			.override_failure_message("SEPARATE-1IN on the %s half: %s" % [half, ctrl[half]["illegal"]]).is_true()
	# PLAN_FIRST_DELETION 3d: where the models stand is a free choice when both ends are legal - a 3 in shift of the whole defender is
	# reported (`free_position`), not a mismatch; a planted overlap on the TABLE half is reported by the checker (`table_illegal`).
	var shift := func(_a: GameUnit, f: GameUnit) -> void:
		for m in f.get_alive_models():
			(m as ModelInstance).node.global_position.x += 3.0 * RosterSweep.INCH
	var moved := await RosterSweep.charge(_main, att_fn, foe_fn, 0, {"core_fault": shift})
	assert_bool(bool(moved["equal"])).override_failure_message("a legal 3 in difference read as a mismatch: %s" % [moved["diffs"]]).is_true()
	assert_array(moved["free_position"]).override_failure_message("the 3 in difference went unreported").is_not_empty()
	var stack := func(_a: GameUnit, f: GameUnit) -> void:
		(f.get_alive_models()[1] as ModelInstance).node.global_position = (f.get_alive_models()[0] as ModelInstance).node.global_position
	var stacked := await RosterSweep.charge(_main, att_fn, foe_fn, 0, {"table_fault": stack})
	assert_array((stacked["table"]["illegal"] as Array).map(func(i: Dictionary) -> String: return str(i["kind"]))) \
		.override_failure_message("a planted overlap on the table half went unseen: %s" % [stacked["table"]]).contains(["overlap"])
	var flip := func(_a: GameUnit, f: GameUnit) -> void: f.is_shaken = not f.is_shaken
	var shaken := await RosterSweep.charge(_main, att_fn, foe_fn, 0, {"core_fault": flip})
	assert_bool(bool(shaken["equal"])).override_failure_message("a Shaken fault went unseen").is_false()
	assert_str(str(shaken["first_diff"])).is_equal("shaken")
	var lists := _lists()
	var real_res := await RosterSweep.charge(_main, lists[0]["units"][0], lists[1]["units"][1], 0, {"bypass_slice": true})
	assert_bool(bool(real_res["taken"])).override_failure_message("real list charge was not driven through the core").is_true()
	assert_array(real_res["refusals"]).is_not_empty()
	assert_array(real_res["core"]["lines"]).is_not_empty()


func _melee_entry(nm: String, size: int, rng: int, w_rules: Array[String] = []) -> Dictionary:
	var ou := OPRApiClient.OPRUnit.new()
	ou.name = nm; ou.size = size; ou.quality = 4; ou.defense = 4; ou.game_system = "gf"
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Blade" if rng == 0 else "Rifle"; w.range_value = rng; w.attacks = 2; w.count = size; w.special_rules.assign(w_rules)
	ou.weapons = [w]
	return {"unit": ou, "faction": "robot_legions", "system": "gf"}


## Plan E (step 4b): melee sweep (`--door melee`) sweeps ring pairs x melee units x enemy units x seeds, emits JSON verdict rows
## with `taken`, `deny`, `equal`, `first_diff` like the shoot sweep, and marks planted fault rows UNEQUAL.
## RED: stub `verdicts()` melee `first_diff` to "" -> planted fault rows read equal.
func test_melee_sweep_pair_emits_verdict_rows_and_catches_planted_fault() -> void:
	var dice := ProjectSettings.globalize_path(DICE)
	RosterSweep.arm(_main, dice)
	var blades := _melee_entry("Blades", 1, 0, ["AP(1)"])
	var rifles := _melee_entry("Rifles", 1, 24)
	var guards := _melee_entry("Guards", 1, 0)
	var horde := _melee_entry("Horde", 10, 0)
	assert_bool(RosterSweep.has_melee(blades) and not RosterSweep.has_melee(rifles)).is_true()
	var rows: Array = await RosterSweep.sweep_melee_pair(_main, {"name": "A", "system": "gf", "units": [blades, rifles]},
		{"name": "B", "system": "gf", "units": [guards, horde]}, 1, dice)
	assert_int(rows.size()).override_failure_message("1x2 + 2x2 = 6 melee-charger x enemy charges").is_equal(6)
	var cmp := RosterSweep.compare(rows, OUT)
	assert_array(cmp["problems"]).is_empty()
	var vs: Array = cmp["verdicts"]
	assert_bool(vs.all(func(v: Dictionary) -> bool: return str(v["att"]) != "Rifles") and vs.any(func(v: Dictionary) -> bool: return str(v["tgt"]) == "Rifles")).is_true()
	for v in vs:
		for k in ["id", "pair", "att", "tgt", "seed", "fired", "taken", "deny", "equal", "first_diff", "labels"]:
			assert_bool((v as Dictionary).has(k)).override_failure_message("missing key %s" % k).is_true()
		if str(v["att"]) == "Horde" or str(v["tgt"]) == "Horde":
			assert_bool(bool(v["taken"])).is_false()
			assert_array(v["deny"]).contains(["size"])
		else:
			assert_bool(bool(v["fired"]) and bool(v["taken"]) and bool(v["equal"])).override_failure_message("control row failed: %s" % [v]).is_true()
			assert_array(v["deny"]).is_empty()
			assert_str(str(v["first_diff"])).is_empty()
	assert_dict(RosterSweep.deny_share(vs)).contains_key_value("taken", 3).contains_key_value("equal", 3)
	var small := [{"name": "A", "system": "gf", "units": [blades]}, {"name": "B", "system": "gf", "units": [guards]}]
	for case in [[{"core_fault": func(_a: GameUnit, f: GameUnit) -> void: f.is_shaken = not f.is_shaken}, "shaken", 0], [{"core_swap_face": 0}, "rolls", 2]]:
		var fault := RosterSweep.compare(await RosterSweep.sweep_melee_pair(_main, small[0], small[1], 1, dice, 0, case[0]), OUT)
		for v in fault["verdicts"]:
			assert_bool(bool(v["equal"])).override_failure_message("planted %s fault unseen: %s" % [case[1], v]).is_false()
			assert_str(str(v["first_diff"])).is_equal(str(case[1]))
		assert_int((RosterSweep.deny_share(fault["verdicts"])["unequal"] as Array).size()).is_equal(2)
		assert_int(int(fault["roll_mismatches"])).is_equal(int(case[2]))
