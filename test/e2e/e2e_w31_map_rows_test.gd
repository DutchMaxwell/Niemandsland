extends GdUnitTestSuite
## E2E W31-F3/F4 (rules 3.6, release 0.3.15): the solo "apply it manually" note must not send a player to do
## by hand what the table does. Six rule rows sat missing next to mapped siblings, the named-hero marker had
## no row at all (the engine counts it as Hero), and AI-list item names with a trailing space slipped past the
## item-container filter. Driven on the real main.tscn: the real _solo_log_unmodeled_rules builds the note.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const NOTE_TAIL := "is not automated in solo — apply it manually"

## [system, book, rule, primitive] - the rows this change adds. Unique Hero is a common row (every book).
const ROWS := [
	["gf", "watch_brothers", "Enhanced Watchborn Aura", "Aura Channel"],
	["gf", "watch_prime_brothers", "Enhanced Watchborn Aura", "Aura Channel"],
	["gf", "machine_cults", "Grounded Evasion", "Stealth"],
	["gf", "infected_colonies", "Spawn", "Spawn"],
	["aof", "saurians", "Versatile Warrior Aura", "Aura Channel"],
	["aof", "kingdom_of_angels", "Versatile Warrior Buff", "Utility Buff"],
	["aof", "ratmen", "Increased Shooting Range", "Royal Legion"],
	["gf", "alien_hives", "Unique Hero", "Hero"],
	["gf", "orc_marauders", "Unique Hero", "Hero"],
	["aof", "dwarves", "Unique Hero", "Hero"],
	["aof", "wood_elves", "Unique Hero", "Hero"],
]

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main._solo_unmodeled_logged = {}


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _unit(system: String, faction: String, rules: Array, item_grants: Dictionary = {}) -> GameUnit:
	var u := GameUnit.new()
	u.unit_properties = {"name": "Test Unit", "game_system": system, "faction_folder": faction,
		"special_rules": rules, "item_grants": item_grants}
	return u


## The rule names the battle log told the player to apply by hand.
func _noted_rules() -> Array:
	var out: Array = []
	for e in _main.battle_log.entries():
		var t := str((e as Dictionary)["text"])
		if t.ends_with(NOTE_TAIL):
			out.append(t.get_slice(char(34), 1))   # the rule name sits between the first pair of double quotes
	return out


func test_each_new_row_resolves_to_its_sibling_primitive() -> void:
	for r: Array in ROWS:
		var entry := RulesRegistry.lookup(r[0], r[1], r[2])
		assert_str(str(entry.get("primitive", ""))) \
			.override_failure_message("%s/%s: %s does not resolve to %s: %s" % [r[0], r[1], r[2], r[3], entry]) \
			.is_equal(r[3])


## The player-visible fix: a carrier of each row's rule is no longer told to apply it by hand.
func test_a_carrier_of_each_new_row_gets_no_manual_note() -> void:
	for r: Array in ROWS:
		_main._solo_unmodeled_logged = {}
		_main._solo_log_unmodeled_rules(_unit(r[0], r[1], [r[2]]))
		assert_bool(_noted_rules().has(r[2])) \
			.override_failure_message("%s/%s: the table runs %s, yet the log says 'apply manually'" % [r[0], r[1], r[2]]) \
			.is_false()


## AI lists spell an item container with a trailing space ("Psy-Witch ") while the unit card's grant
## table keys it the same way; the note filter looked the stripped name up and missed, so the container
## name itself reached the note. Its grant (Caster) is what the table runs.
func test_an_item_container_name_with_a_trailing_space_gets_no_manual_note() -> void:
	_main._solo_log_unmodeled_rules(_unit("gf", "war_disciples", ["Hero", "Psy-Witch ", "Caster(2)"], {"Psy-Witch ": ["Caster(2)"]}))
	_main._solo_log_unmodeled_rules(_unit("aof", "plague_disciples", ["Hero", "Sorcerer ", "Caster(2)"], {"Sorcerer ": ["Caster(2)"]}))
	assert_array(_noted_rules()) \
		.override_failure_message("an item container name reached the manual note: %s" % [_noted_rules()]) \
		.is_empty()


## The control: the check can still fail. A name no map ever carries must keep its note (F2's Precision Charge got
## its rows in the follow-up, so the control uses an invented name that can never be mapped).
func test_a_rule_without_a_row_still_gets_the_manual_note() -> void:
	_main._solo_log_unmodeled_rules(_unit("gf", "orc_marauders", ["Unmapped Probe Rule"]))
	assert_array(_noted_rules()).is_equal(["Unmapped Probe Rule"])
