extends GdUnitTestSuite
## P1 (RATMEN_SHIP_REPORT §6.2, "Storm Ogres mixed pairs") through the REAL melee path: a unit carrying
## Bash (A2) x1 and Bash (A1) x2 — one Bash per model, rules identical — must swing 2 + 1 + 1 = 4 Bash
## attacks, the core's answer (attacks x count). On main AiShooting.merge_identical merged the two
## entries into ONE profile (attacks 4, count 3: the signature skips attacks/count as summable), and
## SoloController.scaled_attacks_report then swung per_copy = 4 / 3 = 1 attack per living bearer = 3.
## (The report's "table 9 vs core 4" came from its harness scaling the two entries unmerged with the
## name-keyed bearer count — both halves are fixed here: distinct per-copy attacks stay distinct
## profiles, and a bearer holds a copy of THIS profile, same name AND same per-copy attacks.)

const Profiles := preload("res://scripts/solo/ai_shooting.gd")

var _a2 := {"name": "Bash", "range": 0, "attacks": 2, "count": 1, "special_rules": []}
var _a1 := {"name": "Bash", "range": 0, "attacks": 1, "count": 2, "special_rules": []}


func _ogres(per_model: Array) -> GameUnit:
	var gu := GameUnit.new()
	gu.unit_id = "storm_ogres"
	gu.unit_properties = {"player_id": 1, "name": "Storm Ogres"}
	for ws in per_model:
		var mi := ModelInstance.new()
		mi.is_alive = true
		mi.unit = gu
		mi.properties = {"weapons": ws}
		gu.models.append(mi)
	return gu


func _swing(gu: GameUnit) -> int:
	var total := 0
	for p in Profiles.melee_profiles([_a2, _a1]):
		total += SoloController.bearer_scaled_attacks(gu, p, gu.models.size(), gu.models.size())
	return total


func test_mixed_bash_pairs_swing_what_the_core_swings() -> void:
	var gu := _ogres([[_a2], [], [], [], [_a1], [_a1]])
	assert_int(_swing(gu)) \
		.override_failure_message("P1 — Bash (A2) x1 + Bash (A1) x2 must swing 2 + 1 + 1 = 4 like the core") \
		.is_equal(4)


func test_a_dead_a2_bearer_takes_only_its_own_attacks_down() -> void:
	var gu := _ogres([[_a2], [], [], [], [_a1], [_a1]])
	(gu.models[0] as ModelInstance).is_alive = false
	assert_int(_swing(gu)).override_failure_message("the dead A2 bearer's two attacks die with it — 1 + 1 left").is_equal(2)


func test_distinct_per_copy_attacks_never_merge_but_identical_copies_still_do() -> void:
	assert_int(Profiles.melee_profiles([_a2, _a1]).size()).is_equal(2)
	var merged: Array = Profiles.melee_profiles([_a1, _a1])
	assert_int(merged.size()).override_failure_message("#217 — identical entries still merge").is_equal(1)
	assert_int(int(merged[0]["attacks"])).is_equal(4)
	assert_int(int(merged[0]["count"])).is_equal(4)


func test_the_name_only_call_keeps_its_answer() -> void:
	# The dead-weapon checks (solo_controller.gd:2808, main.gd:10097) still ask by name alone.
	var gu := _ogres([[_a2], [], [], [], [_a1], [_a1]])
	assert_int(SoloController.alive_bearers_of(gu, "Bash")).is_equal(3)
	assert_int(SoloController.alive_bearers_of(gu, "Bash", 2)).is_equal(1)
	assert_int(SoloController.alive_bearers_of(gu, "Bash", 1)).is_equal(2)
	# Thin per-model data (no attacks value) still matches by name — never a silenced volley.
	var thin := _ogres([[{"name": "Bash"}], [{"name": "Bash"}]])
	assert_int(SoloController.alive_bearers_of(thin, "Bash", 2)).is_equal(2)
