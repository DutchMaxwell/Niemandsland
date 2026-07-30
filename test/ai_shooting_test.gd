extends GdUnitTestSuite
## Solo-AI M2 (goal 001 P3): AiShooting — ranged profiles in range, attack totals, AP extraction.


func _w(nm: String, rng: int, atk: int, count: int, rules: Array) -> Dictionary:
	return {"name": nm, "range_value": rng, "attacks": atk, "count": count, "special_rules": rules}


func test_profiles_filter_by_range_and_skip_melee() -> void:
	var weapons: Array = [
		_w("CCW", 0, 2, 10, []),              # melee — never shoots
		_w("Rifle", 24, 1, 10, []),           # in range at 18"
		_w("Pistol", 12, 1, 2, []),           # out of range at 18"
	]
	var profiles := AiShooting.profiles_in_range(weapons, 18.0)
	assert_int(profiles.size()).is_equal(1)
	assert_str(str(profiles[0]["name"])).is_equal("Rifle")
	assert_int(int(profiles[0]["attacks"])).is_equal(10)   # attacks × count


func test_profiles_carry_ap() -> void:
	var profiles := AiShooting.profiles_in_range([_w("Melter", 12, 1, 3, ["AP(4)", "Deadly(3)"])], 10.0)
	assert_int(int(profiles[0]["ap"])).is_equal(4)
	assert_int(int(profiles[0]["attacks"])).is_equal(3)


func test_profiles_carry_deadly_relentless_and_range() -> void:
	var profiles := AiShooting.profiles_in_range([_w("Sniper", 30, 1, 2, ["AP(1)", "Deadly(3)", "Relentless"])], 20.0)
	assert_int(int(profiles[0]["deadly"])).is_equal(3)
	assert_bool(bool(profiles[0]["relentless"])).is_true()
	assert_int(int(profiles[0]["range"])).is_equal(30)
	assert_int(int(profiles[0]["ap"])).is_equal(1)
	# A plain weapon carries the neutral defaults.
	var plain := AiShooting.profiles_in_range([_w("Rifle", 24, 1, 5, [])], 10.0)
	assert_int(int(plain[0]["deadly"])).is_equal(0)
	assert_bool(bool(plain[0]["relentless"])).is_false()


func test_profiles_carry_wave2_weapon_rules() -> void:
	# Surge / Rending / Bane / Thrust are pre-parsed onto the profile like the wave-1 facets.
	var profiles := AiShooting.profiles_in_range([_w("Blade", 12, 2, 1, ["Rending", "Bane", "Surge", "Thrust"])], 6.0)
	assert_bool(bool(profiles[0]["rending"])).is_true()
	assert_bool(bool(profiles[0]["bane"])).is_true()
	assert_bool(bool(profiles[0]["surge"])).is_true()
	assert_bool(bool(profiles[0]["thrust"])).is_true()
	# A plain weapon carries the neutral (false) defaults for all four.
	var plain := AiShooting.profiles_in_range([_w("Rifle", 24, 1, 5, [])], 10.0)
	assert_bool(bool(plain[0]["rending"])).is_false()
	assert_bool(bool(plain[0]["bane"])).is_false()
	assert_bool(bool(plain[0]["surge"])).is_false()
	assert_bool(bool(plain[0]["thrust"])).is_false()


func test_melee_profiles_carry_wave2_weapon_rules() -> void:
	# Thrust/Rending are melee weapon rules; they must survive onto melee profiles too.
	var profiles := AiShooting.melee_profiles([_w("Lance", 0, 1, 3, ["Thrust", "Rending"])])
	assert_bool(bool(profiles[0]["thrust"])).is_true()
	assert_bool(bool(profiles[0]["rending"])).is_true()


func test_lacerate_aliases_bane() -> void:
	# Lacerate (AoF Advanced v3.5.1) is worded identically to plain Bane, so it must raise the same
	# 'bane' facet the EV metric and save resolution read — no separate mechanic. (Coverage down-payment
	# on special-rules-coverage-plan: Lacerate is AoF's most common weapon rule, 168 occurrences.)
	var shoot := AiShooting.profiles_in_range([_w("Claw", 12, 3, 2, ["Lacerate"])], 6.0)
	assert_bool(bool(shoot[0]["bane"])).is_true()
	var melee := AiShooting.melee_profiles([_w("Rip", 0, 3, 2, ["Lacerate"])])
	assert_bool(bool(melee[0]["bane"])).is_true()


func test_boundary_range_counts_as_in_range() -> void:
	assert_int(AiShooting.profiles_in_range([_w("Rifle", 24, 1, 1, [])], 24.0).size()).is_equal(1)
	assert_int(AiShooting.profiles_in_range([_w("Rifle", 24, 1, 1, [])], 24.01).size()).is_equal(0)


