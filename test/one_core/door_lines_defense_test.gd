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


func _same(label: String, shooter: Dictionary, target: Dictionary, prefix: String, min_fired := 1, opts := {}) -> void:
	var r := await DoorLines.compare(_main, shooter, target, prefix, SEEDS, ProjectSettings.globalize_path(DICE), opts)
	print("DOOR_LINES %s fired=%d/%d mismatches=%d state_bad=%d" % [label, r["fired"], SEEDS, (r["bad"] as Array).size(), r["state_bad"]])
	assert_int(int(r["state_bad"])).override_failure_message("%s: the end states differ, the lines are compared over a pair the door must not take" % label).is_equal(0)
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


## H-17b (Plan H): an Armor(X) target that the rating IMPROVES names it once before the announce (`<U> has Armor(X): counts as Defense X+`, the table's
## `_solo_log_armor`); a rating no better than the printed Defense (4+) says nothing on either side. RED: drop `say_armor` from the volley seam -> the table says the line and the door does not.
func test_an_armored_target_names_its_defense() -> void:
	await _same("armor", _striker([], []), DoorLines.entry("Ranks", 10, ["Armor(3)"], [], "battle_brothers", 0), "Ranks has Armor", 6)
	await _same("armor 2+", _striker([], []), DoorLines.entry("Ranks", 10, ["Armor(2)"], [], "battle_brothers", 0), "Ranks has Armor", 6)
	await _same("armor no better", _striker([], []), DoorLines.entry("Ranks", 10, ["Armor(5)"], [], "battle_brothers", 0), "Ranks has Armor", 0)


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


## The distance-gated ignore rule (Warding / Knightborn / Angelic Blessing: 6+ only when shot from over 9 in) says its verdict once per volley, under the
## name "Warding": the ignore when the gate is open, the refusal when the shooter is within it; the roll lines follow when it rolled.
func test_the_gated_ignore_rule_says_its_verdict() -> void:
	for far in [14.0, 5.0]:
		var label := "knightborn at %d in" % int(far)
		await _same(label, _striker([], []), _ignorer(["Knightborn"], "knight_brothers"), "Warding:", 6, {"distance_in": far})
		if far > 9.0:
			await _same(label + " (roll)", _striker([], []), _ignorer(["Knightborn"], "knight_brothers"), "Ranks rolls", 6, {"distance_in": far})
	await _same("warding at 14 in", _striker([], []), _ignorer(["Warding"], "knight_brothers"), "Warding:", 6, {"distance_in": 14.0})
	await _same("angelic blessing at 14 in", _striker([], []), _ignorer(["Angelic Blessing"], "kingdom_of_angels", "aof"), "Warding:", 6, {"distance_in": 14.0})
	await _same("knightborn vs bane at 14 in", _striker(["Bane"], []), _ignorer(["Knightborn"], "knight_brothers"), "Ranks:", 6, {"distance_in": 14.0})


## WDENY (19.11., found reviewing dlines train 4): the gated ignore rule BESIDE another ignore group. The core stamped the gate only when the gated rule was the best
## ignore, so beside Regeneration the `Warding:` line was missing from over 9 in (12/12 seeds) and, from within 9 in, the door still rolled the gated group the table
## refuses (lines 12/12, end state 7/12). Each pair is compared on the gate line AND on every roll line, both distances; `_same` asserts the end states equal (0 diffs).
func test_the_gated_ignore_rule_beside_another_group_says_its_verdict_and_rolls_alike() -> void:
	var pairs := [
		["regeneration + warding", ["Regeneration", "Warding"], "knight_brothers", "gf"],
		["regeneration + knightborn", ["Regeneration", "Knightborn"], "knight_brothers", "gf"],
		["regeneration + angelic blessing", ["Regeneration", "Angelic Blessing"], "kingdom_of_angels", "aof"],
		["regeneration aura + knightborn", ["Regeneration Aura", "Knightborn"], "knight_brothers", "gf"],
		["medical training + knightborn", ["Medical Training", "Knightborn"], "knight_brothers", "gf"],
		["spell resistance + knightborn", ["Spell Resistance", "Knightborn"], "knight_brothers", "gf"],
		["warding + knightborn", ["Warding", "Knightborn"], "knight_brothers", "gf"],
		["regeneration + warding + knightborn", ["Regeneration", "Warding", "Knightborn"], "knight_brothers", "gf"],
	]
	for pair in pairs:
		for dist in [14.0, 5.0]:
			var label := "%s at %d in" % [pair[0], int(dist)]
			await _same(label + " (gate line)", _striker([], ["AP(1)"], "battle_brothers"), _ignorer(pair[1], pair[2], pair[3]), "Warding:", 6, {"distance_in": dist})
			# two gated names from within the gate: both are shut and nothing rolls on either path (the empty comparison is the point)
			var rolls := 0 if dist < 9.0 and pair[0] == "warding + knightborn" else 6
			await _same(label + " (rolls)", _striker([], ["AP(1)"], "battle_brothers"), _ignorer(pair[1], pair[2], pair[3]), "Ranks rolls", rolls, {"distance_in": dist})
	for dist in [14.0, 5.0]:
		await _same("regeneration + knightborn vs bane at %d in" % int(dist), _striker(["Bane"], []), _ignorer(["Regeneration", "Knightborn"], "knight_brothers"), "Ranks:", 6, {"distance_in": dist})


## PLAN_COVER_36 step 9c: cover from sight blockers through the door at epoch 95. A third unit of the shooter's seat, short models in a closed
## line (20 mm bases, gaps under 1 in) 2 in in front of the target, hides its feet, not its heads: both halves say the screen line and save
## alike (`_same` asserts the end states). A held Indirect gun at the same target lifts it and both say the lift line. Planted fault: the door
## at 94 (table at 95) has no screen line - the row turns red, so the comparison can fail on this rule.
func test_cover_from_sight_blockers_says_the_same_lines_through_the_door() -> void:
	var was := AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_95_PARITY_BATCH
	var wall := DoorLines.entry("Wall", 9, [], [], "battle_brothers", 0)
	(wall["unit"] as OPRApiClient.OPRUnit).base_size_round = 20
	var opts := {"distance_in": 14.0, "blocker": wall, "blocker_in": 12.0}
	await _same("screened by a closed unit line", DoorLines.entry("Gunners", 5, [], []), DoorLines.entry("Squad", 5, [], []), "Cover:", 6, opts)
	await _same("held indirect lifts it", DoorLines.entry("Mortars", 3, [], ["Indirect"]), DoorLines.entry("Squad", 5, [], []), "Indirect:", 1, opts)
	var r := await DoorLines.compare(_main, DoorLines.entry("Gunners", 5, [], []), DoorLines.entry("Squad", 5, [], []), "Cover:", 4,
		ProjectSettings.globalize_path(DICE), opts.merged({"core_epoch": AiActRecorder.EPOCH_95_PARITY_BATCH - 1}))
	AiActRecorder.rules_epoch = was
	assert_int((r["bad"] as Array).size()).override_failure_message("planted fault: a door at 94 must differ from the table at 95").is_equal(4)
