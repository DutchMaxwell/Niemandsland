extends GdUnitTestSuite
## PLAN_GAME_SYSTEM_SWITCH step 17: the table reads the catalogue's PER-BOARD entries by the same lookup the core does
## (deployment.rs `catalog_zones_for_board`: boards[key], and for 72 x 48 the top-level `styles`). Before this the table
## read only `styles`, so a 48 x 48 table was handed the 72 x 48 front_line polygon and nine styles. The parity cases
## compare the GDScript answer with the JSON the core reads, and re-do the core's `zones_fit_board` check on it.

const B48 := Vector2(48, 48)
const B72 := Vector2(72, 48)
## PLAN_GAME_SYSTEM_SWITCH step 18 (L-6): the standard family the Firefight / Skirmish books draw on their square diagrams.
const STANDARD_48: Array = ["disordered", "front_line", "ground_war", "opposing_forces", "side_battle", "spearhead"]


func before_test() -> void:
	DeploymentCatalog.reset_cache()


func after_test() -> void:
	DeploymentCatalog.reset_cache()


func _json() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(DeploymentCatalog.CATALOG_PATH))


func _max_abs_x(style: Dictionary) -> float:
	var hi := 0.0
	for player in [1, 2]:
		for poly in DeploymentCatalog.zone_polygons(style, player):
			for p in poly:
				hi = maxf(hi, absf(p.x))
	return hi


func test_a_48_by_48_table_is_handed_the_48_front_line_and_the_six_standard_styles() -> void:
	assert_array(DeploymentCatalog.style_ids(B48)).is_equal(STANDARD_48)
	var style := DeploymentCatalog.get_style("front_line", B48)
	assert_float(_max_abs_x(style)).is_equal(24.0)
	assert_bool(DeploymentCatalog.in_zone(style, 1, Vector2(0, -20))).is_true()
	assert_bool(DeploymentCatalog.in_zone(style, 1, Vector2(30, -20))).is_false()


func test_72_by_48_keeps_today_nine_styles_and_the_wide_front_line() -> void:
	assert_int(DeploymentCatalog.style_ids(B72).size()).is_equal(9)
	assert_array(DeploymentCatalog.style_ids()).is_equal(DeploymentCatalog.style_ids(B72))
	assert_float(_max_abs_x(DeploymentCatalog.get_style("front_line", B72))).is_equal(36.0)
	assert_dict(DeploymentCatalog.get_style("spearhead")).is_equal(DeploymentCatalog.get_style("spearhead", B72))


func test_a_style_the_board_does_not_define_falls_back_to_that_boards_front_line() -> void:
	assert_dict(DeploymentCatalog.get_style("centre_disc_12", B48)).is_equal(DeploymentCatalog.get_style("front_line", B48))


func test_zone_test_follows_the_board() -> void:
	var wide := DeploymentCatalog.zone_test("front_line", 1, B72)
	var square := DeploymentCatalog.zone_test("front_line", 1, B48)
	var probe := Vector2(30, -20) * DeploymentCatalog.IN2M   # inside the 72 x 48 strip, off the 48 x 48 table
	assert_bool(wide.call(probe)).is_true()
	assert_bool(square.call(probe)).is_false()
	assert_bool(square.call(Vector2(10, -20) * DeploymentCatalog.IN2M)).is_true()


func test_a_board_the_catalogue_does_not_describe_keeps_todays_styles() -> void:
	# A custom size has no entry: no styles are DEFINED for it (the core refuses it), the table keeps today's list.
	assert_dict(DeploymentCatalog.styles_for_board(Vector2(60, 36))).is_empty()
	assert_array(DeploymentCatalog.style_ids(Vector2(60, 36))).is_equal(DeploymentCatalog.style_ids())


func test_a_style_registered_at_run_time_is_valid_on_every_board() -> void:
	var disc := DeploymentCatalog.disc_style(Vector2(0, 0), 6.0)
	DeploymentCatalog.register_style("marker_disc_12", disc)
	assert_dict(DeploymentCatalog.get_style("marker_disc_12", B48)).is_equal(disc)
	assert_dict(DeploymentCatalog.get_style("marker_disc_12", B72)).is_equal(disc)


