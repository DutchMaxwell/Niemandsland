extends GdUnitTestSuite
## Rules 3.6 row MOR-16b (table half): a carrier of "Spell Drain" picks its
## committed enemy at the attack seam, takes the REAL table Morale test and, on
## a failure, spends two of that unit's spell tokens (floor 0). The core twin
## is MOR-16a; this suite drives main.gd's live seam and the committed map.

const Boot := preload("res://test/e2e/e2e_boot.gd")

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
	_main._solo_batch = true


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0
	RulesRegistry.reset_cache()
	Boot.free_stray_root_nodes(get_tree(), _roots)
	_main = null
	_runner = null


func _unit(unit_name: String, pid: int, pos: Vector3, rules: Array, quality: int, tokens: int) -> GameUnit:
	var unit := Boot.make_unit(_main, pid, unit_name, [pos])
	unit.unit_properties["game_system"] = "gf"
	unit.unit_properties["faction_folder"] = "blessed_sisters"
	unit.unit_properties["special_rules"] = rules.duplicate()
	unit.unit_properties["quality"] = quality
	unit.casts_current = tokens
	return unit


func _bearer_and_target(tokens: int = 5, quality: int = 6, target_rules: Array = []) -> Array:
	var bearer := _unit("Drainer", 1, Vector3(-0.3, 0, 0), ["Spell Drain"], 4, 0)
	var target := _unit("Target", 2, Vector3(0.3, 0, 0), ["Caster(2)"] + target_rules, quality, tokens)
	return [bearer, target]


func _attach_hero(target: GameUnit) -> GameUnit:
	var hero := _unit("Hero", 3, Vector3(0.3, 0, 0), [], 4, 0)
	target.unit_properties["attached_heroes"] = [hero]
	hero.unit_properties["attached_to"] = target
	return hero


## The first tray face this seed produces (and the second, when asked) — the
## live dice stream is the tray's own RNG, seeded exactly as the arena does.
func _seed_for(face: int, second: int = 0) -> int:
	for s in range(2000):
		_main._tray_rng.seed = s
		if _main._tray_rng.randi_range(1, 6) != face:
			continue
		if second == 0 or _main._tray_rng.randi_range(1, 6) == second:
			return s
	return 0


func _log_text() -> String:
	var text := ""
	for entry in _main.battle_log.entries():
		text += str(entry["text"]) + "\n"
	return text


## A solid container wall across the lane (same shape as the Mark LOS suite).
func _wall_between(o: Node3D) -> void:
	for i in range(41):
		var t := float(i) / 40.0
		if t < 0.4 or t > 0.6:
			continue
		o.grid_cells[o.world_to_cell(Vector3(-0.3, 0, 0).lerp(Vector3(0.3, 0, 0), t))] = o.TerrainType.CONTAINER


func test_a_failed_morale_test_takes_two_spell_tokens() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var pair := _bearer_and_target()
	var bearer: GameUnit = pair[0]
	var target: GameUnit = pair[1]
	var hero := _attach_hero(target)
	_main.opr_army_manager.current_round = 1
	_main.seed_tray_rng(_seed_for(1))
	await _main._solo_apply_vs_marks(bearer, target, 10.0)
	assert_int(target.casts_current).is_equal(3)
	assert_str(_log_text()).contains("Drainer drains Target: Morale test failed, -2 spell tokens (5 -> 3) — Shaken")
	assert_bool(target.is_shaken).is_true()
	assert_bool(hero.is_shaken).is_true()
	assert_int(int(bearer.unit_properties.get("vs_mark_round", -1))).is_equal(1)


func test_a_passed_morale_test_keeps_the_tokens_and_names_the_test() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var pair := _bearer_and_target(3, 2)
	var bearer: GameUnit = pair[0]
	var target: GameUnit = pair[1]
	var hero := _attach_hero(target)
	_main.opr_army_manager.current_round = 1
	_main.seed_tray_rng(_seed_for(6))
	await _main._solo_apply_vs_marks(bearer, target, 10.0)
	assert_int(target.casts_current).is_equal(3)
	assert_str(_log_text()).contains("Drainer drains Target: Morale test passed")
	assert_bool(target.is_shaken).is_false()
	assert_bool(hero.is_shaken).is_false()


