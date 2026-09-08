extends GdUnitTestSuite
## GH #325 — spell-granted ATTACKER rules must be honoured exactly where the unit's own rule is
## read. The family rides the #313 record shape ({grants_rule, beneficiary: "attackers", scope,
## duration} placed on the token BEARER's spell-mod store) but its members have NO profile-flag
## read: Quick Shot / Rapid Charge / Slayer / Unwieldy / Piercing Fighter / Unpredictable * live
## on unit-level read paths, so a flag bridge would silently do nothing (and the pinning test
## spell_foresight_relentless_test.gd:88 refuses them on purpose). The fix is a shared
## "granted rules of this attacker" query — AiSpell.granted_rules_of — read at each rule's own
## site. RED-GREEN: this suite ships BEFORE the wiring; against main the query does not exist
## and the site helpers ignore the bearer's token, so every test below fails (RED).

const MainScript := preload("res://scripts/main.gd")

# Every rule of the issue family the shared query must surface (base names; the data's scope
# suffixes — "Bane in Melee" style — name the SAME rule and are stripped by the query).
const FAMILY := ["Quick Shot", "Rapid Charge", "Slayer", "Unwieldy", "Piercing Fighter",
	"Unpredictable Fighter", "Unpredictable Shooter"]


func _granted(grants: String, beneficiary: String = "attackers", extras: Dictionary = {}) -> Dictionary:
	# Mirrors the record shape main.gd:_solo_record_spell_mod writes into a unit's spell-mod store.
	var r := {"spell": "Test Spell", "hit_mod": 0, "def_mod": 0, "casting_mod": 0,
		"morale_mod": 0, "range_in": 0, "advance_in": 0, "rush_in": 0,
		"grants_rule": grants, "scope": "", "beneficiary": beneficiary, "duration": "once"}
	for k in extras:
		r[k] = extras[k]
	return r


func _unit(faction: String = "") -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "u_%s" % faction if not faction.is_empty() else "u_plain"
	u.unit_properties = {"player_id": 1, "name": "U", "quality": 4, "defense": 4,
		"special_rules": [], "faction_folder": faction}
	return u


func _bearer_with(grants: Dictionary) -> GameUnit:
	# The token BEARER: a unit whose durable mirror (main.gd SOLO_SPELL_RECORDS_KEY — the shape
	# _solo_mirror_spell_state writes) carries spell-grant records.
	var u := _unit()
	var recs: Array = []
	for k in grants:
		recs.append(_granted(str(k), str(grants[k])))
	u.unit_properties["spell_records"] = recs
	return u


func test_attacker_without_the_rule_gains_it_from_the_bearers_token() -> void:
	# The issue's RED shape, per rule: a unit WITHOUT the printed rule, attacking a bearer whose
	# token grants the rule to its attackers, must see the rule in the granted set.
	for rule in FAMILY:
		var attacker := _unit()
		assert_bool(attacker.has_special_rule(rule)) \
			.override_failure_message("fixture must not carry the printed rule %s" % rule).is_false()
		assert_array(AiSpell.granted_rules_of(attacker, _bearer_with({rule: "attackers"}))) \
			.override_failure_message("granted %s must surface to the attacker" % rule) \
			.contains_exactly([rule])


func test_a_unit_without_the_token_stays_without_the_grant() -> void:
	# No token → no grant: the query must not invent a rule (and the attacker's own records
	# without grants_rule contribute nothing).
	var attacker := _unit()
	attacker.unit_properties["spell_records"] = [_granted("", "")]
	assert_array(AiSpell.granted_rules_of(attacker, _unit())).is_empty()


func test_grants_on_the_attacker_itself_surface_too() -> void:
	# A friendly buff token placed ON the attacker (beneficiary "" — the utility-buff shape)
	# counts as its own grant; the overlay path already stamps special_rules for it, the query
	# must agree so both reads see the same truth.
	var attacker := _bearer_with({"Quick Shot": ""})
	attacker.unit_properties["spell_records"] = [_granted("Quick Shot", "")]
	assert_array(AiSpell.granted_rules_of(attacker, _unit())).contains_exactly(["Quick Shot"])


