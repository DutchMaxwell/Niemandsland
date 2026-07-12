extends GdUnitTestSuite
## Solo/AI M1: the walking-skeleton controller. Pure logic (nearest-target selection, table-edge move
## clamp) is unit-tested directly; a light integration proves an AI unit advances toward the nearest
## human unit by its Advance distance and is marked activated.


func test_nearest_index_picks_the_closest_table_plane() -> void:
	var from := Vector3.ZERO
	assert_int(SoloController.nearest_index(from, [Vector3(10, 0, 0), Vector3(1, 0, 0), Vector3(5, 0, 0)])).is_equal(1)
	assert_int(SoloController.nearest_index(from, [])).is_equal(-1)
	# Y is ignored (table plane): the x=0.5 point is nearer than the tall x=0,z=2 one.
	assert_int(SoloController.nearest_index(from, [Vector3(0, 100, 2), Vector3(0.5, 0, 0)])).is_equal(1)


func test_axis_scale_clamps_a_move_at_the_table_edge() -> void:
	assert_float(SoloController._axis_scale(0.0, 0.3, 0.6)).is_equal_approx(1.0, 0.001)   # within → full
	assert_float(SoloController._axis_scale(0.0, 1.0, 0.6)).is_equal_approx(0.6, 0.001)   # overshoot → onto edge
	assert_float(SoloController._axis_scale(0.5, 0.0, 0.6)).is_equal_approx(1.0, 0.001)   # no move → full
	assert_float(SoloController._axis_scale(0.0, -1.0, 0.6)).is_equal_approx(0.6, 0.001)  # negative dir


func _unit(pid: int, positions: Array) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "p%d_%d" % [pid, positions.size()]
	u.unit_properties = {"player_id": pid, "name": "U%d" % pid, "quality": 4, "defense": 4}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		var n := Node3D.new()
		add_child(n)
		n.global_position = p
		m.node = n
		u.models.append(m)
	return u


## Field-test finding 1: a Slow unit MUST get the reduced move band even when no MovementRangeController
## is injected (the old _act fell back to a hardcoded 6"/12" that dropped Slow). Slow = -2"/-4" (GF/AoF
## Advanced Rules v3.5.1 p.13), so a Slow unit's Advance band is 4" and Rush 8" — from the SAME band
## source the human's reach rings use.
func test_move_bands_for_unit_honours_slow_without_a_controller() -> void:
	var slow := _unit(2, [Vector3(0.2, 0, 0)])
	slow.unit_properties["special_rules"] = ["Slow", "Tough(3)"]
	var bands := SoloController.move_bands_for_unit(slow, null)   # no controller — must NOT hardcode 6"/12"
	assert_int(int(bands["advance"])).is_less_equal(4)
	assert_int(int(bands["advance"])).is_equal(4)
	assert_int(int(bands["rush"])).is_equal(8)
	# A plain unit (no move rule) still reads the OPR defaults, and Fast still adds +2"/+4".
	var plain := _unit(2, [Vector3(0.2, 0, 0)])
	assert_int(int(SoloController.move_bands_for_unit(plain, null)["advance"])).is_equal(6)
	var fast := _unit(2, [Vector3(0.2, 0, 0)])
	fast.unit_properties["special_rules"] = ["Fast"]
	assert_int(int(SoloController.move_bands_for_unit(fast, null)["advance"])).is_equal(8)


func test_ai_unit_advances_toward_nearest_human_and_activates() -> void:
	var human := _unit(1, [Vector3(0, 0, 0)])
	var ai := _unit(2, [Vector3(0.5, 0, 0)])   # 0.5 m east of the human, inside a 4 ft table
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {human.unit_id: human, ai.unit_id: ai}
	army.current_round = 1

	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)

	var moved := solo.activate_next_ai_unit()
	assert_object(moved).is_equal(ai)
	assert_bool(ai.is_activated).is_true()
	# A weaponless unit counts as MELEE; at 0.5 m (~19.7") the enemy is beyond charge range (12") — the
	# official v3.5.0 tree RUSHES 12" = 0.3048 m toward the human at x=0 → x drops from 0.5 to ~0.1952.
	assert_float(ai.models[0].node.global_position.x).is_equal_approx(0.1952, 0.004)
	assert_int(int(solo.last_report["action"])).is_equal(AiDecision.Action.RUSH)
	# A second call finds no more eligible AI units.
	assert_object(solo.activate_next_ai_unit()).is_null()


func test_targeting_prefers_a_not_yet_activated_human_over_a_nearer_activated_one() -> void:
	# OPR Solo v3.5.0: nearest valid enemy, but prefer not-yet-activated.
	var near_active := _unit(1, [Vector3(0.35, 0, 0)])   # closer, but already acted
	near_active.is_activated = true
	near_active.unit_id = "human_active"
	var far_fresh := _unit(1, [Vector3(0.1, 0, 0)])      # farther from the AI, not yet activated
	far_fresh.unit_id = "human_fresh"
	var ai := _unit(2, [Vector3(0.5, 0, 0)])
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {near_active.unit_id: near_active, far_fresh.unit_id: far_fresh, ai.unit_id: ai}
	army.current_round = 1
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	assert_object(solo.nearest_human_unit(ai)).is_equal(far_fresh)
	# If ALL humans are activated, fall back to the nearest.
	far_fresh.is_activated = true
	assert_object(solo.nearest_human_unit(ai)).is_equal(near_active)


