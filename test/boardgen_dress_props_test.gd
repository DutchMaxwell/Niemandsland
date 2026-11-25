extends GdUnitTestSuite
## The props planner (SPEC_RUINTOWN_DRESSING step 30) on the stub kit: one lamp visual per lantern
## point of BoardgenTownDressing.lanterns() (outer lamps included) within 0.2 in of it, a bracket
## never below CLEAR, the fountain and the plinth inside their solid landmark footprints, the solid
## landmark colliders untouched, no honesty rule broken, and a town with the modules dresses the
## class (the greybox post + glowing cube stay the no-kit fallback).

const SEEDS := [41, 25]
const IN := 0.0254
const TOL_IN := 0.02


func _layout(board_seed: int) -> Dictionary:
	return (ClassDB.instantiate("NmlCore") as Object).boardgen_layout_themed(board_seed, "ruintown")


func _ctx(layout: Dictionary) -> DressContext:
	var kit := BoardgenKit.new("ruintown")
	add_child(kit)
	auto_free(kit)
	var dress := BoardgenDressKit.new(kit, true)
	return DressContext.new(layout, dress, BoardgenDressStory.of(layout), int(layout["seed"]))


## The XZ rect (board inches) a placement's module aabb covers through its transform.
func _rect(ctx: DressContext, p: DressPlacement) -> Rect2:
	var spec := ctx.spec(p.module)
	var lo := spec.aabb_lo
	var hi := spec.aabb_hi
	var r := Rect2()
	for k in 8:
		var c := Vector3(hi.x if k & 1 else lo.x, hi.y if k & 2 else lo.y, hi.z if k & 4 else lo.z)
		var q := p.transform * (c * IN) / IN
		r = Rect2(q.x, q.z, 0.0, 0.0) if k == 0 else r.expand(Vector2(q.x, q.z))
	return r


func _distance(at: Vector2, r: Rect2) -> float:
	var near := Vector2(clampf(at.x, r.position.x, r.end.x), clampf(at.y, r.position.y, r.end.y))
	return at.distance_to(near)


## The test's own door zones (R12, independent of the planner): every opening from the ground up
## of a house placement, widened 0.5 in either side, 0..1.0 in out from the face (board inches).
func _doors(ctx: DressContext) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for pl: DressPlacement in BoardgenDressHouses.new().plan(ctx):
		for op: Array in ctx.spec(pl.module).openings:
			if float(op[2]) <= 0.05:
				var b := pl.transform.basis
				var p := Vector2(pl.transform.origin.x, pl.transform.origin.z) / IN
				var a := Vector2(b.x.x, b.x.z).normalized()
				out.append(
					{
						"p": p,
						"a": a,
						"o": Vector2(b.z.x, b.z.z).normalized(),
						"s0": float(op[0]) - 0.5,
						"s1": float(op[1]) + 0.5
					}
				)
	return out


func _blocks(z: Dictionary, q: Vector2, r: float) -> bool:
	var s: float = (q - z["p"]).dot(z["a"])
	var o: float = (q - z["p"]).dot(z["o"])
	return s > z["s0"] - r and s < z["s1"] + r and o > -0.3 - r and o < 1.0 + r


func test_one_lamp_visual_per_lantern_point_within_a_fifth_of_an_inch() -> void:
	var kinds := {}
	for board_seed: int in SEEDS:
		var layout := _layout(board_seed)
		var ctx := _ctx(layout)
		var lamps := BoardgenDressProps.new().plan(ctx).filter(
			func(p: DressPlacement) -> bool: return p.module.begins_with("dr_lamp_")
		)
		var points: Array[Dictionary] = BoardgenTownDressing.lanterns(layout)
		var doors := _doors(ctx)
		assert_int(lamps.size()).is_less_equal(points.size())
		for l: Dictionary in points:
			if doors.any(func(z: Dictionary) -> bool: return _blocks(z, l["at"], 0.4)):
				continue  # a point at a door: its lamp moves along the face or is dropped (R12)
			var hits := 0
			for p: DressPlacement in lamps:
				kinds[p.module] = true
				if _distance(l["at"], _rect(ctx, p)) <= 0.2 + 0.001:
					hits += 1
			(
				assert_int(hits)
				. override_failure_message("seed %d at %s" % [board_seed, l["at"]])
				. is_equal(1)
			)
	assert_bool(kinds.has("dr_lamp_bracket") and kinds.has("dr_lamp_post")).is_true()


func test_a_bracket_hangs_no_lower_than_clear() -> void:
	var brackets := 0
	for board_seed: int in SEEDS:
		var ctx := _ctx(_layout(board_seed))
		for p: DressPlacement in BoardgenDressProps.new().plan(ctx):
			if p.module != "dr_lamp_bracket":
				continue
			brackets += 1
			var bottom := (
				(p.transform * (Vector3(0.0, ctx.spec(p.module).aabb_lo.y, 0.0) * IN)).y / IN
			)
			assert_float(bottom).is_greater_equal(BoardgenDressRules.CLEAR - 0.001)
	assert_int(brackets).is_greater(0)


