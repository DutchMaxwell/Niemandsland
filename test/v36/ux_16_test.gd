extends GdUnitTestSuite
## Rules 3.6 wave, row UX-16: a unit that Spawn places or that Split creates cannot seize or contest an
## objective in the round it appears. It reuses the round stamp Ambush arrivals already carry, so the
## round-end seize, the AI's simulation and the core all read one field. Rules 3.5 (epoch 72) had no such
## limit: there the fresh unit contests at once.

const Boot := preload("res://test/e2e/e2e_boot.gd")
const ROUND := 2

var _runner: GdUnitSceneRunner
var _main: Node
var _roots: Array
var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	Boot.arm_harness_mode()
	_roots = Boot.root_children(get_tree())
	_runner = scene_runner(Boot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = ROUND
	_main._solo_batch = true


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests — restore
	Boot.free_stray_root_nodes(get_tree(), _roots)
	_main = null
	_runner = null


## A player-2 carrier of `size` models with one unit-creating rule; the named unit comes off a fixture book.
func _carrier(rule: String, faction: String, size: int) -> GameUnit:
	var manager: OPRArmyManager = _main.opr_army_manager
	var army := OPRApiClient.OPRArmy.new()
	army.army_id = "ux_16_fixture"
	army.game_system_abbrev = "gf"
	army.faction_folder = faction
	manager.armies[2] = army
	manager.api_client._army_books[army.army_id] = {"units": [{"id": "hatchlings",
		"name": "Hatchlings", "size": 3, "quality": 5, "defense": 5, "specialRules": [],
		"equipment": [{"name": "Claws", "range": 0, "attacks": 1}]}]}
	var profile := OPRApiClient.OPRUnit.new()
	profile.name = "Carrier"
	profile.size = size
	profile.quality = 4
	profile.defense = 4
	profile.game_system = "gf"
	profile.base_size_round = 25
	profile.special_rules.assign([rule])
	var spots: Array = []
	for i in size:
		spots.append(Vector3(0.05 * i, 0, 0))
	return manager.create_runtime_unit({"opr_unit": profile, "faction_folder": faction}, 2, spots, "fixture")


## The one unit the rule put on the table this round.
func _created(origin: String) -> GameUnit:
	var units: Array = _main.opr_army_manager.get_all_game_units().filter(func(u: GameUnit) -> bool:
		return str(u.unit_properties.get("origin", "")) == origin)
	assert_array(units).has_size(1)
	return units[0] as GameUnit if not units.is_empty() else null


## One marker under the fresh unit, with a player-1 holder standing on it as well: whoever may count there
## decides whether the marker stays with player 1 or goes neutral.
func _contest_marker_under(fresh: GameUnit) -> void:
	var at := (fresh.get_alive_models()[0] as ModelInstance).node.global_position
	at.y = 0.0
	var holder := Boot.make_unit(_main, 1, "Holder", [at])
	_main.opr_army_manager.game_units[holder.unit_id] = holder
	_main.terrain_overlay.update_objectives([at], [1])


func _spawned_unit() -> GameUnit:
	var carrier := _carrier("Spawn(Hatchlings [3])", "alien_hives", 1)
	await _main._solo_try_reanimation(carrier)
	Boot.place_unit_at(carrier, Vector3(0.6, 0, 0.6))   # the carrier itself stays clear of the marker
	return _created("spawn")


func _split_unit() -> GameUnit:
	var carrier := _carrier("Split(Hatchlings [3])", "daemons_of_change", 2)
	await _main._solo_apply_wounds(carrier, 1)
	await _main._solo_apply_wounds(carrier, 1)
	return _created("split")


func _log_text() -> String:
	var out := ""
	for entry in _main.battle_log.entries():
		out += str((entry as Dictionary)["text"]) + "\n"
	return out


func _owner_after_round_end() -> int:
	_main._solo_auto_seize()
	return _main.terrain_overlay.get_objective_owner(0)


func test_a_freshly_spawned_unit_cannot_contest_on_its_placement_round_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var fresh := await _spawned_unit()
	if fresh == null:
		return
	_contest_marker_under(fresh)
	assert_int(_owner_after_round_end()) \
		.override_failure_message("a unit placed by Spawn this round must not contest the marker") \
		.is_equal(1)
	assert_str(_log_text()).contains("placed by Spawn this round and cannot seize or contest")
	_main.opr_army_manager.current_round = ROUND + 1
	assert_int(_owner_after_round_end()) \
		.override_failure_message("from the next round on the spawned unit contests like any other") \
		.is_equal(0)


func test_a_freshly_spawned_unit_contests_at_once_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var fresh := await _spawned_unit()
	if fresh == null:
		return
	_contest_marker_under(fresh)
	assert_int(_owner_after_round_end()).is_equal(0)


func test_a_unit_created_by_split_cannot_contest_on_its_placement_round_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var fresh := await _split_unit()
	if fresh == null:
		return
	_contest_marker_under(fresh)
	assert_int(_owner_after_round_end()) \
		.override_failure_message("a unit created by Split this round must not contest the marker") \
		.is_equal(1)
	assert_str(_log_text()).contains("placed by Split this round and cannot seize or contest")
	_main.opr_army_manager.current_round = ROUND + 1
	assert_int(_owner_after_round_end()).is_equal(0)


func test_a_unit_created_by_split_contests_at_once_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var fresh := await _split_unit()
	if fresh == null:
		return
	_contest_marker_under(fresh)
	assert_int(_owner_after_round_end()).is_equal(0)