func test_run_ai_turn_activates_every_eligible_ai_unit() -> void:
	var human := _unit(1, [Vector3(0, 0, 0)])
	var ai1 := _unit(2, [Vector3(0.4, 0, 0)])
	var ai2 := _unit(2, [Vector3(0, 0, 0.4)])
	ai2.unit_id = "ai2"
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {human.unit_id: human, ai1.unit_id: ai1, ai2.unit_id: ai2}
	army.current_round = 1

	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)

	assert_int(solo.run_ai_turn()).is_equal(2)
	assert_bool(ai1.is_activated).is_true()
	assert_bool(ai2.is_activated).is_true()


func test_ambush_reserve_arrives_round_two_and_empties() -> void:
	var enemy := _unit(1, [Vector3(0, 0, 0)])           # human unit at the table centre
	var ambusher := _unit(2, [Vector3(3, 0, 3)])        # held in reserve (staging position)
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {enemy.unit_id: enemy, ambusher.unit_id: ambusher}

	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	solo.ambush_reserve = [ambusher]
	solo._deploy_objectives = [Vector2(0.4, 0.4)]        # an objective attractor

	# 4ft table; the enemy sits at the origin — the ambusher must land MORE THAN 9" (0.2286 m) away.
	var zone := Rect2(Vector2(-0.61, -0.61), Vector2(1.22, 1.22))
	var res: Dictionary = solo.arrive_ambush_reserve(zone, [Vector2(0, 0)])

	assert_int(int(res["arrived"])).is_equal(1)
	assert_int(solo.ambush_reserve.size()).is_equal(0)   # reserve emptied
	var c := solo.unit_centre(ambusher)
	assert_float(Vector2(c.x, c.z).length()).is_greater(0.2286)   # >9" from the enemy


func test_ambush_arrival_is_noop_with_empty_reserve() -> void:
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(auto_free(OPRArmyManager.new()), null, null, 1, 2)
	var res: Dictionary = solo.arrive_ambush_reserve(Rect2(0, 0, 1, 1), [])
	assert_int(int(res["arrived"])).is_equal(0)


## Field-test finding 5: a reserve Ambush unit is NOT activatable while held, and arriving from Ambush does
## NOT consume its activation — it is eligible to act that same round (GF/AoF v3.5.1 p.13).
func test_ambush_reserve_unit_is_ineligible_until_it_arrives_then_can_act() -> void:
	var enemy := _unit(1, [Vector3(0.5, 0, 0.5)])
	var ambusher := _unit(2, [Vector3(3, 0, 3)])
	ambusher.unit_properties["ambush_reserve"] = true          # held off-table
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {enemy.unit_id: enemy, ambusher.unit_id: ambusher}
	army.current_round = 2
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	solo.ambush_reserve = [ambusher]
	solo._deploy_objectives = [Vector2(0.3, 0.3)]
	# Held in reserve → ineligible, and the AI has nothing to activate.
	assert_bool(solo.is_eligible(ambusher)).is_false()
	assert_array(solo.eligible_ai_units()).is_empty()
	# One paced arrival >9" from the enemy → flag cleared, activation NOT spent, eligible THIS round.
	var occupied: Array = []
	var arrived := solo.arrive_one_ambush_unit(Rect2(Vector2(-0.61, -0.61), Vector2(1.22, 1.22)), [Vector2(0.5, 0.5)], occupied, 2)
	assert_object(arrived).is_equal(ambusher)
	assert_bool(ambusher.is_activated).is_false()
	assert_bool(bool(ambusher.unit_properties.get("ambush_reserve", false))).is_false()
	assert_bool(solo.is_eligible(ambusher)).is_true()
	assert_int(int(ambusher.unit_properties["ambush_arrived_round"])).is_equal(2)


## Field-test finding 5 (seize rule): a unit that arrived from Ambush this round can neither seize nor
## contest an objective it stands on (GF/AoF v3.5.1 p.13) — but the same unit seizes normally otherwise.
func test_seize_objectives_skips_ambush_units_on_their_arrival_round() -> void:
	var obj: Array = [Vector3(0, 0, 0)]
	var locked: Array = [{"player": 2, "shaken": false, "ambush_locked": true, "positions": [Vector3(0, 0, 0)]}]
	assert_int(int((SoloController.seize_objectives(locked, obj, [0])["owners"] as Array)[0])).is_equal(0)
	var free: Array = [{"player": 2, "shaken": false, "ambush_locked": false, "positions": [Vector3(0, 0, 0)]}]
	assert_int(int((SoloController.seize_objectives(free, obj, [0])["owners"] as Array)[0])).is_equal(2)


## Field-test finding 6: cover feeds the EV from REAL terrain, not a constant. majority_in_cover reads the
## injected terrain callback and honours the strict-majority rule (GF/AoF v3.5.1 p.11).
func test_majority_in_cover_reads_real_terrain() -> void:
	var unit := _unit(1, [Vector3(0, 0, 0), Vector3(0.1, 0, 0), Vector3(5, 0, 5)])
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {unit.unit_id: unit}
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	assert_bool(solo.majority_in_cover(unit)).is_false()   # no terrain wired → honest false
	# A forest patch around the origin covers 2 of the 3 models → strict majority → in cover.
	solo.terrain_type_at = func(p: Vector3) -> int:
		return TerrainRules.TerrainType.FOREST if Vector2(p.x, p.z).length() < 1.0 else TerrainRules.TerrainType.NONE
	assert_bool(solo.majority_in_cover(unit)).is_true()
	unit.models[1].node.global_position = Vector3(5, 0, 5)   # only 1/3 left in the woods
	assert_bool(solo.majority_in_cover(unit)).is_false()


