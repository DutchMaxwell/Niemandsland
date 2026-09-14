extends GdUnitTestSuite
## Sweep F row `Fortified Aura` — the aofs/gff aura entry's
## `lost_if_bearer_killed` must end the squad's Fortified AP(-1) when the
## bearer falls, and `max_picks` caps the picks. This suite pins the TABLE
## walk's pure half: the bearer-dead answer the save seam consults before it
## applies the family's reduction (main.gd `_solo_save_batch`'s bare
## "Fortified" branch and its Fortified-primitive alias walk).
##
## The registry, two spellings: aof fields "Fortified Aura" as an
## `Aura Channel` (grants the base — the benefit is NOT bearer-conditional
## by the entry's own data); aofs/gff field the aura entry as ITSELF a
## `Fortified`-primitive with `aura_expand`, `max_picks 3`,
## `lost_if_bearer_killed`. The import expansion stamps the granted base on
## the unit AND every attached hero and records the provenance
## (`unit_properties["aura_granted"]`, the Reanimation-wave stamp), so a
## granted benefit is aura-sourced exactly when the provenance lists it.

const MainScript = preload("res://scripts/main.gd")


func _squad(rules: Array, system: String, faction: String, aura_granted: Array = []) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "fa_squad"
	u.unit_properties = {"player_id": 2, "name": "Squad", "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": system, "faction_folder": faction,
		"aura_granted": aura_granted}
	var m := ModelInstance.new()
	m.is_alive = true
	u.models.append(m)
	return u


func _hero(rules: Array, alive: bool = true) -> GameUnit:
	var h := GameUnit.new()
	h.unit_id = "fa_hero"
	h.unit_properties = {"player_id": 2, "name": "Bearer", "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": "aofs", "faction_folder": "duchies_of_vinci"}
	var m := ModelInstance.new()
	m.is_alive = alive
	h.models.append(m)
	return h


## The bearer lives: the aofs squad's aura-granted Fortified stays on.
func test_bearer_alive_keeps_the_aofs_benefit() -> void:
	var squad := _squad(["Fortified"], "aofs", "duchies_of_vinci", ["Fortified"])
	var hero := _hero(["Fortified Aura", "Fortified"])
	squad.unit_properties["attached_heroes"] = [hero]
	assert_str(MainScript.fortified_aura_dead_bearer(squad, "Fortified")).is_empty()


## The bearer falls: the aura entry's `lost_if_bearer_killed` is READ — the
## save seam must stand the AP(-1) down (the helper names the dead aura so
## the seam's rules-must-log line can say so).
func test_bearer_death_ends_the_aofs_benefit() -> void:
	var squad := _squad(["Fortified"], "aofs", "duchies_of_vinci", ["Fortified"])
	assert_str(MainScript.fortified_aura_dead_bearer(squad, "Fortified")) \
		.is_equal("Fortified Aura")


## No bearer at all (the hero was never attached, or fell before the first
## save): the granted benefit is already lost.
func test_missing_bearer_ends_the_aofs_benefit() -> void:
	var squad := _squad(["Fortified"], "aofs", "duchies_of_vinci", ["Fortified"])
	assert_str(MainScript.fortified_aura_dead_bearer(squad, "Fortified")) \
		.is_equal("Fortified Aura")


## The aof spelling: the aura entry is an `Aura Channel` with no
## `lost_if_bearer_killed` — the base benefit is NOT demoted (the aof leg is
## unchanged by this sweep).
func test_aof_aura_channel_benefit_is_not_bearer_conditional() -> void:
	var squad := _squad(["Fortified"], "aof", "duchies_of_vinci", ["Fortified"])
	assert_str(MainScript.fortified_aura_dead_bearer(squad, "Fortified")).is_empty()


## A unit that OWNS the plain rule (no aura provenance) keeps it whatever
## the chain looks like.
func test_owned_fortified_is_never_bearer_conditional() -> void:
	var squad := _squad(["Fortified"], "aofs", "duchies_of_vinci", [])
	assert_str(MainScript.fortified_aura_dead_bearer(squad, "Fortified")).is_empty()


## The alias walk's spelling: the granted "Guardian Boost" (hired_guards
## fields "Guardian Boost Aura" with the same knobs) ends with its bearer.
func test_guardian_boost_spelling_ends_with_its_bearer() -> void:
	var squad := _squad(["Guardian Boost"], "aofs", "hired_guards", ["Guardian Boost"])
	assert_str(MainScript.fortified_aura_dead_bearer(squad, "Guardian Boost")) \
		.is_equal("Guardian Boost Aura")
	var alive := _squad(["Guardian Boost"], "aofs", "hired_guards", ["Guardian Boost"])
	alive.unit_properties["attached_heroes"] = [_hero(["Guardian Boost Aura", "Guardian Boost"])]
	assert_str(MainScript.fortified_aura_dead_bearer(alive, "Guardian Boost")).is_empty()
