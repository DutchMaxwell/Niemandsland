extends GdUnitTestSuite
## PLAN_GAME_SYSTEM_SWITCH step 9: assets/terrain_systems.json holds the signed terrain-per-system table and
## GameSystem.offers answers it. The runtime fails OPEN (an id without a row is offered); THIS suite fails CLOSED:
## every id the game catalogues has a row, no row names an id that is gone, and a gf table (and a table with no
## system set) is offered exactly what main offers today. Red proof: delete one row, or flip a gf row to "fantasy".

const THEMES_DIR := "res://assets/themes"
const GENERATED_BOARDS := ["tiefwerk", "ruined_town"]
const ALL := ["gf", "gff", "aof", "aofs", "aofr"]
const GRIMDARK := ["gf", "gff"]
const FANTASY := ["aof", "aofs", "aofr"]


func before_test() -> void:
	GameSystem.reset_cache()


## kind -> the ids the game catalogues today (read from the code that owns each list).
func _catalogued() -> Dictionary:
	var themes: Array = []
	for f in DirAccess.get_files_at(THEMES_DIR):
		if f.ends_with(".json"):
			themes.append(f.get_basename())
	var hazard_looks: Array = TerrainGroupBase.BIOME_HAZARD_MODEL_BY_PREFIX.values()
	hazard_looks.append("anti_tank_mine")
	for look: String in TerrainGroupBase.FANTASY_HAZARD_MODEL_BY_PREFIX.values():
		if not hazard_looks.has(look):
			hazard_looks.append(look)
	return {
		"biome": Array(preload("res://scripts/table.gd").BIOMES),
		"ruin": ObjectManager.SANDBOX_RUINS.keys(),
		"group": ObjectManager.SANDBOX_GROUPS.keys(),
		"solid": ObjectManager.SANDBOX_SOLIDS.keys(),
		"prefab": TerrainPrefabs.PREFABS.keys(),
		"container_look": Array(ContainersLibrary.COLOURWAYS),
		"hazard_look": hazard_looks,
		"stain": [BattlefieldStains.BLOOD_PANEL, BattlefieldStains.OIL_PANEL],
		"theme": themes,
		"generated_board": GENERATED_BOARDS,
	}


func _data() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(GameSystem.TERRAIN_PATH))


func test_every_catalogued_id_has_a_row() -> void:
	var data := _data()
	for kind in _catalogued():
		var rows: Dictionary = data.get(kind, {})
		for id in _catalogued()[kind]:
			assert_bool(rows.has(id)).override_failure_message("terrain_systems.json has no %s row for '%s'" % [kind, id]).is_true()


func test_no_row_names_an_id_that_is_gone() -> void:
	var cat := _catalogued()
	for kind in _data():
		if str(kind).begins_with("_"):
			continue
		assert_bool(cat.has(kind)).override_failure_message("terrain_systems.json has an unknown kind '%s'" % kind).is_true()
		for id in _data()[kind]:
			assert_bool((cat[kind] as Array).has(id)).override_failure_message("stale row %s/%s" % [kind, id]).is_true()


func test_a_gf_table_is_offered_everything_main_offers_today() -> void:
	var cat := _catalogued()
	for kind in cat:
		if kind == "generated_board":
			continue   # a board chooser entry is new, not something main offers today
		for id in cat[kind]:
			if kind == "hazard_look" and not TerrainGroupBase.BIOME_HAZARD_MODEL_BY_PREFIX.values().has(id) and id != "anti_tank_mine":
				continue   # the fantasy hazard looks of step 14 are new, not something a gf table had
			for system in ["gf", "", "unknown"]:   # no system set / an unknown one folds to the gf offers
				assert_bool(GameSystem.offers(kind, id, system)).override_failure_message(
					"gf table lost %s/%s (system '%s')" % [kind, id, system]).is_true()


func test_fantasy_tables_drop_the_grimdark_only_looks() -> void:
	var drops := {
		"biome": ["urban_ruins", "alien_jungle"],
		"container_look": ["container_red", "container_blue"],
		"hazard_look": ["anti_tank_mine", "carnivore_plant"],
		"stain": ["oil_stain"],
	}
	for kind in drops:
		for id in drops[kind]:
			for system in GRIMDARK:
				assert_bool(GameSystem.offers(kind, id, system)).override_failure_message("%s/%s on %s" % [kind, id, system]).is_true()
			for system in FANTASY:
				assert_bool(GameSystem.offers(kind, id, system)).override_failure_message("%s/%s on %s" % [kind, id, system]).is_false()


func test_everything_else_is_offered_on_every_system() -> void:
	var dropped := ["urban_ruins", "alien_jungle", "container_red", "container_blue", "anti_tank_mine", "carnivore_plant",
		"oil_stain", "ruined_borderland", "tiefwerk", "ruined_town", "thorn_field", "sinkhole", "stone_circle"]   # the last three: fantasy only (step 14)
	var cat := _catalogued()
	for kind in cat:
		for id in cat[kind]:
			if dropped.has(id):
				continue
			for system in ALL:
				assert_bool(GameSystem.offers(kind, id, system)).override_failure_message("%s/%s on %s" % [kind, id, system]).is_true()


func test_the_theme_is_a_battle_scale_offer() -> void:
	# size gate exists already (TableTheme.fits): the 6 x 4 theme is a battle-scale offer, both settings.
	for system in ["gf", "aof", "aofr"]:
		assert_bool(GameSystem.offers("theme", "ruined_borderland", system)).is_true()
	for system in ["gff", "aofs"]:
		assert_bool(GameSystem.offers("theme", "ruined_borderland", system)).is_false()


func test_generated_boards_follow_setting_and_scale_and_availability() -> void:
	for system in ALL:
		assert_bool(GameSystem.offers("generated_board", "tiefwerk", system)).is_equal(system == "gff")
		# GEN-14: the ruined town ships for AoF: Skirmish only
		assert_bool(GameSystem.offers("generated_board", "ruined_town", system)).is_equal(system == "aofs")


func test_an_id_or_kind_without_a_row_is_offered() -> void:
	assert_bool(GameSystem.offers("biome", "no_such_biome", "aofs")).is_true()
	assert_bool(GameSystem.offers("no_such_kind", "x", "aofs")).is_true()