func test_melee_profiles_take_only_range_zero_weapons() -> void:
	var weapons: Array = [_w("CCW", 0, 2, 5, []), _w("Claws", 0, 3, 1, ["AP(1)"]), _w("Rifle", 24, 1, 5, [])]
	var profiles := AiShooting.melee_profiles(weapons)
	assert_int(profiles.size()).is_equal(2)
	assert_int(int(profiles[0]["attacks"])).is_equal(10)   # 2 × 5
	assert_int(int(profiles[1]["ap"])).is_equal(1)


func test_total_attacks_sums_profiles() -> void:
	var profiles := AiShooting.profiles_in_range([_w("Rifle", 24, 1, 5, []), _w("Cannon", 30, 3, 1, ["AP(2)"])], 20.0)
	assert_int(AiShooting.total_attacks(profiles)).is_equal(8)
	assert_int(AiShooting.total_attacks([])).is_equal(0)


func test_melee_profiles_carry_counter_facet() -> void:
	# Counter (GF/AoF v3.5.1 p.13) is pre-parsed onto the profile for the strike-first phase.
	var profiles := AiShooting.melee_profiles([_w("Spear", 0, 1, 5, ["Counter"]), _w("Fists", 0, 2, 5, [])])
	assert_bool(bool(profiles[0]["counter"])).is_true()
	assert_bool(bool(profiles[1]["counter"])).is_false()


# === Wave-4: Destructive weapon flag (army-book — Robot Legions / Mummified Undead) ===

func test_destructive_flag_is_parsed_onto_the_profile() -> void:
	# "Destructive" (unmodified-6-to-hit → AP(+4)) is pre-parsed like the wave-1..3 facets.
	var d := AiShooting.profiles_in_range([_w("Rail Cannon", 36, 2, 1, ["AP(2)", "Destructive"])], 20.0)
	assert_int(d.size()).is_equal(1)
	assert_bool(bool((d[0] as Dictionary)["destructive"])).is_true()
	# A plain weapon does not carry it.
	var plain := AiShooting.profiles_in_range([_w("Rifle", 24, 1, 5, [])], 10.0)
	assert_bool(bool((plain[0] as Dictionary)["destructive"])).is_false()


## Resolver wave A — Hazardous ("Gets AP(4), but …"): the profile builder folds the AP(4) grant in
## and raises the hazardous flag; a weapon with better printed AP keeps it.
func test_hazardous_profile_gets_ap4_floor_and_flag() -> void:
	var p := AiShooting.profiles_in_range([_w("Warp Gun", 18, 2, 1, ["Hazardous"])], 12.0)
	assert_int(int(p[0]["ap"])).is_equal(4)
	assert_bool(bool(p[0]["hazardous"])).is_true()
	var better := AiShooting.profiles_in_range([_w("Mega Warp", 18, 2, 1, ["AP(5)", "Hazardous"])], 12.0)
	assert_int(int(better[0]["ap"])).is_equal(5)
	var plain := AiShooting.profiles_in_range([_w("Rifle", 18, 2, 1, [])], 12.0)
	assert_bool(bool(plain[0]["hazardous"])).is_false()


# ===== #217 — identical weapon entries merge into one profile =====

func test_identical_per_pick_entries_merge_into_one_volley() -> void:
	# The DAO battlesuit export: three "count 1" copies of the same weapon per pick. One
	# profile, summed dice — the aggregated-export form the engine always handled.
	var weapons: Array = [
		_w("Suit-Plasma", 18, 2, 1, ["AP(2)"]),
		_w("Suit-Plasma", 18, 2, 1, ["AP(2)"]),
		_w("Suit-Plasma", 18, 2, 1, ["AP(2)"]),
	]
	var profiles := AiShooting.profiles_in_range(weapons, 12.0)
	assert_int(profiles.size()) \
		.override_failure_message("#217 — identical per-pick entries stayed separate: they card-list and fire as N copies") \
		.is_equal(1)
	assert_int(int(profiles[0]["attacks"])).is_equal(6)
	assert_int(int(profiles[0]["count"])).is_equal(3)


func test_different_profiles_never_merge() -> void:
	var profiles := AiShooting.profiles_in_range([
		_w("Plasma", 18, 2, 1, ["AP(2)"]),
		_w("Plasma", 18, 2, 1, ["AP(4)"]),   # same name, different AP — distinct
	], 12.0)
	assert_int(profiles.size()).is_equal(2)


func test_limited_copies_keep_their_own_bookkeeping() -> void:
	var profiles := AiShooting.profiles_in_range([
		_w("Missile", 24, 1, 1, ["Limited"]),
		_w("Missile", 24, 1, 1, ["Limited"]),
	], 12.0)
	assert_int(profiles.size()).is_equal(2)   # once-per-game marks stay per weapon


func test_identical_melee_weapons_merge_too() -> void:
	var profiles := AiShooting.melee_profiles([
		_w("Heavy CCW", 0, 2, 1, ["AP(1)"]),
		_w("Heavy CCW", 0, 2, 1, ["AP(1)"]),
		_w("Heavy CCW", 0, 2, 1, ["AP(1)"]),
	])
	assert_int(profiles.size()).is_equal(1)
	assert_int(int(profiles[0]["attacks"])).is_equal(6)
