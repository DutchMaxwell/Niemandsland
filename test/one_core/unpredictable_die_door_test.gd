extends GdUnitTestSuite
## Gate 12 (21.11., Zairetia): the core throws the Unpredictable (Shooter) die before any weapon fires, even when no weapon of the shooter reaches the
## target; the table fires nothing and rolls nothing then. Zairetia's one gun reaches 12 in, the sweep puts the target 14 in away: 16 of 16 seeds differ
## (with or without a Versatile pick, `Unpredictable Shooter` and the generic `Unpredictable`); in reach both halves are equal. The deny group
## `unpredictable_die_without_weapon_in_reach` refuses a die bearer as a SHOOTER by its primitives (a bearer as a target is taken).
## RED: take the group out of the deny file -> the first test's refusal assertion fails. The difference assertion fails the day the core fixes the cause.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DICE := "user://unpredictable_die_dice"
const SEEDS := 16

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


func after_test() -> void:
	RosterSweep.disarm(_main)
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _weapon(wname: String, reach: int, attacks: int, count: int, rules := []) -> OPRApiClient.OPRWeapon:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = wname
	w.range_value = reach
	w.attacks = attacks
	w.count = count
	w.special_rules.assign(rules)
	return w


## Zairetia's shape: a lone Vinci hero, Vinci Tech (the Versatile pick) beside the die, one 12 in Blast gun and a hand weapon.
func _unit(uname: String, size: int, rules: Array, weapons: Array, faction := "duchies_of_vinci") -> Dictionary:
	var ou := OPRApiClient.OPRUnit.new()
	ou.name = uname
	ou.size = size
	ou.quality = 4
	ou.defense = 5
	ou.game_system = "aof"
	ou.special_rules.assign(rules)
	ou.weapons.assign(weapons)
	return {"unit": ou, "faction": faction, "system": "aof"}


func _bearer(die_rule: String, versatile := true) -> Dictionary:
	var rules := ["Hero", "Tough(3)"] + (["Vinci Tech"] if versatile else []) + ([die_rule] if die_rule != "" else [])
	return _unit("Alchemist", 1, rules, [_weapon("Toxin Bellow", 12, 1, 1, ["Blast(3)", "Bane"]), _weapon("Hand Weapon", 0, 3, 1)])


func _squad() -> Dictionary:
	return _unit("Squad", 5, [], [], "dwarves")

func _faces(rolls: Array) -> Array:
	return rolls.map(func(r: Dictionary) -> String: return "%s:%d:%s" % [r["kind"], int(r["count"]), r["faces"]])


## {"differing": seeds (of 16) whose dice or end state differ between the table and the core, "deny": the pair's deny-slice reasons (seed 0)}.
func _compare(shooter: Dictionary, target: Dictionary, distance_in: float) -> Dictionary:
	var dice := ProjectSettings.globalize_path(DICE)
	var differing := 0
	var deny: Array = []
	for s in SEEDS:
		var t := await RosterSweep.volley(_main, shooter, target, s, false, dice, {"distance_in": distance_in})
		var c := await RosterSweep.volley(_main, shooter, target, s, true, dice, {"distance_in": distance_in})
		deny = t["deny"] if s == 0 else deny
		if _faces(t["rolls"]) != _faces(c["rolls"]) or RosterSweep.first_state_diff(t["state"], c["state"]) != "":
			differing += 1
	return {"differing": differing, "deny": deny}


## The refused case: the bearer 14 in away, its only gun reaching 12: the table rolls nothing, the core throws the die, the slice refuses the shooter.
## Pinned below the epoch 95 batch (UPR_NEEDS_SHOT): from 95 the core throws no die then and the halves are equal (the next test leg); the deny group stays
## in the file until its lift, so the refusal assertion holds at both epochs.
func test_a_die_bearer_out_of_reach_differs_and_is_refused_as_a_shooter() -> void:
	var epoch_before := AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_95_PARITY_BATCH - 1
	for row in [["Unpredictable Shooter", true], ["Unpredictable Shooter", false], ["Unpredictable", true], ["Unpredictable", false]]:
		var r := await _compare(_bearer(row[0], row[1]), _squad(), 14.0)
		assert_int(int(r["differing"])).override_failure_message("%s (Versatile %s): %d of %d seeds differ - the core no longer throws the die, lift the group" % [row[0], row[1], r["differing"], SEEDS]).is_equal(SEEDS)
		assert_array(r["deny"]).override_failure_message("%s (Versatile %s): the deny slice takes a die bearer out of reach" % [row[0], row[1]]).contains(["unit_rule:" + row[0]])
	AiActRecorder.rules_epoch = epoch_before
	# From 95 the same out-of-reach volley is equal: no weapon in reach, no die.
	var r95 := await _compare(_bearer("Unpredictable Shooter"), _squad(), 14.0)
	assert_int(int(r95["differing"])).override_failure_message("from 95 an out-of-reach die bearer is equal: %d of %d seeds differ" % [r95["differing"], SEEDS]).is_equal(0)


## In reach both halves are equal: the refusal is wider than the difference (the slice cannot see the reach).
func test_a_die_bearer_in_reach_is_equal() -> void:
	var r := await _compare(_bearer("Unpredictable Shooter"), _squad(), 8.0)
	assert_int(int(r["differing"])).override_failure_message("%d of %d seeds differ in reach" % [r["differing"], SEEDS]).is_equal(0)


## The die is the SHOOTER's: a bearer as a target is taken and equal.
func test_a_die_bearer_as_a_target_is_taken() -> void:
	var rifles := _unit("Rifles", 5, [], [_weapon("Rifle", 24, 2, 5)], "dwarves")
	var r := await _compare(rifles, _bearer("Unpredictable Shooter"), 8.0)
	assert_array(r["deny"]).override_failure_message("a die-bearing target is refused: %s" % [r["deny"]]).is_empty()
	assert_int(int(r["differing"])).override_failure_message("%d of %d seeds differ at a die-bearing target" % [r["differing"], SEEDS]).is_equal(0)


## Control: the same shooter without the die, out of reach, is taken and equal.
func test_the_same_shooter_without_the_die_out_of_reach_is_taken_and_equal() -> void:
	var r := await _compare(_bearer("", false), _squad(), 14.0)
	assert_array(r["deny"]).is_empty()
	assert_int(int(r["differing"])).override_failure_message("%d of %d seeds differ without the die" % [r["differing"], SEEDS]).is_equal(0)
