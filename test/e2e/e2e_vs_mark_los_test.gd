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
