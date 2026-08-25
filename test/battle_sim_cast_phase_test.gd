extends GdUnitTestSuite
## NML-1069 A1a-2 — the CAST SUB-PHASE of BattleSim.resolve().
##
## Before this wave the sim's ONLY cast site was a rider inside resolve()'s
## SHOOT branch (battle_sim.gd ~:580-586: spell_ev_of folded into the volley).
## A MELEE caster never picks a shoot target, so it never cast: the trainer
## played 120 core games with ZERO casts while the arena cast in 68 of 68
## caster slots. The sub-phase runs after the move and before every attack,
## for every activation, exactly where the rule puts it (GF v3.5.1 Caster(X):
## "at any point before attacking ... spend as many tokens as the spell's
## value to try casting").
##
## Fixture recipe mirrors test/battle_sim_resolve_test.gd: hand-built GameUnits
## whose model nodes are parented under the suite, captured through
## BattleSim.capture(). The faction slug rides unit_properties["faction_folder"]
## — the very key SpellsRegistry indexes the committed spell map by, so a
## fixture picks its spell book by CHOOSING the slug, never by stamping spells.

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


## The melee caster fixture: Caster(X), robot_legions (a faction the committed
## gf map fields), no ranged weapon at all — the case the old shoot-rider could
## never reach. `gap_in` places the enemy squad. The caster rule is the RATED
## STRING form ("Caster(1)"): GameUnit.get_caster_value parses the rating out of
## the rule NAME, so a {name, rating} dict would silently read as X = 0.
func _melee_caster_state(gap_in: float, tokens: int = 1,
		faction: String = "robot_legions", caster_x: int = 1) -> Dictionary:
	var caster := _unit(1, "Wizard", [Vector3.ZERO], ["Caster(%d)" % caster_x],
		faction, tokens)
	var foes: Array = []
	for i in range(4):
		foes.append(Vector3((gap_in + float(i)) * IN2M, 0, 0))
	var squad := _unit(2, "Squad", foes)
	return _capture([caster, squad])


func _hold(state: Dictionary) -> Dictionary:
	return BattleSim.resolve(state, {"unit": "Wizard", "kind": AiDecision.Action.HOLD})


## (a) THE RED CASE: a melee caster 3" from an enemy casts on a plain HOLD.
## robot_legions with Caster(1) and 1 token: the D3=1 face starts the official
## cycle at index 1 ("Piercing Bots", damage, threshold 1, 12") — tokens drop by
## its cost, the enemy carries expected wounds, one damage event is stamped.
func test_melee_caster_casts_on_a_hold_and_spends_its_token() -> void:
	var next := _hold(_melee_caster_state(3.0))
	var su: Dictionary = next["units"]["Wizard"]
	assert_int(int(su["casts"])).is_equal(0)
	var tu: Dictionary = next["units"]["Squad"]
	assert_float(float(tu.get("wound_frac", 0.0))).is_greater(0.0)
	var events: Array = next.get("cast_events", [])
	assert_int(events.size()).is_equal(1)
	var ev: Dictionary = events[0] if not events.is_empty() else {}
	assert_str(str(ev.get("kind", ""))).is_equal("damage")
	assert_str(str(ev.get("target", ""))).is_equal("Squad")
	assert_int(int(ev.get("cost", 0))).is_equal(1)
	assert_float(float(ev.get("p_success", 0.0))).is_equal_approx(0.5, 0.001)


## (b) Discriminator: nothing in range and no affordable buff (robot_legions'
## two friendly spells cost 2 and 3) — the caster HOLDS: no token spent, no
## event, no damage anywhere.
func test_no_valid_spell_holds_the_tokens() -> void:
	var next := _hold(_melee_caster_state(30.0))
	assert_int(int((next["units"]["Wizard"] as Dictionary)["casts"])).is_equal(1)
	assert_array(next.get("cast_events", [])).is_empty()
	assert_float(float((next["units"]["Squad"] as Dictionary).get("wound_frac", 0.0))).is_equal(0.0)


