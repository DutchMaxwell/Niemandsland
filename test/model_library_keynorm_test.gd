extends GdUnitTestSuite
## Model lookup must be separator-insensitive on the UNIT NAME: the canonical OPR name
## ("Heavy Exo-Suit") has to match a manifest key generated from a slug-derived name
## ("Heavy Exo Suit"), or the R2 model would never resolve at spawn time. The faction
## part (faction_folder, e.g. "battle_brothers") is already consistent and kept as-is.

const ModelLibraryScript := preload("res://scripts/model_library.gd")


func test_make_key_normalizes_unit_separators_and_case() -> void:
	var a := ModelLibraryScript.make_key("battle_brothers", "Heavy Exo-Suit")
	var b := ModelLibraryScript.make_key("battle_brothers", "Heavy_Exo_Suit")
	var c := ModelLibraryScript.make_key("battle_brothers", "  heavy   exo   suit ")
	assert_str(a).is_equal("battle_brothers/heavy exo suit")
	assert_str(b).is_equal(a)
	assert_str(c).is_equal(a)


func test_has_model_matches_unit_across_separators() -> void:
	var lib = auto_free(ModelLibraryScript.new())
	lib.apply_manifest_text(
		'{"base_url":"https://x/","models":{"battle_brothers/heavy exo suit":{"url":"a.glb","sha256":"a"}}}')
	# OPR import requests the hyphenated name — must still resolve.
	assert_bool(lib.has_model("battle_brothers", "Heavy Exo-Suit")).is_true()
	assert_bool(lib.has_model("battle_brothers", "heavy exo-suit")).is_true()
	assert_bool(lib.has_model("battle_brothers", "Totally Different Unit")).is_false()
