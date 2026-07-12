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


# === Ruins are Cover + SEE-THROUGH, not LOS blockers (finding 5) ===

func test_ruins_do_not_block_line_of_sight() -> void:
	# GF/AoF v3.5.1 terrain guidelines: "Ruins - Cover + Dangerous on rush/charge" — their low walls confer
	# cover yet are see-through (field-test finding 5). Buildings/Containers ("Impassable + Blocking") and
	# Forests ("see into/out, not through") still block sight through them; Dangerous is Open.
	var o := _overlay()
	assert_bool(o.terrain_blocks_los(OverlayScript.TerrainType.RUINS)).is_false()
	assert_bool(o.terrain_blocks_los(OverlayScript.TerrainType.CONTAINER)).is_true()
	assert_bool(o.terrain_blocks_los(OverlayScript.TerrainType.FOREST)).is_true()
	assert_bool(o.terrain_blocks_los(OverlayScript.TerrainType.DANGEROUS)).is_false()
	# A see-through ruin is Ground (Height 0), not a Height-5 sight blocker.
	assert_int(o.terrain_height_category(OverlayScript.TerrainType.RUINS)).is_equal(0)
