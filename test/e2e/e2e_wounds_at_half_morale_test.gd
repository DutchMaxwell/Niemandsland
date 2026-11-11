extends GdUnitTestSuite
## E2E — play test 29.10.2026 (audit A2): a unit at half strength or less that took wounds but lost no
## model skipped its morale test.
##
## GF/AoF Advanced Rules v3.5.1 p.10: at the end of an activation in which a unit takes WOUNDS that leave
## it with half or less of its starting size, it must take a morale test. The p.14 hero example says the
## same from the other side: the last hero of a unit tests whenever it takes wounds. The table's
## multi-model trigger (`AiCombatMath.should_test_shooting_morale`) only fired when the alive count
## dropped, so wounds on a surviving Tough model of a halved unit never tested.
## These cases ride the real spell-damage resolution on scenes/main.tscn (save roll, wound landing,
## morale hook), with an AI-owned target so every die auto-rolls.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const TOUGH := 6

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


func _caster() -> GameUnit:
	var c := E2EBoot.make_unit(_main, 1, "Mystic", [Vector3.ZERO])
	var opr := OPRApiClient.OPRUnit.new()
	var ws: Array[OPRApiClient.OPRWeapon] = []
	opr.weapons = ws
	c.source_type = "opr"
	c.source_data = opr
	_main.opr_army_manager.game_units[c.unit_id] = c
	return c


## An AI-owned unit of four Tough(6) models, `dead` of them already removed (starting size stays 4).
func _brutes(dead: int) -> GameUnit:
	var positions: Array = []
	for i in range(4):
		positions.append(Vector3(6.0 * INCH, 0, 0.03 * i))
	var u := E2EBoot.make_unit(_main, 2, "Brutes", positions)
	u.unit_properties["tough"] = TOUGH
	for i in range(u.models.size()):
		var m := u.models[i] as ModelInstance
		m.wounds_max = TOUGH
		m.wounds_current = TOUGH
		if i < dead:
			m.is_alive = false
			m.wounds_current = 0
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## Three AP(4) spell hits: Defense 4+ saves only on natural 6s, so wounds land, and three wounds can
## never kill a fresh Tough(6) model.
func _cast_at(foe: GameUnit) -> Dictionary:
	var caster := _caster()
	var alive_before: int = foe.get_alive_count()
	var wounds_before: int = _main._solo_unit_wounds_now(foe)
	var entry := {"effect": {"kind": "damage", "hits": 3, "weapon_rules": ["AP(4)"]},
		"target": {"kind": "unit", "side": "enemy"}}
	_main.seed_tray_rng(11)
	await _main._solo_resolve_spell_damage(caster, caster, "Test Bolt", entry, foe)
	var out := {"text": _log_text(), "alive_lost": alive_before - foe.get_alive_count(),
		"wounds_taken": wounds_before - _main._solo_unit_wounds_now(foe)}
	await E2EBoot.settle(get_tree())
	return out


## The claim: 2 of 4 models left (half), wounds land on a Tough model, nobody dies — morale test.
func test_wounds_at_half_strength_without_a_loss_take_the_morale_test() -> void:
	var foe := _brutes(2)
	var r: Dictionary = await _cast_at(foe)
	var text := str(r["text"])
	# Fixture preconditions, named so a drifting seed fails loudly instead of passing silently.
	assert_int(int(r["wounds_taken"])).override_failure_message("fixture: no wound landed (log: %s)" % text).is_greater(0)
	assert_int(int(r["alive_lost"])).override_failure_message("fixture: a model died (log: %s)" % text).is_equal(0)
	assert_str(text) \
		.override_failure_message("A2 — wounds left the unit at half strength, so it must test morale (log: %s)" % text.strip_edges()) \
		.contains("Brutes takes wounds at half strength or less (2/4 models) — morale test")
	assert_bool(text.contains("Brutes passes morale") or text.contains("Brutes fails morale")) \
		.override_failure_message("A2 — the morale test was announced but never rolled (log: %s)" % text.strip_edges()) \
		.is_true()


## CONTROL: the same wounds on a unit above half strength (3 of 4 left) cause no test.
func test_wounds_above_half_strength_take_no_morale_test() -> void:
	var foe := _brutes(1)
	var r: Dictionary = await _cast_at(foe)
	var text := str(r["text"])
	assert_int(int(r["wounds_taken"])).override_failure_message("fixture: no wound landed (log: %s)" % text).is_greater(0)
	assert_int(int(r["alive_lost"])).is_equal(0)
	assert_str(text).not_contains("morale")
