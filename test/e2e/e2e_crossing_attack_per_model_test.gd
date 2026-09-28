extends GdUnitTestSuite
## E2E — D20 (a), PLAN_wave3_2026-09-27.md step 24: Crossing Attack (GF p.4 "this model" — a MODEL
## rule, not a unit-wide one; army-book: "Once per activation, when this model moves through enemy
## units, pick one of them and roll X dice."). Before this fix, `_solo_apply_crossing_attack`
## pooled every model's trail into ONE roll of the rule's plain rating and `return`ed after the
## first bearer, so a joined hero's own entry never fired. From this fix each bearer rolls X dice
## PER crossing model of its OWN trail, and a joined hero rolls its own entry too.

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


## 5 models spread across z at x=0" — z ±3"/±0.5"/0", so exactly 3 (the ±0.5"/0" ones) end up
## within the victim's base radius after the same +12" advance every model shares.
func _spread_host() -> GameUnit:
	var zs: Array = [-3.0, -0.5, 0.0, 0.5, 3.0]
	var positions: Array = []
	for z in zs:
		positions.append(Vector3(0.0, 0.0, z * INCH))
	var u := _reg(E2EBoot.make_unit(_main, 2, "Line", positions))
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["faction_folder"] = "high_elf_fleets"
	u.unit_properties["special_rules"] = ["Crossing Attack(2)"]
	return u


func _hero_at_origin() -> GameUnit:
	var u := _reg(E2EBoot.make_unit(_main, 2, "Herald", [Vector3.ZERO]))
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["faction_folder"] = "high_elf_fleets"
	u.unit_properties["special_rules"] = ["Crossing Attack(2)"]
	return u


## Several models at the SAME spot (D20 a only cares about the base disc, not the head count) so
## the unit survives the host's crossing wounds and is still there for the hero's own roll.
func _target(pos: Vector3) -> GameUnit:
	var positions: Array = []
	for i in range(10):
		positions.append(pos)
	return _reg(E2EBoot.make_unit(_main, 1, "Marked", positions))


## Every model's straight leg from its start position to start + (12", 0, 0) — the shared
## +x advance both the host and its joined hero take together.
func _advance_paths(u: GameUnit) -> Array:
	var out: Array = []
	for m in u.models:
		var mi := m as ModelInstance
		var start: Vector3 = mi.node.global_position
		var finish: Vector3 = start + Vector3(12.0 * INCH, 0.0, 0.0)
		out.append({"model": mi, "path": [start, finish]})
	return out


func test_crossing_attack_scales_dice_by_crossing_models_and_a_joined_hero_rolls_too() -> void:
	var host := _spread_host()
	var hero := _hero_at_origin()
	host.unit_properties["attached_heroes"] = [hero]
	hero.unit_properties["attached_to"] = host
	_target(Vector3(6.0 * INCH, 0.0, 0.0))
	_main.solo_controller.last_move_paths = _advance_paths(host) + _advance_paths(hero)
	await _main._solo_apply_crossing_attack(host)
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("rules-must-log — must name the host with 6 dice (3 crossing models x 2) — got: %s" % text.strip_edges()) \
		.contains("Crossing Attack: 3 models of Line cross Marked — ")
	assert_str(text).contains(" of 6 dice wound")
	assert_str(text) \
		.override_failure_message("D20 a: the joined hero's own entry must roll too — got: %s" % text.strip_edges()) \
		.contains("Crossing Attack: 1 model of Herald cross Marked — ")
	assert_str(text).contains(" of 2 dice wound")
