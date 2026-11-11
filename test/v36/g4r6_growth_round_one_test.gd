extends GdUnitTestSuite
## G4R6 R22 (0.3.15): a per-round Growth rule (Precision / Piercing / Fortified Growth) places its marker at the start of EACH
## round the unit is on the table and not Shaken, round 1 included. The table's sweep (`_solo_growth_round_start`) ran from
## round 2 only, so every carrier was one marker behind the book at every round, and the core (which ticks a joined hero a
## second time) only matched it by accident. From EPOCH_73_V36 the sweep also runs at the opening of round 1 -- in the human-
## vs-AI opening (`_solo_ensure_playing_phase`) and in the both-AI opening (`_solo_both_ai_opening`) -- BEFORE the Rapid Ambush
## arrivals, like every later round's order (growth, then arrivals). The Rust twin is `a_joined_heros_ticked_marker_is_not_
## ticked_again_at_the_hosts_activation`. Controls first (gdUnit drops cases declared after a failing one in a scene suite).

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
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.DEPLOYMENT
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


## A unit of `faction` carrying `rules`, registered on the table (the sweep walks the army manager's units).
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

## Below the 3.6 epoch the table keeps its old reading: the opening places nothing.
func test_below_73_the_opening_places_no_marker() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var u := _unit(2, "Hive Warrior", Vector3.ZERO, "gf", "alien_hives", ["Piercing Growth"])
	_main._solo_ensure_playing_phase()
	assert_int(_markers(u, "growth_piercing_growth")).is_equal(0)
	assert_str(_log_text()).not_contains("Hive Warrior gains a marker")


## A unit with no Growth rule gets no marker and no log line from the opening.
func test_a_unit_without_a_growth_rule_gets_nothing() -> void:
	var u := _unit(2, "Hive Warrior", Vector3.ZERO, "gf", "alien_hives", [])
	_main._solo_ensure_playing_phase()
	assert_int(_markers(u, "growth_piercing_growth")).is_equal(0)
	assert_str(_log_text()).not_contains("gains a marker")


## The opening is ONE sweep: once the game is PLAYING a later call of the playing-phase seam (every activation makes one)
## adds nothing, so round 1 never runs the sweep twice.
func test_the_playing_phase_seam_sweeps_once_not_per_call() -> void:
	var u := _unit(2, "Hive Warrior", Vector3.ZERO, "gf", "alien_hives", ["Piercing Growth"])
	_main._solo_ensure_playing_phase()
	var after_first := _markers(u, "growth_piercing_growth")
	_main._solo_ensure_playing_phase()
	assert_int(_markers(u, "growth_piercing_growth")) \
		.override_failure_message("a second call of the seam ticked again (log: %s)" % _log_text()).is_equal(after_first)


# ===== the fix (RED before) =====

## Human-vs-AI opening: a carrier has 1 marker before anyone acts in round 1, the log names the book rule; round 2's sweep makes 2.
func test_the_human_vs_ai_opening_places_the_round_one_marker_at_73() -> void:
	var u := _unit(2, "Hive Warrior", Vector3.ZERO, "gf", "alien_hives", ["Piercing Growth"])
	_main._solo_ensure_playing_phase()
	assert_int(_markers(u, "growth_piercing_growth")) \
		.override_failure_message("no round-1 marker after the opening (log: %s)" % _log_text()).is_equal(1)
	assert_str(_log_text()).contains("Piercing Growth: Hive Warrior gains a marker (1/4)")
	_main._solo_growth_round_start()   # the round-2 sweep both round starts make
	assert_int(_markers(u, "growth_piercing_growth")).is_equal(2)
	assert_str(_log_text()).contains("Piercing Growth: Hive Warrior gains a marker (2/4)")


## Both-AI opening: the same one marker, placed before the Rapid Ambush arrivals.
func test_the_both_ai_opening_places_the_round_one_marker_at_73() -> void:
	# A missing seam must be a clean RED, never a debugger break that takes the whole shard down.
	assert_bool(_main.has_method("_solo_both_ai_opening")) \
		.override_failure_message("the both-AI loop has no opening seam that sweeps round 1's Growth markers").is_true()
	if not _main.has_method("_solo_both_ai_opening"):
		return
	var u := _unit(2, "Hive Warrior", Vector3.ZERO, "gf", "alien_hives", ["Piercing Growth"])
	await _main._solo_both_ai_opening()
	assert_int(_markers(u, "growth_piercing_growth")) \
		.override_failure_message("no round-1 marker after the both-AI opening (log: %s)" % _log_text()).is_equal(1)
	assert_str(_log_text()).contains("Piercing Growth: Hive Warrior gains a marker (1/4)")


## A joined hero ticks at the opening too, on his own rule; the host (no rule) gets none.
func test_a_joined_hero_gains_his_round_one_marker_at_73() -> void:
	var pair := _pair("aof", "daemons_of_plague", ["Fortified Growth"])
	_main._solo_ensure_playing_phase()
	assert_int(_markers(pair[1], "growth_fortified_growth")) \
		.override_failure_message("the joined hero's round-1 marker never arrived (log: %s)" % _log_text()).is_equal(1)
	assert_int(_markers(pair[0], "growth_fortified_growth")).is_equal(0)
	assert_str(_log_text()).contains("Fortified Growth: Champion of Plague gains a marker (1/4)")
