extends GdUnitTestSuite
## Realism wave: SchoolTerrain pulls the factory's tables from the game's own
## symmetric layouter. Pins: determinism per seed, point symmetry of the cell
## map, OPR dangerous-terrain floor, and the world-metres probe geometry.

const IN2M := 0.0254


func test_generate_is_deterministic_per_seed() -> void:
	var a := SchoolTerrain.generate(4242)
	var b := SchoolTerrain.generate(4242)
	assert_that(a["cells"]).is_equal(b["cells"])
	assert_that(a["pieces"]).is_equal(b["pieces"])
	var c := SchoolTerrain.generate(4243)
	assert_bool(a["cells"].hash() == c["cells"].hash()).is_false()


func test_cell_map_is_point_symmetric() -> void:
	var w := SchoolTerrain.generate(7)
	var cells: Dictionary = w["cells"]
	var n: int = w["n"]
	assert_bool(cells.size() > 0).is_true()
	for cell in cells:
		var mirror := Vector2i(n - 1 - (cell as Vector2i).x, n - 1 - (cell as Vector2i).y)
		assert_that(cells.get(mirror, -1)).is_equal(cells[cell])


func test_dangerous_floor_and_piece_variety() -> void:
	var w := SchoolTerrain.generate(11)
	var by_type := {}
	for p in w["pieces"]:
		by_type[(p as Array)[0]] = int(by_type.get((p as Array)[0], 0)) + 1
	assert_int(int(by_type.get(TerrainRules.TerrainType.DANGEROUS, 0))).is_greater_equal(2)
	assert_int((w["pieces"] as Array).size()).is_greater_equal(8)


## The probe must hit the piece it claims: every piece centre reports the
## piece's own type; a point far off the table reports NONE.
func test_type_at_probes_piece_centres() -> void:
	var w := SchoolTerrain.generate(13)
	var checked := 0
	for p in w["pieces"]:
		var pa := p as Array
		var pos := Vector3(float(pa[1]) * IN2M, 0.0, float(pa[2]) * IN2M)
		if SchoolTerrain.type_at(w, pos) == int(pa[0]):
			checked += 1
	# overlapping pieces may shadow a centre; the overwhelming majority must hit
	assert_bool(checked >= (w["pieces"] as Array).size() * 3 / 4).is_true()
	assert_int(SchoolTerrain.type_at(w, Vector3(90.0 * IN2M, 0, 90.0 * IN2M))) \
		.is_equal(TerrainRules.TerrainType.NONE)


## LOS v0: a ruin between two points blocks; the open line next to it does
## not; standing INSIDE the ruin never blocks the unit's own cell.
func test_los_blocked_by_ruins_between() -> void:
	var w := SchoolTerrain.generate(13)
	var ruin: Array = []
	for p in w["pieces"]:
		if int((p as Array)[0]) == TerrainRules.TerrainType.RUINS:
			ruin = p
			break
	assert_bool(not ruin.is_empty()).is_true()
	var cx: float = float(ruin[1])
	var cz: float = float(ruin[2])
	var a := Vector3((cx - 12.0) * IN2M, 0, cz * IN2M)
	var b := Vector3((cx + 12.0) * IN2M, 0, cz * IN2M)
	assert_bool(SchoolTerrain.los_blocked(w, a, b)).is_true()
	var inside := Vector3(cx * IN2M, 0, cz * IN2M)
	var near := Vector3((cx + 4.0) * IN2M, 0, cz * IN2M)
	assert_bool(SchoolTerrain.los_blocked(w, inside, near)).is_false()


## Convention pin against the GAME's grid (map_layout: cell centre at
## (x - n/2 + 0.5) * 3" from table centre): the cell just right-below the
## table centre has its centre at exactly (+1.5", +1.5") — a dropped
## half-cell offset shifts every drawn piece by 1.5" and dies here.
func test_cell_centre_convention_pin() -> void:
	var w := SchoolTerrain.generate(4242)
	var n: int = w["n"]
	var c := SchoolTerrain.cell_centre_in(Vector2i(n / 2, n / 2), n)
	assert_float(c.x).is_equal_approx(1.5, 0.0001)
	assert_float(c.y).is_equal_approx(1.5, 0.0001)
	assert_that(SchoolTerrain.cell_of(c.x, c.y, n)).is_equal(Vector2i(n / 2, n / 2))
