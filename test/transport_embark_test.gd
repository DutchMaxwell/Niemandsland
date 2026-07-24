extends GdUnitTestSuite
## Transport(X) embark STATE layer (NML-105 S1): capacity gate, save-stable id state, model
## parking metas and the choke-point signal — without trays (the slot allocator has its own
## suite; with no tray registered the models keep their spot, which is exactly the warn path).


var _mgr: OPRArmyManager
var _signals: Array = []


func before_test() -> void:
	_mgr = auto_free(OPRArmyManager.new())
	_signals = []
	_mgr.unit_embark_changed.connect(func(u, t, e): _signals.append([u, t, e]))


func _unit(id: String, n: int, rules: Array, pid: int = 1) -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = id
	u.unit_properties = {"player_id": pid, "special_rules": rules, "name": id}
	for i in range(n):
		var m: ModelInstance = ModelInstance.new()
		m.unit = u
		m.node = auto_free(Node3D.new())
		add_child(m.node)   # global_transform needs the tree (stash/restore path)
		u.models.append(m)
	_mgr.game_units[id] = u
	return u


func test_book_squad_fills_the_apc_exactly() -> void:
	var apc := _unit("apc", 1, ["Transport(11)", "Tough(6)"])
	var squad := _unit("squad", 10, [])
	var hero := _unit("hero", 1, ["Hero", "Tough(3)"])
	squad.unit_properties["attached_heroes"] = [hero]
	assert_int(_mgr.unit_embark_spaces(squad)).is_equal(11)   # book example: 10 + Tough(3) hero
	assert_bool(bool(_mgr.can_embark(squad, apc).get("ok"))).is_true()
	assert_bool(_mgr.set_unit_embarked(squad, apc, true)).is_true()
	assert_int(_mgr.transport_used_spaces(apc)).is_equal(11)
	# Full: not even a single extra model fits.
	var one := _unit("one", 1, [])
	var gate: Dictionary = _mgr.can_embark(one, apc)
	assert_bool(bool(gate.get("ok"))).is_false()
	assert_str(str(gate.get("reason"))).contains("not enough space")


func test_state_roundtrip_sets_and_clears_everything() -> void:
	var apc := _unit("apc", 1, ["Transport(6)"])
	var squad := _unit("squad", 3, [])
	var spot: Vector3 = Vector3(1.0, 0.0, 2.0)
	(squad.models[0] as ModelInstance).node.global_position = spot
	assert_bool(_mgr.set_unit_embarked(squad, apc, true)).is_true()
	assert_object(_mgr.transport_of(squad)).is_same(apc)
	assert_bool(_mgr.cargo_units(apc).has(squad)).is_true()
	assert_bool(bool((squad.models[0] as ModelInstance).node.get_meta("embarked", false))).is_true()
	# Double-embark blocked; embark into a second transport blocked.
	assert_bool(_mgr.set_unit_embarked(squad, apc, true)).is_false()
	var apc2 := _unit("apc2", 1, ["Transport(6)"])
	assert_str(str(_mgr.can_embark(squad, apc2).get("reason"))).contains("already embarked")
	# Disembark clears state + metas; the 6" placer owns the exit position (near the APC's
	# node at the origin — NOT the old table spot).
	assert_bool(_mgr.set_unit_embarked(squad, null, false)).is_true()
	assert_object(_mgr.transport_of(squad)).is_null()
	assert_int(_mgr.transport_used_spaces(apc)).is_equal(0)
	assert_bool((squad.models[0] as ModelInstance).node.has_meta("embarked")).is_false()
	assert_bool((squad.models[0] as ModelInstance).node.has_meta("embark_return_transform")).is_false()
	var exit_p: Vector3 = (squad.models[0] as ModelInstance).node.global_position
	assert_float(exit_p.distance_to((apc.models[0] as ModelInstance).node.global_position)).is_less(
		6.0 * 0.0254 + 0.08)
	# Signal fired once per flip, with the right direction.
	assert_int(_signals.size()).is_equal(2)
	assert_bool(bool(_signals[0][2])).is_true()
	assert_bool(bool(_signals[1][2])).is_false()


func test_untransportable_and_non_transport_gates() -> void:
	var apc := _unit("apc", 1, ["Transport(11)"])
	var walker := _unit("walker", 1, ["Tough(12)"])
	var gate: Dictionary = _mgr.can_embark(walker, apc)
	assert_bool(bool(gate.get("ok"))).is_false()
	assert_str(str(gate.get("reason"))).contains("cannot be transported")
	var grunt := _unit("grunt", 1, [])
	var not_a_bus := _unit("tank", 1, ["Tough(6)"])
	assert_str(str(_mgr.can_embark(grunt, not_a_bus).get("reason"))).contains("not a transport")
	# A transport that is itself embarked may not receive cargo.
	var big := _unit("big", 1, ["Transport(20)"])
	var small_bus := _unit("bus", 1, ["Transport(6)", "Tough(3)", "Hero"])
	assert_bool(_mgr.set_unit_embarked(small_bus, big, true)).is_true()
	assert_str(str(_mgr.can_embark(grunt, small_bus).get("reason"))).contains("itself embarked")


