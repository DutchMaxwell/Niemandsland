extends GdUnitTestSuite
## One core, door lines (lane dlines train 4, DS-GHITN): the core door writes the table's "To-hit vs <U>: <note> → hits on N+" line
## (Artillery shooter/target, Stealth, Stealth aliases, Evasive + stand-down, Aircraft, Shot Modifier entries, Instinctive, multi-fragment
## order and net-0 logging) and the three Takedown lines (pick, context embedding the to-hit note, wounded/killed, without "takes N wounds").
## Each case runs SEEDS (12) seeded volleys on the table and on the door and compares the lines (`door_lines.gd`). RED on main's library;
## GREEN after this train.
## Real: the main scene, NmlCore, the importer's own unit builder, the table's AI body. Constructed: the OPR units (no list file).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DoorLines := preload("res://test/one_core/door_lines.gd")
const SEEDS := 12
const DICE := "user://door_lines_to_hit_dice"

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	RosterSweep.arm(_main, ProjectSettings.globalize_path(DICE))


func after_test() -> void:
	RosterSweep.disarm(_main)
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _unit(uname: String, size: int, rules: Array, weapon_rules: Array, faction := "battle_brothers", system := "gf", guns := 6) -> Dictionary:
	var e := DoorLines.entry(uname, size, rules, weapon_rules, faction, guns)
	(e["unit"] as OPRApiClient.OPRUnit).game_system = system
	e["system"] = system
	return e


func _same(label: String, shooter: Dictionary, target: Dictionary, prefix: String, min_fired := SEEDS, opts := {}, needle := "") -> void:
	var r := await DoorLines.compare(_main, shooter, target, prefix, SEEDS, ProjectSettings.globalize_path(DICE), opts, needle)
	print("DOOR_LINES %s fired=%d/%d with_text=%d mismatches=%d state_bad=%d" % [label, r["fired"], SEEDS, r["with_text"], (r["bad"] as Array).size(), r["state_bad"]])
	assert_int(int(r["state_bad"])).override_failure_message("%s: the end states differ, the lines are compared over a pair the door must not take" % label).is_equal(0)
	assert_int(int(r["fired"])).override_failure_message("%s: the rule never fired on the table, nothing is compared" % label).is_greater_equal(min_fired)
	if needle != "":
		assert_int(int(r["with_text"])).override_failure_message("%s: no seed wrote a line with %s" % [label, needle]).is_greater_equal(1)
	assert_array(r["bad"]).override_failure_message("%s: the door's lines differ from the table's:\n%s" % [label, "\n".join((r["bad"] as Array).slice(0, 4))]).is_empty()


func _silent(label: String, shooter: Dictionary, target: Dictionary, prefix: String, opts := {}) -> void:
	var r := await DoorLines.compare(_main, shooter, target, prefix, SEEDS, ProjectSettings.globalize_path(DICE), opts)
	print("DOOR_LINES %s fired=%d/%d mismatches=%d state_bad=%d" % [label, r["fired"], SEEDS, (r["bad"] as Array).size(), r["state_bad"]])
	assert_int(int(r["state_bad"])).override_failure_message("%s: the end states differ" % label).is_equal(0)
	assert_int(int(r["fired"])).override_failure_message("%s: expected silent on table" % label).is_equal(0)
	assert_array(r["bad"]).override_failure_message("%s: door wrote a line when table was silent:\n%s" % [label, "\n".join((r["bad"] as Array).slice(0, 4))]).is_empty()


func _plain_shooter(faction := "battle_brothers", system := "gf") -> Dictionary:
	return _unit("Gunners", 6, [], [], faction, system, 6)


func _plain_target(size := 10, rules := [], faction := "battle_brothers", system := "gf") -> Dictionary:
	return _unit("Targets", size, rules, [], faction, system, 0)


func test_artillery_shooter_and_target_write_their_to_hit_notes() -> void:
	var art_s := _unit("Gunners", 6, ["Artillery"], [], "battle_brothers", "gf", 6)
	var art_t := _plain_target(10, ["Artillery"])
	await _same("artillery shooter >12", art_s, _plain_target(), "To-hit vs", SEEDS, {"distance_in": 18.0}, "Artillery +1 (Held, target over 12\")")
	await _same("artillery shooter <=12", art_s, _plain_target(), "To-hit vs", SEEDS, {"distance_in": 11.0}, "Artillery: no +1 (target within 12\")")
	await _same("artillery shooter <=9", art_s, _plain_target(), "To-hit vs", SEEDS, {"distance_in": 6.0}, "Artillery: no +1 (target within 9\")")
	await _same("artillery target >12", _plain_shooter(), art_t, "To-hit vs", SEEDS, {"distance_in": 18.0}, "Artillery target -1 over 12\" (unmoved)")
	await _same("artillery target <=12", _plain_shooter(), art_t, "To-hit vs", SEEDS, {"distance_in": 11.0}, "Artillery target: no -1 (within 12\")")
	await _same("artillery target moved", _plain_shooter(), art_t, "To-hit vs", SEEDS, {"distance_in": 18.0, "ledger": {"tgt": {"moved_round": 1}}}, "Artillery target: no -1 (moved this round)")


