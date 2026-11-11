# gdUnit4 guard: the shipped tutorial files and the arena lists carry NO rule-description or spell-effect
# text. The game fills those from the army book at runtime; the lesson saves must not ship a frozen copy.
# Offenders are reported as "<file>: <path> (<count>)" — never with any text content.
extends GdUnitTestSuite

const TUTORIAL_DIR := "res://assets/tutorial"
const SCENARIO_DIR := "res://assets/tutorial/scenarios"
const ARENA_DIR := "res://assets/arena_lists"


## Paths (and counts) of non-empty rule-description / spell-effect text inside a parsed JSON value:
## any "rule_descriptions" map with a non-empty string value, any "specialRules" entry with a non-empty
## "description", any "player_spells" entry with a non-empty "effect".
static func find_text(node: Variant, path: String = "") -> Array:
	var hits: Array = []
	if node is Dictionary:
		var d: Dictionary = node
		for k in d:
			var key := str(k)
			var v: Variant = d[k]
			var p := path + "/" + key
			if key == "rule_descriptions" and v is Dictionary:
				var n := 0
				for rn in (v as Dictionary):
					if v[rn] is String and not (v[rn] as String).strip_edges().is_empty():
						n += 1
				if n > 0:
					hits.append("%s (%d)" % [p, n])
			elif key == "specialRules" and v is Array:
				var n := 0
				for e in (v as Array):
					if e is Dictionary and str((e as Dictionary).get("description", "")).strip_edges() != "":
						n += 1
				if n > 0:
					hits.append("%s (%d)" % [p, n])
			elif key == "player_spells" and v is Dictionary:
				var n := 0
				for pid in (v as Dictionary):
					if v[pid] is Array:
						for sp in (v[pid] as Array):
							if sp is Dictionary and str((sp as Dictionary).get("effect", "")).strip_edges() != "":
								n += 1
				if n > 0:
					hits.append("%s (%d)" % [p, n])
			else:
				hits.append_array(find_text(v, p))
	elif node is Array:
		for i in (node as Array).size():
			hits.append_array(find_text((node as Array)[i], "%s[%d]" % [path, i]))
	return hits


func _shipped_files() -> Array:
	var out: Array = []
	for dir in [TUTORIAL_DIR, SCENARIO_DIR, ARENA_DIR]:
		var da := DirAccess.open(dir)
		if da == null:
			continue
		for f in da.get_files():
			if f.ends_with(".json") or f.ends_with(".nml"):
				out.append(dir + "/" + f)
	out.sort()
	return out


func test_detector_flags_text_and_passes_empty() -> void:
	# The detector itself must be able to fail: own synthetic data, one case per shape it looks for.
	var dirty := {
		"rule_descriptions": {"Some Rule": "some words"},
		"units": [{"unit_properties": {"rule_descriptions": {"Other Rule": "x"}}}],
		"specialRules": [{"name": "R", "description": "words"}],
		"player_spells": {"1": [{"name": "S", "threshold": 1, "effect": "words"}]},
	}
	assert_int(find_text(dirty).size()).is_equal(4)
	var clean := {
		"rule_descriptions": {},
		"units": [{"unit_properties": {"rule_descriptions": {"Other Rule": ""}}}],
		"specialRules": [{"name": "R", "description": ""}, {"name": "Q"}],
		"player_spells": {"1": [{"name": "S", "threshold": 1}, {"name": "T", "threshold": 2, "effect": ""}]},
	}
	assert_array(find_text(clean)).is_empty()


func test_the_guard_sees_the_shipped_files() -> void:
	# Not vacuous: all 12 boards, the 3 army files and the 4 arena lists are in scope.
	var files := _shipped_files()
	var boards := 0
	var armies := 0
	var arenas := 0
	for f in files:
		if (f as String).begins_with(ARENA_DIR):
			arenas += 1
		elif (f as String).ends_with(".nml"):
			boards += 1
		else:
			armies += 1
	assert_int(boards).is_equal(12)
	assert_int(armies).is_equal(3)
	assert_int(arenas).is_equal(4)


func test_no_shipped_tutorial_or_arena_file_carries_rule_or_spell_text() -> void:
	var offenders: Array = []
	for f in _shipped_files():
		var fa := FileAccess.open(f, FileAccess.READ)
		assert_object(fa).is_not_null()
		var data: Variant = JSON.parse_string(fa.get_as_text())
		assert_bool(data is Dictionary).is_true()  # every file still parses
		for h in find_text(data):
			offenders.append("%s: %s" % [(f as String).get_file(), h])
	assert_array(offenders).is_empty()
