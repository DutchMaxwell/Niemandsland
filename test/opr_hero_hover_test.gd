extends GdUnitTestSuite
## Tests for joined-hero attachment (import + save/load) and the visual hover
## detection used to float Flying units, drones and hover vehicles.


func _mgr() -> OPRArmyManager:
	return auto_free(OPRArmyManager.new())  # not in tree -> _ready() skipped


func _opr_unit(selection_id: String, unit_name: String, join_to: String) -> OPRApiClient.OPRUnit:
	var unit := OPRApiClient.OPRUnit.new()
	unit.selection_id = selection_id
	unit.name = unit_name
	unit.join_to_unit = join_to
	return unit


func _game_unit(unit_id: String, unit_name: String) -> GameUnit:
	var unit := GameUnit.new()
	unit.unit_id = unit_id
	unit.unit_properties = {"name": unit_name, "attached_heroes": [], "attached_to": null}
	return unit


# ===== Joined-hero attachment at import =====

func test_joined_hero_is_attached_to_host() -> void:
	var mgr := _mgr()
	var host_opr := _opr_unit("host1", "Prosecution Sisters", "")
	var hero_opr := _opr_unit("hero1", "Great Sister", "host1")
	var host_gu := _game_unit("H", "Prosecution Sisters")
	var hero_gu := _game_unit("E", "Great Sister")
	mgr.unit_to_game_unit[host_opr] = host_gu
	mgr.unit_to_game_unit[hero_opr] = hero_gu

	var army := OPRApiClient.OPRArmy.new()
	army.units = [host_opr, hero_opr]
	mgr._attach_joined_heroes(army)

	assert_bool(hero_gu.get_attached_to() == host_gu).is_true()
	assert_array(host_gu.get_attached_heroes()).contains([hero_gu])


func test_unit_without_join_is_not_attached() -> void:
	var mgr := _mgr()
	var opr := _opr_unit("a", "Battle Brothers", "")
	var gu := _game_unit("A", "Battle Brothers")
	mgr.unit_to_game_unit[opr] = gu

	var army := OPRApiClient.OPRArmy.new()
	army.units = [opr]
	mgr._attach_joined_heroes(army)

	assert_bool(gu.is_attached()).is_false()


# ===== Attachment serialization (JSON-safe ids) =====

func test_to_dict_stores_attachment_as_ids() -> void:
	var host := _game_unit("H", "Squad")
	var hero := _game_unit("E", "Champion")
	EquipmentDistributor.attach_hero_to_unit(hero, host)

	var hero_dict := hero.to_dict()
	var host_dict := host.to_dict()

	# attached_to / attached_heroes are stored as unit_id strings, not GameUnit refs.
	assert_str(hero_dict["unit_properties"]["attached_to"]).is_equal("H")
	assert_array(host_dict["unit_properties"]["attached_heroes"]).contains(["E"])
	# And the dict is JSON-serializable (GameUnit refs would break this).
	assert_str(JSON.stringify(hero_dict)).is_not_empty()


func test_restore_hero_attachments_resolves_ids() -> void:
	var mgr := _mgr()
	var host := _game_unit("H", "Squad")
	host.unit_properties["attached_heroes"] = ["E"]
	var hero := _game_unit("E", "Champion")
	hero.unit_properties["attached_to"] = "H"
	mgr.game_units["H"] = host
	mgr.game_units["E"] = hero

	var save_manager: SaveManager = auto_free(SaveManager.new())
	save_manager.army_manager = mgr
	save_manager._restore_hero_attachments_after_load()

	assert_bool(hero.get_attached_to() == host).is_true()
	assert_array(host.get_attached_heroes()).contains([hero])


# ===== Effective models (unit + attached heroes) =====

func test_get_alive_models_with_attached() -> void:
	var host := _game_unit("H", "Squad")
	host.models.append(ModelInstance.new())
	host.models.append(ModelInstance.new())
	var hero := _game_unit("E", "Champion")
	hero.models.append(ModelInstance.new())
	EquipmentDistributor.attach_hero_to_unit(hero, host)

	# Host's effective models include the attached hero's model.
	assert_int(host.get_alive_models_with_attached().size()).is_equal(3)
	# A unit with no attached heroes returns only its own.
	assert_int(hero.get_alive_models_with_attached().size()).is_equal(1)


# ===== Spawn ordering: hero right after host =====

func test_order_units_places_hero_after_host() -> void:
	var mgr := _mgr()
	var host := _opr_unit("h", "Squad", "")
	var hero := _opr_unit("e", "Champion", "h")
	# Hero listed BEFORE host (as in real Army Forge data) must end up after it.
	var ordered := mgr._order_units_heroes_after_host([hero, host])

	assert_int(ordered.size()).is_equal(2)
	assert_bool(ordered[0] == host).is_true()
	assert_bool(ordered[1] == hero).is_true()


func test_order_units_keeps_hero_with_missing_host() -> void:
	var mgr := _mgr()
	var hero := _opr_unit("e", "Champion", "missing")
	var ordered := mgr._order_units_heroes_after_host([hero])

	assert_int(ordered.size()).is_equal(1)
	assert_bool(ordered[0] == hero).is_true()


# ===== Visual hover detection =====

func test_should_hover_detection() -> void:
	var mgr := _mgr()
	assert_bool(mgr._should_hover("Battle Suits", ["Flying", "Tough(3)"])).is_true()   # Flying rule
	assert_bool(mgr._should_hover("Gun Drones", ["Good Shot", "Strider"])).is_true()    # name: drone
	assert_bool(mgr._should_hover("Hover Tank", ["Fast", "Strider"])).is_true()         # name: hover
	assert_bool(mgr._should_hover("Battle Brothers", ["Tough(3)"])).is_false()          # neither