func test_disembark_placer_forms_legally_within_six_inches() -> void:
	var apc := _unit("apc", 1, ["Transport(11)"])
	(apc.models[0] as ModelInstance).node.global_position = Vector3(2.0, 0.0, 2.0)
	var squad := _unit("squad", 6, [])
	for i in range(6):
		(squad.models[i] as ModelInstance).node.global_position = Vector3(0.1 * i, 0.0, 0.0)
	assert_bool(_mgr.set_unit_embarked(squad, apc, true)).is_true()
	assert_bool(_mgr.set_unit_embarked(squad, null, false)).is_true()
	var zone: float = 6.0 * 0.0254
	var t_pos: Vector3 = (apc.models[0] as ModelInstance).node.global_position
	var pts: Array = []
	for m in squad.models:
		var p: Vector3 = (m as ModelInstance).node.global_position
		pts.append(p)
		# Fully within 6" of the transport (bounding-circle contract; radii add slack, so gate
		# on centre distance <= zone + a generous transport-base allowance).
		assert_float(p.distance_to(t_pos)).is_less(zone + 0.08)
	# No two placed bases overlap (default base radius pair distance).
	for i in range(pts.size()):
		for j in range(i + 1, pts.size()):
			assert_float((pts[i] as Vector3).distance_to(pts[j] as Vector3)).is_greater(
				2.0 * SeparationChecker.DEFAULT_BASE_RADIUS_M - 0.002)


func test_disembark_placer_avoids_a_blocking_base() -> void:
	var apc := _unit("apc", 1, ["Transport(6)"])
	(apc.models[0] as ModelInstance).node.global_position = Vector3.ZERO
	var enemy := _unit("enemy", 1, [], 2)
	# The enemy stands exactly on the default exit bearing (transport facing -Z).
	(enemy.models[0] as ModelInstance).node.global_position = Vector3(0.0, 0.0, -0.06)
	var grunt := _unit("grunt", 1, [])
	assert_bool(_mgr.set_unit_embarked(grunt, apc, true)).is_true()
	assert_bool(_mgr.set_unit_embarked(grunt, null, false)).is_true()
	var p: Vector3 = (grunt.models[0] as ModelInstance).node.global_position
	assert_float(p.distance_to((enemy.models[0] as ModelInstance).node.global_position)).is_greater(
		2.0 * SeparationChecker.DEFAULT_BASE_RADIUS_M - 0.002)


func test_destroyed_transport_spills_cargo_shaken_at_its_last_table_spot() -> void:
	var spills: Array = []
	_mgr.transport_cargo_spilled.connect(func(t, s): spills.append([t, s]))
	var apc := _unit("apc", 1, ["Transport(11)", "Tough(6)"])
	var apc_model := apc.models[0] as ModelInstance
	var wreck_spot := Vector3(3.0, 0.0, -1.0)
	apc_model.node.global_position = wreck_spot
	apc_model.node.set_meta("model_instance", apc_model)
	var squad := _unit("squad", 4, [])
	assert_bool(_mgr.set_unit_embarked(squad, apc, true)).is_true()
	# The killing blow: the model dies and runs through the dead-parking choke point.
	apc_model.is_alive = false
	_mgr.set_loose_model_dead(apc_model.node, 1, true, "apc")
	# Cargo spilled: disembarked, Shaken, placed near the WRECK spot (not the tray), signal fired.
	assert_object(_mgr.transport_of(squad)).is_null()
	assert_bool(squad.is_shaken).is_true()
	assert_int(spills.size()).is_equal(1)
	for m in squad.models:
		var p: Vector3 = (m as ModelInstance).node.global_position
		assert_float(p.distance_to(wreck_spot)).is_less(6.0 * 0.0254 + 0.08)
		assert_bool((m as ModelInstance).node.has_meta("embarked")).is_false()


func test_restore_after_load_reparks_and_spots_survive_the_save() -> void:
	var apc := _unit("apc", 1, ["Transport(6)"])
	var squad := _unit("squad", 2, [])
	var spot := Vector3(1.5, 0.0, 0.5)
	(squad.models[0] as ModelInstance).node.global_position = spot
	assert_bool(_mgr.set_unit_embarked(squad, apc, true)).is_true()
	# The pre-embark spots ride unit_properties — exactly what a save serializes.
	var spots: Array = squad.unit_properties.get("embark_return_spots", [])
	assert_int(spots.size()).is_equal(2)
	assert_float(float((spots[0] as Array)[0])).is_equal_approx(spot.x, 0.001)
	# Simulate the load: runtime metas are gone, props survived.
	for m in squad.models:
		(m as ModelInstance).node.remove_meta("embarked")
	_mgr.restore_embarked_after_load()
	for m in squad.models:
		assert_bool(bool((m as ModelInstance).node.get_meta("embarked", false))).is_true()
	assert_object(_mgr.transport_of(squad)).is_same(apc)
	# And the state still unwinds cleanly after the restore.
	assert_bool(_mgr.set_unit_embarked(squad, null, false)).is_true()
	assert_bool(squad.unit_properties.has("embark_return_spots")).is_false()
