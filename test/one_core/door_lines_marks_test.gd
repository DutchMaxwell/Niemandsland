extends GdUnitTestSuite
## PLAN H, the shooter-side Mark beats (`vs_target` Utility Buffs: "once per activation, before attacking, pick one enemy unit ... which friendly
## units get <Rule> against once"). The table says three lines (`_solo_apply_vs_marks`: the pick; `_solo_record_spell_mod`: `... is ACTIVE`;
## `_solo_spend_records`: `... is consumed`); the core placed and spent the Mark without saying them. Per Mark name: 16 seeds of a unit carrying
## it at a plain unit on both halves, compared on the dice faces, the end state of both units and every line that names the Mark.
## RED: with a library from before the core's lines the compare reads UNEQUAL on every name below.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DICE := "user://door_lines_marks_dice"
const SEEDS := 16
## [Mark name, game system, faction folder]; every one carries `vs_target` in the registry map of its system. Only the Marks whose probe read EQUAL
## on the dice, both end states and every Mark line over 16 seeds belong here (Plan H probe, 20.11.). Not here, with the reason: Relentless Mark and
## Surge Mark (the table's per-effect line names the Mark, the core's does not), Rapid Charge Mark and Piercing Fighting Mark (a melee-scoped record:
## the core spends it in a volley, the table does not), Shred Mark (dice differ), Slayer / Indirect / Quick Shot / Increased Shooting Range Mark
## (the table never placed the Mark in this fixture, so nothing was compared).
const MARKS := [["Furious Mark", "gf", "rebel_guerrillas"], ["Rending Mark", "gf", "orc_marauders"], ["Unstoppable Mark", "gf", "battle_brothers"],
	["Piercing Shooting Mark", "gf", "dao_union"], ["Unpredictable Shooter Mark", "gf", "goblin_reclaimers"], ["Unpredictable Fighter Mark", "gf", "alien_hives"]]

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


func _entry(uname: String, rules: Array, system: String, faction: String) -> Dictionary:
	var ou := OPRApiClient.OPRUnit.new()
	ou.name = uname
	ou.size = 5
	ou.quality = 4
	ou.defense = 4
	ou.game_system = system
	ou.special_rules.assign(rules)
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rifle"
	w.range_value = 24
	w.attacks = 2
	w.count = 5
	ou.weapons.append(w)
	return {"unit": ou, "faction": faction, "system": system}


func _faces(rolls: Array) -> Array:
	return rolls.map(func(r: Dictionary) -> String: return "%s:%d:%s" % [r["kind"], int(r["count"]), r["faces"]])


func _named(lines: Array, mark: String) -> Array:
	return lines.filter(func(l: String) -> bool: return l.begins_with("COMBAT|") and l.contains(mark))


## 16 seeds of a carrier of `mark` at a plain unit: {"differing": seeds whose dice, end state or Mark lines differ, "said": seeds where the table said a Mark line}.
func _compare(mark: Array) -> Dictionary:
	var dice := ProjectSettings.globalize_path(DICE)
	var shooter := _entry("Att", [mark[0]], mark[1], mark[2])
	var target := _entry("Def", [], mark[1], mark[2])
	var differing := 0
	var said := 0
	var first := ""
	for s in SEEDS:
		var t := await RosterSweep.volley(_main, shooter, target, s, false, dice)
		var c := await RosterSweep.volley(_main, shooter, target, s, true, dice)
		var tl := _named(t["lines"], mark[0])
		said += 1 if not tl.is_empty() else 0
		if _faces(t["rolls"]) != _faces(c["rolls"]) or RosterSweep.first_state_diff(t["state"], c["state"]) != "" or tl != _named(c["lines"], mark[0]):
			differing += 1
			first = first if first != "" else "seed %d table %s core %s" % [s, JSON.stringify(tl), JSON.stringify(_named(c["lines"], mark[0]))]
	return {"differing": differing, "said": said, "first": first}


func test_a_mark_says_the_pick_the_record_and_the_spend_on_both_halves() -> void:
	for mark in MARKS:
		var r: Dictionary = await _compare(mark)
		assert_int(int(r["said"])).override_failure_message("%s: the table never said a Mark line, the compare proved nothing" % mark[0]).is_equal(SEEDS)
		assert_int(int(r["differing"])).override_failure_message("%s: %d of %d seeds differ: %s" % [mark[0], r["differing"], SEEDS, str(r["first"]).left(600)]).is_equal(0)
