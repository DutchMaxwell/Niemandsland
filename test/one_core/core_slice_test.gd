extends GdUnitTestSuite
## One core P4.D-6: `CoreSlice` (assets/solo/core_slice_allow.json) decides which units the core door takes. With NO group
## it must be byte-identical to the old `CoreActivation.is_plain`: a grid over every unit of the gf and aof fixture lists
## (and synthetic units for the shapes a list has none of) compares `CoreSlice.takes` with a frozen copy of the old
## predicate, and `CoreSlice.refusals` with a frozen copy of the P4.D-3 census labels. The cases that widen the slice use
## a temp file through `CoreSlice.path_override` and prove the grid CAN fail.
## Real: the importer (`build_army_offline` + `create_from_opr_unit`), the registry maps. Constructed: synthetic units.

const LISTS := [
	"res://test/fixtures/card_list_gf_custodian_brothers_1000.json", "res://test/fixtures/wolf_brothers_3000.json",
	"res://test/fixtures/card_list_aof_beastmen_1000.json", "res://test/fixtures/card_list_aof_ratmen_1500.json",
	"res://assets/arena_lists/p1_2000.json", "res://assets/arena_lists/p2_2000.json",
	"res://assets/arena_lists/p1_3000.json", "res://assets/arena_lists/p2_3000.json"]
const TMP := "user://core_slice_test.json"


func after_test() -> void:
	CoreSlice.path_override = ""
	CoreSlice.reset_cache()
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(TMP)


## A temp slice file with one group per entry of `groups` (name -> primitives) in `mode`; the slice reads it from now on.
func _allow(groups: Dictionary, mode := "allow") -> void:
	var g := {}
	for name in groups:
		g[name] = {"primitives": groups[name], "step": "P4.D-0", "golden": "x", "parity": "x"}
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string(JSON.stringify({"schema": CoreSlice.SCHEMA, "door": "shoot", "mode": mode, "groups": g}))
	f.close()
	CoreSlice.path_override = TMP
	CoreSlice.reset_cache()


## The slice with no group (what ships today), through a temp file so a widening of the shipped file cannot move the grid.
func _empty_slice() -> void:
	_allow({})


## A synthetic OPR unit: unit rules, one weapon per entry of `weapon_rules`; gf, no faction (common lookups).
func _unit(unit_rules: Array, weapon_rules: Array) -> GameUnit:
	var gu := GameUnit.new()
	gu.unit_properties["special_rules"] = unit_rules
	gu.unit_properties["game_system"] = "gf"
	var src := OPRApiClient.OPRUnit.new()
	for rules in weapon_rules:
		var w := OPRApiClient.OPRWeapon.new()
		w.special_rules.assign(rules)
		src.weapons.append(w)
	gu.source_type = "opr"
	gu.source_data = src
	return gu


## The P4.D-3 census reasons of `gu` as shooter and target ("no_core" is the build's, not the slice's).
func _why(gu: GameUnit) -> Array:
	return CoreActivation.why_not(_StubMain.new(), gu, gu).filter(func(r: String) -> bool: return r != "no_core")


func _synthetic() -> Array:
	var host := _unit([], [[]])
	var hero := _unit([], [[]])
	hero.unit_properties["attached_to"] = host
	host.unit_properties["attached_heroes"] = [hero]
	var bare := GameUnit.new()   # no OPR source: a loaded foreign save
	return [_unit([], [[]]), _unit([], [[], []]), _unit(["Tough(3)"], [[]]), _unit([{"name": "Fear (spell)"}], [[]]),
		_unit([], [["AP(1)"]]), _unit([], [["AP(1)"], ["Blast(3)", "Deadly(3)"]]), _unit(["Fast", "Scout"], [["Rending"]]),
		_unit(["Unheard Of Rule"], [[]]), host, hero, bare]


## Every unit of every fixture list, built by the table's own importer.
func _grid() -> Array:
	var out: Array = _synthetic()
	var holder: Node = auto_free(Node.new())
	add_child(holder)
	for path in LISTS:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		assert_bool(data is Dictionary).override_failure_message("%s unreadable" % path).is_true()
		var client := OPRApiClient.new()
		var army: OPRApiClient.OPRArmy = client.build_army_offline(data as Dictionary)
		client.free()
		assert_object(army).override_failure_message("%s: no army" % path).is_not_null()
		for ou: OPRApiClient.OPRUnit in army.units:
			var nodes: Array[Node3D] = []
			for _m in range(maxi(ou.size, 1)):
				var n := Node3D.new()
				holder.add_child(n)
				nodes.append(n)
			out.append(EquipmentDistributor.create_from_opr_unit(ou, nodes, 1))
	return out


