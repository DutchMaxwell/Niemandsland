extends GdUnitTestSuite
## GH #325 (PR B) — "Indirect" / "Indirect when Shooting" is read at TARGETING time, before the
## volley's target is committed: the LOS gate (solo_controller.gd "waives the LOS gate here") and
## the volley's per-model sighting must honour a spell-granted Indirect too. A per-target bridge
## is the chicken-egg the issue names — the seam reads the ATTACKER'S OWN token store instead
## (the NML-949 `spell_records` mirror), not any target's records.
##
## Data shape (spells_mechanics_aof.json Ancestral Guidance: grants_rule="Indirect when
## Shooting", beneficiary="attackers"; gf/aof "Triangulation Bots": "Indirect"). RED-GREEN:
## this suite ships BEFORE the wiring; against main the helper does not exist, so it fails.

const CONTROLLER := preload("res://scripts/solo/solo_controller.gd")


func _granted(grants: String, beneficiary: String = "", scope: String = "shooting") -> Dictionary:
	# Mirrors the record shape main.gd:_solo_record_spell_mod writes into a unit's spell-mod store.
	return {"spell": "Test Spell", "hit_mod": 0, "def_mod": 0, "casting_mod": 0,
		"morale_mod": 0, "range_in": 0, "advance_in": 0, "rush_in": 0,
		"grants_rule": grants, "scope": scope, "beneficiary": beneficiary, "duration": "once"}


func _unit() -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "u_indirect"
	u.unit_properties = {"player_id": 1, "name": "U", "quality": 4, "defense": 4, "special_rules": []}
	return u


func test_the_shooters_own_indirect_grant_waives_the_los_gate() -> void:
	# The targeting seam: the shooter's OWN token (a friendly buff granting Indirect) counts at
	# targeting time — no target needed, no per-target bridge.
	var shooter := _unit()
	shooter.unit_properties["spell_records"] = [_granted("Indirect")]
	assert_bool(CONTROLLER.granted_indirect_of(shooter)).is_true()


func test_indirect_when_shooting_names_the_same_rule() -> void:
	# The AoF encoding ("Indirect when Shooting") strips to the base name, like bridge_flag_for.
	var shooter := _unit()
	shooter.unit_properties["spell_records"] = [_granted("Indirect when Shooting")]
	assert_bool(CONTROLLER.granted_indirect_of(shooter)).is_true()


func test_a_shooter_without_the_token_stays_without_the_grant() -> void:
	# No token → no waiver; a melee-scoped grant must not fire a shooting read either.
	var shooter := _unit()
	shooter.unit_properties["spell_records"] = [_granted("Indirect", "", "melee")]
	assert_bool(CONTROLLER.granted_indirect_of(shooter)).is_false()
	assert_bool(CONTROLLER.granted_indirect_of(_unit())).is_false()


func test_an_attackers_side_record_on_the_shooter_does_not_self_benefit() -> void:
	# A record with beneficiary "attackers" on the shooter's own store names the units attacking
	# IT — the shooter must not read its own debuff as a grant (mirror of the query's filter).
	var shooter := _unit()
	shooter.unit_properties["spell_records"] = [_granted("Indirect", "attackers")]
	assert_bool(CONTROLLER.granted_indirect_of(shooter)).is_false()
