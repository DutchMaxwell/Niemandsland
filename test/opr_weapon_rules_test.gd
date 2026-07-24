extends GdUnitTestSuite
## Weapon special-rule parsing across the REAL Army Forge shapes (maintainer field-test bug: the
## Annihilator's AP(2) never reached the defender's save). The rating may arrive as an int, float or
## String under `rating` — or ONLY inside `label` ("AP(2)"). Every shape must survive both parsers
## (share-link/TTS + file import) and reach the combat layer as a numeric AP via AiShooting.


func _client() -> OPRApiClient:
	var c: OPRApiClient = auto_free(OPRApiClient.new())
	add_child(c)
	return c


func _weapon_dict(rule: Dictionary) -> Dictionary:
	return {"name": "Annihilator", "range": 30, "attacks": 2, "count": 1, "specialRules": [rule]}


func _ap_of(weapon: OPRApiClient.OPRWeapon) -> int:
	if weapon == null:
		return -1
	var profiles: Array = AiShooting.profiles_in_range([weapon], 30.0)
	return int((profiles[0] as Dictionary).get("ap", -1)) if not profiles.is_empty() else -1


func test_int_rating_survives_both_parsers() -> void:
	var c := _client()
	var rule := {"name": "AP", "rating": 2}
	assert_int(_ap_of(c._parse_tts_weapon(_weapon_dict(rule)))).is_equal(2)
	# The file-import parser used to CRASH on int ratings ('is_empty' on an int) and drop the weapon.
	assert_int(_ap_of(c._parse_weapon(_weapon_dict(rule)))).is_equal(2)


func test_float_and_string_ratings_survive_both_parsers() -> void:
	var c := _client()
	assert_int(_ap_of(c._parse_tts_weapon(_weapon_dict({"name": "AP", "rating": 2.0})))).is_equal(2)
	assert_int(_ap_of(c._parse_weapon(_weapon_dict({"name": "AP", "rating": 2.0})))).is_equal(2)
	assert_int(_ap_of(c._parse_tts_weapon(_weapon_dict({"name": "AP", "rating": "2"})))).is_equal(2)
	assert_int(_ap_of(c._parse_weapon(_weapon_dict({"name": "AP", "rating": "2"})))).is_equal(2)


func test_label_only_rating_survives_both_parsers() -> void:
	# The field-test shape: no `rating` key at all — the value lives only in the label. Both parsers
	# used to store a bare "AP", which the combat layer reads as AP 0 (Defense unmodified).
	var c := _client()
	var rule := {"name": "AP", "label": "AP(2)"}
	assert_int(_ap_of(c._parse_tts_weapon(_weapon_dict(rule)))).is_equal(2)
	assert_int(_ap_of(c._parse_weapon(_weapon_dict(rule)))).is_equal(2)


func test_flag_rules_stay_bare_names() -> void:
	var c := _client()
	var w: OPRApiClient.OPRWeapon = c._parse_tts_weapon(_weapon_dict({"name": "Relentless"}))
	assert_array(w.special_rules).is_equal(["Relentless"])
	var w2: OPRApiClient.OPRWeapon = c._parse_weapon(_weapon_dict({"name": "Relentless", "label": "Relentless"}))
	assert_array(w2.special_rules).is_equal(["Relentless"])


func test_save_threshold_math_and_the_6_always_succeeds_floor() -> void:
	# GF v3.5.1 AP(X): "Targets get -X to Defense rolls" → the save target is Defense + AP…
	assert_int(AiCombatMath.save_target(4, 2)).is_equal(6)
	# …and there is NO cap: Def 5 + AP 2 = 7 still leaves 6s succeeding ("rolls of 6 always succeed"),
	# so a save can never become impossible.
	assert_bool(DiceRules.is_success(6, 7, 0)).is_true()
	assert_bool(DiceRules.is_success(5, 7, 0)).is_false()


func test_deadly_label_only_rating_reaches_the_profile() -> void:
	# The maintainer's "Deadly not multiplying" report: a label-only Deadly(3) degraded to a bare
	# "Deadly" → multiplier 0. Same parser fix as AP — pin it end-to-end into the AiShooting profile.
	var c := _client()
	var w: OPRApiClient.OPRWeapon = c._parse_tts_weapon(
		{"name": "Fist", "range": 12, "attacks": 2, "count": 1, "specialRules": [{"name": "Deadly", "label": "Deadly(3)"}]})
	var prof := AiShooting.profiles_in_range([w], 12.0)[0] as Dictionary
	assert_int(int(prof["deadly"])).is_equal(3)
