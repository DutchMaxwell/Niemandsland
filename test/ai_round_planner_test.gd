extends GdUnitTestSuite
## NML-210 — the NACHTMAHR round planner's pure assignment core. Contract: feasible arrival
## promises, one committed runner per free marker (anti-congestion), pairs only on enemy-held
## markers, rich shooters keep fighting when someone else can take the marker, deterministic.

const IN := 0.0254


func _u(key: String, x_in: float, band: float = 12.0, ev: float = 0.0) -> Dictionary:
	return {"key": key, "centre": Vector3(x_in * IN, 0, 0), "band_in": band, "ev_best": ev}


func _m(i: int, x_in: float, enemy: int = 0, owned: bool = false, enemy_owned: bool = false) -> Dictionary:
	return {"index": i, "pos": Vector3(x_in * IN, 0, 0), "ai_owned": owned,
		"enemy_owned": enemy_owned, "enemy_near": enemy}


func test_free_markers_get_exactly_one_runner_each_no_stacking() -> void:
	var sol := AiRoundPlanner.solve({
		"units": [_u("A", 0), _u("B", 2), _u("C", 4)],
		"markers": [_m(0, 10), _m(1, 14)],
		"rounds_left": 4, "current_round": 1})
	var tasks: Dictionary = sol["tasks"]
	var per := {}
	for k in tasks:
		var t: Dictionary = tasks[k]
		if str(t.get("kind")) == "seize":
			per[int(t["marker"])] = per.get(int(t["marker"]), 0) + 1
	assert_int(per.get(0, 0)).is_equal(1)   # one committed runner per free marker
	assert_int(per.get(1, 0)).is_equal(1)
	# The third unit fights — it does not stack a claimed marker.
	var fights := 0
	for k in tasks:
		if str((tasks[k] as Dictionary).get("kind")) == "fight":
			fights += 1
	assert_int(fights).is_equal(1)
	assert_str(str(sol["log"])).contains("NACHTMAHR plan")


func test_infeasible_marker_is_never_promised() -> void:
	# 50" away, band 6", 3 rounds left (incl. current) → needs 8 rounds: no promise, unit fights.
	var sol := AiRoundPlanner.solve({
		"units": [_u("Slow", 0, 6.0)],
		"markers": [_m(0, 50)],
		"rounds_left": 3, "current_round": 2})
	assert_str(str((sol["tasks"]["Slow"] as Dictionary).get("kind"))).is_equal("fight")


func test_last_round_arrival_still_counts_and_stamps_the_round() -> void:
	# 14" away, band 6": travel 11 after the ring → 2 marches (R2 + R3) — the unit stands on the
	# marker at the END of R3 (the old stamp said R4: the maintainer-log off-by-one).
	var sol := AiRoundPlanner.solve({
		"units": [_u("Runner", 0, 6.0)],
		"markers": [_m(0, 14)],
		"rounds_left": 3, "current_round": 2})
	var t: Dictionary = sol["tasks"]["Runner"]
	assert_str(str(t.get("kind"))).is_equal("seize")
	assert_int(int(t.get("arrive_round"))).is_equal(3)


func test_final_round_one_march_trip_is_feasible() -> void:
	# Maintainer log R4 (lost 0:3): "everyone fights — no feasible marker trip" while Battle
	# Brothers stood 13.7" from the marker — ONE 12" rush away. A march in THIS round arrives at
	# THIS round's end: need ≤ rounds_left, and the final round still sends the runner.
	var sol := AiRoundPlanner.solve({
		"units": [_u("Runner", 0, 12.0)],
		"markers": [_m(0, 13.7)],
		"rounds_left": 1, "current_round": 4})
	var t: Dictionary = sol["tasks"]["Runner"]
	assert_str(str(t.get("kind"))).is_equal("seize")
	assert_int(int(t.get("arrive_round"))).is_equal(4)


