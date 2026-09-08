extends GdUnitTestSuite
## Issue #340 — the off-table tray grouped by arrival class with headers and counts.
## The tray's staged units (Ambush reserve, staged Scouts, Transport cargo, Reinforcement
## promises) sort into four fixed groups, one non-interactive header per class with a live
## count. Pure-seam tests: the flag-level classification, the group plan (fixed order, a
## stable secondary sort on the existing row key, live counts, class changes re-slot on
## rebuild) and the header nodes' non-interactivity. No tray node or army import needed.


func _gu(id: String, props: Dictionary = {}) -> GameUnit:
	var gu := GameUnit.new()
	gu.unit_id = id
	gu.unit_properties = props
	return gu


func test_one_unit_of_each_class_renders_four_headers_in_fixed_order_with_counts() -> void:
	var units: Array = [
		_gu("r1", {"reinforcement_due_round": 2}),
		_gu("s1", {"special_rules": ["Scout"]}),
		_gu("a1", {"ambush_reserve": true}),
		_gu("c1", {"embarked_in": "T1"}),
	]
	var plan: Array = OPRArmyManager.tray_group_plan(units)
	assert_array(plan).has_size(4)
	var order: Array = []
	var counts: Array = []
	var labels: Array = []
	for g in plan:
		order.append(str(g["class"]))
		counts.append(int(g["count"]))
		labels.append(OPRArmyManager.tray_group_label(str(g["class"]), int(g["count"])))
	assert_array(order).is_equal(["Ambush", "Scout", "Transport cargo", "Reinforcement"])
	assert_array(counts).is_equal([1, 1, 1, 1])
	assert_array(labels).is_equal(["Ambush — 1", "Scout — 1", "Transport cargo — 1", "Reinforcement — 1"])


func test_secondary_sort_is_stable_on_the_existing_row_key_inside_each_class() -> void:
	var units: Array = [
		_gu("b2", {"ambush_reserve": true}),
		_gu("a1", {"ambush_reserve": true}),
		_gu("b1", {"ambush_reserve": true}),
	]
	var plan: Array = OPRArmyManager.tray_group_plan(units)
	assert_array(plan).has_size(1)
	var ids: Array = []
	for gu in plan[0]["rows"]:
		ids.append((gu as GameUnit).unit_id)
	assert_array(ids).is_equal(["a1", "b1", "b2"])


func test_empty_classes_are_left_out_of_the_plan() -> void:
	# No header for a class with no staged units — and an unstaged unit (no flags, no rules)
	# never enters a group.
	var plan: Array = OPRArmyManager.tray_group_plan([_gu("x1", {})])
	assert_array(plan).is_empty()


func test_cargo_unit_that_disembarks_leaves_the_cargo_group_on_rebuild() -> void:
	var cargo := _gu("c1", {"embarked_in": "T1"})
	var before: Array = OPRArmyManager.tray_group_plan([cargo])
	assert_array(before).has_size(1)
	assert_str(str(before[0]["class"])).is_equal("Transport cargo")
	cargo.unit_properties.erase("embarked_in")   # disembark clears the flag (no grouping state)
	var after: Array = OPRArmyManager.tray_group_plan([cargo])
	assert_array(after).is_empty()               # re-classified from scratch on the next rebuild


func test_headers_are_plain_flat_labels_and_never_selectable() -> void:
	var tray: Node3D = auto_free(Node3D.new())
	var header: Label3D = OPRArmyManager.build_tray_group_header(tray, "Ambush — 3")
	assert_str(header.text).is_equal("Ambush — 3")
	assert_array(tray.get_children()).has_size(1)   # one node, no collider children at all
	assert_bool(header.is_in_group("selectable")).is_false()
