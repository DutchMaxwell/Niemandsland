extends GdUnitTestSuite
## AIG-G2 R2 (0.3.15): the Growth-Marker rules (Fortified Growth, Defensive Frenzy, Piercing Growth) never ticked for a
## JOINED hero. `_solo_growth_round_start` skipped every attached unit and the host does not carry the hero's rule, so the
## round marker never arrived (aof_1000_net_004: Champion of Plague, 0 of 4 expected lines); the on-kill accrual asked the
## attacker (the host) only. Lead ruling: the marker belongs to the HERO; its effect applies where the hero's own values are
## read (his attacks, his saves once he stands alone), never to the host's models. From EPOCH_73_V36 the round tick and the
## kill credit reach a living joined hero who carries the rule, and the line names the book rule and the hero. Controls
## first (gdUnit drops cases declared after a failing one in a scene suite).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const INCH := 0.0254
const PG_DICE := "user://aig2_r2_growth_dice"

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
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
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

## The game's own call: the core door takes the AI's volley (the board is captured first), as the lone-hero door suite does.
## The epoch is the live one: the table's epoch-73 gates are the core's from its own epochs on.
func _door_ai(report: Dictionary) -> void:
	AiActRecorder.rules_epoch = _epoch_before
	CoreActivation._env = 1
	var runs := CoreActivation.ai_runs
	_main._solo_core_ai_h = CoreActivation.capture(_main)
	await _main._run_ai_shooting(report)
	assert_int(CoreActivation.ai_runs).override_failure_message("the core did not take the volley (the table shot it)") \
		.is_equal(runs + 1)
	if _main._solo_core_ai_h != 0:
		_main.solo_controller._core_node_ready().release(_main._solo_core_ai_h)
	_main._solo_core_ai_h = 0


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


## A real statline as an OPRUnit (the AI volley reads the importer's own weapons); `wname` "" = none.
func _opr_entry(n: String, size: int, rules: Array, wname: String) -> Dictionary:
	var ou := OPRApiClient.OPRUnit.new()
	ou.name = n
	ou.size = size
	ou.quality = 5
	ou.defense = 3
	ou.game_system = "gf"
	ou.special_rules.assign(rules)
	if wname != "":
		var w := OPRApiClient.OPRWeapon.new()
		w.name = wname
		w.range_value = 12
		w.attacks = 4 if wname == "Spine Shooter" else 3
		w.count = 3 if wname == "Spine Shooter" else 1
		w.special_rules.assign(["AP(1)"] if wname == "Spine Shooter" else [])
		ou.weapons.append(w)
	return {"unit": ou, "faction": "alien_hives", "system": "gf"}


## DS-PG: the carrier's Growth AP reaches the carrier's OWN attacks in the AI volley BODY, as the core folds it
## (sim.rs:4403 growth_bonus_of into dice.rs:1715) and the human/melee path already did (main.gd:6979). RED: the
## joined hero's own gun saves at the target's printed Defense (3+) again.
func test_a_joined_heros_piercing_growth_reaches_the_ai_volley_at_73() -> void:
	var host := RosterSweep.spawn(_main, _opr_entry("DS-PG Host", 3, [], "Spine Shooter"), RosterSweep.SEAT_SHOOTER, 0.0)
	var hero := RosterSweep.spawn(_main, _opr_entry("DS-PG Hero", 1, ["Hero", "Piercing Growth"], "Veteran Bio-Borer"),
		RosterSweep.SEAT_SHOOTER, 0.0)
	host.unit_properties["attached_heroes"] = [hero]
	hero.unit_properties["attached_to"] = host
	hero.unit_properties["growth_piercing_growth"] = 2
	var tgt := RosterSweep.spawn(_main, _opr_entry("DS-PG Target", 10, [], ""), RosterSweep.SEAT_TARGET, 9.0)
	RosterSweep.arm(_main, ProjectSettings.globalize_path(PG_DICE))
	_main.seed_tray_rng(0)
	await _door_ai({"unit": host, "moved": false, "action": AiDecision.Action.HOLD})
	AiDiceRecorder.close()
	var rolls: Array = ParityTable._read_dice(ProjectSettings.globalize_path(PG_DICE))
	var saves: Array = rolls.filter(func(x: Dictionary) -> bool: return str(x["kind"]) == "defense").map(
		func(x: Dictionary) -> int: return int(x["target"]))
	var log_text := _log_text()
	RosterSweep.free_units(_main, [host, hero, tgt])
	RosterSweep.disarm(_main)
	assert_array(saves).override_failure_message("host AP(1) and hero AP(+1) save at 4+ (saves: %s)" % str(saves)).contains_exactly([4, 4])
	assert_str(log_text).contains("Piercing Growth: DS-PG Hero adds AP(+1) from its growth markers")
