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
const SlicePin := preload("res://test/one_core/slice_pin.gd")


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


## C-15 / C-19: the measured deny-list is what the live slice reads (env `deny`, as before; since C-19 also with the env unset).
## The deny file refuses its listed primitives (a Teleport unit) and takes a unit whose
## rules are automated and not listed (AP, Tough); a name no map knows is taken (unmapped_inert). The list only shrinks: CEILING.
## RED: read PATH regardless of the switch -> the first assertion reads mode "allow".
const DENY_CEILING := 6   # H-8 (Plan H): Mind Control left the beat group through the beats guard (7 -> 6). H-7 (Plan H): Storm Attack left the beat group through the beats guard (8 -> 7). H-6 (Plan H): Breath Attack left the beat group through the beats guard (9 -> 8). H-5 (Plan H): Mend left the beat group through the beats guard (10 -> 9). H-17a (Plan H): Disintegrate and Tear left with their line, the core says `<rule>: AP(+N) against <U>` (12 -> 10). DLINES train 4 (DS-GHITN): the to-hit note (6 primitives: Artillery, Stealth, Evasive, Aircraft, Shot Modifier, Instinctive) and Takedown left with their lines (19 -> 12). DLINES3 train 3: Shred, Self-Repair and Resistance left with their lines (19 -> 16), then the probes at 1500 / 2000 / 3000 pts showed three more families whose line the door omits: Armor, Disintegrate, Tear (+3 -> 19). DLINES2 train 2: Ranged Shrouding, Lacerate, Shielded, Fortified and Regeneration left with their lines (24 -> 19). 19.11.: +15 primitives in eight `rule_line` groups (a rule whose table line the door omits stays on the table until the line exists, dlines_gap rows 2, 3, 7, 13, 15, 16, 17, 21), they leave group by group with their lines. BEATS 19.11.: the pre-attack beat slot adds 6 primitives, the list stands at exactly 9 (3 ledger + 6 beat), no slack left, they leave with the beats guard; HR-POS: Hit & Run + Hit & Run Shooter lifted again (the delta carries the stepped positions; G10 had re-denied them); C-18: Indirect added, attached_heroes lifted for Growth Markers, wound-ignore by name lifted (C-R1); LD-6 18.11. lifted the six EQUAL-probe names; only shrinks


func test_the_deny_switch_reads_the_measured_deny_list() -> void:
	OS.set_environment("NML_CORE_SLICE", "deny")
	CoreSlice.reset_cache()
	assert_str(str(CoreSlice.config()["mode"])).is_equal("deny")
	# C-R1 (epochs 82 + 84) ported the wound-ignore rules by name and left the deny list; DLINES2 refuses the families whose roll line the door
	# does not write (dlines_gap row 3): the terrain and once-per-game aliases (Grounded Protection, Protection Feat) by name; the groups' rolls are said since trains 2 and 3. Tough stays taken.
	var grounded := _unit(["Grounded Protection"], [["AP(1)"]])
	grounded.unit_properties["faction_folder"] = "soul_snatcher_cults"
	assert_array(CoreSlice.refusals(grounded)).is_equal(["unit_rule:Grounded Protection"])
	assert_bool(CoreSlice.takes(_unit(["Regeneration"], [["AP(1)"]]))).is_true()
	assert_bool(CoreSlice.takes(_unit(["Tough(3)"], [["AP(1)"]]))).is_true()
	# DS-STEALTH: Changebound (primitive Stealth) left the deny names; the dice are equal (stealth_target_door_test.gd), the one difference sits behind a refused shooter.
	var changed := _unit(["Changebound"], [])
	changed.unit_properties["faction_folder"] = "change_disciples"   # the faction whose map entry gives it primitive Stealth
	assert_array(CoreSlice.refusals(changed, true)).is_empty()
	# OD-H8: Teleport / Ethereal / plain Infiltrate left the ledger group (real-activation probe, core_ledger_lift_door_test.gd); the Surprise Attack
	# burst, an Infiltrate-primitive entry, stays refused by NAME (it rolls twice with the door on).
	var teleporter := _unit(["Teleport"], [])
	teleporter.unit_properties["faction_folder"] = "elven_jesters"   # a faction whose map gives Teleport its primitive
	assert_array(CoreSlice.refusals(teleporter)).is_empty()
	var surprise := _unit(["Surprise Attack"], [])
	surprise.unit_properties["faction_folder"] = "alien_hives"
	assert_array(CoreSlice.refusals(surprise)).is_equal(["unit_rule:Surprise Attack"])
	assert_bool(CoreSlice.takes(_unit(["Tough(3)"], [["AP(1)"]]))).is_true()
	# HR-POS brought the after-volley step back through the delta (`positions`); lane shootfix refused the shooter again (group
	# `hit_and_run_landing`: the core's rigid step lands bases inside other units, the door has no landing check). Shot at it is taken.
	var raider := _unit(["Hit & Run"], [["AP(1)"]])
	raider.unit_properties["faction_folder"] = "dao_union"   # a faction whose map gives Hit & Run its primitive
	assert_array(CoreSlice.refusals(raider)).is_equal(["unit_rule:Hit & Run"])
	assert_array(CoreSlice.refusals(raider, true)).is_empty()
	# An Indirect weapon (lifted after #2939/#2942/#2947) and a joined hero are taken (the lone-hero target, epoch 81).
	assert_bool(CoreSlice.takes(_unit([], [["Indirect"]]))).is_true()   # lifted with #2939 / #2942 / #2947
	var host := _unit(["Tough(3)"], [["AP(1)"]])
	EquipmentDistributor.attach_hero_to_unit(_unit(["Hero"], []), host)
	assert_array(CoreSlice.refusals(host, true)).not_contains(["attached"])
	assert_bool(CoreSlice.takes(_unit(["No Such Rule"], []))).is_true()   # unmapped_inert: a name no map knows
	assert_int((CoreSlice.config()["primitives"] as Dictionary).size()).override_failure_message(
		"the deny list only shrinks (ceiling %d)" % DENY_CEILING).is_less_equal(DENY_CEILING)
	OS.unset_environment("NML_CORE_SLICE")
	CoreSlice.reset_cache()


## DLINES2 19.11. (lead rule: a missing line blocks the door): every rule whose table line the door omits is refused by its primitive (a
## `rule_line` group of the deny file) or by name, so the table resolves a volley that carries one. `rep` = [rule name, faction folder, label
## the slice reports]; the name is a real registry entry of that faction, so the refusal comes from the file, not from the name alone. Controls:
## the fixed families (Blast, Deadly alone, Reliable, Surge, Sturdy, a Bane WEAPON alias) and a plain unit stay taken.
## RED: drop a group from the file -> its row reads [] (the door takes it).
func test_deny_mode_refuses_the_rules_whose_table_line_the_door_omits() -> void:
	OS.set_environment("NML_CORE_SLICE", "deny")
	CoreSlice.reset_cache()
	var rep: Array = [
		["Grounded Protection", "soul_snatcher_cults"], ["Protection Feat", "alien_hives"],
	]
	for row in rep:
		var as_unit := _unit([row[0]], [[]])
		if row[1] != "":
			as_unit.unit_properties["faction_folder"] = row[1]
		assert_array(CoreSlice.refusals(as_unit)).override_failure_message("%s as a unit rule is taken, its line is missing on the door" % row[0]).is_equal(["unit_rule:" + row[0]])
		assert_array(CoreSlice.refusals(as_unit, true)).override_failure_message("%s on a target is taken" % row[0]).is_equal(["unit_rule:" + row[0]])
		var as_weapon := _unit([], [[row[0]]])
		if row[1] != "":
			as_weapon.unit_properties["faction_folder"] = row[1]
		assert_array(CoreSlice.refusals(as_weapon)).override_failure_message("%s as a weapon rule is taken" % row[0]).is_equal(["weapon_rule:" + row[0]])
	for kept in [["Blast(3)"], ["Reliable"], ["Surge when Shooting"], ["Rending"], ["Sturdy"], ["Slayer"], ["Tough(3)"]]:
		assert_bool(CoreSlice.takes(_unit(kept, [["AP(1)"]]))).override_failure_message("%s stays on the core" % kept[0]).is_true()
	# H-17b: Armor left with its line (`<U> has Armor(X): counts as Defense X+`, door_lines_defense_test.gd).
	# Train 2 (lines said, groups lifted): the Ranged Shrouding range cut, the Bane re-roll named by plain Bane / Lacerate / the unit-level aliases, the
	# Shielded and Fortified lines, the plain Regeneration group's roll.
	for lifted in [["Ranged Shrouding", "custodian_brothers"], ["Bane", ""], ["Lacerate", "battle_brothers"], ["Anti-Regen", ""],
			["Mischievous", "goblin_reclaimers"], ["Vicious", "goblin_reclaimers"], ["Unstoppable when Shooting", ""],
			["Shielded", "battle_brothers"], ["Fortified", "alien_hives"], ["Regeneration", ""], ["Regeneration Aura", "alien_hives"],
			["Shred", ""], ["Warbound", "war_disciples"], ["Self-Repair", "robot_legions"], ["Resistance", "alien_hives"], ["Plaguebound", "plague_disciples"],
			["Artillery", ""], ["Stealth", ""], ["Evasive", "battle_brothers"], ["Aircraft", ""],
			["Precision Fighter", ""], ["Instinctive", "goblin_reclaimers"], ["Takedown", ""], ["Armor", ""]]:
		var lifted_unit := _unit([lifted[0]], [[lifted[0]]])
		if lifted[1] != "":
			lifted_unit.unit_properties["faction_folder"] = lifted[1]
		assert_bool(CoreSlice.takes(lifted_unit, true)).override_failure_message("%s says its line on the door now (train 2)" % lifted[0]).is_true()
		assert_bool(CoreSlice.takes(lifted_unit)).override_failure_message("%s as a unit and weapon rule stays on the core" % lifted[0]).is_true()
	var smash := _unit([], [["Smash"]])
	smash.unit_properties["faction_folder"] = "battle_brothers"   # a Bane WEAPON alias: the core says its line (dlines 3)
	assert_bool(CoreSlice.takes(smash)).override_failure_message("a Bane weapon alias stays on the core").is_true()
	OS.unset_environment("NML_CORE_SLICE")
	CoreSlice.reset_cache()