## Wave-4 Royal Legion (Mummified Undead army-book rule): +4" shooting range. The +2" Charge is verified
## via move_bands_for_props in the movement-range suite.
func test_royal_legion_shooting_range_bonus() -> void:
	var u := _unit(2, [Vector3(0, 0, 0)])
	assert_int(SoloController.shooting_range_bonus(u)).is_equal(0)   # plain unit
	u.unit_properties["special_rules"] = ["Royal Legion", "Tough(3)"]
	assert_int(SoloController.shooting_range_bonus(u)).is_equal(4)
	assert_int(SoloController.shooting_range_bonus(null)).is_equal(0)


func test_effective_attacks_scales_by_the_surviving_fraction() -> void:
	# OPR "Determine Attacks": only living models' weapons count → attacks × alive / max (rounded). This is
	# the real-game mirror of the sim's dead-models fix (goal 003 P3).
	assert_int(SoloController.effective_attacks(10, 10, 10)).is_equal(10)   # full strength
	assert_int(SoloController.effective_attacks(10, 4, 10)).is_equal(4)     # 4 of 10 alive
	assert_int(SoloController.effective_attacks(4, 1, 4)).is_equal(1)       # last model
	assert_int(SoloController.effective_attacks(4, 0, 4)).is_equal(0)       # wiped → no attacks
	assert_int(SoloController.effective_attacks(3, 5, 0)).is_equal(3)       # no max known → unchanged


func test_striking_models_counts_only_models_within_2in_reach() -> void:
	# OPR "Who Can Strike": a striker model contributes only if within 2" (+ base contact) of an enemy model.
	var enemy := [Vector3(0, 0, 0)]
	var striker := [Vector3(0.05, 0, 0), Vector3(0.2, 0, 0)]   # ~2" vs ~7.9" from the enemy (metres)
	assert_int(SoloController.striking_models(striker, enemy)).is_equal(1)
	# Fallbacks: no enemy positions → the whole living set strikes; no striker → none.
	assert_int(SoloController.striking_models([Vector3(0, 0, 0), Vector3(1, 0, 0)], [])).is_equal(2)
	assert_int(SoloController.striking_models([], [Vector3(0, 0, 0)])).is_equal(0)


func test_ai_rushes_toward_an_uncontrolled_objective_over_the_enemy() -> void:
	# The FULL Solo & Co-Op tree (decide_solo) is objective-first: a MELEE unit with an uncontrolled objective
	# and no enemy in the way RUSHES the objective (not the enemy). Wires objectives via the injected providers.
	var human := _unit(1, [Vector3(0.5, 0, -0.5)])         # ~19.7" south of the AI (beyond charge)
	var ai := _unit(2, [Vector3(0.5, 0, 0)])               # weaponless → MELEE
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {human.unit_id: human, ai.unit_id: ai}
	army.current_round = 1
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	var objective := Vector3(0.5, 0, 0.3)                  # ~11.8" NORTH — the opposite way from the enemy
	solo.objectives_provider = func() -> Array: return [objective]
	solo.objective_owner_of = func(_i: int) -> int: return 0   # neutral → uncontrolled by the AI

	var moved := solo.activate_next_ai_unit()
	assert_object(moved).is_equal(ai)
	assert_int(int(solo.last_report["action"])).is_equal(AiDecision.Action.RUSH)
	assert_int(int(solo.last_report["toward"])).is_equal(AiDecision.Toward.OBJECTIVE)
	# It rushes north onto the objective (clamped at the marker), NOT south toward the enemy.
	assert_float(ai.models[0].node.global_position.z).is_equal_approx(0.3, 0.01)
	assert_float(ai.models[0].node.global_position.x).is_equal_approx(0.5, 0.01)


func test_shaken_ai_unit_idles_recovers_and_moves_nothing() -> void:
	# OPR p.10 (goal 003 P2): a Shaken unit spends its activation idle. The controller reports idle_shaken
	# (main clears the state via the radial seam), the unit does not move, and it counts as activated.
	var human := _unit(1, [Vector3(0, 0, 0)])
	var ai := _unit(2, [Vector3(0.5, 0, 0)])
	ai.is_shaken = true
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {human.unit_id: human, ai.unit_id: ai}
	army.current_round = 1
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)

	var moved := solo.activate_next_ai_unit()
	assert_object(moved).is_equal(ai)
	assert_bool(bool(solo.last_report.get("idle_shaken", false))).is_true()
	assert_bool(ai.is_activated).is_true()
	assert_float(ai.models[0].node.global_position.x).is_equal_approx(0.5, 0.0001)   # did not move


func test_non_shaken_units_activate_before_shaken_ones() -> void:
	# OPR Solo p.2: Shaken units activate LAST. With one fresh and one Shaken AI unit, the fresh one goes first.
	var human := _unit(1, [Vector3(0, 0, 0)])
	var fresh := _unit(2, [Vector3(0.4, 0, 0)])
	fresh.unit_id = "ai_fresh"
	var shaken := _unit(2, [Vector3(0.3, 0, 0)])
	shaken.unit_id = "ai_shaken"
	shaken.is_shaken = true
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {human.unit_id: human, fresh.unit_id: fresh, shaken.unit_id: shaken}
	army.current_round = 1
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	assert_object(solo.activate_next_ai_unit()).is_equal(fresh)
	assert_object(solo.activate_next_ai_unit()).is_equal(shaken)


# === Objective auto-seize (goal 003 P2 — pure SoloController.seize_objectives) ===

const IN3 := 3.0 * 0.0254   # the 3" control radius in metres


func _info(player: int, positions: Array, shaken: bool = false) -> Dictionary:
	return {"player": player, "shaken": shaken, "positions": positions}