func test_enemy_held_denial_is_late_game_only() -> void:
	# Maintainer find ("die KI findet sich damit ab, dass der Punkt besetzt ist") + wave5 A/B: on an
	# ENEMY-HELD marker the fight happens AT the marker, so the trip forfeits no volleys — but only
	# in the LAST TWO rounds (blanket denial churned mirror games into neutrals; the late form
	# measured best). Mid-game keeps the commander-hold economics; empty markers always pay.
	var late := AiRoundPlanner.solve({
		"units": [_u("Gunner", 0, 12.0, 2.0)],
		"markers": [_m(0, 24, 1)],
		"rounds_left": 2, "current_round": 3})
	assert_str(str((late["tasks"]["Gunner"] as Dictionary).get("kind"))).is_equal("seize")   # endgame: contest
	var mid := AiRoundPlanner.solve({
		"units": [_u("Gunner", 0, 12.0, 2.0)],
		"markers": [_m(0, 33, 1)],
		"rounds_left": 4, "current_round": 1})
	assert_str(str((mid["tasks"]["Gunner"] as Dictionary).get("kind"))).is_equal("fight")    # mid-game: volley economics
	var free := AiRoundPlanner.solve({
		"units": [_u("Gunner", 0, 12.0, 2.0)],
		"markers": [_m(0, 33)],
		"rounds_left": 4, "current_round": 1})
	assert_str(str((free["tasks"]["Gunner"] as Dictionary).get("kind"))).is_equal("fight")   # empty marker always pays


func test_rich_shooter_keeps_fighting_when_a_cheap_runner_exists() -> void:
	# Both can reach; the shooter's volley (EV 6) makes the trip a bad trade — the idle unit runs.
	var sol := AiRoundPlanner.solve({
		"units": [_u("Shooter", 8, 12.0, 6.0), _u("Idle", 6, 12.0, 0.0)],
		"markers": [_m(0, 12)],
		"rounds_left": 4, "current_round": 1})
	assert_str(str((sol["tasks"]["Idle"] as Dictionary).get("kind"))).is_equal("seize")
	assert_str(str((sol["tasks"]["Shooter"] as Dictionary).get("kind"))).is_equal("fight")


func test_enemy_held_marker_may_take_a_pair_with_lanes() -> void:
	var sol := AiRoundPlanner.solve({
		"units": [_u("A", 0), _u("B", 2), _u("C", 30)],
		"markers": [_m(0, 10, 2)],
		"rounds_left": 4, "current_round": 1, "max_per_marker": 1, "contest_cap": 2})
	var a: Dictionary = sol["tasks"]["A"]
	var b: Dictionary = sol["tasks"]["B"]
	assert_str(str(a.get("kind"))).is_equal("seize")
	assert_str(str(b.get("kind"))).is_equal("seize")
	# Lane indices separate the pair (the execution spreads their approach laterally).
	assert_bool(int(a.get("lane", -1)) != int(b.get("lane", -1))).is_true()


func test_solve_is_deterministic() -> void:
	var p := {
		"units": [_u("A", 0, 12.0, 1.0), _u("B", 2, 6.0, 2.0), _u("C", 4, 12.0, 0.0)],
		"markers": [_m(0, 10, 1), _m(1, 14), _m(2, 40)],
		"rounds_left": 3, "current_round": 2}
	var s1 := AiRoundPlanner.solve(p)
	var s2 := AiRoundPlanner.solve(p.duplicate(true))
	assert_str(JSON.stringify(s1["tasks"])).is_equal(JSON.stringify(s2["tasks"]))
	assert_str(str(s1["log"])).is_equal(str(s2["log"]))


func test_opportunity_cost_scales_with_the_march_length() -> void:
	# Live gun (EV 1.0), marker 3 rounds away: the trip costs three volleys — the shooter fights.
	var far := AiRoundPlanner.solve({
		"units": [_u("Gun", 0, 12.0, 1.0)],
		"markers": [_m(0, 30)],
		"rounds_left": 4, "current_round": 1})
	assert_str(str((far["tasks"]["Gun"] as Dictionary).get("kind"))).is_equal("fight")
	# The same trek with NOTHING to shoot is pure profit — it walks.
	var idle := AiRoundPlanner.solve({
		"units": [_u("Idle", 0, 12.0, 0.0)],
		"markers": [_m(0, 30)],
		"rounds_left": 4, "current_round": 1})
	assert_str(str((idle["tasks"]["Idle"] as Dictionary).get("kind"))).is_equal("seize")
