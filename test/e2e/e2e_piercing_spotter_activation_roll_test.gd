extends GdUnitTestSuite
## E2E — W3-4 (a), PLAN_wave3_2026-09-27.md step 22: Piercing Spotter (army-book v3.5.3,
## gf/high_elf_fleets: "Once per activation, pick one enemy unit within 30\" and in line of
## sight of this model and roll one die, on a 4+ place a marker on it"). Before this fix,
## `_solo_apply_piercing_tag` shared the family's once-per-GAME latch and never rolled — a
## Spotter placed exactly once per game, unconditionally. From EPOCH_67_MARKERS_BURSTS it rolls
## the printed 4+ and gates on a per-activation-ROUND latch instead, so a live Spotter can place
## again next round.

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
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func _reg(u: GameUnit) -> GameUnit:
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _spotter(pos: Vector3) -> GameUnit:
	var u := _reg(E2EBoot.make_unit(_main, 2, "Watcher", [pos]))
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["faction_folder"] = "high_elf_fleets"
	u.unit_properties["special_rules"] = ["Piercing Spotter"]
	return u


func _target(pos: Vector3) -> GameUnit:
	return _reg(E2EBoot.make_unit(_main, 1, "Marked", [pos]))


## A forced hit (seeded tray) places one marker and burns this round's latch, but NOT the
## once-per-game flag — the same Spotter must be free to roll again next round.
func test_piercing_spotter_rolls_and_places_on_a_hit() -> void:
	_main.seed_tray_rng(1)
	var spotter := _spotter(Vector3.ZERO)
	var tgt := _target(Vector3(10.0 * INCH, 0, 0))
	_main.opr_army_manager.current_round = 1
	await _main._solo_apply_piercing_tag(spotter)
	var text := _log_text()
	assert_bool(bool(spotter.unit_properties.get("piercing_tag_used", false))) \
		.override_failure_message("the Spotter's latch must be the ROUND stamp, not the once-per-game flag") \
		.is_false()
	assert_int(int(spotter.unit_properties.get("piercing_spot_round", -1))) \
		.override_failure_message("the roll must burn this round's latch") \
		.is_equal(1)
	var markers := int(tgt.unit_properties.get("piercing_tag_markers", 0))
	assert_int(markers).override_failure_message("seed 1 is a forced hit").is_equal(1)
	assert_str(text) \
		.override_failure_message("rules-must-log — got: %s" % text.strip_edges()) \
		.contains("Piercing Spotter: Watcher places 1 marker on Marked")

	# Same round: the latch refuses a second roll — a second call places nothing more.
	var before := int(tgt.unit_properties.get("piercing_tag_markers", 0))
	await _main._solo_apply_piercing_tag(spotter)
	assert_int(int(tgt.unit_properties.get("piercing_tag_markers", 0))) \
		.override_failure_message("once per activation round: a second call this round must not re-roll") \
		.is_equal(before)

	# Next round: the latch is free again — this is the point of NOT sharing the once-per-game flag.
	_main.opr_army_manager.current_round = 2
	await _main._solo_apply_piercing_tag(spotter)
	assert_int(int(spotter.unit_properties.get("piercing_spot_round", -1))) \
		.override_failure_message("W3-4 a: a live Spotter must be able to roll again next round") \
		.is_equal(2)


## A forced miss (seed 3) places nothing, but the round latch still burns — the tray was rolled,
## the pick just did not clear 4+.
func test_piercing_spotter_miss_places_nothing_but_still_burns_the_round() -> void:
	_main.seed_tray_rng(3)
	var spotter := _spotter(Vector3.ZERO)
	var tgt := _target(Vector3(10.0 * INCH, 0, 0))
	_main.opr_army_manager.current_round = 1
	await _main._solo_apply_piercing_tag(spotter)
	assert_int(int(tgt.unit_properties.get("piercing_tag_markers", 0))) \
		.override_failure_message("a forced miss must place nothing") \
		.is_equal(0)
	assert_int(int(spotter.unit_properties.get("piercing_spot_round", -1))) \
		.override_failure_message("the roll still spends the activation, hit or miss") \
		.is_equal(1)
	assert_str(_log_text()).contains("Piercing Spotter: Watcher misses the mark on Marked (needed 4+)")
