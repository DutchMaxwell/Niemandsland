extends GdUnitTestSuite
## Pure-logic tests for OPRApiClient parsing/formatting helpers + the OPRArmy/OPRUnit/
## OPRWeapon data structs. The live-HTTP import paths (import_from_share_link,
## _fetch_army_book, _on_request_completed) need the network and are out of scope.
## Already covered elsewhere: _base_size_from_tough, _merge_combined_units,
## rule-description extraction, loadout parsing.

# OPRArmy / OPRUnit / OPRWeapon are inner classes of OPRApiClient.


func _client() -> OPRApiClient:
	# Not added to the tree: _ready() (HTTPRequest setup) is skipped; the helpers
	# under test are pure.
	return auto_free(OPRApiClient.new())


# ===== _safe_int (static) =====

func test_safe_int_coercions() -> void:
	assert_int(OPRApiClient._safe_int(null, 5)).is_equal(5)
	assert_int(OPRApiClient._safe_int(3)).is_equal(3)
	assert_int(OPRApiClient._safe_int(2.7)).is_equal(2)
	assert_int(OPRApiClient._safe_int("42")).is_equal(42)
	assert_int(OPRApiClient._safe_int("abc")).is_equal(0)


func test_safe_int_oval_returns_larger_dimension() -> void:
	assert_int(OPRApiClient._safe_int("60x35")).is_equal(60)
	assert_int(OPRApiClient._safe_int("120x92")).is_equal(120)


# ===== _parse_base_size (static) -> [is_oval, width, depth] =====

func test_parse_base_size_round() -> void:
	var r: Array = OPRApiClient._parse_base_size(null, 32)
	assert_bool(r[0]).is_false()
	assert_int(r[1]).is_equal(32)
	assert_int(r[2]).is_equal(32)
	var r2: Array = OPRApiClient._parse_base_size(40)
	assert_bool(r2[0]).is_false()
	assert_int(r2[1]).is_equal(40)
	assert_int(r2[2]).is_equal(40)
	var r3: Array = OPRApiClient._parse_base_size("32")
	assert_bool(r3[0]).is_false()
	assert_int(r3[1]).is_equal(32)


func test_parse_base_size_oval_width_is_short_depth_is_long() -> void:
	# Oval "WxD": short side -> width (perpendicular), long side -> depth (facing).
	var r: Array = OPRApiClient._parse_base_size("60x35")
	assert_bool(r[0]).is_true()
	assert_int(r[1]).is_equal(35)
	assert_int(r[2]).is_equal(60)
	var r2: Array = OPRApiClient._parse_base_size("120x92")
	assert_int(r2[1]).is_equal(92)
	assert_int(r2[2]).is_equal(120)


# ===== OPRArmy aggregates =====

func test_army_totals_empty() -> void:
	var army := OPRApiClient.OPRArmy.new()
	assert_int(army.get_total_points()).is_equal(0)
	assert_int(army.get_unit_count()).is_equal(0)


func test_army_totals_sum_units() -> void:
	var army := OPRApiClient.OPRArmy.new()
	var u1 := OPRApiClient.OPRUnit.new()
	u1.cost = 100
	u1.size = 5
	var u2 := OPRApiClient.OPRUnit.new()
	u2.cost = 150
	u2.size = 3
	army.units.append(u1)
	army.units.append(u2)
	assert_int(army.get_total_points()).is_equal(250)
	assert_int(army.get_unit_count()).is_equal(8)


# ===== OPRUnit display + base geometry =====

func test_unit_display_name() -> void:
	var u := OPRApiClient.OPRUnit.new()
	u.name = "Battle Brothers"
	u.size = 5
	assert_str(u.get_display_name()).is_equal("Battle Brothers [5]")
	u.size = 1
	assert_str(u.get_display_name()).is_equal("Battle Brothers")
	u.custom_name = "The Hammers"
	assert_str(u.get_display_name()).is_equal("The Hammers")


