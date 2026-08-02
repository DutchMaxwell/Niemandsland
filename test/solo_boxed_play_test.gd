extends GdUnitTestSuite
## BOXED PLAY (NML-935) — a unit whose straight lane is jammed must still spend its turn.
##
## THE FORENSICS BEHIND THIS SUITE. Since the movement planner learned the table edge (#215/#259) the
## AI can no longer flee across it, and the self-play captures show what it does instead: it stands
## still. The signature in the decision log is a move record with a FULL band and `achieved_in` 0.00 —
## e.g. t61002 Stalkers R2+R3 (band 14", achieved 0.0) and t61005 Possessed Henchmen R3+R4 (band 12",
## achieved 0.0). Those units burn a whole activation and move nothing, round after round.
##
## THE SEAM UNDER TEST. SoloController has a lateral escape for exactly this ("boxed reposition"): when
## the straight advance collapses, the unit re-aims the same band sideways. But it ran AFTER the
## gate-collapse ladder and inherited that ladder's shortened `reach` — so a unit whose 14" advance had
## collapsed to 3.5" probed for lateral room at 1.75" (inside its own friendly wall by construction),
## found none, and stubbed. The ladder shortened because the STRAIGHT lane had no legal end state; that
## says nothing about how far the unit may legally walk SIDEWAYS.
##
## WHAT IS REAL vs CONSTRUCTED. Real: the whole SoloController activation path — the official decision
## tree, the move planner, the placement gate, the collapse ladder and the lateral escape, plus the
## decision records they write. Constructed: the GameUnits and their model nodes, at genuine table
## coordinates in inches.

const IN2M := 0.0254


func _unit(pid: int, positions: Array, uid: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4, "special_rules": []}
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


func _arm_melee(u: GameUnit) -> void:
	var opr := OPRApiClient.OPRUnit.new()
	var ow := OPRApiClient.OPRWeapon.new()
	ow.name = "Claws"
	ow.range_value = 0
	ow.attacks = 2
	ow.count = 1
	opr.weapons.append(ow)
	u.source_type = "opr"
	u.source_data = opr


## The jam: a two-model AI melee unit at the origin, a THREE-DEEP wall of already-activated friends
## straight ahead of it (+x, the only way to the enemy), and the enemy 30" away on that same axis. The
## straight lane is physically closed by friendly bases; open ground remains to either side.
func _boxed_board() -> Array:
	var mover := _unit(2, [Vector3.ZERO, Vector3(0, 0, 1.2 * IN2M)], "Boxed")
	_arm_melee(mover)
	var units: Array = [mover]
	var w := 0
	for dx in [2.4, 4.8, 7.2]:
		for dz in [-3.6, -1.2, 1.2, 3.6]:
			w += 1
			units.append(_unit(2, [Vector3(dx * IN2M, 0, dz * IN2M)], "Wall%d" % w))
	units.append(_unit(1, [Vector3(30.0 * IN2M, 0, 0)], "FarFoe"))
	var sc := _controller(units)
	for u in units:
		if str((u as GameUnit).unit_id).begins_with("Wall"):
			(u as GameUnit).is_activated = true
	return [sc, mover]


func _move_record(sc: SoloController) -> Dictionary:
	var out := {}
	for rec in sc.drain_decisions():
		var r := rec as Dictionary
		if str(r.get("kind", "")) == "move" and str(r.get("why", "")) != "band clamp":
			out = r
	return out


## THE CLAIM. The jammed unit takes its lateral escape at the band it was actually GRANTED, and really
## clears the jam with it — not at the quarter-band remnant the collapse ladder happened to stop on.
##
## ROT (proven): with the escape reading the ladder's `reach` instead of the granted band, the same
## board produces a `budget_in` well under the 12" band and a correspondingly shorter step.
func test_a_boxed_unit_sidesteps_at_the_band_it_was_granted() -> void:
	var board := _boxed_board()
	var sc: SoloController = board[0]
	sc.activate_next_ai_unit()
	var rec := _move_record(sc)

	assert_bool(rec.is_empty()) \
		.override_failure_message("the boxed unit produced no move record at all").is_false()
	assert_str(str(rec.get("why", ""))) \
		.override_failure_message("the jam was not answered with the lateral escape but with %r" % str(rec.get("why", ""))) \
		.is_equal("boxed reposition")
	var data := rec.get("data", {}) as Dictionary
	var band := float(data.get("band_in", 0.0))
	var budget := float(data.get("budget_in", 0.0))
	var achieved := float(data.get("achieved_in", 0.0))
	assert_float(band).is_greater(6.0)   # fixture guard: this really is a Rush band
	assert_float(budget) \
		.override_failure_message("the escape walked on %.2f\" of a %.2f\" band — it inherited the collapse ladder's remnant" % [budget, band]) \
		.is_equal_approx(band, 0.01)
	assert_float(achieved) \
		.override_failure_message("the unit ended %.2f\" from where it started on a %.2f\" band — the escape did not clear the jam" % [achieved, band]) \
		.is_greater(band * 0.5)


## The same board, read as the pathology the forensics named: a unit with a real band must never end an
## activation on the spot. This is the invariant the self-play detectors measure (`achieved_in` ≈ 0 with
## `band_in` ≥ 6"), pinned here so a future planner change cannot quietly reintroduce it on this board.
func test_a_boxed_unit_never_ends_its_activation_on_the_spot() -> void:
	var board := _boxed_board()
	var sc: SoloController = board[0]
	var mover: GameUnit = board[1]
	var before: Array = []
	for m in mover.get_alive_models():
		before.append((m as ModelInstance).node.global_position)
	sc.activate_next_ai_unit()
	var moved := 0.0
	var i := 0
	for m in mover.get_alive_models():
		moved = maxf(moved, ((m as ModelInstance).node.global_position - (before[i] as Vector3)).length())
		i += 1
	assert_float(moved / IN2M) \
		.override_failure_message("the boxed unit walked %.2f\" — it stood still through its whole activation" % (moved / IN2M)) \
		.is_greater(1.0)
