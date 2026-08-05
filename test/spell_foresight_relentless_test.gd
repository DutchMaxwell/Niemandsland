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
