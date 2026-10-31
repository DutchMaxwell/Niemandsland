extends GdUnitTestSuite
## Rules 3.6 wave, row DAT-16b: a rule that changes a roll must name itself in the battle log.
##   * The HUMAN volley names the map-read rule that skips cover (the AI volley's AI-08a line already
##     does): Ignores Cover / Blast / Indirect / Anti-Cover are the rules that skip it.
##   * A Regeneration-bypass line is written only when the hit target actually has a Regeneration-
##     family roll to skip; a bypass against a plain unit does not claim to ignore anything.
## Both cases drive the real table path over main.tscn (`_run_human_shooting`), so the assertions read
## the same battle log a player sees. The control is declared first: gdUnit drops the cases declared
## after a failing one on a scene suite.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const SEED := Vector3(0.03, 0.0, 0.03)   # a point inside some 3" terrain cell
const NEW_NAMES := ["Anti-Cover", "Anti-Regen"]
const ENTRIES := {
	"Anti-Cover": {"primitive": "Indirect", "params": {"ignores_cover": true, "cover_only": true}},
	"Anti-Regen": {"primitive": "Lacerate", "params": {"bypass_regen": true}},
}

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
	_set_entries()


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	RulesRegistry.reset_cache()
	AiActRecorder.rules_epoch = _epoch_before


## The real gf map, with the two 3.6 entries DAT-04 lands in the shared map.
func _set_entries() -> void:
	RulesRegistry.reset_cache()
	var gf: Dictionary = RulesRegistry.map_for("gf").duplicate(true)
	var common: Dictionary = gf.get("common", {})
	for n in NEW_NAMES:
		common.erase(n)
	common.merge(ENTRIES.duplicate(true), true)
	gf["common"] = common
	RulesRegistry._cache["gf"] = gf


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func _gun(rule: String) -> OPRApiClient.OPRWeapon:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Test Gun"
	w.range_value = 24
	w.attacks = 60
	w.count = 1
	var rs: Array[String] = [rule]
	w.special_rules = rs
	return w


## A gf shooter 6" east of `at`, with a 24" gun printing `rule`.
func _shooter(at: Vector3, rule: String) -> GameUnit:
	var u := E2EBoot.make_unit(_main, 1, "Gunners", [at + Vector3(6.0 * INCH, 0, 0)])
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["faction_folder"] = "alien_hives"
	u.unit_properties["special_rules"] = []
	var src := OPRApiClient.OPRUnit.new()
	src.weapons = [_gun(rule)]
	u.source_type = "opr"
	u.source_data = src
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _foe(at: Vector3, rules: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, 2, "Foemen", [at])
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["faction_folder"] = "alien_hives"
	u.unit_properties["special_rules"] = rules
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


# ===== control: a real Regeneration target keeps the bypass line =====

func test_a_regeneration_bypass_still_names_itself_against_a_regenerator(timeout := 120000) -> void:
	var foe := _foe(Vector3(0.20, 0.0, 0.0), ["Regeneration"])
	var shooter := _shooter(Vector3(0.20, 0.0, 0.0), "Anti-Regen")
	await _main._run_human_shooting(shooter, foe)
	var text := _log_text()
	await E2EBoot.settle(get_tree())
	assert_str(text).override_failure_message(
		"rules-must-log: an Anti-Regen weapon vs a Regeneration unit must name the rule:\n%s" % text) \
		.contains("Anti-Regen: Regeneration ignored")


# ===== the two missing lines (one method, so a failing case cannot hide the other) =====

func test_the_cover_skip_and_the_regen_bypass_name_their_rules(timeout := 120000) -> void:
	# (1) The human volley into a lone model in a wood: Anti-Cover skips the save and the log says so.
	var o: Node3D = _main.terrain_overlay
	o.grid_cells[o.world_to_cell(SEED)] = o.TerrainType.FOREST
	var foe := _foe(SEED, [])
	assert_bool(_main._solo_majority_in_cover(foe)) \
		.override_failure_message("precondition: the foe is in cover").is_true()
	var shooter := _shooter(SEED, "Anti-Cover")
	_main.seed_tray_rng(7)
	await _main._run_human_shooting(shooter, foe)
	var text := _log_text()
	await E2EBoot.settle(get_tree())
	assert_str(text).override_failure_message(
		"the Anti-Cover gun must not use the cover (log: %s)" % text.strip_edges()) \
		.not_contains("is in cover")
	assert_str(text).override_failure_message(
		"rules-must-log: the human volley must name the rule that skipped cover (log: %s)" % text.strip_edges()) \
		.contains("Anti-Cover: Gunners")
	# (2) The same bypass against a unit WITHOUT Regeneration must not claim to ignore it.
	var plain := _foe(Vector3(0.40, 0.0, 0.0), [])
	var gunner := _shooter(Vector3(0.40, 0.0, 0.0), "Anti-Regen")
	_main.seed_tray_rng(7)
	await _main._run_human_shooting(gunner, plain)
	var bypass_text := _log_text()
	await E2EBoot.settle(get_tree())
	assert_str(bypass_text).override_failure_message(
		"rules-must-log: no Regeneration on the target means no bypass line (log: %s)" % bypass_text.strip_edges()) \
		.not_contains("Regeneration ignored")