## DLINES2 lift (epoch 95): a Deadly (or Takedown) weapon beside another ranged weapon is taken as a shooter. The core lands Deadly inline from 94 and
## says `Simultaneous fire` and Blast's cap note, keeps the declared Defense (95), and stops the ignore dice once the target is dead (95); the roster
## sweep (1000 and 2000 pt, 5 seeds) took every such row and found it equal. The group `door_omits_simultaneous_fire_line` left the deny file.
## RED: put the group and the predicate back -> the first assertion reads ["deadly_beside_other_weapons"].
func test_deny_mode_takes_a_deadly_weapon_beside_another_ranged_weapon() -> void:
	OS.set_environment("NML_CORE_SLICE", "deny")
	CoreSlice.reset_cache()
	var both := _ranged_unit([["Deadly(3)"], ["AP(1)"]])
	assert_array(CoreSlice.refusals(both)).override_failure_message("a Deadly weapon beside another one is taken since the lift").is_empty()
	assert_array(CoreSlice.refusals(both, true)).override_failure_message("as a target the weapons do not matter").is_empty()
	assert_bool(CoreSlice.takes(_ranged_unit([["Takedown"], ["AP(1)"]]))).override_failure_message("Takedown beside another ranged weapon is taken too").is_true()
	var host := _ranged_unit([["AP(1)"]])
	var hero := _ranged_unit([["Deadly(3)"]])
	EquipmentDistributor.attach_hero_to_unit(hero, host)
	assert_array(CoreSlice.refusals(host)).override_failure_message("the hero's Deadly gun in the host's volley is taken").is_empty()
	OS.unset_environment("NML_CORE_SLICE")
	CoreSlice.reset_cache()


## Epoch 95 lift: the deny file names neither the simultaneous-fire group nor the die-bearer guard any more. RED: put either block back into the file.
func test_the_deny_file_names_no_simultaneous_fire_or_die_bearer_group() -> void:
	var committed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CoreSlice.DENY_PATH))
	assert_array((committed["groups"] as Dictionary).keys()).override_failure_message("both groups left the deny file at the epoch 95 lift") \
		.not_contains(["door_omits_simultaneous_fire_line", "unpredictable_die_without_weapon_in_reach"])


## A unit whose `ranged` weapons have range 24 and whose `melee` ones range 0.
func _ranged_unit(ranged: Array, melee: Array = []) -> GameUnit:
	var gu := _unit([], ranged)
	for w in (gu.source_data as OPRApiClient.OPRUnit).weapons:
		w.range_value = 24
	for rules in melee:
		var w := OPRApiClient.OPRWeapon.new()
		w.special_rules.assign(rules)
		(gu.source_data as OPRApiClient.OPRUnit).weapons.append(w)
	return gu


## C-19: with NO env the AI door's slice is the deny-list; `NML_CORE_SLICE=allow` (or `plain`) is the way back to the shipped
## allow file, any other value (`deny`, a typo) is the default. RED on main (before C-19): unset read the allow file -> mode
## "allow", and a unit with automated rules (Tough, AP) is refused. The startup line names the mode in use.
func test_the_ai_door_reads_the_deny_list_unless_the_way_back_is_asked_for() -> void:
	var ruled := _unit(["Tough(3)"], [["AP(1)"]])
	OS.unset_environment("NML_CORE_SLICE")
	CoreSlice.reset_cache()
	assert_str(str(CoreSlice.config()["mode"])).override_failure_message("no env: the default slice is not the deny-list").is_equal("deny")
	assert_bool(CoreSlice.takes(ruled)).override_failure_message("no env: a unit with automated rules stays on the table").is_true()
	assert_str(CoreSlice.mode_line()).contains("AI door deny (core_slice_deny.json)").contains("NML_CORE_SLICE=allow")
	for raw in ["allow", "ALLOW", "plain"]:
		OS.set_environment("NML_CORE_SLICE", raw)
		CoreSlice.reset_cache()
		assert_str(str(CoreSlice.config()["mode"])).override_failure_message("NML_CORE_SLICE=%s is the way back to allow" % raw).is_equal("allow")
		assert_bool(CoreSlice.takes(ruled)).override_failure_message("the way back refuses a unit with rules").is_false()
		assert_str(CoreSlice.mode_line()).contains("AI door allow (core_slice_allow.json)")
	for raw in ["deny", "typo", ""]:
		OS.set_environment("NML_CORE_SLICE", raw)
		CoreSlice.reset_cache()
		assert_str(str(CoreSlice.config()["mode"])).override_failure_message("NML_CORE_SLICE='%s' must read the deny-list" % raw).is_equal("deny")
	OS.unset_environment("NML_CORE_SLICE")
	CoreSlice.reset_cache()


## H-30 (DS-109): the HUMAN door reads the live slice, the AI door's own: with no env the deny-list takes a unit with rules for
## both doors; `NML_CORE_SLICE=allow` (the way back) refuses it for both; a test seam (`path_override`) is read by both.
## RED (the human door keeps the allow file): the unset case refuses the unit and the startup line names the allow file.
func test_the_human_door_reads_the_live_slice_like_the_ai_door() -> void:
	var ruled := _unit(["Tough(3)"], [["AP(1)"]])
	OS.unset_environment("NML_CORE_SLICE")
	CoreSlice.reset_cache()
	assert_bool(CoreSlice.takes(ruled)).override_failure_message("AI door, no env").is_true()
	assert_bool(CoreSlice.takes_human(ruled)).override_failure_message("human door, no env: the deny-list takes it").is_true()
	assert_array(CoreSlice.refusals_human(ruled)).is_empty()
	assert_bool(CoreSlice.takes_human(ruled, true)).override_failure_message("human door, target").is_true()
	assert_str(CoreSlice.human_path()).is_equal(CoreSlice.live_path())
	assert_str(CoreSlice.mode_line()).contains("human door deny (core_slice_deny.json)")
	OS.set_environment("NML_CORE_SLICE", "allow")
	CoreSlice.reset_cache()
	assert_bool(CoreSlice.takes_human(ruled)).override_failure_message("the way back refuses it for the human door too").is_false()
	assert_array(CoreSlice.refusals_human(ruled)).is_equal(["unit_rule:Tough", "weapon_rule:AP"])
	assert_str(CoreSlice.mode_line()).contains("human door allow (core_slice_allow.json)")
	OS.unset_environment("NML_CORE_SLICE")
	_allow({}, "deny")   # a test seam is read by both doors
	assert_bool(CoreSlice.takes_human(ruled)).override_failure_message("the seam's slice is the human door's too").is_true()


