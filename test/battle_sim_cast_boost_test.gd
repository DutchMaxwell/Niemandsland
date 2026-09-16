extends GdUnitTestSuite
## D-MAGIC step 7 — the token economy IN the cast sub-phase: boost and
## interference. The sim's _cast_phase now plans the attempt's token spend
## exactly like the table (solo_controller.gd:4336-4390) and the core (sim.rs
## plan_caster_boost / interference_pool): the caster's own leftover tokens
## are the FIRST boost source, friendly casters within the Caster rule's 18"
## in line of sight lend next (nearest-first draw), and the opposing casters'
## pool counters at the cast's own EV — an unpriced cast draws no counter.
## The plan lands ONCE, at the first face that produces a pick.
##
## Fixture recipe mirrors battle_sim_cast_phase_test.gd: hand-built GameUnits
## captured through BattleSim.capture(), faction slug via
## unit_properties["faction_folder"], NML_SIM_CAST seam ON in before/after.
##
## THE ONE EV the hand numbers rest on: robot_legions "Piercing Bots"
## (threshold 1, 12", hits 2, AP(2)) into a Defense-4 squad —
## save_target(4, 2) = 6, block 1/6, so _spell_damage_ev_of = 2 x 5/6 = 5/3.
## Every expected value below is derived from that with AiSpell's pure math:
## cast_success_chance(t) = (7 - clampi(t, 2, 6)) / 6, a bought token moves
## the roll target one step, gain = delta_p x 5/3 >= 5/18 above the
## TOKEN_VALUE_EPS floor of 0.05 — and the clamp at target 2 stops the climb.

const IN2M := 0.0254


func before_test() -> void:
	OS.set_environment("NML_SIM_CAST", "1")
	BattleSim.new().set("_cast_env", -1)


func after_test() -> void:
	OS.set_environment("NML_SIM_CAST", "")
	BattleSim.new().set("_cast_env", -1)


func _unit(pid: int, uid: String, positions: Array, rules: Array = [],
		faction: String = "", tokens: int = 0) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4,
		"special_rules": rules, "faction_folder": faction, "game_system": "gf"}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		m.wounds_current = 1
		m.wounds_max = 1
		m.unit = u
		var n := Node3D.new()
		add_child(n)
		n.global_position = p
		m.node = n
		u.models.append(m)
	u.casts_current = tokens
	u.casts_per_round = tokens
	return u


func _capture(units: Array) -> Dictionary:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	var gu := {}
	for u in units:
		gu[(u as GameUnit).unit_id] = u
	army.game_units = gu
	return BattleSim.capture(army)


## The boost fixture: Wizard (Caster(1), 2 tokens) at 0", a HELPER caster
## (Caster(1), 1 token) at 6" — inside the 18" aura — and the enemy squad at
## 3". The D3=1 face starts the official cycle at index 1 ("Piercing Bots"),
## the same pick the plain cast-phase test pins.
func _boost_state(helper_gap_in: float = 6.0, enemy: bool = false) -> Dictionary:
	var units: Array = [
		_unit(1, "Wizard", [Vector3.ZERO], ["Caster(1)"], "robot_legions", 2),
		_unit(1, "Helper", [Vector3(helper_gap_in * IN2M, 0, 0)],
			["Caster(1)"], "robot_legions", 1),
	]
	var foes: Array = []
	for i in range(4):
		foes.append(Vector3((3.0 + float(i)) * IN2M, 0, 0))
	units.append(_unit(2, "Squad", foes))
	if enemy:
		units.append(_unit(2, "EnemyCaster", [Vector3(8.5 * IN2M, 0, 0)],
			["Caster(1)"], "robot_legions", 2))
	return _capture(units)


func _hold(state: Dictionary) -> Dictionary:
	return BattleSim.resolve(state, {"unit": "Wizard", "kind": AiDecision.Action.HOLD})


