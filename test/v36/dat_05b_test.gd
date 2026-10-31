extends GdUnitTestSuite
## Rules 3.6 wave, row DAT-05b: three weapon rules were renamed without a mechanic change
## (Crossing Strike = Strafing, Fracture = Crack, Puncture = Disintegrate). A rules 3.6 book that
## fielded the new name had no map entry, so the table printed "apply manually" and did nothing.
## Each case below is a book that fields the new name in 3.6 and has no faction entry for it; the
## lookup must reach ONE common entry per system. The controls pin that the old-name entries (and
## the 3.6 "Disintegrate", which is a different rule now) stay byte-for-byte untouched.

const GAP_CASES := [
	["gf", "alien_hives", "Crossing Strike", "Strafing", {"move_through_attack": true, "weapon_only": true}],
	["gf", "high_elf_fleets", "Fracture", "Crack", {"on6_ap": 2}],
	["gf", "dao_union", "Puncture", "Disintegrate", {"ap_bonus": 2, "condition": "vs_armor", "threshold": 3, "bypass_regen": true}],
	["aof", "dragon_empire", "Crossing Strike", "Strafing", {"move_through_attack": true, "weapon_only": true}],
	["aof", "high_elves", "Fracture", "Crack", {"on6_ap": 2}],
	["aof", "duchies_of_vinci", "Puncture", "Disintegrate", {"ap_bonus": 2, "condition": "vs_armor", "threshold": 3, "bypass_regen": true}],
]


func before_test() -> void:
	RulesRegistry.reset_cache()


func after_test() -> void:
	RulesRegistry.reset_cache()


## The map's JSON numbers load as floats, so params compare key by key, numbers by value.
func _params_match(actual: Dictionary, expected: Dictionary) -> bool:
	if actual.size() != expected.size():
		return false
	for k in expected:
		if not actual.has(k):
			return false
		var want: Variant = expected[k]
		var got: Variant = actual[k]
		if want is int or want is float:
			if not (got is int or got is float) or not is_equal_approx(float(got), float(want)):
				return false
		elif got != want:
			return false
	return true


func test_every_gap_book_resolves_its_renamed_rule_from_common() -> void:
	for c in GAP_CASES:
		var system := str(c[0])
		var book := str(c[1])
		var rule := str(c[2])
		var entry := RulesRegistry.lookup(system, book, rule)
		assert_str(str(entry.get("primitive", ""))) \
			.override_failure_message("%s/%s: %s resolves to nothing, the table never applies it" % [system, book, rule]) \
			.is_equal(str(c[3]))
		assert_bool(_params_match(entry.get("params", {}) as Dictionary, c[4] as Dictionary)) \
			.override_failure_message("%s/%s: %s params differ from the 3.5 twin" % [system, book, rule]) \
			.is_true()
		assert_str(str(entry.get("book_version", ""))) \
			.override_failure_message("%s/%s: %s carries the wrong book stamp" % [system, book, rule]) \
			.is_equal("3.6.0")


## Control: the old-name entries are add-only untouched (the later cleanup row removes them).
func test_old_name_entries_stay_unchanged() -> void:
	var crack := RulesRegistry.lookup("gf", "high_elf_fleets", "Crack")
	assert_str(str(crack.get("primitive", ""))).is_equal("Crack")
	assert_bool(_params_match(crack.get("params", {}) as Dictionary, {"on6_ap": 2})).is_true()
	assert_str(str(crack.get("book_version", ""))).is_equal("3.5.3")
	# 3.6 "Disintegrate" is a different rule now; the old entry must not move.
	var dis := RulesRegistry.lookup("aof", "duchies_of_vinci", "Disintegrate")
	assert_str(str(dis.get("primitive", ""))).is_equal("Disintegrate")
	assert_bool(_params_match(dis.get("params", {}) as Dictionary,
		{"ap_bonus": 2, "condition": "vs_armor", "threshold": 3, "bypass_regen": true})).is_true()
	assert_str(str(dis.get("book_version", ""))).is_equal("3.5.3")