func test_unit_base_geometry_meters() -> void:
	var u := OPRApiClient.OPRUnit.new()
	u.base_size_round = 32
	assert_float(u.get_base_radius_meters()).is_equal_approx(0.016, 0.0001)
	assert_float(u.get_base_diameter_meters()).is_equal_approx(0.032, 0.0001)
	u.base_size_round = 25
	assert_float(u.get_base_radius_meters()).is_equal_approx(0.0125, 0.0001)


# ===== OPRWeapon display text =====

func test_weapon_display_text() -> void:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "CCW"
	w.range_value = 0
	w.attacks = 2
	assert_str(w.get_display_text()).is_equal("CCW (Melee, A2)")
	var r := OPRApiClient.OPRWeapon.new()
	r.name = "Rifle"
	r.range_value = 24
	r.attacks = 1
	r.count = 5
	assert_str(r.get_display_text()).is_equal("5x Rifle (24\", A1)")
	var c := OPRApiClient.OPRWeapon.new()
	c.name = "Cannon"
	c.range_value = 36
	c.attacks = 3
	c.special_rules = ["AP(2)"]
	assert_str(c.get_display_text()).is_equal("Cannon (36\", A3) [AP(2)]")


# ===== _format_rating (instance) =====

func test_format_rating_strips_whole_float() -> void:
	var c := _client()
	assert_str(c._format_rating(1.0)).is_equal("1")
	assert_str(c._format_rating(2.0)).is_equal("2")
	assert_str(c._format_rating(1.5)).is_equal("1.5")
	assert_str(c._format_rating(3)).is_equal("3")
	assert_str(c._format_rating("AP")).is_equal("AP")


# ===== _extract_list_id (instance) =====

func test_extract_list_id() -> void:
	var c := _client()
	assert_str(c._extract_list_id("https://army-forge.onepagerules.com/share?id=abc123&name=Foo")).is_equal("abc123")
	assert_str(c._extract_list_id("rawListId")).is_equal("rawListId")
	assert_str(c._extract_list_id("  rawListId  ")).is_equal("rawListId")


# ===== _expand_game_system (instance) =====

func test_expand_game_system() -> void:
	var c := _client()
	assert_str(c._expand_game_system("gf")).is_equal("Grimdark Future")
	assert_str(c._expand_game_system("aof")).is_equal("Age of Fantasy")
	assert_str(c._expand_game_system("bogus")).is_equal("bogus")


# ===== #73: the OPR profile survives serialization so a peer's card shows the full loadout =====

func test_oprweapon_dict_round_trip() -> void:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "HE Autocannon"
	w.range_value = 30
	w.attacks = 3
	w.count = 1
	w.from_item = "Weapon Team"
	w.special_rules = ["AP(2)", "Blast(3)"]
	var w2 := OPRApiClient.OPRWeapon.from_dict(w.to_dict())
	assert_str(w2.name).is_equal("HE Autocannon")
	assert_int(w2.range_value).is_equal(30)
	assert_int(w2.attacks).is_equal(3)
	assert_str(w2.from_item).is_equal("Weapon Team")
	assert_array(w2.special_rules).is_equal(["AP(2)", "Blast(3)"])


func test_oprunit_dict_round_trip_keeps_weapons() -> void:
	var u := OPRApiClient.OPRUnit.new()
	u.equipment = ["Banner"]
	u.special_rules = ["Tough(3)", "Fearless"]
	u.base_is_oval = true
	u.base_width_mm = 60
	u.base_depth_mm = 35
	var gun := OPRApiClient.OPRWeapon.new()
	gun.name = "Shredder Rifle"
	gun.range_value = 24
	gun.special_rules = ["Rending"]
	u.weapons = [gun]
	var u2 := OPRApiClient.OPRUnit.from_dict(u.to_dict())
	assert_int(u2.weapons.size()).is_equal(1)
	assert_str(u2.weapons[0].name).is_equal("Shredder Rifle")
	assert_array(u2.weapons[0].special_rules).is_equal(["Rending"])
	assert_array(u2.equipment).is_equal(["Banner"])
	assert_array(u2.special_rules).is_equal(["Tough(3)", "Fearless"])
	assert_bool(u2.base_is_oval).is_true()
	assert_int(u2.base_width_mm).is_equal(60)


