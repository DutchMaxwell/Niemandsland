extends GdUnitTestSuite
## E2E — the solo "apply it manually" notes must not send a player to do by hand what the table
## already does (release week 25.09.2026, docpass report section 8).
##
## Driven on the real main.tscn: the real _solo_log_unmodeled_rules (the once-per-rule note) and the
## real _solo_modeled_rules_for (the list both the note and the handoff inventory read).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const NOTE_TAIL := "is not automated in solo — apply it manually"

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


# === Fix 1: the modeled list is the registry, not a lagging hand export ===

## Brutal (Surge), Courageous (Banner) and Vicious (Bane) resolve on the table through their
## primitives, but were missing from the committed GF `modeled` list — so the game told the player
## to apply them manually.
func test_registry_resolved_gf_rules_get_no_manual_note() -> void:
	var carriers := {"orc_marauders": "Brutal", "alien_hives": "Courageous", "jackals": "Vicious"}
	for faction in carriers:
		var rule_name := str(carriers[faction])
		assert_bool(RulesRegistry.has_primitive("gf", str(faction), rule_name)) \
			.override_failure_message("fixture drift: %s no longer has a primitive in gf/%s" % [rule_name, faction]) \
			.is_true()
		_main._solo_log_unmodeled_rules(_unit("gf", str(faction), [rule_name]))
	assert_array(_noted_rules()) \
		.override_failure_message("the table resolves these rules, yet the log says 'apply manually': %s" % [_noted_rules()]) \
		.is_empty()


## One map section (of a faction, or the common one for faction ""): every name the registry gives a
## primitive there that the modeled list of such a unit lacks.
func _collect_unmodeled(system: String, faction: String, section: Dictionary, missing: Array) -> void:
	var modeled: Array = _main._solo_modeled_rules_for(_unit(system, faction, []))
	for rule_name in section:
		if RulesRegistry.has_primitive(system, faction, str(rule_name)) and not modeled.has(rule_name):
			missing.append("%s/%s: %s" % [system, faction, rule_name])


## The invariant, for every system map: every rule name the registry gives a primitive (for the
## faction of the unit or the common section of its system) is in the list the note reads.
func test_modeled_list_covers_every_registry_name_with_a_primitive() -> void:
	var missing: Array = []
	for system in RulesRegistry.SYSTEMS:
		var m: Dictionary = RulesRegistry.map_for(str(system))
		_collect_unmodeled(str(system), "", m.get("common", {}), missing)
		var factions: Dictionary = m.get("factions", {})
		for faction in factions:
			_collect_unmodeled(str(system), str(faction), factions[faction], missing)
	assert_array(missing) \
		.override_failure_message("%d registry names with a primitive are not in the modeled list, e.g. %s" % [
			missing.size(), missing.slice(0, 12)]) \
		.is_empty()


# === Fix 2: an Army Forge ITEM is not a rule ===

## The Guardians of the bundled tutorial board carry the item "Jetpacks (Ambush, Flying, Swift)": the
## import keeps the item NAME in special_rules next to the rules it grants, and maps it in
## unit_properties.item_grants. The note said "Jetpacks is not automated" although all three
## granted rules resolve.
func test_item_name_jetpacks_gets_no_manual_note() -> void:
	var board: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/tutorial/tutorial_board.nml"))
	var props: Dictionary = {}
	for gu in (board as Dictionary)["game_units"]:
		var p: Dictionary = (gu as Dictionary).get("unit_properties", {})
		if (p.get("item_grants", {}) as Dictionary).has("Jetpacks"):
			props = p
	assert_bool(props.is_empty()).override_failure_message("fixture drift: no Jetpacks unit on the tutorial board").is_false()
	assert_array(props["special_rules"]).contains(["Jetpacks"])
	var u := GameUnit.new()
	u.unit_properties = props.duplicate(true)
	_main._solo_log_unmodeled_rules(u)
	assert_array(_noted_rules()) \
		.override_failure_message("an item name reached the manual note: %s" % [_noted_rules()]) \
		.not_contains(["Jetpacks"])


## The item is replaced by what it grants: a granted rule the table does NOT resolve is still named —
## by its own name, never by the item container.
func test_an_item_surfaces_its_unresolved_granted_rule_not_its_name() -> void:
	_main._solo_log_unmodeled_rules(_unit("gf", "robot_legions", ["Made-Up Kit"], {"Made-Up Kit": ["Made-Up Rule"]}))
	assert_array(_noted_rules()).contains(["Made-Up Rule"])
	assert_array(_noted_rules()).not_contains(["Made-Up Kit"])
