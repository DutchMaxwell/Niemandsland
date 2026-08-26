extends GdUnitTestSuite
## NML-1068: BattleSim.resolve's unit-spacing clamp — a research seam
## (NML_SIM_SPACING) mirroring SoloController._spacing_zones_world's no-go
## disc (other model radius + UNIT_SPACING_IN + mover model radius) as a
## delta shortener on the rigid formation translate. Fixture mirrors
## battle_sim_resolve_test.gd's _state_with_grunts (bare GameUnit + Node3D
## models, default 32mm base -> SeparationChecker.DEFAULT_BASE_RADIUS_M).
##
## _spacing_env does not exist pre-fix (this file is written RED-first).
## Dynamic dispatch via a throwaway instance (BattleSim.new().set(...)) keeps
## this file PARSING pre-fix — a direct BattleSim._spacing_env reference
## would be a parse error, which would mask the behavioral REDs this file
## exists to prove (same trick as ai_planner_depth_seam_test.gd).

const IN2M := 0.0254


func _reset_spacing_cache() -> void:
	BattleSim.new().set("_spacing_env", -1)


func _unit_at(pid: int, positions: Array, uid: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4,
		"special_rules": []}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		m.unit = u
		var n := Node3D.new()
		add_child(n)
		n.global_position = p
		m.node = n
		u.models.append(m)
	return u


func _capture(mover: GameUnit, blocker: GameUnit) -> Dictionary:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Mover": mover, "Blocker": blocker}
	return BattleSim.capture(army)


func before_test() -> void:
	OS.set_environment("NML_SIM_SPACING", "")
	_reset_spacing_cache()


func after_test() -> void:
	OS.set_environment("NML_SIM_SPACING", "")
	_reset_spacing_cache()


## (a) pins today's behaviour: seam off, resolve rigidly translates the whole
## mover onto the destination with no regard for the Blocker sitting there —
## a full overlap (0" between centres).
func test_seam_off_the_mover_ends_fully_overlapping_the_blocker() -> void:
	var mover := _unit_at(1, [Vector3.ZERO], "Mover")
	var blocker := _unit_at(2, [Vector3(6.0 * IN2M, 0, 0)], "Blocker")
	var state := _capture(mover, blocker)
	var next := BattleSim.resolve(state, {"unit": "Mover", "kind": AiDecision.Action.RUSH,
		"dest": Vector3(6.0 * IN2M, 0, 0)})
	var mp: Vector3 = (next["units"]["Mover"] as Dictionary)["positions"][0]
	var bp: Vector3 = (next["units"]["Blocker"] as Dictionary)["positions"][0]
	assert_float((mp - bp).length() / IN2M).is_less(1.0)


## (b) seam on: the mover stops with its base edge exactly UNIT_SPACING_IN
## clear of the Blocker's — the disc boundary the binary search converges on.
## Distance kept short (2.3") so the 8-step search lands within 0.01" of it.
func test_seam_on_the_mover_stops_outside_the_blockers_spacing_disc() -> void:
	OS.set_environment("NML_SIM_SPACING", "1")
	_reset_spacing_cache()
	var mover := _unit_at(1, [Vector3.ZERO], "Mover")
	var blocker := _unit_at(2, [Vector3(2.3 * IN2M, 0, 0)], "Blocker")
	var state := _capture(mover, blocker)
	var next := BattleSim.resolve(state, {"unit": "Mover", "kind": AiDecision.Action.RUSH,
		"dest": Vector3(2.3 * IN2M, 0, 0)})
	var mp: Vector3 = (next["units"]["Mover"] as Dictionary)["positions"][0]
	var bp: Vector3 = (next["units"]["Blocker"] as Dictionary)["positions"][0]
	var r_in := SeparationChecker.DEFAULT_BASE_RADIUS_M / IN2M
	var gap_in: float = (mp - bp).length() / IN2M - 2.0 * r_in
	assert_float(gap_in).is_greater_equal(SoloController.UNIT_SPACING_IN - 0.01)


