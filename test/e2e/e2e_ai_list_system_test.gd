extends GdUnitTestSuite
## PLAN_GAME_SYSTEM_SWITCH step 8: the AI Opponent dialog offers only the lists of the table's EXACT game system. Before, it
## folded every system onto two families (gff -> gf, aofs / aofr -> aof): a Firefight table was offered battle-size lists.
## Real scenes/main.tscn, a fake manifest and a recorder loader (no CDN, no import).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const MANIFEST := {
	"grim_clan": {"name": "Grim Clan", "system": "gf", "lists": [{"points": 1000, "file": "grim_1000.json"}]},
	"old_guard": {"name": "Old Guard", "lists": [{"points": 750, "file": "old_750.json"}]},   # no "system": a gf list
	"elf_court": {"name": "Elf Court", "system": "aof", "lists": [{"points": 1000, "file": "elf_1000.json"}]},
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


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)


## The faction option texts of the open dialog, or null when no dialog is open.
func _factions() -> Variant:
	for c in _main.get_children():
		if c is CanvasLayer and c.name == "AiOpponentLayer" and not c.is_queued_for_deletion():
			var opt := c.find_children("*", "OptionButton", true, false)[0] as OptionButton
			var out: Array = []
			for i in opt.item_count:
				out.append(opt.get_item_text(i))
			return out
	return null


func _open_for(system: String) -> Variant:
	_main.opr_army_manager.table_system = system
	_main._show_ai_opponent_dialog(MANIFEST, func(_f: String, _s: int) -> void: pass)
	await _runner.simulate_frames(2)
	return _factions()


func test_a_firefight_table_is_offered_no_battle_size_list() -> void:
	assert_object(await _open_for("gff")).override_failure_message("a gff table was offered the gf / aof lists").is_null()


func test_aofs_and_aofr_tables_get_no_aof_list_either() -> void:
	assert_object(await _open_for("aofs")).override_failure_message("aofs was offered aof lists").is_null()
	assert_object(await _open_for("aofr")).override_failure_message("aofr was offered aof lists").is_null()


func test_gf_and_aof_tables_keep_their_own_lists() -> void:
	assert_array(await _open_for("gf")).is_equal(["Grim Clan", "Old Guard"])   # sorted by key; the entry without a system is gf
	_main.get_children().filter(func(c: Node) -> bool: return c.name == "AiOpponentLayer").map(func(c: Node) -> void: c.queue_free())
	await _runner.simulate_frames(2)
	assert_array(await _open_for("aof")).is_equal(["Elf Court"])


func test_a_table_with_no_system_is_offered_every_list_with_its_system() -> void:
	assert_array(await _open_for("")).is_equal(["Elf Court (AoF)", "Grim Clan (GF)", "Old Guard (GF)"])
