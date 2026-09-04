extends GdUnitTestSuite
## E2E — audit row 3: the live LOS line + per-model "N/M sight" count while targeting also works
## against a HUMAN opponent in a multiplayer room, not only against the solo AI opponent.
##
## THE GATE. main.gd _solo_update_los_line bailed out unless _solo_is_ai_unit(hovered) — in a plain
## human-vs-human room nobody is an AI unit, so the line never showed for the only enemies that
## exist there. The fix adds a second disjunct: in a live multiplayer session, a hovered unit
## belonging to a DIFFERENT player_id than the attacker counts too. The AI disjunct stays as one
## branch of the OR, so solo behaviour is preserved unchanged (control test at the bottom).
##
## HOW THIS IS DRIVEN. The real UI path into targeting mode is itself gated by audit row 1
## (declare attack — out of scope this wave, needs a design decision), so the suite sets
## _solo_target_mode directly at the audited seam and calls _solo_update_los_line with a real
## camera unproject over the target's miniature: the pick still runs the real physics raycast
## (_solo_pick_unit_at), only the menu clicks are bypassed.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")


## Stands in for NetworkManager at main's seam: a live session. `slot_has_human_peer` stays
## false — a plain human-vs-human room, no AI-held slot anywhere.
class FakeNet extends Node:
	var active: bool = true
	func is_multiplayer_active() -> bool:
		return active
	func slot_has_human_peer(_slot: int) -> bool:
		return false


var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _fake: FakeNet


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(10)
	# A PLAIN human-vs-human room: NO solo AI slot is designated — the configuration in which the
	# gate was dead, because every unit on the table belongs to a human player.
	_main.solo_ai_slots = {}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true
	_fake = auto_free(FakeNet.new())
	_main.network_manager = _fake


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	_fake = null


## One real miniature via the SHIPPED spawn path (StaticBody3D + collider, so the pick ray can
## actually hit it), wired into a one-model GameUnit owned by `pid`.
func _spawn_unit(pid: int, unit_name: String, pos: Vector3) -> GameUnit:
	var node: Node3D = (_main.object_manager as Object).call("spawn_miniature", pos, false)
	var unit := GameUnit.new()
	unit.unit_id = "e2e_mp_los_p%d_%s" % [pid, unit_name]
	unit.unit_properties = {"player_id": pid, "name": unit_name, "quality": 4, "defense": 4}
	var mi := ModelInstance.new()
	mi.is_alive = true
	mi.unit = unit
	mi.node = node
	unit.models.append(mi)
	node.set_meta("game_unit", unit)
	return unit


## Register a fixture unit on the army manager the way a fielded unit is.
func _register(u: GameUnit) -> void:
	_main.opr_army_manager.game_units[u.unit_id] = u


## Place an attacker (pid_a) and a target (pid_b) on open table and return [attacker, target,
## screen_point] where the point is one the REAL pick resolves to the target — scanned over the
## table like e2e_click_drop_test, so camera framing can never silently starve the suite.
func _place_pair(pid_a: int, pid_b: int) -> Array:
	var cam: Camera3D = _main.get_viewport().get_camera_3d()
	if cam == null:
		return [null, null, Vector2.INF]
	for wz in [0.15, 0.30, 0.0, -0.15]:
		for wx in [0.20, 0.40, 0.0, -0.20]:
			var origin := Vector3(float(wx), 0.0, float(wz))
			var target := _spawn_unit(pid_b, "Raiders", origin + Vector3(0.25, 0.0, 0.0))
			var attacker := _spawn_unit(pid_a, "Riflemen", origin)
			# One frame so the physics space has registered the fresh bodies (the pick is a raycast).
			await _runner.simulate_frames(1)
			var pt: Vector2 = cam.unproject_position(origin + Vector3(0.25, 0.016, 0.0))
			if _main._solo_pick_unit_at(pt) == target:
				_register(attacker)
				_register(target)
				return [attacker, target, pt]
			_free_unit(target)
			_free_unit(attacker)
	return [null, null, Vector2.INF]


