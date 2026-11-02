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
var _epoch_before: int


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch
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
	AiActRecorder.rules_epoch = _epoch_before
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


## The live grant push, with no stamp: _solo_record_spell_mod is the same mechanical
## entry a real once spell uses, so the `used` field stays whatever the engine sets.
func _grant_regen(u: GameUnit) -> void:
	_main._solo_record_spell_mod(u, "Regeneration Buff", {
		"spell": "Regeneration Buff",
		"grants_rule": "Regeneration",
		"beneficiary": "",
		"duration": "once",
		"scope": "",
	})


## A tray seed whose first `count` batch faces all meet the 5+ Regeneration target
## (the batch tray draws its faces from the tray RNG, in order).
func _all_ignored_seed(count: int) -> int:
	var rng := RandomNumberGenerator.new()
	for s in 4000:
		rng.seed = s
		var all := true
		for _i in count:
			if rng.randi_range(1, 6) < 5:
				all = false
				break
		if all:
			return s
	return -1


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


## DAT-17a follow-up: from epoch 73 the grant is spent by the FIRST exchange that
## brings a wound in, so an all-ignored Regeneration roll still spends it. The
## grant lands through the live record builder and the mark comes from the real
## landing path, never a hand-set `used` field.
func test_an_all_ignored_exchange_spends_the_grant_at_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var holder := _unit(2, "Holder", Vector3.ZERO)
	var attacker := _unit(1, "Attacker", Vector3(2.0 * 0.0254, 0, 0))
	_grant_regen(holder)
	_main.solo_ai_slots = {2: true}
	_main._solo_batch = true
	_main.seed_tray_rng(_all_ignored_seed(3))
	var landed: int = await _main._solo_land_wounds(holder, 3, 0)
	assert_int(landed) \
		.override_failure_message("fixture: the Regeneration roll must ignore every wound; log: %s" % _log_text().strip_edges()) \
		.is_equal(0)
	assert_array(_records_on(holder)) \
		.override_failure_message("the incoming wounds must leave the grant marked for the spend; log: %s" % _log_text().strip_edges()) \
		.has_size(1)
	assert_bool(bool(_records_on(holder)[0].get("used", false))) \
		.override_failure_message("an all-ignored roll still spends the grant: the landing must mark it used; log: %s" % _log_text().strip_edges()) \
		.is_true()
	_main._solo_consume_once_mods(attacker, holder, true)
	assert_array(_records_on(holder)) \
		.override_failure_message("the marked grant must be gone after the exchange; log: %s" % _log_text().strip_edges()) \
		.is_empty()


## CONTROL below 73: the landing path adds no extra mark. The old unconditional
## exchange spend stays the only path there, so a recorded replay keeps its exact
## buff list.
func test_an_all_ignored_landing_adds_no_mark_at_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var holder := _unit(2, "Holder", Vector3.ZERO)
	_grant_regen(holder)
	_main.solo_ai_slots = {2: true}
	_main._solo_batch = true
	_main.seed_tray_rng(_all_ignored_seed(3))
	var landed: int = await _main._solo_land_wounds(holder, 3, 0)
	assert_int(landed) \
		.override_failure_message("fixture: the Regeneration roll must ignore every wound; log: %s" % _log_text().strip_edges()) \
		.is_equal(0)
	assert_array(_records_on(holder)) \
		.override_failure_message("below 73 the landing must not spend the grant; log: %s" % _log_text().strip_edges()) \
		.has_size(1)
	assert_bool(bool(_records_on(holder)[0].get("used", false))) \
		.override_failure_message("below 73 the landing must add no extra mark; log: %s" % _log_text().strip_edges()) \
		.is_false()


## A zero-incoming exchange leaves the grant in place at 73: Regeneration was
## never asked to turn a wound away.
func test_a_zero_incoming_exchange_keeps_the_grant_at_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var holder := _unit(2, "Holder", Vector3.ZERO)
	var attacker := _unit(1, "Attacker", Vector3(2.0 * 0.0254, 0, 0))
	_grant_regen(holder)
	var landed: int = await _main._solo_land_wounds(holder, 0, 0)
	assert_int(landed).is_equal(0)
	_main._solo_consume_once_mods(attacker, holder, true)
	assert_array(_records_on(holder)) \
		.override_failure_message("a zero-incoming exchange must keep the grant at 73; log: %s" % _log_text().strip_edges()) \
		.has_size(1)
