extends GdUnitTestSuite
## Fable A6 / F6 (epoch 73) — DOUBT, not a known fix yet: a human Artillery unit SHOOTS first (the
## shooting activation completes and stamps `is_activated`) and is priced as Held, because the table's
## Hold is "not moved this round" (`moved_round`). Can the player then still drag it? If so the same
## activation both earns Hold's +1 and advances — the table and the core (`att.held = kind == HOLD`)
## would disagree.
##
## This suite drives the REAL table flow: the real resolver (`_run_human_attack`, which completes the
## activation) and the real release seam of a player drag (`ObjectManager._stop_dragging`, the same door
## the hotseat snap-back suite uses). It asserts the invariant: after the shot, a later move is refused
## (the base returns to its pre-drag spot and `moved_round` stays unset).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _epoch0: int
var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	RulesRegistry.reset_cache()
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true   # fair faces, drawn instantly


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0
	RulesRegistry.reset_cache()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## A registered human (slot 1) gun carrying the Artillery rule; `foe` is the AI-side target.
func _gun(pos: Vector3, unit_name: String) -> GameUnit:
	var u := E2EBoot.make_unit(_main, 1, unit_name, [pos])
	u.unit_properties.merge({"quality": 4, "defense": 4, "special_rules": ["Artillery"],
		"game_system": "gf", "faction_folder": "some_book"}, true)
	var opr := OPRApiClient.OPRUnit.new()
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Cannon"
	w.range_value = 36
	w.attacks = 2
	var ws: Array[OPRApiClient.OPRWeapon] = [w]
	opr.weapons = ws
	u.source_type = "opr"
	u.source_data = opr
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _foe(pos: Vector3) -> GameUnit:
	var u := E2EBoot.make_unit(_main, 2, "Foe", [pos])
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## A solo controller with the foe on the AI slot (so its saves/casualties are automated) but the AI
## reply pinned shut: the doubt is about the human's own post-shot drag, so the fixture must not roll
## the table into the AI's turn after the shot.
func _controller_without_reply() -> void:
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main._solo_ai_busy = true   # `_solo_pump` early-returns: the owed reply never runs


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## The real release seam: the object manager carries the drag state a pickup sets, then
## `_stop_dragging()` commits the drop or snaps it back (the hotseat snap-back suite's shape).
func _drag(node: Node3D, from: Vector3, to: Vector3) -> void:
	var om: ObjectManager = _main.object_manager
	om._selected_objects = [node]
	om._drag_start_positions[node] = from
	om._drag_start_rotations[node] = node.rotation.y
	om._drag_anchor_object = node
	om._drag_anchor_position = from
	om._drag_path_points = PackedVector2Array([Vector2(from.x, from.z), Vector2(to.x, to.z)])
	om._is_dragging = true
	node.global_position = to
	om._stop_dragging()
	await E2EBoot.settle(get_tree())


## The doubt: shoot first (Held bonus applied), then drag 6". The table must refuse that move.
func test_a_shooting_artillery_unit_cannot_then_advance(timeout := 240000) -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	_controller_without_reply()
	var gun := _gun(Vector3.ZERO, "Gun")
	var foe := _foe(Vector3(17.0 * INCH, 0, 0))   # edge gap well past the 12" Hold gate
	var from: Vector3 = (gun.models[0] as ModelInstance).node.global_position
	await _main._run_human_attack(gun, foe, false)   # the real shooting activation
	await E2EBoot.settle(get_tree())
	var log_after_shot := _log_text()
	assert_bool(gun.is_activated) \
		.override_failure_message("the shooting attack must complete the activation (log: %s)" % log_after_shot.strip_edges()) \
		.is_true()
	assert_str(log_after_shot) \
		.override_failure_message("the shot must be priced as Held at 15\"+ (log: %s)" % log_after_shot.strip_edges()) \
		.contains("Artillery +1 (Held, target over 12\")")
	assert_bool(gun.unit_properties.has("moved_round")).is_false()   # Held = not moved this round
	var node: Node3D = (gun.models[0] as ModelInstance).node
	await _drag(node, from, from + Vector3(6.0 * INCH, 0, 0))
	var log_after_drag := _log_text()
	assert_vector(node.global_position) \
		.override_failure_message("a unit that already attacked still moved: the drag was not refused (log: %s)" % log_after_drag.strip_edges()) \
		.is_equal_approx(from, Vector3.ONE * 0.0001)
	assert_bool(gun.unit_properties.has("moved_round")) \
		.override_failure_message("a refused post-shot drag must not stamp moved_round (log: %s)" % log_after_drag.strip_edges()) \
		.is_false()
	assert_str(log_after_drag) \
		.override_failure_message("the refusal must name the unit and why (log: %s)" % log_after_drag.strip_edges()) \
		.contains("has already shot this round — it cannot move now")


