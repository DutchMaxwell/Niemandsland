extends GdUnitTestSuite
## PLAN_GAME_SYSTEM_SWITCH step 1: GameSystem is the one table-level list of game systems. Its ids must equal
## RulesRegistry.SYSTEMS and the core's rules.rs SYSTEMS, and its board defaults must equal the core's
## `Book.default_board_in` (read from the Rust source as text), so the setup screen can never preselect a board
## the core's book disagrees with. Red proof: change BOOK_AOFS's board (or drop one id) in rules.rs / game_system.gd.

const RULES_RS := "res://core/nml-core/src/rules.rs"


func _rust() -> String:
	var src := FileAccess.get_file_as_string(RULES_RS)
	assert_str(src).override_failure_message("%s is unreadable" % RULES_RS).is_not_empty()
	return src


## The ids of `pub const SYSTEMS: [&str; N] = [...]` in rules.rs, in order.
func _rust_ids() -> Array:
	var re := RegEx.new()
	assert_int(re.compile("pub const SYSTEMS: \\[&str; \\d+\\] = \\[([^\\]]*)\\]")).is_equal(OK)
	var m := re.search(_rust())
	assert_object(m).override_failure_message("SYSTEMS not found in rules.rs").is_not_null()
	var out: Array = []
	for part in m.get_string(1).split(","):
		var id := part.strip_edges().trim_prefix("\"").trim_suffix("\"")
		if not id.is_empty():
			out.append(id)
	return out


## system id -> default_board_in as Vector2 (inches), from every `Book { system: "x", ... default_board_in: [w, d] }`.
func _rust_boards() -> Dictionary:
	var re := RegEx.new()
	assert_int(re.compile("system: \"(\\w+)\",[^}]*?default_board_in: \\[([\\d.]+), ([\\d.]+)\\]")).is_equal(OK)
	var out := {}
	for m in re.search_all(_rust()):
		out[m.get_string(1)] = Vector2(float(m.get_string(2)), float(m.get_string(3)))
	return out


func test_ids_equal_the_registry_and_the_core() -> void:
	assert_array(GameSystem.IDS).is_equal(RulesRegistry.SYSTEMS)
	assert_array(GameSystem.IDS).is_equal(_rust_ids())
	assert_str(GameSystem.DEFAULT_ID).is_equal(RulesRegistry.DEFAULT_SYSTEM)


func test_board_defaults_equal_the_core_books() -> void:
	var boards := _rust_boards()
	assert_int(boards.size()).override_failure_message("rules.rs must hold one Book per system").is_equal(GameSystem.IDS.size())
	for id in GameSystem.IDS:
		assert_bool(boards.has(id)).override_failure_message("rules.rs has no Book for %s" % id).is_true()
		var feet := GameSystem.default_board_feet(id)
		assert_vector(Vector2(feet.x * 12, feet.y * 12)).override_failure_message(
			"%s: GameSystem.default_board_feet %s != rules.rs default_board_in %s" % [id, feet, boards.get(id)]
		).is_equal(boards.get(id, Vector2.ZERO))


func test_scale_follows_the_board() -> void:
	# Skirmish scale = the 4 x 4 ft books, battle scale = the 6 x 4 ft books (PLAN_GAME_SYSTEM_SWITCH Goal).
	for id in GameSystem.IDS:
		var square := GameSystem.default_board_feet(id) == Vector2i(4, 4)
		assert_str(GameSystem.scale(id)).is_equal(GameSystem.SCALE_SKIRMISH if square else GameSystem.SCALE_BATTLE)


func test_setting_labels_and_scale_per_system() -> void:
	var expected := {
		"gf": ["Grimdark Future", "grimdark", "battle"],
		"gff": ["Grimdark Future: Firefight", "grimdark", "skirmish"],
		"aof": ["Age of Fantasy", "fantasy", "battle"],
		"aofs": ["Age of Fantasy: Skirmish", "fantasy", "skirmish"],
		"aofr": ["Age of Fantasy: Regiments", "fantasy", "battle"],
	}
	assert_int(expected.size()).is_equal(GameSystem.IDS.size())
	for id in GameSystem.IDS:
		assert_str(GameSystem.label(id)).is_equal(expected[id][0])
		assert_str(GameSystem.setting(id)).is_equal(expected[id][1])
		assert_str(GameSystem.scale(id)).is_equal(expected[id][2])


func test_normalize_and_is_known() -> void:
	assert_str(GameSystem.normalize(" AOFS ")).is_equal("aofs")
	assert_str(GameSystem.normalize("")).is_equal("gf")
	assert_bool(GameSystem.is_known("gff")).is_true()
	assert_bool(GameSystem.is_known(" Aof ")).is_true()
	assert_bool(GameSystem.is_known("")).is_false()
	assert_bool(GameSystem.is_known("fantasy")).is_false()
	# An unknown id folds to the default everywhere (label, setting, board) instead of crashing a lookup.
	assert_str(GameSystem.label("nonsense")).is_equal("Grimdark Future")
	assert_vector(Vector2(GameSystem.default_board_feet("nonsense"))).is_equal(Vector2(6, 4))
