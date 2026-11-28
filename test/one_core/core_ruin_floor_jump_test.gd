extends GdUnitTestSuite
## Plan step 27-pre-R R3: from EPOCH_107_RUIN_LEDGES the core sees a free ruin's floors as ledges, so a player's
## skirmish model that walks off a ruin floor in its open activation is rolled ONCE - by the core, when the activation
## resolves; its drop check lists the jump, so the table's JumpRules branch stands aside (P3's guard). One run observes both
## halves: the table's line ("<unit> jumps ...") and the core's ("Jump: <unit> model 1 jumps down ...").
## Real: the main scene, NmlCore, a three-storey sandbox ruin, the drop door, the drop signal, End.

const INCH := 0.0254
const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")

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
	SoloHarness.start(_main, [2], 1)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	SoloHarness.instant(_main)
	SoloHarness.fast(_main)
	SoloHarness.lesson_paused(_main)


func after_test() -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	AiActRecorder.rules_epoch = _epoch_before
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


static func _holds(sl: Dictionary, p: Vector2) -> bool:   # sight.rs BoxFoot::local's frame
	var d := p - (sl["c"] as Vector2)
	var s := sin(float(sl["yaw"]))
	var c := cos(float(sl["yaw"]))
	return absf(d.x * c - d.y * s) <= (sl["he"] as Vector2).x and absf(d.x * s + d.y * c) <= (sl["he"] as Vector2).y


## The top floor and a ground spot 3 in past its short side, on a side where no lower floor lies under the edge or the
## spot (the 3 in floor would make it two plain drops; 3 in leaves the core room to land a fall, `jump_foot`, ruling D13):
## [floor, from, to] (world XZ).
static func _walk_off(slabs: Array) -> Array:
	var top: Dictionary = slabs[0]
	for sl in slabs:
		top = sl if float(sl["y1"]) > float(top["y1"]) else top
	var he: Vector2 = top["he"]
	var k := 0 if he.x < he.y else 1
	var s := sin(float(top["yaw"]))
	var c := cos(float(top["yaw"]))
	var axis := Vector2(c, -s) if k == 0 else Vector2(s, c)   # the inverse of the local frame above
	var half := he.x if k == 0 else he.y
	for sign in [1.0, -1.0]:
		var past: Vector2 = (top["c"] as Vector2) + axis * sign * (half + 0.25 * INCH)   # just over the edge: no lower floor
		var to: Vector2 = (top["c"] as Vector2) + axis * sign * (half + 3.0 * INCH)
		if not slabs.any(func(o: Dictionary) -> bool: return _holds(o, past) or _holds(o, to)):
			return [top, top["c"], to]
	return []


@warning_ignore('unused_parameter')
func test_a_ruin_floor_jump_is_rolled_once(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_107_RUIN_LEDGES
	_main.object_manager.spawn_sandbox_terrain("ruin_large_3f", ObjectManager.SandboxPropKind.RUIN, Vector3.ZERO, false, 7401)
	await _runner.simulate_frames(2)
	var shapes: Array = _main.terrain_overlay._sandbox_shapes()
	var slabs: Array = shapes[0].get("slabs", []) if not shapes.is_empty() else []
	assert_array(slabs).override_failure_message("the three-storey ruin has floors").is_not_empty()
	var walk := _walk_off(slabs)
	assert_array(walk).override_failure_message("a way off the top floor straight to the ground").is_not_empty()
	var top_y := float(walk[0]["y1"])
	print("[R3] top floor %.2f in, from %s to %s" % [top_y / INCH, walk[1], walk[2]])
	var att := ParityTable._make_unit(_main, {"player": 1, "name": "Leaper", "models": 1, "x_in": 0.0, "z_step_in": 1.0,
		"quality": 4, "defense": 4, "tough": 1, "game_system": "gff", "faction_folder": "robot_legions", "rules": []},
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 1, "rules": []})   # a weapon = an OPR profile: the core move path
	var node: Node3D = (att.models[0] as ModelInstance).node
	node.global_position = Vector3(walk[1].x, top_y, walk[1].y)
	CoreActivation._env = 1
	assert_bool(_main.core_activation_start(att)).override_failure_message("no Start").is_true()
	var lines: Array = []
	var tap := func(e: Dictionary) -> void: lines.append(str(e["text"]))
	_main.battle_log.entry_added.connect(tap)
	var from: Vector3 = node.global_position
	node.global_position = Vector3(walk[2].x, 0.0, walk[2].y)
	att.unit_properties["moved_round"] = 1
	assert_bool(_main.attacked_unit_drag_refused(att, 2.0)).override_failure_message("the drop was refused").is_false()
	assert_bool(CoreActivation.core_sees_jump(att.unit_id)).override_failure_message("the core lists the jump").is_true()
	await SoloHarness.drop(_main, [{"node": node, "inches": 2.0, "from_raw": from,
		"path": PackedVector2Array([Vector2(from.x, from.z), Vector2(walk[2].x, walk[2].y)])}])
	await CoreActivation.end(_main, att)
	_main.battle_log.entry_added.disconnect(tap)
	var table := lines.filter(func(l: String) -> bool: return l.begins_with("Leaper jumps "))
	var by_core := lines.filter(func(l: String) -> bool: return l.begins_with("Jump: Leaper model 1 jumps down"))
	assert_array(by_core).override_failure_message("the core rolls the jump: %s" % [lines]).has_size(1)
	assert_array(table).override_failure_message("the table rolled it too: %s" % [lines]).is_empty()
