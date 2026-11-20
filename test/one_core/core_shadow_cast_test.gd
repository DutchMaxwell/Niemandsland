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
## A damage spell: six AP(2) hits at a unit; five of six foes fall on the seeds below, the survivor is the casualty order's call.
const PSYCHIC_BLAST := {"name": "Psychic Blast", "threshold": 1, "range_in": 18,
	"target": {"side": "enemy", "count": 1, "kind": "unit"},
	"effect": {"kind": "damage", "hits": 6, "weapon_rules": ["AP(2)"]}}
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
	CoreShadow._slots_env = -1
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
## the body), flush (the wrapper), release. The debuff lands on a second foe the volley does not shoot at (the once-grant
## on the volley's own target is the next test's), and the caster holds exactly the cast's price (a spare token feeds the
## core's modelled spell rider on a volley, `seam_cast` off).
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


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## CAST-O7 (lead ruling O7, 20.11.): a once-grant cast in an activation BEFORE its own attack is spent by that same volley
## (casting precedes attacking; `_solo_spend_once_mods`). The core placed the record and spent it inside one call, so its
## delta carried no `buffs_spent` and the shadow read `buffs` (table: no token, core: one placed) - the four not-taken records
## of the CC-11 soak (games 4 idx 9 and 14, 5 idx 5, 10 idx 16). Here the once-debuff lands on the volley's OWN target. RED on
## 6e850e5f1: first_diff "buffs" on every seed whose cast die passes. The log line proves the table spent it (no vacuous pass).
func test_a_once_grant_cast_at_the_volleys_target_is_spent_by_it_and_reads_equal() -> void:
	var table_spent := 0
	for seed in [0, 1, 2]:
		var caster := ParityTable._make_unit(_main, MYSTIC, RIFLE)
		var foe := ParityTable._make_unit(_main, FOE, {})
		var cast := {"caster": caster, "caster_unit": caster, "name": "Infuse Bloodthirst", "spell": BLOODTHIRST,
			"targets": [foe], "boost": 0, "interference": 0, "base_target": 4, "threshold": 1,
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
		if _log_text().contains("\"Infuse Bloodthirst\" on Foe is consumed (applies once)"):
			table_spent += 1
		CoreShadow.hold(_main, caster, report, {foe.unit_id: {"target": foe, "shots": shots}}, [foe.unit_id])
		CoreShadow.flush(_main)
		CoreShadow.release(_main)
		assert_int(CoreShadow.records.size()).override_failure_message("seed %d: %s" % [seed, CoreShadow.records]).is_equal(1)
		assert_dict(CoreShadow.records[0]).override_failure_message("seed %d: %s" % [seed, CoreShadow.records]) \
			.contains_key_value("equal", true).contains_key_value("first_diff", "")
		CoreShadow.records.clear()
		Harness._free_units(_main, [caster, foe])
		await _main.get_tree().process_frame
	assert_int(table_spent).override_failure_message("no seed passed the cast die and spent the grant on the table: the test proved nothing").is_greater(0)


## EPOCH_94_PARITY_BATCH (94): WHICH models survive a spell is compared, not only how many. Six foes in a line, a spell that
## kills five: the table's casualty order leaves slot 3 standing, the core's f64 distance left slot 2 (cast door probe, 20.11.);
## the shadow compared counts and a sorted wounds multiset, so it read this equal. RED on a core without the epoch's reading: first_diff
## "positions" at 94; below the epoch the old reading stays (the same cases read "positions" at 93 once NML_CORE_SHADOW_SLOTS asks
## for the compare, and "" without it), so the gate is pinned too.
func test_a_spell_that_kills_five_of_six_leaves_the_same_model_standing() -> void:
	var seen_kill := 0
	for epoch in [94, 93, -93]:   # -93: epoch 93 with the compare switched on
		for seed in [0, 1]:
			CoreShadow._slots_env = 1 if epoch == -93 else -1
			AiActRecorder.rules_epoch = absi(epoch)
			_main.solo_controller._core_header_done = false   # the header carries the epoch: rebuild it for this one
			var caster := ParityTable._make_unit(_main, MYSTIC, STAFF)
			var foe := ParityTable._make_unit(_main, FOE.merged({"models": 6}, true), {})
			var rec := await _shadow_cast(caster, PSYCHIC_BLAST, [foe], seed)
			seen_kill += 1 if foe.get_alive_count() == 1 else 0
			assert_dict(rec).override_failure_message("epoch %d seed %d: %s" % [epoch, seed, rec]) \
				.contains_key_value("first_diff", "positions" if epoch == -93 else "")
			Harness._free_units(_main, [caster, foe])
			await _main.get_tree().process_frame
	CoreShadow._slots_env = -1
	assert_int(seen_kill).override_failure_message("no case killed five of six: the test proved nothing").is_equal(6)