func test_fountain_and_plinth_sit_inside_their_solid_footprints() -> void:
	var seen := {}
	for board_seed: int in SEEDS:
		var layout := _layout(board_seed)
		var ctx := _ctx(layout)
		var placed := BoardgenDressProps.new().plan(ctx)
		for lm: Dictionary in layout["landmarks"]:
			var module: String = {"TankCluster": "dr_fountain", "Crane": "dr_statue_plinth"}.get(
				lm["kind"], ""
			)
			if module == "":
				continue
			var foot := Rect2(
				ctx.origin_in + Vector2(lm["x"], lm["z"]) * ctx.cell_in,
				Vector2(lm["w"], lm["h"]) * ctx.cell_in
			)
			var mine := placed.filter(
				func(p: DressPlacement) -> bool:
					return (
						p.module == module
						and foot.has_point(Vector2(p.transform.origin.x, p.transform.origin.z) / IN)
					)
			)
			assert_int(mine.size()).is_equal(1)
			if mine.size() == 1:
				var p: DressPlacement = mine[0]
				assert_bool(foot.grow(TOL_IN).encloses(_rect(ctx, p))).is_true()
				assert_float(p.transform.origin.y).is_equal_approx(0.0, 0.0001)
				seen[module] = true
	assert_bool(seen.has("dr_fountain") and seen.has("dr_statue_plinth")).is_true()


func test_the_solid_landmarks_keep_their_colliders() -> void:
	var table: Node3D = auto_free(Node3D.new())
	add_child(table)
	var layout := _layout(41)
	var board := BoardgenGreybox.attach(table, layout)
	var shapes := board.find_children("*", "CollisionShape3D", true, false)
	var cell := float(layout["cell_in"])
	var org := Vector2(int(layout["nx"]), int(layout["nz"])) * cell * -0.5
	var found := 0
	for lm: Dictionary in layout["landmarks"]:
		if not lm["solid"]:
			continue
		found += 1
		var size := (
			Vector3(float(lm["w"]) * cell, BoardgenGreybox.SOLID_IN, float(lm["h"]) * cell) * IN
		)
		var c := org + (Vector2(lm["x"], lm["z"]) + Vector2(lm["w"], lm["h"]) * 0.5) * cell
		var centre := Vector3(c.x, BoardgenGreybox.SOLID_IN * 0.5, c.y) * IN
		var hit := false
		for shape: CollisionShape3D in shapes:
			var box := shape.shape as BoxShape3D
			if (
				box != null
				and box.size.is_equal_approx(size)
				and shape.position.is_equal_approx(centre)
			):
				hit = true
		assert_bool(hit).override_failure_message("%s keeps its collider" % lm["kind"]).is_true()
	assert_int(found).is_greater(0)
	board.free()


func test_the_props_break_no_honesty_rule() -> void:
	for board_seed: int in SEEDS:
		var ctx := _ctx(_layout(board_seed))
		var placed := BoardgenDressProps.new().plan(ctx)
		var lines := BoardgenDressRules.violations(ctx, placed)
		(
			assert_array(Array(lines))
			. override_failure_message("seed %d: %s" % [board_seed, lines])
			. is_empty()
		)
		assert_int(placed.size()).is_greater(0)


func test_a_town_with_the_prop_modules_dresses_its_lamps() -> void:
	var kit := BoardgenKit.new("ruintown")
	add_child(kit)
	auto_free(kit)
	var dress: BoardgenDress = auto_free(BoardgenDress.new(BoardgenDressKit.new(kit, true)))
	assert_bool(dress.setup(_layout(41))).is_true()
	assert_bool(dress.classes().has("props")).is_true()  # the greybox skips its lantern boxes
	for b: Dictionary in BoardgenTownDressing.lantern_boxes(_layout(41)):
		assert_bool(BoardgenGreybox.draws_itself(b, dress.classes())).is_false()
		assert_bool(BoardgenGreybox.draws_itself(b, {})).is_true()


## R12 (maintainer 25.11.): a lamp never stands in front of a door - no post or bracket within the
## door opening + 0.5 in either side, 1.0 in out from the face, on seeds 41, 25 and 1-20.
func test_no_lamp_stands_in_front_of_a_door() -> void:
	var near := 0
	var seeds: Array[int] = [41, 25]
	for s in range(1, 21):
		seeds.append(s)
	for board_seed in seeds:
		var layout := _layout(board_seed)
		var ctx := _ctx(layout)
		var doors := _doors(ctx)
		assert_int(doors.size()).is_greater(0)
		for l: Dictionary in BoardgenTownDressing.lanterns(layout):
			if doors.any(func(z: Dictionary) -> bool: return _blocks(z, l["at"], 0.4)):
				near += 1
				if board_seed == 41:
					print("R12 seed 41 lantern at a door: ", l["at"])
		for p: DressPlacement in BoardgenDressProps.new().plan(ctx):
			if not p.module.begins_with("dr_lamp_"):
				continue
			var r := _rect(ctx, p)
			for z: Dictionary in doors:
				var hit := false
				for q: Vector2 in [
					r.position,
					r.end,
					Vector2(r.position.x, r.end.y),
					Vector2(r.end.x, r.position.y),
					r.get_center()
				]:
					hit = hit or _blocks(z, q, 0.0)
				(
					assert_bool(hit)
					. override_failure_message(
						"seed %d: %s at %s blocks a door" % [board_seed, p.module, r.get_center()]
					)
					. is_false()
				)
	print("R12 lantern points at a door over 22 seeds: ", near)
	assert_int(near).is_greater(0)  # the case occurs on real boards (else this test proves nothing)