func test_the_bearer_does_not_read_its_own_attackers_side_grant() -> void:
	# beneficiary "attackers" on the BEARER's own store names the units attacking it — the bearer
	# itself must not self-benefit (an Evasive-style defensive grant must not leak either way).
	var bearer := _bearer_with({"Quick Shot": "attackers"})
	assert_array(AiSpell.granted_rules_of(bearer, bearer)).is_empty()


func test_scope_suffixes_name_the_same_rule() -> void:
	# "Indirect when Shooting"-style suffixes (data encoding for the same rule) strip to the base
	# name — the bridge treats them identically and so does the query.
	var attacker := _unit()
	assert_array(AiSpell.granted_rules_of(attacker, _bearer_with({"Quick Shot when Shooting": "attackers"}))) \
		.contains_exactly(["Quick Shot"])


func test_melee_scoped_grant_stays_out_of_a_shooting_read() -> void:
	# The `shooting` leg mirrors AiSpell.mods_for: a melee-scoped grant must not fire a shooting
	# read, and vice versa.
	var attacker := _unit()
	var bearer := _bearer_with({"Unwieldy": "attackers"})
	var rec: Dictionary = (bearer.unit_properties["spell_records"] as Array)[0]
	rec["scope"] = "melee"
	assert_array(AiSpell.granted_rules_of(attacker, bearer, true)).is_empty()
	assert_array(AiSpell.granted_rules_of(attacker, bearer, false)).contains_exactly(["Unwieldy"])


# ===== the own read sites =====


func test_unpredictable_pair_site_honours_the_bearers_grant() -> void:
	# main.gd:_solo_unpredictable_rule — the melee-only Fighter leg and the shooting-only
	# Shooter leg each fire from the bearer's token (Mob Frenzy shape, spells_mechanics_gf.json).
	var main: Node3D = auto_free(MainScript.new())
	var melee_attacker := _unit()
	assert_str(main._solo_unpredictable_rule(melee_attacker, true, _bearer_with({"Unpredictable Fighter": "attackers"}))) \
		.is_equal("Unpredictable Fighter")
	var shooter := _unit()
	assert_str(main._solo_unpredictable_rule(shooter, false, _bearer_with({"Unpredictable Shooter": "attackers"}))) \
		.is_equal("Unpredictable Shooter")
	# Without the token nothing changes — the melee leg must not fire from a Shooter grant either.
	assert_str(main._solo_unpredictable_rule(_unit(), true, _bearer_with({"Unpredictable Shooter": "attackers"}))) \
		.is_equal("")


func test_unwieldy_site_honours_the_bearers_grant() -> void:
	# main.gd:_solo_unit_has_unwieldy — a charger granted Unwieldy by the defender's token
	# strikes last exactly like a printed carrier.
	var main: Node3D = auto_free(MainScript.new())
	assert_bool(main._solo_unit_has_unwieldy(_unit(), _bearer_with({"Unwieldy": "attackers"}))).is_true()
	assert_bool(main._solo_unit_has_unwieldy(_unit(), _unit())).is_false()


func test_slayer_site_honours_the_bearers_grant() -> void:
	# main.gd:_solo_conditional_ap_parts — Slayer's gate (dao_union book: AP(+2) when it shoots
	# over 9" or charges, vs Tough 3+) fires for the granted rule under the same registry lookup.
	var main: Node3D = auto_free(MainScript.new())
	var striker := _unit("dao_union")
	var defender := _bearer_with({"Slayer": "attackers"})
	defender.unit_properties["special_rules"] = ["Tough(3)"]
	assert_array(main._solo_conditional_ap_parts({"rules": []}, striker, defender, true, -1.0, false)) \
		.override_failure_message("granted Slayer must add its conditional AP on the charge") \
		.contains_exactly([{"name": "Slayer", "bonus": 2}])
	# Without the token: no part — the striker's book gate alone decides nothing here.
	assert_array(main._solo_conditional_ap_parts({"rules": []}, _unit("dao_union"), _unit(), true, -1.0, false)).is_empty()
