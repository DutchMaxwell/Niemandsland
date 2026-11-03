extends GdUnitTestSuite
## Rules 3.6 wave, row UX-CITE: every player-visible rules citation names the rules version from the
## SINGLE SOURCE (OPRApiClient.rules_core_version, rendered by the new rules_cite helper) and drops
## page numbers. Comments are stripped before the scan, string literals are kept.
## PR A scans only the source it converts: main.gd up to the split line (stated in the PR body).

const MAIN := "res://scripts/main.gd"
const SPLIT_LINE := 12000
const FILES := [MAIN]


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
	page_re.compile("p\\.\\s?\\d")
	var bad: Array[String] = []
	for path in FILES:
		var file := FileAccess.open(path, FileAccess.READ)
		assert_object(file).is_not_null()
		if file == null:
			continue
		var line_no := 0
		while not file.eof_reached():
			var line := file.get_line()
			line_no += 1
			if path == MAIN and line_no > SPLIT_LINE:
				break
			for lit in _literals(_code_without_comment(line)):
				if lit.contains("v3.5") or page_re.search(lit) != null:
					bad.append("%s:%d -> %s" % [path, line_no, lit])
		file.close()
	assert_array(bad).is_empty()


func test_rules_cite_uses_the_rule_maps_version() -> void:
	var cases := [["gf", "GF ", "gf"], ["aof", "AoF ", "aof"], ["gf/aof", "GF/AoF ", "gf"]]
	for c in cases:
		var scope: String = c[0]
		var label: String = c[1]
		var system: String = c[2]
		var expected := label + OPRApiClient._major_minor(OPRApiClient.rules_core_version(system))
		assert_str(OPRApiClient.rules_cite(scope)).is_equal(expected)
