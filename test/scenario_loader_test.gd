extends GdUnitTestSuite
## Tests for the Game School scenario loader (ScenarioLoader) — the capture -> load -> restore
## component that keeps a lesson isolated from the player's own table.
##
## TWO layers:
##  1. Orchestration (lightweight fakes): begin_lesson captures + pauses autosave, load_scenario
##     routes through save_manager.load_game (and refuses an unbundled path without touching the
##     table), end_lesson restores the captured snapshot + resumes autosave.
##  2. The real STATE ROUND-TRIP (the adversarial isolation invariant): with a real SaveManager over a
##     mock table, capture the player's layout -> mutate the table as a "scenario load" would ->
##     restore, and assert the re-serialized state is byte-identical to the captured one. The save
##     serializer itself is the equality oracle (both sides are its output, so types always match).

const Loader := preload("res://scripts/scenario_loader.gd")
## A real bundled save that exists on disk — so load_scenario's file_exists guard passes and the fake
## save_manager's load_game records the path (we assert the routing, not a real parse).
const REAL_BUNDLED := "res://assets/tutorial/scenarios/s01_werkzeug_grundlagen.nml"


# ============================================================================
# Lightweight fakes (duck-typed via has_method, exactly how the loader calls them)
# ============================================================================

class _FakeSaveManager extends Node:
	var captured_marker := {"marker": "player-table", "n": 42}
	var loaded_path := ""
	var restored_state := {}
	var load_return: Error = OK

	func serialize_game_state() -> Dictionary:
		return captured_marker.duplicate(true)

	func load_game(path: String) -> Error:
		loaded_path = path
		return load_return

	func restore_state(state: Dictionary) -> Error:
		restored_state = state.duplicate(true)
		return OK


class _FakeAutosave extends Node:
	var paused: bool = false
	var pause_calls: int = 0

	func set_lesson_paused(value: bool) -> void:
		paused = value
		pause_calls += 1


# ============================================================================
# 1. Orchestration
# ============================================================================

func test_begin_lesson_captures_the_table_and_pauses_autosave() -> void:
	var sm: _FakeSaveManager = auto_free(_FakeSaveManager.new())
	var av: _FakeAutosave = auto_free(_FakeAutosave.new())
	var loader := Loader.new()
	loader.setup(sm, av)

	loader.begin_lesson()

	assert_bool(loader.has_snapshot()).is_true()
	assert_dict(loader.snapshot()).is_equal(sm.captured_marker)
	assert_bool(av.paused).is_true()


func test_load_scenario_routes_through_the_real_load_game() -> void:
	var sm: _FakeSaveManager = auto_free(_FakeSaveManager.new())
	var loader := Loader.new()
	loader.setup(sm)

	var err: Error = await loader.load_scenario(REAL_BUNDLED)

	assert_int(err).is_equal(OK)
	assert_str(sm.loaded_path).is_equal(REAL_BUNDLED)


func test_load_scenario_refuses_an_unbundled_path_without_touching_the_table() -> void:
	var sm: _FakeSaveManager = auto_free(_FakeSaveManager.new())
	var loader := Loader.new()
	loader.setup(sm)

	var err: Error = await loader.load_scenario("res://assets/tutorial/scenarios/does_not_exist.nml")

	assert_int(err).is_equal(ERR_FILE_NOT_FOUND)
	# load_game was NEVER called — a "scenario coming soon" chapter can't wipe the board.
	assert_str(sm.loaded_path).is_equal("")


func test_end_lesson_restores_the_captured_snapshot_and_resumes_autosave() -> void:
	var sm: _FakeSaveManager = auto_free(_FakeSaveManager.new())
	var av: _FakeAutosave = auto_free(_FakeAutosave.new())
	var loader := Loader.new()
	loader.setup(sm, av)

	loader.begin_lesson()
	var err: Error = await loader.end_lesson()

	assert_int(err).is_equal(OK)
	# The EXACT captured snapshot was fed back to restore_state.
	assert_dict(sm.restored_state).is_equal(sm.captured_marker)
	assert_bool(av.paused).is_false()
	assert_bool(loader.has_snapshot()).is_false()


func test_end_lesson_without_a_capture_is_a_safe_no_op() -> void:
	var sm: _FakeSaveManager = auto_free(_FakeSaveManager.new())
	var av: _FakeAutosave = auto_free(_FakeAutosave.new())
	var loader := Loader.new()
	loader.setup(sm, av)

	# Abort path: end without begin. No restore, but autosave is still un-paused defensively.
	var err: Error = await loader.end_lesson()

	assert_int(err).is_equal(OK)
	assert_dict(sm.restored_state).is_empty()
	assert_bool(av.paused).is_false()


# ============================================================================
# 2. Real state round-trip — capture -> mutate -> restore == captured (byte-identical)
# ============================================================================

