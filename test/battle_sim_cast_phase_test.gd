extends GdUnitTestSuite
## The CAST SUB-PHASE, resolved in the ONE CORE: a caster picks a spell, pays the attempt, stamps the
## event and lands the effect read out of NmlCore::resolve with the cast seam on (CoreResolve). What
## stays here is what no Rust unit test pins: "no spell in range holds the tokens", "a buff lands on
## the caster's own mods", "a casting unit that also shoots casts once" and "a Shaken caster casts
## nothing" (+ its un-shaken control). The two state_to_plain event-shape cases and the round-scope
## reset hand-set the event and never resolve.
##
## The cast attempts that only replayed the recorded corpus, the legacy seam-off arms, the
## stochastic-path token ledger and the Spell Conduit origins are covered by Rust tests (sub-phase,
## cast kind, boost, interference, conduit, parity gate B); their GDScript twins were removed here.
##
## Fixture recipe mirrors test/battle_sim_resolve_test.gd: hand-built GameUnits whose model nodes are
## parented under the suite, captured through BattleSim.capture(). The faction slug rides
## unit_properties["faction_folder"] — the key the spell book is indexed by, so a fixture picks its
## book by CHOOSING the slug.

const IN2M := 0.0254


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


## The melee caster fixture: the rated Caster rule and no ranged weapon at all. `gap_in` places the
## enemy squad. The rule is the RATED STRING form ("Caster(1)"): get_caster_value parses the rating
## out of the rule NAME, so a {name, rating} dict would silently read as X = 0.
func _melee_caster_state(gap_in: float, tokens: int = 1,
		faction: String = "robot_legions", caster_x: int = 1) -> Dictionary:
	var caster := _unit(1, "Wizard", [Vector3.ZERO], ["Caster(%d)" % caster_x],
		faction, tokens)
	var foes: Array = []
	for i in range(4):
		foes.append(Vector3((gap_in + float(i)) * IN2M, 0, 0))
	var squad := _unit(2, "Squad", foes)
	return _capture([caster, squad])


func _hold() -> Dictionary:
	return {"unit": "Wizard", "kind": AiDecision.Action.HOLD}


## The recorded plain state carries the cast attempt: one event, the seven keys of the cast contract.
## A state that never cast writes no key at all (cast-off corpora stay byte-identical). The event is
## hand-set — this is the recorder's own shape test, not a resolve.
func test_state_to_plain_carries_the_cast_attempt_event() -> void:
	var state := _melee_caster_state(3.0)
	state["cast_events"] = [{"spell": "Test Spell", "kind": "damage", "cost": 1,
		"target": "Squad", "p_success": 0.5, "boost": 0, "interference": 0}]
	var plain := BattleSim.state_to_plain(state, false)
	var events: Array = plain.get("cast_events", [])
	assert_int(events.size()).is_equal(1)
	var ev: Dictionary = events[0] if not events.is_empty() else {}
	for k in ["spell", "kind", "cost", "target", "p_success", "boost", "interference"]:
		assert_bool(ev.has(k)).is_true()
	assert_str(str(ev.get("target", ""))).is_equal("Squad")
	assert_bool(BattleSim.state_to_plain(_melee_caster_state(3.0), false).has("cast_events")).is_false()


## A cast through a conduit carries its origin position in the plain state as an [x,y,z] array
## (JSON-safe), the shape the core's plain writer uses. Hand-set event, no resolve.
func test_state_to_plain_writes_a_conduit_origin_position_as_an_array() -> void:
	var state := _melee_caster_state(3.0)
	state["cast_events"] = [{"spell": "Test Spell", "kind": "damage", "cost": 1,
		"target": "Squad", "p_success": 0.5, "boost": 0, "interference": 0,
		"origin": {"unit": "Banner", "position": Vector3(10.0 * IN2M, 0, 0)}}]
	var plain := BattleSim.state_to_plain(state, false)
	var origin: Dictionary = (plain["cast_events"][0] as Dictionary)["origin"]
	assert_str(str(origin["unit"])).is_equal("Banner")
	assert_bool(origin["position"] is Array).is_true()
	assert_float(float(origin["position"][0])).is_equal_approx(10.0 * IN2M, 0.001)