func test_seize_single_side_takes_the_marker() -> void:
	var res := SoloController.seize_objectives(
		[_info(1, [Vector3(0.02, 0, 0)])], [Vector3(0, 0, 0)], [0])
	assert_array(res["owners"]).is_equal([1])
	assert_int((res["changes"] as Array).size()).is_equal(1)


func test_seize_respects_the_3in_boundary() -> void:
	# Exactly 3" counts; just beyond does not (owner persists at neutral, no change entry).
	var on_edge := SoloController.seize_objectives(
		[_info(2, [Vector3(IN3, 0, 0)])], [Vector3(0, 0, 0)], [0])
	assert_array(on_edge["owners"]).is_equal([2])
	var beyond := SoloController.seize_objectives(
		[_info(2, [Vector3(IN3 + 0.003, 0, 0)])], [Vector3(0, 0, 0)], [0])
	assert_array(beyond["owners"]).is_equal([0])
	assert_int((beyond["changes"] as Array).size()).is_equal(0)


func test_seize_both_sides_near_contests_to_neutral() -> void:
	var res := SoloController.seize_objectives(
		[_info(1, [Vector3(0.02, 0, 0)]), _info(2, [Vector3(-0.02, 0, 0)])],
		[Vector3(0, 0, 0)], [1])
	assert_array(res["owners"]).is_equal([0])
	assert_int((res["changes"] as Array).size()).is_equal(1)


func test_seize_owner_persists_when_nobody_is_near() -> void:
	var res := SoloController.seize_objectives(
		[_info(1, [Vector3(1.0, 0, 0)])], [Vector3(0, 0, 0)], [2])
	assert_array(res["owners"]).is_equal([2])
	assert_int((res["changes"] as Array).size()).is_equal(0)


func test_seize_shaken_units_neither_seize_nor_contest() -> void:
	# A Shaken unit alone cannot seize; and it cannot contest the other side's seize either.
	var alone := SoloController.seize_objectives(
		[_info(1, [Vector3(0.02, 0, 0)], true)], [Vector3(0, 0, 0)], [0])
	assert_array(alone["owners"]).is_equal([0])
	var vs := SoloController.seize_objectives(
		[_info(1, [Vector3(0.02, 0, 0)], true), _info(2, [Vector3(-0.02, 0, 0)])],
		[Vector3(0, 0, 0)], [0])
	assert_array(vs["owners"]).is_equal([2])


# === P8 targeting-input routing (pure SoloController.targeting_route) ===
# REGRESSION (maintainer field-test): the enemy click in Shoot/Fight targeting did nothing — the handler
# was fed only from _unhandled_key_input, which never receives mouse events in Godot 4. These tests pin
# the contract that MOUSE events are first-class targeting input: LMB picks, RMB cancels, motion tracks.

func _lmb(pressed: bool = true) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	return e


func test_targeting_route_left_click_picks_the_target() -> void:
	assert_int(SoloController.targeting_route(_lmb(), false)).is_equal(SoloController.TargetingRoute.PICK)
	# Release is not a pick (only the press resolves the target).
	assert_int(SoloController.targeting_route(_lmb(false), false)).is_equal(SoloController.TargetingRoute.IGNORE)


func test_targeting_route_click_over_hud_control_is_ignored() -> void:
	# A click on an interactive HUD widget (dock, dice tray) keeps working during targeting.
	assert_int(SoloController.targeting_route(_lmb(), true)).is_equal(SoloController.TargetingRoute.IGNORE)


func test_targeting_route_right_click_and_escape_cancel() -> void:
	var rmb := InputEventMouseButton.new()
	rmb.button_index = MOUSE_BUTTON_RIGHT
	rmb.pressed = true
	assert_int(SoloController.targeting_route(rmb, false)).is_equal(SoloController.TargetingRoute.CANCEL)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	assert_int(SoloController.targeting_route(esc, false)).is_equal(SoloController.TargetingRoute.CANCEL)
	# Any other key passes through untouched.
	var other := InputEventKey.new()
	other.keycode = KEY_A
	other.pressed = true
	assert_int(SoloController.targeting_route(other, false)).is_equal(SoloController.TargetingRoute.IGNORE)


func test_targeting_route_mouse_motion_tracks_the_los_line() -> void:
	assert_int(SoloController.targeting_route(InputEventMouseMotion.new(), false)).is_equal(SoloController.TargetingRoute.TRACK)


# === Attached-hero unity (GF v3.5.1 "Hero": a joined hero deploys/activates/moves WITH its host) ===

func test_attached_hero_is_never_its_own_activation() -> void:
	# The AI's D6 pick moved a joined hero SOLO out of his unit (maintainer field test) — an attached
	# hero must not be eligible on its own; activating the HOST covers both (GameUnit.activate cascades).
	var human := _unit(1, [Vector3(0, 0, 0)])
	var host := _unit(2, [Vector3(0.5, 0, 0), Vector3(0.53, 0, 0)])
	host.unit_id = "host"
	var hero := _unit(2, [Vector3(0.56, 0, 0)])
	hero.unit_id = "hero"
	EquipmentDistributor.attach_hero_to_unit(hero, host)
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {human.unit_id: human, host.unit_id: host, hero.unit_id: hero}
	army.current_round = 1
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	var eligible := solo.eligible_ai_units()
	assert_int(eligible.size()).is_equal(1)          # the host only — the hero is not a separate activation
	assert_object(eligible[0]).is_equal(host)
	assert_object(solo.activate_next_ai_unit()).is_equal(host)
	assert_bool(hero.is_activated).is_true()          # activated WITH the host (cascade)
	assert_object(solo.activate_next_ai_unit()).is_null()   # round over — no phantom hero activation


