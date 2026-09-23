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


# === 2. The hover tooltip after a save-load ===================================================
# Capture 04 + probe A: pointing at a loaded model showed nothing — the hover asks get_unit_for_model(),
# whose model -> profile map is filled only at spawn (0 entries after a load). And the profile the save
# hands back had lost name, points, Quality and Defense (OPRUnit.to_dict carries the loadout only), so a
# tooltip forced onto it read the class defaults Q4+/D4+ where the unit card said Q3+/D3+.

func test_the_hover_tooltip_shows_a_loaded_unit_with_its_own_profile() -> void:
	var uid: String = await _unit_through_save_and_fresh_load()
	var loaded: GameUnit = _main.opr_army_manager.game_units.get(uid)
	assert_object(loaded).is_not_null()
	if loaded == null:
		return
	var node: Node3D = (loaded.models[0] as ModelInstance).node
	# The exact lookup _update_opr_hover makes for the model under the cursor.
	var profile = _main.opr_army_manager.get_unit_for_model(node)
	assert_object(profile).is_not_null() \
		.override_failure_message("hovering a loaded model finds no unit — the tooltip stays dead")
	# The profile the load restored, whichever way the hover reaches it.
	var restored := loaded.source_data as OPRApiClient.OPRUnit
	assert_object(restored).is_not_null()
	if restored == null:
		return
	assert_str(restored.name).is_equal("Battle Brothers")
	assert_int(restored.quality).is_equal(3)
	assert_int(restored.defense).is_equal(3)
	assert_int(restored.cost).is_equal(300)
	var tip = _main.opr_stats_tooltip
	tip.show_unit(restored, node, true)
	assert_str(tip.unit_name_label.text).contains("Battle Brothers")
	assert_str(tip.stats_label.text).contains("Quality: [color=#88ff88]3+") \
		.contains("Defense: [color=#8888ff]3+").contains("300 pts")
	tip.hide_tooltip()
	await E2EBoot.settle(get_tree())


# === 3. The ruler readout ======================================================================
# Probe B: DistanceLabel (860,10 200x40) sat under the Battle Log tab (790,6 340x41) — both children of
# UI/HUD, the log added later and so painted on top: "30.4″" was invisible for the whole measurement.

func test_the_ruler_readout_is_not_covered_while_measuring() -> void:
	_main._on_distance_changed(30.4, Vector3.ZERO, Vector3(30.4 * INCH, 0.0, 0.0))
	await _runner.simulate_frames(2)
	var label: Label = _main.distance_label
	assert_str(label.text).is_equal("30.4\"")
	assert_bool(label.is_visible_in_tree()).is_true()
	var neighbours := {
		"Battle Log tab": _main.battle_log_panel,
		"FPS line": _main.performance_label,
		"controls list": _main.get_node("UI/HUD/InfoLabel"),
	}
	for what in neighbours:
		assert_bool(label.get_global_rect().intersects((neighbours[what] as Control).get_global_rect())).is_false() \
			.override_failure_message("the ruler readout %s lies under the %s %s" % [
				label.get_global_rect(), what, (neighbours[what] as Control).get_global_rect()])
	# Measuring with the log OPEN — its panel grows downward from the same tab.
	_main.battle_log_panel._toggle()
	await _runner.simulate_frames(2)
	assert_bool(label.get_global_rect().intersects(_main.battle_log_panel.get_global_rect())).is_false() \
		.override_failure_message("the ruler readout lies under the opened battle log")
	_main.battle_log_panel._toggle()