func test_game_unit_serializes_opr_source_data() -> void:
	# The #73 fix: a synced/loaded OPR unit must carry its OPRUnit profile so the peer's card shows
	# the full loadout instead of falling back to model 0's basic weapons.
	var u := OPRApiClient.OPRUnit.new()
	var gun := OPRApiClient.OPRWeapon.new()
	gun.name = "Plasma Rifle"
	u.weapons = [gun]
	var gu := GameUnit.new()
	gu.unit_id = "u1"
	gu.source_type = "opr"
	gu.source_data = u
	var restored := GameUnit.from_dict(gu.to_dict())
	assert_bool(restored.source_data is OPRApiClient.OPRUnit).is_true()
	var ru: OPRApiClient.OPRUnit = restored.source_data
	assert_int(ru.weapons.size()).is_equal(1)
	assert_str(ru.weapons[0].name).is_equal("Plasma Rifle")


func test_game_unit_non_opr_keeps_null_source_data() -> void:
	# Back-compat: a non-OPR (or old-save) unit round-trips with source_data null (leaner card).
	var gu := GameUnit.new()
	gu.unit_id = "g1"
	gu.source_type = "generic"
	var restored := GameUnit.from_dict(gu.to_dict())
	assert_object(restored.source_data).is_null()


# ===== rule-only upgrades (Banner / Musician / Sergeant) folded from selectedUpgrades =====

func test_selected_upgrade_roles_show_on_card_and_mark_bearer() -> void:
	# Banner/Musician/Sergeant grant a bare ArmyBookRule on the upgrade OPTION and never appear in
	# the resolved loadout. Their bonus is unit-relevant, so each is listed on the card as a rule
	# (special_rules); and since a specific model carries it, each ALSO becomes a per-model
	# equipment_item (base ring on the bearer). NOT added to `equipment` (would duplicate the card).
	var client: OPRApiClient = auto_free(OPRApiClient.new())
	var unit := OPRApiClient.OPRUnit.new()
	unit.size = 5
	var selected := [
		{"option": {"label": "Banner", "gains": [{"name": "Banner", "type": "ArmyBookRule"}]}},
		{"option": {"label": "Musician", "gains": [{"name": "Musician", "type": "ArmyBookRule"}]}},
		{"option": {"label": "Sergeant", "gains": [{"name": "Sergeant", "type": "ArmyBookRule"}]}},
		# item/weapon gains are SKIPPED here — they already ride in the loadout.
		{"option": {"label": "War Boon", "gains": [{"name": "War Boon", "type": "ArmyBookItem", "content": []}]}},
		{"option": {"label": "Sword", "gains": [{"name": "Sword", "type": "ArmyBookWeapon"}]}},
	]
	client._apply_selected_upgrade_rules(unit, selected)
	# On the card as rules (effect shown on hover from the fetched descriptions).
	assert_array(unit.special_rules).contains(["Banner", "Musician", "Sergeant"])
	# Each also a per-model equipment_item -> base ring on the bearer model.
	var names: Array = []
	for e in unit.equipment_items:
		names.append(e.get("name", ""))
	assert_array(names).contains(["Banner", "Musician", "Sergeant"])
	# NOT in `equipment` (the card renders equipment + special_rules, so that would double them).
	assert_bool("Banner" in unit.equipment).is_false()
	# items/weapons are ignored entirely by this pass.
	assert_bool("War Boon" in unit.special_rules).is_false()
	assert_bool("Sword" in unit.special_rules).is_false()


func test_selected_upgrade_role_count_equals_models_upgraded() -> void:
	# Two Banner selections (e.g. a merged combined unit) -> one equipment_item carried by 2 models.
	var client: OPRApiClient = auto_free(OPRApiClient.new())
	var unit := OPRApiClient.OPRUnit.new()
	unit.size = 10
	client._apply_selected_upgrade_rules(unit, [
		{"option": {"gains": [{"name": "Banner", "type": "ArmyBookRule"}]}},
		{"option": {"gains": [{"name": "Banner", "type": "ArmyBookRule"}]}},
	])
	assert_int(unit.equipment_items.size()).is_equal(1)
	assert_int(int(unit.equipment_items[0].get("count", 0))).is_equal(2)