func test_lesson_round_trip_restores_the_players_table_exactly() -> void:
	var sm := _real_save_manager()

	# The PLAYER's table (layout A).
	sm.map_layout_editor.grid_cells = {Vector2i(5, 5): 1, Vector2i(7, 7): 2}
	sm.map_layout_editor.grid_rotation_degrees = 15.0
	sm.map_layout_editor.deployment_type = 1
	sm.table.table_size = Vector2(6, 4)
	sm.table.biome = "temperate_grassland"

	var before := sm.serialize_game_state()

	var loader := Loader.new()
	loader.setup(sm, null, null)
	loader.begin_lesson()   # capture the player's table (layout A)

	# A "scenario load" replaces the table with a DIFFERENT layout (layout B).
	sm.map_layout_editor.grid_cells = {Vector2i(1, 1): 3}
	sm.map_layout_editor.grid_rotation_degrees = 40.0
	sm.map_layout_editor.deployment_type = 0
	sm.table.table_size = Vector2(4, 4)
	sm.table.biome = "arid_desert"

	# End the lesson -> restore layout A through the REAL load path (temp file -> load_game).
	var err: Error = await loader.end_lesson()
	assert_int(err).is_equal(OK)

	var after := sm.serialize_game_state()

	# The save-relevant state is byte-identical (serializer output == serializer output). saved_at is
	# a wall-clock stamp, not table state, so it is neutralised on both sides.
	assert_dict(_strip(after)).is_equal(_strip(before))
	# And it really is layout A again, not the lesson's layout B.
	assert_that(after["table"]["grid_cells"]).is_equal({"5,5": 1, "7,7": 2})
	assert_str(after["table"]["biome"]).is_equal("temperate_grassland")

	_free_real_save_manager(sm)


## The FILE hop alone: save_state_to_file -> parse -> SaveMigrations.migrate preserves the state, so a
## restore feeds the deserializers exactly what a normal save-load would.
func test_save_state_to_file_survives_json_and_the_migration_chain() -> void:
	var sm := SaveManager.new()
	add_child(sm)
	var state := {
		"version": SaveManager.SAVE_VERSION,
		"saved_at": "whenever",
		"table": {"size_feet": [6, 4], "biome": "temperate_grassland", "grid_cells": {"5,5": 1}},
		"objects": [],
		"game_units": [],
		"game_state": {"current_round": 3, "game_phase": 1, "current_player": 1, "token_library": {}},
		"object_counter": 7,
		"army_names": {},
	}
	var path := "user://test_scenario_filehop.nml"
	assert_int(sm.save_state_to_file(state, path)).is_equal(OK)

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var mig: Dictionary = SaveMigrations.migrate(parsed)
	assert_bool(bool(mig["ok"])).is_true()
	var restored: Dictionary = mig["state"]

	assert_str(str(restored["version"])).is_equal(SaveManager.SAVE_VERSION)
	assert_int(int(restored["object_counter"])).is_equal(7)
	assert_str(str(restored["table"]["biome"])).is_equal("temperate_grassland")
	assert_int(int(restored["game_state"]["current_round"])).is_equal(3)
	# All save-relevant top-level keys survive the hop.
	for key in ["version", "table", "objects", "game_units", "game_state", "object_counter"]:
		assert_bool(restored.has(key)) \
			.override_failure_message("key '%s' lost in the file/JSON/migration round-trip" % key).is_true()

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	sm.queue_free()


# ============================================================================
# Helpers
# ============================================================================

## A drop-of-volatile-fields view so the equality oracle compares TABLE STATE, not the wall clock.
func _strip(state: Dictionary) -> Dictionary:
	var out := state.duplicate(true)
	out.erase("saved_at")
	return out


## A real SaveManager wired to a mock table + mock map-layout editor (no object/army managers needed:
## an empty-objects, empty-units state exercises the full table serialize/deserialize round-trip).
func _real_save_manager() -> SaveManager:
	var sm := SaveManager.new()
	add_child(sm)

	var table_script := GDScript.new()
	table_script.source_code = "extends Node3D\n" \
		+ "var table_size := Vector2(6, 4)\n" \
		+ "var biome := \"temperate_grassland\"\n" \
		+ "func setup_table(s: Vector2) -> void: table_size = s\n" \
		+ "func set_biome(b: String) -> void: biome = b\n"
	table_script.reload()
	var table := Node3D.new()
	table.set_script(table_script)
	add_child(table)
	sm.table = table

	var editor_script := GDScript.new()
	editor_script.source_code = "extends Control\n" \
		+ "var grid_cells = {}\n" \
		+ "var grid_rotation_degrees := 0.0\n" \
		+ "var deployment_type := 0\n" \
		+ "var table_size_feet := Vector2(6, 4)\n" \
		+ "var custom_zone_vertices_p1: Array[Vector2] = []\n" \
		+ "var custom_zone_vertices_p2: Array[Vector2] = []\n" \
		+ "var mission_objectives: Array[Vector2] = []\n" \
		+ "var wall_segments: Array[Dictionary] = []\n" \
		+ "var placed_objects: Array[Dictionary] = []\n"
	editor_script.reload()
	var editor := Control.new()
	editor.set_script(editor_script)
	add_child(editor)
	sm.map_layout_editor = editor

	return sm


func _free_real_save_manager(sm: SaveManager) -> void:
	if is_instance_valid(sm.table):
		sm.table.queue_free()
	if is_instance_valid(sm.map_layout_editor):
		sm.map_layout_editor.queue_free()
	sm.queue_free()