## FROZEN copy of `CoreActivation.is_plain` as it was before P4.D-6.
func _plain_old(gu: GameUnit, as_target := false) -> bool:
	if not (gu.unit_properties.get("special_rules", []) as Array).is_empty() \
			or gu.has_attached_heroes() or gu.is_attached() or (not as_target and not gu.source_data is OPRApiClient.OPRUnit):
		return false
	var src := gu.source_data as OPRApiClient.OPRUnit
	for w in src.weapons if src != null else []:
		if not w.special_rules.is_empty():
			return false
	return true


## FROZEN copy of the P4.D-3 census labels (`CoreActivation._refusals`) as they were before P4.D-6.
func _labels_old(gu: GameUnit, as_target := false) -> Array:
	var lab := func(r) -> String:
		return (str((r as Dictionary).get("name", "")) if r is Dictionary else str(r)).get_slice("(", 0).strip_edges()
	var out: Array = (gu.get_special_rules() as Array).map(func(r) -> String: return "unit_rule:" + lab.call(r))
	if gu.has_attached_heroes() or gu.is_attached():
		out.append("attached")
	if not gu.source_data is OPRApiClient.OPRUnit:
		return out if as_target else out + ["non_opr"]
	for w in (gu.source_data as OPRApiClient.OPRUnit).weapons:
		out.append_array(w.special_rules.map(func(r) -> String: return "weapon_rule:" + lab.call(r)))
	return out


func _differences(units: Array) -> Array:
	var bad: Array = []
	for u in units:
		var gu := u as GameUnit
		for as_target in [false, true]:
			if CoreSlice.takes(gu, as_target) != _plain_old(gu, as_target):
				bad.append("%s (target %s): takes %s, old %s" % [gu.get_name(), as_target, CoreSlice.takes(gu, as_target), _plain_old(gu, as_target)])
			if CoreSlice.refusals(gu, as_target) != _labels_old(gu, as_target):
				bad.append("%s (target %s): labels %s, old %s" % [gu.get_name(), as_target, CoreSlice.refusals(gu, as_target), _labels_old(gu, as_target)])
	return bad


## The grid: with no group the slice is the old predicate and the old labels, for every unit, as shooter and as target.
## RED: allow primitives in a temp file (the next two cases) or make `takes` ignore a weapon rule -> the grid names the unit.
func test_an_empty_slice_is_byte_identical_to_the_old_predicate() -> void:
	_empty_slice()
	var units := _grid()
	assert_int(units.size()).override_failure_message("the grid has %d units: too small to mean anything" % units.size()).is_greater(60)
	var plain := units.filter(func(u: GameUnit) -> bool: return _plain_old(u)).size()
	assert_int(plain).override_failure_message("no plain unit in the grid: only the refusing side is compared").is_greater(1)
	var bad := _differences(units)
	print("CORE_SLICE_GRID units=%d plain=%d lists=%d mismatches=%d" % [units.size(), plain, LISTS.size(), bad.size()])
	assert_array(bad).override_failure_message("grid differs:\n" + "\n".join(bad.slice(0, 10))).is_empty()


## The shipped file is well-formed: its schema, the shoot door, and for every group the four fields of the template, with a
## golden fixture and a parity scenario that exist. (Today there is no group: the loop is empty and the next step fills it.)
func test_the_shipped_allowlist_is_well_formed() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CoreSlice.PATH))
	assert_str(str(data.get("schema"))).is_equal(CoreSlice.SCHEMA)
	assert_str(str(data.get("door"))).is_equal("shoot")
	assert_array(CoreSlice.MODES).override_failure_message("the shipped mode is none of %s" % [CoreSlice.MODES]).contains([str(data.get("mode"))])
	for g in data["groups"]:
		var grp: Dictionary = data["groups"][g]
		assert_array((grp.get("primitives", []) as Array)).override_failure_message("%s: no primitives" % g).is_not_empty()
		assert_str(str(grp.get("step", ""))).override_failure_message("%s: no step" % g).starts_with("P4.D-")
		assert_bool(FileAccess.file_exists(str(grp.get("golden", "")))).override_failure_message("%s: golden %s missing" % [g, grp.get("golden")]).is_true()
		assert_bool(FileAccess.file_exists("res://test/parity/scenarios/shoot/%s.json" % grp.get("parity", ""))).override_failure_message(
			"%s: parity scenario %s missing" % [g, grp.get("parity")]).is_true()


