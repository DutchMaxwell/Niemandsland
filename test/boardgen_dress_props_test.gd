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


func test_one_lamp_visual_per_lantern_point_within_a_fifth_of_an_inch() -> void:
	var kinds := {}
	for board_seed: int in SEEDS:
		var layout := _layout(board_seed)
		var ctx := _ctx(layout)
		var lamps := BoardgenDressProps.new().plan(ctx).filter(
			func(p: DressPlacement) -> bool: return p.module.begins_with("dr_lamp_")
		)
		var points: Array[Dictionary] = BoardgenTownDressing.lanterns(layout)
		assert_int(lamps.size()).is_equal(points.size())
		for l: Dictionary in points:
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
