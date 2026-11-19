extends GdUnitTestSuite
## CC-10b: `CoreActivation.cast_inputs(report)` turns the planner's cast dicts into the core's `Input::Cast` shape
## (activation.rs `CastInput`, the parser in actcall.rs): one dict per planned cast, plan order, `seq` 0-based, every
## unit named by its roster key (`unit_id`), the payers as `[[key, tokens]..]` in spend order, the pools per foe slot.
## Pure: it reads the report and nothing else; nothing sends the array to the core yet (that is CC-13).
## RED: the payer lists (and the conduit / pools) dropped -> the assertions below see empty defaults.


func _unit(uid: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	return u


func _cast(caster: GameUnit, targets: Array, extra: Dictionary = {}) -> Dictionary:
	var d := {"caster": caster, "name": "Arcane Blast", "spell": {"name": "Arcane Blast",
		"effect": {"kind": "damage", "duration": "once"}}, "threshold": 1, "base_target": 4,
		"targets": targets, "boost": 0, "interference": 0, "interference_open": false}
	d.merge(extra, true)
	return d


func test_the_cast_input_matches_the_core_shape_and_keys_by_unit_id() -> void:
	var caster := _unit("m1")
	var target := _unit("e1")
	var helper := _unit("m2")
	var foe := _unit("e2")
	var conduit := _unit("m3")
	var relayed := _unit("e3")
	var input := _cast(caster, [target], {"boost": 2, "boost_sources": [{"unit": helper, "tokens": 2}],
		"interference": 1, "interference_sources": [{"unit": foe, "tokens": 1}],
		"conduit": conduit, "conduit_shaken": [{"rule": {"name": "Spell Conduit"}, "unit": relayed}],
		"pools": [[1, [{"unit": foe, "tokens": 2}, {"unit": relayed, "tokens": 1}]], [2, []]],
		"interference_open": true})
	var out := CoreActivation.cast_inputs({"casts": [input]})
	assert_int(out.size()).is_equal(1)
	if out.is_empty():
		return
	var c: Dictionary = out[0]
	var want := ["t", "seq", "caster", "spell", "targets", "base", "threshold", "boost", "boost_sources",
		"interference", "interference_sources", "conduit", "conduit_shaken", "pools", "once", "open"]
	var got := c.keys()
	got.sort()
	want.sort()
	assert_array(got).is_equal(want)
	assert_str(str(c.get("t", ""))).is_equal("cast")
	assert_int(int(c.get("seq", -1))).is_equal(0)
	assert_str(str(c.get("caster", ""))).is_equal("m1")
	assert_str(str(c.get("spell", ""))).is_equal("Arcane Blast")
	assert_array(c.get("targets", [])).is_equal(["e1"])
	assert_int(int(c.get("base", -1))).is_equal(4)
	assert_int(int(c.get("threshold", -1))).is_equal(1)
	assert_int(int(c.get("boost", -1))).is_equal(2)
	assert_array(c.get("boost_sources", [])).is_equal([["m2", 2]])
	assert_int(int(c.get("interference", -1))).is_equal(1)
	assert_array(c.get("interference_sources", [])).is_equal([["e2", 1]])
	assert_str(str(c.get("conduit", "?"))).is_equal("m3")
	assert_array(c.get("conduit_shaken", [])).is_equal(["e3"])
	var pools: Array = c.get("pools", [])
	assert_int(pools.size()).is_equal(2)
	if pools.size() == 2:
		assert_int(int((pools[0] as Array)[0])).is_equal(1)
		assert_array((pools[0] as Array)[1]).is_equal([["e2", 2], ["e3", 1]])
		assert_array((pools[1] as Array)[1]).is_empty()
	assert_bool(bool(c.get("once", false))).is_true()
	assert_bool(bool(c.get("open", false))).is_true()


func test_seq_rises_in_plan_order_and_no_conduit_is_the_empty_key() -> void:
	var caster := _unit("m1")
	var other := _unit("m2")
	var target := _unit("e1")
	var out := CoreActivation.cast_inputs({"casts": [_cast(caster, [target]), _cast(other, [target])]})
	assert_int(out.size()).is_equal(2)
	if out.size() != 2:
		return
	assert_int(int((out[0] as Dictionary).get("seq", -1))).is_equal(0)
	assert_int(int((out[1] as Dictionary).get("seq", -1))).is_equal(1)
	assert_str(str((out[0] as Dictionary).get("caster", ""))).is_equal("m1")
	assert_str(str((out[1] as Dictionary).get("caster", ""))).is_equal("m2")
	assert_str(str((out[0] as Dictionary).get("conduit", "?"))).is_equal("")
	assert_array((out[0] as Dictionary).get("boost_sources", [])).is_empty()
	assert_array((out[1] as Dictionary).get("interference_sources", [])).is_empty()
	assert_bool(bool((out[0] as Dictionary).get("open", true))).is_false()


func test_a_round_buff_needs_no_once() -> void:
	var caster := _unit("m1")
	var blast := _cast(caster, [_unit("e1")])
	blast["spell"] = {"name": "Spark", "effect": {"kind": "damage", "duration": "round"}}
	var out := CoreActivation.cast_inputs({"casts": [blast]})
	assert_int(out.size()).is_equal(1)
	if out.is_empty():
		return
	assert_bool(bool((out[0] as Dictionary).get("once", true))).is_false()


func test_an_empty_report_has_no_cast_inputs() -> void:
	assert_array(CoreActivation.cast_inputs({})).is_empty()