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
