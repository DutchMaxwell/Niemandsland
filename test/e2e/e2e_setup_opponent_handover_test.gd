extends GdUnitTestSuite
## Step 04 of the setup, "Who is at the table?", at the table: the opponent the setup chose travels as
## niemandsland/pending_table_opponent and the reveal gate loads NACHTMAHR's list into its seat. The list is a
## fixture written into the user cache (no bundle, no network); the book and the shared rules are seeded, so the
## parse never asks the API. Red before the step: the table opened empty.

const Boot := preload("res://test/e2e/e2e_boot.gd")
const SETUP_KEY := "niemandsland/pending_table_setup"
const OPPONENT_KEY := "niemandsland/pending_table_opponent"
const HARNESS_KEY := "niemandsland/harness_mode"
const FIXTURE := "res://test/fixtures/setup_opponent/probe_list.json"
const FILE := "_e2e_setup_opponent_probe.json"
const CACHE := "user://ai_lists_cache_v36"
const MAX_FRAMES := 900

var _roots: Array
var _prev: Dictionary = {}


func before_test() -> void:
	for key: String in [SETUP_KEY, OPPONENT_KEY, HARNESS_KEY]:
		_prev[key] = ProjectSettings.get_setting(key, null)
	ProjectSettings.set_setting(HARNESS_KEY, false)
	ProjectSettings.set_setting(SETUP_KEY, {"size": Vector2(6, 4), "biome": "urban_ruins", "system": "gf"})
	DirAccess.make_dir_recursive_absolute(CACHE)
	FileAccess.open("%s/%s" % [CACHE, FILE], FileAccess.WRITE).store_string(FileAccess.get_file_as_string(FIXTURE))
	_roots = Boot.root_children(get_tree())


func after_test() -> void:
	CoreActivation.offer_override = -1
	for key: String in _prev:
		ProjectSettings.set_setting(key, _prev[key])
	DirAccess.remove_absolute("%s/%s" % [CACHE, FILE])
	PendingOpponent.who = "local"
	PendingOpponent.label = ""
	Boot.free_stray_root_nodes(get_tree(), _roots)


## Boots the main scene and waits for the reveal (the UI shows) and then for `until` (or MAX_FRAMES).
func _boot(until: Callable = Callable()) -> Node:
	var runner := scene_runner(Boot.MAIN_SCENE)
	var main: Node = runner.scene()
	main.opr_army_manager.api_client._common_rules_cache[2] = {"rules": [], "traits": []}   # 2 = gf: no API call
	var frames := 0
	while frames < MAX_FRAMES and (not main.get_node("UI").visible or (until.is_valid() and not until.call(main))):
		await runner.simulate_frames(10, 100)
		frames += 10
	return main


func _off_lines(main: Node) -> int:
	var n := 0
	for e in main.battle_log.entries():
		if str((e as Dictionary)["text"]) == CoreLoadNotice.ENGINE_OFF_LINE:
			n += 1
	return n


func test_solo_puts_nachtmahrs_list_into_its_seat() -> void:
	PendingOpponent.store({"who": "solo", "file": FILE, "slot": 2, "label": "NACHTMAHR · Probe · 100"})
	var main := await _boot(func(m: Node) -> bool: return m.opr_army_manager.armies.has(2))
	assert_bool(main.opr_army_manager.armies.has(2)).override_failure_message("no army in seat 2").is_true()
	assert_bool(main.solo_ai_slots.has(2)).override_failure_message("seat 2 is not NACHTMAHR's").is_true()
	assert_object(ProjectSettings.get_setting(OPPONENT_KEY, null)).override_failure_message("not cleared").is_null()
	assert_str(PendingOpponent.who).is_equal("solo")
	assert_str(PendingOpponent.label).is_equal("NACHTMAHR · Probe · 100")


func test_two_players_load_no_army() -> void:
	PendingOpponent.store({"who": "local", "label": "Two players, one screen"})
	var main := await _boot()
	await get_tree().process_frame
	assert_bool(main.opr_army_manager.armies.is_empty()).is_true()
	assert_bool(main.solo_ai_slots.is_empty()).is_true()
	assert_str(PendingOpponent.who).is_equal("local")
	assert_object(ProjectSettings.get_setting(OPPONENT_KEY, null)).is_null()


## Moved here from e2e_core_mandatory_test (the AI Opponent dialog's refusal): without the core no list is
## loaded and the core's own line is logged once.
func test_without_the_core_nachtmahr_stays_out() -> void:
	CoreActivation.offer_override = 0
	PendingOpponent.store({"who": "solo", "file": FILE, "slot": 2, "label": "NACHTMAHR · Probe · 100"})
	var main := await _boot()
	assert_bool(main.opr_army_manager.armies.is_empty()).is_true()
	assert_bool(main.solo_ai_slots.is_empty()).is_true()
	assert_int(_off_lines(main)).is_equal(1)


## The harness skips the gate: a stored choice loads nothing there.
func test_a_harness_boot_loads_no_stored_opponent() -> void:
	ProjectSettings.set_setting(HARNESS_KEY, true)
	PendingOpponent.store({"who": "solo", "file": FILE, "slot": 2, "label": "NACHTMAHR · Probe · 100"})
	var main := await _boot()
	await get_tree().process_frame
	assert_bool(main.opr_army_manager.armies.is_empty()).is_true()
	PendingOpponent.store({})
