extends GdUnitTestSuite
## BG-01 (0.3.15, rules 3.6): the terrain labels a player reads must say what the engine
## already plays. 3.6 renames "Blocking" to "Sight Blocking" and names the forest rule
## "Dense" (see into and out of, not through). The engine treats forest AND ruins that way
## and the container as impassable + sight blocking, so both label surfaces say so now.
## Ruins flip to "Unstable" only when the engine changes (row BG-03b) — not here.

const OverlayScript := preload("res://scripts/terrain_overlay.gd")
const MapLayoutScript := preload("res://scripts/map_layout.gd")


func _overlay() -> Node3D:
	return auto_free(OverlayScript.new())


func _layout() -> Control:
	# No add_child: avoids the @onready crash; the constant needs no tree.
	return auto_free(MapLayoutScript.new())


func _description(terrain_type: int) -> String:
	return str(MapLayoutScript.TERRAIN_DESCRIPTIONS.get(terrain_type, ""))


# ===== Battlefield effect labels (_terrain_effect_label) =====

func test_forest_label_says_dense() -> void:
	var o := _overlay()
	assert_str(o._terrain_effect_label(OverlayScript.TerrainType.FOREST)).contains("Dense")


func test_ruins_label_says_dense() -> void:
	var o := _overlay()
	assert_str(o._terrain_effect_label(OverlayScript.TerrainType.RUINS)).contains("Dense")


func test_container_label_says_sight_blocking() -> void:
	var o := _overlay()
	assert_str(o._terrain_effect_label(OverlayScript.TerrainType.CONTAINER)).contains("Sight Blocking")


# ===== Map editor tooltips (TERRAIN_DESCRIPTIONS) =====

func test_forest_description_says_dense() -> void:
	assert_str(_description(MapLayoutScript.TerrainType.FOREST)).contains("Dense")


func test_ruins_description_says_dense() -> void:
	assert_str(_description(MapLayoutScript.TerrainType.RUINS)).contains("Dense")


func test_container_description_says_sight_blocking() -> void:
	assert_str(_description(MapLayoutScript.TerrainType.CONTAINER)).contains("Sight Blocking")