## C-19: the way back is the shipped file exactly (what `allow` reads is the old slice: the move-through group, nothing else).
func test_the_way_back_reads_the_shipped_allow_file() -> void:
	OS.set_environment("NML_CORE_SLICE", "allow")
	CoreSlice.reset_cache()
	var prims := (CoreSlice.config()["primitives"] as Dictionary).keys()
	prims.sort()
	assert_array(prims).is_equal(["Crossing Attack", "Strafing"])
	OS.unset_environment("NML_CORE_SLICE")
	CoreSlice.reset_cache()


## H-15 (Plan H): Experimental Tinctures left `deny_names` (ds/h_probe_experimental_tinctures.md; core_deny_lift_door_test.gd rows). The check can fail without editing the
## committed file: a COPY of the deny file with the name put back refuses a bearer (as a shooter and as a target), the committed file takes both.
func test_putting_experimental_tinctures_back_refuses_the_bearer() -> void:
	var copy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CoreSlice.DENY_PATH))
	(copy["deny_names"] as Dictionary)["Experimental Tinctures"] = "put back for the check"
	var tmp := "user://deny_with_experimental_tinctures.json"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	f.store_string(JSON.stringify(copy))
	f.close()
	var bearer := _unit(["Experimental Tinctures"], [[]])
	for as_target in [false, true]:
		assert_array(CoreSlice.refusals_in(CoreSlice.DENY_PATH, bearer, as_target)).override_failure_message("the committed file refuses Experimental Tinctures").is_empty()
		assert_array(CoreSlice.refusals_in(tmp, bearer, as_target)).override_failure_message("the copy with the name does not refuse it: the check cannot fail").is_equal(["unit_rule:Experimental Tinctures"])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))


## LD-6 (18.11.): the deny list's EQUAL-probe names leave in one batch. Each name's volley replays equal 16/16
## (wave1116/ds/probe_*.md) and its state comes back from the core (STATE_DELTA_INVENTORY). RED on the old list:
## every name below is refused by its primitive; the failure message names it.
func test_deny_mode_takes_the_lifted_equal_probes() -> void:
	OS.set_environment("NML_CORE_SLICE", "deny")
	CoreSlice.reset_cache()
	var unit_rules := {"Unstoppable when Shooting": "",
		"Guarded": "blessed_sisters", "Piercing Tag": "alien_hives", "Vengeance": "eternal_dynasty"}
	for name in unit_rules:
		var gu := _unit([name], [])
		gu.unit_properties["faction_folder"] = unit_rules[name]
		assert_bool(CoreSlice.takes(gu)).override_failure_message(
			"deny mode takes a unit that carries %s" % name).is_true()
	# DLINES3: Tear was refused for its missing conditional-AP line (dlines_gap row 11); H-17a: the door says it now (door_lines_hit_roll_test), the group is gone.
	# Lifted again (C-19): the soak's unequal volley was a shot at base contact the table read as melee, not Point-Blank
	# Surge (surge_contact_door_test.gd, 16/16 equal through the door in deny mode after the table fix).
	var sisters := _unit(["Point-Blank Surge"], [])
	sisters.unit_properties["faction_folder"] = "blessed_sisters"
	assert_bool(CoreSlice.takes(sisters)).override_failure_message(
		"deny mode takes a unit that carries Point-Blank Surge").is_true()
	OS.unset_environment("NML_CORE_SLICE")
	CoreSlice.reset_cache()


## LIFT92 (20.11.): the Growth Markers family leaves the ledger group once the door says its four lines (the AP, the Defense bonus, Fortified
## Growth's cut, the Frenzy kill marker: door_lines_growth_test.gd) - its dice, end state and ledger were equal on the door already. Each row is
## [game system, faction folder, rule]; the folder is the map that gives the rule its primitive. Teleport and Infiltrate left with OD-H8 (the Surprise Attack burst stays refused by name).
## RED on the old list: every family name below is refused by its primitive.
func test_deny_mode_takes_the_growth_markers_family() -> void:
	OS.set_environment("NML_CORE_SLICE", "deny")
	CoreSlice.reset_cache()
	for c in [["gf", "alien_hives", "Piercing Growth"], ["gf", "infected_colonies", "Precision Growth"], ["gf", "human_inquisition", "Defensive Growth"],
			["aof", "daemons_of_plague", "Fortified Growth"], ["aof", "dark_elves", "Piercing Frenzy"], ["aof", "dwarves", "Precision Frenzy"],
			["aof", "daemons_of_war", "Defensive Frenzy"], ["aof", "dark_elves", "Regenerative Strength"]]:
		var bearer := _unit([c[2]], [["AP(1)"]])
		bearer.unit_properties["game_system"] = c[0]
		bearer.unit_properties["faction_folder"] = c[1]
		assert_array(CoreSlice.refusals(bearer)).override_failure_message("deny mode takes a unit that carries %s" % c[2]).is_empty()
		assert_array(CoreSlice.refusals(bearer, true)).override_failure_message("deny mode takes a target that carries %s" % c[2]).is_empty()
	var teleporter := _unit(["Teleport"], [])
	teleporter.unit_properties["faction_folder"] = "elven_jesters"
	assert_array(CoreSlice.refusals(teleporter)).is_empty()   # OD-H8: lifted with the ledger group
	OS.unset_environment("NML_CORE_SLICE")
	CoreSlice.reset_cache()


## BEATS (19.11.): a unit that carries a pre-attack beat rule (main.gd, the block between the casts and the volley) stays on
## the table in deny mode: the table resolves the beat, and a core that took the activation would resolve it a second time
## from its stale capture (door probe on one real AI activation: Mend 8/8, Breath Attack 8/8, Mind Control, Storm Attack,
## Reckless Piercing, a Utility Buff once-record). Each case is [system, faction folder, rule]; the faction folder is the map
## that gives the rule its primitive. Piercing Tag stays taken (LD-6, measured equal through the door). RED: take the group
## out of assets/solo/core_slice_deny.json -> every case below is taken instead of refused.
func test_deny_mode_refuses_the_pre_attack_beat_bearers() -> void:
	OS.set_environment("NML_CORE_SLICE", "deny")
	CoreSlice.reset_cache()
	var cases := [
		["aof", "daemons_of_war", "Reckless Piercing"], ["gf", "human_defense_force", "Precision Shooter Buff"],
		["gf", "jackals", "Precision Tag"], ["gf", "battle_brothers", "Re-Position Artillery"]]
	for c in cases:
		var bearer := _unit([c[2], "Tough(3)"], [["AP(1)"]])
		bearer.unit_properties["game_system"] = c[0]
		bearer.unit_properties["faction_folder"] = c[1]
		assert_array(CoreSlice.refusals(bearer)).override_failure_message(
			"%s (%s/%s) must stay on the table in deny mode" % [c[2], c[0], c[1]]).is_equal(["unit_rule:" + c[2]])
		# H-9a: the beat is the bearer's own act, so a bearer SHOT AT is taken (the group's side is the shooter; probe ds/h_probe_beat_targets.md).
		assert_array(CoreSlice.refusals(bearer, true)).override_failure_message(
			"%s (%s/%s) as a target does not act in the volley" % [c[2], c[0], c[1]]).is_empty()
	# H-9b: the Utility Buff names probed equal through real activations leave the group by name (`lifted_names`); the rest of the family stays refused.
	for lifted in [["gf", "eternal_dynasty", "Casting Buff"], ["gf", "blessed_sisters", "Courage Buff"], ["gf", "dwarf_guilds", "Speed Debuff"],
			["gf", "blessed_sisters", "Precision Fighter Buff"], ["gf", "robot_legions", "Unstoppable when Shooting Aura"],
			["gf", "dark_elf_raiders", "Regeneration Buff"], ["gf", "alien_hives", "Furious Buff"], ["gf", "custodian_brothers", "Shred Mark"],
			["gf", "daemons_of_lust", "Quick Shot Mark"], ["gf", "eternal_dynasty", "Increased Shooting Range Mark"]]:
		var buffer := _unit([lifted[2], "Tough(3)"], [["AP(1)"]])
		buffer.unit_properties["game_system"] = lifted[0]
		buffer.unit_properties["faction_folder"] = lifted[1]
		assert_array(CoreSlice.refusals(buffer)).override_failure_message("%s was probed equal through the door and leaves the group" % lifted[2]).is_empty()
	# H-5 / H-6: Mend and Breath Attack left the group (the beats guard hands their beat to the core's one call), so their bearers are taken.
	var mender := _unit(["Mend", "Tough(3)"], [["AP(1)"]])
	mender.unit_properties["faction_folder"] = "battle_brothers"
	assert_array(CoreSlice.refusals(mender)).override_failure_message("Mend is guarded, not denied, from H-5").is_empty()
	# The same unit without the beat rule is taken (the group refuses the rule, not the faction).
	var plain := _unit(["Tough(3)"], [["AP(1)"]])
	plain.unit_properties["faction_folder"] = "battle_brothers"
	assert_array(CoreSlice.refusals(plain)).is_empty()
	# A joined hero's beat rule keeps its host on the table (deny mode reads the hero's rules too).
	var host := _unit(["Tough(3)"], [["AP(1)"]])
	host.unit_properties["faction_folder"] = "battle_brothers"
	var healer := _unit(["Hero", "Precision Tag"], [])
	healer.unit_properties["faction_folder"] = "jackals"
	EquipmentDistributor.attach_hero_to_unit(healer, host)
	assert_array(CoreSlice.refusals(host)).contains(["unit_rule:Precision Tag"])
	assert_array(CoreSlice.refusals(host, true)).override_failure_message("the same host shot at: the hero's Precision Tag does not act in the volley").is_empty()
	OS.unset_environment("NML_CORE_SLICE")
	CoreSlice.reset_cache()


