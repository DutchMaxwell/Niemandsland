extends GdUnitTestSuite
## Caster tokens through the TABLE's import path (plan G step 13a). These eleven tests used to drive
## `tools/core_selfplay.gd`'s `_units_from_list` (a non-running SceneTree instance of the tool), which
## calls the table's own import functions; the tool is being retired, so the suite now calls those
## functions directly — OPRApiClient.build_army_offline -> EquipmentDistributor.create_from_opr_unit ->
## OPRArmyManager's two post-spawn passes — and keeps guarding the same quantity: the Caster(X)
## tokens a unit enters the game with (scripts/equipment_distributor.gd, initialize_caster_points).
##
## History: NML-1046 M1 — the tool hand-built GameUnits and skipped the grant, so every core-generated
## unit entered BattleSim.capture() with casts_current == 0 and no spell was ever cast. NML-1066 —
## upgrade-granted Casters; NML-1105 — the typed `option.gains` are the only shape the table reads.
##
## Python twins (the Python loader, not the table): test_list_to_profile.py asserts `caster_value` for a
## printed Caster(2) and for the legacy label reading; none of the other quantities below has one.

var _nodes: Array[Node3D] = []


func after_test() -> void:
	for n in _nodes:
		n.free()
	_nodes.clear()


## A list in the TTS-API shape the table imports (a Dictionary: `build_army_offline` takes it directly).
func _list(units: Array, gsys: String = "gf") -> Dictionary:
	return {"gameSystem": gsys, "units": units}


## The table's import path, called function by function (the order OPRArmyManager.spawn_army runs them):
## build the army offline, make one GameUnit per unit, then attach joined heroes, then expand auras.
func _import(data: Dictionary, player: int = 1) -> Array:
	var client := OPRApiClient.new()
	var army: OPRApiClient.OPRArmy = client.build_army_offline(data)
	client.free()
	assert_object(army).is_not_null()
	var by_unit := {}
	var out: Array = []
	for ou: OPRApiClient.OPRUnit in army.units:
		var nodes: Array[Node3D] = []
		for _m in range(maxi(ou.size, 1)):
			var n := Node3D.new()
			add_child(n)
			nodes.append(n)
			_nodes.append(n)
		var gu := EquipmentDistributor.create_from_opr_unit(ou, nodes, player)
		by_unit[ou] = gu
		out.append(gu)
	OPRArmyManager.attach_joined_heroes_of(army.units, by_unit)
	OPRArmyManager.expand_auras_of(army.units, by_unit)
	return out


func _unit_spec(id: String, size: int, rules: Array, sel: String = "",
		join: Variant = null, combined: bool = false) -> Dictionary:
	return {"id": id, "name": id, "size": size, "quality": 4, "defense": 4,
		"rules": rules, "weapons": [], "selectionId": sel, "joinToUnit": join,
		"combined": combined}


## Adds ONE selectedUpgrades entry with the option's TYPED gains — the ONLY shape the table reads
## (opr_api_client.gd:_apply_selected_upgrade_rules).
func _with_upgrade_gains(spec: Dictionary, gains: Array) -> Dictionary:
	spec["selectedUpgrades"] = [{"option": {"label": "Upgrade", "gains": gains}}]
	return spec


## Adds ONE selectedUpgrades entry that carries an option LABEL and nothing else — no typed gain,
## so it grants nothing.
func _with_upgrade_label(spec: Dictionary, option_label: String) -> Dictionary:
	spec["selectedUpgrades"] = [{"option": {"label": option_label}}]
	return spec


## One ArmyBookRule gain entry, e.g. _rule_gain("Caster", 2) -> "Caster(2)".
func _rule_gain(rule_name: String, rating: Variant = null) -> Dictionary:
	var gain := {"type": "ArmyBookRule", "name": rule_name}
	if rating != null:
		gain["rating"] = rating
	return gain


## (a) A Caster(X) list unit is granted X tokens after the build.
func test_caster_list_unit_gets_tokens() -> void:
	var units := _import(_list([_unit_spec("Wizard", 1,
		[{"name": "Caster", "rating": 2, "label": "Caster(2)"}])]))
	assert_int(units.size()).is_equal(1)
	assert_int((units[0] as GameUnit).casts_current).is_equal(2)


## (b) Discriminator: a unit with no caster rule stays at 0 tokens. This case must stay GREEN under the
## red toggle that stubs the grant body with `pass`.
func test_non_caster_list_unit_keeps_zero_tokens() -> void:
	var units := _import(_list([_unit_spec("Grunts", 5,
		[{"name": "Tough", "rating": 3, "label": "Tough(3)"}])]))
	assert_int(units.size()).is_equal(1)
	assert_int((units[0] as GameUnit).casts_current).is_equal(0)


## (c) Ordering guard: Caster Group's X is the ALIVE MODEL COUNT of the unit (game_unit.gd
## get_caster_value), and a combined pair folds its partner's models into the host in the pass just above
## the grant loop. The grant must run AFTER that fold, or it only sees the host's own pre-combine models.
func test_caster_group_grant_counts_the_combined_models() -> void:
	# BOTH halves of an OPR Combined unit carry combined:true (the anchor has no joinToUnit) — that is the
	# shape opr_api_client.gd:_merge_combined_units folds.
	var host := _unit_spec("Musician", 2,
		[{"name": "Caster Group", "label": "Caster Group"}], "hostSel", null, true)
	var partner := _unit_spec("Musician_B", 3,
		[{"name": "Caster Group", "label": "Caster Group"}], "partnerSel", "hostSel", true)
	var units := _import(_list([host, partner]))
	assert_int(units.size()).is_equal(1)   # the combined partner folds into the host
	assert_int((units[0] as GameUnit).casts_current).is_equal(5)   # 2 + 3 combined models


