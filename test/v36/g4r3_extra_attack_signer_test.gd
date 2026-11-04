extends GdUnitTestSuite
## G4 round 3, row H-EXTRA-ATTACK-SIGNER: the extra attack a rule generates ("1 extra attack from unmodified 6s",
## Bloodborn / Primal) is rolled by the firing member, like every other die of its shot — the core signs it with the
## member. The AI volley signed it with the host unit, so a joined hero's extra die carried the host's label
## (gf_003/21, gf_004/20, gf_034/28, gf_035/11). From EPOCH_73_V36 the extra die carries the firing member's label;
## EPOCH_72_PLAYTEST_RULES keeps the host label so recorded games replay unchanged. The labels are read from the
## dice dump (AiDiceRecorder), the table's own per-roll record.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const SEED := 21
const _DUMP_DIR := "user://g4r3_extra_attack_signer_test_tmp"

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
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true
	DirAccess.make_dir_recursive_absolute(_DUMP_DIR)
	AiDiceRecorder._checked = false
	AiDiceRecorder._stream = null
	AiDiceRecorder._count = 0
	OS.set_environment("NML_DICE_DUMP", ProjectSettings.globalize_path(_DUMP_DIR))


func after_test() -> void:
	AiDiceRecorder.close()
	OS.set_environment("NML_DICE_DUMP", "")
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


## The owner labels of every roll the dump holds, in order.
func _owners() -> Array:
	var out: Array = []
	var f := FileAccess.open(_DUMP_DIR.path_join("dice.jsonl"), FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line := f.get_line()
		if line != "":
			out.append(str((JSON.parse_string(line) as Dictionary).get("owner", "")))
	f.close()
	return out


## A host squad with a Bloodborn hero joined to it. The hero's pistol (Quality 2+, 12 dice) is the shot; the volley's
## attacker is the host, the firing member is the hero — the parity acts' shape.
func _volley(epoch: int) -> void:
	AiActRecorder.rules_epoch = epoch
	var host := E2EBoot.make_unit(_main, 1, "Test Squad", [Vector3.ZERO])
	(host.models[0] as ModelInstance).model_index = 0
	var hero := E2EBoot.make_unit(_main, 1, "Test Hero", [Vector3(0, 0, 0.02)])
	(hero.models[0] as ModelInstance).model_index = 0
	hero.unit_properties["game_system"] = "gf"
	hero.unit_properties["faction_folder"] = "blood_brothers"
	hero.unit_properties["special_rules"] = ["Bloodborn"]
	(hero.models[0] as ModelInstance).properties["special_rules"] = ["Bloodborn"]
	hero.unit_properties["quality"] = 2
	_main.opr_army_manager.game_units[host.unit_id] = host
	_main.opr_army_manager.game_units[hero.unit_id] = hero
	EquipmentDistributor.attach_hero_to_unit(hero, host)
	var pistol := OPRApiClient.OPRWeapon.new()
	pistol.name = "Hero Pistol"
	pistol.range_value = 12
	pistol.attacks = 12
	pistol.count = 1
	var src := OPRApiClient.OPRUnit.new()
	src.weapons.assign([pistol])
	hero.source_type = "opr"
	hero.source_data = src
	var squad := E2EBoot.make_unit(_main, 2, "Test Scouts", [Vector3(5.0 * INCH, 0, 0), Vector3(5.0 * INCH, 0, 0.02)])
	squad.unit_properties["defense"] = 6
	_main.opr_army_manager.game_units[squad.unit_id] = squad
	var shots: Array = []
	for p in AiEv.stamp_sergeant(AiShooting.profiles_in_range([pistol], 0.0), hero):
		shots.append({"member": hero, "quality": 2, "alive": 1, "max": 1, "reach": 12, "profile": p})
	_main.seed_tray_rng(SEED)
	await _main._solo_resolve_ai_volley(host, squad, shots)
	await E2EBoot.settle(get_tree())


func _assert_extra_die_rolled() -> void:
	var text := _log_text()
	assert_str(text).override_failure_message("fixture: the hero's sixes must spawn extra attacks (log: %s)" % text) \
		.contains("Bloodborn:")
	assert_str(text).contains("extra attack")


## EPOCH_72 leg (declared first: gdUnit drops tests declared after a failing one): the extra die keeps the host's label.
func test_the_extra_die_is_signed_by_the_host_at_epoch_72(timeout := 120000) -> void:
	await _volley(AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	_assert_extra_die_rolled()
	assert_array(_owners()).override_failure_message("EPOCH_72 keeps the host's label").contains(["AI (Test Squad)"])


## EPOCH_73: the extra die carries the firing hero's label, like the hero's own attack dice.
func test_the_extra_die_is_signed_by_the_firing_member_at_epoch_73(timeout := 120000) -> void:
	await _volley(AiActRecorder.EPOCH_73_V36)
	_assert_extra_die_rolled()
	var owners := _owners()
	assert_array(owners).override_failure_message("fixture: the hero must sign its attack dice (owners: %s)" % [owners]) \
		.contains(["AI (Test Hero)"])
	assert_array(owners) \
		.override_failure_message("H-EXTRA-ATTACK-SIGNER — no die of the hero's shot may carry the host's label (owners: %s)" % [owners]) \
		.not_contains(["AI (Test Squad)"])
