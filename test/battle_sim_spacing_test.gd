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


## NML-1073 S1b: melee-capable fixture — a CCW (melee, range 0, 4 attacks) on
## top of _unit_at's bare Node3D models, so the CHARGE branch's EV is
## non-zero. Mirrors battle_sim_resolve_test.gd's _armed fixture.
func _armed_at(pid: int, positions: Array, uid: String) -> GameUnit:
	var u := _unit_at(pid, positions, uid)
	var opr := OPRApiClient.OPRUnit.new()
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "CCW"
	w.range_value = 0
	w.attacks = 4
	w.count = 1
	opr.weapons.append(w)
	u.source_type = "opr"
	u.source_data = opr
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
## contact (GREEN). Two-sided (S1 review c): the lower bound alone (gap_m <
## 0.001) would also pass with the spacing seam OFF entirely — seam-off lands
## the mover exactly on the Blocker's centre, a deeply negative gap — so the
## upper bound (no overlap) proves the seam actually clamped the move.
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
	assert_float(gap_m).is_greater_equal(-1e-6)


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
## Two-sided (S1 review c): "mp == dest" alone would also pass with the
## spacing seam OFF entirely (seam-off applies delta unconditionally, same
## result) — it can't tell "the hero is correctly exempted" from "the seam
## never engaged". The control run below swaps the exempt Hero for a PLAIN
## unit at the identical start position and asserts THAT one gets clamped —
## proving the seam is live and the free pass is the exemption, not inertia.
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
	var decoy_mover := _unit_at(1, [Vector3.ZERO], "Mover")
	var decoy := _unit_at(2, [Vector3.ZERO], "Blocker")
	var decoy_state := _capture(decoy_mover, decoy)
	var clamped := BattleSim.resolve(decoy_state, {"unit": "Mover", "kind": AiDecision.Action.RUSH,
		"dest": dest})
	var cmp: Vector3 = (clamped["units"]["Mover"] as Dictionary)["positions"][0]
	assert_that(cmp).is_not_equal(dest)


## NML-1073 S1b: a charge that reaches BASE CONTACT resolves melee. Two 32 mm
## bases (radius 0.016 m, _unit_at's default) meet at a 1.26" CENTRE distance
## once S1's spacing exemption lets the mover in — past the OLD trigger's
## CONTACT_IN=1.0" centre-distance gate, so this is RED pre-fix (no melee
## ever fires here) and GREEN once the trigger measures the EDGE gap against
## the table's own contact epsilon, CHARGE_CONTACT_MARGIN_IN (0.25").
func test_a_charge_reaching_base_contact_resolves_melee() -> void:
	OS.set_environment("NML_SIM_SPACING", "1")
	_reset_spacing_cache()
	var mover := _armed_at(1, [Vector3.ZERO], "Mover")
	var blocker := _armed_at(2, [Vector3(6.0 * IN2M, 0, 0)], "Blocker")
	var state := _capture(mover, blocker)
	var next := BattleSim.resolve(state, {"unit": "Mover", "kind": AiDecision.Action.CHARGE,
		"dest": Vector3(6.0 * IN2M, 0, 0), "charge": "Blocker"})
	var b: Dictionary = next["units"]["Blocker"]
	assert_int(int(b["alive"])).is_equal(0)


## NML-1073 S1b guard: a charge whose 12" reach band runs out exactly 1" short
## of base contact (well past CHARGE_CONTACT_MARGIN_IN=0.25") never resolves
## melee. GREEN before and after this fix — the old centre-distance gate
## agreed here too (2.26" centre gap > CONTACT_IN=1.0").
func test_a_charge_short_of_contact_by_the_reach_band_applies_no_melee() -> void:
	OS.set_environment("NML_SIM_SPACING", "1")
	_reset_spacing_cache()
	var r_in := SeparationChecker.DEFAULT_BASE_RADIUS_M / IN2M
	var target_x_in := 12.0 + 1.0 + 2.0 * r_in   # 12" charge band leaves exactly a 1" edge gap
	var mover := _armed_at(1, [Vector3.ZERO], "Mover")
	var blocker := _armed_at(2, [Vector3(target_x_in * IN2M, 0, 0)], "Blocker")
	var state := _capture(mover, blocker)
	var next := BattleSim.resolve(state, {"unit": "Mover", "kind": AiDecision.Action.CHARGE,
		"dest": Vector3(target_x_in * IN2M, 0, 0), "charge": "Blocker"})
	var b: Dictionary = next["units"]["Blocker"]
	assert_int(int(b["alive"])).is_equal(1)
	assert_int(int(b["wounds"][0])).is_equal(1)


## NML-1073 S1 review (a): the charge VICTIM can itself be a joined hero
## (ai_planner._enemy_keys/._best_charge iterate every unit dict, heroes
## included) — its "attached_to" host must NOT ride along into the body-only
## exemption. Hero sits at (3,0), its Host 1.75" further out along Z; the
## mover charges the Hero. RED on HEAD: _unit_group(next, "Hero") pulled in
## "Host" too (bug), so Host went body-only and the mover ended only ~0.94"
## from Host's edge — under the 1" buffer. GREEN post-fix: Host keeps its
## full 1" buffer (the mover stops a little short of true Hero contact to
## respect it), while still landing well inside the Hero's own
## CHARGE_CONTACT_MARGIN_IN (0.25") — a real, checkable base contact.
func test_a_charge_at_a_joined_hero_still_buffers_the_hosts_own_body() -> void:
	OS.set_environment("NML_SIM_SPACING", "1")
	_reset_spacing_cache()
	var mover := _unit_at(1, [Vector3.ZERO], "Mover")
	var hero := _unit_at(2, [Vector3(3.0 * IN2M, 0, 0)], "Hero")
	var host := _unit_at(2, [Vector3(3.0 * IN2M, 0, 1.75 * IN2M)], "Host")
	hero.unit_properties["attached_to"] = host
	host.unit_properties["attached_heroes"] = [hero]
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Mover": mover, "Hero": hero, "Host": host}
	var state := BattleSim.capture(army)
	var next := BattleSim.resolve(state, {"unit": "Mover", "kind": AiDecision.Action.CHARGE,
		"dest": Vector3(3.0 * IN2M, 0, 0), "charge": "Hero"})
	var mp: Vector3 = (next["units"]["Mover"] as Dictionary)["positions"][0]
	var hp: Vector3 = (next["units"]["Hero"] as Dictionary)["positions"][0]
	var hop: Vector3 = (next["units"]["Host"] as Dictionary)["positions"][0]
	var r_in := SeparationChecker.DEFAULT_BASE_RADIUS_M / IN2M
	var gap_hero_in: float = (mp - hp).length() / IN2M - 2.0 * r_in
	var gap_host_in: float = (mp - hop).length() / IN2M - 2.0 * r_in
	assert_float(gap_hero_in).is_less(SoloController.CHARGE_CONTACT_MARGIN_IN)
	assert_float(gap_host_in).is_greater_equal(SoloController.UNIT_SPACING_IN - 0.02)
