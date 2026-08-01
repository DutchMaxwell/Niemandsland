extends GdUnitTestSuite
## E2E — NML-933: a reanimated REGIMENT model comes back in its block's rank, not on a ring spot.
##
## THE DEFECT. _solo_apply_reanimation placed every returning model itself: it looked for a free spot
## in coherency with a survivor (_solo_reanimation_spot) and wrote it as a WORLD position. For a loose
## skirmish model that is exactly right. A regiment model, however, is parented to its movement tray
## and its place is the rank the block hands it — the revive seam re-ranks the whole block
## (RegimentTray.reform_from_unit, the AoF:R rank-removal/-return the manual wound workflow uses), and
## the coherency spot was then written ON TOP of that result. The returning rank model teleported out
## of its own block, taking the tray's geometry with it.
##
## The MP peer never had the defect: it only ever receives the wounds message and re-ranks from it, so
## host and guest disagreed about where the model stands. #267 already made this decision for the wire
## (a regiment member's position is not broadcast — the block is re-ranked instead); this suite pins
## the local half of the same decision.
##
## The suite drives the REAL main.tscn resolver (_solo_resolve_reanimation) over a REAL RegimentTray.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	# Batch mode: no physics dice tray, no floating text — headless would never settle either.
	_main._solo_batch = true


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## A reanimating unit of `count` models on a 1" line, registered with the army manager.
func _bots(unit_name: String, count: int, at: Vector3 = Vector3.ZERO) -> GameUnit:
	var spots: Array = []
	for i in count:
		spots.append(at + Vector3(float(i) * INCH, 0, 0))
	var u := E2EBoot.make_unit(_main, 2, unit_name, spots)
	_main.opr_army_manager.game_units[u.unit_id] = u
	u.unit_properties["special_rules"] = ["Reanimation"]
	u.unit_properties["faction_folder"] = "robot_legions"
	for i in count:
		var m := u.models[i] as ModelInstance
		m.model_index = i
		m.wounds_max = 1
		m.wounds_current = 1
	return u


## Rank the unit's models into a REAL movement tray (AoF:R block) and hand the tray back.
func _form_block(u: GameUnit, frontage: int) -> RegimentTray:
	var tray := RegimentTray.new()
	_main.add_child(tray)
	var members: Dictionary = RegimentTray.collect_members(u)
	tray.form(members["nodes"], members["footprints"], frontage)
	return tray


## Take model `idx` down the REGIMENT way (rank removal: hidden in place, block closes ranks), then
## drop its hidden node onto a surviving comrade — a fall point the loose placer must refuse, so the
## old code was forced onto a ring spot and the teleport is deterministic rather than lucky.
func _drop_rank_model(u: GameUnit, tray: RegimentTray, idx: int, onto: int) -> ModelInstance:
	var dead := u.models[idx] as ModelInstance
	dead.wounds_current = 0
	dead.is_alive = false
	OPRArmyManager.set_model_alive_state(dead.node, false)
	tray.reform_from_unit(u)
	dead.node.global_position = (u.models[onto] as ModelInstance).node.global_position
	return dead


## Where the BLOCK itself would stand this model: re-ranking is idempotent, so a model that already
## sits in its rank does not move — and one that was teleported away snaps back.
func _rank_position_of(u: GameUnit, tray: RegimentTray, m: ModelInstance) -> Vector3:
	tray.reform_from_unit(u)
	return m.node.global_position


# ===== (1) the ROT case: the rank model must not be teleported out of its block =====

func test_a_regiment_returner_stands_in_its_block_rank(timeout := 120000) -> void:
	var u := _bots("Legion", 6)
	var tray := _form_block(u, 3)
	var back := _drop_rank_model(u, tray, 5, 0)
	_main._solo_resolve_reanimation(u, 1, 5, 1)
	assert_bool(back.is_alive) \
		.override_failure_message("fixture check: the success must actually restore the model") \
		.is_true()
	assert_object(back.node.get_parent()) \
		.override_failure_message("a returning rank model must stay parented to its movement tray") \
		.is_equal(tray)
	var stood: Vector3 = back.node.global_position
	var rank: Vector3 = _rank_position_of(u, tray, back)
	assert_float(stood.distance_to(rank)) \
		.override_failure_message("the model was placed on a coherency spot instead of its rank — it stands %.3f m away from where the block puts it" % stood.distance_to(rank)) \
		.is_less(0.001)


# ===== (2) a block always has a rank — the coherency gate is a LOOSE-model gate =====

func test_a_boxed_in_block_still_returns_its_model(timeout := 120000) -> void:
	# Every ring spot around the block is occupied by other bases, so the loose placer would find
	# nowhere legal and let the success expire. A block does not need a spot: it re-ranks.
	var u := _bots("Boxed", 4)
	var tray := _form_block(u, 2)
	var back := _drop_rank_model(u, tray, 3, 0)
	var anchor: Vector3 = (u.models[0] as ModelInstance).node.global_position
	var wall: Array = []
	for ring in 3:
		var dist: float = 0.034 + float(ring) * (INCH * 0.5)
		for k in 24:
			var ang: float = TAU * float(k) / 24.0
			wall.append(Vector3(anchor.x + cos(ang) * dist, anchor.y, anchor.z + sin(ang) * dist))
	var blockers := E2EBoot.make_unit(_main, 1, "Wall", wall)
	_main.opr_army_manager.game_units[blockers.unit_id] = blockers
	var result: Dictionary = _main._solo_apply_reanimation(u, 1)
	assert_bool(back.is_alive) \
		.override_failure_message("a rank in the block is always available — the success must not expire") \
		.is_true()
	assert_int(int(result.get("unplaceable", -1))) \
		.override_failure_message("the coherency gate belongs to loose models; a block member can never be unplaceable") \
		.is_equal(0)
	assert_int(int(result.get("models", 0))).is_equal(1)


# ===== (3) counter-proof: loose models keep the coherency placement they always had =====

func test_a_loose_returner_still_takes_its_coherency_spot(timeout := 120000) -> void:
	# No tray anywhere: the casualty fell on top of its comrade, so the fall point is refused and
	# the placer must stand it on a free ring spot beside a survivor — unchanged by NML-933.
	var u := _bots("Loose", 2)
	var back := u.models[1] as ModelInstance
	back.wounds_current = 0
	back.is_alive = false
	back.node.global_position = (u.models[0] as ModelInstance).node.global_position
	_main.opr_army_manager.set_loose_model_dead(back.node, 2, true, u.unit_id)
	var fell: Vector3 = (back.node.get_meta("revive_transform") as Transform3D).origin
	_main._solo_resolve_reanimation(u, 1, 5, 1)
	assert_bool(back.is_alive).is_true()
	assert_float(back.node.global_position.distance_to(fell)) \
		.override_failure_message("a loose model whose fall point is blocked must still be moved to a ring spot") \
		.is_greater(0.01)
	var result := CoherencyChecker.check_unit_coherency(u)
	assert_bool(result.valid) \
		.override_failure_message("the loose ring spot must still land the model in coherency") \
		.is_true()
