extends GdUnitTestSuite
## One core, door lines (lane dlines2, train 2): the rule lines a DEFENDER's rules add before the volley, in the table's words - the Ranged
## Shrouding family's range cut ("<rule>: <U> - weapon ranges against it 6" shorter (min 6")"). Each part of the train lifts its deny group
## in the same commit: the deny file no longer lists the primitive, so the door takes these volleys, and this suite proves the lines equal
## (`door_lines.gd`: `SEEDS` seeded volleys on the table and on the door, the lines that name the rule compared).
## Real: the main scene, NmlCore, the importer's own unit builder, the table's AI body. Constructed: the OPR units (no list file).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DoorLines := preload("res://test/one_core/door_lines.gd")
const SEEDS := 12
const DICE := "user://door_lines_defense_dice"

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


func _same(label: String, shooter: Dictionary, target: Dictionary, prefix: String, min_fired := 1) -> void:
	var r := await DoorLines.compare(_main, shooter, target, prefix, SEEDS, ProjectSettings.globalize_path(DICE))
	print("DOOR_LINES %s fired=%d/%d mismatches=%d" % [label, r["fired"], SEEDS, (r["bad"] as Array).size()])
	assert_int(int(r["fired"])).override_failure_message("%s: the rule never fired on the table, nothing is compared" % label).is_greater_equal(min_fired)
	assert_array(r["bad"]).override_failure_message("%s: the door's lines differ from the table's:\n%s" % [label, "\n".join((r["bad"] as Array).slice(0, 4))]).is_empty()


func _gunners() -> Dictionary:
	return DoorLines.entry("Gunners", 10, [], [], "battle_brothers", 10)


func test_a_shrouded_target_names_its_range_cut() -> void:
	await _same("ranged shrouding", _gunners(), DoorLines.entry("Targets", 10, ["Ranged Shrouding"], [], "custodian_brothers", 0), "Ranged Shrouding:", SEEDS)
	await _same("darkborn", _gunners(), DoorLines.entry("Targets", 10, ["Darkborn"], [], "dark_brothers", 0), "Darkborn:", SEEDS)


func _striker(rules: Array, weapon_rules: Array, faction := "battle_brothers", system := "gf") -> Dictionary:
	var e := DoorLines.entry("Strikers", 10, rules, weapon_rules, faction, 10)
	(e["unit"] as OPRApiClient.OPRUnit).game_system = system
	e["system"] = system
	return e


func _ranks() -> Dictionary:
	return DoorLines.entry("Ranks", 10, [], [], "battle_brothers", 0)


## The Bane family names its re-roll: plain Bane, a lone Lacerate, the unit-level aliases (Mischievous, Vicious, Scrapper, Unstoppable when
## Shooting) - before the re-roll dice, the way the table does (weapon aliases said theirs since the first train).
func test_the_bane_family_names_its_rerolls() -> void:
	await _same("bane unit", _striker(["Bane"], []), _ranks(), "Bane:", 6)
	await _same("bane weapon", _striker([], ["Bane"]), _ranks(), "Bane:", 6)
	await _same("lacerate", _striker([], ["Lacerate"]), _ranks(), "Lacerate:", 6)
	await _same("mischievous", _striker(["Mischievous"], [], "goblin_reclaimers"), _ranks(), "Mischievous", 6)
	await _same("vicious", _striker(["Vicious"], [], "goblin_reclaimers"), _ranks(), "Vicious", 6)
	await _same("scrapper", _striker(["Scrapper"], [], "jackals"), _ranks(), "Scrapper", 6)
	await _same("unstoppable when shooting", _striker(["Unstoppable when Shooting"], []), _ranks(), "Unstoppable when Shooting:", 6)


func _ap(n: int) -> Array:
	return ["AP(%d)" % n]


