extends GdUnitTestSuite
## Tray-exact S4 — the TABLE side of the casualty-order parity pin. Every unit in
## core/nml-core/tests/fixtures/casualty_order.json is built as a GameUnit and
## SoloController.casualty_order must return the fixture's "expected"; the core's
## casualty::casualty_order is pinned to the same file (casualty.rs), so both agree.

const FIXTURE := "res://core/nml-core/tests/fixtures/casualty_order.json"


func _unit(spec: Dictionary) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = str(spec["name"])
	u.unit_properties = {"player_id": 1, "name": u.unit_id, "quality": 4, "defense": 4, "special_rules": []}
	for ms in spec["models"]:
		var m := ModelInstance.new()
		m.is_alive = true
		m.unit = u
		m.wounds_max = int(ms["wounds_max"])
		m.wounds_current = int(ms["wounds"])
		var weapons: Array = []
		for w in ms["weapons"]:
			weapons.append({"name": w})
		var equipment: Array = []
		for k in range(int(ms["equipment"])):
			equipment.append("Item %d" % k)
		m.properties = {"weapons": weapons, "equipment": equipment}
		var n := Node3D.new()
		add_child(n)
		n.global_position = Vector3(ms["pos"][0], ms["pos"][1], ms["pos"][2])
		m.node = n
		u.models.append(m)
	return u


## Tray-exact S5 — the chain-keeping order (SoloController.chain_casualty_order) on the fixture's
## "chains": round bases of `base_mm` at base scale 1 (model tough property 1), every pick.
func test_the_tables_chain_casualty_order_matches_the_shared_fixture() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	for spec in data["chains"]:
		var u := _unit(spec)
		u.unit_properties["base_size_round"] = int(spec["base_mm"])
		u.unit_properties["game_system"] = "gf"
		for m in u.models:
			(m as ModelInstance).properties["tough"] = 1
		var got: Array = SoloController.chain_casualty_order(u)
		var want: Array = (spec["expected"] as Array).map(func(x: Variant) -> int: return int(x))
		assert_array(got).override_failure_message("%s: table %s, fixture %s" % [
			spec["name"], str(got), str(want)]).is_equal(want)


func test_the_tables_casualty_order_matches_the_shared_fixture() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	for spec in data["units"]:
		var got: Array = SoloController.casualty_order(_unit(spec))
		var want: Array = (spec["expected"] as Array).map(func(x: Variant) -> int: return int(x))  # JSON numbers are floats
		assert_array(got).override_failure_message("%s: table %s, fixture %s" % [
			spec["name"], str(got), str(want)]).is_equal(want)


## EPOCH_94_PARITY_BATCH: symmetric formations whose mirror models tie or part by rounding only. The fixture's `ties` hold
## the Godot board's f32 positions; the table's order on them is the reference the core's `f32_dist` reading is pinned to
## (casualty.rs). Exact ties in units above 16 models: the two tests below.
func test_the_tables_casualty_order_on_symmetric_formations_matches_the_shared_fixture() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	for spec in data["ties"]:
		var got: Array = SoloController.casualty_order(_unit(spec))
		var want: Array = (spec["expected"] as Array).map(func(x: Variant) -> int: return int(x))
		assert_array(got).override_failure_message("%s: table %s, fixture %s" % [
			spec["name"], str(got), str(want)]).is_equal(want)


## shootpos (gate 12, games 7/9/19): a 20-model unit whose mirror models share one rank EXACTLY. The core sorts stably
## (casualty.rs `sort_by`), so a tie keeps the slot order; Godot's sort_custom is unstable from 17 elements, so the table
## removed a different mirror model (game 7: core 0, table 19). The table must break the tie by slot index.
## A 5 x 4 grid on 0.0625 m steps: every coordinate is exact in f32, so the four corners {0, 4, 15, 19} tie exactly.
func test_a_twenty_model_grid_breaks_exact_rank_ties_by_slot_like_the_core() -> void:
	var models: Array = []
	for r in range(4):
		for c in range(5):
			models.append({"wounds_max": 1, "wounds": 1, "weapons": ["Rifle"], "equipment": 0,
				"pos": [(c - 2) * 0.0625, 0.0, (r - 1.5) * 0.0625]})
	var got: Array = SoloController.casualty_order(_unit({"name": "grid 5x4", "models": models}))
	# the core's stable order on this grid (outermost first, ties by slot)
	assert_array(got).is_equal([0, 4, 15, 19, 5, 9, 10, 14, 1, 3, 16, 18, 2, 17, 6, 8, 11, 13, 7, 12])


## Twenty models with one and the same rank: the twenty integer points of a radius-25 circle, scaled to 1/64 m, so every
## distance to the (exact, zero) centroid is 25/64 m in f32 as well. The order must be the slot order, as the core's.
func test_twenty_equal_rank_models_keep_their_slot_order() -> void:
	var pts: Array = [[25, 0], [-7, 24], [20, -15], [0, -25], [-24, -7], [15, 20], [7, -24], [-20, 15], [24, 7], [-15, -20],
		[-25, 0], [7, 24], [-20, -15], [0, 25], [24, -7], [-15, 20], [-7, -24], [20, 15], [-24, 7], [15, -20]]
	var models: Array = []
	for p in pts:
		models.append({"wounds_max": 1, "wounds": 1, "weapons": ["Rifle"], "equipment": 0,
			"pos": [float(p[0]) / 64.0, 0.0, float(p[1]) / 64.0]})
	var got: Array = SoloController.casualty_order(_unit({"name": "ring 20", "models": models}))
	assert_array(got).is_equal(range(20))
