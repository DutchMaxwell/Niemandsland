extends GdUnitTestSuite
## MENU step 31 (spec of step 30): TableRevealGate names the hand-over's stages - Table, Battlemap, Terrain,
## Miniatures - from the table's own signals, feeds them to the menu's loading picture and reveals once.
## Stubs stand in for main, its table, its save manager and the model library. Red on main: no gate.

const GATE := "res://scripts/table_reveal_gate.gd"


class StubTable:
	extends Node
	signal table_resized(size_feet: Vector2)
	signal battlemap_settled(biome_name: String, applied: bool)
	var biome := "urban_ruins"


class StubSaves:
	extends Node
	signal load_completed(object_count: int)
	signal load_failed(error: String)
	signal _restore_unlocked


class StubModels:
	extends RefCounted
	signal caching_started(total: int)
	signal caching_finished


class StubArmies:
	extends RefCounted
	var model_library := StubModels.new()


class StubMain:
	extends Node
	var table := StubTable.new()
	var save_manager := StubSaves.new()
	var opr_army_manager := StubArmies.new()
	var toasts: Array[String] = []

	func _show_toast(text: String) -> void:
		toasts.append(text)


var _main: StubMain
var _reveals: Array = []
var _stages: Array = []


func before_test() -> void:
	_main = StubMain.new()
	_main.add_child(_main.table)
	_main.add_child(_main.save_manager)
	add_child(_main)
	_reveals.clear()
	_stages.clear()


func after_test() -> void:
	_main.queue_free()


func _start(mode: String) -> Node:
	(
		assert_bool(ResourceLoader.exists(GATE))
		. override_failure_message("no TableRevealGate")
		. is_true()
	)
	if not ResourceLoader.exists(GATE):
		return null
	var gate: Node = load(GATE).start(_main, mode)
	gate.revealed.connect(func(by_cap: bool) -> void: _reveals.append(by_cap))
	gate.stage_changed.connect(func(stage: String, _ratio: float) -> void: _stages.append(stage))
	return gate


func test_a_new_table_waits_for_its_size_and_its_battlemap() -> void:
	var gate := _start("new")
	if gate == null:
		return
	_main.table.battlemap_settled.emit("arid_desert", true)  # another biome's map: not this table's
	_main.table.table_resized.emit(Vector2(6, 4))
	assert_array(_stages).is_equal(["Battlemap", "Battlemap", "Battlemap"])  # Table, Terrain, Miniatures done
	assert_array(_reveals).is_empty()
	_main.table.battlemap_settled.emit("urban_ruins", false)  # none comes: the bundled surface is final
	_main.table.battlemap_settled.emit("urban_ruins", true)
	assert_array(_reveals).is_equal([false])


func test_a_load_waits_for_the_save_and_its_models() -> void:
	var gate := _start("load")
	if gate == null:
		return
	_main.opr_army_manager.model_library.caching_started.emit(12)
	_main.table.battlemap_settled.emit("urban_ruins", true)
	_main.save_manager.load_completed.emit(30)
	(
		assert_array(_reveals)
		. override_failure_message("revealed while the models still cache")
		. is_empty()
	)
	assert_str(str(_stages.back())).is_equal("Miniatures")
	_main.opr_army_manager.model_library.caching_finished.emit()
	assert_array(_reveals).is_equal([false])


func test_a_join_waits_for_the_host_and_names_that_wait() -> void:
	var overlay := LoadingOverlay.new()
	overlay.add_to_group("transition_overlay")
	add_child(overlay)
	await get_tree().process_frame
	var gate := _start("join")
	if gate == null:
		overlay.queue_free()
		return
	assert_str(overlay._stage.text).is_equal("WAITING FOR THE HOST")
	_main.save_manager._restore_unlocked.emit()
	assert_str(overlay._stage.text).is_equal("BATTLEMAP")
	overlay.queue_free()


func test_the_cap_reveals_once_and_a_late_signal_changes_nothing() -> void:
	var gate := _start("new")
	if gate == null:
		return
	gate._reveal(true)  # what the CAP_S timer does
	_main.table.table_resized.emit(Vector2(6, 4))
	_main.table.battlemap_settled.emit("urban_ruins", true)
	assert_array(_reveals).is_equal([true])
	assert_float(load(GATE).CAP_S).is_equal(20.0)


## MENU step 32 (lead, 26.11.): a join whose host never answers opens at the cap with one line of notice.
func test_a_join_past_the_cap_opens_with_one_line_of_notice() -> void:
	var gate := _start("join")
	if gate == null:
		return
	gate._reveal(true)
	assert_array(_main.toasts).is_equal([gate.HOST_LATE])