func test_host_move_carries_the_attached_hero() -> void:
	# One unit, one move: the hero's model must shift with the host's models (movement cohesion).
	var human := _unit(1, [Vector3(0, 0, 0)])
	var host := _unit(2, [Vector3(0.5, 0, 0)])
	host.unit_id = "host"
	var hero := _unit(2, [Vector3(0.53, 0, 0)])
	hero.unit_id = "hero"
	EquipmentDistributor.attach_hero_to_unit(hero, host)
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {human.unit_id: human, host.unit_id: host, hero.unit_id: hero}
	army.current_round = 1
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	var hero_before: Vector3 = hero.models[0].node.global_position
	assert_object(solo.activate_next_ai_unit()).is_equal(host)   # weaponless MELEE → rushes the enemy
	var hero_delta: float = hero.models[0].node.global_position.distance_to(hero_before)
	assert_float(hero_delta).is_greater(0.1)                     # the hero moved with the block (~12" rush)
	# The hero stays in formation next to the host (rigid slide preserves the offset).
	assert_float(hero.models[0].node.global_position.distance_to(host.models[0].node.global_position)) \
		.is_equal_approx(0.03, 0.005)


# === Per-model line of sight (GF v3.5.1 p.8 "Who Can Shoot") ===

func test_sighted_models_gates_per_model_behind_a_blocker() -> void:
	# A CONTAINER strip blocks the southern half of the shooting line: only the 2 clear models fire.
	var grid := {}
	for x in range(0, 8):
		grid[Vector2i(x, 1)] = TerrainRules.TerrainType.CONTAINER   # wall row at y in [3,6)"
	# Blocker only spans x in [0,24)": shooters at x=26,29 see PAST its end, x=2,5 are blocked.
	for x in range(8, 16):
		grid.erase(Vector2i(x, 1))
	var los := func(a: Vector3, b: Vector3) -> bool:
		return TerrainRules.has_line_of_sight(grid,
			Vector2(a.x, a.z) / 0.0254, Vector2(b.x, b.z) / 0.0254, 1, 1)
	var m := 0.0254
	var shooters := [Vector3(2 * m, 0, 0), Vector3(5 * m, 0, 0), Vector3(26 * m, 0, 0), Vector3(29 * m, 0, 0)]
	var targets := [Vector3(2 * m, 0, 12 * m), Vector3(26 * m, 0, 12 * m)]
	assert_int(SoloController.sighted_models(shooters, targets, 24.0 * m, los)).is_equal(2)
	# Range gates too: at 6" nothing reaches the 12"-away targets even with clear LOS.
	assert_int(SoloController.sighted_models(shooters, targets, 6.0 * m, los)).is_equal(0)
	# Open field: everyone in range fires.
	assert_int(SoloController.sighted_models(shooters, targets, 24.0 * m,
		func(_a: Vector3, _b: Vector3) -> bool: return true)).is_equal(4)


# === Auto-tail alternation state machine (goal 003 P2 — the maintainer's "how do I proceed?" gap) ===

func test_alternation_next_replies_then_tails_then_ends() -> void:
	var S := SoloController
	assert_int(S.alternation_next(1, 3, 3)).is_equal(S.AltStep.REPLY)      # human just activated → one answer
	assert_int(S.alternation_next(0, 3, 3)).is_equal(S.AltStep.WAIT)       # balanced → wait for the human
	assert_int(S.alternation_next(0, 0, 3)).is_equal(S.AltStep.TAIL)       # human exhausted → AI plays on
	assert_int(S.alternation_next(1, 0, 3)).is_equal(S.AltStep.REPLY)      # owed reply resolves before the tail
	assert_int(S.alternation_next(0, 2, 0)).is_equal(S.AltStep.WAIT)       # AI exhausted → human finishes alone
	assert_int(S.alternation_next(0, 0, 0)).is_equal(S.AltStep.END_ROUND)  # both done → round over
	assert_int(S.alternation_next(3, 0, 0)).is_equal(S.AltStep.END_ROUND)  # stale replies never outlive the AI side


# === Wound application core (maintainer field test: Tough hero soaked wounds with no visible tick) ===

func test_apply_wounds_decrements_tough_and_reports_seams() -> void:
	var unit := _unit(2, [Vector3.ZERO])
	unit.models[0].wounds_max = 3
	unit.models[0].wounds_current = 3   # a Tough(3) hero
	var changed: Array = []
	var died: Array = []
	var on_changed := func(m: ModelInstance) -> void: changed.append(m)
	var on_died := func(m: ModelInstance) -> void: died.append(m)
	# 2 wounds: the hero soaks them, stays alive, and the CHANGED seam fires (wound token + broadcast).
	assert_int(SoloController.apply_wounds_to_models(unit, 2, on_changed, on_died)).is_equal(0)
	assert_int(unit.models[0].wounds_current).is_equal(1)
	assert_bool(unit.models[0].is_alive).is_true()
	assert_int(changed.size()).is_equal(1)
	assert_int(died.size()).is_equal(0)
	# 1 more wound kills him: the DIED seam fires instead.
	assert_int(SoloController.apply_wounds_to_models(unit, 1, on_changed, on_died)).is_equal(0)
	assert_bool(unit.models[0].is_alive).is_false()
	assert_int(died.size()).is_equal(1)
	assert_int(changed.size()).is_equal(1)