## Free a fixture unit's MODEL NODES (a GameUnit is RefCounted — only its nodes live in the tree).
func _free_unit(u: GameUnit) -> void:
	for m in u.models:
		var n: Node3D = (m as ModelInstance).node
		if n != null and is_instance_valid(n):
			n.queue_free()


## Enter targeting mode at the audited seam (the real UI path is audit row 1, out of scope) and
## drive the function under test with the scanned screen point.
func _hover_target(attacker: GameUnit, pt: Vector2) -> void:
	_main._solo_target_mode = {"unit": attacker, "melee": false}
	_main._solo_update_los_line(pt)


func _line_shown() -> bool:
	var line: MeshInstance3D = _main._solo_los_line
	return line != null and line.visible


func _label_shown() -> bool:
	var label: Label3D = _main._solo_los_label
	return label != null and label.visible


# === 1. The MP gate (audit row 3) ================================================================

## THE CLAIM: in a live human-vs-human room, hovering the enemy while targeting shows the live LOS
## line + "N/M sight" label. Before this wave the gate refused every human-owned unit, and the
## line stayed dark over the ONLY enemies a plain MP room has.
func test_the_line_shows_over_a_different_player_id_target_in_multiplayer(timeout := 120000) -> void:
	var pair := await _place_pair(1, 2)
	var attacker: GameUnit = pair[0]
	var target: GameUnit = pair[1]
	var pt: Vector2 = pair[2]
	assert_bool(attacker != null) \
		.override_failure_message("fixture check: no clickable attacker spot found") \
		.is_true()
	assert_bool(target != null) \
		.override_failure_message("fixture check: no clickable target spot found") \
		.is_true()
	assert_vector(pt).is_not_equal(Vector2.INF)
	assert_bool(int(target.unit_properties.get("player_id", 0)) != int(attacker.unit_properties.get("player_id", 0))) \
		.override_failure_message("fixture check: the two units must belong to different players") \
		.is_true()

	_hover_target(attacker, pt)

	assert_bool(_line_shown()) \
		.override_failure_message("the live LOS line stays dark while targeting a human opponent's unit in multiplayer") \
		.is_true()
	assert_bool(_label_shown()) \
		.override_failure_message("the per-model sight count stays hidden alongside the line") \
		.is_true()


# === 2. Counter-proofs ===========================================================================

## Ownership matters: in the same room, hovering a unit of the attacker's OWN side must stay dark.
func test_the_line_stays_hidden_over_a_same_player_id_unit(timeout := 120000) -> void:
	var pair := await _place_pair(1, 1)
	var attacker: GameUnit = pair[0]
	assert_bool(attacker != null) \
		.override_failure_message("fixture check: no clickable spot found") \
		.is_true()

	_hover_target(attacker, pair[2])

	assert_bool(_line_shown()) \
		.override_failure_message("a friendly unit of the same player lit the LOS line in multiplayer") \
		.is_false()
	assert_bool(_label_shown()).is_false()


## The solo disjunct is untouched: offline, a designated AI slot's unit still shows the line —
## the original check's result is preserved as one disjunct of the OR.
func test_the_solo_ai_path_is_unchanged(timeout := 120000) -> void:
	_fake.active = false
	_main.solo_ai_slots = {2: true}
	var pair := await _place_pair(1, 2)
	var attacker: GameUnit = pair[0]
	assert_bool(attacker != null) \
		.override_failure_message("fixture check: no clickable spot found") \
		.is_true()
	assert_bool(_main._solo_is_ai_unit(pair[1])) \
		.override_failure_message("fixture check: the pid-2 unit must resolve as the AI's here") \
		.is_true()

	_hover_target(attacker, pair[2])

	assert_bool(_line_shown()) \
		.override_failure_message("the solo AI targeting line stopped showing") \
		.is_true()
