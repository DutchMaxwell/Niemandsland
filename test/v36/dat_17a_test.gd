extends GdUnitTestSuite
## DAT-17a — the table's half of the Regeneration Buff engine row. A granted
## Regeneration is a one-time grant: the first exchange that WOUNDS its holder
## spends it. The holder's own attack does not spend it, and a zero-wound
## exchange does not spend it either. Wounds that bypass Regeneration still
## count as wounding the holder. The once-spend must skip Regeneration grants
## that are not `used`, and name the spend in the battle log. RED first — the
## table spends every once-record unconditionally today.

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
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _unit(pid: int, unit_name: String, pos: Vector3) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [pos])
	u.unit_properties["special_rules"] = []
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _records_on(u: GameUnit) -> Array:
	return _main._solo_spell_mods.get(u.get_instance_id(), [])


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## The exporter's shape of the Regeneration Buff: a granted "Regeneration",
## once. `used` is the flag the exchange sets when it wounds the holder.
func _record_regen(u: GameUnit, used: bool) -> void:
	_main._solo_record_spell_mod(u, "Regeneration Buff", {
		"spell": "Regeneration Buff",
		"grants_rule": "Regeneration",
		"beneficiary": "",
		"duration": "once",
		"scope": "",
		"used": used,
	})


func test_a_regeneration_grant_not_marked_used_survives_a_spend_call() -> void:
	var holder := _unit(2, "Holder", Vector3.ZERO)
	var attacker := _unit(1, "Attacker", Vector3(2.0 * 0.0254, 0, 0))
	_record_regen(holder, false)
	_main._solo_consume_once_mods(attacker, holder, true)
	assert_array(_records_on(holder)) \
		.override_failure_message("a zero-wound exchange must leave the Regeneration grant in place; log: %s" % _log_text().strip_edges()) \
		.has_size(1)


func test_a_regeneration_grant_marked_used_is_spent_and_names_itself() -> void:
	var holder := _unit(2, "Holder", Vector3.ZERO)
	var attacker := _unit(1, "Attacker", Vector3(2.0 * 0.0254, 0, 0))
	_record_regen(holder, true)
	_main._solo_consume_once_mods(attacker, holder, true)
	assert_array(_records_on(holder)).is_empty()
	assert_str(_log_text()) \
		.override_failure_message("the spend must name the Regeneration grant; log: %s" % _log_text().strip_edges()) \
		.contains("Regeneration Buff")


func test_the_holders_own_attack_does_not_spend_its_regeneration_grant() -> void:
	var holder := _unit(2, "Holder", Vector3.ZERO)
	var target := _unit(1, "Target", Vector3(2.0 * 0.0254, 0, 0))
	_record_regen(holder, false)
	_main._solo_consume_once_mods(holder, target, true)
	assert_array(_records_on(holder)) \
		.override_failure_message("the holder's own attack must not spend its Regeneration grant; log: %s" % _log_text().strip_edges()) \
		.has_size(1)