## Discriminator: nothing in range and no affordable friendly spell (the book's two cost 2 and 3) —
## the caster HOLDS: no token spent, no event, no damage anywhere.
func test_no_valid_spell_holds_the_tokens() -> void:
	var next := CoreResolve.resolve(_melee_caster_state(30.0), _hold(), {"cast": true})
	assert_int(int((next["units"]["Wizard"] as Dictionary)["casts"])).is_equal(1)
	assert_array(next.get("cast_events", [])).is_empty()
	assert_float(float((next["units"]["Squad"] as Dictionary).get("wound_frac", 0.0))).is_equal(0.0)


## A buff cast lands on the caster's own snapshot mods: the first face is a friendly 12" buff
## (threshold 1, +1 morale), the ledger pays it plus the one boost token an unpriced cast buys, and
## the morale mod moves off its captured base.
func test_buff_cast_moves_the_casters_own_mods() -> void:
	var next := CoreResolve.resolve(
		_melee_caster_state(6.0, 6, "rebel_guerrillas", 6), _hold(), {"cast": true})
	var su: Dictionary = next["units"]["Wizard"]
	assert_int(int(su["casts"])).is_equal(4)
	assert_float(float((su["mods"] as Dictionary).get("morale", 0.0))).is_greater(0.0)


## Guard on the removed shoot-rider: a casting unit that also picks a shoot target casts exactly
## ONCE per activation — the token is gone and the enemy carries the one attempt's expected wounds.
func test_shooting_caster_casts_once_not_twice() -> void:
	var caster := _unit(1, "Wizard", [Vector3.ZERO], ["Caster(1)"], "robot_legions", 1)
	var foes: Array = []
	for i in range(4):
		foes.append(Vector3((3.0 + float(i)) * IN2M, 0, 0))
	var squad := _unit(2, "Squad", foes)
	var state := _capture([caster, squad])
	var next := CoreResolve.resolve(state,
		{"unit": "Wizard", "kind": AiDecision.Action.HOLD, "shoot": "Squad"}, {"cast": true})
	assert_int(int((next["units"]["Wizard"] as Dictionary)["casts"])).is_equal(0)
	assert_float(float((next["units"]["Squad"] as Dictionary).get("wound_frac", 0.0))).is_greater(0.0)


## A Shaken caster spends its activation idle and casts nothing. The un-shaken twin is the CONTROL:
## the same fixture and the same call DO spend the token, so a green is never a fixture that could
## not cast at all.
func test_shaken_caster_casts_nothing() -> void:
	var control := CoreResolve.resolve(_melee_caster_state(3.0), _hold(), {"cast": true})
	assert_int(int((control["units"]["Wizard"] as Dictionary)["casts"])).is_equal(0)
	var state := _melee_caster_state(3.0)
	(state["units"]["Wizard"] as Dictionary)["shaken"] = true
	var next := CoreResolve.resolve(state, _hold(), {"cast": true})
	assert_int(int((next["units"]["Wizard"] as Dictionary)["casts"])).is_equal(1)
	assert_array(next.get("cast_events", [])).is_empty()
	assert_float(float((next["units"]["Squad"] as Dictionary).get("wound_frac", 0.0))).is_equal(0.0)


## Spell mods are ROUND-SCOPED: the round-loop reset (called where activated/fatigued are cleared)
## puts every unit back on its CAPTURE-TIME base, so a round-2 snapshot never carries round-1 buffs.
## The buff is hand-set here; the reset is the subject.
func test_round_reset_returns_mods_to_the_capture_base() -> void:
	var state := _melee_caster_state(6.0, 6, "rebel_guerrillas", 6)
	var su: Dictionary = state["units"]["Wizard"]
	var base: Dictionary = (su.get("mods_base", {}) as Dictionary).duplicate(true)
	su["mods"] = base.duplicate(true)
	(su["mods"] as Dictionary)["morale"] = float(base.get("morale", 0.0)) + 1.0
	assert_that(su["mods"]).is_not_equal(base)
	BattleSim.reset_round_mods(state)
	assert_that(su["mods"]).is_equal(base)
