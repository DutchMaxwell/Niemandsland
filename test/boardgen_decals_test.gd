extends GdUnitTestSuite
## The decals of a boardgen board (BoardgenDecals, AAA step 12): one seed plans the same decals every time, at most 48, every one is a
## cell of the atlas manifest, none lies on a ladder foot, a sump or a landmark, a leak sits under a free pipe end and a numeral
## names the height of the wall it is on. Pure plan() on the recorded seed 42 layout; build() is only checked for the empty cache.

const FIXTURE := "res://test/fixtures/boardgen/layout_42.txt"
const CELL_IN := 3.0


func _fixture() -> Dictionary:
	return str_to_var(FileAccess.get_file_as_string(FIXTURE))


## The cell (x, z) a point (inches off the board centre) is in.
func _cell_at(layout: Dictionary, p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL_IN + layout["nx"] * 0.5), floori(p.z / CELL_IN + layout["nz"] * 0.5))


func _bare_cells(layout: Dictionary) -> Dictionary:
	var bare := {}
	for c: Dictionary in layout["connectors"]:
		bare[Vector2i(c["low_xz"][0], c["low_xz"][1])] = true
	for i in layout["cells"].size():
		if layout["cells"][i]["lot_kind"] == "Hazard":
			bare[Vector2i(i % int(layout["nx"]), i / int(layout["nx"]))] = true
	return bare


func test_one_seed_plans_the_same_decals_and_another_seed_others() -> void:
	var layout := _fixture()
	var first := BoardgenDecals.plan(layout)
	assert_int(first.size()).is_greater(8)
	randomize()
	assert_array(BoardgenDecals.plan(_fixture())).is_equal(first)
	var other := _fixture()
	other["seed"] = int(layout["seed"]) + 1
	assert_bool(BoardgenDecals.plan(other) == first).is_false()


func test_at_most_48_and_every_cell_is_in_the_manifest() -> void:
	var cells: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/tiefwerk_manifest.json"))["decals"]["cells"]
	for seed_offset in 12:   # a few seeds, the cap must hold on all
		var layout := _fixture()
		layout["seed"] = int(layout["seed"]) + seed_offset
		var plan := BoardgenDecals.plan(layout)
		assert_int(plan.size()).is_less_equal(BoardgenDecals.MAX_DECALS)
		for e in plan:
			assert_bool(cells.has(e["cell"])).override_failure_message("%s is not an atlas cell" % e["cell"]).is_true()


func test_every_kind_stays_within_its_cap_and_none_is_crowded_out() -> void:
	var caps := {"num_": 14, "louvre_": 4, "scorch": 4, "leak_oil": 4, "leak_rust": 10, "grime_corner": 6, "floor_arrow": 6}
	for seed_offset in 6:
		var layout := _fixture()
		layout["seed"] = int(layout["seed"]) + seed_offset
		var count := {}
		for e in BoardgenDecals.plan(layout):
			for prefix: String in caps:
				if str(e["cell"]).begins_with(prefix):
					count[prefix] = count.get(prefix, 0) + 1
		for prefix: String in caps:
			assert_int(count.get(prefix, 0)).override_failure_message("%s: %d over the cap %d" % [prefix, count.get(prefix, 0), caps[prefix]]).is_less_equal(caps[prefix])
	var base := BoardgenDecals.plan(_fixture())
	assert_int(base.filter(func(e: Dictionary) -> bool: return str(e["cell"]).begins_with("num_")).size()).is_equal(14)   # the numerals keep their share


func test_no_decal_on_a_ladder_foot_a_sump_or_a_landmark() -> void:
	var layout := _fixture()
	layout["landmarks"] = [{"kind": "TankCluster", "x": 4, "z": 4, "w": 3, "h": 3, "turn": 0}]
	var bare := _bare_cells(layout)
	for dz in 3:
		for dx in 3:
			bare[Vector2i(4 + dx, 4 + dz)] = true
	assert_int(bare.size()).is_greater(9)
	for e in BoardgenDecals.plan(layout):
		var on: Vector3 = e["pos"] + e["n"] * 0.5   # a point just off the surface, on the open side
		assert_bool(bare.has(_cell_at(layout, on))).override_failure_message("%s lies on a bare cell %s" % [e["cell"], _cell_at(layout, on)]).is_false()


func test_a_numeral_names_the_height_of_its_wall() -> void:
	var layout := _fixture()
	var seen := 0
	for e in BoardgenDecals.plan(layout):
		if str(e["cell"]).begins_with("num_"):
			var wall_cell := _cell_at(layout, e["pos"] - e["n"] * 0.5)   # just behind the surface: the tier block
			var h: float = layout["level_in"][layout["cells"][wall_cell.y * int(layout["nx"]) + wall_cell.x]["level"]]
			assert_str(e["cell"]).is_equal("num_%d" % int(h))
			seen += 1
	assert_int(seen).is_greater(0)


func test_a_leak_hangs_under_a_free_pipe_end() -> void:
	var layout := _fixture()
	var ends: Array[Vector3] = []
	for p: Dictionary in BoardgenProps.plan(layout):
		var s: Vector3 = p["xf"].basis.get_scale() / BoardgenProps.INCHES_TO_METERS
		if p["shape"] == "cyl" and absf(s.y - (CELL_IN - 0.12)) < 0.01:
			var c: Vector3 = p["xf"].origin / BoardgenProps.INCHES_TO_METERS
			for sign_ in [-1.0, 1.0]:
				ends.append(c + p["xf"].basis.y.normalized() * s.y * 0.5 * sign_)
	var leaks := 0
	for e in BoardgenDecals.plan(layout):
		if e["cell"] == "leak_rust":
			leaks += 1
			assert_bool(ends.any(func(end: Vector3) -> bool: return Vector2(end.x, end.z).distance_to(Vector2(e["pos"].x, e["pos"].z)) < 0.8 and e["pos"].y < end.y)).is_true()
	assert_int(leaks).is_greater(0)


func test_nothing_is_built_while_the_atlas_is_not_cached() -> void:
	var lib := TiefwerkLibrary.new()
	add_child(lib)
	auto_free(lib)
	var fake := {"url": "x.webp", "sha256": "decals_test_not_cached", "size": 1}   # a hash that no cache holds, whatever this machine has downloaded
	lib.apply_manifest_text(JSON.stringify({"decals": {"atlas_px": 8, "albedo": fake, "normal": fake, "orm": fake, "cells": {"scorch": {"x": 0, "y": 0, "w": 8, "h": 8}}}}))
	var decals := BoardgenDecals.new()
	add_child(decals)
	auto_free(decals)
	decals.build(_fixture(), lib)
	assert_int(decals.get_child_count()).is_equal(0)
