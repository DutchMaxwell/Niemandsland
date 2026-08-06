extends GdUnitTestSuite
## #319 — movement-commitment hysteresis: a non-driven unit keeps its committed movement target
## across activations unless the fresh nearest is MEANINGFULLY closer (under STICKY_SWITCH_FACTOR
## of the committed distance), the commitment died, or it left the table. Community evidence
## (playtest log 2026-08-05): Iron Veterans rushed a different target five activations straight —
## per-activation "nearest enemy" re-picks flip on small position changes.
##
## The filter is pinned DIRECTLY (an _act round-trip executes the move, which legitimately
## reshuffles every distance — the first version of this suite learned that the hard way).

const IN2M := 0.0254


func _unit(pid: int, positions: Array, rules: Array = [], uid: String = "") -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid if uid != "" else "p%d_%d" % [pid, positions.size()]
	u.unit_properties = {"player_id": pid, "name": (uid if uid != "" else "U%d" % pid),
		"quality": 4, "defense": 4, "special_rules": rules}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		m.unit = u
		var n := Node3D.new()
		add_child(n)
		n.global_position = p
		m.node = n
		u.models.append(m)
	return u


func _army(units: Array) -> OPRArmyManager:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	var gu := {}
	for u in units:
		gu[(u as GameUnit).unit_id] = u
	army.game_units = gu
	army.current_round = 1
	return army


func _controller(units: Array) -> SoloController:
	var sc: SoloController = auto_free(SoloController.new())
	add_child(sc)
	sc.setup(_army(units), null, null, 1, 2)
	return sc


func test_committed_target_survives_a_marginally_closer_rival() -> void:
	var mover := _unit(2, [Vector3.ZERO], [], "Mover")
	var a := _unit(1, [Vector3(12.0 * IN2M, 0, 0)], [], "A")
	var b := _unit(1, [Vector3(0, 0, 11.0 * IN2M)], [], "B")
	var sc := _controller([mover, a, b])
	sc._move_commitments["Mover"] = "A"
	# B at 11" is nearer than A's 12", but not under 80% of it (9.6") — the commitment holds.
	var report := {"rule_notes": []}
	assert_object(sc._sticky_move_target(mover, b, report)).is_same(a)
	var texts := PackedStringArray()
	for n in report.get("rule_notes", []):
		texts.append(str((n as Dictionary).get("text", "")))
	assert_str("\n".join(texts)).contains("stays on A")


func test_meaningfully_closer_rival_breaks_the_commitment() -> void:
	var mover := _unit(2, [Vector3.ZERO], [], "Mover")
	var a := _unit(1, [Vector3(12.0 * IN2M, 0, 0)], [], "A")
	var b := _unit(1, [Vector3(0, 0, 8.0 * IN2M)], [], "B")
	var sc := _controller([mover, a, b])
	sc._move_commitments["Mover"] = "A"
	# B at 8" is under 80% of A's 12" — a real reason to switch, no note owed.
	var report := {"rule_notes": []}
	assert_object(sc._sticky_move_target(mover, b, report)).is_same(b)
	assert_array(report["rule_notes"]).is_empty()


func test_dead_commitment_releases() -> void:
	var mover := _unit(2, [Vector3.ZERO], [], "Mover")
	var a := _unit(1, [Vector3(12.0 * IN2M, 0, 0)], [], "A")
	var b := _unit(1, [Vector3(0, 0, 11.0 * IN2M)], [], "B")
	var sc := _controller([mover, a, b])
	sc._move_commitments["Mover"] = "A"
	(a.models[0] as ModelInstance).is_alive = false
	var report := {"rule_notes": []}
	assert_object(sc._sticky_move_target(mover, b, report)).is_same(b)


func test_act_stores_the_final_pick_as_commitment() -> void:
	# The _act round trip: whatever the tree finally targets lands in the commitment map, so the
	# NEXT activation's hysteresis has something to hold on to.
	var mover := _unit(2, [Vector3.ZERO], [], "Mover")
	var a := _unit(1, [Vector3(12.0 * IN2M, 0, 0)], [], "A")
	var sc := _controller([mover, a])
	sc._act(mover)
	assert_str(str(sc._move_commitments.get("Mover", ""))).is_equal("A")
