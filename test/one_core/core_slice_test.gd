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
const DENY_CEILING := 19   # DLINES3 train 3: Shred, Self-Repair and Resistance left with their lines (19 -> 16), then the probes at 1500 / 2000 / 3000 pts showed three more families whose line the door omits: Armor, Disintegrate, Tear (+3 -> 19). DLINES2 train 2: Ranged Shrouding, Lacerate, Shielded, Fortified and Regeneration left with their lines (24 -> 19). 19.11.: +15 primitives in eight `rule_line` groups (a rule whose table line the door omits stays on the table until the line exists, dlines_gap rows 2, 3, 7, 13, 15, 16, 17, 21), they leave group by group with their lines. BEATS 19.11.: the pre-attack beat slot adds 6 primitives, the list stands at exactly 9 (3 ledger + 6 beat), no slack left, they leave with the beats guard; HR-POS: Hit & Run + Hit & Run Shooter lifted again (the delta carries the stepped positions; G10 had re-denied them); C-18: Indirect added, attached_heroes lifted for Growth Markers, wound-ignore by name lifted (C-R1); LD-6 18.11. lifted the six EQUAL-probe names; only shrinks


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
	# A rule refused by NAME where its primitive is shared (Changebound = Stealth; plain Stealth stays taken).
	var changed := _unit(["Changebound"], [])
	changed.unit_properties["faction_folder"] = "change_disciples"   # the faction whose map entry gives it primitive Stealth
	assert_array(CoreSlice.refusals(changed)).is_equal(["unit_rule:Changebound"])
	var teleporter := _unit(["Teleport"], [])
	teleporter.unit_properties["faction_folder"] = "elven_jesters"   # a faction whose map gives Teleport its primitive
	assert_array(CoreSlice.refusals(teleporter)).is_equal(["unit_rule:Teleport"])
	assert_bool(CoreSlice.takes(_unit(["Tough(3)"], [["AP(1)"]]))).is_true()
	# HR-POS: the after-volley step comes back through the delta (`positions`), so Hit & Run goes to the core again.
	var raider := _unit(["Hit & Run"], [["AP(1)"]])
	raider.unit_properties["faction_folder"] = "dao_union"   # a faction whose map gives Hit & Run its primitive
	assert_array(CoreSlice.refusals(raider)).is_empty()
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
		["Artillery", ""], ["Stealth", ""], ["Evasive", "battle_brothers"], ["Aircraft", ""], ["Precision Fighter", ""],
		["Instinctive", "goblin_reclaimers"],
		["Takedown", ""], ["Grounded Protection", "soul_snatcher_cults"], ["Protection Feat", "alien_hives"],
		["Armor", ""], ["Disintegrate", "custodian_brothers"], ["Tear", "custodian_brothers"],
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
	# Train 2 (lines said, groups lifted): the Ranged Shrouding range cut, the Bane re-roll named by plain Bane / Lacerate / the unit-level aliases, the
	# Shielded and Fortified lines, the plain Regeneration group's roll.
	for lifted in [["Ranged Shrouding", "custodian_brothers"], ["Bane", ""], ["Lacerate", "battle_brothers"], ["Anti-Regen", ""],
			["Mischievous", "goblin_reclaimers"], ["Vicious", "goblin_reclaimers"], ["Unstoppable when Shooting", ""],
			["Shielded", "battle_brothers"], ["Fortified", "alien_hives"], ["Regeneration", ""], ["Regeneration Aura", "alien_hives"],
			["Shred", ""], ["Warbound", "war_disciples"], ["Self-Repair", "robot_legions"], ["Resistance", "alien_hives"], ["Plaguebound", "plague_disciples"]]:
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


## DLINES2: a Deadly weapon beside another ranged weapon, as a shooter (the table lands Deadly inline, the core after the dice: "Simultaneous
## fire" and Blast's cap note are missing); Deadly alone, two plain weapons, a melee weapon beside Deadly and a TARGET are taken. A joined hero's
## weapons fire in the same volley. RED: drop the predicate -> the first assertion reads [].
func test_deny_mode_refuses_a_deadly_weapon_beside_another_ranged_weapon() -> void:
	OS.set_environment("NML_CORE_SLICE", "deny")
	CoreSlice.reset_cache()
	var both := _ranged_unit([["Deadly(3)"], ["AP(1)"]])
	assert_array(CoreSlice.refusals(both)).is_equal(["deadly_beside_other_weapons"])
	assert_array(CoreSlice.refusals(both, true)).override_failure_message("as a target the weapons do not matter").is_empty()
	assert_bool(CoreSlice.takes(_ranged_unit([["Deadly(3)"]]))).override_failure_message("Deadly alone stays on the core").is_true()
	assert_bool(CoreSlice.takes(_ranged_unit([["AP(1)"], ["Blast(3)"]]))).override_failure_message("no Deadly: no inline casualties").is_true()
	assert_bool(CoreSlice.takes(_ranged_unit([["Deadly(3)"]], [["Reliable"]]))).override_failure_message("a melee weapon (range 0) is no second ranged weapon").is_true()
	var host := _ranged_unit([["AP(1)"]])
	var hero := _ranged_unit([["Deadly(3)"]])
	EquipmentDistributor.attach_hero_to_unit(hero, host)
	assert_array(CoreSlice.refusals(host)).override_failure_message("the hero's Deadly gun fires in the host's volley").is_equal(["deadly_beside_other_weapons"])
	OS.unset_environment("NML_CORE_SLICE")
	CoreSlice.reset_cache()


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


