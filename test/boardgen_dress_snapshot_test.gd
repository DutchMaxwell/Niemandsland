extends GdUnitTestSuite
## A byte-exact snapshot of the dressing output on the stub kit for seeds 41 and 25: the house
## placements (module and transform), the honesty-rule report, the merged mesh and the shadow proxy.
## Pure refactors of the dressing scripts must keep these hashes; a change of the look re-pins them
## on purpose. Re-pinned 25.11. by the layout change D-R2 = C (more intact houses:
## 114 -> 183 and 97 -> 154 placements). Re-pinned 26.11. by D-R16 = b (fewer filler slabs: 180 -> 183 and 155 -> 157 placements).

const SEEDS: Array[int] = [41, 25]
## SHA-256 of the snapshot bytes per seed; printed by the test when they differ.
const PINNED := {
	41: "183:df16ef795f9fc787ab2b14c8947eb3372b327b2f838a4894dd93f8cb2b227cfc",
	25: "157:abddcace3698a3ae197d58e8d702485e0cb481506989827087dc910bab144abb",
}


func _snapshot(seed: int) -> String:
	var layout: Dictionary = (ClassDB.instantiate("NmlCore") as Object).boardgen_layout_themed(
		seed, "ruintown"
	)
	var town_kit := BoardgenKit.new("ruintown")
	add_child(town_kit)
	auto_free(town_kit)
	var kit := BoardgenDressKit.new(town_kit, true)
	var story := BoardgenDressStory.of(layout)
	var context := DressContext.new(layout, kit, story, seed)
	var placements: Array[DressPlacement] = BoardgenDressHouses.new().plan(context)
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	for p: DressPlacement in placements:
		hashing.update(var_to_bytes([p.module, p.transform, p.cls]))
	hashing.update(var_to_bytes(BoardgenDressRules.violations(context, placements)))
	for mesh: ArrayMesh in [
		BoardgenDressMesh.merge(placements, kit), BoardgenDressMesh.shadow(placements, kit)
	]:
		for s in mesh.get_surface_count():
			hashing.update(
				var_to_bytes(
					[
						mesh.surface_get_name(s),
						mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX],
						mesh.surface_get_arrays(s)[Mesh.ARRAY_NORMAL]
					]
				)
			)
	return "%d:%s" % [placements.size(), hashing.finish().hex_encode()]


func test_the_dressing_output_matches_its_snapshot() -> void:
	for seed in SEEDS:
		var got := _snapshot(seed)
		if got != PINNED[seed]:
			print("BoardgenDress snapshot seed %d: %s" % [seed, got])
		assert_str(got).override_failure_message("seed %d snapshot %s" % [seed, got]).is_equal(
			PINNED[seed]
		)