## (d) Per-model grant semantics: Caster Group's X is the unit's ALIVE model count (game_unit.gd
## get_caster_value), re-evaluated on each grant, not a count frozen at build time. Killing a model and
## re-granting must drop the pool — the exact quantity the build-time ordering guard (c) depends on.
func test_caster_group_tokens_recount_after_casualties() -> void:
	var units := _import(_list([_unit_spec("Musician", 4,
		[{"name": "Caster Group", "label": "Caster Group"}])]))
	var unit := units[0] as GameUnit
	assert_int(unit.casts_current).is_equal(4)
	(unit.models[0] as ModelInstance).is_alive = false
	unit.initialize_caster_points()
	assert_int(unit.casts_current).is_equal(3)


## NML-1066 (a): an UPGRADE-granted Caster (a selectedUpgrades gain, not a printed unit rule) must reach
## the unit and grant its tokens — resolved from the option's typed "gains", exactly as the table does.
func test_upgrade_granted_caster_gets_tokens() -> void:
	var units := _import(_list([_with_upgrade_gains(
		_unit_spec("Master Brother", 1, []), [_rule_gain("Caster", 2)])]))
	assert_int(units.size()).is_equal(1)
	assert_int((units[0] as GameUnit).casts_current).is_equal(2)


## NML-1066 (b): an option with no typed gain (a plain weapon/item swap, e.g. "Replace CCW" ->
## "Iron Sights") grants no rule.
func test_upgrade_option_without_parens_grants_nothing() -> void:
	var units := _import(_list([_with_upgrade_label(
		_unit_spec("Trooper", 1, []), "Iron Sights")]))
	var unit := units[0] as GameUnit
	assert_int(unit.casts_current).is_equal(0)
	assert_array(unit.get_special_rules()).is_empty()


## NML-1066 (c): a printed Caster(1) AND an upgrade-granted "Seer (Caster(2))" both land in special_rules
## (printed rule first, upgrade rule appended after it), but game_unit.gd:get_caster_value() returns on the
## FIRST "Caster(" match it finds — so the PRINTED value wins, not the higher one. Pinning this actual
## (first-listed) behavior, not a max/combine that doesn't exist.
func test_upgrade_caster_alongside_printed_caster_keeps_printed_value() -> void:
	var units := _import(_list([_with_upgrade_gains(_unit_spec("Hybrid Caster", 1,
		[{"name": "Caster", "rating": 1, "label": "Caster(1)"}]), [_rule_gain("Caster", 2)])]))
	var unit := units[0] as GameUnit
	assert_int(unit.casts_current).is_equal(1)
	var rules := unit.get_special_rules()
	assert_bool(rules.has("Caster(1)")).is_true()
	assert_bool(rules.has("Caster(2)")).is_true()


## NML-1066 (d): an option with SEVERAL typed gains grants every one of them, e.g. a Champion carrying
## both "Fear" and "Caster(1)".
func test_upgrade_multi_rule_label_grants_all_of_them() -> void:
	var units := _import(_list([_with_upgrade_gains(
		_unit_spec("Champion Bearer", 1, []), [_rule_gain("Fear"), _rule_gain("Caster", 1)])]))
	var unit := units[0] as GameUnit
	assert_int(unit.casts_current).is_equal(1)
	assert_bool(unit.has_special_rule("Fear")).is_true()
	assert_bool(unit.has_special_rule("Caster(1)")).is_true()


## NML-1066: the combined-partner second pass must ALSO pick up its OWN selectedUpgrades rules onto the
## shared host — a caster hero folded into a unit via combined:true must not lose its upgrade-granted Caster.
func test_combined_partner_upgrade_caster_reaches_the_host() -> void:
	var host := _unit_spec("Grunts", 2, [], "hostSel", null, true)
	var partner := _with_upgrade_gains(
		_unit_spec("Archivist", 1, [], "partnerSel", "hostSel", true), [_rule_gain("Caster", 2)])
	var units := _import(_list([host, partner]))
	assert_int(units.size()).is_equal(1)
	assert_int((units[0] as GameUnit).casts_current).is_equal(2)


## NML-1066 (e) guard, NML-1105 reading: a WEAPON-SWAP option's label carries a parenthesized profile —
## "Energy Sword (A2, AP(1), Rending)" must grant NOTHING, not leak "A2"/"AP(1)"/"Rending" into unit-wide
## special_rules. The import never parses labels at all, so this is free by construction.
func test_upgrade_weapon_swap_profile_grants_nothing() -> void:
	var units := _import(_list([_with_upgrade_label(
		_unit_spec("Swordsman", 1, []), "Energy Sword (A2, AP(1), Rending)")]))
	var unit := units[0] as GameUnit
	assert_int(unit.casts_current).is_equal(0)
	assert_array(unit.get_special_rules()).is_empty()


## NML-1066 (f) guard: same, for a RANGED weapon profile — the leading `24"` range figure must also void
## the whole label.
func test_upgrade_weapon_swap_with_range_grants_nothing() -> void:
	var units := _import(_list([_with_upgrade_label(
		_unit_spec("Rifleman", 1, []), "Heavy Rifle (24\", A1, AP(1))")]))
	var unit := units[0] as GameUnit
	assert_int(unit.casts_current).is_equal(0)
	assert_array(unit.get_special_rules()).is_empty()
