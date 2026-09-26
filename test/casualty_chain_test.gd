extends GdUnitTestSuite
## Casualty removal keeps the survivors' chain (GF/AoF Advanced Rules v3.5.1 p.8: the defender removes models "in any
## order, keeping unit coherency in mind"; p.7: every model within 1" of another, one chain, within 9" of all).
## measured 26.09.: 5 of 8 coherency violations after an AI move were casualty removal tearing the chain
## (`casualty_order` picked by loadout, then outermost-first, and never asked whether the model was a bridge).
## Rules: a wounded Tough body is still finished first (p.14, no choice); otherwise the first model in the value order
## whose removal keeps the survivors coherent goes; when NO removal can (unit already torn) the order is unchanged.
## Bases are 0 mm so edge-to-edge equals centre-to-centre. Controls are declared first: gdUnit drops tests declared
## after a failing one.

const INCH := 0.0254  # metres per inch


func _row(xs_in: Array, pid: int = 1) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "cc_%d_%d" % [xs_in.size(), randi()]
	u.unit_properties = {"player_id": pid, "name": "Squad", "base_size_round": 0, "base_is_oval": false}
	for i in range(xs_in.size()):
		u.models.append(_model(u, i, Vector3(float(xs_in[i]) * INCH, 0.0, 0.0)))
	return u


func _model(u: GameUnit, i: int, pos: Vector3) -> ModelInstance:
	var m := ModelInstance.new()
	m.is_alive = true
	m.unit = u
	m.model_index = i
	var n: Node3D = auto_free(Node3D.new())
	add_child(n)
	n.global_position = pos
	m.node = n
	return m


## Five in a row, 0.9" apart (D nudged so no two distances tie); the two END models carry the rare Flamer, so the
## value order kills the plain middle bodies first — every one of which is a bridge. Value order: D, B, C, E, A.
func _bridge_row() -> GameUnit:
	var u := _row([0.0, 0.9, 1.8, 2.75, 3.65])
	u.models[0].properties["weapons"] = [{"name": "Flamer"}]
	u.models[4].properties["weapons"] = [{"name": "Flamer"}]
	return u


func _coherent(u: GameUnit) -> bool:
	return CoherencyChecker.check_unit_coherency(u).valid


func _kill(u: GameUnit, wounds: int) -> void:
	assert_int(SoloController.apply_wounds_to_models(u, wounds, Callable(), Callable())).is_equal(0)


# --- controls (must hold before and after the fix) ---

func test_control_the_value_order_is_the_old_one_the_bridge_row_stays_a_bridge_row() -> void:
	var u := _bridge_row()
	assert_bool(_coherent(u)).is_true()
	assert_array(SoloController.casualty_order(u)).is_equal([3, 1, 2, 4, 0])


func test_control_an_already_torn_unit_keeps_the_old_order() -> void:
	# Two pairs 5" apart: NO removal can make the survivors coherent, so nothing is reordered ("otherwise as before").
	var u := _row([0.0, 0.5, 5.5, 6.0])
	u.models[0].properties["weapons"] = [{"name": "Flamer"}]
	var base := SoloController.casualty_order(u)
	_kill(u, 1)
	assert_bool(u.models[int(base[0])].is_alive).is_false()
	var dead := 0
	for m in u.models:
		if not m.is_alive:
			dead += 1
	assert_int(dead).is_equal(1)


func test_control_a_wounded_tough_body_is_finished_first_even_when_it_is_the_bridge() -> void:
	# p.14 Tough: wounds keep landing on the wounded body until it dies — that is a rule, not a preference.
	var u := _row([0.0, 0.9, 1.8])
	for m in u.models:
		m.wounds_max = 3
		m.wounds_current = 3
	u.models[1].wounds_current = 1
	_kill(u, 1)
	assert_bool(u.models[1].is_alive).is_false()   # the middle (bridge) body died: no choice
	assert_bool(u.models[0].is_alive).is_true()
	assert_bool(u.models[2].is_alive).is_true()


# --- RED before the fix / GREEN after ---

func test_one_casualty_never_takes_the_bridge_when_an_end_model_can_go() -> void:
	var u := _bridge_row()
	_kill(u, 1)
	assert_bool(_coherent(u)).is_true()
	assert_bool(u.models[4].is_alive).is_false()   # E: the first value-order body whose removal keeps the chain
	assert_bool(u.models[3].is_alive).is_true()    # D (plain, first in the value order) is a bridge to E — spared


func test_two_casualties_keep_the_chain_too_the_greedy_step_uses_the_survivors() -> void:
	var u := _bridge_row()
	_kill(u, 2)
	assert_bool(_coherent(u)).is_true()
	assert_bool(u.models[4].is_alive).is_false()   # E first (no plain body can go without a tear)
	assert_bool(u.models[3].is_alive).is_false()   # then D — an end of the shortened row, plain, first in value order
	assert_bool(u.models[0].is_alive and u.models[1].is_alive and u.models[2].is_alive).is_true()


func test_the_deadly_pick_follows_the_same_chain_rule() -> void:
	var pick := SoloController.deadly_pick(_bridge_row())
	assert_int(int(pick["index"])).is_equal(4)
	assert_bool(bool(pick["forced"])).is_false()