## (c) A buff cast lands on the caster's own snapshot mods. rebel_guerrillas
## with Caster(6): the D3=1 face starts the cycle at index 0 ("Aura of Peace",
## buff, +1 morale, threshold 1) — the ledger pays that face's threshold, the
## event names it, and the morale mod moves off its captured base.
func test_buff_cast_moves_the_casters_own_mods() -> void:
	var next := _hold(_melee_caster_state(6.0, 6, "rebel_guerrillas", 6))
	var su: Dictionary = next["units"]["Wizard"]
	assert_int(int(su["casts"])).is_equal(5)
	var events: Array = next.get("cast_events", [])
	assert_int(events.size()).is_equal(1)
	var ev: Dictionary = events[0] if not events.is_empty() else {}
	assert_str(str(ev.get("kind", ""))).is_equal("buff")
	assert_str(str(ev.get("target", ""))).is_equal("Wizard")
	assert_float(float((su["mods"] as Dictionary).get("morale", 0.0))).is_greater(0.0)


## (d) The stochastic path (core self-play) casts too, and pays an INTEGER
## token price — the trainer's ledger counts token deltas, so a fractional
## spend would be unrepresentable.
func test_stochastic_path_casts_and_pays_integer_tokens() -> void:
	var state := _melee_caster_state(3.0, 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var next := BattleSim.resolve_stochastic(state,
		{"unit": "Wizard", "kind": AiDecision.Action.HOLD}, rng)
	var left := int((next["units"]["Wizard"] as Dictionary)["casts"])
	assert_int(left).is_less(3)
	var events: Array = next.get("cast_events", [])
	assert_int(events.size()).is_equal(1)
	var ev: Dictionary = events[0] if not events.is_empty() else {}
	assert_int(3 - left).is_equal(int(ev.get("cost", -1)))


## (e) Spell mods are ROUND-SCOPED: the round-loop reset (BattleSim
## .reset_round_mods, called by tools/core_selfplay.gd:_play_one where
## activated/fatigued are cleared) puts every unit back on its CAPTURE-TIME
## base, so a round-2 snapshot never carries round-1 buffs.
func test_round_reset_returns_mods_to_the_capture_base() -> void:
	var state := _melee_caster_state(6.0, 6, "rebel_guerrillas", 6)
	var base: Dictionary = (state["units"]["Wizard"] as Dictionary).get("mods_base", {})
	var next := _hold(state)
	var su: Dictionary = next["units"]["Wizard"]
	assert_that(su["mods"]).is_not_equal(base)
	BattleSim.reset_round_mods(next)
	assert_that(su["mods"]).is_equal(base)


## Guard on the removed shoot-rider: a SHOOTING caster must still cast exactly
## ONCE per activation — the old rider folded a second cast into the volley.
func test_shooting_caster_casts_once_not_twice() -> void:
	var caster := _unit(1, "Wizard", [Vector3.ZERO], ["Caster(1)"], "robot_legions", 1)
	var foes: Array = []
	for i in range(4):
		foes.append(Vector3((3.0 + float(i)) * IN2M, 0, 0))
	var squad := _unit(2, "Squad", foes)
	var state := _capture([caster, squad])
	var next := BattleSim.resolve(state,
		{"unit": "Wizard", "kind": AiDecision.Action.HOLD, "shoot": "Squad"})
	assert_int((next.get("cast_events", []) as Array).size()).is_equal(1)
	assert_int(int((next["units"]["Wizard"] as Dictionary)["casts"])).is_equal(0)


## (f) A SHAKEN caster spends its activation idle and casts nothing (GF v3.5.1
## p.10). Same fixture as (a) — enemy 3" out, one affordable damage spell — so
## the only difference is the flag: no token spent, no event, no wound.
func test_shaken_caster_casts_nothing() -> void:
	var state := _melee_caster_state(3.0)
	(state["units"]["Wizard"] as Dictionary)["shaken"] = true
	var next := _hold(state)
	assert_int(int((next["units"]["Wizard"] as Dictionary)["casts"])).is_equal(1)
	assert_array(next.get("cast_events", [])).is_empty()
	assert_float(float((next["units"]["Squad"] as Dictionary).get("wound_frac", 0.0))).is_equal(0.0)
