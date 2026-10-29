extends GdUnitTestSuite
## Automodus decision 14 (maintainer play test 29.10.2026, "sieht doof aus"): NACHTMAHR's miniatures face
## the enemy after they are deployed and after every move. Each model's yaw (rotation.y, local +Z forward —
## the convention of the player's own drag auto-face) aims at the nearest enemy model on the table plane;
## in a melee after a charge at the engaged unit. The player's models are never turned.
## Facing is presentation only (OPR has no facing rules): the last case runs one seeded deployment + AI
## turn with the facing off and on and requires the identical rule outcome.

const TOL_DEG := 5.0


## NML-902: MovementPlanner.fast_planner is a process-wide static an e2e suite may leave on — pin it.
func before_test() -> void:
	MovementPlanner.fast_planner = false
	MovementPlanner.fast_planner_guard = MovementPlanner.FAST_PLANNER_GUARD


func _unit(pid: int, uname: String, positions: Array, yaw := 0.0) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "face_p%d_%s" % [pid, uname]
	u.unit_properties = {"player_id": pid, "name": uname, "quality": 4, "defense": 4}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		m.unit = u
		var n := Node3D.new()
		add_child(n)
		n.global_position = p
		n.rotation.y = yaw
		m.node = n
		u.models.append(m)
	return u


func _world(units: Array) -> SoloController:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	for u in units:
		army.game_units[(u as GameUnit).unit_id] = u
	army.current_round = 1
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	return solo


## Degrees between a model's facing and the table-plane direction to `at`.
static func _aim_err_deg(node: Node3D, at: Vector3) -> float:
	var want := atan2(at.x - node.global_position.x, at.z - node.global_position.z)
	return absf(rad_to_deg(angle_difference(node.rotation.y, want)))


## The nearest living model of `foes` to `node` (table plane).
static func _nearest_foe(node: Node3D, foes: Array) -> Vector3:
	var pts: Array = []
	for f in foes:
		pts.append_array(SoloController.alive_positions(f as GameUnit))
	return pts[SoloController.nearest_index(node.global_position, pts)]


func _assert_all_face(unit: GameUnit, foes: Array, what: String) -> void:
	for m in unit.models:
		var node := (m as ModelInstance).node
		var err := _aim_err_deg(node, _nearest_foe(node, foes))
		assert_float(err).override_failure_message("%s: the AI model at %s faces %.1f deg off the enemy model it should look at" % [
			what, node.global_position, err]).is_less_equal(TOL_DEG)


func test_ai_models_face_the_nearest_enemy_after_a_move() -> void:
	var human := _unit(1, "Wall", [Vector3(0, 0, 0), Vector3(0, 0, 0.12)])
	var ai := _unit(2, "Raider", [Vector3(0.5, 0, 0), Vector3(0.5, 0, 0.04)])
	var solo := _world([human, ai])
	assert_object(solo.activate_next_ai_unit()).is_equal(ai)
	assert_bool(solo.last_move_paths.is_empty()).override_failure_message("the AI unit must really move").is_false()
	_assert_all_face(ai, [human], "after a move")


func test_ai_models_face_the_nearest_enemy_after_deployment() -> void:
	var human := _unit(1, "Wall", [Vector3(-0.2, 0, -0.4), Vector3(-0.16, 0, -0.4)])
	# Staged on the AI's tray (off the 4x4 ft test table, z > 0.61) like an imported army.
	var ai := _unit(2, "Raider", [Vector3(0.0, 0, 0.9), Vector3(0.04, 0, 0.9), Vector3(0.08, 0, 0.9)])
	var solo := _world([human, ai])
	var zone := Rect2(Vector2(-0.61, 0.3), Vector2(1.22, 0.3))   # the south strip; the human stands north
	var no_block := func(_p: Vector2) -> bool: return false
	var res: Dictionary = solo.deploy_army(zone, [Vector2(0, 0)], no_block, no_block, 7)
	assert_int(int(res["deployed"])).is_equal(1)
	_assert_all_face(ai, [human], "after deployment")


## The rear charger stands nearer a bystander unit than the charged one: in the melee it still faces
## the ENGAGED unit, not the nearest model on the table.
func test_charging_models_face_the_engaged_enemy_not_a_nearer_bystander() -> void:
	var ai := _unit(2, "Raider", [Vector3(0, 0, 0), Vector3(0.04, 0, 0), Vector3(0.08, 0, 0)])
	var target := _unit(1, "Target", [Vector3(-0.05, 0, 0)])        # ~0.7" from the front model
	var bystander := _unit(1, "Bystander", [Vector3(0.075, 0, 0.055)])
	var solo := _world([ai, target, bystander])
	solo.snap_charge(ai, target)   # main's AI charge resolution (main._run_ai_melee)
	assert_float(solo.nearest_melee_gap_in(ai, target)).is_less_equal(SoloController.MELEE_ENGAGE_IN)
	var rear := (ai.models[2] as ModelInstance).node
	assert_bool(_nearest_foe(rear, [target, bystander]) == _nearest_foe(rear, [bystander])) \
		.override_failure_message("premise: the bystander is the rear model's nearest enemy").is_true()
	_assert_all_face(ai, [target], "after the charge")


