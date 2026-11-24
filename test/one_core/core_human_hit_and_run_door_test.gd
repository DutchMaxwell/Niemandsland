extends GdUnitTestSuite
## PLAN_FIRST_DELETION step 21: the human door takes a Hit & Run shooter. Its intent says `no_step` (step 20): the core resolves the
## volley, takes NO Hit & Run step and keeps the round's use open, so the player drags the step (as on the table, fab_a6). Before, the
## door left such a unit to `_run_human_shooting` (H-30), which the deletion removes.
## Real: the main scene, NmlCore, the human session ("Activate"), `_run_human_attack`, the live deny slice. Constructed: a 3-model gf
## unit with Hit & Run Shooter and a rifle, a foe 10" away, no drop (Hold).
## RED (on main): the door does not take the unit - the table's volley runs (`human_shoot` legacy +1).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SIDE := {"quality": 3, "defense": 4, "tough": 1, "z_step_in": 1.5, "game_system": "gf",
	"faction_folder": "custodian_brothers", "rules": []}
const RIFLE := {"name": "Rifle", "range_in": 24, "attacks": 4, "count": 3, "rules": []}
const SEEDS := 4

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	SoloHarness.start(_main, [2], 1)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	SoloHarness.instant(_main)
	CoreActivation._env = 1
	CoreSlice.path_override = ""
	CoreSlice.reset_cache()


func after_test() -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## One human activation of the Hit & Run shooter: Start, no drop, Shoot. Returns what the door did.
func _shoot(s: int) -> Dictionary:
	_main.opr_army_manager.current_round = 1
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Runners", "models": 3, "x_in": 0.0,
		"rules": ["Hit & Run Shooter"]}, true), RIFLE)
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Foe", "models": 5, "x_in": 10.0,
		"faction_folder": "robot_legions"}, true), {})
	foe.is_activated = true   # no AI reply
	for m in att.models:
		m.node.set_meta("network_id", 801 + att.models.find(m))
		m.node.set_meta("model_instance", m)
	var core_unit := CoreActivation.is_core_unit(_main, att)
	var legacy0 := int((CoreActivation.legacy.get("human_shoot", {}) as Dictionary).get("_all", 0))
	var at: Array = att.get_alive_models().map(func(m: ModelInstance) -> Vector3: return m.node.global_position)
	var lines: Array = []
	var tap := func(e: Dictionary) -> void: lines.append(str(e["text"]))
	_main.battle_log.entry_added.connect(tap)
	assert_bool(_main.core_activation_start(att)).override_failure_message("seed %d: no Start" % s).is_true()
	_main.seed_tray_rng(s)
	await _main._run_human_attack(att, foe, false)
	_main.battle_log.entry_added.disconnect(tap)
	var moved := 0.0
	var now: Array = att.get_alive_models().map(func(m: ModelInstance) -> Vector3: return m.node.global_position)
	for i in mini(at.size(), now.size()):
		moved = maxf(moved, Vector2((at[i] as Vector3).x, (at[i] as Vector3).z).distance_to(Vector2((now[i] as Vector3).x, (now[i] as Vector3).z)))
	var out := {"core_unit": core_unit, "table_volleys": int((CoreActivation.legacy.get("human_shoot", {}) as Dictionary).get("_all", 0)) - legacy0,
		"moved_in": moved / 0.0254, "hnr_round": int(att.unit_properties.get("hit_and_run_round", -1)),
		"foe_alive": foe.get_alive_count(), "fired": lines.any(func(l: String) -> bool: return l.contains("fires at") or l.contains("Rifle"))}
	CoreActivation.close_session(_main, att.unit_id)
	for u in [att, foe]:
		_main.opr_army_manager.game_units.erase((u as GameUnit).unit_id)
		for m in (u as GameUnit).models:
			if (m as ModelInstance).node != null and is_instance_valid((m as ModelInstance).node):
				(m as ModelInstance).node.free()
	await _main.get_tree().process_frame
	return out


@warning_ignore('unused_parameter')
func test_the_human_door_takes_a_hit_and_run_shooter_and_leaves_the_step_to_the_player(timeout := 600000,
		do_skip := not ClassDB.class_exists("NmlCore"), skip_reason := "no NmlCore") -> void:
	var rows: Array = []
	for s in SEEDS:
		rows.append(await _shoot(s))
	for s in rows.size():
		var r: Dictionary = rows[s]
		assert_bool(bool(r["core_unit"])).override_failure_message("seed %d: the Hit & Run shooter is a core unit (%s)" % [s, r]).is_true()
		assert_int(int(r["table_volleys"])).override_failure_message("seed %d: no table volley (%s)" % [s, r]).is_equal(0)
		assert_bool(bool(r["fired"])).override_failure_message("seed %d: the volley fired (%s)" % [s, r]).is_true()
		assert_float(float(r["moved_in"])).override_failure_message("seed %d: the core took no Hit & Run step (%s)" % [s, r]).is_less(0.01)
		assert_int(int(r["hnr_round"])).override_failure_message("seed %d: the round's use stays open for the drag (%s)" % [s, r]).is_not_equal(1)
	assert_int(rows.filter(func(r: Dictionary) -> bool: return int(r["foe_alive"]) < 5).size()) \
		.override_failure_message("no seed hurt the foe: the check proved nothing (%s)" % [rows]).is_greater(0)
