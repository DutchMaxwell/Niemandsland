extends GdUnitTestSuite
## S1-15 — a Solo game keeps its mission through save and load, proven on the REAL scenes/main.tscn.
##
## THE DEFECT. The save carried neither main._solo_mission_id nor SoloController's six live mission
## statics (scoring, VP flavour, VP ledger, first-seize memo, marker metadata, destruction counter).
## A loaded game therefore kept whatever the session held before the load (in-game Load Game) or the
## class defaults (cold start + CONTINUE), and was scored by the default "end" rule — Sabotage,
## Demolition and the VP missions named the wrong winner.
##
## HOW THIS SUITE PROVES IT. Each scenario plays the SAME four round ends twice through the game's own
## functions: once straight through, once saved with SaveManager after round 1 and loaded again. The
## loaded game must book every later round and name the winner exactly like the game that never left
## the table. Rounds 1-3 book through main._solo_book_mission_vp (the seam BOTH round drivers call); the
## last round runs the real _solo_end_round, which books the final round and shows the game-over summary.
## Constructed: only the marker HOLDERS per round (who stands on which marker at that round end).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

const SAVE_PATH := "user://e2e_mission_save_reload.nml"
## main.gd SOLO_GAME_ROUNDS — the round whose end is the game's last.
const LAST_ROUND := 4
## Marker spots well inside the real 6x4 ft table; only their OWNERS carry meaning here.
const MARKER_POSITIONS := [Vector3(-0.3, 0.0, 0.3), Vector3(0.3, 0.0, -0.3)]
## What a save of version 1.7 written before S1-15 carried — the AC5 fixture keeps only these keys.
const ROOT_KEYS_1_7 := ["version", "saved_at", "table", "objects", "game_units", "game_state",
	"object_counter", "rule_descriptions", "player_spells", "army_names"]
const GAME_STATE_KEYS_1_7 := ["current_round", "game_phase", "current_player", "token_library", "rule_state"]
## The verdicts the human (P1) reads against NACHTMAHR (P2) — main._solo_show_game_summary.
const HUMAN_WINS := "You win — NACHTMAHR yields."
const NACHTMAHR_WINS := "NACHTMAHR claims the field."

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	SoloController.mission_reset("end", {})
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	SoloController.mission_reset("end", {})   # statics: never leak this game's mission into the next suite
	ProjectSettings.set_setting("niemandsland/pending_load_path", "")
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


# === Helpers ======================================================================================

## The mission contract state, JSON-normalised so 1 and 1.0 compare equal after a round trip.
func _mission_snapshot() -> Dictionary:
	return JSON.parse_string(JSON.stringify({
		"id": _main._solo_mission_id,
		"scoring": SoloController.mission_scoring,
		"flavour": SoloController.mission_vp_flavour,
		"vp": SoloController.mission_vp,
		"memo": SoloController.mission_vp_memo,
		"markers": SoloController.mission_markers,
		"destroy_seq": SoloController.mission_destroy_seq,
	}))


## A fresh process: no mission picked, every static at its declaration default.
func _no_mission_snapshot() -> Dictionary:
	return JSON.parse_string(JSON.stringify({"id": "", "scoring": "end", "flavour": {}, "vp": [0, 0],
		"memo": {}, "markers": [], "destroy_seq": [0]}))


func _start_mission(mission: String) -> void:
	_main._solo_mission_id = mission
	_main._solo_apply_mission_if_chosen()


## The round's marker holders on the table.
func _hold(owners: Array) -> void:
	_main.terrain_overlay.update_objectives(MARKER_POSITIONS.slice(0, owners.size()), owners)


## A non-final round end through the booking seam both round drivers call.
func _book_round(round_no: int, owners: Array) -> void:
	_main.opr_army_manager.current_round = round_no
	_hold(owners)
	_main._solo_book_mission_vp(false)


