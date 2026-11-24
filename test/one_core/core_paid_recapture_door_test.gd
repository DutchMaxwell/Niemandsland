extends GdUnitTestSuite
## D-PAR3 step 15b: an AI shooter that CASTS before its volley (cast door off) was refused by the door for `cast` (the board captured
## at the activation start holds no spell effect). Now the table pays the whole pre-volley part (`takes_ai_activation` said no ->
## `report["table_paid"]`), and the volley goes to the core on a RECAPTURE taken right before it (the casts on the board, the
## shooter put back on its move's start spots) with `paid {start, dangerous, beats}` (14a/14b): no die twice.
## Per seed the same activation twice on fresh units and the same tray seed: "table" = the table's resolvers (casts, volley);
## "body" = the AI body's seams (`takes_ai_activation`, `_solo_ai_casts`, `_solo_ai_core_call`), as cast_door_test.gd drives them.
## Real: the main scene, NmlCore, the table's cast and volley resolvers, the door. Constructed: a one-model caster with a rifle
## (Psychic Blast at a six-model foe), HOLD.
## RED (main without 15b): the door refuses the volley (core runs 0) and the table shoots.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const Harness := preload("res://test/one_core/golden_witness_harness.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")

const MYSTIC := {"key": "my", "player": 1, "name": "Mystic", "models": 1, "quality": 4, "defense": 4, "tough": 1,
	"x_in": 0.0, "z_step_in": 1.2, "base_radius_in": 0.63, "game_system": "gf", "faction_folder": "alien_hives",
	"rules": ["Caster"]}
const FOE := {"key": "foe", "player": 2, "name": "Foe", "models": 6, "quality": 4, "defense": 4, "tough": 1,
	"x_in": 8.0, "z_step_in": 1.3, "base_radius_in": 0.63, "game_system": "gf", "faction_folder": "alien_hives",
	"rules": []}
const RIFLE := {"name": "Rifle", "range_in": 24, "attacks": 3, "count": 1, "rules": []}
const PSYCHIC_BLAST := {"name": "Psychic Blast", "threshold": 1, "range_in": 18,
	"target": {"side": "enemy", "count": 1, "kind": "unit"},
	"effect": {"kind": "damage", "hits": 6, "weapon_rules": ["AP(2)"]}}
const SEEDS := 16

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
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
	GraphicsSettings.combat_stage_hold_s = 0.0
	CoreActivation._env = 1
	CoreActivation._cast_env = 0   # the cast door is off: the table casts, the volley may still be the core's (15b)


func after_test() -> void:
	CoreActivation._cast_env = -1
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	GraphicsSettings.combat_stage_hold_s = 2.5
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _run(seed: int, body: bool) -> Dictionary:
	CoreActivation.reset_all(_main)
	var caster := ParityTable._make_unit(_main, MYSTIC, RIFLE)
	var foe := ParityTable._make_unit(_main, FOE, {})
	var cast := {"caster": caster, "caster_unit": caster, "name": str(PSYCHIC_BLAST["name"]), "spell": PSYCHIC_BLAST,
		"targets": [foe], "boost": 0, "interference": 0, "base_target": 4, "threshold": 1,
		"owner_label": "AI (Mystic)", "interference_open": false, "boost_sources": [], "interference_sources": [],
		"conduit": null, "conduit_shaken": [], "pools": []}
	var report := {"action": AiDecision.Action.HOLD, "moved": false, "casts": [cast]}
	var shots: Array = []
	for pr in AiShooting.profiles_in_range([(caster.source_data as OPRApiClient.OPRUnit).weapons[0]], float(FOE["x_in"])):
		shots.append({"member": caster, "quality": caster.get_quality(), "alive": caster.get_alive_count(),
			"max": caster.models.size(), "reach": float(RIFLE["range_in"]), "profile": pr})
	_main._solo_spell_tokens_active.clear()
	caster.casts_current = 1
	var h := CoreActivation.capture(_main, true) if body else 0   # the AI body's capture at the activation start
	caster.spend_caster_points(1)   # the planner pays the attempt at plan time
	_main._solo_act_flags = _main._solo_unit_flags()
	var runs_before := CoreActivation.ai_runs
	CoreShadow.tap.clear()
	CoreShadow.tapping = true
	_main.seed_tray_rng(seed)
	if body:
		_main._solo_core_ai_h = h
		var takes: bool = CoreActivation.takes_ai_activation(_main, caster, report)
		report["table_paid"] = not takes   # main.gd's activation body, beside its `core_takes`
		await _main._solo_ai_casts(caster, report, takes)
		await _main._solo_ai_core_call(caster, report, foe, shots)
		if int(_main._solo_core_ai_h) != 0:
			_main.solo_controller._core_node_ready().release(int(_main._solo_core_ai_h))
		_main._solo_core_ai_h = 0
	else:
		await _main._solo_resolve_ai_casts(report)
		await _main._solo_resolve_ai_volley(caster, foe, shots)
	CoreShadow.tapping = false
	var rolls: Array = CoreShadow.tap.map(func(r: Dictionary) -> String: return "%s|%dx%d+|%s" % [
		str(r["kind"]), int(r["count"]), int(r["target"]), ",".join((r["faces"] as Array).map(func(f: Variant) -> String: return str(int(f))))])
	CoreShadow.tap.clear()
	var out := {"rolls": rolls, "final": Harness._final([caster, foe]), "core_ran": CoreActivation.ai_runs - runs_before,
		"paid": bool(report.get("core_paid", false))}
	for gu in [caster, foe]:
		_main._solo_spell_mods.erase((gu as GameUnit).get_instance_id())
	_main._solo_spell_tokens_active.clear()
	Harness._free_units(_main, [caster, foe])
	await _main.get_tree().process_frame
	return out


@warning_ignore('unused_parameter')
func test_a_casting_shooters_volley_goes_to_the_core_on_a_recapture(timeout := 900000,
		do_skip := not ClassDB.class_exists("NmlCore"), skip_reason := "no NmlCore") -> void:
	var bad: Array = []
	var taken := 0
	for s in SEEDS:
		var table := await _run(s, false)
		var door := await _run(s, true)
		taken += 1 if int(door["core_ran"]) == 1 and bool(door["paid"]) else 0
		if door["rolls"] != table["rolls"]:
			bad.append("seed %d rolls: door %s | table %s" % [s, door["rolls"], table["rolls"]])
		elif door["final"] != table["final"]:
			bad.append("seed %d state: door %s | table %s" % [s, door["final"], table["final"]])
	print("PAID_RECAPTURE seeds=%d taken=%d bad=%d" % [SEEDS, taken, bad.size()])
	assert_int(taken).override_failure_message("the door takes the casting shooter's volley on a recapture (taken %d of %d)" % [taken, SEEDS]).is_equal(SEEDS)
	assert_array(bad).override_failure_message("door against table:\n%s" % "\n".join(bad.slice(0, 3))).is_empty()
