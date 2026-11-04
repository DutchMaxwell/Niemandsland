extends GdUnitTestSuite
## G4 round 3, row T-DUP-WEAPON-BEARERS: a unit that lists one weapon name twice (the Jesters' "Atom Pistol" x8 and
## "Atom Pistol" x2, two entries because their profiles differ) used to count the living bearers BY NAME for each
## entry, so both entries got all 10 bearers: 8 + 8 dice for 10 pistols. From EPOCH_73_V36 the entries of one name
## and per-copy attack count share their bearers in the AI volley: the guns of the sighted models fire once, each
## entry capped by its own copies; EPOCH_72_PLAYTEST_RULES keeps the by-name count so recorded games replay unchanged.
## The dice are read from the shot dump (AiShotRecorder), the table's own per-shot record of the attacks it rolled.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const SEED := 3
const _DUMP_DIR := "user://g4r3_dup_bearers_test_tmp"

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
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true
	DirAccess.make_dir_recursive_absolute(_DUMP_DIR)
	AiShotRecorder._checked = false
	AiShotRecorder._stream = null
	AiShotRecorder._count = 0
	OS.set_environment("NML_SHOT_DUMP", ProjectSettings.globalize_path(_DUMP_DIR))


func after_test() -> void:
	AiShotRecorder.close()
	OS.set_environment("NML_SHOT_DUMP", "")
	var d := DirAccess.open(_DUMP_DIR)
	if d != null:
		for f in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(_DUMP_DIR)
	AiActRecorder.rules_epoch = _epoch_before
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func _pistol(copies: int, rules: Array) -> OPRApiClient.OPRWeapon:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Atom Pistol"
	w.range_value = 12
	w.attacks = 1
	w.count = copies
	var typed: Array[String] = []
	for r in rules:
		typed.append(str(r))
	w.special_rules = typed
	return w


## Dice rolled per Atom Pistol entry, read back from the table's per-shot record.
func _pistol_attacks() -> Array:
	var out: Array = []
	var f := FileAccess.open(_DUMP_DIR.path_join("shots.jsonl"), FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line := f.get_line()
		if line == "":
			continue
		var rec: Dictionary = JSON.parse_string(line)
		if str(rec.get("weapon", "")) == "Atom Pistol":
			out.append(int(rec.get("attacks", -1)))
	f.close()
	return out


func _total(a: Array) -> int:
	var n := 0
	for v in a:
		n += int(v)
	return n


## Ten Jesters, each with one Atom Pistol in the per-model loadout (the way the army import pins it), two entries of
## the weapon (x8 and x2; the second one carries AP(1) so the two profiles stay apart). `near` of the ten stand 5"
## from a three-model squad, the rest 30" behind: only `near` models are in range and sight.
func _volley(epoch: int, near: int) -> void:
	AiActRecorder.rules_epoch = epoch
	var entry_a := _pistol(8, [])
	var entry_b := _pistol(2, ["AP(1)"])
	var positions: Array = []
	for i in 10:
		positions.append(Vector3((-5.0 if i < near else -30.0) * INCH, 0, 0.02 * i))
	var jesters := E2EBoot.make_unit(_main, 1, "Jesters", positions)
	for i in jesters.models.size():
		var mi := jesters.models[i] as ModelInstance
		mi.model_index = i
		mi.properties["weapons"] = [{"name": "Atom Pistol", "attacks": 1}]
	var src := OPRApiClient.OPRUnit.new()
	src.weapons.assign([entry_a, entry_b])
	jesters.source_type = "opr"
	jesters.source_data = src
	jesters.unit_properties["quality"] = 2
	_main.opr_army_manager.game_units[jesters.unit_id] = jesters
	var squad := E2EBoot.make_unit(_main, 2, "Test Scouts", [Vector3.ZERO, Vector3(0, 0, 0.02), Vector3(0, 0, 0.04)])
	squad.unit_properties["defense"] = 6
	_main.opr_army_manager.game_units[squad.unit_id] = squad
	var shots: Array = []
	for p in AiShooting.profiles_in_range([entry_a, entry_b], 0.0):
		shots.append({"member": jesters, "quality": 2, "alive": 10, "max": 10, "reach": 12, "profile": p})
	_main.seed_tray_rng(SEED)
	await _main._solo_resolve_ai_volley(jesters, squad, shots)
	await E2EBoot.settle(get_tree())


## EPOCH_72 leg (declared first: gdUnit drops tests declared after a failing one): the by-name count stays, so
## both entries read all ten bearers and roll 8 + 8 dice.
func test_both_entries_read_every_bearer_at_epoch_72(timeout := 120000) -> void:
	await _volley(AiActRecorder.EPOCH_72_PLAYTEST_RULES, 8)
	assert_array(_pistol_attacks()).override_failure_message("EPOCH_72 keeps the by-name count").is_equal([8, 8])


## The parity act's shape: 8 of the 10 models sighted. The eight sighted pistols fire once — the first entry takes
## all eight, the second has no bearer left and stays silent (the core fires the one volley of 8).
func test_entries_of_one_weapon_share_the_sighted_bearers_at_epoch_73(timeout := 120000) -> void:
	await _volley(AiActRecorder.EPOCH_73_V36, 8)
	var dice := _pistol_attacks()
	assert_int(_total(dice)) \
		.override_failure_message("T-DUP-WEAPON-BEARERS — 8 sighted pistols must roll 8 dice in total, not %s" % [dice]) \
		.is_equal(8)
	assert_str(_log_text()).override_failure_message("rules-must-log: the silent entry says why (log: %s)" % _log_text()) \
		.contains("Atom Pistol silent")


## All ten models sighted: each entry fires its own copies, 8 + 2 — ten dice for ten pistols.
func test_every_pistol_fires_once_when_all_ten_models_are_sighted_at_epoch_73(timeout := 120000) -> void:
	await _volley(AiActRecorder.EPOCH_73_V36, 10)
	var dice := _pistol_attacks()
	assert_int(_total(dice)) \
		.override_failure_message("T-DUP-WEAPON-BEARERS — 10 pistols must roll 10 dice in total, not %s" % [dice]) \
		.is_equal(10)
	assert_array(dice).override_failure_message("each entry fires its own copies").is_equal([8, 2])