## RED proof 1: one allowed primitive takes a unit whose only rule it is - the old predicate says no, the grid differs.
func test_allowing_a_primitive_takes_the_units_that_carry_only_it() -> void:
	var ap_only := _unit([], [["AP(1)"]])
	var ap_blast := _unit([], [["AP(1)", "Blast(3)"]])
	_empty_slice()
	assert_bool(CoreSlice.takes(ap_only)).is_false()
	_allow({"ap": ["AP"]})
	assert_bool(CoreSlice.takes(ap_only)).override_failure_message("AP allowed, a unit with only AP is refused").is_true()
	assert_bool(CoreSlice.takes(ap_blast)).override_failure_message("a unit with an unallowed rule is taken").is_false()
	assert_array(CoreSlice.refusals(ap_blast)).is_equal(["weapon_rule:Blast"])
	assert_array(_differences([ap_only])).override_failure_message("the grid cannot see a widening").is_not_empty()


## RED proof 2: an unknown rule name is refused even when every primitive is allowed; a known one of the allowed set passes
## whether it sits on the unit or on a weapon, and the census labels agree with the decision (one lookup).
func test_an_unknown_name_is_refused_and_the_census_agrees() -> void:
	_allow({"all": ["AP", "Tough", "Blast", "Fast"]})
	var odd := _unit(["Unheard Of Rule"], [[]])
	assert_bool(CoreSlice.takes(odd)).is_false()
	assert_array(CoreSlice.refusals(odd)).is_equal(["unit_rule:Unheard Of Rule"])
	var ok := _unit(["Tough(3)", "Fast"], [["Blast(3)"], ["AP(2)"]])
	assert_bool(CoreSlice.takes(ok)).is_true()
	assert_array(_why(ok)).is_empty()
	var half := _unit(["Tough(3)", "Scout"], [["AP(2)"]])
	assert_array(_why(half)).is_equal(["unit_rule:Scout", "target_rule:Scout"])


## Attachments are refused unless the group "attached_heroes" is in the file; a shooter with no OPR profile never passes,
## a target with none does.
func test_attachments_and_the_profile_follow_the_file() -> void:
	var host := _unit([], [[]])
	var hero := _unit([], [[]])
	hero.unit_properties["attached_to"] = host
	host.unit_properties["attached_heroes"] = [hero]
	var bare := GameUnit.new()
	_allow({"ap": ["AP"]})
	assert_bool(CoreSlice.takes(host)).is_false()
	_allow({"ap": ["AP"], "attached_heroes": ["Hero"]})
	assert_bool(CoreSlice.takes(host)).override_failure_message("the host with an allowed attachment").is_true()
	assert_bool(CoreSlice.takes(hero)).is_true()
	assert_bool(CoreSlice.takes(bare)).override_failure_message("a shooter with no profile").is_false()
	assert_bool(CoreSlice.takes(bare, true)).override_failure_message("a target with no profile").is_true()


## Every primitive any registry map resolves a rule name to (what a deny-list that lists "everything" lists).
func _all_primitives() -> Array:
	var seen := {}
	for sys in RulesRegistry.SYSTEMS:
		var m := RulesRegistry.map_for(sys)
		for section in [m.get("common", {})] + (m.get("factions", {}) as Dictionary).values():
			for entry in (section as Dictionary).values():
				var p: Variant = (entry as Dictionary).get("primitive")
				if p is String:
					seen[p] = true
	return seen.keys()


## The predicate reads either way: a DENY slice that lists every primitive and the attachments takes exactly what the empty
## ALLOW slice takes (the old predicate), on the whole grid.
func test_a_deny_slice_listing_everything_is_the_empty_allow_slice() -> void:
	var prims := _all_primitives()
	assert_int(prims.size()).override_failure_message("the registry names no primitives").is_greater(50)
	_allow({"everything": prims, "attached_heroes": ["Hero"]}, "deny")
	var units := _grid()
	assert_array(_differences(units)).override_failure_message("deny-all differs from allow-none").is_empty()


## Mode "deny": allow by default, the listed primitives refused; an unknown name is still refused.
func test_deny_mode_takes_what_is_not_listed() -> void:
	var ap_only := _unit([], [["AP(1)"]])
	var blast := _unit([], [["AP(1)", "Blast(3)"]])
	var odd := _unit(["Unheard Of Rule"], [[]])
	var host := _unit([], [[]])
	var hero := _unit([], [[]])
	hero.unit_properties["attached_to"] = host
	host.unit_properties["attached_heroes"] = [hero]
	_allow({}, "deny")   # nothing listed: everything with a known primitive is taken, attachments too
	assert_bool(CoreSlice.takes(ap_only)).is_true()
	assert_bool(CoreSlice.takes(blast)).is_true()
	assert_bool(CoreSlice.takes(host)).override_failure_message("an attachment with nothing denied").is_true()
	assert_bool(CoreSlice.takes(odd)).override_failure_message("an unknown name is taken in deny mode").is_false()
	_allow({"blast": ["Blast"], "attached_heroes": ["Hero"]}, "deny")
	assert_bool(CoreSlice.takes(ap_only)).is_true()
	assert_bool(CoreSlice.takes(blast)).is_false()
	assert_array(CoreSlice.refusals(blast)).is_equal(["weapon_rule:Blast"])
	assert_bool(CoreSlice.takes(host)).override_failure_message("an attachment on the deny-list").is_false()
	assert_bool(CoreSlice.takes(_unit([], [[]]))).is_true()


