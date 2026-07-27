extends GdUnitTestSuite
## Deployment-zone colour flip (asymmetric-map side choice). Pure colour math — the overlay is
## created WITHOUT add_child() so _ready()/rendering never run.

const OverlayScript := preload("res://scripts/terrain_overlay.gd")


func _overlay() -> Node3D:
	return auto_free(OverlayScript.new())


func test_zone_colors_default() -> void:
	var o := _overlay()
	assert_bool(o._zone_color("player1") == OverlayScript.DEPLOYMENT_COLORS["player1"]).is_true()
	assert_bool(o._zone_color("player2") == OverlayScript.DEPLOYMENT_COLORS["player2"]).is_true()


func test_zone_colors_flip_swaps() -> void:
	var o := _overlay()
	o.set_deployment_colors_flipped(true)
	assert_bool(o.deployment_colors_flipped).is_true()
	# Flipped: player1 shows player2's colour and vice versa.
	assert_bool(o._zone_color("player1") == OverlayScript.DEPLOYMENT_COLORS["player2"]).is_true()
	assert_bool(o._zone_color("player2") == OverlayScript.DEPLOYMENT_COLORS["player1"]).is_true()


func test_toggle_flip_returns_state() -> void:
	var o := _overlay()
	assert_bool(o.toggle_deployment_colors_flipped()).is_true()
	assert_bool(o.toggle_deployment_colors_flipped()).is_false()


# === Ruins are AREA terrain: see in/out, not through (maintainer correction to round-4) ===

func test_ruins_are_area_terrain_blockers() -> void:
	# GF/AoF v3.5.1 p.12: "Forests - Difficult + Cover + units can see into and out of forests, but not
	# through them." The maintainer applies the same AREA-terrain rule to Ruins (round-4 over-corrected them
	# to fully see-through): ruins DO block a sight line drawn all the way through them, so they are a
	# Height-5 area blocker like a forest. Buildings/Containers ("Impassable + Blocking") hard-block;
	# Dangerous is Open.
	var o := _overlay()
	assert_bool(o.terrain_blocks_los(OverlayScript.TerrainType.RUINS)).is_true()
	assert_bool(o.terrain_blocks_los(OverlayScript.TerrainType.CONTAINER)).is_true()
	assert_bool(o.terrain_blocks_los(OverlayScript.TerrainType.FOREST)).is_true()
	assert_bool(o.terrain_blocks_los(OverlayScript.TerrainType.DANGEROUS)).is_false()
	# An area-terrain ruin is a Height-5 sight blocker (matches the forest).
	assert_int(o.terrain_height_category(OverlayScript.TerrainType.RUINS)).is_equal(5)
	# Ruins + Forests are area terrain (see in/out); solid Containers are not.
	assert_bool(o.terrain_is_area(OverlayScript.TerrainType.RUINS)).is_true()
	assert_bool(o.terrain_is_area(OverlayScript.TerrainType.FOREST)).is_true()
	assert_bool(o.terrain_is_area(OverlayScript.TerrainType.CONTAINER)).is_false()