func test_apply_wounds_spills_back_rank_first_and_returns_leftover() -> void:
	var unit := _unit(2, [Vector3.ZERO, Vector3(0.03, 0, 0), Vector3(0.06, 0, 0)])   # 3 one-wound models
	var dead: Array = []
	var on_died := func(m: ModelInstance) -> void: dead.append(m)
	# 5 wounds into 3 models: all die back-rank-first (index 2 → 0) and 2 wounds spill to the caller
	# (attached-hero spill — GF v3.5.1 p.9 casualty removal is the defender's order choice).
	assert_int(SoloController.apply_wounds_to_models(unit, 5, Callable(), on_died)).is_equal(2)
	assert_int(unit.get_alive_count()).is_equal(0)
	assert_int(dead.size()).is_equal(3)
	assert_object(dead[0]).is_equal(unit.models[2])   # back rank removed first


# === AI-action pacing machine (goal 003 game-feel — pure) ===

func test_pace_phases_run_in_order_and_end() -> void:
	var S := SoloController
	assert_int(S.pace_next(S.Pace.ANNOUNCE)).is_equal(S.Pace.EXECUTE)
	assert_int(S.pace_next(S.Pace.EXECUTE)).is_equal(S.Pace.RESOLVE)
	assert_int(S.pace_next(S.Pace.RESOLVE)).is_equal(S.Pace.OUTCOME)
	assert_int(S.pace_next(S.Pace.OUTCOME)).is_equal(S.Pace.DONE)
	assert_int(S.pace_next(S.Pace.DONE)).is_equal(S.Pace.DONE)


func test_pace_holds_are_readable_and_fast_forward_shrinks_them() -> void:
	var S := SoloController
	# ANNOUNCE and OUTCOME are fixed readable holds; EXECUTE is event-gated (animation/dice) → no hold;
	# RESOLVE is the post-settle buffer on top of the tray's own physical-rest gate.
	assert_float(S.pace_seconds(S.Pace.ANNOUNCE, false)).is_equal(S.PACE_ANNOUNCE_S)
	assert_float(S.pace_seconds(S.Pace.OUTCOME, false)).is_equal(S.PACE_OUTCOME_S)
	assert_float(S.pace_seconds(S.Pace.RESOLVE, false)).is_equal(S.PACE_DICE_SETTLE_BUFFER_S)
	assert_float(S.pace_seconds(S.Pace.EXECUTE, false)).is_equal(0.0)
	assert_float(S.pace_seconds(S.Pace.ANNOUNCE, true)).is_equal_approx(S.PACE_ANNOUNCE_S * S.PACE_FAST_SCALE, 0.0001)
	assert_float(S.pace_seconds(S.Pace.OUTCOME, true)).is_less(S.pace_seconds(S.Pace.OUTCOME, false))


## Finding 7: the activation-choreography attention beat is the named PACE_ATTENTION_S (~2s), and Fast-AI
## compresses it by PACE_FAST_SCALE exactly like every other fixed hold — so focus → corridors → glide →
## attacks all shrink proportionally under Fast AI.
func test_attention_beat_is_named_and_fast_ai_compresses_it() -> void:
	var S := SoloController
	assert_float(S.pace_attention_seconds(false)).is_equal(S.PACE_ATTENTION_S)
	assert_float(S.pace_attention_seconds(true)).is_equal_approx(S.PACE_ATTENTION_S * S.PACE_FAST_SCALE, 0.0001)
	assert_float(S.pace_attention_seconds(true)).is_less(S.pace_attention_seconds(false))


# === Blast(X) + Reliable (GF v3.5.1) ===

func test_blast_hits_match_the_rulebook_example() -> void:
	# "2 Attacks and Blast(3) scores two hits against a unit with 2 models. Each hit is multiplied by 2,
	# so the target takes a total of 4 hits."
	assert_int(AiCombatMath.blast_hits(2, 3, 2)).is_equal(4)
	assert_int(AiCombatMath.blast_hits(2, 3, 10)).is_equal(6)   # full ×3 against a big unit
	assert_int(AiCombatMath.blast_hits(2, 3, 1)).is_equal(2)    # capped at 1 model → ×1
	assert_int(AiCombatMath.blast_hits(0, 3, 5)).is_equal(0)
	assert_int(AiCombatMath.blast_hits(4, 0, 5)).is_equal(4)    # no Blast → unchanged


func test_reliable_shoots_at_quality_2() -> void:
	assert_int(AiCombatMath.reliable_quality(4, true)).is_equal(2)
	assert_int(AiCombatMath.reliable_quality(4, false)).is_equal(4)
	assert_int(AiCombatMath.reliable_quality(2, true)).is_equal(2)


func test_shooting_profile_threads_blast_reliable_and_deadly() -> void:
	# The real-game adapter reads these keys off the AiShooting profile — pin them at the source.
	var w := {"name": "Heavy Flamer", "range_value": 12, "attacks": 1, "count": 1,
		"special_rules": ["AP(1)", "Blast(3)", "Reliable", "Deadly(3)"]}
	var prof := AiShooting.profiles_in_range([w], 12.0)[0] as Dictionary
	assert_int(int(prof["blast"])).is_equal(3)
	assert_bool(bool(prof["reliable"])).is_true()
	assert_int(int(prof["deadly"])).is_equal(3)
	assert_int(int(prof["ap"])).is_equal(1)


func test_forces_hold_for_immobile_and_artillery() -> void:
	# GF/AoF v3.5.1 p.13: Immobile / Artillery "may only use Hold actions".
	assert_bool(SoloController.forces_hold(["Immobile"])).is_true()
	assert_bool(SoloController.forces_hold(["Artillery"])).is_true()
	assert_bool(SoloController.forces_hold(["Fearless", "Tough(3)"])).is_false()
	assert_bool(SoloController.forces_hold([])).is_false()