func test_a_fearless_target_recovers_and_keeps_its_tokens() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var pair := _bearer_and_target(5, 6, ["Fearless"])
	var bearer: GameUnit = pair[0]
	var target: GameUnit = pair[1]
	_main.opr_army_manager.current_round = 1
	_main.seed_tray_rng(_seed_for(1, 4))
	await _main._solo_apply_vs_marks(bearer, target, 10.0)
	assert_int(target.casts_current).is_equal(5)
	assert_str(_log_text()).contains("Fearless — recovery die (4+) holds")
	assert_str(_log_text()).contains("Drainer drains Target: Morale test passed")


func test_a_second_activation_in_the_same_round_drains_nothing() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var pair := _bearer_and_target()
	var bearer: GameUnit = pair[0]
	var target: GameUnit = pair[1]
	_main.opr_army_manager.current_round = 1
	_main.seed_tray_rng(_seed_for(1))
	await _main._solo_apply_vs_marks(bearer, target, 10.0)
	var first := target.casts_current
	await _main._solo_apply_vs_marks(bearer, target, 10.0)
	assert_int(target.casts_current).is_equal(first)
	assert_int(_log_text().count("drains Target")).is_equal(1)


func test_out_of_range_drains_nothing() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var pair := _bearer_and_target()
	var bearer: GameUnit = pair[0]
	var target: GameUnit = pair[1]
	_main.opr_army_manager.current_round = 1
	await _main._solo_apply_vs_marks(bearer, target, 19.0)
	assert_int(target.casts_current).is_equal(5)
	assert_str(_log_text()).not_contains("drains Target")


func test_a_target_behind_a_wall_drains_nothing() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	_wall_between(_main.terrain_overlay)
	var pair := _bearer_and_target()
	var bearer: GameUnit = pair[0]
	var target: GameUnit = pair[1]
	_main.opr_army_manager.current_round = 1
	await _main._solo_apply_vs_marks(bearer, target, 6.0)
	assert_int(target.casts_current).is_equal(5)
	assert_str(_log_text()).not_contains("drains Target")


func test_epoch_72_drains_nothing() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var pair := _bearer_and_target()
	var bearer: GameUnit = pair[0]
	var target: GameUnit = pair[1]
	_main.opr_army_manager.current_round = 1
	await _main._solo_apply_vs_marks(bearer, target, 10.0)
	assert_int(target.casts_current).is_equal(5)
	assert_str(_log_text()).not_contains("drains Target")


## FAB-B3: the target is not a caster itself; its joined hero is. The hero's
## pool pays the two tokens, the host's empty pool stays at zero.
func test_a_joined_caster_hero_pays_the_drain() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var bearer := _unit("Drainer", 1, Vector3(-0.3, 0, 0), ["Spell Drain"], 4, 0)
	var target := _unit("Target", 2, Vector3(0.3, 0, 0), [], 6, 0)
	var hero := _unit("Hero", 3, Vector3(0.3, 0, 0), ["Caster(2)"], 4, 5)
	target.unit_properties["attached_heroes"] = [hero]
	hero.unit_properties["attached_to"] = target
	_main.opr_army_manager.current_round = 1
	_main.seed_tray_rng(_seed_for(1))
	await _main._solo_apply_vs_marks(bearer, target, 10.0)
	assert_int(hero.casts_current).is_equal(3)
	assert_int(target.casts_current).is_equal(0)
	assert_str(_log_text()).contains("Drainer drains Hero: Morale test failed, -2 spell tokens (5 -> 3) — Shaken")


## A chain with no caster takes the Morale test like any target: a failure
## leaves it Shaken and latches, but there is no token pool to spend.
func test_a_non_caster_target_is_shaken_but_loses_no_tokens() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var bearer := _unit("Drainer", 1, Vector3(-0.3, 0, 0), ["Spell Drain"], 4, 0)
	var target := _unit("Target", 2, Vector3(0.3, 0, 0), [], 6, 5)
	_main.opr_army_manager.current_round = 1
	_main.seed_tray_rng(_seed_for(1))
	await _main._solo_apply_vs_marks(bearer, target, 10.0)
	assert_bool(target.is_shaken).is_true()
	assert_int(target.casts_current).is_equal(5)
	assert_int(int(bearer.unit_properties.get("vs_mark_round", -1))).is_equal(1)
	assert_str(_log_text()).contains("no spell tokens to lose")
