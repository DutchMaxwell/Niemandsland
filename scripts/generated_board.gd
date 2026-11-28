class_name GeneratedBoard
extends RefCounted
## A generated board as data (GEN-3): the record a table, a save and an MP peer share - `{id, theme, seed, version,
## digest}` - its share code and the silent re-roll of a seed the generator rejects (D-GEN8). Names no look class
## (tools/ci_path_classes.py): the drawn board is main's business, this file only asks `NmlCore.boardgen_tiers`.

## Offer id (assets/terrain_systems.json "generated_board") -> [code prefix, the core's theme id].
const THEMES := {"tiefwerk": ["TW", "deepworks"], "ruined_town": ["RT", "ruintown"]}
## How many times a rejected seed moves on to seed + 1 before the board is given up.
const REROLLS := 20


## The record of board `id` from `seed_value`: the first seed from it on whose board has no `problems` (at most
## REROLLS steps on), or {} for an unknown id, without the core, or when every try is rejected. `core` is for tests.
static func resolve(id: String, seed_value: int, core: Object = null) -> Dictionary:
	if not THEMES.has(id):
		return {}
	if core == null:
		if not ClassDB.class_exists("NmlCore"):
			return {}
		core = ClassDB.instantiate("NmlCore") as Object
	var theme: String = THEMES[id][1]
	for step in REROLLS + 1:
		var s := seed_value + step
		var t: Dictionary = core.call("boardgen_tiers", s, theme)
		if t.has("digest") and (t.get("problems", []) as Array).is_empty():
			return {"id": id, "theme": theme, "seed": s, "version": int(t["version"]), "digest": str(t["digest"])}
	return {}


## A fresh board of `id` from a random seed (31 bits, so a code stays short and every platform parses it).
static func random(id: String, core: Object = null) -> Dictionary:
	return resolve(id, randi() & 0x7fffffff, core)


## The share code of `record`: `<prefix>-<version>-<seed>`, e.g. "TW-1-1234"; "" for no record.
static func code(record: Dictionary) -> String:
	if not THEMES.has(str(record.get("id", ""))):
		return ""
	return "%s-%d-%d" % [THEMES[record["id"]][0], int(record["version"]), int(record["seed"])]


## The `{id, seed, version}` a code names, or `{"reason": ..}` when it is not one this build can lay. `version` is the
## build's GENERATOR_VERSION (-1 = ask the core); a code of another version is refused ("made by another version").
static func parse(text: String, version: int = -1) -> Dictionary:
	var parts := text.strip_edges().to_upper().split("-")
	if parts.size() != 3 or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return {"reason": "not a board code"}
	var id := ""
	for key in THEMES:
		if THEMES[key][0] == parts[0]:
			id = key
	if id.is_empty():
		return {"reason": "not a board code"}
	if version < 0:
		version = _core_version()
	if int(parts[1]) != version:
		return {"reason": "made by another version of the game (board version %s, this game makes %d)" % [parts[1], version]}
	return {"id": id, "seed": int(parts[2]), "version": version}


static func _core_version() -> int:
	if not ClassDB.class_exists("NmlCore"):
		return -1
	var t: Dictionary = (ClassDB.instantiate("NmlCore") as Object).call("boardgen_tiers", 0, "deepworks")
	return int(t.get("version", -1))


## GEN-11: "" when `record` is this build's board of its seed (the same `version` and `digest`), else the reason,
## naming both board codes. A record without a digest (the dev door's board) is not checked. `core` is for tests.
static func verify(record: Dictionary, core: Object = null) -> String:
	if not record.has("digest"):
		return ""
	if core == null:
		if not ClassDB.class_exists("NmlCore"):
			return "This build has no rules core to check the board %s." % code(record)
		core = ClassDB.instantiate("NmlCore") as Object
	var t: Dictionary = core.call("boardgen_tiers", int(record["seed"]), str(record["theme"]))
	var mine := record.duplicate()
	mine["version"] = int(t.get("version", -1))
	if int(record.get("version", -1)) != int(mine["version"]):
		return "This table was made with board version %d (%s); this build makes version %d (%s)." % [
			int(record.get("version", -1)), code(record), mine["version"], code(mine)]
	if str(t.get("digest", "")) != str(record["digest"]):
		return "The board %s does not match this build's board of the same code (digest %s, here %s)." % [
			code(record), str(record["digest"]), str(t.get("digest", ""))]
	return ""