## A joined unit whose own models are all dead is shot as its living hero ("Hero: X is the unit now"). The core's lone-hero target
## exists from EPOCH_83_LONE_HERO_TARGET and its step path says the table's lines for it (test/one_core/core_lone_hero_door_test.gd), so
## deny mode refuses such a TARGET below 83 only (a replay stamp; v36/g4r5_r8_lonehero_retarget_test and g4r5_r8b_lonehero_nearest_test pin 73).
## A host with a living model, a dead hero or a shooter is untouched at every epoch.
## RED: refuse at every epoch -> the 83 and current-epoch assertions read ["lone_hero_target"]; drop the epoch gate -> the 82 leg reads [].
func test_deny_mode_takes_a_lone_hero_target_from_83() -> void:
	var epoch_before := AiActRecorder.rules_epoch
	OS.set_environment("NML_CORE_SLICE", "deny")
	CoreSlice.reset_cache()
	var host := _unit(["Tough(3)"], [["AP(1)"]])
	var hero := _unit(["Hero"], [])
	EquipmentDistributor.attach_hero_to_unit(hero, host)
	var hm := ModelInstance.new()
	hm.is_alive = true
	hero.models.append(hm)
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_83_LONE_HERO_TARGET - 1
	assert_array(CoreSlice.refusals(host, true)).override_failure_message("below 83: a lone hero stays on the table").is_equal(["lone_hero_target"])
	assert_bool(CoreSlice.takes(host, true)).is_false()
	for epoch in [AiActRecorder.EPOCH_83_LONE_HERO_TARGET, epoch_before]:
		AiActRecorder.rules_epoch = epoch
		assert_array(CoreSlice.refusals(host, true)).override_failure_message("epoch %d: the core shoots it as the hero" % epoch).is_empty()
		assert_bool(CoreSlice.takes(host, true)).is_true()
	assert_array(CoreSlice.refusals(host)).override_failure_message("as a shooter it is not a target case").is_empty()
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_83_LONE_HERO_TARGET - 1
	var xm := ModelInstance.new()
	xm.is_alive = true
	host.models.append(xm)
	assert_array(CoreSlice.refusals(host, true)).override_failure_message("a host with a living model is no lone hero").is_empty()
	host.models.clear()
	hm.is_alive = false
	assert_array(CoreSlice.refusals(host, true)).override_failure_message("a dead hero is no lone hero").is_empty()
	AiActRecorder.rules_epoch = epoch_before
	OS.unset_environment("NML_CORE_SLICE")
	CoreSlice.reset_cache()


## Deny mode takes a joined hero with its unit, so a rule the hero carries is read too: a host whose only listed rule
## sits on its joined hero is refused by that rule (C-18 soak: Piercing Growth on a joined Grunt Veteran). RED: read only
## the host's own rules -> the host is taken.
func test_deny_mode_reads_the_joined_heros_rules() -> void:
	_allow({"g": ["Tear"]}, "deny")
	var host := _unit(["Tough(3)"], [["AP(1)"]])
	var hero := _unit(["Hero"], [["Tear"]])
	hero.unit_properties["faction_folder"] = "custodian_brothers"   # Tear's map entry, so the refusal is the list's
	EquipmentDistributor.attach_hero_to_unit(hero, host)
	assert_array(CoreSlice.refusals(host)).contains(["weapon_rule:Tear"])
	assert_bool(CoreSlice.takes(host, true)).is_false()


## Deny mode takes the measured inert names (no primitive, no effect on a volley): Unique, Army Standard Bearer, Courage.
## Allow mode never reads them. RED: drop the inert read -> a Unique unit is refused in deny mode.
func test_deny_mode_takes_the_inert_names() -> void:
	OS.set_environment("NML_CORE_SLICE", "deny")
	CoreSlice.reset_cache()
	assert_bool(CoreSlice.takes(_unit(["Unique", "Army Standard Bearer", "Courage"], [["AP(1)"]]))).is_true()
	OS.set_environment("NML_CORE_SLICE", "allow")   # C-19: the allow file is the way back, no longer the default
	CoreSlice.reset_cache()
	assert_array(CoreSlice.refusals(_unit(["Unique"], []))).is_equal(["unit_rule:Unique"])
	OS.unset_environment("NML_CORE_SLICE")
	CoreSlice.reset_cache()


## Deny mode takes a name no rules map knows (an upgrade's own label); allow mode still refuses it. RED: drop the unmapped
## read -> the upgrade label is refused in deny mode.
func test_deny_mode_takes_an_unmapped_upgrade_label() -> void:
	OS.set_environment("NML_CORE_SLICE", "deny")
	CoreSlice.reset_cache()
	assert_bool(CoreSlice.takes(_unit(["Some Upgrade Label"], [["AP(1)"]]))).is_true()
	OS.set_environment("NML_CORE_SLICE", "allow")   # C-19: the allow file is the way back, no longer the default
	CoreSlice.reset_cache()
	assert_array(CoreSlice.refusals(_unit(["Some Upgrade Label"], []))).is_equal(["unit_rule:Some Upgrade Label"])
	OS.unset_environment("NML_CORE_SLICE")
	CoreSlice.reset_cache()


