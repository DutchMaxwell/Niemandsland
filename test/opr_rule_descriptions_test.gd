extends GdUnitTestSuite
## Tests the OPR special-rule description integration (army-forge API): game-system
## id mapping, army-book extraction, common-rule merge precedence, and the
## parameterised-rule lookup fallback (Tough(3) -> Tough).

const OPRApiClientScript := preload("res://scripts/opr_api_client.gd")


func test_game_system_id_mapping() -> void:
	assert_int(OPRApiClientScript._game_system_id("gf")).is_equal(2)
	assert_int(OPRApiClientScript._game_system_id("gff")).is_equal(3)
	assert_int(OPRApiClientScript._game_system_id("aof")).is_equal(4)
	assert_int(OPRApiClientScript._game_system_id("aofs")).is_equal(5)
	assert_int(OPRApiClientScript._game_system_id("aofr")).is_equal(6)
	assert_int(OPRApiClientScript._game_system_id("bogus")).is_equal(2)  # default GF


func test_extract_rule_descriptions_from_book() -> void:
	var client = auto_free(OPRApiClientScript.new())
	var army = OPRApiClientScript.OPRArmy.new()
	var book := {"specialRules": [{"name": "Shielded", "description": "+1 to defense rolls."}]}
	client._extract_rule_descriptions(army, book)
	assert_str(army.rule_descriptions.get("Shielded", "")).contains("+1 to defense")


func test_common_rules_do_not_override_army_book() -> void:
	var client = auto_free(OPRApiClientScript.new())
	var army = OPRApiClientScript.OPRArmy.new()
	army.rule_descriptions["Tough"] = "ARMY-SPECIFIC"
	var common := {
		"rules": [{"name": "Tough", "description": "COMMON"}, {"name": "AP", "description": "ignores armor"}],
		"traits": [{"name": "Suppressor", "description": "-1 to hit"}],
	}
	client._merge_common_descriptions(army, common)
	assert_str(army.rule_descriptions["Tough"]).is_equal("ARMY-SPECIFIC")  # army-book wins
	assert_str(army.rule_descriptions["AP"]).contains("ignores armor")     # common added
	assert_str(army.rule_descriptions["Suppressor"]).contains("-1 to hit") # traits merged too


func test_get_rule_description_parameterised_fallback() -> void:
	var army = OPRApiClientScript.OPRArmy.new()
	army.rule_descriptions["Tough"] = "Takes extra hits to kill."
	assert_str(OPRApiClientScript.get_rule_description("Tough(3)", army)).is_equal("Takes extra hits to kill.")
	assert_str(OPRApiClientScript.get_rule_description("Tough", army)).is_equal("Takes extra hits to kill.")
	assert_str(OPRApiClientScript.get_rule_description("Fearless", army)).is_equal("")
	assert_str(OPRApiClientScript.get_rule_description("Tough(3)", null)).is_equal("")


# =============================================================================
# NML-1126: rule-text provenance — a failed fetch must be LOUD and STAMPED
# =============================================================================
## The descriptions this suite exercises above exist only because a live army-forge fetch
## succeeded. When it does not, the old code did `push_warning` + `return` and the game played
## on with `rule_descriptions` empty — so the description-driven move modifiers
## (movement_range_controller.gd) were silently off and the row was banked anyway (NML-1114).
## These two tests hold the new contract: any failure on the fetch path flips
## `rule_text_ok` to false for the rest of the process, and a fetch that really delivered
## text stamps the source as "api".


func test_a_failed_rule_text_fetch_stamps_rule_text_not_ok() -> void:
	OPRApiClientScript.reset_rule_text_stamp()
	OS.set_environment("NML_ARMY_BOOKS_DIR", "")   # NML-1115: no snapshot may answer this one
	assert_bool(OPRApiClientScript.rule_text_ok).is_true()   # the clean reading to start from

	# STUB THE FETCH TO FAIL, without a network and without touching the API: an HTTPRequest
	# that is not inside the tree answers request() with ERR_UNCONFIGURED (measured: 3), which
	# is exactly the `error != OK` branch of _fetch_common_rules. The push_error it raises is
	# the point of the change and does not fail the test (gdUnit reports 0 errors for it).
	var client = auto_free(OPRApiClientScript.new())
	client._book_http_request = auto_free(HTTPRequest.new())
	var army = OPRApiClientScript.OPRArmy.new()
	army.army_id = "w7qor7b2kuifcyvk"
	army.game_system_abbrev = "gf"
	await client._fetch_common_rules(army)

	assert_bool(army.rule_descriptions.is_empty()).is_true()      # nothing arrived, as expected
	assert_bool(OPRApiClientScript.rule_text_ok).is_false()       # ... and the process now SAYS so
	OPRApiClientScript.reset_rule_text_stamp()


