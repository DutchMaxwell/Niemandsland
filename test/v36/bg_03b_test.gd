extends GdUnitTestSuite
## Rules 3.6 row BG-03b: Unstable ruins on the table. A model whose OWN move is longer than 6 inches
## and whose route goes into or through a ruin takes the same unit-level Dangerous test that row
## UX-20/UX-21 already wires; a 6 inch advance across the same cell never does. Below EPOCH_73_V36
## nothing changes. Every case pins one epoch. The labels follow the current rules, no epoch.

const IN2M := 0.0254
const OverlayScript := preload("res://scripts/terrain_overlay.gd")

var _solo: SoloController
var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	_solo = auto_free(SoloController.new())
	add_child(_solo)


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests - restore


## A ruin band two inches wide around x = 0, open ground beyond it.
func _set_ruin_band() -> void:
	_solo.terrain_type_at = func(p: Vector3) -> int:
		return TerrainRules.TerrainType.RUINS if absf(p.x) <= 1.0 * IN2M else TerrainRules.TerrainType.NONE


## A dangerous band two inches wide around x = 0 (the control).
func _set_dangerous_band() -> void:
	_solo.terrain_type_at = func(p: Vector3) -> int:
		return TerrainRules.TerrainType.DANGEROUS if absf(p.x) <= 1.0 * IN2M else TerrainRules.TerrainType.NONE


## A straight trail of `length_in` inches along x, centred on the band.
func _through(length_in: float) -> Array:
	var half := length_in * 0.5 * IN2M
	return [Vector3(-half, 0.0, 0.0), Vector3(half, 0.0, 0.0)]


func _flag(trail: Array, epoch: int) -> bool:
	AiActRecorder.rules_epoch = epoch
	return bool((_solo._dangerous_trail_flags([trail]) as Array)[0])


func test_an_eight_inch_rush_through_a_ruin_is_not_dangerous_at_epoch_72() -> void:
	_set_ruin_band()
	assert_bool(_flag(_through(8.0), AiActRecorder.EPOCH_72_PLAYTEST_RULES)).is_false()


func test_an_eight_inch_rush_through_a_ruin_is_dangerous_at_epoch_73() -> void:
	_set_ruin_band()
	assert_bool(_flag(_through(8.0), AiActRecorder.EPOCH_73_V36)) \
		.override_failure_message("a move over 6 inches into or through a ruin takes the Dangerous test") \
		.is_true()


func test_a_six_inch_advance_through_a_ruin_is_not_dangerous_at_epoch_72() -> void:
	_set_ruin_band()
	assert_bool(_flag(_through(6.0), AiActRecorder.EPOCH_72_PLAYTEST_RULES)).is_false()


func test_a_six_inch_advance_through_a_ruin_is_not_dangerous_at_epoch_73() -> void:
	_set_ruin_band()
	assert_bool(_flag(_through(6.0), AiActRecorder.EPOCH_73_V36)).is_false()


func test_a_dangerous_cell_flags_a_six_inch_advance_at_epoch_72() -> void:
	_set_dangerous_band()
	assert_bool(_flag(_through(6.0), AiActRecorder.EPOCH_72_PLAYTEST_RULES)).is_true()


func test_a_dangerous_cell_flags_a_six_inch_advance_at_epoch_73() -> void:
	_set_dangerous_band()
	assert_bool(_flag(_through(6.0), AiActRecorder.EPOCH_73_V36)).is_true()


# ===== Labels follow the current rules (3.6), no epoch =====

func _overlay() -> Node3D:
	return auto_free(OverlayScript.new())


func test_ruins_label_says_unstable_not_dense() -> void:
	var label: String = _overlay()._terrain_effect_label(OverlayScript.TerrainType.RUINS)
	assert_str(label).contains("Unstable")
	assert_str(label).not_contains("Dense")


func test_forest_label_still_says_dense() -> void:
	assert_str(_overlay()._terrain_effect_label(OverlayScript.TerrainType.FOREST)).contains("Dense")