## PLAN_DOOR_ACTIVATION_START step 2: the deny group `activation_start_twice` keeps a Reanimation SHOOTER on the table at both shoot doors and
## at the charge door (the table rolls the pool at the activation start, the core rolled it again; core_start_once_door_test.gd). The
## primitive reaches a unit that gets the rule from a joined hero's Reanimation Aura (the import copies it onto the host and the hero).
## Shot at, a bearer is taken (it does not activate in the shooter's volley); a Bounding bearer stays taken (measured equal: the core refuses
## a bonus move and the table resolves it). RED: drop the group -> the bearers read [] as shooters.
func test_deny_mode_refuses_an_activation_start_bearer_as_shooter() -> void:
	OS.set_environment("NML_CORE_SLICE", "deny")
	CoreSlice.reset_cache()
	for c in [["gf", "robot_legions"], ["aof", "vampiric_undead"]]:
		var bearer := _unit(["Reanimation", "Tough(3)"], [["AP(1)"]])
		bearer.unit_properties["game_system"] = c[0]
		bearer.unit_properties["faction_folder"] = c[1]
		assert_array(CoreSlice.refusals(bearer)).override_failure_message("%s/%s Reanimation shooter" % c).is_equal(["unit_rule:Reanimation"])
		assert_array(CoreSlice.refusals(bearer, true)).override_failure_message("%s/%s Reanimation target" % c).is_empty()
		assert_array(CoreSlice.melee_refusals(bearer, false, true)).override_failure_message("%s/%s Reanimation charger" % c).is_equal(["unit_rule:Reanimation"])
	# A host without the rule, joined by a hero with Reanimation Aura: the import's aura pass gives both Reanimation.
	var host := _unit(["Tough(3)"], [["AP(1)"]])
	var hero := _unit(["Hero", "Reanimation Aura"], [])
	for u in [host, hero]:
		u.unit_properties["faction_folder"] = "robot_legions"
	EquipmentDistributor.attach_hero_to_unit(hero, host)
	assert_array(CoreSlice.refusals(host)).override_failure_message("before the aura pass nothing names Reanimation").is_empty()
	OPRArmyManager.expand_auras_of([host.source_data], {host.source_data: host})
	assert_array(CoreSlice.refusals(host)).override_failure_message("an Aura-granted host is refused").contains(["unit_rule:Reanimation"])
	assert_array(CoreSlice.refusals(host, true)).override_failure_message("the same host shot at is taken").is_empty()
	var jumper := _unit(["Bounding"], [["AP(1)"]])
	jumper.unit_properties["faction_folder"] = "eternal_dynasty"
	assert_array(CoreSlice.refusals(jumper)).override_failure_message("Bounding was measured equal and stays taken").is_empty()
	OS.unset_environment("NML_CORE_SLICE")
	CoreSlice.reset_cache()


## Lane shootfix (containment): the deny group `hit_and_run_landing` keeps every SHOOTER whose rule reaches the core's Hit & Run step after a
## volley on the table at the shoot doors (the core's rigid step lands bases inside other units; core_hit_and_run_door_test.gd). Shot at, a
## bearer is taken (it does not step in that volley). Hit & Run Fighter steps only after melee: taken as a shooter, refused as a charger by the
## melee file's group. RED: drop the group -> the shooters read [].
func test_deny_mode_refuses_a_hit_and_run_family_shooter() -> void:
	OS.set_environment("NML_CORE_SLICE", "deny")
	CoreSlice.reset_cache()
	for c in [["Harassing", "dark_elf_raiders"], ["Enhanced Harassing", "dark_elf_raiders"], ["Guerrilla", "rebel_guerrillas"],
			["Hit & Run", "custodian_brothers"], ["Hit & Run Shooter", "custodian_brothers"]]:
		var bearer := _unit([c[0]], [["AP(1)"]])
		bearer.unit_properties["faction_folder"] = c[1]
		assert_array(CoreSlice.refusals(bearer)).override_failure_message("%s shooter" % c[0]).is_equal(["unit_rule:%s" % c[0]])
		assert_array(CoreSlice.refusals(bearer, true)).override_failure_message("%s target" % c[0]).is_empty()
	var fighter := _unit(["Hit & Run Fighter"], [["AP(1)"]])
	fighter.unit_properties["faction_folder"] = "alien_hives"
	assert_array(CoreSlice.refusals(fighter)).override_failure_message("a Fighter-only bearer does not step after a volley").is_empty()
	assert_array(CoreSlice.melee_refusals(fighter, false, true)).override_failure_message("Hit & Run Fighter charger").is_equal(["unit_rule:Hit & Run Fighter"])
	OS.unset_environment("NML_CORE_SLICE")
	CoreSlice.reset_cache()


## Plan E step 2: the melee deny slice (`MELEE_DENY_PATH`, mode "deny", door "melee") sits beside the allow file.
## A unit with AP(1) is refused by the allow file (`deny = false`, default) and taken by the deny file (`deny = true`),
## as charger and as target; inert names and unmapped upgrade labels pass in deny mode; joined heroes stay refused
## (`attached_heroes`), while a standalone Hero passes. Reading the melee deny file does not disturb the live shoot slice.
## RED: `melee_refusals` ignores `deny` (reads MELEE_PATH) or `config()` rejects MELEE_DENY_PATH's door -> AP is refused.
func test_the_melee_deny_slice_takes_ap_and_refuses_attachments() -> void:
	var raw := FileAccess.get_file_as_string(CoreSlice.MELEE_DENY_PATH) if FileAccess.file_exists(CoreSlice.MELEE_DENY_PATH) else ""
	var parsed: Variant = JSON.parse_string(raw) if not raw.is_empty() else null
	var data: Dictionary = parsed if parsed is Dictionary else {}
	assert_bool(parsed is Dictionary).override_failure_message("%s unreadable" % CoreSlice.MELEE_DENY_PATH).is_true()
	assert_str(str(data.get("schema"))).is_equal(CoreSlice.SCHEMA)
	assert_str(str(data.get("door"))).is_equal("melee")
	assert_str(str(data.get("mode"))).is_equal("deny")
	assert_bool(bool(data.get("unmapped_inert", false))).is_true()
	assert_array((data.get("inert", {}) as Dictionary).keys()).contains(["Unique", "Army Standard Bearer", "Courage"])
	assert_array((data.get("deny_names", {}) as Dictionary).keys()).is_equal(["Angelic Blessing", "Unmovable", "Power Shrooms", "Cleric", "Furious Buff", "Precision Attacks Buff", "Hold the Line", "Destroyer"])
	assert_array((data.get("groups", {}) as Dictionary).keys()).is_equal(["attached_heroes", "unpredictable_fighter_die", "strafing_not_in_melee", "evasive_to_hit_line",
		"breath_attack_dice_in_melee", "ravage_line", "armor_line", "hit_and_run_landing", "ambush_flying_landing", "activation_start_twice"])
	for g in (data["groups"] as Dictionary):
		assert_str(str(data["groups"][g].get("why", ""))).override_failure_message("group %s names its measurement" % g).is_not_empty()
		assert_str(str(data["groups"][g].get("leaves_with", ""))).override_failure_message("group %s names what lifts it" % g).is_not_empty()
	var ap := _unit([], [["AP(1)"]])
	assert_array(CoreSlice.melee_refusals(ap)).is_equal(["weapon_rule:AP"])
	assert_array(CoreSlice.melee_refusals(ap, true, false)).is_equal(["weapon_rule:AP"])
	assert_array(CoreSlice.melee_refusals(ap, false, true)).override_failure_message("melee deny must take AP charger").is_empty()
	assert_array(CoreSlice.melee_refusals(ap, true, true)).override_failure_message("melee deny must take AP target").is_empty()
	assert_array(CoreSlice.melee_refusals(_unit(["Unique", "Army Standard Bearer", "Courage", "Some Upgrade Label"], [["AP(1)"]]), false, true)).is_empty()
	assert_array(CoreSlice.melee_refusals(_unit(["Hero"], [["AP(1)"]]), false, true)).override_failure_message("standalone Hero is taken").is_empty()
	var host := _unit(["Tough(3)"], [["AP(1)"]])
	var hero := _unit(["Hero"], [])
	EquipmentDistributor.attach_hero_to_unit(hero, host)
	assert_array(CoreSlice.melee_refusals(host, false, true)).is_equal(["attached"])
	assert_array(CoreSlice.melee_refusals(hero, true, true)).is_equal(["attached"])
	assert_array(CoreSlice.melee_refusals(_unit([], [["Unpredictable Fighter"]]), false, true)).override_failure_message("an Unpredictable Fighter weapon is refused in the deny view").is_not_empty()
	assert_array(CoreSlice.melee_refusals(_unit(["Armor(1)"], [["AP(1)"]]), false, true)).override_failure_message("an Armor unit is refused in the deny view").is_not_empty()
	assert_array(CoreSlice.melee_refusals(_unit(["Angelic Blessing"], [["AP(1)"]]), true, true)).override_failure_message("a denied name is refused on the target side").is_not_empty()
	# melee95: Ambush and Flying on ONE charger is refused as a pair; either alone, and the pair on a target, are taken.
	assert_array(CoreSlice.melee_refusals(_unit(["Ambush", "Flying"], [["AP(1)"]]), false, true)).override_failure_message("an Ambush + Flying charger is refused").is_equal(["ambush_flying_landing"])
	assert_array(CoreSlice.melee_refusals(_unit(["Ambush"], [["AP(1)"]]), false, true)).override_failure_message("Ambush alone is taken").is_empty()
	assert_array(CoreSlice.melee_refusals(_unit(["Flying"], [["AP(1)"]]), false, true)).override_failure_message("Flying alone is taken").is_empty()
	assert_array(CoreSlice.melee_refusals(_unit(["Ambush", "Flying"], [["AP(1)"]]), true, true)).override_failure_message("the pair on a target is taken").is_empty()
	OS.set_environment("NML_CORE_SLICE", "allow")
	CoreSlice.reset_cache()
	assert_array(CoreSlice.melee_refusals(ap, false, true)).is_empty()
	assert_str(str(CoreSlice.config()["mode"])).is_equal("allow")
	OS.unset_environment("NML_CORE_SLICE")
	CoreSlice.reset_cache()


