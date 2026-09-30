extends GdUnitTestSuite
## E2E — D19 (a), PLAN_wave3_2026-09-27.md step 23: Surprise Attack (army-book v3.5.3: "The first
## time this unit is activated, pick one enemy unit within 6\" in line of sight, and roll X
## dice…"; maintainer note D19: usable at the very first activation, one-time). Before this fix,
## `_solo_apply_surprise_attack` stamped `surprise_attack_used` only AFTER a successful target
## pick, so a bearer with nothing in range on its first activation kept the ability armed and
## could still fire later. From EPOCH_67_MARKERS_BURSTS the latch burns on the FIRST activation
## whether or not a target exists.

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


func _reg(u: GameUnit) -> GameUnit:
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _ambusher(pos: Vector3) -> GameUnit:
	var u := _reg(E2EBoot.make_unit(_main, 2, "Skulker", [pos]))
	u.unit_properties["special_rules"] = ["Surprise Attack"]
	return u


func _enemy(pos: Vector3) -> GameUnit:
	return _reg(E2EBoot.make_unit(_main, 1, "Target", [pos]))


## No enemy anywhere near (well outside the 6" printed range): the ability must still be spent on
## this, the bearer's first, activation — not left armed for a later one.
func test_surprise_attack_latch_burns_with_no_target_in_range() -> void:
	var bearer := _ambusher(Vector3.ZERO)
	_enemy(Vector3(40.0 * INCH, 0, 0))   # far outside the 6" range
	await _main._solo_apply_surprise_attack(bearer)
	assert_bool(bool(bearer.unit_properties.get("surprise_attack_used", false))) \
		.override_failure_message("D19 a: the latch must burn on the first activation whether or not a target exists") \
		.is_true()


## A bearer whose first activation already burned the latch (proven above) must never fire on a
## LATER activation even once a target moves into range.
func test_surprise_attack_never_fires_after_the_latch_already_burned() -> void:
	var bearer := _ambusher(Vector3.ZERO)
	_enemy(Vector3(40.0 * INCH, 0, 0))   # far outside 6" — nothing to strike on the first activation
	await _main._solo_apply_surprise_attack(bearer)   # first activation, no target: burns the latch
	assert_bool(bool(bearer.unit_properties.get("surprise_attack_used", false))).is_true()

	# A second, later activation — a DIFFERENT enemy is well within 6" this time.
	var near_foe := _reg(E2EBoot.make_unit(_main, 1, "Closer", [Vector3(2.0 * INCH, 0, 0)]))
	var wounds_before := near_foe.get_alive_count()
	await _main._solo_apply_surprise_attack(bearer)
	assert_int(near_foe.get_alive_count()) \
		.override_failure_message("a spent bearer must not strike a second time") \
		.is_equal(wounds_before)
