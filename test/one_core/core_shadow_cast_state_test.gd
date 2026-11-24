extends GdUnitTestSuite
## CC-10d: the shadow's state diff reads the caster's token count (`casts`) and the buff names each unit gained this
## activation (the table's own token list against the tokens the core's cast lines place). The three planted faults the
## soak raises (NML_CORE_SHADOW_PLANT = cast_boost | cast_payer | cast_buff) each surface as their own reading.
## RED before this step: `_state_diff` knows neither `casts` nor `buffs`, so the planted runs still read equal.
## Real: the main scene, NmlCore, the table's `_solo_resolve_ai_casts`. Constructed: golden-grid units, alien_hives book.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const Harness := preload("res://test/one_core/golden_witness_harness.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")

const MYSTIC := {"key": "my", "player": 1, "name": "Mystic", "models": 1, "quality": 4, "defense": 4, "tough": 1,
	"x_in": 0.0, "z_step_in": 1.2, "base_radius_in": 0.63, "game_system": "gf", "faction_folder": "alien_hives",
	"rules": ["Caster"]}
const STAFF := {"name": "Staff", "range_in": 0, "attacks": 1, "count": 1, "rules": []}
const TERROR_SEEKER := {"name": "Terror Seeker", "threshold": 1, "range_in": 12,
	"target": {"side": "friendly", "count": 1, "kind": "unit"},
	"effect": {"kind": "buff", "grants_rule": "Hit & Run Fighter", "duration": "once"}}


class StubMain:
	var opr_army_manager: OPRArmyManager
	var _solo_spell_tokens_active: Array = []


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
	SoloHarness.start(_main, [1, 2], 1)
	_main.solo_controller.last_move_paths = []
	_main._solo_both_ai = true
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	SoloHarness.instant(_main)
	CoreActivation._env = 1
	CoreShadow._env = 1
	CoreShadow._cast_env = 1
	CoreShadow.records.clear()


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	CoreShadow._env = -1
	CoreShadow._cast_env = -1
	CoreShadow._plant = ""
	CoreShadow._plant_read = true
	CoreShadow.records.clear()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _plant(name: String) -> void:
	CoreShadow._plant = name
	CoreShadow._plant_read = true


## One cast-only activation through the table's resolver and the shadow's flush, with `plant` set as the soak does.
## `over` replaces keys of the planned cast; `tokens` is what the caster holds at the capture, `spend` what the plan pays.
func _shadow_cast(caster: GameUnit, entry: Dictionary, seed: int, plant: String, over: Dictionary = {},
		tokens: int = 3, spend: int = 1) -> Dictionary:
	var cast := {"caster": caster, "caster_unit": caster, "name": str(entry["name"]), "spell": entry,
		"targets": [caster], "boost": 0, "interference": 0, "base_target": 4, "threshold": 1,
		"owner_label": "AI (%s)" % caster.get_name(), "interference_open": false,
		"boost_sources": [], "interference_sources": [], "conduit": null, "conduit_shaken": [], "pools": []}
	cast.merge(over, true)
	var report := {"action": AiDecision.Action.HOLD, "moved": false, "casts": [cast]}
	_main._solo_spell_tokens_active.clear()   # one activation from a clean token board (the same unit key each iteration)
	caster.casts_current = tokens
	_main._solo_core_shadow_h = CoreShadow.capture(_main, caster)
	assert_int(_main._solo_core_shadow_h).override_failure_message("no shadow board").is_not_equal(0)
	caster.spend_caster_points(spend)   # the planner paid the attempt; the core pays from the capture
	_plant(plant)
	CoreShadow.note_placed(_main, caster, report)
	_main.seed_tray_rng(seed)
	await _main._solo_resolve_ai_casts(report)
	CoreShadow.flush(_main)
	CoreShadow.release(_main)
	assert_int(CoreShadow.records.size()).override_failure_message("the cast-only activation was not compared").is_greater(0)
	return CoreShadow.records[-1]


