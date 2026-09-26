extends GdUnitTestSuite
## D17 / Q8 — Deadly(X) casualty pick (GF v3.5.1 p.13 Deadly + p.15 Tough).
## "Assign each wound to one model, and multiply it by X … these wounds don't carry over to other models if the
## original target is killed." Tough(X): "You must continue to put wounds on the tough model with most wounds in the
## unit until it is killed, before starting to put them on the next tough model (heroes must be assigned wounds
## last, even if already wounded)." The engine used to hand every Deadly wound to the FIRST model with the MOST
## remaining wounds: a fresh Tough weapon team was hit before plain bodies and an already-wounded Tough model was
## skipped for a fresh one. Now: the wounded Tough model first (automatic), then the defender-optimal order
## (`casualty_order`), a joined hero last. When a FRESH model is about to be hit the DEFENDER picks — a human
## clicks (see e2e_deadly_defender_pick_test.gd), the automatic path takes casualty_order.
## Controls are declared first: gdUnit drops tests declared after a failing one.


func _unit(pid: int, count: int, tough: Array = []) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "p%d_%d_%d" % [pid, count, randi()]
	u.unit_properties = {"player_id": pid, "name": "U%d" % pid, "quality": 4, "defense": 4}
	for i in range(count):
		var m := ModelInstance.new()
		m.is_alive = true
		m.unit = u
		m.model_index = i
		var n := Node3D.new()
		add_child(n)
		n.global_position = Vector3(0.05 * i, 0, 0)
		m.node = n
		var t: int = int(tough[i]) if i < tough.size() else 1
		m.wounds_max = t
		m.wounds_current = t
		u.models.append(m)
	return u


func _deal(u: GameUnit, unsaved: int, x: int) -> int:
	return SoloController.apply_deadly_wounds(u, unsaved, x, Callable(), Callable())


func test_a_lone_tough_model_takes_the_wound_capped_at_what_it_has() -> void:
	var ogre := _unit(1, 1, [3])
	assert_int(_deal(ogre, 1, 2)).is_equal(2)
	assert_int(ogre.models[0].wounds_current).is_equal(1)
	# Deadly(3) on the 1 wound it has left: 1 dealt, the excess is lost, the model is dead (no carry-over).
	assert_int(_deal(ogre, 1, 3)).is_equal(1)
	assert_bool(ogre.models[0].is_alive).is_false()


func test_excess_deadly_wounds_never_carry_over_to_the_next_model() -> void:
	var squad := _unit(1, 3, [3, 3, 3])
	squad.models[1].wounds_current = 2   # the wounded one is hit first, Deadly(3) is capped at its 2 wounds
	assert_int(_deal(squad, 1, 3)).is_equal(2)
	assert_bool(squad.models[1].is_alive).is_false()
	assert_int(squad.models[0].wounds_current).is_equal(3)
	assert_int(squad.models[2].wounds_current).is_equal(3)


func test_a_wounded_tough_model_takes_the_deadly_wound_before_a_fresh_one() -> void:
	# p.15: "continue to put wounds on the tough model with most wounds … until it is killed". Three Tough(3) bodies,
	# index 1 already down to 1 wound: the old "most remaining wounds" rule skipped it for a fresh body.
	var mortars := _unit(1, 3, [3, 3, 3])
	mortars.models[1].wounds_current = 1
	assert_int(_deal(mortars, 1, 2)).is_equal(1)
	assert_bool(mortars.models[1].is_alive) \
		.override_failure_message("D17 — the already-wounded Tough model was skipped for a fresh one") \
		.is_false()
	assert_int(mortars.models[0].wounds_current).is_equal(3)
	assert_int(mortars.models[2].wounds_current).is_equal(3)


func test_the_wounded_tough_model_with_the_most_wounds_taken_goes_first() -> void:
	var squad := _unit(1, 3, [3, 3, 3])
	squad.models[0].wounds_current = 2   # 1 taken
	squad.models[2].wounds_current = 1   # 2 taken — the one to finish
	assert_int(_deal(squad, 1, 1)).is_equal(1)
	assert_bool(squad.models[2].is_alive).is_false()
	assert_int(squad.models[0].wounds_current).is_equal(2)


func test_a_fresh_tough_weapon_team_is_hit_after_the_plain_bodies() -> void:
	# p.15: a Tough model that joined a unit without it "is removed last". Three plain bodies + a fresh Tough(3) team
	# with the special weapon: a Deadly(3) wound used to land on the team (most remaining wounds).
	var squad := _unit(1, 4, [1, 1, 1, 3])
	squad.models[3].properties = {"weapons": [{"name": "Missile Launcher"}]}
	assert_int(_deal(squad, 1, 3)).is_equal(1)
	assert_int(squad.models[3].wounds_current) \
		.override_failure_message("D17 — a Deadly wound hit the fresh Tough weapon team before the plain bodies") \
		.is_equal(3)
	assert_int(squad.get_alive_count()).is_equal(3)


func test_deadly_pick_says_when_the_wound_is_forced() -> void:
	var fresh := _unit(1, 3, [3, 3, 3])
	assert_bool(bool(SoloController.deadly_pick(fresh)["forced"])).is_false()   # fresh bodies: the defender picks
	fresh.models[2].wounds_current = 2
	var pick := SoloController.deadly_pick(fresh)
	assert_bool(bool(pick["forced"])).is_true()                                 # a wounded Tough body: continue on it
	assert_int(int(pick["index"])).is_equal(2)
	assert_bool(SoloController.deadly_pick(_unit(1, 3, [1, 1, 1]))["forced"]).is_false()   # plain bodies are never "wounded"


func test_a_joined_hero_takes_deadly_wounds_last_even_when_already_wounded() -> void:
	var host := _unit(1, 1, [1])
	var hero := _unit(1, 1, [3])
	hero.models[0].wounds_current = 1
	host.unit_properties["attached_heroes"] = [hero]
	hero.unit_properties["attached_to"] = host
	var first := SoloController.deadly_pick(host)
	assert_bool(first["unit"] == host) \
		.override_failure_message("D17 — the wounded hero was picked before the host's own model") \
		.is_true()
	assert_int(_deal(host, 1, 3)).is_equal(1)
	assert_bool(host.models[0].is_alive).is_false()
	# The host is gone: the NEXT Deadly wound reaches the hero (dead-host wounds used to be wasted).
	var second := SoloController.deadly_pick(host)
	assert_bool(second["unit"] == hero).is_true()
	assert_bool(bool(second["forced"])).is_true()
	assert_int(_deal(host, 1, 3)).is_equal(1)
	assert_bool(hero.models[0].is_alive).is_false()
	assert_bool(SoloController.deadly_pick(host).is_empty()).is_true()
