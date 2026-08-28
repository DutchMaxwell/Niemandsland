extends GdUnitTestSuite
## NML-1132 — the JOINED HERO's WEAPONS and MODELS inside the IMAGINATION.
##
## The live table fights a host and its joined hero as ONE body: `main._run_ai_shooting`
## (:2910-2941) builds "a shot per ranged weapon of the unit + attached heroes", each member
## with its own weapons, and `_solo_attack_groups` (main.gd:4284-4290) builds a melee strike
## phase the same way; the reach of a shot is measured from the FIRING MEMBER's models
## (`main._solo_sighted_count` :4103) to the target unit AND its heroes (:4086-4092).
## `BattleSim._profiles_of` read the HOST's OPR weapons alone and `dist_in` the host's models
## alone — so the planner valued, targeted and charged a rifle squad as if the heavy-gun hero
## riding with it were not on the table. The Rust twin read it the same way, which is why the
## two imaginations agreed and no parity gate went red (`hero_ev_gate.py` is the one that does).
##
## Gated on `hero_fold_enabled()` alone, like `_engage_gap_in` (NML-1129): fold off is the
## shipped reading, byte for byte. The knob reset mirrors test/battle_sim_hero_fold_test.gd.

const IN2M := 0.0254


func before_test() -> void:
	BattleSim.hero_fold = false
	OS.set_environment("NML_HERO_FOLD", "")
	BattleSim.new().set("_hero_fold_env", -1)


func after_test() -> void:
	BattleSim.hero_fold = false
	OS.set_environment("NML_HERO_FOLD", "")
	BattleSim.new().set("_hero_fold_env", -1)


func _weapon(wname: String, range_in: int, attacks: int) -> OPRApiClient.OPRWeapon:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = wname
	w.range_value = range_in
	w.attacks = attacks
	w.count = 1
	return w


func _unit(pid: int, uid: String, xs: Array, weapons: Array) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4,
		"special_rules": []}
	for x in xs:
		var m := ModelInstance.new()
		m.is_alive = true
		m.wounds_current = 1
		m.wounds_max = 1
		m.unit = u
		var n := Node3D.new()
		add_child(n)
		n.global_position = Vector3(float(x) * IN2M, 0, 0)
		m.node = n
		u.models.append(m)
	var opr := OPRApiClient.OPRUnit.new()
	for w in weapons:
		opr.weapons.append(w)
	u.source_type = "opr"
	u.source_data = opr
	return u


## A RIFLE SQUAD with a HEAVY-WEAPON HERO out in front, and one enemy beyond the rifles.
## Host models sit at 0" and 1", the joined hero at 8", the foe at 30". The host's own
## nearest model is therefore 29" from the foe and the hero's 22":
##   * the host's 24" rifle only reaches once the reach is measured from the HERO's model,
##   * the hero's 36" heavy gun only fires once the PROFILE carries it.
## One fixture, both halves of the ticket, and the numbers are far enough apart that no
## rounding can decide either.
func _state() -> Dictionary:
	var host := _unit(2, "Rifles", [0.0, 1.0], [_weapon("Rifle", 24, 1), _weapon("CCW", 0, 2)])
	var hero := _unit(2, "Champion", [8.0], [_weapon("Heavy Gun", 36, 3), _weapon("Fist", 0, 4)])
	var foe := _unit(1, "Foe", [30.0], [_weapon("Foe Gun", 24, 1)])
	host.unit_properties["attached_heroes"] = [hero]
	hero.unit_properties["attached_to"] = host
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Rifles": host, "Champion": hero, "Foe": foe}
	return BattleSim.capture(army)


func _names(profiles: Array) -> Array:
	var out: Array = []
	for p in profiles:
		out.append(str((p as Dictionary).get("name", "")))
	return out


# === the RANGE half =========================================================

## KNOB OFF (the shipped reading): the two HOSTS are measured, 29".
func test_the_reach_is_the_host_to_host_distance_with_the_fold_off() -> void:
	var state := _state()
	var su: Dictionary = state["units"]["Rifles"]
	var tu: Dictionary = state["units"]["Foe"]
	assert_float(BattleSim._fold_dist_in(state, su, su["positions"], tu)) \
		.is_equal_approx(29.0, 0.01)
	# The identity that keeps every recorded corpus replaying: fold off is `dist_in`.
	assert_float(BattleSim._fold_dist_in(state, su, su["positions"], tu)) \
		.is_equal_approx(BattleSim.dist_in(su["positions"], tu["positions"]), 1e-6)


