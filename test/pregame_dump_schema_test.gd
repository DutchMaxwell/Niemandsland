extends GdUnitTestSuite
## NML-1152 step 1 — the pregame dump SCHEMA: a dumped fixture JSON (tools/pregame_dump.gd via
## `dump=<dir>`) must carry every key the deployment gate (design §4.2) reads. Green: the loaded
## sample passes the key walk. Red proof: the same walk on a copy with ONE key removed reports the
## gap. When a real fixture exists on this box (NML_PREGAME_DUMP_FILE, or the first
## pregame_*.json under NML_PREGAME_OUT), it is walked too — CI, without the fixture, skips that.

const REQUIRED_TOP := ["schema", "tool", "seed", "dice_seed", "layout_seed", "git_head",
	"armies", "symmetric", "roll_off_attempts", "opener", "deploy_order", "sides"]
const REQUIRED_SIDE := ["seed_value", "probe_hits", "fills", "reserved", "placement_order", "units"]
const REQUIRED_UNIT := ["key", "name", "section", "scout", "ambush", "base_r_m", "footprint",
	"base_is_oval", "base_width_mm", "base_depth_mm", "base_size_round",
	"spot", "vanguard_pushed", "facing_rad", "models"]

var _tmp := ""


func before_test() -> void:
	_tmp = create_temp_dir("pregame_schema")


## One minimal-but-complete dump at the schema's leaf shapes (side 2 = the design's empty-side case).
## `legacy` downgrades the sample to the v1 name-keyed format (unit rows without `name`, sides
## without `placement_order`) — the red proof that old dumps no longer pass the walk.
func _write_sample(path: String, drop_key := "", legacy := false) -> void:
	DirAccess.make_dir_recursive_absolute(_tmp)
	var dump := {"schema": 1, "tool": "pregame_dump", "seed": 7, "dice_seed": 7, "layout_seed": 500007,
		"git_head": "deadbeef", "armies": {"p1": "a.json", "p2": "b.json"}, "symmetric": true,
		"roll_off_attempts": [{"p1": 4, "p2": 4}, {"p1": 6, "p2": 2}], "opener": 1,
		"deploy_order": [1, 2],
		"sides": {"1": {"seed_value": 8, "probe_hits": 0, "fills": [], "reserved": [],
			"placement_order": ["0"],
			"units": [{"key": "0", "name": "Rangers", "section": 2, "scout": false, "ambush": false,
				"base_r_m": 0.016, "footprint": [[0.0, 0.0]], "base_is_oval": false,
				"base_width_mm": 32, "base_depth_mm": 32, "base_size_round": 32,
				"spot": [0.31, -0.52],
				"vanguard_pushed": false, "facing_rad": 0.0, "models": [[0.31, -0.52]]}]},
			"2": {"seed_value": 9, "probe_hits": 0, "fills": [], "reserved": ["X"],
				"placement_order": [], "units": []}}}
	if legacy:
		for side in (dump["sides"] as Dictionary).values():
			(side as Dictionary).erase("placement_order")
			for u in (side as Dictionary).get("units", []):
				(u as Dictionary).erase("name")
	if drop_key != "":
		dump.erase(drop_key)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(dump))
	f.close()


## The walk under test — mirrors what the gate's loader must find. Returns the missing-key paths.
func _schema_gaps(path: String) -> Array:
	var gaps: Array = []
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return ["<file unreadable>"]
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		return ["<unparseable>"]
	var d: Dictionary = parsed
	for k in REQUIRED_TOP:
		if not d.has(k):
			gaps.append(k)
	for side in (d.get("sides", {}) as Dictionary).values():
		for k in REQUIRED_SIDE:
			if not (side as Dictionary).has(k):
				gaps.append("sides.%s" % k)
		for u in (side as Dictionary).get("units", []):
			for k in REQUIRED_UNIT:
				if not (u as Dictionary).has(k):
					gaps.append("units.%s" % k)
	return gaps


func test_dumped_fixture_carries_every_schema_key() -> void:
	_write_sample(_tmp + "/sample.json")
	assert_array(_schema_gaps(_tmp + "/sample.json")).is_empty()


func test_removed_key_is_reported_the_red_proof() -> void:
	_write_sample(_tmp + "/sample_missing.json", "opener")
	assert_array(_schema_gaps(_tmp + "/sample_missing.json")).contains("opener")


## NML-1152 step 3b: a v1 name-keyed dump (unit rows without `name`, sides without
## `placement_order`) must FAIL the walk — the fixture format moved to unit ids.
func test_legacy_name_keyed_dump_fails_the_schema() -> void:
	_write_sample(_tmp + "/sample_legacy.json", "", true)
	var gaps := _schema_gaps(_tmp + "/sample_legacy.json")
	assert_array(gaps).contains("sides.placement_order")
	assert_array(gaps).contains("units.name")


func test_real_fixture_dump_if_present() -> void:
	var path := OS.get_environment("NML_PREGAME_DUMP_FILE")
	if path.is_empty():
		var dir := OS.get_environment("NML_PREGAME_OUT")
		if dir.is_empty():
			return   # no fixture on this box (CI) — the real-dump walk is a local extra
		for f in DirAccess.get_files_at(dir):
			if str(f).begins_with("pregame_") and str(f).ends_with(".json"):
				path = dir.path_join(str(f))
				break
	if path.is_empty():
		return
	assert_array(_schema_gaps(path)).is_empty()
