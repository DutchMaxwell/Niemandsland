extends GdUnitTestSuite
## Missions wave M2a — the deployment-style catalog data model. front_line
## must state TODAY'S implicit deployment exactly (12" strips off each long
## edge, player 1 on the z-negative side): any drift here would silently
## redeploy every game the catalog feeds. Unknown ids fall back to
## front_line — data refines, never breaks. Spearhead and opposing_forces
## get wedge/corner sanity checks on top of the exact front_line match.


func before_test() -> void:
	DeploymentCatalog.reset_cache()


func test_catalog_lists_the_v1_six_and_the_attack_defend_three() -> void:
	assert_that(DeploymentCatalog.style_ids()).is_equal(
		["anywhere", "centre_disc_12", "disordered", "edge_band_12", "front_line", "ground_war",
		"opposing_forces", "side_battle", "spearhead"])


func test_front_line_matches_todays_live_constants() -> void:
	var style := DeploymentCatalog.get_style("front_line")
	assert_bool(DeploymentCatalog.in_zone(style, 1, Vector2(0, -20))).is_true()
	assert_bool(DeploymentCatalog.in_zone(style, 2, Vector2(0, 20))).is_true()
	assert_bool(DeploymentCatalog.in_zone(style, 1, Vector2(0, 0))).is_false()
	assert_bool(DeploymentCatalog.in_zone(style, 2, Vector2(0, 0))).is_false()
	assert_bool(DeploymentCatalog.in_zone(style, 1, Vector2(0, 20))).is_false()
	# Edge pins: one inch either side of the 12" strip boundary, so ANY
	# depth drift flips an assertion (a 12->18 mutation once slipped
	# through the coarser points above — prove-the-check-can-fail).
	assert_bool(DeploymentCatalog.in_zone(style, 1, Vector2(0, -13))).is_true()
	assert_bool(DeploymentCatalog.in_zone(style, 1, Vector2(0, -11))).is_false()
	assert_bool(DeploymentCatalog.in_zone(style, 2, Vector2(0, 13))).is_true()
	assert_bool(DeploymentCatalog.in_zone(style, 2, Vector2(0, 11))).is_false()


func test_unknown_id_falls_back_to_front_line() -> void:
	var s := DeploymentCatalog.get_style("no_such_style")
	assert_that(s).is_equal(DeploymentCatalog.get_style("front_line"))


func test_spearhead_wedge_sanity() -> void:
	var style := DeploymentCatalog.get_style("spearhead")
	assert_bool(DeploymentCatalog.in_zone(style, 1, Vector2(-34, 0))).is_true()
	assert_bool(DeploymentCatalog.in_zone(style, 1, Vector2(-10, 0))).is_false()
	assert_bool(DeploymentCatalog.in_zone(style, 1, Vector2(-20, 22))).is_false()
	assert_bool(DeploymentCatalog.in_zone(style, 1, Vector2(-20, 4))).is_true()


func test_opposing_forces_corners() -> void:
	var style := DeploymentCatalog.get_style("opposing_forces")
	assert_bool(DeploymentCatalog.in_zone(style, 2, Vector2(-30, 20))).is_true()
	assert_bool(DeploymentCatalog.in_zone(style, 2, Vector2(-30, -20))).is_false()
	assert_bool(DeploymentCatalog.in_zone(style, 1, Vector2(30, -20))).is_true()
	assert_bool(DeploymentCatalog.in_zone(style, 1, Vector2(30, 20))).is_false()


## The role convention (the front-line overlay's too): player 1 owns the z-negative side; a style that splits left / right
## (equal z) gives player 1 the x-negative side. Role-agnostic styles carry the same zone under both keys and have no side.
## Read from the JSON for EVERY style on EVERY board, so a new entry cannot drift from it.
func test_player_one_owns_the_negative_side_of_every_style_on_every_board() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DeploymentCatalog.CATALOG_PATH))
	var sets := {"72x48": data["styles"]}
	for key in data.get("boards", {}):
		sets[key] = data["boards"][key]
	var checked := 0
	for board in sets:
		for id in sets[board]:
			var zones: Dictionary = sets[board][id]["zones"]
			if zones["1"] == zones["2"]:
				continue
			checked += 1
			var m1 := _mean_xz(zones["1"])
			var m2 := _mean_xz(zones["2"])
			var ok: bool = m1.y < m2.y - 1e-6 or (absf(m1.y - m2.y) <= 1e-6 and m1.x < m2.x - 1e-6)
			assert_bool(ok).override_failure_message("%s/%s: player 1 is not on the negative side (z %.1f vs %.1f, x %.1f vs %.1f)" % [
				board, id, m1.y, m2.y, m1.x, m2.x]).is_true()
	assert_int(checked).is_greater_equal(5)


## Mean of every vertex (a disc counts as its centre) of a player's zone list, as (x, z).
func _mean_xz(polys: Array) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for poly in polys:
		if poly is Dictionary:
			var c: Array = (poly as Dictionary)["disc"]["c"]
			sum += Vector2(c[0], c[1])
			n += 1
			continue
		for xz in poly:
			sum += Vector2(xz[0], xz[1])
			n += 1
	return sum / maxf(n, 1.0)


## D4a: the SAME six points per style are pinned in core/nml-core/tests/objectives.rs (D4b).
const AD_POINTS := {
	"centre_disc_12": [[0, 0, true], [11, 0, true], [13, 0, false], [0, -13, false], [8, 8, true], [9, 9, false]],
	"edge_band_12": [[0, -20, true], [30, 0, true], [0, 0, false], [23, 0, false], [0, 11, false], [-35, 23, true]],
	"anywhere": [[0, 0, true], [35, 23, true], [-35, -23, true], [37, 0, false], [0, 25, false], [37, 25, false]],
}


func test_attack_defend_styles_pin_six_points_each_for_both_players() -> void:
	for id in AD_POINTS:
		var style := DeploymentCatalog.get_style(id)
		for pt in AD_POINTS[id]:
			for player in [1, 2]:
				assert_bool(DeploymentCatalog.in_zone(style, player, Vector2(pt[0], pt[1]))) \
					.override_failure_message("%s p%d (%s, %s)" % [id, player, pt[0], pt[1]]).is_equal(pt[2])


func test_zone_polygons_turn_a_disc_into_a_ring_and_keep_polygons() -> void:
	var disc := DeploymentCatalog.zone_polygons(DeploymentCatalog.get_style("centre_disc_12"), 1)
	assert_int(disc.size()).is_equal(1)
	assert_int((disc[0] as PackedVector2Array).size()).is_equal(48)
	assert_float((disc[0] as PackedVector2Array)[7].length()).is_equal_approx(12.0, 0.001)
	assert_int(DeploymentCatalog.zone_polygons(DeploymentCatalog.get_style("edge_band_12"), 2).size()).is_equal(4)


func test_the_overlay_draws_one_mesh_per_polygon_for_a_style() -> void:
	var ov = auto_free(preload("res://scripts/terrain_overlay.gd").new())
	ov.set_style_zones(DeploymentCatalog.get_style("edge_band_12"))
	assert_int(ov.deployment_zone_meshes.size()).is_equal(8)
	ov.set_style_zones(DeploymentCatalog.get_style("centre_disc_12"))
	assert_int(ov.deployment_zone_meshes.size()).is_equal(2)
