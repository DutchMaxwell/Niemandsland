extends GdUnitTestSuite
## AIG-G2 R2 (0.3.15): the Growth-Marker rules (Fortified Growth, Defensive Frenzy, Piercing Growth) never ticked for a
## JOINED hero. `_solo_growth_round_start` skipped every attached unit and the host does not carry the hero's rule, so the
## round marker never arrived (aof_1000_net_004: Champion of Plague, 0 of 4 expected lines); the on-kill accrual asked the
## attacker (the host) only. Lead ruling: the marker belongs to the HERO; its effect applies where the hero's own values are
## read (his attacks, his saves once he stands alone), never to the host's models. From EPOCH_73_V36 the round tick and the
## kill credit reach a living joined hero who carries the rule, and the line names the book rule and the hero. Controls
## first (gdUnit drops cases declared after a failing one in a scene suite).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch_before := 0


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_epoch_before = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	RulesRegistry.reset_cache()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	RulesRegistry.reset_cache()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## A unit of `faction` carrying `rules`, registered on the table (the round tick walks the army manager's units).
func _unit(pid: int, unit_name: String, pos: Vector3, system: String, faction: String, rules: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [pos])
	u.unit_properties["game_system"] = system
	u.unit_properties["faction_folder"] = faction
	u.unit_properties["special_rules"] = rules
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## A host and a joined hero (the hero carries `hero_rules`, the host none), the way the import attaches them.
func _pair(system: String, faction: String, hero_rules: Array) -> Array:
	var host := _unit(2, "Plague Host", Vector3.ZERO, system, faction, [])
	var hero := _unit(2, "Champion of Plague", Vector3(2.0 * INCH, 0, 0), system, faction, hero_rules)
	host.unit_properties["attached_heroes"] = [hero]
	hero.unit_properties["attached_to"] = host
	return [host, hero]


func _markers(u: GameUnit, key: String) -> int:
	return int(u.unit_properties.get(key, 0))


# ===== controls (green before and after the fix) =====

## A standalone carrier ticks and the line names the book rule: the long-standing behaviour.
func test_a_standalone_carrier_gains_its_round_marker() -> void:
	var u := _unit(2, "Champion of Plague", Vector3.ZERO, "aof", "daemons_of_plague", ["Fortified Growth"])
	_main._solo_growth_round_start()
	assert_int(_markers(u, "growth_fortified_growth")).is_equal(1)
	assert_str(_log_text()).contains("Fortified Growth: Champion of Plague gains a marker (1/4)")


## The host never inherits the hero's rule: no marker on the host, whatever the hero does.
func test_the_host_gains_no_marker_from_its_heros_rule() -> void:
	var pair := _pair("aof", "daemons_of_plague", ["Fortified Growth"])
	_main._solo_growth_round_start()
	assert_int(_markers(pair[0], "growth_fortified_growth")).is_equal(0)


## Below the 3.6 epoch the attached skip stands byte for byte: the hero's marker never arrives.
func test_below_73_a_joined_hero_gains_no_marker() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var pair := _pair("aof", "daemons_of_plague", ["Fortified Growth"])
	_main._solo_growth_round_start()
	assert_int(_markers(pair[1], "growth_fortified_growth")).is_equal(0)
	assert_str(_log_text()).not_contains("Champion of Plague gains a marker")


# ===== the fix (RED before) =====

## aof_1000_net_004: Champion of Plague joined to a host, Fortified Growth at the round start.
func test_a_joined_hero_gains_his_round_marker_at_73() -> void:
	var pair := _pair("aof", "daemons_of_plague", ["Fortified Growth"])
	_main._solo_growth_round_start()
	assert_int(_markers(pair[1], "growth_fortified_growth")) \
		.override_failure_message("the joined hero's round marker never arrived (log: %s)" % _log_text()).is_equal(1)
	assert_str(_log_text()).contains("Fortified Growth: Champion of Plague gains a marker (1/4)")


## Piercing Growth (gf alien_hives): after two round ticks the HERO's own attack reads AP(+1); the host's does not.
func test_a_joined_heros_piercing_growth_reaches_his_own_attacks_at_73() -> void:
	var pair := _pair("gf", "alien_hives", ["Piercing Growth"])
	_main._solo_growth_round_start()
	_main._solo_growth_round_start()
	assert_int(int(_main._solo_growth_attack_bonus(pair[1])["ap"])) \
		.override_failure_message("two markers must read AP(+1) on the hero's own attack (log: %s)" % _log_text()).is_equal(1)
	assert_int(int(_main._solo_growth_attack_bonus(pair[0])["ap"])).is_equal(0)
	assert_str(_log_text()).contains("Piercing Growth: Champion of Plague gains a marker (2/4)")


## Defensive Frenzy (gf daemons_of_war): the chain's kill credits the hero who carries the rule.
func test_a_joined_heros_defensive_frenzy_counts_the_chains_kill_at_73() -> void:
	var pair := _pair("gf", "daemons_of_war", ["Defensive Frenzy"])
	_main._solo_growth_on_kill(pair[0])
	assert_int(_markers(pair[1], "growth_defensive_frenzy")) \
		.override_failure_message("the kill never reached the joined hero's rule (log: %s)" % _log_text()).is_equal(1)
	assert_str(_log_text()).contains("Defensive Frenzy: Champion of Plague gains a marker for the kill (1/2)")
	assert_int(_markers(pair[0], "growth_defensive_frenzy")).is_equal(0)