## A caster whose core row holds 2 tokens where the table holds 3: the token spend is a reading of its own.
func test_the_token_count_is_compared() -> void:
	var gu := GameUnit.new()
	gu.unit_id = "u"
	gu.unit_properties = {"player_id": 1, "name": "u", "quality": 4, "defense": 4, "special_rules": []}
	gu.casts_current = 3
	var main := StubMain.new()
	main.opr_army_manager = auto_free(OPRArmyManager.new())
	main.opr_army_manager.game_units = {"u": gu}
	var core := {"units": {"u": {"alive": 0, "wounds": [], "shaken": false, "fatigued": false, "casts": 2}}}
	assert_str(CoreShadow._state_diff(main, core)).is_equal("casts")
	core["units"]["u"]["casts"] = 3
	assert_str(CoreShadow._state_diff(main, core)).is_equal("")


## The soak's three planted faults: a moved cast target (rolls), a wrong spend (casts), a dropped buff (buffs).
func test_a_planted_boost_moves_the_cast_die() -> void:
	var caster := ParityTable._make_unit(_main, MYSTIC, STAFF)
	var rec := await _shadow_cast(caster, TERROR_SEEKER, 0, "cast_boost")
	assert_dict(rec).override_failure_message("cast_boost: %s" % [rec]) \
		.contains_key_value("equal", false).contains_key_value("first_diff", "rolls")
	Harness._free_units(_main, [caster])
	await _main.get_tree().process_frame


func test_a_planted_payer_is_a_token_difference() -> void:
	var caster := ParityTable._make_unit(_main, MYSTIC, STAFF)
	var rec := await _shadow_cast(caster, TERROR_SEEKER, 0, "cast_payer")
	assert_dict(rec).override_failure_message("cast_payer: %s" % [rec]) \
		.contains_key_value("equal", false).contains_key_value("first_diff", "casts")
	Harness._free_units(_main, [caster])
	await _main.get_tree().process_frame


func test_a_planted_buff_is_a_buff_difference() -> void:
	var caster := ParityTable._make_unit(_main, MYSTIC, STAFF)
	var rec := await _shadow_cast(caster, TERROR_SEEKER, 0, "cast_buff")
	assert_dict(rec).override_failure_message("cast_buff: %s" % [rec]) \
		.contains_key_value("equal", false).contains_key_value("first_diff", "buffs")
	Harness._free_units(_main, [caster])
	await _main.get_tree().process_frame


## No plant: the same activation reads equal, so the two readings agree by themselves (not by a loose comparator).
func test_the_cast_state_is_equal_without_a_plant() -> void:
	for seed in [0, 2]:
		var caster := ParityTable._make_unit(_main, MYSTIC, STAFF)
		var rec := await _shadow_cast(caster, TERROR_SEEKER, seed, "")
		assert_dict(rec).override_failure_message("seed %d: %s" % [seed, rec]) \
			.contains_key_value("equal", true).contains_key_value("first_diff", "")
		Harness._free_units(_main, [caster])
		await _main.get_tree().process_frame


## A token the table already held before a cast-free activation is no difference: "gained this activation" starts from
## the board at the activation's start whether or not it casts (the soak replays every activation of a round).
func test_a_token_held_before_a_cast_free_activation_is_no_buffs_difference() -> void:
	var caster := ParityTable._make_unit(_main, MYSTIC, STAFF)
	_main._solo_spell_tokens_active = [{"unit": caster, "token": "Old Blessing"}]
	_main._solo_core_shadow_h = CoreShadow.capture(_main, caster)
	CoreShadow.note_placed(_main, caster, {"action": AiDecision.Action.HOLD, "moved": false, "casts": []})
	assert_str(CoreShadow._buffs_diff(_main, {})).is_equal("")
	CoreShadow.release(_main)
	Harness._free_units(_main, [caster])
	await _main.get_tree().process_frame


