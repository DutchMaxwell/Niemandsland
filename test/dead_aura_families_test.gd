extends GdUnitTestSuite
## NML-931 — the nine dead aura families.
##
## An army-book "X Aura" reads "this model and its unit get X", and the import expands it by stamping
## the bare name X onto the unit (OPRArmyManager._expand_auras -> AiEv.aura_granted_rules). So the aura
## only DOES something if something resolves: either the aura entry itself carries a primitive
## (pattern A), or a rule named exactly X resolves for the SAME (system, faction) through the registry's
## faction->common fallback (pattern B). Nine families satisfied neither — the unit was handed a name
## that resolved nowhere, and the ability never reached the table.
##
## This suite pins BOTH halves: that the granted rule now resolves, and that it actually changes a
## number. The invariant at the bottom is the standing net — it fails the moment a new aura family
## ships dead again.

const SYSTEMS := ["gf", "gff", "aof", "aofs", "aofr"]

## The aura families that are still knowingly open — they need a mechanic that does not exist yet, so
## they are a separate wave, not a data fix. Anything NOT on this list must resolve.
const KNOWN_OPEN := ["Thrust in Melee", "Piercing Fighter", "Piercing Shooter"]


func _unit_with(rules: Array, system: String, faction: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "t_%d" % rules.size()
	u.unit_properties = {"player_id": 2, "name": "T", "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": system, "faction_folder": faction}
	var m := ModelInstance.new()
	m.is_alive = true
	u.models.append(m)
	return u


## The unit an import produces for a model carrying "<base> Aura": the aura name stays on the carrier,
## and _expand_auras adds the bare base name. Both are on the unit, exactly as in play.
func _aura_carrier(base: String, system: String, faction: String) -> GameUnit:
	return _unit_with([base + " Aura", base], system, faction)


func _shoot_profile(reach: int = 24) -> Dictionary:
	return {"range": reach, "attacks": 2, "ap": 0, "rules": []}


func _melee_profile() -> Dictionary:
	return {"range": 0, "attacks": 2, "ap": 0, "rules": []}


# --- the nine families: the granted rule resolves at all -----------------------------------------

func test_family_1_shred_when_shooting_resolves_in_every_book_that_grants_it() -> void:
	# aof/aofr fielded the aura but had no "Shred when Shooting" in their core (gf/gff did).
	for pair in [["aof", "change_disciples"], ["aof", "war_disciples"], ["aofr", "deep_sea_elves"],
			["aofr", "plague_disciples"]]:
		var u := _aura_carrier("Shred when Shooting", str(pair[0]), str(pair[1]))
		assert_bool(RulesRegistry.unit_rule_active(u, "Shred when Shooting")) \
			.override_failure_message("%s/%s: the granted Shred when Shooting resolves nowhere" % pair).is_true()
		assert_str(str(RulesRegistry.lookup(str(pair[0]), str(pair[1]), "Shred when Shooting").get("primitive", ""))) \
			.is_equal("Shred")
	# It is the SHOOTING half — the gate the stamps read must say so. The four books whose auras are
	# healed through the base rule carry it in core; aofs heals its own six through the aura entry
	# itself (pattern A) and needs no core entry, which the family test above already covers.
	for s in ["gf", "gff", "aof", "aofr"]:
		var p: Dictionary = RulesRegistry.lookup(str(s), "", "Shred when Shooting").get("params", {})
		assert_bool(bool(p.get("shooting_only", false))) \
			.override_failure_message("%s: Shred when Shooting is not gated to shooting" % s).is_true()
	for faction in ["change_disciples", "war_disciples"]:
		var aofs_entry := RulesRegistry.lookup("aofs", str(faction), "Shred when Shooting Aura")
		assert_str(str(aofs_entry.get("primitive", ""))).is_equal("Shred")
		assert_bool(bool((aofs_entry.get("params", {}) as Dictionary).get("shooting_only", false))).is_true()


func test_family_2_rending_when_shooting_exists_in_all_five_books() -> void:
	for s in SYSTEMS:
		var e := RulesRegistry.lookup(str(s), "", "Rending when Shooting")
		assert_str(str(e.get("primitive", ""))).override_failure_message("%s misses it" % s).is_equal("Rending")
		var p: Dictionary = e.get("params", {})
		assert_int(int(p.get("on6_ap", 0))).is_equal(4)                 # same lever as Rending in Melee
		assert_bool(bool(p.get("bypass_regen", false))).is_true()
		assert_bool(bool(p.get("shooting_only", false))).is_true()
		assert_bool(bool(p.get("melee_only", false))).is_false()
	for pair in [["gf", "machine_cults"], ["aof", "halflings"], ["aofs", "hidden_syndicates"],
			["aofr", "sky_city_dwarves"], ["gff", "shortling_federations"]]:
		var u := _aura_carrier("Rending when Shooting", str(pair[0]), str(pair[1]))
		assert_bool(RulesRegistry.unit_rule_active(u, "Rending when Shooting")) \
			.override_failure_message("%s/%s: resolves nowhere" % pair).is_true()


func test_family_3_unstoppable_in_melee_resolves_in_aofs_too() -> void:
	# The one system whose core file had lost the entry; its four books fielded the aura regardless.
	for faction in ["duchies_of_vinci", "eternal_wardens", "rift_daemons_of_change", "volcanic_dwarves"]:
		var u := _aura_carrier("Unstoppable in Melee", "aofs", str(faction))
		assert_bool(RulesRegistry.unit_rule_active(u, "Unstoppable in Melee")) \
			.override_failure_message("aofs/%s: resolves nowhere" % faction).is_true()
	var p: Dictionary = RulesRegistry.lookup("aofs", "", "Unstoppable in Melee").get("params", {})
	assert_bool(bool(p.get("bypass_regen", false))).is_true()
	assert_bool(bool(p.get("melee_only", false))).is_true()


func test_families_4_to_6_precision_auras_carry_the_shot_modifier() -> void:
	var cases := {
		"Precision Fighter Aura": [["gf", "jackals"], ["gf", "eternal_dynasty"], ["aof", "halflings"],
			["aofr", "ratmen"]],
		"Precision Shooter Aura": [["gf", "ratmen_clans"], ["aof", "beastmen"], ["aofr", "beastmen"]],
		"Precision Charge Aura": [["gf", "orc_marauders"], ["aof", "dwarves"], ["aofr", "dwarves"]],
	}
	for rule_name in cases:
		for pair in cases[rule_name]:
			var e := RulesRegistry.lookup(str(pair[0]), str(pair[1]), str(rule_name))
			assert_str(str(e.get("primitive", ""))) \
				.override_failure_message("%s/%s %s: no primitive" % [pair[0], pair[1], rule_name]) \
				.is_equal("Shot Modifier")
			assert_int(int((e.get("params", {}) as Dictionary).get("hit_bonus", 0))).is_equal(1)
	# Each of the three is scoped to a DIFFERENT half of the game — that scoping is the whole point.
	assert_bool(bool((RulesRegistry.lookup("gf", "jackals", "Precision Fighter Aura").get("params", {}) as Dictionary)
		.get("melee_only", false))).is_true()
	assert_str(str((RulesRegistry.lookup("gf", "ratmen_clans", "Precision Shooter Aura").get("params", {}) as Dictionary)
		.get("phase", ""))).is_equal("shoot")
	assert_str(str((RulesRegistry.lookup("gf", "orc_marauders", "Precision Charge Aura").get("params", {}) as Dictionary)
		.get("when", ""))).is_equal("charge")


func test_family_8_indirect_when_shooting_resolves_in_gf() -> void:
	var u := _aura_carrier("Indirect when Shooting", "gf", "wormhole_daemons_of_change")
	assert_bool(RulesRegistry.unit_rule_active(u, "Indirect when Shooting")).is_true()
	var p: Dictionary = RulesRegistry.lookup("gf", "", "Indirect when Shooting").get("params", {})
	assert_bool(bool(p.get("ignores_los", false))).is_true()
	assert_bool(bool(p.get("ignores_cover", false))).is_true()
	assert_int(int(p.get("moved_hit_penalty", 0))).is_equal(1)


func test_family_9_hit_and_run_fighter_passes_the_gate_the_mover_actually_checks() -> void:
	# SoloController.hit_and_run_move asks EXACTLY this conjunction before it moves the unit. The
	# aofs/crazed_zealots book granted the name without owning the rule, so the second half said no.
	var u := _aura_carrier("Hit & Run Fighter", "aofs", "crazed_zealots")
	assert_bool(AiEv.has_exact_rule(u, "Hit & Run Fighter")).is_true()
	assert_bool(RulesRegistry.unit_rule_active(u, "Hit & Run Fighter")) \
		.override_failure_message("aofs/crazed_zealots: the granted Hit & Run Fighter still resolves nowhere").is_true()
	assert_float(float(RulesRegistry.unit_param(u, "Hit & Run Fighter", "move_in", 0.0))).is_equal_approx(3.0, 0.001)
	# A book that does NOT field it must stay untouched (no cross-book bleed through the common map).
	assert_bool(RulesRegistry.unit_rule_active(_aura_carrier("Hit & Run Fighter", "aofs", "ogres"),
		"Hit & Run Fighter")).is_false()


func test_borderline_unstoppable_when_shooting_resolves_and_is_shooting_scoped() -> void:
	for s in SYSTEMS:
		var e := RulesRegistry.lookup(str(s), "", "Unstoppable when Shooting")
		assert_str(str(e.get("primitive", ""))).override_failure_message("%s misses it" % s).is_equal("Lacerate")
		var p: Dictionary = e.get("params", {})
		assert_bool(bool(p.get("bypass_regen", false))).is_true()
		assert_bool(bool(p.get("shooting_only", false))).is_true()
		assert_bool(bool(p.get("melee_only", false))).is_false()


# --- the effects: the granted rule now changes a number ------------------------------------------

func test_effect_range_bonus_reaches_the_one_reader_every_consumer_uses() -> void:
	# Pattern A, real effect: SoloController.shooting_range_bonus feeds the AI's reach, the human's
	# target validity and the sight ring. Before the fix the aura carrier read 0".
	for pair in [["gf", "dwarf_guilds"], ["gf", "blessed_sisters"], ["aof", "shadow_stalkers"],
			["aofr", "havoc_dwarves"]]:
		var u := _aura_carrier("Increased Shooting Range", str(pair[0]), str(pair[1]))
		assert_int(SoloController.shooting_range_bonus(u)) \
			.override_failure_message("%s/%s: aura carrier still shoots at printed range" % pair).is_equal(6)
	# A unit without the aura is untouched.
	assert_int(SoloController.shooting_range_bonus(_unit_with([], "gf", "dwarf_guilds"))).is_equal(0)
	# Range only — the rule grants no charge movement, so the Royal Legion charge lever must read 0.
	assert_int(int(RulesRegistry.unit_param(_aura_carrier("Increased Shooting Range", "gf", "dwarf_guilds"),
		"Increased Shooting Range Aura", "charge_mod", -1))).is_equal(0)


func test_effect_rending_facet_lands_on_the_shooting_profile_only() -> void:
	# Pattern B, real effect: AiEv.stamp_sergeant is the ONE stamping both the EV metric and the dice
	# path read. The facet must appear on the ranged profile and stay off the melee profile.
	var u := _aura_carrier("Rending when Shooting", "aof", "halflings")
	var shoot := _shoot_profile()
	var melee := _melee_profile()
	AiEv.stamp_sergeant([shoot, melee], u)
	assert_bool(bool(shoot.get("rending", false))) \
		.override_failure_message("the granted Rending never reached the shooting profile").is_true()
	assert_bool(bool(melee.get("rending", false))) \
		.override_failure_message("a shooting-only Rending leaked into melee").is_false()
	# Its melee sibling is the mirror image — same primitive, opposite half.
	var m := _aura_carrier("Rending in Melee", "aof", "halflings")
	var shoot2 := _shoot_profile()
	var melee2 := _melee_profile()
	AiEv.stamp_sergeant([shoot2, melee2], m)
	assert_bool(bool(melee2.get("rending", false))).is_true()
	assert_bool(bool(shoot2.get("rending", false))).is_false()


func test_effect_facet_gate_is_one_truth_for_both_halves() -> void:
	# The gate every unit-level stamp now shares. Before this wave `shooting_only` was read in exactly
	# ONE place in the engine, so a shooting-gated rule still fired in melee everywhere else.
	assert_bool(AiEv.facet_applies({"melee_only": true}, 0)).is_true()
	assert_bool(AiEv.facet_applies({"melee_only": true}, 24)).is_false()
	assert_bool(AiEv.facet_applies({"shooting_only": true}, 24)).is_true()
	assert_bool(AiEv.facet_applies({"shooting_only": true}, 0)).is_false()
	assert_bool(AiEv.facet_applies({}, 0)).is_true()          # ungated rules keep applying to both
	assert_bool(AiEv.facet_applies({}, 24)).is_true()
	# The live params, not invented ones: the two Shred halves must answer opposite questions.
	var shooting: Dictionary = RulesRegistry.lookup("aof", "", "Shred when Shooting").get("params", {})
	var melee: Dictionary = RulesRegistry.lookup("aof", "", "Shred in Melee").get("params", {})
	assert_bool(AiEv.facet_applies(shooting, 24)).is_true()
	assert_bool(AiEv.facet_applies(shooting, 0)).is_false()
	assert_bool(AiEv.facet_applies(melee, 0)).is_true()
	assert_bool(AiEv.facet_applies(melee, 24)).is_false()


func test_effect_predator_shooter_no_longer_spawns_its_extra_attack_in_melee() -> void:
	# The leak the shared gate closed on the way past: Predator Shooter is Surge + shooting_only, and
	# stamp_sergeant's Surge loop only ever read melee_only.
	var p: Dictionary = RulesRegistry.lookup("gf", "alien_hives", "Predator Shooter").get("params", {})
	if p.is_empty():
		return   # book data moved on; the gate itself is pinned above
	var u := _unit_with(["Predator Shooter"], "gf", "alien_hives")
	var shoot := _shoot_profile()
	var melee := _melee_profile()
	AiEv.stamp_sergeant([shoot, melee], u)
	assert_bool(bool(melee.get("surge_attack", false)) or bool(melee.get("surge", false))) \
		.override_failure_message("a shooting-only Surge still fires in melee").is_false()


# --- the standing net ----------------------------------------------------------------------------

func test_no_aura_grants_a_rule_that_resolves_nowhere() -> void:
	# THE invariant. For every "X Aura" in every book of every system: either the aura entry itself
	# automates the effect, or the bare "X" the import stamps onto the unit resolves for that same
	# (system, faction). Otherwise the book promises an ability the table never sees.
	var dead: Dictionary = {}
	var checked := 0
	for s in SYSTEMS:
		var m := RulesRegistry.map_for(str(s))
		assert_bool(m.is_empty()).override_failure_message("map missing for %s" % s).is_false()
		for faction in (m.get("factions", {}) as Dictionary):
			var rules: Dictionary = (m["factions"] as Dictionary)[faction]
			for rule_name in rules:
				if not str(rule_name).ends_with(" Aura"):
					continue
				checked += 1
				var base := str(rule_name).trim_suffix(" Aura")
				if KNOWN_OPEN.has(base):
					continue
				if RulesRegistry.has_primitive(str(s), str(faction), str(rule_name)):
					continue      # pattern A — the aura entry automates it itself
				if RulesRegistry.has_primitive(str(s), str(faction), base):
					continue      # pattern B — the granted base rule resolves
				dead[base] = int(dead.get(base, 0)) + 1
	assert_int(checked).override_failure_message("no aura entries scanned — the maps did not load").is_greater(500)
	assert_dict(dead).override_failure_message(
		"aura families granting a rule that resolves nowhere: %s" % str(dead)).is_empty()


func test_the_known_open_families_are_still_exactly_three() -> void:
	# The debt this wave deliberately did NOT take: they need a mechanic that does not exist yet.
	# If one of them gets built, it must drop off KNOWN_OPEN — this test is what forces that.
	var open_counts: Dictionary = {}
	for s in SYSTEMS:
		var m := RulesRegistry.map_for(str(s))
		for faction in (m.get("factions", {}) as Dictionary):
			var rules: Dictionary = (m["factions"] as Dictionary)[faction]
			for rule_name in rules:
				if not str(rule_name).ends_with(" Aura"):
					continue
				var base := str(rule_name).trim_suffix(" Aura")
				if not KNOWN_OPEN.has(base):
					continue
				if RulesRegistry.has_primitive(str(s), str(faction), str(rule_name)) \
						or RulesRegistry.has_primitive(str(s), str(faction), base):
					continue
				open_counts[base] = int(open_counts.get(base, 0)) + 1
	for base in KNOWN_OPEN:
		assert_bool(open_counts.has(base)) \
			.override_failure_message("%s now resolves — take it off KNOWN_OPEN" % base).is_true()
