extends GdUnitTestSuite
## Rules 3.6 wave, row SHO-16: Cumbersome (37 units). From the rules 3.6 epoch (73) on, a Cumbersome
## unit may only Hold or Advance and never shoots after it moved; below it (72) it plays as before.
## The map carries the rule for both systems (so the inventory stops listing it "by hand"), and the
## player's engine verbs refuse Rush and Charge for it and keep the shot pick shut after an Advance.
## The manual table (free drag, then Shoot) reads the drop's moved_round stamp: a unit that moved fires nothing.

const MainScript := preload("res://scripts/main.gd")
const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _epoch0: int
var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	RulesRegistry.reset_cache()


func after_test() -> void:
	# statics leak across gdUnit tests — restore
	AiActRecorder.rules_epoch = _epoch0
	RulesRegistry.reset_cache()
	if _main != null:
		E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _unit_with(rules: Array, system: String) -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = "t_1"
	u.unit_properties = {"player_id": 2, "name": "Walker", "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": system, "faction_folder": "some_book"}
	return u


## main.gd's static helpers are called by name on a bare instance, so a tree without them fails on
## the assertion below, not on a missing symbol.
func _main_static(fn: String, args: Array, fallback: Variant) -> Variant:
	var main: Node = auto_free(MainScript.new())
	return main.callv(fn, args) if main.has_method(fn) else fallback


func test_cumbersome_resolves_from_the_map_in_both_systems() -> void:
	for system in ["gf", "aof"]:
		var u := _unit_with(["Cumbersome"], system)
		assert_bool(RulesRegistry.unit_rule_active(u, "Cumbersome")) \
			.override_failure_message("%s: the map must carry Cumbersome in common" % system).is_true()


func test_cumbersome_is_active_only_from_epoch_73() -> void:
	var u := _unit_with(["Cumbersome"], "gf")
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	assert_bool(bool(_main_static("cumbersome_active", [u], false))) \
		.override_failure_message("rules 3.6: the rule is live").is_true()
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	assert_bool(bool(_main_static("cumbersome_active", [u], false))) \
		.override_failure_message("rules 3.5 has no Cumbersome").is_false()


func test_an_ordinary_unit_is_never_cumbersome_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var u := _unit_with(["Tough(3)"], "gf")
	assert_bool(bool(_main_static("cumbersome_active", [u], false))).is_false()


func test_rush_and_charge_are_refused_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var u := _unit_with(["Cumbersome"], "aof")
	for verb in [AiDecision.Action.RUSH, AiDecision.Action.CHARGE]:
		var why := str(_main_static("cumbersome_refusal", [u, verb], ""))
		assert_str(why).override_failure_message("rules 3.6: verb %d must be refused" % verb) \
			.contains("Cumbersome")


func test_rush_and_charge_stay_open_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var u := _unit_with(["Cumbersome"], "aof")
	for verb in [AiDecision.Action.RUSH, AiDecision.Action.CHARGE]:
		assert_str(str(_main_static("cumbersome_refusal", [u, verb], ""))).is_empty()


func test_advance_is_not_refused_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var u := _unit_with(["Cumbersome"], "gf")
	assert_str(str(_main_static("cumbersome_refusal", [u, AiDecision.Action.ADVANCE], ""))).is_empty()


# ===== the manual table: free drag, then Shoot (the real main.tscn, round 2) =====

## A human Cumbersome gunner (player 1) 8" from a foe at `epoch`; returns [gunner, foe].
func _boot_table(epoch: int) -> Array:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 2
	_main._solo_batch = true   # the harness lever for the dice tray: fair faces, drawn instantly
	AiActRecorder.rules_epoch = epoch
	var gunner := E2EBoot.make_unit(_main, 1, "Walker", [Vector3.ZERO])
	gunner.unit_properties.merge({"quality": 2, "special_rules": ["Cumbersome"],
		"game_system": "gf", "faction_folder": "some_book"}, true)
	var opr := OPRApiClient.OPRUnit.new()
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rifle"
	w.range_value = 24
	w.attacks = 8
	var ws: Array[OPRApiClient.OPRWeapon] = [w]
	opr.weapons = ws
	gunner.source_type = "opr"
	gunner.source_data = opr
	var foe := E2EBoot.make_unit(_main, 2, "Foe", [Vector3(8.0 * INCH, 0, 0)])
	_main.opr_army_manager.game_units[gunner.unit_id] = gunner
	_main.opr_army_manager.game_units[foe.unit_id] = foe
	return [gunner, foe]


## The gunner's drop of `inches` on the table: the free drag the manual table stamps moved_round from.
func _drop(unit: GameUnit, inches: float) -> void:
	await _main._on_units_dropped([{"node": (unit.models[0] as ModelInstance).node, "inches": inches}])


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func test_a_moved_cumbersome_human_unit_fires_no_volley_at_epoch_73(timeout := 240000) -> void:
	var t: Array = await _boot_table(AiActRecorder.EPOCH_73_V36)
	await _drop(t[0], 0.11)   # a hair over the 0.1" the table counts as a move
	await _main._run_human_shooting(t[0], t[1])
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("rules 3.6: the moved unit names the rule (log: %s)" % text.strip_edges()) \
		.contains("Cumbersome: Walker moved, so it cannot shoot this activation")
	assert_str(text) \
		.override_failure_message("rules 3.6: no volley is declared (log: %s)" % text.strip_edges()) \
		.not_contains("line of sight")
	await E2EBoot.settle(get_tree())


func test_a_cumbersome_human_unit_that_did_not_move_shoots_at_epoch_73(timeout := 240000) -> void:
	var t: Array = await _boot_table(AiActRecorder.EPOCH_73_V36)
	await _main._run_human_shooting(t[0], t[1])
	var text := _log_text()
	assert_str(text).override_failure_message("standing still keeps the shot (log: %s)" % text.strip_edges()) \
		.contains("line of sight")
	assert_str(text).not_contains("Cumbersome")
	await E2EBoot.settle(get_tree())


func test_a_moved_cumbersome_human_unit_still_shoots_at_epoch_72(timeout := 240000) -> void:
	var t: Array = await _boot_table(AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	await _drop(t[0], 0.11)
	await _main._run_human_shooting(t[0], t[1])
	var text := _log_text()
	assert_str(text).override_failure_message("rules 3.5: the shot stands (log: %s)" % text.strip_edges()) \
		.contains("line of sight")
	assert_str(text).not_contains("Cumbersome")
	await E2EBoot.settle(get_tree())
