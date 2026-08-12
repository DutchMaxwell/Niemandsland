extends GdUnitTestSuite
## Missions wave M2a — the deployment-style catalog data model. front_line
## must state TODAY'S implicit deployment exactly (12" strips off each long
## edge, player 1 on the z-negative side): any drift here would silently
## redeploy every game the catalog feeds. Unknown ids fall back to
## front_line — data refines, never breaks. Spearhead and opposing_forces
## get wedge/corner sanity checks on top of the exact front_line match.


func before_test() -> void:
	DeploymentCatalog.reset_cache()


func test_catalog_lists_the_v1_six() -> void:
	assert_that(DeploymentCatalog.style_ids()).is_equal(
		["disordered", "front_line", "ground_war", "opposing_forces", "side_battle", "spearhead"])


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
	assert_bool(DeploymentCatalog.in_zone(style, 1, Vector2(-30, 20))).is_true()
	assert_bool(DeploymentCatalog.in_zone(style, 1, Vector2(-30, -20))).is_false()
	assert_bool(DeploymentCatalog.in_zone(style, 2, Vector2(30, -20))).is_true()
	assert_bool(DeploymentCatalog.in_zone(style, 2, Vector2(30, 20))).is_false()
