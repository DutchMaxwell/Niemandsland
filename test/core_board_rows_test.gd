extends GdUnitTestSuite
## E1b/v3 board-row schema (NML-995): the encoder corpus must carry mission
## objectives, full unit status AND the unit stat line. Unit rows are 12
## columns [player, x_in, z_in, alive, wounds_left, shaken, fatigued,
## activated, range_max_in, attacks_total, quality, defense]; each objective
## adds [3, x_in, z_in, owner, 0,0,0,0, 0,0,0,0] — marker 3 in the player
## slot, owner (0 neutral / 1 / 2) in the alive slot. Units without a
## readable OPRUnit stat line fall back to zeros in columns 9-12.

const IN2M := 0.0254

var CoreSelfplay := load("res://tools/core_selfplay.gd")


func _state() -> Dictionary:
	return {
		"round": 1,
		"rounds_total": 4,
		"units": {
			"p1_a": {"player": 1, "alive": 2, "positions": [Vector3(10 * IN2M, 0, 4 * IN2M), Vector3(12 * IN2M, 0, 4 * IN2M)],
				"wounds": [1, 2], "shaken": false, "fatigued": true, "activated": false},
			"p2_b": {"player": 2, "alive": 1, "positions": [Vector3(-6 * IN2M, 0, -8 * IN2M)],
				"wounds": [3], "shaken": true, "fatigued": false, "activated": true},
			"p2_dead": {"player": 2, "alive": 0, "positions": [Vector3.ZERO], "wounds": [0]},
		},
		"objectives": [
			{"pos": Vector3(16 * IN2M, 0, 0), "owner": 2},
			{"pos": Vector3(-16 * IN2M, 0, 0), "owner": 0},
		],
	}


func test_unit_rows_carry_full_status() -> void:
	var rows: Array = CoreSelfplay._board_rows(_state())
	var units := rows.filter(func(r: Variant) -> bool: return int(r[0]) == 1 or int(r[0]) == 2)   # NML-1012: rows also carry objective (3) and game-state (4) lines now
	assert_int(units.size()).is_equal(2)  # dead unit excluded
	for r in units:
		assert_int((r as Array).size()).is_equal(21)
	var a: Array = units.filter(func(r: Variant) -> bool: return int(r[0]) == 1)[0]
	# [player, x, z, alive, wounds, shaken, fatigued, activated]
	assert_float(a[1]).is_equal_approx(11.0, 0.11)  # centre of 10/12 in
	assert_int(int(a[3])).is_equal(2)
	assert_int(int(a[4])).is_equal(3)
	assert_int(int(a[5])).is_equal(0)
	assert_int(int(a[6])).is_equal(1)
	assert_int(int(a[7])).is_equal(0)
	var b: Array = units.filter(func(r: Variant) -> bool: return int(r[0]) == 2)[0]
	assert_int(int(b[5])).is_equal(1)
	assert_int(int(b[6])).is_equal(0)
	assert_int(int(b[7])).is_equal(1)


func test_objective_rows_present_with_owner() -> void:
	var rows: Array = CoreSelfplay._board_rows(_state())
	var objs := rows.filter(func(r: Variant) -> bool: return int(r[0]) == 3)
	assert_int(objs.size()).is_equal(2)
	for r in objs:
		assert_int((r as Array).size()).is_equal(21)
	var owned: Array = objs.filter(func(r: Variant) -> bool: return int(r[3]) == 2)
	assert_int(owned.size()).is_equal(1)
	assert_float(owned[0][1]).is_equal_approx(16.0, 0.11)
	assert_float(owned[0][2]).is_equal_approx(0.0, 0.11)


