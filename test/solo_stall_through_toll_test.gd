extends GdUnitTestSuite
## Stall escalation (solo_controller _execute_move): the THROUGH-plan that crosses a minefield is kept only
## when its expected toll (Tough-weighted dangerous dice / 6, the currency of charge_dangerous_toll) is
## below max(1.0, 10 % of the unit's current wounds). Otherwise the avoiding stub stays. A move the player
## ordered is never refused (tested on the verdict; the real player path is e2e_game_school_ch8_test, whose
## movement outcome depends on planner state that differs between CI shards, so it is not repeated here).

const IN2M := 0.0254

var _mgr: OPRArmyManager
var _solo: SoloController


func before_test() -> void:
	_mgr = auto_free(OPRArmyManager.new())
	_solo = auto_free(SoloController.new())
	add_child(_solo)
	_solo.army_manager = _mgr
	_solo.human_slot = 1
	_solo.ai_slot = 2
	# A dangerous band across the whole table at z in [3", 5"] — no detour exists, the goal lies behind it.
	_solo.terrain_type_at = func(p: Vector3) -> int:
		var z_in := p.z / IN2M
		return TerrainRules.TerrainType.DANGEROUS if z_in >= 3.0 and z_in <= 5.0 \
			else TerrainRules.TerrainType.NONE


func _unit(id: String, n: int) -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = id
	u.unit_properties = {"player_id": 2, "special_rules": [], "name": id, "quality": 4, "defense": 4}
	for i in range(n):
		var m := ModelInstance.new()
		m.unit = u
		m.is_alive = true
		m.wounds_max = 1
		m.wounds_current = 1
		m.node = auto_free(Node3D.new())
		add_child(m.node)
		m.node.global_position = Vector3(float(i % 5) * 1.5 * IN2M, 0, float(i / 5) * -1.5 * IN2M + 1.0 * IN2M)
		u.models.append(m)
	_mgr.game_units[id] = u
	return u


func _front_z_in(u: GameUnit) -> float:
	var z := -INF
	for m in u.models:
		z = maxf(z, (m as ModelInstance).node.global_position.z / IN2M)
	return z


func _crossing_trails(n: int) -> Array:
	var trails: Array = []
	for i in range(n):
		trails.append([Vector3(float(i) * IN2M, 0, 0), Vector3(float(i) * IN2M, 0, 12.0 * IN2M)])
	return trails


func _radii(n: int) -> Array:
	var r: Array = []
	for _i in range(n):
		r.append(0.5 * IN2M)
	return r


func test_verdict_refuses_a_big_crossing_for_the_ai() -> void:
	var horde := _unit("Horde", 15)
	var v: Dictionary = _solo.through_toll_verdict(horde.models, _crossing_trails(15), _radii(15), "Horde", false)
	assert_bool(bool(v["refused"])).is_true()
	assert_str(str(v["note"])).contains("no crossing through DANGEROUS ground")


func test_verdict_never_refuses_a_move_the_player_ordered() -> void:
	var horde := _unit("Horde", 15)
	var v: Dictionary = _solo.through_toll_verdict(horde.models, _crossing_trails(15), _radii(15), "Horde", true)
	assert_bool(bool(v["refused"])).is_false()
	assert_str(str(v["note"])).contains("as ordered")


func test_verdict_lets_a_small_crossing_through() -> void:
	var pair := _unit("Pair", 2)
	var v: Dictionary = _solo.through_toll_verdict(pair.models, _crossing_trails(2), _radii(2), "Pair", false)
	assert_bool(bool(v["refused"])).is_false()
	assert_str(str(v["note"])).contains("expected toll")


func test_small_unit_still_crosses() -> void:
	var pair := _unit("Pair", 2)
	_solo._execute_move(pair, Vector3(0, 0, 14.0 * IN2M), 12.0, false)
	assert_float(_front_z_in(pair)).is_greater(5.0)


func _rush(u: GameUnit, source: String) -> void:
	var intent := {"unit": u, "action": AiDecision.Action.RUSH, "goal": Vector3(0, 0, 14.0 * IN2M),
		"band_in": 12.0, "source": source, "why": "test"}
	_solo.execute_intent(intent, ActIntent.blank_report(u))


# Whether the stall check fires is decided by the FRONT RANK's progress toward the goal, so these two do not
# depend on how far a rear model happens to shuffle in the avoiding stub (CI differed from local there).
func test_player_ordered_rush_crosses_the_field() -> void:
	var horde := _unit("Horde", 15)
	_rush(horde, "player")
	assert_float(_front_z_in(horde)).is_greater(5.0)


func test_ai_rush_stops_short_of_the_field() -> void:
	var horde := _unit("Horde", 15)
	_rush(horde, "ai")
	assert_float(_front_z_in(horde)).is_less(3.5)


# The unit's centroid can move a lot while its front does not advance (a rear model shuffles sideways in the
# avoiding stub). That must count as a stall: progress is measured toward the goal at the front rank.
func test_rear_model_moving_sideways_is_a_stall() -> void:
	var before: Array = []
	var after: Array = []
	for i in 15:
		var p := Vector3(float(i % 5) * 1.5 * IN2M, 0, float(i / 5) * -1.5 * IN2M)
		before.append(p)
		after.append(p)
	# rear rank (rows 1-2, 10 models) slides 6 in. sideways (centroid 4 in. > 3 in. bar); the front row stays put
	for i in range(5, 15):
		after[i] = (before[i] as Vector3) + Vector3(-6.0 * IN2M, 0, 0)
	var goal := Vector3(0, 0, 14.0 * IN2M)
	var bar_m := 12.0 * IN2M * SoloController.STALL_REPLAN_FRACTION
	assert_float(SoloController.stall_progress_m(before, after, goal)).is_less(bar_m)
	# a front rank that really advances is not a stall
	var advanced: Array = []
	for p in before:
		advanced.append((p as Vector3) + Vector3(0, 0, 4.0 * IN2M))
	assert_float(SoloController.stall_progress_m(before, advanced, goal)).is_greater(bar_m)
