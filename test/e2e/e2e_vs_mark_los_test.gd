extends GdUnitTestSuite
## NML-936 (BUG A) — "vs-target Marks fire through walls". scripts/main.gd
## _solo_apply_vs_marks resolves "Utility Buff" rules whose params carry vs_target == true
## (the doc comment above it quotes the book: "pick one enemy unit within 18\" IN LINE OF
## SIGHT"), but the body only gates on `dist_in > range_in` — there is no line-of-sight check
## at all, so a Mark lands on a target hidden behind a solid wall.
##
## Drives the REAL _solo_apply_vs_marks over main.tscn with a container wall between the
## bearer and its target — the same wall shape e2e_indirect_targeting_test.gd's
## _wall_between() already proved out for the LOS-gated shooting path. A synthetic registry
## map (RulesRegistry._cache injection, same pattern as test/rules_registry_test.gd's
## _inject_gf_map) keeps the fixture independent of any real faction's data.
##
## test_a_mark_does_not_reach_a_target_behind_a_wall pins the fix: without the line-of-sight
## gate the mark lands anyway. test_a_mark_still_reaches_a_target_in_the_open is the CONTROL: same
## fixture minus the wall, must stay green before and after the fix.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main._ensure_solo_controller()


func after_test() -> void:
	RulesRegistry.reset_cache()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## A solid container wall painted across the line between x=-0.3 and x=+0.3 — VERBATIM from
## e2e_indirect_targeting_test.gd's _wall_between (same synthetic-terrain injection pattern).
func _wall_between(o: Node3D) -> void:
	for i in range(41):
		var t := float(i) / 40.0
		if t < 0.4 or t > 0.6:
			continue
		var p := Vector3(-0.3, 0, 0).lerp(Vector3(0.3, 0, 0), t)
		o.grid_cells[o.world_to_cell(p)] = o.TerrainType.CONTAINER


## Synthetic map: one rule, "Bane Mark", the "Utility Buff" primitive with vs_target true and
## an 18" range — deliberately NO "needs_los" key, so a correct reader must default to
## REQUIRING line of sight (that is the book's own wording, not an opt-in flag).
func _inject_mark_map() -> void:
	RulesRegistry.reset_cache()
	RulesRegistry._cache["gf"] = {"factions": {"testfac": {
		"Bane Mark": {"primitive": "Utility Buff", "params": {"vs_target": true, "range_in": 18.0}},
	}}, "common": {}}


## The bearer (player 1, carries "Bane Mark") and its would-be target (player 2), straddling
## the wall lane at x=-0.3/x=+0.3 (same geometry as e2e_indirect_targeting_test.gd). The tests
## below pass dist_in explicitly (6.0), so the real-world gap only matters for the wall's LOS
## geometry, not the range gate.
func _bearer_and_target() -> Array:
	var bearer := E2EBoot.make_unit(_main, 1, "Bearer", [Vector3(-0.3, 0, 0)])
	bearer.unit_properties["game_system"] = "gf"
	bearer.unit_properties["faction_folder"] = "testfac"
	bearer.unit_properties["special_rules"] = ["Bane Mark"]
	var target := E2EBoot.make_unit(_main, 2, "Target", [Vector3(0.3, 0, 0)])
	target.unit_properties["game_system"] = "gf"
	target.unit_properties["faction_folder"] = "testfac"
	return [bearer, target]


## Every "grants_rule" name currently active in `member`'s once-mod chain (the seam
## _solo_apply_vs_marks writes through _solo_record_spell_mod and _solo_mods_of_chain reads
## back — see main.gd:15050 / main.gd:3427).
func _granted_rules(member: GameUnit) -> Array:
	var out: Array = []
	for m in _main._solo_mods_of_chain(member):
		out.append(str((m as Dictionary).get("grants_rule", "")))
	return out


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