## The last round end through the real round driver: final booking + the game-over summary. Returns the
## verdict the player reads (the summary dialog is freed again, so a second game can show its own).
func _finish_game(owners: Array) -> String:
	_main._solo_both_ai = false
	_main.solo_ai_slots = {2: true}
	_main._solo_game_finished = false
	_main.opr_army_manager.current_round = LAST_ROUND
	_hold(owners)
	_main._solo_end_round()
	await get_tree().process_frame
	var verdict := "<no summary dialog>"
	for c in _main.get_children():
		if c is AcceptDialog and (c as AcceptDialog).title == "Game over":
			var text: String = (c as AcceptDialog).dialog_text
			verdict = text.substr(text.rfind("\n") + 1)
			_main.remove_child(c)
			c.free()
	return verdict


## Another game running in this session when the load happens: a different mission, with one round
## booked so its ledger, memo and markers are all off their defaults.
func _play_another_game(saved_mission: String) -> void:
	_start_mission("mosh_pit" if saved_mission == "demolition" else "demolition")
	_book_round(2, [2, 1])


## In-game Load Game (main._on_load_file_selected). Returns the contract state as it stood when
## load_completed fired.
func _load_in_game(path: String) -> Dictionary:
	var at_completion: Array = []
	_main.save_manager.load_completed.connect(
		func(_n: int) -> void: at_completion.append(_mission_snapshot()), CONNECT_ONE_SHOT)
	await _main._on_load_file_selected(path)
	assert_int(at_completion.size()).override_failure_message("load_completed never fired").is_equal(1)
	return at_completion[0] if not at_completion.is_empty() else {}


