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
