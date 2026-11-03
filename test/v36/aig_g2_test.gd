extends GdUnitTestSuite
## Rules 3.6 wave, AI gate AI-G2 (alias primitives): a WEAPON rule the faction map resolves to the Bane
## primitive (Smash, Reap, Decimate) re-rolls the defender's Defense 6s like the printed Bane, from the 3.6
## epoch on, under its own book name. The reads go through the committed gf map's entry (battle_brothers /
## Smash), never a name literal. Twin of core/nml-core/src/tests/unit/v36_aig_g2.rs. The controls come first
## (gdUnit drops the cases declared after a failing one in a scene suite).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const SEED := Vector3(0.03, 0.0, 0.03)   # a point inside some 3" terrain cell

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
	RulesRegistry.reset_cache()


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	RulesRegistry.reset_cache()
	AiActRecorder.rules_epoch = _epoch_before


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## A gf battle_brothers shooter `east_in` inches east of the seed point.
func _shooter(east_in: float) -> GameUnit:
	var u := E2EBoot.make_unit(_main, 1, "Gunners", [SEED + Vector3(east_in * INCH, 0, 0)])
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["faction_folder"] = "battle_brothers"
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


## Control: the printed Bane keeps its re-roll and its Regeneration bypass.
func test_the_printed_bane_still_re_rolls_and_cuts_regeneration() -> void:
	var shooter := _shooter(6.0)
	var p := _profile(shooter, "Bane")
	assert_bool(_main._solo_striker_has_bane(shooter, p, false)).is_true()
	assert_bool(_main._solo_ignores_regen(shooter, p)).is_true()


## Control: below the 3.6 epoch a Smash weapon replays as before (no Bane anywhere).
func test_below_73_a_smash_weapon_stays_plain() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var shooter := _shooter(6.0)
	var p := _profile(shooter, "Smash")
	assert_bool(bool(p.get("bane", false))).is_false()
	assert_bool(_main._solo_striker_has_bane(shooter, p, false)).is_false()


func test_a_smash_weapon_stamps_the_bane_facet_through_the_map_at_73() -> void:
	var shooter := _shooter(6.0)
	var p := _profile(shooter, "Smash")
	assert_bool(bool(p.get("bane", false))) \
		.override_failure_message("the Smash gun's profile must carry the Bane facet").is_true()
	assert_str(str((p.get("bane_condition", {}) as Dictionary).get("condition", ""))) \
		.override_failure_message("the entry's own gate must ride along").is_equal("over_half_range")
	assert_bool(_main._solo_striker_has_bane(shooter, p, false)) \
		.override_failure_message("the table's dice reader must see the alias").is_true()


## The map entry prints bypass_regen: false, so the alias re-rolls sixes without cutting Regeneration.
func test_a_smash_weapon_never_cuts_regeneration() -> void:
	var shooter := _shooter(6.0)
	assert_bool(_main._solo_ignores_regen(shooter, _profile(shooter, "Smash"))).is_false()


## The real volley past half range: the gate is open and the log names the book rule.
func test_the_table_names_smash_when_it_re_rolls_past_half_range() -> void:
	var foe := E2EBoot.make_unit(_main, 2, "Woodsman", [SEED])
	_main.opr_army_manager.game_units[foe.unit_id] = foe
	var shooter := _shooter(18.0)
	var shots := [{"member": shooter, "quality": shooter.get_quality(), "alive": shooter.get_alive_count(),
		"max": shooter.models.size(), "reach": 24, "profile": _profile(shooter, "Smash")}]
	_main.seed_tray_rng(7)
	await _main._solo_resolve_ai_volley(shooter, foe, shots)
	var text := _log_text()
	await E2EBoot.settle(get_tree())
	assert_str(text) \
		.override_failure_message("rules-must-log: the re-roll names Smash (log: %s)" % text.strip_edges()) \
		.contains("Smash: Woodsman re-rolls")
