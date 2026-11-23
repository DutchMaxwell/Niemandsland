extends GdUnitTestSuite
## Exact rule names (NML-1112): the table's regeneration read (`_solo_has_regeneration` -> `_solo_is_regen_rule`) matched by PREFIX, so a unit that only carried the label
## "Regeneration Buff" (a Utility Buff that grants Regeneration to ANOTHER unit; gf dark_elf_raiders) rolled free regeneration dice when shot at: the planner's EV read and the
## core read the exact name and rolled none (found by the H-9a beat-target probe, ds/h_probe_beat_targets.md: 5 of 6 seeds differed). A bare prefix is another rule.
## RED: put `begins_with("Regeneration")` back into `_solo_is_regen_rule` -> the static cases and the volley case below fail.

const MainScript := preload("res://scripts/main.gd")
const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DICE := "user://regen_exact_name_dice"

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


## The name, or the name plus a parenthesised qualifier, is the rule; any other spelling that merely starts with it is not.
func test_only_the_exact_names_are_regeneration_rules() -> void:
	for yes in ["Regeneration", "Regeneration (spell)", "Medical Training", " Medical Training "]:
		assert_bool(MainScript._solo_is_regen_rule(yes)).override_failure_message("%s is a regeneration rule" % yes).is_true()
	for no in ["Regeneration Buff", "Regeneration Aura", "Regeneration when Shooting", "Medical Training Aura", "Medical Trainings"]:
		assert_bool(MainScript._solo_is_regen_rule(no)).override_failure_message("%s only starts like one: a rule of its own" % no).is_false()


func _unit_with(rule: String, faction: String) -> GameUnit:
	var gu := GameUnit.new()
	gu.unit_properties = {"player_id": 1, "name": "Squad", "quality": 4, "defense": 4, "special_rules": [rule], "game_system": "gf", "faction_folder": faction}
	var m := ModelInstance.new()
	m.is_alive = true
	gu.models.append(m)
	return gu


## The table's own answer: a bearer of the label is no regenerator, the plain rule is.
func test_the_table_gives_no_regeneration_to_a_label_carrier() -> void:
	assert_bool(_main._solo_has_regeneration(_unit_with("Regeneration Buff", "dark_elf_raiders"))).override_failure_message("Regeneration Buff gives the carrier nothing").is_false()
	assert_bool(_main._solo_has_regeneration(_unit_with("Regeneration", "battle_brothers"))).override_failure_message("a real Regeneration still rolls").is_true()
	assert_bool(_main._solo_has_regeneration(_unit_with("Medical Training", "battle_brothers"))).override_failure_message("Medical Training still rolls").is_true()
