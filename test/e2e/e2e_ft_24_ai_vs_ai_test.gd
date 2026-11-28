extends GdUnitTestSuite
## Feature test FT-24: a whole AI-vs-AI game on the table, Firefight (gff) and Skirmish (aofs), 4 x 4 ft, base mission.
## FF36 p.6 l.376-394, p.7 l.487-507 (AS36 the same): 4 rounds of alternating activations, then the side holding most
## markers wins. Per game (3 tray seeds a system): the game ends after round 4 with a verdict, the core refused no AI
## activation, and the log holds at least one volley, one melee and one morale test. A census line counts jumps and push
## offers (expected 0 at the shipped epoch: jumping is dormant below 106, no AI pushes - recorded, not asserted).
## Scene: own-stats units built on the table (both sides: two 5-model rifle squads, one 3-model Tough(3) melee squad), set
## up 12 in from their edges, three markers.
## Real: the main scene, the both-AI seat, the table's both-AI game loop, the AI planner, the core, the round-end seize,
## the game summary.

const INCH := 0.0254
const SEEDS := [0, 1, 2]

var _t: SkirmishTable


func before_test() -> void:
	_t = await SkirmishTable.boot(self, "A")
	await _t.table_feet(Vector2(4, 4))


func after_test() -> void:
	if _t != null:
		_t.teardown()
	_t = null


func _armies(sys: String) -> void:
	for side in [1, 2]:
		var z := -18.0 if side == 1 else 18.0
		var tag := "P%d" % side
		_t.unit(sys, side, tag + " Rifles A", 5, 1, -12.0, z, {"name": "Rifle", "range_in": 24, "attacks": 1, "count": 5, "rules": []})
		_t.unit(sys, side, tag + " Rifles B", 5, 1, 12.0, z, {"name": "Rifle", "range_in": 24, "attacks": 1, "count": 5, "rules": []})
		_t.unit(sys, side, tag + " Blades", 3, 3, 0.0, z, {"name": "Blade", "range_in": 0, "attacks": 3, "count": 3, "rules": []})
	_t.main.terrain_overlay.update_objectives([Vector3(-12.0 * INCH, 0, 0), Vector3.ZERO, Vector3(12.0 * INCH, 0, 0)], [0, 0, 0])


func _has(needle: String) -> bool:
	return _t.lines.any(func(l: String) -> bool: return l.find(needle) != -1)


func _games(sys: String) -> void:
	var bad: Array = []
	for s in SEEDS:
		_t.reset()
		await _t.runner.simulate_frames(2)
		_armies(sys)
		_t.main.seed_tray_rng(s)
		var refusals := CoreActivation.ai_refusals
		await _t.run_ai_game(1)
		var summary := _t.summary_text()
		if not summary.contains("4 rounds played."):
			bad.append("seed %d: no 4-round summary: %s" % [s, summary])
		if not (summary.ends_with("wins") or summary.ends_with("Draw")):
			bad.append("seed %d: no verdict: %s" % [s, summary])
		if CoreActivation.ai_refusals != refusals:
			bad.append("seed %d: %d core refusals" % [s, CoreActivation.ai_refusals - refusals])
		for want in ["fires", "Melee result:", "morale"]:
			if not _has(want):
				bad.append("seed %d: no '%s' line" % [s, want])
		print("FT-24 %s seed %d census: jumps %d, pushes offered %d, lines %d, round %d" % [sys, s,
			_t.lines.filter(func(l: String) -> bool: return l.begins_with("Jump")).size(),
			_t.lines.filter(func(l: String) -> bool: return l.begins_with("Push")).size(), _t.lines.size(),
			_t.main.opr_army_manager.current_round])
	assert_array(bad).override_failure_message("\n".join(bad)).is_empty()


func test_gff_ai_vs_ai_games(timeout := 900000) -> void:
	await _games("gff")


func test_aofs_ai_vs_ai_games(timeout := 900000) -> void:
	await _games("aofs")
