extends GdUnitTestSuite
## R-1 step 7: the bypass reaches the two places the roll split left behind.
##   (a) A spell wound that bypasses Regeneration still meets the other wound-ignore rules - and must meet
##       them at the SPELL threshold (a unit with Resistance rolls 2+ against spell wounds, not 6+).
##   (b) (the human volley's "<rule>: Regeneration ignored" line, only against a real Regeneration; Self-Repair gets none)
##       left with the table's human resolver: the Anti-Regen, Regeneration and Self-Repair cells read equal in the shoot ledger.
## (a) rides the real table path over main.tscn.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch_before: int


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
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
	AiActRecorder.rules_epoch = _epoch_before   # statics leak across gdUnit tests - restore
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## The caster of part (a): a gf unit with no weapons (the spell carries the damage).
func _caster() -> GameUnit:
	var u := E2EBoot.make_unit(_main, 1, "Spell Raiders", [Vector3.ZERO])
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["faction_folder"] = "alien_hives"
	u.unit_properties["special_rules"] = []
	var opr := OPRApiClient.OPRUnit.new()
	var ws: Array[OPRApiClient.OPRWeapon] = []
	opr.weapons = ws
	u.source_type = "opr"
	u.source_data = opr
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## The AI-owned target of part (a): every model carries Resistance.
func _resistant_foe() -> GameUnit:
	var positions: Array = []
	for i in range(5):
		positions.append(Vector3(6.0 * INCH, 0, 0.02 * i))
	var foe := E2EBoot.make_unit(_main, 2, "Warded Squad", positions)
	foe.unit_properties["game_system"] = "gf"
	foe.unit_properties["faction_folder"] = "alien_hives"
	foe.unit_properties["special_rules"] = ["Resistance"]
	_main.opr_army_manager.game_units[foe.unit_id] = foe
	return foe


func _spell(weapon_rules: Array, foe: GameUnit) -> String:
	var caster := _caster()
	var entry := {"effect": {"kind": "damage", "hits": 12, "weapon_rules": weapon_rules},
		"target": {"kind": "unit", "side": "enemy"}}
	_main.seed_tray_rng(7)
	await _main._solo_resolve_spell_damage(caster, caster, "Test Bolt", entry, foe)
	var text := _log_text()
	await E2EBoot.settle(get_tree())
	return text


# ===== (a): the bypassed spell wound rolls at the spell threshold =====

func test_a_bypassed_spell_wound_rolls_resistance_at_the_spell_threshold(timeout := 120000) -> void:
	var text: String = await _spell(["AP(4)", "Bane"], _resistant_foe())
	assert_str(text).override_failure_message(
		"the bypassed spell wounds must still meet Resistance (log: %s)" % text.strip_edges()) \
		.contains("resistance di")
	assert_str(text).override_failure_message(
		"a bypassed SPELL wound must roll Resistance at the spell threshold, 2+ (log: %s)" % text.strip_edges()) \
		.contains("(2+)")
