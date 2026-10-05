extends GdUnitTestSuite
## The Ruined Borderland theme (maintainer: layout v3 OK, 05.10.): 14 free pieces the shelf knows, all on a 6x4 ft
## table, point-symmetric (every piece has a twin at the mirrored spot, turned 180 deg, so neither side gets the
## better cover), grassland and evening light. Other table sizes do not fit (D11: the entry is greyed out there).

const IN2M := 0.0254


func test_the_borderland_theme_loads_as_the_approved_table() -> void:
	var t := TableTheme.load_theme("ruined_borderland")
	assert_object(t).is_not_null()
	if t == null:
		return
	assert_str(t.biome).is_equal("temperate_grassland")
	assert_str(t.mood).is_equal("Sunset")
	assert_bool(t.fits(Vector2(6, 4))).is_true()
	assert_bool(t.fits(Vector2(4, 4))).is_false()
	assert_int(t.pieces.size()).is_equal(14)
	for p: Dictionary in t.pieces:
		var id: String = p["prop_id"]
		var known: bool = ObjectManager.SANDBOX_SOLIDS.has(id) or ObjectManager.SANDBOX_RUINS.has(id) \
			or ObjectManager.SANDBOX_GROUPS.has(id)
		assert_bool(known).override_failure_message("unknown piece %s" % id).is_true()
		var pos: Vector3 = p["position"]
		assert_bool(absf(pos.x) < 36.0 * IN2M and absf(pos.z) < 24.0 * IN2M).is_true()
		var twins := t.pieces.filter(func(q: Dictionary) -> bool:
			return q["prop_id"] == id and (q["position"] as Vector3).is_equal_approx(-pos) \
				and is_equal_approx(fposmod(float(q["yaw_deg"]) - float(p["yaw_deg"]), 360.0), 180.0))
		assert_int(twins.size()).override_failure_message("%s at %s has no mirrored twin" % [id, pos]).is_equal(1)
