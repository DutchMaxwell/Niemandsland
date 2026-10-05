extends GdUnitTestSuite
## Pins test/fixtures/shelf_sight_parity/cases.json to the table's sight truth: every stored verdict is what
## VolumetricLos.has_los answers today for that free shelf piece and those two models. The Rust core replays the same
## file (sight.rs, shelf_sight_parity), so a change on either side that moves a verdict fails one of the two suites.
## Regenerate with tools/shelf_sight_parity.gd.

const FIXTURE := "res://test/fixtures/shelf_sight_parity/cases.json"


func _cyl(d: Dictionary) -> Dictionary:
	return {"c": Vector2(d["c"][0], d["c"][1]), "r": float(d["r"]), "y0": float(d["y0"]), "y1": float(d["y1"])}


func test_every_stored_verdict_is_the_tables_verdict() -> void:
	var cases: Array = (JSON.parse_string(FileAccess.get_file_as_string(FIXTURE)) as Dictionary)["cases"]
	assert_int(cases.size()).is_equal(1000)
	var wrong: Array = []
	var seen := 0
	for i in cases.size():
		var c: Dictionary = cases[i]
		var vol := {"kind": "box", "c": Vector2(c["c"][0], c["c"][1]), "he": Vector2(c["he"][0], c["he"][1]),
			"yaw": float(c["yaw"]), "y0": 0.0, "y1": float(c["y1"]), "solid": bool(c["solid"])}
		var los := VolumetricLos.has_los(_cyl(c["from"]), _cyl(c["to"]), [vol])
		seen += 1 if los else 0
		if los != bool(c["los"]):
			wrong.append(i)
	assert_array(wrong).is_empty()
	assert_int(seen).is_between(100, 900)   # both verdicts well represented: the fixture can tell a box from no box
