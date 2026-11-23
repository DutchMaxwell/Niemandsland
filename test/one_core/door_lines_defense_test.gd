extends GdUnitTestSuite
## One core, door lines (lane dlines2, train 2): the rule lines a DEFENDER's rules add before the volley, in the table's words - the Ranged
## Shrouding family's range cut ("<rule>: <U> - weapon ranges against it 6" shorter (min 6")"). Each part of the train lifts its deny group
## in the same commit: the deny file no longer lists the primitive, so the door takes these volleys, and this suite proves the lines equal
## (`door_lines.gd`: `SEEDS` seeded volleys on the door, the lines that name the rule pinned per seed).
## Real: the main scene, NmlCore, the importer's own unit builder. Constructed: the OPR units (no list file).
## The table arm left with the AI table resolver; door values are snapshot pins read on main df2284f38 (docs/adr/0005-snapshot-pins.md).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DoorLines := preload("res://test/one_core/door_lines.gd")
const SEEDS := 12
const DICE := "user://door_lines_defense_dice"
## Per label: the door's count of rule lines that name the prefix, per seed (SEEDS entries).
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_LINES := {
	"ranged shrouding": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"darkborn": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"bane unit": [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"bane weapon": [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"lacerate": [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"mischievous": [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"vicious": [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"scrapper": [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"unstoppable when shooting": [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"fortified": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"guardian": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"enhanced guardian": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"shielded": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"enhanced sturdy": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"defense rating": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"armor": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"armor 2+": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"armor no better": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
	"regeneration": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"regeneration aura": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"bypass": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"self-repair": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"enhanced self-repair": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"resistance": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"plaguebound": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"enhanced plaguebound": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"protected": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"cursed undead": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"self-repair vs bane": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"plaguebound vs bane": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"regeneration + self-repair vs bane": [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2],
	"knightborn at 14 in": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"knightborn at 14 in (roll)": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"knightborn at 5 in": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"warding at 14 in": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"angelic blessing at 14 in": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"knightborn vs bane at 14 in": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"regeneration + warding at 14 in (gate line)": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"regeneration + warding at 14 in (rolls)": [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2],
	"regeneration + warding at 5 in (gate line)": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"regeneration + warding at 5 in (rolls)": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"regeneration + knightborn at 14 in (gate line)": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"regeneration + knightborn at 14 in (rolls)": [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2],
	"regeneration + knightborn at 5 in (gate line)": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"regeneration + knightborn at 5 in (rolls)": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"regeneration + angelic blessing at 14 in (gate line)": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"regeneration + angelic blessing at 14 in (rolls)": [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2],
	"regeneration + angelic blessing at 5 in (gate line)": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"regeneration + angelic blessing at 5 in (rolls)": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"regeneration aura + knightborn at 14 in (gate line)": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"regeneration aura + knightborn at 14 in (rolls)": [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2],
	"regeneration aura + knightborn at 5 in (gate line)": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"regeneration aura + knightborn at 5 in (rolls)": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"medical training + knightborn at 14 in (gate line)": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"medical training + knightborn at 14 in (rolls)": [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2],
	"medical training + knightborn at 5 in (gate line)": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"medical training + knightborn at 5 in (rolls)": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"spell resistance + knightborn at 14 in (gate line)": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"spell resistance + knightborn at 14 in (rolls)": [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2],
	"spell resistance + knightborn at 5 in (gate line)": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"spell resistance + knightborn at 5 in (rolls)": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"warding + knightborn at 14 in (gate line)": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"warding + knightborn at 14 in (rolls)": [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2],
	"warding + knightborn at 5 in (gate line)": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"warding + knightborn at 5 in (rolls)": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
	"regeneration + warding + knightborn at 14 in (gate line)": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"regeneration + warding + knightborn at 14 in (rolls)": [3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3],
	"regeneration + warding + knightborn at 5 in (gate line)": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"regeneration + warding + knightborn at 5 in (rolls)": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"regeneration + knightborn vs bane at 14 in": [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2],
	"regeneration + knightborn vs bane at 5 in": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"screened by a closed unit line": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	"held indirect lifts it": [1, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1, 0],
}

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


## One case: the door alone runs SEEDS volleys and writes the pinned count of `<prefix>` rule lines per seed.
func _door_says(label: String, shooter: Dictionary, target: Dictionary, prefix: String, opts := {}) -> void:
	var want: Array = WANT_LINES.get(label, [])
	var got: Array = []
	for s in SEEDS:
		var v: Dictionary = await RosterSweep.volley(_main, shooter, target, s, true, ProjectSettings.globalize_path(DICE), opts)
		got.append(DoorLines.named(v["lines"], prefix).size())
	print("DOOR_LINES %s %s" % [label, JSON.stringify(got)])
	assert_array(got).override_failure_message("%s: the door's %s lines per seed %s, want %s" % [label, prefix, JSON.stringify(got), JSON.stringify(want)]).is_equal(want)


func _gunners() -> Dictionary:
	return DoorLines.entry("Gunners", 10, [], [], "battle_brothers", 10)


func test_a_shrouded_target_names_its_range_cut() -> void:
	await _door_says("ranged shrouding", _gunners(), DoorLines.entry("Targets", 10, ["Ranged Shrouding"], [], "custodian_brothers", 0), "Ranged Shrouding:")
	await _door_says("darkborn", _gunners(), DoorLines.entry("Targets", 10, ["Darkborn"], [], "dark_brothers", 0), "Darkborn:")


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
	await _door_says("bane unit", _striker(["Bane"], []), _ranks(), "Bane:")
	await _door_says("bane weapon", _striker([], ["Bane"]), _ranks(), "Bane:")
	await _door_says("lacerate", _striker([], ["Lacerate"]), _ranks(), "Lacerate:")
	await _door_says("mischievous", _striker(["Mischievous"], [], "goblin_reclaimers"), _ranks(), "Mischievous")
	await _door_says("vicious", _striker(["Vicious"], [], "goblin_reclaimers"), _ranks(), "Vicious")
	await _door_says("scrapper", _striker(["Scrapper"], [], "jackals"), _ranks(), "Scrapper")
	await _door_says("unstoppable when shooting", _striker(["Unstoppable when Shooting"], []), _ranks(), "Unstoppable when Shooting:")


func _ap(n: int) -> Array:
	return ["AP(%d)" % n]


## The Fortified family names its AP cut once per save batch: the plain rule, a Boost (no distance gate) and the gated alias; the weapon
## has AP to cut, so every volley that hits says it.
func test_a_fortified_target_names_its_ap_cut() -> void:
	await _door_says("fortified", _striker([], _ap(2)), DoorLines.entry("Ranks", 10, ["Fortified"], [], "alien_hives", 0), "Fortified:")
	await _door_says("guardian", _striker([], _ap(2)), DoorLines.entry("Ranks", 10, ["Guardian"], [], "custodian_brothers", 0), "Guardian:")
	await _door_says("enhanced guardian", _striker([], _ap(3)), DoorLines.entry("Ranks", 10, ["Guardian", "Enhanced Guardian"], [], "custodian_brothers", 0), "Enhanced Guardian:")


## A Shielded target names its +1 Defense once, before the announce (its own name leads the line, so the prefix is the target's).
func test_a_shielded_target_names_its_defense_bonus() -> void:
	await _door_says("shielded", _striker([], []), DoorLines.entry("Ranks", 10, ["Shielded"], [], "battle_brothers", 0), "Ranks is")
	await _door_says("enhanced sturdy", _striker([], []), DoorLines.entry("Ranks", 10, ["Sturdy", "Enhanced Sturdy"], [], "dwarf_guilds", 0), "Ranks is")
	await _door_says("defense rating", _striker([], []), DoorLines.entry("Ranks", 10, ["Defense(1)"], [], "battle_brothers", 0), "Ranks is")


## H-17b (Plan H): an Armor(X) target that the rating IMPROVES names it once before the announce (`<U> has Armor(X): counts as Defense X+`, the table's
## `_solo_log_armor`); a rating no better than the printed Defense (4+) says nothing on either side. RED: drop `say_armor` from the volley seam -> the table says the line and the door does not.
func test_an_armored_target_names_its_defense() -> void:
	await _door_says("armor", _striker([], []), DoorLines.entry("Ranks", 10, ["Armor(3)"], [], "battle_brothers", 0), "Ranks has Armor")
	await _door_says("armor 2+", _striker([], []), DoorLines.entry("Ranks", 10, ["Armor(2)"], [], "battle_brothers", 0), "Ranks has Armor")
	await _door_says("armor no better", _striker([], []), DoorLines.entry("Ranks", 10, ["Armor(5)"], [], "battle_brothers", 0), "Ranks has Armor")


## The plain Regeneration group names its roll ("regeneration", the table's own spelling) and, against a bypass weapon, the skip.
func test_the_regeneration_group_names_its_roll_and_the_bypass() -> void:
	await _door_says("regeneration", _striker([], []), DoorLines.entry("Ranks", 10, ["Regeneration"], [], "battle_brothers", 0), "Ranks rolls")
	await _door_says("regeneration aura", _striker([], []), DoorLines.entry("Ranks", 10, ["Regeneration Aura"], [], "alien_hives", 0), "Ranks rolls")
	await _door_says("bypass", _striker(["Bane"], []), DoorLines.entry("Ranks", 10, ["Regeneration"], [], "battle_brothers", 0), "Ranks:")


func _ignorer(rules: Array, faction: String, system := "gf") -> Dictionary:
	var e := DoorLines.entry("Ranks", 10, rules, [], faction, 0)
	(e["unit"] as OPRApiClient.OPRUnit).game_system = system
	e["system"] = system
	return e


## The other wound-ignore groups name their roll the way the table spells it (the rule's own name, "self-repair" / "resistance" in lower case), and a
## bypass weapon (Bane / Rending) at a group not named Regeneration names the "ignore only Regeneration - X still rolls" line, the count of the
## bypass wounds that joined the pool. The aliases with a distance gate, a terrain condition or a once-per-game latch stay refused by name.
func test_the_other_ignore_groups_name_their_roll() -> void:
	await _door_says("self-repair", _striker([], []), _ignorer(["Self-Repair"], "robot_legions"), "Ranks rolls")
	await _door_says("enhanced self-repair", _striker([], []), _ignorer(["Self-Repair", "Enhanced Self-Repair"], "robot_legions"), "Ranks rolls")
	await _door_says("resistance", _striker([], []), _ignorer(["Resistance"], "alien_hives"), "Ranks rolls")
	await _door_says("plaguebound", _striker([], []), _ignorer(["Plaguebound"], "plague_disciples"), "Ranks rolls")
	await _door_says("enhanced plaguebound", _striker([], []), _ignorer(["Plaguebound", "Enhanced Plaguebound"], "plague_disciples"), "Ranks rolls")
	await _door_says("protected", _striker([], []), _ignorer(["Protected"], "plague_disciples"), "Ranks rolls")
	await _door_says("cursed undead", _striker([], []), _ignorer(["Cursed Undead"], "vampiric_undead", "aof"), "Ranks rolls")
	await _door_says("self-repair vs bane", _striker(["Bane"], []), _ignorer(["Self-Repair"], "robot_legions"), "Ranks:")
	await _door_says("plaguebound vs bane", _striker(["Bane"], []), _ignorer(["Plaguebound"], "plague_disciples"), "Ranks:")
	await _door_says("regeneration + self-repair vs bane", _striker(["Bane"], []), _ignorer(["Regeneration", "Self-Repair"], "robot_legions"), "Ranks:")


## The distance-gated ignore rule (Warding / Knightborn / Angelic Blessing: 6+ only when shot from over 9 in) says its verdict once per volley, under the
## name "Warding": the ignore when the gate is open, the refusal when the shooter is within it; the roll lines follow when it rolled.
func test_the_gated_ignore_rule_says_its_verdict() -> void:
	for far in [14.0, 5.0]:
		var label := "knightborn at %d in" % int(far)
		await _door_says(label, _striker([], []), _ignorer(["Knightborn"], "knight_brothers"), "Warding:", {"distance_in": far})
		if far > 9.0:
			await _door_says(label + " (roll)", _striker([], []), _ignorer(["Knightborn"], "knight_brothers"), "Ranks rolls", {"distance_in": far})
	await _door_says("warding at 14 in", _striker([], []), _ignorer(["Warding"], "knight_brothers"), "Warding:", {"distance_in": 14.0})
	await _door_says("angelic blessing at 14 in", _striker([], []), _ignorer(["Angelic Blessing"], "kingdom_of_angels", "aof"), "Warding:", {"distance_in": 14.0})
	await _door_says("knightborn vs bane at 14 in", _striker(["Bane"], []), _ignorer(["Knightborn"], "knight_brothers"), "Ranks:", {"distance_in": 14.0})


## WDENY (19.11., found reviewing dlines train 4): the gated ignore rule BESIDE another ignore group. The core stamped the gate only when the gated rule was the best
## ignore, so beside Regeneration the `Warding:` line was missing from over 9 in (12/12 seeds) and, from within 9 in, the door still rolled the gated group the table
## refuses (lines 12/12, end state 7/12). Each pair pins the door's gate line AND its roll lines, both distances.
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
			await _door_says(label + " (gate line)", _striker([], ["AP(1)"], "battle_brothers"), _ignorer(pair[1], pair[2], pair[3]), "Warding:", {"distance_in": dist})
			await _door_says(label + " (rolls)", _striker([], ["AP(1)"], "battle_brothers"), _ignorer(pair[1], pair[2], pair[3]), "Ranks rolls", {"distance_in": dist})
	for dist in [14.0, 5.0]:
		await _door_says("regeneration + knightborn vs bane at %d in" % int(dist), _striker(["Bane"], []), _ignorer(["Regeneration", "Knightborn"], "knight_brothers"), "Ranks:", {"distance_in": dist})


## PLAN_COVER_36 step 9c: cover from sight blockers through the door at epoch 95. A third unit of the shooter's seat, short models in a closed
## line (20 mm bases, gaps under 1 in) 2 in in front of the target, hides its feet, not its heads: the door says the screen line. A held
## Indirect gun at the same target lifts it and the door says the lift line.
func test_cover_from_sight_blockers_says_the_same_lines_through_the_door() -> void:
	var was := AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_95_PARITY_BATCH
	var wall := DoorLines.entry("Wall", 9, [], [], "battle_brothers", 0)
	(wall["unit"] as OPRApiClient.OPRUnit).base_size_round = 20
	var opts := {"distance_in": 14.0, "blocker": wall, "blocker_in": 12.0}
	await _door_says("screened by a closed unit line", DoorLines.entry("Gunners", 5, [], []), DoorLines.entry("Squad", 5, [], []), "Cover:", opts)
	await _door_says("held indirect lifts it", DoorLines.entry("Mortars", 3, [], ["Indirect"]), DoorLines.entry("Squad", 5, [], []), "Indirect:", opts)
	AiActRecorder.rules_epoch = was
