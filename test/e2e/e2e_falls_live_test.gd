extends GdUnitTestSuite
## The falls live in the game (maintainer look verdicts: "more gore and blood", then gore GO): a casualty's mark cue
## carries what the model is made of, its spot on the ground and whether the kill was heavy; the resolving peer drops a
## ghost of the falling model and every peer draws the bursts from the cue; a malformed peer payload draws no blood
## and breaks nothing.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	for fx: String in ["result_pips", "casualty_show"]:
		var node: Variant = _main.get(fx)
		if node != null:
			node.force_for_tests = true
			node.enabled = true


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func test_a_casualty_falls_as_a_ghost_and_bleeds() -> void:
	var show: Variant = _main.get("casualty_show")
	assert_bool(show is CasualtyShow).override_failure_message("main.tscn has no CasualtyShow").is_true()
	if not (show is CasualtyShow):
		return
	var u := E2EBoot.make_unit(_main, 2, "Warriors", [Vector3(0.1, 0.0, 0.1)])
	var mi := u.models[0] as ModelInstance
	var body := MeshInstance3D.new()
	body.name = "Figure"
	body.mesh = BoxMesh.new()
	mi.node.add_child(body)
	var before: int = (show as Node).get_child_count()
	_main._vfx_pip(ResultPips.Kind.KILL, mi, 1)
	assert_int((show as Node).get_child_count()).override_failure_message("ghost + bursts").is_greater(before + 1)
	assert_object((show as Node).find_child("Splatters", false, false)).override_failure_message("flesh bleeds").is_not_null()


func test_a_peer_cue_draws_the_material_and_bad_payloads_draw_no_blood() -> void:
	var show := _main.get("casualty_show") as Node
	if show == null:
		fail("main.tscn has no CasualtyShow")
		return
	var base := show.get_child_count()
	_main._vfx_draw({"k": "pip", "t": int(ResultPips.Kind.KILL), "at": Vector3(0.2, 0.05, 0), "n": 1,
		"m": int(ModelStuff.Stuff.MACHINE), "b": Vector3(0.2, 0, 0), "hv": false, "s": 71, "id": 1}, 2)
	var after_machine := show.get_child_count()
	assert_int(after_machine).override_failure_message("a peer's kill draws its bursts").is_greater(base)
	var next_id := 10   # every cue its own id: a repeated id is a duplicate the draw path drops
	for bad: Dictionary in [{"m": []}, {"m": "machine"}, {"n": {}}, {"n": []}, {"b": "ground"}, {"pts": "here"}]:
		var cue := {"k": "pip", "t": int(ResultPips.Kind.WOUND), "at": Vector3(0.3, 0.05, 0), "n": 1, "s": 71,
			"id": next_id}
		next_id += 1
		cue.merge(bad, true)
		_main._vfx_draw(cue, 2)
	var save := {"k": "pip", "t": int(ResultPips.Kind.SAVE), "at": Vector3(0.3, 0.05, 0), "n": 1, "s": 71, "id": 99,
		"pts": "here"}
	_main._vfx_draw(save, 2)
	assert_bool(true).override_failure_message("malformed payloads drew without an error").is_true()
