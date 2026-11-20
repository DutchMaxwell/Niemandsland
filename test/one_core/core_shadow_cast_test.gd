extends GdUnitTestSuite
## CC-10c: with NML_CORE_SHADOW_CAST=1 the shadow replay carries the activation's cast inputs (after the intent, before
## the first faces), keeps the cast / spell legs of the table's tap, reads the core's cast legs by the door's kind map,
## and compares a cast-only activation (no volley) at the end of the AI body.
## RED on main: a cast-only activation is never compared (`records` stays empty) and the kind map reads the core's
## "cast" kind as "cast", not the tray's "attack". Real: the main scene, NmlCore, the table's own
## `_solo_resolve_ai_casts` and its tray. Constructed: golden-grid units with the alien_hives spell book.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const Harness := preload("res://test/one_core/golden_witness_harness.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")

const MYSTIC := {"key": "my", "player": 1, "name": "Mystic", "models": 1, "quality": 4, "defense": 4, "tough": 1,
	"x_in": 0.0, "z_step_in": 1.2, "base_radius_in": 0.63, "game_system": "gf", "faction_folder": "alien_hives",
	"rules": ["Caster"]}
const FOE := {"key": "foe", "player": 2, "name": "Foe", "models": 4, "quality": 4, "defense": 4, "tough": 1,
	"x_in": 8.0, "z_step_in": 1.3, "base_radius_in": 0.63, "game_system": "gf", "faction_folder": "alien_hives",
	"rules": []}
const STAFF := {"name": "Staff", "range_in": 0, "attacks": 1, "count": 1, "rules": []}
const RIFLE := {"name": "Rifle", "range_in": 24, "attacks": 1, "count": 1, "rules": []}
## A friendly once-buff (the token lands on the caster) and an enemy once-debuff (the token lands on the foe).
const TERROR_SEEKER := {"name": "Terror Seeker", "threshold": 1, "range_in": 12,
	"target": {"side": "friendly", "count": 1, "kind": "unit"},
	"effect": {"kind": "buff", "grants_rule": "Hit & Run Fighter", "duration": "once"}}
const BLOODTHIRST := {"name": "Infuse Bloodthirst", "threshold": 1, "range_in": 12,
	"target": {"side": "enemy", "count": 3, "kind": "unit"},
	"effect": {"kind": "debuff", "grants_rule": "Unpredictable Fighter", "duration": "once", "beneficiary": "attackers"}}

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
	_main.solo_ai_slots = {1: true, 2: true}
	_main._ensure_solo_controller()
	_main.solo_controller.ai_slot = 2
	_main.solo_controller.human_slot = 1
	_main.solo_controller.last_move_paths = []
	_main._solo_both_ai = true
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true
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
	CoreShadow.records.clear()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## One cast-only activation through the table's resolver, then the shadow's flush (no volley to hold a compare): the
## capture holds the caster's tokens BEFORE the plan, the plan's spend is mirrored by the test, as `_plan_member_cast` does.
func _shadow_cast(caster: GameUnit, entry: Dictionary, targets: Array, seed: int) -> Dictionary:
	var cast := {"caster": caster, "caster_unit": caster, "name": str(entry["name"]), "spell": entry,
		"targets": targets, "boost": 0, "interference": 0, "base_target": 4, "threshold": 1,
		"owner_label": "AI (%s)" % caster.get_name(), "interference_open": false,
		"boost_sources": [], "interference_sources": [], "conduit": null, "conduit_shaken": [], "pools": []}
	var report := {"action": AiDecision.Action.HOLD, "moved": false, "casts": [cast]}
	_main._solo_spell_tokens_active.clear()   # one activation from a clean token board (the same unit key each iteration)
	caster.casts_current = 3
	_main._solo_core_shadow_h = CoreShadow.capture(_main, caster)
	assert_int(_main._solo_core_shadow_h).override_failure_message("no shadow board").is_not_equal(0)
	caster.spend_caster_points(1)   # the planner pays the attempt before the die; the core pays from the capture
	CoreShadow.note_placed(_main, caster, report)
	_main.seed_tray_rng(seed)
	await _main._solo_resolve_ai_casts(report)
	CoreShadow.flush(_main)
	CoreShadow.release(_main)
	assert_int(CoreShadow.records.size()).override_failure_message("the cast-only activation was not compared").is_greater(0)
	return CoreShadow.records[-1]


