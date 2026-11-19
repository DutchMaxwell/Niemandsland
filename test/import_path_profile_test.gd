extends GdUnitTestSuite
## What the TABLE's import path hands a unit (plan G step 13b). These four tests used to drive
## `tools/core_selfplay.gd`'s `_units_from_list` (a non-running SceneTree instance of the tool); the tool
## is being retired, so the suite calls the table's own functions directly — OPRApiClient.build_army_offline
## -> EquipmentDistributor.create_from_opr_unit -> OPRArmyManager's two post-spawn passes, the calls
## `tools/arena_match.gd` makes too — and keeps guarding the same four readings (NML-1105):
## the recommended base, an item's granted rule with its provenance, a joined hero with his aura, and the
## rule that an upgrade option's LABEL is never parsed into a rule. Every one of them FAILS against the
## old hand-rolled path (no `bases`, no item grants, no aura expansion, rule names parsed out of label text).
##
## Nearest Python twins (they gate the Python loader, not the table): test_list_to_profile.py
## test_base_radius_reads_the_lists_round_base (a), test_an_items_name_and_its_rules_reach_the_rule_line (b),
## test_an_aura_grants_its_base_rule_to_the_unit_and_to_its_hero (c) and test_joined_hero_stays_a_separate_unit (c);
## (d) has none (the Python reading of labels is the legacy switch test_the_legacy_reading_still_parses_the_upgrade_label).

var _nodes: Array[Node3D] = []


func after_test() -> void:
	for n in _nodes:
		n.free()
	_nodes.clear()


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


## One list in the TTS-API shape the table imports: a 3-model squad on a RECOMMENDED 40 mm base carrying
## a unit-wide item that grants Furious, plus a Hero joined to it (selectionId/joinToUnit) whose
## "Relentless Aura" the aura pass must hand to the whole unit.
func _list() -> Dictionary:
	var squad := {"id": "grunts", "name": "Grunts", "size": 3, "quality": 4, "defense": 4,
		"bases": {"round": "40", "square": "40"},
		"rules": [{"name": "Tough", "rating": 2, "label": "Tough(2)"}],
		"selectionId": "hostSel", "joinToUnit": null, "combined": false,
		"loadout": [{"name": "Rage Totem", "type": "ArmyBookItem", "count": 3,
			"content": [{"type": "ArmyBookRule", "name": "Furious", "label": "Furious"}]}],
		# A LABEL-only upgrade option: the table reads typed gains, so this one grants nothing.
		"selectedUpgrades": [{"option": {"label": "Standard Bearer (Fear)"}}]}
	var hero := {"id": "warlord", "name": "Warlord", "size": 1, "quality": 3, "defense": 3,
		"rules": [{"name": "Hero", "label": "Hero"},
			{"name": "Relentless Aura", "label": "Relentless Aura"}],
		"selectionId": "heroSel", "joinToUnit": "hostSel", "combined": false}
	return {"gameSystem": "gf", "units": [squad, hero]}


## (a) The Army-Forge base recommendation reaches unit_properties — and with it every base reading the sim
## takes (SeparationChecker.shape_for_model, the act header's `base_radius`). The old path never wrote the
## key at all, so every unit answered with the 32 mm / 0.016 m default.
func test_recommended_base_reaches_the_unit_and_its_radius() -> void:
	var units := _import(_list())
	assert_int(units.size()).is_equal(2)
	var squad := units[0] as GameUnit
	assert_int(int(squad.unit_properties.get("base_size_round", 0))).is_equal(40)
	assert_float(SoloController.model_base_radius_m(squad.models[0])).is_equal_approx(0.020, 0.0005)


## (b) A unit-wide item's granted rule lands in special_rules AND keeps its provenance in `item_grants` —
## the registry input RulesRegistry.unit_rules_of_primitive and the act header's `item_grants` field read.
func test_item_granted_rule_and_its_provenance_reach_the_unit() -> void:
	var units := _import(_list())
	var squad := units[0] as GameUnit
	assert_bool(squad.has_special_rule("Furious")).is_true()
	var grants: Dictionary = squad.unit_properties.get("item_grants", {})
	assert_bool(grants.has("Rage Totem")).is_true()
	assert_array(grants.get("Rage Totem", [])).contains(["Furious"])


## (c) The joined Hero is ATTACHED (both directions), and his "Relentless Aura" is expanded to the base rule
## on the host — the two post-spawn passes OPRArmyManager.spawn_army runs. The old path ran neither.
func test_joined_hero_is_attached_and_his_aura_is_expanded() -> void:
	var units := _import(_list())
	var squad := units[0] as GameUnit
	var hero := units[1] as GameUnit
	assert_str((hero.source_data as OPRApiClient.OPRUnit).join_to_unit).is_equal("hostSel")
	assert_array(squad.get_attached_heroes()).contains([hero])
	assert_object(hero.unit_properties.get("attached_to")).is_same(squad)
	assert_bool(squad.has_special_rule("Relentless")).is_true()
	assert_array(squad.unit_properties.get("aura_granted", [])).contains(["Relentless"])


## (d) The discriminator that keeps (a)-(c) honest: an upgrade OPTION's LABEL is never parsed. "Standard
## Bearer (Fear)" carries no typed gain, so the table grants nothing — and neither may the import.
func test_upgrade_option_label_is_never_parsed_into_a_rule() -> void:
	var units := _import(_list())
	var squad := units[0] as GameUnit
	assert_bool(squad.has_special_rule("Fear")).is_false()
	assert_bool(squad.has_special_rule("Standard Bearer")).is_false()
