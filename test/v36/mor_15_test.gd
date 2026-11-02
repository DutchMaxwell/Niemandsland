extends GdUnitTestSuite
## Rules 3.6 wave, row MOR-15: a WEAPON-borne "Spell Amplifier" adds +1 to the bearer's own
## casting rolls from EPOCH_73_V36 (4+ -> 3+). It is a static, weapon-borne rule: it rides the
## weapon's rule list, is not a token and not a unit special rule, and only helps the bearer.
## The core's twin is core/nml-core/src/tests/unit/v36_morale.rs (`mod mor_15`).

const Boot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _roots: Array
var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	Boot.arm_harness_mode()
	_roots = Boot.root_children(get_tree())
	_runner = scene_runner(Boot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests — restore
	Boot.free_stray_root_nodes(get_tree(), _roots)
	_main = null
	_runner = null


## A real OPR unit whose weapon carries `weapon_rules`; `special_rules` goes on the unit itself.
func _armed(pid: int, unit_name: String, weapon_rules: Array, special_rules: Array) -> GameUnit:
	var u: GameUnit = Boot.make_unit(_main, pid, unit_name, [Vector3.ZERO])
	var opr := OPRApiClient.OPRUnit.new()
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rod"
	w.range_value = 12
	w.attacks = 1
	w.special_rules.assign(weapon_rules)
	var ws: Array[OPRApiClient.OPRWeapon] = [w]
	opr.weapons = ws
	u.source_type = "opr"
	u.source_data = opr
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["faction_folder"] = "blessed_sisters"
	u.unit_properties["special_rules"] = special_rules
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## Drive the real cast resolver once and return only the lines it wrote.
func _cast_log(caster: GameUnit, ally: GameUnit) -> String:
	var start: int = _main.battle_log.entries().size()
	await _main._solo_resolve_one_cast({"caster": caster, "caster_unit": caster,
		"spell": {"effect": {"kind": "buff", "grants_rule": "Fearless"}},
		"name": "Warding Chant", "targets": [ally], "boost": 0, "interference": 0,
		"base_target": AiSpell.CAST_BASE_TARGET, "threshold": 1, "owner_label": "You",
		"human_cast": true})
	var text := ""
	for e in _main.battle_log.entries().slice(start):
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func test_a_weapon_borne_spell_amplifier_lowers_the_cast_target_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var caster := _armed(1, "Amplified", ["Spell Amplifier"], ["Caster(1)"])
	var ally := _armed(1, "Ally", [], [])
	var text := await _cast_log(caster, ally)
	assert_str(text).override_failure_message(
		"the weapon-borne amplifier must make the cast need 3+:\n%s" % text).contains("needs 3+")
	await Boot.settle(get_tree())


func test_a_caster_without_the_rule_stays_at_four_plus_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var caster := _armed(1, "Plain", [], ["Caster(1)"])
	var ally := _armed(1, "Ally", [], [])
	var text := await _cast_log(caster, ally)
	assert_str(text).override_failure_message(
		"a plain caster stays at 4+:\n%s" % text).contains("needs 4+")
	await Boot.settle(get_tree())


func test_the_amplifier_does_nothing_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var caster := _armed(1, "Amplified", ["Spell Amplifier"], ["Caster(1)"])
	var ally := _armed(1, "Ally", [], [])
	var text := await _cast_log(caster, ally)
	assert_str(text).override_failure_message(
		"below 73 the amplifier does nothing:\n%s" % text).contains("needs 4+")
	await Boot.settle(get_tree())


func test_a_special_rule_spelling_does_nothing_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var caster := _armed(1, "SpecialOnly", [], ["Caster(1)", "Spell Amplifier"])
	var ally := _armed(1, "Ally", [], [])
	var text := await _cast_log(caster, ally)
	assert_str(text).override_failure_message(
		"the row is weapon-borne: special_rules never grant it:\n%s" % text).contains("needs 4+")
	await Boot.settle(get_tree())