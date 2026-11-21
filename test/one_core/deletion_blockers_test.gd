extends GdUnitTestSuite
## One core P4.D-12: the deletion blockers of the GDScript table as an executable list. Each row names ONE fact that
## stops a deletion (a caller, a switch, a clause), the file that holds it and the step that retires it. The suite
## asserts the fact is STILL true, so the list cannot rot silently: the step that removes the fact flips its row (the
## row moves to the "gone" assertion or is deleted) in the same diff. A row that fails says which blocker moved.
##
## The last case proves the comparison is not blind: it plants a fault in an in-memory COPY of each source (the needle
## removed, or the whole function removed) and expects the checker to report exactly that blocker and its step.

const ACTIVATION := "res://scripts/solo/core_activation.gd"
const SLICE := "res://scripts/solo/core_slice.gd"
const MAIN := "res://scripts/main.gd"
const PARITY_MELEE := "res://test/parity/parity_table_melee.gd"

## name / retire = the step that removes the fact / file / header = the top-level `func` line whose body is searched
## ("" = the whole file) / needles = every one must be present.
const BLOCKERS: Array[Dictionary] = [
	{"name": "kill switch CoreActivation.enabled", "retire": "P4.D-41/-43", "file": ACTIVATION,
		"header": "static func enabled() -> bool:", "needles": ["NML_ONE_CORE_ACTIVATION"]},
	{"name": "NmlCore-less build (applies needs the class)", "retire": "P4.D-41 (P4.D-40 made the core mandatory at the doors)", "file": ACTIVATION,
		"header": "static func applies(main) -> bool:", "needles": ["ClassDB.class_exists(\"NmlCore\")"]},
	{"name": "non-OPR clause of is_plain (the attacker side; the target side went with P4.D-13b)",
		"retire": "the P4.D-13 follow-up, before P4.D-41", "file": SLICE,
		"header": "static func refusals(", "needles": ["not gu.source_data is OPRApiClient.OPRUnit"]},
	{"name": "parity_table_melee.gd drives the melee resolver", "retire": "P4.D-49", "file": PARITY_MELEE, "header": "",
		"needles": ["main._run_ai_melee("]},
	{"name": "Strafing hands its volley to the AI resolver", "retire": "P4.D-37", "file": MAIN,
		"header": "func _solo_apply_strafing(", "needles": ["await _solo_resolve_ai_volley(unit, target, shots, true)"]},
	# PLAN H (H-4): the facts the table-remains plan retires.
	{"name": "the AI body runs the pre-attack beats itself (Breath Attack before the volley)", "retire": "P4.D-41 / H-5..H-9", "file": MAIN,
		"header": "func _solo_activate_one_ai_body(", "needles": ["await _solo_apply_breath_attack(unit)"]},
	{"name": "human_shoot hands an Auto verb's volley back to the table", "retire": "P4.D-43 / H-32", "file": ACTIVATION,
		"header": "static func human_shoot(", "needles": ["if auto:"]},
	{"name": "the human door reads the allow file, not the live slice", "retire": "P4.D-43f / H-30", "file": SLICE,
		"header": "static func human_path() -> String:", "needles": ["return PATH"]},
	{"name": "hotseat Automatic is OFF unless NML_ONE_CORE_HOTSEAT is set", "retire": "P4.D-43c / H-31", "file": ACTIVATION,
		"header": "static func hotseat_enabled() -> bool:", "needles": ["_hotseat_env = 1 if (raw == \"1\" or raw == \"on\") else 0"]},
	{"name": "the AI door takes a Rush only for a move-through bearer or a caster", "retire": "P4.D-41 / H-23", "file": ACTIVATION,
		"header": "static func takes_action(", "needles": ["kind == AiDecision.Action.RUSH and (casting or moves_through(unit))"]},
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
	assert_int(BLOCKERS.size()).is_greater_equal(10)
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


## P4.D-13b retired the TARGET side of the non-OPR clause: both core doors ask `is_plain_target` (C-19: the human door its
## `_human` twin), never `is_plain`, about the target. RED: put `is_plain(target)` back into either door.
func test_the_target_side_of_the_non_opr_clause_is_gone() -> void:
	var src := _source(ACTIVATION)
	for header in ["static func run_ai(", "static func human_shoot("]:
		var body := _span(src, header)
		var asks := "is_plain_target(target)" if header == "static func run_ai(" else "is_plain_target_human(target)"
		assert_str(body).override_failure_message("%s not found" % header).is_not_empty()
		assert_bool(body.contains("is_plain(target)")).override_failure_message("%s asks is_plain(target) again" % header).is_false()
		assert_bool(body.contains(asks)).override_failure_message("%s lost %s" % [header, asks]).is_true()


## P4.D-41 retired the row "the core door shows the table's volley outcome sentence": `_present` asks the door's own
## `volley_outcome` (the table's sentence, moved verbatim); DN-2 removed the table wrapper, the resolver asks the door itself.
## RED: put `main._solo_volley_outcome(` back into `_present`, or drop either `volley_outcome` call.
func test_the_core_door_owns_the_volley_outcome_sentence() -> void:
	var door := _span(_source(ACTIVATION), "static func _present(")
	assert_str(door).override_failure_message("_present not found").is_not_empty()
	assert_bool(door.contains("main._solo_volley_outcome(")).override_failure_message(
		"_present calls the table's sentence again").is_false()
	assert_bool(door.contains("CoreActivation.volley_outcome(")).override_failure_message(
		"_present lost the door's own sentence").is_true()
	# DN-2: the table's wrapper is gone, the resolver asks the door's sentence itself.
	assert_bool(_source(MAIN).contains("func _solo_volley_outcome(")).override_failure_message(
		"the table wrapper is still there").is_false()
	assert_bool(_span(_source(MAIN), "func _solo_resolve_ai_volley(").contains("CoreActivation.volley_outcome(")).override_failure_message(
		"the resolver does not ask the door's sentence").is_true()
	assert_bool(_span(_source(ACTIVATION), "static func volley_outcome(").contains("loses %d model%s")).override_failure_message(
		"the door does not build the sentence itself").is_true()
	for b in BLOCKERS:
		assert_str(String(b["name"])).override_failure_message("the retired row is still in BLOCKERS").is_not_equal(
			"the core door shows the table's volley outcome sentence")