## (c) seam on but nothing nearby: the Blocker sits far away, so the clamp
## never engages — byte-identical positions to seam off.
func test_seam_on_a_move_far_from_any_other_unit_is_untouched() -> void:
	var mover := _unit_at(1, [Vector3.ZERO], "Mover")
	var blocker := _unit_at(2, [Vector3(100.0 * IN2M, 0, 0)], "Blocker")
	var state := _capture(mover, blocker)
	var action := {"unit": "Mover", "kind": AiDecision.Action.RUSH, "dest": Vector3(4.0 * IN2M, 0, 0)}
	var off := BattleSim.resolve(state, action)
	OS.set_environment("NML_SIM_SPACING", "1")
	_reset_spacing_cache()
	var on := BattleSim.resolve(state, action)
	assert_that((on["units"]["Mover"] as Dictionary)["positions"]).is_equal(
		(off["units"]["Mover"] as Dictionary)["positions"])


## (d) seam on, mover starting INSIDE a disc but with a CLEAR destination: the
## engine forbids ENDING inside a no-go disc, never merely leaving one —
## deployment in the trainer has no spacing rule, so a captured state may
## legally start overlapped. t=1 is legal here, so the full move goes through
## regardless of the illegal start.
func test_seam_on_a_mover_starting_inside_a_disc_moves_to_a_clear_destination() -> void:
	OS.set_environment("NML_SIM_SPACING", "1")
	_reset_spacing_cache()
	var mover := _unit_at(1, [Vector3.ZERO], "Mover")
	var blocker := _unit_at(2, [Vector3(1.0 * IN2M, 0, 0)], "Blocker")
	var state := _capture(mover, blocker)
	var dest := Vector3(-6.0 * IN2M, 0, 0)
	var next := BattleSim.resolve(state, {"unit": "Mover", "kind": AiDecision.Action.RUSH,
		"dest": dest})
	var mp: Vector3 = (next["units"]["Mover"] as Dictionary)["positions"][0]
	assert_that(mp).is_equal(dest)


## (e) seam on, BOTH the start and the full move illegal (Blocker models
## flank the start and the destination) but a middle fraction of the path
## crosses open ground: no monotone guarantee, so the descending 8-point
## sample (t=1.0,0.875,...,0.125) is used — it must pick the largest legal t
## (0.625 here -> x=5.0") and land the mover clear of every disc.
func test_seam_on_start_and_destination_both_blocked_picks_the_open_middle() -> void:
	OS.set_environment("NML_SIM_SPACING", "1")
	_reset_spacing_cache()
	var mover := _unit_at(1, [Vector3.ZERO], "Mover")
	var blocker := _unit_at(2, [Vector3(1.0 * IN2M, 0, 0), Vector3(8.0 * IN2M, 0, 0)], "Blocker")
	var state := _capture(mover, blocker)
	var next := BattleSim.resolve(state, {"unit": "Mover", "kind": AiDecision.Action.RUSH,
		"dest": Vector3(8.0 * IN2M, 0, 0)})
	var mp: Vector3 = (next["units"]["Mover"] as Dictionary)["positions"][0]
	assert_float(mp.x / IN2M).is_equal_approx(5.0, 0.001)
	var r_in := SeparationChecker.DEFAULT_BASE_RADIUS_M / IN2M
	for bp in (next["units"]["Blocker"] as Dictionary)["positions"]:
		var gap_in: float = (mp - (bp as Vector3)).length() / IN2M - 2.0 * r_in
		assert_float(gap_in).is_greater_equal(0.0)


