extends GdUnitTestSuite
## Last Stand recycling (D11a) is ONCE per destroyed unit, however many casualty signals arrive: a volley
## parks its dead one model at a time with the whole unit already dead, and every signal used to put one
## more full-strength copy into reserve while the log line said "ONCE".

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	MissionCatalog._catalog()["stand_fixture"] = {"name": "Stand Fixture", "family": "attack_defend", "rounds": 6,
		"scoring": "end", "deployment": "front_line", "roles": true,
		"reserves": {"who": "attacker", "recycle": true, "arrive_on": 6, "from_round": 2, "zone": "edge_band_12", "gates": {}},
		"markers": {"count": 1, "placement": "table_centre"}}
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true
	SoloController.mission_roles = {"attacker": 2, "defender": 1}   # the AI attacks
	_main._solo_mission_id = "stand_fixture"


func after_test() -> void:
	SoloController.mission_reset("end", {})
	MissionCatalog.reset_cache()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)


func _profile(unit_name: String, size: int) -> OPRApiClient.OPRUnit:
	var u := OPRApiClient.OPRUnit.new()
	u.name = unit_name
	u.size = size
	u.quality = 4
	u.defense = 4
	u.cost = 100
	u.base_size_round = 25
	u.base_width_mm = 25
	u.base_depth_mm = 25
	u.game_system = "gf"
	return u


func _on_table(pid: int, unit_name: String, size: int) -> GameUnit:
	var spots: Array = []
	for i in size:
		spots.append(Vector3(float(i) * 1.2 * INCH, 0.0, 10.0 * INCH))
	return _main.opr_army_manager.create_runtime_unit({"opr_unit": _profile(unit_name, size), "faction_folder": "ratmen_clans"},
		pid, spots, "spawn")


## What a volley leaves behind: every wound applied (all models dead), none parked yet; parking sends one
## casualty signal per model.
func _wipe(u: GameUnit) -> void:
	var died: Array[ModelInstance] = []
	for m in u.models:
		(m as ModelInstance).is_alive = false
		died.append(m as ModelInstance)
	await _main._solo_remove_dead_models(u, died, int(u.unit_properties["player_id"]))


func _copies_of(unit_name: String) -> Array:
	return _main.opr_army_manager.get_game_units_for_player(2).filter(
		func(g: GameUnit) -> bool: return bool(g.unit_properties.get("recycled", false)) and g.get_name().begins_with(unit_name))


func test_a_unit_wiped_out_in_one_volley_returns_once(timeout := 240000) -> void:
	await _wipe(_on_table(2, "Fighters", 3))
	assert_int(_copies_of("Fighters").size()).override_failure_message("three casualty signals, one copy").is_equal(1)
	await E2EBoot.settle(get_tree())


## Counter-check: the guard is per destroyed unit, not global (two destroyed units = two copies).
func test_two_destroyed_units_each_return_once(timeout := 240000) -> void:
	await _wipe(_on_table(2, "Alpha", 2))
	await _wipe(_on_table(2, "Beta", 2))
	assert_int(_copies_of("Alpha").size()).is_equal(1)
	assert_int(_copies_of("Beta").size()).is_equal(1)
	await E2EBoot.settle(get_tree())


## Counter-check: the copy's own destruction stays final, also when it falls in one volley.
func test_the_copy_wiped_out_in_one_volley_does_not_return(timeout := 240000) -> void:
	await _wipe(_on_table(2, "Fighters", 3))
	await _wipe(_copies_of("Fighters")[0])
	assert_int(_copies_of("Fighters").size()).is_equal(1)
	await E2EBoot.settle(get_tree())