## A missing or malformed file is the EMPTY slice (the table shoots everything with a rule), never a wider one.
func test_a_missing_or_malformed_file_is_the_empty_slice() -> void:
	var ap_only := _unit([], [["AP(1)"]])
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string("{\"schema\": \"nml-core-slice-v1\", \"door\": \"melee\", \"groups\": {\"ap\": {\"primitives\": [\"AP\"]}}}")
	f.close()
	CoreSlice.path_override = TMP
	CoreSlice.reset_cache()
	assert_bool(CoreSlice.takes(ap_only)).override_failure_message("a file for another door widened the shoot door").is_false()
	f = FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string("{\"schema\": \"nml-core-slice-v1\", \"door\": \"shoot\", \"mode\": \"sideways\", \"groups\": {}}")
	f.close()
	CoreSlice.reset_cache()
	assert_bool(CoreSlice.takes(_unit(["Fast"], [[]]))).override_failure_message("an unknown mode widened the slice").is_false()
	CoreSlice.path_override = "user://core_slice_does_not_exist.json"
	CoreSlice.reset_cache()
	assert_bool(CoreSlice.takes(ap_only)).is_false()
	assert_bool(CoreSlice.takes(_unit([], [[]]))).override_failure_message("a plain unit must stay taken").is_true()


## C-15: env NML_CORE_SLICE=deny reads the measured deny-list file instead of the shipped allowlist; unset, the shipped
## file as before. The deny file refuses its listed primitives (a wound-ignore target, a Tear weapon) and takes a unit whose
## rules are automated and not listed (AP, Tough); an unknown name stays refused. The list only shrinks: CEILING.
## RED: read PATH regardless of the switch -> the first assertion reads mode "allow".
const DENY_CEILING := 11   # C-18 measurement added Indirect (the first soak of the taken share); from here it only shrinks


func test_the_deny_switch_reads_the_measured_deny_list() -> void:
	OS.set_environment("NML_CORE_SLICE", "deny")
	CoreSlice.reset_cache()
	assert_str(str(CoreSlice.config()["mode"])).is_equal("deny")
	assert_array(CoreSlice.refusals(_unit(["Regeneration"], [["AP(1)"]]))).is_equal(["unit_rule:Regeneration"])
	assert_array(CoreSlice.refusals(_unit(["Tough(3)"], [["Tear"]]))).is_equal(["weapon_rule:Tear"])
	assert_bool(CoreSlice.takes(_unit(["Tough(3)"], [["AP(1)"]]))).is_true()
	# C-18 measured: an Indirect weapon and a joined hero (either side) stay on the table.
	assert_array(CoreSlice.refusals(_unit([], [["Indirect"]]))).is_equal(["weapon_rule:Indirect"])
	var host := _unit(["Tough(3)"], [["AP(1)"]])
	EquipmentDistributor.attach_hero_to_unit(_unit(["Hero"], []), host)
	assert_array(CoreSlice.refusals(host, true)).contains(["attached"])
	assert_array(CoreSlice.refusals(_unit(["No Such Rule"], []))).is_equal(["unit_rule:No Such Rule"])
	assert_int((CoreSlice.config()["primitives"] as Dictionary).size()).override_failure_message(
		"the deny list only shrinks (ceiling %d)" % DENY_CEILING).is_less_equal(DENY_CEILING)
	OS.unset_environment("NML_CORE_SLICE")
	CoreSlice.reset_cache()
	assert_str(str(CoreSlice.config()["mode"])).is_equal("allow")


## Deny mode takes a joined hero with its unit, so a rule the hero carries is read too: a host whose only listed rule
## sits on its joined hero is refused by that rule (C-18 soak: Piercing Growth on a joined Grunt Veteran). RED: read only
## the host's own rules -> the host is taken.
func test_deny_mode_reads_the_joined_heros_rules() -> void:
	_allow({"g": ["Tear"]}, "deny")
	var host := _unit(["Tough(3)"], [["AP(1)"]])
	EquipmentDistributor.attach_hero_to_unit(_unit(["Hero"], [["Tear"]]), host)
	assert_array(CoreSlice.refusals(host)).contains(["weapon_rule:Tear"])
	assert_bool(CoreSlice.takes(host, true)).is_false()


## `applies` reads only these two members (the census test's stub).
class _StubMain extends RefCounted:
	var solo_ai_slots := {1: true}
	func _online_turn_room() -> bool:
		return false