## NML-1073 S1: the CHARGE target gets a body-only (buffer 0.0) disc — GF
## Advanced Rules v3.5.1 p.7's "may ignore that [1"] restriction" toward base
## contact with ONE enemy unit. Pre-fix every other unit (including a charge
## victim) keeps the full UNIT_SPACING_IN buffer, so the mover stops ~1" short
## (RED); post-fix the charge target is body-only, so the mover reaches base
## contact (GREEN).
func test_a_charge_may_end_the_mover_in_base_contact_with_its_target() -> void:
	OS.set_environment("NML_SIM_SPACING", "1")
	_reset_spacing_cache()
	var mover := _unit_at(1, [Vector3.ZERO], "Mover")
	var blocker := _unit_at(2, [Vector3(6.0 * IN2M, 0, 0)], "Blocker")
	var state := _capture(mover, blocker)
	var next := BattleSim.resolve(state, {"unit": "Mover", "kind": AiDecision.Action.CHARGE,
		"dest": Vector3(6.0 * IN2M, 0, 0), "charge": "Blocker"})
	var mp: Vector3 = (next["units"]["Mover"] as Dictionary)["positions"][0]
	var bp: Vector3 = (next["units"]["Blocker"] as Dictionary)["positions"][0]
	var gap_m: float = (mp - bp).length() - 2.0 * SeparationChecker.DEFAULT_BASE_RADIUS_M
	assert_float(gap_m).is_less(0.001)


## Guard against over-exemption: a RUSH (not a Charge) toward the same point
## must still respect the full UNIT_SPACING_IN buffer against the same unit —
## the exemption is charge-target-only, never a general "ignore everyone" seam.
## GREEN both before and after this fix (no behaviour change for non-charges).
func test_a_rush_toward_the_same_point_still_keeps_the_spacing_buffer() -> void:
	OS.set_environment("NML_SIM_SPACING", "1")
	_reset_spacing_cache()
	var mover := _unit_at(1, [Vector3.ZERO], "Mover")
	var blocker := _unit_at(2, [Vector3(6.0 * IN2M, 0, 0)], "Blocker")
	var state := _capture(mover, blocker)
	var next := BattleSim.resolve(state, {"unit": "Mover", "kind": AiDecision.Action.RUSH,
		"dest": Vector3(6.0 * IN2M, 0, 0)})
	var mp: Vector3 = (next["units"]["Mover"] as Dictionary)["positions"][0]
	var bp: Vector3 = (next["units"]["Blocker"] as Dictionary)["positions"][0]
	var r_in := SeparationChecker.DEFAULT_BASE_RADIUS_M / IN2M
	var gap_in: float = (mp - bp).length() / IN2M - 2.0 * r_in
	assert_float(gap_in).is_greater_equal(SoloController.UNIT_SPACING_IN - 0.01)


func _capture_with_hero(mover: GameUnit, hero: GameUnit) -> Dictionary:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Mover": mover, "Hero": hero}
	return BattleSim.capture(army)


## NML-1073 S1: an attached hero moves as part of its host's body, so it must
## never obstruct the host's own move — mirrors SoloController._spacing_
## zones_world's "mover + its attached heroes are exempt entirely". Pre-fix
## the hero is just another unit's model sitting on top of the mover's start,
## so even a short move stays inside its no-go disc the whole way (RED, t=0.0
## — none of the fast-path/bisection/8-point-sample candidates are legal).
## Post-fix the hero is skipped as an obstacle entirely, leaving no obstacle
## at all, so the move goes through in full (GREEN).
func test_an_attached_hero_does_not_block_its_hosts_rush() -> void:
	OS.set_environment("NML_SIM_SPACING", "1")
	_reset_spacing_cache()
	var mover := _unit_at(1, [Vector3.ZERO], "Mover")
	var hero := _unit_at(1, [Vector3.ZERO], "Hero")
	hero.unit_properties["attached_to"] = mover
	mover.unit_properties["attached_heroes"] = [hero]
	var state := _capture_with_hero(mover, hero)
	var dest := Vector3(1.0 * IN2M, 0, 0)
	var next := BattleSim.resolve(state, {"unit": "Mover", "kind": AiDecision.Action.RUSH,
		"dest": dest})
	var mp: Vector3 = (next["units"]["Mover"] as Dictionary)["positions"][0]
	assert_that(mp).is_equal(dest)
