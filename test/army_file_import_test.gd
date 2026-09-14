extends GdUnitTestSuite
## Characterisation test for the Army Forge FILE import — the offline fallback
## when the live share-link API changes (scripts/opr_api_client.gd:509
## `import_from_file`, reachable from the army menu scripts/opr_army_manager.gd:224).
##
## The finding this suite pins: the file import takes `_parse_army_forge_json`,
## NOT the tutorial board builder's offline seam (`import_from_tts_json` /
## `_parse_tts_api_response`). Unlike the TTS seam, the file path NEVER consults
## the pinned book snapshot (`_snapshot_book`) — it goes straight to the live
## book API (`_fetch_army_book`). Offline that fetch only avoids HTTP when the
## per-instance book cache is already warm, so this test seeds the two caches
## (`_army_books`, `_common_rules_cache`) exactly as a warmed-up session would
## and asserts the import completes with ZERO HTTP calls.

const ApiScript := preload("res://scripts/opr_api_client.gd")

const FIXTURE := "res://test/fixtures/army_forge_file_export.json"
## The real book id the bundled offline index (assets/solo/army_books_index.json)
## resolves to "Wolf Brothers" / wolf_brothers.
const WOLF_BOOK_ID := "yxjboa8oma9bbdck"


## The Army-Forge book payload the import resolves units against. In a warmed
## session this lives in OPRApiClient._army_books — the per-instance cache
## `_fetch_army_book` checks FIRST; seeding it is the offline seam this test uses.
func _book() -> Dictionary:
	return {
		"name": "Wolf Brothers",
		"units": [
			{"id": "wf-elites", "name": "Wolf Elite Pathfinder", "size": 1, "quality": 4,
				"defense": 4, "cost": 70,
				"specialRules": [{"name": "Tough", "rating": 3}],
				"bases": {"round": "25", "square": "25"}},
			{"id": "wf-longshots", "name": "Wolf Longshots", "size": 4, "quality": 4,
				"defense": 3, "cost": 160, "specialRules": [], "bases": {"round": "25"}},
		],
		"upgradePackages": [],
	}


## A client whose two network feeds are pre-warmed: the book cache (checked by
## _fetch_army_book before any HTTP) and the common-rules cache (checked by
## _fetch_common_rules before any HTTP). No HTTPRequest node exists — _ready()
## never ran — so a cache miss could not quietly touch the network.
func _offline_client() -> OPRApiClient:
	var client: OPRApiClient = ApiScript.new()
	client._army_books[WOLF_BOOK_ID] = _book()
	client._common_rules_cache[2] = {"rules": [], "traits": []}  # 2 = _game_system_id("gf")
	return client


## The headline: a local Army Forge export file builds a full army offline —
## non-null, units on the board, header fields straight out of the fixture.
func test_file_import_builds_the_fixture_army_offline() -> void:
	var client := _offline_client()
	var army := await client.import_from_file(FIXTURE)
	assert_object(army).is_not_null()
	assert_int(army.units.size()).is_equal(2)
	assert_str(army.name).is_equal("Wolf Brothers Warband 1500")
	assert_int(army.points).is_equal(1500)
	assert_str(army.game_system).is_equal("Grimdark Future")
	client.free()


## The faction key comes from the bundled OFFLINE book index (NML-1115
## `_apply_book_index`), not from any fetch: armyId -> "Wolf Brothers".
func test_file_import_stamps_the_faction_from_the_offline_index() -> void:
	var client := _offline_client()
	var army := await client.import_from_file(FIXTURE)
	assert_object(army).is_not_null()
	assert_str(army.faction_name).is_equal("Wolf Brothers")
	assert_str(army.faction_folder).is_equal("wolf_brothers")
	client.free()


## Units resolve against the cached book — real definitions with stats and a
## typed Tough(3) rule, not the "Unit <id>" placeholders a cold offline cache
## would produce.
func test_file_units_resolve_from_the_book_cache_not_placeholders() -> void:
	var client := _offline_client()
	var army := await client.import_from_file(FIXTURE)
	assert_object(army).is_not_null()
	var elites: OPRApiClient.OPRUnit = army.units[0]
	assert_str(elites.name).is_equal("Wolf Elite Pathfinder")
	assert_int(elites.size).is_equal(1)
	assert_int(elites.quality).is_equal(4)
	assert_int(elites.defense).is_equal(4)
	assert_array(elites.special_rules).contains(["Tough(3)"])
	var longshots: OPRApiClient.OPRUnit = army.units[1]
	assert_str(longshots.name).is_equal("Wolf Longshots")
	assert_int(longshots.size).is_equal(4)
	client.free()