extends GdUnitTestSuite
## E2E — NML-967: the player clicks "Spot" on the radial wheel and NOTHING can be picked
## afterwards. The whole dispatch chain is wired (radial_menu.gd's "solo_spot" entry ->
## radial_menu_controller._on_action_selected -> _solo_begin_spot -> main.solo_begin_spot),
## and main._solo_targeting_input only takes the mouse while solo_owns_mouse() is true —
## which is true exactly while _solo_target_mode is non-empty. So a Spot that never ARMS
## _solo_target_mode is indistinguishable, from the table, from a dead menu entry.
##
## WHY THE EXISTING SUITE MISSES IT. test/e2e/e2e_spotter_ux_test.gd calls solo_begin_spot()
## and _solo_spot_click() directly on a fixture where the candidate predicate is trivially
## true (open table, no terrain), so it can only ever prove the happy path. This suite drives
## the REAL wheel id through radial_menu_controller._on_action_selected("solo_spot", ctx) —
## the same call e2e_embark_activation_test.gd uses for "unload_cargo_0"/"embark_1" — and puts
## a solid piece on the table, which is what a real battlefield has.
##
## THE DEFECT (main.gd:9185). The candidate scan gates on
##     solo_controller.nearest_melee_gap_in(unit, eu) <= 36.0 and _solo_has_los(unit, eu)
## and _solo_has_los (main.gd:8778-8785) is a UNIT-CENTRE, terrain-only, radius-less test:
## one line from the mean of the spotter's model positions to the mean of the target's. The
## shooting truth for the very same book wording ("in line of sight of this model") is
## PER MODEL — _solo_sighted_count -> _solo_true_los_callable (main.gd:3920/3957), which is
## what _solo_validate_target uses. The two disagree the moment a unit is wide enough for its
## notional centre to sit behind cover its models are not behind: every model sees the enemy,
## the centre point does not, and the scan produces an EMPTY candidate list. solo_begin_spot
## then logs one line and returns BEFORE arming _solo_target_mode — no rings, no pick, no
## mouse. Exactly the reported symptom.
##
## test_spot_dispatch_arms_and_picks_in_reach is the CONTROL (green at HEAD): identical
## fixture minus the piece, driven through the same wheel id — it proves the dispatch route
## itself is sound, so the RED below cannot be blamed on the harness.
##
## NOTE ON DECLARATION ORDER: control first. Measured on Godot 4.6.2 headless, gdUnit4's
## static discovery drops whichever test is declared after a failing one (see the same note in
## test/e2e/e2e_vs_mark_los_test.gd). Order carries no other meaning here.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

## Fixture geometry (metres). The spotter is a two-model firing line straddling the lane; its
## unit CENTRE is the midpoint between the two models, i.e. dead on z = 0. The target sits
## straight ahead at 0.60 m ≈ 23.6", well inside the book's 36". The piece plugs the midpoint
## of the centre-to-centre lane only — both real model lanes pass 0.15 m (≈ 2 grid cells) clear
## of it, which is why the per-model shooting truth still sees the target.
const SPOTTER_LEFT := Vector3(0.0, 0.0, -0.30)
const SPOTTER_RIGHT := Vector3(0.0, 0.0, 0.30)
const TARGET_POS := Vector3(0.60, 0.0, 0.0)
const PIECE_CENTRE := Vector3(0.30, 0.0, 0.0)

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## A REGISTERED unit (solo_begin_spot scans opr_army_manager.get_all_game_units()) whose
## members carry one real ranged OPR weapon, so the shooting gate _solo_validate_target has a
## reach to judge — same helper shape as test/e2e/e2e_los_refusal_detail_test.gd's _armed_unit.
func _armed_unit(pid: int, unit_name: String, positions: Array, range_in: int) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	var opr := OPRApiClient.OPRUnit.new()
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Test Rifle"
	w.range_value = range_in
	var weapons: Array[OPRApiClient.OPRWeapon] = [w]
	opr.weapons = weapons
	u.source_type = "opr"
	u.source_data = opr
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## The two-model spotter (DAO Union 3.5.2 "Precision Spotter") and its enemy, 23.6" apart.
func _spotter_and_target() -> Array:
	var spotter := _armed_unit(1, "Eyes", [SPOTTER_LEFT, SPOTTER_RIGHT], 36)
	spotter.unit_properties["special_rules"] = ["Precision Spotter"]
	var target := _armed_unit(2, "Marked", [TARGET_POS], 36)
	return [spotter, target]


