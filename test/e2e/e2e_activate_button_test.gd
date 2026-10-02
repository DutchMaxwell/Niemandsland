extends GdUnitTestSuite
## E2E — D23 stage 2 (NML-977): the unit card's "Activate" button is the irrevocable start of an
## activation. It shows on a live (PLAYING), not yet activated unit; pressing it runs the ONE activation
## door (main.begin_activation, stage 1) and marks the unit activated; it is gone afterwards.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const LIST := "res://test/fixtures/wolf_brothers_3000.json"

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
	_main = null
	_runner = null


func _unit() -> GameUnit:
	var client := OPRApiClient.new()
	var army := client.build_army_offline(JSON.parse_string(FileAccess.get_file_as_string(LIST)))
	var opr: OPRApiClient.OPRUnit = army.units[0]
	var nodes: Array[Node3D] = []
	for i in range(maxi(opr.size, 1)):
		var n := Node3D.new()
		_main.object_manager.add_child(n)
		nodes.append(n)
	var gu: GameUnit = EquipmentDistributor.create_from_opr_unit(opr, nodes, 1)
	_main.opr_army_manager.game_units[gu.unit_id] = gu
	client.free()
	return gu


func _activate_button() -> Button:
	var dock: UnitDock = _main.unit_dock
	for n: Node in dock.find_children("*", "Button", true, false):
		if (n as Button).text == "Activate" and n.is_visible_in_tree():
			return n as Button
	return null


func _present(gu: GameUnit) -> void:
	_main.unit_dock.present_unit(gu)
	await E2EBoot.settle(get_tree())


func test_the_button_shows_only_on_a_live_unactivated_unit(timeout := 120000) -> void:
	var gu := _unit()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.DEPLOYMENT
	await _present(gu)
	assert_object(_activate_button()).override_failure_message("Activate shows during deployment").is_null()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.unit_dock.rebuild()
	await E2EBoot.settle(get_tree())
	var b := _activate_button()
	assert_object(b).override_failure_message("no Activate button on a live unit").is_not_null()
	if b != null:
		assert_str(String(b.theme_type_variation)).is_equal(String(HouseStyle.PRIMARY))
	gu.is_activated = true
	_main.unit_dock.rebuild()
	await E2EBoot.settle(get_tree())
	assert_object(_activate_button()).override_failure_message("Activate shows on an activated unit").is_null()


func test_pressing_it_runs_the_activation_door_once_and_activates(timeout := 120000) -> void:
	var gu := _unit()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	await _present(gu)
	var b := _activate_button()
	assert_object(b).override_failure_message("no Activate button on a live unit").is_not_null()
	if b == null:
		return
	b.pressed.emit()
	await E2EBoot.settle(get_tree())
	assert_bool(gu.is_activated).override_failure_message("pressing Activate did not activate the unit").is_true()
	assert_object(_activate_button()).override_failure_message("the button outlived the activation").is_null()
