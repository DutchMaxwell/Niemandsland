extends GdUnitTestSuite
## E2E — NML-940: Retaliate(X) ("when this model takes a wound in melee, the attacker takes X hits
## per wound taken", v3.5.3) never fired for Deadly(X) melee wounds. Deadly lands INSIDE the weapon
## loop of _solo_melee_strike_phase (its own per-model landing, no carry-over), while the Retaliate
## pool snapshot and the `landed_on_defender` gate sat AFTER the loop — so the wounds Deadly dealt
## were invisible to the lash-back. The Rust core already measures it right (sim.rs: pool snapshot
## before both landings), so this is a table-only defect.
##
## No assertion sits behind a single die: 80 attacks at Quality 4+ into Defense 4+ leave ~20 unsaved
## wounds, so "no wound landed" is a ~1e-10 event; the asserts read the LOG, written after the dice.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	# BOTH sides AI: a human striker's Retaliate saves wait on the player's own tray, which headless never settles.
	_main.solo_ai_slots = {1: true, 2: true}
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


## One striker with a single MELEE weapon of 80 attacks carrying `weapon_rules` (the shape
## _solo_attack_groups reads — see e2e_unstoppable_melee_test).
func _striker(weapon_rules: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, 1, "Brawlers", [Vector3.ZERO])
	(u.models[0] as ModelInstance).model_index = 0
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Runeblade"
	w.range_value = 0
	w.attacks = 80
	w.count = 1
	var rules: Array[String] = []
	for r in weapon_rules:
		rules.append(str(r))
	w.special_rules = rules
	var src := OPRApiClient.OPRUnit.new()
	src.weapons = [w]
	u.source_type = "opr"
	u.source_data = src
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## A Retaliate(3) squad of 6 Tough(3) models, real emitted gf map (alien_hives fields Retaliate).
func _retaliator() -> GameUnit:
	var positions: Array = []
	for i in range(6):
		positions.append(Vector3(0.03 * i, 0.0, 0.05))
	var u := E2EBoot.make_unit(_main, 2, "Klauenbrut", positions)
	for i in range(u.models.size()):
		var m := u.models[i] as ModelInstance
		m.model_index = i
		m.wounds_max = 3
		m.wounds_current = 3
	u.unit_properties["special_rules"] = ["Retaliate(3)"]
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["faction_folder"] = "alien_hives"
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func test_a_deadly_melee_weapon_triggers_retaliate(timeout := 240000) -> void:
	var striker := _striker(["Deadly(3)"])
	var foe := _retaliator()
	assert_bool(RulesRegistry.unit_rule_active(foe, "Retaliate")) \
		.override_failure_message("fixture: the emitted gf map must field Retaliate for alien_hives") \
		.is_true()
	await _main._solo_melee_strike_phase(striker, foe, false, 0)   # 0 = SoloStrike.ALL
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("fixture: the Deadly weapon must land wounds on the foe (log: %s)" % text.strip_edges()) \
		.contains("Deadly(3)")
	assert_str(text) \
		.override_failure_message("NML-940 — Deadly wounds were TAKEN, so Retaliate must lash back (log: %s)" % text.strip_edges()) \
		.contains("Retaliate: Klauenbrut lashes back")
	await E2EBoot.settle(get_tree())


func test_a_plain_melee_weapon_still_triggers_retaliate(timeout := 240000) -> void:
	# The counter-probe: the pooled path always worked — this keeps the fixture honest (the foe
	# really carries Retaliate, the strike really wounds) and pins the pooled behaviour across the fix.
	var striker := _striker([])
	var foe := _retaliator()
	await _main._solo_melee_strike_phase(striker, foe, false, 0)
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("fixture broken: a plain melee strike must trigger Retaliate (log: %s)" % text.strip_edges()) \
		.contains("Retaliate: Klauenbrut lashes back")
	assert_str(text) \
		.override_failure_message("no Deadly weapon in the fixture — the log may not claim it (log: %s)" % text.strip_edges()) \
		.not_contains("Deadly(")
	await E2EBoot.settle(get_tree())
