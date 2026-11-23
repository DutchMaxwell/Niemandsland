extends GdUnitTestSuite
## A byte-exact snapshot of the dressing output on the stub kit for seeds 41 and 25: the house placements (module and
## transform), the honesty-rule report, the merged mesh and the shadow proxy. Pure refactors of the dressing scripts must
## keep these hashes; a change of the look re-pins them on purpose.

const SEEDS: Array[int] = [41, 25]
## SHA-256 of the snapshot bytes per seed; printed by the test when they differ.
const PINNED := {
	41: "60:adc89843799bb243add88f7558501fe12f939a57d1b7f8aab3a3dd5602f0ae30",
	25: "52:afc07a4ad66f6cf97d75ba133ee98a7c9ed265fe9467d2ffb06309f0b76f360b",
}


func _snapshot(seed: int) -> String:
	var layout: Dictionary = (ClassDB.instantiate("NmlCore") as Object).boardgen_layout_themed(seed, "ruintown")
	var town_kit := BoardgenKit.new("ruintown")
	add_child(town_kit)
	auto_free(town_kit)
	var kit := BoardgenDressKit.new(town_kit, true)
	var ctx := {"kit": kit, "story": BoardgenDressStory.of(layout), "meta": kit.meta, "seed": seed}
	var placements: Array[Dictionary] = BoardgenDressHouses.plan(layout, ctx)
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	for p: Dictionary in placements:
		hashing.update(var_to_bytes([p["module"], p["xf"], p["cls"]]))
	hashing.update(var_to_bytes(BoardgenDressRules.violations(layout, placements, kit.meta)))
	for mesh: ArrayMesh in [BoardgenDressMesh.merge(placements, kit), BoardgenDressMesh.shadow(placements, kit)]:
		for s in mesh.get_surface_count():
			hashing.update(var_to_bytes([mesh.surface_get_name(s), mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX], mesh.surface_get_arrays(s)[Mesh.ARRAY_NORMAL]]))
	return "%d:%s" % [placements.size(), hashing.finish().hex_encode()]


func test_the_dressing_output_matches_its_snapshot() -> void:
	for seed in SEEDS:
		var got := _snapshot(seed)
		if got != PINNED[seed]:
			print("BoardgenDress snapshot seed %d: %s" % [seed, got])
		assert_str(got).override_failure_message("seed %d snapshot %s" % [seed, got]).is_equal(PINNED[seed])