func test_has_counter_from_weapon_or_unit_rule() -> void:
	# Counter as a melee-weapon rule (the usual shape) or granted unit-wide; ranged Counter never counts
	# (melee_profiles drops ranged weapons).
	var counter_melee := AiShooting.melee_profiles([{"name": "Spear", "range_value": 0, "attacks": 1, "count": 5, "special_rules": ["Counter"]}])
	var plain_melee := AiShooting.melee_profiles([{"name": "Fists", "range_value": 0, "attacks": 1, "count": 5, "special_rules": []}])
	assert_bool(SoloController.has_counter(counter_melee, [])).is_true()
	assert_bool(SoloController.has_counter(plain_melee, [])).is_false()
	assert_bool(SoloController.has_counter(plain_melee, ["Counter"])).is_true()
	assert_bool(SoloController.has_counter([], [])).is_false()


func test_model_base_radius_falls_back_without_a_shape() -> void:
	# A model with no live node yields no SeparationChecker shape → the module's shared 32 mm fallback
	# (one radius truth between the proximity hint and the AI planner).
	var m := ModelInstance.new()
	assert_float(SoloController.model_base_radius_m(m)).is_equal_approx(SeparationChecker.DEFAULT_BASE_RADIUS_M, 0.0001)


func test_classify_rule_inventory_three_classes_with_counts() -> void:
	# RESOLVED (modeled), of which the decision-relevant subset is ALSO marked, and UNKNOWN — prefix
	# matched ("AP(1)" → "AP"); occurrence counting per bearing entry.
	var inv := SoloController.classify_rule_inventory(
		["AP(1)", "AP(2)", "Fearless", "Battleborn", "Deadly(3)", "Weird Aura"],
		["AP", "Fearless", "Deadly"], ["AP", "Deadly"])
	assert_int(int((inv["resolved"] as Dictionary).get("AP", 0))).is_equal(2)
	assert_int(int((inv["resolved"] as Dictionary).get("Fearless", 0))).is_equal(1)
	assert_int(int((inv["decision"] as Dictionary).get("AP", 0))).is_equal(2)
	assert_bool((inv["decision"] as Dictionary).has("Fearless")).is_false()
	assert_int(int((inv["unknown"] as Dictionary).get("Battleborn", 0))).is_equal(1)
	assert_int(int((inv["unknown"] as Dictionary).get("Weird Aura", 0))).is_equal(1)
	assert_bool((inv["resolved"] as Dictionary).has("Battleborn")).is_false()


func test_decision_log_records_cap_and_drain() -> void:
	var sc: SoloController = auto_free(SoloController.new())
	for i in range(SoloController.DECISION_LOG_CAP + 25):
		sc.record_decision({"kind": "action", "unit": "U%d" % i, "rule": "", "candidates": [],
			"chosen": "", "why": "", "data": {}})
	# Ring: bounded at the cap, oldest dropped.
	assert_int(sc.decision_log.size()).is_equal(SoloController.DECISION_LOG_CAP)
	assert_str(str((sc.decision_log[0] as Dictionary)["unit"])).is_equal("U25")
	# Drain empties the buffer and returns everything pending.
	var drained := sc.drain_decisions()
	assert_int(drained.size()).is_equal(SoloController.DECISION_LOG_CAP)
	assert_int(sc.decision_log.size()).is_equal(0)


func test_render_decision_formats_candidates_and_reason() -> void:
	# Rendering is the ONLY formatting step (dev-off = records stay raw dictionaries).
	var line := SoloController.render_decision({"kind": "target", "unit": "Squad A",
		"rule": "Solo v3.5.0 p.2", "candidates": [{"name": "B", "ev": 2.4}, {"name": "C", "ev": 1.1}],
		"chosen": "B", "why": "ev tie-break", "data": {"dist_in": 9.4}})
	assert_bool(line.contains("Squad A")).is_true()
	assert_bool(line.contains("B EV 2.40")).is_true()
	assert_bool(line.contains("chose B")).is_true()
	assert_bool(line.contains("ev tie-break")).is_true()
	# A minimal record renders without optional sections.
	assert_bool(SoloController.render_decision({"kind": "move", "unit": "X"}).contains("X")).is_true()


func test_target_key_compare_official_order() -> void:
	# Not-yet-activated beats activated regardless of band; then the nearer band; equal = genuine tie.
	var fresh_far := {"activated": false, "band": 20}
	var done_near := {"activated": true, "band": 2}
	var fresh_near := {"activated": false, "band": 2}
	assert_bool(SoloController._target_key_compare(fresh_far, done_near) < 0).is_true()
	assert_bool(SoloController._target_key_compare(fresh_near, fresh_far) < 0).is_true()
	assert_int(SoloController._target_key_compare(fresh_near, {"activated": false, "band": 2})).is_equal(0)


## Field-test finding 3: a unit HELD in Ambush reserve is off-table — never eligible, never activated (even
## when it is the only "unit" on its side), and skipped as a valid target. `unit_in_reserve` is the single
## truth the game reads everywhere.
func test_reserve_units_never_eligible_activate_or_target() -> void:
	var enemy := _unit(1, [Vector3(0, 0, 0)])
	enemy.unit_id = "enemy"
	var human_reserve := _unit(1, [Vector3(0.15, 0, 0)])   # nearer to the AI, but off-table in reserve
	human_reserve.unit_id = "human_reserve"
	human_reserve.unit_properties["ambush_reserve"] = true
	var reserved := _unit(2, [Vector3(3, 0, 3)])
	reserved.unit_id = "ai_reserve"
	reserved.unit_properties["ambush_reserve"] = true
	var fielded := _unit(2, [Vector3(0.4, 0, 0)])
	fielded.unit_id = "ai_fielded"
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {enemy.unit_id: enemy, human_reserve.unit_id: human_reserve,
		reserved.unit_id: reserved, fielded.unit_id: fielded}
	army.current_round = 1
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	assert_bool(SoloController.unit_in_reserve(reserved)).is_true()
	assert_bool(SoloController.unit_in_reserve(fielded)).is_false()
	assert_bool(solo.is_eligible(reserved)).is_false()
	# Only the fielded unit is eligible; activation never picks the reserve, and the second call is empty.
	assert_array(solo.eligible_ai_units()).contains_exactly([fielded])
	assert_object(solo.activate_next_ai_unit()).is_equal(fielded)
	assert_object(solo.activate_next_ai_unit()).is_null()
	# A reserved HUMAN unit is not a valid AI target even though it is nearer — nearest_human_unit skips it.
	assert_object(solo.nearest_human_unit(fielded)).is_equal(enemy)