func test_descriptions_that_really_land_stamp_the_source_as_api() -> void:
	OPRApiClientScript.reset_rule_text_stamp()
	assert_str(OPRApiClientScript.rule_text_source).is_equal("none")

	var client = auto_free(OPRApiClientScript.new())
	var army = OPRApiClientScript.OPRArmy.new()
	# An answer with no usable text leaves the source alone — a 200 is not the same as text.
	client._extract_rule_descriptions(army, {"specialRules": [{"name": "Shielded", "description": ""}]})
	assert_str(OPRApiClientScript.rule_text_source).is_equal("none")

	client._merge_common_descriptions(army, {"rules": [{"name": "Tough", "description": "extra hits"}]})
	assert_str(OPRApiClientScript.rule_text_source).is_equal("api")
	assert_bool(OPRApiClientScript.rule_text_ok).is_true()   # a success never flips the alarm
	OPRApiClientScript.reset_rule_text_stamp()


# =============================================================================
# NML-1115: the army-book SNAPSHOT is resolved before the network
# =============================================================================
## The rule text an army plays with used to be whatever army-forge served at import time,
## and army-forge edits its books weekly (measured 28.08.: 79 of the 87 books the pools use
## at versionString 3.5.3, 8 at 3.5.2, one edited the day before). Two corpora recorded a
## week apart against the live API are therefore not the same corpus, and nothing said so.
## A private snapshot — same delivery as the AI lists, never in the repo — is checked FIRST;
## a miss is loud and stamps "api", which a corpus run refuses to record.

const _SNAP_ROOT := "user://test_army_books_nml1115"


## Writes a one-book snapshot (book + common + manifest) and points the env at it.
## Returns the absolute directory, so the test reads it exactly like a fleet box would.
func _write_snapshot(book_id: String, system := "gf") -> String:
	var abs_root := ProjectSettings.globalize_path(_SNAP_ROOT)
	DirAccess.make_dir_recursive_absolute(abs_root.path_join(system))
	var book := {"armyId": book_id, "gameSystem": system, "name": "Ghostly Undead",
		"versionString": "3.5.3", "modifiedAt": "2026-08-27T22:39:08.652Z",
		"specialRules": [{"name": "Ethereal", "description": "SNAPSHOT ETHEREAL TEXT"}],
		"spells": [{"name": "Wither", "threshold": 4, "effect": "Target within 12\" takes a hit."}]}
	FileAccess.open(abs_root.path_join("%s/%s.json" % [system, book_id]),
		FileAccess.WRITE).store_string(JSON.stringify(book))
	FileAccess.open(abs_root.path_join("%s/_common.json" % system),
		FileAccess.WRITE).store_string(JSON.stringify(
			{"rules": [{"name": "Tough", "description": "SNAPSHOT TOUGH TEXT"}], "traits": []}))
	FileAccess.open(abs_root.path_join("_manifest.json"), FileAccess.WRITE).store_string(
		JSON.stringify({"sha256": "cafef00d", "generated": "2026-08-28T16:14:42Z"}))
	OS.set_environment("NML_ARMY_BOOKS_DIR", abs_root)
	return abs_root


func _clear_snapshot() -> void:
	OS.set_environment("NML_ARMY_BOOKS_DIR", "")
	OPRApiClientScript.reset_rule_text_stamp()


