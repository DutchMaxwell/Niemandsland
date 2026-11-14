extends GdUnitTestSuite
## One core P4.0-3: the state-delta inventory must not rot. This suite parses the field names of the core's
## `pub struct State` out of core/nml-core/src/state.rs and compares them with the rows of
## docs/one_core/STATE_DELTA_INVENTORY.md. A new State field without a row (or a row for a field that is gone)
## reddens here, so the inventory stays the complete list it claims to be.
##
## The second case proves the comparison is not blind: it appends a fake field name to a COPY of the parsed
## list and expects the comparator to report it as undocumented (the red proof from the brief, kept as a test).

const STATE_RS := "res://core/nml-core/src/state.rs"
const DOC := "res://docs/one_core/STATE_DELTA_INVENTORY.md"


## The `pub name:` fields of `pub struct State`, in declaration order.
func _state_fields() -> Array:
	var src := FileAccess.get_file_as_string(STATE_RS)
	assert_str(src).override_failure_message("%s is unreadable" % STATE_RS).is_not_empty()
	var start := src.find("pub struct State {")
	assert_int(start).override_failure_message("pub struct State not found in %s" % STATE_RS).is_greater_equal(0)
	var body := src.substr(start)
	var end := body.find("\n}\n")
	assert_int(end).override_failure_message("the State struct has no closing brace").is_greater_equal(0)
	body = body.substr(0, end)
	var re := RegEx.new()
	assert_int(re.compile("(?m)^    pub (\\w+):")).is_equal(OK)
	var out: Array = []
	for m in re.search_all(body):
		out.append(m.get_string(1))
	return out


## The field names of the inventory table: every row starts with "| `field`".
func _documented_fields() -> Array:
	var doc := FileAccess.get_file_as_string(DOC)
	assert_str(doc).override_failure_message("%s is unreadable" % DOC).is_not_empty()
	var re := RegEx.new()
	assert_int(re.compile("(?m)^\\| `([a-z0-9_]+)`")).is_equal(OK)
	var out: Array = []
	for m in re.search_all(doc):
		out.append(m.get_string(1))
	return out


## Fields in `parsed` but not in `documented` (missing row) and vice versa (stale row).
func _diff(parsed: Array, documented: Array) -> Dictionary:
	var missing: Array = []
	var extra: Array = []
	for f in parsed:
		if not documented.has(f):
			missing.append(f)
	for f in documented:
		if not parsed.has(f):
			extra.append(f)
	return {"missing": missing, "extra": extra}


func test_every_state_field_has_a_row_and_every_row_has_a_field() -> void:
	var parsed := _state_fields()
	assert_int(parsed.size()).override_failure_message("the State parse found too few fields to be real").is_greater(50)
	var d := _diff(parsed, _documented_fields())
	assert_array(d["missing"]).override_failure_message(
		"State fields with no inventory row: %s" % [d["missing"]]).is_empty()
	assert_array(d["extra"]).override_failure_message(
		"inventory rows for fields State does not have: %s" % [d["extra"]]).is_empty()


func test_the_comparator_flags_a_new_field_in_a_copy_of_the_parsed_list() -> void:
	var copy := _state_fields().duplicate()
	copy.append("fake_new_state_field")
	var d := _diff(copy, _documented_fields())
	assert_array(d["missing"]).override_failure_message(
		"the comparator missed a fake field - the inventory check is blind").contains(["fake_new_state_field"])
