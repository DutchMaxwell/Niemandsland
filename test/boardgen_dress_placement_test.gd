extends GdUnitTestSuite
## DressPlacement and DressContext: the temporary dictionary bridge of the planners, and the grid
## lookups a planner reads (tops, walkability, the kept-clear cells, the module specs).

const R := preload("res://scripts/boardgen_dress_rules.gd")
const SEED := 41


func _layout(seed := SEED) -> Dictionary:
	return (ClassDB.instantiate("NmlCore") as Object).boardgen_layout_themed(seed, "ruintown")


func _kit() -> BoardgenDressKit:
	var town := BoardgenKit.new("ruintown")
	add_child(town)
	auto_free(town)
	return BoardgenDressKit.new(town, true)


func _context(layout: Dictionary) -> DressContext:
	return DressContext.new(layout, _kit(), {}, SEED)


func test_from_dict_reads_the_planner_fields_and_defaults() -> void:
	var xf := Transform3D(Basis(Vector3.UP, 0.5), Vector3(1.0, 2.0, 3.0))
	var p := (
		DressPlacement
		. from_dict(
			{
				"module": "dr_house_tb_plain_a",
				"xf": xf,
				"cls": "houses",
				"lot": 7,
				"variant": "holed",
			}
		)
	)
	assert_str(p.module).is_equal("dr_house_tb_plain_a")
	assert_bool(p.transform == xf).is_true()
	assert_str(p.cls).is_equal("houses")
	assert_int(p.lot).is_equal(7)
	assert_str(p.look).is_equal("holed")
	var bare := DressPlacement.from_dict(
		{"module": "dr_litter_straw", "xf": Transform3D(), "cls": "clutter"}
	)
	assert_int(bare.lot).is_equal(-1)
	assert_str(bare.look).is_empty()


func test_the_context_reads_the_grid_through_the_rules() -> void:
	var layout := _layout()
	var context := _context(layout)
	var nx := int(layout["nx"])
	for i in (layout["cells"] as Array).size():
		var x := i % nx
		var z := floori(i / float(nx))
		assert_float(context.top_in(x, z)).is_equal(R.top_in(layout, x, z))
		assert_bool(context.walkable(i)).is_equal(R.walkable(layout, i))
	assert_float(context.top_in(-1, 0)).is_equal(0.0)
	assert_float(context.top_in(0, int(layout["nz"]))).is_equal(0.0)


func test_kept_clear_is_the_rules_result_and_is_cached() -> void:
	var layout := _layout()
	var context := _context(layout)
	var first := context.kept_clear()
	assert_dict(first).is_equal(R.kept_clear(layout))
	assert_bool(is_same(first, context.kept_clear())).is_true()


func test_spec_returns_the_kit_spec_and_null_for_an_unknown_module() -> void:
	var context := _context(_layout())
	var spec := context.spec("dr_house_tb_plain_a")
	assert_object(spec).is_not_null()
	assert_str(spec.name).is_equal("dr_house_tb_plain_a")
	assert_object(context.spec("dr_nope")).is_null()
	assert_object(DressContext.new(_layout(), null, {}, SEED).spec("dr_house_tb_plain_a")).is_null()