## `applies` reads only these two members (the census test's stub).
class _StubMain extends RefCounted:
	var solo_ai_slots := {1: true}
	func _online_turn_room() -> bool:
		return false


## DLINES2: `SlicePin.dice_only()` is the production deny list minus its line refusals - the helper the dice parity tests read. RED: if it kept the
## `rule_line` groups the Grounded Protection row below is refused; if it dropped every refusal Surprise Attack (a DICE difference: its burst rolls twice) would be taken.
func test_the_dice_only_slice_drops_the_line_refusals_and_keeps_the_dice_ones() -> void:
	var self_repair := _unit(["Grounded Protection"], [])
	self_repair.unit_properties["faction_folder"] = "soul_snatcher_cults"
	SlicePin.dice_only()
	assert_bool(CoreSlice.takes(self_repair, true)).override_failure_message("Grounded Protection's missing line is not a dice difference").is_true()
	assert_bool(CoreSlice.takes(_unit(["Shred"], []), true)).override_failure_message("Shred's missing line is not a dice difference").is_true()
	assert_bool(CoreSlice.takes(_unit(["Surprise Attack"], []), true)).override_failure_message("Surprise Attack changes the dice: still refused").is_false()
	SlicePin.release_dice_only()
	assert_bool(CoreSlice.takes(self_repair, true)).override_failure_message("the production list refuses Grounded Protection again").is_false()


## DLINES3: a weapon's own Shred beside a unit-level Shred rule of another name is two rules in the table (R-1 A2) and one in the core: the target's
## wounds differ (found by the Shred door test, 5 of 12 seeds), so the deny file refuses it by predicate. Controls: either alone, or the plain
## unit-level Shred beside the weapon's (one group), stay taken; the dice-only pin keeps the refusal (a state difference, not a missing line).
func test_an_own_shred_beside_an_alias_is_refused() -> void:
	OS.set_environment("NML_CORE_SLICE", "deny")
	CoreSlice.reset_cache()
	var both := _unit(["Warbound"], [["Shred"]])
	both.unit_properties["faction_folder"] = "war_disciples"
	assert_array(CoreSlice.refusals(both)).is_equal(["own_shred_beside_alias"])
	assert_bool(CoreSlice.takes(both, true)).override_failure_message("a target is not refused for what it would fire").is_true()
	var alias_only := _unit(["Warbound"], [["AP(1)"]])
	alias_only.unit_properties["faction_folder"] = "war_disciples"
	assert_bool(CoreSlice.takes(alias_only)).is_true()
	assert_bool(CoreSlice.takes(_unit([], [["Shred"]]))).is_true()
	var same_group := _unit(["Shred"], [["Shred"]])
	assert_bool(CoreSlice.takes(same_group)).override_failure_message("the plain unit-level Shred is the weapon's own group").is_true()
	SlicePin.dice_only()
	assert_array(CoreSlice.refusals(both)).override_failure_message("a state difference stays refused in the dice-only slice").is_equal(["own_shred_beside_alias"])
	SlicePin.release_dice_only()
	OS.unset_environment("NML_CORE_SLICE")
	CoreSlice.reset_cache()


## DLINES train 4 (DS-GHITN part 3): refuse BY STATE (not by rule name) any activation whose ledger carries a shooting
## spell-token hit modifier or Vengeance markers. Both ways: a plain unit (or a Vengeance carrier with 0 markers, or a unit
## with a non-hit / melee-only / opposite-side spell record) stays taken; a live shooting hit spell or Vengeance markers > 0
## is refused on the affected side (including through a joined hero).
func test_state_refusals_for_spell_hit_modifiers_and_vengeance_markers() -> void:
	OS.set_environment("NML_CORE_SLICE", "deny")
	CoreSlice.reset_cache()
	var shooter := _unit([], [["AP(1)"]])
	var target := _unit(["Vengeance"], [])
	target.unit_properties["faction_folder"] = "eternal_dynasty"
	# Without live state, both are taken (Vengeance is NOT refused by rule name).
	assert_array(CoreSlice.refusals(shooter)).is_empty()
	assert_array(CoreSlice.refusals(target, true)).is_empty()
	# Non-hit / melee-only / opposite-role spell records stay taken.
	shooter.unit_properties["spell_records"] = [
		{"spell": "Iron Skin", "def_mod": 1, "scope": "all"},
		{"spell": "Fury", "hit_mod": 1, "scope": "melee"},
		{"spell": "Mark", "hit_mod": 1, "beneficiary": "attackers", "scope": "shooting"},
	]
	assert_array(CoreSlice.refusals(shooter)).override_failure_message("non-shooting / wrong-role spell must stay taken").is_empty()
	# Live attacker_own shooting hit spell refuses the shooter, not a target.
	shooter.unit_properties["spell_records"] = [{"spell": "Aim", "hit_mod": 1, "scope": "shooting"}]
	assert_array(CoreSlice.refusals(shooter)).is_equal(["spell_hit_mod"])
	assert_array(CoreSlice.refusals(shooter, true)).override_failure_message("attacker_own spell does not apply to a target").is_empty()
	# Live vs_target shooting hit spell refuses the target, not a shooter.
	target.unit_properties["spell_records"] = [{"spell": "Eagle-Eyed Focus", "hit_mod": 1, "beneficiary": "attackers", "scope": "all"}]
	assert_array(CoreSlice.refusals(target, true)).is_equal(["spell_hit_mod"])
	assert_array(CoreSlice.refusals(target)).override_failure_message("vs_target spell does not apply to a shooter").is_empty()
	target.unit_properties.erase("spell_records")
	# Vengeance markers refuse the target (> 0), not a shooter, and not when 0.
	target.unit_properties["vengeance_markers"] = 2
	assert_array(CoreSlice.refusals(target, true)).is_equal(["vengeance_markers"])
	assert_array(CoreSlice.refusals(target)).override_failure_message("Vengeance markers apply when attacked, not when shooting").is_empty()
	target.unit_properties["vengeance_markers"] = 0
	assert_array(CoreSlice.refusals(target, true)).is_empty()
	# Joined hero: shooter's hero carrying attacker_own hit spell refuses host as shooter; hero's Vengeance refuses host as target.
	var host := _unit([], [["AP(1)"]])
	var hero := _unit(["Hero"], [])
	EquipmentDistributor.attach_hero_to_unit(hero, host)
	hero.unit_properties["spell_records"] = [{"spell": "Aim", "hit_mod": -1, "scope": "all"}]
	assert_array(CoreSlice.refusals(host)).is_equal(["spell_hit_mod"])
	assert_array(CoreSlice.refusals(host, true)).is_empty()
	hero.unit_properties.erase("spell_records")
	hero.unit_properties["vengeance_markers"] = 1
	assert_array(CoreSlice.refusals(host, true)).is_equal(["vengeance_markers"])
	assert_array(CoreSlice.refusals(host)).is_empty()
	OS.unset_environment("NML_CORE_SLICE")
	CoreSlice.reset_cache()


