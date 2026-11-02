extends GdUnitTestSuite
## Rules 3.6, row SHO-18e: the AI's expected-wounds estimate is the twin of SHO-18 / SHO-18b.
## The offensive Surge/Shred alias families (Ferocious, Warbound and their siblings) only pay
## from a shot over 9" or a charge over 6"; a strike-back pays nothing. The profiles come from
## the real `AiShooting` builder + `AiEv.stamp_sergeant`, and the charge distance comes in through
## `AiEv.melee_ev`'s `charge_dist_in` (the W1.5b edge gap). Below `EPOCH_73_V36` the old
## unconditional read stays, so both twins price the alias at every distance.

const ATT := {"quality": 4, "models": 1}
const DEF := {"defense": 4, "tough": 1, "models": 5}

var _epoch0 := 0


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests — restore


func _unit(rules: Array, system: String, faction: String) -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = "sho18e_%s" % system
	u.unit_properties = {"player_id": 2, "name": "Fixture", "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": system, "faction_folder": faction}
	var m := ModelInstance.new()
	m.is_alive = true
	u.models.append(m)
	return u


func _weapon(nm: String, rng: int, atk: int, rules: Array = []) -> Dictionary:
	return {"name": nm, "range_value": rng, "attacks": atk, "count": 1, "special_rules": rules}


## A charge estimate at `gap_in`, through the real profile builder + stamp.
func _charge_ev(rules: Array, system: String, faction: String, epoch: int, gap_in: float,
		weapon_rules: Array = []) -> float:
	AiActRecorder.rules_epoch = epoch
	var u := _unit(rules, system, faction)
	var profiles := AiEv.stamp_sergeant(
		AiShooting.melee_profiles([_weapon("Blade", 0, 6, weapon_rules)]), u)
	return AiEv.melee_ev(profiles, ATT, DEF, true, gap_in)


## A shot estimate at `dist_in`, through the same builder + stamp.
func _shot_ev(rules: Array, system: String, faction: String, epoch: int, dist_in: float,
		weapon_rules: Array = []) -> float:
	AiActRecorder.rules_epoch = epoch
	var u := _unit(rules, system, faction)
	var profiles := AiEv.stamp_sergeant(
		AiShooting.profiles_in_range([_weapon("Rifle", 24, 8, weapon_rules)], dist_in), u)
	return AiEv.profile_ev(profiles[0], ATT, DEF, dist_in, false)


func _plain_charge(epoch: int, gap_in: float) -> float:
	return _charge_ev([], "gf", "war_disciples", epoch, gap_in)


const WARBOUND := ["Warbound"]
const FEROCIOUS := ["Ferocious"]


## RED on main: the charge gate is 6" — Ferocious at 3" pays nothing at 73, at 7" it pays.
func test_ferocious_charge_pays_over_six_inches_and_not_inside_at_epoch_73() -> void:
	var three := _charge_ev(FEROCIOUS, "aof", "orcs", AiActRecorder.EPOCH_73_V36, 3.0)
	var seven := _charge_ev(FEROCIOUS, "aof", "orcs", AiActRecorder.EPOCH_73_V36, 7.0)
	assert_float(three) \
		.override_failure_message("a 3\" charge is inside the 6\" gate") \
		.is_equal_approx(_plain_charge(AiActRecorder.EPOCH_73_V36, 3.0), 0.0001)
	assert_float(seven) \
		.override_failure_message("a 7\" charge is over the 6\" gate") \
		.is_greater(three)


## RED on main: Warbound's Shred follows the same charge gate.
func test_warbound_charge_shreds_over_six_inches_and_not_inside_at_epoch_73() -> void:
	var three := _charge_ev(WARBOUND, "gf", "war_disciples", AiActRecorder.EPOCH_73_V36, 3.0)
	var seven := _charge_ev(WARBOUND, "gf", "war_disciples", AiActRecorder.EPOCH_73_V36, 7.0)
	assert_float(three) \
		.override_failure_message("a 3\" charge is inside the 6\" gate") \
		.is_equal_approx(_plain_charge(AiActRecorder.EPOCH_73_V36, 3.0), 0.0001)
	assert_float(seven) \
		.override_failure_message("a 7\" charge is over the 6\" gate") \
		.is_greater(three)


## The old side: below 73 both families pay at every charge distance.
func test_below_epoch_73_both_families_pay_at_every_charge_distance() -> void:
	for pair in [[FEROCIOUS, "aof", "orcs"], [WARBOUND, "gf", "war_disciples"]]:
		var three := _charge_ev(pair[0], pair[1], pair[2], AiActRecorder.EPOCH_72_PLAYTEST_RULES, 3.0)
		var seven := _charge_ev(pair[0], pair[1], pair[2], AiActRecorder.EPOCH_72_PLAYTEST_RULES, 7.0)
		assert_float(three) \
			.override_failure_message("%s at 72: 3\" and 7\" price the same" % pair[0]) \
			.is_equal_approx(seven, 0.0001)
		assert_float(three) \
			.override_failure_message("%s at 72: the alias still pays" % pair[0]) \
			.is_greater(_plain_charge(AiActRecorder.EPOCH_72_PLAYTEST_RULES, 3.0))


## RED on main: the shot leg gates the same families at over 9".
func test_the_aliases_pay_over_nine_inches_shooting_and_not_inside_at_epoch_73() -> void:
	for pair in [[FEROCIOUS, "aof", "orcs"], [WARBOUND, "gf", "war_disciples"]]:
		var seven := _shot_ev(pair[0], pair[1], pair[2], AiActRecorder.EPOCH_73_V36, 7.0)
		var ten := _shot_ev(pair[0], pair[1], pair[2], AiActRecorder.EPOCH_73_V36, 10.0)
		assert_float(seven) \
			.override_failure_message("%s: a 7\" shot is inside the 9\" band" % pair[0]) \
			.is_equal_approx(_shot_ev([], "gf", "war_disciples", AiActRecorder.EPOCH_73_V36, 7.0), 0.0001)
		assert_float(ten) \
			.override_failure_message("%s: a 10\" shot is over the 9\" band" % pair[0]) \
			.is_greater(seven)


## The old side: below 73 the same 7" shot pays.
func test_below_epoch_73_the_aliases_pay_at_every_shot_distance() -> void:
	for pair in [[FEROCIOUS, "aof", "orcs"], [WARBOUND, "gf", "war_disciples"]]:
		var seven := _shot_ev(pair[0], pair[1], pair[2], AiActRecorder.EPOCH_72_PLAYTEST_RULES, 7.0)
		var ten := _shot_ev(pair[0], pair[1], pair[2], AiActRecorder.EPOCH_72_PLAYTEST_RULES, 10.0)
		assert_float(seven) \
			.override_failure_message("%s at 72: 7\" and 10\" price the same" % pair[0]) \
			.is_equal_approx(ten, 0.0001)
		assert_float(seven) \
			.override_failure_message("%s at 72: the alias still pays" % pair[0]) \
			.is_greater(_shot_ev([], "gf", "war_disciples", AiActRecorder.EPOCH_72_PLAYTEST_RULES, 10.0))


## A weapon's OWN Surge/Shred keeps the old unconditional read at every distance.
func test_a_weapons_own_surge_and_shred_stay_ungated_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var own := _charge_ev([], "gf", "war_disciples", AiActRecorder.EPOCH_73_V36, 3.0,
		["Surge", "Shred"])
	assert_float(own) \
		.override_failure_message("the weapon's own Surge/Shred never rides the alias gate") \
		.is_greater(_plain_charge(AiActRecorder.EPOCH_73_V36, 3.0))