## A snapshot present = no network at all. The client's HTTPRequest is deliberately OUT of
## the tree, so any request() it made would answer ERR_UNCONFIGURED and leave the map empty
## (that is exactly how the NML-1126 test above forces a failure). Text arriving anyway is
## the proof that nothing was fetched.
func test_a_snapshot_answers_the_book_and_the_common_rules_without_the_network() -> void:
	_clear_snapshot()
	var abs_root := _write_snapshot("gh0stbook")
	var client = auto_free(OPRApiClientScript.new())
	client._book_http_request = auto_free(HTTPRequest.new())   # unusable on purpose

	var book: Dictionary = client._snapshot_book("gh0stbook", "gf")
	assert_str(str(book.get("name", ""))).is_equal("Ghostly Undead")
	assert_str(OPRApiClientScript.snapshot_dir()).is_equal(abs_root)

	var army = OPRApiClientScript.OPRArmy.new()
	army.army_id = "gh0stbook"
	army.game_system_abbrev = "gf"
	client._extract_rule_descriptions(army, book, "snapshot")
	client._extract_spells(army, book)
	await client._fetch_common_rules(army)

	assert_str(army.rule_descriptions.get("Ethereal", "")).is_equal("SNAPSHOT ETHEREAL TEXT")
	assert_str(army.rule_descriptions.get("Tough", "")).is_equal("SNAPSHOT TOUGH TEXT")
	assert_int(army.spells.size()).is_equal(1)
	assert_str(OPRApiClientScript.rule_text_source).is_equal("snapshot")
	assert_bool(OPRApiClientScript.rule_text_ok).is_true()
	# ... and the header can name WHICH snapshot: the manifest is read on the first hit.
	assert_str(OPRApiClientScript.snapshot_sha256).is_equal("cafef00d")
	assert_str(OPRApiClientScript.snapshot_generated).is_equal("2026-08-28T16:14:42Z")
	_clear_snapshot()


## The miss. A book the snapshot does not carry resolves to {} — the caller then falls back
## to the live API and the game is stamped "api", not silently text-less. Same for the
## common rules of a system the snapshot never fetched: the API branch runs, fails without a
## network, and leaves the NML-1126 alarm set.
func test_a_snapshot_miss_falls_back_to_the_api_and_says_so() -> void:
	_clear_snapshot()
	_write_snapshot("gh0stbook")
	var client = auto_free(OPRApiClientScript.new())
	client._book_http_request = auto_free(HTTPRequest.new())

	assert_bool(client._snapshot_book("not-in-the-snapshot", "gf").is_empty()).is_true()
	assert_bool(client._snapshot_book("gh0stbook", "aof").is_empty()).is_true()  # wrong system

	var army = OPRApiClientScript.OPRArmy.new()
	army.army_id = "not-in-the-snapshot"
	army.game_system_abbrev = "aof"          # no aof/_common.json in this snapshot
	await client._fetch_common_rules(army)
	assert_bool(army.rule_descriptions.is_empty()).is_true()
	assert_bool(OPRApiClientScript.rule_text_ok).is_false()   # loud, per NML-1126
	_clear_snapshot()


## "api" is STICKY. A game that took one description off the network is not a snapshot game,
## whatever landed afterwards — otherwise a single live fetch could hide inside a corpus row
## that claims to be pinned.
func test_the_api_reading_survives_a_later_snapshot_read() -> void:
	_clear_snapshot()
	assert_str(OPRApiClientScript.rule_text_source).is_equal("none")
	OPRApiClientScript._note_rule_text_source("snapshot")
	assert_str(OPRApiClientScript.rule_text_source).is_equal("snapshot")
	OPRApiClientScript._note_rule_text_source("api")
	assert_str(OPRApiClientScript.rule_text_source).is_equal("api")
	OPRApiClientScript._note_rule_text_source("snapshot")
	assert_str(OPRApiClientScript.rule_text_source).is_equal("api")
	_clear_snapshot()


## No env = the local `user://` default, for a hand-placed copy. Never res://: THIRD_PARTY.md
## forbids bundling OPR rule prose in the repo or an exported .pck.
func test_the_default_snapshot_dir_is_the_user_cache_never_the_repo() -> void:
	OS.set_environment("NML_ARMY_BOOKS_DIR", "")
	assert_str(OPRApiClientScript.snapshot_dir()).is_equal("user://army_books")
	assert_bool(OPRApiClientScript.snapshot_dir().begins_with("res://")).is_false()


## How LOUD a miss is depends on whether a snapshot was configured. A box (env set) that lost
## its rsync must scream; an ordinary install, which is never given one, must not raise an
## error per army for a file nobody ships it. The stamp is the same either way — "api" — so
## the arena's refusal does not depend on this distinction, only the human-facing noise does.
func test_a_miss_is_only_expected_to_be_loud_where_a_snapshot_was_promised() -> void:
	OS.set_environment("NML_ARMY_BOOKS_DIR", "")
	var promised_by_cache: bool = DirAccess.dir_exists_absolute("user://army_books")
	assert_bool(OPRApiClientScript._snapshot_expected()).is_equal(promised_by_cache)

	# The env names one even when the rsync failed and the directory is not there at all.
	OS.set_environment("NML_ARMY_BOOKS_DIR", "/nonexistent/army_books")
	assert_bool(OPRApiClientScript._snapshot_expected()).is_true()
	OS.set_environment("NML_ARMY_BOOKS_DIR", "")