## DLINES train 4 (review): the core latches a Versatile Attack pick on the plain Quality, the table on the MODIFIED to-hit number, so a
## Versatile shooter and any to-hit modifier in play (a Stealth / Evasive / Artillery / Aircraft target, or the shooter's own Artillery) are
## refused as a PAIR (found by the 3000 pts roster sweep once the to-hit families left the deny list: 6 volleys with different dice).
## Both ways: either side alone, a plain pair, the allow slice (no group) stay taken; the dice-only pin keeps the refusal (a state difference).
func test_a_versatile_shooter_against_a_to_hit_modifier_is_refused_as_a_pair() -> void:
	OS.set_environment("NML_CORE_SLICE", "deny")
	CoreSlice.reset_cache()
	# From the epoch 94 batch the pair is taken (see test_the_versatile_pair_is_taken_from_the_epoch_94_batch): this test pins the refusal below it.
	var epoch_before := AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_94_PARITY_BATCH - 1
	var vers := _unit(["Versatile Attack"], [[]])
	vers.unit_properties["faction_folder"] = "battle_brothers"
	var plain := _unit([], [[]])
	for rule in ["Stealth", "Evasive", "Artillery", "Aircraft"]:
		var tgt := _unit([rule], [[]])
		tgt.unit_properties["faction_folder"] = "battle_brothers"   # Evasive is a faction entry
		assert_array(CoreSlice.pair_refusals(vers, tgt)).override_failure_message("a Versatile shooter at a %s target picks on a modified number" % rule).is_equal(["versatile_pick_modified_to_hit"])
		assert_array(CoreSlice.pair_refusals(plain, tgt)).override_failure_message("no Versatile pick, nothing to differ on").is_empty()
	assert_array(CoreSlice.pair_refusals(vers, plain)).override_failure_message("a Versatile shooter at a plain target stays on the core").is_empty()
	var art_vers := _unit(["Versatile Attack", "Artillery"], [[]])
	art_vers.unit_properties["faction_folder"] = "battle_brothers"
	assert_array(CoreSlice.pair_refusals(art_vers, plain)).override_failure_message("the shooter's own Artillery modifies the number too").is_equal(["versatile_pick_modified_to_hit"])
	# H-10 (Plan H): Unpredictable Shooter's +1 to hit (the 4-6 half) is folded into the number the table latches the pick on: Vinci Tech
	# (Versatile Attack) + Unpredictable Shooter differed on 5 of 16 seeds at over 9 in. RED: take the primitive out of TO_HIT_ON_SHOOTER.
	var vinci := _unit(["Vinci Tech", "Unpredictable Shooter"], [[]])
	vinci.unit_properties["game_system"] = "aof"
	vinci.unit_properties["faction_folder"] = "duchies_of_vinci"
	assert_array(CoreSlice.pair_refusals(vinci, plain)).override_failure_message("Versatile + Unpredictable Shooter picks on a modified number").is_equal(["versatile_pick_modified_to_hit"])
	var vinci_generic := _unit(["Vinci Tech", "Unpredictable"], [[]])   # the generic "when attacking" spelling: the same die in shooting
	vinci_generic.unit_properties["game_system"] = "aof"
	vinci_generic.unit_properties["faction_folder"] = "duchies_of_vinci"
	assert_array(CoreSlice.pair_refusals(vinci_generic, plain)).override_failure_message("Versatile + Unpredictable picks on a modified number").is_equal(["versatile_pick_modified_to_hit"])
	var vinci_only := _unit(["Vinci Tech"], [[]])
	vinci_only.unit_properties["game_system"] = "aof"
	vinci_only.unit_properties["faction_folder"] = "duchies_of_vinci"
	assert_array(CoreSlice.pair_refusals(vinci_only, plain)).override_failure_message("Versatile alone stays on the core").is_empty()
	var unpredictable_only := _unit(["Unpredictable Shooter"], [[]])
	unpredictable_only.unit_properties["game_system"] = "aof"
	unpredictable_only.unit_properties["faction_folder"] = "duchies_of_vinci"
	assert_array(CoreSlice.pair_refusals(unpredictable_only, plain)).override_failure_message("no Versatile pick, nothing to differ on").is_empty()
	var host := _unit([], [[]])
	var hero := _unit(["Versatile Attack"], [])
	hero.unit_properties["faction_folder"] = "battle_brothers"
	EquipmentDistributor.attach_hero_to_unit(hero, host)
	assert_array(CoreSlice.pair_refusals(host, _unit(["Stealth"], [[]]))).override_failure_message("a joined hero's Versatile Attack picks in the host's volley").is_equal(["versatile_pick_modified_to_hit"])
	assert_array(CoreSlice.pair_refusals(vers, null)).is_empty()
	assert_array(CoreSlice.pair_refusals_in(CoreSlice.DENY_PATH, vers, _unit(["Stealth"], [[]]))).is_equal(["versatile_pick_modified_to_hit"])
	SlicePin.dice_only()
	assert_array(CoreSlice.pair_refusals(vers, _unit(["Stealth"], [[]]))).override_failure_message("a state difference stays refused in the dice-only slice").is_equal(["versatile_pick_modified_to_hit"])
	SlicePin.release_dice_only()
	SlicePin.narrow()
	assert_array(CoreSlice.pair_refusals(vers, _unit(["Stealth"], [[]]))).override_failure_message("the allow slice has no such group").is_empty()
	SlicePin.release()
	AiActRecorder.rules_epoch = epoch_before


## A slice dict a test injects through `CoreSlice._cache_by_path` (melee_morale_lines_test.gd) predates the `lifted_names` (H-9b) and `shooter_only` (H-9a) keys: the readers
## default to empty, they do not abort the engine ("Invalid access to property or key 'lifted_names'", gdUnit shard 9). RED: read both with `c["..."]` -> SCRIPT ERROR.
func test_a_cached_slice_dict_without_the_newer_keys_still_reads() -> void:
	var path := "user://slice_cache_without_newer_keys.json"
	CoreSlice._cache_by_path[path] = {"mode": "deny", "primitives": {}, "attached": false, "inert": {}, "deny_names": {}, "unmapped_inert": false}
	var tgt := _unit(["Stealth"], [[]])
	assert_array(CoreSlice.refusals_in(path, tgt, true)).override_failure_message("an empty deny slice takes a mapped rule, as target").is_empty()
	assert_array(CoreSlice.refusals_in(path, tgt)).override_failure_message("and as shooter").is_empty()
	CoreSlice._cache_by_path.erase(path)


## Plan H, H-18: from the pending epoch 94 the core's dice pick Versatile Attack on the modified to-hit number, so the pair is taken (the door test
## `versatile_pick_door_test.gd` shows both halves equal there). Below it the pair stays refused, in the dice-only pin too. RED: drop the epoch clause.
func test_the_versatile_pair_is_taken_from_the_epoch_94_batch() -> void:
	OS.set_environment("NML_CORE_SLICE", "deny")
	CoreSlice.reset_cache()
	var vers := _unit(["Versatile Attack"], [[]])
	vers.unit_properties["faction_folder"] = "battle_brothers"
	var stealth := _unit(["Stealth"], [[]])
	var epoch_before := AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_94_PARITY_BATCH - 1
	var below := CoreSlice.pair_refusals(vers, stealth)
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_94_PARITY_BATCH
	var at_pending := CoreSlice.pair_refusals(vers, stealth)
	AiActRecorder.rules_epoch = epoch_before
	assert_array(below).override_failure_message("below 94 the core still latches on the plain Quality").is_equal(["versatile_pick_modified_to_hit"])
	assert_array(at_pending).override_failure_message("from 94 both halves pick on the modified number").is_empty()


## H-18 lift (Versatile half): the deny file names no Versatile pair group any more; the pair is taken from 94 (the clause is the epoch alone, kept for
## replays under an older stamp). RED: put `door_versatile_pick_modified_to_hit` back into the file -> this fails.
func test_the_deny_file_names_no_versatile_pair_group() -> void:
	var committed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CoreSlice.DENY_PATH))
	assert_array((committed["groups"] as Dictionary).keys()).override_failure_message("the Versatile pair group left the deny file at the lift").not_contains(["door_versatile_pick_modified_to_hit"])


