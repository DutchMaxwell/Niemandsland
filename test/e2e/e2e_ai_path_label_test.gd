extends GdUnitTestSuite
## E2E — DEFECT 4: the AI's corridor distance label was positioned BEFORE it entered the tree.
##
## What shipped broken: _solo_spawn_corridor_distance_label wrote lbl.global_position and only then
## called add_child(). Godot cannot resolve a global transform for a node outside the tree — it logs
## `Condition "!is_inside_tree()" is true. Returning: Transform3D()` and hands back identity — so the
## label silently landed in the wrong place and a self-play batch flooded its log with thousands of
## those lines. Nothing in test/ caught it, because nothing in test/ moves a unit.
##
## WHAT THIS SUITE DRIVES: the REAL scenes/main.tscn (real _ready()), the REAL SoloController wiring,
## and the REAL _solo_animate_move() choreography — the same function an AI activation calls, with the
## same corridor/label/tween/pacing code. Constructed: the move_paths payload (one GameUnit's models
## and their polyline), because producing one from a live AI turn needs a real army import.
##
## TWO INDEPENDENT OBSERVABLES, because each alone is weak:
##  1. assert_error(...).is_success() — the engine error itself, which is what the real flood was.
##  2. A positional check under an OFFSET parent. In play Main sits at identity, and that is precisely
##     why a naive positional assert is TAUTOLOGICAL: setting global_position on a detached node writes
##     straight through to position, so with an identity parent the broken order produces the SAME
##     coordinates as the correct one (measured). Give Main a non-identity transform and the two orders
##     separate: correct = label lands on the path midpoint; broken = it lands offset by Main's origin.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const OFFSET := Vector3(0.0, 0.0, 10.0)   # Main's test-time origin; any non-identity value works

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## Batch + fast: the choreography's fixed 2 s attention beats collapse to nothing and the glide runs at
## 1/PACE_FAST_SCALE speed, so a real activation animation costs a fraction of a second in CI.
func _arm_fast_solo() -> void:
	_main._solo_batch = true
	_main._solo_fast = true
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()


## One model with a straight 3-point route; the shape _solo_animate_move consumes.
func _move_paths(unit: GameUnit, from: Vector3, to: Vector3) -> Array:
	var mid := (from + to) * 0.5
	return [{
		"model": unit.models[0],
		"path": [from, mid, to],
		"radius_m": 0.0125,
	}]


func _labels_on_main() -> Array:
	var out: Array = []
	for c in _main.get_children():
		if c is Label3D:
			out.append(c)
	return out


# DELIBERATELY REMOVED, not forgotten: a blanket "the move animation raises no engine error at all"
# assertion stood here. It passes when this suite runs alone and FAILS in the full run, on an
# unrelated 'Condition "multiplayer_peer.is_null()" is true' left behind by an earlier suite. An
# assertion whose colour depends on its neighbours is worse than none — it teaches everyone to shrug
# at red. The guard against the real defect is the positional test below: it pins WHERE the label
# lands, which is exactly what the broken ordering got wrong, and it does not care who ran before it.


func test_ai_corridor_labels_land_on_their_route_midpoint(timeout := 120000) -> void:
	_arm_fast_solo()
	# The parent is deliberately NOT at identity — see the header: at identity the broken ordering is
	# indistinguishable from the correct one.
	_main.position = OFFSET
	var from := Vector3(-0.4, 0.0, -0.3)
	var to := Vector3(0.1, 0.0, 0.25)
	var u := E2EBoot.make_unit(_main, 2, "Nachtzehrer", [from])
	var paths := _move_paths(u, from, to)
	var route_mid := (from + to) * 0.5

	# An AI move happens in PLAYING, never in deployment — and MoveTrails deliberately builds no chalk
	# while deployment is active (record-only, so nothing pops in when play begins). The boot leaves
	# the scene in the deployment phase, so without this transition the chalk assertion below tests
	# the wrong world and goes red on correct code.
	if _main.opr_army_manager != null and _main.opr_army_manager.has_method("start_game"):
		_main.opr_army_manager.start_game()
		await await_idle_frame()

	await _main._solo_animate_move(paths)

	# _solo_animate_move spawns the distance-truth pace label (one per unit, walked/budget — the
	# per-model corridor labels are gone: ten stacked "6.0\"" blobs on a ten-model unit were the
	# maintainer's "aus der Hölle"). It is a Label3D child of Main and must have been add_child()ed
	# BEFORE its global_position was written.
	var labels := _labels_on_main()
	assert_int(labels.size()) \
		.override_failure_message("the AI move choreography spawned no Label3D at all — the distance readout the maintainer asked for is gone") \
		.is_greater_equal(1)

	# The DURABLE half of the maintainer's ask: the AI's move must leave the same persistent chalk the
	# player's does (ribbon + inch stamp via MoveTrails), not just the 2-second pace label. The first
	# implementation instead stacked one giant Label3D per MODEL — ten overlapping "6.0\"" blobs on a
	# ten-model unit ("aus der Hölle") — and the AI never wrote chalk at all, because commit only ran
	# on selection_dropped, which a choreographed move never fires.
	var trails_node := _main.get_node_or_null("MoveTrails")
	assert_object(trails_node) \
		.override_failure_message("MoveTrails is missing from the booted scene — the chalk system the AI must write into") \
		.is_not_null()
	var committed: Array = trails_node._trails
	assert_int(committed.size()) \
		.override_failure_message("the AI move committed NO chalk trail — its path leaves no persistent inches on the table while the player's own drag does") \
		.is_greater_equal(1)
	var inches := 0.0
	for t in committed:
		inches = maxf(inches, float((t as Dictionary).get("inches", 0.0)))
	assert_float(inches) \
		.override_failure_message("the AI's chalk trail carries no measured inches — the stamp would read 0.0\"") \
		.is_greater(0.0)
	for l in labels:
		var lbl := l as Label3D
		assert_bool(lbl.is_inside_tree()).is_true()
		# X/Z are the route midpoint; Y carries a small per-label lift, so it is not compared.
		assert_float(lbl.global_position.x) \
			.override_failure_message("Label3D '%s' global x = %f, route midpoint x = %f — it was positioned before add_child(), so Godot resolved an identity transform and it landed off the corridor" % [lbl.text, lbl.global_position.x, route_mid.x]) \
			.is_equal_approx(route_mid.x, 0.001)
		assert_float(lbl.global_position.z) \
			.override_failure_message("Label3D '%s' global z = %f, route midpoint z = %f — it was positioned before add_child(), so Godot resolved an identity transform and it landed off the corridor (Main's own origin z = %f)" % [lbl.text, lbl.global_position.z, route_mid.z, OFFSET.z]) \
			.is_equal_approx(route_mid.z, 0.001)
