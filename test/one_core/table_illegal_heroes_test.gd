extends GdUnitTestSuite
## The table half of the legality read (`CoreShadow.table_illegal`) names the joined heroes of the units it is given, as the core's own
## `illegal` list does (it names every unit that moved, a joined hero included). fd-gate G1' soak g18: a hero's forbidden rest stood on
## both boards but read as core-only, because the table half checked the host and the target only.
## Planted: a joined hero's model on top of a model of a third, unnamed unit. RED on main: the table half lists nothing for the hero.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.5, "game_system": "gf", "faction_folder": "battle_brothers", "rules": []}

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {1: true, 2: true}
	_main._ensure_solo_controller()
	CoreActivation._env = 1


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## The hero's own overlap entries (a stray hero's coherency is read with its host on both sides, so it says nothing here).
func _hero_entries(illegal: Array, hero: GameUnit) -> Array:
	return illegal.filter(func(i: Dictionary) -> bool: return str(i.get("unit", "")) == hero.unit_id and str(i.get("kind", "")) == "overlap")


func test_a_joined_heros_illegal_rest_is_on_the_table_half() -> void:
	var host := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Host", "models": 3, "x_in": 0.0}, true), {})
	var hero := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Hero", "models": 1, "x_in": 3.0, "rules": ["Hero"]}, true), {})
	var other := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Other", "models": 1, "x_in": 12.0}, true), {})
	(hero.models[0] as ModelInstance).node.global_position = (host.models[0] as ModelInstance).node.global_position + Vector3(2.0 * 0.0254, 0.0, 0.0)
	EquipmentDistributor.attach_hero_to_unit(hero, host)
	var clean: Array = CoreShadow.table_illegal(_main, [host])
	assert_array(_hero_entries(clean, hero)).override_failure_message("control: a legal hero read illegal: %s" % [clean]).is_empty()
	(hero.models[0] as ModelInstance).node.global_position = (other.models[0] as ModelInstance).node.global_position
	var planted: Array = CoreShadow.table_illegal(_main, [host])
	assert_array(_hero_entries(planted, hero).map(func(i: Dictionary) -> String: return str(i["kind"]))) \
		.override_failure_message("the joined hero's overlap is not on the table half: %s" % [planted]).contains(["overlap"])