## DLINES train 4 (review): the table names a Takedown's picked model by its first item when it is no Tough and no special-weapon model; the core holds
## only an item count, so its line says "trooper" (door test, one Banner carrier: 12 of 12 seeds differ). A Takedown shooter at a target with a living
## item-carrying model is refused as a pair; no item, a dead carrier, no Takedown, and the dice-only pin (it drops line refusals) stay taken.
func test_a_takedown_shooter_against_an_item_carrier_is_refused_as_a_pair() -> void:
	OS.set_environment("NML_CORE_SLICE", "deny")
	CoreSlice.reset_cache()
	var sniper := _ranged_unit([["Takedown"]])
	var plain_shooter := _ranged_unit([["AP(1)"]])
	var carrier := _unit([], [[]])
	var banner := ModelInstance.new()
	banner.properties["equipment"] = ["Banner"]
	carrier.models.append(banner)
	assert_array(CoreSlice.pair_refusals(sniper, carrier)).override_failure_message("the table would say `the Banner`, the core `trooper`").is_equal(["takedown_label_equipment"])
	assert_array(CoreSlice.pair_refusals(plain_shooter, carrier)).override_failure_message("no Takedown: no label").is_empty()
	var bare := _unit([], [[]])
	bare.models.append(ModelInstance.new())
	assert_array(CoreSlice.pair_refusals(sniper, bare)).override_failure_message("no item on any model: `trooper` on both sides").is_empty()
	banner.is_alive = false
	assert_array(CoreSlice.pair_refusals(sniper, carrier)).override_failure_message("a dead carrier is no pick").is_empty()
	banner.is_alive = true
	var host := _unit([], [[]])
	host.models.append(ModelInstance.new())
	var hero := _unit(["Hero"], [])
	var hero_model := ModelInstance.new()
	hero_model.properties["equipment"] = ["Banner"]
	hero.models.append(hero_model)
	EquipmentDistributor.attach_hero_to_unit(hero, host)
	assert_array(CoreSlice.pair_refusals(sniper, host)).override_failure_message("a joined hero can be the pick").is_equal(["takedown_label_equipment"])
	SlicePin.dice_only()
	assert_array(CoreSlice.pair_refusals(sniper, carrier)).override_failure_message("a missing line is not a dice difference").is_empty()
	SlicePin.release_dice_only()


## H-14 (Plan H): Fortified Aura, Guardian Boost Aura and Gleaming Armour left the deny names (equal dice, state and lines with a LIVE bearer, 16 seeds in
## `core_deny_lift_door_test.gd`). The one state left on the table is an aofs / gff aura-granted Fortified whose bearer has fallen: the table says
## `<aura>: bearer killed -> benefit lost` (once, guarded across volleys) where the core writes no line, and for the alias walk (Guardian Boost) the core keeps
## the benefit (defense 5+ against the table's 6+, probe 16 of 16), so the TARGET is refused by state and the dice-only pin keeps it (a state difference).
## Controls: a live joined bearer, a unit that carries the aura itself, the gf / aof Aura Channel spelling (no loss rule) and a SHOOTER in that state stay taken.
func test_a_fallen_fortified_aura_bearer_is_refused_as_a_target() -> void:
	OS.set_environment("NML_CORE_SLICE", "deny")
	CoreSlice.reset_cache()
	for row in [["aofs", "duchies_of_vinci", "Fortified", "Fortified Aura"], ["gff", "custodian_brothers", "Guardian Boost", "Guardian Boost Aura"]]:
		var squad := _ignorer([row[2]], row[1], row[0])
		squad.unit_properties["aura_granted"] = [row[2]]
		squad.models.append(ModelInstance.new())
		var hero := _ignorer(["Hero", row[3], row[2]], row[1], row[0])
		var bearer := ModelInstance.new()
		hero.models.append(bearer)
		EquipmentDistributor.attach_hero_to_unit(hero, squad)
		assert_array(CoreSlice.refusals(squad, true)).override_failure_message("%s: a live bearer keeps the benefit on both sides" % row[3]).is_empty()
		bearer.is_alive = false
		assert_array(CoreSlice.refusals(squad, true)).override_failure_message("%s: the fallen bearer's loss line is the table's" % row[3]).is_equal(["fortified_aura_bearer_dead"])
		assert_array(CoreSlice.refusals(squad)).override_failure_message("a shooter's own Fortified is not read").is_empty()
		SlicePin.dice_only()
		assert_array(CoreSlice.refusals(squad, true)).override_failure_message("the alias's dice differ: the dice-only slice keeps the refusal").is_equal(["fortified_aura_bearer_dead"])
		SlicePin.release_dice_only()
		bearer.is_alive = true
		squad.unit_properties["aura_granted"] = []
		var own := _ignorer([row[3], row[2]], row[1], row[0])
		own.unit_properties["aura_granted"] = [row[2]]
		own.models.append(ModelInstance.new())
		assert_array(CoreSlice.refusals(own, true)).override_failure_message("a unit that carries the aura itself is its own bearer").is_empty()
	var channel := _ignorer(["Fortified"], "mummified_undead", "aof")
	channel.unit_properties["aura_granted"] = ["Fortified"]
	channel.models.append(ModelInstance.new())
	assert_array(CoreSlice.refusals(channel, true)).override_failure_message("the aof Aura Channel has no loss rule").is_empty()
	OS.unset_environment("NML_CORE_SLICE")
	CoreSlice.reset_cache()


## The lift the test above rests on can fail without editing the committed file: a COPY of the deny file with the three names put back refuses a bearer of each,
## the committed file takes it.
func test_putting_the_fortified_aura_names_back_refuses_them() -> void:
	var copy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CoreSlice.DENY_PATH))
	var names := ["Fortified Aura", "Guardian Boost Aura", "Gleaming Armour"]
	for n in names:
		(copy["deny_names"] as Dictionary)[n] = "put back for the check"
	var tmp := "user://deny_with_fortified_names.json"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	f.store_string(JSON.stringify(copy))
	f.close()
	for n in names:
		assert_array(CoreSlice.refusals_in(CoreSlice.DENY_PATH, _unit([n], []))).override_failure_message("the committed file refuses %s" % n).is_empty()
		assert_array(CoreSlice.refusals_in(tmp, _unit([n], []))).override_failure_message("the copy with %s does not refuse it: the check cannot fail" % n).is_equal(["unit_rule:" + n])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))


## A target unit of `faction` / `system` with `rules` (the Warding family lives in faction maps: Knightborn / Warding in knight_brothers, Angelic Blessing in kingdom_of_angels).
func _ignorer(rules: Array, faction: String, system := "gf") -> GameUnit:
	var gu := _unit(rules, [[]])
	gu.unit_properties["faction_folder"] = faction
	gu.unit_properties["game_system"] = system
	return gu


## WDENY PR 2 (19.11.): the core now stamps the Warding gate on its own group beside Regeneration and the other ignore groups (unit.rs), so the PR 1 pair refusal is
## lifted: a Warding-family target beside another wound-ignore group is TAKEN again, whatever the pair. The door proves the lines and the end state equal over 12
## seeds (`door_lines_defense_test.gd`, `test_the_gated_ignore_rule_beside_another_group_says_its_verdict_and_rolls_alike`). RED against PR 1: its deny group refused every row below.
func test_a_warding_family_target_beside_another_ignore_group_is_taken() -> void:
	OS.set_environment("NML_CORE_SLICE", "deny")
	CoreSlice.reset_cache()
	assert_bool(FileAccess.get_file_as_string(CoreSlice.DENY_PATH).contains("door_warding_gate_beside_other_ignore")).override_failure_message("the pair refusal is gone from the deny file").is_false()
	var shooter := _unit([], [["AP(1)"]])
	for row in [["Warding", "knight_brothers", "gf"], ["Knightborn", "knight_brothers", "gf"], ["Angelic Blessing", "kingdom_of_angels", "aof"]]:
		for other in ["Regeneration", "Regeneration Aura", "Medical Training", "Spell Resistance"]:
			if other == "Regeneration Aura" and row[1] == "kingdom_of_angels":
				continue   # the Aura is a gf faction entry of knight_brothers, not of kingdom_of_angels
			var target := _ignorer([row[0], other], row[1], row[2])
			assert_array(CoreSlice.pair_refusals(shooter, target)).override_failure_message("%s + %s: the gate is stamped on its own group, the door takes it" % [row[0], other]).is_empty()
			assert_array(CoreSlice.refusals(target, true)).is_empty()
	assert_array(CoreSlice.pair_refusals(shooter, _ignorer(["Warding", "Knightborn"], "knight_brothers"))).override_failure_message("two gated names are two groups, both gated").is_empty()
	var host := _ignorer(["Knightborn"], "knight_brothers")
	EquipmentDistributor.attach_hero_to_unit(_ignorer(["Regeneration"], "knight_brothers"), host)
	assert_array(CoreSlice.pair_refusals(shooter, host)).is_empty()
	OS.unset_environment("NML_CORE_SLICE")
	CoreSlice.reset_cache()