## Default OFF: with the cast switch off the state diff reads neither the token count nor the buffs (an activation whose
## planner spent tokens, or a unit holding a token, must not turn an otherwise equal record unequal).
func test_the_cast_readings_are_off_with_the_cast_switch_off() -> void:
	CoreShadow._cast_env = 0
	var gu := GameUnit.new()
	gu.unit_id = "u"
	gu.unit_properties = {"player_id": 1, "name": "u", "quality": 4, "defense": 4, "special_rules": []}
	gu.casts_current = 3
	var main := StubMain.new()
	main.opr_army_manager = auto_free(OPRArmyManager.new())
	main.opr_army_manager.game_units = {"u": gu}
	main._solo_spell_tokens_active = [{"unit": gu, "token": "Old Blessing"}]
	var core := {"units": {"u": {"alive": 0, "wounds": [], "shaken": false, "fatigued": false, "casts": 2}}}
	assert_str(CoreShadow._state_diff(main, core, {})).is_equal("")


## A token the table already held, cast again by the activation: the table keeps ONE token (its list is a set of names) while
## the core's cast line says "placed". "Gained this activation" counts only what was not live before it (soak 20.11., game 9
## idx 6: Aura of Heroism on a unit that still held it). A token that really is new and missing on the table still differs.
## RED on 56ba3c4e2: the core's side was not filtered by the board at the activation's start, so the re-cast read "buffs".
func test_a_token_cast_again_while_live_is_no_buffs_difference() -> void:
	var caster := ParityTable._make_unit(_main, MYSTIC, STAFF)
	_main._solo_spell_tokens_active = [{"unit": caster, "token": "Terror Seeker"}]
	_main._solo_core_shadow_h = CoreShadow.capture(_main, caster)
	CoreShadow.note_placed(_main, caster, {"action": AiDecision.Action.HOLD, "moved": false, "casts": []})
	assert_str(CoreShadow._buffs_diff(_main, {caster.unit_id: ["Terror Seeker"]})) \
		.override_failure_message("a re-cast of a live token is no difference").is_equal("")
	assert_str(CoreShadow._buffs_diff(_main, {caster.unit_id: ["Terror Seeker", "Infuse Bloodthirst"]})) \
		.override_failure_message("a token the table never placed still differs").is_equal("buffs")
	CoreShadow.release(_main)
	Harness._free_units(_main, [caster])
	await _main.get_tree().process_frame


## The cast_boost plant moves the cast die's target and leaves the payers as the table paid them. RED on 56ba3c4e2: it
## added a boost and overwrote `boost_sources` with the caster alone, so a cast that already carried a boost ("boost 2 but its
## payers give 1") or whose caster held no spare token ("holds 0 token(s)") was REFUSED before any die and never read "rolls"
## (soak 20.11.: 39 of 39 cast records read "refused").
func test_a_planted_boost_reads_rolls_when_the_cast_already_carries_a_boost() -> void:
	var caster := ParityTable._make_unit(_main, MYSTIC, STAFF)
	var paid := [{"unit": caster, "tokens": 1}]
	var rec := await _shadow_cast(caster, TERROR_SEEKER, 0, "cast_boost", {"boost": 1, "boost_sources": paid}, 3, 2)
	assert_dict(rec).override_failure_message("boosted cast: %s" % [rec]) \
		.contains_key_value("equal", false).contains_key_value("first_diff", "rolls")
	Harness._free_units(_main, [caster])
	await _main.get_tree().process_frame


func test_a_planted_boost_reads_rolls_when_the_caster_has_no_spare_token() -> void:
	var caster := ParityTable._make_unit(_main, MYSTIC, STAFF)
	var rec := await _shadow_cast(caster, TERROR_SEEKER, 0, "cast_boost", {}, 1, 1)
	assert_dict(rec).override_failure_message("no spare token: %s" % [rec]) \
		.contains_key_value("equal", false).contains_key_value("first_diff", "rolls")
	Harness._free_units(_main, [caster])
	await _main.get_tree().process_frame


## The die already needs the top number (6+): the plant moves it down, not up into the clamp where nothing would change.
func test_a_planted_boost_reads_rolls_when_the_cast_needs_six() -> void:
	var caster := ParityTable._make_unit(_main, MYSTIC, STAFF)
	var rec := await _shadow_cast(caster, TERROR_SEEKER, 0, "cast_boost", {"base_target": 6})
	assert_dict(rec).override_failure_message("needs 6+: %s" % [rec]) \
		.contains_key_value("equal", false).contains_key_value("first_diff", "rolls")
	Harness._free_units(_main, [caster])
	await _main.get_tree().process_frame