# NOTE ON ORDER: this control test is declared BEFORE the RED test below on purpose — measured
# on Godot 4.6.2 headless, gdUnit4's static test-discovery scanner (GdScriptParser /
# GdUnitTestDiscoverer, which walks the file's SOURCE TEXT to enrich each reflected test method)
# silently drops whichever test is declared AFTER this suite's RED test if that RED test comes
# first: "Executed test cases: (1/1)" instead of (2/2), with the second test never even logging
# STARTED. Swapping the declaration order reproducibly restores (2/2). Declaration order carries
# no semantic meaning for gdUnit test execution otherwise, so this is a harmless workaround for a
# tooling quirk, not a test-logic change.
func test_a_mark_still_reaches_a_target_in_the_open() -> void:
	# Control: identical fixture, no wall — the mark must land whether or not the fix lands.
	_inject_mark_map()
	var pair := _bearer_and_target()
	var bearer: GameUnit = pair[0]
	var target: GameUnit = pair[1]
	_main.opr_army_manager.current_round = 1
	_main._solo_apply_vs_marks(bearer, target, 6.0)
	var granted := _granted_rules(bearer)
	assert_array(granted) \
		.override_failure_message("control fixture: an UNBLOCKED Mark within range must still land (granted: %s)" %
			str(granted)) \
		.contains(["Bane"])


func test_a_mark_does_not_reach_a_target_behind_a_wall() -> void:
	_inject_mark_map()
	_wall_between(_main.terrain_overlay)
	var pair := _bearer_and_target()
	var bearer: GameUnit = pair[0]
	var target: GameUnit = pair[1]
	_main.opr_army_manager.current_round = 1
	# 6" — well inside the rule's 18" range, so ONLY line of sight can refuse it.
	_main._solo_apply_vs_marks(bearer, target, 6.0)
	var granted := _granted_rules(bearer)
	assert_array(granted) \
		.override_failure_message("NML-936 — Bane Mark landed on a target BEHIND A WALL (no LOS gate in " +
			"_solo_apply_vs_marks; the once-mod chain now grants: %s)" % str(granted)) \
		.not_contains(["Bane"])
	assert_str(_log_text()) \
		.override_failure_message("NML-936 — no logged line refuses the Mark for lack of sight (log:\n%s)" % _log_text()) \
		.contains("sight")


# =====================================================================================
# NML-972 (elevation program, Phase A / W3.11) — the SHOOTING truth reads real heights.
# =====================================================================================
# The shooting gate walked the terrain GRID at ground level and compared Asgard height
# CATEGORIES, so a model standing on a 2.5" container roof was walled in by the very box
# it stood on: the sight line's own elevation was never part of the question. The
# volumetric truth (VolumetricLos) makes the line a real 3D segment from eye to eye, so a
# shooter on the roof looks OVER the container's near edge at the ground beyond it.
#
# The patch below is painted between x = -0.38 m and x = -0.08 m, the shooter stands on it
# at x = -0.30 m and the target is at x = +0.30 m. The eye-to-eye line only sinks below the
# 2.5" roof at the halfway point (x = 0), which is well past the patch's far edge — so it
# clears the box geometrically, not by any exemption.

## A solid CONTAINER patch painted on the lane, covering the shooter's half of it only.
## The cache the volume registry keeps is dropped by hand: painting straight into
## grid_cells (the synthetic-terrain idiom of this directory) skips every registration seam.
func _container_patch(o: Node3D) -> void:
	for i in range(31):
		var t := float(i) / 30.0
		var p := Vector3(-0.34, 0.0, 0.0).lerp(Vector3(-0.12, 0.0, 0.0), t)
		o.grid_cells[o.world_to_cell(p)] = o.TerrainType.CONTAINER
	o._los_volumes_dirty = true


## Shooter (player 1) and target (player 2) on the patch lane; `shooter_y` lifts the shooter
## onto the container roof (2.5") or leaves it on the table.
func _shooter_and_ground_target(shooter_y: float) -> Array:
	var shooter := E2EBoot.make_unit(_main, 1, "Rooftop", [Vector3(-0.30, shooter_y, 0.0)])
	var target := E2EBoot.make_unit(_main, 2, "Grounded", [Vector3(0.30, 0.0, 0.0)])
	return [shooter, target]


