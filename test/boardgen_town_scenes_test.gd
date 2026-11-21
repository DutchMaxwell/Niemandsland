extends GdUnitTestSuite
## Story scenes of the ruin town (plan PLAN_RUINTOWN_GRIT S1 / S2): 5-7 per board from existing kit modules, never the same kind twice in a half, 6 in apart, the halves their own; and
## THE LOOK MUST NOT LIE - solid pieces only in the 0.75 in strip of a wall face or in a yard, flat pieces (<= 0.08 in) on open ground, nothing on a ladder end, landmark, pool or plot; at least
## 30 % of the open level-0 cells stay empty.

const SEEDS := [7, 25, 41, 11, 13]
const IN := 0.0254


func _layout(board_seed: int) -> Dictionary:
	return ClassDB.instantiate("NmlCore").boardgen_layout_themed(board_seed, "ruintown")


func _cell(layout: Dictionary, p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / 3.0 + int(layout["nx"]) * 0.5), floori(p.y / 3.0 + int(layout["nz"]) * 0.5))


func test_five_to_seven_scenes_a_board_no_kind_twice_in_a_half_six_inches_apart() -> void:
	for s: int in SEEDS:
		var plan := BoardgenTownScenes.plan(_layout(s))
		var scenes: Array = plan["scenes"]
		print("SCENES seed %d %s" % [s, scenes.map(func(e: Dictionary) -> String: return "%s/h%d" % [e["kind"], e["half"]])])
		assert_int(scenes.size()).override_failure_message("seed %d: %d scenes" % [s, scenes.size()]).is_between(5, 7)
		for half in 2:
			var kinds: Array = scenes.filter(func(e: Dictionary) -> bool: return e["half"] == half).map(func(e: Dictionary) -> String: return e["kind"])
			for k: String in kinds:
				assert_int(kinds.count(k)).is_equal(1)
		for i in scenes.size():
			for j in range(i + 1, scenes.size()):
				assert_float((scenes[i]["at"] as Vector2).distance_to(scenes[j]["at"])).is_greater_equal(6.0)
		assert_bool(BoardgenTownScenes.plan(_layout(s)) == plan).is_true()


func test_the_look_must_not_lie_solid_in_the_strip_or_a_yard_flat_on_open_ground() -> void:
	for s: int in SEEDS:
		var layout := _layout(s)
		var nx: int = layout["nx"]
		var clear := BoardgenTownClutter._kept_clear(layout)
		var plan := BoardgenTownScenes.plan(layout)
		for m: String in plan["items"]:
			for it: Dictionary in plan["items"][m]:
				var o: Vector3 = (it["xf"] as Transform3D).origin / IN
				var p := Vector2(o.x, o.z)
				var at := _cell(layout, p - Vector2(0.001, 0.001))
				var cd: Dictionary = layout["cells"][clampi(at.y, 0, 15) * nx + clampi(at.x, 0, 15)]
				if BoardgenTownScenes.FLAT_MODULES.has(m):
					var c2 := _cell(layout, p)
					var cf: Dictionary = layout["cells"][c2.y * nx + c2.x]
					assert_int(int(cf["level"])).override_failure_message("seed %d: flat %s on a raised cell" % [s, m]).is_equal(0)
					assert_bool(cf["lot_kind"] == "Hazard" or cf["lot_kind"] == "Rough" or clear.has(c2.y * nx + c2.x)).override_failure_message("seed %d: flat %s on %s" % [s, m, cf["lot_kind"]]).is_false()
					continue
				var fx := fposmod(p.x, 3.0)
				var fz := fposmod(p.y, 3.0)
				var on_face := minf(minf(fx, 3.0 - fx), minf(fz, 3.0 - fz)) < 0.01
				var c3 := _cell(layout, p)
				var yard: bool = layout["cells"][c3.y * nx + c3.x]["lot_kind"] == "Terrace" and int(layout["cells"][c3.y * nx + c3.x]["level"]) == 0
				assert_bool(on_face or yard).override_failure_message("seed %d: solid %s at %s is neither on a wall face nor in a yard" % [s, m, p]).is_true()
		for i: int in plan["reserved"]:
			assert_bool(clear.has(i)).is_false()


func test_the_halves_tell_their_own_scenes() -> void:
	var differ := 0
	for s: int in SEEDS:
		var scenes: Array = BoardgenTownScenes.plan(_layout(s))["scenes"]
		var a := scenes.filter(func(e: Dictionary) -> bool: return e["half"] == 0).map(func(e: Dictionary) -> String: return e["kind"])
		var b := scenes.filter(func(e: Dictionary) -> bool: return e["half"] == 1).map(func(e: Dictionary) -> String: return e["kind"])
		differ += 1 if a != b else 0
	assert_int(differ).is_greater_equal(SEEDS.size() - 1)


## The clutter counts of the style bible (rule 11), printed per seed: flat and strip pieces per 100 open level-0 cells and the share of those cells that carry nothing (>= 30 %).
func test_at_least_thirty_percent_of_the_open_cells_stay_empty() -> void:
	for s: int in SEEDS:
		var layout := _layout(s)
		var nx: int = layout["nx"]
		var open := {}
		for cd: Dictionary in layout["cells"]:
			if int(cd["level"]) == 0 and not ["Hazard", "Rough", "Roofed"].has(cd["lot_kind"]):
				open[int(cd["z"]) * nx + int(cd["x"])] = true
		var plan := BoardgenTownClutter.plan(layout)
		var carried := {}
		var flat := 0
		var solid := 0
		for m: String in plan:
			for it: Dictionary in plan[m]:
				var o: Vector3 = (it["xf"] as Transform3D).origin / IN
				var at := _cell(layout, Vector2(o.x, o.z) - Vector2(0.001, 0.001))
				var i := clampi(at.y, 0, 15) * nx + clampi(at.x, 0, 15)
				if not open.has(i):
					continue
				carried[i] = true
				if BoardgenTownClutter.FLAT.has(m):
					flat += 1
				else:
					solid += 1
		var empty := 1.0 - float(carried.size()) / float(open.size())
		print("CLUTTER seed %d open %d flat/100 %.1f solid/100 %.1f empty %.2f" % [s, open.size(), 100.0 * flat / open.size(), 100.0 * solid / open.size(), empty])
		assert_float(empty).is_greater_equal(0.3)
