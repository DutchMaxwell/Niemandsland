extends GdUnitTestSuite
## E2E — play test 29.10.2026 (audit B1, maintainer ruling the same day): Deadly(X) against Regeneration /
## Self-Repair rolls ONE die PER WOUND AFTER the multiplication. The ruling, verbatim: "Ne, man wuerfelt pro
## Wunde einen Reparaturwurf" — a Deadly(3) wound is 3 wounds and 3 rolls, not 1 roll before multiplying.
##
## `_solo_land_deadly_wounds` rolled the Regeneration family on the RAW unsaved count, then multiplied the
## survivors. Now each wound is assigned to its model and multiplied first (capped at what that model has
## left — no carry-over, unchanged), and the roll covers those wounds. Every roll is logged.
## These cases drive the real landing on scenes/main.tscn with an AI-owned target (auto-rolled dice).

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


## An AI-owned unit of three Tough(`tough`) models carrying `rule` on every model.
func _foe(rule: String, tough: int) -> GameUnit:
	var positions: Array = []
	for i in range(3):
		positions.append(Vector3(6.0 * INCH, 0, 0.03 * i))
	var u := E2EBoot.make_unit(_main, 2, "Brutes", positions)
	u.unit_properties["special_rules"] = [rule]
	u.unit_properties["tough"] = tough
	for m in u.models:
		(m as ModelInstance).wounds_max = tough
		(m as ModelInstance).wounds_current = tough
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _wounds_left(u: GameUnit) -> int:
	var total := 0
	for m in u.models:
		if (m as ModelInstance).is_alive:
			total += (m as ModelInstance).wounds_current
	return total


## The claim: one Deadly(3) wound on a fresh Tough(6) model = 3 wounds = 3 Regeneration dice.
func test_one_deadly_wound_rolls_regeneration_per_multiplied_wound() -> void:
	var foe := _foe("Regeneration", 6)
	_main.seed_tray_rng(5)
	var dealt: int = await _main._solo_land_deadly_wounds(foe, "Test Rifle", 3, 1, 0)
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("A4 — the ruling: one roll per wound AFTER the ×3 (log: %s)" % text.strip_edges()) \
		.contains("Brutes rolls 3 regeneration dice (5+)")
	assert_str(text).not_contains("rolls 1 regeneration die")
	assert_int(dealt).is_less_equal(3)
	assert_int(18 - _wounds_left(foe)).is_equal(dealt)
	await E2EBoot.settle(get_tree())


## Two unsaved Deadly(3) wounds: two models, two rolls of three dice each (Self-Repair, 6+).
func test_each_deadly_wound_gets_its_own_roll() -> void:
	var foe := _foe("Self-Repair", 6)
	_main.seed_tray_rng(5)
	var dealt: int = await _main._solo_land_deadly_wounds(foe, "Test Rifle", 3, 2, 0)
	var text := _log_text()
	assert_int(text.count("Brutes rolls 3 self-repair dice (6+)")) \
		.override_failure_message("A4 — each multiplied wound group needs its own logged roll (log: %s)" % text.strip_edges()) \
		.is_equal(2)
	assert_int(dealt).is_less_equal(6)
	assert_int(18 - _wounds_left(foe)).is_equal(dealt)
	await E2EBoot.settle(get_tree())


## The Tough cap stays: Deadly(3) on a fresh Tough(2) model is 2 wounds, so 2 dice, and nothing carries over.
func test_the_tough_cap_limits_the_roll_and_never_carries_over() -> void:
	var foe := _foe("Regeneration", 2)
	_main.seed_tray_rng(5)
	var dealt: int = await _main._solo_land_deadly_wounds(foe, "Test Rifle", 3, 1, 0)
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("A4 — capped at the model's 2 wounds, so 2 rolls (log: %s)" % text.strip_edges()) \
		.contains("Brutes rolls 2 regeneration dice (5+)")
	assert_int(dealt).is_less_equal(2)
	var hurt := 0
	for m in foe.models:
		if (m as ModelInstance).wounds_current < 2 or not (m as ModelInstance).is_alive:
			hurt += 1
	assert_int(hurt).override_failure_message("no carry-over: one model takes the wound").is_less_equal(1)
	await E2EBoot.settle(get_tree())


## CONTROL: a Deadly wound that ignores Regeneration rolls nothing and deals its full ×3.
func test_regen_proof_deadly_wound_rolls_nothing() -> void:
	var foe := _foe("Regeneration", 6)
	var dealt: int = await _main._solo_land_deadly_wounds(foe, "Test Rifle", 3, 0, 1)
	assert_str(_log_text()).not_contains("regeneration di")
	assert_int(dealt).is_equal(3)
	await E2EBoot.settle(get_tree())
