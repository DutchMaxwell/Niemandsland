extends GdUnitTestSuite
## One core C-8: planted faults for the roster sweep (test/one_core/roster_sweep.gd). A sweep that stays green when a fault is planted
## is not an instrument: each case plants ONE fault on the core half only, on the bundled real pair, and the gate must go red; the
## control run (nothing planted) is green in the same test, so the red is the fault's. The four faults:
##   (i)   one rule parameter edited on the core side only (a shooter's AP(1) read as AP(2));
##   (ii)  one ledger key dropped from the capture (the target's Vengeance markers: a table fact the core never hears of);
##   (iii) one face of the recorded roll stream swapped (the replay disagrees by a single die);
##   (iv)  one deny entry removed while its difference still exists (the (i) difference is explained by `AP`; without the entry the
##         same volleys are unexplained).
## Real: the main scene, NmlCore, the real lists, the table's AI body, the live capture and the step driver, parity_compare.py.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const LISTS := ["res://assets/arena_lists/p1_2000.json", "res://assets/arena_lists/p2_2000.json"]
const DICE := "user://roster_sweep_faults_dice"
const OUT := "user://roster_sweep_faults_out"

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _lists: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_lists = LISTS.map(func(p: String) -> Dictionary: return RosterSweep.load_list(p))
	RosterSweep.arm(_main, ProjectSettings.globalize_path(DICE))


func after_test() -> void:
	RosterSweep.disarm(_main)
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## One seed of the pair on both paths with `opts`, compared; returns the compare result.
func _sweep(opts := {}) -> Dictionary:
	var rows: Array = await RosterSweep.sweep_pair(_main, _lists[0], _lists[1], 1, ProjectSettings.globalize_path(DICE), 0, opts)
	return RosterSweep.compare(rows, OUT)


## The first weapon rule of the shooters that starts with `prefix` ("AP(1)"): the string a core-side edit replaces.
func _weapon_rule(prefix: String) -> String:
	for l in _lists:
		for e in l["units"]:
			for w in (e["unit"] as OPRApiClient.OPRUnit).weapons:
				for r in w.special_rules:
					if str(r).begins_with(prefix):
						return str(r)
	return ""


func _unexplained(cmp: Dictionary, deny := {}) -> int:
	return (RosterSweep.gate(cmp["verdicts"], deny)["unexplained"] as Array).size()


## (i) RED: the core reads AP(2) where the table reads AP(1): the saves differ in every volley of a shooter that carries it.
func test_a_rule_parameter_edited_on_the_core_side_only_is_caught() -> void:
	var rule := _weapon_rule("AP(1)")
	assert_str(rule).override_failure_message("the pair carries no AP(1) weapon: the fault has nothing to edit").is_not_empty()
	assert_int(_unexplained(await _sweep())).override_failure_message("the control is not green").is_equal(0)
	var planted := await _sweep({"core_edit_rule": {"from": rule, "to": "AP(2)"}})
	print("ROSTER_FAULT ap_edit unexplained=%d" % _unexplained(planted))
	assert_int(_unexplained(planted)).override_failure_message("a core-only AP edit went unseen").is_greater(0)
	assert_str(_weapon_rule("AP(1)")).override_failure_message("the edit was not undone").is_equal(rule)


## (ii) RED: the table knows the target carries a Vengeance marker (+1 to hit for its attackers), the core's capture does not.
func test_a_ledger_key_dropped_from_the_capture_is_caught() -> void:
	var fact := {"ledger": {"tgt": {"vengeance_markers": 1}}}
	assert_int(_unexplained(await _sweep(fact))).override_failure_message("the control (fact on both halves) is not green").is_equal(0)
	var planted := await _sweep(fact.merged({"core_drop": {"tgt": ["vengeance_markers"]}}))
	var dice := (planted["verdicts"] as Array).filter(func(v: Dictionary) -> bool: return v["first_diff"] == "rolls").size()
	print("ROSTER_FAULT ledger_drop unexplained=%d roll_diffs=%d" % [_unexplained(planted), dice])
	assert_int(_unexplained(planted)).override_failure_message("a dropped ledger key went unseen").is_greater(0)
	assert_int(dice).override_failure_message("the dice must differ too, not only the ledger left behind").is_greater(0)


## (iii) RED: the core's recorded stream differs by one face of one roll; the compare reads faces.
func test_one_face_swapped_in_the_core_half_is_caught() -> void:
	assert_int(_unexplained(await _sweep())).override_failure_message("the control is not green").is_equal(0)
	var planted := await _sweep({"core_swap_face": 0})
	var fired := (planted["verdicts"] as Array).filter(func(v: Dictionary) -> bool: return bool(v["fired"])).size()
	print("ROSTER_FAULT face_swap unexplained=%d fired=%d" % [_unexplained(planted), fired])
	assert_int(fired).is_greater(0)
	assert_int(_unexplained(planted)).override_failure_message("every fired volley has a roll 0: all of them must differ").is_equal(fired)


## (iv) RED: the (i) difference is real; an entry for `AP` explains it, the same run without the entry does not.
func test_a_removed_deny_entry_turns_the_explained_difference_red() -> void:
	var rule := _weapon_rule("AP(1)")
	var planted := await _sweep({"core_edit_rule": {"from": rule, "to": "AP(2)"}})
	var deny := {"AP": "planted core-side edit"}
	assert_int(int(RosterSweep.gate(planted["verdicts"], deny)["explained"])).override_failure_message("nothing to explain").is_greater(0)
	assert_int(_unexplained(planted, deny)).override_failure_message("the entry does not explain its own difference").is_equal(0)
	assert_int(_unexplained(planted, {})).override_failure_message("the entry was removed and the sweep stayed green").is_greater(0)
