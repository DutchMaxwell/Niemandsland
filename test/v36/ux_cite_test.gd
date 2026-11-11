extends GdUnitTestSuite
## Rules 3.6 wave, row UX-CITE: every player-visible rules citation names the rules version from the
## SINGLE SOURCE (OPRApiClient.rules_core_version, rendered by the rules_cite helper) and drops page
## numbers. Comments are stripped before the scan, string literals are kept.
## PR B scans the full set of files this row converts and checks the two lead corrections: the
## citation follows the CURRENT GAME's system (no hardcoded "gf"/"aof" call site) and the Solo & Co-Op
## marker line carries no core version at all.

const FILES := [
	"res://scripts/main.gd",
	"res://scripts/opr_api_client.gd",
	"res://scripts/opr_army_manager.gd",
	"res://scripts/placement_ghost.gd",
	"res://scripts/radial_menu.gd",
	"res://scripts/radial_menu_controller.gd",
]
## The label rules_cite renders per normalized game system (the version itself comes from the map).
const SYSTEM_LABELS := [
	["gf", "GF "], ["gff", "GFF "], ["aof", "AoF "], ["aofs", "AoFS "], ["aofr", "AoF:R "],
]


## Drops a trailing `#` comment, keeping quoted text (and `#` inside a string) intact.
func _code_without_comment(line: String) -> String:
	var out := ""
	var quote := ""
	var escaped := false
	for i in line.length():
		var c := line[i]
		if escaped:
			escaped = false
			out += c
			continue
		if c == "\\":
			escaped = true
			out += c
			continue
		if quote != "":
			out += c
			if c == quote:
				quote = ""
			continue
		if c == "\"" or c == "'":
			quote = c
			out += c
		elif c == "#":
			break
		else:
			out += c
	return out


## The string-literal bodies of one line of code (comment already stripped).
func _literals(code: String) -> Array[String]:
	var out: Array[String] = []
	var quote := ""
	var escaped := false
	var buf := ""
	for i in code.length():
		var c := code[i]
		if quote == "":
			if c == "\"" or c == "'":
				quote = c
				buf = ""
			continue
		if escaped:
			escaped = false
			buf += c
			continue
		if c == "\\":
			escaped = true
			buf += c
			continue
		if c == quote:
			out.append(buf)
			quote = ""
			buf = ""
			continue
		buf += c
	return out


func test_player_visible_citations_name_the_rules_version() -> void:
	var page_re := RegEx.new()
	page_re.compile("(p\\.\\s?\\d|v3\\.\\d|rules\\s+\\d\\.\\d)")
	var bad: Array[String] = []
	var checked := 0
	for path in FILES:
		var file := FileAccess.open(path, FileAccess.READ)
		assert_object(file).override_failure_message("cannot read %s" % path).is_not_null()
		if file == null:
			continue
		var line_no := 0
		while not file.eof_reached():
			var line := file.get_line()
			line_no += 1
			for lit in _literals(_code_without_comment(line)):
				checked += 1
				if lit.contains("v3.5") or page_re.search(lit) != null:
					bad.append("%s:%d -> %s" % [path, line_no, lit])
		file.close()
	assert_int(checked).override_failure_message(
		"the citation scan saw no string literal at all").is_greater(0)
	assert_array(bad).override_failure_message(
		"player-visible citation(s) still name a page or a hardcoded version:\n%s" % "\n".join(bad)).is_empty()


## The lead correction: a call site never hardcodes the system; it passes the game's own system.
func test_no_call_site_hardcodes_a_system() -> void:
	var call_re := RegEx.create_from_string("rules_cite\\(")
	var literal_re := RegEx.create_from_string("rules_cite\\(\"")
	var bad: Array[String] = []
	var checked := 0
	for path in FILES:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var line_no := 0
		while not file.eof_reached():
			var line := file.get_line()
			line_no += 1
			var code := _code_without_comment(line)
			if call_re.search(code) != null:
				checked += 1
				if literal_re.search(code) != null:
					bad.append("%s:%d -> %s" % [path, line_no, code.strip_edges()])
		file.close()
	assert_int(checked).override_failure_message(
		"found no rules_cite call site to check").is_greater(0)
	assert_array(bad).override_failure_message(
		"these citations hardcode a system instead of the current game's:\n%s" % "\n".join(bad)).is_empty()


## A Solo & Co-Op sentence is not a GF/AoF core citation, so the marker line carries no version.
func test_solo_marker_line_carries_no_version_citation() -> void:
	var file := FileAccess.open("res://scripts/main.gd", FileAccess.READ)
	assert_object(file).is_not_null()
	if file == null:
		return
	var bad: Array[String] = []
	var checked := 0
	var line_no := 0
	while not file.eof_reached():
		var line := file.get_line()
		line_no += 1
		var code := _code_without_comment(line)
		if not code.contains("Solo & Co-Op"):
			continue
		checked += 1
		if code.contains("rules_cite(") or code.contains("v3.5") or code.contains("rules 3.6"):
			bad.append("%s:%d -> %s" % ["res://scripts/main.gd", line_no, code.strip_edges()])
	file.close()
	assert_int(checked).override_failure_message(
		"found no Solo & Co-Op line in main.gd").is_greater(0)
	assert_array(bad).override_failure_message(
		"a Solo & Co-Op line still carries a core version citation:\n%s" % "\n".join(bad)).is_empty()


func test_rules_cite_uses_the_rule_maps_version() -> void:
	for c in SYSTEM_LABELS:
		var system: String = c[0]
		var label: String = c[1]
		var expected := label + OPRApiClient._major_minor(OPRApiClient.rules_core_version(system))
		assert_str(OPRApiClient.rules_cite(system)).override_failure_message(
			"rules_cite(%s) does not name that system" % system).is_equal(expected)
	# The combined scope stays available for the legacy two-book wording.
	assert_str(OPRApiClient.rules_cite("gf/aof")).is_equal(
		"GF/AoF " + OPRApiClient._major_minor(OPRApiClient.rules_core_version("gf")))