## KNOB ON: the joined hero's model is 22" out, and that is the reach the table measures.
func test_the_reach_is_measured_from_the_joined_heros_model() -> void:
	BattleSim.hero_fold = true
	var state := _state()
	var su: Dictionary = state["units"]["Rifles"]
	var tu: Dictionary = state["units"]["Foe"]
	assert_float(BattleSim._fold_dist_in(state, su, su["positions"], tu)) \
		.is_equal_approx(22.0, 0.01)


## A hero with no models left has an empty position array — it drops out of the minimum
## instead of dragging it anywhere, exactly as an empty side does in `dist_in`.
func test_a_dead_joined_hero_does_not_move_the_reach() -> void:
	BattleSim.hero_fold = true
	var state := _state()
	var su: Dictionary = state["units"]["Rifles"]
	var tu: Dictionary = state["units"]["Foe"]
	((state["units"]["Champion"] as Dictionary)["positions"] as Array).clear()
	assert_float(BattleSim._fold_dist_in(state, su, su["positions"], tu)) \
		.is_equal_approx(29.0, 0.01)


# === the WEAPON half ========================================================

## KNOB OFF — the RED. At the host-to-host 29" the rifle cannot reach and the hero's gun is
## not in the profile at all, so the imagination fires nothing: this activation is worth zero
## to the planner while the table would have drawn the hero's three dice.
func test_the_imagined_volley_is_empty_with_the_fold_off() -> void:
	var state := _state()
	var su: Dictionary = state["units"]["Rifles"]
	assert_array(_names(BattleSim._profiles_of(su, false, 29.0, state))).is_empty()
	assert_array(_names(BattleSim._profiles_of(su, true, 0.0, state))).is_equal(["CCW"])


## KNOB ON: the imagined shots are the table's member list — the host's rifle (reachable now
## that the reach is the hero's 22") and the hero's own heavy gun, host first.
func test_the_imagined_shots_include_the_heros_heavy_weapon() -> void:
	BattleSim.hero_fold = true
	var state := _state()
	var su: Dictionary = state["units"]["Rifles"]
	var tu: Dictionary = state["units"]["Foe"]
	var d := BattleSim._fold_dist_in(state, su, su["positions"], tu)
	assert_array(_names(BattleSim._profiles_of(su, false, d, state))) \
		.is_equal(["Rifle", "Heavy Gun"])


## The MELEE half of the same fold (`_solo_attack_groups` main.gd:4284-4290).
func test_the_imagined_melee_includes_the_heros_weapon() -> void:
	BattleSim.hero_fold = true
	var state := _state()
	var su: Dictionary = state["units"]["Rifles"]
	assert_array(_names(BattleSim._profiles_of(su, true, 0.0, state))).is_equal(["CCW", "Fist"])


## A hero with no living model brings no shot — `main._run_ai_shooting` :2915 skips exactly
## that member, and so does the fold.
func test_a_dead_joined_hero_brings_no_weapon() -> void:
	BattleSim.hero_fold = true
	var state := _state()
	var su: Dictionary = state["units"]["Rifles"]
	(state["units"]["Champion"] as Dictionary)["alive"] = 0
	assert_array(_names(BattleSim._profiles_of(su, true, 0.0, state))).is_equal(["CCW"])


## WITHOUT A STATE there is nothing to fold from: `su["attached"]` carries KEYS, not units.
## The menu-side probes in AiPlanner call `_profiles_of` that way and must keep the host's
## own answer — the Rust twin folds at the same two `resolve` sites and nowhere else, so the
## two imaginations still agree everywhere.
func test_no_state_means_no_fold() -> void:
	BattleSim.hero_fold = true
	var state := _state()
	var su: Dictionary = state["units"]["Rifles"]
	assert_array(_names(BattleSim._profiles_of(su, true))).is_equal(["CCW"])