func test_a_joined_hero_counts_as_a_link_of_the_chain() -> void:
	# X --0.9-- H(hero) --0.9-- Y --0.9-- Z. Y (plain) is first in the value order but bridges H to Z.
	var host := _row([0.0, 1.8, 2.7])
	host.models[0].properties["weapons"] = [{"name": "Flamer"}]
	host.models[2].properties["weapons"] = [{"name": "Flamer"}]
	var hero := GameUnit.new()
	hero.unit_id = "cc_hero_%d" % randi()
	hero.unit_properties = {"player_id": 1, "name": "Hero", "base_size_round": 0, "base_is_oval": false, "attached_to": host}
	hero.models.append(_model(hero, 0, Vector3(0.9 * INCH, 0.0, 0.0)))
	host.unit_properties["attached_heroes"] = [hero]
	assert_bool(_coherent(host)).is_true()
	_kill(host, 1)
	assert_bool(host.models[1].is_alive).is_true()   # the bridge Y stays
	assert_bool(_coherent(host)).is_true()


func test_a_coherent_unit_stays_coherent_for_every_casualty_count() -> void:
	# 150 random coherent squads (2-12 bodies, random loadouts): removing 1..N-2 bodies never tears the survivors.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260926
	var checked := 0
	for _case in range(150):
		var n: int = rng.randi_range(3, 12)
		var pts: Array = [Vector2.ZERO]
		var guard := 0
		while pts.size() < n and guard < 400:
			guard += 1
			var base: Vector2 = pts[rng.randi_range(0, pts.size() - 1)]
			var p: Vector2 = base + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.3, 0.95)
			var spread_ok := true
			for q in pts:
				if (p - q).length() > 8.5:
					spread_ok = false
			if spread_ok:
				pts.append(p)
		if pts.size() < n:
			continue
		for wounds in range(1, n - 1):
			var u := GameUnit.new()
			u.unit_id = "cc_prop_%d" % randi()
			u.unit_properties = {"player_id": 1, "name": "Squad", "base_size_round": 0, "base_is_oval": false}
			for i in range(n):
				var m := _model(u, i, Vector3(pts[i].x * INCH, 0.0, pts[i].y * INCH))
				var roll := rng.randi_range(0, 2)
				if roll == 1:
					m.properties["weapons"] = [{"name": "Rifle"}]
				elif roll == 2:
					m.properties["weapons"] = [{"name": "Flamer"}, {"name": "CCW"}]
				u.models.append(m)
			assert_bool(_coherent(u)).is_true()
			SoloController.apply_wounds_to_models(u, wounds, Callable(), Callable())
			var still := _coherent(u)
			assert_bool(still).override_failure_message("case %d: %d bodies, %d casualties tore the chain" % [_case, n, wounds]).is_true()
			if not still:
				return
			checked += 1
	assert_int(checked).is_greater(300)


func test_a_hair_over_one_inch_link_does_not_switch_the_chain_rule_off() -> void:
	# The AI places bodies exactly on 1.000", so a link of 1.003" is common: invisible to a tape, strictly torn for
	# check_unit_coherency. Replay of arena seed 2 (26.09.): one such hair in the MIDDLE of the chain made every
	# removal look tearing (no single removal can heal it), the picker fell back to the value order and four
	# casualties stranded the survivors 5.3" apart. Value order here: D, B, C, E, A (E and A carry the Flamer).
	var u := _row([0.0, 0.9, 1.8, 2.803, 3.703])
	u.models[0].properties["weapons"] = [{"name": "Flamer"}]
	u.models[4].properties["weapons"] = [{"name": "Flamer"}]
	assert_bool(_coherent(u)).is_false()   # strictly torn by 0.003" at the C-D link — the hair
	_kill(u, 1)
	assert_bool(u.models[4].is_alive).is_false()   # E: the end whose removal leaves A-B-C-D as one chain
	assert_bool(u.models[3].is_alive).is_true()    # D (plain, first in the value order) bridges to E — spared
	for i in [0, 1, 2]:
		assert_bool(u.models[i].is_alive).is_true()


func test_hairs_over_one_inch_do_not_break_the_property_either() -> void:
	# Same property as above on squads whose links run up to 1.006" (the AI places on exactly 1.000", float noise and
	# gate rounding leave hairs): judged with the picker's own tape slack, no casualty count tears the survivors.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260927
	var checked := 0
	for _case in range(150):
		var n: int = rng.randi_range(4, 12)
		var pts: Array = [Vector2.ZERO]
		var guard := 0
		while pts.size() < n and guard < 400:
			guard += 1
			var base: Vector2 = pts[rng.randi_range(0, pts.size() - 1)]
			var p: Vector2 = base + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.7, 1.006)
			var spread_ok := true
			for q in pts:
				if (p - q).length() > 8.5:
					spread_ok = false
			if spread_ok:
				pts.append(p)
		if pts.size() < n:
			continue
		for wounds in range(1, n - 1):
			var u := GameUnit.new()
			u.unit_id = "cc_hair_%d" % randi()
			u.unit_properties = {"player_id": 1, "name": "Squad", "base_size_round": 0, "base_is_oval": false}
			for i in range(n):
				var m := _model(u, i, Vector3(pts[i].x * INCH, 0.0, pts[i].y * INCH))
				m.properties["weapons"] = [{"name": "Rifle"}] if rng.randi_range(0, 1) == 1 else []
				u.models.append(m)
			var slack := CoherencyChecker.MEASURING_SLACK_INCHES
			assert_bool(CoherencyChecker.LinkTable.new(u.get_alive_models_with_attached(), slack).coherent_without({}, 9.0)).is_true()
			SoloController.apply_wounds_to_models(u, wounds, Callable(), Callable())
			var still := CoherencyChecker.LinkTable.new(u.get_alive_models_with_attached(), slack).coherent_without({}, 9.0)
			assert_bool(still).override_failure_message("case %d: %d bodies, %d casualties tore the chain (within slack)" % [_case, n, wounds]).is_true()
			if not still:
				return
			checked += 1
	assert_int(checked).is_greater(300)
