extends GdUnitTestSuite
## NML-987 (GH #313) — Calculated Foresight (HDF L2) and the whole `beneficiary: "attackers"`
## spell family (Unpredictable Fighter, Unstoppable Aura, ...) must hand the granted rule to the
## unit shooting AT the token bearer, not stamp it on the bearer itself.
##
## Pipeline shape (main.gd:3497 _solo_record_spell_mod → main.gd:3521 _solo_apply_grant):
## the placer stores a dictionary with `grants_rule` + `beneficiary` on the target's
## _solo_spell_mods list. Today the shooter-side overlay (main.gd ~16149) reads only the
## shooter's OWN grants; the target is never asked. This suite pins the small helper that lets
## the shooter read a target's attackers-side grants, so the extra-hits pass finally sees them.
##
## RED-GREEN: this suite fails against the stub AiSpell.attacker_grants_from_target that ships
## with step 1 (returns []). Step 3 replaces the stub with the real read; the tests turn green.


func _record(grants: String, beneficiary: String, extras: Dictionary = {}) -> Dictionary:
	# Mirrors the shape `main.gd:_solo_record_spell_mod` writes into a unit's spell-mod list.
	var r := {"spell": "Test Spell", "hit_mod": 0, "def_mod": 0, "casting_mod": 0,
		"morale_mod": 0, "range_in": 0, "advance_in": 0, "rush_in": 0,
		"grants_rule": grants, "scope": "", "beneficiary": beneficiary, "duration": "once"}
	for k in extras:
		r[k] = extras[k]
	return r


func test_foresight_style_grant_surfaces_relentless_to_attackers() -> void:
	# The exact shape Calculated Foresight writes onto its enemy target (spells_mechanics_gf.json
	# entry: grants_rule=Relentless, beneficiary=attackers, duration=once). A shooter aiming at
	# that target must see "Relentless" in the pulled list, so its extra-hits pass can honour it.
	var mods := [_record("Relentless", "attackers", {"spell": "Calculated Foresight"})]
	assert_array(AiSpell.attacker_grants_from_target(mods)).contains_exactly(["Relentless"])


func test_target_beneficiary_grants_are_hidden_from_attackers() -> void:
	# A `beneficiary: "target"` grant (e.g. Evasive on the bearer) must NOT leak to the shooter —
	# that would flip a defensive buff into an offensive one. Only attackers-side grants surface.
	var mods := [_record("Evasive", "target")]
	assert_array(AiSpell.attacker_grants_from_target(mods)).is_empty()


func test_mixed_records_return_only_attacker_grants_in_order() -> void:
	# Real units carry multiple mods at once (a debuff spell + a defensive spell, say). The helper
	# picks only the attackers-side grants, and preserves placement order so the shooter's log line
	# names them in the same sequence the game placed them.
	var mods := [
		_record("Evasive", "target"),
		_record("Unstoppable", "attackers", {"spell": "Unstoppable Aura"}),
		_record("", ""),
		_record("Relentless", "attackers", {"spell": "Calculated Foresight"}),
	]
	assert_array(AiSpell.attacker_grants_from_target(mods)) \
		.contains_exactly(["Unstoppable", "Relentless"])


func test_empty_records_yield_empty_list() -> void:
	assert_array(AiSpell.attacker_grants_from_target([])).is_empty()


func test_attacker_grant_source_names_the_spell_that_placed_the_rule() -> void:
	# Origin-tag helper for the "Relentless: +N hit(s)" log line — when Relentless landed via a
	# target's Foresight token (not the shooter's own weapon), the log must name the source spell
	# so the player sees WHY the extra hits arrived. Case-insensitive on the rule side because
	# callers pass either "Relentless" (rule name) or "relentless" (profile flag).
	var mods := [
		_record("Evasive", "target", {"spell": "Silver Shield"}),
		_record("Relentless", "attackers", {"spell": "Calculated Foresight"}),
	]
	assert_str(AiSpell.attacker_grant_source(mods, "Relentless")) \
		.is_equal("Calculated Foresight")
	assert_str(AiSpell.attacker_grant_source(mods, "relentless")) \
		.is_equal("Calculated Foresight")


func test_bridge_flag_covers_every_flag_shaped_family_member() -> void:
	# The full `beneficiary: "attackers"` family sweep (2026-08-05) found these grant names with a
	# profile-flag read in the attack path. Each must map to its flag; scope suffixes ("Bane in
	# Melee", "Indirect when Shooting") name the SAME rule and must map identically.
	assert_str(AiSpell.bridge_flag_for("Relentless")).is_equal("relentless")
	assert_str(AiSpell.bridge_flag_for("Furious")).is_equal("furious")
	assert_str(AiSpell.bridge_flag_for("Rending")).is_equal("rending")
	assert_str(AiSpell.bridge_flag_for("Surge")).is_equal("surge")
	assert_str(AiSpell.bridge_flag_for("Bane")).is_equal("bane")
	assert_str(AiSpell.bridge_flag_for("Bane in Melee")).is_equal("bane")
	assert_str(AiSpell.bridge_flag_for("Shred")).is_equal("shred")
	assert_str(AiSpell.bridge_flag_for("Unstoppable")).is_equal("unstoppable")


func test_bridge_flag_refuses_rules_with_other_read_paths() -> void:
	# These family members are NOT profile flags in the attack path (unit-level rules, targeting-
	# time reads). Bridging them as flags would silently do nothing — the honest answer is "":
	# they stay visibly unfixed until their own seam lands (follow-up issue).
	for name in ["Quick Shot", "Slayer", "Rapid Charge", "Unwieldy", "Piercing Fighter",
			"Unpredictable Fighter", "Unpredictable Shooter", "Indirect", "Indirect when Shooting", ""]:
		assert_str(AiSpell.bridge_flag_for(name)).is_equal("")


func test_attacker_grant_source_returns_empty_when_no_match() -> void:
	# No matching attackers-side grant → empty string; the caller then omits the origin tag and
	# logs the plain Relentless line. Also: a target-beneficiary grant with the SAME rule name
	# must not leak (defensive Relentless on the bearer is not the shooter's Foresight).
	assert_str(AiSpell.attacker_grant_source([], "Relentless")).is_equal("")
	var only_target := [_record("Relentless", "target", {"spell": "Confused Aura"})]
	assert_str(AiSpell.attacker_grant_source(only_target, "Relentless")).is_equal("")
	var mods := [_record("Unstoppable", "attackers", {"spell": "Unstoppable Aura"})]
	assert_str(AiSpell.attacker_grant_source(mods, "Relentless")).is_equal("")
