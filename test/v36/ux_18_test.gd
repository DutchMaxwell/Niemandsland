extends GdUnitTestSuite
## UX-18 (rules 3.6): every Bounding-primitive alias (Wolfborn, Wave-Step, Rapid Blink) MOVES its
## rolled inches instead of placing the unit, exactly like the named Bounding family from UX-17.
## The table AI already spends the roll as a bonus on every move band, so from EPOCH_73_V36 its
## decision record says the unit moves; at EPOCH_72 the old "placed" wording stays.

const IN2M := 0.0254

## Alias name, game system, book folder — the three carriers the row names.
const ALIASES := [
	["Wolfborn", "gf", "wolf_brothers"],
	["Wave-Step", "aof", "deep_sea_elves"],
	["Rapid Blink", "gf", "elven_jesters"],
]

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	MovementPlanner.fast_planner = false
	MovementPlanner.fast_planner_guard = MovementPlanner.FAST_PLANNER_GUARD


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests — restore


func _unit(pid: int, uid: String, pos: Vector3) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4}
	var m := ModelInstance.new()
	m.is_alive = true
	var n := Node3D.new()
	add_child(n)
	n.global_position = pos
	m.node = n
	u.models.append(m)
	return u


## One seeded AI activation of an alias carrier far from its foe, at `epoch`.
## Returns the activation's decision log.
func _activate_carrier(rule: String, system: String, faction: String, epoch: int) -> Array:
	AiActRecorder.rules_epoch = epoch
	var foe := _unit(1, "Foe", Vector3(30.0 * IN2M, 0, 0))
	var ai := _unit(2, "Carrier", Vector3.ZERO)
	ai.unit_properties["special_rules"] = [rule]
	ai.unit_properties["game_system"] = system
	ai.unit_properties["faction_folder"] = faction
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {foe.unit_id: foe, ai.unit_id: ai}
	army.current_round = 1
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	solo._rng.seed = 7
	solo._act(ai)
	return solo.decision_log.duplicate()


func _bounding_record(dlog: Array) -> Dictionary:
	for rec in dlog:
		if str((rec as Dictionary).get("why", "")) == "bounding placement":
			return rec
	return {}


func test_bounding_aliases_keep_the_placed_wording_at_epoch_72() -> void:
	for a in ALIASES:
		var dlog := _activate_carrier(a[0], a[1], a[2], AiActRecorder.EPOCH_72_PLAYTEST_RULES)
		var rec := _bounding_record(dlog)
		assert_bool(rec.is_empty()).override_failure_message(
			"%s: no Bounding record: %s" % [a[0], dlog]).is_false()
		var text := str(rec["rule"])
		assert_str(text).override_failure_message("%s: %s" % [a[0], text]).contains(a[0])
		assert_str(text).override_failure_message("%s: %s" % [a[0], text]).contains("placed")


func test_bounding_aliases_say_the_unit_moves_at_epoch_73() -> void:
	for a in ALIASES:
		var dlog := _activate_carrier(a[0], a[1], a[2], AiActRecorder.EPOCH_73_V36)
		var rec := _bounding_record(dlog)
		assert_bool(rec.is_empty()).override_failure_message(
			"%s: no Bounding record: %s" % [a[0], dlog]).is_false()
		var text := str(rec["rule"])
		assert_str(text).override_failure_message("%s: %s" % [a[0], text]).contains(a[0])
		assert_str(text).override_failure_message("%s: %s" % [a[0], text]).contains("moves up to")
		assert_str(text).override_failure_message("%s: %s" % [a[0], text]).not_contains("placed")
