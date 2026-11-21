extends GdUnitTestSuite
## The half-timber shells (plan PLAN_RUINTOWN_TARGET_C, train 3) on real town boards from the core: the frame panels lie ON a house face (at most 0.2 in proud of the
## collider), the ruins' panels stay on their tier's face, below its top and off every ladder face. Nothing here touches a level, a cell or a collider.

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
