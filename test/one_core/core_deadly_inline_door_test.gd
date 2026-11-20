extends GdUnitTestSuite
## PLAN H, DEADLY LANDING INLINE (`PENDING_EPOCH_DEADLY_INLINE` = 94, lead decision 20.11.). The table lands a Deadly weapon's unsaved wounds right
## after that weapon's saves, so a later weapon of the same volley reads the target as it stands then: a lone Hero the Deadly wounds killed no
## longer lends its Stealth / Changebound / Stealth Aura / Evasive to the weapons still to fire ("dead models lend nothing"). The core landed Deadly
## after all the dice and kept the captured target: 11 of 16 seeds of this fixture rolled a different to-hit number on the later weapon (H-10,
## ds/h_probe_stealth_family.md). From 94 the core's volley fold lands each Deadly weapon's groups on a scratch copy of the state and reads
## `Ctx::wiped` for the weapons still to fire; below 94 it is byte-identical.
## RED: against the library without the change, the 94 leg differs on 11 of 16 seeds per rule (and the 92 leg of this suite shows the fixture
## differs where the epoch does not apply). Only dice and end state are compared here; the lines (Simultaneous fire) follow in a later step.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DICE := "user://deadly_inline_dice"
const SEEDS := 16
const PENDING_EPOCH := 94

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch_before := 0


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	RosterSweep.arm(_main, ProjectSettings.globalize_path(DICE))


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	RosterSweep.disarm(_main)
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _weapon(wname: String, count: int, rules: Array) -> OPRApiClient.OPRWeapon:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = wname
	w.range_value = 24
	w.attacks = 1
	w.count = count
	w.special_rules.assign(rules)
	return w


## A 10-model shooter with a Deadly(3) AP(2) launcher (one copy) beside a plain rifle (five copies): the Deadly weapon resolves first.
func _shooter() -> Dictionary:
	var ou := OPRApiClient.OPRUnit.new()
	ou.name = "Multi"
	ou.size = 10
	ou.quality = 3
	ou.defense = 4
	ou.game_system = "gf"
	ou.weapons.append(_weapon("Deadly Launcher", 1, ["Deadly(3)", "AP(2)"]))
	ou.weapons.append(_weapon("Plain Rifle", 5, []))
	return {"unit": ou, "faction": "battle_brothers", "system": "gf"}


## A lone Hero, Tough(3), with `rules` (the Deadly launcher kills it on a hit that stays unsaved).
func _hero(rules: Array, faction: String) -> Dictionary:
	var ou := OPRApiClient.OPRUnit.new()
	ou.name = "Lone Hero"
	ou.size = 1
	ou.quality = 4
	ou.defense = 4
	ou.game_system = "gf"
	ou.special_rules.assign(["Hero", "Tough(3)"] + rules)
	return {"unit": ou, "faction": faction, "system": "gf"}


func _faces(rolls: Array) -> Array:
	return rolls.map(func(r: Dictionary) -> String: return "%s:%d:%s" % [r["kind"], int(r["count"]), r["faces"]])


## Seeds (of 16) whose dice or end state differ between the table and the core at `epoch`.
func _differing(target: Dictionary, epoch: int) -> int:
	AiActRecorder.rules_epoch = epoch
	var dice := ProjectSettings.globalize_path(DICE)
	var bad := 0
	for s in SEEDS:
		var t := await RosterSweep.volley(_main, _shooter(), target, s, false, dice)
		var c := await RosterSweep.volley(_main, _shooter(), target, s, true, dice)
		if _faces(t["rolls"]) != _faces(c["rolls"]) or RosterSweep.first_state_diff(t["state"], c["state"]) != "":
			bad += 1
	return bad


func test_a_hero_the_deadly_weapon_killed_lends_no_rule_to_the_later_weapon_from_94() -> void:
	var cases := [["Stealth", _hero(["Stealth"], "alien_hives")], ["Changebound", _hero(["Changebound"], "change_disciples")],
		["Stealth Aura", _hero(["Stealth Aura"], "robot_legions")], ["Evasive", _hero(["Evasive"], "battle_brothers")]]
	for c in cases:
		var at_92 := await _differing(c[1], 92)
		assert_int(at_92).override_failure_message("%s: the fixture reads equal below 94, the check cannot fail" % c[0]).is_greater(0)
		var at_94 := await _differing(c[1], PENDING_EPOCH)
		assert_int(at_94).override_failure_message("%s: %d of 16 seeds still differ at 94" % [c[0], at_94]).is_equal(0)


## Controls: no such rule on the Hero, and a Stealth unit of ten (nobody dies): equal at both epochs.
func test_the_controls_are_equal_at_both_epochs() -> void:
	var ranks := _hero(["Stealth"], "alien_hives")
	(ranks["unit"] as OPRApiClient.OPRUnit).size = 10
	for target in [_hero([], "battle_brothers"), ranks]:
		for epoch in [92, PENDING_EPOCH]:
			var bad := await _differing(target, epoch)
			assert_int(bad).override_failure_message("a control differs on %d of 16 seeds at %d" % [bad, epoch]).is_equal(0)
