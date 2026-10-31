extends GdUnitTestSuite
## SHO-07 (0.3.15, rules 3.6): a shot AT an Aircraft is also -1 to hit, on top of the -12" range
## penalty (held in solo_aircraft_test.gd). The number is the shipped map's Aircraft
## `target_hit_penalty`, read only from AiActRecorder.EPOCH_73_V36; at EPOCH_72_PLAYTEST_RULES the table
## and the AI keep the 3.5 reading. Both legs read the real maps (default faction = common entry).

const MainScript := preload("res://scripts/main.gd")
const RIFLE := {"range": 24, "attacks": 10, "ap": 0}
const GUNNER := {"quality": 4, "models": 1}


func before_test() -> void:
	RulesRegistry.reset_cache()


func _unit(rules: Array, system: String = "gf") -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = "flyer"
	u.unit_properties = {"player_id": 2, "name": "Flyer", "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": system}
	var m := ModelInstance.new()
	m.is_alive = true
	m.node = auto_free(Node3D.new())
	add_child(m.node)
	u.models.append(m)
	return u


## The table's to-hit breakdown for one shot from 12" at `target`, read at `epoch`.
func _hit_info_at(epoch: int, target: GameUnit) -> Dictionary:
	var epoch0: int = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = epoch
	var main: Node3D = auto_free(MainScript.new())
	var info: Dictionary = main._solo_hit_mod_info(null, target, 12.0, false)
	AiActRecorder.rules_epoch = epoch0   # statics leak across gdUnit tests: restore
	return info


## The AI's expected damage of one 10-shot Quality 4+ rifle volley at `target`, read at `epoch`.
func _ev_at(epoch: int, target: GameUnit, profile: Dictionary = RIFLE) -> float:
	var epoch0: int = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = epoch
	var ev := AiEv.profile_ev(profile, GUNNER, AiEv.ctx_for(target), 12.0, false)
	AiActRecorder.rules_epoch = epoch0
	return ev


## OLD leg: at 72 a shot at an Aircraft carries no to-hit modifier and names none.
func test_a_shot_at_aircraft_has_no_hit_penalty_at_epoch_72() -> void:
	var info := _hit_info_at(AiActRecorder.EPOCH_72_PLAYTEST_RULES, _unit(["Aircraft"]))
	assert_int(int(info["mod"])).is_equal(0)
	assert_str(str(info.get("note", ""))).not_contains("Aircraft")


## NEW leg: from 73 the same shot is -1 in both systems and the note names the rule (the volley's
## to-hit log line carries it).
func test_a_shot_at_aircraft_is_minus_one_to_hit_at_epoch_73() -> void:
	for system: String in ["gf", "aof"]:
		var info := _hit_info_at(AiActRecorder.EPOCH_73_V36, _unit(["Aircraft"], system))
		assert_int(int(info["mod"])).override_failure_message("%s: Aircraft -1 to hit" % system).is_equal(-1)
		assert_str(str(info.get("note", ""))).contains("Aircraft -1")


## Control: a ground unit takes nothing at 73, and the range penalty stays 12" at both epochs.
func test_ground_targets_and_the_range_penalty_are_unchanged_at_epoch_73() -> void:
	var info := _hit_info_at(AiActRecorder.EPOCH_73_V36, _unit([]))
	assert_int(int(info["mod"])).is_equal(0)
	assert_str(str(info.get("note", ""))).not_contains("Aircraft")
	assert_float(SoloController.target_range_penalty_in(_unit(["Aircraft"]))).is_equal_approx(12.0, 0.001)


## The EV twin: from 73 the AI prices the shot at 5+ (1/3) instead of 4+ (1/2), exactly 2/3 of the
## 72 value; an Unstoppable weapon keeps the full value (the -1 is a negative modifier it ignores).
func test_the_ev_prices_the_aircraft_minus_one_from_epoch_73() -> void:
	var old := _ev_at(AiActRecorder.EPOCH_72_PLAYTEST_RULES, _unit(["Aircraft"]))
	var new := _ev_at(AiActRecorder.EPOCH_73_V36, _unit(["Aircraft"]))
	assert_float(old).is_greater(0.0)
	assert_float(new).is_equal_approx(old * 2.0 / 3.0, 0.0001)
	var unstoppable := RIFLE.duplicate()
	unstoppable["unstoppable"] = true
	assert_float(_ev_at(AiActRecorder.EPOCH_73_V36, _unit(["Aircraft"]), unstoppable)).is_equal_approx(old, 0.0001)


## The map row both engines read: the new key sits beside the untouched range key, gf and aof.
func test_the_shipped_maps_carry_the_aircraft_hit_penalty() -> void:
	for system: String in ["gf", "aof"]:
		var params: Dictionary = RulesRegistry.lookup(system, "", "Aircraft").get("params", {})
		assert_float(float(params.get("target_hit_penalty", 0.0))).is_equal(1.0)
		assert_float(float(params.get("target_range_penalty_in", 0.0))).is_equal(12.0)
