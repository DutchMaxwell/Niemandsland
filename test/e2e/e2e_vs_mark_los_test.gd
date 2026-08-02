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
