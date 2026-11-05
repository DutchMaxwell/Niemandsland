extends GdUnitTestSuite
## AI-G2 R1 (0.3.15): the arena wrote no Vanguard placement line. The free placement is real (the AI
## repositions the carrier and leaves a note naming the BOOK rule), but only the human-vs-AI deployment FSM
## drains those notes into the battle log. The arena drives no FSM, so 352 arena logs held 0 Vanguard /
## Drakesworn / Fanatic lines. From EPOCH_73_V36 the arena's start-of-play lines drain the notes too; below
## 73 the arena log stays byte-identical.
##
## Live path: a real book carrier is deployed by the production deployment (`deploy_army`) on the real
## solo controller of the real main scene, so the note comes from the placement code, not from a hand-set
## array; the arena's own seam (`ArenaMatch.log_deployment_notes`) then writes the log.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ArenaMatch := preload("res://tools/arena_match.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch_before: int


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch
	RulesRegistry.reset_cache()
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main._solo_batch = true


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	RulesRegistry.reset_cache()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## Deploy ONE carrier of the given book rule with an objective behind its zone (so the free placement
## really moves it); returns nothing, the notes sit in the solo controller as in a real arena game.
func _deploy_carrier(system: String, book: String, rule: String, unit_name: String) -> void:
	var u := E2EBoot.make_unit(_main, 2, unit_name, [Vector3(0, 0, 0.5)])
	u.unit_properties["game_system"] = system
	u.unit_properties["faction_folder"] = book
	u.unit_properties["special_rules"] = [rule]
	_main.opr_army_manager.game_units[u.unit_id] = u
	var no_block := func(_p: Vector2) -> bool: return false
	var zone := Rect2(Vector2(-0.15, 0.3), Vector2(0.30, 0.3))
	_main.solo_controller.deploy_army(zone, [Vector2(0.0, 0.66)], no_block, no_block, 7)


func test_the_arena_names_the_vanguard_placement_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	_deploy_carrier("gf", "dark_elf_raiders", "Vanguard", "Horse Marksmen")
	assert_int(_main.solo_controller.vanguard_notes.size()).override_failure_message(
		"fixture: the production deployment must have left ONE free-placement note").is_equal(1)
	ArenaMatch.log_deployment_notes(_main)
	assert_str(_log_text()).override_failure_message(
		"the arena repositioned a Vanguard carrier and wrote NO log line for it").contains(
		"Vanguard: Horse Marksmen takes its free 9\" placement after deploying")
	assert_int(_main.solo_controller.vanguard_notes.size()).override_failure_message(
		"the notes must be drained, not logged twice").is_equal(0)


func test_the_arena_names_the_book_entry_not_the_primitive_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	_deploy_carrier("aof", "volcanic_dwarves", "Drakesworn", "Drakes")
	ArenaMatch.log_deployment_notes(_main)
	assert_str(_log_text()).override_failure_message(
		"the arena repositioned a Drakesworn carrier and wrote NO log line naming the book rule").contains(
		"Drakesworn: Drakes takes its free 9\" placement after deploying")


func test_the_arena_log_is_unchanged_below_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	_deploy_carrier("gf", "dark_elf_raiders", "Vanguard", "Horse Marksmen")
	ArenaMatch.log_deployment_notes(_main)
	assert_str(_log_text()).override_failure_message(
		"below EPOCH_73_V36 the arena log must stay byte-identical (no Vanguard line)").not_contains("free 9")