## Field-test finding 4: DANGEROUS cells enter the planner's avoid set only when asked (route AROUND them
## when a clear path exists); Impassable is always avoided, plain ground never.
func test_terrain_grid_marks_dangerous_avoid_only_when_requested() -> void:
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(auto_free(OPRArmyManager.new()), null, null, 1, 2)
	# Cell (0,0)'s centre (~0.038 m) is Dangerous; everything else is open ground.
	solo.terrain_type_at = func(p: Vector3) -> int:
		return TerrainRules.TerrainType.DANGEROUS if (p.x < 0.05 and p.z < 0.05) else TerrainRules.TerrainType.NONE
	var with_avoid: Dictionary = solo._terrain_grid_in(6.0, Vector2.ZERO, false, true)
	assert_bool((with_avoid["avoid"] as Dictionary).has(Vector2i(0, 0))).is_true()
	var without: Dictionary = solo._terrain_grid_in(6.0, Vector2.ZERO, false, false)
	assert_bool((without["avoid"] as Dictionary).has(Vector2i(0, 0))).is_false()
	# The grid still records the cell's type regardless (so the dangerous TEST still fires when crossed).
	assert_int(int((without["grid"] as Dictionary).get(Vector2i(0, 0), 0))).is_equal(TerrainRules.TerrainType.DANGEROUS)


## Field-test finding 10: Difficult and Dangerous are detected INDEPENDENTLY along a route — a path that
## crosses a difficult cell AND a dangerous cell reports BOTH, so the dangerous test still happens even when
## the difficult-terrain (6" cap) handling applies.
func test_route_reports_difficult_and_dangerous_independently() -> void:
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(auto_free(OPRArmyManager.new()), null, null, 1, 2)
	# West half (x<0) is Forest (Difficult); east half (x>0.2) is Dangerous; a W→E path crosses both.
	solo.terrain_type_at = func(p: Vector3) -> int:
		if p.x < 0.0:
			return TerrainRules.TerrainType.FOREST
		if p.x > 0.2:
			return TerrainRules.TerrainType.DANGEROUS
		return TerrainRules.TerrainType.NONE
	var a := Vector3(-0.1, 0, 0)
	var b := Vector3(0.3, 0, 0)
	assert_bool(solo._path_crosses_terrain(a, b, TerrainRules.PathCheck.DIFFICULT)).is_true()
	assert_bool(solo._path_crosses_terrain(a, b, TerrainRules.PathCheck.DANGEROUS)).is_true()


## Field-test finding 5: melee contact is measured base-to-base (not unit centre), and the charge snap pulls
## the whole unit into clean base contact preserving formation (coherency).
func test_nearest_melee_gap_and_charge_snap() -> void:
	var att := _unit(2, [Vector3(0, 0, 0), Vector3(-0.05, 0, 0)])   # two round bases (r≈0.016 m)
	var foe := _unit(1, [Vector3(0.05, 0, 0)])                       # ~0.018 m edge gap (~0.7") from the front model
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {att.unit_id: att, foe.unit_id: foe}
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	var gap := solo.nearest_melee_gap_in(att, foe)
	assert_float(gap).is_between(0.5, 1.0)                           # within melee-engage tolerance, not touching
	var back_before := att.models[1].node.global_position.x         # the rear model, for the coherency check
	var snapped := solo.snap_charge(att, foe)
	assert_float(snapped).is_greater(0.0)
	# After the snap the nearest models are in clean contact (~0 gap) and the enemy did not move.
	assert_float(solo.nearest_melee_gap_in(att, foe)).is_less(0.06)
	assert_float(foe.models[0].node.global_position.x).is_equal_approx(0.05, 0.0001)
	# The rear model translated by the SAME delta (rigid = coherency preserved).
	var delta := att.models[0].node.global_position.x - 0.0
	assert_float(att.models[1].node.global_position.x).is_equal_approx(back_before + delta, 0.0005)


# === Round opener: the side that finished FIRST opens the next round (finding 7) ===

func test_ai_opens_next_round_never_back_to_back() -> void:
	# GF/AoF v3.5.1: "the player that finished activating first on the last round gets to activate first" —
	# i.e. the side that did NOT take the last activation opens next. So no side takes a round's last
	# activation AND the next round's first (field-test finding 7).
	assert_bool(SoloController.ai_opens_next_round(true, true, true)).is_false()    # AI went last → human opens
	assert_bool(SoloController.ai_opens_next_round(false, true, true)).is_true()    # human went last → AI opens


func test_ai_opens_next_round_falls_through_when_opener_is_wiped() -> void:
	# The designated opener has no units → the other side opens instead.
	assert_bool(SoloController.ai_opens_next_round(true, false, true)).is_true()    # human wiped → AI opens
	assert_bool(SoloController.ai_opens_next_round(false, true, false)).is_false()  # AI wiped → human opens