## One solid CONTAINER cell column painted straight onto the terrain grid — the synthetic
## terrain idiom of e2e_vs_mark_los_test.gd / e2e_indirect_targeting_test.gd (_wall_between),
## tightened to a single 3" cell so it plugs ONLY the unit-centre lane and neither model lane.
func _solid_piece_at(o: Node3D, centre: Vector3) -> void:
	for i in range(13):
		var t := float(i) / 12.0
		var p: Vector3 = centre + Vector3(-0.03, 0.0, 0.0).lerp(Vector3(0.03, 0.0, 0.0), t)
		o.grid_cells[o.world_to_cell(p)] = o.TerrainType.CONTAINER


## THE REAL WHEEL PRESS. radial_menu.gd:462 builds RadialMenuItem("solo_spot", "Spot", …) and
## the wheel emits the id into radial_menu_controller._on_action_selected with the context the
## menu-open path filled — "game_unit" is the key _get_game_unit_from_context reads
## (radial_menu_controller.gd:656). Same seam e2e_embark_activation_test.gd:117/142 drives.
func _press_spot(unit: GameUnit) -> void:
	_main.radial_menu_controller._on_action_selected("solo_spot", {"game_unit": unit})


func test_spot_dispatch_arms_and_picks_in_reach(timeout := 120000) -> void:
	# CONTROL — the exact fixture of the RED below, minus the solid piece. If this goes red the
	# harness is at fault, not solo_begin_spot's predicate.
	var pair := _spotter_and_target()
	var spotter: GameUnit = pair[0]
	var target: GameUnit = pair[1]
	_press_spot(spotter)
	assert_bool(_main._solo_target_mode.has("spot")) \
		.override_failure_message("control fixture: the wheel's Spot must arm the pick mode on an OPEN table (log:\n%s)" % _log_text()) \
		.is_true()
	assert_array(_main._solo_target_mode.get("spot_valid", [])) \
		.override_failure_message("control fixture: the enemy at 23.6\" must be on offer") \
		.contains([target])
	assert_str(_log_text()).contains("pick a target to spot")
	# The pick half, the way test/e2e/e2e_spotter_ux_test.gd completes it.
	_main._solo_spot_click(target)
	assert_int(int(spotter.unit_properties.get("spotted_round", -1))) \
		.override_failure_message("control fixture: the pick must burn the once-per-activation spot") \
		.is_equal(_main.opr_army_manager.current_round)
	assert_bool(_main._solo_target_mode.is_empty()) \
		.override_failure_message("control fixture: the pick must hand the mouse back") \
		.is_true()


func test_spot_dispatch_arms_when_shooting_truth_sees_the_target(timeout := 120000) -> void:
	# NML-967 — the spotter peeks past a solid piece: BOTH its models have a clear lane to the
	# enemy, only the unit's notional centre point is behind the piece.
	_solid_piece_at(_main.terrain_overlay, PIECE_CENTRE)
	var pair := _spotter_and_target()
	var spotter: GameUnit = pair[0]
	var target: GameUnit = pair[1]

	# PRECONDITION — the SHOOTING truth (the same book wording, per model) accepts this pair.
	# Whatever refuses the spot cannot be "the target is not in range and sight".
	var gap: float = _main.solo_controller.nearest_melee_gap_in(spotter, target)
	assert_bool(gap < 36.0) \
		.override_failure_message("precondition: the base-edge gap must be finite and inside 36\" (got %s)" % str(gap)) \
		.is_true()
	assert_int(_main._solo_sighted_count(spotter, target, 36)) \
		.override_failure_message("precondition: at least one spotter model must SEE the target (per-model LOS, main.gd:3920)") \
		.is_greater(0)
	assert_str(_main._solo_validate_target(spotter, target, false)) \
		.override_failure_message("precondition: the shooting gate must accept this exact pair") \
		.is_equal("")

	_press_spot(spotter)
	assert_bool(_main._solo_target_mode.has("spot")) \
		.override_failure_message(("NML-967 — the wheel's Spot armed NOTHING, so no target can be selected. " +
			"The candidate scan (main.gd:9185) gates on _solo_has_los, a UNIT-CENTRE terrain line, while " +
			"the shooting truth asserted above is PER MODEL — so the scan came back empty and " +
			"solo_begin_spot returned before setting _solo_target_mode. Log:\n%s") % _log_text()) \
		.is_true()
	# gdUnit records a failed assertion and carries on, so the arming failure would otherwise
	# cascade into two more meaningless reports. Stop here: one defect, one failure line.
	if not _main._solo_target_mode.has("spot"):
		return
	# Reached only once the scan judges like the dice do: the armed mode must take the click.
	assert_array(_main._solo_target_mode.get("spot_valid", [])) \
		.override_failure_message("NML-967 — armed, but the target the shooting truth sees is not on offer") \
		.contains([target])
	_main._solo_spot_click(target)
	assert_int(int(spotter.unit_properties.get("spotted_round", -1))) \
		.override_failure_message("NML-967 — the pick did not land") \
		.is_equal(_main.opr_army_manager.current_round)
