extends GdUnitTestSuite
## Tests for CoherencyChecker - OPR Unit Coherency (Grimdark Future Advanced
## Rules v3.5.0): models must form an uninterrupted chain in 1" coherency
## (3" across different elevation) AND stay within 9" of all other models.
##
## Bases are set to 0mm so edge-to-edge distance equals centre-to-centre,
## keeping the geometry in these tests easy to reason about.

const INCH := 0.0254  # meters per inch


# ===== Helpers =====

func _model_at(unit: GameUnit, index: int, pos: Vector3) -> ModelInstance:
	var node: Node3D = auto_free(Node3D.new())
	add_child(node)
	node.global_position = pos

	var model := ModelInstance.new()
	model.model_index = index
	model.is_alive = true
	model.node = node
	model.unit = unit
	return model


func _make_unit(positions: Array) -> GameUnit:
	var unit := GameUnit.new()
	unit.unit_properties = {"base_size_round": 0, "base_is_oval": false}
	for i in range(positions.size()):
		unit.models.append(_model_at(unit, i, positions[i]))
	return unit


func _issues_of_type(result, type: int) -> Array:
	var out: Array = []
	for issue in result.issues:
		if issue.type == type:
			out.append(issue)
	return out


func _isolated(result) -> Array:
	return _issues_of_type(result, CoherencyChecker.IssueType.ISOLATED)


func _chain(result) -> Array:
	return _issues_of_type(result, CoherencyChecker.IssueType.CHAIN_TOO_LONG)


func _flagged_indices(issues: Array) -> Array:
	var indices: Array = []
	for issue in issues:
		indices.append(issue.model.model_index)
	return indices


# ===== Joined Hero coherency =====

func test_attached_hero_out_of_coherency_is_flagged() -> void:
	# Host: two models 0.5" apart (coherent). Joined hero 5" away -> isolated.
	var host := _make_unit([Vector3.ZERO, Vector3(0.5 * INCH, 0, 0)])
	var hero := _make_unit([Vector3(5.0 * INCH, 0, 0)])
	EquipmentDistributor.attach_hero_to_unit(hero, host)

	var result := CoherencyChecker.check_unit_coherency(host)
	assert_bool(result.valid).is_false()
	assert_int(_isolated(result).size()).is_equal(1)


func test_attached_hero_within_coherency_is_valid() -> void:
	# Host two models at 0 and 0.5"; hero 0.5" from the second -> coherent.
	var host := _make_unit([Vector3.ZERO, Vector3(0.5 * INCH, 0, 0)])
	var hero := _make_unit([Vector3(1.0 * INCH, 0, 0)])
	EquipmentDistributor.attach_hero_to_unit(hero, host)

	var result := CoherencyChecker.check_unit_coherency(host)
	assert_bool(result.valid).is_true()


# ===== 1" Chain (connectivity) =====

func test_single_model_is_always_coherent() -> void:
	var unit := _make_unit([Vector3.ZERO])
	var result := CoherencyChecker.check_unit_coherency(unit)
	assert_bool(result.valid).is_true()


func test_two_models_within_one_inch_are_coherent() -> void:
	var unit := _make_unit([Vector3.ZERO, Vector3(0.8 * INCH, 0, 0)])
	var result := CoherencyChecker.check_unit_coherency(unit)
	assert_bool(result.valid).is_true()


func test_two_models_beyond_one_inch_break_coherency() -> void:
	var unit := _make_unit([Vector3.ZERO, Vector3(2.0 * INCH, 0, 0)])
	var result := CoherencyChecker.check_unit_coherency(unit)

	assert_bool(result.valid).is_false()
	assert_int(_isolated(result).size()).is_equal(1)


func test_chain_of_three_models_is_coherent() -> void:
	var unit := _make_unit([
		Vector3.ZERO,
		Vector3(0.8 * INCH, 0, 0),
		Vector3(1.6 * INCH, 0, 0),
	])
	var result := CoherencyChecker.check_unit_coherency(unit)
	assert_bool(result.valid).is_true()


func test_two_separate_clusters_break_coherency() -> void:
	# Cluster A (models 0,1,2) tight; cluster B (3,4) tight but 4" away.
	# Each model has a 1" neighbour, yet the unit is not one connected chain.
	var unit := _make_unit([
		Vector3(0.0, 0, 0),
		Vector3(0.5 * INCH, 0, 0),
		Vector3(1.0 * INCH, 0, 0),
		Vector3(5.0 * INCH, 0, 0),
		Vector3(5.5 * INCH, 0, 0),
	])
	var result := CoherencyChecker.check_unit_coherency(unit)

	assert_bool(result.valid).is_false()
	# Main chain is the larger cluster (A); the 2-model cluster B is flagged.
	var isolated := _isolated(result)
	assert_int(isolated.size()).is_equal(2)
	assert_array(_flagged_indices(isolated)).contains([3, 4])


func test_isolated_issue_reports_nearest_unit_model() -> void:
	var unit := _make_unit([Vector3.ZERO, Vector3(2.0 * INCH, 0, 0)])
	var result := CoherencyChecker.check_unit_coherency(unit)

	var isolated := _isolated(result)
	assert_int(isolated.size()).is_equal(1)
	assert_object(isolated[0].get("nearest_model")).is_not_null()
	assert_float(isolated[0].get("nearest_distance")).is_equal_approx(2.0, 0.05)


# ===== 9" Spread =====

func test_connected_chain_exceeding_nine_inches_is_flagged() -> void:
	# 11 models spaced 0.95" apart: every link <= 1" (connected as one chain),
	# but the unit spans ~9.5" so it exceeds the 9" spread rule.
	var positions: Array = []
	for i in range(11):
		positions.append(Vector3(i * 0.95 * INCH, 0, 0))
	var unit := _make_unit(positions)
	var result := CoherencyChecker.check_unit_coherency(unit)

	assert_bool(result.valid).is_false()
	assert_int(_isolated(result).size()).is_equal(0)  # fully connected
	assert_int(_chain(result).size()).is_equal(1)      # but too spread out


# ===== Elevation =====

func test_elevation_allows_three_inch_coherency() -> void:
	# 2" apart horizontally but at clearly different heights -> linked (<= 3").
	var unit := _make_unit([Vector3.ZERO, Vector3(2.0 * INCH, 0.1, 0)])
	var result := CoherencyChecker.check_unit_coherency(unit)
	assert_bool(result.valid).is_true()


# ===== Dead models =====

func test_dead_models_are_ignored() -> void:
	# A dead model far away must not break the living unit's coherency.
	var unit := _make_unit([
		Vector3.ZERO,
		Vector3(0.5 * INCH, 0, 0),
		Vector3(20.0 * INCH, 0, 0),
	])
	unit.models[2].is_alive = false
	var result := CoherencyChecker.check_unit_coherency(unit)
	assert_bool(result.valid).is_true()