## Lead 09:16: the lock is the SHOT, not the activation — a melee survivor keeps its
## post-melee containment/back-step drag (the old is_activated read refused it).
func test_the_post_melee_containment_drag_still_works(timeout := 240000) -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	_controller_without_reply()
	var gun := _gun(Vector3.ZERO, "Gun")
	var foe := _foe(Vector3(1.0 * INCH, 0, 0))
	await _main.begin_activation(gun)
	await _main._run_human_melee(gun, foe)
	await E2EBoot.settle(get_tree())
	var node: Node3D = (gun.models[0] as ModelInstance).node
	var from := node.global_position
	await _drag(node, from, from + Vector3(0, 0, 3.0 * INCH))
	assert_vector(node.global_position) \
		.override_failure_message("a melee survivor's containment drag was refused (log: %s)" % _log_text().strip_edges()) \
		.is_equal_approx(from + Vector3(0, 0, 3.0 * INCH), Vector3.ONE * 0.0001)


## Lead 11:17: the Hit & Run family lets a HUMAN make its one post-shot step by dragging - 2.5" stands
## and is logged like the AI step, a second drag in the same round is refused.
func test_a_human_hit_and_run_shooter_makes_its_one_post_shot_step(timeout := 240000) -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	_controller_without_reply()
	var gun := _gun(Vector3.ZERO, "Gunner")
	gun.unit_properties["special_rules"] = ["Artillery", "Hit & Run Shooter"]
	# The registry is the source of the family: the book must actually carry the half-variant.
	gun.unit_properties["faction_folder"] = "custodian_brothers"
	RulesRegistry.reset_cache()
	var foe := _foe(Vector3(17.0 * INCH, 0, 0))
	await _main._run_human_attack(gun, foe, false)
	await E2EBoot.settle(get_tree())
	var node: Node3D = (gun.models[0] as ModelInstance).node
	var from := node.global_position
	await _drag(node, from, from + Vector3(0, 0, 2.5 * INCH))
	assert_vector(node.global_position) \
		.override_failure_message("a Hit & Run Shooter's 2.5\" step was refused (log: %s)" % _log_text().strip_edges()) \
		.is_equal_approx(from + Vector3(0, 0, 2.5 * INCH), Vector3.ONE * 0.0001)
	assert_str(_log_text()) \
		.override_failure_message("the human step must be logged like the AI one") \
		.contains("Hit & Run Shooter: Gunner steps up to 2.5\" after shooting")
	var after_step := node.global_position
	await _drag(node, after_step, after_step + Vector3(0, 0, 2.0 * INCH))
	assert_vector(node.global_position) \
		.override_failure_message("a SECOND post-shot step must be refused (log: %s)" % _log_text().strip_edges()) \
		.is_equal_approx(after_step, Vector3.ONE * 0.0001)


## The 3" ceiling: a first 4" post-shot drag is refused even for a bearer.
func test_a_human_hit_and_run_step_longer_than_three_inches_is_refused(timeout := 240000) -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	_controller_without_reply()
	var gun := _gun(Vector3.ZERO, "Gunner")
	gun.unit_properties["special_rules"] = ["Artillery", "Hit & Run Shooter"]
	# The registry is the source of the family: the book must actually carry the half-variant.
	gun.unit_properties["faction_folder"] = "custodian_brothers"
	RulesRegistry.reset_cache()
	var foe := _foe(Vector3(17.0 * INCH, 0, 0))
	await _main._run_human_attack(gun, foe, false)
	await E2EBoot.settle(get_tree())
	var node: Node3D = (gun.models[0] as ModelInstance).node
	var from := node.global_position
	await _drag(node, from, from + Vector3(0, 0, 4.0 * INCH))
	assert_vector(node.global_position) \
		.override_failure_message("a 4\" Hit & Run step was allowed (log: %s)" % _log_text().strip_edges()) \
		.is_equal_approx(from, Vector3.ONE * 0.0001)
