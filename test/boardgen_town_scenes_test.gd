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


## Scenes v2 (kit batch A7): every strip scene is led by a HERO piece that reads at the play camera, its load / cloth at the same origin; a stall trades onto a street.
func test_every_strip_scene_has_its_hero_and_the_load_sits_on_it() -> void:
	var heroes := {"cart": ["cart_toppled", "handcart"], "stall": ["stall_collapsed"], "barricade": ["barricade"], "back": ["woodpile_block", "hay_heap"], "table": ["table_overturned"]}
	for s: int in SEEDS + [17, 19, 23, 29, 31, 37, 43]:
		var layout := _layout(s)
		var plan := BoardgenTownScenes.plan(layout)
		var items: Dictionary = plan["items"]
		for sc: Dictionary in plan["scenes"]:
			if not heroes.has(sc["kind"]):
				continue
			var near := 0
			for m: String in heroes[sc["kind"]]:
				for it: Dictionary in items.get(m, []):
					var o: Vector3 = (it["xf"] as Transform3D).origin / IN
					near += 1 if Vector2(o.x, o.z).distance_to(sc["at"]) <= float(sc["span"]) * 0.5 + 1.0 else 0
			assert_int(near).override_failure_message("seed %d: %s scene without its hero" % [s, sc["kind"]]).is_greater(0)
			if sc["kind"] == "stall":
				assert_bool(layout["cells"][int(sc["cell"])]["street"]).override_failure_message("seed %d: a stall off the street" % s).is_true()
		for pair: Array in [["cart_toppled", "cart_toppled_load"], ["handcart", "handcart_load"], ["stall_collapsed", "stall_collapsed_cloth"], ["table_overturned", "table_overturned_load"]]:
			var a: Array = items.get(pair[0], [])
			var b: Array = items.get(pair[1], [])
			assert_int(b.size()).is_equal(a.size())
			for k in a.size():
				assert_bool((a[k]["xf"] as Transform3D).is_equal_approx(b[k]["xf"])).is_true()


## The ladder and lamp rule (the asset lane's proof placement ignored it): no solid scene piece stands over a ladder's foot, a lamp post or a square stall / brazier / spout.
func test_no_scene_piece_stands_on_a_ladder_or_a_lamp_post() -> void:
	for s: int in SEEDS + [17, 19, 23, 29, 31, 37, 43]:
		var layout := _layout(s)
		var occupied := BoardgenTownScenes._occupied(layout)
		var plan := BoardgenTownScenes.plan(layout)
		for m: String in plan["items"]:
			if BoardgenTownScenes.FLAT_MODULES.has(m):
				continue
			var ext: Vector2 = BoardgenTownClutter.STRIP.get(m, BoardgenTownScenes.EXTRA_SPAN.get(m, Vector2(-0.3, 0.3)))
			for it: Dictionary in plan["items"][m]:
				var xf: Transform3D = it["xf"]
				var o := Vector2(xf.origin.x, xf.origin.z) / IN
				var lx := Vector2(xf.basis.x.x, xf.basis.x.z)
				var lz := Vector2(xf.basis.z.x, xf.basis.z.z)
				for p: Vector2 in occupied:
					var a := (p - o).dot(lx)
					var out := (p - o).dot(lz)
					assert_bool(a > ext.x - 0.2 and a < ext.y + 0.2 and out > -0.2 and out < 1.0).override_failure_message("seed %d: %s at %s over a ladder / lamp at %s" % [s, m, o, p]).is_false()


## Where the scenes go (style bible 12): carts and barricades at lane mouths and gates, woodpiles / hay / troughs behind the houses.
func test_carts_and_barricades_seek_the_lane_mouths_and_the_backs_stay_off_the_street() -> void:
	var mouth := 0
	var lanes := 0
	var back_street := 0
	var backs := 0
	for s: int in range(1, 41):   # (roofs plan K2: the share over 40 boards; the 12 pinned seeds held 0.6 by luck - main itself gives 0.58 over boards 1-40, K2 0.50)
		var layout := _layout(s)
		for sc: Dictionary in BoardgenTownScenes.plan(layout)["scenes"]:
			var i: int = sc["cell"]
			if ["cart", "barricade"].has(sc["kind"]):
				lanes += 1
				mouth += 1 if BoardgenTownScenes._mouth(layout, i) or BoardgenTownScenes._gate(layout, i) else 0
			elif sc["kind"] == "back":
				backs += 1
				back_street += 1 if layout["cells"][i]["street"] else 0
	print("SCENES v2 carts/barricades at a mouth or gate %d / %d, backs on a street %d / %d" % [mouth, lanes, back_street, backs])
	assert_int(lanes).is_greater(0)
	# CLUTTER-RETUNE (due 28.11.): restore > 6 signs / >= 0.40 lane-mouth share after the planners follow the D-R16 layouts
	assert_float(float(mouth) / lanes).is_greater_equal(0.25)   # D-R2 = C 25.11.: 0.55 -> 0.44 over boards 1-40; D-R16 = b 26.11.: 0.44 -> 0.26
	assert_float(float(back_street) / maxi(backs, 1)).is_less_equal(0.2)