## The door's kind map (design: core `cast` -> tray kind attack / leg cast, `spell_*` -> the plain kind / leg spell).
func test_the_core_cast_legs_read_as_the_tray_kind() -> void:
	assert_array(CoreShadow.gate_key({"kind": "cast", "count": 1, "target": 4, "owner": "Mystic"}, false)) \
		.is_equal(["attack", 1, 4, "Mystic"])
	assert_array(CoreShadow.gate_key({"kind": "spell_attack", "count": 3, "target": 6, "owner": "Mystic"}, false)) \
		.is_equal(["attack", 3, 6, "Mystic"])
	assert_array(CoreShadow.gate_key({"kind": "spell_defense", "count": 6, "target": 1, "owner": "Foe"}, false)) \
		.is_equal(["defense", 6, 2, "Foe"])
	assert_array(CoreShadow.gate_key({"kind": "spell_morale", "count": 1, "target": 4, "owner": "Foe"}, false)) \
		.is_equal(["attack", 1, 4, "Foe"])
	# The Fearless re-roll and the No Retreat dice of a spell's morale test are spell legs too (`Tray::tag_spell_morale`).
	for k in ["spell_fearless", "spell_no_retreat"]:
		assert_array(CoreShadow.gate_key({"kind": k, "count": 1, "target": 4, "owner": "Foe"}, false)) \
			.override_failure_message(k).is_equal(["attack", 1, 4, "Foe"])
		assert_bool(CoreShadow._leg_ok({"kind": k}, {"leg": "spell"})).override_failure_message(k).is_true()
		assert_bool(CoreShadow._leg_ok({"kind": k}, {"leg": "main"})).override_failure_message(k).is_false()


## A cast-only activation (a buff on the caster) replays equal: the cast die's face, the spend and the token. Seed 1 fails
## the 4+ die on the table (no token), the others pass it; both readings must agree.
func test_a_cast_only_activation_replays_equal() -> void:
	for seed in [0, 1, 2]:
		var caster := ParityTable._make_unit(_main, MYSTIC, STAFF)
		var rec := await _shadow_cast(caster, TERROR_SEEKER, [caster], seed)
		assert_dict(rec).override_failure_message("seed %d: %s" % [seed, rec]) \
			.contains_key_value("equal", true).contains_key_value("first_diff", "")
		assert_array(rec["deny"]).override_failure_message("the casts were sent: no 'cast' deny").not_contains(["cast"])
		Harness._free_units(_main, [caster])
		await _main.get_tree().process_frame


## A debuff on another unit: its token lands on the foe, so the per-unit reading covers more than the caster.
func test_a_debuff_on_a_foe_replays_equal() -> void:
	for seed in [0, 2]:
		var caster := ParityTable._make_unit(_main, MYSTIC, STAFF)
		var foe := ParityTable._make_unit(_main, FOE, {})
		var rec := await _shadow_cast(caster, BLOODTHIRST, [foe], seed)
		assert_dict(rec).override_failure_message("seed %d: %s" % [seed, rec]).contains_key_value("equal", true)
		Harness._free_units(_main, [caster, foe])
		await _main.get_tree().process_frame


