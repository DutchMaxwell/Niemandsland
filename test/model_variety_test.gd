extends GdUnitTestSuite
## Per-model variety: a unit whose models all carry the base loadout shows a second sculpt on every second model
## when the manifest holds `<unit>#var2` (Vampiric Undead Bat Horrors: two accepted designs for one 3-model unit).
## Deterministic by model index, so both multiplayer clients place the same sculpt on the same model, and the
## second sculpt is prefetched with the base model. Weapon variants and units without `#var2` are unchanged.

const VU_ARMY := "qABIfXYbYxmA75yL"


func _manager(keys: Array) -> OPRArmyManager:
	var lib: ModelLibrary = auto_free(ModelLibrary.new())
	lib._load_label_slug_map()
	var models := {}
	for key in keys:
		models[key] = {"url": "x.glb", "sha256": "x", "size": 1}
	lib.apply_manifest_text(JSON.stringify({"version": 1, "models": models}))
	var manager: OPRArmyManager = auto_free(OPRArmyManager.new())
	manager.model_library = lib
	return manager


func _unit(name: String, size: int, weapon: String) -> Variant:
	var api: OPRApiClient = auto_free(OPRApiClient.new())
	return api.build_army_offline({"gameSystem": "aof", "units": [{"armyId": VU_ARMY, "name": name, "size": size,
		"bases": {"round": "40"}, "loadout": [{"type": "ArmyBookWeapon", "name": weapon, "attacks": 1, "count": size}]}]}).units[0]


func test_every_second_base_model_takes_the_second_sculpt() -> void:
	var manager := _manager(["vampiric_undead/bat horrors", "vampiric_undead/bat horrors#var2"])
	assert_array(manager._unit_model_variant_names(_unit("Bat Horrors", 3, "Deadly Fangs"), "vampiric_undead")) \
		.is_equal(["", "Bat Horrors#var2", ""])


func test_the_second_sculpt_is_prefetched() -> void:
	var manager := _manager(["vampiric_undead/bat horrors", "vampiric_undead/bat horrors#var2"])
	var names: Array = manager._unit_model_variant_names(_unit("Bat Horrors", 3, "Deadly Fangs"), "vampiric_undead")
	assert_array(OPRArmyManager._collect_prefetch_names("Bat Horrors", names, "")) \
		.is_equal(["Bat Horrors", "Bat Horrors#var2"])


func test_spawn_and_prefetch_name_the_same_model() -> void:
	var manager := _manager(["vampiric_undead/bat horrors", "vampiric_undead/bat horrors#var2"])
	var unit = _unit("Bat Horrors", 3, "Deadly Fangs")
	var names: Array = manager._unit_model_variant_names(unit, "vampiric_undead")
	var labels: Array = manager._model_labels_for_unit(unit, "vampiric_undead")
	for i in range(unit.size):
		assert_str(manager._spawn_model_name(unit, labels, i, "vampiric_undead", "")).is_equal(names[i])


func test_without_a_second_sculpt_nothing_changes() -> void:
	var manager := _manager(["vampiric_undead/bat horrors"])
	assert_array(manager._unit_model_variant_names(_unit("Bat Horrors", 3, "Deadly Fangs"), "vampiric_undead")) \
		.is_equal(["", "", ""])


func test_weapon_variants_keep_their_bake() -> void:
	var manager := _manager(["vampiric_undead/ghouls#halberd", "vampiric_undead/ghouls#var2"])
	assert_array(manager._unit_model_variant_names(_unit("Ghouls", 3, "Halberd"), "vampiric_undead")) \
		.is_equal(["Ghouls#halberd", "Ghouls#halberd", "Ghouls#halberd"])


func test_a_weapon_word_without_its_own_bake_still_varies() -> void:
	# Ghoul Beast Riders: the book weapon "Lance" maps to a variant word, but the base key IS the lance form (no
	# `#lance` bake), so the riders fall back to the base model - and every second one takes the winged sculpt.
	var manager := _manager(["vampiric_undead/ghoul beast riders", "vampiric_undead/ghoul beast riders#var2"])
	assert_array(manager._unit_model_variant_names(_unit("Ghoul Beast Riders", 3, "Lance"), "vampiric_undead")) \
		.is_equal(["", "Ghoul Beast Riders#var2", ""])