func test_selected_upgrade_all_models_rule_is_unit_wide() -> void:
	# An "affects all models" rule upgrade is a unit-wide rule, not a per-model role.
	var client: OPRApiClient = auto_free(OPRApiClient.new())
	var unit := OPRApiClient.OPRUnit.new()
	unit.size = 5
	client._apply_selected_upgrade_rules(unit, [
		{"upgrade": {"affects": {"type": "all"}}, "option": {"gains": [{"name": "Furious", "type": "ArmyBookRule"}]}},
	])
	assert_array(unit.special_rules).contains(["Furious"])
	assert_bool("Furious" in unit.equipment).is_false()


func test_selected_upgrade_rule_with_rating_formats() -> void:
	# A rated rule on a single-model unit folds unit-wide as "Name(X)".
	var client: OPRApiClient = auto_free(OPRApiClient.new())
	var unit := OPRApiClient.OPRUnit.new()
	unit.size = 1
	client._apply_selected_upgrade_rules(unit, [
		{"option": {"gains": [{"name": "Tough", "type": "ArmyBookRule", "rating": 3}]}},
	])
	assert_array(unit.special_rules).contains(["Tough(3)"])


# ===== Base-size precedence: explicit API base data WINS, derived sizing is the fallback (QA r5) =====

func test_apply_base_recommendation_round_value_applies() -> void:
	var unit := OPRApiClient.OPRUnit.new()
	assert_bool(OPRApiClient._apply_base_recommendation(unit, {"round": "60", "square": "50"}, false)).is_true()
	assert_int(unit.base_size_round).is_equal(60)
	assert_bool(unit.base_is_oval).is_false()


func test_apply_base_recommendation_none_is_not_a_recommendation() -> void:
	var unit := OPRApiClient.OPRUnit.new()
	# Army Forge sends bases:{round:"none"} for model-less entries — NOT a usable recommendation.
	assert_bool(OPRApiClient._apply_base_recommendation(unit, {"round": "none"}, false)).is_false()
	assert_bool(OPRApiClient._apply_base_recommendation(unit, {}, false)).is_false()
	assert_bool(OPRApiClient._apply_base_recommendation(unit, null, false)).is_false()


func test_parse_unit_from_list_api_base_beats_derived() -> void:
	# The Great-Scorpion regression: the file/army-book import path used to SKIP the book's bases and
	# always Tough-derive. The book's round '60' must WIN over any derived sizing.
	var client := _client()
	var book := {"units": [{
		"id": "gs1", "name": "Great Scorpion", "size": 1, "quality": 3, "defense": 3, "cost": 100,
		"specialRules": [{"name": "Tough", "rating": "6"}],
		"bases": {"round": "60", "square": "50"},
	}]}
	var unit := client._parse_unit_from_list({"id": "gs1", "selectionId": "s1"}, book, "aof")
	assert_str(unit.name).is_equal("Great Scorpion")
	assert_int(unit.base_size_round).is_equal(60)   # the API base, NOT a derived one
	assert_bool(unit.base_from_tough).is_false()


func test_parse_unit_from_list_falls_back_to_derived_without_base() -> void:
	var client := _client()
	# No usable base in the book -> the Tough-derived fallback sizes it (Tough 6 single model,
	# no type keyword -> vehicle oval, the documented ladder anchor 52x90).
	var book := {"units": [{
		"id": "v1", "name": "Sun Barge", "size": 1, "quality": 3, "defense": 3, "cost": 100,
		"specialRules": [{"name": "Tough", "rating": "6"}],
		"bases": {"round": "none"},
	}]}
	var unit := client._parse_unit_from_list({"id": "v1", "selectionId": "s2"}, book, "aof")
	assert_bool(unit.base_from_tough).is_true()
	assert_bool(unit.base_is_oval).is_true()
	assert_int(unit.base_width_mm).is_equal(52)
	assert_int(unit.base_depth_mm).is_equal(90)
