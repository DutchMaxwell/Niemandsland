extends GdUnitTestSuite
## E2E — MOVE_GAPS D4 (P3 step 73, flag-free): a human unit's move uses up its "+X once" speed mods.
##
## The AI's executed move spends a Great Musician +1" (main._solo_spend_once_kind after the move); the
## human side never did, so a buffed human unit kept the +1" on every later move. Now the human
## activation door (_on_solo_human_activated) spends a moved unit's speed once-records before its
## Utility Buff door. Covered on BOTH doors: the solo branch (an AI seat) and the plain-room branch
## (no AI seat). A unit that did not move keeps its record; a round-long Speed Feat record stays; a
## buff the bearer hands itself at the door survives (the spend runs before the buff).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const ROUND := 2

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = ROUND
	_main._solo_fast = true
	_main._solo_batch = true


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## with_ai: NACHTMAHR holds slot 2 (the solo branch); else a plain room with no AI seat.
func _seat(with_ai: bool) -> void:
	_main.solo_ai_slots = {2: true} if with_ai else {}
	if with_ai:
		_main._ensure_solo_controller()


## A human unit carrying a Great Musician +1" once-record (as the Utility Buff writes it) and a
## round-long Speed Feat +2" record (as solo_spend_speed_feat writes it).
func _buffed_unit(unit_name: String, moved: bool) -> GameUnit:
	var u := E2EBoot.make_unit(_main, 1, unit_name, [Vector3.ZERO])
	_main.opr_army_manager.game_units[u.unit_id] = u
	if moved:
		u.unit_properties["moved_round"] = ROUND
	_main._solo_record_spell_mod(u, "Great Musician", {"modifier": {"advance_in": 1, "rush_in": 1}, "duration": "once"})
	_main._solo_record_spell_mod(u, "Speed Feat", {"modifier": {"advance_in": 2, "rush_in": 2}, "duration": "round", "quiet": true})
	return u


func _spells_on(u: GameUnit) -> Array:
	var out: Array = []
	for rd in _main._solo_spell_mods.get(u.get_instance_id(), []):
		out.append(str((rd as Dictionary).get("spell", "")))
	return out


func _assert_spent(u: GameUnit, branch: String) -> void:
	assert_array(_spells_on(u)).override_failure_message(
			"%s: a unit that moved this round kept its Great Musician once-record (%s)" % [branch, str(_spells_on(u))]) \
		.is_equal(["Speed Feat"])
	assert_dict(u.unit_properties.get("spell_move_mod", {})).override_failure_message(
			"%s: the spent +1\" stayed in the move bands" % branch) \
		.is_equal({"advance": 2, "rush": 2})


func _assert_kept(u: GameUnit, branch: String) -> void:
	assert_array(_spells_on(u)).override_failure_message(
			"%s: a unit that did not move lost its Great Musician once-record (%s)" % [branch, str(_spells_on(u))]) \
		.is_equal(["Great Musician", "Speed Feat"])
	assert_dict(u.unit_properties.get("spell_move_mod", {})).is_equal({"advance": 3, "rush": 3})


func test_solo_door_spends_a_moved_units_speed_once_record(timeout := 120000) -> void:
	_seat(true)
	var u := _buffed_unit("Movers", true)
	await _main._on_solo_human_activated(u)
	_assert_spent(u, "solo door")


func test_solo_door_keeps_an_unmoved_units_speed_once_record(timeout := 120000) -> void:
	_seat(true)
	var u := _buffed_unit("Holders", false)
	await _main._on_solo_human_activated(u)
	_assert_kept(u, "solo door")


func test_plain_room_door_spends_a_moved_units_speed_once_record(timeout := 120000) -> void:
	_seat(false)
	var u := _buffed_unit("Movers", true)
	await _main._on_solo_human_activated(u)
	_assert_spent(u, "plain-room door")


func test_plain_room_door_keeps_an_unmoved_units_speed_once_record(timeout := 120000) -> void:
	_seat(false)
	var u := _buffed_unit("Holders", false)
	await _main._on_solo_human_activated(u)
	_assert_kept(u, "plain-room door")


## A lone Great Musician bearer that moved buffs itself at its door (a hero may buff itself): that
## NEW record is for its next move and must survive the door.
func test_a_buff_the_bearer_hands_out_at_the_door_survives(timeout := 120000) -> void:
	_seat(true)
	var giver := E2EBoot.make_unit(_main, 1, "Great Musician", [Vector3.ZERO])
	giver.unit_properties["game_system"] = "aof"
	giver.unit_properties["faction_folder"] = "ogres"
	giver.unit_properties["special_rules"] = ["Hero", "Great Musician"]
	giver.unit_properties["moved_round"] = ROUND
	_main.opr_army_manager.game_units[giver.unit_id] = giver
	await _main._on_solo_human_activated(giver)
	assert_array(_spells_on(giver)).override_failure_message(
			"the bearer's new Great Musician record was spent by the same door (%s)" % str(_spells_on(giver))) \
		.is_equal(["Great Musician"])
