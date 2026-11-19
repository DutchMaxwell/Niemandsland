extends GdUnitTestSuite
## AIG-G2 R5 (0.3.15): Unpredictable Shooter on a JOINED HERO's own gun never rolled its die. Both volleys (the AI's
## `_solo_resolve_ai_volley`, the human's `_run_human_shooting`) asked `_solo_unpredictable_rule(attacker)` on the HOST
## only, so a hero carrying the rule (aof duchies_of_vinci Zairetia, "Toxin Bellow") fired with no die and no log line.
## From EPOCH_73_V36 a hero who carries the rule himself, while his host rolls none, rolls ONE die for his own guns and
## the line names the book rule and the hero. A host that rolled keeps covering the whole unit exactly as before (one die
## per volley). Controls first (gdUnit drops cases declared after a failing one in a scene suite).

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


## A unit of the aof duchies_of_vinci book (the book that fields the rule) with one ranged weapon on its OPR source.
func _armed(pid: int, unit_name: String, positions: Array, rules: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	var i := 0
	for m in u.models:
		(m as ModelInstance).model_index = i
		i += 1
	u.unit_properties["game_system"] = "aof"
	u.unit_properties["faction_folder"] = "duchies_of_vinci"
	u.unit_properties["special_rules"] = rules
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Toxin Bellow"
	w.range_value = 24
	w.attacks = 2
	w.count = 1
	var src := OPRApiClient.OPRUnit.new()
	src.weapons = [w]
	u.source_type = "opr"
	u.source_data = src
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## A joined pair (host first): the host carries `host_rules`, the hero `hero_rules`; both fire a 24" gun.
func _pair(pid: int, host_rules: Array, hero_rules: Array) -> Array:
	var host := _armed(pid, "City Guard", [Vector3(0, 0, 3.0 * INCH), Vector3(0, 0, 5.0 * INCH)], host_rules)
	var hero := _armed(pid, "Zairetia", [Vector3(0, 0, 1.0 * INCH)], hero_rules)
	host.unit_properties["attached_heroes"] = [hero]
	hero.unit_properties["attached_to"] = host
	return [host, hero]


## Four models so a volley can never wipe the target: the case ends on the dice, not on destruction bookkeeping.
func _target(pid: int) -> GameUnit:
	var t := E2EBoot.make_unit(_main, pid, "Marked", [Vector3(10.0 * INCH, 0, -1.0 * INCH),
		Vector3(10.0 * INCH, 0, 0), Vector3(10.0 * INCH, 0, 1.0 * INCH), Vector3(10.0 * INCH, 0, 2.0 * INCH)])
	_main.opr_army_manager.game_units[t.unit_id] = t
	return t


## The human's volley reads the same chain: host without the rule, hero with it, the hero's gun rolls his die.
func test_the_human_volley_rolls_the_joined_heros_die_at_73() -> void:
	var pair := _pair(1, [], ["Unpredictable Shooter"])
	var target := _target(2)
	await _main._run_human_shooting(pair[0], target)
	var text := _log_text()
	assert_str(text).override_failure_message("the hero's own gun fired with no Unpredictable die (log: %s)" % text) \
		.contains("Unpredictable Shooter: Zairetia rolls")
