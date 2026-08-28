extends GdUnitTestSuite
## NML-1115 (A0): the PUBLIC, text-free army-book index resolves a unit's registry key
## (`faction_folder`) with NO network at all. Before this, the key came only from the
## live army-book fetch: a failed fetch left it "" and every faction-scoped registry
## lookup silently collapsed to the `common` fallback (NML-1114). Every test here runs
## through `build_army_offline` — the network-free half of the TTS import — so a green
## run IS the proof that the key no longer depends on a reachable API.

const GF_ALIEN_HIVES := "w7qor7b2kuifcyvk"   # Grimdark Future book id, indexed
const AOF_GHOSTLY_UNDEAD := "mdT4HVzHUmxGevc_"  # Age of Fantasy book id, indexed


func _client() -> OPRApiClient:
	# Not added to the tree: _ready() (HTTPRequest setup) is skipped, and nothing below
	# issues a request.
	return auto_free(OPRApiClient.new())


func _tts_payload(army_id: String, system: String, list_name: String) -> Dictionary:
	# The shape `_parse_tts_api_response` hands to `build_army_offline`: the armyId sits
	# on the UNIT, exactly as Army Forge sends it and as the bundled AI lists store it.
	return {
		"id": "test-list",
		"name": list_name,
		"gameSystem": system,
		"units": [{
			"id": "u1", "name": "Test Squad", "size": 5, "cost": 100,
			"armyId": army_id, "quality": 4, "defense": 4,
			"specialRules": [], "weapons": [], "loadout": [],
		}],
	}


# ===== the index itself =====

func test_index_resolves_a_known_book_per_system() -> void:
	var gf := OPRApiClient.book_index_entry(GF_ALIEN_HIVES, "gf")
	assert_str(str(gf.get("faction_folder", ""))).is_equal("alien_hives")
	assert_str(str(gf.get("book_name", ""))).is_equal("Alien Hives")
	var aof := OPRApiClient.book_index_entry(AOF_GHOSTLY_UNDEAD, "aof")
	assert_str(str(aof.get("faction_folder", ""))).is_equal("ghostly_undead")


func test_index_is_scoped_by_game_system_and_misses_cleanly() -> void:
	# No cross-system bleed, and an unindexed book is a clean {} (import falls back to
	# today's behaviour), never a wrong key.
	assert_dict(OPRApiClient.book_index_entry(GF_ALIEN_HIVES, "aof")).is_empty()
	assert_dict(OPRApiClient.book_index_entry("no-such-book-id", "gf")).is_empty()


func test_index_carries_no_rule_text() -> void:
	# THIRD_PARTY.md: OPR rule prose is never bundled. The index may hold ids, slugs,
	# titles and versions — nothing else.
	var allowed := ["faction_folder", "book_name", "version"]
	for key in OPRApiClient.book_index_entry(GF_ALIEN_HIVES, "gf").keys():
		assert_bool(allowed.has(str(key))).override_failure_message(
			"army_books_index.json carries an unexpected key: %s" % key).is_true()


# ===== the import path =====

func test_offline_import_resolves_the_faction_without_network() -> void:
	var army := _client().build_army_offline(_tts_payload(GF_ALIEN_HIVES, "gf", "alien_hives_1000pts"))
	assert_str(army.faction_folder).is_equal("alien_hives")
	assert_str(army.faction_name).is_equal("Alien Hives")


func test_failed_book_fetch_can_no_longer_lose_the_registry_key() -> void:
	# The NML-1114 scenario: a bundled AI list whose NAME is no miniatures folder, and a
	# book fetch that answers nothing. `build_army_offline` runs BEFORE that fetch, and
	# the fetch only refines what it set — so the key survives.
	var army := _client().build_army_offline(
		_tts_payload(AOF_GHOSTLY_UNDEAD, "aof", "ghostly_undead_kriegsherr_1000pts"))
	assert_str(army.faction_folder).is_not_empty()
	assert_str(army.faction_folder).is_equal("ghostly_undead")
