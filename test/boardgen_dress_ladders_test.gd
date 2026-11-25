extends GdUnitTestSuite
## The ladder planner (SPEC_RUINTOWN_DRESSING step 21) on the stub kit: one placement per segment
## of BoardgenGreybox.ladder_kit_plan, one dr_ladder_top per connector at the greybox's very
## transform, the honesty rules report nothing, the replaced box ladders are not solid, and with
## the planner the greybox draws no ladder box (the dressing takes the class).

const SEEDS := [41, 25, 3]


func _layout(board_seed: int) -> Dictionary:
	return (ClassDB.instantiate("NmlCore") as Object).boardgen_layout_themed(board_seed, "ruintown")


func _ctx(layout: Dictionary) -> DressContext:
	var kit := BoardgenKit.new("ruintown")
	add_child(kit)
	auto_free(kit)
	var dress := BoardgenDressKit.new(kit, true)
	return DressContext.new(layout, dress, BoardgenDressStory.of(layout), int(layout["seed"]))


func test_the_plan_is_the_kit_ladder_plan_renamed() -> void:
	for board_seed: int in SEEDS:
		var layout := _layout(board_seed)
		var kit := BoardgenGreybox.ladder_kit_plan(layout)
		var placed := BoardgenDressLadders.new().plan(_ctx(layout))
		var segments := 0
		for key: String in kit:
			segments += (kit[key] as Array).size()
		assert_int(placed.size()).is_equal(segments)
		var want: Array[Transform3D] = []
		for item: Dictionary in kit.get("ladder_top", []):
			want.append(item["xf"])
		var got: Array[Transform3D] = []
		for p: DressPlacement in placed:
			assert_bool(BoardgenDressLadders.MODULES.has(p.module)).is_true()
			assert_str(p.cls).is_equal("ladders")
			if p.module == "dr_ladder_top":
				got.append(p.transform)
		assert_int(got.size()).is_equal((layout["connectors"] as Array).size())
		assert_array(got).is_equal(want)


func test_the_dressed_ladders_break_no_honesty_rule() -> void:
	for board_seed: int in SEEDS:
		var layout := _layout(board_seed)
		var ctx := _ctx(layout)
		var lines := BoardgenDressRules.violations(ctx, BoardgenDressLadders.new().plan(ctx))
		(
			assert_array(Array(lines))
			. override_failure_message("seed %d: %s" % [board_seed, lines])
			. is_empty()
		)


func test_the_replaced_ladder_boxes_are_not_solid_and_skip_their_draw() -> void:
	for board_seed: int in SEEDS:
		var ladders := BoardgenGreybox.plan(_layout(board_seed)).filter(
			func(b: Dictionary) -> bool: return BoardgenDress.box_class(b) == "ladders"
		)
		assert_int(ladders.size()).is_greater(0)
		for b: Dictionary in ladders:
			assert_bool(b["solid"]).is_false()  # a solid ladder box would lose its collider
			assert_bool(BoardgenGreybox.draws_itself(b, {"ladders": true})).is_false()
			assert_bool(BoardgenGreybox.draws_itself(b, {})).is_true()  # no kit: the greybox ladder stays


func test_a_town_with_the_ladder_modules_dresses_its_ladders() -> void:
	var kit := BoardgenKit.new("ruintown")
	add_child(kit)
	auto_free(kit)
	var dress: BoardgenDress = auto_free(BoardgenDress.new(BoardgenDressKit.new(kit, true)))
	assert_bool(dress.setup(_layout(41))).is_true()
	assert_bool(dress.classes().has("ladders")).is_true()  # the greybox skips its ladder boxes
