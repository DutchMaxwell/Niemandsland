extends GdUnitTestSuite
## PLAN_COVER_36 step 9a: the table twin of core `sight::screen` over the SAME case file the Rust test reads
## (test/fixtures/one_core/cover_screen_cases.json): `VolumetricLos.screen` with eye / foot callables built on
## `VolumetricLos.has_los`, each case's verdict equal to its `want`. RED: without `VolumetricLos.screen` the suite does not
## parse; with the eye line only (no foot call) five cases fail.

const CASES := "res://test/fixtures/one_core/cover_screen_cases.json"


func _cyl(p: Array, r: float, h: float) -> Dictionary:
	return {"c": Vector2(p[0], p[2]), "r": r, "y0": float(p[1]), "y1": float(p[1]) + h}


func _verdict(c: Dictionary) -> Dictionary:
	var volumes: Array = []
	for b: Dictionary in c["boxes"]:
		volumes.append({"kind": "box", "c": Vector2(b["c"][0], b["c"][1]), "he": Vector2(b["he"][0], b["he"][1]),
			"yaw": float(b["yaw"]), "y0": float(b["y0"]), "y1": float(b["y1"]), "solid": true})
	var blockers: Array = []
	for b: Dictionary in c["blockers"]:
		blockers.append({"c": Vector2(b["c"][0], b["c"][1]), "r": float(b["r"]), "y0": float(b["y0"]), "y1": float(b["y1"]),
			"unit_key": int(b["unit"]), "is_aircraft": bool(b["aircraft"])})
	var sr := float(c["shooter_r"])
	var sh := float(c["shooter_h"])
	var tr := float(c["target_r"])
	var th := float(c["target_h"])
	var see := func(sp: Vector3, tp: Vector3, h: float) -> bool:
		return VolumetricLos.has_los({"c": Vector2(sp.x, sp.z), "r": sr, "y0": sp.y, "y1": sp.y + sh},
			{"c": Vector2(tp.x, tp.z), "r": tr, "y0": tp.y, "y1": tp.y + h}, volumes, blockers, [])
	var pos := func(key: String) -> Array:
		var out: Array = []
		for p: Array in c[key]:
			out.append(Vector3(p[0], p[1], p[2]))
		return out
	var group := {"pos": pos.call("shooters"), "eye": func(sp: Vector3, tp: Vector3) -> bool: return see.call(sp, tp, th),
		"foot": func(sp: Vector3, tp: Vector3) -> bool: return see.call(sp, tp, VolumetricLos.FOOT_LIFT_M)}
	return VolumetricLos.screen([group], pos.call("targets"), [])


func test_every_shared_case_gives_the_cores_verdict() -> void:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CASES))
	assert_float(float(doc["foot_lift_m"])).is_equal(VolumetricLos.FOOT_LIFT_M)
	var bad: Array = []
	for c: Dictionary in doc["cases"]:
		var got := _verdict(c)
		var want: Dictionary = c["want"]
		if int(got["sighting"]) != int(want["sighting"]) or got["hidden"] != want["hidden"] or got["screened"] != want["screened"]:
			bad.append("%s: got %s, want %s" % [c["name"], got, want])
	assert_int((doc["cases"] as Array).size()).is_equal(12)
	assert_array(bad).is_empty()