## A human charge: the AI defenders pile in (main's _run_human_attack) and face the charger — the front
## model that already touches it as well as the rear one that steps around it.
func test_piled_in_defenders_face_the_charger() -> void:
	var ai := _unit(2, "Raider", [Vector3(0, 0, 0), Vector3(0.04, 0, 0)])
	var charger := _unit(1, "Charger", [Vector3(-0.034, 0, 0)])     # in base contact with the front model
	var solo := _world([ai, charger])
	solo.pile_in(ai, charger)
	_assert_all_face(ai, [charger], "after the pile-in")


## The AI deployed a unit before any enemy stood on the table: the battle start turns it to the enemy.
func test_the_ai_army_faces_the_enemy_when_the_battle_begins() -> void:
	var ai := _unit(2, "Raider", [Vector3(0, 0, 0.4), Vector3(0.04, 0, 0.4)])
	var human := _unit(1, "Wall", [Vector3(0.3, 0, -0.4)])
	var solo := _world([ai, human])
	solo.army_manager.start_game()
	_assert_all_face(ai, [human], "at the battle start")


## Control: the player's models keep their yaw through the engine's snap of THEIR charge, the AI's
## pile-in against them, the battle start and the AI's whole activation.
func test_player_models_keep_their_facing() -> void:
	var human := _unit(1, "Wall", [Vector3(0, 0, 0), Vector3(-0.04, 0, 0)], 0.7)
	var ai := _unit(2, "Raider", [Vector3(0.068, 0, 0), Vector3(0.108, 0, 0)])   # ~0.8" from the front model
	var solo := _world([human, ai])
	solo.snap_charge(human, ai)
	solo.pile_in(ai, human)
	solo.army_manager.start_game()
	solo.activate_next_ai_unit()
	for m in human.models:
		assert_float((m as ModelInstance).node.rotation.y).is_equal_approx(0.7, 0.000001)


## One seeded deployment + AI turn (two AI units deploy, then rush/charge) with the facing off and on.
func _scripted_battle(face: bool) -> Dictionary:
	var h1 := _unit(1, "Wall", [Vector3(-0.2, 0, -0.35), Vector3(-0.16, 0, -0.35)], 0.7)
	var h2 := _unit(1, "Tower", [Vector3(0.25, 0, -0.3)], 0.7)
	var a1 := _unit(2, "Raider", [Vector3(0.0, 0, 0.9), Vector3(0.04, 0, 0.9), Vector3(0.08, 0, 0.9)])
	var a2 := _unit(2, "Stalker", [Vector3(0.2, 0, 0.9), Vector3(0.24, 0, 0.9)])
	var solo := _world([h1, h2, a1, a2])
	solo.set("face_enemy", face)   # set(): a no-op on a build without the switch (the RED run on main)
	solo._rng.seed = 4242
	var zone := Rect2(Vector2(-0.61, 0.3), Vector2(1.22, 0.3))
	var no_block := func(_p: Vector2) -> bool: return false
	solo.deploy_army(zone, [Vector2(0, 0)], no_block, no_block, 7)
	solo.army_manager.start_game()
	var moved := solo.run_ai_turn()
	var out := {"moved": moved, "digest": solo.state_digest(), "rng": solo._rng.state,
		"positions": [], "log": [], "ai_yaws": [], "human_yaws": []}
	for u in [h1, h2, a1, a2]:
		for m in (u as GameUnit).models:
			var n := (m as ModelInstance).node
			(out["positions"] as Array).append("%s %.6f %.6f %.6f" % [(u as GameUnit).get_name(),
				n.global_position.x, n.global_position.y, n.global_position.z])
			(out["ai_yaws" if u == a1 or u == a2 else "human_yaws"] as Array).append(n.rotation.y)
	for rec in solo.decision_log:
		(out["log"] as Array).append(SoloController.render_decision(rec as Dictionary))
	return out


func test_facing_changes_no_rule_outcome() -> void:
	var off := _scripted_battle(false)
	var on := _scripted_battle(true)
	assert_int(int(off["moved"])).is_equal(2)
	assert_str(str(on["digest"])).is_equal(str(off["digest"]))
	assert_array(on["positions"] as Array).is_equal(off["positions"] as Array)
	assert_array(on["log"] as Array).is_equal(off["log"] as Array)
	assert_bool((on["log"] as Array).size() > 0).is_true()
	assert_int(int(on["rng"])).is_equal(int(off["rng"]))
	assert_array(on["human_yaws"] as Array).is_equal(off["human_yaws"] as Array)
	# Both legs really differ where they should: off = the old path (no AI model turned), on = turned.
	assert_bool((off["ai_yaws"] as Array).all(func(y: float) -> bool: return is_zero_approx(y))) \
		.override_failure_message("facing off must leave every AI yaw at 0: %s" % [off["ai_yaws"]]).is_true()
	assert_bool((on["ai_yaws"] as Array).any(func(y: float) -> bool: return not is_zero_approx(y))) \
		.override_failure_message("facing on must turn the AI models: %s" % [on["ai_yaws"]]).is_true()
