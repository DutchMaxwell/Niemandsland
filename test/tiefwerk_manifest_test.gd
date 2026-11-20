extends GdUnitTestSuite
## The Tiefwerk asset manifest (assets/tiefwerk_manifest.json): every file entry is content-addressed, every PBR set has its three
## maps, every decal-atlas cell lies inside the atlas and no two cells overlap. Pure data; the files themselves live on R2.

const MANIFEST_PATH := "res://assets/tiefwerk_manifest.json"
const MAPS: Array[String] = ["albedo", "normal", "orm"]
const REQUIRED_CELLS: Array[String] = ["num_0", "num_3", "num_6", "num_9", "grime_strip", "scorch", "leak_rust", "leak_oil", "bay_box"]


## Every problem found in a manifest dictionary (empty = sound).
static func problems(m: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var sets: Dictionary = m.get("sets", {})
	if sets.size() < 4:
		out.append("fewer than four PBR sets")
	for set_name: String in sets:
		for map: String in MAPS:
			out.append_array(_entry_problems("%s.%s" % [set_name, map], sets[set_name].get(map, {}), "ctex"))
		if str(sets[set_name].get("license", "")).is_empty() or str(sets[set_name].get("source", "")).is_empty():
			out.append("%s: licence or source missing" % set_name)
	var d: Dictionary = m.get("decals", {})
	for map: String in MAPS:
		out.append_array(_entry_problems("decals.%s" % map, d.get(map, {}), "webp"))
	var atlas: int = int(d.get("atlas_px", 0))
	var cells: Dictionary = d.get("cells", {})
	for want in REQUIRED_CELLS:
		if not cells.has(want):
			out.append("decal cell %s missing" % want)
	var rects: Dictionary = {}
	for c: String in cells:
		var r := Rect2i(int(cells[c]["x"]), int(cells[c]["y"]), int(cells[c]["w"]), int(cells[c]["h"]))
		if r.position.x < 0 or r.position.y < 0 or r.end.x > atlas or r.end.y > atlas or r.size.x < 8 or r.size.y < 8:
			out.append("decal cell %s outside the atlas" % c)
		for other: String in rects:
			if rects[other].intersects(r):
				out.append("decal cells %s and %s overlap" % [other, c])
		rects[c] = r
	return out


static func _entry_problems(label: String, e: Dictionary, ext: String) -> Array[String]:
	var sha := str(e.get("sha256", ""))
	var re := RegEx.create_from_string("^[0-9a-f]{64}$")
	if re.search(sha) == null:
		return ["%s: sha256 is not 64 hex digits" % label]
	if str(e.get("url", "")) != "%s.%s" % [sha, ext] or int(e.get("size", 0)) <= 0:
		return ["%s: url is not <sha256>.%s or size is 0" % [label, ext]]
	return []


func _real() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))


func test_shipped_manifest_is_sound() -> void:
	assert_array(problems(_real())).is_empty()


func test_validator_sees_an_overlapping_cell() -> void:
	var m := _real()
	var cells: Dictionary = m["decals"]["cells"]
	cells["num_1"]["x"] = cells["num_0"]["x"]
	cells["num_1"]["y"] = cells["num_0"]["y"]
	assert_bool(problems(m).any(func(p: String) -> bool: return p.contains("overlap"))).is_true()


func test_validator_sees_a_broken_hash_and_a_missing_map() -> void:
	var m := _real()
	m["sets"]["concrete"]["albedo"]["sha256"] = "abc"
	m["sets"]["roof_slab"].erase("orm")
	var found := problems(m)
	assert_bool(found.any(func(p: String) -> bool: return p.begins_with("concrete.albedo"))).is_true()
	assert_bool(found.any(func(p: String) -> bool: return p.begins_with("roof_slab.orm"))).is_true()


func test_validator_sees_a_cell_outside_the_atlas() -> void:
	var m := _real()
	m["decals"]["cells"]["scorch"]["y"] = int(m["decals"]["atlas_px"]) - 10
	assert_bool(problems(m).any(func(p: String) -> bool: return p.contains("outside"))).is_true()
