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
	# to fully see-through): ruins DO block a sight line drawn all the way through them, so they are an
	# area blocker like a forest. Buildings/Containers ("Impassable + Blocking") hard-block;
	# Dangerous is Open.
	var o := _overlay()
	assert_bool(o.terrain_blocks_los(OverlayScript.TerrainType.RUINS)).is_true()
	assert_bool(o.terrain_blocks_los(OverlayScript.TerrainType.CONTAINER)).is_true()
	assert_bool(o.terrain_blocks_los(OverlayScript.TerrainType.FOREST)).is_true()
	assert_bool(o.terrain_blocks_los(OverlayScript.TerrainType.DANGEROUS)).is_false()
	# Ruins + Forests are area terrain (see in/out); solid Containers are not.
	assert_bool(o.terrain_is_area(OverlayScript.TerrainType.RUINS)).is_true()
	assert_bool(o.terrain_is_area(OverlayScript.TerrainType.FOREST)).is_true()
	assert_bool(o.terrain_is_area(OverlayScript.TerrainType.CONTAINER)).is_false()


# === W5.22: real heights, not Asgard categories (the height ladder is retired) ===

## The overlay used to answer "how tall is this?" with the category 5 for every blocker alike. It now
## answers in REAL INCHES, and those numbers are declared ONCE — in the pure module TerrainRules, which
## the overlay's own prop constants alias. That single source is what stops the mesh a player looks at
## from drifting away from the volume the rules measure.
func test_terrain_heights_are_real_inches_from_the_one_source() -> void:
	var o := _overlay()
	var T := OverlayScript.TerrainType
	assert_float(o.terrain_volume_height_inches(T.RUINS)).is_equal_approx(TerrainRules.RUIN_ZONE_HEIGHT_INCHES, 1e-9)
	assert_float(o.terrain_volume_height_inches(T.FOREST)).is_equal_approx(TerrainRules.FOREST_HEIGHT_INCHES, 1e-9)
	assert_float(o.terrain_volume_height_inches(T.CONTAINER)).is_equal_approx(TerrainRules.CONTAINER_HEIGHT_INCHES, 1e-9)
	assert_float(o.terrain_volume_height_inches(T.DANGEROUS)).is_equal_approx(0.0, 1e-9)
	# The prop constants the meshes are built from are the very same numbers.
	assert_float(OverlayScript.CONTAINER_HEIGHT_INCHES).is_equal_approx(TerrainRules.CONTAINER_HEIGHT_INCHES, 1e-9)
	assert_float(OverlayScript.TREE_HEIGHT_INCHES).is_equal_approx(TerrainRules.FOREST_HEIGHT_INCHES, 1e-9)
	assert_float(OverlayScript.RUIN_ZONE_HEIGHT_INCHES).is_equal_approx(TerrainRules.RUIN_ZONE_HEIGHT_INCHES, 1e-9)


## Ported from the retired terrain_los_test: the battlefield labels a player reads off the table. They
## used to say "Height 5" for ruins, forest and container alike — a category that told nobody what a
## model can see over. Each now names the piece's real height in the map editor's wording (`6" tall`).
func test_effect_labels_name_real_heights_not_categories() -> void:
	var o := _overlay()
	var T := OverlayScript.TerrainType
	var ruins: String = o._terrain_effect_label(T.RUINS)
	assert_str(ruins).contains("6\" tall")
	assert_str(ruins).contains("Cover")
	assert_str(ruins).contains("Blocks LoS")
	assert_str(ruins).not_contains("Height 5")
	var forest: String = o._terrain_effect_label(T.FOREST)
	assert_str(forest).contains("3.4\" tall")
	assert_str(forest).contains("Difficult")
	assert_str(forest).contains("Cover")
	assert_str(forest).not_contains("Height 5")
	var container: String = o._terrain_effect_label(T.CONTAINER)
	assert_str(container).contains("2.5\" tall")
	assert_str(container).contains("Impassable")
	assert_str(container).not_contains("Height 5")
	# Dangerous is Open ground — it has no height to name, and NONE has no label at all.
	assert_str(o._terrain_effect_label(T.DANGEROUS)).contains("Dangerous")
	assert_str(o._terrain_effect_label(T.NONE)).is_empty()