func test_stealth_and_its_aliases_write_their_to_hit_notes() -> void:
	await _same("stealth >9", _plain_shooter(), _plain_target(10, ["Stealth"]), "To-hit vs", SEEDS, {"distance_in": 18.0}, "Stealth -1")
	await _same("stealth <=9", _plain_shooter(), _plain_target(10, ["Stealth"]), "To-hit vs", SEEDS, {"distance_in": 6.0}, "Stealth: no -1 (within 9\")")
	await _same("screened >9", _plain_shooter("saurians", "aof"), _plain_target(10, ["Screened"], "ghostly_undead", "aof"), "To-hit vs", SEEDS, {"distance_in": 18.0}, "Screened -1 over 9\"")
	await _same("entrenched >12", _plain_shooter(), _plain_target(10, ["Entrenched"], "human_defense_force", "gf"), "To-hit vs", SEEDS, {"distance_in": 18.0}, "Entrenched -1 over 12\"")


func test_evasive_the_stand_down_and_aircraft_write_their_to_hit_notes() -> void:
	await _same("evasive", _plain_shooter(), _plain_target(10, ["Evasive"]), "To-hit vs", SEEDS, {"distance_in": 14.0}, "Evasive -1")
	await _same("evasive stand-down", _plain_shooter("saurians", "aof"),
		_plain_target(10, ["Empyrean Spirit", "Enhanced Empyrean Spirit"], "ghostly_undead", "aof"),
		"To-hit vs", SEEDS, {"distance_in": 14.0}, "Enhanced Empyrean Spirit: -1 to hit (base Evasive stood down)")
	await _same("aircraft", _plain_shooter(), _plain_target(1, ["Aircraft", "Tough(6)"]), "To-hit vs", SEEDS, {"distance_in": 10.0}, "Aircraft -1")


func test_shot_modifiers_and_instinctive_write_their_to_hit_notes() -> void:
	await _same("good shot", _unit("Gunners", 6, ["Good Shot"], [], "saurians", "aof", 6), _plain_target(10, [], "saurians", "aof"), "To-hit vs", SEEDS, {"distance_in": 14.0}, "Good Shot +1")
	await _same("bad shot", _unit("Gunners", 6, ["Bad Shot"], [], "orc_marauders", "gf", 6), _plain_target(), "To-hit vs", SEEDS, {"distance_in": 14.0}, "Bad Shot -1")
	await _same("buccaneer >9", _unit("Gunners", 6, ["Buccaneer"], [], "sky_city_dwarves", "aof", 6), _plain_target(10, [], "saurians", "aof"), "To-hit vs", SEEDS, {"distance_in": 14.0}, "Buccaneer +1")
	await _silent("buccaneer <=9", _unit("Gunners", 6, ["Buccaneer"], [], "sky_city_dwarves", "aof", 6), _plain_target(10, [], "saurians", "aof"), "To-hit vs", {"distance_in": 6.0})
	await _same("targeting visor", _unit("Gunners", 6, ["Targeting Visor"], [], "dao_union", "gf", 6), _plain_target(), "To-hit vs", SEEDS, {"distance_in": 14.0}, "Targeting Visor +1")
	await _same("mobile artillery", _unit("Gunners", 6, ["Mobile Artillery"], [], "human_defense_force", "gf", 6), _plain_target(), "To-hit vs", SEEDS, {"distance_in": 14.0}, "Mobile Artillery +1")
	await _same("instinctive", _unit("Gunners", 6, ["Instinctive"], [], "goblins", "aof", 6), _plain_target(10, [], "saurians", "aof"), "To-hit vs", SEEDS, {"distance_in": 14.0}, "Instinctive +1 (closest target)")


func test_multi_fragment_order_and_zero_net_still_log_the_to_hit_note() -> void:
	# Artillery +1 + Good Shot +1 vs Stealth -1 + Evasive -1 -> net 0, still logged in exact table order.
	var att := _unit("Gunners", 6, ["Artillery", "Good Shot"], [], "saurians", "aof", 6)
	var tgt := _plain_target(10, ["Stealth", "Evasive"], "saurians", "aof")
	await _same("net-zero order", att, tgt, "To-hit vs", SEEDS, {"distance_in": 18.0},
		"Artillery +1 (Held, target over 12\"), Stealth -1, Evasive -1, Good Shot +1 → hits on 4+")
	await _silent("plain control", _plain_shooter(), _plain_target(), "To-hit vs", {"distance_in": 14.0})


func test_takedown_writes_its_three_lines_and_embeds_the_to_hit_note() -> void:
	var sniper := _unit("Snipers", 3, [], ["Takedown", "AP(1)"], "battle_brothers", "gf", 3)
	await _same("takedown troopers", sniper, _plain_target(10), "Takedown", SEEDS, {"distance_in": 14.0}, "unit of [1]: hits on 4+, no cover of its own, saves on 4+")
	await _silent("takedown no takes-line", sniper, _plain_target(10), "Targets takes", {"distance_in": 14.0})
	await _same("takedown tough", sniper, _plain_target(3, ["Tough(3)"]), "Takedown", SEEDS, {"distance_in": 14.0}, "Tough(3) model")
	var boosted := _unit("Snipers", 3, ["Good Shot"], ["Takedown"], "saurians", "aof", 3)
	var stealth_tgt := _plain_target(10, ["Stealth"], "saurians", "aof")
	await _same("takedown with note (to-hit)", boosted, stealth_tgt, "To-hit vs", SEEDS, {"distance_in": 14.0}, "Stealth -1, Good Shot +1")
	await _same("takedown with note (ctx)", boosted, stealth_tgt, "Takedown", SEEDS, {"distance_in": 14.0}, "hits on 4+, Stealth -1, Good Shot +1, no cover of its own, saves on 4+")
	var unit_td := _unit("Snipers", 3, ["Takedown when Shooting"], [], "saurians", "aof", 3)
	await _same("takedown when shooting", unit_td, _plain_target(10, [], "saurians", "aof"), "Takedown", SEEDS, {"distance_in": 14.0}, "Takedown when Shooting (Gun): targets the trooper")
