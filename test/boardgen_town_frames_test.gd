extends GdUnitTestSuite
## The half-timber shells (plan PLAN_RUINTOWN_TARGET_C, train 3) on real town boards from the core: the frame panels lie ON a house face (at most 0.2 in proud of the
## collider), the ruins' panels stay on their tier's face below its top and off every ladder face, the timber gables, corner posts and chimney stacks stay inside the
## 0.75 in edge strip (gables no higher than the masonry gable they replace, stacks below the 9 in tower crown). Nothing here touches a level, a cell or a collider.

const SEEDS := [3, 7, 11, 13, 25, 41]
const EPS := 0.002
## The modules' bounds in their own frame (inches; the H1 build log): x along the face, y up (nominal 1), z out of the face.
const BOUNDS := {"hf_panel_window": [Vector3(-1.5, 0.0, -0.02), Vector3(1.5, 1.0, 0.07)], "hf_panel_shutter": [Vector3(-1.5, 0.0, -0.02), Vector3(1.5, 1.0, 0.108)],
	"hf_panel_boarded": [Vector3(-1.5, 0.0, -0.02), Vector3(1.5, 1.0, 0.1)], "hf_panel_brace": [Vector3(-1.5, 0.0, -0.02), Vector3(1.5, 1.0, 0.07)],
	"hf_panel_lath": [Vector3(-1.5, 0.0, -0.02), Vector3(1.5, 1.0, 0.07)], "hf_panel_plain": [Vector3(-1.5, 0.0, -0.02), Vector3(1.5, 1.0, 0.07)],
	"hf_panel_brace1": [Vector3(-1.5, 0.0, -0.02), Vector3(1.5, 1.0, 0.07)], "hf_door": [Vector3(-1.5, 0.0, -0.02), Vector3(1.5, 1.0, 0.18)],
	"hf_post": [Vector3(-0.07, 0.0, -0.07), Vector3(0.07, 1.0, 0.07)], "hf_gable": [Vector3(-1.511, -0.05, -0.26), Vector3(1.5, 1.942, -0.04)],
	"hf_gable_burnt": [Vector3(-1.5, -0.05, -0.26), Vector3(1.511, 1.699, -0.04)], "hf_beam_fallen": [Vector3(-1.371, -0.014, 0.006), Vector3(1.204, 0.521, 0.643)],
	"hf_stub_post": [Vector3(-0.091, 0.0, -0.168), Vector3(0.104, 1.239, 0.08)]}


func _towns() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var core: Object = ClassDB.instantiate("NmlCore")
	for s: int in SEEDS:
		out.append(core.boardgen_layout_themed(s, "ruintown"))
	return out


func _origin(layout: Dictionary) -> Vector2:
	return Vector2(layout["nx"], layout["nz"]) * float(layout["cell_in"]) * -0.5


## The eight corners of an item's module box in board inches.
func _corners(item: Dictionary) -> Array[Vector3]:
	var b: Array = BOUNDS[item["module"]]
	var xf: Transform3D = item["xf"]
	var out: Array[Vector3] = []
	for k in 8:
		var p := Vector3(b[1].x if k & 1 else b[0].x, b[1].y if k & 2 else b[0].y, b[1].z if k & 4 else b[0].z)
		out.append(xf * (p * BoardgenTownFrames.IN_M) / BoardgenTownFrames.IN_M)
	return out


## The cell rect of a lot (board inches).
func _lot_rect(layout: Dictionary, lot: Dictionary) -> Rect2:
	var c := float(layout["cell_in"])
	return Rect2(_origin(layout) + Vector2(lot["x"], lot["z"]) * c, Vector2(lot["w"], lot["h"]) * c)


## How far a point lies outside a rect (0 inside).
func _outside(r: Rect2, p: Vector2) -> float:
	return maxf(maxf(r.position.x - p.x, p.x - r.end.x), maxf(r.position.y - p.y, p.y - r.end.y))


func test_house_panels_lie_on_their_own_house_face_at_most_a_fifth_of_an_inch_proud() -> void:
	var total := 0
	for layout in _towns():
		var rects: Array[Rect2] = []
		for lot: Dictionary in layout["lots"]:
			if lot["kind"] == "Roofed":
				rects.append(_lot_rect(layout, lot))
		var tops := {}
		for b: Dictionary in BoardgenTownDressing.house_bodies(layout):
			tops[b["lot"]] = b["top"]
		for item: Dictionary in BoardgenTownFrames.house_items(layout):
			total += 1
			var cs := _corners(item)
			var mid := (cs[0] + cs[7]) * 0.5
			var own: Rect2 = rects.filter(func(r: Rect2) -> bool: return _outside(r, Vector2(mid.x, mid.z)) < 0.25).front()
			for p: Vector3 in cs:
				assert_float(_outside(own, Vector2(p.x, p.z))).override_failure_message("a house panel %.3f in off its collider face" % _outside(own, Vector2(p.x, p.z))).is_less_equal(0.2 + EPS)
				assert_float(p.y).is_between(-EPS, 3.0)
	assert_int(total).is_greater(40)