func test_a_ground_shooter_stays_blocked_by_the_container() -> void:
	# CONTROL — same fixture at table level: the patch is solid and must keep blocking, before
	# and after the migration. If this ever goes green the RED below proves nothing.
	_container_patch(_main.terrain_overlay)
	var pair := _shooter_and_ground_target(0.0)
	assert_int(_main._solo_sighted_count(pair[0] as GameUnit, pair[1] as GameUnit, 36)) \
		.override_failure_message("control fixture: a GROUND shooter must not see through a solid container") \
		.is_equal(0)


func test_a_shooter_on_a_container_sees_the_ground_target_beyond_it() -> void:
	_container_patch(_main.terrain_overlay)
	var pair := _shooter_and_ground_target(2.5 * 0.0254)
	assert_int(_main._solo_sighted_count(pair[0] as GameUnit, pair[1] as GameUnit, 36)) \
		.override_failure_message("NML-972 — a shooter standing ON the 2.5\" container roof still counts as " +
			"blind: the shooting gate walks the terrain grid at ground level and compares height " +
			"CATEGORIES, so the line's own elevation never enters the test (main.gd _solo_true_los_callable).") \
		.is_greater(0)


# =====================================================================================
# NML-972 / W3.14 — the AI's positional sight checker.
# =====================================================================================
# solo_controller.los_checker answers "could something standing HERE see something standing
# THERE" for spots no model occupies yet — the endpoint of a candidate move, an anchor, a
# hypothetical firing position. The y it is handed is therefore meaningless (callers pass the
# unit's current centre height, or none at all), which is exactly why the closure has to stand
# its own query on the table: overlay.surface_y_at gives the height the drop probe would place
# a model at, so a candidate spot on a container roof is judged FROM the roof.

func test_the_ai_los_checker_stands_a_ground_query_on_the_table() -> void:
	# CONTROL — both spots are open ground on either side of the patch: still blocked, before and
	# after. Without this the elevated case below could pass on an empty registry.
	_container_patch(_main.terrain_overlay)
	var checker: Callable = _main.solo_controller.los_checker
	assert_bool(bool(checker.call(Vector3(-0.45, 0.0, 0.0), Vector3(0.30, 0.0, 0.0)))) \
		.override_failure_message("control fixture: two ground spots across a solid container must not see each other") \
		.is_false()


func test_the_ai_los_checker_sees_from_a_container_roof() -> void:
	_container_patch(_main.terrain_overlay)
	var checker: Callable = _main.solo_controller.los_checker
	# The same XZ pair as the shooting case above — the FROM spot lies on the painted patch, so a
	# model placed there would stand 2.5" up and look over the box's far edge.
	assert_bool(bool(checker.call(Vector3(-0.30, 0.0, 0.0), Vector3(0.30, 0.0, 0.0)))) \
		.override_failure_message("NML-972 — the AI's sight checker judges every candidate spot from the " +
			"table floor: it hands its two points to the flat grid walk with fixed height categories, so " +
			"the AI can never see a firing position ON a container as one (main.gd:2154).") \
		.is_true()


# =====================================================================================
# NML-971 / W4.21 — the hover line's colour and geometry read the SAME one query.
# =====================================================================================
# The line drawn to a hovered target is display only, and display that argues with the dice
# is worse than no display. Its colour and its "n/N sight" label are ONE number —
# _solo_hover_sighted_count, which rides the migrated per-model volumetric query (or, while a
# cast is aimed, the cast gate's own candidate set: e2e_indirect_targeting_test) — and its
# geometry hangs off solo_controller.unit_centre, which carries the models' real standing
# height. These cases pin both ends against the container patch above: no second sight or
# range source may creep back into the visual path.