## Quit, start the game again, press CONTINUE. The startup menu only sets pending_load_path and changes
## scene; a FRESH Main loads that path deferred from its _ready. The old Main is freed first so the new
## one mounts at /root/Main again, and the statics go back to their declared defaults — a restarted
## process starts from those, while this test process would keep them for free.
func _cold_start_and_continue(path: String) -> Dictionary:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)   # the old Main is not in the snapshot
	SoloController.mission_reset("end", {})
	ProjectSettings.set_setting("niemandsland/pending_load_path", path)
	E2EBoot.arm_harness_mode()
	_main = (load(E2EBoot.MAIN_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child(_main)
	var at_completion: Array = []
	_main.save_manager.load_completed.connect(
		func(_n: int) -> void: at_completion.append(_mission_snapshot()), CONNECT_ONE_SHOT)
	for _i in 600:
		if not at_completion.is_empty():
			break
		await get_tree().process_frame
	await get_tree().process_frame
	assert_int(at_completion.size()).override_failure_message("CONTINUE never finished its load").is_equal(1)
	return at_completion[0] if not at_completion.is_empty() else {}


## Plays `mission` over four round ends with the marker holders in `rounds`. `how` = "" plays straight
## through; "in_game" / "cold" saves after round 1 and loads that way. Returns where the game ended.
func _play(mission: String, rounds: Array, how: String) -> Dictionary:
	_start_mission(mission)
	_book_round(1, rounds[0])
	if not how.is_empty():
		var saved := _mission_snapshot()
		assert_int(_main.save_manager.save_game(SAVE_PATH)).is_equal(OK)
		var at_completion: Dictionary
		if how == "in_game":
			_play_another_game(mission)
			at_completion = await _load_in_game(SAVE_PATH)
		else:
			at_completion = await _cold_start_and_continue(SAVE_PATH)
		assert_that(at_completion) \
			.override_failure_message("%s load: when load_completed fired the mission state was\n%s\nbut the game was saved with\n%s" % [how, at_completion, saved]) \
			.is_equal(saved)
	_book_round(2, rounds[1])
	_book_round(3, rounds[2])
	var verdict: String = await _finish_game(rounds[3])
	var end := _mission_snapshot()
	end["verdict"] = verdict
	return end


func _assert_same_game(loaded: Dictionary, straight: Dictionary, what: String) -> void:
	assert_that(loaded) \
		.override_failure_message("%s: the saved-and-loaded game ended as\n%s\nthe game that was never saved ended as\n%s" % [what, loaded, straight]) \
		.is_equal(straight)


# === The mission and its scoring state survive a load =============================================

## Demolition's revenge VP goes to the side whose marker fell FIRST. P1's marker falls in round 1 (before
## the save), P2's in round 2 (after the load): the destruction counter must continue at 2, or both carry
## seq 1, nobody earns revenge and NACHTMAHR wins 1:0 instead of losing 1:3.
func test_demolition_revenge_order_continues_across_an_in_game_load(timeout := 180000) -> void:
	var rounds := [[2, 0], [0, 1], [0, 0], [0, 0]]
	var straight := await _play("demolition", rounds, "")
	var loaded := await _play("demolition", rounds, "in_game")
	assert_that(loaded["vp"]).is_equal([3.0, 1.0])
	assert_that(loaded["destroy_seq"]).is_equal([2.0])
	assert_str(loaded["verdict"]).is_equal(HUMAN_WINS)
	_assert_same_game(loaded, straight, "Demolition, in-game load")
	await E2EBoot.settle(get_tree())


## Mosh Pit pays the first-seize VP once per game. P1 took it in round 1; after the load P2 seizes the
## marker — without the memo P2 is paid a second first-seize and the game ends 3:3 instead of 3:2.
func test_mosh_pit_never_pays_first_seize_twice_after_an_in_game_load(timeout := 180000) -> void:
	var rounds := [[1], [2], [1], [2]]
	var straight := await _play("mosh_pit", rounds, "")
	var loaded := await _play("mosh_pit", rounds, "in_game")
	assert_that(loaded["vp"]).is_equal([3.0, 2.0])
	assert_that(loaded["memo"]).is_equal({"first_seizer": 1.0})
	assert_str(loaded["verdict"]).is_equal(HUMAN_WINS)
	_assert_same_game(loaded, straight, "Mosh Pit, in-game load")
	await E2EBoot.settle(get_tree())


## Sabotage is decided by which OWNED markers were destroyed: P1's fell in round 1, P2's stands, so
## NACHTMAHR wins. Scored by the default rule, the empty board reads as a draw.
func test_sabotage_is_decided_by_the_destroyed_markers_after_an_in_game_load(timeout := 180000) -> void:
	var rounds := [[2, 0], [0, 0], [0, 0], [0, 0]]
	var straight := await _play("sabotage", rounds, "")
	var loaded := await _play("sabotage", rounds, "in_game")
	assert_str(loaded["scoring"]).is_equal("sabotage")
	assert_str(loaded["verdict"]).is_equal(NACHTMAHR_WINS)
	_assert_same_game(loaded, straight, "Sabotage, in-game load")
	await E2EBoot.settle(get_tree())


## The same Demolition game through quit + restart + CONTINUE: a fresh Main and fresh statics.
func test_demolition_survives_a_cold_start_and_continue(timeout := 180000) -> void:
	var rounds := [[2, 0], [0, 1], [0, 0], [0, 0]]
	var straight := await _play("demolition", rounds, "")
	var loaded := await _play("demolition", rounds, "cold")
	assert_str(loaded["id"]).is_equal("demolition")
	assert_that(loaded["vp"]).is_equal([3.0, 1.0])
	assert_str(loaded["verdict"]).is_equal(HUMAN_WINS)
	_assert_same_game(loaded, straight, "Demolition, cold start + CONTINUE")
	await E2EBoot.settle(get_tree())


## Mosh Pit through quit + restart + CONTINUE: the ledger and the first-seize memo come back too.
func test_mosh_pit_survives_a_cold_start_and_continue(timeout := 180000) -> void:
	var rounds := [[1], [2], [1], [2]]
	var straight := await _play("mosh_pit", rounds, "")
	var loaded := await _play("mosh_pit", rounds, "cold")
	assert_str(loaded["id"]).is_equal("mosh_pit")
	assert_that(loaded["vp"]).is_equal([3.0, 2.0])
	_assert_same_game(loaded, straight, "Mosh Pit, cold start + CONTINUE")
	await E2EBoot.settle(get_tree())


## Every catalog mission, not only the three the scenarios above play: one round booked, saved, another
## game started over it, loaded — the state at load_completed is the state that was saved.
func test_every_catalog_mission_comes_back_from_an_in_game_load(timeout := 180000) -> void:
	for id in MissionCatalog.mission_ids():
		_start_mission(id)
		_book_round(1, [1, 2])
		var saved := _mission_snapshot()
		assert_int(_main.save_manager.save_game(SAVE_PATH)).is_equal(OK)
		_play_another_game(id)
		var at_completion := await _load_in_game(SAVE_PATH)
		assert_that(at_completion) \
			.override_failure_message("mission '%s': at load_completed the state was\n%s\nbut the game was saved with\n%s" % [id, at_completion, saved]) \
			.is_equal(saved)
	await E2EBoot.settle(get_tree())


# === A save made without a mission leaves no mission active =======================================

func test_a_duel_save_loaded_over_a_mission_game_leaves_no_mission_active(timeout := 180000) -> void:
	_main._solo_mission_id = ""
	assert_that(_mission_snapshot()).override_failure_message("fixture: the Duel game is not at the defaults").is_equal(_no_mission_snapshot())
	assert_int(_main.save_manager.save_game(SAVE_PATH)).is_equal(OK)
	_play_another_game("")   # Demolition, one round booked
	var at_completion := await _load_in_game(SAVE_PATH)
	assert_that(at_completion) \
		.override_failure_message("a Duel save must replace the running mission; at load_completed the state was\n%s" % at_completion) \
		.is_equal(_no_mission_snapshot())
	_book_round(2, [2, 1])
	assert_that(_mission_snapshot()) \
		.override_failure_message("a round end after loading a Duel save booked mission state:\n%s" % _mission_snapshot()) \
		.is_equal(_no_mission_snapshot())
	await E2EBoot.settle(get_tree())


# === A save from before the fix (1.7, no mission data) still loads ===============================

## Rewrites the save at `path` into what a 1.7 build before S1-15 wrote for the same game: none of the
## keys added since.
func _rewrite_as_save_1_7(path: String) -> void:
	var state: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	for k in state.keys():
		if not ROOT_KEYS_1_7.has(k):
			state.erase(k)
	var gs: Dictionary = state["game_state"]
	for k in gs.keys():
		if not GAME_STATE_KEYS_1_7.has(k):
			gs.erase(k)
	state["version"] = "1.7"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(state, "\t"))
	f.close()


func test_an_old_1_7_save_loads_as_a_game_without_mission(timeout := 180000) -> void:
	_start_mission("mosh_pit")   # the old build played missions too, it only never saved them
	_book_round(1, [1])
	assert_int(_main.save_manager.save_game(SAVE_PATH)).is_equal(OK)
	_rewrite_as_save_1_7(SAVE_PATH)
	_play_another_game("mosh_pit")   # Demolition, one round booked
	var failures: Array = []
	_main.save_manager.load_failed.connect(func(e: String) -> void: failures.append(e), CONNECT_ONE_SHOT)
	var at_completion := await _load_in_game(SAVE_PATH)
	assert_array(failures).override_failure_message("the 1.7 save failed to load: %s" % [failures]).is_empty()
	assert_that(at_completion) \
		.override_failure_message("a 1.7 save carries no mission, so it must load as none; at load_completed the state was\n%s" % at_completion) \
		.is_equal(_no_mission_snapshot())
	_book_round(2, [2, 1])
	assert_that(_mission_snapshot()) \
		.override_failure_message("a round end after loading a 1.7 save booked mission state:\n%s" % _mission_snapshot()) \
		.is_equal(_no_mission_snapshot())
	await E2EBoot.settle(get_tree())
