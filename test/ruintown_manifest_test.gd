extends GdUnitTestSuite
## The ruin-town delivery manifest (assets/ruintown_manifest.json): without it every player gets the kit-less town. Every module the
## dresser's planners ask for and every non-stub module of assets/ruintown_dress.json is listed, every texture set the town samples is
## listed, and every file entry is content-addressed. Pure data; the files themselves live on R2 (terrain-source/ruintown/).

const MANIFEST_PATH := "res://assets/ruintown_manifest.json"
const DRESS_PATH := "res://assets/ruintown_dress.json"


static func _json(path: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	return data if typeof(data) == TYPE_DICTIONARY else {}


## Every module name the dresser can ask the kit for: the MODULES of each planner, plus every non-stub module of the dress table.
static func wanted_modules() -> Array[String]:
	var out: Array[String] = []
	for name: String in BoardgenDress.PLANNERS:
		var path := "res://scripts/boardgen_dress_%s.gd" % name
		if ResourceLoader.exists(path):
			for m: String in (load(path) as Script).get_script_constant_map().get("MODULES", []):
				if not out.has(m):
					out.append(m)
	var dress: Dictionary = _json(DRESS_PATH).get("modules", {})
	for m: String in dress:
		if not dress[m].get("stub", false) and not out.has(m):
			out.append(m)
	return out


## Every problem found in a manifest dictionary (empty = sound).
static func problems(m: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if m.is_empty():
		return ["manifest missing or not a JSON object"]
	if not str(m.get("base_url", "")).begins_with("{cdn}/"):
		out.append("base_url does not start with {cdn}/")
	var models: Dictionary = m.get("models", {})
	for want in wanted_modules():
		if not models.has(want):
			out.append("module %s missing" % want)
	for name: String in models:
		out.append_array(_entry_problems("models.%s" % name, models[name], "glb"))
	var sets: Dictionary = m.get("sets", {})
	for pair: Array in BoardgenTheme.TOWN_SETS:
		if not sets.has(pair[0]):
			out.append("set %s missing" % pair[0])
	for soil: String in BoardgenTheme.TOWN_SOIL:   # (LOOK5 S2) the yards' four soil sets reach the players too
		if not sets.has(soil) or not (sets[soil] as Dictionary).has("orm"):
			out.append("soil set %s missing" % soil)
	for set_name: String in sets:
		for map: String in ["albedo", "normal"]:
			if not sets[set_name].has(map):
				out.append("%s.%s missing" % [set_name, map])
		for key: String in sets[set_name]:
			if typeof(sets[set_name][key]) == TYPE_DICTIONARY:
				out.append_array(_entry_problems("%s.%s" % [set_name, key], sets[set_name][key], "ctex"))
	return out


static func _entry_problems(label: String, e: Dictionary, ext: String) -> Array[String]:
	var sha := str(e.get("sha256", ""))
	if RegEx.create_from_string("^[0-9a-f]{64}$").search(sha) == null:
		return ["%s: sha256 is not 64 hex digits" % label]
	if str(e.get("url", "")) != "%s.%s" % [sha, ext] or int(e.get("size", 0)) <= 0:
		return ["%s: url is not <sha256>.%s or size is 0" % [label, ext]]
	return []


func test_shipped_manifest_lists_every_wanted_module_and_set() -> void:
	assert_int(wanted_modules().size()).is_greater(50)
	assert_array(problems(_json(MANIFEST_PATH))).is_empty()


func test_the_kit_and_the_library_read_it() -> void:
	var kit: BoardgenKit = auto_free(BoardgenKit.new(BoardgenTheme.TOWN_LIBRARY))
	assert_int(kit.module_names().size()).is_equal((_json(MANIFEST_PATH).get("models", {}) as Dictionary).size())
	var lib: TiefwerkLibrary = auto_free(TiefwerkLibrary.new(BoardgenTheme.TOWN_LIBRARY))
	assert_array(lib.set_names()).contains(["coursed_stone", "earth", "grass_cards"])
	assert_int(lib.set_files("cobbles").size()).is_equal(4)   # albedo, normal, orm AND height: every file of a set is fetched


func test_validator_sees_a_missing_module_a_missing_set_and_a_broken_hash() -> void:
	var m := _json(MANIFEST_PATH)
	(m["models"] as Dictionary).erase("dr_ladder_top")
	(m["sets"] as Dictionary).erase("roof_tiles")
	m["sets"]["earth"]["albedo"]["sha256"] = "abc"
	var found := problems(m)
	assert_bool(found.has("module dr_ladder_top missing")).is_true()
	assert_bool(found.has("set roof_tiles missing")).is_true()
	assert_bool(found.any(func(p: String) -> bool: return p.begins_with("earth.albedo"))).is_true()
	assert_array(problems({})).is_equal(["manifest missing or not a JSON object"])