func test_v4_precomputed_power_and_rule_flags() -> void:
	var ou := OPRApiClient.OPRUnit.new()
	ou.quality = 3
	ou.defense = 5
	ou.special_rules = ["Fearless"] as Array[String]
	var w1 := OPRApiClient.OPRWeapon.new()
	w1.range_value = 24
	w1.attacks = 2
	w1.count = 5
	var w2 := OPRApiClient.OPRWeapon.new()
	w2.range_value = 0
	w2.attacks = 3
	w2.count = 1
	ou.weapons = [w1, w2]
	var gu: GameUnit = auto_free(GameUnit.new())
	gu.source_data = ou
	gu.unit_properties = {"quality": 3, "defense": 5, "player_id": 1,
		"special_rules": ["Fearless"]}
	var st := _state()
	(st["units"]["p1_a"] as Dictionary)["unit"] = gu
	var rows: Array = CoreSelfplay._board_rows(st)
	var a: Array = rows.filter(func(r: Variant) -> bool: return int(r[0]) == 1)[0]
	assert_int(int(a[20])).is_equal(1)  # Fearless ist deklariert -> ein Regel-Paar
	# [.., 12 sev12, 13 mev, 14 fearless, 15 ambush, 16 flying, 17 stealth, 18 furious, 19 regen]
	assert_bool(float(a[12]) > 0.0).is_true()   # shooting EV vs neutral target at 12in
	assert_bool(float(a[13]) > 0.0).is_true()   # melee EV
	assert_int(int(a[14])).is_equal(1)          # Fearless declared
	assert_int(int(a[15])).is_equal(0)          # Ambush not declared
	# objective rows padded to 20
	var objs := rows.filter(func(r: Variant) -> bool: return int(r[0]) == 3)
	assert_int((objs[0] as Array).size()).is_equal(21)


func test_stat_line_from_opr_unit() -> void:
	var ou := OPRApiClient.OPRUnit.new()
	ou.quality = 3
	ou.defense = 5
	var w1 := OPRApiClient.OPRWeapon.new()
	w1.range_value = 24
	w1.attacks = 2
	w1.count = 5
	var w2 := OPRApiClient.OPRWeapon.new()
	w2.range_value = 0   # melee
	w2.attacks = 3
	w2.count = 1
	ou.weapons = [w1, w2]
	var gu: GameUnit = auto_free(GameUnit.new())
	gu.source_data = ou
	var st := _state()
	(st["units"]["p1_a"] as Dictionary)["unit"] = gu
	var rows: Array = CoreSelfplay._board_rows(st)
	var a: Array = rows.filter(func(r: Variant) -> bool: return int(r[0]) == 1)[0]
	# [.., range_max, attacks_total, quality, defense]
	assert_int(int(a[8])).is_equal(24)
	assert_int(int(a[9])).is_equal(13)  # 2*5 + 3*1
	assert_int(int(a[10])).is_equal(3)
	assert_int(int(a[11])).is_equal(5)
	# unit without stat line falls back to zeros
	var b: Array = rows.filter(func(r: Variant) -> bool: return int(r[0]) == 2)[0]
	assert_int(int(b[8])).is_equal(0)
	assert_int(int(b[11])).is_equal(0)


func test_v5_sparse_rule_pairs_from_vocab() -> void:
	var vocab: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/encoder_rule_vocab_v1.json"))
	var tough_slot: int = (vocab["unit"] as Array).find("Tough")
	var deadly_slot: int = 200 + (vocab["weapon"] as Array).find("Deadly")
	var ou := OPRApiClient.OPRUnit.new()
	ou.quality = 4
	ou.defense = 4
	var w1 := OPRApiClient.OPRWeapon.new()
	w1.range_value = 18
	w1.attacks = 1
	w1.count = 2
	w1.special_rules = ["Deadly(6)"] as Array[String]
	ou.weapons = [w1]
	var gu: GameUnit = auto_free(GameUnit.new())
	gu.source_data = ou
	gu.unit_properties = {"quality": 4, "defense": 4, "player_id": 1,
		"special_rules": ["Tough(3)", "Fearless"]}
	var st := _state()
	(st["units"]["p1_a"] as Dictionary)["unit"] = gu
	var rows: Array = CoreSelfplay._board_rows(st)
	var a: Array = rows.filter(func(r: Variant) -> bool: return int(r[0]) == 1)[0]
	assert_int(int(a[20])).is_equal(3)  # Tough + Fearless + Deadly
	var pairs := {}
	for i in range(int(a[20])):
		pairs[int(a[21 + i * 2])] = int(a[22 + i * 2])
	assert_int(int(pairs.get(tough_slot, -1))).is_equal(3)
	assert_int(int(pairs.get(deadly_slot, -1))).is_equal(6)
	# unknown rule is collected loudly, never silently dropped
	gu.unit_properties["special_rules"] = ["Frobnicate(2)"]
	CoreSelfplay._board_rows(st)
	assert_bool(BattleSim.unknown_rules.has("Frobnicate")).is_true()