## Default OFF: with the cast switch off the same activation is not replayed at all (the old shadow, byte-identical).
func test_the_cast_replay_is_off_by_default() -> void:
	CoreShadow._cast_env = 0
	var caster := ParityTable._make_unit(_main, MYSTIC, STAFF)
	caster.casts_current = 3
	var entry := TERROR_SEEKER
	var cast := {"caster": caster, "caster_unit": caster, "name": str(entry["name"]), "spell": entry, "targets": [caster],
		"boost": 0, "interference": 0, "base_target": 4, "threshold": 1, "owner_label": "AI (Mystic)",
		"interference_open": false, "boost_sources": [], "interference_sources": [], "conduit": null,
		"conduit_shaken": [], "pools": []}
	var report := {"action": AiDecision.Action.HOLD, "moved": false, "casts": [cast]}
	_main._solo_core_shadow_h = CoreShadow.capture(_main, caster)
	caster.spend_caster_points(1)
	CoreShadow.note_placed(_main, caster, report)
	_main.seed_tray_rng(0)
	await _main._solo_resolve_ai_casts(report)
	CoreShadow.flush(_main)
	CoreShadow.release(_main)
	assert_int(CoreShadow.records.size()).is_equal(0)
	Harness._free_units(_main, [caster])
	await _main.get_tree().process_frame


## An activation that casts AND shoots: the volley's hold carries the casts, so the body's second flush (its wrapper's, on
## every exit) must find nothing left to compare. RED on 56ba3c4e2: `flush` kept `_cast_pending` after the held compare, so a
## second, cast-only record followed every cast+volley activation (targets [], first_diff "table_rolled_more": the tap still
## held the volley's dice). The order below is the body's: capture, plan spend, placement, casts, volley, hold, flush (end of
## the body), flush (the wrapper), release. The debuff lands on a second foe the volley does not shoot at (a once-grant on
## the volley's own target is spent by that volley on the table, which the core does not report yet), and the caster holds
## exactly the cast's price (a spare token feeds the core's modelled spell rider on a volley).
func test_a_cast_and_volley_activation_yields_exactly_one_record() -> void:
	for seed in [0, 1, 2]:
		var caster := ParityTable._make_unit(_main, MYSTIC, RIFLE)
		var foe := ParityTable._make_unit(_main, FOE, {})
		var other := ParityTable._make_unit(_main, FOE.merged({"key": "other", "name": "Other", "x_in": 9.0}, true), {})
		var cast := {"caster": caster, "caster_unit": caster, "name": "Infuse Bloodthirst", "spell": BLOODTHIRST,
			"targets": [other], "boost": 0, "interference": 0, "base_target": 4, "threshold": 1,
			"owner_label": "AI (Mystic)", "interference_open": false, "boost_sources": [], "interference_sources": [],
			"conduit": null, "conduit_shaken": [], "pools": []}
		var report := {"action": AiDecision.Action.HOLD, "moved": false, "casts": [cast]}
		_main._solo_spell_tokens_active.clear()
		caster.casts_current = 1
		_main._solo_core_shadow_h = CoreShadow.capture(_main, caster)
		assert_int(_main._solo_core_shadow_h).override_failure_message("no shadow board").is_not_equal(0)
		caster.spend_caster_points(1)
		CoreShadow.note_placed(_main, caster, report)
		_main.seed_tray_rng(seed)
		await _main._solo_resolve_ai_casts(report)
		var dist_in := float(FOE["x_in"]) - float(MYSTIC["x_in"])
		var shots: Array = []
		for pr in AiShooting.profiles_in_range([(caster.source_data as OPRApiClient.OPRUnit).weapons[0]], dist_in):
			shots.append({"member": caster, "quality": caster.get_quality(), "alive": caster.get_alive_count(),
				"max": caster.models.size(), "reach": float(RIFLE["range_in"]), "profile": pr})
		await _main._solo_resolve_ai_volley(caster, foe, shots)
		CoreShadow.hold(_main, caster, report, {foe.unit_id: {"target": foe, "shots": shots}}, [foe.unit_id])
		CoreShadow.flush(_main)   # main.gd:1374, the body's own
		CoreShadow.flush(_main)   # main.gd:1124, the wrapper's on every exit
		CoreShadow.release(_main)
		assert_int(CoreShadow.records.size()).override_failure_message("seed %d: %s" % [seed, CoreShadow.records]).is_equal(1)
		assert_dict(CoreShadow.records[0]).override_failure_message("seed %d: %s" % [seed, CoreShadow.records]) \
			.contains_key_value("equal", true).contains_key_value("targets", ["Foe"])
		CoreShadow.records.clear()
		Harness._free_units(_main, [caster, foe, other])
		await _main.get_tree().process_frame
