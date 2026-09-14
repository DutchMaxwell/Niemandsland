extends GdUnitTestSuite
## Surprise Attack, the HUMAN seat (STANDALONE_SWEEP_D_2026-09-14, row Surprise Attack — DIVERGES):
## the burst existed only inside the AI activation body (main.gd:1088 gates on _solo_is_ai_unit),
## so the human bearer's first activation never struck while the AI's identical bearer did. The
## rule (gf + aof): "The first time this unit is activated, pick one enemy unit within 6" in line
## of sight, and roll X dice. For each 2+ it takes one hit with AP(1)." The first-activation latch
## is the once-per-game `surprise_attack_used` stamp the AI path already writes (main.gd:17719/17733).
## The seam under test is the seat-agnostic bearer-latch probe the burst loop shares. Test-first:
## the probe arrives with the fix, so the suite guards with has_method (the #183
## charge_path_probe precedent, solo_charge_corridor_gate_test.gd:67) and the assertions FAIL
## while the gate is still AI-only.

const MainScript := preload("res://scripts/main.gd")


func _bearer(player_id: int, unit_id: String, alive_models: int = 3,
		used: bool = false, bearer: bool = true) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = unit_id
	u.unit_properties = {"player_id": player_id, "name": unit_id, "quality": 4, "defense": 4,
		"special_rules": ["Surprise Attack"] if bearer else []}
	if used:
		u.unit_properties["surprise_attack_used"] = true
	for i in range(alive_models):
		var m := ModelInstance.new()
		m.is_alive = true
		var n := Node3D.new()
		add_child(n)
		n.global_position = Vector3(0, 0, 0.5)
		m.node = n
		u.models.append(m)
	return u


func _controller(units: Array) -> SoloController:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	for unit in units:
		army.game_units[(unit as GameUnit).unit_id] = unit
	army.current_round = 1
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	return solo


func _ready(solo: SoloController, bu: GameUnit) -> bool:
	# The missing-marker default makes every test below FAIL while the seam does not
	# exist yet — a parse-error-free red that flips green with the fix.
	if not solo.has_method("surprise_attack_bearer_ready"):
		return false
	return bool(solo.call("surprise_attack_bearer_ready", bu))


func test_human_bearer_on_its_first_activation_is_ready() -> void:
	var bu := _bearer(1, "human_bearer")
	var solo := _controller([bu])
	assert_bool(_ready(solo, bu)).override_failure_message(
		"the human's Surprise Attack bearer never fires its first-activation burst — "
		+ "the table gate is AI-only (main.gd _solo_is_ai_unit)").is_true()


func test_ai_bearer_on_its_first_activation_is_ready_too() -> void:
	# The core fires the burst for both seats (sim.rs:5128-5132) — the seam must never
	# re-introduce a seat split.
	var bu := _bearer(2, "ai_bearer")
	var solo := _controller([bu])
	assert_bool(_ready(solo, bu)).is_true()


func test_the_once_per_game_latch_stops_the_second_activation() -> void:
	var bu := _bearer(1, "human_bearer", 3, true)
	var solo := _controller([bu])
	assert_bool(_ready(solo, bu)).is_false()


func test_a_dead_bearer_is_never_ready() -> void:
	var bu := _bearer(1, "dead_bearer", 0)
	var solo := _controller([bu])
	assert_bool(_ready(solo, bu)).is_false()


func test_a_unit_without_the_rule_is_never_ready() -> void:
	var bu := _bearer(1, "plain_unit", 3, false, false)
	var solo := _controller([bu])
	assert_bool(_ready(solo, bu)).is_false()
