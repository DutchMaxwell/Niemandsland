extends GdUnitTestSuite
## The readability gate stands its pawns only where the rules let a model stand (gate change 22.11.): tools/boardgen/bg_capture_town.gd legal_spot must refuse
## every spot whose 1 in base touches an intact house (Roofed = the core's solid cell, boardgen/plain.rs + terrain.rs is_forbidden_rest) or straddles two levels.

const CAPTURE := "res://tools/boardgen/bg_capture_town.gd"


func _cell(layout: Dictionary, p: Vector2) -> Dictionary:
	var nx: int = layout["nx"]
	var cell := float(layout["cell_in"])
	var cx := floori(p.x / cell + nx * 0.5)
	var cz := floori(p.y / cell + int(layout["nz"]) * 0.5)
	return layout["cells"][cz * nx + cx]


func test_every_legal_spot_has_its_whole_base_on_one_level_and_never_in_a_house() -> void:
	var core: Object = ClassDB.instantiate("NmlCore")
	var capture: GDScript = load(CAPTURE)
	var tiers := 0
	var refused_houses := 0
	for board_seed in [25, 41, 47, 53]:
		var layout: Dictionary = core.boardgen_layout_themed(board_seed, "ruintown")
		var half := float(layout["nx"]) * float(layout["cell_in"]) * 0.5 - 0.6
		for zi in range(0, 96):
			for xi in range(0, 96):
				var p := Vector2(-half + xi * half / 48.0, -half + zi * half / 48.0)
				var top: float = capture.legal_spot(layout, p)
				if _cell(layout, p)["lot_kind"] == "Roofed":
					refused_houses += 1
					assert_float(top).override_failure_message("seed %d: a pawn stands in an intact house at %s" % [board_seed, p]).is_less(0.0)
				if top < 0.0:
					continue
				var level: int = _cell(layout, p)["level"]
				tiers += 1 if level > 0 else 0
				for k in 16:   # the base rim at 16 points, independent of the exact circle-versus-cell test the tool does
					var c := _cell(layout, p + Vector2.from_angle(k * PI / 8.0) * 0.5)
					assert_str(c["lot_kind"]).override_failure_message("seed %d: base at %s touches a house" % [board_seed, p]).is_not_equal("Roofed")
					assert_int(c["level"]).override_failure_message("seed %d: base at %s straddles a tier edge" % [board_seed, p]).is_equal(level)
				assert_float(top).is_equal(float(layout["level_in"][level]))
	assert_int(refused_houses).override_failure_message("the boards have no intact house: the test proves nothing").is_greater(0)
	assert_int(tiers).override_failure_message("no spot on a tier: elevated pawns would never be judged").is_greater(0)
