extends GdUnitTestSuite
## W31-F5a1 (release 0.3.15): rules the table dropped in books that field them without a mechanics row. The
## "is it automated?" test reads the static `modeled` list for every book, while every reader below asks the
## registry PER BOOK, so a book with no row neither applied the rule nor told the player to do it by hand.
## Each case builds a unit of the book the way the army import writes it (system + faction slug + the unit's own
## rules), drives the table's own reader and asserts the effect AND the battle-log line that names the BOOK rule.
## Every rule has a control book that already had its row. Rust twin:
## `core/nml-core/src/tests/unit/v36_data_rows/f5a1_rows.rs`.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const IN2M := 0.0254
## Base-edge to base-edge ranges (B11): a centre offset carries both default base radii (0.016 m) on top.
const EDGE_SLACK_IN := 2.0 * 0.016 / IN2M

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	RulesRegistry.reset_cache()
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
	await E2EBoot.settle(get_tree())
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	AiActRecorder.rules_epoch = _epoch0
	RulesRegistry.reset_cache()


## A unit of `faction` carrying `rules`, with one ranged weapon on its OPR source (what _solo_log_range_bonus reads).
func _unit(pid: int, unit_name: String, pos: Vector3, system: String, faction: String, rules: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [pos])
	u.unit_properties["quality"] = 4
	u.unit_properties["game_system"] = system
	u.unit_properties["faction_folder"] = faction
	u.unit_properties["special_rules"] = rules
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rifle"
	w.range_value = 24
	w.attacks = 2
	w.count = 1
	var src := OPRApiClient.OPRUnit.new()
	src.weapons = [w]
	u.source_type = "opr"
	u.source_data = src
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _x_for_gap(gap_in: float) -> float:
	return (gap_in + EDGE_SLACK_IN) * IN2M


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## The reach line a gunner of `faction` prints against a target 26" away: the rule's own book name and +6".
func _range_line(faction: String, rules: Array) -> String:
	var gunner := _unit(1, "Gunner", Vector3.ZERO, "gf", faction, rules)
	var target := _unit(2, "Target", Vector3(_x_for_gap(26.0), 0, 0), "gf", faction, [])
	assert_int(SoloController.shooting_range_bonus(gunner)) \
		.override_failure_message("gf/%s %s: the +6\" reach silently dropped" % [faction, rules]).is_equal(6)
	_main._solo_log_range_bonus(gunner, target)
	return _log_text()


func test_range_control_alien_hives_aura_and_base() -> void:
	assert_str(_range_line("alien_hives", ["Increased Shooting Range Aura", "Increased Shooting Range"])) \
		.contains("Increased Shooting Range Aura +6\" shooting range")


func test_increased_shooting_range_aura_names_itself_in_elven_jesters() -> void:
	assert_str(_range_line("elven_jesters", ["Increased Shooting Range Aura", "Increased Shooting Range"])) \
		.contains("Increased Shooting Range Aura +6\" shooting range")


func test_the_granted_base_alone_reaches_six_inches_in_elven_jesters() -> void:
	assert_str(_range_line("elven_jesters", ["Increased Shooting Range"])) \
		.contains("Increased Shooting Range +6\" shooting range")


func test_increased_shooting_range_reaches_six_inches_in_blessed_sisters() -> void:
	assert_str(_range_line("blessed_sisters", ["Increased Shooting Range"])) \
		.contains("Increased Shooting Range +6\" shooting range")


## Takedown Shot: the once-per-game extra attack joins the volley and the log names the book rule.
func _takedown_log(faction: String) -> String:
	var u := _unit(2, "Shooter", Vector3.ZERO, "gf", faction, ["Takedown Shot"])
	var groups: Array = _main._solo_takedown_bonus_groups(u, false)
	assert_int(groups.size()) \
		.override_failure_message("gf/%s: Takedown Shot silently dropped (no extra attack)" % faction).is_equal(1)
	return _log_text()


func test_takedown_shot_control_human_inquisition() -> void:
	assert_str(_takedown_log("human_inquisition")).contains("Takedown Shot: Shooter makes one extra attack")


