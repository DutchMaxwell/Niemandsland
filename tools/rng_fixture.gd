extends SceneTree
## NML-1073 M2-0b: the Rust port needs to prove its RNG draws the SAME
## sequence Godot's RandomNumberGenerator (PCG32) draws for the SAME seed —
## without this fixture there is no ground truth to check a Rust reimplement
## against. For each seed: 1000 randf() draws, then 1000 randi_range(1, 6)
## draws (the two calls the search's dice/tie-break code actually uses),
## plus the PCG32 internal `state` after all 2000 draws (a second, cheaper
## check: replay N draws and compare state instead of every value).
##
## Run once: godot --headless --path . -s res://tools/rng_fixture.gd
## Writes core/nml-core/tests/fixtures/rng_godot.json.

const SEEDS := [1, 12345, 1099511627783]
const OUT_PATH := "res://core/nml-core/tests/fixtures/rng_godot.json"
const DRAWS := 1000


func _init() -> void:
	var out := {}
	for s in SEEDS:
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		var randfs: Array = []
		for i in range(DRAWS):
			randfs.append(rng.randf())
		var randis: Array = []
		for i in range(DRAWS):
			randis.append(rng.randi_range(1, 6))
		out[str(s)] = {"randf": randfs, "randi_range_1_6": randis, "state": rng.state}
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f == null:
		printerr("[RNG_FIXTURE] cannot open ", OUT_PATH)
		quit(1)
		return
	# full_precision=true (4th arg): a truncated double would make the fixture
	# lie about what Godot actually drew — same fix as a474064 (node recorder).
	f.store_string(JSON.stringify(out, "", true, true))
	f.close()
	print("[RNG_FIXTURE] wrote ", OUT_PATH)
	quit(0)