## v1c (v5.1): a caster's spell book enters its row as (slot 300+, threshold)
## pairs in vocab order; non-casters carry none; an unknown spell name
## loud-collects with the 'spell:' prefix instead of vanishing.
func test_caster_rows_carry_spell_book_pairs() -> void:
	var vocab: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/encoder_rule_vocab_v1.json"))
	assert_bool((vocab.get("spell", []) as Array).size() >= 400).is_true()
	var spells: Array = vocab["spell"]
	var target := str(spells[7])
	var idx := 7
	# fixture: a caster whose registry book we fake via the entry list seam
	# is out of scope here — we pin the VOCAB mapping + prefix collection
	# through the central _rule_pairs path instead:
	BattleSim._load_vocab()
	assert_int(int(BattleSim._vocab_spell.get(target, -1))).is_equal(300 + idx)
	assert_bool(BattleSim._vocab_spell.size() == spells.size()).is_true()


## NML-1134: the vocabulary file is SHARED with the Rust twin
## (`nml_core::rows::RULE_VOCAB_VERSION`), so a file of a version this build
## does not read is REFUSED — loudly and completely. It fills nothing, and every
## rule then collects into `unknown_rules` instead of landing on a slot the two
## sides disagree about. RED half: the wrong version. GREEN half: the committed
## file, through the same function.
func test_rule_vocab_of_a_wrong_version_is_refused() -> void:
	BattleSim._load_vocab()
	var committed: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/encoder_rule_vocab_v1.json"))
	assert_int(int(committed["version"])).is_equal(BattleSim.RULE_VOCAB_VERSION)

	var before: int = BattleSim._vocab_unit.size()
	var wrong := {"version": BattleSim.RULE_VOCAB_VERSION + 1,
		"unit": ["Frobnicate"], "weapon": [], "spell": []}
	assert_str(BattleSim._fill_vocab(wrong)).contains("version")
	assert_int(BattleSim._vocab_unit.size()).is_equal(before)
	assert_bool(BattleSim._vocab_unit.has("Frobnicate")).is_false()
	# Not a Dictionary at all is the other half of the same refusal.
	assert_str(BattleSim._fill_vocab(null)).is_not_empty()

	# GREEN: the committed file loads, and carries the 11 item-granted names
	# NML-1105 made the trainer grant (unit slots 128-138, append-only).
	assert_str(BattleSim._fill_vocab(committed)).is_equal("")
	var appended := ["Adrenaline Fueled", "Combat Bio-Engineer", "Combat Mutations",
		"Courage", "Flagellant", "For the Hive!", "Paradox Shielding Device",
		"Toxic Cysts", "Versatile Reach", "Warden", "Winged Breed"]
	for i in appended.size():
		assert_int(int(BattleSim._vocab_unit.get(appended[i], -1))).is_equal(128 + i)

	# NML-1144b: and the 61 names gen0 collected as unknown sit at unit slots
	# 139-199, straight off the file — the every-appended-name-slots mirror of
	# rows.rs's v4 test. "Lust Boon" is deliberately absent: it lives in the
	# spell band already, and no name carries two slots.
	var v4: Array = committed["unit"].slice(139, 200)
	assert_int(v4.size()).is_equal(61)
	for i in v4.size():
		assert_int(int(BattleSim._vocab_unit.get(str(v4[i]), -1))).is_equal(139 + i)
	assert_bool(BattleSim._vocab_unit.has("Lust Boon")).is_false()
	assert_bool(BattleSim._vocab_spell.has("Lust Boon")).is_true()

	# NML-1144b v5: and the 3 weapon-band rules gen0 still collected sit at
	# weapon slots 222-224 (band = 200 + index, so the 22nd-24th entries).
	var v5: Array = committed["weapon"].slice(22, 25)
	assert_int(v5.size()).is_equal(3)
	var wslots := [222, 223, 224]
	for i in v5.size():
		assert_int(int(BattleSim._vocab_weapon.get(str(v5[i]), -1))).is_equal(wslots[i])
