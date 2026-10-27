extends GdUnitTestSuite
## D5 (b), step 7 of the v3.6 plan: the game IMPORTS a book that is newer than the rules it plays,
## but says so visibly, and the pinned rules version is read from the maps themselves - not from a
## second constant that can drift.
##
## The books come from the per-instance cache (checked by `_fetch_army_book` before any HTTP) and
## the common-rules cache, exactly as `army_file_import_test.gd` does: no HTTPRequest node exists,
## so a cache miss could not quietly touch the network.

const ApiScript := preload("res://scripts/opr_api_client.gd")

const LIST_FIXTURE := "res://test/fixtures/wolf_brothers_3000.json"
## The book id the wolf fixture's units carry (and the offline index resolves).
const WOLF_BOOK_ID := "yxjboa8oma9bbdck"


func _client(book_version: String) -> OPRApiClient:
	var client: OPRApiClient = ApiScript.new()
	client._army_books[WOLF_BOOK_ID] = {
		"name": "Wolf Brothers", "versionString": book_version, "units": [],
	}
	client._common_rules_cache[2] = {"rules": [], "traits": []}  # 2 = _game_system_id("gf")
	return client


func _import(book_version: String) -> OPRApiClient.OPRArmy:
	return await _client(book_version).import_from_tts_json(
		FileAccess.get_file_as_string(LIST_FIXTURE))


## The pinned rules version is the maps' own `_meta.core_version` (single source of truth).
func test_the_pinned_rules_version_comes_from_the_rule_maps() -> void:
	for system: String in ["gf", "gff", "aof", "aofs", "aofr"]:
		assert_str(OPRApiClient.rules_core_version(system)).override_failure_message(
			"no core_version in rules_mechanics_%s.json" % system).is_equal("3.5.1")


## A 3.6 book imports WITH a warning naming both versions (the player may play on).
func test_a_36_book_imports_and_warns() -> void:
	var army := await _import("3.6.0")
	assert_object(army).is_not_null()
	assert_str(army.book_version).is_equal("3.6.0")
	var warning := OPRApiClient.rules_version_warning(
		army.book_version, OPRApiClient.rules_core_version(army.game_system_abbrev))
	assert_str(warning).contains("3.6.0")
	assert_str(warning).contains("3.5.1")


## A patch bump inside the pinned major.minor is the same rules and stays silent.
func test_a_35_book_passes_silently() -> void:
	var army := await _import("3.5.3")
	assert_str(army.book_version).is_equal("3.5.3")
	assert_str(OPRApiClient.rules_version_warning(
		army.book_version, OPRApiClient.rules_core_version(army.game_system_abbrev))).is_empty()


## No version string (an old book, a synthetic payload) must never invent a warning.
func test_a_book_without_a_version_stays_silent() -> void:
	assert_str(OPRApiClient.rules_version_warning("", "3.5.1")).is_empty()
	assert_str(OPRApiClient.rules_version_warning("3.6.0", "")).is_empty()


## Major.minor decide: "3.5" == 3.5.x, "3.6" != 3.5.x, and a bare "3" says nothing.
func test_major_minor_is_the_comparison() -> void:
	assert_str(OPRApiClient.rules_version_warning("3.5", "3.5.1")).is_empty()
	assert_str(OPRApiClient.rules_version_warning("3.6", "3.5.1")).is_not_empty()
	assert_str(OPRApiClient.rules_version_warning("3", "3.5.1")).is_empty()