## The Fortified family names its AP cut once per save batch: the plain rule, a Boost (no distance gate) and the gated alias; the weapon
## has AP to cut, so every volley that hits says it.
func test_a_fortified_target_names_its_ap_cut() -> void:
	await _same("fortified", _striker([], _ap(2)), DoorLines.entry("Ranks", 10, ["Fortified"], [], "alien_hives", 0), "Fortified:", 6)
	await _same("guardian", _striker([], _ap(2)), DoorLines.entry("Ranks", 10, ["Guardian"], [], "custodian_brothers", 0), "Guardian:", 6)
	await _same("enhanced guardian", _striker([], _ap(3)), DoorLines.entry("Ranks", 10, ["Guardian", "Enhanced Guardian"], [], "custodian_brothers", 0), "Enhanced Guardian:", 6)


## A Shielded target names its +1 Defense once, before the announce (its own name leads the line, so the prefix is the target's).
func test_a_shielded_target_names_its_defense_bonus() -> void:
	await _same("shielded", _striker([], []), DoorLines.entry("Ranks", 10, ["Shielded"], [], "battle_brothers", 0), "Ranks is", 6)
	await _same("enhanced sturdy", _striker([], []), DoorLines.entry("Ranks", 10, ["Sturdy", "Enhanced Sturdy"], [], "dwarf_guilds", 0), "Ranks is", 6)
	await _same("defense rating", _striker([], []), DoorLines.entry("Ranks", 10, ["Defense(1)"], [], "battle_brothers", 0), "Ranks is", 6)


## The plain Regeneration group names its roll ("regeneration", the table's own spelling) and, against a bypass weapon, the skip.
func test_the_regeneration_group_names_its_roll_and_the_bypass() -> void:
	await _same("regeneration", _striker([], []), DoorLines.entry("Ranks", 10, ["Regeneration"], [], "battle_brothers", 0), "Ranks rolls", 6)
	await _same("regeneration aura", _striker([], []), DoorLines.entry("Ranks", 10, ["Regeneration Aura"], [], "alien_hives", 0), "Ranks rolls", 6)
	await _same("bypass", _striker(["Bane"], []), DoorLines.entry("Ranks", 10, ["Regeneration"], [], "battle_brothers", 0), "Ranks:", 6)


func _ignorer(rules: Array, faction: String, system := "gf") -> Dictionary:
	var e := DoorLines.entry("Ranks", 10, rules, [], faction, 0)
	(e["unit"] as OPRApiClient.OPRUnit).game_system = system
	e["system"] = system
	return e


## The other wound-ignore groups name their roll the way the table spells it (the rule's own name, "self-repair" / "resistance" in lower case), and a
## bypass weapon (Bane / Rending) at a group not named Regeneration names the "ignore only Regeneration - X still rolls" line, the count of the
## bypass wounds that joined the pool. The aliases with a distance gate, a terrain condition or a once-per-game latch stay refused by name.
func test_the_other_ignore_groups_name_their_roll() -> void:
	await _same("self-repair", _striker([], []), _ignorer(["Self-Repair"], "robot_legions"), "Ranks rolls", 6)
	await _same("enhanced self-repair", _striker([], []), _ignorer(["Self-Repair", "Enhanced Self-Repair"], "robot_legions"), "Ranks rolls", 6)
	await _same("resistance", _striker([], []), _ignorer(["Resistance"], "alien_hives"), "Ranks rolls", 6)
	await _same("plaguebound", _striker([], []), _ignorer(["Plaguebound"], "plague_disciples"), "Ranks rolls", 6)
	await _same("enhanced plaguebound", _striker([], []), _ignorer(["Plaguebound", "Enhanced Plaguebound"], "plague_disciples"), "Ranks rolls", 6)
	await _same("protected", _striker([], []), _ignorer(["Protected"], "plague_disciples"), "Ranks rolls", 6)
	await _same("cursed undead", _striker([], []), _ignorer(["Cursed Undead"], "vampiric_undead", "aof"), "Ranks rolls", 6)
	await _same("self-repair vs bane", _striker(["Bane"], []), _ignorer(["Self-Repair"], "robot_legions"), "Ranks:", 6)
	await _same("plaguebound vs bane", _striker(["Bane"], []), _ignorer(["Plaguebound"], "plague_disciples"), "Ranks:", 6)
	await _same("regeneration + self-repair vs bane", _striker(["Bane"], []), _ignorer(["Regeneration", "Self-Repair"], "robot_legions"), "Ranks:", 6)
