extends GdUnitTestSuite
## Feature test FT-29: the setup offers skirmish opponents. Step 04 of the table setup ("Who is at the table?") reads
## NACHTMAHR's list index for the game system picked in step 01, and the table loads the chosen list into its seat.
## The index is a fixture copy of entries of the live v36 manifest (test/fixtures/setup_opponent/ai_manifest_v36.json:
## gf / aof / gff / aofs entries, names and brackets only); the list itself is the own-stats Firefight fixture written
## into the AI-list user cache under the chosen file name. Nothing here reaches the CDN.
## - gff: the Solo card's faction dropdown offers exactly Orc Marauders and Robot Legions, each at 400 / 800, no gf
##   list; picking the first faction at 400 hands the table `gff_orc_marauders_400.json` for seat 2;
## - aofs: Goblins and Havoc Dwarves at 300 / 600, no aof list;
## - the table (system gff, 4 x 4 ft) loads that list into seat 2, NACHTMAHR's, and its units carry game_system gff.
## Real: SetupOpponent + SetupOpponentStep (the dropdowns and their signals), PendingOpponent, the main scene's reveal
## gate and its AI-list load through AiLists (bundle -> cache -> CDN; the cache answers).

const Boot := preload("res://test/e2e/e2e_boot.gd")
const MANIFEST := "res://test/fixtures/setup_opponent/ai_manifest_v36.json"
const LIST := "res://test/fixtures/card_list_gff_own_stats_400.json"
const FILE := "gff_orc_marauders_400.json"
const CACHE := "user://ai_lists_cache_v36"
const SETUP_KEY := "niemandsland/pending_table_setup"
const OPPONENT_KEY := "niemandsland/pending_table_opponent"
const HARNESS_KEY := "niemandsland/harness_mode"
const MAX_FRAMES := 900

var _prev: Dictionary = {}
var _roots: Array


func before_test() -> void:
	for key: String in [SETUP_KEY, OPPONENT_KEY, HARNESS_KEY]:
		_prev[key] = ProjectSettings.get_setting(key, null)
	_roots = Boot.root_children(get_tree())


func after_test() -> void:
	for key: String in _prev:
		ProjectSettings.set_setting(key, _prev[key])
	DirAccess.remove_absolute("%s/%s" % [CACHE, FILE])
	PendingOpponent.who = "local"
	PendingOpponent.label = ""
	Boot.free_stray_root_nodes(get_tree(), _roots)


func _step(system: String) -> Control:
	var opponent := SetupOpponent.new()
	opponent.set_system(system)
	opponent.set_manifest(JSON.parse_string(FileAccess.get_file_as_string(MANIFEST)))
	var step: Control = auto_free(SetupOpponentStep.new())
	step.size = Vector2(1920, 1080)
	add_child(step)
	step.setup(opponent, [GameSystem.label(system), "Urban ruins", "48 × 48 in", "Empty table"])
	return step


func _items(pick: OptionButton) -> Array:
	var out: Array = []
	for i in pick.item_count:
		out.append(pick.get_item_text(i))
	return out


## Per faction on offer (its manifest key: two systems may share a faction name) its name and the points it shows.
func _offer(step: Control) -> Dictionary:
	var faction: OptionButton = step.get("_faction")
	var points: OptionButton = step.get("_points")
	var out := {}
	for i in faction.item_count:
		faction.select(i)
		faction.item_selected.emit(i)
		out[str(faction.get_item_metadata(i))] = [faction.get_item_text(i)] + _items(points)
	return out


func test_a_firefight_table_offers_the_two_firefight_factions(timeout := 60000) -> void:
	var step := _step("gff")
	var offer := _offer(step)
	assert_dict(offer).override_failure_message("the gff offer: %s" % [offer]).is_equal(
		{"gff_orc_marauders": ["Orc Marauders", "400 points", "800 points"],
		"gff_robot_legions": ["Robot Legions", "400 points", "800 points"]})
	var faction: OptionButton = step.get("_faction")
	faction.select(0)
	faction.item_selected.emit(0)
	(step.get("_points") as OptionButton).item_selected.emit(0)
	var choice: Dictionary = (step.get("_opponent") as SetupOpponent).choice()
	assert_str(str(choice.get("file", ""))).is_equal(FILE)
	assert_int(int(choice.get("slot", 0))).is_equal(2)


func test_a_skirmish_table_offers_the_two_skirmish_factions(timeout := 60000) -> void:
	var offer := _offer(_step("aofs"))
	assert_dict(offer).override_failure_message("the aofs offer: %s" % [offer]).is_equal(
		{"aofs_goblins": ["Goblins", "300 points", "600 points"],
		"aofs_havoc_dwarves": ["Havoc Dwarves", "300 points", "600 points"]})


func test_the_table_loads_the_chosen_firefight_list_into_nachtmahrs_seat(timeout := 120000) -> void:
	DirAccess.make_dir_recursive_absolute(CACHE)
	FileAccess.open("%s/%s" % [CACHE, FILE], FileAccess.WRITE).store_string(FileAccess.get_file_as_string(LIST))
	ProjectSettings.set_setting(HARNESS_KEY, false)
	ProjectSettings.set_setting(SETUP_KEY, {"size": Vector2(4, 4), "biome": "urban_ruins", "system": "gff"})
	PendingOpponent.store({"who": "solo", "file": FILE, "slot": 2, "label": "NACHTMAHR · Orc Marauders · 400"})
	var runner := scene_runner(Boot.MAIN_SCENE)
	var main: Node = runner.scene()
	var client: Object = main.opr_army_manager.api_client
	client._common_rules_cache[3] = {"rules": [], "traits": []}   # 3 = gff: no API call
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LIST))
	client._army_books[str(data["units"][0]["armyId"])] = {}   # no army-book call either
	var frames := 0
	while frames < MAX_FRAMES and not main.opr_army_manager.armies.has(2):
		await runner.simulate_frames(10, 100)
		frames += 10
	assert_bool(main.opr_army_manager.armies.has(2)).override_failure_message("no army in seat 2").is_true()
	assert_bool(main.solo_ai_slots.has(2)).override_failure_message("seat 2 is not NACHTMAHR's").is_true()
	var units: Array = main.opr_army_manager.get_game_units_for_player(2)
	assert_int(units.size()).is_greater(0)
	for u in units:
		assert_str(str((u as GameUnit).unit_properties.get("game_system", ""))).override_failure_message("a gff unit").is_equal("gff")
