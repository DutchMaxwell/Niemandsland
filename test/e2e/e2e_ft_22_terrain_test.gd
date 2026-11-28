extends GdUnitTestSuite
## Feature test FT-22: Dangerous and Difficult terrain on a hot-seat Firefight (gff) table. FF36 p.12 l.1002-1004 (a unit
## that moves through Dangerous terrain takes a test: as many dice as wounds needed to destroy it, each 1 a wound),
## l.1094-1096 (a move in or through Difficult terrain is capped at 6 in).
## Scene: a single Tough(3) model; one overlay cell painted Dangerous on its path; a row of Forest (Difficult) cells on
## another unit's path.
## #3858 (fixed): the player's log names the Dangerous test before its dice line.
## Real: the main scene, the terrain overlay, the card's Activate / End, the real drag and the core's move check.

const INCH := 0.0254

var _t: SkirmishTable


func before_test() -> void:
	_t = await SkirmishTable.boot(self, "H")
	_t.unit("gff", 2, "Far", 1, 1, 0.0, 30.0)
	_t.unit("gff", 2, "Far2", 1, 1, 10.0, 30.0)


func after_test() -> void:
	if _t != null:
		_t.teardown()
	_t = null


func _paint(x_in: float, z_in: float, kind: int) -> void:
	var o: Node3D = _t.main.terrain_overlay
	o.grid_cells[o.world_to_cell(Vector3(x_in * INCH, 0, z_in * INCH))] = kind


## A 6 in Advance of the Tough(3) model across one Dangerous cell, ended.
func _through_dangerous() -> GameUnit:
	_paint(-7.0, 0.0, TerrainRules.TerrainType.DANGEROUS)
	var u := _t.unit("gff", 1, "Walker", 1, 3, -11.0, 0.0)
	assert_bool(await _t.start(u)).is_true()
	await _t.walk(u, 6.0, 0.0, CoreActivation.CAP_ADVANCE)
	await _t.end(u)
	return u


func test_a_move_through_dangerous_terrain_rolls_one_die_per_wound_left(timeout := 120000) -> void:
	var u := await _through_dangerous()
	var dice: Array = _t.lines.filter(func(l: String) -> bool: return l.begins_with("P1: ") and l.ends_with("(each 1)"))
	assert_int(dice.size()).override_failure_message("one Dangerous dice line: %s" % [_t.lines]).is_equal(1)
	var faces: PackedStringArray = str(dice[0]).trim_prefix("P1: ").split(" → ")[0].split(" ")
	assert_int(faces.size()).override_failure_message("3 dice = 3 wounds to destroy: %s" % [dice]).is_equal(3)
	var ones := Array(faces).filter(func(f: String) -> bool: return f == "1").size()
	var m := u.models[0] as ModelInstance
	assert_int(m.wounds_max - m.wounds_current).override_failure_message("each 1 a wound: %s" % [_t.lines]).is_equal(ones)


## #3858: the player's move names its Dangerous test (the table writes the line the core does not).
func test_the_dangerous_test_is_named_in_the_log(timeout := 120000) -> void:
	await _through_dangerous()
	assert_bool(_t.lines.any(func(l: String) -> bool: return l.find("Dangerous terrain") != -1)) \
		.override_failure_message("a line names the test: %s" % [_t.lines]).is_true()


func test_a_rush_through_difficult_terrain_is_capped_at_6_in(timeout := 120000) -> void:
	for x in [-6.0, -3.0, 0.0]:
		_paint(x, 0.0, TerrainRules.TerrainType.FOREST)
	var u := _t.unit("gff", 1, "Walker", 1, 3, -11.0, 0.0)
	var from: Vector3 = (u.models[0] as ModelInstance).node.global_position
	assert_bool(await _t.start(u)).is_true()
	await _t.walk(u, 8.0, 0.0, CoreActivation.CAP_RUSH)
	assert_float(((u.models[0] as ModelInstance).node.global_position - from).length() / INCH) \
		.override_failure_message("the 8 in Rush snaps back: %s" % [_t.lines]).is_equal_approx(0.0, 0.05)
	assert_int(_t.count("Walker: a model moved 8.0\" - the Rush allowance is 6.0\" in Difficult terrain.")) \
		.override_failure_message("one line names the 6 in cap: %s" % [_t.lines]).is_equal(1)
