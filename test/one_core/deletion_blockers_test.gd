extends GdUnitTestSuite
## One core P4.D-12: the deletion blockers of the GDScript table as an executable list. Each row names ONE fact that
## stops a deletion (a caller, a switch, a clause), the file that holds it and the step that retires it. The suite
## asserts the fact is STILL true, so the list cannot rot silently: the step that removes the fact flips its row (the
## row moves to the "gone" assertion or is deleted) in the same diff. A row that fails says which blocker moved.
##
## The last case proves the comparison is not blind: it plants a fault in an in-memory COPY of each source (the needle
## removed, or the whole function removed) and expects the checker to report exactly that blocker and its step.

const ACTIVATION := "res://scripts/solo/core_activation.gd"
const MAIN := "res://scripts/main.gd"
const SELFPLAY := "res://tools/solo_selfplay.gd"
const PARITY_SHOOT := "res://test/parity/parity_table.gd"
const PARITY_MELEE := "res://test/parity/parity_table_melee.gd"

## name / retire = the step that removes the fact / file / header = the top-level `func` line whose body is searched
## ("" = the whole file) / needles = every one must be present.
const BLOCKERS: Array[Dictionary] = [
	{"name": "kill switch CoreActivation.enabled", "retire": "P4.D-41/-43", "file": ACTIVATION,
		"header": "static func enabled() -> bool:", "needles": ["NML_ONE_CORE_ACTIVATION"]},
	{"name": "NmlCore-less build (applies needs the class)", "retire": "P4.D-40", "file": ACTIVATION,
		"header": "static func applies(main) -> bool:", "needles": ["ClassDB.class_exists(\"NmlCore\")"]},
	{"name": "non-OPR clause of is_plain", "retire": "the P4.D-13 follow-up, before P4.D-41", "file": ACTIVATION,
		"header": "static func is_plain(gu: GameUnit) -> bool:", "needles": ["not gu.source_data is OPRApiClient.OPRUnit"]},
	{"name": "tools/solo_selfplay.gd drives the table", "retire": "P4.D-39", "file": SELFPLAY, "header": "",
		"needles": ["main._run_ai_shooting(", "main._run_ai_dangerous(", "main._solo_shooting_morale("]},
	{"name": "parity_table.gd calls the AI volley resolver", "retire": "P4.D-38", "file": PARITY_SHOOT, "header": "",
		"needles": ["main._solo_resolve_ai_volley("]},
	{"name": "parity_table_melee.gd drives the melee resolver", "retire": "P4.D-49", "file": PARITY_MELEE, "header": "",
		"needles": ["main._run_ai_melee("]},
	{"name": "Strafing hands its volley to the AI resolver", "retire": "P4.D-37", "file": MAIN,
		"header": "func _solo_apply_strafing(", "needles": ["await _solo_resolve_ai_volley(unit, target, shots, true)"]},
]


## The text of the top-level function that starts with `header`: up to the next column-0 `func`/`static func`.
## "" header = the whole source. Returns "" when the header is not there.
func _span(src: String, header: String) -> String:
	if header.is_empty():
		return src
	var start := src.find("\n" + header)
	if start < 0:
		return ""
	var rest := src.substr(start + 1 + header.length())
	var ends: Array[int] = []
	for marker in ["\nfunc ", "\nstatic func "]:
		var at := rest.find(marker)
		if at >= 0:
			ends.append(at)
	return src.substr(start, header.length() + 1 + (ends.min() if not ends.is_empty() else rest.length()))


## "" when the blocker's fact holds in `src`, else the sentence that names the blocker and the step that retires it.
func _check(b: Dictionary, src: String) -> String:
	var body := _span(src, b["header"])
	if body.is_empty():
		return "blocker '%s' (retire with %s): %s not found in %s" % [b["name"], b["retire"], b["header"], b["file"]]
	for needle in b["needles"]:
		if not body.contains(needle):
			return "blocker '%s' (retire with %s): `%s` is gone from %s - the fact moved, flip this row" % [
				b["name"], b["retire"], needle, b["file"]]
	return ""


func _source(path: String) -> String:
	var src := FileAccess.get_file_as_string(path)
	assert_str(src).override_failure_message("%s is unreadable" % path).is_not_empty()
	return src


func test_every_deletion_blocker_still_holds() -> void:
	for b in BLOCKERS:
		var verdict := _check(b, _source(b["file"]))
		assert_str(verdict).override_failure_message(verdict).is_empty()


func test_the_list_is_not_empty_and_names_a_step_per_row() -> void:
	assert_int(BLOCKERS.size()).is_greater_equal(7)
	for b in BLOCKERS:
		assert_str(String(b["retire"])).override_failure_message("%s names no step" % b["name"]).contains("P4.D-")


## The checker can fail: a copy of each source without the needle (or without the function) is reported by name.
func test_the_checker_names_a_blocker_whose_fact_is_gone() -> void:
	for b in BLOCKERS:
		var src := _source(b["file"])
		for needle in b["needles"]:
			var planted := src.replace(needle, "")
			var verdict := _check(b, planted)
			assert_str(verdict).override_failure_message("planted fault in '%s' not seen" % b["name"]) \
				.contains(b["name"]).contains("retire with " + b["retire"]).contains(needle)
		if not String(b["header"]).is_empty():
			var no_func := src.replace("\n" + String(b["header"]), "\nfunc _renamed_away(")
			assert_str(_check(b, no_func)).contains(b["name"]).contains("not found")
	# and the whole table is green on the untouched sources
	for b in BLOCKERS:
		assert_str(_check(b, _source(b["file"]))).is_empty()