## The shooter of _shooter_and_ground_target, armed with one long gun so only SIGHT can
## decide the hover count (the range gate is the same flat measure it always was, G3).
func _armed_rooftop_shooter(shooter_y: float) -> Array:
	var pair := _shooter_and_ground_target(shooter_y)
	var shooter := pair[0] as GameUnit
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Long Gun"
	w.range_value = 36
	w.attacks = 1
	w.count = 1
	var src := OPRApiClient.OPRUnit.new()
	var ws: Array[OPRApiClient.OPRWeapon] = [w]
	src.weapons = ws
	shooter.source_type = "opr"
	shooter.source_data = src
	return pair


func test_the_hover_line_stays_red_for_a_ground_shooter() -> void:
	# CONTROL — the same gun behind the same box: the line must still count zero, so the
	# elevated case below cannot pass on a broken fixture.
	_container_patch(_main.terrain_overlay)
	var pair := _armed_rooftop_shooter(0.0)
	assert_int(_main._solo_hover_sighted_count(pair[0] as GameUnit, pair[1] as GameUnit)) \
		.override_failure_message("control fixture: a ground shooter behind a solid container must draw a red line") \
		.is_equal(0)


func test_the_hover_line_reads_the_volumetric_truth_and_hangs_at_the_real_height() -> void:
	_container_patch(_main.terrain_overlay)
	var pair := _armed_rooftop_shooter(2.5 * 0.0254)
	var shooter := pair[0] as GameUnit
	var target := pair[1] as GameUnit
	assert_int(_main._solo_hover_sighted_count(shooter, target)) \
		.override_failure_message("NML-971 — the hover line disagrees with the gate: its count must come from " +
			"the ONE migrated query (main.gd _solo_hover_sighted_count), never from a second sight or range source.") \
		.is_greater(0)
	assert_int(_main._solo_sighted_count(shooter, target, 36)) \
		.override_failure_message("the hover count and the shooting gate must be the same number") \
		.is_equal(_main._solo_hover_sighted_count(shooter, target))
	# The drawn line's endpoints are unit_centre + 4 cm — so on the roof it starts 2.5" up.
	assert_float(_main.solo_controller.unit_centre(shooter).y) \
		.override_failure_message("the drawn line's geometry must carry the shooter's real standing height") \
		.is_equal_approx(2.5 * 0.0254, 0.001)


# =====================================================================================
# P6 / W4.21b — an Aircraft target is always visible.
# =====================================================================================
# GF v3.5.1 p.13 keeps Aircraft abstract: their base is transparent to line of sight and they
# have no altitude coordinate, so nothing on the table can hide one. VolumetricLos carries that
# branch, but production never flagged the TARGET cylinder as an aircraft, so the branch was
# unwired — the old flat walk had the same gap, which is why this is a known wrong rather than
# a regression. The fixture is the ground control above: a shooter standing in the container's
# own footprint sees nothing at all — except a flyer.

func test_an_aircraft_target_is_visible_from_inside_the_container() -> void:
	_container_patch(_main.terrain_overlay)
	var pair := _shooter_and_ground_target(0.0)
	var shooter := pair[0] as GameUnit
	var flyer := pair[1] as GameUnit
	flyer.unit_properties["special_rules"] = ["Aircraft"]
	assert_bool(SoloController.is_aircraft(flyer)) \
		.override_failure_message("fixture broken: the Aircraft rule did not resolve for the target") \
		.is_true()
	assert_int(_main._solo_sighted_count(shooter, flyer, 36)) \
		.override_failure_message("P6 — an Aircraft is abstract and always visible (GF v3.5.1 p.13), but the " +
			"per-model shooting query hides it behind terrain: the TARGET cylinder built in " +
			"main.gd _solo_true_los_callable never carries the is_aircraft flag VolumetricLos looks for.") \
		.is_greater(0)
	assert_bool(_main._solo_has_los(shooter, flyer)) \
		.override_failure_message("P6 — the unit-centre sight test (melee display, breath, spell targeting) " +
			"hides an Aircraft behind terrain too: main.gd _solo_has_los builds its target cylinder without " +
			"the is_aircraft flag.") \
		.is_true()