## C-19: the HUMAN door is not switched by the default (the gate measured the AI door; DS-109 switches the human door): with
## no env it still reads the allow file, so a unit with rules is a table unit for it and a deny-list unit for the AI door.
## An explicit `deny` reads the deny-list for both doors (as before C-19); `allow` reads the allow file for both; a test
## seam (`path_override`) is read by both. RED (the human door follows the AI door): the unset case takes the unit.
func test_the_human_door_keeps_the_allow_file_until_it_is_switched() -> void:
	var ruled := _unit(["Tough(3)"], [["AP(1)"]])
	OS.unset_environment("NML_CORE_SLICE")
	CoreSlice.reset_cache()
	assert_bool(CoreSlice.takes(ruled)).override_failure_message("AI door, no env").is_true()
	assert_bool(CoreSlice.takes_human(ruled)).override_failure_message("human door, no env: switched by C-19").is_false()
	assert_array(CoreSlice.refusals_human(ruled)).is_equal(["unit_rule:Tough", "weapon_rule:AP"])
	assert_bool(CoreSlice.takes_human(_unit([], [[]]))).override_failure_message("a plain unit stays taken").is_true()
	assert_bool(CoreSlice.takes_human(ruled, true)).override_failure_message("human door, target").is_false()
	assert_str(CoreSlice.mode_line()).contains("human door allow (core_slice_allow.json)")
	OS.set_environment("NML_CORE_SLICE", "deny")
	CoreSlice.reset_cache()
	assert_bool(CoreSlice.takes_human(ruled)).override_failure_message("explicit deny reads the deny-list for both doors").is_true()
	assert_str(CoreSlice.mode_line()).contains("human door deny (core_slice_deny.json)")
	OS.set_environment("NML_CORE_SLICE", "allow")
	CoreSlice.reset_cache()
	assert_bool(CoreSlice.takes_human(ruled)).is_false()
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
	# DLINES3: Tear left this list: its dice are equal but the table names its conditional AP (`Tear: AP(+N) against <U>`) and the door says
	# nothing for it (dlines_gap row 11), so the conditional-AP group refuses it (test above).
	# Lifted again (C-19): the soak's unequal volley was a shot at base contact the table read as melee, not Point-Blank
	# Surge (surge_contact_door_test.gd, 16/16 equal through the door in deny mode after the table fix).
	var sisters := _unit(["Point-Blank Surge"], [])
	sisters.unit_properties["faction_folder"] = "blessed_sisters"
	assert_bool(CoreSlice.takes(sisters)).override_failure_message(
		"deny mode takes a unit that carries Point-Blank Surge").is_true()
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
		["gf", "battle_brothers", "Mend"], ["gf", "alien_hives", "Breath Attack"], ["gf", "jackals", "Mind Control"],
		["gf", "daemons_of_war", "Fatigue Debuff"], ["gf", "daemons_of_war", "Storm of War"],
		["aof", "daemons_of_war", "Reckless Piercing"], ["gf", "human_defense_force", "Precision Shooter Buff"],
		["gf", "jackals", "Precision Tag"], ["gf", "battle_brothers", "Re-Position Artillery"]]
	for c in cases:
		var bearer := _unit([c[2], "Tough(3)"], [["AP(1)"]])
		bearer.unit_properties["game_system"] = c[0]
		bearer.unit_properties["faction_folder"] = c[1]
		assert_array(CoreSlice.refusals(bearer)).override_failure_message(
			"%s (%s/%s) must stay on the table in deny mode" % [c[2], c[0], c[1]]).is_equal(["unit_rule:" + c[2]])
	# The same unit without the beat rule is taken (the group refuses the rule, not the faction).
	var plain := _unit(["Tough(3)"], [["AP(1)"]])
	plain.unit_properties["faction_folder"] = "battle_brothers"
	assert_array(CoreSlice.refusals(plain)).is_empty()
	# A joined hero's beat rule keeps its host on the table (deny mode reads the hero's rules too).
	var host := _unit(["Tough(3)"], [["AP(1)"]])
	host.unit_properties["faction_folder"] = "battle_brothers"
	var healer := _unit(["Hero", "Mend"], [])
	healer.unit_properties["faction_folder"] = "battle_brothers"
	EquipmentDistributor.attach_hero_to_unit(healer, host)
	assert_array(CoreSlice.refusals(host)).contains(["unit_rule:Mend"])
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
	assert_dict(data.get("deny_names", {}) as Dictionary).is_empty()
	assert_array((data.get("groups", {}) as Dictionary).keys()).is_equal(["attached_heroes"])
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
## `rule_line` groups the Grounded Protection row below is refused; if it dropped every refusal Changebound (a DICE difference) would be taken.
func test_the_dice_only_slice_drops_the_line_refusals_and_keeps_the_dice_ones() -> void:
	var self_repair := _unit(["Grounded Protection"], [])
	self_repair.unit_properties["faction_folder"] = "soul_snatcher_cults"
	SlicePin.dice_only()
	assert_bool(CoreSlice.takes(self_repair, true)).override_failure_message("Grounded Protection's missing line is not a dice difference").is_true()
	assert_bool(CoreSlice.takes(_unit(["Shred"], []), true)).override_failure_message("Shred's missing line is not a dice difference").is_true()
	assert_bool(CoreSlice.takes(_unit(["Changebound"], []), true)).override_failure_message("Changebound changes the dice: still refused").is_false()
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
