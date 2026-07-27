extends GdUnitTestSuite
## TEMP diagnostic — measure the charge-reach gap for small vs large target bases.

const M := 0.0254

var _uid := 0
func _unit(pid: int, positions: Array, base_mm: int = 32) -> GameUnit:
	var u := GameUnit.new()
	_uid += 1
	u.unit_id = "p%d_%d_%d_%d" % [pid, positions.size(), base_mm, _uid]
	u.unit_properties = {"player_id": pid, "name": "U%d" % pid, "quality": 4, "defense": 4,
		"base_size_round": base_mm}
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


func _run(base_mm: int, sep_in: float, extra_enemy: bool) -> void:
	var att := _unit(2, [Vector3(0, 0, 0), Vector3(-0.03, 0, 0)], 32)
	# target sep_in inches to the +x, given radii
	var att_r_in := 16.0 / 25.4
	var tgt_r_in := (base_mm / 2.0) / 25.4
	var cx := (sep_in + att_r_in + tgt_r_in) * M
	var foe := _unit(1, [Vector3(cx, 0, 0)], base_mm)
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {att.unit_id: att, foe.unit_id: foe}
	if extra_enemy:
		# a BLOCKER enemy unit straddling the straight charge line (forces a detour around its 1" zone)
		var foe2 := _unit(1, [Vector3(cx * 0.5, 0.0, 0.02)], 60)
		army.game_units[foe2.unit_id] = foe2
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	var gap_before := solo.nearest_melee_gap_in(att, foe)
	var dang := solo._charge_move(att, foe, 12.0)
	var gap_after := solo.nearest_melee_gap_in(att, foe)
	var pos_str := ""
	for m in att.models:
		var p: Vector3 = (m.node as Node3D).global_position
		pos_str += "(%.3f,%.3f) " % [p.x / M, p.z / M]
	prints("DIAG base_mm=%d sep_in=%.2f extra=%s | before=%.3f after=%.3f dang=%d tgt=(%.3f,%.3f) att=%s" % [
		base_mm, sep_in, str(extra_enemy), gap_before, gap_after, dang, cx / M, 0.0, pos_str])


func test_charge_diag() -> void:
	_run(32, 5.0, false)
	_run(60, 5.0, false)
	_run(90, 5.0, false)
	_run(120, 5.0, false)
	_run(90, 9.0, false)
	_run(90, 2.0, false)
	_run(90, 5.0, true)
	_run(32, 5.0, true)
	_run(60, 8.0, true)
	assert_bool(true).is_true()
