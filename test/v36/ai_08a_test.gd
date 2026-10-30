extends GdUnitTestSuite
## Rules 3.6 wave, row AI-08a: rules 3.6 prints Ignores Cover as Anti-Cover and Ignores Regeneration as
## Anti-Regen. A weapon that prints one of them must skip cover / the Regeneration roll on the table and in
## the AI's estimate, read through the rule's map entry (row DAT-04 adds the entries; this suite injects
## the same entries into the gf map), and the battle log names the rule each time it applies. The control
## is declared first (gdUnit drops the cases declared after a failing one in a scene suite).

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
	_set_entries(true)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	RulesRegistry.reset_cache()
	AiActRecorder.rules_epoch = _epoch_before


## The real gf map, with the two 3.6 entries (`with_entries`) or without them (whatever the committed map has).
func _set_entries(with_entries: bool) -> void:
	RulesRegistry.reset_cache()
	var gf: Dictionary = RulesRegistry.map_for("gf").duplicate(true)
	var common: Dictionary = gf.get("common", {})
	for n in NEW_NAMES:
		common.erase(n)
	if with_entries:
		common.merge(ENTRIES.duplicate(true), true)
	gf["common"] = common
	RulesRegistry._cache["gf"] = gf


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## The AI shooter, a gf unit 6" east of the seed point.
func _shooter() -> GameUnit:
	var u := E2EBoot.make_unit(_main, 1, "Gunners", [SEED + Vector3(6.0 * INCH, 0, 0)])
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["faction_folder"] = "alien_hives"
	u.unit_properties["special_rules"] = []
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _gun(rule: String) -> OPRApiClient.OPRWeapon:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Test Gun"
	w.range_value = 24
	w.attacks = 60
	w.count = 1
	var rs: Array[String] = [rule]
	w.special_rules = rs
	return w


## The shooter's stamped profile for a 24" gun printing `rule`: the one the volley and the AI estimate read.
func _profile(shooter: GameUnit, rule: String) -> Dictionary:
	var profiles := AiEv.stamp_sergeant(AiShooting.profiles_in_range([_gun(rule)], 0.0), shooter)
	assert_int(profiles.size()).is_equal(1)
	return profiles[0] as Dictionary


func _ev(profile: Dictionary, def_extra: Dictionary) -> float:
	var def_ctx := {"defense": 4, "models": 1, "tough": 1}
	def_ctx.merge(def_extra, true)
	return AiEv.profile_ev(profile, {"quality": 2}, def_ctx, 12.0, false)


## Control: without the map entries (this row lands before DAT-04) both new names stay inert on the table and
## in the AI estimate; the read is the map's, never a new name literal.
func test_without_the_map_entries_both_names_stay_inert() -> void:
	_set_entries(false)
	var shooter := _shooter()
	assert_bool(bool(_profile(shooter, "Anti-Cover").get("ignores_cover", false))).is_false()
	var regen := _profile(shooter, "Anti-Regen")
	assert_bool(_main._solo_ignores_regen(shooter, regen)).is_false()
	assert_float(_ev(regen, {"regeneration": true, "regen_target": 5})) \
		.is_less(_ev(regen, {}))


func test_an_anti_cover_weapon_skips_cover_in_the_ai_profile_and_estimate() -> void:
	var p := _profile(_shooter(), "Anti-Cover")
	assert_bool(bool(p.get("ignores_cover", false))) \
		.override_failure_message("the Anti-Cover gun's profile must skip cover") \
		.is_true()
	assert_float(_ev(p, {"in_cover": true})) \
		.override_failure_message("the AI estimate must charge no cover save") \
		.is_equal(_ev(p, {}))


func test_an_anti_regen_weapon_counts_every_wound_in_the_ai_estimate() -> void:
	var p := _profile(_shooter(), "Anti-Regen")
	assert_float(_ev(p, {"regeneration": true, "regen_target": 5})) \
		.override_failure_message("the AI estimate must give the target no Regeneration roll") \
		.is_equal(_ev(p, {}))


func test_the_table_names_anti_regen_when_it_skips_regeneration() -> void:
	var shooter := _shooter()
	assert_bool(_main._solo_ignores_regen(shooter, _profile(shooter, "Anti-Regen"))).is_true()
	assert_str(_log_text()) \
		.override_failure_message("rules-must-log: the bypass names Anti-Regen (log: %s)" % _log_text().strip_edges()) \
		.contains("Anti-Regen: Regeneration ignored")


## The real volley into a lone model standing in a wood: the cover save is skipped and the log says which
## rule skipped it, instead of claiming the cover.
func test_the_table_names_anti_cover_when_it_skips_cover() -> void:
	var o: Node3D = _main.terrain_overlay
	o.grid_cells[o.world_to_cell(SEED)] = o.TerrainType.FOREST
	var foe := E2EBoot.make_unit(_main, 2, "Woodsman", [SEED])
	_main.opr_army_manager.game_units[foe.unit_id] = foe
	assert_bool(_main._solo_majority_in_cover(foe)).override_failure_message("precondition: the foe is in cover").is_true()
	var shooter := _shooter()
	var shots := [{"member": shooter, "quality": shooter.get_quality(), "alive": shooter.get_alive_count(),
		"max": shooter.models.size(), "reach": 24, "profile": _profile(shooter, "Anti-Cover")}]
	_main.seed_tray_rng(7)
	await _main._solo_resolve_ai_volley(shooter, foe, shots)
	var text := _log_text()
	await E2EBoot.settle(get_tree())
	assert_str(text) \
		.override_failure_message("the Anti-Cover gun must not use the cover (log: %s)" % text.strip_edges()) \
		.not_contains("is in cover")
	assert_str(text) \
		.override_failure_message("rules-must-log: the skip names Anti-Cover (log: %s)" % text.strip_edges()) \
		.contains("Anti-Cover: Gunners")