func test_takedown_shot_makes_its_extra_attack_in_elven_jesters() -> void:
	assert_str(_takedown_log("elven_jesters")).contains("Takedown Shot: Shooter makes one extra attack")


## Piercing Target: the AI marks an enemy within 18" and the log names the book rule.
func _piercing_target_log(faction: String) -> String:
	var spotter := _unit(2, "Watcher", Vector3.ZERO, "gf", faction, ["Piercing Target"])
	_unit(1, "Marked", Vector3(10.0 * IN2M, 0, 0), "gf", "alien_hives", [])
	_main.opr_army_manager.current_round = 1
	await _main._solo_apply_piercing_tag(spotter)
	return _log_text()


func test_piercing_target_control_custodian_brothers() -> void:
	assert_str(await _piercing_target_log("custodian_brothers")).contains("Piercing Target: Watcher places 1 token")


func test_piercing_target_places_its_token_in_alien_hives() -> void:
	var text: String = await _piercing_target_log("alien_hives")
	assert_str(text).override_failure_message("gf/alien_hives: Piercing Target silently dropped (log: %s)" % text) \
		.contains("Piercing Target: Watcher places 1 token")


## Melee Slayer: AP(+2) on a charge against Tough(3)+; the named part is what the strike's log prints.
func _slayer_parts(faction: String) -> Array:
	var striker := _unit(2, "Charger", Vector3.ZERO, "gf", faction, ["Melee Slayer"])
	var target := _unit(1, "Brute", Vector3(2.0 * IN2M, 0, 0), "gf", "alien_hives", ["Tough(6)"])
	return _main._solo_conditional_ap_parts({"name": "Blade", "range": 0, "rules": []}, striker, target, true, 2.0, true)


func test_melee_slayer_control_blood_prime_brothers() -> void:
	assert_array(_slayer_parts("blood_prime_brothers")).is_equal([{"name": "Melee Slayer", "bonus": 2}])


func test_melee_slayer_adds_its_ap_in_lust_disciples() -> void:
	assert_array(_slayer_parts("lust_disciples")) \
		.override_failure_message("gf/lust_disciples: Melee Slayer silently dropped") \
		.is_equal([{"name": "Melee Slayer", "bonus": 2}])


## Hit & Run: the step pick names the family member the unit carries (the callers log that name).
func _hit_and_run_pick(system: String, faction: String) -> String:
	var u := _unit(2, "Skirmisher", Vector3.ZERO, system, faction, ["Hit & Run"])
	return _main.solo_controller._hit_and_run_pick(u, true)


func test_hit_and_run_control_custodian_brothers() -> void:
	assert_str(_hit_and_run_pick("gf", "custodian_brothers")).is_equal("Hit & Run")


func test_hit_and_run_steps_in_high_elves() -> void:
	assert_str(_hit_and_run_pick("aof", "high_elves")) \
		.override_failure_message("aof/high_elves: Hit & Run silently dropped").is_equal("Hit & Run")


## Primeborn: the real save batch cuts the incoming AP by one and the log line names the book rule.
func _primeborn_log(faction: String) -> String:
	var defender := _unit(1, "Wolf Pack", Vector3.ZERO, "gf", faction, ["Primeborn"])
	var striker := _unit(2, "Raiders", Vector3(0.5, 0.0, 0.5), "gf", "alien_hives", [])
	await _main._solo_save_batch(striker, defender, "Rifle", 3, 4, 2, {"name": "Rifle", "ap": 2, "deadly": 0, "rules": []}, false, false)
	return _log_text()


func test_primeborn_control_prime_brothers() -> void:
	assert_str(await _primeborn_log("prime_brothers")).contains("Primeborn: Wolf Pack takes the hits at AP(1) instead of AP(2)")


func test_primeborn_cuts_incoming_ap_in_wolf_prime_brothers() -> void:
	var text: String = await _primeborn_log("wolf_prime_brothers")
	assert_str(text).override_failure_message("gf/wolf_prime_brothers: Primeborn silently dropped (log: %s)" % text) \
		.contains("Primeborn: Wolf Pack takes the hits at AP(1) instead of AP(2)")
