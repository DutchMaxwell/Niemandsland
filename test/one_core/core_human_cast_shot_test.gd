extends GdUnitTestSuite
## A human unit whose caster resolved a spell in this activation does not fire through the core: the core captured the
## board at the Start, before the table resolved the spell, so it would roll the volley against a board with no spell
## effect. The door leaves that volley to the table's own roll (reason `cast_this_activation`) for the single shot and
## for a declared split alike. A unit that did not cast is still taken.
## Real: the main scene, NmlCore, the human session ("Activate"), the real human cast path, the door's refusal line.
## Constructed: plain gf units and their positions.
## RED (on main): the door takes the shot after the cast (dice thrown, `last_target` set).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}
const RIFLE := {"name": "Rifle", "range_in": 24, "attacks": 1, "count": 5, "rules": []}
const REASON := "cast_this_activation"

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
	_main.opr_army_manager.current_round = 1
	SoloHarness.instant(_main)
	SoloHarness.auto_saves(_main)
	CoreActivation._env = 1
	CoreSlice.path_override = ""
	CoreSlice.reset_cache()


func after_test() -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## A plain gf unit of 5 models at `x_in`.
func _unit(pid: int, uname: String, x_in: float) -> GameUnit:
	var u := ParityTable._make_unit(_main, SIDE.merged({"player": pid, "name": uname, "models": 5, "x_in": x_in}, true), RIFLE)
	for i in u.models.size():
		(u.models[i] as ModelInstance).node.set_meta("network_id", 700 + pid * 100 + i)
		(u.models[i] as ModelInstance).node.set_meta("model_instance", u.models[i])
	return u


func _free(units: Array) -> void:
	for u in units:
		_main.opr_army_manager.game_units.erase((u as GameUnit).unit_id)
		for m in (u as GameUnit).models:
			if (m as ModelInstance).node != null and is_instance_valid((m as ModelInstance).node):
				(m as ModelInstance).node.free()


## The unit's Start with Advance declared on the selector.
func _started(att: GameUnit) -> void:
	CoreActivation.last_target = null
	assert_bool(CoreActivation.open_session(_main, att)).override_failure_message("no session").is_true()
	_main.object_manager.set_movement_cap(ObjectManager.MovementCap.ADVANCE)


## A resolved spell of this activation: the caster spends its token and the real human cast path rolls it.
func _cast(att: GameUnit, foe: GameUnit) -> void:
	att.casts_current = 1
	var before := att.casts_current
	await SoloHarness.cast(_main, att, {"name": "Bolt", "threshold": 1}, [foe])
	assert_int(att.casts_current).override_failure_message("the cast spent no token").is_equal(before - 1)


@warning_ignore('unused_parameter')
func test_a_shot_after_a_cast_stays_on_the_table(timeout := 120000) -> void:
	var att := _unit(1, "Seer", 0.0)
	var foe := _unit(2, "Raiders", 12.0)
	_started(att)
	await _cast(att, foe)
	var lines: Array = []
	var tap := func(e: Dictionary) -> void: lines.append(str(e["text"]))
	_main.battle_log.entry_added.connect(tap)
	var throws := [0]
	var taken: bool = await CoreActivation.human_shoot(_main, att, foe, func(_k: String, _i: int) -> void: throws[0] += 1)
	_main.battle_log.entry_added.disconnect(tap)
	assert_bool(taken).override_failure_message("the core took the shot after this activation's cast").is_false()
	assert_int(throws[0]).override_failure_message("a die was thrown for a refused shot").is_equal(0)
	assert_bool(CoreActivation.last_target == null).override_failure_message("last_target set by a refused shot").is_true()
	assert_array(lines.filter(func(l: String) -> bool: return l.contains(REASON))) \
		.override_failure_message("no refusal line names %s: %s" % [REASON, lines]).is_not_empty()
	CoreActivation.close_session(_main, att.unit_id)
	_free([att, foe])


@warning_ignore('unused_parameter')
func test_a_split_after_a_cast_stays_on_the_table(timeout := 120000) -> void:
	var att := _unit(1, "Seer", 0.0)
	var a := _unit(2, "DefA", 12.0)
	var b := _unit(2, "DefB", 30.0)
	_started(att)
	await _cast(att, a)
	var taken: bool = await CoreActivation.human_shoot_split(_main, att, a, b, [])
	assert_bool(taken).override_failure_message("the core took the split after this activation's cast").is_false()
	assert_bool(CoreActivation.last_target == null).override_failure_message("last_target set by a refused split").is_true()
	assert_int(a.get_alive_count()).is_equal(5)
	CoreActivation.close_session(_main, att.unit_id)
	_free([att, a, b])


## Control: the same door takes the same volley when this activation resolved no spell.
@warning_ignore('unused_parameter')
func test_a_shot_without_a_cast_is_taken(timeout := 120000) -> void:
	var att := _unit(1, "Rifles", 0.0)
	var foe := _unit(2, "Raiders", 12.0)
	_started(att)
	var throws := [0]
	var taken: bool = await CoreActivation.human_shoot(_main, att, foe, func(_k: String, _i: int) -> void: throws[0] += 1)
	assert_bool(taken).override_failure_message("a plain volley was left to the table").is_true()
	assert_bool(CoreActivation.last_target == foe).override_failure_message("the core did not resolve the volley").is_true()
	CoreActivation.close_session(_main, att.unit_id)
	_free([att, foe])
