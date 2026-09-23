extends GdUnitTestSuite
## E2E — defects in the in-game HUD that ships on 25.09., each one measured in a real 1920x1080
## capture of the live game before it was fixed (HUD agenda, 23.09.). Every test boots the REAL
## scenes/main.tscn and drives the functions main.gd itself calls, because every one of these lived in
## main.gd's own flow (the load path, the hover, the HUD layout) where no unit-level suite looks.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _tmp_saves: Array = []


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	for p in _tmp_saves:
		if FileAccess.file_exists(str(p)):
			DirAccess.remove_absolute(str(p))
	_tmp_saves.clear()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


# --- helpers -------------------------------------------------------------------------------

## A Battle Brothers profile as Army Forge delivers it: Quality 3+, Defense 3+ — deliberately NOT the
## OPRUnit class defaults (4/4), so a profile that silently falls back to the defaults is caught.
func _profile() -> OPRApiClient.OPRUnit:
	var u := OPRApiClient.OPRUnit.new()
	u.name = "Battle Brothers"
	u.size = 2
	u.quality = 3
	u.defense = 3
	u.cost = 300
	u.base_size_round = 32
	u.base_width_mm = 32
	u.base_depth_mm = 32
	u.game_system = "gf"
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Heavy Rifle"
	w.range_value = 24
	w.attacks = 1
	u.weapons.append(w)
	return u


## A unit on the table, saved, the table emptied, the save loaded — what a player gets when the game
## starts straight into a saved battle: that process never saw the spawn, so nothing the spawn builds
## (unit strip cards, the model -> profile map) exists before the load. Returns the unit's id.
func _unit_through_save_and_fresh_load() -> String:
	var mgr = _main.opr_army_manager
	var gu: GameUnit = mgr.create_runtime_unit({"opr_unit": _profile(), "faction_folder": "ratmen_clans"}, 1,
		[Vector3(0.25, 0.0, -0.35), Vector3(0.25 + 1.2 * INCH, 0.0, -0.35)], "spawn")
	assert_object(gu).is_not_null()
	var uid: String = gu.unit_id
	await _runner.simulate_frames(2)
	var path := "user://e2e_hud_release_%d.nml" % Time.get_ticks_usec()
	_tmp_saves.append(path)
	assert_int(_main.save_manager.save_game(path)).is_equal(OK)
	mgr.clear_all()
	_main.unit_dock.rebuild()
	assert_int(_main.unit_dock._cards.size()).is_equal(0)
	await _runner.simulate_frames(2)
	await _main.save_manager.load_game(path)
	await _runner.simulate_frames(4)
	return uid


# === 1. The unit strip after a save-load ======================================================
# Capture 02a: after starting into a saved battle the strip under the Units tab was empty — rebuild()
# only ever ran on army_spawned, and a load emits none. Fixed on main by 729c28f6 (#1069) without a
# test; this is that test.

func test_the_unit_strip_has_a_card_for_every_unit_of_a_loaded_save() -> void:
	var uid: String = await _unit_through_save_and_fresh_load()
	var dock = _main.unit_dock
	assert_bool(dock._cards.has(uid)).is_true() \
		.override_failure_message("the unit strip has no card for the loaded unit — the load never rebuilt it")
	assert_int(dock._cards.size()).is_equal(dock._local_units().size())
	await E2EBoot.settle(get_tree())