func test_every_board_style_equals_the_json_the_core_reads_and_fits_its_board() -> void:
	var data := _json()
	var boards: Dictionary = data.get("boards", {})
	assert_bool(boards.has("48x48")).override_failure_message("catalogue lost its 48x48 entry").is_true()
	for key in boards:
		var parts: PackedStringArray = str(key).split("x")
		var board := Vector2(float(parts[0]), float(parts[1]))
		assert_str(DeploymentCatalog.board_key(board)).is_equal(key)
		var got := DeploymentCatalog.styles_for_board(board)
		for id in boards[key]:
			assert_dict(got.get(id, {})).override_failure_message("%s/%s differs from the JSON" % [key, id]).is_equal(boards[key][id])
			_assert_fits(id, got[id], board)
	# 72 x 48 = the top-level styles, each of them fitting the wide board.
	var wide := DeploymentCatalog.styles_for_board(B72)
	for id in data["styles"]:
		assert_dict(wide.get(id, {})).override_failure_message("72x48/%s differs from the JSON" % id).is_equal(data["styles"][id])
		_assert_fits(id, wide[id], B72)


## deployment.rs `zones_fit_board`, restated: every vertex inside the centred rect, every disc inside it.
func _assert_fits(id: String, style: Dictionary, board: Vector2) -> void:
	for player in ["1", "2"]:
		for poly in (style["zones"] as Dictionary)[player]:
			if poly is Dictionary:
				var d: Dictionary = (poly as Dictionary)["disc"]
				var c: Array = d["c"]
				assert_bool(absf(c[0]) + float(d["r_in"]) <= board.x * 0.5 + 1e-6 and absf(c[1]) + float(d["r_in"]) <= board.y * 0.5 + 1e-6) \
					.override_failure_message("%s disc exceeds %s" % [id, board]).is_true()
				continue
			for xz in poly:
				assert_bool(absf(xz[0]) <= board.x * 0.5 + 1e-6 and absf(xz[1]) <= board.y * 0.5 + 1e-6) \
					.override_failure_message("%s vertex %s exceeds %s" % [id, xz, board]).is_true()


func _mean_z(style: Dictionary, player: int) -> float:
	var sum := 0.0
	var n := 0
	for poly in DeploymentCatalog.zone_polygons(style, player):
		for p in poly:
			sum += p.y
			n += 1
	return sum / maxf(n, 1.0)


func test_player_one_owns_the_z_negative_side_in_every_48_style() -> void:
	for id in STANDARD_48:
		var style := DeploymentCatalog.get_style(id, B48)
		assert_float(_mean_z(style, 1)).override_failure_message("%s: player 1 is not on the z-negative side" % id).is_less(0.0)
		assert_float(_mean_z(style, 2)).override_failure_message("%s: player 2 is not on the z-positive side" % id).is_greater(0.0)


## The book's square diagrams, probed one inch either side of every printed edge: [style, player, x, z, inside?].
func test_the_48_styles_match_the_book_diagrams() -> void:
	var cases := [
		["ground_war", 1, 5, -20, true], ["ground_war", 1, 20, -5, true], ["ground_war", 1, 5, -5, false], ["ground_war", 1, -5, -20, false],
		["ground_war", 2, -5, 20, true], ["ground_war", 2, -20, 5, true], ["ground_war", 2, -5, 5, false],
		["side_battle", 1, -20, -22, true], ["side_battle", 1, -23, -3, true], ["side_battle", 1, -23, -2, false], ["side_battle", 1, 19, -24, false],
		["side_battle", 2, 20, 22, true], ["side_battle", 2, 23, 3, true], ["side_battle", 2, 23, 2, false],
		["disordered", 1, -20, -20, true], ["disordered", 1, -10, -10, false], ["disordered", 2, 20, 20, true], ["disordered", 2, 0, 0, false],
		["spearhead", 1, 0, -13, true], ["spearhead", 1, 0, -11, false], ["spearhead", 1, 20, -23, true], ["spearhead", 1, 20, -20, false],
		["spearhead", 2, 0, 13, true], ["spearhead", 2, 0, 11, false],
		["opposing_forces", 1, 12, -18, true], ["opposing_forces", 1, 12, -10, false], ["opposing_forces", 1, -12, -18, false],
		["opposing_forces", 2, -12, 18, true], ["opposing_forces", 2, -12, 10, false], ["opposing_forces", 2, 12, 18, false],
	]
	for c in cases:
		var got := DeploymentCatalog.in_zone(DeploymentCatalog.get_style(c[0], B48), c[1], Vector2(c[2], c[3]))
		assert_bool(got).override_failure_message("%s player %d at (%d, %d): expected %s" % [c[0], c[1], c[2], c[3], c[4]]).is_equal(c[4])
