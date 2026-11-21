extends GdUnitTestSuite
## PLAN H, DEADLY LANDING INLINE (`EPOCH_94_PARITY_BATCH` = 94, lead decision 20.11.). The table lands a Deadly weapon's unsaved wounds right
## after that weapon's saves, so a later weapon of the same volley reads the target as it stands then: a lone Hero the Deadly wounds killed no
## longer lends its Stealth / Changebound / Stealth Aura / Evasive to the weapons still to fire ("dead models lend nothing"). The core landed Deadly
## after all the dice and kept the captured target: 11 of 16 seeds of this fixture rolled a different to-hit number on the later weapon (H-10,
## ds/h_probe_stealth_family.md). From 94 the core's volley fold lands each Deadly weapon's groups on a scratch copy of the state and reads
## `Ctx::wiped` for the weapons still to fire; below 94 it is byte-identical.
## RED: against the library without the change, the 94 leg differs on 11 of 16 seeds per rule (and the 92 leg of this suite shows the fixture
## differs where the epoch does not apply). Dice and end state are compared, and the two lines the inline landing adds: the table's `Simultaneous fire:`
## (casualties since the declaration did not shrink this shot) and the ` (cap read when the volley started)` note of a Blast line.

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


func _named(lines: Array, prefixes: Array) -> Array:
	return lines.filter(func(l: String) -> bool: return prefixes.any(func(p: String) -> bool: return l.begins_with("COMBAT|" + p)))


## Seeds (of 16) whose dice, end state or `prefixes` lines differ between the table and the core at `epoch`; `said` counts the seeds where the
## table said such a line (so a check on lines proves something).
func _differing(target: Dictionary, epoch: int, shooter := {}, prefixes := []) -> Dictionary:
	AiActRecorder.rules_epoch = epoch
	var dice := ProjectSettings.globalize_path(DICE)
	var bad := 0
	var said := 0
	for s in SEEDS:
		var sh := shooter if not shooter.is_empty() else _shooter()
		var t := await RosterSweep.volley(_main, sh, target, s, false, dice)
		var c := await RosterSweep.volley(_main, sh, target, s, true, dice)
		var tl := _named(t["lines"], prefixes)
		said += 1 if not tl.is_empty() else 0
		if _faces(t["rolls"]) != _faces(c["rolls"]) or RosterSweep.first_state_diff(t["state"], c["state"]) != "" \
				or tl != _named(c["lines"], prefixes):
			bad += 1
	return {"bad": bad, "said": said}


func test_a_hero_the_deadly_weapon_killed_lends_no_rule_to_the_later_weapon_from_94() -> void:
	var cases := [["Stealth", _hero(["Stealth"], "alien_hives")], ["Changebound", _hero(["Changebound"], "change_disciples")],
		["Stealth Aura", _hero(["Stealth Aura"], "robot_legions")], ["Evasive", _hero(["Evasive"], "battle_brothers")]]
	for c in cases:
		var at_92: Dictionary = await _differing(c[1], 92)
		assert_int(int(at_92["bad"])).override_failure_message("%s: the fixture reads equal below 94, the check cannot fail" % c[0]).is_greater(0)
		var at_94: Dictionary = await _differing(c[1], PENDING_EPOCH, {}, ["Simultaneous fire"])
		assert_int(int(at_94["said"])).override_failure_message("%s: the table never said `Simultaneous fire`, the line check proved nothing" % c[0]).is_greater(0)
		assert_int(int(at_94["bad"])).override_failure_message("%s: %d of 16 seeds still differ at 94" % [c[0], at_94["bad"]]).is_equal(0)


## Controls: no such rule on the Hero, and a Stealth unit of ten (nobody dies): equal at both epochs.
func test_the_controls_are_equal_at_both_epochs() -> void:
	var ranks := _hero(["Stealth"], "alien_hives")
	(ranks["unit"] as OPRApiClient.OPRUnit).size = 10
	for target in [_hero([], "battle_brothers"), ranks]:
		for epoch in [92, PENDING_EPOCH]:
			var r: Dictionary = await _differing(target, epoch)
			assert_int(int(r["bad"])).override_failure_message("a control differs on %d of 16 seeds at %d" % [r["bad"], epoch]).is_equal(0)


## A Blast weapon fired after the Deadly one at a unit of four Tough(1) models: the Deadly launcher kills one, the cap of the Blast line was read when the
## volley started (4), the table writes the note, the core now writes it too; the casualty also makes `Simultaneous fire` due.
func test_a_blast_line_after_a_deadly_kill_carries_the_cap_note() -> void:
	var ou := OPRApiClient.OPRUnit.new()
	ou.name = "Blasters"
	ou.size = 10
	ou.quality = 3
	ou.defense = 4
	ou.game_system = "gf"
	ou.weapons.append(_weapon("Deadly Launcher", 1, ["Deadly(3)", "AP(2)"]))
	ou.weapons.append(_weapon("Blast Rifle", 5, ["Blast(3)"]))
	var shooter := {"unit": ou, "faction": "battle_brothers", "system": "gf"}
	var tgt_unit := OPRApiClient.OPRUnit.new()
	tgt_unit.name = "Squad"
	tgt_unit.size = 4
	tgt_unit.quality = 4
	tgt_unit.defense = 4
	tgt_unit.game_system = "gf"
	var target := {"unit": tgt_unit, "faction": "battle_brothers", "system": "gf"}
	var r: Dictionary = await _differing(target, PENDING_EPOCH, shooter, ["Simultaneous fire", "Blast("])
	assert_int(int(r["said"])).override_failure_message("no Blast / Simultaneous line on the table").is_greater(0)
	assert_int(int(r["bad"])).override_failure_message("%d of 16 seeds differ in dice, state or the two lines" % r["bad"]).is_equal(0)

