extends GdUnitTestSuite
## One core, door lines (lane dlines3, train 3): the rule lines an ATTACKER's rules add, in the table's words - the Shred family's pay line
## (`<rule>: N Defense rolls of 1 -> +N wounds`), the widened window's line and the once-per-volley announcement of the widening. Each part of the
## train lifts its deny entry in the same commit; this suite proves the lines equal (`door_lines.gd`: seeded volleys on the table and on the
## door, the lines that name the rule compared).
## Real: the main scene, NmlCore, the importer's own unit builder, the table's AI body. Constructed: the OPR units (no list file).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DoorLines := preload("res://test/one_core/door_lines.gd")
const SEEDS := 12
const DICE := "user://door_lines_attack_dice"

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


func _same(label: String, shooter: Dictionary, target: Dictionary, prefix: String, min_fired := 6, opts := {}) -> void:
	var r := await DoorLines.compare(_main, shooter, target, prefix, SEEDS, ProjectSettings.globalize_path(DICE), opts)
	print("DOOR_LINES %s fired=%d/%d mismatches=%d state_bad=%d" % [label, r["fired"], SEEDS, (r["bad"] as Array).size(), r["state_bad"]])
	assert_int(int(r["state_bad"])).override_failure_message("%s: the end states differ, the lines are compared over a pair the door must not take" % label).is_equal(0)
	assert_int(int(r["fired"])).override_failure_message("%s: the rule never fired on the table, nothing is compared" % label).is_greater_equal(min_fired)
	assert_array(r["bad"]).override_failure_message("%s: the door's lines differ from the table's:\n%s" % [label, "\n".join((r["bad"] as Array).slice(0, 4))]).is_empty()


func _striker(rules: Array, weapon_rules: Array, faction := "battle_brothers", system := "gf", size := 10) -> Dictionary:
	var e := DoorLines.entry("Strikers", size, rules, weapon_rules, faction, size)
	(e["unit"] as OPRApiClient.OPRUnit).game_system = system
	e["system"] = system
	return e


func _ranks(defense := 5) -> Dictionary:
	var e := DoorLines.entry("Ranks", 10, [], [], "battle_brothers", 0)
	(e["unit"] as OPRApiClient.OPRUnit).defense = defense
	return e


## The Shred family: a weapon's own Shred, the unit-level rule, a data alias (Warbound), the Enhanced form (pays at any distance, announces it).
func test_the_shred_family_names_its_pay_line() -> void:
	await _same("shred weapon", _striker([], ["Shred"]), _ranks(), "Shred:")
	await _same("shred unit", _striker(["Shred"], []), _ranks(), "Shred:")
	await _same("shred when shooting", _striker(["Shred when Shooting"], []), _ranks(), "Shred when Shooting:")
	await _same("warbound", _striker(["Warbound"], [], "war_disciples"), _ranks(), "Warbound:")
	await _same("enhanced warbound", _striker(["Warbound", "Enhanced Warbound"], [], "war_disciples"), _ranks(), "Enhanced Warbound:")
	await _same("infected", _striker(["Infected", "Enhanced Infected"], [], "infected_colonies"), _ranks(), "Enhanced Infected:")


## The 3.5 Boost widens the window of failed saves to 1-2 past 9": its announcement once per volley and its pay line (aofr: Warbound Boost).
func test_the_shred_boost_names_its_window() -> void:
	await _same("warbound boost", _striker(["Warbound", "Warbound Boost"], [], "war_disciples", "aofr"), _ranks(), "Warbound Boost:", 6, {"distance_in": 14.0})
	await _same("destroyer boost", _striker(["Destroyer", "Destroyer Boost"], [], "ogres", "aofr"), _ranks(), "Destroyer Boost:", 6, {"distance_in": 14.0})


## Deadly at a Tough target that has an ignore group: every unsaved Deadly wound takes its pick BEFORE the ignore roll (the table's `deadly_pick`), so
## the "finish the already-wounded Tough model first" count includes a wound whose X were all ignored; the core dropped such a wound and counted one
## forced pick too few. Many shooters and a Defense 6+ target make all-ignored wounds (three 5+ dice) turn up within the seeds.
func test_deadly_counts_the_picks_of_ignored_wounds() -> void:
	var target := DoorLines.entry("Ranks", 10, ["Regeneration", "Tough(6)"], [], "battle_brothers", 0)
	(target["unit"] as OPRApiClient.OPRUnit).defense = 6
	await _same("deadly vs regeneration", _striker([], ["Deadly(3)"], "battle_brothers", "gf", 30), target, "Deadly(3):", 6)