## (a) THE BOOST CASE: own leftover FIRST, then the 18" LoS helper. ev = 5/3;
## own_left = 2 - 1 = 1; token 1 buys at the coin-flip floor (gain (2/3-1/2)
## x 5/3 = 5/18 > 0), token 2 comes from the HELPER (gain 5/18 > 0.05), the
## third gain is 0 (the clamp at roll target 2). boost = 2, interference = 0
## (the squad holds no caster) -> p_success = (7-2)/6 = 5/6. The spend: the
## Wizard pays threshold + own draw (1 + 1), the Helper pays its 1 drawn
## token — both end at 0.
func test_helper_tokens_boost_the_cast_and_get_drawn() -> void:
	var next := _hold(_boost_state())
	var wizard: Dictionary = next["units"]["Wizard"]
	var helper: Dictionary = next["units"]["Helper"]
	assert_int(int(wizard["casts"])).is_equal(0)
	assert_int(int(helper["casts"])).is_equal(0)
	var events: Array = next.get("cast_events", [])
	assert_int(events.size()).is_equal(1)
	var ev: Dictionary = events[0] if not events.is_empty() else {}
	assert_str(str(ev.get("kind", ""))).is_equal("damage")
	assert_str(str(ev.get("target", ""))).is_equal("Squad")
	assert_int(int(ev.get("boost", -1))).is_equal(2)
	assert_int(int(ev.get("interference", -1))).is_equal(0)
	assert_float(float(ev.get("p_success", 0.0))).is_equal_approx(5.0 / 6.0, 0.001)
	assert_float(float((next["units"]["Squad"] as Dictionary).get("wound_frac", 0.0))).is_greater(0.0)


## (b) THE INTERFERENCE CASE: the enemy caster's pool counters the committed
## boost at the cast's own EV. Enemy pool = 2; each token cuts the roll
## chance by 1/6 x 5/3 = 5/18 > 0.05, so the pool is spent to its cap:
## interference = 2. p_success = cast_success_chance(2, 2) = (7-4)/6 = 1/2.
## The squad stays the target (same 5/3 ev as the enemy caster, nearer wins
## the tie). The counter-spend empties the EnemyCaster too.
func test_enemy_caster_interference_counters_the_boost() -> void:
	var next := _hold(_boost_state(6.0, true))
	var events: Array = next.get("cast_events", [])
	assert_int(events.size()).is_equal(1)
	var ev: Dictionary = events[0] if not events.is_empty() else {}
	assert_str(str(ev.get("target", ""))).is_equal("Squad")
	assert_int(int(ev.get("boost", -1))).is_equal(2)
	assert_int(int(ev.get("interference", -1))).is_equal(2)
	assert_float(float(ev.get("p_success", 0.0))).is_equal_approx(0.5, 0.001)
	assert_int(int((next["units"]["EnemyCaster"] as Dictionary)["casts"])).is_equal(0)
	assert_float(float((next["units"]["Squad"] as Dictionary).get("wound_frac", 0.0))).is_greater(0.0)


## (c) A caster with NO tokens holds: no plan, no event, no spend anywhere —
## the early return the plain cast-phase test already pins, kept here as the
## economy's floor.
func test_a_caster_without_tokens_holds() -> void:
	var state := _boost_state()
	(state["units"]["Wizard"] as Dictionary)["casts"] = 0
	(state["units"]["Wizard"] as Dictionary)["casts_current"] = 0
	var next := _hold(state)
	assert_array(next.get("cast_events", [])).is_empty()
	assert_int(int((next["units"]["Wizard"] as Dictionary)["casts"])).is_equal(0)
	assert_int(int((next["units"]["Helper"] as Dictionary)["casts"])).is_equal(1)
	assert_float(float((next["units"]["Squad"] as Dictionary).get("wound_frac", 0.0))).is_equal(0.0)


## (d) THE RANGE GATE: a friendly caster 25" out (beyond the Caster rule's
## 18" aura) lends NOTHING. available = own_left = 1 only -> boost = 1
## (coin-flip floor), p_success = (7-3)/6 = 2/3, and the Helper keeps its
## token. The same discriminator at the table (_aura_casters) and the core
## (caster_boost_pool).
func test_helper_outside_the_aura_lends_nothing() -> void:
	var next := _hold(_boost_state(25.0))
	var wizard: Dictionary = next["units"]["Wizard"]
	var helper: Dictionary = next["units"]["Helper"]
	assert_int(int(wizard["casts"])).is_equal(0)
	assert_int(int(helper["casts"])).is_equal(1)
	var events: Array = next.get("cast_events", [])
	assert_int(events.size()).is_equal(1)
	var ev: Dictionary = events[0] if not events.is_empty() else {}
	assert_int(int(ev.get("boost", -1))).is_equal(1)
	assert_int(int(ev.get("interference", -1))).is_equal(0)
	assert_float(float(ev.get("p_success", 0.0))).is_equal_approx(2.0 / 3.0, 0.001)
