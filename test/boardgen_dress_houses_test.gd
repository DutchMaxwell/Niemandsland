extends GdUnitTestSuite
## The house planner on the stub kit: seeds 41, 25 and 1-20. Every Roofed lot gets exactly one door, on the frontage's front face when it has one and on a free edge
## otherwise; every free cell edge (neighbour top below 2.5 in) carries exactly one panel and no other edge does; every lot gets four corner pieces; the honesty rules report nothing.

const H := preload("res://scripts/boardgen_dress_houses.gd")
const R := preload("res://scripts/boardgen_dress_rules.gd")


func _seeds() -> Array[int]:
	var out: Array[int] = [41, 25]
	for s in range(1, 21):
		out.append(s)
	return out


func _layout(seed: int) -> Dictionary:
	return (ClassDB.instantiate("NmlCore") as Object).boardgen_layout_themed(seed, "ruintown")


func _kit() -> BoardgenKit:
	var kit := BoardgenKit.new("ruintown")
	add_child(kit)
	auto_free(kit)
	return kit


func _ctx(layout: Dictionary, kit: BoardgenKit) -> Dictionary:
	var dress := BoardgenDressKit.new(kit, true)
	return {"kit": dress, "story": BoardgenDressStory.of(layout), "meta": dress.meta, "seed": int(layout["seed"])}


func _family(meta: Dictionary, module: String) -> String:
	return String((meta["modules"].get(module, {}) as Dictionary).get("family", ""))


## The cell a face placement belongs to: the midpoint at half the module's length, not the corner origin.
func _mid_cell(layout: Dictionary, p: Dictionary, meta: Dictionary) -> Vector2i:
	var m: Dictionary = meta["modules"][p["module"]]
	var mid := ((p["xf"] as Transform3D) * (Vector3(float(m["len_in"]) * 0.5, 0.0, 0.0) * R.IN_M)) / R.IN_M
	return _cell(layout, mid)


## The cell holding a board point in inches.
func _cell(layout: Dictionary, p_in: Vector3) -> Vector2i:
	var c := float(layout["cell_in"])
	return Vector2i(floori(p_in.x / c + int(layout["nx"]) * 0.5), floori(p_in.z / c + int(layout["nz"]) * 0.5))


func _origin_cell(layout: Dictionary, p: Dictionary) -> Vector2i:
	return _cell(layout, (p["xf"] as Transform3D).origin / R.IN_M)


## The face index N E S W a placement looks out of.
func _k_of(p: Dictionary) -> int:
	var o := Vector2((p["xf"] as Transform3D).basis.z.x, (p["xf"] as Transform3D).basis.z.z).normalized()
	var best := 0
	var best_dot := -2.0
	for k in 4:
		var d := o.dot(Vector2(float(R.DIRS[k].x), float(R.DIRS[k].y)))
		if d > best_dot:
			best_dot = d
			best = k
	return best


func _in_lot(lot: Dictionary, cell: Vector2i) -> bool:
	return cell.x >= int(lot["x"]) and cell.x < int(lot["x"]) + int(lot["w"]) and cell.y >= int(lot["z"]) and cell.y < int(lot["z"]) + int(lot["h"])


## The free edges of a Roofed lot, counted from the layout alone (neighbour top below the house's 2.5 in).
func _free_edges(layout: Dictionary, lot: Dictionary) -> int:
	var n := 0
	for cz in range(int(lot["z"]), int(lot["z"]) + int(lot["h"])):
		for cx in range(int(lot["x"]), int(lot["x"]) + int(lot["w"])):
			for k in 4:
				var nb := Vector2i(cx, cz) + R.DIRS[k]
				n += 1 if R.top_in(layout, nb.x, nb.y) < 2.5 else 0
	return n


func test_every_roofed_lot_has_exactly_one_door_on_its_front_face() -> void:
	var kit := _kit()
	for seed in _seeds():
		var layout := _layout(seed)
		var ctx := _ctx(layout, kit)
		var meta: Dictionary = ctx["meta"]
		var plan: Array = H.plan(layout, ctx)
		var fronts := {}
		for f: Dictionary in BoardgenTownDressing.frontage(layout):
			if String(f["front"]) != "":
				fronts[int(f["lot"])] = String(f["front"])
		var doors: Array = plan.filter(func(p: Dictionary) -> bool: return String(p["module"]).ends_with("_door"))
		for lot: Dictionary in layout["lots"]:
			if lot["kind"] != "Roofed":
				continue
			var mine: Array = doors.filter(func(p: Dictionary) -> bool: return _in_lot(lot, _mid_cell(layout, p, meta)))
			assert_int(mine.size()).override_failure_message("seed %d lot %d: %d doors" % [seed, lot["id"], mine.size()]).is_equal(1)
			if fronts.has(int(lot["id"])):
				var k := _k_of(mine[0])
				assert_str(H.FACE_NAMES[k]).override_failure_message("seed %d lot %d: door on %s, front is %s" % [seed, lot["id"], H.FACE_NAMES[k], fronts[int(lot["id"])]]).is_equal(fronts[int(lot["id"])])


func test_every_free_edge_carries_one_panel_and_no_walled_edge_does() -> void:
	var kit := _kit()
	for seed in _seeds():
		var layout := _layout(seed)
		var ctx := _ctx(layout, kit)
		var meta: Dictionary = ctx["meta"]
		var plan: Array = H.plan(layout, ctx)
		var panels: Array = plan.filter(func(p: Dictionary) -> bool: return _family(meta, p["module"]) == "house_panel")
		var free := 0
		for lot: Dictionary in layout["lots"]:
			if lot["kind"] == "Roofed":
				free += _free_edges(layout, lot)
		assert_int(panels.size()).override_failure_message("seed %d: %d panels for %d free edges" % [seed, panels.size(), free]).is_equal(free)
		for p: Dictionary in panels:
			var k := _k_of(p)
			var nb := _mid_cell(layout, p, meta) + R.DIRS[k]
			assert_bool(R.top_in(layout, nb.x, nb.y) < 2.5).override_failure_message("seed %d: %s faces a neighbour top of %.2f in" % [seed, p["module"], R.top_in(layout, nb.x, nb.y)]).is_true()


func test_every_roofed_lot_gets_four_corner_pieces() -> void:
	var kit := _kit()
	for seed in _seeds():
		var layout := _layout(seed)
		var ctx := _ctx(layout, kit)
		var meta: Dictionary = ctx["meta"]
		var plan: Array = H.plan(layout, ctx)
		var corners: Array = plan.filter(func(p: Dictionary) -> bool: return _family(meta, p["module"]) == "quoin")
		for lot: Dictionary in layout["lots"]:
			if lot["kind"] != "Roofed":
				continue
			var mine: Array = corners.filter(func(p: Dictionary) -> bool: return _in_lot(lot, _origin_cell(layout, p)))
			assert_int(mine.size()).override_failure_message("seed %d lot %d: %d corner pieces" % [seed, lot["id"], mine.size()]).is_equal(4)


func test_the_house_plan_is_honest_on_every_seed() -> void:
	var kit := _kit()
	for seed in _seeds():
		var layout := _layout(seed)
		var ctx := _ctx(layout, kit)
		var plan: Array = H.plan(layout, ctx)
		assert_bool(plan.size() > 0).override_failure_message("seed %d: no placements" % seed).is_true()
		var lines := R.violations(layout, plan, ctx["meta"])
		assert_array(lines).override_failure_message("seed %d: %s" % [seed, ", ".join(lines)]).is_empty()
