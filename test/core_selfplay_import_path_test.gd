extends GdUnitTestSuite
## NML-1105: `tools/core_selfplay.gd` is the Godot-side ORACLE — it records the
## M3 reference sidecars the Godot-free trainer is gated against. It used to
## build its units in a hand-rolled `_units_from_list` that the table's import
## path had long outgrown: no `bases` (so 32 mm for a Titan and a Grunt alike),
## no item grants, no aura expansion, no hero attachment, and rule names parsed
## out of upgrade LABEL text — a hack that could only ever INVENT rules, because
## real Army-Forge lists carry the grant in the typed `option.gains`/`loadout`
## and never in a parsable label.
##
## This suite pins the four readings the harness now takes from the SAME calls
## `tools/arena_match.gd` makes (OPRApiClient.build_army_offline ->
## EquipmentDistributor.create_from_opr_unit -> OPRArmyManager's two post-spawn
## passes). Every one of them FAILS against the old hand-rolled path.
##
## Fixture recipe follows test/core_selfplay_caster_test.gd: a NON-RUNNING
## SceneTree.new() instance of core_selfplay.gd, `_units_from_list` parenting
## its model nodes under `root`, freed at the end of each test body so gdUnit
## samples 0 orphans.

const CoreSelfplayScript := preload("res://tools/core_selfplay.gd")

var _seq := 0


## One list JSON in the TTS-API shape the table imports: a 3-model squad on a
## RECOMMENDED 40 mm base carrying a unit-wide item that grants Furious, plus a
## Hero joined to it (selectionId/joinToUnit) whose "Relentless Aura" the aura
## pass must hand to the whole unit.
func _write_list() -> String:
	_seq += 1
	var squad := {"id": "grunts", "name": "Grunts", "size": 3, "quality": 4, "defense": 4,
		"bases": {"round": "40", "square": "40"},
		"rules": [{"name": "Tough", "rating": 2, "label": "Tough(2)"}],
		"selectionId": "hostSel", "joinToUnit": null, "combined": false,
		"loadout": [{"name": "Rage Totem", "type": "ArmyBookItem", "count": 3,
			"content": [{"type": "ArmyBookRule", "name": "Furious", "label": "Furious"}]}],
		# A LABEL-only upgrade option: the table reads typed gains, so this one
		# grants nothing. The old path parsed the tail and invented "Fear".
		"selectedUpgrades": [{"option": {"label": "Standard Bearer (Fear)"}}]}
	var hero := {"id": "warlord", "name": "Warlord", "size": 1, "quality": 3, "defense": 3,
		"rules": [{"name": "Hero", "label": "Hero"},
			{"name": "Relentless Aura", "label": "Relentless Aura"}],
		"selectionId": "heroSel", "joinToUnit": "hostSel", "combined": false}
	var path := "user://test_import_path_%d.json" % _seq
	var fa := FileAccess.open(path, FileAccess.WRITE)
	fa.store_string(JSON.stringify({"gameSystem": "gf", "units": [squad, hero]}))
	fa.close()
	return path


## (a) The Army-Forge base recommendation reaches unit_properties — and with it
## every base reading the sim takes (SeparationChecker.shape_for_model, the act
## header's `base_radius`). The old path never wrote the key at all, so every
## unit answered with the 32 mm / 0.016 m default.
func test_recommended_base_reaches_the_unit_and_its_radius() -> void:
	var cs: SceneTree = CoreSelfplayScript.new()
	var units: Array = cs._units_from_list(_write_list(), 1)
	assert_int(units.size()).is_equal(2)
	var squad := units[0] as GameUnit
	assert_int(int(squad.unit_properties.get("base_size_round", 0))).is_equal(40)
	assert_float(SoloController.model_base_radius_m(squad.models[0])).is_equal_approx(0.020, 0.0005)
	cs.free()


## (b) A unit-wide item's granted rule lands in special_rules AND keeps its
## provenance in `item_grants` — the registry input RulesRegistry.
## unit_rules_of_primitive and the act header's `item_grants` field read.
func test_item_granted_rule_and_its_provenance_reach_the_unit() -> void:
	var cs: SceneTree = CoreSelfplayScript.new()
	var units: Array = cs._units_from_list(_write_list(), 1)
	var squad := units[0] as GameUnit
	assert_bool(squad.has_special_rule("Furious")).is_true()
	var grants: Dictionary = squad.unit_properties.get("item_grants", {})
	assert_bool(grants.has("Rage Totem")).is_true()
	assert_array(grants.get("Rage Totem", [])).contains(["Furious"])
	cs.free()


## (c) The joined Hero is ATTACHED (both directions), and his "Relentless Aura"
## is expanded to the base rule on the host — the two post-spawn passes
## OPRArmyManager.spawn_army runs. The old path ran neither.
func test_joined_hero_is_attached_and_his_aura_is_expanded() -> void:
	var cs: SceneTree = CoreSelfplayScript.new()
	var units: Array = cs._units_from_list(_write_list(), 1)
	var squad := units[0] as GameUnit
	var hero := units[1] as GameUnit
	assert_str((hero.source_data as OPRApiClient.OPRUnit).join_to_unit).is_equal("hostSel")
	assert_array(squad.get_attached_heroes()).contains([hero])
	assert_object(hero.unit_properties.get("attached_to")).is_same(squad)
	assert_bool(squad.has_special_rule("Relentless")).is_true()
	assert_array(squad.unit_properties.get("aura_granted", [])).contains(["Relentless"])
	cs.free()


## (d) The discriminator that keeps (a)-(c) honest: an upgrade OPTION's LABEL is
## never parsed. "Standard Bearer (Fear)" carries no typed gain, so the table
## grants nothing — and neither may the harness.
func test_upgrade_option_label_is_never_parsed_into_a_rule() -> void:
	var cs: SceneTree = CoreSelfplayScript.new()
	var units: Array = cs._units_from_list(_write_list(), 1)
	var squad := units[0] as GameUnit
	assert_bool(squad.has_special_rule("Fear")).is_false()
	assert_bool(squad.has_special_rule("Standard Bearer")).is_false()
	cs.free()