func test_tier_panels_stay_on_their_tier_face_below_its_top_and_off_every_ladder_face() -> void:
	var total := 0
	for layout in _towns():
		var tops: Array[Vector2] = []
		for c: Dictionary in layout["connectors"]:
			tops.append(Vector2(c["edge_in"][0], c["edge_in"][1]) + _origin(layout))
		for item: Dictionary in BoardgenTownFrames.tier_items(layout):
			total += 1
			var at: Vector3 = (item["xf"] as Transform3D).origin / BoardgenTownFrames.IN_M
			for t: Vector2 in tops:
				assert_float(t.distance_to(Vector2(at.x, at.z))).override_failure_message("a ruin panel on a ladder face").is_greater(0.5)
			var out_dir: Vector3 = (item["xf"] as Transform3D).basis.z.normalized()
			var q := ((Vector2(at.x - out_dir.x * 0.1, at.z - out_dir.z * 0.1) - _origin(layout)) / float(layout["cell_in"])).floor()
			var cd: Dictionary = layout["cells"][int(q.y) * int(layout["nx"]) + int(q.x)]
			assert_array(["Wall", "Roofed"]).not_contains([str(cd["lot_kind"])])   # on a ruined tier's own face (Block, Deck, Terrace or a raised ruin of a street sector)
			assert_int(int(cd["level"])).is_between(1, 2)
			for p: Vector3 in _corners(item):
				assert_float(p.y).override_failure_message("a ruin panel above its tier's top").is_between(-EPS, float(layout["level_in"][cd["level"]]) + EPS)
	assert_int(total).is_greater(20)


func test_timber_gables_stay_in_the_edge_strip_and_never_above_the_masonry_gable() -> void:
	var total := 0
	for layout in _towns():
		var faces: Array = []
		BoardgenTownSilhouette.ruin_gables(layout, {}, faces)
		var lots := {}
		for lot: Dictionary in layout["lots"]:
			lots[lot["id"]] = lot
		var timber := BoardgenTownFrames.timber_lots(layout)
		var masonry := BoardgenTownSilhouette.ruin_gables(layout, timber)
		assert_int(masonry.size()).is_less(BoardgenTownSilhouette.ruin_gables(layout).size() + 1)
		for item: Dictionary in BoardgenTownFrames.ruin_items(layout).filter(func(i: Dictionary) -> bool: return str(i["module"]).begins_with("hf_gable")):
			total += 1
			var cs := _corners(item)
			var mid := (cs[0] + cs[7]) * 0.5
			var f: Dictionary = faces.filter(func(f: Dictionary) -> bool: return (f["mid"] as Vector2).distance_to(Vector2(mid.x, mid.z)) < 0.3).front()
			assert_bool(f["free"]).is_true()   # never on a face with a ladder top
			var r := _lot_rect(layout, lots[f["lot"]])
			for p: Vector3 in cs:
				assert_float(_outside(r, Vector2(p.x, p.z))).is_less_equal(EPS)   # inside the lot
				assert_float(p.y).is_less_equal(float(f["top"]) + float(f["peak"]) + EPS)
				var d := DIRS_TO_DEPTH(r, f["side"], Vector2(p.x, p.z))
				assert_float(d).override_failure_message("a gable %.3f in deep" % d).is_less_equal(0.75)
	assert_int(total).is_greater(0)


## Depth of a point behind the lot's face on `side` (N, E, S, W).
func DIRS_TO_DEPTH(r: Rect2, side: int, p: Vector2) -> float:
	match side:
		0:
			return p.y - r.position.y
		1:
			return r.end.x - p.x
		2:
			return r.end.y - p.y
	return p.x - r.position.x


func test_snapped_corner_posts_stand_on_a_tier_corner_inside_the_strip() -> void:
	var total := 0
	for layout in _towns():
		for item: Dictionary in BoardgenTownFrames.ruin_items(layout).filter(func(i: Dictionary) -> bool: return i["module"] == "hf_stub_post"):
			total += 1
			var at: Vector3 = (item["xf"] as Transform3D).origin / BoardgenTownFrames.IN_M
			var q := ((Vector2(at.x, at.z) - _origin(layout)) / float(layout["cell_in"])).floor()
			var cd: Dictionary = layout["cells"][int(q.y) * int(layout["nx"]) + int(q.x)]
			assert_float(at.y).is_equal_approx(float(layout["level_in"][cd["level"]]), EPS)   # stands ON the tier top
			var r := Rect2(_origin(layout) + q * float(layout["cell_in"]), Vector2.ONE * float(layout["cell_in"]))
			for p: Vector3 in _corners(item):
				assert_float(_outside(r, Vector2(p.x, p.z))).is_less_equal(EPS)
				var dx := minf(p.x - r.position.x, r.end.x - p.x)
				var dz := minf(p.z - r.position.y, r.end.y - p.z)
				assert_float(maxf(dx, dz)).override_failure_message("a corner post off its corner").is_less_equal(0.75)
	assert_int(total).is_greater_equal(0)


func test_chimney_stacks_on_ruins_stay_in_the_strip_and_below_the_tower_crown() -> void:
	var total := 0
	for layout in _towns():
		for item: Dictionary in BoardgenTownFrames.ruin_items(layout).filter(func(i: Dictionary) -> bool: return str(i["module"]).begins_with("chimney")):
			total += 1
			var xf: Transform3D = item["xf"]
			var at := xf.origin / BoardgenTownFrames.IN_M
			var half := xf.basis.x.length() * 0.38   # the corbel's half width (0.76 in), scaled
			var q := ((Vector2(at.x, at.z) - _origin(layout)) / float(layout["cell_in"])).floor()
			var r := Rect2(_origin(layout) + q * float(layout["cell_in"]), Vector2.ONE * float(layout["cell_in"]))
			var to_edge := minf(minf(at.x - r.position.x, r.end.x - at.x), minf(at.z - r.position.y, r.end.y - at.z))
			assert_float(to_edge + half).override_failure_message("a stack off the edge strip").is_less_equal(0.75 + EPS)
			assert_float(to_edge - half).is_greater_equal(-EPS)
			assert_float(at.y + xf.basis.y.length() * 3.78).is_less_equal(BoardgenTownFrames.STACK_TOP_IN + EPS)
	assert_int(total).is_greater(0)
