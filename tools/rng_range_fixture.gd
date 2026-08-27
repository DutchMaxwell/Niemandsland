extends SceneTree
## NML-1073 M3-5: ground truth for `RandomNumberGenerator.randf_range`, the one
## draw `tools/core_selfplay.gd:_deploy_zone` makes and `tools/rng_fixture.gd`
## does not cover. Without it the Rust twin's mapping would be an inference off
## deployed positions instead of a measurement — and the mapping is NOT obvious:
## the engine's `randf_range` is `RandomPCG::random(float, float)`, i.e.
## `randf() * (to - from) + from` in SINGLE precision with a rounding step per
## operation. A f64 form and the three-draw `randd` form both reproduce the
## first digits and then miss by an ULP, which moves a deployed model.
##
## For each seed: DRAWS of `randf_range(-3, 3)` (the x jitter), then DRAWS of
## `randf_range(1, 9)` (the z spot), then the PCG32 `state` after them all —
## the same shape rng_fixture.gd writes, in a file of its own so that fixture's
## recorded stream stays byte-identical.
##
## Run once: godot --headless --path . -s res://tools/rng_range_fixture.gd
## Writes core/nml-core/tests/fixtures/rng_range_godot.json.

const SEEDS := [1, 27, 12345]
const OUT_PATH := "res://core/nml-core/tests/fixtures/rng_range_godot.json"
const DRAWS := 500


func _init() -> void:
	var out := {}
	for s in SEEDS:
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		var xs: Array = []
		for i in range(DRAWS):
			xs.append(rng.randf_range(-3.0, 3.0))
		var zs: Array = []
		for i in range(DRAWS):
			zs.append(rng.randf_range(1.0, 9.0))
		out[str(s)] = {"randf_range_m3_3": xs, "randf_range_1_9": zs, "state": rng.state}
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f == null:
		printerr("[RNG_RANGE_FIXTURE] cannot open ", OUT_PATH)
		quit(1)
		return
	# full_precision=true (4th arg): a truncated double would make the fixture
	# lie about what Godot actually drew — same rule as rng_fixture.gd.
	f.store_string(JSON.stringify(out, "", true, true))
	f.close()
	print("[RNG_RANGE_FIXTURE] wrote ", OUT_PATH)
	quit(0)
